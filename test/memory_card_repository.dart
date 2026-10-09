import 'package:nfcpin/features/cards/data/card_repository.dart';
import 'package:nfcpin/features/cards/domain/registered_card.dart';

class MemoryCardRepository implements CardRepository {
  List<RegisteredCard> stored = [];
  int saves = 0;
  bool failSaves = false;

  @override
  Future<List<RegisteredCard>> loadAll() async => List.of(stored);

  @override
  Future<void> saveAll(List<RegisteredCard> cards) async {
    if (failSaves) throw const CardStoreException('disk full');
    saves++;
    stored = List.of(cards);
  }
}
