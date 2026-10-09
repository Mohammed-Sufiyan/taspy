import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme.dart';
import '../../../shared/format.dart';
import '../../../shared/motion.dart';
import '../../../shared/widgets/glow_background.dart';
import '../../../shared/widgets/pop_button.dart';
import '../../nfc/data/nfc_platform.dart';
import '../../tap/tap_app.dart';
import '../domain/registered_card.dart';
import '../domain/tap_resolver.dart';
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
  });

  final CardsController cards;
  final String cardId;
  final NfcPlatform platform;

  @override
  State<CardDetailsScreen> createState() => _CardDetailsScreenState();
}

class _CardDetailsScreenState extends State<CardDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _message = TextEditingController();
  int _style = 0;
  bool _editing = false;
  bool _busy = false;

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

  void _startEditing(RegisteredCard card) {
    _name.text = card.name;
    _message.text = card.message;
    _style = card.style;
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
    showTapPopupPreview(context, RegisteredTap(card));
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
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        final style = _editing ? _style : card.style;

        final sections = <Widget>[
          if (_editing) ...[
            Text('Design', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            SkinPicker(
              value: _style,
              enabled: !_busy,
              onChanged: (v) => setState(() => _style = v),
            ),
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: CardFormFields(
                name: _name,
                message: _message,
                enabled: !_busy,
              ),
            ),
            const SizedBox(height: 12),
            PopButton(label: 'SAVE CHANGES', busy: _busy, onPressed: _saveEdit),
            const SizedBox(height: 12),
            PopButton.dark(
              label: 'CANCEL',
              onPressed: _busy ? null : () => setState(() => _editing = false),
            ),
          ] else ...[
            Row(
              children: [
                _Stat(value: '${taps.length}', label: 'total taps'),
                const SizedBox(width: 10),
                _Stat(
                  value: '${taps.where((t) => t.at.isAfter(weekAgo)).length}',
                  label: 'this week',
                ),
                const SizedBox(width: 10),
                _Stat(
                  value: card.lastTriggeredAt == null
                      ? '—'
                      : timeAgo(card.lastTriggeredAt!),
                  label: 'last tap',
                ),
              ],
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
                  Text(
                    card.message,
                    style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  PopButton.dark(
                    label: 'PREVIEW TAP',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => _preview(card),
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
                      ? 'Tapping shows your message'
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
