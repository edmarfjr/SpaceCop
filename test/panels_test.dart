import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

void main() {
  test('cracked turns into a hole when its unit leaves, heals when empty', () {
    final battle = battleWith([])
      ..setPanel(const GridPos(1, 1), PanelState.cracked);
    wait(battle, crackedTicks + 5);
    expect(battle.panelAt(const GridPos(1, 1)).state, PanelState.cracked);
    battle.tick(const PlayerInput(dy: -1));
    expect(battle.player.pos, const GridPos(1, 0));
    expect(battle.panelAt(const GridPos(1, 1)).state, PanelState.hole);

    battle.setPanel(const GridPos(0, 2), PanelState.cracked);
    wait(battle, crackedTicks);
    expect(battle.panelAt(const GridPos(0, 2)).state, PanelState.normal);
  });

  test('nobody enters a hole, shots fly over it, it heals after 10 s', () {
    final battle = battleWith([Chips.shot])
      ..setPanel(const GridPos(2, 1), PanelState.hole);
    battle.tick(const PlayerInput(dx: 1));
    expect(battle.player.pos, const GridPos(1, 1));
    use(battle, Chips.shot);
    expect(battle.enemies.single.hp, 100 - Chips.shot.damage);
    wait(battle, holeTicks);
    expect(battle.panelAt(const GridPos(2, 1)).state, PanelState.normal);
  });

  test('ice slides the mover to the edge and Elec on it stuns', () {
    final battle = battleWith([shotOf(Element.elec)])
      ..player.pos = const GridPos(0, 1)
      ..setPanel(const GridPos(1, 1), PanelState.ice);
    battle.tick(const PlayerInput(dx: 1));
    expect(battle.player.pos, const GridPos(2, 1));

    battle
      ..player.pos = const GridPos(1, 1)
      ..setPanel(const GridPos(3, 1), PanelState.ice);
    use(battle, shotOf(Element.elec));
    expect(battle.enemies.single.has(Status.stunned), isTrue);
    wait(battle, iceTicks);
    expect(battle.panelAt(const GridPos(3, 1)).state, PanelState.normal);
  });

  test('grass heals, boosts Wood chips, doubles Fire and burns away', () {
    final battle = battleWith([shotOf(Element.wood), shotOf(Element.fire)])
      ..setPanel(const GridPos(1, 1), PanelState.grass)
      ..setPanel(const GridPos(3, 1), PanelState.grass);
    battle.player.hp = 50;
    final ticksToSecond = ticksPerSecond - battle.ticks % ticksPerSecond;
    wait(battle, ticksToSecond);
    expect(battle.player.hp, 50 + grassHeal);

    final enemy = battle.enemies.single;
    use(battle, shotOf(Element.wood));
    expect(enemy.hp, 100 - 13);
    use(battle, shotOf(Element.fire));
    expect(enemy.hp, 100 - 13 - 20);
    expect(battle.panelAt(const GridPos(3, 1)).state, PanelState.normal);
    wait(battle, grassTicks);
    expect(battle.panelAt(const GridPos(1, 1)).state, PanelState.normal);
  });

  test('lava burns non-Fire units, boosts Fire ones and Aqua puts it out', () {
    final fireEnemy = dummyOf(Element.fire, shotDamage: 10);
    final battle =
        battleWith(
            [shotOf(Element.aqua)],
            spawns: [EnemySpawn(fireEnemy, const GridPos(3, 1))],
          )
          ..setPanel(const GridPos(3, 1), PanelState.lava)
          ..setPanel(const GridPos(0, 0), PanelState.lava);
    wait(battle, fireEnemy.moveTicks + 89);
    final enemy = battle.enemies.single;
    expect(enemy.hp, 100);
    expect(battle.player.hp, 100 - 13);

    battle.player.pos = const GridPos(0, 0);
    final before = battle.player.hp;
    wait(battle, ticksPerSecond);
    expect(battle.player.hp, before - lavaDamage);
    expect(battle.panelAt(const GridPos(0, 0)).state, PanelState.lava);

    battle.player.pos = const GridPos(1, 1);
    use(battle, shotOf(Element.aqua));
    expect(battle.panelAt(const GridPos(3, 1)).state, PanelState.normal);
  });
}
