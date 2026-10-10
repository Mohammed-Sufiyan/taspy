import 'dart:async';

import 'package:nfcpin/features/actions/domain/card_action.dart';
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

  int soundCalls = 0;
  bool sound = true;
  bool onboarded = true;
  bool appLock = false;
  bool secure = false;

  @override
  Future<void> setSecure(bool value) async => secure = value;

  @override
  Future<void> playTapSound() async => soundCalls++;

  @override
  Future<AppSettings> getSettings() async =>
      AppSettings(sound: sound, onboarded: onboarded, appLock: appLock);

  @override
  Future<void> setSetting(String key, bool value) async {
    if (key == 'sound') sound = value;
    if (key == 'onboarded') onboarded = value;
    if (key == 'appLock') appLock = value;
  }

  final List<CardAction> ranActions = [];

  /// Result per action type; defaults to done (flashlight: on).
  final Map<ActionType, ActionResult> actionResults = {};
  List<InstalledApp> apps = const [];
  PickedContact? contact;

  @override
  Future<ActionResult> runAction(CardAction action) async {
    ranActions.add(action);
    return actionResults[action.type] ??
        (action.type == ActionType.flashlight
            ? ActionResult.on
            : ActionResult.done);
  }

  @override
  Future<List<InstalledApp>> listApps() async => apps;

  @override
  Future<PickedContact?> pickContact() async => contact;

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
