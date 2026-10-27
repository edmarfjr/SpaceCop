import '../chips/battle_chip.dart';
import 'relics.dart';
import 'run_state.dart';

const int chipPrice = 50;
const int removalPrice = 75;
const int relicPrice = 150;

/// One visit to a shop node: 5 chips and 3 relics for sale, plus one chip
/// removal. Cartão de Sócio takes 25% off and makes the removal free.
class Shop {
  Shop(this.run)
    : chips = run.rollRewards(5),
      relics = [
        for (final r in Relics.all)
          if (!run.relics.contains(r)) r,
      ]..shuffle(run.random) {
    if (relics.length > 3) relics.removeRange(3, relics.length);
  }

  final RunState run;

  /// Still for sale; bought items leave these.
  final List<ChipDef> chips;
  final List<RelicDef> relics;

  bool _removedHere = false;

  bool get _member => run.hasRelic(Relics.memberCard);

  int _price(int base) => _member ? (base * 0.75).round() : base;

  int get chipCost => _price(chipPrice);
  int get relicCost => _price(relicPrice);
  int get removalCost => _member ? 0 : _price(removalPrice);

  /// Only one card can be removed per visit.
  bool get canRemove => !_removedHere;

  bool _pay(int cost) {
    if (run.credits < cost) return false;
    run.credits -= cost;
    return true;
  }

  bool buyChip(ChipDef def) {
    if (!chips.contains(def) || !_pay(chipCost)) return false;
    chips.remove(def);
    run.deck.add(ChipCard(def));
    return true;
  }

  bool buyRelic(RelicDef relic) {
    if (!relics.contains(relic) || !_pay(relicCost)) return false;
    relics.remove(relic);
    run.relics.add(relic);
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
