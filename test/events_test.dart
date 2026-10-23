import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/run/events.dart';
import 'package:starcop/domain/run/relics.dart';
import 'package:starcop/domain/run/run_state.dart';

void main() {
  RunState newRun() => RunState(random: Random(4));

  group('Nave à Deriva', () {
    final [extract, debug, disconnect] = Events.driftingShip.options;

    test('Saquear o porão: Bug plus a random 3-energy card', () {
      final run = newRun();
      final size = run.deck.length;
      expect(extract.apply(run, null), isNull);
      expect(run.deck, hasLength(size + 2));
      expect(run.deck[size].def, Chips.bug);
      expect(run.deck[size + 1].def.cost, 3);
    });

    test('Consertar: -15 HP, removes the chip, adds a combat relic', () {
      final run = newRun();
      final card = run.deck.first;
      debug.apply(run, card);
      expect(run.hp, run.maxHp - 15);
      expect(run.deck, isNot(contains(card)));
      expect(run.relics.single.kind, RelicKind.combat);
    });

    test('Desconectar changes nothing', () {
      final run = newRun();
      final size = run.deck.length;
      expect(disconnect.apply(run, null), isNull);
      expect(run.deck, hasLength(size));
      expect(run.hp, run.maxHp);
    });
  });

  group('Arena Clandestina', () {
    final [duel, bet, train] = Events.undergroundArena.options;

    test(
      'Aceitar o duelo starts a fight; winning pays 100 and 1 of 2 relics',
      () {
        final run = newRun();
        expect(duel.apply(run, null), isA<StartDuel>());
        final reward = duelWon(run);
        expect(run.credits, 100);
        expect(reward.offers, hasLength(2));
        reward.offers.first.apply(run);
        expect(run.relics, hasLength(1));
      },
    );

    test('Apostar a bateria: -1 base energy for one of two fusion pairs', () {
      final run = newRun();
      final size = run.deck.length;
      final choice = bet.apply(run, null)! as OfferChoice;
      expect(run.energyBaseBonus, -1);
      expect(choice.offers, hasLength(2));
      choice.offers.last.apply(run);
      expect(run.deck, hasLength(size + 2));
      final (a, b) = (run.deck[size].def, run.deck[size + 1].def);
      expect(Chips.fusionPairs, contains((a, b)));
    });

    test('Treinar no simulador: -10 HP and a copy of the chip', () {
      final run = newRun();
      final card = run.deck.last;
      train.apply(run, card);
      expect(run.hp, run.maxHp - 10);
      expect(run.deck.where((c) => c.def == card.def).length, greaterThan(1));
      expect(run.deck.last.def, card.def);
      expect(run.deck.last, isNot(card));
    });
  });

  test('HP costs never drop the run below 1 HP', () {
    final run = newRun()..hp = 5;
    Events.driftingShip.options[1].apply(run, run.deck.first);
    expect(run.hp, 1);
  });
}
