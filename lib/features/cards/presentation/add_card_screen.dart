import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme.dart';
import '../../../shared/motion.dart';
import '../../../shared/widgets/effects.dart';
import '../../../shared/widgets/glow_background.dart';
import '../../../shared/widgets/pop_button.dart';
import '../../nfc/data/nfc_platform.dart';
import '../../security/security_controller.dart';
import '../domain/registered_card.dart';
import 'add_card_controller.dart';
import 'card_face.dart';
import 'card_form.dart';
import 'cards_controller.dart';
import 'scan_animation.dart';

/// Pops with the new card's name once it is saved.
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({
    super.key,
    required this.platform,
    required this.cards,
    required this.security,
  });

  final NfcPlatform platform;
  final CardsController cards;
  final SecurityController security;

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  late final AddCardController _c = AddCardController(
    widget.platform,
    widget.cards,
  );
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _message = TextEditingController(text: CardValidation.defaultMessage);
  int _style = 0;
  bool _secret = false;
  AddCardStep _lastStep = AddCardStep.checkingNfc;
  RegisteredCard? _saved;

  static const _errorSteps = {
    AddCardStep.timedOut,
    AddCardStep.noId,
    AddCardStep.idChanged,
    AddCardStep.alreadyRegistered,
    AddCardStep.nfcUnavailable,
  };

  @override
  void initState() {
    super.initState();
    _c.addListener(_onStep);
    _name.addListener(() => setState(() {})); // Live card preview.
    _c.start();
  }

  void _onStep() {
    final step = _c.step;
    if (step == _lastStep) return;
    if (step == AddCardStep.waitingConfirmTap) Haptics.detected();
    if (step == AddCardStep.ready) Haptics.success();
    if (_errorSteps.contains(step)) Haptics.error();
    _lastStep = step;
    setState(() {}); // Background glow follows the step.
  }

  @override
  void dispose() {
    _c.removeListener(_onStep);
    _c.dispose(); // Also stops any running scan.
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final card = await _c.save(
      name: _name.text,
      message: _message.text,
      style: _style,
      secret: _secret,
    );
    if (card == null || !mounted) return;
    Haptics.celebrate();
    setState(() => _saved = card);
    await Future<void>.delayed(
      reduceMotion(context)
          ? const Duration(milliseconds: 600)
          : const Duration(milliseconds: 1600),
    );
    if (mounted) Navigator.of(context).pop(card.name);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _c.step == AddCardStep.ready || _c.step == AddCardStep.saving;
    return GlowBackground(
      color: ready ? CardSkin.glowOf(_style) : TapsyColors.lime,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Add card')),
        body: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _StepDots(step: _c.step),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: reduceMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.94, end: 1.0).animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_panelKey(_c.step)),
                      child: _stepPanel(context),
                    ),
                  ),
                  ..._form(context),
                ],
              ),
              if (_saved case final card?) _SavedOverlay(card: card),
            ],
          ),
        ),
      ),
    );
  }

  /// Steps that look the same share a key so the panel doesn't re-animate.
  String _panelKey(AddCardStep s) => switch (s) {
    AddCardStep.ready || AddCardStep.saving => 'ready',
    _ => s.name,
  };

  Widget _stepPanel(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget panel({
      required Widget art,
      required String title,
      required String body,
      Widget? action,
      bool shake = false,
    }) {
      Widget card = Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            children: [
              art,
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 16), action],
            ],
          ),
        ),
      );
      if (shake && !reduceMotion(context)) {
        card = card.animate().shakeX(hz: 5, amount: 6, duration: 450.ms);
      }
      return card;
    }

    Widget errorIcon(IconData icon) => PulseRings(
      color: scheme.error,
      size: 120,
      active: false,
      child: CircleAvatar(
        radius: 40,
        backgroundColor: scheme.errorContainer,
        child: Icon(icon, size: 40, color: scheme.onErrorContainer),
      ),
    );

    final tryAgain = PopButton(
      label: 'TRY AGAIN',
      icon: Icons.refresh_rounded,
      expand: false,
      onPressed: _c.restart,
    );

    return switch (_c.step) {
      AddCardStep.checkingNfc => panel(
        art: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
        title: 'Checking NFC…',
        body: '',
      ),
      AddCardStep.nfcUnavailable => panel(
        art: errorIcon(Icons.portable_wifi_off),
        title: 'NFC not ready',
        body: _c.nfcProblem ?? '',
        shake: true,
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _c.openSettings,
              child: const Text('Open NFC settings'),
            ),
            FilledButton.tonal(onPressed: _c.start, child: const Text('Retry')),
          ],
        ),
      ),
      AddCardStep.waitingFirstTap => panel(
        art: const ScanAnimation(style: 5),
        title: 'Tap your card on the back',
        body:
            'Hold it flat near the middle of the phone. Nothing is written to '
            'the card and no payment data is read.',
      ),
      AddCardStep.waitingConfirmTap => panel(
        art: PulseRings(
          color: scheme.primary,
          size: 200,
          child:
              CircleAvatar(
                radius: 44,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.contactless,
                  size: 48,
                  color: scheme.onPrimaryContainer,
                ),
              ).animate().scale(
                begin: const Offset(0.6, 0.6),
                curve: Curves.elasticOut,
                duration: 700.ms,
              ),
        ),
        title: 'Got it! Tap once more',
        body:
            'Move the card away, then tap again. This checks it gives the '
            'same ID every time, so Tapsy can recognise it later.',
      ),
      AddCardStep.timedOut => panel(
        art: errorIcon(Icons.timer_off_outlined),
        title: 'No card detected',
        body:
            'Nothing was detected for ${_c.scanTimeout.inSeconds} seconds. '
            'Try a different spot on the back of the phone.',
        shake: true,
        action: tryAgain,
      ),
      AddCardStep.noId => panel(
        art: errorIcon(Icons.block),
        title: "This card can't be registered",
        body: 'It does not report an ID, so Tapsy has no way to recognise it.',
        shake: true,
        action: tryAgain,
      ),
      AddCardStep.idChanged => panel(
        art: errorIcon(Icons.shuffle),
        title: 'The ID changed between taps',
        body:
            'Either a different card was used for the second tap, or this card '
            'changes its ID on every tap. Cards like that cannot be recognised.',
        shake: true,
        action: tryAgain,
      ),
      AddCardStep.alreadyRegistered => panel(
        art: errorIcon(Icons.bookmark_added_outlined),
        title: 'Already registered',
        body:
            'This card is already registered as "${_c.existing?.name}". '
            'Edit it from the home screen.',
        shake: true,
        action: tryAgain,
      ),
      AddCardStep.ready || AddCardStep.saving => panel(
        art: AnimatedCheck(color: scheme.primary, size: 88),
        title: 'Card verified',
        body:
            '${_c.firstTap?.category.title ?? 'Card'} · same ID on both taps. '
            'Now make it yours.',
      ),
    };
  }

  List<Widget> _form(BuildContext context) {
    if (_c.step != AddCardStep.ready && _c.step != AddCardStep.saving) {
      return const [];
    }
    final saving = _c.step == AddCardStep.saving;
    final theme = Theme.of(context);
    final items = <Widget>[
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: TiltOnDrag(
          child: CardFace(name: _name.text.trim(), style: _style),
        ),
      ),
      const SizedBox(height: 20),
      Text('Design', style: theme.textTheme.titleSmall),
      const SizedBox(height: 10),
      SkinPicker(
        value: _style,
        enabled: !saving,
        onChanged: (v) => setState(() => _style = v),
      ),
      const SizedBox(height: 20),
      Form(
        key: _formKey,
        child: CardFormFields(name: _name, message: _message, enabled: !saving),
      ),
      const SizedBox(height: 8),
      SecretSwitch(
        value: _secret,
        enabled: !saving,
        available: widget.security.available,
        onChanged: (v) => setState(() => _secret = v),
      ),
      if (_c.saveError case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ),
      const SizedBox(height: 16),
      PopButton(
        label: saving ? 'SAVING…' : 'SAVE CARD',
        icon: Icons.check_rounded,
        busy: saving,
        onPressed: _save,
      ),
    ];
    if (reduceMotion(context)) return items;
    return items
        .animate(interval: 60.ms)
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.15, curve: Curves.easeOutCubic);
  }
}

/// "Step 1 → Step 2 → Done" indicator.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final AddCardStep step;

  int get _index => switch (step) {
    AddCardStep.waitingConfirmTap => 1,
    AddCardStep.ready || AddCardStep.saving => 2,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = ['Tap', 'Tap again', 'Name it'];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: i <= _index ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                width: i == _index ? 30 : 24,
                height: i == _index ? 30 : 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= _index ? scheme.primary : scheme.surfaceContainer,
                  border: Border.all(
                    color: i <= _index ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
                alignment: Alignment.center,
                child: i < _index
                    ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: i <= _index
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Text(labels[i], style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ],
    );
  }
}

/// Full-screen celebration after saving.
class _SavedOverlay extends StatelessWidget {
  const _SavedOverlay({required this.card});

  final RegisteredCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: _fade(
        ColoredBox(
          color: theme.colorScheme.surface.withValues(alpha: 0.96),
          child: Stack(
            children: [
              const Positioned.fill(child: ConfettiBurst()),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CardFace(name: card.name, style: card.style)
                          .animate()
                          .scale(
                            begin: const Offset(0.7, 0.7),
                            curve: Curves.elasticOut,
                            duration: 900.ms,
                          )
                          .shimmer(delay: 400.ms, duration: 900.ms),
                      const SizedBox(height: 24),
                      Text(
                        'All set!',
                        style: theme.textTheme.headlineMedium,
                      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.4),
                      const SizedBox(height: 8),
                      Text(
                        'Tap "${card.name}" on your phone anytime.',
                        textAlign: TextAlign.center,
                      ).animate().fadeIn(delay: 350.ms),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fade(Widget child) => child.animate().fadeIn(duration: 200.ms);
}
