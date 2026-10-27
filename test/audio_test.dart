import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/game/audio.dart';

void main() {
  test('every sound file exists', () {
    for (final path in AudioFiles.all) {
      expect(File('assets/$path').existsSync(), isTrue, reason: path);
    }
  });

  test('playing before init does nothing', () {
    GameAudio.instance.play(Sfx.shot);
    GameAudio.instance.music(Music.battle);
  });

  test('battle reports a used chip, a new hand and the win', () {
    final battle = BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [ChipCard(Chips.shotgun)],
      encounter: const Encounter([
        EnemySpawn(Enemies.mobileCannon, GridPos(4, 1)),
      ]),
      random: Random(1),
    );
    battle.tick();
    expect(
      battle.events.map((e) => e.kind),
      contains(BattleEventKind.newHand),
    );
    battle.tick(const PlayerInput(useChip: true));
    expect(
      battle.events.where((e) => e.kind == BattleEventKind.chipUsed),
      isNotEmpty,
    );
    for (final enemy in battle.enemies) {
      enemy.hp = 0;
    }
    battle.tick();
    final kinds = battle.events.map((e) => e.kind);
    expect(kinds, contains(BattleEventKind.death));
    expect(kinds, contains(BattleEventKind.won));
  });
}
