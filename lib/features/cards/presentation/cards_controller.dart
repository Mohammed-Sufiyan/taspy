import 'package:flutter/foundation.dart';

import '../../nfc/domain/nfc_models.dart';
import '../data/card_repository.dart';
import '../domain/registered_card.dart';

/// Thrown when a card cannot be added or edited; [message] is user-facing.
class CardRuleException implements Exception {
  const CardRuleException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Loads, validates and saves registered cards. Every change is written to
/// the repository before the in-memory list is updated, so the UI never shows
/// a change that failed to save.
class CardsController extends ChangeNotifier {
  CardsController(this._repository);

  final CardRepository _repository;

  List<RegisteredCard> _cards = const [];
  bool loading = true;
  String? loadError;

  List<RegisteredCard> get cards => _cards;

  RegisteredCard? byId(String id) {
    for (final c in _cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  RegisteredCard? byFingerprint(String fingerprint) {
    for (final c in _cards) {
      if (c.fingerprint == fingerprint) return c;
    }
    return null;
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      _cards = await _repository.loadAll();
      loadError = null;
    } on CardStoreException catch (e) {
      loadError = e.message;
    }
    loading = false;
    notifyListeners();
  }

  Future<RegisteredCard> add({
    required String name,
    required String message,
    required String fingerprint,
    required CardCategory category,
    int style = 0,
  }) async {
    _validate(name: name, message: message);
    // Re-read from disk: the tap popup may have changed the file meanwhile.
    final current = await _repository.loadAll();
    for (final c in current) {
      if (c.fingerprint == fingerprint) {
        throw CardRuleException(
          'This card is already registered as "${c.name}".',
        );
      }
    }
    final card = RegisteredCard.create(
      name: name,
      fingerprint: fingerprint,
      category: category,
      message: message,
      style: style,
    );
    await _commit([...current, card]);
    return card;
  }

  Future<void> edit(
    String id, {
    required String name,
    required String message,
    int? style,
  }) {
    _validate(name: name, message: message);
    return _update(
      id,
      (c) => c.copyWith(name: name, message: message, style: style),
    );
  }

  /// Puts back a card removed by [delete] (for "Undo").
  Future<void> restore(RegisteredCard card) async {
    final current = await _repository.loadAll();
    if (current.any(
      (c) => c.id == card.id || c.fingerprint == card.fingerprint,
    )) {
      return;
    }
    await _commit([...current, card]);
  }

  Future<void> setEnabled(String id, bool enabled) =>
      _update(id, (c) => c.copyWith(enabled: enabled));

  Future<void> markTriggered(String id, {DateTime? at}) =>
      _update(id, (c) => c.copyWith(lastTriggeredAt: at ?? DateTime.now()));

  Future<void> delete(String id) async {
    final current = await _repository.loadAll();
    await _commit(current.where((c) => c.id != id).toList());
  }

  Future<void> _update(
    String id,
    RegisteredCard Function(RegisteredCard) change,
  ) async {
    final current = await _repository.loadAll();
    if (!current.any((c) => c.id == id)) {
      throw const CardRuleException('This card no longer exists.');
    }
    await _commit([for (final c in current) c.id == id ? change(c) : c]);
  }

  Future<void> _commit(List<RegisteredCard> next) async {
    await _repository.saveAll(next);
    _cards = next;
    loadError = null;
    notifyListeners();
  }

  void _validate({required String name, required String message}) {
    final error = CardValidation.name(name) ?? CardValidation.message(message);
    if (error != null) throw CardRuleException(error);
  }
}
