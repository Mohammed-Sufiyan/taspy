import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../cards/data/card_repository.dart';
import '../cards/domain/tap_resolver.dart';
import '../cards/presentation/cards_controller.dart';
import '../nfc/data/nfc_platform.dart';

/// The popup shown over other apps when a card is tapped (runs in
/// `TapActivity`, a transparent Android activity with its own Flutter engine).
class TapApp extends StatefulWidget {
  const TapApp({super.key, required this.platform, required this.repository});

  final NfcPlatform platform;
  final CardRepository repository;

  @override
  State<TapApp> createState() => _TapAppState();
}

class _TapAppState extends State<TapApp> {
  late final CardsController _cards = CardsController(widget.repository);
  StreamSubscription<NfcEvent>? _subscription;
  TapOutcome? _outcome;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.platform.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _cards.dispose();
    super.dispose();
  }

  Future<void> _onEvent(NfcEvent event) async {
    if (event is! NfcTagDetected) return;
    // Always read fresh: cards may have changed since this engine started.
    await _cards.load();
    if (_cards.loadError case final error?) {
      setState(() => _error = error);
      return;
    }
    final outcome = resolveTap(event.reading, _cards.cards);
    setState(() {
      _outcome = outcome;
      _error = null;
    });
    if (outcome is RegisteredTap) {
      // Best effort: the popup still shows if this write fails.
      _cards.markTriggered(outcome.card.id).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.platform.close,
          child: ColoredBox(
            color: Colors.black54,
            child: Center(
              child: GestureDetector(
                onTap: () {}, // Taps inside the dialog don't dismiss it.
                child: _TapDialog(
                  outcome: _outcome,
                  error: _error,
                  onClose: widget.platform.close,
                  onOpenApp: widget.platform.openApp,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TapDialog extends StatelessWidget {
  const _TapDialog({
    required this.outcome,
    required this.error,
    required this.onClose,
    required this.onOpenApp,
  });

  final TapOutcome? outcome;
  final String? error;
  final VoidCallback onClose;
  final VoidCallback onOpenApp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = FilledButton(onPressed: onClose, child: const Text('OK'));
    final openApp = TextButton(
      onPressed: onOpenApp,
      child: const Text('Open app'),
    );

    final (icon, color, title, body, actions) = switch ((error, outcome)) {
      (final String e, _) => (
        Icons.error_outline,
        scheme.error,
        'Could not check this card',
        e,
        [openApp, ok],
      ),
      (_, RegisteredTap(:final card)) => (
        Icons.verified,
        scheme.primary,
        card.name,
        card.message,
        [ok],
      ),
      (_, DisabledCardTap(:final card)) => (
        Icons.notifications_off_outlined,
        scheme.outline,
        card.name,
        'This card is turned off. Turn it back on in the app to show its message.',
        [openApp, ok],
      ),
      (_, UnknownCardTap()) => (
        Icons.help_outline,
        scheme.tertiary,
        'Unregistered card',
        'This card is not registered. Open the app to add it.',
        [openApp, ok],
      ),
      (_, null) => (
        Icons.contactless,
        scheme.primary,
        'Reading card…',
        '',
        <Widget>[],
      ),
    };

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      margin: const EdgeInsets.all(24),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
              if (outcome == null && error == null) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final a in actions) ...[const SizedBox(width: 8), a],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
