import 'dart:math';

import '../battle/enemies.dart';
import '../chips/battle_chip.dart';
import '../chips/chip_library.dart';
import '../map/run_map.dart';
import '../rarity.dart';
import 'events.dart';
import 'relics.dart';

/// Credits for winning a normal or elite battle.
const int battleCredits = 20;
const int eliteCredits = 40;

/// Créditos the Chip de Recompensa adds to each won battle.
const int rewardChipCredits = 10;

/// HP the Kit Médico heals after a won battle.
const int medKitHeal = 6;

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
    ).._rollBoss();
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
      ..jumps = json['jumps'] as int? ?? 0
      ..relics.addAll([
        for (final id in (json['relics']! as List).cast<String>())
          ?Relics.byId(id),
      ])
      ..drawnNormals.addAll(_ints(json['drawnNormals']))
      ..drawnElites.addAll(_ints(json['drawnElites']))
      ..drawnCards.addAll(_strings(json['drawnCards']))
      ..seenRelics.addAll(_strings(json['seenRelics']))
      ..seenEvents.addAll(_strings(json['seenEvents']));
    // Saves from before the pools have no boss yet.
    if (json['bossIndex'] case final int i
        when i < Encounters.bossesOf(run.act).length) {
      run.bossIndex = i;
    } else {
      run._rollBoss();
    }
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
    'jumps': jumps,
    'bossIndex': bossIndex,
    'drawnNormals': drawnNormals.toList(),
    'drawnElites': drawnElites.toList(),
    'drawnCards': drawnCards.toList(),
    'seenRelics': seenRelics.toList(),
    'seenEvents': seenEvents.toList(),
  };

  static Iterable<int> _ints(Object? list) =>
      (list as List?)?.cast<int>() ?? const [];

  static Iterable<String> _strings(Object? list) =>
      (list as List?)?.cast<String>() ?? const [];

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

  /// Propulsor de Salto: moves left that may go to any node of the next
  /// floor, off the paths.
  int jumps = 0;

  /// Choices a relic asked for when it was taken, shown one by one before
  /// anything else.
  final List<PickupStep> pending = [];

  /// This act's boss, an index into [Encounters.bossesOf]; picked with the
  /// map, so the map can show it.
  int bossIndex = 0;

  /// Basic enemies and elite fights drawn this act, as indices into the
  /// act's lists. Each is a bag: nothing repeats until all of it was drawn,
  /// then it starts over.
  final Set<int> drawnNormals = {};
  final Set<int> drawnElites = {};

  /// Ids of the cards offered so far; a rarity starts over when too few of
  /// it are left.
  final Set<String> drawnCards = {};

  /// Ids of the relics already offered, taken or not: never offered again.
  final Set<String> seenRelics = {};

  /// Titles of the events already visited: none repeats in a run. The
  /// third act draws from the first act's, so it gets the ones left.
  final Set<String> seenEvents = {};

  bool hasRelic(RelicDef relic) => relics.contains(relic);

  /// The next floor's nodes on the paths, or all of them while [jumps]
  /// are left.
  List<MapNode> get availableNodes {
    final from = current;
    if (from == null) return map.startNodes;
    final next = map.nextOf(from);
    if (jumps == 0) return next;
    final floor = [
      for (final n in map.usedNodes)
        if (n.floor == from.floor + 1) n,
    ];
    return floor.isEmpty ? next : floor;
  }

  void enter(MapNode node) {
    assert(availableNodes.contains(node), 'node not reachable');
    if (current case final from? when !map.nextOf(from).contains(node)) {
      jumps--;
    }
    node.visited = true;
    current = node;
  }

  /// The act's boss fell: on to the next act, with a new map and
  /// [actHeal] of the missing HP back.
  void nextAct() {
    assert(!lastAct, 'no act after the last');
    act++;
    map = MapGenerator(random: random).generate();
    drawnNormals.clear();
    drawnElites.clear();
    _rollBoss();
    current = null;
    hp += ((maxHp - hp) * actHeal).round();
  }

  void _rollBoss() =>
      bossIndex = random.nextInt(Encounters.bossesOf(act).length);

  /// The act's boss fight.
  Encounter get bossEncounter => Encounters.bossesOf(act)[bossIndex];

  /// The act's boss itself, for its map art.
  EnemyDef get boss => bossEncounter.spawns.first.def;

  /// A random index below [length] not in [drawn], which it joins; [drawn]
  /// starts over once every index is in it.
  int _draw(Set<int> drawn, int length) {
    if (drawn.length >= length) drawn.clear();
    final left = [
      for (var i = 0; i < length; i++)
        if (!drawn.contains(i)) i,
    ];
    final i = left[random.nextInt(left.length)];
    drawn.add(i);
    return i;
  }

  /// A normal fight, its enemies drawn from the act's bag.
  Encounter normalEncounter() {
    final pool = Enemies.basicsOf(act);
    return Encounters.normal(
      random,
      act: act,
      draw: () => pool[_draw(drawnNormals, pool.length)],
    );
  }

  /// An elite fight drawn from the act's bag.
  Encounter eliteEncounter() {
    final all = Encounters.elitesOf(act);
    return all[_draw(drawnElites, all.length)](random);
  }

  /// An event of the act not visited yet in the run; null if none is left.
  EventDef? drawEvent() {
    final left = [
      for (final event in Events.of(act))
        if (!seenEvents.contains(event.title)) event,
    ];
    if (left.isEmpty) return null;
    final event = left[random.nextInt(left.length)];
    seenEvents.add(event.title);
    return event;
  }

  /// Campfire: heal 30% of max HP.
  void rest() => hp = min(maxHp, hp + (maxHp * 0.3).round());

  /// A battle ended with the player at [hp]: the Kit Médico heals after a
  /// win, and a Núcleo Fênix that was [phoenixUsed] goes out.
  void endBattle(int hp, {required bool won, bool phoenixUsed = false}) {
    this.hp = hp;
    if (won && hasRelic(Relics.medKit)) {
      this.hp = min(maxHp, this.hp + medKitHeal);
    }
    if (phoenixUsed) relics.remove(Relics.phoenixCore);
  }

  /// Reator Instável forbids resting.
  bool get canRest => !hasRelic(Relics.unstableReactor);

  /// Every Créditos gain goes through here: none with Cofre Blindado.
  void gainCredits(int amount) {
    if (!hasRelic(Relics.armoredVault)) credits += amount;
  }

  /// Takes [relic], with its max HP change (a gain heals as much) and what
  /// it does once taken; choices it asks for wait in [pending].
  void addRelic(RelicDef relic) {
    relics.add(relic);
    maxHp = max(1, maxHp + relic.maxHp);
    hp = min(max(hp, hp + relic.maxHp), maxHp);
    relic.onPickup?.call(this);
  }

  /// A random card of the pool other than [def], for transforms.
  ChipDef transformed(ChipDef def) {
    final pool = [
      for (final c in Chips.all)
        if (c.id != def.id) c,
    ];
    return pool[random.nextInt(pool.length)];
  }

  /// Swaps [card] for [def] in the deck, in place.
  void replace(ChipCard card, ChipDef def) {
    final index = deck.indexOf(card);
    if (index >= 0) deck[index] = ChipCard(def);
  }

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
      if (!hasRelic(Relics.armoredVault))
        CreditsSpoil(
          (elite || boss ? eliteCredits : battleCredits) +
              (hasRelic(Relics.rewardChip) ? rewardChipCredits : 0),
        ),
      if (relic != null) RelicSpoil(relic),
      CardSpoil(
        rollRewards(
          hasRelic(Relics.etCrown) ? 2 : 3,
          elite: elite || boss,
          boss: boss,
        ),
      ),
      if (bossRelics.isNotEmpty) BossRelicSpoil(bossRelics),
    ];
  }

  /// Takes [spoil]; a [CardSpoil] needs the picked [card], a
  /// [BossRelicSpoil] the picked [relic].
  void claim(Spoil spoil, {ChipDef? card, RelicDef? relic}) {
    switch (spoil) {
      case CreditsSpoil(:final amount):
        gainCredits(amount);
      case RelicSpoil(:final relic):
        addRelic(relic);
      case CardSpoil():
        deck.add(ChipCard(card!));
      case BossRelicSpoil():
        addRelic(relic!);
    }
  }

  /// Relics the run doesn't own and was never offered.
  bool _relicLeft(RelicDef relic) =>
      !relics.contains(relic) && !seenRelics.contains(relic.id);

  /// Marks [offered] as seen and returns it.
  List<RelicDef> _offerRelics(List<RelicDef> offered) {
    seenRelics.addAll([for (final r in offered) r.id]);
    return offered;
  }

  /// Up to 3 boss relics the run doesn't own and was never offered.
  List<RelicDef> rollBossRelics() => _offerRelics(
    ([...Relics.boss.where(_relicLeft)]..shuffle(random)).take(3).toList(),
  );

  /// A relic the run doesn't own and was never offered, optionally of one
  /// [kind], rarer ones less often.
  RelicDef? randomRelic({RelicKind? kind}) {
    final picked = rollRelics(1, kind: kind);
    return picked.isEmpty ? null : picked.single;
  }

  /// Up to [count] distinct relics the run doesn't own and was never
  /// offered, by rarity. They count as offered from now on.
  List<RelicDef> rollRelics(int count, {RelicKind? kind}) => _offerRelics(
    pickByRarity(
      [
        for (final r in Relics.all)
          if (_relicLeft(r) && (kind == null || r.kind == kind)) r,
      ],
      (r) => r.rarity,
      count,
      random,
    ),
  );

  /// Picks [count] distinct chips to offer, by rarity, from those not
  /// offered yet; [elite] and Chip da Sorte roll rare ones more often, and
  /// a [boss] offers only rare ones.
  List<ChipDef> rollRewards(int count, {bool elite = false, bool boss = false}) {
    final pool = [
      for (final chip in Chips.all)
        if (!boss || chip.rarity == Rarity.rare) chip,
    ];
    for (final rarity in Rarity.values) {
      final ofRarity = [
        for (final chip in pool)
          if (chip.rarity == rarity) chip.id,
      ];
      if (ofRarity.where((id) => !drawnCards.contains(id)).length < count) {
        drawnCards.removeAll(ofRarity);
      }
    }
    final picked = pickByRarity(
      [
        for (final chip in pool)
          if (!drawnCards.contains(chip.id)) chip,
      ],
      (c) => c.rarity,
      count,
      random,
      elite: elite,
      lucky: hasRelic(Relics.luckyChip),
    );
    drawnCards.addAll([for (final chip in picked) chip.id]);
    return picked;
  }
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

/// One choice a relic asks for when it is taken.
sealed class PickupStep {
  const PickupStep(this.title);

  final String title;
}

/// Pick a card of the deck that passes [pickable], then [apply] it.
class DeckPickStep extends PickupStep {
  const DeckPickStep(super.title, this.apply, {this.pickable});

  final bool Function(ChipDef def)? pickable;
  final void Function(RunState run, ChipCard card) apply;

  List<ChipCard> cards(RunState run) => [
    for (final card in run.deck)
      if (pickable?.call(card.def) ?? true) card,
  ];
}

/// A card reward, like a battle's: one of [cards] for the deck, or none.
class CardRewardStep extends PickupStep {
  const CardRewardStep(super.title, this.cards);

  final List<ChipDef> cards;
}
