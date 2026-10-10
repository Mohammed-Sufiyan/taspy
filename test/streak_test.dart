import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/app/theme.dart';
import 'package:nfcpin/features/actions/domain/card_action.dart';
import 'package:nfcpin/features/cards/data/card_repository.dart';
import 'package:nfcpin/features/cards/domain/card_template.dart';
import 'package:nfcpin/features/cards/domain/registered_card.dart';
import 'package:nfcpin/features/cards/domain/streak.dart';
import 'package:nfcpin/features/cards/domain/tap_resolver.dart';
import 'package:nfcpin/features/cards/presentation/card_face.dart';
import 'package:nfcpin/features/cards/presentation/cards_controller.dart';
import 'package:nfcpin/features/nfc/data/nfc_platform.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';
import 'package:nfcpin/features/tap/tap_app.dart';

import 'fake_auth.dart';
import 'fake_nfc_platform.dart';
import 'memory_card_repository.dart';

void main() {
  group('streak', () {
    final mon = DateTime(2026, 10, 12, 9);

    test('consecutive days grow it, a missed day resets it', () {
      var s = Streak.none.tap(mon);
      expect(s.current, 1);
      s = s.tap(mon.add(const Duration(hours: 10))); // Same day.
      expect(s.current, 1);
      s = s.tap(mon.add(const Duration(days: 1)));
      s = s.tap(mon.add(const Duration(days: 2)));
      expect((s.current, s.best), (3, 3));
      s = s.tap(mon.add(const Duration(days: 4))); // Skipped a day.
      expect((s.current, s.best), (1, 3));
    });

    test('is still active the day after, broken after that', () {
      final s = Streak.none.tap(mon).tap(mon.add(const Duration(days: 1)));
      expect(s.activeOn(mon.add(const Duration(days: 1))), 2);
      expect(s.activeOn(mon.add(const Duration(days: 2))), 2);
      expect(s.activeOn(mon.add(const Duration(days: 3))), 0);
    });

    test('a clock moved backwards changes nothing', () {
      final s = Streak.none.tap(mon);
      expect(s.tap(mon.subtract(const Duration(days: 3))), s);
    });

    test('crosses a month end', () {
      final s = Streak.none
          .tap(DateTime(2026, 10, 31, 23))
          .tap(DateTime(2026, 11, 1, 1));
      expect(s.current, 2);
    });
  });

  test('look and streak survive a save; old cards get defaults', () async {
    final dir = await Directory.systemTemp.createTemp('tapsy_look');
    addTearDown(() => dir.delete(recursive: true));
    final repo = FileCardRepository(directory: () async => dir);
    final card = RegisteredCard.create(
      name: 'Gym',
      fingerprint: 'aaaa-bbbb-cccc',
      category: CardCategory.otherTag,
      message: 'Go',
      emoji: '🏋️',
      effect: CardEffect.holo,
    ).copyWith(streak: Streak.none.tap(DateTime(2026, 10, 12)));
    await repo.saveAll([card]);
    final loaded = (await repo.loadAll()).single;
    expect(loaded.emoji, '🏋️');
    expect(loaded.effect, CardEffect.holo);
    expect(loaded.streak, card.streak);

    final old = RegisteredCard.fromJson({
      'id': 'x',
      'name': 'Old',
      'fingerprint': 'f',
      'category': 'smartCard',
      'message': 'hi',
      'createdAt': '2026-01-01T00:00:00.000',
    });
    expect(old.effect, CardEffect.shine);
    expect(old.streak, Streak.none);
    expect(old.toJson().keys, isNot(contains('effect')));
  });

  test('every tap updates the card streak', () async {
    final repo = MemoryCardRepository();
    final cards = CardsController(repo);
    final card = await cards.add(
      name: 'Gym',
      message: 'Go',
      fingerprint: 'aaaa-bbbb-cccc',
      category: CardCategory.otherTag,
    );
    final day = DateTime(2026, 10, 12, 7);
    await cards.markTriggered(card.id, at: day);
    await cards.markTriggered(card.id, at: day.add(const Duration(days: 1)));
    expect(cards.byId(card.id)!.streak.current, 2);
  });

  test('templates are valid cards', () {
    for (final t in CardTemplate.all) {
      expect(ActionRules.list(t.actions), isNull, reason: t.name);
      expect(t.message.isNotEmpty || t.actions.isNotEmpty, isTrue);
      expect(t.style, lessThan(CardSkin.all.length), reason: t.name);
    }
  });

  testWidgets('every design and effect renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < CardSkin.all.length; i++)
                CardFace(
                  name: CardSkin.all[i].name,
                  style: i,
                  emoji: '⭐',
                  streak: 4,
                  effect: CardEffect.values[i % CardEffect.values.length],
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text('🔥 4'), findsWidgets);
  });

  group('tap popup', () {
    late FakeNfcPlatform platform;
    late MemoryCardRepository repo;

    Future<void> tapWithStreak(WidgetTester tester, Streak streak) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      platform = FakeNfcPlatform();
      repo = MemoryCardRepository()
        ..stored = [
          RegisteredCard.create(
            name: 'Gym',
            fingerprint: 'aaaa-bbbb-cccc',
            category: CardCategory.otherTag,
            message: 'Go',
          ).copyWith(streak: streak),
        ];
      await tester.pumpWidget(
        TapApp(platform: platform, repository: repo, auth: FakeAuthService()),
      );
      platform.tap(source: TagSource.launchedFromClosed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('first tap starts a streak', (tester) async {
      await tapWithStreak(tester, Streak.none);
      expect(find.text('🔥 Streak started'), findsOneWidget);
      expect(repo.stored.single.streak.current, 1);
    });

    testWidgets('reaching a milestone celebrates', (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final two = Streak.none
          .tap(yesterday.subtract(const Duration(days: 1)))
          .tap(yesterday);
      await tapWithStreak(tester, two);
      expect(find.text('🎉 3-day streak!'), findsOneWidget);
      expect(repo.stored.single.streak.current, 3);
    });

    testWidgets('only actions for this time of day run', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final ran = <CardAction>[];
      const morningApp = CardAction(
        type: ActionType.openApp,
        value: 'com.slack',
        label: 'Slack',
        time: ActionTime.morning,
      );
      const nightApp = CardAction(
        type: ActionType.openApp,
        value: 'com.youtube',
        label: 'YouTube',
        time: ActionTime.night,
      );
      final card = RegisteredCard.create(
        name: 'Desk',
        fingerprint: 'f',
        category: CardCategory.otherTag,
        message: 'Hi',
        actions: const [morningApp, nightApp],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TapSheet(
              outcome: RegisteredTap(card),
              now: DateTime(2026, 10, 12, 22),
              onClose: () {},
              onRunAction: (a) async {
                ran.add(a);
                return ActionResult.done;
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Open YouTube'), findsOneWidget);
      expect(find.text('Open Slack'), findsNothing);
      expect(find.text('1 more action runs at other times'), findsOneWidget);
      await tester.pump(TapSheet.openDelay);
      await tester.pump(const Duration(seconds: 1));
      expect(ran, [nightApp]);
    });
  });
}
