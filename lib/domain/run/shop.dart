import '../chips/battle_chip.dart';
import 'relics.dart';
import 'run_state.dart';

/// Base prices by rarity, before Cartão de Sócio.
int chipPrice(Rarity rarity) => switch (rarity) {
  Rarity.common => 40,
  Rarity.uncommon => 65,
  Rarity.rare => 100,
};

int relicPrice(Rarity rarity) => switch (rarity) {
  Rarity.common => 110,
  Rarity.uncommon => 150,
  Rarity.rare => 200,
};

const int removalPrice = 75;

/// One visit to a shop node: 5 chips and 3 relics for sale, priced by
/// rarity, plus one chip removal. Cartão de Sócio takes 25% off and makes
/// the removal free.
class Shop {
  Shop(this.run) : chips = run.rollRewards(5), relics = run.rollRelics(3);

  final RunState run;

  /// Still for sale; bought items leave these.
  final List<ChipDef> chips;
  final List<RelicDef> relics;

  bool _removedHere = false;

  bool get _member => run.hasRelic(Relics.memberCard);

  int _price(int base) => _member ? (base * 0.75).round() : base;

  int chipCost(ChipDef def) => _price(chipPrice(def.rarity));
  int relicCost(RelicDef relic) => _price(relicPrice(relic.rarity));
  int get removalCost => _member ? 0 : _price(removalPrice);

  /// Only one card can be removed per visit.
  bool get canRemove => !_removedHere;

  bool _pay(int cost) {
    if (run.credits < cost) return false;
    run.credits -= cost;
    return true;
  }

  bool buyChip(ChipDef def) {
    if (!chips.contains(def) || !_pay(chipCost(def))) return false;
    chips.remove(def);
    run.deck.add(ChipCard(def));
    return true;
  }

  bool buyRelic(RelicDef relic) {
    if (!relics.contains(relic) || !_pay(relicCost(relic))) return false;
    relics.remove(relic);
    run.addRelic(relic);
    return true;
  }

  bool removeChip(ChipCard card) {
    if (!canRemove || !run.deck.contains(card) || !_pay(removalCost)) {
      return false;
    }
    run.deck.remove(card);
    _removedHere = true;
    return true;
  }
}
