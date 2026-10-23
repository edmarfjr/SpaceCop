import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

void main() {
  test('Bug does nothing: no Storm, no hits, bonus kept', () {
    final battle = battleWith([Chips.bug], spawns: [dummyAt(4, 1)]);
    battle.damageBonus = 10;
    use(battle, Chips.bug);
    final enemy = battle.enemies.single;
    expect(enemy.hp, 100);
    expect(enemy.has(Status.wet), isFalse);
    expect(battle.flashes, isEmpty);
    expect(battle.damageBonus, 10);
  });

  test('Rachador hits and cracks the target panel', () {
    final battle = battleWith([Chips.cracker], spawns: [dummyAt(3, 1)]);
    use(battle, Chips.cracker);
    expect(battle.enemies.single.hp, 100 - 20);
    expect(battle.panelAt(const GridPos(3, 1)).state, PanelState.cracked);
  });

  test('Bolha Empurradora wets and pushes the target', () {
    final battle = battleWith([Chips.bubblePush], spawns: [dummyAt(3, 1)]);
    use(battle, Chips.bubblePush);
    final enemy = battle.enemies.single;
    expect(enemy.hp, 100 - 10);
    expect(enemy.pos, const GridPos(4, 1));
    expect(enemy.has(Status.wet), isTrue);
  });

  test('Chama Cruzada hits a cross and burns grass', () {
    final battle = battleWith(
      [Chips.crossFlame],
      spawns: [dummyAt(3, 1), dummyAt(4, 1), dummyAt(3, 0), dummyAt(5, 2)],
    )..setPanel(const GridPos(3, 2), PanelState.grass);
    use(battle, Chips.crossFlame);
    expect(battle.enemies.map((e) => e.hp), [85, 85, 85, 100]);
    expect(battle.panelAt(const GridPos(3, 2)).state, PanelState.normal);
  });

  test('tossed chips land after a short flight, then take effect', () {
    final battle = battleWith([Chips.crossFlame], spawns: [dummyAt(4, 1)]);
    battle
      ..selectChip(0)
      ..tick(const PlayerInput(useChip: true));
    expect(battle.player.pose, ChipPose.toss);
    expect(battle.lobs.single.from, battle.player);
    expect(battle.lobs.single.to, const GridPos(4, 1));
    expect(battle.telegraphs, isEmpty, reason: 'player throws are not warned');
    // The use tick already counts toward the flight.
    wait(battle, playerTossTicks - 2);
    expect(battle.enemies.single.hp, 100);
    wait(battle, 1);
    expect(battle.enemies.single.hp, 100 - Chips.crossFlame.damage);
  });

  test('Lança Trovão hits columns 3 to 5 of the row, double on Wet', () {
    final battle = battleWith(
      [Chips.thunderLance],
      spawns: [dummyAt(3, 1), dummyAt(5, 1), dummyAt(4, 0)],
    );
    battle.enemies[1].applyStatus(Status.wet, wetTicks);
    use(battle, Chips.thunderLance);
    expect(battle.enemies.map((e) => e.hp), [85, 70, 100]);
  });

  test('Escudo de Energia cancels the next hit and expires after 5 s', () {
    final battle = battleWith([Chips.barrier, Chips.barrier]);
    use(battle, Chips.barrier);
    battle.damage(battle.player, 50);
    expect(battle.player.hp, 100);
    battle.damage(battle.player, 20);
    expect(battle.player.hp, 80);

    use(battle, Chips.barrier);
    wait(battle, 5 * ticksPerSecond);
    battle.damage(battle.player, 5);
    expect(battle.player.hp, 75);
  });

  test('Escudo Refletor bounces enemy shots back, doubled, for 5 s', () {
    final battle = battleWith([Chips.mirror], spawns: [dummyAt(4, 1)]);
    use(battle, Chips.mirror);
    final reflector = battle.obstacles.single;
    expect(reflector.kind, ObstacleKind.reflector);
    expect(reflector.pos, const GridPos(2, 1));
    battle.projectiles.add(
      Projectile(
        team: Team.enemy,
        pos: const GridPos(3, 1),
        dir: -1,
        stepTicks: 2,
        damage: 10,
        pattern: const [GridPos(0, 0)],
      ),
    );
    wait(battle, 10);
    expect(battle.player.hp, 100);
    expect(battle.enemies.single.hp, 100 - 20);

    // Strikes can't break it; it goes away on its own.
    battle.strike(reflector.pos, 50, Team.player, Element.neutral);
    expect(battle.obstacles, contains(reflector));
    wait(battle, reflectorTicks);
    expect(battle.obstacles, isEmpty);
  });

  test("the player's own shots go through the Escudo Refletor", () {
    final battle = battleWith(
      [Chips.mirror, Chips.shot],
      spawns: [dummyAt(4, 1)],
    );
    use(battle, Chips.mirror);
    use(battle, Chips.shot);
    wait(battle, 5);
    expect(battle.enemies.single.hp, 95);
  });

  test('Semear Grama turns the player side into grass', () {
    final battle = battleWith([Chips.seedGrass])
      ..setPanel(const GridPos(0, 0), PanelState.hole);
    use(battle, Chips.seedGrass);
    for (var x = 0; x < playerColumns; x++) {
      for (var y = 0; y < gridRows; y++) {
        expect(
          battle.panelAt(GridPos(x, y)).state,
          x == 0 && y == 0 ? PanelState.hole : PanelState.grass,
        );
      }
    }
    expect(battle.panelAt(const GridPos(3, 0)).state, PanelState.normal);
  });

  test('Avanço takes column 3 for 10 s', () {
    final battle = battleWith([Chips.areaSteal], spawns: [dummyAt(5, 1)]);
    use(battle, Chips.areaSteal);
    expect(battle.ownerAt(const GridPos(3, 0)), Team.player);
    battle.tick(const PlayerInput(dx: 1));
    wait(battle, playerMoveCooldown);
    battle.tick(const PlayerInput(dx: 1));
    expect(battle.player.pos, const GridPos(3, 1));
    wait(battle, 10 * ticksPerSecond);
    expect(battle.ownerAt(const GridPos(3, 0)), Team.enemy);
    expect(battle.player.pos.x, lessThan(playerColumns));
  });

  test('Avanço hits and pushes back whoever stands in the column', () {
    final battle = battleWith([Chips.areaSteal], spawns: [dummyAt(3, 0)]);
    use(battle, Chips.areaSteal);
    expect(battle.enemies.single.hp, 100 - 5);
    expect(battle.enemies.single.pos, const GridPos(4, 0));
    expect(battle.ownerAt(const GridPos(3, 0)), Team.player);
  });

  test('Avanço leaves the panel of an enemy it cannot push', () {
    final battle = battleWith(
      [Chips.areaSteal],
      spawns: [const EnemySpawn(Enemies.cannon, GridPos(3, 0))],
    );
    use(battle, Chips.areaSteal);
    expect(battle.enemies.single.pos, const GridPos(3, 0));
    expect(battle.ownerAt(const GridPos(3, 0)), Team.enemy);
    expect(battle.ownerAt(const GridPos(3, 1)), Team.player);
  });

  test('Rocha blocks shots and hits hard when pushed', () {
    final battle = battleWith(
      [Chips.rock, Chips.shot, Chips.bubblePush],
      spawns: [dummyAt(3, 1)],
    );
    use(battle, Chips.rock);
    final rock = battle.obstacles.single;
    expect(rock.pos, const GridPos(2, 1));
    use(battle, Chips.shot);
    expect(rock.hp, rockHp - Chips.shot.damage);
    expect(battle.enemies.single.hp, 100);
    use(battle, Chips.bubblePush);
    expect(battle.enemies.single.hp, 100 - rockCollisionDamage);
  });

  test('Mina hides on a free enemy panel and blows up whoever steps on it', () {
    final battle = battleWith([Chips.mine], spawns: [dummyAt(4, 0)]);
    battle.enemies.single.applyStatus(Status.stunned, 20);
    for (var x = playerColumns; x < gridColumns; x++) {
      for (var y = 0; y < gridRows; y++) {
        final pos = GridPos(x, y);
        if (pos != const GridPos(4, 0) && pos != const GridPos(4, 1)) {
          battle.setPanel(pos, PanelState.hole, 0);
        }
      }
    }
    use(battle, Chips.mine);
    expect(battle.panelAt(const GridPos(4, 1)).mine, isTrue);
    wait(battle, 2 * ticksPerSecond);
    expect(battle.enemies.single.pos, const GridPos(4, 1));
    expect(battle.enemies.single.hp, 100 - mineDamage);
    expect(battle.panelAt(const GridPos(4, 1)).mine, isFalse);
  });

  test('Torreta shoots down its row every second for 10 s', () {
    final battle = battleWith([Chips.turret], spawns: [dummyAt(3, 1)]);
    use(battle, Chips.turret);
    final turret = battle.obstacles.single;
    expect(turret.pos, const GridPos(0, 1));
    wait(battle, ticksPerSecond);
    expect(battle.enemies.single.hp, 100 - turretShotDamage);
    wait(battle, turretTicks);
    expect(battle.obstacles, isEmpty);
  });

  test('Torreta goes in front of the player when they stand at the back', () {
    final battle = battleWith([Chips.turret], spawns: [dummyAt(3, 1)]);
    battle.player.pos = const GridPos(0, 1);
    use(battle, Chips.turret);
    expect(battle.obstacles.single.pos, const GridPos(1, 1));
  });

  test('Gancho pulls the first target of the row', () {
    final battle = battleWith([Chips.hook], spawns: [dummyAt(4, 1)]);
    use(battle, Chips.hook);
    expect(battle.enemies.single.pos, const GridPos(3, 1));
  });
}
