import 'dart:math';

import '../../nfc/domain/nfc_models.dart';

/// A card the user registered as an automation trigger.
///
/// Stores no card data: [fingerprint] is the salted, truncated hash of the
/// card's ID produced natively (see `NfcBridge.kt`), only usable on this
/// install. A static ID can be copied, so a match means "this card's ID was
/// seen", not proof that the physical card is genuine.
class RegisteredCard {
  const RegisteredCard({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.category,
    required this.message,
    required this.enabled,
    required this.createdAt,
    this.lastTriggeredAt,
    this.style = 0,
  });

  factory RegisteredCard.create({
    required String name,
    required String fingerprint,
    required CardCategory category,
    required String message,
    int style = 0,
    DateTime? now,
  }) => RegisteredCard(
    id: _newId(),
    name: name.trim(),
    fingerprint: fingerprint,
    category: category,
    message: message.trim(),
    enabled: true,
    createdAt: now ?? DateTime.now(),
    style: style,
  );

  factory RegisteredCard.fromJson(Map<String, Object?> json) => RegisteredCard(
    id: json['id']! as String,
    name: json['name']! as String,
    fingerprint: json['fingerprint']! as String,
    category: CardCategory.values.firstWhere(
      (c) => c.name == json['category'],
      orElse: () => CardCategory.otherTag,
    ),
    message: json['message']! as String,
    enabled: json['enabled'] as bool? ?? true,
    createdAt: DateTime.parse(json['createdAt']! as String),
    lastTriggeredAt: switch (json['lastTriggeredAt']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
    style: json['style'] as int? ?? 0,
  );

  final String id;
  final String name;
  final String fingerprint;
  final CardCategory category;
  final String message;
  final bool enabled;
  final DateTime createdAt;
  final DateTime? lastTriggeredAt;

  /// Index into the card colour palette (see `CardFace`). Optional field added
  /// without a schema bump: older files simply default to 0.
  final int style;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'fingerprint': fingerprint,
    'category': category.name,
    'message': message,
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
    'lastTriggeredAt': lastTriggeredAt?.toIso8601String(),
    'style': style,
  };

  RegisteredCard copyWith({
    String? name,
    String? message,
    bool? enabled,
    DateTime? lastTriggeredAt,
    int? style,
  }) => RegisteredCard(
    id: id,
    name: name?.trim() ?? this.name,
    fingerprint: fingerprint,
    category: category,
    message: message?.trim() ?? this.message,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt,
    lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
    style: style ?? this.style,
  );

  static String _newId() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

/// Input rules shared by the registration and edit forms.
abstract final class CardValidation {
  static const maxNameLength = 40;
  static const maxMessageLength = 200;
  static const defaultMessage = 'Your registered card was detected.';

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter a name for this card';
    if (v.length > maxNameLength) {
      return 'Keep the name under $maxNameLength characters';
    }
    return null;
  }

  static String? message(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter the message to show';
    if (v.length > maxMessageLength) {
      return 'Keep the message under $maxMessageLength characters';
    }
    return null;
  }
}

/// One recognised tap of a registered card. Stored locally for the "Recent
/// taps" list and stats; contains only the card's internal id and a time.
class TapEvent {
  const TapEvent({required this.cardId, required this.at});

  factory TapEvent.fromJson(Map<String, Object?> json) => TapEvent(
    cardId: json['cardId']! as String,
    at: DateTime.parse(json['at']! as String),
  );

  final String cardId;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'cardId': cardId,
    'at': at.toIso8601String(),
  };
}
