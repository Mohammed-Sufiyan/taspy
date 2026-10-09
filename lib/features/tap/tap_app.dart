import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme.dart';
import '../../shared/motion.dart';
import '../../shared/security/auth_service.dart';
import '../../shared/widgets/effects.dart';
import '../../shared/widgets/pop_button.dart';
import '../cards/data/card_repository.dart';
import '../cards/domain/registered_card.dart';
import '../cards/domain/tap_resolver.dart';
import '../cards/presentation/card_face.dart';
import '../cards/presentation/cards_controller.dart';
import '../nfc/data/nfc_platform.dart';

/// Shown over other apps when a card is tapped (runs in `TapActivity`, a
/// transparent Android activity with its own Flutter engine).
class TapApp extends StatefulWidget {
  const TapApp({
    super.key,
    required this.platform,
    required this.repository,
    required this.auth,
  });

  final NfcPlatform platform;
  final CardRepository repository;
  final AuthService auth;

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
    if (outcome is RegisteredTap) {
      Haptics.celebrate();
      widget.platform.playTapSound();
      // No screenshots or screen recording while a secret could be shown.
      widget.platform.setSecure(outcome.card.secret).ignore();
    } else {
      Haptics.error();
    }
    setState(() {
      _outcome = outcome;
      _error = null;
      _tapCount++;
    });
    if (outcome is RegisteredTap) {
      // Best effort: the sheet still shows if this write fails.
      _cards.markTriggered(outcome.card.id).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.platform.close,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0x99000000)),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: TapSheet(
                  key: ValueKey(_tapCount),
                  outcome: _outcome,
                  error: _error,
                  onClose: widget.platform.close,
                  onOpenApp: widget.platform.openApp,
                  onVerify: () =>
                      widget.auth.authenticate('Reveal your secret message'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the tap sheet inside the app (the "Preview" action).
Future<void> showTapPopupPreview(
  BuildContext context,
  TapOutcome outcome, {
  Future<AuthResult> Function()? onVerify,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close preview',
    barrierColor: const Color(0x99000000),
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.bottomCenter,
      child: TapSheet(
        outcome: outcome,
        onClose: () => Navigator.of(context).pop(),
        onVerify: onVerify,
      ),
    ),
  );
}

/// Bottom sheet confirming a tap, in the style of a wallet "done" screen:
/// the card rises, a lime check pops, then the message. Swipe down to close.
class TapSheet extends StatefulWidget {
  const TapSheet({
    super.key,
    required this.outcome,
    required this.onClose,
    this.error,
    this.onOpenApp,
    this.onVerify,
  });

  final TapOutcome? outcome;
  final String? error;
  final VoidCallback onClose;
  final VoidCallback? onOpenApp;

  /// Biometric check used to reveal a secret card's message.
  final Future<AuthResult> Function()? onVerify;

  @override
  State<TapSheet> createState() => _TapSheetState();
}

class _TapSheetState extends State<TapSheet> {
  double _drag = 0;
  bool _revealed = false;
  bool _verifying = false;
  String? _verifyError;

  bool get _hidden =>
      !_revealed &&
      widget.outcome is RegisteredTap &&
      (widget.outcome! as RegisteredTap).card.secret;

  Future<void> _verify() async {
    final verify = widget.onVerify;
    if (verify == null || _verifying) return;
    setState(() {
      _verifying = true;
      _verifyError = null;
    });
    final result = await verify();
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _revealed = result == AuthResult.success;
      _verifyError = switch (result) {
        AuthResult.success => null,
        AuthResult.failed => 'Not verified. The message stays hidden.',
        AuthResult.unavailable =>
          'Set up a fingerprint or screen lock to reveal secret messages.',
      };
    });
    result == AuthResult.success ? Haptics.success() : Haptics.error();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final still = reduceMotion(context);
    final outcome = widget.outcome;

    final content = switch ((widget.error, outcome)) {
      (final String e, _) => _message(
        theme,
        icon: Icons.error_outline,
        color: TapsyColors.danger,
        title: 'Couldn’t check this card',
        body: e,
      ),
      (_, RegisteredTap(:final card)) => _registered(theme, card, still),
      (_, DisabledCardTap(:final card)) => _message(
        theme,
        icon: Icons.pause_circle_outline,
        color: TapsyColors.textMuted,
        title: '${card.name} is paused',
        body: 'Resume it in Tapsy to show its message again.',
      ),
      (_, UnknownCardTap()) => _message(
        theme,
        icon: Icons.question_mark_rounded,
        color: TapsyColors.warning,
        title: 'New card?',
        body: 'Tapsy doesn’t know this card yet. Add it to give it a message.',
        wobble: !still,
      ),
      (_, null) => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
    };

    final actions = switch (outcome) {
      RegisteredTap() when _hidden => [
        PopButton(
          label: 'VERIFY TO REVEAL',
          icon: Icons.fingerprint_rounded,
          busy: _verifying,
          onPressed: widget.onVerify == null ? null : _verify,
        ),
        const SizedBox(height: 12),
        PopButton.dark(label: 'CLOSE', onPressed: widget.onClose),
      ],
      RegisteredTap() => [PopButton(label: 'DONE', onPressed: widget.onClose)],
      null when widget.error == null => <Widget>[],
      _ => [
        if (widget.onOpenApp != null) ...[
          PopButton(
            label: outcome is UnknownCardTap ? 'ADD IT IN TAPSY' : 'OPEN TAPSY',
            onPressed: widget.onOpenApp,
          ),
          const SizedBox(height: 12),
        ],
        PopButton.dark(label: 'CLOSE', onPressed: widget.onClose),
      ],
    };

    // Material gives text its theme styles; the in-app preview has no
    // Scaffold above it (without this, text renders with debug underlines).
    Widget sheet = Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () {}, // Taps inside the sheet don't close it.
        onVerticalDragUpdate: (d) =>
            setState(() => _drag = (_drag + d.delta.dy).clamp(0, 400)),
        onVerticalDragEnd: (d) {
          if (_drag > 110 || (d.primaryVelocity ?? 0) > 700) {
            widget.onClose();
          } else {
            setState(() => _drag = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 520),
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              color: TapsyColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              border: Border(top: BorderSide(color: TapsyColors.outline)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: TapsyColors.outline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 20),
                content,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  ...actions,
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (still) return sheet;
    return sheet
        .animate()
        .slideY(begin: 1, duration: 420.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 150.ms);
  }

  Widget _registered(ThemeData theme, RegisteredCard card, bool still) {
    final glow = CardSkin.glowOf(card.style);
    Widget art = SizedBox(
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PulseRings(color: glow, size: 260, child: const SizedBox.shrink()),
          SizedBox(
            width: 230,
            child: CardFace(
              name: card.name,
              style: card.style,
              secret: card.secret,
            ),
          ),
          Positioned(
            right: 40,
            bottom: 6,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: TapsyColors.surface,
              ),
              padding: const EdgeInsets.all(4),
              child: const AnimatedCheck(color: TapsyColors.lime, size: 52),
            ),
          ),
        ],
      ),
    );
    if (!still) {
      art = art
          .animate()
          .slideY(begin: 0.35, duration: 600.ms, curve: Curves.easeOutBack)
          .fadeIn(duration: 250.ms);
    }
    final texts = [
      Text(
        card.name,
        style: theme.textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      if (_hidden)
        _SecretPlaceholder(error: _verifyError)
      else
        Text(
          card.message,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: TapsyColors.textMuted,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ).animate(key: ValueKey(_revealed)).fadeIn(duration: 350.ms),
    ];
    return Column(
      children: [
        art,
        const SizedBox(height: 16),
        if (still)
          ...texts
        else
          ...texts
              .animate(delay: 250.ms, interval: 60.ms)
              .fadeIn()
              .slideY(begin: 0.3),
      ],
    );
  }

  Widget _message(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    bool wobble = false,
  }) {
    Widget badge = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Icon(icon, size: 38, color: color),
    );
    if (wobble) {
      badge = badge
          .animate()
          .rotate(begin: -0.05, end: 0.05, duration: 110.ms)
          .then()
          .rotate(begin: 0.05, end: -0.03, duration: 110.ms)
          .then()
          .rotate(begin: -0.03, end: 0, duration: 140.ms);
    }
    return Column(
      children: [
        badge,
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: TapsyColors.textMuted,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Stand-in for a secret card's message until the user verifies.
class _SecretPlaceholder extends StatelessWidget {
  const _SecretPlaceholder({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: TapsyColors.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TapsyColors.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 18, color: TapsyColors.lime),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Secret message',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: TapsyColors.danger,
            ),
          ),
        ],
      ],
    );
  }
}
