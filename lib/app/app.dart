import 'package:flutter/material.dart';

import '../features/cards/presentation/cards_controller.dart';
import '../features/cards/presentation/home_screen.dart';
import '../features/nfc/data/nfc_platform.dart';
import 'theme.dart';

class NfcPinApp extends StatelessWidget {
  const NfcPinApp({super.key, required this.platform, required this.cards});

  final NfcPlatform platform;
  final CardsController cards;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFC PIN App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: HomeScreen(platform: platform, cards: cards),
    );
  }
}
