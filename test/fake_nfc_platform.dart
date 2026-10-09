import 'dart:async';

import 'package:nfcpin/features/nfc/data/nfc_platform.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';

class FakeNfcPlatform implements NfcPlatform {
  FakeNfcPlatform({this.hardware = true, this.enabled = true});

  bool hardware;
  bool enabled;
  int startCalls = 0;
  int stopCalls = 0;
  final _events = StreamController<NfcEvent>.broadcast();

  NfcStatus get _status => NfcStatus(
    hardware: hardware,
    enabled: enabled,
    device: 'Test phone',
    androidVersion: '15',
    sdkInt: 35,
  );

  @override
  Future<NfcStatus> getStatus() async => _status;

  @override
  Future<void> startScan() async {
    startCalls++;
    if (!hardware) throw const NfcScanException('unavailable');
    if (!enabled) throw const NfcScanException('disabled');
  }

  @override
  Future<void> stopScan() async => stopCalls++;

  @override
  Future<void> openSettings() async {}

  int closeCalls = 0;
  int openAppCalls = 0;

  @override
  Future<void> close() async => closeCalls++;

  @override
  Future<void> openApp() async => openAppCalls++;

  @override
  Stream<NfcEvent> get events => _events.stream;

  void setEnabled(bool value) {
    enabled = value;
    _events.add(NfcStatusChanged(_status));
  }

  void tap({
    String? fingerprint = 'aaaa-bbbb-cccc',
    TagSource source = TagSource.foregroundScan,
    List<String> techs = const ['IsoDep', 'NfcA'],
    DateTime? at,
  }) {
    _events.add(
      NfcTagDetected(
        TagReading(
          source: source,
          techs: techs,
          fingerprint: fingerprint,
          idLength: 4,
          randomIdHint: false,
          at: at ?? DateTime.now(),
        ),
      ),
    );
  }
}
