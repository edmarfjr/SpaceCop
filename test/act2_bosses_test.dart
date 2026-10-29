import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/battle/enemy_behaviors.dart';
import 'package:starcop/domain/battle/panels.dart';
import 'package:starcop/domain/grid.dart';

import 'battle_helpers.dart';

Set<GridPos> warned(BattleState battle) => {
  for (final t in battle.telegraphs) t.pos,
};

void main() {
  test('the second mission draws one of 3 bosses', () {
    final random = Random(1);
    final bosses = {
      for (var i = 0; i < 60; i++)
        Encounters.boss(random, act: 2).spawns.first.def,
    };
    expect(bosses, {Enemies.tribeKing, Enemies.highPriest, Enemies.serpent});
  });

  group('Sumo-Sacerdote Xul', () {
    (BattleState, EnemyFighter) priestAbout(int index) {
      final battle = battleWith(
        [],
        spawns: [const EnemySpawn(Enemies.highPriest, GridPos(5, 1))],
      );
      final priest = battle.enemies.single
        ..attackTimer = index
        ..timer = 0
        ..moveTimer = 100000;
      return (battle, priest);
    }

    test('runes left lit hurt the whole side, then he is exhausted', () {
      final (battle, priest) = priestAbout(0);
      battle.tick();
      expect(battle.runes, hasLength(HighPriestBehavior.runeCount));
      expect(battle.runes, isNot(contains(battle.player.pos)));
      expect(priest.pose, HighPriestBehavior.castPose);
      wait(battle, HighPriestBehavior.ritualTicks);
      expect(battle.runes, isEmpty);
      expect(
        battle.player.hp,
        100 - HighPriestBehavior.runeDamage * HighPriestBehavior.runeCount,
      );
      battle.tick();
      expect(priest.pose, HighPriestBehavior.exhaustedPose);
      final before = priest.hp;
      battle.damage(priest, 10);
      expect(priest.hp, before - 20);
    });

    test('stepping on every rune puts the ritual out', () {
      final (battle, priest) = priestAbout(0);
      battle.tick();
      for (final rune in battle.runes.toList()) {
        battle.player.pos = rune;
        battle.tick();
      }
      expect(battle.runes, isEmpty);
      wait(battle, HighPriestBehavior.ritualTicks);
      expect(battle.player.hp, 100);
      expect(priest.exposedTicks, greaterThan(0), reason: 'still exhausted');
    });

    test('Ascensão: one more rune, and they move', () {
      final (battle, priest) = priestAbout(0);
      priest.hp = priest.maxHp ~/ 2 - 1;
      battle.tick();
      expect(battle.runes, hasLength(HighPriestBehavior.runeCount + 1));
      final before = Set.of(battle.runes);
      wait(battle, HighPriestBehavior.runeMoveTicks * 2);
      expect(battle.runes, isNot(before));
    });

    test('Transmutação turns 3 panels to ice or grass', () {
      final (battle, _) = priestAbout(1);
      battle.tick();
      final cells = warned(battle);
      expect(cells, hasLength(HighPriestBehavior.transmuteCells));
      wait(battle, HighPriestBehavior.spellWarn);
      for (final cell in cells) {
        expect(
          battle.panelAt(cell).state,
          isIn([PanelState.ice, PanelState.grass]),
        );
      }
    });

    test('Troca de Lugar moves the player to the warned panel', () {
      final (battle, _) = priestAbout(2);
      battle.tick();
      final to = warned(battle).single;
      wait(battle, HighPriestBehavior.spellWarn);
      expect(battle.player.pos, to);
    });
  });

  group('Serpente Ancestral', () {
    (BattleState, EnemyFighter) serpentAbout(int index) {
      final battle = battleWith(
        [],
        spawns: [const EnemySpawn(Enemies.serpent, GridPos(3, 1))],
      );
      final head = battle.enemies.first;
      battle.tick();
      head
        ..attackTimer = index
        ..timer = 0
        ..moveTimer = 100000;
      return (battle, head);
    }

    test('grows its body behind it, the tail last', () {
      final (battle, head) = serpentAbout(0);
      expect(head.body, hasLength(SerpentBehavior.segments));
      expect(head.body.last.def, Enemies.serpentTail);
      for (final segment in head.body) {
        expect(battle.ownerAt(segment.pos), Team.enemy);
      }
    });

    test('the body follows the head panel by panel', () {
      final (battle, head) = serpentAbout(1);
      head.timer = 100000;
      final before = [head.pos, for (final s in head.body) s.pos];
      head.moveTimer = 0;
      battle.tick();
      expect(head.pos, isNot(before.first));
      for (final (i, segment) in head.body.indexed) {
        expect(segment.pos, before[i]);
      }
    });

    test('a broken segment hurts the head', () {
      final (battle, head) = serpentAbout(1);
      head.body.first.hp = 0;
      wait(battle, 2);
      expect(head.body, hasLength(SerpentBehavior.segments - 1));
      expect(head.hp, Enemies.serpent.hp - SerpentBehavior.segmentLoss);
    });

    test(
      'Mergulho: hidden, bursts out under the player, comes back exposed',
      () {
        final (battle, head) = serpentAbout(0);
        battle.tick();
        expect(head.hidden, isTrue);
        expect(head.body.every((s) => s.hidden), isTrue);
        expect(warned(battle), {battle.player.pos});
        battle.damage(head, 50);
        expect(head.hp, Enemies.serpent.hp, reason: 'out of reach underground');
        wait(battle, SerpentBehavior.diveWarn);
        expect(battle.player.hp, 100 - SerpentBehavior.diveDamage);
        expect(head.hidden, isFalse);
        battle.damage(head, 10);
        expect(head.hp, Enemies.serpent.hp - 20);
      },
    );

    test('fury: it dives twice', () {
      final (battle, head) = serpentAbout(0);
      head.hp = (head.maxHp * SerpentBehavior.furyAt).floor() - 1;
      battle.tick();
      wait(battle, 2 * SerpentBehavior.diveWarn + SerpentBehavior.diveGap + 1);
      expect(battle.player.hp, 100 - 2 * SerpentBehavior.diveDamage);
    });

    test('Sopro de Areia: the player can not use cards in the sand', () {
      final (battle, _) = serpentAbout(1);
      battle.tick();
      expect(warned(battle), contains(battle.player.pos));
      wait(battle, SerpentBehavior.spellWarn);
      expect(battle.inSmoke(battle.player), isTrue);
    });

    test('killing the head wins, whatever is left of the body', () {
      final (battle, head) = serpentAbout(1);
      head.hp = 0;
      battle.tick();
      expect(battle.phase, BattlePhase.won);
    });
  });
}
