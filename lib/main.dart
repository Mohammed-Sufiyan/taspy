import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/cards/data/card_repository.dart';
import 'features/cards/presentation/cards_controller.dart';
import 'features/nfc/data/nfc_platform.dart';
import 'features/security/security_controller.dart';
import 'features/tap/tap_app.dart';
import 'shared/security/auth_service.dart';
import 'shared/security/keystore_cipher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelNfcPlatform();
  runApp(
    NfcPinApp(
      platform: platform,
      cards: CardsController(FileCardRepository(cipher: KeystoreCipher())),
      security: SecurityController(platform, LocalAuthService())..load(),
    ),
  );
}

/// Entry point for the card-tap popup (`TapActivity.kt`).
@pragma('vm:entry-point')
void tapMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    TapApp(
      platform: MethodChannelNfcPlatform(),
      repository: FileCardRepository(cipher: KeystoreCipher()),
      auth: LocalAuthService(),
    ),
  );
}
