import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';

/// The Tapsy "Tap point" logo (card + ripples) drawn in code, so it can animate.
/// Geometry matches `tool/generate_icons.py` (140x140 design space).
class TapsyMark extends StatefulWidget {
  const TapsyMark({
    super.key,
    this.size = 96,
    this.animate = true,
    this.tile = false,
  });

  final double size;

  /// Ripples pulse outward and the card gently bobs.
  final bool animate;

  /// Draw the teal rounded-square background like the app icon.
  final bool tile;

  @override
  State<TapsyMark> createState() => _TapsyMarkState();
}

class _TapsyMarkState extends State<TapsyMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TapsyMark old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.animate && !reduceMotion(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run) _c.value = 0.35;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: TapsyMarkPainter(t: _c.value, tile: widget.tile),
          ),
        ),
      ),
    );
  }
}

class TapsyMarkPainter extends CustomPainter {
  TapsyMarkPainter({required this.t, this.tile = false});

  /// Animation phase 0..1.
  final double t;
  final bool tile;

  static const teal = Color(0xFF0E7C7B);
  static const amber = Color(0xFFF5B841);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 140;
    canvas.scale(k);
    final ink = tile ? Colors.white : teal;

    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 140, 140),
          const Radius.circular(34),
        ),
        Paint()..color = teal,
      );
    }

    // Three staggered ripples expanding from the tap point and fading out.
    const tap = Offset(98, 42);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final radius = 10 + p * 30;
      canvas.drawCircle(
        tap,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = ink.withValues(alpha: (1 - p) * 0.75),
      );
    }

    // The card bobs toward the tap point once per cycle.
    final bob = math.sin(t * 2 * math.pi) * 3;
    canvas.save();
    canvas.translate(bob * 0.6, -bob);
    canvas.translate(64, 84);
    canvas.rotate(-12 * math.pi / 180);
    canvas.translate(-64, -84);
    canvas.drawRRect(
      RRect.fromLTRBR(26, 60, 102, 108, const Radius.circular(8)),
      Paint()..color = tile ? Colors.white : teal,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(37, 72, 53, 84, const Radius.circular(2.5)),
      Paint()..color = amber,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(37, 93, 77, 98, const Radius.circular(2.5)),
      Paint()..color = (tile ? teal : Colors.white).withValues(alpha: 0.35),
    );
    canvas.restore();

    canvas.drawCircle(tap, 9, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(TapsyMarkPainter old) => old.t != t || old.tile != tile;
}
