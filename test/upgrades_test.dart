import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/domain/run/run_state.dart';

import 'battle_helpers.dart';

ChipDef up(ChipDef def) => Chips.upgradeOf(def)!;

void main() {
  test('every card but Bug has a "+" version that keeps its id', () {
    for (final def in [...Chips.all, Chips.cannon]) {
      final plus = up(def);
      expect(plus.id, def.id);
      expect(plus.name, '${def.name}+');
      expect(plus.upgraded, isTrue);
      expect(Chips.upgradeOf(plus), isNull, reason: 'only one upgrade');
    }
    expect(Chips.upgradeOf(Chips.bug), isNull);
  });

  test('upgrade table', () {
    expect(up(Chips.shot).damage, 10);
    expect(up(Chips.cannon).damage, 25);
    expect(up(Chips.shotgun).damage, 15);
    expect(up(Chips.vShot).damage, 15);
    expect(up(Chips.melta).damage, 15);
    expect(up(Chips.missile).damage, 20);
    expect(up(Chips.baton).damage, 15);
    expect(up(Chips.sword).damage, 30);
    expect(up(Chips.cracker).damage, 30);
    expect(up(Chips.bubblePush).damage, 15);
    expect(up(Chips.crossFlame).damage, 20);
    expect(up(Chips.energyDrink).cost, 0);
    expect(up(Chips.energyTank).cost, 1);
    expect(up(Chips.thunderLance).cost, 1);
    expect(up(Chips.seedGrass).cost, 0);
    expect(up(Chips.hook).cost, 0);
    expect(up(Chips.recover).exhaust, isTrue);
  });

  test('SMG+ fires 4 shots', () {
    final battle = battleWith([up(Chips.smg)], spawns: [dummyAt(3, 1)]);
    use(battle, up(Chips.smg));
    wait(battle, 10);
    expect(battle.enemies.single.hp, 100 - 4 * 5);
  });

  test('Cacetete+ stuns for 3 s', () {
    final battle = battleWith([up(Chips.baton)], spawns: [dummyAt(3, 1)]);
    battle.tick(const PlayerInput(dx: 1));
    wait(battle, playerMoveCooldown);
    use(battle, up(Chips.baton));
    expect(battle.enemies.single.hp, 85);
    expect(
      battle.enemies.single.statuses[Status.stunned],
      greaterThan(3 * ticksPerSecond - playerAttackCooldown - 2),
    );
  });

  test('Primeiros Socorros+ heals 10', () {
    final battle = battleWith([up(Chips.recover)]);
    battle.player.hp = 50;
    use(battle, up(Chips.recover));
    expect(battle.player.hp, 60);
  });

  test('Bala Oca+ adds 20', () {
    final battle = battleWith(
      [up(Chips.atkBoost), Chips.shot],
      spawns: [dummyAt(3, 1)],
    );
    use(battle, up(Chips.atkBoost));
    use(battle, Chips.shot);
    expect(battle.enemies.single.hp, 100 - 25);
  });

  test('Gerador+ speeds the gauge 30%', () {
    final battle = battleWith([up(Chips.powerGenerator)]);
    use(battle, up(Chips.powerGenerator));
    final before = battle.gauge;
    wait(battle, 100);
    expect(battle.gauge, before + 130);
  });

  test('Escudo de Energia+ lasts 8 s', () {
    final battle = battleWith([up(Chips.barrier)]);
    use(battle, up(Chips.barrier));
    expect(battle.player.barrierTicks, greaterThan(7 * ticksPerSecond));
  });

  test('Barricada+, Mina+, Drone+ and Escudo Refletor+ obstacles', () {
    final rock = battleWith([up(Chips.barricade)]);
    use(rock, up(Chips.barricade));
    expect(rock.barricades.single.hp, 60);

    final drone = battleWith([up(Chips.turret)]);
    use(drone, up(Chips.turret));
    expect(drone.obstacles.single.lifetime, 15 * ticksPerSecond);

    final reflector = battleWith([up(Chips.mirror)]);
    use(reflector, up(Chips.mirror));
    expect(reflector.obstacles.single.lifetime, 8 * ticksPerSecond);

    final mine = battleWith([up(Chips.mine)], spawns: [dummyAt(5, 2)]);
    use(mine, up(Chips.mine));
    final panels = [
      for (var x = playerColumns; x < gridColumns; x++)
        for (var y = 0; y < gridRows; y++) mine.panelAt(GridPos(x, y)),
    ];
    expect(panels.where((p) => p.mine).single.mineDamage, 60);
  });

  test('Avanço+ takes the column for 15 s and hits for 10', () {
    final battle = battleWith([up(Chips.areaSteal)], spawns: [dummyAt(3, 0)]);
    use(battle, up(Chips.areaSteal));
    expect(battle.enemies.single.hp, 90);
    wait(battle, 12 * ticksPerSecond);
    expect(battle.ownerAt(const GridPos(3, 1)), Team.player);
  });

  group('campfire', () {
    test('upgrading swaps the card for its "+" version, once', () {
      final run = RunState(random: Random(1));
      final card = run.deck.first;
      final base = card.def;
      expect(run.upgrade(card), isTrue);
      expect(run.deck, hasLength(10));
      expect(run.deck, isNot(contains(card)));
      final upgraded = run.deck.firstWhere((c) => c.def.upgraded);
      expect(upgraded.def, up(base));
      expect(run.upgrade(upgraded), isFalse);
      expect(run.upgradeable, isNot(contains(upgraded)));
    });

    test('Bug is never offered for upgrade', () {
      final run = RunState(random: Random(1));
      run.deck.add(ChipCard(Chips.bug));
      expect(run.upgradeable.map((c) => c.def), isNot(contains(Chips.bug)));
    });
  });
}
