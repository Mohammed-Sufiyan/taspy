import 'package:flutter/material.dart';

import '../features/cards/presentation/cards_controller.dart';
import '../features/cards/presentation/home_screen.dart';
import '../features/nfc/data/nfc_platform.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'theme.dart';

class NfcPinApp extends StatefulWidget {
  const NfcPinApp({super.key, required this.platform, required this.cards});

  final NfcPlatform platform;
  final CardsController cards;

  @override
  State<NfcPinApp> createState() => _NfcPinAppState();
}

class _NfcPinAppState extends State<NfcPinApp> {
  /// Null while loading; then whether the welcome tour still needs showing.
  bool? _showTour;

  @override
  void initState() {
    super.initState();
    widget.platform
        .getSettings()
        .then((s) => !s.onboarded, onError: (_) => false)
        .then((show) {
          if (mounted) setState(() => _showTour = show);
        });
  }

  void _finishTour() {
    widget.platform.setSetting('onboarded', true).ignore();
    setState(() => _showTour = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tapsy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: switch (_showTour) {
        null => const Scaffold(),
        true => OnboardingScreen(onDone: _finishTour),
        false => HomeScreen(platform: widget.platform, cards: widget.cards),
      },
    );
  }
}
