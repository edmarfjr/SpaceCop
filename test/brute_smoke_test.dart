import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/grid.dart';

void main() {
  test('a Capanga Bruto charges again after its charge fizzles in smoke', () {
    final battle = BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [ChipCard(Chips.shot)],
      encounter: const Encounter([
        EnemySpawn(Enemies.brute, GridPos(4, 1)),
      ]),
      random: Random(1),
    );
    final brute = battle.enemies.single;
    final smoke = battle.panelAt(brute.pos)..smokeTicks = 6 * ticksPerSecond;
    // Long enough for a charge to start and fizzle inside the cloud.
    for (var i = 0; i < 6 * ticksPerSecond; i++) {
      battle.tick();
    }
    expect(smoke.smoky, isFalse);
    final hp = battle.player.hp;
    for (var i = 0; i < 6 * ticksPerSecond; i++) {
      battle.tick();
    }
    expect(battle.player.hp, lessThan(hp));
  });
}
