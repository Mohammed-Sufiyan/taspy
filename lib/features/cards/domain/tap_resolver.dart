import '../../nfc/domain/nfc_models.dart';
import 'registered_card.dart';

/// What a card tap means, given the registered cards.
sealed class TapOutcome {
  const TapOutcome();
}

/// A registered, enabled card: run its action.
class RegisteredTap extends TapOutcome {
  const RegisteredTap(this.card);

  final RegisteredCard card;
}

/// A registered card the user switched off: do not run its action.
class DisabledCardTap extends TapOutcome {
  const DisabledCardTap(this.card);

  final RegisteredCard card;
}

/// A card that is not registered (or reports no ID at all).
class UnknownCardTap extends TapOutcome {
  const UnknownCardTap();
}

TapOutcome resolveTap(TagReading reading, List<RegisteredCard> cards) {
  final fingerprint = reading.fingerprint;
  if (fingerprint == null) return const UnknownCardTap();
  for (final card in cards) {
    if (card.fingerprint == fingerprint) {
      return card.enabled ? RegisteredTap(card) : DisabledCardTap(card);
    }
  }
  return const UnknownCardTap();
}
