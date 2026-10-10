import '../../actions/domain/card_action.dart';
import 'registered_card.dart';

/// A ready-made setup offered when adding a card. Everything stays editable;
/// only actions that need nothing personal (no numbers, no addresses) are
/// included, so a template never runs something the user didn't fill in.
class CardTemplate {
  const CardTemplate({
    required this.name,
    required this.emoji,
    required this.style,
    required this.message,
    this.effect = CardEffect.shine,
    this.actions = const [],
  });

  final String name;
  final String emoji;
  final int style;
  final CardEffect effect;
  final String message;
  final List<CardAction> actions;

  static const all = [
    CardTemplate(
      name: 'Gym',
      emoji: '🏋️',
      style: 4, // Carbon
      effect: CardEffect.glow,
      message: 'Workout started. Let’s go! 💪',
      actions: [
        CardAction(type: ActionType.timer, value: '60', label: 'Workout'),
      ],
    ),
    CardTemplate(
      name: 'Focus',
      emoji: '💻',
      style: 3, // Steel
      effect: CardEffect.shimmer,
      message: '25 minutes of deep work. Phone down.',
      actions: [
        CardAction(type: ActionType.timer, value: '25', label: 'Focus'),
      ],
    ),
    CardTemplate(
      name: 'Bedtime',
      emoji: '🌙',
      style: 0, // Midnight
      effect: CardEffect.sparkle,
      message: 'Lights out. Sleep well.',
      actions: [
        CardAction(type: ActionType.flashlight, value: 'off'),
        CardAction(type: ActionType.timer, value: '30', label: 'Wind down'),
      ],
    ),
    CardTemplate(
      name: 'Medicine',
      emoji: '💊',
      style: 5, // Sunset
      message: 'Medicine taken ✔︎ See you tomorrow.',
    ),
    CardTemplate(
      name: 'Car',
      emoji: '🚗',
      style: 6, // Ocean
      message: 'Drive safe!',
      actions: [
        CardAction(
          type: ActionType.openApp,
          value: 'com.google.android.apps.maps',
          label: 'Google Maps',
        ),
      ],
    ),
    CardTemplate(
      name: 'Torch',
      emoji: '🔦',
      style: 7, // Neon
      effect: CardEffect.glow,
      message: '',
      actions: [CardAction(type: ActionType.flashlight, value: 'toggle')],
    ),
    CardTemplate(
      name: 'Morning',
      emoji: '☀️',
      style: 10, // Gold
      effect: CardEffect.shimmer,
      message: 'Good morning! Drink a glass of water 💧',
      actions: [
        CardAction(type: ActionType.timer, value: '5', label: 'Stretch'),
      ],
    ),
    CardTemplate(
      name: 'Tea',
      emoji: '☕',
      style: 12, // Forest
      message: 'Tea is brewing.',
      actions: [CardAction(type: ActionType.timer, value: '4', label: 'Tea')],
    ),
  ];
}
