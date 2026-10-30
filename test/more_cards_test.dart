import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

BattleState withDummies(List<GridPos> enemies, List<ChipDef> chips) =>
    battleWith(chips, spawns: [for (final p in enemies) dummyAt(p.x, p.y)]);

/// The player steps to (2, 1), right in front of the enemy side.
BattleState atFront(List<GridPos> enemies, List<ChipDef> chips) {
  final battle = withDummies(enemies, chips);
  battle.tick(const PlayerInput(dx: 1));
  wait(battle, playerMoveCooldown);
  return battle;
}

void main() {
  test('Rifle de Precisão: +15 on a target in the back column', () {
    final far = withDummies([const GridPos(5, 1)], [Chips.sniper]);
    use(far, Chips.sniper);
    wait(far, 30);
    expect(far.enemies.single.hp, 55);
    final near = withDummies([const GridPos(3, 1)], [Chips.sniper]);
    use(near, Chips.sniper);
    expect(near.enemies.single.hp, 70);
  });

  test('Bala Incendiária burns', () {
    final battle = withDummies([const GridPos(3, 1)], [Chips.incendiaryRound]);
    use(battle, Chips.incendiaryRound);
    expect(battle.enemies.single.has(Status.burning), isTrue);
  });

  test('Tiro Perfurante hits the whole row', () {
    final battle = withDummies(
      [const GridPos(3, 1), const GridPos(5, 1)],
      [Chips.piercingShot],
    );
    use(battle, Chips.piercingShot);
    for (final enemy in battle.enemies) {
      expect(enemy.hp, 88);
    }
  });

  test('Dardo Tranquilizante stuns', () {
    final battle = withDummies([const GridPos(3, 1)], [Chips.tranqDart]);
    use(battle, Chips.tranqDart);
    expect(battle.enemies.single.hp, 95);
    expect(battle.enemies.single.has(Status.stunned), isTrue);
  });

  test('Granada de Fragmentação hits a 3x3 square, single use', () {
    final battle = withDummies(
      [const GridPos(3, 0), const GridPos(5, 2)],
      [Chips.fragGrenade],
    );
    use(battle, Chips.fragGrenade);
    wait(battle, 30);
    for (final enemy in battle.enemies) {
      expect(enemy.hp, 100 - boom(15));
    }
    expect(battle.deck.discardPile, isEmpty);
  });

  test('Morteiro lands 4 panels ahead', () {
    final battle = withDummies([const GridPos(5, 1)], [Chips.mortar]);
    use(battle, Chips.mortar);
    wait(battle, 30);
    expect(battle.enemies.single.hp, 100 - boom(20));
  });

  test('Bomba de Fissura cracks the column it hits', () {
    final battle = withDummies([const GridPos(4, 0)], [Chips.fissureBomb]);
    use(battle, Chips.fissureBomb);
    wait(battle, 30);
    expect(battle.enemies.single.hp, 100 - boom(10));
    for (var y = 0; y < 3; y++) {
      // Cracked, or already a hole if the dummy stepped off it.
      expect(
        battle.panelAt(GridPos(4, y)).state,
        isIn([PanelState.cracked, PanelState.hole]),
      );
    }
  });

  test(
    'Laser de Fusão hits the row and turns the first enemy panel to Lava',
    () {
      final battle = withDummies(
        [const GridPos(4, 1), const GridPos(5, 1)],
        [Chips.fusionLaser],
      );
      use(battle, Chips.fusionLaser);
      expect(battle.enemies.last.hp, 85);
      expect(battle.panelAt(const GridPos(4, 1)).state, PanelState.lava);
      expect(battle.panelAt(const GridPos(5, 1)).state, PanelState.normal);
    },
  );

  test('Raio Congelante wets and freezes the target panel', () {
    final battle = withDummies([const GridPos(3, 1)], [Chips.freezeRay]);
    use(battle, Chips.freezeRay);
    expect(battle.enemies.single.has(Status.wet), isTrue);
    expect(battle.panelAt(const GridPos(3, 1)).state, PanelState.ice);
  });

  test('Feixe Contínuo fires 4 shots', () {
    final battle = withDummies([const GridPos(3, 1)], [Chips.steadyBeam]);
    use(battle, Chips.steadyBeam);
    wait(battle, 30);
    expect(battle.enemies.single.hp, 80);
  });

  test('Adaga hits the panel in front for free', () {
    final battle = atFront([const GridPos(3, 1)], [Chips.dagger]);
    final energy = battle.energy;
    use(battle, Chips.dagger);
    expect(battle.enemies.single.hp, 94);
    expect(battle.energy, energy);
  });

  test('Lâmina Térmica burns the 3 panels in front', () {
    final battle = atFront(
      [const GridPos(3, 0), const GridPos(3, 2)],
      [Chips.thermalBlade],
    );
    use(battle, Chips.thermalBlade);
    for (final enemy in battle.enemies) {
      expect(enemy.has(Status.burning), isTrue);
    }
  });

  test('Foice hits the diagonals only', () {
    final battle = atFront(
      [const GridPos(3, 0), const GridPos(3, 1), const GridPos(3, 2)],
      [Chips.scythe],
    );
    use(battle, Chips.scythe);
    expect(battle.enemies.map((e) => e.hp), [85, 100, 85]);
  });

  test('Punho Hidráulico pushes 3 panels', () {
    final battle = atFront([const GridPos(3, 1)], [Chips.hydraulicFist]);
    use(battle, Chips.hydraulicFist);
    wait(battle, 30);
    expect(battle.enemies.single.hp, lessThanOrEqualTo(75));
    expect(battle.enemies.single.pos, const GridPos(5, 1));
  });

  test('Torre Incendiária fires a burning Fire shot', () {
    final battle = withDummies([const GridPos(3, 1)], [Chips.fireTurret]);
    use(battle, Chips.fireTurret);
    final turret = battle.obstacles.single;
    expect(turret.hp, turretHp);
    expect(turret.fireEvery, fireTurretEvery);
    wait(battle, 2 * ticksPerSecond);
    expect(battle.enemies.single.has(Status.burning), isTrue);
  });

  test('Campo Minado hides 2 mines', () {
    final battle = withDummies([const GridPos(5, 2)], [Chips.minefield]);
    use(battle, Chips.minefield);
    wait(battle, 30);
    var mines = 0;
    for (var x = 0; x < gridColumns; x++) {
      for (var y = 0; y < gridRows; y++) {
        if (battle.panelAt(GridPos(x, y)).mine) mines++;
      }
    }
    expect(mines, 2);
  });

  test('Estimulante: +3 Energia, single use', () {
    final battle = withDummies([const GridPos(3, 1)], [Chips.stimulant]);
    use(battle, Chips.stimulant);
    expect(battle.energy, baseEnergy - 1 + 3);
    expect(battle.deck.discardPile, isEmpty);
  });

  test(
    'Munição Especial: Projectile cards deal +3 for the rest of the battle',
    () {
      final battle = withDummies(
        [const GridPos(3, 1)],
        [Chips.specialAmmo, Chips.shot],
      );
      use(battle, Chips.specialAmmo);
      use(battle, Chips.shot);
      expect(battle.enemies.single.hp, 100 - Chips.shot.damage - 3);
      expect(battle.projectileBonus, 3);
    },
  );

  test('Análise de Combate marks and Interferência stuns every enemy', () {
    final battle = withDummies(
      [const GridPos(3, 0), const GridPos(5, 2)],
      [Chips.combatScan, Chips.jammer],
    );
    use(battle, Chips.combatScan);
    use(battle, Chips.jammer);
    for (final enemy in battle.enemies) {
      expect(enemy.has(Status.marked), isTrue);
      expect(enemy.has(Status.stunned), isTrue);
    }
  });

  test('every new card has an upgrade', () {
    for (final def in [
      Chips.sniper,
      Chips.incendiaryRound,
      Chips.piercingShot,
      Chips.tranqDart,
      Chips.fragGrenade,
      Chips.mortar,
      Chips.fissureBomb,
      Chips.fusionLaser,
      Chips.freezeRay,
      Chips.steadyBeam,
      Chips.dagger,
      Chips.thermalBlade,
      Chips.scythe,
      Chips.hydraulicFist,
      Chips.fireTurret,
      Chips.minefield,
      Chips.stimulant,
      Chips.specialAmmo,
      Chips.combatScan,
      Chips.jammer,
    ]) {
      expect(Chips.upgradeOf(def), isNotNull, reason: def.name);
      expect(Chips.byId(def.id), def);
    }
  });
}
