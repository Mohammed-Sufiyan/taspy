import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../shared/motion.dart';
import '../domain/card_template.dart';
import '../domain/registered_card.dart';
import 'card_face.dart';

/// Design, sticker and effect pickers for the add/edit card forms.
class CardDesigner extends StatelessWidget {
  const CardDesigner({
    super.key,
    required this.style,
    required this.emoji,
    required this.effect,
    required this.onStyle,
    required this.onEmoji,
    required this.onEffect,
    this.enabled = true,
  });

  final int style;
  final String emoji;
  final CardEffect effect;
  final ValueChanged<int> onStyle;
  final ValueChanged<String> onEmoji;
  final ValueChanged<CardEffect> onEffect;
  final bool enabled;

  static const stickers = [
    '', '💳', '🏋️', '🚗', '🏠', '💼', '💻', '🎧', '☕', '🌙', '☀️', '💊', //
    '📚', '🎮', '✈️', '🐶', '🐱', '❤️', '⭐', '🔥', '💸', '🎯', '🍀', '🚀',
  ];

  static IconData effectIcon(CardEffect e) => switch (e) {
    CardEffect.shine => Icons.flare_rounded,
    CardEffect.holo => Icons.gradient_rounded,
    CardEffect.sparkle => Icons.auto_awesome_rounded,
    CardEffect.glow => Icons.blur_on_rounded,
    CardEffect.shimmer => Icons.waves_rounded,
    CardEffect.none => Icons.block_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Design'),
        SkinPicker(value: style, enabled: enabled, onChanged: onStyle),
        const SizedBox(height: 18),
        label('Sticker'),
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stickers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final s = stickers[i];
              final selected = s == emoji;
              return Semantics(
                button: true,
                selected: selected,
                label: s.isEmpty ? 'No sticker' : 'Sticker $s',
                child: GestureDetector(
                  key: ValueKey('sticker-$i'),
                  onTap: enabled
                      ? () {
                          Haptics.detected();
                          onEmoji(s);
                        }
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    width: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? TapsyColors.lime.withValues(alpha: 0.14)
                          : TapsyColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? TapsyColors.lime
                            : TapsyColors.outline,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: s.isEmpty
                        ? const Icon(
                            Icons.block_rounded,
                            color: TapsyColors.textFaint,
                          )
                        : AnimatedScale(
                            scale: selected ? 1.2 : 1,
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              s,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        label('Effect'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in CardEffect.values)
              ChoiceChip(
                key: ValueKey('effect-${e.name}'),
                avatar: Icon(
                  effectIcon(e),
                  size: 18,
                  color: e == effect ? TapsyColors.onLime : TapsyColors.lime,
                ),
                showCheckmark: false,
                label: Text(e.title),
                selected: e == effect,
                selectedColor: TapsyColors.lime,
                labelStyle: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontWeight: FontWeight.w600,
                  color: e == effect ? TapsyColors.onLime : TapsyColors.text,
                ),
                onSelected: enabled
                    ? (_) {
                        Haptics.detected();
                        onEffect(e);
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// "Start from a template" strip shown while adding a card.
class TemplatePicker extends StatelessWidget {
  const TemplatePicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final CardTemplate? selected;
  final ValueChanged<CardTemplate> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Start from a template', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Fills in a design, message and actions. Change anything after.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 122,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: CardTemplate.all.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final t = CardTemplate.all[i];
              final on = identical(t, selected);
              return GestureDetector(
                key: ValueKey('template-${t.name}'),
                onTap: enabled
                    ? () {
                        Haptics.success();
                        onSelected(t);
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  width: 96,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: on
                        ? TapsyColors.lime.withValues(alpha: 0.12)
                        : TapsyColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: on ? TapsyColors.lime : TapsyColors.outline,
                      width: on ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      CardFace(
                        name: '',
                        style: t.style,
                        emoji: t.emoji,
                        compact: true,
                        shine: false,
                      ),
                      const Spacer(),
                      Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: on ? TapsyColors.lime : TapsyColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        t.actions.isEmpty
                            ? 'Message'
                            : '${t.actions.length} '
                                  '${t.actions.length == 1 ? 'action' : 'actions'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
