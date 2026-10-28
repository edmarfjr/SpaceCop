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
  group('family chain', () {
    final shot = shotOf(Element.neutral, family: ChipFamily.projectile);
    final blast = shotOf(Element.neutral, family: ChipFamily.explosive);
    final zap = shotOf(Element.neutral, family: ChipFamily.energy);

    test('2nd chip +25%, 3rd +50% and applies the family status', () {
      final battle = battleWith([blast, blast, blast]);
      final enemy = battle.enemies.single;
      use(battle, blast);
      expect(enemy.hp, 100 - 10);
      expect(battle.chainCount, 1);
      expect(battle.chainFamily, ChipFamily.explosive);
      use(battle, blast);
      expect(enemy.hp, 100 - 10 - 13);
      use(battle, blast);
      expect(enemy.hp, 100 - 10 - 13 - 15);
      expect(enemy.has(Status.burning), isTrue);
      expect(battle.chainCount, 0);
    });

    test('each damage family has its own finishing status', () {
      for (final (family, status) in [
        (ChipFamily.projectile, Status.marked),
        (ChipFamily.energy, Status.stunned),
        (ChipFamily.melee, Status.rooted),
      ]) {
        final chip = shotOf(Element.neutral, family: family);
        final battle = battleWith([chip, chip, chip]);
        for (var i = 0; i < 3; i++) {
          use(battle, chip);
        }
        expect(battle.enemies.single.has(status), isTrue, reason: '$family');
      }
    });

    test('cards that do not chain keep it; another family or a 2 s gap '
        'break it', () {
      final other = shotOf(Element.neutral);
      final battle = battleWith([shot, other, shot, blast, shot]);
      final enemy = battle.enemies.single;
      use(battle, shot);
      use(battle, other);
      expect(battle.chainCount, 1, reason: 'Tático leaves the chain alone');
      use(battle, shot);
      expect(enemy.hp, 100 - 10 - 10 - 13);
      use(battle, blast);
      expect(battle.chainFamily, ChipFamily.explosive);
      expect(battle.chainCount, 1);
      wait(battle, chainWindowTicks);
      expect(battle.chainCount, 0);
      use(battle, shot);
      expect(enemy.hp, 100 - 10 - 10 - 13 - 10 - 10);
    });

    test('a complete chain fires Gatilho de Corrente', () {
      final battle = BattleState(
        playerHp: 100,
        playerMaxHp: 100,
        deckCards: [for (var i = 0; i < 3; i++) ChipCard(zap)],
        encounter: Encounter([dummyAt(3, 1)]),
        random: Random(1),
        relics: const [Relics.chainTrigger],
      )..tick();
      for (var i = 0; i < 3; i++) {
        use(battle, zap);
      }
      expect(battle.enemies.single.has(Status.stunned), isTrue);
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
