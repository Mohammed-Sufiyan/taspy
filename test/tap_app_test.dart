import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/features/actions/domain/card_action.dart';
import 'package:nfcpin/features/cards/domain/registered_card.dart';
import 'package:nfcpin/features/nfc/data/nfc_platform.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';
import 'package:nfcpin/features/tap/tap_app.dart';
import 'package:nfcpin/shared/security/auth_service.dart';

import 'fake_auth.dart';
import 'fake_nfc_platform.dart';
import 'memory_card_repository.dart';

void main() {
  late FakeNfcPlatform platform;
  late MemoryCardRepository repo;
  late FakeAuthService auth;

  Future<void> pumpPopup(
    WidgetTester tester, {
    bool enabled = true,
    bool secret = false,
    List<CardAction> actions = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    platform = FakeNfcPlatform();
    repo = MemoryCardRepository()
      ..stored = [
        RegisteredCard.create(
          name: 'SBI Card',
          fingerprint: 'aaaa-bbbb-cccc',
          category: CardCategory.smartCard,
          message: 'Your registered card was detected.',
        ).copyWith(enabled: enabled, secret: secret, actions: actions),
      ];
    auth = FakeAuthService();
    await tester.pumpWidget(
      TapApp(platform: platform, repository: repo, auth: auth),
    );
  }

  Future<void> tapCard(WidgetTester tester, String fingerprint) async {
    platform.tap(
      source: TagSource.launchedFromClosed,
      fingerprint: fingerprint,
    );
    await tester.pump();
    await tester.pump(
      const Duration(seconds: 1),
    ); // Sheet builds, animation starts.
    await tester.pump(const Duration(seconds: 1)); // Slide-up finishes.
  }

  testWidgets('registered card shows its message and records the tap', (
    tester,
  ) async {
    await pumpPopup(tester);
    await tapCard(tester, 'aaaa-bbbb-cccc');

    expect(find.text('SBI Card'), findsWidgets); // Title and card face.
    expect(find.text('Your registered card was detected.'), findsOneWidget);
    expect(repo.stored.single.lastTriggeredAt, isNotNull);
    expect(repo.taps.single.cardId, repo.stored.single.id);
    expect(platform.soundCalls, 1);

    await tester.tap(find.text('DONE'));
    expect(platform.closeCalls, 1);
  });

  testWidgets('unrelated card does not trigger the action', (tester) async {
    await pumpPopup(tester);
    await tapCard(tester, 'ffff-0000-1111');

    expect(find.text('New card?'), findsOneWidget);
    expect(find.text('Your registered card was detected.'), findsNothing);
    expect(repo.stored.single.lastTriggeredAt, isNull);
    expect(repo.taps, isEmpty);
    expect(platform.soundCalls, 0);

    await tester.tap(find.text('ADD IT IN TAPSY'));
    expect(platform.openAppCalls, 1);
  });

  testWidgets('disabled card says it is off instead of the message', (
    tester,
  ) async {
    await pumpPopup(tester, enabled: false);
    await tapCard(tester, 'aaaa-bbbb-cccc');

    expect(find.textContaining('paused'), findsOneWidget);
    expect(find.text('Your registered card was detected.'), findsNothing);
  });

  testWidgets('popup works with animations turned off', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpPopup(tester);
    await tapCard(tester, 'aaaa-bbbb-cccc');
    expect(find.text('Your registered card was detected.'), findsOneWidget);
    await tester.pumpAndSettle(); // Nothing loops when motion is reduced.
  });

  testWidgets('secret card hides its message until verified', (tester) async {
    await pumpPopup(tester, secret: true);
    await tapCard(tester, 'aaaa-bbbb-cccc');
    expect(find.text('Secret message'), findsOneWidget);
    expect(find.text('Your registered card was detected.'), findsNothing);
    expect(platform.secure, isTrue); // Screenshots blocked.

    auth.result = AuthResult.failed;
    await tester.tap(find.text('VERIFY TO REVEAL'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Your registered card was detected.'), findsNothing);
    expect(find.textContaining('Not verified'), findsOneWidget);

    auth.result = AuthResult.success;
    await tester.tap(find.text('VERIFY TO REVEAL'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your registered card was detected.'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // Reveal animation ends.
  });

  group('actions', () {
    const spotify = CardAction(
      type: ActionType.openApp,
      value: 'com.spotify.music',
      label: 'Spotify',
    );
    const torch = CardAction(type: ActionType.flashlight);

    testWidgets(
      'quick actions run first, then the app opens and the popup closes',
      (tester) async {
        await pumpPopup(tester, actions: const [spotify, torch]);
        platform.tap(source: TagSource.launchedFromClosed);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100)); // Sheet builds.
        await tester.pump(const Duration(milliseconds: 600)); // Slide-up ends.
        expect(platform.ranActions, [torch]);
        expect(find.text('Now on'), findsOneWidget);
        expect(find.text('OPEN NOW'), findsOneWidget);
        expect(platform.closeCalls, 0);

        await tester.pump(TapSheet.openDelay);
        expect(platform.ranActions, [torch, spotify]);
        expect(platform.closeCalls, 1);
      },
    );

    testWidgets('opening the app can be cancelled', (tester) async {
      await pumpPopup(tester, actions: const [spotify]);
      platform.tap(source: TagSource.launchedFromClosed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // Sheet builds.
      await tester.pump(const Duration(milliseconds: 600)); // Slide-up ends.
      await tester.tap(find.text('CANCEL'));
      await tester.pump(const Duration(seconds: 3));
      expect(platform.ranActions, isEmpty);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
      expect(platform.closeCalls, 0);
    });

    testWidgets('a missing app is reported instead of closing', (tester) async {
      await pumpPopup(tester, actions: const [spotify]);
      platform.actionResults[ActionType.openApp] = ActionResult.notFound;
      await tapCard(tester, 'aaaa-bbbb-cccc');
      expect(find.text('App not installed'), findsOneWidget);
      expect(platform.closeCalls, 0);
    });

    testWidgets('a secret card runs nothing until verified', (tester) async {
      await pumpPopup(tester, secret: true, actions: const [torch]);
      await tapCard(tester, 'aaaa-bbbb-cccc');
      expect(platform.ranActions, isEmpty);
      expect(find.text('Toggle flashlight'), findsNothing);

      await tester.tap(find.text('VERIFY TO REVEAL'));
      await tester.pump(const Duration(seconds: 1));
      expect(platform.ranActions, [torch]);
      expect(find.text('Toggle flashlight'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a paused card runs nothing', (tester) async {
      await pumpPopup(tester, enabled: false, actions: const [torch]);
      await tapCard(tester, 'aaaa-bbbb-cccc');
      expect(platform.ranActions, isEmpty);
    });
  });
}
