import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/domain/run/events.dart';
import 'package:starcop/domain/run/relics.dart';
import 'package:starcop/domain/run/run_state.dart';
import 'package:starcop/domain/run/shop.dart';

import 'battle_helpers.dart';

void main() {
  RunState newRun([int seed = 4]) => RunState(random: Random(seed))
    ..credits = 0
    ..act = 3;

  EventOption option(EventDef event, String label) =>
      event.options.firstWhere((o) => o.label == label);

  /// Plays [option] through, always taking the first card or offer, and
  /// winning any fight.
  void playThrough(RunState run, EventOption option) {
    final cards = option.pickableCards(run);
    var next = option.apply(
      run,
      option.pick == EventPick.deckChip ? cards.first : null,
    );
    while (next != null) {
      switch (next) {
        case OfferChoice(:final offers):
          offers.first.apply(run);
          next = null;
        case CardChoice(:final cards):
          run.deck.add(ChipCard(cards.first));
          next = null;
        case final PickCard pick:
          final cards = pick.cards(run);
          next = cards.isEmpty ? null : pick.apply(run, cards.first);
        case StartFight(:final onWin, :final encounter):
          encounter?.call(run);
          next = onWin?.call(run);
      }
    }
  }

  int count(RunState run, ChipDef def) =>
      run.deck.where((c) => c.def == def).length;

  test('the abyss has its own 10 events', () {
    expect(Events.of(3), Events.abyss);
    expect(Events.abyss, hasLength(10));
    expect(Events.abyss.map((e) => e.title).toSet(), hasLength(10));
  });

  test('every abyss option plays through on any run', () {
    for (var seed = 0; seed < 30; seed++) {
      for (final event in Events.abyss) {
        for (final option in event.options) {
          final run = newRun(seed)..credits = 500;
          if (!option.available(run)) continue;
          playThrough(run, option);
          expect(run.hp, greaterThan(0));
        }
      }
    }
  });

  test('Arquivo: watching costs max HP for a rare card', () {
    final run = newRun();
    final next = option(Events.archive, 'Assistir até o fim').apply(run, null);
    expect(run.maxHp, 90);
    expect(next, isA<CardChoice>());
    expect(
      (next! as CardChoice).cards.every((c) => c.rarity == Rarity.rare),
      isTrue,
    );
  });

  test('Câmara do Sono Eterno: 2 cards out, the boss loses 15% HP', () {
    final run = newRun();
    final size = run.deck.length;
    playThrough(run, option(Events.sleeper, 'Reforçar as correntes'));
    expect(run.deck, hasLength(size - 2));
    expect(run.bossHpCut, chainsBossCut);

    final battle = BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: run.deck,
      encounter: const Encounter([EnemySpawn(Enemies.voidEye, GridPos(4, 0))]),
      bossHpCut: run.bossHpCut,
    );
    final boss = battle.enemies.first;
    expect(boss.hp, (boss.maxHp * (1 - chainsBossCut)).round());
  });

  test('Sussurro hurts the player when drawn', () {
    final battle = battleWith([Chips.whisper]);
    expect(battle.hand.single.def, Chips.whisper);
    expect(battle.player.hp, 100 - whisperDamage);
  });

  test('Sussurro: the pact upgrades a whole family and curses twice', () {
    final run = newRun();
    playThrough(run, option(Events.whisperDark, 'Aceitar o pacto'));
    expect(count(run, Chips.whisper), 2);
    final family = run.deck.firstWhere((c) => c.def.upgraded).def.family;
    expect(
      run.deck
          .where((c) => c.def.family == family)
          .every((c) => c.def.upgraded || Chips.upgradeOf(c.def) == null),
      isTrue,
    );
  });

  test('Biblioteca: a book rewrites a card into an upgraded one', () {
    final run = newRun();
    final card = run.deck.first;
    playThrough(run, option(Events.library, 'Ler um livro'));
    final rewritten = run.deck.first.def;
    expect(rewritten.upgraded, isTrue);
    expect(rewritten.rarity, card.def.rarity);
    expect(rewritten.id, isNot(card.def.id));
  });

  test('Biblioteca: burning it removes every curse', () {
    final run = newRun()
      ..deck.addAll([ChipCard(Chips.bug), ChipCard(Chips.whisper)]);
    playThrough(run, option(Events.library, 'Queimar a biblioteca'));
    expect(count(run, Chips.bug) + count(run, Chips.whisper), 0);
    expect(run.hp, 85);
  });

  test('Espelho: touching it duplicates a card', () {
    final run = newRun();
    final def = run.deck.first.def;
    final before = count(run, def);
    playThrough(run, option(Events.mirror, 'Tocar o espelho'));
    expect(count(run, def), before + 1);
  });

  test('Último Sobrevivente: the story heals and lasts 2 battles', () {
    final run = newRun()..hp = 20;
    playThrough(run, option(Events.survivor, 'Ouvir a história'));
    expect(run.hp, 70);
    expect(run.energyBattles, storyBattles);
  });

  test('Bênção do Último keeps the player at 1 HP once', () {
    final battle = BattleState(
      playerHp: 5,
      playerMaxHp: 100,
      deckCards: [ChipCard(Chips.shot)],
      encounter: Encounter([
        EnemySpawn(dummyOf(Element.neutral), const GridPos(3, 1)),
      ]),
      relics: [Relics.lastBlessing],
    )..tick();
    battle.damage(battle.player, 50);
    battle.tick();
    expect(battle.player.hp, 1);
    expect(battle.phoenixUsed, isTrue);

    final run = newRun()..addRelic(Relics.lastBlessing);
    run.endBattle(1, won: true, phoenixUsed: true);
    expect(run.hasRelic(Relics.lastBlessing), isFalse);
  });

  test('Elo do Abismo: single-use cards deal +10', () {
    final battle = battleWith([Chips.c4]);
    final withLink = BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [ChipCard(Chips.c4)],
      encounter: Encounter([
        EnemySpawn(dummyOf(Element.neutral), const GridPos(3, 1)),
      ]),
      relics: [Relics.abyssLink],
    )..tick();
    expect(Chips.c4.exhaust, isTrue);
    expect(Relics.abyssLink.modifyDamage!(withLink, Chips.c4, 20), 30);
    expect(Relics.abyssLink.modifyDamage!(battle, Chips.shot, 20), 20);
  });

  test('Altar: the badge trades every Crédito for 2 rare relics', () {
    final run = newRun()..credits = 300;
    playThrough(run, option(Events.namelessAltar, 'Oferecer o distintivo'));
    expect(run.credits, 0);
    expect(run.relics.where((r) => r.rarity == Rarity.rare), hasLength(2));
  });

  test('Transmissão: the next shop gives one item away', () {
    final run = newRun()..credits = 0;
    playThrough(run, option(Events.transmission, 'Pedir suprimento'));
    expect(run.credits, 100);
    run.credits = 0;
    final shop = Shop(run);
    final def = shop.chips.first;
    expect(shop.chipCost(def), 0);
    expect(shop.buyChip(def), isTrue);
    expect(run.freeShopItem, isFalse);
    expect(shop.relicCost(shop.relics.first), greaterThan(0));
  });

  test('Transmissão: the alert shields the boss fight only, this act', () {
    final run = newRun()..act = 2;
    playThrough(run, option(Events.transmission, 'Mandar o alerta'));
    expect(run.bossBarrier, isTrue);
    final battle = battleWith([]);
    expect(battle.player.barrierTicks, 0);
    final shielded = BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: const [],
      encounter: Encounter([
        EnemySpawn(dummyOf(Element.neutral), const GridPos(3, 1)),
      ]),
      openingBarrier: true,
    );
    expect(shielded.player.barrierTicks, openingBarrierTicks);
    run.nextAct();
    expect(run.bossBarrier, isFalse);
  });

  test('a run saves its abyss effects', () {
    final run = newRun()
      ..energyBattles = 2
      ..bossHpCut = 0.15
      ..bossBarrier = true
      ..freeShopItem = true;
    final loaded = RunState.fromJson(run.toJson());
    expect(loaded.energyBattles, 2);
    expect(loaded.bossHpCut, 0.15);
    expect(loaded.bossBarrier, isTrue);
    expect(loaded.freeShopItem, isTrue);
  });
}
