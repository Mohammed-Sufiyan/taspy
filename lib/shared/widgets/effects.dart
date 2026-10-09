import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';

/// Rings pulsing out from behind [child] (e.g. "listening for a card").
class PulseRings extends StatefulWidget {
  const PulseRings({
    super.key,
    required this.child,
    required this.color,
    this.size = 200,
    this.active = true,
  });

  final Widget child;
  final Color color;
  final double size;
  final bool active;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulseRings old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && !reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.active)
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => CustomPaint(
                    painter: _RingsPainter(_c.value, widget.color),
                  ),
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      canvas.drawCircle(
        center,
        maxR * (0.35 + 0.65 * p),
        Paint()..color = color.withValues(alpha: (1 - p) * 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}

/// A circle that pops in and a checkmark that draws itself.
class AnimatedCheck extends StatelessWidget {
  const AnimatedCheck({super.key, required this.color, this.size = 72});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final instant = reduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: instant ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 650),
      builder: (_, t, _) => CustomPaint(
        size: Size.square(size),
        painter: _CheckPainter(t, color),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final circle = Curves.elasticOut.transform((t / 0.55).clamp(0, 1));
    canvas.drawCircle(
      Offset(s / 2, s / 2),
      s / 2 * circle,
      Paint()..color = color,
    );
    final draw = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
    if (draw == 0) return;
    final path = Path()
      ..moveTo(s * 0.28, s * 0.52)
      ..lineTo(s * 0.44, s * 0.67)
      ..lineTo(s * 0.73, s * 0.37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * Curves.easeOut.transform(draw)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}

/// One-shot confetti burst from the centre of its area. Draws nothing when
/// the user has reduced motion.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.particles = 70});

  final int particles;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final List<_Piece> _pieces;

  static const _colors = [
    Color(0xFF14B8A6),
    Color(0xFFF5B841),
    Color(0xFFFB7185),
    Color(0xFF818CF8),
    Color(0xFF38BDF8),
  ];

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    _pieces = List.generate(widget.particles, (_) {
      final angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.4;
      return _Piece(
        velocity: Offset.fromDirection(angle, 380 + r.nextDouble() * 520),
        color: _colors[r.nextInt(_colors.length)],
        spin: (r.nextDouble() - 0.5) * 18,
        size: 6 + r.nextDouble() * 6,
        round: r.nextBool(),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_c.value, _pieces),
          ),
        ),
      ),
    );
  }
}

class _Piece {
  _Piece({
    required this.velocity,
    required this.color,
    required this.spin,
    required this.size,
    required this.round,
  });

  final Offset velocity;
  final Color color;
  final double spin;
  final double size;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.pieces);

  final double t;
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0 || t == 1) return;
    final origin = Offset(size.width / 2, size.height * 0.42);
    final seconds = t * 1.6;
    const gravity = 900.0;
    for (final p in pieces) {
      final pos =
          origin +
          p.velocity * seconds * (1 - t * 0.35) +
          Offset(0, 0.5 * gravity * seconds * seconds);
      final paint = Paint()
        ..color = p.color.withValues(alpha: (1 - t).clamp(0, 1));
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * seconds);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.5,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
