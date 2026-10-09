import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/features/cards/presentation/add_card_controller.dart';
import 'package:nfcpin/features/cards/presentation/add_card_screen.dart';
import 'package:nfcpin/features/cards/presentation/cards_controller.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';

import 'package:nfcpin/features/security/security_controller.dart';

import 'fake_auth.dart';
import 'fake_nfc_platform.dart';
import 'memory_card_repository.dart';

void main() {
  late FakeNfcPlatform platform;
  late MemoryCardRepository repo;
  late CardsController cards;
  late AddCardController controller;
  final t0 = DateTime(2026, 10, 9, 12);

  Future<void> setUpFlow({
    bool enabled = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    platform = FakeNfcPlatform(enabled: enabled);
    repo = MemoryCardRepository();
    cards = CardsController(repo);
    await cards.load();
    controller = AddCardController(platform, cards, scanTimeout: timeout);
    await controller.start();
  }

  tearDown(() => controller.dispose());

  Future<void> tapAt(
    Duration offset, {
    String? fingerprint = 'aaaa-bbbb-cccc',
  }) async {
    platform.tap(fingerprint: fingerprint, at: t0.add(offset));
    await pumpEventQueue();
  }

  test('two matching taps verify the card, then it can be saved', () async {
    await setUpFlow();
    expect(controller.step, AddCardStep.waitingFirstTap);

    await tapAt(Duration.zero);
    expect(controller.step, AddCardStep.waitingConfirmTap);

    await tapAt(const Duration(seconds: 2));
    expect(controller.step, AddCardStep.ready);
    expect(platform.stopCalls, 1);

    final saved = await controller.save(name: 'SBI Card', message: 'Hi');
    expect(saved, isNotNull);
    expect(repo.stored.single.fingerprint, 'aaaa-bbbb-cccc');
  });

  test('cannot save before the card is verified', () async {
    await setUpFlow();
    await tapAt(Duration.zero);
    expect(await controller.save(name: 'X', message: 'Y'), isNull);
    expect(repo.stored, isEmpty);
  });

  test(
    'a repeat detection of the same touch is not a confirming tap',
    () async {
      await setUpFlow();
      await tapAt(Duration.zero);
      await tapAt(const Duration(milliseconds: 100));
      expect(controller.step, AddCardStep.waitingConfirmTap);
    },
  );

  test('a changed ID is rejected', () async {
    await setUpFlow();
    await tapAt(Duration.zero);
    await tapAt(const Duration(seconds: 2), fingerprint: 'ffff-0000-1111');
    expect(controller.step, AddCardStep.idChanged);
  });

  test('a tag without an ID is rejected', () async {
    await setUpFlow();
    await tapAt(Duration.zero, fingerprint: null);
    expect(controller.step, AddCardStep.noId);
  });

  test('an already registered card is reported', () async {
    await setUpFlow();
    await cards.add(
      name: 'SBI Card',
      message: 'Hi',
      fingerprint: 'aaaa-bbbb-cccc',
      category: CardCategory.smartCard,
    );
    await tapAt(Duration.zero);
    expect(controller.step, AddCardStep.alreadyRegistered);
    expect(controller.existing!.name, 'SBI Card');
  });

  test('times out and can retry', () async {
    await setUpFlow(timeout: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(controller.step, AddCardStep.timedOut);

    await controller.restart();
    expect(controller.step, AddCardStep.waitingFirstTap);
    expect(platform.startCalls, 2);
  });

  test('NFC off is explained', () async {
    await setUpFlow(enabled: false);
    expect(controller.step, AddCardStep.nfcUnavailable);
    expect(controller.nfcProblem, contains('turned off'));
  });

  test('NFC switched off mid-scan stops the flow', () async {
    await setUpFlow();
    platform.setEnabled(false);
    await pumpEventQueue();
    expect(controller.step, AddCardStep.nfcUnavailable);
  });

  test('leaving the screen stops the scan', () async {
    await setUpFlow();
    controller.dispose();
    expect(platform.stopCalls, 1);
    controller = AddCardController(platform, cards); // for tearDown
  });

  Future<void> walkThroughScreen(WidgetTester tester) async {
    platform = FakeNfcPlatform();
    repo = MemoryCardRepository();
    cards = CardsController(repo);
    controller = AddCardController(platform, cards); // unused; for tearDown
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddCardScreen(
                  platform: platform,
                  cards: cards,
                  security: SecurityController(platform, FakeAuthService()),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Tap your card on the back'), findsOneWidget);

    platform.tap(at: t0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Got it! Tap once more'), findsOneWidget);

    platform.tap(at: t0.add(const Duration(seconds: 2)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Card verified'), findsOneWidget);

    final list = find.byType(Scrollable).first;
    final nameField = find.widgetWithText(TextFormField, 'Card name');
    await tester.scrollUntilVisible(nameField, 200, scrollable: list);
    await tester.enterText(nameField, 'SBI Card');
    await tester.pump(const Duration(milliseconds: 500));
    // Live preview on the card face.
    expect(find.text('SBI Card'), findsWidgets);

    final grape = find.byKey(const ValueKey('skin-2'));
    await tester.scrollUntilVisible(grape, -200, scrollable: list);
    await tester.tap(grape);
    final save = find.text('SAVE CARD');
    await tester.scrollUntilVisible(save, 200, scrollable: list);
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('All set!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1)); // Route pop transition.
    expect(find.text('open'), findsOneWidget); // Back on the previous screen.
    expect(repo.stored.single.name, 'SBI Card');
    expect(repo.stored.single.style, 2);
  }

  testWidgets('screen walks through tap, confirm and form', walkThroughScreen);

  testWidgets('same flow works with animations turned off', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await walkThroughScreen(tester);
  });
}
