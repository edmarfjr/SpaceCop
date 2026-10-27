import 'dart:math';

import '../chips/battle_chip.dart';
import '../chips/chip_library.dart';
import '../map/run_map.dart';
import 'relics.dart';

/// Credits for winning a normal or elite battle.
const int battleCredits = 20;
const int eliteCredits = 40;

/// Créditos a new run starts with.
const int startCredits = 99;

/// Everything that persists between nodes of one run: HP, deck, map
/// position. Battles copy from here and write HP back when they end.
class RunState {
  RunState({Random? random}) : this._(random ?? Random());

  RunState._(this.random)
    : map = MapGenerator(random: random).generate(),
      deck = Chips.starterDeck();

  final Random random;
  final RunMap map;

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

  /// A relic the run doesn't own yet, optionally of one [kind].
  RelicDef? randomRelic({RelicKind? kind}) {
    final pool = [
      for (final r in Relics.all)
        if (!relics.contains(r) && (kind == null || r.kind == kind)) r,
    ];
    return pool.isEmpty ? null : pool[random.nextInt(pool.length)];
  }

  /// Picks [count] distinct chips to offer after a battle.
  List<ChipDef> rollRewards(int count) =>
      (List.of(Chips.all)..shuffle(random)).take(count).toList();
}
