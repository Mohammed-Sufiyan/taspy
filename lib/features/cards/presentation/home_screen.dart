import 'package:flutter/material.dart';

import '../../nfc/data/nfc_platform.dart';
import '../../nfc/domain/nfc_models.dart';
import '../../settings/settings_screen.dart';
import 'add_card_screen.dart';
import 'card_details_screen.dart';
import 'cards_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.platform, required this.cards});

  final NfcPlatform platform;
  final CardsController cards;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _lifecycle;
  NfcStatus? _status;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// NFC may have been toggled, and the tap popup may have updated a card.
  Future<void> _refresh() async {
    widget.cards.load();
    try {
      final status = await widget.platform.getStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // The banner simply stays hidden if status can't be read.
    }
  }

  Future<void> _addCard() async {
    final added = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            AddCardScreen(platform: widget.platform, cards: widget.cards),
      ),
    );
    if (added != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$added" registered')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC PIN App'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(platform: widget.platform),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _status?.hardware == false ? null : _addCard,
        icon: const Icon(Icons.add_card),
        label: const Text('Add card'),
      ),
      body: ListenableBuilder(
        listenable: widget.cards,
        builder: (context, _) {
          final c = widget.cards;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (_status case final s? when !s.hardware || !s.enabled) ...[
                _NfcBanner(
                  status: s,
                  onOpenSettings: widget.platform.openSettings,
                ),
                const SizedBox(height: 12),
              ],
              if (c.loadError case final error?)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('Could not load your cards'),
                    subtitle: Text(error),
                  ),
                )
              else if (c.loading && c.cards.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (c.cards.isEmpty)
                const _EmptyState()
              else ...[
                for (final card in c.cards)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.credit_card,
                        color: card.enabled
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).disabledColor,
                      ),
                      title: Text(card.name),
                      subtitle: Text(
                        card.enabled ? card.message : 'Turned off',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CardDetailsScreen(cards: c, cardId: card.id),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const _HowItWorks(),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NfcBanner extends StatelessWidget {
  const _NfcBanner({required this.status, required this.onOpenSettings});

  final NfcStatus status;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status.hardware ? 'NFC is off' : 'This phone has no NFC',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              status.hardware
                  ? 'Card taps will not be detected until NFC is turned on.'
                  : 'Cards cannot be registered or detected on this phone.',
            ),
            if (status.hardware) ...[
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: onOpenSettings,
                child: const Text('Open NFC settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.nfc, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('No cards yet', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Register a card, give it a message, and that message pops up '
            'whenever you tap the card on the back of your phone.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const _HowItWorks(),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How it works', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Works with the phone unlocked and NFC on, even when this app is '
              'closed. The app recognises a card by its ID only and never reads '
              'card numbers or other payment data. An ID can be copied, so '
              "don't use this to protect anything sensitive.",
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
