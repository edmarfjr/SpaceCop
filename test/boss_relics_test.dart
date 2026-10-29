import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/enemy_behaviors.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/domain/run/events.dart';
import 'package:starcop/domain/run/relics.dart';
import 'package:starcop/domain/run/run_state.dart';

import 'battle_helpers.dart';

/// A battle with [relics], 10 test shots in the deck; the first tick (which
/// draws the hand) has already run.
BattleState battleWithRelics(
  List<RelicDef> relics, {
  List<EnemySpawn>? spawns,
}) => BattleState(
  playerHp: 100,
  playerMaxHp: 100,
  deckCards: [for (var i = 0; i < 10; i++) ChipCard(shotOf(Element.neutral))],
  encounter: Encounter(
    spawns ?? [EnemySpawn(dummyOf(Element.neutral), const GridPos(3, 1))],
  ),
  random: Random(5),
  relics: relics,
)..tick();

void main() {
  test('a boss offers 3 distinct boss relics the run does not own', () {
    final run = RunState(random: Random(3))..relics.add(Relics.etCrown);
    for (var i = 0; i < 20; i++) {
      final offered = run.rollBossRelics();
      expect(offered, hasLength(3));
      expect(offered.toSet(), hasLength(3));
      expect(offered, isNot(contains(Relics.etCrown)));
      expect(offered.every(Relics.boss.contains), isTrue);
    }
    for (final relic in Relics.boss) {
      expect(Relics.all, isNot(contains(relic)), reason: 'boss only');
    }
  });

  test('a saved run keeps its boss relics', () {
    final run = RunState(random: Random(4))..relics.add(Relics.combatVisor);
    final loaded = RunState.fromJson(
      jsonDecode(jsonEncode(run.toJson())) as Map<String, Object?>,
    );
    expect(loaded.relics, [Relics.combatVisor]);
  });

  test('Reator Instável: no resting', () {
    final run = RunState(random: Random(1));
    expect(run.canRest, isTrue);
    run.relics.add(Relics.unstableReactor);
    expect(run.canRest, isFalse);
  });

  test('Coroa do Rei ET: 2 cards in a battle reward', () {
    final run = RunState(random: Random(1))..relics.add(Relics.etCrown);
    final cards = run.battleSpoils(elite: false).whereType<CardSpoil>().single;
    expect(cards.cards, hasLength(2));
  });

  test('Cofre Blindado: no Créditos from battles or events', () {
    final run = RunState(random: Random(1))..relics.add(Relics.armoredVault);
    final credits = run.credits;
    expect(run.battleSpoils(elite: true), isNot(contains(isA<CreditsSpoil>())));
    run.gainCredits(50);
    Events.armory.options[1].apply(run, run.deck.first);
    expect(run.credits, credits);
  });

  test('Visor de Combate costs 15 max HP when taken', () {
    final run = RunState(random: Random(1));
    final spoil = BossRelicSpoil([Relics.combatVisor]);
    run.claim(spoil, relic: Relics.combatVisor);
    expect(run.maxHp, 85);
    expect(run.hp, 85);
  });

  test('the energy boss relics add 1 base Energia', () {
    for (final relic in [
      Relics.unstableReactor,
      Relics.etCrown,
      Relics.heavyExoskeleton,
      Relics.armoredVault,
    ]) {
      expect(battleWithRelics([relic]).energyMax, baseEnergy + 1);
    }
  });

  test('Exoesqueleto Pesado: slower steps', () {
    final battle = battleWithRelics([Relics.heavyExoskeleton]);
    battle.tick(const PlayerInput(dy: 1));
    expect(battle.player.pos, const GridPos(1, 2));
    expect(battle.player.moveCooldown, heavyMoveCooldown);
  });

  test('Implante Neural: 6 cards a hand, a slower gauge', () {
    final battle = battleWithRelics([Relics.neuralImplant]);
    expect(battle.hand, hasLength(handSize + 1));
    wait(battle, 100);
    expect(battle.gauge, 75);
    expect(battleWith([]).gauge, 0, reason: 'without it, unchanged');
  });

  group('readiness, for the Visor de Combate', () {
    test('a cycle enemy fills up to its attack', () {
      final battle = battleWithRelics(
        [],
        spawns: [const EnemySpawn(Enemies.etWarrior, GridPos(4, 1))],
      );
      final enemy = battle.enemies.single;
      final behavior = enemy.def.behavior;
      expect(behavior.readiness(enemy), isNotNull);
      final start = behavior.readiness(enemy)!;
      wait(battle, 30);
      expect(behavior.readiness(enemy), greaterThan(start));
    });

    test("the Coronel's bar is full the tick before he attacks", () {
      final battle = battleWithRelics(
        [],
        spawns: [const EnemySpawn(Enemies.colonel, GridPos(5, 1))],
      );
      final colonel = battle.enemies.single..moveTimer = 100000;
      final behavior = colonel.def.behavior;
      var before = 0.0;
      for (var i = 0; i < 300 && battle.telegraphs.isEmpty; i++) {
        before = behavior.readiness(colonel)!;
        battle.tick();
      }
      expect(battle.telegraphs, isNotEmpty);
      expect(before, closeTo(1, 0.05));
      expect(behavior.readiness(colonel), 1, reason: 'full while attacking');
    });

    test('summoned parts and idle units show no bar', () {
      expect(
        const IdleBehavior().readiness(
          EnemyFighter(Enemies.serpentBody, const GridPos(4, 0)),
        ),
        isNull,
      );
    });
  });
}
