import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/registered_card.dart';

class CardStoreException implements Exception {
  const CardStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class CardRepository {
  Future<List<RegisteredCard>> loadAll();
  Future<void> saveAll(List<RegisteredCard> cards);

  /// Tap history, newest first.
  Future<List<TapEvent>> loadTaps();
  Future<void> saveTaps(List<TapEvent> taps);
}

/// Encrypts file contents at rest (see `KeystoreCipher`).
abstract class StorageCipher {
  Future<String> encrypt(String plain);
  Future<String> decrypt(String data);
}

/// Stores cards as versioned JSON in the app's private files directory,
/// encrypted with [cipher] when one is given.
///
/// Reads always hit disk (no cache), because the main app and the tap popup
/// run separate Flutter engines that both use this file. Writes go to a temp
/// file first and are then renamed over the original, so an interrupted write
/// leaves the previous version intact. Files written before encryption was
/// added are still read; they are encrypted on the next save.
class FileCardRepository implements CardRepository {
  FileCardRepository({Future<Directory> Function()? directory, this.cipher})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const schemaVersion = 1;
  static const fileName = 'cards.json';
  static const tapsFileName = 'taps.json';

  final Future<Directory> Function() _directory;
  final StorageCipher? cipher;

  Future<File> _file([String name = fileName]) async =>
      File('${(await _directory()).path}/$name');

  @override
  Future<List<RegisteredCard>> loadAll() async {
    final json = await _read(fileName, label: 'Saved cards');
    if (json == null) return [];
    try {
      final version = json['version'] as int? ?? 0;
      if (version > schemaVersion) {
        throw const CardStoreException(
          'Saved cards were created by a newer version of the app.',
        );
      }
      return (json['cards']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(RegisteredCard.fromJson)
          .toList();
    } on CardStoreException {
      rethrow;
    } catch (e) {
      throw CardStoreException('Saved cards could not be read ($e).');
    }
  }

  @override
  Future<void> saveAll(List<RegisteredCard> cards) => _write(fileName, {
    'version': schemaVersion,
    'cards': [for (final c in cards) c.toJson()],
  });

  @override
  Future<List<TapEvent>> loadTaps() async {
    try {
      final json = await _read(tapsFileName, label: 'Tap history');
      if (json == null) return [];
      return (json['taps']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(TapEvent.fromJson)
          .toList();
    } catch (_) {
      // History is a nice-to-have: a damaged file just starts over.
      return [];
    }
  }

  @override
  Future<void> saveTaps(List<TapEvent> taps) => _write(tapsFileName, {
    'version': 1,
    'taps': [for (final t in taps) t.toJson()],
  });

  /// Reads a file, decrypting it if it was written encrypted.
  Future<Map<String, Object?>?> _read(
    String name, {
    required String label,
  }) async {
    final file = await _file(name);
    if (!await file.exists()) return null;
    final Map<String, Object?> outer;
    try {
      outer = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    } catch (e) {
      throw CardStoreException('$label could not be read ($e).');
    }
    if (outer['enc'] == null) {
      // Legacy plain file from before encryption: upgrade it in place now,
      // rather than waiting for the next change. Best effort.
      if (cipher != null) {
        try {
          await _write(name, outer);
        } catch (_) {}
      }
      return outer;
    }
    final c = cipher;
    if (c == null) {
      throw CardStoreException('$label: encrypted, but no key is available.');
    }
    try {
      return jsonDecode(await c.decrypt(outer['data']! as String))
          as Map<String, Object?>;
    } catch (e) {
      throw CardStoreException('$label could not be decrypted ($e).');
    }
  }

  /// Writes to a temp file, then renames over the original (atomic on the
  /// same filesystem), so an interrupted write keeps the previous version.
  Future<void> _write(String name, Map<String, Object?> json) async {
    final file = await _file(name);
    await file.parent.create(recursive: true);
    final plain = jsonEncode(json);
    final c = cipher;
    final body = c == null
        ? plain
        : jsonEncode({'enc': 'aes-256-gcm', 'data': await c.encrypt(plain)});
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(body, flush: true);
    await temp.rename(file.path);
  }
}
