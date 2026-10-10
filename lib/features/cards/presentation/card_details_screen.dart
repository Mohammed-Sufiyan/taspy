import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme.dart';
import '../../../shared/format.dart';
import '../../../shared/motion.dart';
import '../../../shared/widgets/glow_background.dart';
import '../../../shared/widgets/pop_button.dart';
import '../../../shared/security/auth_service.dart';
import '../../actions/domain/card_action.dart';
import '../../actions/presentation/action_tile.dart';
import '../../actions/presentation/actions_editor.dart';
import '../../nfc/data/nfc_platform.dart';
import '../../security/security_controller.dart';
import '../../tap/tap_app.dart';
import '../domain/registered_card.dart';
import '../domain/streak.dart';
import '../domain/tap_resolver.dart';
import 'card_designer.dart';
import 'card_face.dart';
import 'card_form.dart';
import 'cards_controller.dart';

/// Pops with the deleted card (so the caller can offer Undo), or null.
class CardDetailsScreen extends StatefulWidget {
  const CardDetailsScreen({
    super.key,
    required this.cards,
    required this.cardId,
    required this.platform,
    required this.security,
  });

  final CardsController cards;
  final String cardId;
  final NfcPlatform platform;
  final SecurityController security;

  @override
  State<CardDetailsScreen> createState() => _CardDetailsScreenState();
}

class _CardDetailsScreenState extends State<CardDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _message = TextEditingController();
  int _style = 0;
  String _emoji = '';
  CardEffect _effect = CardEffect.shine;
  bool _secret = false;
  List<CardAction> _actions = const [];
  bool _editing = false;
  bool _busy = false;

  /// A secret card's message stays hidden on this screen until verified.
  bool _revealed = false;

  Future<bool> _ensureRevealed(RegisteredCard card) async {
    if (!card.secret || _revealed) return true;
    final result = await widget.security.verify('Reveal your secret message');
    if (!mounted) return false;
    if (result == AuthResult.success) {
      setState(() => _revealed = true);
      Haptics.success();
      return true;
    }
    Haptics.error();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == AuthResult.unavailable
              ? 'Set up a fingerprint or screen lock to view secret messages.'
              : 'Not verified.',
        ),
      ),
    );
    return false;
  }

  @override
  void initState() {
    super.initState();
    _name.addListener(
      () => setState(() {}),
    ); // Live card preview while editing.
  }

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startEditing(RegisteredCard card) async {
    // Editing shows the message, so a secret card must be verified first.
    if (!await _ensureRevealed(card)) return;
    _name.text = card.name;
    _message.text = card.message;
    _style = card.style;
    _emoji = card.emoji;
    _effect = card.effect;
    _secret = card.secret;
    _actions = card.actions;
    setState(() => _editing = true);
  }

  Future<void> _saveEdit() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await widget.cards.edit(
        widget.cardId,
        name: _name.text,
        message: _message.text,
        style: _style,
        secret: _secret,
        actions: _actions,
        emoji: _emoji,
        effect: _effect,
      );
      Haptics.success();
      if (mounted) setState(() => _editing = false);
    });
  }

  Future<void> _delete(RegisteredCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: TapsyColors.danger),
        title: Text('Delete "${card.name}"?'),
        content: const Text(
          'Tapping this card will no longer show your message. '
          'You can register it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: TapsyColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await widget.cards.delete(card.id);
      if (mounted) Navigator.of(context).pop(card);
    });
  }

  void _preview(RegisteredCard card) {
    Haptics.celebrate();
    widget.platform.playTapSound();
    showTapPopupPreview(
      context,
      RegisteredTap(card),
      onVerify: () => widget.security.verify('Reveal your secret message'),
      onRunAction: widget.platform.runAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.cards,
      builder: (context, _) {
        final card = widget.cards.byId(widget.cardId);
        if (card == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This card no longer exists.')),
          );
        }
        final theme = Theme.of(context);
        final taps = widget.cards.tapsOf(card.id);
        final now = DateTime.now();
        final weekAgo = now.subtract(const Duration(days: 7));
        final streak = card.streak.activeOn(now);
        final style = _editing ? _style : card.style;

        final sections = <Widget>[
          if (_editing) ...[
            CardDesigner(
              style: _style,
              emoji: _emoji,
              effect: _effect,
              enabled: !_busy,
              onStyle: (v) => setState(() => _style = v),
              onEmoji: (v) => setState(() => _emoji = v),
              onEffect: (v) => setState(() => _effect = v),
            ),
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: CardFormFields(
                name: _name,
                message: _message,
                enabled: !_busy,
                messageOptional: _actions.isNotEmpty,
              ),
            ),
            const SizedBox(height: 8),
            ActionsEditor(
              actions: _actions,
              platform: widget.platform,
              enabled: !_busy,
              onChanged: (v) => setState(() => _actions = v),
            ),
            const SizedBox(height: 12),
            SecretSwitch(
              value: _secret,
              enabled: !_busy,
              available: widget.security.available,
              onChanged: (v) => setState(() => _secret = v),
            ),
            const SizedBox(height: 16),
            PopButton(label: 'SAVE CHANGES', busy: _busy, onPressed: _saveEdit),
            const SizedBox(height: 12),
            PopButton.dark(
              label: 'CANCEL',
              onPressed: _busy ? null : () => setState(() => _editing = false),
            ),
          ] else ...[
            Row(
              children: [
                _Stat(
                  value: streak > 0 ? '🔥 $streak' : '0',
                  label: streak == 1 ? 'day streak' : 'days streak',
                ),
                const SizedBox(width: 10),
                _Stat(value: '${card.streak.best}', label: 'best streak'),
                const SizedBox(width: 10),
                _Stat(value: '${taps.length}', label: 'total taps'),
              ],
            ),
            const SizedBox(height: 10),
            _Panel(
              child: _WeekStrip(
                taps: taps,
                now: now,
                lastTap: card.lastTriggeredAt,
                thisWeek: taps.where((t) => t.at.isAfter(weekAgo)).length,
              ),
            ),
            const SizedBox(height: 16),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MESSAGE ON TAP',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: TapsyColors.textFaint,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (card.secret && !_revealed)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _ensureRevealed(card),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lock_rounded,
                              size: 18,
                              color: TapsyColors.lime,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '••••••••••  Tap to reveal',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            const Icon(
                              Icons.fingerprint_rounded,
                              color: TapsyColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (card.message.isNotEmpty)
                    Text(
                      card.message,
                      style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
                    )
                  else
                    Text(
                      'No message, just actions',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: TapsyColors.textFaint,
                      ),
                    ),
                  if (card.actions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'THEN',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: TapsyColors.textFaint,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (card.secret && !_revealed)
                      Text(
                        '${card.actions.length} hidden '
                        '${card.actions.length == 1 ? 'action' : 'actions'}',
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      for (final a in ActionRules.runOrder(card.actions))
                        ActionTile(action: a),
                  ],
                  const SizedBox(height: 16),
                  PopButton.dark(
                    label: 'TEST THIS CARD',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => _preview(card),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      card.actions.isEmpty
                          ? 'Shows the popup without tapping the card'
                          : 'Shows the popup and runs the actions for real',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: TapsyColors.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Panel(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: const Text('Active'),
                subtitle: Text(
                  card.enabled
                      ? 'Tapping runs this card'
                      : 'Paused: tapping shows “paused”',
                  style: theme.textTheme.bodySmall,
                ),
                value: card.enabled,
                onChanged: _busy
                    ? null
                    : (v) {
                        Haptics.detected();
                        _run(() => widget.cards.setEnabled(card.id, v));
                      },
              ),
            ),
            const SizedBox(height: 12),
            _Panel(
              child: Column(
                children: [
                  _InfoRow(label: 'Card type', value: card.category.title),
                  const Divider(height: 24),
                  _InfoRow(label: 'Registered', value: timeAgo(card.createdAt)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: _busy ? null : () => _delete(card),
                style: TextButton.styleFrom(
                  foregroundColor: TapsyColors.danger,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete card'),
              ),
            ),
          ],
        ];

        return GlowBackground(
          color: CardSkin.glowOf(style),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              actions: [
                if (!_editing)
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _busy ? null : () => _startEditing(card),
                  ),
                const SizedBox(width: 8),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                TiltOnDrag(
                  child: Hero(
                    tag: 'card-${card.id}',
                    child: CardFace(
                      name: _editing ? _name.text.trim() : card.name,
                      style: style,
                      enabled: card.enabled,
                      secret: _editing ? _secret : card.secret,
                      emoji: _editing ? _emoji : card.emoji,
                      effect: _editing ? _effect : card.effect,
                      streak: streak,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (reduceMotion(context))
                  ...sections
                else
                  ...sections
                      .animate(interval: 40.ms, delay: 120.ms)
                      .fadeIn(duration: 300.ms)
                      .slideY(begin: 0.1, curve: Curves.easeOutCubic),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: TapsyColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: TapsyColors.outline),
    ),
    child: child,
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: _Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: TapsyColors.lime,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// The last 7 days as dots (filled = tapped that day), today last.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.taps,
    required this.now,
    required this.lastTap,
    required this.thisWeek,
  });

  final List<TapEvent> taps;
  final DateTime now;
  final DateTime? lastTap;
  final int thisWeek;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tappedDays = {for (final t in taps) Streak.daysBetween(t.at, now)};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'LAST 7 DAYS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: TapsyColors.textFaint,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              lastTap == null
                  ? 'Not tapped yet'
                  : '$thisWeek this week · last ${timeAgo(lastTap!)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var ago = 6; ago >= 0; ago--)
              _DayDot(
                letter: _letters[now.subtract(Duration(days: ago)).weekday - 1],
                on: tappedDays.contains(ago),
                today: ago == 0,
                delay: Duration(milliseconds: (6 - ago) * 60),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.letter,
    required this.on,
    required this.today,
    required this.delay,
  });

  final String letter;
  final bool on;
  final bool today;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    Widget dot = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? TapsyColors.lime : TapsyColors.surfaceHigh,
        border: Border.all(
          color: today ? TapsyColors.lime : TapsyColors.outline,
          width: today ? 2 : 1,
        ),
      ),
      child: on
          ? const Icon(Icons.check_rounded, size: 18, color: TapsyColors.onLime)
          : null,
    );
    if (on && !reduceMotion(context)) {
      dot = dot
          .animate(delay: delay + 300.ms)
          .scaleXY(
            begin: 0.3,
            end: 1,
            duration: 450.ms,
            curve: Curves.elasticOut,
          );
    }
    return Column(
      children: [
        dot,
        const SizedBox(height: 6),
        Text(
          letter,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: today ? TapsyColors.lime : TapsyColors.textFaint,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const Spacer(),
      Text(value, style: Theme.of(context).textTheme.titleSmall),
    ],
  );
}
