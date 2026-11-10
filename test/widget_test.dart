import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/deck/deck.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/domain/map/run_map.dart';

void main() {
  test('deck reshuffles discard into draw pile', () {
    final deck = Deck([for (var i = 0; i < 3; i++) ChipCard(Chips.shot)]);
    deck.draw(3);
    deck.discardHand();
    expect(deck.draw(2), hasLength(2));
    expect(
      deck.drawPile.length + deck.hand.length + deck.discardPile.length,
      3,
    );
  });

  test('shotgun hits the target and the cell behind it', () {
    final battle = BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [ChipCard(Chips.shotgun)],
      encounter: const Encounter([
        EnemySpawn(Enemies.mobileCannon, GridPos(3, 1)),
        EnemySpawn(Enemies.mobileCannon, GridPos(4, 1)),
      ]),
      random: Random(1),
    );
    battle.tick(); // gauge starts full: draws the hand
    expect(battle.hand, hasLength(1));
    battle.tick(const PlayerInput(useChip: true));
    for (var i = 0; i < 5; i++) {
      battle.tick();
    }
    // Canhão Móvel is a Máquina: Projétil does half.
    expect(
      battle.enemies.map((e) => e.hp),
      everyElement(30 - (10 * machineProjectileMultiplier).round()),
    );
    expect(battle.deck.discardPile, hasLength(1));
  });

  test('map paths never leave the grid and floor 0 is reachable', () {
    final map = MapGenerator(random: Random(7)).generate();
    expect(map.startNodes, isNotEmpty);
    for (final node in map.usedNodes) {
      expect(map.nextOf(node), isNotEmpty);
    }
  });
}
