import 'package:nfcpin/shared/security/auth_service.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({this.available = true, this.result = AuthResult.success});

  bool available;
  AuthResult result;
  final reasons = <String>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AuthResult> authenticate(String reason) async {
    reasons.add(reason);
    return available ? result : AuthResult.unavailable;
  }
}
