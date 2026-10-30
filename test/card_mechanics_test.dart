import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/game/sprites.dart';

import 'battle_helpers.dart';

void main() {
  test('every obstacle and status has a sprite', () {
    // Mines live on panels, never drawn as obstacles.
    for (final kind in ObstacleKind.values.where(
      (k) => k != ObstacleKind.mine,
    )) {
      expect(SpriteFiles.obstacles[kind], isNotNull, reason: kind.name);
    }
    for (final status in Status.values) {
      expect(SpriteFiles.statuses[status], isNotNull, reason: status.name);
    }
  });

  group('phase 1', () {
    test('Investida dashes to the front of its side and hits', () {
      final battle = battleWith([Chips.dash], spawns: [dummyAt(3, 1)]);
      use(battle, Chips.dash);
      expect(battle.player.pos, const GridPos(2, 1));
      expect(battle.enemies.single.hp, 80);
    });

    test('Investida does not move a Rooted player', () {
      final battle = battleWith([Chips.dash], spawns: [dummyAt(3, 1)]);
      battle.player.applyStatus(Status.rooted, 60);
      use(battle, Chips.dash);
      expect(battle.player.pos, const GridPos(1, 1));
      expect(battle.enemies.single.hp, 100);
    });

    test('Drone Médico heals 2 per second', () {
      final battle = battleWith([Chips.medicDrone]);
      battle.player.hp = 50;
      use(battle, Chips.medicDrone);
      wait(battle, 3 * ticksPerSecond);
      expect(battle.player.hp, greaterThanOrEqualTo(54));
      expect(battle.obstacles.single.kind, ObstacleKind.medic);
    });

    test('Gerador de Domo cancels 3 hits, then the 4th hurts', () {
      final battle = battleWith([Chips.domeGenerator]);
      use(battle, Chips.domeGenerator);
      for (var i = 0; i < 3; i++) {
        battle.damage(battle.player, 10);
      }
      expect(battle.player.hp, 100);
      battle.damage(battle.player, 10);
      expect(battle.player.hp, 90);
    });

    test('Escudo de Energia still cancels a single hit', () {
      final battle = battleWith([Chips.barrier]);
      use(battle, Chips.barrier);
      battle.damage(battle.player, 10);
      battle.damage(battle.player, 10);
      expect(battle.player.hp, 90);
    });

    test('Kit de Reparos heals and clears harmful statuses only', () {
      final battle = battleWith([Chips.repairKit]);
      battle.player
        ..hp = 50
        ..applyStatus(Status.burning, 90)
        ..applyStatus(Status.marked, 90)
        ..applyStatus(Status.regen, 90);
      use(battle, Chips.repairKit);
      expect(battle.player.has(Status.burning), isFalse);
      expect(battle.player.has(Status.marked), isFalse);
      expect(battle.player.has(Status.regen), isTrue);
      expect(battle.player.hp, greaterThanOrEqualTo(55));
    });

    test('Nanobots regenerate 1 per second', () {
      final battle = battleWith([Chips.nanobots]);
      battle.player.hp = 50;
      use(battle, Chips.nanobots);
      wait(battle, 3 * ticksPerSecond);
      expect(battle.player.hp, inInclusiveRange(52, 54));
      expect(battle.player.has(Status.regen), isTrue);
    });

    test('Recarga Tática draws 2, up to 7 cards in hand', () {
      final battle = battleWith(List.filled(12, Chips.tacticalReload));
      expect(battle.hand, hasLength(handSize));
      use(battle, Chips.tacticalReload);
      expect(battle.hand, hasLength(6));
      use(battle, Chips.tacticalReload);
      expect(battle.hand, hasLength(maxHand));
      use(battle, Chips.tacticalReload);
      expect(battle.hand, hasLength(maxHand));
    });
  });

  group('phase 2', () {
    test('Pulso Ressonante scales with its place in the chain', () {
      final battle = battleWith(
        [Chips.resonance, Chips.resonance],
        spawns: [dummyAt(3, 1)],
      );
      use(battle, Chips.resonance);
      expect(battle.enemies.single.hp, 95);
      use(battle, Chips.resonance);
      expect(battle.enemies.single.hp, 95 - (10 * chain2Multiplier).round());
    });

    test('Coringa: the next card joins the chain in progress', () {
      final battle = battleWith(
        [Chips.shot, Chips.wildcard, Chips.vShot],
        spawns: [dummyAt(3, 1)],
      );
      use(battle, Chips.shot);
      use(battle, Chips.wildcard);
      use(battle, Chips.vShot);
      expect(battle.chainFamily, ChipFamily.projectile);
      expect(battle.chainCount, 2);
      expect(battle.wildcard, isFalse);
    });

    test('Adrenalina: +5 on the next 3 attacks only', () {
      final shot = shotOf(Element.neutral);
      final battle = battleWith(
        [Chips.adrenaline, shot, shot, shot, shot],
        spawns: [dummyAt(3, 1)],
      );
      use(battle, Chips.adrenaline);
      for (var i = 0; i < 4; i++) {
        use(battle, shot);
      }
      expect(battle.enemies.single.hp, 100 - 3 * 15 - 10);
      expect(battle.attackCharges, 0);
    });

    test('Bala Oca is spent once by a whole SMG burst', () {
      final battle = battleWith(
        [Chips.atkBoost, Chips.smg],
        spawns: [dummyAt(3, 1)],
      );
      use(battle, Chips.atkBoost);
      use(battle, Chips.smg);
      wait(battle, 30);
      expect(battle.damageBonus, 0);
      expect(battle.enemies.single.hp, 100 - 3 * 15);
    });
  });

  group('phase 3', () {
    test('Foguete Teleguiado lands on the weakest enemy', () {
      final battle = battleWith(
        [Chips.homingRocket],
        spawns: [dummyAt(3, 1), dummyAt(5, 0)],
      );
      final [strong, weak] = battle.enemies;
      weak.hp = 50;
      use(battle, Chips.homingRocket);
      wait(battle, 30);
      expect(weak.hp, 50 - boom(15));
      expect(strong.hp, 100);
    });

    test('Mira Assistida: the next shot lands on the weakest enemy', () {
      final battle = battleWith(
        [Chips.assistedAim, Chips.shot],
        spawns: [dummyAt(3, 1), dummyAt(4, 2)],
      );
      final [strong, weak] = battle.enemies;
      weak.hp = 40;
      use(battle, Chips.assistedAim);
      use(battle, Chips.shot);
      expect(weak.hp, 40 - Chips.shot.damage);
      expect(strong.hp, 100);
      expect(battle.homingShots, 0);
    });

    test('Ricochete bounces to another enemy', () {
      final battle = battleWith(
        [Chips.ricochet],
        spawns: [dummyAt(3, 1), dummyAt(5, 0)],
      );
      use(battle, Chips.ricochet);
      for (final enemy in battle.enemies) {
        expect(enemy.hp, 90);
      }
    });

    test('Arco Voltaico jumps only to an enemy next to the target', () {
      final battle = battleWith(
        [Chips.voltaicArc],
        spawns: [dummyAt(3, 1), dummyAt(4, 1), dummyAt(5, 0)],
      );
      use(battle, Chips.voltaicArc);
      expect(battle.enemies.map((e) => e.hp), [90, 90, 100]);
    });

    test('Carga C4 blows up 3 s after it sticks', () {
      final battle = battleWith([Chips.c4], spawns: [dummyAt(3, 1)]);
      use(battle, Chips.c4);
      expect(battle.enemies.single.hp, 100);
      wait(battle, 3 * ticksPerSecond);
      expect(battle.enemies.single.hp, 100 - boom(30));
    });
  });
}
