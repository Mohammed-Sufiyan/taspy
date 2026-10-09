import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/motion.dart';
import 'card_face.dart';

/// Looping illustration of a card sliding onto the back of a phone, with
/// ripples bursting at the moment of contact.
class ScanAnimation extends StatefulWidget {
  const ScanAnimation({super.key, this.style = 0, this.height = 200});

  final int style;
  final double height;

  @override
  State<ScanAnimation> createState() => _ScanAnimationState();
}

class _ScanAnimationState extends State<ScanAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 0.45; // Static frame: card resting on the phone.
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = CardPalette.of(widget.style);
    return SizedBox(
      height: widget.height,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            size: Size.infinite,
            painter: _ScanPainter(
              t: _c.value,
              phone: scheme.onSurface,
              screen: scheme.surfaceContainerHighest,
              ripple: scheme.primary,
              cardStart: palette.start,
              cardEnd: palette.end,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter({
    required this.t,
    required this.phone,
    required this.screen,
    required this.ripple,
    required this.cardStart,
    required this.cardEnd,
  });

  final double t;
  final Color phone;
  final Color screen;
  final Color ripple;
  final Color cardStart;
  final Color cardEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final center = Offset(size.width / 2 - h * 0.12, h / 2);
    final phoneRect = Rect.fromCenter(
      center: center,
      width: h * 0.42,
      height: h * 0.82,
    );

    // Timeline: 0-.35 slide in, .35-.65 rest + ripple, .65-1 slide out.
    double slide;
    if (t < 0.35) {
      slide = 1 - Curves.easeOutCubic.transform(t / 0.35);
    } else if (t < 0.65) {
      slide = 0;
    } else {
      slide = Curves.easeInCubic.transform((t - 0.65) / 0.35);
    }
    final contact = phoneRect.center + Offset(h * 0.05, h * 0.05);

    // Ripples from the contact point while the card rests.
    if (t > 0.33 && t < 0.8) {
      final p = (t - 0.33) / 0.47;
      for (var i = 0; i < 3; i++) {
        final q = (p - i * 0.18).clamp(0.0, 1.0);
        if (q <= 0) continue;
        canvas.drawCircle(
          contact,
          h * (0.1 + q * 0.45),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = h * 0.02
            ..color = ripple.withValues(alpha: (1 - q) * 0.6),
        );
      }
    }

    // Phone (seen from the back).
    final body = RRect.fromRectAndRadius(phoneRect, Radius.circular(h * 0.07));
    canvas.drawRRect(body, Paint()..color = screen);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.018
        ..color = phone.withValues(alpha: 0.75),
    );
    // Camera bump.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          phoneRect.left + h * 0.04,
          phoneRect.top + h * 0.04,
          h * 0.12,
          h * 0.12,
        ),
        Radius.circular(h * 0.03),
      ),
      Paint()..color = phone.withValues(alpha: 0.25),
    );

    // The card, sliding in from the lower right.
    final cardW = h * 0.5;
    final cardH = cardW / CardFace.aspectRatio;
    final cardCenter =
        contact + Offset(h * 0.75, h * 0.35) * slide + Offset(h * 0.06, 0);
    canvas.save();
    canvas.translate(cardCenter.dx, cardCenter.dy);
    canvas.rotate((-14 + slide * 20) * math.pi / 180);
    final cardRect = Rect.fromCenter(
      center: Offset.zero,
      width: cardW,
      height: cardH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        cardRect.shift(Offset(0, h * 0.02)),
        Radius.circular(h * 0.03),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.15),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cardRect, Radius.circular(h * 0.03)),
      Paint()
        ..shader = LinearGradient(
          colors: [cardStart, cardEnd],
        ).createShader(cardRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cardRect.left + cardW * 0.1,
          cardRect.top + cardH * 0.35,
          cardW * 0.14,
          cardH * 0.18,
        ),
        Radius.circular(h * 0.008),
      ),
      Paint()..color = const Color(0xFFF5B841),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScanPainter old) =>
      old.t != t || old.ripple != ripple || old.cardStart != cardStart;
}
