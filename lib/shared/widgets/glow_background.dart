import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Near-black background with a soft coloured glow near the top, which fades
/// to a new colour when [color] changes (e.g. to match the selected card).
class GlowBackground extends StatelessWidget {
  const GlowBackground({
    super.key,
    required this.child,
    this.color = TapsyColors.lime,
    this.intensity = 0.22,
  });

  final Widget child;
  final Color color;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: const Duration(milliseconds: 600),
      builder: (context, c, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: TapsyColors.background,
          gradient: RadialGradient(
            center: const Alignment(0.6, -1.1),
            radius: 1.25,
            colors: [
              (c ?? color).withValues(alpha: intensity),
              (c ?? color).withValues(alpha: intensity * 0.25),
              TapsyColors.background.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
        child: child,
      ),
      child: child,
    );
  }
}
