import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../shared/format.dart';
import '../../../shared/motion.dart';
import '../../../shared/widgets/flip_card.dart';
import '../domain/registered_card.dart';
import 'card_face.dart';

/// Apple Wallet-style stack of cards.
///
/// * Collapsed: cards overlap, each showing its top strip; the front card is
///   fully visible. Swipe the front card up to shuffle it to the back.
/// * Tap a card: it rises to the top, the others drop into a pile below, and
///   an action panel appears. Tap the selected card to flip it over.
class WalletStack extends StatefulWidget {
  const WalletStack({
    super.key,
    required this.cards,
    required this.tapsOf,
    required this.onPreview,
    required this.onToggle,
    required this.onOpen,
    this.onFocusChanged,
  });

  final List<RegisteredCard> cards;
  final List<TapEvent> Function(String cardId) tapsOf;
  final ValueChanged<RegisteredCard> onPreview;
  final ValueChanged<RegisteredCard> onToggle;
  final ValueChanged<RegisteredCard> onOpen;

  /// Called with the card currently in focus (selected, or the front card).
  final ValueChanged<RegisteredCard?>? onFocusChanged;

  @override
  State<WalletStack> createState() => WalletStackState();
}

class WalletStackState extends State<WalletStack> {
  final List<String> _order = [];
  String? _selected;
  bool _flipped = false;
  double _drag = 0;
  bool _dragging = false;

  static const _panelHeight = 148.0;
  static const _pileStep = 14.0;

  bool get hasSelection => _selected != null;

  @override
  void initState() {
    super.initState();
    _syncOrder();
  }

  @override
  void didUpdateWidget(WalletStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOrder();
  }

  /// Keeps the user's shuffled order; new cards arrive at the front.
  void _syncOrder() {
    final ids = {for (final c in widget.cards) c.id};
    _order.removeWhere((id) => !ids.contains(id));
    for (final c in widget.cards) {
      if (!_order.contains(c.id)) _order.add(c.id);
    }
    if (_selected != null && !ids.contains(_selected)) _selected = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportFocus());
  }

  RegisteredCard _card(String id) => widget.cards.firstWhere((c) => c.id == id);

  void _reportFocus() {
    if (!mounted) return;
    final id = _selected ?? (_order.isEmpty ? null : _order.last);
    widget.onFocusChanged?.call(id == null ? null : _card(id));
  }

  void deselect() {
    if (_selected == null) return;
    setState(() {
      _selected = null;
      _flipped = false;
    });
    _reportFocus();
  }

  void _select(String id) {
    Haptics.detected();
    setState(() {
      _selected = id;
      _flipped = false;
    });
    _reportFocus();
  }

  void _shuffleFrontToBack() {
    if (_order.length < 2) return;
    Haptics.success();
    setState(() {
      final id = _order.removeLast();
      _order.insert(0, id);
    });
    _reportFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_order.isEmpty) return const SizedBox.shrink();
    final duration = reduceMotion(context) || _dragging
        ? Duration.zero
        : const Duration(milliseconds: 480);

    return PopScope(
      canPop: _selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) deselect();
      },
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final cardH = w / CardFace.aspectRatio;
          final n = _order.length;
          final peek = n > 6 ? 50.0 : 64.0;
          final selected = _selected;
          final pileTop = cardH + 20 + _panelHeight + 12;

          final height = selected == null
              ? (n - 1) * peek + cardH + 12
              : n == 1
              ? cardH + 20 + _panelHeight
              : pileTop + (n - 2) * _pileStep + cardH * 0.92 + 12;

          // Paint order: in selection mode the chosen card goes on top.
          final paintOrder = selected == null
              ? _order
              : [..._order.where((id) => id != selected), selected];
          final others = _order.where((id) => id != selected).toList();

          return AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final id in paintOrder)
                  _positioned(
                    id: id,
                    width: w,
                    cardH: cardH,
                    peek: peek,
                    pileTop: pileTop,
                    pileIndex: others.indexOf(id),
                    duration: duration,
                  ),
                if (selected != null)
                  Positioned(
                    key: const ValueKey('panel'),
                    top: cardH + 20,
                    left: 0,
                    right: 0,
                    height: _panelHeight,
                    child: _ActionPanel(
                      card: _card(selected),
                      taps: widget.tapsOf(selected),
                      onPreview: widget.onPreview,
                      onToggle: widget.onToggle,
                      onOpen: widget.onOpen,
                      onClose: deselect,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _positioned({
    required String id,
    required double width,
    required double cardH,
    required double peek,
    required double pileTop,
    required int pileIndex,
    required Duration duration,
  }) {
    final n = _order.length;
    final i = _order.indexOf(id);
    final card = _card(id);
    final isFront = i == n - 1;
    final selected = _selected;

    double top;
    double scale;
    if (selected == null) {
      top = i * peek + (isFront ? _drag : 0);
      scale = (1 - (n - 1 - i) * 0.025).clamp(0.88, 1.0);
    } else if (id == selected) {
      top = 0;
      scale = 1;
    } else {
      top = pileTop + pileIndex * _pileStep;
      scale = 0.92;
    }

    Widget face = CardFace(
      name: card.name,
      style: card.style,
      enabled: card.enabled,
      secret: card.secret,
      subtitle: card.lastTriggeredAt == null
          ? 'Not tapped yet'
          : 'Last tap ${timeAgo(card.lastTriggeredAt!)}',
    );

    if (id == selected) {
      face = GestureDetector(
        onTap: () {
          Haptics.detected();
          setState(() => _flipped = !_flipped);
        },
        child: FlipCard(
          flipped: _flipped,
          front: face,
          back: _CardBack(card: card, taps: widget.tapsOf(id)),
        ),
      );
    } else if (selected == null && isFront && n > 1) {
      face = GestureDetector(
        onTap: () => _select(id),
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: (d) =>
            setState(() => _drag = (_drag + d.delta.dy).clamp(-cardH, 40)),
        onVerticalDragEnd: (d) {
          final fling = (d.primaryVelocity ?? 0) < -600;
          final far = _drag < -70;
          setState(() {
            _dragging = false;
            _drag = 0;
          });
          if (fling || far) _shuffleFrontToBack();
        },
        child: face,
      );
    } else {
      face = GestureDetector(onTap: () => _select(id), child: face);
    }

    return AnimatedPositioned(
      key: ValueKey(id),
      duration: duration,
      curve: Curves.easeOutCubic,
      top: top,
      left: 0,
      right: 0,
      height: cardH,
      child: AnimatedScale(
        scale: scale,
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Hero(tag: 'card-$id', child: face),
      ),
    );
  }
}

/// Back of a card: tap statistics.
class _CardBack extends StatelessWidget {
  const _CardBack({required this.card, required this.taps});

  final RegisteredCard card;
  final List<TapEvent> taps;

  @override
  Widget build(BuildContext context) {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final thisWeek = taps.where((t) => t.at.isAfter(weekAgo)).length;
    final glow = CardSkin.glowOf(card.style);
    return AspectRatio(
      aspectRatio: CardFace.aspectRatio,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          Widget stat(String value, String label) => Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: w * 0.075,
                    fontWeight: FontWeight.w800,
                    color: TapsyColors.text,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: w * 0.036,
                    color: TapsyColors.textMuted,
                  ),
                ),
              ],
            ),
          );
          return Container(
            padding: EdgeInsets.all(w * 0.07),
            decoration: BoxDecoration(
              color: TapsyColors.surfaceHigh,
              borderRadius: BorderRadius.circular(w * 0.065),
              border: Border.all(color: glow.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        card.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: w * 0.05,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: glow,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.flip,
                      size: w * 0.06,
                      color: TapsyColors.textFaint,
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    stat('${taps.length}', 'total taps'),
                    stat('$thisWeek', 'this week'),
                    stat(
                      card.lastTriggeredAt == null
                          ? '—'
                          : timeAgo(card.lastTriggeredAt!),
                      'last tap',
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  card.secret ? '🔒 Secret message' : '“${card.message}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: w * 0.04,
                    color: TapsyColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.card,
    required this.taps,
    required this.onPreview,
    required this.onToggle,
    required this.onOpen,
    required this.onClose,
  });

  final RegisteredCard card;
  final List<TapEvent> taps;
  final ValueChanged<RegisteredCard> onPreview;
  final ValueChanged<RegisteredCard> onToggle;
  final ValueChanged<RegisteredCard> onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion(context) ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  taps.isEmpty
                      ? 'Tap the card to flip it'
                      : 'Tapped ${taps.length}× · tap card to flip',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Action(
                icon: Icons.play_arrow_rounded,
                label: 'Preview',
                onTap: () => onPreview(card),
              ),
              _Action(
                icon: card.enabled
                    ? Icons.pause_rounded
                    : Icons.play_circle_outline_rounded,
                label: card.enabled ? 'Pause' : 'Resume',
                onTap: () => onToggle(card),
              ),
              _Action(
                icon: Icons.tune_rounded,
                label: 'Edit',
                onTap: () => onOpen(card),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Haptics.detected();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: TapsyColors.surfaceHigh,
                  shape: BoxShape.circle,
                  border: Border.all(color: TapsyColors.outline),
                ),
                child: Icon(icon, color: TapsyColors.lime),
              ),
              const SizedBox(height: 6),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
