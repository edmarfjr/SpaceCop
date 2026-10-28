import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/run/events.dart';
import 'package:starcop/domain/run/relics.dart';
import 'package:starcop/domain/run/run_state.dart';

void main() {
  RunState newRun([int seed = 4]) => RunState(random: Random(seed))
    ..credits = 0
    ..act = 2;

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
        case final PickCard pick:
          final cards = pick.cards(run);
          next = cards.isEmpty ? null : pick.apply(run, cards.first);
        case StartFight(:final onWin, :final encounter):
          encounter?.call(run);
          next = onWin?.call(run);
      }
    }
  }

  test('the ruins have their own 10 events', () {
    expect(Events.of(2), Events.ruins);
    expect(Events.ruins, hasLength(10));
    expect(Events.of(1), Events.all);
  });

  test('every ruins option plays through on any run', () {
    for (var seed = 0; seed < 30; seed++) {
      for (final event in Events.ruins) {
        for (final option in event.options) {
          final run = newRun(seed)..credits = 500;
          if (!option.available(run)) continue;
          playThrough(run, option);
          expect(run.hp, greaterThan(0));
        }
      }
    }
  });

  test('Mural: Decifrar offers 3 Energia cards', () {
    final choice =
        Events.mural.options.first.apply(newRun(), null)! as OfferChoice;
    expect(choice.offers, hasLength(3));
    for (final offer in choice.offers) {
      final def = Chips.all.firstWhere((c) => c.name == offer.label);
      expect(def.family, ChipFamily.energy);
    }
  });

  test('Altar: blood costs max HP for a rare relic', () {
    final run = newRun();
    Events.altar.options.first.apply(run, null);
    expect(run.maxHp, 90);
    expect(run.relics.single.rarity, Rarity.rare);
  });

  test('Fonte: Beber heals fully and adds Bug', () {
    final run = newRun()..hp = 20;
    Events.fountain.options.first.apply(run, null);
    expect(run.hp, run.maxHp);
    expect(run.deck.last.def, Chips.bug);
  });

  test('Ninho: 3 Escaravelhos paying 100 Créditos', () {
    final run = newRun();
    final fight =
        Events.scarabNest.options.first.apply(run, null)! as StartFight;
    expect(
      fight.encounter!(run).spawns.map((s) => s.def),
      everyElement(Enemies.scarab),
    );
    fight.onWin!(run);
    expect(run.credits, 100);
  });

  test('Festa: the dance adds energy to the next battle only', () {
    final run = newRun();
    Events.harvestFeast.options[1].apply(run, null);
    expect(run.nextBattleEnergy, danceEnergy);
    expect(run.energyBaseBonus, 0);
  });

  test('Forja: Fundir trades 2 Projéteis for 1 Corpo-a-corpo', () {
    final run = newRun();
    final projectiles = run.deck
        .where((c) => c.def.family == ChipFamily.projectile)
        .length;
    playThrough(run, Events.forge.options[1]);
    expect(
      run.deck.where((c) => c.def.family == ChipFamily.projectile),
      hasLength(max(0, projectiles - 2)),
    );
    expect(run.deck.last.def.family, ChipFamily.melee);
    expect(run.deck.last.def.rarity, isNot(Rarity.common));
  });

  test('Mural: Copiar gives Créditos once the Decodificador is owned', () {
    final run = newRun()..relics.add(Relics.decoder);
    Events.mural.options[1].apply(run, null);
    expect(run.credits, 60);
    expect(run.relics, hasLength(1));
  });
}
