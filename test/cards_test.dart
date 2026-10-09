import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/features/cards/data/card_repository.dart';
import 'package:nfcpin/features/cards/domain/registered_card.dart';
import 'package:nfcpin/features/cards/domain/tap_resolver.dart';
import 'package:nfcpin/features/cards/presentation/cards_controller.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';

import 'memory_card_repository.dart';

RegisteredCard card({
  String name = 'SBI Card',
  String fingerprint = 'aaaa-bbbb-cccc',
  bool enabled = true,
}) => RegisteredCard.create(
  name: name,
  fingerprint: fingerprint,
  category: CardCategory.smartCard,
  message: 'Hello',
).copyWith(enabled: enabled);

TagReading reading(String? fingerprint) => TagReading(
  source: TagSource.launchedFromBackground,
  techs: const ['IsoDep', 'NfcA'],
  fingerprint: fingerprint,
  idLength: 7,
  randomIdHint: false,
  at: DateTime(2026),
);

void main() {
  group('CardValidation', () {
    test('name', () {
      expect(CardValidation.name('  '), isNotNull);
      expect(CardValidation.name('x' * 41), isNotNull);
      expect(CardValidation.name(' SBI '), isNull);
    });

    test('message', () {
      expect(CardValidation.message(''), isNotNull);
      expect(CardValidation.message('x' * 201), isNotNull);
      expect(CardValidation.message(CardValidation.defaultMessage), isNull);
    });
  });

  test('RegisteredCard JSON round trip', () {
    final original = card().copyWith(lastTriggeredAt: DateTime(2026, 10, 9));
    final copy = RegisteredCard.fromJson(original.toJson());
    expect(copy.toJson(), original.toJson());
    expect(copy.category, CardCategory.smartCard);
  });

  group('resolveTap', () {
    final cards = [
      card(),
      card(name: 'Off', fingerprint: 'off', enabled: false),
    ];

    test('matches a registered, enabled card', () {
      final outcome = resolveTap(reading('aaaa-bbbb-cccc'), cards);
      expect((outcome as RegisteredTap).card.name, 'SBI Card');
    });

    test('does not run the action for a disabled card', () {
      expect(resolveTap(reading('off'), cards), isA<DisabledCardTap>());
    });

    test('an unrelated card is unknown', () {
      expect(resolveTap(reading('other'), cards), isA<UnknownCardTap>());
    });

    test('a tag without an ID is unknown', () {
      expect(resolveTap(reading(null), cards), isA<UnknownCardTap>());
    });
  });

  group('FileCardRepository', () {
    late Directory dir;
    late FileCardRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nfcpin_test');
      repo = FileCardRepository(directory: () async => dir);
    });

    tearDown(() => dir.delete(recursive: true));

    test('starts empty', () async {
      expect(await repo.loadAll(), isEmpty);
    });

    test('saves and loads, leaving no temp file', () async {
      await repo.saveAll([card(), card(name: 'B', fingerprint: 'b')]);
      final loaded = await repo.loadAll();
      expect(loaded.map((c) => c.name), ['SBI Card', 'B']);
      expect(File('${dir.path}/cards.json.tmp').existsSync(), isFalse);
    });

    test('corrupt file raises a readable error', () async {
      File('${dir.path}/cards.json').writeAsStringSync('{not json');
      expect(repo.loadAll(), throwsA(isA<CardStoreException>()));
    });

    test('refuses data from a newer schema', () async {
      File(
        '${dir.path}/cards.json',
      ).writeAsStringSync('{"version":99,"cards":[]}');
      expect(repo.loadAll(), throwsA(isA<CardStoreException>()));
    });
  });

  group('CardsController', () {
    late MemoryCardRepository repo;
    late CardsController cards;

    setUp(() async {
      repo = MemoryCardRepository();
      cards = CardsController(repo);
      await cards.load();
    });

    Future<RegisteredCard> addDefault() => cards.add(
      name: 'SBI Card',
      message: 'Detected',
      fingerprint: 'aaaa-bbbb-cccc',
      category: CardCategory.smartCard,
    );

    test('adds a card and persists it', () async {
      final c = await addDefault();
      expect(cards.cards.single.id, c.id);
      expect(repo.stored.single.enabled, isTrue);
    });

    test('rejects a duplicate card', () async {
      await addDefault();
      expect(
        addDefault(),
        throwsA(
          isA<CardRuleException>().having(
            (e) => e.message,
            'message',
            contains('already registered as "SBI Card"'),
          ),
        ),
      );
    });

    test('rejects invalid input without saving', () async {
      expect(
        cards.add(
          name: ' ',
          message: 'x',
          fingerprint: 'f',
          category: CardCategory.smartCard,
        ),
        throwsA(isA<CardRuleException>()),
      );
      expect(repo.saves, 0);
    });

    test('edit, disable and delete', () async {
      final c = await addDefault();
      await cards.edit(c.id, name: 'Renamed', message: 'New message');
      await cards.setEnabled(c.id, false);
      expect(cards.byId(c.id)!.name, 'Renamed');
      expect(repo.stored.single.enabled, isFalse);

      await cards.delete(c.id);
      expect(cards.cards, isEmpty);
      expect(repo.stored, isEmpty);
    });

    test('editing a deleted card fails clearly', () async {
      expect(
        cards.setEnabled('missing', false),
        throwsA(isA<CardRuleException>()),
      );
    });

    test('failed save leaves the list unchanged', () async {
      repo.failSaves = true;
      await expectLater(addDefault(), throwsA(isA<CardStoreException>()));
      expect(cards.cards, isEmpty);
    });

    test('markTriggered records the time', () async {
      final c = await addDefault();
      await cards.markTriggered(c.id, at: DateTime(2026, 10, 9, 12));
      expect(repo.stored.single.lastTriggeredAt, DateTime(2026, 10, 9, 12));
    });
  });
}
