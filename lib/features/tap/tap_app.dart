import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme.dart';
import '../../shared/motion.dart';
import '../../shared/security/auth_service.dart';
import '../../shared/widgets/effects.dart';
import '../../shared/widgets/pop_button.dart';
import '../actions/domain/card_action.dart';
import '../actions/presentation/action_tile.dart';
import '../cards/data/card_repository.dart';
import '../cards/domain/registered_card.dart';
import '../cards/domain/streak.dart';
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
  bool _milestone = false;

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
    var outcome = resolveTap(event.reading, _cards.cards);
    var milestone = false;
    if (outcome is RegisteredTap) {
      // Show the streak including this tap (it is saved just below).
      final card = outcome.card;
      final next = card.streak.tap(DateTime.now());
      milestone =
          next.current != card.streak.current &&
          Streak.milestones.contains(next.current);
      outcome = RegisteredTap(card.copyWith(streak: next));
    }
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
      _milestone = milestone;
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
              if (_outcome case final outcome?)
                Positioned.fill(
                  child: TapRipple(
                    key: ValueKey('ripple-$_tapCount'),
                    color: _rippleColor(outcome),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: TapSheet(
                  key: ValueKey(_tapCount),
                  outcome: _outcome,
                  error: _error,
                  milestone: _milestone,
                  onClose: widget.platform.close,
                  onOpenApp: widget.platform.openApp,
                  onVerify: () =>
                      widget.auth.authenticate('Reveal your secret message'),
                  onRunAction: widget.platform.runAction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _rippleColor(TapOutcome outcome) => switch (outcome) {
  RegisteredTap(:final card) => CardSkin.glowOf(card.style),
  DisabledCardTap() => TapsyColors.textMuted,
  UnknownCardTap() => TapsyColors.warning,
};

/// Shows the tap sheet inside the app ("Test this card"). Actions run for
/// real, but the tap isn't recorded.
Future<void> showTapPopupPreview(
  BuildContext context,
  TapOutcome outcome, {
  Future<AuthResult> Function()? onVerify,
  Future<ActionResult> Function(CardAction)? onRunAction,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close preview',
    barrierColor: const Color(0x99000000),
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(child: TapRipple(color: _rippleColor(outcome))),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: TapSheet(
            outcome: outcome,
            onClose: () => Navigator.of(context).pop(),
            onVerify: onVerify,
            onRunAction: onRunAction,
          ),
        ),
      ],
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
    this.onRunAction,
    this.milestone = false,
    this.now,
  });

  final TapOutcome? outcome;
  final String? error;
  final VoidCallback onClose;
  final VoidCallback? onOpenApp;

  /// Biometric check used to reveal a secret card's message.
  final Future<AuthResult> Function()? onVerify;

  /// Runs the card's actions; without it they are listed but not run.
  final Future<ActionResult> Function(CardAction)? onRunAction;

  /// This tap reached a streak milestone: celebrate.
  final bool milestone;

  /// Time used to pick the actions that run now (defaults to the clock).
  final DateTime? now;

  /// Pause before an action that opens another app, so the popup can be
  /// read (and the opening cancelled).
  static const openDelay = Duration(milliseconds: 1800);

  @override
  State<TapSheet> createState() => _TapSheetState();
}

class _TapSheetState extends State<TapSheet> {
  double _drag = 0;
  bool _revealed = false;
  bool _verifying = false;
  String? _verifyError;

  late final DateTime _now = widget.now ?? DateTime.now();

  /// The tapped card's actions that run at this time, in run order, and how
  /// each one went.
  late final List<CardAction> _actions = switch (widget.outcome) {
    RegisteredTap(:final card) => ActionRules.runOrder(
      ActionRules.activeAt(card.actions, _now),
    ),
    _ => const [],
  };

  /// Actions of this card set for other times of day.
  late final int _later = switch (widget.outcome) {
    RegisteredTap(:final card) => card.actions.length - _actions.length,
    _ => 0,
  };
  final Map<int, _Run> _runs = {};
  Timer? _openTimer;
  bool _started = false;

  int get _openerIndex => _actions.isNotEmpty && _actions.last.type.opensApp
      ? _actions.length - 1
      : -1;

  bool get _openPending =>
      _openerIndex >= 0 && _runs[_openerIndex]?.state == _RunState.waiting;

  @override
  void initState() {
    super.initState();
    // After the first frame: setState is not allowed while mounting.
    if (!_hidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startActions();
      });
    }
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    super.dispose();
  }

  Future<void> _startActions() async {
    final run = widget.onRunAction;
    if (_started || run == null || _actions.isEmpty) return;
    _started = true;
    for (var i = 0; i < _actions.length; i++) {
      if (i == _openerIndex) break;
      setState(() => _runs[i] = const _Run(_RunState.running));
      final result = await run(_actions[i]);
      if (!mounted) return;
      result.ok ? Haptics.detected() : Haptics.error();
      setState(() => _runs[i] = _Run.of(result));
    }
    if (_openerIndex >= 0) {
      setState(() => _runs[_openerIndex] = const _Run(_RunState.waiting));
      _openTimer = Timer(TapSheet.openDelay, _openNow);
    }
  }

  Future<void> _openNow() async {
    _openTimer?.cancel();
    final i = _openerIndex;
    if (i < 0 || _runs[i]?.state != _RunState.waiting) return;
    setState(() => _runs[i] = const _Run(_RunState.running));
    final result = await widget.onRunAction!(_actions[i]);
    if (!mounted) return;
    if (result.ok) {
      // The other app is in front now; the popup has done its job.
      widget.onClose();
    } else {
      Haptics.error();
      setState(() => _runs[i] = _Run.of(result));
    }
  }

  void _cancelOpen() {
    _openTimer?.cancel();
    setState(() => _runs[_openerIndex] = const _Run(_RunState.cancelled));
  }

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
    if (result == AuthResult.success) {
      Haptics.success();
      _startActions();
    } else {
      Haptics.error();
    }
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
      RegisteredTap() when _openPending => [
        PopButton(
          label: 'OPEN NOW',
          icon: Icons.open_in_new_rounded,
          onPressed: _openNow,
        ),
        const SizedBox(height: 12),
        PopButton.dark(label: 'CANCEL', onPressed: _cancelOpen),
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
    final streak = card.streak.activeOn(_now);
    Widget face = SizedBox(
      width: 230,
      child: CardFace.of(card, streak: streak),
    );
    if (!still) {
      // The card flies in from where it touched the phone, turning over.
      face = face
          .animate()
          .moveY(
            begin: -260,
            end: 0,
            duration: 650.ms,
            curve: Curves.easeOutCubic,
          )
          .flipH(
            begin: -0.35,
            end: 0,
            duration: 750.ms,
            curve: Curves.easeOutBack,
          )
          .scaleXY(
            begin: 0.55,
            end: 1,
            duration: 650.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 200.ms);
    }
    Widget art = SizedBox(
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          PulseRings(color: glow, size: 260, child: const SizedBox.shrink()),
          face,
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
    final texts = [
      Text(
        card.name,
        style: theme.textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
      if (streak > 0) ...[
        const SizedBox(height: 8),
        _StreakChip(days: streak, milestone: widget.milestone, still: still),
      ],
      const SizedBox(height: 8),
      if (_hidden)
        _SecretPlaceholder(error: _verifyError)
      else if (card.message.isNotEmpty)
        Text(
          card.message,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: TapsyColors.textMuted,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ).animate(key: ValueKey(_revealed)).fadeIn(duration: 350.ms),
      if (!_hidden && _actions.isNotEmpty) ...[
        const SizedBox(height: 12),
        _actionList(),
      ],
      if (!_hidden && _later > 0) ...[
        const SizedBox(height: 8),
        Text(
          '$_later more ${_later == 1 ? 'action runs' : 'actions run'} '
          'at other times',
          style: theme.textTheme.bodySmall?.copyWith(
            color: TapsyColors.textFaint,
          ),
        ),
      ],
    ];
    final column = Column(
      children: [
        art,
        const SizedBox(height: 16),
        if (still)
          ...texts
        else
          ...texts
              .animate(delay: 350.ms, interval: 60.ms)
              .fadeIn()
              .slideY(begin: 0.3),
      ],
    );
    if (!widget.milestone || still) return column;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        column,
        const Positioned.fill(child: ConfettiBurst(particles: 90)),
      ],
    );
  }

  Widget _actionList() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TapsyColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TapsyColors.outline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _actions.length; i++)
            _runTile(_actions[i], _runs[i]),
        ],
      ),
    );
  }

  Widget _runTile(CardAction action, _Run? run) {
    final failed = run?.state == _RunState.failed;
    return ActionTile(
      action: action,
      detail: switch (run) {
        null when widget.onRunAction == null => 'Runs when you tap the card',
        _Run(state: _RunState.waiting) => 'Opening…',
        _Run(state: _RunState.cancelled) => 'Cancelled',
        _Run(state: _RunState.failed, :final result) => _failure(
          action,
          result,
        ),
        _Run(result: ActionResult.on) => 'Now on',
        _Run(result: ActionResult.off) => 'Now off',
        _Run(state: _RunState.done) when action.type == ActionType.copyText =>
          'Copied',
        _Run(state: _RunState.done) when action.type == ActionType.timer =>
          'Timer started',
        _ => null,
      },
      detailColor: failed ? TapsyColors.danger : null,
      trailing: SizedBox.square(
        dimension: 26,
        child: switch (run?.state) {
          null => const SizedBox.shrink(),
          _RunState.running => const Padding(
            padding: EdgeInsets.all(4),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          _RunState.waiting => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: TapSheet.openDelay,
            builder: (_, v, _) => Padding(
              padding: const EdgeInsets.all(3),
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: 2.5,
                backgroundColor: TapsyColors.outline,
              ),
            ),
          ),
          _RunState.done =>
            const Icon(
              Icons.check_circle_rounded,
              color: TapsyColors.lime,
            ).animate().scaleXY(
              begin: 0.2,
              end: 1,
              duration: 500.ms,
              curve: Curves.elasticOut,
            ),
          _RunState.failed => const Icon(
            Icons.error_rounded,
            color: TapsyColors.danger,
          ),
          _RunState.cancelled => const Icon(
            Icons.remove_circle_outline_rounded,
            color: TapsyColors.textFaint,
          ),
        },
      ),
    );
  }

  static String _failure(CardAction action, ActionResult? result) =>
      switch (result) {
        ActionResult.notFound when action.type == ActionType.openApp =>
          'App not installed',
        ActionResult.notFound => 'No app on this phone can open this',
        ActionResult.unsupported => 'No flashlight on this phone',
        ActionResult.busy => 'Flashlight is in use by another app',
        ActionResult.blocked => 'Blocked for safety',
        _ => 'Didn’t work',
      };

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

/// "🔥 5-day streak", bigger and bouncing on a milestone.
class _StreakChip extends StatelessWidget {
  const _StreakChip({
    required this.days,
    required this.milestone,
    required this.still,
  });

  final int days;
  final bool milestone;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final text = milestone
        ? '🎉 $days-day streak!'
        : days == 1
        ? '🔥 Streak started'
        : '🔥 $days-day streak';
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(
          0xFFFF8A3D,
        ).withValues(alpha: milestone ? 0.25 : 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF8A3D).withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: const Color(0xFFFFB27A),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (milestone && !still) {
      chip = chip
          .animate(delay: 500.ms)
          .scaleXY(
            begin: 0.4,
            end: 1,
            duration: 700.ms,
            curve: Curves.elasticOut,
          )
          .then(delay: 200.ms)
          .shimmer(duration: 900.ms, color: Colors.white54);
    }
    return chip;
  }
}

enum _RunState { running, waiting, done, failed, cancelled }

class _Run {
  const _Run(this.state, [this.result]);

  factory _Run.of(ActionResult result) =>
      _Run(result.ok ? _RunState.done : _RunState.failed, result);

  final _RunState state;
  final ActionResult? result;
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
