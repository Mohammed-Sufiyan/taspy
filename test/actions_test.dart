import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/app/theme.dart';
import 'package:nfcpin/features/actions/domain/card_action.dart';
import 'package:nfcpin/features/actions/presentation/actions_editor.dart';
import 'package:nfcpin/features/cards/data/card_repository.dart';
import 'package:nfcpin/features/cards/domain/registered_card.dart';
import 'package:nfcpin/features/cards/presentation/cards_controller.dart';
import 'package:nfcpin/features/nfc/data/nfc_platform.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';

import 'fake_nfc_platform.dart';
import 'memory_card_repository.dart';

const _spotify = CardAction(
  type: ActionType.openApp,
  value: 'com.spotify.music',
  label: 'Spotify',
);
const _torch = CardAction(type: ActionType.flashlight, value: 'toggle');
const _upi = CardAction(type: ActionType.copyText, value: 'me@upi');
const _link = CardAction(
  type: ActionType.openLink,
  value: 'https://youtube.com',
);

void main() {
  group('rules', () {
    test('links must be https; a bare address gets https added', () {
      expect(ActionRules.normalizeLink('youtube.com'), 'https://youtube.com');
      expect(ActionRules.link('youtube.com'), isNull);
      expect(ActionRules.link('http://youtube.com'), isNotNull);
      expect(ActionRules.link('javascript:alert(1)'), isNotNull);
      expect(ActionRules.link('https://localhost'), isNotNull);
    });

    test('WhatsApp needs the country code', () {
      expect(ActionRules.whatsappPhone('98765 43210'), contains('country'));
      expect(ActionRules.whatsappPhone('+91 98765 43210'), isNull);
      expect(ActionRules.phone('100'), isNull);
      expect(ActionRules.phone('call me'), isNotNull);
    });

    test('timer minutes are bounded', () {
      expect(ActionRules.minutes('0'), isNotNull);
      expect(ActionRules.minutes('10'), isNull);
      expect(ActionRules.minutes('99999'), isNotNull);
    });

    test('only one action may open an app, and it runs last', () {
      expect(ActionRules.list([_spotify, _link]), contains('Only one'));
      expect(ActionRules.list([_spotify, _torch, _upi]), isNull);
      expect(ActionRules.runOrder([_spotify, _torch, _upi]), [
        _torch,
        _upi,
        _spotify,
      ]);
    });

    test('at most eight actions', () {
      expect(ActionRules.list(List.filled(8, _torch)), isNull);
      expect(ActionRules.list(List.filled(9, _torch)), contains('up to'));
    });
  });

  group('time of day', () {
    // 2026-10-12 is a Monday.
    final mondayMorning = DateTime(2026, 10, 12, 8);
    final mondayNight = DateTime(2026, 10, 12, 23);
    final sundayEarly = DateTime(2026, 10, 11, 2);

    test('windows and days decide when an action runs', () {
      final morning = _spotify.copyWith(time: ActionTime.morning);
      expect(morning.runsAt(mondayMorning), isTrue);
      expect(morning.runsAt(mondayNight), isFalse);

      final night = _link.copyWith(time: ActionTime.night);
      expect(night.runsAt(mondayNight), isTrue);
      expect(night.runsAt(sundayEarly), isTrue); // Wraps past midnight.

      final weekdays = _torch.copyWith(days: ActionDays.weekdays);
      expect(weekdays.runsAt(mondayMorning), isTrue);
      expect(weekdays.runsAt(sundayEarly), isFalse);
      expect(_torch.runsAt(sundayEarly), isTrue);
      expect(weekdays.whenLabel, 'Weekdays');
      expect(
        night.copyWith(days: ActionDays.weekends).whenLabel,
        'Nights · weekends',
      );
    });

    test('two openers are allowed only at different times', () {
      final am = _spotify.copyWith(time: ActionTime.morning);
      final pm = _link.copyWith(time: ActionTime.evening);
      expect(ActionRules.list([am, pm]), isNull);
      expect(ActionRules.list([am, _link]), ActionRules.clashMessage);
      // Same time but weekdays vs weekends don't overlap either.
      expect(
        ActionRules.list([
          _spotify.copyWith(days: ActionDays.weekdays),
          _link.copyWith(days: ActionDays.weekends),
        ]),
        isNull,
      );
      expect(ActionRules.activeAt([am, pm, _torch], mondayMorning), [
        am,
        _torch,
      ]);
    });

    test('schedules survive JSON and old actions default to always', () {
      final a = _spotify.copyWith(
        time: ActionTime.evening,
        days: ActionDays.weekends,
      );
      expect(CardAction.fromJson(a.toJson()), a);
      expect(_spotify.toJson().containsKey('time'), isFalse);
      expect(
        CardAction.fromJson({'type': 'flashlight', 'value': 'on'}).time,
        ActionTime.always,
      );
    });
  });

  group('storage', () {
    test('actions survive a save and load', () async {
      final dir = await Directory.systemTemp.createTemp('tapsy_actions');
      addTearDown(() => dir.delete(recursive: true));
      final repo = FileCardRepository(directory: () async => dir);
      await repo.saveAll([
        RegisteredCard.create(
          name: 'Gym tag',
          fingerprint: 'aaaa-bbbb-cccc',
          category: CardCategory.otherTag,
          message: '',
          actions: const [
            _torch,
            CardAction(
              type: ActionType.whatsapp,
              value: '+919876543210',
              label: 'Mom',
              extra: 'On my way',
            ),
          ],
        ),
      ]);
      final card = (await repo.loadAll()).single;
      expect(card.actions, [
        _torch,
        const CardAction(
          type: ActionType.whatsapp,
          value: '+919876543210',
          label: 'Mom',
          extra: 'On my way',
        ),
      ]);
      expect(card.summary, '⚡ Toggle flashlight +1');
    });

    test('cards saved before actions existed load with none', () {
      final card = RegisteredCard.fromJson({
        'id': 'x',
        'name': 'Old',
        'fingerprint': 'aaaa-bbbb-cccc',
        'category': 'smartCard',
        'message': 'hi',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(card.actions, isEmpty);
      expect(card.toJson().containsKey('actions'), isFalse);
    });
  });

  group('controller', () {
    late CardsController cards;

    setUp(() => cards = CardsController(MemoryCardRepository()));

    test('message may be empty only when there are actions', () async {
      expect(
        () => cards.add(
          name: 'Tag',
          message: '',
          fingerprint: 'aaaa-bbbb-cccc',
          category: CardCategory.otherTag,
        ),
        throwsA(isA<CardRuleException>()),
      );
      final card = await cards.add(
        name: 'Tag',
        message: '',
        fingerprint: 'aaaa-bbbb-cccc',
        category: CardCategory.otherTag,
        actions: const [_torch],
      );
      expect(card.actions, [_torch]);
    });

    test('rejects two actions that open apps', () async {
      final card = await cards.add(
        name: 'Tag',
        message: 'hi',
        fingerprint: 'aaaa-bbbb-cccc',
        category: CardCategory.otherTag,
      );
      expect(
        () => cards.edit(
          card.id,
          name: 'Tag',
          message: 'hi',
          actions: const [_spotify, _link],
        ),
        throwsA(isA<CardRuleException>()),
      );
      await cards.edit(
        card.id,
        name: 'Tag',
        message: 'hi',
        actions: const [_spotify],
      );
      expect(cards.byId(card.id)!.actions, [_spotify]);
      // Editing without passing actions keeps them.
      await cards.edit(card.id, name: 'Tag 2', message: 'hi');
      expect(cards.byId(card.id)!.actions, [_spotify]);
    });
  });

  group('editor', () {
    late FakeNfcPlatform platform;
    late List<CardAction> actions;

    Future<void> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ActionsEditor(
                actions: actions,
                platform: platform,
                onChanged: (v) => setState(() => actions = v),
              ),
            ),
          ),
        ),
      );
    }

    setUp(() {
      platform = FakeNfcPlatform();
      actions = [];
    });

    testWidgets('adds a copy-text action', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('add-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('type-copyText')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Text to copy'),
        'me@upi',
      );
      await tester.tap(find.text('ADD ACTION'));
      await tester.pumpAndSettle();
      expect(actions, [_upi]);
      expect(find.text('Copy text'), findsOneWidget);
    });

    testWidgets('a link without https gets it added', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('add-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('type-openLink')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'youtube.com');
      await tester.tap(find.text('ADD ACTION'));
      await tester.pumpAndSettle();
      expect(actions, [_link]);
    });

    testWidgets('picking a contact fills the WhatsApp number', (tester) async {
      platform.contact = const PickedContact(
        name: 'Mom',
        phone: '+91 98765 43210',
      );
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('add-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('type-whatsapp')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose a contact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ADD ACTION'));
      await tester.pumpAndSettle();
      expect(actions.single.title, 'WhatsApp Mom');
      expect(actions.single.value, '+91 98765 43210');
    });

    testWidgets('choosing an app from the picker', (tester) async {
      platform.apps = const [
        InstalledApp(
          packageName: 'com.google.android.youtube',
          label: 'YouTube',
        ),
        InstalledApp(packageName: 'com.spotify.music', label: 'Spotify'),
      ];
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('add-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('type-openApp')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'spot');
      await tester.pumpAndSettle();
      expect(find.text('YouTube'), findsNothing);
      await tester.tap(find.text('Spotify'));
      await tester.pumpAndSettle();
      // Then when it runs.
      expect(find.text('Spotify'), findsOneWidget);
      await tester.tap(find.text('ADD ACTION'));
      await tester.pumpAndSettle();
      expect(actions, [_spotify]);
    });

    testWidgets('a second opener needs a different time', (tester) async {
      actions = [_spotify.copyWith(time: ActionTime.morning)];
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('add-action')));
      await tester.pumpAndSettle();
      expect(find.textContaining('already opens'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('type-openLink')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'youtube.com');
      await tester.tap(find.text('ADD ACTION'));
      await tester.pumpAndSettle();
      // "Any time" would clash with the morning app.
      expect(find.text(ActionRules.clashMessage), findsOneWidget);
      expect(actions, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('time-night')));
      await tester.pump();
      await tester.tap(find.text('ADD ACTION'));
      await tester.pumpAndSettle();
      expect(actions, hasLength(2));
      expect(actions.last, _link.copyWith(time: ActionTime.night));
      expect(find.text('Nights'), findsOneWidget); // Schedule pill.
    });
  });
}
