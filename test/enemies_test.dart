import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/enemy_behaviors.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

Set<GridPos> warned(BattleState battle, [TelegraphKind? kind]) => {
  for (final t in battle.telegraphs)
    if (kind == null || t.kind == kind) t.pos,
};

/// Freezes every enemy's AI so a test can set positions by hand.
void freeze(BattleState battle) {
  for (final enemy in battle.enemies) {
    enemy.applyStatus(Status.stunned, 1000);
  }
}

void main() {
  group('enemy kinds', () {
    int hitWith(ChipFamily family, EnemyKind kind) {
      final chip = shotOf(Element.neutral, family: family);
      final battle = battleWith([chip], spawns: [dummyAt(3, 1, kind: kind)]);
      freeze(battle);
      use(battle, chip);
      return 100 - battle.enemies.single.hp;
    }

    test('Máquina: Projétil half, Energia double', () {
      expect(hitWith(ChipFamily.projectile, EnemyKind.machine), 5);
      expect(hitWith(ChipFamily.energy, EnemyKind.machine), 20);
      expect(hitWith(ChipFamily.melee, EnemyKind.machine), 10);
      expect(hitWith(ChipFamily.explosive, EnemyKind.machine), 10);
    });

    test('Orgânico: Explosivo +50%, the rest plain', () {
      expect(hitWith(ChipFamily.explosive, EnemyKind.organic), 15);
      expect(hitWith(ChipFamily.projectile, EnemyKind.organic), 10);
      expect(hitWith(ChipFamily.energy, EnemyKind.organic), 10);
    });

    test('Etéreo in phase: Projétil and Corpo-a-corpo pass through', () {
      expect(hitWith(ChipFamily.projectile, EnemyKind.ethereal), 0);
      expect(hitWith(ChipFamily.melee, EnemyKind.ethereal), 0);
      expect(hitWith(ChipFamily.energy, EnemyKind.ethereal), 10);
      expect(hitWith(ChipFamily.explosive, EnemyKind.ethereal), 10);
    });

    test('Cacetete neither hurts nor stuns a phased Etéreo', () {
      final battle = battleWith(
        [Chips.baton],
        spawns: [dummyAt(3, 1, kind: EnemyKind.ethereal)],
      )..player.pos = const GridPos(2, 1);
      final enemy = battle.enemies.single;
      use(battle, Chips.baton);
      expect(enemy.hp, 100);
      expect(enemy.has(Status.stunned), isFalse);
    });

    test('a shot flies through a phased Etéreo to the enemy behind', () {
      final shot = shotOf(Element.neutral, family: ChipFamily.projectile);
      final battle = battleWith(
        [shot],
        spawns: [
          dummyAt(3, 1, kind: EnemyKind.ethereal),
          dummyAt(5, 1),
        ],
      );
      freeze(battle);
      use(battle, shot);
      wait(battle, 5);
      expect(battle.enemies.map((e) => e.hp), [100, 90]);
    });

    test('Etéreo is solid while it attacks and for 2 s after an Explosivo', () {
      final shot = shotOf(Element.neutral, family: ChipFamily.projectile);
      final blast = shotOf(Element.neutral, family: ChipFamily.explosive);
      final battle = battleWith(
        [shot, blast, shot, shot],
        spawns: [dummyAt(3, 1, kind: EnemyKind.ethereal)],
      );
      freeze(battle);
      final enemy = battle.enemies.single;
      expect(enemy.phased, isTrue);
      enemy.attackPose = 5;
      expect(enemy.phased, isFalse, reason: 'attacking');
      enemy.attackPose = 0;
      use(battle, blast);
      expect(enemy.phased, isFalse);
      use(battle, shot);
      expect(enemy.hp, 100 - 10 - 10);
      wait(battle, materializeTicks);
      expect(enemy.phased, isTrue);
      use(battle, shot);
      expect(enemy.hp, 100 - 10 - 10);
    });
  });

  test('Canhão Móvel outlines its row for 1 s before shooting', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.mobileCannon, GridPos(3, 1))],
    );
    expect(warned(battle), isEmpty, reason: 'waits its move cooldown first');
    wait(battle, Enemies.mobileCannon.moveTicks);
    expect(warned(battle), containsAll(const [GridPos(1, 1), GridPos(0, 1)]));
    expect(battle.telegraphs.first.ticksLeft, basicWarnTicks - 1);
    expect(battle.projectiles, isEmpty);
    wait(battle, basicWarnTicks);
    expect(battle.projectiles, hasLength(1));
  });

  test('an enemy holds still while its attack winds up and lands', () {
    final battle = battleWith([], spawns: [dummyAt(4, 0)]);
    final enemy = battle.enemies.single;
    battle.schedule(enemy, [const GridPos(1, 1)], 10, () {});
    expect(enemy.attacking, isTrue);
    expect(battle.tryMove(enemy, const GridPos(0, 1)), isFalse);
    wait(battle, 10);
    expect(enemy.attacking, isTrue, reason: 'keeps the pose a moment');
    wait(battle, attackPoseTicks);
    expect(enemy.attacking, isFalse);
    expect(battle.tryMove(enemy, const GridPos(0, 1)), isTrue);
  });

  test('a lobbed ball is in the air only as the attack is about to land', () {
    final battle = battleWith([], spawns: [dummyAt(4, 0)]);
    final enemy = battle.enemies.single;
    var landed = false;
    battle.schedule(
      enemy,
      [const GridPos(1, 1)],
      lobFlightTicks + 5,
      () => landed = true,
      lob: Lob.ball,
    );
    expect(battle.lobs, isEmpty);
    wait(battle, 5);
    expect(battle.lobs.single.to, const GridPos(1, 1));
    wait(battle, lobFlightTicks - 1);
    expect(landed, isFalse);
    wait(battle, 1);
    expect(landed, isTrue);
    expect(battle.lobs, isEmpty);
  });

  test('Raiz strikes every panel of the player column', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.root, GridPos(4, 1))],
    );
    expect(warned(battle), isEmpty, reason: 'starts with a full cooldown');
    wait(battle, RootBehavior.cycleTicks);
    expect(warned(battle), {for (var y = 0; y < 3; y++) GridPos(1, y)});
    wait(battle, basicWarnTicks);
    expect(battle.player.hp, 100 - RootBehavior.damage);
  });

  test('Bolhador hits the player panel and freezes it', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.bubbler, GridPos(5, 1))],
    );
    expect(warned(battle), isEmpty, reason: 'starts with a full cooldown');
    wait(battle, BubblerBehavior.cycleTicks);
    wait(battle, basicWarnTicks);
    expect(battle.player.hp, 100 - BubblerBehavior.damage);
    expect(battle.panelAt(const GridPos(1, 1)).state, PanelState.ice);
    for (final enemy in battle.enemies) {
      expect(enemy.pos.x, greaterThanOrEqualTo(4));
    }
  });

  test('Canhão Fixo fires after 1 s in its row; a rock takes the beam', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.cannon, GridPos(5, 1))],
    );
    wait(battle, CannonBehavior.cooldownTicks);
    wait(battle, CannonBehavior.aimTicks);
    expect(battle.player.hp, 100 - CannonBehavior.damage);

    final rock = Obstacle(
      ObstacleKind.rock,
      pos: const GridPos(2, 1),
      hp: rockHp,
    );
    battle.obstacles.add(rock);
    wait(battle, CannonBehavior.cooldownTicks + CannonBehavior.aimTicks + 1);
    expect(battle.player.hp, 100 - CannonBehavior.damage);
    expect(rock.hp, rockHp - CannonBehavior.damage);
  });

  test('Brute shield stops straight shots, not diagonals or after a crash', () {
    final battle = battleWith(
      [Chips.shot, Chips.vShot, Chips.shot],
      spawns: const [
        EnemySpawn(Enemies.brute, GridPos(4, 1)),
        EnemySpawn(Enemies.mobileCannon, GridPos(3, 0)),
      ],
    );
    freeze(battle);
    final brute = battle.enemies.first;
    use(battle, Chips.shot);
    expect(brute.hp, 80);

    battle.player.pos = const GridPos(1, 0);
    use(battle, Chips.vShot);
    expect(brute.hp, 80 - 10);

    battle
      ..player.pos = const GridPos(1, 1)
      ..displace(brute, 1, 0, 5);
    expect(brute.pos, const GridPos(5, 1));
    use(battle, Chips.shot);
    expect(brute.hp, 80 - 10 - collisionDamage - Chips.shot.damage);
  });

  test('Brute charges down the player row every 4 s', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.brute, GridPos(4, 1))],
    );
    wait(battle, BruteBehavior.chargeEvery - 1);
    expect(warned(battle), contains(const GridPos(1, 1)));
    expect(battle.player.hp, 100);
    wait(battle, BruteBehavior.warnTicks);
    expect(battle.player.hp, 100 - BruteBehavior.damage);
  });

  test('Brute shield is down for a while after its charge', () {
    final battle = battleWith(
      [Chips.shot, Chips.shot],
      spawns: [const EnemySpawn(Enemies.brute, GridPos(4, 1))],
    );
    final brute = battle.enemies.single;
    use(battle, Chips.shot);
    expect(brute.hp, 80);
    wait(battle, BruteBehavior.chargeEvery + BruteBehavior.warnTicks);
    expect(brute.shieldDown, greaterThan(0));
    use(battle, Chips.shot);
    expect(brute.hp, 80 - Chips.shot.damage);
  });

  test('Escavador is untouchable underground and its pickaxe cracks', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.digger, GridPos(4, 1))],
    );
    final digger = battle.enemies.single;
    expect(digger.hidden, isFalse, reason: 'starts revealed');
    wait(battle, DiggerBehavior.underTicks + DiggerBehavior.digTicks + 2);
    expect(digger.hidden, isTrue);
    battle.damage(digger, 10);
    expect(digger.hp, 70);

    wait(battle, DiggerBehavior.underTicks + 1);
    expect(digger.hidden, isFalse, reason: 'climbing out');
    expect(digger.buried, greaterThan(0));
    final at = digger.pos;
    battle.damage(digger, 10);
    expect(digger.hp, 60, reason: 'vulnerable while climbing out');
    wait(battle, DiggerBehavior.digTicks);
    expect(digger.pos, at);
    expect(digger.buried, 0);
    expect(warned(battle, TelegraphKind.terrain), {const GridPos(1, 1)});
    wait(battle, DiggerBehavior.upTicks);
    expect(battle.panelAt(const GridPos(1, 1)).state, PanelState.cracked);

    // Digging back in: still standing there, and still hittable.
    wait(battle, 2);
    expect(digger.hidden, isFalse);
    expect(digger.buried, greaterThan(0));
    battle.damage(digger, 10);
    expect(digger.hp, 50);
    wait(battle, DiggerBehavior.digTicks);
    expect(digger.hidden, isTrue);
  });

  test('Escavador falls when it pops up on a cracked panel', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.digger, GridPos(4, 1))],
    );
    wait(battle, DiggerBehavior.underTicks + DiggerBehavior.digTicks + 2);
    for (var x = playerColumns; x < gridColumns; x++) {
      for (var y = 0; y < gridRows; y++) {
        battle.setPanel(GridPos(x, y), PanelState.cracked);
      }
    }
    wait(battle, DiggerBehavior.underTicks + 1);
    final digger = battle.enemies.single;
    expect(digger.hp, 70 - fallDamage);
    expect(digger.hidden, isTrue);
    expect(battle.panelAt(digger.pos).state, PanelState.hole);
  });

  test('Dupla Prisma reflects straight shots unless lined up', () {
    final battle = battleWith(
      [Chips.shot, Chips.shot, Chips.thunderLance],
      spawns: const [
        EnemySpawn(Enemies.prism, GridPos(4, 0)),
        EnemySpawn(Enemies.prism, GridPos(5, 2)),
      ],
    );
    freeze(battle);
    final [a, b] = battle.enemies;
    a.pos = const GridPos(4, 0);
    b.pos = const GridPos(5, 2);
    battle.player.pos = const GridPos(1, 0);
    use(battle, Chips.shot);
    expect(a.hp, 40);
    wait(battle, 10);
    expect(battle.player.hp, 100 - Chips.shot.damage);

    use(battle, Chips.thunderLance);
    expect(a.hp, 40 - Chips.thunderLance.damage);

    b.pos = const GridPos(5, 0);
    use(battle, Chips.shot);
    expect(a.hp, 40 - Chips.thunderLance.damage - Chips.shot.damage);
  });

  test('Guardião de Lava puts lava on the player side and flames columns '
      '1-2', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.lavaGuard, GridPos(5, 1))],
    );
    List<GridPos> lavaOn(Team side) => [
      for (var x = 0; x < gridColumns; x++)
        for (var y = 0; y < gridRows; y++)
          if (battle.ownerAt(GridPos(x, y)) == side &&
              battle.panelAt(GridPos(x, y)).state == PanelState.lava)
            GridPos(x, y),
    ];
    expect(warned(battle), isEmpty, reason: 'starts with full cooldowns');
    wait(battle, LavaGuardBehavior.lavaEvery + minWarnTicks);
    expect(lavaOn(Team.player), hasLength(1));
    wait(
      battle,
      LavaGuardBehavior.flameEvery -
          LavaGuardBehavior.lavaEvery +
          ticksPerSecond -
          minWarnTicks,
    );
    // The flames, plus lava burns if it landed under the player.
    expect(battle.player.hp, lessThanOrEqualTo(100 - LavaGuardBehavior.damage));

    // Lava stays, so the next one makes two; its own side never gets any.
    wait(battle, LavaGuardBehavior.lavaEvery);
    expect(lavaOn(Team.player), hasLength(2));
    expect(lavaOn(Team.enemy), isEmpty);
  });

  test('Colosso hammers, cracks, then holes, and leaves a weak fist', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.colossus, GridPos(4, 0))],
    );
    final colossus = battle.enemies.single;
    expect(battle.unitAt(const GridPos(4, 1)), colossus);
    wait(battle, ColossusBehavior.hammerEvery + ticksPerSecond - 1);
    expect(battle.player.hp, 100 - ColossusBehavior.damage);
    expect(battle.panelAt(const GridPos(1, 0)).state, PanelState.cracked);
    expect(battle.panelAt(const GridPos(1, 1)).state, PanelState.cracked);
    final fist = battle.enemies.last;
    expect(fist.def, Enemies.colossusFist);
    expect(fist.pos, const GridPos(3, 1));
    battle.damage(fist, 10);
    expect(colossus.hp, 300 - 20);

    battle.player.hp = 100;
    wait(battle, ColossusBehavior.hammerEvery);
    for (var y = 0; y < gridRows; y++) {
      expect(battle.panelAt(GridPos(1, y)).state, PanelState.hole);
    }
    // The player fell: hammer + fall damage, out on a side panel, stunned.
    expect(battle.player.hp, 100 - ColossusBehavior.damage - fallDamage);
    expect(battle.player.pos, const GridPos(0, 1));
    expect(battle.player.has(Status.stunned), isTrue);
  });

  test(
    'Colosso steals column 2 below half HP; Roubo de Área takes it back',
    () {
      final battle = battleWith(
        [Chips.areaSteal],
        spawns: [const EnemySpawn(Enemies.colossus, GridPos(4, 0))],
      );
      final colossus = battle.enemies.single..hp = 149;
      battle.player.pos = const GridPos(2, 1);
      battle.tick();
      expect(battle.ownerAt(const GridPos(2, 0)), Team.enemy);
      expect(battle.player.pos, const GridPos(1, 1));
      expect(battle.holeReturnTicks, ColossusBehavior.ragingHoleTicks);

      use(battle, Chips.areaSteal);
      expect(battle.ownerAt(const GridPos(2, 0)), Team.player);
      expect(colossus.has(Status.stunned), isTrue);
    },
  );

  test('a multi-cell unit is hit once per attack', () {
    final battle = battleWith(
      [Chips.crossFlame],
      spawns: [const EnemySpawn(Enemies.colossus, GridPos(4, 0))],
    );
    freeze(battle);
    use(battle, Chips.crossFlame);
    expect(battle.enemies.single.hp, 300 - Chips.crossFlame.damage);
  });

  test('Maestro switches element every 10 s and reshapes its side', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.maestro, GridPos(5, 1))],
    );
    final maestro = battle.enemies.single;
    wait(battle, MaestroBehavior.switchEvery - MaestroBehavior.switchWarn);
    expect(warned(battle, TelegraphKind.terrain), hasLength(9));
    wait(battle, MaestroBehavior.switchWarn);
    expect(maestro.element, Element.wood);
    expect(battle.panelAt(const GridPos(3, 0)).state, PanelState.grass);
  });

  test('Maestro hides behind its Notes below half HP', () {
    final battle = battleWith(
      [],
      spawns: [const EnemySpawn(Enemies.maestro, GridPos(5, 1))],
    );
    final maestro = battle.enemies.single..hp = 174;
    battle.tick();
    final notes = battle.enemies.where((e) => e.def == Enemies.note).toList();
    expect(notes, hasLength(2));
    expect(notes.map((n) => n.pos.x), everyElement(playerColumns));
    battle.damage(maestro, 10);
    expect(maestro.hp, 174);

    for (final note in notes) {
      note.hp = 0;
    }
    wait(battle, 2);
    battle.damage(maestro, 10);
    expect(maestro.hp, 164);
  });

  test('encounters roll from the new rosters', () {
    final random = Random(2);
    for (var i = 0; i < 20; i++) {
      final normal = Encounters.normal(random).spawns;
      expect(normal.length, inInclusiveRange(1, 2));
      expect(normal.map((s) => s.def), everyElement(isIn(Enemies.basics)));
      expect(Encounters.elite(random).spawns, isNotEmpty);
      expect(
        Encounters.boss(random).spawns.first.def,
        isIn([Enemies.tank, Enemies.colonel, Enemies.argos]),
      );
    }
  });
}
