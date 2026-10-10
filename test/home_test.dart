import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/app/theme.dart';
import 'package:nfcpin/features/cards/domain/registered_card.dart';
import 'package:nfcpin/features/cards/presentation/cards_controller.dart';
import 'package:nfcpin/features/cards/presentation/home_screen.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';

import 'package:nfcpin/features/security/security_controller.dart';

import 'fake_auth.dart';
import 'fake_nfc_platform.dart';
import 'memory_card_repository.dart';

void main() {
  late FakeNfcPlatform platform;
  late MemoryCardRepository repo;

  RegisteredCard card(String name, String fp, int style) =>
      RegisteredCard.create(
        name: name,
        fingerprint: fp,
        category: CardCategory.smartCard,
        message: '$name message',
        style: style,
      );

  Future<void> pumpHome(
    WidgetTester tester,
    List<RegisteredCard> cards, {
    List<TapEvent> taps = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    platform = FakeNfcPlatform();
    repo = MemoryCardRepository()
      ..stored = cards
      ..taps = List.of(taps);
    final controller = CardsController(repo);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeScreen(
          platform: platform,
          cards: controller,
          security: SecurityController(platform, FakeAuthService()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    // Cards finish loading in the frame above, which starts the staggered
    // entrance; let it finish.
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('empty state invites adding a first card', (tester) async {
    await pumpHome(tester, []);
    expect(find.text('Tap. Pop. Done.'), findsOneWidget);
    expect(find.text('ADD YOUR FIRST CARD'), findsOneWidget);
  });

  testWidgets('tapping a card in the stack opens its action panel', (
    tester,
  ) async {
    await pumpHome(tester, [card('Gym', 'a', 1), card('Metro', 'b', 5)]);
    expect(find.text('Your cards'), findsOneWidget);
    expect(find.text('Test'), findsNothing);

    await tester.tap(find.text('METRO'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Test'), findsNothing);
  });

  testWidgets('swiping the front card up shuffles it to the back', (
    tester,
  ) async {
    await pumpHome(tester, [card('Gym', 'a', 1), card('Metro', 'b', 5)]);
    double topOf(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(topOf('METRO'), greaterThan(topOf('GYM'))); // Metro is in front.

    await tester.timedDrag(
      find.text('METRO'),
      const Offset(0, -150),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(topOf('GYM'), greaterThan(topOf('METRO'))); // Gym is now in front.
  });

  testWidgets('recent taps lists recorded taps', (tester) async {
    final gym = card('Gym', 'a', 1);
    await pumpHome(
      tester,
      [gym],
      taps: [TapEvent(cardId: gym.id, at: DateTime.now())],
    );
    expect(find.text('Recent taps'), findsOneWidget);
    expect(find.text('just now'), findsOneWidget);
  });
}
