import '../chips/battle_chip.dart';
import 'relics.dart';
import 'run_state.dart';

const int chipPrice = 50;
const int removalPrice = 75;
const int relicPrice = 150;

/// One visit to a shop node: 3 chips and 1 relic for sale, plus chip
/// removal. Cartão de Sócio takes 25% off and makes the first removal free.
class Shop {
  Shop(this.run) : chips = run.rollRewards(3), relic = run.randomRelic();

  final RunState run;

  /// Still for sale; bought items leave these.
  final List<ChipDef> chips;
  RelicDef? relic;

  bool _removedHere = false;

  bool get _member => run.hasRelic(Relics.memberCard);

  int _price(int base) => _member ? (base * 0.75).round() : base;

  int get chipCost => _price(chipPrice);
  int get relicCost => _price(relicPrice);
  int get removalCost => _member && !_removedHere ? 0 : _price(removalPrice);

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

  bool buyRelic() {
    final item = relic;
    if (item == null || !_pay(relicCost)) return false;
    relic = null;
    run.relics.add(item);
    return true;
  }

  bool removeChip(ChipCard card) {
    if (!run.deck.contains(card) || !_pay(removalCost)) return false;
    run.deck.remove(card);
    _removedHere = true;
    return true;
  }
}
