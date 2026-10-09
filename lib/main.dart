import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/cards/data/card_repository.dart';
import 'features/cards/presentation/cards_controller.dart';
import 'features/nfc/data/nfc_platform.dart';
import 'features/tap/tap_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    NfcPinApp(
      platform: MethodChannelNfcPlatform(),
      cards: CardsController(FileCardRepository()),
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
      repository: FileCardRepository(),
    ),
  );
}
