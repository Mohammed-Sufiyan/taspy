import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme.dart';
import '../../shared/motion.dart';
import '../../shared/security/auth_service.dart';
import '../../shared/widgets/glow_background.dart';
import '../../shared/widgets/pop_button.dart';
import '../../shared/widgets/tapsy_mark.dart';
import 'security_controller.dart';

/// Shows [child] only while the app is unlocked. The child is not built at
/// all while locked, so nothing of it can show through.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.security, required this.child});

  final SecurityController security;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: widget.security.onHidden,
      onShow: widget.security.onShown,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.security,
      builder: (context, _) {
        final s = widget.security;
        if (!s.loaded) return const Scaffold();
        return AnimatedSwitcher(
          duration: reduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 350),
          child: s.locked
              ? LockScreen(key: const ValueKey('lock'), security: s)
              : KeyedSubtree(key: const ValueKey('app'), child: widget.child),
        );
      },
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.security});

  final SecurityController security;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Ask straight away, like a banking app.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await widget.security.unlock();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (result) {
        AuthResult.success => null,
        AuthResult.failed => 'Not verified. Try again.',
        AuthResult.unavailable =>
          'No fingerprint, face or screen lock is set up on this phone.',
      };
    });
    if (result != AuthResult.success) Haptics.error();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlowBackground(
      intensity: 0.28,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(),
                const TapsyMark(size: 120, tile: true),
                const SizedBox(height: 28),
                Text('Tapsy is locked', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(
                  'Verify it’s you to see your cards.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: TapsyColors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_message case final m?) ...[
                  const SizedBox(height: 16),
                  Text(
                    m,
                    style: const TextStyle(color: TapsyColors.danger),
                    textAlign: TextAlign.center,
                  ).animate().shakeX(hz: 5, amount: 4, duration: 400.ms),
                ],
                const Spacer(),
                PopButton(
                  label: 'UNLOCK',
                  icon: Icons.fingerprint_rounded,
                  busy: _busy,
                  onPressed: _unlock,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
