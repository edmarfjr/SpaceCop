import 'dart:math';

import '../chips/battle_chip.dart';
import '../chips/chip_library.dart';
import '../map/run_map.dart';
import '../rarity.dart';
import 'relics.dart';

/// Credits for winning a normal or elite battle.
const int battleCredits = 20;
const int eliteCredits = 40;

/// Créditos a new run starts with.
const int startCredits = 99;

/// Missions in a run: the capangas, the ruins' ETs, the Etéreos.
const int actCount = 3;

/// Share of the missing HP restored when a new act starts.
const double actHeal = 0.75;

/// Everything that persists between nodes of one run: HP, deck, map
/// position. Battles copy from here and write HP back when they end.
class RunState {
  RunState({Random? random}) : this._(random ?? Random());

  RunState._(this.random)
    : map = MapGenerator(random: random).generate(),
      deck = Chips.starterDeck();

  final Random random;

  /// The current act's map; a new one each act.
  RunMap map;

  /// 1 to [actCount].
  int act = 1;

  bool get lastAct => act == actCount;

  /// The permanent deck (StS "master deck").
  final List<ChipCard> deck;

  /// Lowered by implants (Enfermaria Clandestina).
  int maxHp = 100;
  int hp = 100;

  int credits = startCredits;

  /// The next battle's enemies start stunned this long (Refeitório dos
  /// Capangas); used up by that battle.
  int openingStunTicks = 0;

  /// Added to the base energy of every battle. Can go negative (events).
  int energyBaseBonus = 0;

  final List<RelicDef> relics = [];

  MapNode? current;

  bool hasRelic(RelicDef relic) => relics.contains(relic);

  List<MapNode> get availableNodes =>
      current == null ? map.startNodes : map.nextOf(current!);

  void enter(MapNode node) {
    assert(availableNodes.contains(node), 'node not reachable');
    node.visited = true;
    current = node;
  }

  /// The act's boss fell: on to the next act, with a new map and
  /// [actHeal] of the missing HP back.
  void nextAct() {
    assert(!lastAct, 'no act after the last');
    act++;
    map = MapGenerator(random: random).generate();
    current = null;
    hp += ((maxHp - hp) * actHeal).round();
  }

  /// Campfire: heal 30% of max HP.
  void rest() => hp = min(maxHp, hp + (maxHp * 0.3).round());

  /// Deck cards a campfire can upgrade.
  List<ChipCard> get upgradeable => [
    for (final card in deck)
      if (Chips.upgradeOf(card.def) != null) card,
  ];

  /// Campfire, instead of resting: swaps [card] for its "+" version.
  /// Returns false if it can't be upgraded.
  bool upgrade(ChipCard card) {
    final index = deck.indexOf(card);
    final up = Chips.upgradeOf(card.def);
    if (index < 0 || up == null) return false;
    deck[index] = ChipCard(up);
    return true;
  }

  /// Credits for a won battle; elites also drop a random relic, returned so
  /// the reward screen can show it.
  RelicDef? winBattle({required bool elite}) {
    credits += elite ? eliteCredits : battleCredits;
    if (!elite) return null;
    final relic = randomRelic();
    if (relic != null) relics.add(relic);
    return relic;
  }

  /// A relic the run doesn't own yet, optionally of one [kind], rarer ones
  /// less often.
  RelicDef? randomRelic({RelicKind? kind}) {
    final picked = rollRelics(1, kind: kind);
    return picked.isEmpty ? null : picked.single;
  }

  /// Up to [count] distinct relics the run doesn't own yet, by rarity.
  List<RelicDef> rollRelics(int count, {RelicKind? kind}) => pickByRarity(
    [
      for (final r in Relics.all)
        if (!relics.contains(r) && (kind == null || r.kind == kind)) r,
    ],
    (r) => r.rarity,
    count,
    random,
  );

  /// Picks [count] distinct chips to offer, by rarity; [elite] and Chip da
  /// Sorte roll rare ones more often, and a [boss] offers only rare ones.
  List<ChipDef> rollRewards(
    int count, {
    bool elite = false,
    bool boss = false,
  }) => pickByRarity(
    [
      for (final chip in Chips.all)
        if (!boss || chip.rarity == Rarity.rare) chip,
    ],
    (c) => c.rarity,
    count,
    random,
    elite: elite,
    lucky: hasRelic(Relics.luckyChip),
  );
}
