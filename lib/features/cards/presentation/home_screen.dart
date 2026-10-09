import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../shared/motion.dart';
import '../../../shared/widgets/tapsy_mark.dart';
import '../../nfc/data/nfc_platform.dart';
import '../../nfc/domain/nfc_models.dart';
import '../../settings/settings_screen.dart';
import '../domain/registered_card.dart';
import 'add_card_screen.dart';
import 'card_details_screen.dart';
import 'card_face.dart';
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

  /// Animate the list only on first appearance, not on every rebuild.
  bool _introPlayed = false;

  /// Cards swiped away but possibly still being deleted from storage. A
  /// dismissed Dismissible must leave the tree immediately.
  final _hidden = <String>{};

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$added" is ready. Give it a tap!')),
      );
    }
  }

  Future<void> _delete(RegisteredCard card) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hidden.add(card.id));
    try {
      await widget.cards.delete(card.id);
    } catch (e) {
      if (mounted) setState(() => _hidden.remove(card.id));
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    _hidden.remove(card.id);
    Haptics.success();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('"${card.name}" deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.cards.restore(card),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const TapsyMark(size: 32, tile: true, animate: false),
            const SizedBox(width: 10),
            Text(
              'Tapsy',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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
      floatingActionButton: _status?.hardware == false
          ? null
          : FloatingActionButton.extended(
              onPressed: _addCard,
              icon: const Icon(Icons.add_card),
              label: const Text('Add card'),
            ).animate().scale(
              delay: 300.ms,
              duration: 500.ms,
              curve: Curves.elasticOut,
            ),
      body: ListenableBuilder(
        listenable: widget.cards,
        builder: (context, _) {
          final c = widget.cards;
          final cards = c.cards.where((x) => !_hidden.contains(x.id)).toList();
          final animate = !_introPlayed && !reduceMotion(context);
          if (!c.loading) _introPlayed = true;

          final children = <Widget>[
            if (_status case final s? when !s.hardware || !s.enabled)
              _NfcBanner(
                status: s,
                onOpenSettings: widget.platform.openSettings,
              ),
            if (c.loadError case final error?)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Could not load your cards'),
                  subtitle: Text(error),
                ),
              )
            else if (c.loading && cards.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (cards.isEmpty)
              _EmptyState(onAdd: _status?.hardware == false ? null : _addCard)
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text(
                  cards.length == 1
                      ? '1 card · swipe left to delete'
                      : '${cards.length} cards · swipe left to delete',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final card in cards)
                _CardTile(
                  key: ValueKey(card.id),
                  card: card,
                  onDelete: () => _delete(card),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CardDetailsScreen(cards: c, cardId: card.id),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const _HowItWorks(),
            ],
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
            children: animate
                ? children
                      .animate(interval: 70.ms)
                      .fadeIn(duration: 350.ms)
                      .slideY(begin: 0.12, curve: Curves.easeOutCubic)
                : children,
          );
        },
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    super.key,
    required this.card,
    required this.onOpen,
    required this.onDelete,
  });

  final RegisteredCard card;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = MaterialLocalizations.of(context);
    final last = card.lastTriggeredAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Dismissible(
        key: ValueKey('dismiss-${card.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 28),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
        ),
        child: _Pressable(
          onTap: onOpen,
          child: Hero(
            tag: 'card-${card.id}',
            child: CardFace(
              name: card.name,
              style: card.style,
              enabled: card.enabled,
              subtitle: last == null
                  ? 'Not tapped yet'
                  : 'Last tapped ${loc.formatShortDate(last)}',
            ),
          ),
        ),
      ),
    );
  }
}

/// Shrinks slightly while pressed, for a tactile feel.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
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
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.portable_wifi_off, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.hardware ? 'NFC is off' : 'This phone has no NFC',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    status.hardware
                        ? 'Card taps will not be detected until NFC is on.'
                        : 'Cards cannot be registered or detected here.',
                  ),
                ],
              ),
            ),
            if (status.hardware)
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('Turn on'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const TapsyMark(size: 150),
          const SizedBox(height: 20),
          Text(
            'Tap. Pop. Done.',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Register a card you already own and pick a message. Tap the card '
            'on your phone and the message pops up, even when Tapsy is closed.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.contactless_outlined),
            label: const Text('Add your first card'),
          ),
          const SizedBox(height: 28),
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
    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(
              Icons.lock_open_outlined,
              'Works with the phone unlocked and NFC on, even if Tapsy is closed.',
            ),
            row(
              Icons.shield_outlined,
              'Only the card ID is used. Card numbers and payment data are never read.',
            ),
            row(
              Icons.info_outline,
              "An ID can be copied, so don't use Tapsy to protect anything sensitive.",
            ),
          ],
        ),
      ),
    );
  }
}
