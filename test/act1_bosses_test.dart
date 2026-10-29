import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/enemy_behaviors.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

Set<GridPos> warned(BattleState battle) => {
  for (final t in battle.telegraphs) t.pos,
};

/// Ticks until [done] holds, at most [limit].
void until(BattleState battle, bool Function() done, {int limit = 900}) {
  for (var i = 0; i < limit && !done(); i++) {
    battle.tick();
  }
  expect(done(), isTrue, reason: 'never happened');
}

void main() {
  test('the first mission draws one of 3 bosses', () {
    final random = Random(1);
    final bosses = {
      for (var i = 0; i < 60; i++) Encounters.boss(random).spawns.first.def,
    };
    expect(bosses, {Enemies.tank, Enemies.colonel, Enemies.argos});
  });

  group('Coronel Inimigo', () {
    /// The Coronel alone (no guards), about to pick attack [index].
    (BattleState, EnemyFighter) colonelAbout(int index) {
      final battle = battleWith(
        [],
        spawns: [const EnemySpawn(Enemies.colonel, GridPos(5, 1))],
      );
      final colonel = battle.enemies.single
        ..attackTimer = index
        ..timer = 0;
      return (battle, colonel);
    }

    test('Rajada sweeps the columns, sparing a row in each, then reloads', () {
      final (battle, colonel) = colonelAbout(0);
      battle.tick();
      final cells = warned(battle);
      expect(cells, hasLength(6));
      for (var x = 0; x < 3; x++) {
        expect(cells.where((c) => c.x == x), hasLength(2));
      }
      expect(colonel.pose, ColonelBehavior.shootPose);
      until(battle, () => colonel.exposedTicks > 0);
      expect(colonel.pose, ColonelBehavior.shootPose);
      battle.tick();
      expect(colonel.pose, ColonelBehavior.reloadPose);
      final before = colonel.hp;
      battle.damage(colonel, 10);
      expect(colonel.hp, before - 20, reason: 'double damage while reloading');
    });

    test('Contrato hits the panel the player stood on', () {
      final (battle, colonel) = colonelAbout(1);
      battle.tick();
      expect(warned(battle), {battle.player.pos});
      expect(colonel.pose, ColonelBehavior.radioPose);
      wait(battle, ColonelBehavior.contractWarn);
      expect(battle.player.hp, 100 - ColonelBehavior.contractDamage);
    });

    test('Coquetel Molotov turns a cross around the player to lava', () {
      final (battle, colonel) = colonelAbout(2);
      final center = battle.player.pos;
      battle.tick();
      expect(warned(battle), {
        center,
        center + const GridPos(1, 0),
        center + const GridPos(-1, 0),
        center + const GridPos(0, 1),
        center + const GridPos(0, -1),
      });
      expect(colonel.pose, ColonelBehavior.throwPose);
      wait(battle, ColonelBehavior.molotovWarn);
      expect(battle.panelAt(center).state, PanelState.lava);
      expect(battle.player.hp, lessThan(100));
    });

    test('a fallen Guarda-costas comes back, and they do not keep the '
        'fight going', () {
      final battle = battleWith(
        [],
        spawns: [
          const EnemySpawn(Enemies.colonel, GridPos(5, 1)),
          const EnemySpawn(Enemies.colonelGuard, GridPos(4, 0)),
          const EnemySpawn(Enemies.colonelGuard, GridPos(4, 2)),
        ],
      );
      List<EnemyFighter> guards() => [
        for (final e in battle.enemies)
          if (e.def == Enemies.colonelGuard) e,
      ];
      final colonel = battle.enemies.first..timer = 100000;
      guards().first.hp = 0;
      wait(battle, 2);
      expect(guards(), hasLength(1));
      wait(battle, ColonelBehavior.guardReturn + 2);
      expect(guards(), hasLength(2));
      colonel.hp = 0;
      battle.tick();
      expect(battle.phase, BattlePhase.won);
    });

    test('Fury below half HP: barricades in front, a second Contrato', () {
      final (battle, colonel) = colonelAbout(1);
      colonel.hp = colonel.maxHp ~/ 2 - 1;
      battle.tick();
      expect(colonel.stage, 1);
      expect(battle.obstacles, hasLength(ColonelBehavior.barricades));
      for (final rock in battle.obstacles) {
        expect(rock.pos.x, colonel.pos.x - 1);
      }
      expect(warned(battle), hasLength(2));
    });
  });

  group('ARGOS', () {
    (BattleState, EnemyFighter) argosAbout(int index) {
      final battle = battleWith(
        [],
        spawns: [const EnemySpawn(Enemies.argos, GridPos(4, 0))],
      );
      final argos = battle.enemies.single
        ..attackTimer = index
        ..timer = 0;
      return (battle, argos);
    }

    test('Grade Laser always leaves panels free', () {
      for (var seed = 0; seed < 10; seed++) {
        final (battle, _) = argosAbout(0);
        battle.random.nextInt(seed + 1);
        battle.tick();
        final cells = warned(battle);
        expect(cells, isNotEmpty);
        expect(cells.length, lessThan(9));
        for (final cell in cells) {
          expect(battle.ownerAt(cell), Team.player);
        }
      }
    });

    test('Bloqueio takes the front column and pushes the player back', () {
      final (battle, argos) = argosAbout(1);
      battle.player.pos = const GridPos(2, 1);
      battle.tick();
      wait(battle, ArgosBehavior.lockWarn);
      expect(battle.ownerAt(const GridPos(2, 0)), Team.enemy);
      expect(battle.player.pos.x, 1);
      wait(battle, ArgosBehavior.lockTicks);
      expect(battle.ownerAt(const GridPos(2, 0)), Team.player);
      expect(argos.isDead, isFalse);
    });

    test('Protocolo de Contenção: the lock takes 2 columns', () {
      final (battle, argos) = argosAbout(1);
      argos.hp = (argos.maxHp * ArgosBehavior.alertAt).floor() - 1;
      battle.player.pos = const GridPos(2, 1);
      battle.tick();
      wait(battle, ArgosBehavior.lockWarn);
      expect(battle.ownerAt(const GridPos(1, 0)), Team.enemy);
      expect(battle.player.pos.x, 0);
      wait(battle, attackPoseTicks + 1);
      expect(argos.pose, ArgosBehavior.closedPose + 3);
    });

    test('Torres: 2 turrets that do not keep the fight going', () {
      final (battle, argos) = argosAbout(2);
      battle.tick();
      expect(
        battle.enemies.where((e) => e.def == Enemies.argosTurret),
        hasLength(ArgosBehavior.turrets),
      );
      argos.hp = 0;
      battle.tick();
      expect(battle.phase, BattlePhase.won);
    });

    test('the open core takes Energia 3x', () {
      final (battle, argos) = argosAbout(3);
      battle.tick();
      expect(argos.shieldDown, greaterThan(0));
      expect(argos.pose, ArgosBehavior.openPose);
      battle.damage(argos, 10, family: ChipFamily.energy);
      expect(argos.hp, Enemies.argos.hp - 30);
      wait(battle, ArgosBehavior.openTicks);
      battle.damage(argos, 10, family: ChipFamily.energy);
      expect(argos.hp, Enemies.argos.hp - 30 - 20);
    });
  });
}
