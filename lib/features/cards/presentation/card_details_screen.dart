import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../shared/motion.dart';
import '../../tap/tap_app.dart';
import '../domain/registered_card.dart';
import '../domain/tap_resolver.dart';
import 'card_face.dart';
import 'card_form.dart';
import 'cards_controller.dart';

class CardDetailsScreen extends StatefulWidget {
  const CardDetailsScreen({
    super.key,
    required this.cards,
    required this.cardId,
  });

  final CardsController cards;
  final String cardId;

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
        icon: const Icon(Icons.delete_outline),
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await widget.cards.delete(card.id);
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _previewPopup(RegisteredCard card) {
    Haptics.celebrate();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close preview',
      barrierColor: Colors.black54,
      pageBuilder: (context, _, _) => Center(
        child: TapPopup(
          outcome: RegisteredTap(card),
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
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
        final loc = MaterialLocalizations.of(context);
        String when(DateTime d) =>
            '${loc.formatMediumDate(d)}, ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';

        final sections = <Widget>[
          if (_editing) ...[
            Text('Card colour', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            PalettePicker(
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
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _editing = false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _saveEdit,
                  child: const Text('Save'),
                ),
              ],
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Message when tapped',
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(card.message, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _previewPopup(card),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Preview popup'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: Icon(
                card.enabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
              ),
              title: const Text('Show message when tapped'),
              subtitle: Text(
                card.enabled ? 'On' : 'Off: taps show "turned off" instead',
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
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.contactless_outlined),
                  title: const Text('Card type'),
                  subtitle: Text(card.category.title),
                ),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Registered'),
                  subtitle: Text(when(card.createdAt)),
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Last tapped'),
                  subtitle: Text(
                    card.lastTriggeredAt == null
                        ? 'Not yet'
                        : when(card.lastTriggeredAt!),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _delete(card),
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            label: Text(
              'Delete card',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(card.name),
            actions: [
              if (!_editing)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _busy ? null : () => _startEditing(card),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TiltOnDrag(
                  child: Hero(
                    tag: 'card-${card.id}',
                    child: CardFace(
                      name: _editing ? _name.text.trim() : card.name,
                      style: _editing ? _style : card.style,
                      enabled: card.enabled,
                    ),
                  ),
                ),
              ),
              if (reduceMotion(context))
                const SizedBox(height: 16)
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Text(
                    'Drag the card to tilt it',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (reduceMotion(context))
                ...sections
              else
                ...sections
                    .animate(interval: 50.ms, delay: 150.ms)
                    .fadeIn(duration: 300.ms)
                    .slideY(begin: 0.1, curve: Curves.easeOutCubic),
            ],
          ),
        );
      },
    );
  }
}
