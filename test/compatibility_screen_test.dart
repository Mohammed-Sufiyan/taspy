import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/features/nfc/presentation/compatibility_controller.dart';
import 'package:nfcpin/features/nfc/presentation/compatibility_screen.dart';

import 'fake_nfc_platform.dart';

void main() {
  Future<(FakeNfcPlatform, CompatibilityController)> pumpScreen(
    WidgetTester tester, {
    bool hardware = true,
    bool enabled = true,
  }) async {
    final platform = FakeNfcPlatform(hardware: hardware, enabled: enabled);
    final controller = CompatibilityController(platform);
    addTearDown(controller.dispose);
    await controller.init();
    await tester.pumpWidget(
      MaterialApp(home: CompatibilityScreen(controller: controller)),
    );
    return (platform, controller);
  }

  testWidgets('explains when the phone has no NFC', (tester) async {
    await pumpScreen(tester, hardware: false);
    expect(find.text('This phone has no NFC'), findsOneWidget);
    final scan = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(scan.onPressed, isNull);
  });

  testWidgets('offers settings when NFC is off', (tester) async {
    await pumpScreen(tester, enabled: false);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Open NFC settings'), findsOneWidget);
  });

  testWidgets('scan, detect and cancel', (tester) async {
    final (platform, _) = await pumpScreen(tester);

    await tester.tap(find.text('Scan NFC card'));
    await tester.pump();
    expect(find.text('Scanning…'), findsOneWidget);

    platform.tap();
    await tester.pump();
    expect(find.text('Smart card (ISO-DEP)'), findsOneWidget);

    await tester.tap(find.text('Stop scanning'));
    await tester.pump();
    expect(find.text('Scan NFC card'), findsOneWidget);
    expect(platform.stopCalls, 1);
  });
}
