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

  final Future<Directory> Function() _directory;

  Future<File> _file() async => File('${(await _directory()).path}/$fileName');

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
  Future<void> saveAll(List<RegisteredCard> cards) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    final body = jsonEncode({
      'version': schemaVersion,
      'cards': [for (final c in cards) c.toJson()],
    });
    await temp.writeAsString(body, flush: true);
    await temp.rename(file.path);
  }
}
