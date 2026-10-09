import 'package:flutter/services.dart';

import '../domain/nfc_models.dart';

sealed class NfcEvent {
  const NfcEvent();
}

class NfcStatusChanged extends NfcEvent {
  const NfcStatusChanged(this.status);

  final NfcStatus status;
}

class NfcTagDetected extends NfcEvent {
  const NfcTagDetected(this.reading);

  final TagReading reading;
}

/// Thrown when a scan cannot start. [code] is `unavailable`, `disabled` or a
/// platform error code.
class NfcScanException implements Exception {
  const NfcScanException(this.code);

  final String code;

  @override
  String toString() => 'NfcScanException($code)';
}

/// Boundary to the native NFC layer (see `NfcBridge.kt`).
abstract class NfcPlatform {
  Future<NfcStatus> getStatus();
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> openSettings();

  /// Tap popup only: closes the popup activity.
  Future<void> close();

  /// Tap popup only: opens the main app and closes the popup.
  Future<void> openApp();

  Stream<NfcEvent> get events;
}

class MethodChannelNfcPlatform implements NfcPlatform {
  static const _methods = MethodChannel('nfcpin/nfc');
  static const _events = EventChannel('nfcpin/nfc_events');

  @override
  Future<NfcStatus> getStatus() async {
    final map = await _methods.invokeMapMethod<Object?, Object?>('getStatus');
    return NfcStatus.fromMap(map ?? const {});
  }

  @override
  Future<void> startScan() async {
    try {
      await _methods.invokeMethod<void>('startScan');
    } on PlatformException catch (e) {
      throw NfcScanException(e.code);
    }
  }

  @override
  Future<void> stopScan() => _methods.invokeMethod<void>('stopScan');

  @override
  Future<void> openSettings() => _methods.invokeMethod<void>('openSettings');

  @override
  Future<void> close() => _methods.invokeMethod<void>('close');

  @override
  Future<void> openApp() => _methods.invokeMethod<void>('openApp');

  @override
  late final Stream<NfcEvent> events = _events.receiveBroadcastStream().map((
    raw,
  ) {
    final map = raw as Map<Object?, Object?>;
    return map['type'] == 'status'
        ? NfcStatusChanged(NfcStatus.fromMap(map))
        : NfcTagDetected(TagReading.fromMap(map));
  });
}
