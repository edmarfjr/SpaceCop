import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

void main() {
  test('Criogranada wets everyone in the cross and freezes the center', () {
    final battle = battleWith(
      [Chips.cryoGrenade],
      spawns: [dummyAt(4, 1), dummyAt(4, 0), dummyAt(5, 0)],
    );
    use(battle, Chips.cryoGrenade);
    final [center, side, outside] = battle.enemies;
    for (final hit in [center, side]) {
      expect(hit.hp, 90);
      expect(hit.has(Status.wet), isTrue);
    }
    expect(outside.has(Status.wet), isFalse);
    expect(battle.panelAt(const GridPos(4, 1)).state, PanelState.ice);
  });

  test('Pulso EMP hits the front column and drops front shields', () {
    final battle = battleWith(
      [Chips.emp, Chips.shot],
      spawns: [const EnemySpawn(Enemies.brute, GridPos(3, 1)), dummyAt(3, 0)],
    );
    final [brute, dummy] = battle.enemies;
    use(battle, Chips.emp);
    expect(
      brute.hp,
      Enemies.brute.hp - 10,
      reason: 'the shield stops shots, not the pulse',
    );
    expect(dummy.hp, 90);
    expect(brute.shieldDown, greaterThan(2 * ticksPerSecond));
    use(battle, Chips.shot);
    expect(brute.hp, Enemies.brute.hp - 10 - Chips.shot.damage);
  });

  test('Vinha Neural roots its target for 3 s', () {
    final battle = battleWith([Chips.neuralVine], spawns: [dummyAt(4, 1)]);
    final enemy = battle.enemies.single;
    use(battle, Chips.neuralVine);
    expect(enemy.hp, 85);
    expect(
      enemy.statuses[Status.rooted],
      greaterThan(3 * ticksPerSecond - playerAttackCooldown),
    );
  });

  test('Mira Laser marks: every hit on the target deals +5', () {
    final battle = battleWith(
      [Chips.laserSight, Chips.shot],
      spawns: [dummyAt(4, 1)],
    );
    final enemy = battle.enemies.single;
    use(battle, Chips.laserSight);
    expect(enemy.hp, 100, reason: 'the mark itself does no damage');
    expect(enemy.has(Status.marked), isTrue);
    use(battle, Chips.shot);
    expect(enemy.hp, 100 - Chips.shot.damage - markBonus);
    wait(battle, markTicks);
    expect(enemy.has(Status.marked), isFalse);
  });

  test('Sobrecarga: the next card counts twice in the chain', () {
    final battle = battleWith(
      [Chips.overcharge, Chips.vShot],
      spawns: [dummyAt(4, 1)],
    );
    use(battle, Chips.overcharge);
    expect(battle.chainSurge, isTrue);
    expect(battle.chainCount, 1, reason: 'Sobrecarga is Elec itself');
    use(battle, Chips.vShot);
    final enemy = battle.enemies.single;
    expect(enemy.hp, 100 - 2 * Chips.vShot.damage, reason: '3rd of the chain');
    expect(enemy.has(Status.stunned), isTrue);
    expect(battle.chainSurge, isFalse);
  });

  test('Feixe Trator pulls the whole row, then makes it collide', () {
    final battle = battleWith(
      [Chips.tractorBeam, Chips.tractorBeam],
      spawns: [dummyAt(4, 1), dummyAt(5, 1)],
    );
    final [front, back] = battle.enemies;
    use(battle, Chips.tractorBeam);
    expect(front.pos, const GridPos(3, 1));
    expect(back.pos, const GridPos(4, 1));
    expect(front.hp, 100);
    battle.energy = baseEnergy;
    use(battle, Chips.tractorBeam);
    expect(front.pos, const GridPos(3, 1));
    expect(front.hp, lessThan(100), reason: 'hit the edge of its side');
    expect(back.hp, lessThan(100), reason: 'ran into the front one');
  });

  test('Bobina Tesla zaps the first enemy of its row every second', () {
    final battle = battleWith([Chips.teslaCoil], spawns: [dummyAt(5, 1)]);
    use(battle, Chips.teslaCoil);
    final coil = battle.obstacles.single;
    expect(coil.kind, ObstacleKind.tesla);
    expect(coil.pos, const GridPos(2, 1), reason: 'front of the player side');
    final enemy = battle.enemies.single;
    wait(battle, ticksPerSecond);
    expect(enemy.hp, 100 - teslaZapDamage);
    wait(battle, teslaTicks);
    expect(battle.obstacles, isEmpty);
  });

  test('Bobina Tesla goes behind a player standing at the front', () {
    final battle = battleWith([Chips.teslaCoil], spawns: [dummyAt(5, 1)]);
    battle.player.pos = const GridPos(2, 1);
    use(battle, Chips.teslaCoil);
    expect(battle.obstacles.single.pos, const GridPos(1, 1));
  });

  test('Overclock runs the next card twice for the price of one', () {
    final battle = battleWith(
      [Chips.overclock, Chips.cannon],
      spawns: [dummyAt(4, 1)],
    );
    use(battle, Chips.overclock);
    expect(battle.overclocked, isTrue);
    use(battle, Chips.cannon);
    expect(battle.enemies.single.hp, 100 - 2 * Chips.cannon.damage);
    expect(battle.energy, baseEnergy - 1 - Chips.cannon.cost);
    expect(battle.overclocked, isFalse);
    expect(
      battle.deck.discardPile.map((c) => c.def),
      isNot(contains(Chips.overclock)),
    );
  });
}
