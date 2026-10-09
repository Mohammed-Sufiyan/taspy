import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../app/theme.dart';
import '../../../shared/device_tilt.dart';
import '../../../shared/motion.dart';

/// A painted card design. Stored on each card as an index ([RegisteredCard.style]).
class CardSkin {
  const CardSkin(this.name, this.paint, {this.dark = true, this.chip});

  final String name;
  final void Function(Canvas canvas, Size size) paint;

  /// True when the art is dark, so text and icons are drawn light.
  final bool dark;
  final Color? chip;

  Color get ink => dark ? Colors.white : const Color(0xFF18181B);
  Color get inkMuted => dark ? Colors.white70 : const Color(0xFF3F3F46);

  static final all = <CardSkin>[
    const CardSkin('Midnight', _midnight, chip: TapsyColors.lime),
    const CardSkin('Aurora', _aurora),
    const CardSkin('Holo', _holo, dark: false),
    const CardSkin('Steel', _steel, dark: false),
    const CardSkin('Carbon', _carbon, chip: TapsyColors.lime),
    const CardSkin('Sunset', _sunset),
    const CardSkin('Ocean', _ocean),
    const CardSkin('Neon', _neon),
  ];

  static CardSkin of(int style) => all[style % all.length];

  /// The dominant colour, used for glows behind the card.
  static Color glowOf(int style) => const [
    TapsyColors.lime,
    Color(0xFF9B5CFF),
    Color(0xFFB8E1FF),
    Color(0xFFD4D4D8),
    TapsyColors.lime,
    Color(0xFFFF7A59),
    Color(0xFF22D3EE),
    Color(0xFFFF3DCB),
  ][style % all.length];
}

// ---- Skin painters ----------------------------------------------------------------------

Rect _r(Size s) => Offset.zero & s;

void _midnight(Canvas c, Size s) {
  c.drawRect(
    _r(s),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF18181B), Color(0xFF0A0A0B)],
      ).createShader(_r(s)),
  );
  final center = Offset(s.width * 0.92, s.height * 0.05);
  for (var i = 1; i <= 7; i++) {
    c.drawCircle(
      center,
      s.width * 0.14 * i,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = TapsyColors.lime.withValues(alpha: 0.32 - i * 0.035),
    );
  }
}

void _aurora(Canvas c, Size s) {
  c.drawRect(_r(s), Paint()..color = const Color(0xFF120B2E));
  void blob(double x, double y, double r, Color color) => c.drawCircle(
    Offset(s.width * x, s.height * y),
    s.width * r,
    Paint()
      ..color = color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * 0.12),
  );
  blob(0.15, 0.2, 0.35, const Color(0xFF7C3AED));
  blob(0.8, 0.1, 0.3, const Color(0xFFDB2777));
  blob(0.65, 0.9, 0.38, const Color(0xFF2563EB));
  blob(0.2, 1.0, 0.25, const Color(0xFF06B6D4));
}

void _holo(Canvas c, Size s) {
  c.drawRect(
    _r(s),
    Paint()
      ..shader = const SweepGradient(
        center: Alignment(-0.4, -0.2),
        colors: [
          Color(0xFFFDE2FF),
          Color(0xFFC7F0FF),
          Color(0xFFD9FFD6),
          Color(0xFFFFF4C2),
          Color(0xFFFFD6E8),
          Color(0xFFFDE2FF),
        ],
      ).createShader(_r(s)),
  );
  for (var i = 0; i < 6; i++) {
    final x = s.width * (i * 0.22 - 0.2);
    c.drawPath(
      Path()
        ..moveTo(x, 0)
        ..lineTo(x + s.width * 0.08, 0)
        ..lineTo(x + s.width * 0.08 + s.height * 0.6, s.height)
        ..lineTo(x + s.height * 0.6, s.height)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
  }
}

void _steel(Canvas c, Size s) {
  c.drawRect(
    _r(s),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE4E4E7), Color(0xFFA1A1AA), Color(0xFFE4E4E7)],
      ).createShader(_r(s)),
  );
  final rnd = math.Random(7);
  final line = Paint()..strokeWidth = 0.6;
  for (var y = 0.0; y < s.height; y += 1.6) {
    line.color = (rnd.nextBool() ? Colors.white : Colors.black).withValues(
      alpha: 0.05 + rnd.nextDouble() * 0.06,
    );
    c.drawLine(Offset(0, y), Offset(s.width, y), line);
  }
}

void _carbon(Canvas c, Size s) {
  c.drawRect(_r(s), Paint()..color = const Color(0xFF151517));
  final a = Paint()..color = const Color(0xFF1F1F23);
  final b = Paint()..color = const Color(0xFF0E0E10);
  final cell = s.width / 36;
  for (var y = 0; y * cell < s.height; y++) {
    for (var x = 0; x * cell < s.width; x++) {
      c.drawRect(
        Rect.fromLTWH(x * cell, y * cell, cell, cell * 0.5),
        (x + y).isEven ? a : b,
      );
    }
  }
  c.drawRect(
    _r(s),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: 0.06), Colors.transparent],
      ).createShader(_r(s)),
  );
}

void _sunset(Canvas c, Size s) {
  c.drawRect(
    _r(s),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE11D48), Color(0xFFF97316), Color(0xFFFBBF24)],
      ).createShader(_r(s)),
  );
  _contours(c, s, Colors.white.withValues(alpha: 0.16));
}

void _ocean(Canvas c, Size s) {
  c.drawRect(
    _r(s),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFF1E3A8A), Color(0xFF0891B2), Color(0xFF22D3EE)],
      ).createShader(_r(s)),
  );
  final p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = Colors.white.withValues(alpha: 0.18);
  for (var i = 0; i < 9; i++) {
    final y = s.height * (0.25 + i * 0.09);
    final path = Path()..moveTo(0, y);
    for (var x = 0.0; x <= s.width; x += s.width / 24) {
      path.lineTo(
        x,
        y + math.sin(x / s.width * math.pi * 3 + i) * s.height * 0.03,
      );
    }
    c.drawPath(path, p);
  }
}

void _neon(Canvas c, Size s) {
  c.drawRect(_r(s), Paint()..color = const Color(0xFF07040F));
  final horizon = s.height * 0.45;
  final pink = Paint()
    ..strokeWidth = 1
    ..color = const Color(0xFFFF3DCB).withValues(alpha: 0.55);
  final cyan = Paint()
    ..strokeWidth = 1
    ..color = const Color(0xFF22D3EE).withValues(alpha: 0.45);
  for (var i = 0; i < 8; i++) {
    final t = i / 7;
    final y = horizon + (s.height - horizon) * t * t;
    c.drawLine(Offset(0, y), Offset(s.width, y), pink);
  }
  for (var i = -8; i <= 8; i++) {
    c.drawLine(
      Offset(s.width / 2 + i * s.width * 0.04, horizon),
      Offset(s.width / 2 + i * s.width * 0.22, s.height),
      cyan,
    );
  }
  c.drawCircle(
    Offset(s.width * 0.5, horizon),
    s.width * 0.18,
    Paint()
      ..color = const Color(0xFFFF3DCB).withValues(alpha: 0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * 0.08),
  );
}

void _contours(Canvas c, Size s, Color color) {
  final p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = color;
  final center = Offset(s.width * 0.78, s.height * 0.7);
  for (var i = 1; i <= 9; i++) {
    final path = Path();
    var first = true;
    for (var a = 0.0; a <= math.pi * 2 + 0.01; a += math.pi / 30) {
      final r = s.width * 0.07 * i * (1 + 0.12 * math.sin(a * 3 + i));
      final pt = center + Offset(math.cos(a) * r, math.sin(a) * r * 0.75);
      if (first) {
        path.moveTo(pt.dx, pt.dy);
        first = false;
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    c.drawPath(path, p);
  }
}

class _SkinPainter extends CustomPainter {
  _SkinPainter(this.skin);

  final CardSkin skin;

  @override
  void paint(Canvas canvas, Size size) => skin.paint(canvas, size);

  @override
  bool shouldRepaint(_SkinPainter old) => old.skin != skin;
}

// ---- Card face ---------------------------------------------------------------------------

/// A registered card drawn like a real payment card.
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.name,
    required this.style,
    this.enabled = true,
    this.subtitle,
    this.shine = true,
    this.compact = false,
    this.secret = false,
  });

  final String name;
  final int style;
  final bool enabled;
  final String? subtitle;

  /// Moving highlight that follows the phone's tilt.
  final bool shine;

  /// Hides the details for small thumbnails.
  final bool compact;

  /// Shows a lock next to the contactless mark.
  final bool secret;

  static const aspectRatio = 1.586; // ISO/IEC 7810 ID-1

  @override
  Widget build(BuildContext context) {
    final skin = CardSkin.of(style);
    final face = AspectRatio(
      aspectRatio: aspectRatio,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final radius = BorderRadius.circular(w * 0.065);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: compact
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: w * 0.08,
                        offset: Offset(0, w * 0.04),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(painter: _SkinPainter(skin)),
                  ),
                  if (shine && !compact) const _Shine(),
                  // Thin bright rim, like a card edge catching light.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  if (!compact)
                    Padding(
                      padding: EdgeInsets.all(w * 0.07),
                      child: _Details(
                        skin: skin,
                        name: name,
                        subtitle: subtitle,
                        width: w,
                        secret: secret,
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
            0.3, 0.3, 0.3, 0, 0, //
            0.3, 0.3, 0.3, 0, 0, //
            0.3, 0.3, 0.3, 0, 0, //
            0, 0, 0, 0.6, 0, //
          ]),
          child: face,
        ),
        Positioned(
          right: 14,
          top: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'PAUSED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: TapsyColors.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.skin,
    required this.name,
    required this.subtitle,
    required this.width,
    this.secret = false,
  });

  final CardSkin skin;
  final String name;
  final String? subtitle;
  final double width;
  final bool secret;

  @override
  Widget build(BuildContext context) {
    final w = width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'tapsy',
              style: TextStyle(
                color: skin.ink,
                fontWeight: FontWeight.w800,
                fontSize: w * 0.058,
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),
            if (secret) ...[
              Icon(Icons.lock_rounded, color: skin.ink, size: w * 0.065),
              SizedBox(width: w * 0.025),
            ],
            Icon(Icons.contactless_outlined, color: skin.ink, size: w * 0.09),
          ],
        ),
        const Spacer(),
        Container(
          width: w * 0.12,
          height: w * 0.09,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(w * 0.018),
            gradient: LinearGradient(
              colors: [
                skin.chip ?? const Color(0xFFF5D27A),
                (skin.chip ?? const Color(0xFFC9A34A)).withValues(alpha: 0.7),
              ],
            ),
          ),
        ),
        const Spacer(),
        Text(
          name.isEmpty ? 'YOUR CARD' : name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: skin.ink,
            fontWeight: FontWeight.w700,
            fontSize: w * 0.062,
            letterSpacing: 1.2,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: EdgeInsets.only(top: w * 0.008),
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: skin.inkMuted, fontSize: w * 0.04),
            ),
          ),
      ],
    );
  }
}

/// Diagonal light band that slides across the card as the phone tilts.
class _Shine extends StatefulWidget {
  const _Shine();

  @override
  State<_Shine> createState() => _ShineState();
}

class _ShineState extends State<_Shine> {
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final want = !reduceMotion(context);
    if (want && !_listening) DeviceTilt.instance.acquire();
    if (!want && _listening) DeviceTilt.instance.release();
    _listening = want;
  }

  @override
  void dispose() {
    if (_listening) DeviceTilt.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<Offset>(
        valueListenable: DeviceTilt.instance,
        builder: (_, tilt, _) {
          final x = tilt.dx * 1.4 - 0.2;
          final y = tilt.dy * 1.4 - 0.2;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(x - 1.2, y - 1.2),
                end: Alignment(x + 1.2, y + 1.2),
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0.35, 0.5, 0.65],
              ),
            ),
          );
        },
      ),
    );
  }
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

/// Horizontal strip of mini cards for picking a skin.
class SkinPicker extends StatefulWidget {
  const SkinPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  State<SkinPicker> createState() => _SkinPickerState();
}

class _SkinPickerState extends State<SkinPicker> {
  static const _itemWidth = 92.0;
  late final _scroll = ScrollController(
    initialScrollOffset: math.max(0, widget.value * (_itemWidth + 12) - 40),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        itemCount: CardSkin.all.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final selected = i == widget.value;
          return Semantics(
            button: true,
            selected: selected,
            label: '${CardSkin.all[i].name} card design',
            child: GestureDetector(
              key: ValueKey('skin-$i'),
              onTap: widget.enabled
                  ? () {
                      Haptics.detected();
                      widget.onChanged(i);
                    }
                  : null,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    width: _itemWidth,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? TapsyColors.lime : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: AnimatedScale(
                      scale: selected ? 1 : 0.92,
                      duration: const Duration(milliseconds: 220),
                      child: CardFace(
                        name: '',
                        style: i,
                        compact: true,
                        shine: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    CardSkin.all[i].name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected
                          ? TapsyColors.lime
                          : TapsyColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
