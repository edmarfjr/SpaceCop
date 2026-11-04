import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

BattleState withDummies(List<GridPos> enemies, List<ChipDef> chips) =>
    battleWith(chips, spawns: [for (final p in enemies) dummyAt(p.x, p.y)]);

Obstacle? spearAt(BattleState battle, GridPos pos) => battle.obstacles
    .where((o) => o.kind == ObstacleKind.spear && o.pos == pos && !o.isDead)
    .firstOrNull;

void main() {
  group('Lança', () {
    test('pushes the target back and sticks where it stood', () {
      final battle = withDummies([const GridPos(3, 1)], [Chips.spear]);
      use(battle, Chips.spear);
      final enemy = battle.enemies.single;
      expect(enemy.hp, 100 - Chips.spear.damage);
      expect(enemy.pos, const GridPos(4, 1));
      expect(spearAt(battle, const GridPos(3, 1)), isNotNull);
    });

    test('at the back, the target hits the wall and is thrown forward', () {
      final battle = withDummies([const GridPos(5, 1)], [Chips.spear]);
      use(battle, Chips.spear);
      final enemy = battle.enemies.single;
      expect(enemy.hp, 100 - Chips.spear.damage - collisionDamage);
      expect(enemy.pos, const GridPos(4, 1));
      expect(spearAt(battle, const GridPos(5, 1)), isNotNull);
    });

    test('a miss sticks in the last panel of the row', () {
      final battle = withDummies([const GridPos(4, 0)], [Chips.spear]);
      use(battle, Chips.spear);
      expect(spearAt(battle, const GridPos(5, 1)), isNotNull);
    });

    test('blocks enemies, lets shots through, and lasts 8 s', () {
      final battle = withDummies(
        [const GridPos(3, 1)],
        [Chips.spear, Chips.shot],
      );
      use(battle, Chips.spear);
      final enemy = battle.enemies.single;
      final spear = spearAt(battle, const GridPos(3, 1))!;
      expect(battle.canEnter(enemy, const GridPos(3, 1)), isFalse);
      // Back in front of the spear: the shot flies past it.
      enemy.pos = const GridPos(4, 1);
      final before = enemy.hp;
      use(battle, Chips.shot);
      wait(battle, 5);
      expect(enemy.hp, lessThan(before));
      expect(spear.isDead, isFalse);
      wait(battle, spearTicks);
      expect(spearAt(battle, const GridPos(3, 1)), isNull);
    });

    test('upgraded deals 15', () {
      expect(Chips.byId('spear', upgraded: true)!.damage, 15);
    });
  });

  test('Canhão: a plain Energia shot for 15, 25 upgraded', () {
    final battle = withDummies([const GridPos(3, 1)], [Chips.energyCannon]);
    use(battle, Chips.energyCannon);
    expect(battle.enemies.single.hp, 85);
    expect(Chips.energyCannon.family, ChipFamily.energy);
    expect(Chips.energyCannon.cost, 2);
    expect(Chips.byId('energy_cannon', upgraded: true)!.damage, 25);
  });

  group('Arma de Haste', () {
    test('hits 2 panels and pushes only the far one', () {
      final battle = withDummies(
        [const GridPos(3, 1), const GridPos(4, 1)],
        [Chips.polearm],
      );
      final [near, far] = battle.enemies;
      battle.player.pos = const GridPos(2, 1);
      use(battle, Chips.polearm);
      expect(near.hp, 85);
      expect(far.hp, 85);
      expect(near.pos, const GridPos(3, 1));
      expect(far.pos, const GridPos(5, 1));
    });

    test('upgraded deals 20', () {
      expect(Chips.byId('polearm', upgraded: true)!.damage, 20);
    });
  });
}
