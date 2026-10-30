import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';
import 'package:starcop/domain/run/relics.dart';
import 'package:starcop/domain/run/run_state.dart';

import 'battle_helpers.dart';

RunState newRun() => RunState(random: Random(3));

void main() {
  test('max HP relics raise max HP and heal as much', () {
    for (final (relic, amount) in [
      (Relics.fieldRation, 5),
      (Relics.kevlarVest, 8),
      (Relics.bionicHeart, 12),
      (Relics.syntheticMarrow, 16),
    ]) {
      final run = newRun()..hp = 50;
      run.addRelic(relic);
      expect(run.maxHp, 100 + amount);
      expect(run.hp, 50 + amount);
    }
  });

  test('Propulsor de Salto: 3 moves to any node of the next floor', () {
    final run = newRun();
    run.enter(run.availableNodes.first);
    run.addRelic(Relics.jumpPack);
    expect(run.jumps, Relics.jumpCount);
    final floor = run.current!.floor + 1;
    final all = [
      for (final n in run.map.usedNodes)
        if (n.floor == floor) n,
    ];
    expect(run.availableNodes, unorderedEquals(all));
    final offPath = all.firstWhere(
      (n) => !run.map.nextOf(run.current!).contains(n),
      orElse: () => all.first,
    );
    final jumped = !run.map.nextOf(run.current!).contains(offPath);
    run.enter(offPath);
    expect(run.jumps, Relics.jumpCount - (jumped ? 1 : 0));
    final loaded = RunState.fromJson(
      jsonDecode(jsonEncode(run.toJson())) as Map<String, Object?>,
    );
    expect(loaded.jumps, run.jumps);
  });

  test('Clonador Quântico asks for a card and duplicates it', () {
    final run = newRun()..addRelic(Relics.quantumCloner);
    final step = run.pending.single as DeckPickStep;
    final card = run.deck.first;
    final size = run.deck.length;
    step.apply(run, card);
    expect(run.deck, hasLength(size + 1));
    expect(run.deck.last.def, card.def);
  });

  test('Banco de Dados Tático: 5 card rewards of 3', () {
    final run = newRun()..addRelic(Relics.dataBank);
    expect(run.pending, hasLength(Relics.dataBankRewards));
    for (final step in run.pending) {
      expect((step as CardRewardStep).cards, hasLength(3));
    }
  });

  test('Forja de Dados: 3 transforms, then 3 upgrades', () {
    final run = newRun()..addRelic(Relics.dataForge);
    expect(run.pending, hasLength(6));
    final transform = run.pending.first as DeckPickStep;
    final card = run.deck.first;
    transform.apply(run, card);
    expect(run.deck.first.def.id, isNot(card.def.id));
    final upgrade = run.pending.last as DeckPickStep;
    final target = upgrade.cards(run).first;
    upgrade.apply(run, target);
    expect(run.deck.any((c) => c.def.upgraded), isTrue);
  });

  test('Incinerador removes 2 cards', () {
    final run = newRun()..addRelic(Relics.incinerator);
    final size = run.deck.length;
    for (final step in run.pending.cast<DeckPickStep>()) {
      step.apply(run, run.deck.first);
    }
    expect(run.deck, hasLength(size - 2));
  });

  test('Caixa de Suprimentos: 50 Créditos, +5 max HP, an upgrade and a card '
      'reward', () {
    final run = newRun();
    final credits = run.credits;
    run.addRelic(Relics.supplyCrate);
    expect(run.credits, credits + Relics.crateCredits);
    expect(run.maxHp, 105);
    expect(run.deck.where((c) => c.def.upgraded), hasLength(1));
    expect(run.pending.single, isA<CardRewardStep>());
  });

  test('Impressora 3D: a card for this battle only, exhausted once used', () {
    final run = newRun();
    final battle = BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [for (var i = 0; i < 6; i++) ChipCard(Chips.shot)],
      encounter: Encounter([
        EnemySpawn(dummyOf(Element.neutral), const GridPos(3, 1)),
      ]),
      random: Random(5),
      relics: const [Relics.printer3d],
    )..tick();
    final card = battle.temporary.single;
    expect(battle.hand, contains(card), reason: 'drawn in the first hand');
    battle.selectChip(battle.hand.indexOf(card));
    battle.energy = 10;
    battle.tick(const PlayerInput(useChip: true));
    expect(battle.hand, isNot(contains(card)));
    expect(battle.deck.discardPile, isNot(contains(card)));
    expect(run.deck, hasLength(Chips.starterDeck().length));
  });
}
