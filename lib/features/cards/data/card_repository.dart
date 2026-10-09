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

/// Stores cards as versioned JSON in the app's private files directory.
///
/// Reads always hit disk (no cache), because the main app and the tap popup
/// run separate Flutter engines that both use this file. Writes go to a temp
/// file first and are then renamed over the original, so an interrupted write
/// leaves the previous version intact.
class FileCardRepository implements CardRepository {
  FileCardRepository({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const schemaVersion = 1;
  static const fileName = 'cards.json';
  static const tapsFileName = 'taps.json';

  final Future<Directory> Function() _directory;

  Future<File> _file([String name = fileName]) async =>
      File('${(await _directory()).path}/$name');

  @override
  Future<List<RegisteredCard>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
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
    final file = await _file(tapsFileName);
    if (!await file.exists()) return [];
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
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

  /// Writes to a temp file, then renames over the original (atomic on the
  /// same filesystem), so an interrupted write keeps the previous version.
  Future<void> _write(String name, Map<String, Object?> json) async {
    final file = await _file(name);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }
}
