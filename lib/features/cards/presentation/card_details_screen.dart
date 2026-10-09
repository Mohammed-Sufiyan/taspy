import 'package:flutter/material.dart';

import '../domain/registered_card.dart';
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
  bool _editing = false;
  bool _busy = false;

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
    setState(() => _editing = true);
  }

  Future<void> _saveEdit() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await widget.cards.edit(
        widget.cardId,
        name: _name.text,
        message: _message.text,
      );
      if (mounted) setState(() => _editing = false);
    });
  }

  Future<void> _delete(RegisteredCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            padding: const EdgeInsets.all(16),
            children: [
              if (_editing) ...[
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
              ] else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Message', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text(card.message, style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: const Text('Show message when tapped'),
                  subtitle: Text(
                    card.enabled
                        ? 'On'
                        : 'Off: tapping this card shows "turned off" instead',
                  ),
                  value: card.enabled,
                  onChanged: _busy
                      ? null
                      : (v) => _run(() => widget.cards.setEnabled(card.id, v)),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Card type'),
                      subtitle: Text(card.category.title),
                    ),
                    ListTile(
                      title: const Text('Action'),
                      subtitle: const Text('Show a popup with the message'),
                    ),
                    ListTile(
                      title: const Text('Registered'),
                      subtitle: Text(when(card.createdAt)),
                    ),
                    ListTile(
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
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                label: Text(
                  'Delete card',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
