import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/motion.dart';
import '../../shared/widgets/glow_background.dart';
import '../../shared/widgets/pop_button.dart';
import '../cards/presentation/card_face.dart';

class _Page {
  const _Page(this.style, this.cardName, this.title, this.body);

  final int style;
  final String cardName;
  final String title;
  final String body;
}

const _pages = [
  _Page(
    5,
    'Metro card',
    'Tap any card',
    'The cards already in your wallet (bank, metro, gym) become shortcuts.',
  ),
  _Page(
    1,
    'Gym pass',
    'Pop up a message',
    'Tap it on the back of your phone and your message appears, even when '
        'Tapsy is closed.',
  ),
  _Page(
    0,
    'SBI Card',
    'Private by design',
    'Only the card’s ID is used. No payment data is read, and nothing ever '
        'leaves your phone.',
  ),
];

/// First-launch tour: a carousel of cards that glides along by itself
/// (swipe to take over), with the story told underneath.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController(viewportFraction: 0.74);
  Timer? _auto;
  int _page = 0;
  bool _userTookOver = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auto?.cancel();
    if (!reduceMotion(context) && !_userTookOver) {
      _auto = Timer.periodic(const Duration(milliseconds: 2800), (_) {
        if (!_controller.hasClients) return;
        final next = (_page + 1) % _pages.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    _stopAuto();
    if (_page == _pages.length - 1) {
      widget.onDone();
      return;
    }
    _controller.animateToPage(
      _page + 1,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  void _stopAuto() {
    _userTookOver = true;
    _auto?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _pages[_page];
    final last = _page == _pages.length - 1;
    return GlowBackground(
      color: CardSkin.glowOf(page.style),
      intensity: 0.3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onDone,
                  child: const Text('Skip'),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 230,
                child: NotificationListener<ScrollStartNotification>(
                  onNotification: (n) {
                    if (n.dragDetails != null) _stopAuto();
                    return false;
                  },
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final pos =
                            _controller.hasClients &&
                                _controller.position.haveDimensions
                            ? _controller.page ?? _page.toDouble()
                            : _page.toDouble();
                        final d = (i - pos).clamp(-1.0, 1.0);
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(-d * math.pi / 9)
                            ..scaleByDouble(
                              1 - d.abs() * 0.12,
                              1 - d.abs() * 0.12,
                              1,
                              1,
                            ),
                          // RepaintBoundary: fade the card as one layer
                          // (Impeller can't push opacity into blurred skins).
                          child: Opacity(
                            opacity: 1 - d.abs() * 0.45,
                            child: RepaintBoundary(child: child),
                          ),
                        );
                      },
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: CardFace(
                            name: _pages[i].cardName,
                            style: _pages[i].style,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? TapsyColors.lime
                            : TapsyColors.outline,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: AnimatedSwitcher(
                  duration: reduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 350),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.15),
                        end: Offset.zero,
                      ).animate(a),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey(_page),
                    children: [
                      Text(
                        page.title,
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        page.body,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: TapsyColors.textMuted,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                child: PopButton(
                  label: last ? 'GET STARTED' : 'NEXT',
                  icon: last ? Icons.bolt_rounded : Icons.arrow_forward_rounded,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
