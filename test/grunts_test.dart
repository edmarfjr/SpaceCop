import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/enemy_behaviors.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

/// The first mission: the criminal organization's capangas and its tank.
void main() {
  BattleState against(EnemyDef def, GridPos pos) =>
      battleWith([Chips.mirror, Chips.shot], spawns: [EnemySpawn(def, pos)]);

  /// Ticks [battle] until [enemy] attacks, checking it only does so in the
  /// player's row.
  void attacksLinedUp(BattleState battle, EnemyFighter enemy) {
    for (var i = 0; i < 300 && battle.telegraphs.isEmpty; i++) {
      final y = enemy.pos.y;
      battle.tick();
      if (battle.telegraphs.isNotEmpty) {
        expect(y, battle.player.pos.y, reason: 'only attacks lined up');
      }
    }
    expect(battle.telegraphs, isNotEmpty);
  }

  /// Ticks until something is telegraphed (at most [limit]).
  void untilWarned(BattleState battle, {int limit = 300}) {
    for (var i = 0; i < limit && battle.telegraphs.isEmpty; i++) {
      battle.tick();
    }
    expect(battle.telegraphs, isNotEmpty);
  }

  Set<GridPos> warned(BattleState battle) => {
    for (final t in battle.telegraphs) t.pos,
  };

  test('Capanga Atirador wanders, then stands still to shoot its row', () {
    final battle = against(Enemies.gruntGun, const GridPos(4, 0));
    final grunt = battle.enemies.single;
    untilWarned(battle);
    final pos = grunt.pos;
    expect(warned(battle), {for (var x = 0; x < pos.x; x++) GridPos(x, pos.y)});
    expect(battle.tryMove(grunt, const GridPos(0, 1)), isFalse);
    wait(battle, basicWarnTicks);
    expect(battle.projectiles, hasLength(1));
    expect(grunt.pos, pos);
  });

  test('ticksToAttack counts down to the attack, then clears', () {
    final battle = against(Enemies.gruntGrenade, const GridPos(4, 1));
    final grunt = battle.enemies.single;
    expect(battle.ticksToAttack(grunt), isNull);
    untilWarned(battle);
    // Scheduled and counted down within the same tick.
    expect(battle.ticksToAttack(grunt), basicWarnTicks - 1);
    wait(battle, basicWarnTicks - 1 - ticksPerSecond ~/ 2);
    expect(battle.ticksToAttack(grunt), ticksPerSecond ~/ 2);
    wait(battle, ticksPerSecond ~/ 2);
    expect(battle.ticksToAttack(grunt), isNull);
  });

  test('Capanga Atirador only shoots from the player row', () {
    for (final start in const [GridPos(4, 0), GridPos(5, 2)]) {
      final battle = against(Enemies.gruntGun, start);
      attacksLinedUp(battle, battle.enemies.single);
    }
  });

  test('Capanga Corpo-a-Corpo only dashes from the player row', () {
    for (final start in const [GridPos(4, 0), GridPos(5, 2)]) {
      final battle = against(Enemies.gruntMelee, start);
      attacksLinedUp(battle, battle.enemies.single);
    }
  });

  test('Capanga Atirador Agachado never moves and fires 3 shots', () {
    final battle = against(Enemies.gruntDuck, const GridPos(4, 0));
    final grunt = battle.enemies.single;
    untilWarned(battle);
    wait(battle, basicWarnTicks + 2 * 8);
    expect(battle.projectiles, hasLength(3));
    wait(battle, 300);
    expect(grunt.pos, const GridPos(4, 0));
  });

  test('Capanga Corpo-a-Corpo moves next to the player, slashes 0.5 s '
      'later and goes back', () {
    final battle = against(Enemies.gruntMelee, const GridPos(4, 0));
    final grunt = battle.enemies.single;
    var origin = grunt.pos;
    for (var i = 0; i < 300 && battle.telegraphs.isEmpty; i++) {
      origin = grunt.pos;
      battle.tick();
    }
    expect(grunt.pos, const GridPos(2, 1), reason: 'right of the player');
    expect(warned(battle), {const GridPos(1, 1)});
    expect(grunt.attackFrame, isFalse, reason: 'walking frame until it hits');
    wait(battle, minWarnTicks - 2);
    expect(grunt.attackFrame, isFalse);
    expect(battle.player.hp, 100);
    wait(battle, 2);
    expect(battle.player.hp, 100 - GruntMeleeBehavior.damage);
    expect(grunt.attackFrame, isTrue);
    wait(battle, attackPoseTicks + 1);
    expect(grunt.pos, origin, reason: 'back where it came from');
  });

  test('the Corpo-a-Corpo slash can be dodged', () {
    final battle = against(Enemies.gruntMelee, const GridPos(4, 0));
    untilWarned(battle);
    battle.tick(const PlayerInput(dy: -1));
    wait(battle, minWarnTicks);
    expect(battle.player.pos, const GridPos(1, 0));
    expect(battle.player.hp, 100);
  });

  test('Capanga Granada sets the player panel on fire', () {
    final battle = against(Enemies.gruntGrenade, const GridPos(4, 0));
    untilWarned(battle);
    expect(warned(battle), {const GridPos(1, 1)});
    wait(battle, basicWarnTicks);
    expect(battle.player.hp, 100 - GruntGrenadeBehavior.damage);
    expect(battle.panelAt(const GridPos(1, 1)).state, PanelState.lava);
  });

  test('Capanga Artilharia fires a missile at the player panel', () {
    final battle = against(Enemies.gruntArtillery, const GridPos(5, 0));
    untilWarned(battle);
    expect(warned(battle), {const GridPos(1, 1)});
    expect(
      battle.telegraphs.single.ticksLeft,
      greaterThan(basicWarnTicks),
      reason: 'longer warning',
    );
    wait(battle, GruntArtilleryBehavior.warnTicks);
    expect(battle.player.hp, 100 - GruntArtilleryBehavior.damage);
    expect(battle.enemies.single.pos, const GridPos(5, 0));
    expect(Enemies.gruntArtillery.pushable, isFalse);
  });

  test('Torreta hides, rises to shoot and hides again', () {
    final battle = against(Enemies.sentry, const GridPos(4, 1));
    final sentry = battle.enemies.single;
    expect(sentry.hidden, isTrue);
    use(battle, Chips.shot);
    wait(battle, 5);
    expect(sentry.hp, Enemies.sentry.hp, reason: 'shots pass over it');

    untilWarned(battle);
    expect(sentry.hidden, isFalse);
    expect(sentry.buried, 0);
    wait(battle, basicWarnTicks);
    expect(battle.projectiles.where((p) => p.team == Team.enemy), hasLength(1));
    wait(battle, attackPoseTicks + SentryBehavior.riseTicks + 1);
    expect(sentry.hidden, isTrue);
    expect(sentry.pos, const GridPos(4, 1));
  });

  group('Tanque de Guerra', () {
    /// The tank (front panel at column 4), about to pick attack [index] (0
    /// burst, 1 missiles, 2 charge), with its patrol switched off.
    (BattleState, EnemyFighter) tankAbout(int index) {
      final battle = against(Enemies.tank, const GridPos(4, 1));
      final tank = battle.enemies.single
        ..pos = const GridPos(4, 1)
        ..moveTimer = 10000
        ..attackTimer = index
        ..timer = 0;
      return (battle, tank);
    }

    test('is the only boss of the first mission, on the back 2 columns', () {
      final spawn = Encounters.boss(battleWith([]).random).spawns.single;
      expect(spawn.def, Enemies.tank);
      expect(spawn.pos.x, gridColumns - 2);
    });

    test('takes 2 panels and can be hit on either', () {
      final (battle, tank) = tankAbout(0);
      expect(battle.unitAt(const GridPos(4, 1)), tank);
      expect(battle.unitAt(const GridPos(5, 1)), tank);
      battle.strike(const GridPos(5, 1), 10, Team.enemy, Element.neutral);
      expect(tank.hp, Enemies.tank.hp - 10);
      // A strike over both panels hits it once.
      final struck = <Fighter>{};
      for (final x in [4, 5]) {
        battle.strike(
          GridPos(x, 1),
          10,
          Team.enemy,
          Element.neutral,
          struck: struck,
        );
      }
      expect(tank.hp, Enemies.tank.hp - 20);
    });

    test('patrols up and down with both panels', () {
      final (battle, tank) = tankAbout(0);
      expect(battle.tryMove(tank, const GridPos(0, -1)), isTrue);
      expect(tank.cells, [const GridPos(4, 0), const GridPos(5, 0)]);
      battle.obstacles.add(
        Obstacle(ObstacleKind.rock, pos: const GridPos(5, 1), hp: rockHp),
      );
      expect(
        battle.tryMove(tank, const GridPos(0, 1)),
        isFalse,
        reason: 'its back panel is blocked',
      );
    });

    test('burst: 3 shots down its row', () {
      final (battle, _) = tankAbout(0);
      wait(battle, 3 * ticksPerSecond);
      expect(battle.player.hp, 100 - 3 * Enemies.tank.shotDamage);
    });

    test('missiles: 3 random panels of the player side', () {
      final (battle, _) = tankAbout(1);
      battle.tick();
      expect(battle.telegraphs, hasLength(3));
      expect(
        battle.telegraphs.map((t) => battle.ownerAt(t.pos)),
        everyElement(Team.player),
      );
    });

    /// Runs the charge until the tank leaves the arena; returns the ticks it
    /// took from the end of the warning.
    int charge(BattleState battle, EnemyFighter tank) {
      battle.tick();
      expect(warned(battle), {for (var x = 0; x < 4; x++) GridPos(x, 1)});
      wait(battle, TankBehavior.chargeWarnTicks);
      var ticks = 0;
      var minX = tank.pos.x;
      for (; ticks < 40 && !tank.hidden; ticks++) {
        battle.tick();
        if (tank.pos.x < minX) minX = tank.pos.x;
      }
      expect(minX, 0);
      expect(tank.hidden, isTrue);
      return ticks;
    }

    test('charge: pushes the player 1 panel, then comes back on the right', () {
      final (battle, tank) = tankAbout(2);
      final ticks = charge(battle, tank);
      expect(ticks, lessThanOrEqualTo(4 * 2 + 2), reason: '1 panel / 2 ticks');
      expect(battle.player.pos, const GridPos(0, 1));
      expect(
        battle.player.hp,
        100 - TankBehavior.chargeDamage,
        reason: 'room to be pushed: no collision',
      );
      expect(tank.pos.x, gridColumns - 2, reason: 'moved back while hidden');
      wait(battle, TankBehavior.awayTicks + 2);
      expect(tank.hidden, isFalse);
      expect(tank.cells, [const GridPos(4, 1), const GridPos(5, 1)]);
    });

    test('charge against the back wall adds the collision damage', () {
      final (battle, tank) = tankAbout(2);
      battle.player.pos = const GridPos(0, 1);
      charge(battle, tank);
      expect(battle.player.pos, const GridPos(0, 1));
      expect(
        battle.player.hp,
        100 - TankBehavior.chargeDamage - collisionDamage,
      );
      expect(battle.player.has(Status.stunned), isTrue);
    });

    test('charge runs over obstacles in its way', () {
      final (battle, tank) = tankAbout(2);
      battle.obstacles.add(
        Obstacle(ObstacleKind.rock, pos: const GridPos(2, 1), hp: rockHp),
      );
      wait(battle, TankBehavior.chargeWarnTicks + 20);
      expect(battle.obstacles.single.hp, rockHp - TankBehavior.chargeDamage);
      expect(tank.isDead, isFalse);
    });
  });

  group('Escudo Refletor', () {
    void reflectorThen(BattleState battle) {
      untilWarned(battle);
      battle
        ..selectChip(battle.hand.indexWhere((c) => c.def == Chips.mirror))
        ..tick(const PlayerInput(useChip: true));
      wait(battle, ticksPerSecond + 20);
    }

    test('bounces the Capanga Atirador shot back', () {
      final battle = against(Enemies.gruntGun, const GridPos(4, 0));
      final grunt = battle.enemies.single;
      reflectorThen(battle);
      expect(battle.player.hp, 100);
      expect(grunt.hp, Enemies.gruntGun.hp - 2 * Enemies.gruntGun.shotDamage);
    });

    test('does not stop lobbed grenades', () {
      final battle = against(Enemies.gruntGrenade, const GridPos(4, 0));
      reflectorThen(battle);
      expect(
        battle.player.hp,
        lessThanOrEqualTo(100 - GruntGrenadeBehavior.damage),
      );
    });
  });
}
