import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme.dart';
import '../../shared/motion.dart';
import '../../shared/widgets/effects.dart';
import '../cards/data/card_repository.dart';
import '../cards/domain/tap_resolver.dart';
import '../cards/presentation/card_face.dart';
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

  /// Bumped per tap so a second tap replays the entrance animation.
  int _tapCount = 0;

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
      Haptics.error();
      setState(() {
        _error = error;
        _tapCount++;
      });
      return;
    }
    final outcome = resolveTap(event.reading, _cards.cards);
    outcome is RegisteredTap ? Haptics.celebrate() : Haptics.error();
    setState(() {
      _outcome = outcome;
      _error = null;
      _tapCount++;
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
                onTap: () {}, // Taps inside the popup don't dismiss it.
                child: TapPopup(
                  key: ValueKey(_tapCount),
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

/// The popup card itself. Also used in-app to preview a card's popup.
class TapPopup extends StatelessWidget {
  const TapPopup({
    super.key,
    required this.outcome,
    required this.onClose,
    this.error,
    this.onOpenApp,
  });

  final TapOutcome? outcome;
  final String? error;
  final VoidCallback onClose;
  final VoidCallback? onOpenApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final still = reduceMotion(context);
    final ok = FilledButton(onPressed: onClose, child: const Text('OK'));
    final openApp = onOpenApp == null
        ? null
        : TextButton(onPressed: onOpenApp, child: const Text('Open Tapsy'));

    Widget badge(IconData icon, Color bg, Color fg, {bool wobble = false}) {
      Widget w = CircleAvatar(
        radius: 34,
        backgroundColor: bg,
        child: Icon(icon, size: 36, color: fg),
      );
      if (wobble && !still) {
        w = w
            .animate()
            .rotate(
              begin: -0.04,
              end: 0.04,
              duration: 120.ms,
              curve: Curves.easeInOut,
            )
            .then()
            .rotate(begin: 0.04, end: 0, duration: 200.ms);
      }
      return w;
    }

    final (
      Widget art,
      String title,
      String body,
      List<Widget> actions,
    ) = switch ((error, outcome)) {
      (final String e, _) => (
        badge(Icons.error_outline, scheme.errorContainer, scheme.error),
        'Could not check this card',
        e,
        [?openApp, ok],
      ),
      (_, RegisteredTap(:final card)) => (
        Stack(
          alignment: Alignment.center,
          children: [
            PulseRings(
              color: CardPalette.of(card.style).end,
              size: 220,
              child: const SizedBox.shrink(),
            ),
            SizedBox(
              width: 170,
              child: CardFace(name: card.name, style: card.style),
            ),
            Positioned(
              right: 18,
              bottom: 34,
              child: AnimatedCheck(color: scheme.primary, size: 44),
            ),
          ],
        ),
        card.name,
        card.message,
        [ok],
      ),
      (_, DisabledCardTap(:final card)) => (
        badge(
          Icons.pause_circle_outline,
          scheme.surfaceContainerHighest,
          scheme.outline,
        ),
        card.name,
        'This card is turned off. Turn it back on in Tapsy to show its message.',
        [?openApp, ok],
      ),
      (_, UnknownCardTap()) => (
        badge(
          Icons.question_mark_rounded,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          wobble: true,
        ),
        'New card?',
        "Tapsy doesn't know this card yet. Open the app to add it.",
        [?openApp, ok],
      ),
      (_, null) => (
        const SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator()),
        ),
        'Reading card…',
        '',
        <Widget>[],
      ),
    };

    final registered = outcome is RegisteredTap;
    Widget popup = Container(
      constraints: const BoxConstraints(maxWidth: 360),
      margin: const EdgeInsets.all(24),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(32),
        clipBehavior: Clip.antiAlias,
        elevation: 12,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (registered)
                SizedBox(height: 170, child: Center(child: art))
              else
                Padding(padding: const EdgeInsets.only(top: 8), child: art),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  body,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
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

    if (still) return popup;
    return popup
        .animate()
        .fadeIn(duration: 180.ms)
        .scale(
          begin: const Offset(0.82, 0.82),
          duration: 550.ms,
          curve: Curves.elasticOut,
        );
  }
}
