import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

void main() {
  test('free cells on the same side are crossed step by step', () {
    final battle = battleWith([], spawns: [dummyAt(3, 1)]);
    final enemy = battle.enemies.single;
    battle.displace(enemy, 1, 0, 2);
    expect(enemy.pos, const GridPos(5, 1));
    expect(enemy.hp, 100);
  });

  test('an occupied cell makes both units collide', () {
    final battle = battleWith([], spawns: [dummyAt(3, 1), dummyAt(4, 1)]);
    final [front, back] = battle.enemies;
    battle.displace(front, 1, 0, 2);
    expect(front.pos, const GridPos(3, 1));
    for (final enemy in [front, back]) {
      expect(enemy.hp, 100 - collisionDamage);
      expect(enemy.has(Status.stunned), isTrue);
    }
  });

  test('the grid edge and the side border are walls', () {
    final battle = battleWith([], spawns: [dummyAt(5, 1)]);
    final enemy = battle.enemies.single;
    battle.displace(enemy, 1, 0, 1);
    expect(enemy.pos, const GridPos(5, 1));
    expect(enemy.hp, 100 - collisionDamage);
    expect(enemy.has(Status.stunned), isTrue);

    battle.player.pos = const GridPos(2, 0);
    battle.displace(battle.player, 1, 0, 1);
    expect(battle.player.pos, const GridPos(2, 0));
    expect(battle.player.hp, 100 - collisionDamage);
  });

  test('a unit pushed into a hole falls back to where it started', () {
    final battle = battleWith([], spawns: [dummyAt(3, 1)])
      ..setPanel(const GridPos(4, 1), PanelState.hole);
    final enemy = battle.enemies.single;
    battle.displace(enemy, 1, 0, 2);
    expect(enemy.pos, const GridPos(3, 1));
    expect(enemy.hp, 100 - fallDamage);
    expect(enemy.statuses[Status.stunned], fallStunTicks);
  });

  test('ice keeps the unit sliding and the stop is resolved normally', () {
    final battle = battleWith([], spawns: [dummyAt(3, 1)])
      ..setPanel(const GridPos(4, 1), PanelState.ice);
    final enemy = battle.enemies.single;
    battle.displace(enemy, 1, 0, 1);
    expect(enemy.pos, const GridPos(5, 1));
    expect(enemy.hp, 100 - collisionDamage);
  });

  test('pull drags the target to column 3, or stuns it if already there', () {
    final battle = battleWith(
      [Chips.hook, Chips.hook],
      spawns: [dummyAt(5, 1)],
    );
    final enemy = battle.enemies.single;
    use(battle, Chips.hook);
    expect(enemy.pos, const GridPos(3, 1));
    expect(enemy.has(Status.stunned), isFalse);
    use(battle, Chips.hook);
    expect(enemy.pos, const GridPos(3, 1));
    expect(enemy.has(Status.stunned), isTrue);
  });
}
