import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/domain/run/relics.dart';

import 'battle_helpers.dart';

/// Presses Use on [def] and keeps it held for [ticks] ticks in total, then
/// releases it.
void hold(BattleState battle, ChipDef def, int ticks) {
  battle.selectChip(battle.hand.indexWhere((c) => c.def == def));
  battle.tick(const PlayerInput(useChip: true, holdUse: true));
  wait(battle, ticks - 1, const PlayerInput(holdUse: true));
  wait(battle, playerAttackCooldown);
}

void main() {
  group('element chain', () {
    test('2nd chip +50%, 3rd +100% and applies the status', () {
      final fire = shotOf(Element.fire);
      final battle = battleWith([fire, fire, fire]);
      final enemy = battle.enemies.single;
      use(battle, fire);
      expect(enemy.hp, 100 - 10);
      expect(battle.chainCount, 1);
      use(battle, fire);
      expect(enemy.hp, 100 - 10 - 15);
      use(battle, fire);
      expect(enemy.hp, 100 - 10 - 15 - 20);
      expect(enemy.has(Status.burning), isTrue);
      expect(battle.chainCount, 0);
    });

    test('Neutral chips and a 2 s gap break the chain', () {
      final fire = shotOf(Element.fire);
      final battle = battleWith([fire, Chips.shot, fire, fire]);
      final enemy = battle.enemies.single;
      use(battle, fire);
      use(battle, Chips.shot);
      use(battle, fire);
      expect(enemy.hp, 100 - 10 - Chips.shot.damage - 10);
      wait(battle, chainWindowTicks);
      use(battle, fire);
      expect(enemy.hp, 100 - 10 - Chips.shot.damage - 10 - 10);
    });

    test('a complete chain fires Gatilho de Corrente', () {
      final aqua = shotOf(Element.aqua);
      final battle = BattleState(
        playerHp: 100,
        playerMaxHp: 100,
        deckCards: [for (var i = 0; i < 3; i++) ChipCard(aqua)],
        encounter: Encounter([dummyAt(3, 1)]),
        random: Random(1),
        relics: const [Relics.chainTrigger],
      )..tick();
      for (var i = 0; i < 3; i++) {
        use(battle, aqua);
      }
      expect(battle.enemies.single.has(Status.wet), isTrue);
      expect(battle.boostNextGauge, isTrue);
    });
  });

  group('fusion', () {
    test('holding Use 0.5 s fuses the pair and charges both energy costs', () {
      final battle = battleWith(
        [Chips.hook, Chips.mine],
        spawns: [dummyAt(5, 1)],
      );
      hold(battle, Chips.hook, fusionChargeTicks);
      final enemy = battle.enemies.single;
      expect(battle.hand, isEmpty);
      expect(battle.energy, baseEnergy - 2);
      expect(enemy.pos, const GridPos(3, 1));
      expect(enemy.hp, 100 - Chips.magnetTrap.damage);
    });

    test('releasing Use early uses the selected chip alone', () {
      final battle = battleWith(
        [Chips.hook, Chips.mine],
        spawns: [dummyAt(5, 1)],
      );
      hold(battle, Chips.hook, 5);
      expect(battle.hand.single.def, Chips.mine);
      expect(battle.energy, baseEnergy - Chips.hook.cost);
      expect(battle.enemies.single.pos, const GridPos(3, 1));
      expect(battle.enemies.single.hp, 100);
    });

    test('the player stands still while charging', () {
      final battle = battleWith([Chips.hook, Chips.mine]);
      battle.selectChip(battle.hand.indexWhere((c) => c.def == Chips.hook));
      battle.tick(const PlayerInput(useChip: true, holdUse: true));
      wait(battle, 5, const PlayerInput(holdUse: true, dy: -1));
      expect(battle.player.pos, const GridPos(1, 1));
      expect(battle.chargingCard, isNotNull);
    });

    test('Tempestade wets the enemy side and strikes it for 40', () {
      final battle = battleWith(
        [Chips.bubblePush, Chips.thunderLance],
        spawns: [dummyAt(3, 0), dummyAt(5, 2)],
      );
      hold(battle, Chips.bubblePush, fusionChargeTicks);
      expect(battle.enemies.map((e) => e.hp), [60, 60]);
      expect(
        battle.energy,
        baseEnergy - Chips.bubblePush.cost - Chips.thunderLance.cost,
      );
    });

    test('Avalanche cracks its path, hits for 40 and pushes', () {
      final battle = battleWith(
        [Chips.cracker, Chips.rock],
        spawns: [dummyAt(4, 1)],
      );
      hold(battle, Chips.rock, fusionChargeTicks);
      final enemy = battle.enemies.single;
      expect(enemy.hp, 100 - 40);
      expect(enemy.pos, const GridPos(5, 1));
      for (final x in [2, 3]) {
        expect(battle.panelAt(GridPos(x, 1)).state, PanelState.cracked);
      }
    });
  });
}
