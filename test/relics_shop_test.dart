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
import 'package:starcop/domain/run/run_state.dart';
import 'package:starcop/domain/run/shop.dart';

import 'battle_helpers.dart';

BattleState withRelics(
  List<RelicDef> relics,
  List<ChipDef> chips, {
  List<EnemySpawn>? spawns,
}) => BattleState(
  playerHp: 100,
  playerMaxHp: 100,
  deckCards: [for (final def in chips) ChipCard(def)],
  encounter: Encounter(spawns ?? [dummyAt(3, 1)]),
  random: Random(5),
  relics: relics,
)..tick();

void main() {
  group('combat relics', () {
    test('Linha de Frente: +20% damage from the front column', () {
      final battle = withRelics(
        [Relics.frontLine],
        [for (var i = 0; i < 3; i++) shotOf(Element.neutral)],
        spawns: [dummyAt(5, 1)],
      );
      final enemy = battle.enemies.single;
      use(battle, shotOf(Element.neutral));
      expect(enemy.hp, 100 - 10);
      battle.player.pos = const GridPos(2, 1);
      use(battle, shotOf(Element.neutral));
      expect(enemy.hp, 100 - 10 - 12);
      // A stolen column moves the front line forward.
      battle
        ..setColumnOwner(3, Team.player)
        ..player.pos = const GridPos(3, 1);
      use(battle, shotOf(Element.neutral));
      expect(enemy.hp, 100 - 10 - 12 - 12);
    });

    test('Núcleo de Colisão: +20 damage and +1 s stun', () {
      final battle = withRelics(
        [Relics.collisionCore],
        [Chips.bubblePush],
        spawns: [dummyAt(5, 1)],
      );
      final enemy = battle.enemies.single;
      battle.selectChip(0);
      battle.tick(const PlayerInput(useChip: true));
      wait(battle, 4);
      expect(enemy.hp, 100 - 10 - collisionDamage - 20);
      expect(
        enemy.statuses[Status.stunned],
        greaterThan(collisionStunTicks + ticksPerSecond - 5),
      );
    });

    test('Gatilho de Corrente: the next gauge fills 50% faster', () {
      final battle = withRelics([Relics.chainTrigger], []);
      Relics.chainTrigger.onChainComplete!(battle);
      expect(battle.boostNextGauge, isTrue);
      wait(battle, gaugeTicks);
      expect(battle.gaugeBoosted, isTrue);
      wait(battle, 100);
      expect(battle.gauge, 150);
    });

    test('Botas de Gelo: no sliding, cracked stays cracked', () {
      final battle = withRelics([Relics.iceBoots], [])
        ..setPanel(const GridPos(1, 1), PanelState.cracked)
        ..setPanel(const GridPos(1, 0), PanelState.ice);
      battle.tick(const PlayerInput(dy: -1));
      expect(battle.player.pos, const GridPos(1, 0));
      expect(battle.panelAt(const GridPos(1, 1)).state, PanelState.cracked);

      battle
        ..player.pos = const GridPos(0, 2)
        ..setPanel(const GridPos(1, 2), PanelState.ice);
      wait(battle, playerMoveCooldown);
      battle.tick(const PlayerInput(dx: 1));
      expect(battle.player.pos, const GridPos(1, 2));
    });
  });

  group('global relics', () {
    test('Bateria Extra adds 1 base energy', () {
      final battle = withRelics([Relics.extraBattery], []);
      expect(battle.energyMax, baseEnergy + 1);
      expect(battle.energy, baseEnergy + 1);
    });

    test('Pasta Ordenada shows the next 2 chips and buries one', () {
      final battle = withRelics([
        Relics.sortedFolder,
      ], List.filled(10, Chips.shot));
      final next = battle.peekCards;
      expect(next, hasLength(2));
      battle.sendToBottom(next.first);
      expect(battle.deck.drawPile.first, next.first);
      expect(battle.peekCards, isEmpty);
    });

    test('Pasta Ordenada can keep the order', () {
      final battle = withRelics([
        Relics.sortedFolder,
      ], List.filled(10, Chips.shot));
      final next = battle.peekCards;
      battle.dismissPeek();
      expect(battle.peekOpen, isFalse);
      expect(battle.deck.peek(2), next);
    });
  });

  group('credits and shop', () {
    test('battles pay credits; elites also give a relic', () {
      final run = RunState(random: Random(1));
      expect(run.credits, startCredits);
      expect(startCredits, 99);
      run.credits = 0;
      expect(run.winBattle(elite: false), isNull);
      expect(run.credits, battleCredits);
      final relic = run.winBattle(elite: true);
      expect(run.credits, battleCredits + eliteCredits);
      expect(run.relics, [relic]);
    });

    test('5 chips and 3 distinct relics; buying costs credits', () {
      final run = RunState(random: Random(1))..credits = 200;
      final shop = Shop(run);
      expect(shop.chips, hasLength(5));
      expect(shop.relics, hasLength(3));
      expect(shop.relics.toSet(), hasLength(3));
      final def = shop.chips.first;
      final deckSize = run.deck.length;
      expect(shop.buyChip(def), isTrue);
      expect(run.credits, 200 - chipPrice);
      expect(run.deck, hasLength(deckSize + 1));
      expect(shop.chips, isNot(contains(def)));
      final relic = shop.relics.first;
      expect(shop.buyRelic(relic), isTrue);
      expect(run.relics, [relic]);
      expect(shop.relics, hasLength(2));
      expect(shop.buyChip(shop.chips.first), isFalse);
    });

    test('removing a chip costs 75', () {
      final run = RunState(random: Random(1))..credits = 80;
      final shop = Shop(run);
      final card = run.deck.first;
      expect(shop.removeChip(card), isTrue);
      expect(run.deck, isNot(contains(card)));
      expect(run.credits, 80 - removalPrice);
      expect(shop.removeChip(run.deck.first), isFalse);
    });

    test('only one card can be removed per shop', () {
      final run = RunState(random: Random(1))..credits = 1000;
      final shop = Shop(run);
      expect(shop.removeChip(run.deck.first), isTrue);
      expect(shop.canRemove, isFalse);
      expect(shop.removeChip(run.deck.first), isFalse);
      expect(run.deck, hasLength(9));
      expect(Shop(run).canRemove, isTrue, reason: 'the next shop resets it');
    });

    test('Cartão de Sócio: 25% off and the removal is free', () {
      final run = RunState(random: Random(1))
        ..credits = 100
        ..relics.add(Relics.memberCard);
      final shop = Shop(run);
      expect(shop.chipCost, 38);
      expect(shop.removalCost, 0);
      shop.removeChip(run.deck.first);
      expect(run.credits, 100);
    });
  });
}
