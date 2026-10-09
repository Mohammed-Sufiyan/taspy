import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme.dart';
import '../../../shared/format.dart';
import '../../../shared/motion.dart';
import '../../../shared/widgets/glow_background.dart';
import '../../../shared/widgets/pop_button.dart';
import '../../../shared/widgets/tapsy_mark.dart';
import '../../nfc/data/nfc_platform.dart';
import '../../nfc/domain/nfc_models.dart';
import '../../security/security_controller.dart';
import '../../settings/settings_screen.dart';
import '../../tap/tap_app.dart';
import '../domain/registered_card.dart';
import '../domain/tap_resolver.dart';
import 'add_card_screen.dart';
import 'card_details_screen.dart';
import 'card_face.dart';
import 'cards_controller.dart';
import 'wallet_stack.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.platform,
    required this.cards,
    required this.security,
  });

  final NfcPlatform platform;
  final CardsController cards;
  final SecurityController security;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppLifecycleListener _lifecycle;
  final _stackKey = GlobalKey<WalletStackState>();
  NfcStatus? _status;
  Color _glow = TapsyColors.lime;
  bool _introPlayed = false;

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

  /// NFC may have been toggled, and the tap popup may have recorded taps.
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
    _stackKey.currentState?.deselect();
    final added = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AddCardScreen(
          platform: widget.platform,
          cards: widget.cards,
          security: widget.security,
        ),
      ),
    );
    if (added != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$added" is ready. Give it a tap!')),
      );
    }
  }

  Future<void> _open(RegisteredCard card) async {
    final deleted = await Navigator.of(context).push<RegisteredCard>(
      MaterialPageRoute(
        builder: (_) => CardDetailsScreen(
          cards: widget.cards,
          cardId: card.id,
          platform: widget.platform,
          security: widget.security,
        ),
      ),
    );
    if (deleted == null || !mounted) return;
    _stackKey.currentState?.deselect();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('"${deleted.name}" deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.cards.restore(deleted),
          ),
        ),
      );
  }

  void _preview(RegisteredCard card) {
    Haptics.celebrate();
    widget.platform.playTapSound();
    showTapPopupPreview(
      context,
      RegisteredTap(card),
      onVerify: () => widget.security.verify('Reveal your secret message'),
    );
  }

  Future<void> _toggle(RegisteredCard card) async {
    try {
      await widget.cards.setEnabled(card.id, !card.enabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noNfc = _status?.hardware == false;
    return GlowBackground(
      color: _glow,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: 20,
          title: Row(
            children: [
              const TapsyMark(size: 30, tile: true, animate: false),
              const SizedBox(width: 10),
              Text(
                'tapsy',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
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
                  builder: (_) => SettingsScreen(
                    platform: widget.platform,
                    security: widget.security,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: ListenableBuilder(
          listenable: widget.cards,
          builder: (context, _) => noNfc || widget.cards.cards.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 72),
                  child: PopButton(
                    label: 'ADD CARD',
                    icon: Icons.add_rounded,
                    onPressed: _addCard,
                  ),
                ),
        ),
        body: ListenableBuilder(
          listenable: widget.cards,
          builder: (context, _) {
            final c = widget.cards;
            final animate = !_introPlayed && !reduceMotion(context);
            if (!c.loading) _introPlayed = true;

            final children = <Widget>[
              if (_status case final s? when !s.hardware || !s.enabled)
                _NfcBanner(
                  status: s,
                  onOpenSettings: widget.platform.openSettings,
                ),
              if (c.loadError case final error?)
                _ErrorPanel(message: error)
              else if (c.loading && c.cards.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (c.cards.isEmpty)
                _EmptyState(onAdd: noNfc ? null : _addCard)
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Text(
                    'Your cards',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
                  child: Text(
                    c.cards.length > 1
                        ? '${c.cards.length} cards · tap one, or swipe the front card up'
                        : 'Tap your card to see more',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                WalletStack(
                  key: _stackKey,
                  cards: c.cards,
                  tapsOf: c.tapsOf,
                  onPreview: _preview,
                  onToggle: _toggle,
                  onOpen: _open,
                  onFocusChanged: (card) {
                    final color = card == null
                        ? TapsyColors.lime
                        : CardSkin.glowOf(card.style);
                    if (color != _glow) setState(() => _glow = color);
                  },
                ),
                const SizedBox(height: 28),
                _RecentTaps(cards: c.cards, taps: c.taps),
              ],
            ];

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              children: animate
                  ? children
                        .animate(interval: 80.ms)
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.08, curve: Curves.easeOutCubic)
                  : children,
            );
          },
        ),
      ),
    );
  }
}

class _RecentTaps extends StatelessWidget {
  const _RecentTaps({required this.cards, required this.taps});

  final List<RegisteredCard> cards;
  final List<TapEvent> taps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byId = {for (final c in cards) c.id: c};
    final recent = taps.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent taps', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: TapsyColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TapsyColors.outline),
            ),
            child: Row(
              children: [
                const Icon(Icons.contactless_outlined, color: TapsyColors.lime),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Tap a card on the back of your phone. Your taps show up here.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          )
        else
          for (final t in recent)
            if (byId[t.cardId] case final card?)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TapsyColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: TapsyColors.outline),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: CardFace(
                          name: '',
                          style: card.style,
                          compact: true,
                          shine: false,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card.name, style: theme.textTheme.titleSmall),
                            Text(
                              card.secret ? '🔒 Secret message' : card.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo(t.at),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: TapsyColors.lime,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }
}

class _NfcBanner extends StatelessWidget {
  const _NfcBanner({required this.status, required this.onOpenSettings});

  final NfcStatus status;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TapsyColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TapsyColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.portable_wifi_off, color: TapsyColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.hardware ? 'NFC is off' : 'This phone has no NFC',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  status.hardware
                      ? 'Card taps won’t be detected until NFC is on.'
                      : 'Cards cannot be registered or detected here.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (status.hardware)
            TextButton(onPressed: onOpenSettings, child: const Text('Turn on')),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: TapsyColors.danger.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text('Could not load your cards: $message'),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const fan = [1, 5, 0]; // Aurora, Sunset, Midnight
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        children: [
          SizedBox(
            height: 230,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < fan.length; i++)
                  Transform.translate(
                    offset: Offset((i - 1) * 26.0, (i - 1) * -18.0),
                    child: Transform.rotate(
                      angle: (i - 1) * 0.12,
                      child: SizedBox(
                        width: 220,
                        child: CardFace(
                          name: i == 2 ? 'Your card' : '',
                          style: fan[i],
                          shine: i == 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Tap. Pop. Done.', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(
            'Register a card you already own and pick a message. Tap the card '
            'on your phone and it pops up, even when Tapsy is closed.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: TapsyColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          PopButton(
            label: 'ADD YOUR FIRST CARD',
            icon: Icons.contactless_outlined,
            onPressed: onAdd,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 16,
                color: TapsyColors.textFaint,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Only the card ID is used. No payment data.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: TapsyColors.textFaint,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
