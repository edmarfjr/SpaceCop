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
  factory RunState({Random? random}) {
    random ??= Random();
    return RunState._(
      random,
      MapGenerator(random: random).generate(),
      Chips.starterDeck(),
    );
  }

  RunState._(this.random, this.map, this.deck);

  /// A run saved with [toJson], between two nodes. Cards and relics that no
  /// longer exist are dropped.
  factory RunState.fromJson(Map<String, Object?> json, {Random? random}) {
    final run = RunState._(
      random ?? Random(),
      RunMap.fromJson(json['map']! as Map<String, Object?>),
      [
        for (final card in (json['deck']! as List).cast<Map>())
          if (Chips.byId(
                card['id'] as String,
                upgraded: card['upgraded'] as bool,
              )
              case final def?)
            ChipCard(def),
      ],
    );
    run
      ..act = json['act']! as int
      ..maxHp = json['maxHp']! as int
      ..hp = json['hp']! as int
      ..credits = json['credits']! as int
      ..openingStunTicks = json['openingStunTicks']! as int
      ..energyBaseBonus = json['energyBaseBonus']! as int
      ..nextBattleEnergy = json['nextBattleEnergy']! as int
      ..relics.addAll([
        for (final id in (json['relics']! as List).cast<String>())
          ?Relics.byId(id),
      ]);
    if (json['current'] case [final int floor, final int x]) {
      run.current = run.map.nodeAt(floor, x);
    }
    return run;
  }

  Map<String, Object?> toJson() => {
    'act': act,
    'maxHp': maxHp,
    'hp': hp,
    'credits': credits,
    'openingStunTicks': openingStunTicks,
    'energyBaseBonus': energyBaseBonus,
    'nextBattleEnergy': nextBattleEnergy,
    'deck': [
      for (final card in deck)
        {'id': card.def.id, 'upgraded': card.def.upgraded},
    ],
    'relics': [for (final relic in relics) relic.id],
    'current': switch (current) {
      final node? => [node.floor, node.x],
      null => null,
    },
    'map': map.toJson(),
  };

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

  /// Added to the next battle's base energy only (Festa da Colheita); used
  /// up by that battle.
  int nextBattleEnergy = 0;

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

  /// What a won battle leaves on the Espólios screen: Créditos, a card
  /// choice, a relic for an [elite], and a choice of 3 relics for a [boss]
  /// (which pays like an elite but drops no plain relic). Nothing is given
  /// until [claim]ed.
  List<Spoil> battleSpoils({required bool elite, bool boss = false}) {
    final relic = elite && !boss ? randomRelic() : null;
    final bossRelics = boss ? rollBossRelics() : const <RelicDef>[];
    return [
      CreditsSpoil(elite || boss ? eliteCredits : battleCredits),
      if (relic != null) RelicSpoil(relic),
      CardSpoil(rollRewards(3, elite: elite || boss, boss: boss)),
      if (bossRelics.isNotEmpty) BossRelicSpoil(bossRelics),
    ];
  }

  /// Takes [spoil]; a [CardSpoil] needs the picked [card], a
  /// [BossRelicSpoil] the picked [relic].
  void claim(Spoil spoil, {ChipDef? card, RelicDef? relic}) {
    switch (spoil) {
      case CreditsSpoil(:final amount):
        credits += amount;
      case RelicSpoil(:final relic):
        relics.add(relic);
      case CardSpoil():
        deck.add(ChipCard(card!));
      case BossRelicSpoil():
        relics.add(relic!);
    }
  }

  /// Up to 3 relics the run doesn't own yet for the boss reward: rare ones
  /// first, then uncommon and common ones if there aren't enough.
  List<RelicDef> rollBossRelics() => [
    for (final rarity in Rarity.values.reversed)
      ...([
        for (final r in Relics.all)
          if (r.rarity == rarity && !relics.contains(r)) r,
      ]..shuffle(random)),
  ].take(3).toList();

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

/// One item of the Espólios screen.
sealed class Spoil {
  const Spoil();
}

class CreditsSpoil extends Spoil {
  const CreditsSpoil(this.amount);

  final int amount;
}

/// An elite's relic.
class RelicSpoil extends Spoil {
  const RelicSpoil(this.relic);

  final RelicDef relic;
}

/// Opens the card choice; one of [cards] goes to the deck.
class CardSpoil extends Spoil {
  const CardSpoil(this.cards);

  final List<ChipDef> cards;
}

/// A boss's: opens the choice of one of [relics].
class BossRelicSpoil extends Spoil {
  const BossRelicSpoil(this.relics);

  final List<RelicDef> relics;
}
