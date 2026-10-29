import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/run/events.dart';
import 'package:starcop/domain/run/relics.dart';
import 'package:starcop/domain/run/run_state.dart';

void main() {
  RunState newRun() => RunState(random: Random(4))..credits = 0;

  test('HP costs never drop the run below 1 HP', () {
    final run = newRun()..hp = 5;
    Events.vault.options.first.apply(run, null);
    expect(run.hp, 1);
  });

  test('a "?" node is mostly an event, sometimes a battle, an elite or a '
      'shop', () {
    final random = Random(3);
    final rolls = [for (var i = 0; i < 1000; i++) rollUnknownRoom(random)];
    int share(UnknownRoom room) => rolls.where((r) => r == room).length;
    expect(share(UnknownRoom.event), inInclusiveRange(490, 610));
    expect(share(UnknownRoom.battle), inInclusiveRange(150, 250));
    expect(share(UnknownRoom.elite), inInclusiveRange(60, 140));
    expect(share(UnknownRoom.shop), inInclusiveRange(100, 200));
  });

  group('Arsenal Desprotegido', () {
    final [loot, dismantle, _] = Events.armory.options;

    test('Saquear: -10 HP for 1 of 3 attack cards', () {
      final run = newRun();
      final choice = loot.apply(run, null)! as CardChoice;
      expect(run.hp, 90);
      expect(choice.cards, hasLength(3));
      expect(choice.cards.every((c) => c.type == ChipType.attack), isTrue);
    });

    test('Desmontar: removes the picked card for 40', () {
      final run = newRun();
      final card = run.deck.first;
      expect(dismantle.apply(run, card), isNull);
      expect(run.deck, isNot(contains(card)));
      expect(run.credits, 40);
    });
  });

  group('Cela do Informante', () {
    final [free, interrogate, _] = Events.informant.options;

    test('Libertar: a normal fight that pays 1 of 2 relics', () {
      final run = newRun();
      final fight = free.apply(run, null)! as StartFight;
      expect(fight.elite, isFalse);
      expect(fight.onWin!(run)!.offers, hasLength(2));
    });

    test('Interrogar upgrades the picked card; only upgradeable ones', () {
      final run = newRun()..deck.add(ChipCard(Chips.bug));
      expect(
        interrogate.pickableCards(run).map((c) => c.def),
        isNot(contains(Chips.bug)),
      );
      interrogate.apply(run, run.deck.first);
      expect(run.deck.where((c) => c.def.upgraded), hasLength(1));
    });
  });

  group('Terminal de Segurança', () {
    final [hack, copy, _] = Events.securityTerminal.options;

    test('Hackear: +75 or an elite fight with the usual rewards', () {
      var paid = 0;
      var fights = 0;
      for (var seed = 0; seed < 20; seed++) {
        final run = RunState(random: Random(seed))..credits = 0;
        switch (hack.apply(run, null)) {
          case OfferChoice():
            expect(run.credits, 75);
            paid++;
          case StartFight(:final elite, :final onWin):
            expect(elite, isTrue);
            expect(onWin, isNull);
            fights++;
          default:
            fail('unexpected follow-up');
        }
      }
      expect(paid, greaterThan(0));
      expect(fights, greaterThan(0));
    });

    test('Copiar: -1 base energy for a combat relic', () {
      final run = newRun();
      copy.apply(run, null);
      expect(run.energyBaseBonus, -1);
      expect(run.relics.single.kind, RelicKind.combat);
    });
  });

  group('Cofre da Organização', () {
    final [force, blow, _] = Events.vault.options;

    test('Arrombar: -15 HP for 100', () {
      final run = newRun();
      force.apply(run, null);
      expect(run.hp, 85);
      expect(run.credits, 100);
    });

    test('Explosivo needs a Míssil or Mina and pays 150', () {
      final run = newRun();
      expect(blow.available(run), isFalse);
      run.deck.add(ChipCard(Chips.mine));
      expect(blow.pickableCards(run).single.def, Chips.mine);
      blow.apply(run, run.deck.last);
      expect(run.credits, 150);
      expect(run.deck.map((c) => c.def), isNot(contains(Chips.mine)));
    });
  });

  group('Campo de Tiro', () {
    final [practice, hard, _] = Events.shootingRange.options;

    test('Treinar: -10 HP, upgrades 1 attack card', () {
      final run = newRun();
      practice.apply(run, run.deck.first);
      expect(run.hp, 90);
      expect(run.deck.where((c) => c.def.upgraded), hasLength(1));
    });

    test('Treino intenso: -20 HP, then a second attack card', () {
      final run = newRun();
      final second = hard.apply(run, run.deck.first)! as PickCard;
      expect(run.hp, 80);
      final cards = second.cards(run);
      expect(cards.every((c) => !c.def.upgraded), isTrue);
      expect(second.apply(run, cards.first), isNull);
      expect(run.deck.where((c) => c.def.upgraded), hasLength(2));
    });
  });

  group('Agente Infiltrada', () {
    final [gear, cover, away] = Events.undercoverAgent.options;

    test('Equipamento: 1 of 2 relics', () {
      final run = newRun();
      final choice = gear.apply(run, null)! as OfferChoice;
      expect(choice.offers.every((o) => o.relic != null), isTrue);
    });

    test('Cobertura: heals 30% and upgrades the picked card', () {
      final run = newRun()..hp = 50;
      cover.apply(run, run.deck.first);
      expect(run.hp, 80);
      expect(run.deck.where((c) => c.def.upgraded), hasLength(1));
    });

    test('Mandar sair: a random rare card', () {
      final run = newRun();
      away.apply(run, null);
      expect(run.deck.last.def.rarity, Rarity.rare);
    });
  });

  group('Enfermaria Clandestina', () {
    final [chamber, supplies, implant] = Events.clinic.options;

    test('Câmara: +30 HP and a Bug', () {
      final run = newRun()..hp = 50;
      chamber.apply(run, null);
      expect(run.hp, 80);
      expect(run.deck.last.def, Chips.bug);
    });

    test('Suprimentos: 2 Primeiros Socorros', () {
      final run = newRun();
      supplies.apply(run, null);
      expect(run.deck.where((c) => c.def == Chips.recover), hasLength(2));
    });

    test('Implante: +1 base energy, -10 max HP', () {
      final run = newRun();
      implant.apply(run, null);
      expect(run.energyBaseBonus, 1);
      expect(run.maxHp, 90);
      expect(run.hp, 90);
    });
  });

  group('Hangar de Contrabando', () {
    final [box, trade, _] = Events.hangar.options;

    test('Caixa misteriosa costs 60: a relic or a Bug', () {
      expect(box.available(newRun()), isFalse, reason: 'no Créditos');
      var relics = 0;
      var bugs = 0;
      for (var seed = 0; seed < 20; seed++) {
        final run = RunState(random: Random(seed))..credits = 60;
        expect(box.available(run), isTrue);
        expect(box.apply(run, null), isA<OfferChoice>());
        expect(run.credits, 0);
        if (run.relics.isNotEmpty) relics++;
        if (run.deck.last.def == Chips.bug) bugs++;
      }
      expect(relics, greaterThan(0));
      expect(bugs, greaterThan(0));
    });

    test('Trocar: a common or uncommon card becomes a rarer one', () {
      final run = newRun()..deck.add(ChipCard(Chips.overclock));
      expect(
        trade.pickableCards(run).map((c) => c.def),
        isNot(contains(Chips.overclock)),
      );
      final card = run.deck.first;
      trade.apply(run, card);
      expect(run.deck, isNot(contains(card)));
      expect(
        run.deck.first.def.rarity.index,
        greaterThan(card.def.rarity.index),
      );
      expect(run.deck, hasLength(11));
    });
  });

  group('Triturador de Evidências', () {
    final [shred, recover, _] = Events.shredder.options;

    test('Destruir: -8 HP per card, up to 2 cards', () {
      final run = newRun();
      final second = shred.apply(run, run.deck.first)! as PickCard;
      expect(run.hp, 92);
      expect(run.deck, hasLength(9));
      expect(second.apply(run, run.deck.first), isNull);
      expect(run.hp, 84);
      expect(run.deck, hasLength(8));
    });

    test('Recuperar: a random cost-2 card', () {
      final run = newRun();
      recover.apply(run, null);
      expect(run.deck.last.def.cost, 2);
    });
  });

  group('Refeitório dos Capangas', () {
    final [sabotage, ambush, _] = Events.messHall.options;

    test('Sabotar: the next fight starts with stunned enemies', () {
      final run = newRun();
      sabotage.apply(run, null);
      expect(run.openingStunTicks, sabotageStunTicks);
      final battle = BattleState(
        playerHp: run.hp,
        playerMaxHp: run.maxHp,
        deckCards: run.deck,
        encounter: Encounters.normal(run.random),
        openingStunTicks: run.openingStunTicks,
      );
      expect(
        battle.enemies.map((e) => e.statuses[Status.stunned]),
        everyElement(sabotageStunTicks),
      );
    });

    test('Atacar: an elite fight paying 50 and 1 of 2 relics', () {
      final run = newRun();
      final fight = ambush.apply(run, null)! as StartFight;
      expect(fight.elite, isTrue);
      final reward = fight.onWin!(run)!;
      expect(run.credits, 50);
      expect(reward.offers, hasLength(2));
    });
  });
}
