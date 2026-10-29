import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/enemy_behaviors.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/element.dart';
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

final shot = shotOf(Element.neutral, family: ChipFamily.projectile);

void main() {
  group('ruins enemies', () {
    test('ET Escudeiro blocks shots from the front', () {
      final battle = battleWith(
        [shot],
        spawns: [const EnemySpawn(Enemies.etShieldBearer, GridPos(3, 1))],
      );
      final bearer = battle.enemies.single
        ..pos = const GridPos(3, 1)
        ..applyStatus(Status.stunned, 100000);
      use(battle, shot);
      expect(bearer.hp, Enemies.etShieldBearer.hp);
    });

    test('ET Escudeiro drops the shield to fire, and a moment after', () {
      final battle = battleWith(
        [shot],
        spawns: [const EnemySpawn(Enemies.etShieldBearer, GridPos(3, 1))],
      );
      final bearer = battle.enemies.single..pos = const GridPos(3, 1);
      battle.player.pos = const GridPos(1, 1);
      until(battle, () => battle.ticksToAttack(bearer) != null);
      expect(bearer.shieldDown, greaterThan(ShieldBearerBehavior.openTicks));
      bearer.applyStatus(Status.stunned, 100000);
      use(battle, shot);
      expect(bearer.hp, lessThan(Enemies.etShieldBearer.hp));
    });

    test('ET Escudeiro moves in front of an ally', () {
      final battle = battleWith(
        [],
        spawns: [
          const EnemySpawn(Enemies.etShieldBearer, GridPos(5, 0)),
          EnemySpawn(dummyOf(Element.neutral), const GridPos(5, 2)),
        ],
      );
      final [bearer, ally] = battle.enemies;
      ally.applyStatus(Status.stunned, 100000);
      wait(battle, 6 * ShieldBearerBehavior.moveTicks);
      expect(bearer.pos, const GridPos(4, 2));
    });

    test('ET Curandeiro heals the most hurt ally', () {
      final battle = battleWith(
        [],
        spawns: [
          const EnemySpawn(Enemies.etHealer, GridPos(5, 0)),
          dummyAt(4, 2),
        ],
      );
      final ally = battle.enemies.last..hp = 50;
      wait(battle, HealerBehavior.cycleTicks + HealerBehavior.castTicks + 2);
      expect(ally.hp, 50 + HealerBehavior.heal);
    });

    test('Sentinela Ancestral sweeps the rows in turn', () {
      final battle = battleWith(
        [],
        spawns: [const EnemySpawn(Enemies.sentinel, GridPos(5, 1))],
      );
      wait(battle, SentinelBehavior.cycleTicks ~/ 2 + 1);
      expect(warned(battle), {
        const GridPos(0, 0),
        const GridPos(1, 0),
        const GridPos(2, 0),
      });
      wait(battle, SentinelBehavior.cycleTicks + 1);
      expect(warned(battle), contains(const GridPos(1, 1)));
      wait(battle, SentinelBehavior.warnTicks);
      expect(battle.player.hp, 100 - SentinelBehavior.damage);
    });

    test('Escaravelho Mecânico crawls to the player and blows up', () {
      final battle = battleWith(
        [],
        spawns: [
          const EnemySpawn(Enemies.scarab, GridPos(3, 1)),
          dummyAt(5, 0),
        ],
      );
      until(battle, () => battle.player.hp < 100);
      expect(battle.player.hp, 100 - TickBehavior.damage);
    });
  });

  group('ruins elites', () {
    test('Sacerdotisa ET blinks with 2 copies; copies die to any hit', () {
      final battle = battleWith(
        [],
        spawns: [const EnemySpawn(Enemies.priestess, GridPos(5, 1))],
      );
      wait(battle, ticksPerSecond + 1);
      final copies = battle.enemies
          .where((e) => e.def == Enemies.illusion)
          .toList();
      expect(copies, hasLength(PriestessBehavior.illusions));
      final real = battle.enemies.first;
      battle.damage(copies.first, 5);
      battle.tick();
      expect(battle.enemies, isNot(contains(copies.first)));
      expect(real.hp, Enemies.priestess.hp);
      until(battle, () => battle.player.hp < 100);
      expect(battle.player.hp, 100 - PriestessBehavior.damage);
    });

    test('Portal Ancestral lets out ETs and drops its ring meanwhile', () {
      final battle = battleWith(
        [],
        spawns: [const EnemySpawn(Enemies.portal, GridPos(5, 1))],
      );
      final portal = battle.enemies.single;
      expect(portal.shieldDown, 0);
      wait(battle, PortalBehavior.spawnEvery ~/ 2 + 1);
      expect(battle.enemies, hasLength(2));
      expect(portal.shieldDown, greaterThan(0));
    });

    test('Golem das Ruínas hammers the player column', () {
      final battle = battleWith(
        [],
        spawns: [const EnemySpawn(Enemies.ruinGolem, GridPos(4, 0))],
      );
      until(battle, () => battle.player.hp < 100);
      expect(battle.player.hp, 100 - ColossusBehavior.damage);
    });
  });

  group('Rei da Tribo', () {
    BattleState kingFight([List<ChipDef> chips = const []]) => battleWith(
      chips,
      spawns: [const EnemySpawn(Enemies.tribeKing, GridPos(4, 1))],
    );

    List<EnemyFighter> totems(BattleState battle) => [
      for (final e in battle.enemies)
        if (e.def == Enemies.totem || e.def == Enemies.ragingTotem) e,
    ];

    test('starts behind 2 totems and is hurt only once they fall', () {
      final battle = kingFight();
      final king = battle.enemies.first;
      expect(totems(battle), hasLength(2));
      expect(king.invulnerable, isTrue);
      battle.damage(king, 50);
      expect(king.hp, Enemies.tribeKing.hp);
      for (final totem in totems(battle)) {
        totem.hp = 0;
      }
      wait(battle, 2);
      expect(king.invulnerable, isFalse);
      battle.damage(king, 50);
      expect(king.hp, Enemies.tribeKing.hp - 50);
      wait(battle, TribeKingBehavior.totemReturn + 2);
      expect(totems(battle), hasLength(2), reason: 'they come back');
    });

    test('Onda Crescente spares one row of the player side', () {
      final battle = kingFight();
      wait(battle, TribeKingBehavior.attackEvery ~/ 2 + 1);
      final cells = warned(battle);
      expect(cells, hasLength(6));
      final rows = {for (final c in cells) c.y};
      expect(rows, hasLength(2));
    });

    test('Raio do Cajado overheats the staff, leaving the floor whole', () {
      final battle = kingFight();
      final king = battle.enemies.first..attackTimer = 1;
      for (final totem in totems(battle)) {
        totem.hp = 0;
      }
      wait(battle, TribeKingBehavior.attackEvery ~/ 2 + 1);
      final bolts = warned(battle);
      expect(bolts, hasLength(TribeKingBehavior.lightningBolts));
      wait(battle, TribeKingBehavior.lightningWarn);
      for (final cell in bolts) {
        expect(battle.panelAt(cell).state, PanelState.normal);
      }
      expect(king.exposedTicks, greaterThan(0));
      final before = king.hp;
      battle.damage(king, 10);
      expect(king.hp, before - 20);
    });

    test('Chamado da Tribo: his ETs do not keep the fight going', () {
      final battle = kingFight();
      final king = battle.enemies.first..attackTimer = 2;
      wait(battle, TribeKingBehavior.attackEvery + 1);
      expect(
        battle.enemies.where(
          (e) => e.def == Enemies.tribeWarrior || e.def == Enemies.tribeGunner,
        ),
        hasLength(1),
      );
      king.hp = 0;
      battle.tick();
      expect(battle.phase, BattlePhase.won);
    });

    test('Fúria below half HP: takes column 2 and toughens the totems', () {
      final battle = kingFight();
      final king = battle.enemies.first;
      for (final totem in totems(battle)) {
        totem.hp = 0;
      }
      wait(battle, 2);
      king.hp = king.maxHp ~/ 2 - 1;
      wait(battle, 2);
      expect(king.stage, 1);
      expect(battle.ownerAt(const GridPos(2, 1)), Team.enemy);
      wait(battle, TribeKingBehavior.totemReturn + 2);
      expect(totems(battle).map((t) => t.def).toSet(), {Enemies.ragingTotem});
    });

    test('Energia breaks the totems fast (they are Máquinas)', () {
      final battle = kingFight();
      final totem = totems(battle).first;
      battle.damage(totem, 10, family: ChipFamily.energy);
      expect(totem.hp, Enemies.totem.hp - 20);
    });
  });
}
