import 'package:flutter/foundation.dart';

import '../../shared/security/auth_service.dart';
import '../nfc/data/nfc_platform.dart';

/// App lock state and biometric checks for the main app.
///
/// When app lock is on, Tapsy starts locked and locks again after it has been
/// in the background for [relockAfter]. Screenshots and the Recents thumbnail
/// are blocked while app lock is on.
class SecurityController extends ChangeNotifier {
  SecurityController(this._platform, this._auth, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final NfcPlatform _platform;
  final AuthService _auth;
  final DateTime Function() _now;

  static const relockAfter = Duration(seconds: 60);

  bool loaded = false;
  bool appLock = false;
  bool locked = false;

  /// Whether the phone has a fingerprint, face or screen lock we can check.
  bool available = false;

  DateTime? _hiddenAt;

  Future<void> load() async {
    try {
      final settings = await _platform.getSettings();
      appLock = settings.appLock;
      available = await _auth.isAvailable();
      // If the screen lock was removed after enabling, don't lock the user out.
      if (appLock && !available) appLock = false;
      locked = appLock;
      await _platform.setSecure(appLock);
    } catch (_) {
      appLock = false;
      locked = false;
    }
    loaded = true;
    notifyListeners();
  }

  Future<AuthResult> unlock() async {
    final result = await _auth.authenticate('Unlock Tapsy');
    if (result == AuthResult.success) {
      locked = false;
      notifyListeners();
    }
    return result;
  }

  /// Turning app lock on or off both require the owner to verify first.
  Future<AuthResult> setAppLock(bool enabled) async {
    final result = await _auth.authenticate(
      enabled ? 'Turn on app lock' : 'Turn off app lock',
    );
    if (result == AuthResult.success) {
      appLock = enabled;
      await _platform.setSetting('appLock', enabled);
      await _platform.setSecure(enabled);
      notifyListeners();
    }
    return result;
  }

  /// One-off check, e.g. to reveal a secret card's message.
  Future<AuthResult> verify(String reason) => _auth.authenticate(reason);

  void onHidden() => _hiddenAt = _now();

  void onShown() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (appLock &&
        hiddenAt != null &&
        _now().difference(hiddenAt) >= relockAfter) {
      locked = true;
      notifyListeners();
    }
  }
}
