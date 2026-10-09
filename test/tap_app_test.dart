import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/features/cards/domain/registered_card.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';
import 'package:nfcpin/features/tap/tap_app.dart';

import 'fake_nfc_platform.dart';
import 'memory_card_repository.dart';

void main() {
  late FakeNfcPlatform platform;
  late MemoryCardRepository repo;

  Future<void> pumpPopup(WidgetTester tester, {bool enabled = true}) async {
    platform = FakeNfcPlatform();
    repo = MemoryCardRepository()
      ..stored = [
        RegisteredCard.create(
          name: 'SBI Card',
          fingerprint: 'aaaa-bbbb-cccc',
          category: CardCategory.smartCard,
          message: 'Your registered card was detected.',
        ).copyWith(enabled: enabled),
      ];
    await tester.pumpWidget(TapApp(platform: platform, repository: repo));
  }

  Future<void> tapCard(WidgetTester tester, String fingerprint) async {
    platform.tap(
      source: TagSource.launchedFromClosed,
      fingerprint: fingerprint,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('registered card shows its message and records the tap', (
    tester,
  ) async {
    await pumpPopup(tester);
    await tapCard(tester, 'aaaa-bbbb-cccc');

    expect(find.text('SBI Card'), findsWidgets); // Title and card face.
    expect(find.text('Your registered card was detected.'), findsOneWidget);
    expect(repo.stored.single.lastTriggeredAt, isNotNull);

    await tester.tap(find.text('OK'));
    expect(platform.closeCalls, 1);
  });

  testWidgets('unrelated card does not trigger the action', (tester) async {
    await pumpPopup(tester);
    await tapCard(tester, 'ffff-0000-1111');

    expect(find.text('New card?'), findsOneWidget);
    expect(find.text('Your registered card was detected.'), findsNothing);
    expect(repo.stored.single.lastTriggeredAt, isNull);

    await tester.tap(find.text('Open Tapsy'));
    expect(platform.openAppCalls, 1);
  });

  testWidgets('disabled card says it is off instead of the message', (
    tester,
  ) async {
    await pumpPopup(tester, enabled: false);
    await tapCard(tester, 'aaaa-bbbb-cccc');

    expect(find.textContaining('turned off'), findsOneWidget);
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
}
