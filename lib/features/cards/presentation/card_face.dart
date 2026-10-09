import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../shared/motion.dart';

class CardPalette {
  const CardPalette(this.name, this.start, this.end);

  final String name;
  final Color start;
  final Color end;

  static const all = [
    CardPalette('Teal', Color(0xFF0E7C7B), Color(0xFF2DD4BF)),
    CardPalette('Ocean', Color(0xFF1D4ED8), Color(0xFF38BDF8)),
    CardPalette('Grape', Color(0xFF6D28D9), Color(0xFFC084FC)),
    CardPalette('Sunset', Color(0xFFEA580C), Color(0xFFFBBF24)),
    CardPalette('Rose', Color(0xFFBE185D), Color(0xFFFB7185)),
    CardPalette('Night', Color(0xFF111827), Color(0xFF4B5563)),
  ];

  static CardPalette of(int style) => all[style % all.length];
}

/// A registered card drawn like a real payment card.
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.name,
    required this.style,
    this.enabled = true,
    this.subtitle,
  });

  final String name;
  final int style;
  final bool enabled;
  final String? subtitle;

  static const aspectRatio = 1.586; // ISO/IEC 7810 ID-1

  @override
  Widget build(BuildContext context) {
    final palette = CardPalette.of(style);
    final face = AspectRatio(
      aspectRatio: aspectRatio,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.06),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.start, palette.end],
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.start.withValues(alpha: 0.35),
                  blurRadius: w * 0.08,
                  offset: Offset(0, w * 0.03),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(w * 0.06),
              child: Stack(
                children: [
                  // Soft decorative circles for depth.
                  Positioned(
                    right: -w * 0.18,
                    top: -w * 0.22,
                    child: _Blob(size: w * 0.7),
                  ),
                  Positioned(
                    left: -w * 0.25,
                    bottom: -w * 0.35,
                    child: _Blob(size: w * 0.6),
                  ),
                  Padding(
                    padding: EdgeInsets.all(w * 0.07),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'tapsy',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w800,
                                fontSize: w * 0.06,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.contactless_outlined,
                              color: Colors.white,
                              size: w * 0.1,
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          width: w * 0.13,
                          height: w * 0.1,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5B841),
                            borderRadius: BorderRadius.circular(w * 0.018),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          name.isEmpty ? 'Your card' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: w * 0.075,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: w * 0.045,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (enabled) return face;
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.33, 0.33, 0.33, 0, 0, //
            0.33, 0.33, 0.33, 0, 0, //
            0.33, 0.33, 0.33, 0, 0, //
            0, 0, 0, 0.55, 0, //
          ]),
          child: face,
        ),
        const Positioned(
          right: 12,
          bottom: 12,
          child: Chip(
            label: Text('Off'),
            avatar: Icon(Icons.pause_circle_outline, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: 0.09),
    ),
  );
}

/// Tilts its child in 3D as the user drags across it, then springs back.
class TiltOnDrag extends StatefulWidget {
  const TiltOnDrag({super.key, required this.child});

  final Widget child;

  @override
  State<TiltOnDrag> createState() => _TiltOnDragState();
}

class _TiltOnDragState extends State<TiltOnDrag>
    with SingleTickerProviderStateMixin {
  // Created eagerly: a lazy controller first touched in dispose() would look
  // up TickerMode on an already-deactivated element.
  late final AnimationController _spring;
  Offset _tilt = Offset.zero;
  Offset _from = Offset.zero;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _update(Offset local, Size size) {
    final dx = (local.dx / size.width - 0.5).clamp(-0.5, 0.5);
    final dy = (local.dy / size.height - 0.5).clamp(-0.5, 0.5);
    setState(() => _tilt = Offset(dx, dy));
  }

  void _release() {
    _from = _tilt;
    _spring
      ..value = 1
      ..animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 180, damping: 9),
          1,
          0,
          0,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxWidth / CardFace.aspectRatio);
        return GestureDetector(
          onPanStart: (d) {
            _spring.stop();
            _update(d.localPosition, size);
          },
          onPanUpdate: (d) => _update(d.localPosition, size),
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: AnimatedBuilder(
            animation: _spring,
            builder: (context, child) {
              final t = _spring.isAnimating ? _from * _spring.value : _tilt;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(-t.dy * 0.5)
                  ..rotateY(t.dx * 0.5),
                child: child,
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Row of colour dots for picking a card style.
class PalettePicker extends StatelessWidget {
  const PalettePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var i = 0; i < CardPalette.all.length; i++)
          Semantics(
            button: true,
            selected: i == value,
            label: '${CardPalette.all[i].name} card colour',
            child: GestureDetector(
              key: ValueKey('palette-$i'),
              onTap: enabled
                  ? () {
                      Haptics.detected();
                      onChanged(i);
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                width: 44,
                height: 44,
                padding: EdgeInsets.all(i == value ? 4 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i == value
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        CardPalette.all[i].start,
                        CardPalette.all[i].end,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
