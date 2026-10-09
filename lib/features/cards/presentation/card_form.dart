import 'package:flutter/material.dart';

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
