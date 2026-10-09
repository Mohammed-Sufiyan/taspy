import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../motion.dart';

/// A chunky 3D button (inspired by CRED's NeoPOP): a flat face sitting on a
/// solid offset edge. Pressing pushes the face down onto the edge.
class PopButton extends StatefulWidget {
  const PopButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = TapsyColors.lime,
    this.edgeColor = TapsyColors.limeDeep,
    this.textColor = TapsyColors.onLime,
    this.expand = true,
    this.busy = false,
  });

  /// Secondary style: dark face with a light edge.
  const PopButton.dark({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.busy = false,
  }) : color = TapsyColors.surfaceHigh,
       edgeColor = const Color(0xFF52525B),
       textColor = TapsyColors.text;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color edgeColor;
  final Color textColor;
  final bool expand;
  final bool busy;

  static const depth = 5.0;

  @override
  State<PopButton> createState() => _PopButtonState();
}

class _PopButtonState extends State<PopButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  void _set(bool down) {
    if (_enabled && down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    const d = PopButton.depth;
    final pressed = _down ? d : 0.0;
    final face = _enabled ? widget.color : widget.color.withValues(alpha: 0.4);
    final edge = _enabled
        ? widget.edgeColor
        : widget.edgeColor.withValues(alpha: 0.4);
    final duration = reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 70);

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: widget.textColor,
            ),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 20, color: widget.textColor),
        if (widget.busy || widget.icon != null) const SizedBox(width: 10),
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 0.3,
              color: widget.textColor,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: _enabled
            ? () {
                Haptics.detected();
                widget.onPressed!();
              }
            : null,
        child: SizedBox(
          width: widget.expand ? double.infinity : null,
          height: 56 + d,
          child: Stack(
            children: [
              // The 3D edge: offset down-right behind the face.
              Positioned(
                left: d,
                top: d,
                right: 0,
                bottom: 0,
                child: DecoratedBox(decoration: BoxDecoration(color: edge)),
              ),
              // The face sizes the stack; pressing slides it onto the edge.
              AnimatedContainer(
                duration: duration,
                margin: const EdgeInsets.only(right: d, bottom: d),
                transform: Matrix4.translationValues(pressed, pressed, 0),
                height: 56,
                width: widget.expand ? double.infinity : null,
                color: face,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                alignment: widget.expand ? Alignment.center : null,
                child: widget.expand
                    ? content
                    : Center(widthFactor: 1, child: content),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
