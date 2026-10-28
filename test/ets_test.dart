import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/enemy_behaviors.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

Set<GridPos> warned(BattleState battle) => {
  for (final t in battle.telegraphs) t.pos,
};

BattleState facing(
  EnemyDef def,
  GridPos pos, [
  List<ChipDef> chips = const [],
]) => battleWith(chips, spawns: [EnemySpawn(def, pos)]);

/// Ticks until [done] holds, at most [limit].
void until(BattleState battle, bool Function() done, {int limit = 600}) {
  for (var i = 0; i < limit && !done(); i++) {
    battle.tick();
  }
  expect(done(), isTrue, reason: 'never happened');
}

void main() {
  test('ET Guerreiro slashes the player panel and the one behind it', () {
    final battle = facing(Enemies.etWarrior, const GridPos(4, 1));
    until(battle, () => battle.enemies.single.stage != 0);
    expect(warned(battle), {const GridPos(1, 1), const GridPos(0, 1)});
    until(battle, () => battle.player.hp < 100);
    expect(battle.player.hp, 100 - GruntMeleeBehavior.damage);
  });

  test('ET Guerreiro runs from the player for half its cooldown', () {
    final battle = facing(Enemies.etWarrior, const GridPos(3, 1));
    final et = battle.enemies.single
      ..pos = const GridPos(3, 1)
      ..timer = GruntMeleeBehavior.cycleTicks;
    wait(battle, 2 * 20 + 5);
    expect(et.pos.y, isNot(1));
    expect(et.pos.x, greaterThanOrEqualTo(4));
  });

  test('ET Atirador lines up to shoot, then runs away', () {
    final battle = facing(Enemies.etGunner, const GridPos(3, 1));
    final et = battle.enemies.single..pos = const GridPos(3, 1);
    wait(battle, 2 * 20 + 5);
    expect(et.pos.y, isNot(1), reason: 'fleeing at the start of its cooldown');
    until(battle, () => battle.player.hp < 100);
    expect(battle.player.hp, 100 - Enemies.etGunner.shotDamage);
  });

  group('ET Emboscador', () {
    final shot = shotOf(Element.neutral, family: ChipFamily.projectile);
    final blast = shotOf(Element.neutral, family: ChipFamily.explosive);

    test('burrowed, only Explosivo hurts it and shots fly over', () {
      final battle = battleWith(
        [shot, blast],
        spawns: [
          const EnemySpawn(Enemies.etTrap, GridPos(3, 1)),
          dummyAt(5, 1),
        ],
      );
      final [trap, behind] = battle.enemies;
      trap
        ..pos = const GridPos(3, 1)
        ..applyStatus(Status.stunned, 100000);
      use(battle, shot);
      wait(battle, 5);
      expect(trap.hp, Enemies.etTrap.hp);
      expect(behind.hp, 90, reason: 'the shot flew over the trap');
      use(battle, blast);
      expect(trap.hp, Enemies.etTrap.hp - boom(10));
    });

    test('bursts out on the player panel, stays exposed 1 s, goes home', () {
      final battle = facing(Enemies.etTrap, const GridPos(4, 1));
      final trap = battle.enemies.single;
      until(battle, () => trap.stage == 1);
      final home = trap.home;
      expect(warned(battle), {const GridPos(1, 1)});
      until(battle, () => trap.stage == 2);
      expect(battle.player.hp, 100 - TrapBehavior.damage);
      expect(battle.player.pos, const GridPos(0, 1), reason: 'pushed off');
      expect(trap.pos, const GridPos(1, 1));
      expect(trap.burrowed, isFalse);
      expect(trap.attackFrame, isTrue);
      wait(battle, TrapBehavior.exposedTicks + 2);
      expect(trap.burrowed, isTrue);
      expect(trap.pos, home);
    });
  });

  test('ET Xamã leaves a sphere that fires 3 mortars and fades', () {
    final battle = facing(Enemies.etShaman, const GridPos(4, 1));
    final shaman = battle.enemies.single;
    until(battle, () => battle.enemies.length == 2);
    final sphere = battle.enemies.last;
    expect(sphere.def, Enemies.energySphere);
    expect(shaman.pos, isNot(sphere.pos));
    until(battle, () => !battle.enemies.contains(sphere));
    expect(battle.player.hp, 100 - 3 * SphereBehavior.damage);
  });

  test('ET Montado only charges down the row', () {
    final battle = facing(Enemies.etRider, const GridPos(4, 0));
    until(battle, () => battle.player.hp < 100);
    expect(battle.player.hp, 100 - TankBehavior.chargeDamage);
  });

  test('Esfera de Energia is a Máquina: Energia does double', () {
    final zap = shotOf(Element.neutral, family: ChipFamily.energy);
    final battle = battleWith([zap], spawns: [dummyAt(5, 2)]);
    final sphere = battle.summon(Enemies.energySphere, const GridPos(3, 1))
      ..applyStatus(Status.stunned, 100000);
    use(battle, zap);
    expect(sphere.isDead, isTrue, reason: '20 HP, hit for 20');
  });
}
