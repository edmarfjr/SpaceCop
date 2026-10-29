import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/enemy_behaviors.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

Set<GridPos> warned(BattleState battle) => {
  for (final t in battle.telegraphs) t.pos,
};

BattleState facing(EnemyDef def, GridPos pos, [List chips = const []]) =>
    battleWith([...chips], spawns: [EnemySpawn(def, pos)]);

void main() {
  group('Etéreos', () {
    test('Sombra Atiradora is phased until it lines up to shoot', () {
      final battle = facing(Enemies.shadowGun, const GridPos(4, 1));
      final shadow = battle.enemies.single;
      expect(shadow.phased, isTrue);
      for (var i = 0; i < 10 * ticksPerSecond && !shadow.attacking; i++) {
        battle.tick();
        if (!shadow.attacking) expect(shadow.phased, isTrue);
      }
      expect(shadow.attacking, isTrue);
      expect(shadow.phased, isFalse);
    });

    test('Sombra Alada blinks and lobs a ball at the player', () {
      final battle = facing(Enemies.shadowFly, const GridPos(4, 1));
      wait(battle, ShadowFlyBehavior.cycleTicks ~/ 2 + 1);
      expect(warned(battle), {battle.player.pos});
      expect(battle.enemies.single.phased, isFalse);
      wait(battle, basicWarnTicks);
      expect(battle.player.hp, 100 - ShadowFlyBehavior.damage);
    });

    test('Sombra Saltadora is solid from its leap until it is home', () {
      final battle = facing(Enemies.shadowJumper, const GridPos(4, 1));
      final shadow = battle.enemies.single;
      for (var i = 0; i < 10 * ticksPerSecond && shadow.stage == 0; i++) {
        battle.tick();
      }
      expect(shadow.phased, isFalse, reason: 'leaping');
      wait(battle, 2 * ticksPerSecond);
      expect(battle.player.hp, 100 - GruntMeleeBehavior.damage);
    });

    test('Ninho hatches Carrapatos in front of it, at most 3', () {
      final battle = facing(Enemies.shadowNest, const GridPos(5, 1));
      final nest = battle.enemies.single;
      wait(battle, NestBehavior.cycleTicks ~/ 2 + 1);
      expect(battle.enemies.map((e) => e.def), [
        Enemies.shadowNest,
        Enemies.shadowTick,
      ]);
      expect(nest.phased, isFalse, reason: 'solid right after hatching');
      for (final tick in battle.enemies.skip(1)) {
        tick.applyStatus(Status.stunned, 100000);
      }
      wait(battle, 5 * (NestBehavior.cycleTicks + 1));
      expect(
        battle.enemies.where((e) => e.def == Enemies.shadowTick),
        hasLength(lessThanOrEqualTo(NestBehavior.maxTicks)),
      );
    });

    test('Carrapato crawls to the player and blows up', () {
      final battle = battleWith([], spawns: [dummyAt(5, 0)]);
      battle.enemies.single.applyStatus(Status.stunned, 100000);
      final tick = battle.summon(Enemies.shadowTick, const GridPos(3, 1));
      wait(battle, 2);
      expect(tick.pos, const GridPos(2, 1));
      expect(tick.phased, isFalse, reason: 'always solid while crawling');
      wait(battle, TickBehavior.stepTicks);
      expect(warned(battle), {battle.player.pos});
      wait(battle, minWarnTicks);
      expect(battle.player.hp, 100 - TickBehavior.damage);
      expect(battle.enemies, hasLength(1), reason: 'the Carrapato is gone');
    });

    test('Carrapatos alone do not keep the battle going', () {
      final battle = facing(Enemies.shadowNest, const GridPos(5, 1));
      battle.summon(Enemies.shadowTick, const GridPos(4, 1));
      battle.enemies.first.hp = 0;
      battle.tick();
      expect(battle.phase, BattlePhase.won);
    });

    test('Predador vanishes, reappears in the player row and slashes their '
        'column', () {
      final battle = facing(Enemies.predator, const GridPos(5, 0));
      final predator = battle.enemies.single;
      wait(battle, PredatorBehavior.visibleTicks + 1);
      expect(predator.hidden, isTrue);
      wait(battle, PredatorBehavior.hiddenTicks + 1);
      expect(predator.hidden, isFalse);
      expect(predator.pos, const GridPos(3, 1));
      expect(warned(battle), {
        const GridPos(1, 0),
        const GridPos(1, 1),
        const GridPos(1, 2),
      });
      wait(battle, minWarnTicks);
      expect(battle.player.hp, 100 - PredatorBehavior.damage);
      expect(predator.phased, isFalse, reason: 'recovering');
    });

    test('Espreitador charges down the row and cracks it', () {
      final battle = facing(Enemies.stalker, const GridPos(4, 1));
      wait(battle, StalkerBehavior.chargeEvery ~/ 2);
      expect(warned(battle), contains(battle.player.pos));
      expect(battle.enemies.single.phased, isFalse);
      wait(battle, StalkerBehavior.warnTicks);
      expect(battle.player.hp, 100 - StalkerBehavior.damage);
      expect(battle.panelAt(const GridPos(2, 1)).state, PanelState.cracked);
    });
  });

  group('Corpo-a-corpo cards', () {
    test('Ombrada hits the panel in front and pushes 1', () {
      final battle = battleWith([Chips.shoulderBash], spawns: [dummyAt(3, 1)])
        ..player.pos = const GridPos(2, 1);
      final enemy = battle.enemies.single;
      use(battle, Chips.shoulderBash);
      expect(enemy.hp, 100 - Chips.shoulderBash.damage);
      expect(enemy.pos, const GridPos(4, 1));
    });

    test('Chicote de Energia reaches 2 panels down the row', () {
      final battle = battleWith(
        [Chips.energyWhip],
        spawns: [dummyAt(3, 1), dummyAt(4, 1), dummyAt(5, 1)],
      )..player.pos = const GridPos(2, 1);
      use(battle, Chips.energyWhip);
      final hit = 100 - Chips.energyWhip.damage;
      expect(battle.enemies.map((e) => e.hp), [hit, hit, 100]);
    });

    test('Martelo Sísmico cracks the panel it hits', () {
      final battle = battleWith([Chips.seismicHammer], spawns: [dummyAt(3, 1)])
        ..player.pos = const GridPos(2, 1);
      use(battle, Chips.seismicHammer);
      expect(battle.enemies.single.hp, 100 - Chips.seismicHammer.damage);
      expect(battle.panelAt(const GridPos(3, 1)).state, PanelState.cracked);
    });
  });

  group('Olho do Abismo', () {
    BattleState eyeFight() => battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.voidEye, GridPos(4, 0))],
    );

    test('Olhar Abissal beams down the player row and column', () {
      final battle = eyeFight();
      final eye = battle.enemies.single;
      expect(eye.phased, isTrue);
      wait(battle, VoidEyeBehavior.attackEvery ~/ 2 + 1);
      expect(eye.phased, isFalse, reason: 'solid while it attacks');
      expect(warned(battle), {
        const GridPos(0, 1),
        const GridPos(1, 1),
        const GridPos(2, 1),
        const GridPos(1, 0),
        const GridPos(1, 2),
      });
      wait(battle, VoidEyeBehavior.gazeWarn);
      expect(battle.player.hp, 100 - VoidEyeBehavior.gazeDamage);
    });

    test('Cisão: invulnerable while a Hemisfério lives, then reels and '
        'wakes up', () {
      final battle = eyeFight();
      final eye = battle.enemies.single..hp = 200;
      battle.tick();
      final halves = battle.enemies
          .where((e) => e.def == Enemies.hemisphere)
          .toList();
      expect(halves, hasLength(2));
      expect(eye.invulnerable, isTrue);
      battle.damage(eye, 50);
      expect(eye.hp, 200);
      for (final half in halves) {
        half.hp = 0;
      }
      wait(battle, 2);
      expect(eye.stage, 2);
      expect(eye.invulnerable, isFalse);
      expect(eye.has(Status.stunned), isTrue);
      expect(eye.phased, isFalse);
      battle.damage(eye, 10);
      expect(eye.hp, 200 - 20, reason: 'double damage while reeling');
    });

    test('Despertar: always solid', () {
      final battle = eyeFight();
      final eye = battle.enemies.single..stage = 2;
      wait(battle, 5);
      expect(eye.phased, isFalse);
    });
  });
}
