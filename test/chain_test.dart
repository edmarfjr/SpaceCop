import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/run/relics.dart';

import 'battle_helpers.dart';

void main() {
  group('family chain', () {
    final shot = shotOf(family: ChipFamily.projectile);
    final blast = shotOf(family: ChipFamily.explosive);
    final beam = shotOf(family: ChipFamily.energy);

    test('2nd chip +25%, 3rd +50% and applies the family status', () {
      final battle = battleWith([shot, shot, shot]);
      final enemy = battle.enemies.single;
      use(battle, shot);
      expect(enemy.hp, 100 - pew(10));
      expect(battle.chainCount, 1);
      expect(battle.chainFamily, ChipFamily.projectile);
      use(battle, shot);
      expect(enemy.hp, 100 - pew(10) - pew(13));
      use(battle, shot);
      expect(enemy.hp, 100 - pew(10) - pew(13) - pew(15));
      expect(enemy.has(Status.marked), isTrue);
      expect(battle.chainCount, 0);
    });

    test('each damage family has its own finishing status', () {
      for (final (family, status) in [
        (ChipFamily.explosive, Status.burning),
        (ChipFamily.energy, Status.stunned),
        (ChipFamily.melee, Status.rooted),
      ]) {
        final chip = shotOf(family: family);
        final battle = battleWith([chip, chip, chip]);
        for (var i = 0; i < 3; i++) {
          use(battle, chip);
        }
        expect(battle.enemies.single.has(status), isTrue, reason: '$family');
      }
    });

    test('cards that do not chain keep it; another family or a 2 s gap '
        'break it', () {
      final other = shotOf();
      final battle = battleWith([shot, other, shot, blast, shot]);
      final enemy = battle.enemies.single;
      use(battle, shot);
      use(battle, other);
      expect(battle.chainCount, 1, reason: 'Tático leaves the chain alone');
      use(battle, shot);
      expect(enemy.hp, 100 - pew(10) - 10 - pew(13));
      use(battle, blast);
      expect(battle.chainFamily, ChipFamily.explosive);
      expect(battle.chainCount, 1);
      wait(battle, chainWindowTicks);
      expect(battle.chainCount, 0);
      use(battle, shot);
      expect(enemy.hp, 100 - pew(10) - 10 - pew(13) - boom(10) - pew(10));
    });

    test('a complete chain fires Gatilho de Corrente', () {
      final battle = BattleState(
        playerHp: 100,
        playerMaxHp: 100,
        deckCards: [for (var i = 0; i < 3; i++) ChipCard(beam)],
        encounter: Encounter([dummyAt(3, 1)]),
        random: Random(1),
        relics: const [Relics.chainTrigger],
      )..tick();
      for (var i = 0; i < 3; i++) {
        use(battle, beam);
      }
      expect(battle.enemies.single.has(Status.stunned), isTrue);
      expect(battle.boostNextGauge, isTrue);
    });
  });
}
