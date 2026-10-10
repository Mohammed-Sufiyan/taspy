import 'package:flutter/services.dart';

import '../../actions/domain/card_action.dart';
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

/// Small user preferences kept natively (readable from the tap popup too).
class AppSettings {
  const AppSettings({
    required this.sound,
    required this.onboarded,
    this.appLock = false,
  });

  final bool sound;
  final bool onboarded;

  /// Require fingerprint/face/PIN to open Tapsy.
  final bool appLock;
}

/// How running a [CardAction] went.
enum ActionResult {
  done,

  /// Flashlight result: now on / off.
  on,
  off,

  /// App not installed, or nothing on the phone can open it.
  notFound,

  /// The phone has no flashlight.
  unsupported,

  /// The camera/flash is in use by another app.
  busy,

  /// Refused by Android or by Tapsy's safety rules (e.g. a non-https link).
  blocked,
  failed;

  bool get ok => this == done || this == on || this == off;

  static ActionResult parse(String? code) => switch (code) {
    'ok' => done,
    'on' => on,
    'off' => off,
    'not_found' => notFound,
    'unsupported' => unsupported,
    'busy' => busy,
    'blocked' => blocked,
    _ => failed,
  };
}

/// A launchable app, for the "Open an app" picker.
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    this.icon,
  });

  final String packageName;
  final String label;

  /// PNG bytes of the app icon, if available.
  final Uint8List? icon;
}

/// Name and number of a contact chosen in the system contact picker. Tapsy
/// gets only this one entry, not the contact list.
class PickedContact {
  const PickedContact({required this.name, required this.phone});

  final String name;
  final String phone;
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

  /// Plays the tap chime (native side skips it if sound is off or the phone is silent).
  Future<void> playTapSound();

  Future<AppSettings> getSettings();
  Future<void> setSetting(String key, bool value);

  /// Blocks screenshots and blanks the app's Recents thumbnail while on.
  Future<void> setSecure(bool secure);

  /// Runs one card action natively (opens apps, flashlight, clipboard…).
  Future<ActionResult> runAction(CardAction action);

  /// Apps that appear in the launcher, sorted by name.
  Future<List<InstalledApp>> listApps();

  /// Opens the system contact picker; null if cancelled.
  Future<PickedContact?> pickContact();

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
  Future<void> playTapSound() => _methods.invokeMethod<void>('playTapSound');

  @override
  Future<AppSettings> getSettings() async {
    final map = await _methods.invokeMapMethod<Object?, Object?>('getSettings');
    return AppSettings(
      sound: map?['sound'] != false,
      onboarded: map?['onboarded'] == true,
      appLock: map?['appLock'] == true,
    );
  }

  @override
  Future<void> setSecure(bool secure) =>
      _methods.invokeMethod<void>('setSecure', {'secure': secure});

  @override
  Future<void> setSetting(String key, bool value) =>
      _methods.invokeMethod<void>('setSetting', {'key': key, 'value': value});

  @override
  Future<ActionResult> runAction(CardAction action) async {
    try {
      final code = await _methods.invokeMethod<String>('runAction', {
        'type': action.type.name,
        'value': action.value,
        'label': action.label,
        'extra': action.extra,
      });
      return ActionResult.parse(code);
    } on PlatformException {
      return ActionResult.failed;
    }
  }

  @override
  Future<List<InstalledApp>> listApps() async {
    final list = await _methods.invokeListMethod<Object?>('listApps') ?? [];
    return [
      for (final raw in list.cast<Map<Object?, Object?>>())
        InstalledApp(
          packageName: raw['package']! as String,
          label: raw['label']! as String,
          icon: raw['icon'] as Uint8List?,
        ),
    ];
  }

  @override
  Future<PickedContact?> pickContact() async {
    final map = await _methods.invokeMapMethod<Object?, Object?>('pickContact');
    final phone = map?['phone'] as String?;
    if (map == null || phone == null || phone.isEmpty) return null;
    return PickedContact(name: map['name'] as String? ?? '', phone: phone);
  }

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
