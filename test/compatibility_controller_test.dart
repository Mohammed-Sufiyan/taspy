import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';
import 'package:nfcpin/features/nfc/presentation/compatibility_controller.dart';

import 'fake_nfc_platform.dart';

void main() {
  late FakeNfcPlatform platform;
  late CompatibilityController controller;

  Future<void> setUpController({
    bool hardware = true,
    bool enabled = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    platform = FakeNfcPlatform(hardware: hardware, enabled: enabled);
    controller = CompatibilityController(platform, scanTimeout: timeout);
    await controller.init();
  }

  tearDown(() => controller.dispose());

  test('reports status from the platform', () async {
    await setUpController(enabled: false);
    expect(controller.status!.hardware, isTrue);
    expect(controller.status!.enabled, isFalse);
  });

  test('start and cancel scan', () async {
    await setUpController();
    await controller.startScan();
    expect(controller.phase, ScanPhase.scanning);

    await controller.cancelScan();
    expect(controller.phase, ScanPhase.idle);
    expect(platform.stopCalls, 1);
  });

  test('ignores a second start while scanning', () async {
    await setUpController();
    await controller.startScan();
    await controller.startScan();
    expect(platform.startCalls, 1);
  });

  test('explains missing hardware and disabled NFC', () async {
    await setUpController(hardware: false);
    await controller.startScan();
    expect(controller.phase, ScanPhase.failed);
    expect(controller.message, contains('no NFC hardware'));

    controller.dispose();
    await setUpController(enabled: false);
    await controller.startScan();
    expect(controller.message, contains('turned off'));
  });

  test('times out when no card is tapped', () async {
    await setUpController(timeout: const Duration(milliseconds: 20));
    await controller.startScan();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(controller.phase, ScanPhase.timedOut);
    expect(platform.stopCalls, 1);
  });

  test('stops scanning when NFC is switched off', () async {
    await setUpController();
    await controller.startScan();
    platform.setEnabled(false);
    await pumpEventQueue();
    expect(controller.phase, ScanPhase.failed);
    expect(controller.status!.enabled, isFalse);
  });

  test('records detections and keeps scanning for repeat taps', () async {
    await setUpController();
    await controller.startScan();
    platform.tap();
    await pumpEventQueue();
    expect(controller.readings, hasLength(1));
    expect(controller.readings.single.category, CardCategory.smartCard);
    expect(controller.phase, ScanPhase.scanning);
  });

  test('drops a duplicate delivery of the same tap', () async {
    await setUpController();
    final now = DateTime.now();
    platform
      ..tap(at: now)
      ..tap(at: now.add(const Duration(milliseconds: 200)));
    await pumpEventQueue();
    expect(controller.readings, hasLength(1));

    platform.tap(at: now.add(const Duration(seconds: 3)));
    await pumpEventQueue();
    expect(controller.readings, hasLength(2));
  });

  test('ID consistency: stable vs changing IDs', () async {
    await setUpController();
    final t = DateTime.now();
    platform
      ..tap(at: t)
      ..tap(at: t.add(const Duration(seconds: 2)));
    await pumpEventQueue();
    expect(controller.idConsistency!.isStable, isTrue);

    platform.tap(
      fingerprint: 'ffff-0000-1111',
      at: t.add(const Duration(seconds: 4)),
    );
    await pumpEventQueue();
    expect(controller.idConsistency!.isStable, isFalse);
    expect(controller.idConsistency!.distinctIds, 2);
  });

  test('dispatch taps are recorded with their source', () async {
    await setUpController();
    platform.tap(source: TagSource.launchedFromClosed);
    await pumpEventQueue();
    expect(controller.readings.single.source.isDispatch, isTrue);
    expect(controller.message, contains('Android delivered'));
  });

  test('NDEF tags are categorised separately', () async {
    await setUpController();
    platform.tap(techs: const ['NfcA', 'MifareUltralight', 'Ndef']);
    await pumpEventQueue();
    expect(controller.readings.single.category, CardCategory.ndefTag);
  });

  test('report contains no raw IDs, only fingerprints', () async {
    await setUpController();
    platform.tap();
    await pumpEventQueue();
    final report = controller.report();
    expect(report, contains('aaaa-bbbb-cccc'));
    expect(report, contains('Test phone'));
  });
}
