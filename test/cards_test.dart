import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

/// Cards added with the StarCop theme.
void main() {
  test('SMG fires 3 shots of 5', () {
    final battle = battleWith([Chips.smg], spawns: [dummyAt(3, 1)]);
    use(battle, Chips.smg);
    wait(battle, 5);
    expect(battle.enemies.single.hp, 100 - 3 * 5);
  });

  test('Bala Oca boosts every shot of the SMG burst', () {
    final battle = battleWith(
      [Chips.atkBoost, Chips.smg],
      spawns: [dummyAt(3, 1)],
    );
    use(battle, Chips.atkBoost);
    use(battle, Chips.smg);
    wait(battle, 5);
    expect(battle.enemies.single.hp, 100 - 3 * 15);
    expect(battle.damageBonus, 0);
  });

  test('Melta hits the 3 enemy columns of the row with Fire', () {
    final battle = battleWith(
      [Chips.melta],
      spawns: [dummyAt(3, 1), dummyAt(5, 1), dummyAt(4, 0)],
    );
    use(battle, Chips.melta);
    expect(battle.enemies.map((e) => e.hp), [90, 90, 100]);
    expect(Chips.melta.element, Element.fire);
  });

  test('Plasma is the Elec V-shot', () {
    expect(Chips.vShot.name, 'Plasma');
    expect(Chips.vShot.element, Element.elec);
  });

  test('Míssil travels the row and explodes in a cross', () {
    final battle = battleWith(
      [Chips.missile],
      spawns: [dummyAt(4, 1), dummyAt(4, 0), dummyAt(5, 1), dummyAt(5, 0)],
    );
    use(battle, Chips.missile);
    wait(battle, 5);
    final hit = 100 - boom(Chips.missile.damage);
    expect(battle.enemies.map((e) => e.hp), [hit, hit, hit, 100]);
  });

  BattleState atFront(List<GridPos> enemies, List<ChipDef> chips) {
    final battle = battleWith(
      chips,
      spawns: [for (final p in enemies) dummyAt(p.x, p.y)],
    );
    battle.tick(const PlayerInput(dx: 1));
    wait(battle, playerMoveCooldown);
    expect(battle.player.pos, const GridPos(2, 1));
    return battle;
  }

  test('Cacetete hits the 3 panels in front and stuns for 2 s', () {
    final battle = atFront(
      const [GridPos(3, 0), GridPos(3, 2), GridPos(4, 1)],
      [Chips.baton],
    );
    use(battle, Chips.baton);
    final [top, bottom, behind] = battle.enemies;
    expect([top.hp, bottom.hp, behind.hp], [90, 90, 100]);
    expect(
      top.statuses[Status.stunned],
      greaterThan(2 * ticksPerSecond - playerAttackCooldown - 2),
    );
    expect(behind.has(Status.stunned), isFalse);
  });

  test('Espada hits the 3 panels in front for 20, without stun', () {
    final battle = atFront(const [GridPos(3, 1)], [Chips.sword]);
    use(battle, Chips.sword);
    expect(battle.enemies.single.hp, 80);
    expect(battle.enemies.single.has(Status.stunned), isFalse);
  });

  test('Espada shows one slash in front, not an explosion per panel', () {
    final battle = atFront(const [GridPos(3, 1)], [Chips.sword]);
    battle
      ..selectChip(0)
      ..tick(const PlayerInput(useChip: true));
    expect(battle.flashes.single.kind, FlashKind.slash);
    expect(battle.flashes.single.pos, const GridPos(3, 1));
  });

  test('Granada lands 3 panels ahead, wherever the enemies are', () {
    final battle = battleWith(
      [Chips.grenade],
      spawns: [dummyAt(4, 1), dummyAt(4, 0), dummyAt(5, 0), dummyAt(3, 0)],
    );
    use(battle, Chips.grenade);
    final hit = 100 - boom(Chips.grenade.damage);
    expect(battle.enemies.map((e) => e.hp), [hit, hit, 100, 100]);
    expect(battle.panelAt(const GridPos(4, 1)).state, PanelState.normal);
  });

  test('Granada Incendiária: 15 Fire in a cross, lava in the middle', () {
    final battle = battleWith(
      [Chips.incendiaryGrenade],
      spawns: [dummyAt(5, 1), dummyAt(4, 2)],
    );
    use(battle, Chips.incendiaryGrenade);
    final hit = 100 - boom(Chips.incendiaryGrenade.damage);
    expect(battle.enemies.map((e) => e.hp), [hit, hit]);
    expect(battle.panelAt(const GridPos(4, 1)).state, PanelState.lava);
    expect(Chips.incendiaryGrenade.element, Element.fire);
  });

  test('Granada Atordoante stuns everyone in the cross for 2 s', () {
    final battle = battleWith(
      [Chips.stunGrenade],
      spawns: [dummyAt(4, 1), dummyAt(4, 0), dummyAt(5, 0)],
    );
    use(battle, Chips.stunGrenade);
    final [center, side, outside] = battle.enemies;
    for (final hit in [center, side]) {
      expect(
        hit.statuses[Status.stunned],
        greaterThan(2 * ticksPerSecond - playerAttackCooldown),
      );
      expect(hit.hp, 100, reason: 'no damage');
    }
    expect(outside.has(Status.stunned), isFalse);
    expect(battle.energy, baseEnergy - 2);
    expect(Chips.stunGrenade.element, Element.elec);
  });

  group('Granada de Fumaça', () {
    test('explodes in a cross for 10 and leaves smoke for 10 s', () {
      final battle = battleWith(
        [Chips.smokeGrenade],
        spawns: [dummyAt(4, 1), dummyAt(5, 1)],
      );
      use(battle, Chips.smokeGrenade);
      final hit = 100 - boom(Chips.smokeGrenade.damage);
      expect(battle.enemies.map((e) => e.hp), [hit, hit]);
      final panel = battle.panelAt(const GridPos(4, 1));
      expect(panel.smoky, isTrue);
      expect(battle.panelAt(const GridPos(5, 1)).smoky, isFalse);
      wait(battle, smokeDurationTicks);
      expect(panel.smoky, isFalse);
    });

    test('an enemy in the smoke cannot attack', () {
      final battle = battleWith(
        [],
        spawns: [const EnemySpawn(Enemies.gruntDuck, GridPos(4, 1))],
      );
      battle.panelAt(const GridPos(4, 1)).smokeTicks = 10000;
      wait(battle, 6 * ticksPerSecond);
      expect(battle.player.hp, 100);
      expect(battle.projectiles, isEmpty);
    });

    test('anyone can walk in, but the player cannot use cards there', () {
      final battle = battleWith([Chips.shot], spawns: [dummyAt(4, 1)]);
      battle.panelAt(const GridPos(2, 1)).smokeTicks = 10000;
      battle.tick(const PlayerInput(dx: 1));
      expect(battle.player.pos, const GridPos(2, 1));
      wait(battle, playerMoveCooldown);
      battle.tick(const PlayerInput(useChip: true));
      wait(battle, 10);
      expect(battle.hand, hasLength(1));
      expect(battle.enemies.single.hp, 100);
    });
  });

  test('Primeiros Socorros heals 5 for 2 energy, single use', () {
    final battle = battleWith([Chips.recover]);
    battle.player.hp = 50;
    use(battle, Chips.recover);
    expect(battle.player.hp, 55);
    expect(battle.energy, baseEnergy - 2);
    expect(battle.deck.discardPile, isEmpty);
  });

  test('Gerador de Energia: gauge 20% faster, single use', () {
    final battle = battleWith([Chips.powerGenerator]);
    use(battle, Chips.powerGenerator);
    final before = battle.gauge;
    wait(battle, 100);
    expect(battle.gauge, before + 120);
    expect(battle.hand, isEmpty);
    expect(battle.deck.discardPile, isEmpty);
  });
}
