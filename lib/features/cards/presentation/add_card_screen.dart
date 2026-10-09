import 'package:flutter/material.dart';

import '../../nfc/data/nfc_platform.dart';
import '../domain/registered_card.dart';
import 'add_card_controller.dart';
import 'card_form.dart';
import 'cards_controller.dart';

/// Pops with the new card's name once it is saved.
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key, required this.platform, required this.cards});

  final NfcPlatform platform;
  final CardsController cards;

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

  @override
  void initState() {
    super.initState();
    _c.start();
  }

  @override
  void dispose() {
    _c.dispose(); // Also stops any running scan.
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final card = await _c.save(name: _name.text, message: _message.text);
    if (card != null && mounted) Navigator.of(context).pop(card.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add card')),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [_stepCard(context), ..._form(context)],
        ),
      ),
    );
  }

  Widget _stepCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget panel({
      required IconData icon,
      required String title,
      required String body,
      Color? color,
      bool progress = false,
      Widget? action,
    }) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 56, color: color ?? scheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              if (progress) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (action != null) ...[const SizedBox(height: 16), action],
            ],
          ),
        ),
      );
    }

    final tryAgain = FilledButton.tonalIcon(
      onPressed: _c.restart,
      icon: const Icon(Icons.refresh),
      label: const Text('Try again'),
    );

    return switch (_c.step) {
      AddCardStep.checkingNfc => panel(
        icon: Icons.nfc,
        title: 'Checking NFC…',
        body: '',
        progress: true,
      ),
      AddCardStep.nfcUnavailable => panel(
        icon: Icons.portable_wifi_off,
        color: scheme.error,
        title: 'NFC not ready',
        body: _c.nfcProblem ?? '',
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
        icon: Icons.contactless_outlined,
        title: 'Tap your card',
        body:
            'Hold the card flat against the back of the phone until it is '
            'detected. Nothing is written to the card and no payment data is read.',
        progress: true,
      ),
      AddCardStep.waitingConfirmTap => panel(
        icon: Icons.contactless,
        title: 'Card detected. Tap it again',
        body:
            'Move the card away, then tap it once more. This checks the card '
            'gives the same ID every time, so the app can recognise it later.',
        progress: true,
      ),
      AddCardStep.timedOut => panel(
        icon: Icons.timer_off_outlined,
        color: scheme.error,
        title: 'No card detected',
        body:
            'Nothing was detected for ${_c.scanTimeout.inSeconds} seconds. '
            'Try a different spot on the back of the phone.',
        action: tryAgain,
      ),
      AddCardStep.noId => panel(
        icon: Icons.block,
        color: scheme.error,
        title: "This card can't be registered",
        body:
            'It does not report an ID, so the app has no way to recognise it.',
        action: tryAgain,
      ),
      AddCardStep.idChanged => panel(
        icon: Icons.shuffle,
        color: scheme.error,
        title: 'The ID changed between taps',
        body:
            'Either a different card was used for the second tap, or this card '
            'changes its ID on every tap. Cards like that cannot be recognised. '
            'Try again with the same card.',
        action: tryAgain,
      ),
      AddCardStep.alreadyRegistered => panel(
        icon: Icons.info_outline,
        title: 'Already registered',
        body:
            'This card is already registered as "${_c.existing?.name}". '
            'Edit it from the home screen.',
        action: tryAgain,
      ),
      AddCardStep.ready || AddCardStep.saving => panel(
        icon: Icons.verified,
        title: 'Card verified',
        body:
            '${_c.firstTap?.category.title ?? 'Card'} · same ID on both taps. '
            'Name it and choose the message to show.',
      ),
    };
  }

  List<Widget> _form(BuildContext context) {
    if (_c.step != AddCardStep.ready && _c.step != AddCardStep.saving) {
      return const [];
    }
    final saving = _c.step == AddCardStep.saving;
    return [
      const SizedBox(height: 16),
      Form(
        key: _formKey,
        child: CardFormFields(name: _name, message: _message, enabled: !saving),
      ),
      if (_c.saveError case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: saving ? null : _save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: Text(saving ? 'Saving…' : 'Save card'),
      ),
    ];
  }
}
