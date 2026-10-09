import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../domain/registered_card.dart';

/// Name + message fields, used by registration and editing.
class CardFormFields extends StatelessWidget {
  const CardFormFields({
    super.key,
    required this.name,
    required this.message,
    this.enabled = true,
  });

  final TextEditingController name;
  final TextEditingController message;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: name,
          enabled: enabled,
          maxLength: CardValidation.maxNameLength,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Card name',
            hintText: 'e.g. SBI Card',
            border: OutlineInputBorder(),
          ),
          validator: CardValidation.name,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: message,
          enabled: enabled,
          maxLength: CardValidation.maxMessageLength,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Message to show when tapped',
            border: OutlineInputBorder(),
          ),
          validator: CardValidation.message,
        ),
      ],
    );
  }
}

/// "Secret message" switch: the message is only shown after a fingerprint,
/// face or screen-lock check.
class SecretSwitch extends StatelessWidget {
  const SecretSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.available,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// False when the phone has no fingerprint/face/screen lock set up.
  final bool available;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final canTurnOn = available || value;
    return Container(
      decoration: BoxDecoration(
        color: TapsyColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: value
              ? TapsyColors.lime.withValues(alpha: 0.6)
              : TapsyColors.outline,
        ),
      ),
      child: SwitchListTile(
        key: const ValueKey('secret-switch'),
        secondary: Icon(
          value ? Icons.lock_rounded : Icons.lock_open_rounded,
          color: value ? TapsyColors.lime : TapsyColors.textMuted,
        ),
        title: const Text('Secret message'),
        subtitle: Text(
          available
              ? 'Hidden until you verify with fingerprint, face or PIN'
              : 'Set up a fingerprint or screen lock on your phone first',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        value: value,
        onChanged: enabled && canTurnOn ? onChanged : null,
      ),
    );
  }
}
