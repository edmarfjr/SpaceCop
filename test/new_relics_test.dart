import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/domain/run/events.dart';
import 'package:starcop/domain/run/relics.dart';
import 'package:starcop/domain/run/run_state.dart';

import 'battle_helpers.dart';

/// A battle with [relics] and a deck of [chips] (10 free shots by default);
/// the first tick (which draws the hand) has already run.
BattleState battleWithRelics(
  List<RelicDef> relics, {
  List<ChipDef>? chips,
  List<EnemySpawn>? spawns,
}) => BattleState(
  playerHp: 100,
  playerMaxHp: 100,
  deckCards: [
    for (final def in chips ?? List.filled(10, shotOf(Element.neutral)))
      ChipCard(def),
  ],
  encounter: Encounter(
    spawns ?? [EnemySpawn(dummyOf(Element.neutral), const GridPos(3, 1))],
  ),
  random: Random(5),
  relics: relics,
)..tick();

const use = PlayerInput(useChip: true);

void main() {
  test('the 14 new relics are in the pool, 3 common, 5 uncommon, 6 rare', () {
    final added = Relics.all.skip(23).take(14).toList();
    expect(added, hasLength(14));
    expect(added.where((r) => r.rarity == Rarity.common), hasLength(3));
    expect(added.where((r) => r.rarity == Rarity.uncommon), hasLength(5));
    expect(added.where((r) => r.rarity == Rarity.rare), hasLength(6));
  });

  test('Kit Médico heals 6 after a won battle only', () {
    final run = RunState(random: Random(1))..relics.add(Relics.medKit);
    run.endBattle(50, won: true);
    expect(run.hp, 56);
    run.endBattle(50, won: false);
    expect(run.hp, 50);
  });

  test('Capacete Tático takes 1 off every hit', () {
    final battle = battleWithRelics([Relics.helmet]);
    battle.damage(battle.player, 10);
    expect(battle.player.hp, 91);
  });

  test('Coldre Rápido: the first card of the battle is free', () {
    final card = ChipDef(
      id: 'test_costly',
      name: 'Cara',
      description: '',
      cost: 3,
      family: ChipFamily.tactical,
      type: ChipType.attack,
      target: ChipTarget.row,
      damage: 1,
      element: Element.neutral,
      effect: const ProjectileEffect(),
    );
    final battle = battleWithRelics([
      Relics.quickHolster,
    ], chips: List.filled(10, card));
    final energy = battle.energy;
    battle.tick(use);
    expect(battle.energy, energy);
    expect(battle.costOf(battle.hand.first), 3);
  });

  test('Umidificador: enemies start Molhados', () {
    final battle = battleWithRelics([Relics.humidifier]);
    expect(battle.enemies.single.has(Status.wet), isTrue);
  });

  test('Combustível Extra and Amplificador Elemental double statuses', () {
    final fuel = battleWithRelics([Relics.extraFuel]).enemies.single
      ..applyStatus(Status.burning, 30)
      ..applyStatus(Status.stunned, 30);
    expect(fuel.statuses[Status.burning], 60);
    expect(fuel.statuses[Status.stunned], 30);
    final both = battleWithRelics([
      Relics.extraFuel,
      Relics.elementalAmp,
    ]).enemies.single..applyStatus(Status.burning, 30);
    expect(both.statuses[Status.burning], 120);
  });

  test('Espinhos Reativos hurt the enemies next to the player', () {
    final battle = battleWithRelics(
      [Relics.reactiveSpikes],
      spawns: [EnemySpawn(dummyOf(Element.neutral), const GridPos(4, 1))],
    );
    final enemy = battle.enemies.single;
    enemy.pos = battle.player.pos + const GridPos(1, 0);
    battle.damage(battle.player, 10);
    expect(enemy.hp, 100 - spikesDamage);
  });

  test('Radar de Rota: "?" nodes never hide fights', () {
    final random = Random(2);
    for (var i = 0; i < 200; i++) {
      expect(
        rollUnknownRoom(random, noFights: true),
        isIn([UnknownRoom.event, UnknownRoom.shop]),
      );
    }
  });

  test('Chip de Recompensa: +10 Créditos per battle', () {
    final run = RunState(random: Random(1))..relics.add(Relics.rewardChip);
    final credits = run.battleSpoils(elite: false).first as CreditsSpoil;
    expect(credits.amount, battleCredits + rewardChipCredits);
  });

  test('Núcleo Fênix brings the player back once, then goes out', () {
    final battle = battleWithRelics([Relics.phoenixCore]);
    battle.damage(battle.player, 200);
    battle.tick();
    expect(battle.phase, BattlePhase.fighting);
    expect(battle.player.hp, 30);
    battle.damage(battle.player, 200);
    battle.tick();
    expect(battle.phase, BattlePhase.lost);
    final run = RunState(random: Random(1))..relics.add(Relics.phoenixCore);
    run.endBattle(30, won: true, phoenixUsed: battle.phoenixUsed);
    expect(run.relics, isEmpty);
  });

  test('Drone de Escolta shoots every 5 s', () {
    final battle = battleWithRelics([Relics.escortDrone]);
    wait(battle, droneEvery + 10);
    expect(battle.enemies.single.hp, 100 - droneDamage);
  });

  test('Gatilho Duplo: every 8 cards, the next runs twice', () {
    final battle = battleWithRelics([Relics.doubleTrigger])
      ..cardsUsed = doubleTriggerEvery - 2;
    battle.tick(use);
    expect(battle.overclocked, isFalse);
    wait(battle, playerAttackCooldown);
    battle.tick(use);
    expect(battle.overclocked, isTrue);
  });

  test('Placa de Absorção: 1 Energia on the first hit of each hand', () {
    final battle = battleWithRelics([Relics.absorbPlate]);
    final energy = battle.energy;
    battle.damage(battle.player, 5);
    battle.damage(battle.player, 5);
    expect(battle.energy, energy + 1);
  });

  test('Isolante Térmico: lava does not hurt the player', () {
    final battle = battleWithRelics([Relics.thermalInsulator]);
    battle.panelAt(battle.player.pos).state = PanelState.lava;
    wait(battle, 2 * ticksPerSecond);
    expect(battle.player.hp, 100);
  });
}
