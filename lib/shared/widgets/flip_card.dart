import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';

/// Shows [front] or [back], turning over around the vertical axis.
class FlipCard extends StatelessWidget {
  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.flipped,
  });

  final Widget front;
  final Widget back;
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: flipped ? math.pi : 0),
      duration: reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 550),
      curve: Curves.easeInOutCubic,
      builder: (context, angle, _) {
        final showBack = angle > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0014)
            ..rotateY(angle),
          child: showBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: back,
                )
              : front,
        );
      },
    );
  }
}
