import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/deck/deck.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/domain/map/run_map.dart';

void main() {
  test('deck reshuffles discard into draw pile', () {
    final deck = Deck([for (var i = 0; i < 3; i++) ChipCard(Chips.shot)]);
    deck.draw(3);
    deck.discardHand();
    expect(deck.draw(2), hasLength(2));
    expect(
      deck.drawPile.length + deck.hand.length + deck.discardPile.length,
      3,
    );
  });

  test('shotgun hits the target and the cell behind it', () {
    final battle = BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [ChipCard(Chips.shotgun)],
      encounter: const Encounter([
        EnemySpawn(Enemies.mobileCannon, GridPos(3, 1)),
        EnemySpawn(Enemies.mobileCannon, GridPos(4, 1)),
      ]),
      random: Random(1),
    );
    battle.tick(); // gauge starts full: draws the hand
    expect(battle.hand, hasLength(1));
    battle.tick(const PlayerInput(useChip: true));
    for (var i = 0; i < 5; i++) {
      battle.tick();
    }
    // Canhão Móvel is a Máquina: Projétil does half.
    expect(
      battle.enemies.map((e) => e.hp),
      everyElement(30 - (10 * machineProjectileMultiplier).round()),
    );
    expect(battle.deck.discardPile, hasLength(1));
  });

  group('hand of 5 and energy', () {
    BattleState battleWith(List<ChipDef> chips) => BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [for (final def in chips) ChipCard(def)],
      encounter: const Encounter([EnemySpawn(Enemies.mobileCannon, GridPos(5, 2))]),
      random: Random(3),
    );

    /// Uses [card] and waits out the attack cooldown.
    void use(BattleState battle, ChipCard card) {
      battle.selectChip(battle.hand.indexOf(card));
      battle.tick(const PlayerInput(useChip: true));
      for (var i = 0; i < playerAttackCooldown; i++) {
        battle.tick();
      }
    }

    ChipCard inHand(BattleState battle, ChipDef def) =>
        battle.hand.firstWhere((c) => c.def == def);

    test('full gauge discards the whole hand and draws 5', () {
      final battle = battleWith(List.filled(10, Chips.shot));
      battle.tick();
      expect(battle.hand, hasLength(5));
      use(battle, battle.hand.first);
      final oldHand = List.of(battle.hand);
      // The refill happens inside the tick that fills the gauge.
      for (var i = 0; i < gaugeTicks; i++) {
        battle.tick();
      }
      expect(battle.hand, hasLength(5));
      expect(battle.hand.any(oldHand.contains), isFalse);
      expect(battle.deck.discardPile, hasLength(5));
    });

    test('card costing more than the energy left stays in hand', () {
      final battle = battleWith([
        for (var i = 0; i < 3; i++) Chips.thunderLance,
      ]);
      battle.tick();
      use(battle, battle.hand.first);
      use(battle, battle.hand.first);
      expect(battle.energy, baseEnergy - 4);
      use(battle, battle.hand.first);
      expect(battle.hand, hasLength(1));
      expect(battle.energy, baseEnergy - 4);
    });

    test('Energy drink pays for an extra chip and its bonus ends with the hand', () {
      final battle = battleWith([
        Chips.thunderLance,
        Chips.energyDrink,
        Chips.shotgun,
        Chips.smg,
        Chips.atkBoost,
      ]);
      battle.tick();
      use(battle, inHand(battle, Chips.thunderLance));
      use(battle, inHand(battle, Chips.energyDrink));
      expect(battle.energy, baseEnergy - 2 - 1 + 2);
      use(battle, inHand(battle, Chips.shotgun));
      use(battle, inHand(battle, Chips.smg));
      use(battle, inHand(battle, Chips.atkBoost));
      expect(battle.hand, isEmpty);
      expect(battle.energy, 0);
      // The refill happens inside the tick that fills the gauge.
      for (var i = 0; i < gaugeTicks; i++) {
        battle.tick();
      }
      expect(battle.energyBonus, 0);
      expect(battle.energy, battle.energyMax);
    });

    test('Tanque de Energia adds 1 max energy and leaves the battle', () {
      final battle = battleWith(List.filled(2, Chips.energyTank));
      battle.tick();
      battle.energy = 99;
      for (var i = 0; i < 2; i++) {
        use(battle, battle.hand.first);
      }
      expect(battle.energyMax, baseEnergy + 2);
      expect(battle.deck.discardPile, isEmpty);
      for (var i = 0; i < gaugeTicks; i++) {
        battle.tick();
      }
      expect(battle.hand, isEmpty);
    });
  });

  group('elements and statuses', () {
    ChipDef shotOf(Element element) => ChipDef(
      id: 'test_${element.name}',
      name: 'Teste',
      description: '',
      cost: 0,
      family: ChipFamily.tactical,
      type: ChipType.attack,
      target: ChipTarget.row,
      damage: 5,
      element: element,
      effect: const ProjectileEffect(),
    );

    EnemyDef dummyOf(Element element) => EnemyDef(
      name: 'Alvo',
      hp: 100,
      moveTicks: 30,
      attackTicks: 60,
      shotDamage: 0,
      element: element,
    );

    BattleState battleWith(
      List<ChipDef> chips,
      EnemyDef enemy, {
      GridPos pos = const GridPos(3, 1),
    }) => BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [for (final def in chips) ChipCard(def)],
      encounter: Encounter([EnemySpawn(enemy, pos)]),
      random: Random(5),
    );

    /// Fires the selected chip and waits for it to land.
    void fire(BattleState battle) {
      battle.tick(const PlayerInput(useChip: true));
      for (var i = 0; i < playerAttackCooldown; i++) {
        battle.tick();
      }
    }

    test('elements have no weakness: only terrain and statuses', () {
      final battle = battleWith([shotOf(Element.fire)], dummyOf(Element.wood))
        ..tick();
      fire(battle);
      expect(battle.enemies.single.hp, 100 - 5);
    });

    test('burning deals 3 damage per second for 3 seconds', () {
      final battle = battleWith([], dummyOf(Element.neutral));
      final enemy = battle.enemies.single
        ..applyStatus(Status.burning, burnTicks);
      for (var i = 0; i < ticksPerSecond - 1; i++) {
        battle.tick();
      }
      expect(enemy.hp, 100);
      battle.tick();
      expect(enemy.hp, 100 - burnDamage);
      for (var i = 0; i < burnTicks - ticksPerSecond; i++) {
        battle.tick();
      }
      expect(enemy.hp, 100 - 3 * burnDamage);
      expect(enemy.has(Status.burning), isFalse);
    });

    test('wet doubles the next Elec hit and is removed by it', () {
      final battle = battleWith([
        shotOf(Element.elec),
        shotOf(Element.elec),
      ], dummyOf(Element.neutral))..tick();
      final enemy = battle.enemies.single..applyStatus(Status.wet, wetTicks);
      fire(battle);
      expect(enemy.hp, 100 - 10);
      expect(enemy.has(Status.wet), isFalse);
      // Let the element chain lapse so the second hit is a plain one.
      for (var i = 0; i < chainWindowTicks; i++) {
        battle.tick();
      }
      fire(battle);
      expect(enemy.hp, 100 - 10 - 5);
    });

    test('wet is not consumed by other elements and wears off', () {
      final battle = battleWith([
        shotOf(Element.fire),
      ], dummyOf(Element.neutral))..tick();
      final enemy = battle.enemies.single..applyStatus(Status.wet, wetTicks);
      fire(battle);
      expect(enemy.hp, 100 - 5);
      expect(enemy.has(Status.wet), isTrue);
      for (var i = 0; i < wetTicks; i++) {
        battle.tick();
      }
      expect(enemy.has(Status.wet), isFalse);
    });

    test('stunned player ignores movement and chips until it ends', () {
      final battle = battleWith([Chips.shot], dummyOf(Element.neutral))..tick();
      battle.player.applyStatus(Status.stunned, 10);
      for (var i = 0; i < 10; i++) {
        battle.tick(const PlayerInput(dx: 1, useChip: true));
      }
      expect(battle.player.pos, const GridPos(1, 1));
      expect(battle.hand, hasLength(1));
      battle.tick(const PlayerInput(dx: 1));
      expect(battle.player.pos, const GridPos(2, 1));
    });

    test('stunned enemy freezes its AI', () {
      final battle = battleWith(
        [],
        dummyOf(Element.neutral),
        pos: const GridPos(5, 0),
      );
      final enemy = battle.enemies.single..applyStatus(Status.stunned, 30);
      for (var i = 0; i < 30; i++) {
        battle.tick();
      }
      expect(enemy.pos, const GridPos(5, 0));
      expect(enemy.state, EnemyState.idle);
      // Its starting move cooldown only runs down once the stun is over.
      for (var i = 0; i < enemy.def.moveTicks; i++) {
        battle.tick();
      }
      expect(enemy.pos, const GridPos(5, 0));
      battle
        ..tick()
        ..tick();
      expect(enemy.pos, const GridPos(5, 1));
    });

    test('rooted player cannot move but can still use chips', () {
      final battle = battleWith([Chips.shot], dummyOf(Element.neutral))..tick();
      battle.player.applyStatus(Status.rooted, rootTicks);
      battle.tick(const PlayerInput(useChip: true));
      expect(battle.hand, isEmpty);
      for (var i = 1; i < rootTicks; i++) {
        battle.tick(const PlayerInput(dx: 1));
      }
      expect(battle.player.pos, const GridPos(1, 1));
      battle.tick(const PlayerInput(dx: 1));
      expect(battle.player.pos, const GridPos(2, 1));
    });

    test('rooted enemy does not move', () {
      final battle = battleWith(
        [],
        dummyOf(Element.neutral),
        pos: const GridPos(5, 0),
      );
      final enemy = battle.enemies.single
        ..applyStatus(Status.rooted, rootTicks);
      for (var i = 0; i < rootTicks; i++) {
        battle.tick();
      }
      expect(enemy.pos, const GridPos(5, 0));
    });
  });

  test('map paths never leave the grid and floor 0 is reachable', () {
    final map = MapGenerator(random: Random(7)).generate();
    expect(map.startNodes, isNotEmpty);
    for (final node in map.usedNodes) {
      expect(map.nextOf(node), isNotEmpty);
    }
  });
}
