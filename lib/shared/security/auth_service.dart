import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum AuthResult {
  success,

  /// The user closed the prompt or failed to match.
  failed,

  /// No fingerprint/face/screen lock is set up, so nothing can be checked.
  unavailable,
}

/// Fingerprint / face / device-credential check via the system prompt.
abstract class AuthService {
  Future<bool> isAvailable();
  Future<AuthResult> authenticate(String reason);
}

class LocalAuthService implements AuthService {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<AuthResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? AuthResult.success : AuthResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled => AuthResult.unavailable,
        _ => AuthResult.failed,
      };
    } on PlatformException {
      return AuthResult.failed;
    }
  }
}
