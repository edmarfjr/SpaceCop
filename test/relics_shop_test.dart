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
  group('family and gear relics', () {
    final shot = shotOf(Element.neutral, family: ChipFamily.projectile);
    final blast = shotOf(Element.neutral, family: ChipFamily.explosive);
    final zap = shotOf(Element.neutral, family: ChipFamily.energy);
    final slash = shotOf(Element.neutral, family: ChipFamily.melee);

    int hit(RelicDef relic, ChipDef chip, {EnemyKind? kind}) {
      final battle = withRelics(
        [relic],
        [chip],
        spawns: [dummyAt(3, 1, kind: kind ?? EnemyKind.organic)],
      );
      use(battle, chip);
      return 100 - battle.enemies.single.hp;
    }

    test('Munição Perfurante: Projétil +3', () {
      expect(hit(Relics.piercingAmmo, shot), 13);
      expect(hit(Relics.piercingAmmo, zap), 10);
    });

    test('Carga Dupla: Explosivo +5', () {
      expect(hit(Relics.doubleCharge, blast), boom(15));
      expect(hit(Relics.doubleCharge, shot), 10);
    });

    test('Decodificador: +25% against Máquinas', () {
      expect(hit(Relics.decoder, zap, kind: EnemyKind.machine), 25);
      expect(hit(Relics.decoder, zap), 10);
    });

    test('Sintonizador de Fase: Projétil hits a phased Etéreo for half', () {
      expect(hit(Relics.phaseTuner, shot, kind: EnemyKind.ethereal), 5);
      expect(hit(Relics.phaseTuner, slash, kind: EnemyKind.ethereal), 0);
    });

    test('Lâmina Monomolecular: Corpo-a-corpo +50% on a stunned target', () {
      final battle = withRelics([Relics.monoBlade], [slash, slash]);
      final enemy = battle.enemies.single;
      use(battle, slash);
      expect(enemy.hp, 90);
      wait(battle, chainWindowTicks); // no chain bonus on the 2nd
      enemy.applyStatus(Status.stunned, ticksPerSecond);
      use(battle, slash);
      expect(enemy.hp, 90 - 15);
    });

    test('Bobina Supercondutora: Energia stuns a Wet target', () {
      final battle = withRelics([Relics.superconductor], [zap, zap]);
      final enemy = battle.enemies.single;
      use(battle, zap);
      expect(enemy.has(Status.stunned), isFalse);
      enemy.applyStatus(Status.wet, wetTicks);
      use(battle, zap);
      expect(enemy.has(Status.stunned), isTrue);
    });

    test('Carregador Estendido: the 1st Projétil of each hand is refunded', () {
      final battle = withRelics(
        [Relics.extendedMag],
        [Chips.cannon, Chips.cannon],
        spawns: [dummyAt(5, 1)],
      );
      use(battle, Chips.cannon);
      expect(battle.energy, baseEnergy);
      use(battle, Chips.cannon);
      expect(battle.energy, baseEnergy - Chips.cannon.cost);
      wait(battle, gaugeTicks);
      expect(battle.projectileRefunded, isFalse);
    });

    test('Simbionte: each Consumível heals 5', () {
      final battle = withRelics([Relics.symbiote], [Chips.energyTank])
        ..player.hp = 50;
      use(battle, Chips.energyTank);
      expect(battle.player.hp, 55);
    });

    test('Mochila Tática: the 1st single-use card goes to the discard', () {
      final battle = withRelics(
        [Relics.tacticalPack],
        [Chips.energyTank, Chips.energyTank],
      );
      use(battle, Chips.energyTank);
      expect(battle.deck.discardPile, hasLength(1));
      use(battle, Chips.energyTank);
      expect(battle.deck.discardPile, hasLength(1), reason: 'only once');
    });

    test('Capacitor: up to 2 leftover energy carries into the next hand', () {
      final battle = withRelics([Relics.capacitor], []);
      battle.energy = 3;
      wait(battle, gaugeTicks);
      expect(battle.energy, battle.energyMax + capacitorCarry);
    });

    test('Kit de Engenharia: gear lasts 50% longer', () {
      final battle = withRelics([Relics.engineeringKit], [Chips.barrier]);
      use(battle, Chips.barrier);
      expect(battle.player.barrierTicks, greaterThan(5 * ticksPerSecond));
    });

    test('Placa Blindada: a rock in front of the player at the start', () {
      final battle = withRelics([Relics.armorPlate], []);
      expect(
        battle.obstacles.single.pos,
        battle.player.pos + const GridPos(1, 0),
      );
    });

    test('Armadura: the first hit of each battle does nothing', () {
      final battle = withRelics([Relics.armor], []);
      battle.damage(battle.player, 20);
      expect(battle.player.hp, 100);
      battle.damage(battle.player, 20);
      expect(battle.player.hp, 80);
    });

    test('Servo-braço: melee hits push the target 1 panel', () {
      final battle = withRelics([Relics.servoArm], [Chips.sword])
        ..player.pos = const GridPos(2, 1);
      final enemy = battle.enemies.single;
      use(battle, Chips.sword);
      expect(enemy.pos, const GridPos(4, 1));
    });

    test('Pavio Curto: an Explosivo cracks the panel where it lands', () {
      final battle = withRelics([Relics.shortFuse], [Chips.grenade]);
      use(battle, Chips.grenade);
      expect(battle.panelAt(const GridPos(4, 1)).state, PanelState.cracked);
    });

    test('Chip da Sorte: rare cards come twice as often', () {
      int rares(RunState run) {
        var n = 0;
        for (var i = 0; i < 3000; i++) {
          if (run.rollRewards(1).single.rarity == Rarity.rare) n++;
        }
        return n;
      }

      final plain = rares(RunState(random: Random(7)));
      final lucky = rares(
        RunState(random: Random(7))..relics.add(Relics.luckyChip),
      );
      expect(lucky, greaterThan(plain * 3 ~/ 2));
    });
  });

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
    test('battle spoils: credits and a card; elites add a relic, bosses a '
        'choice of 3', () {
      final run = RunState(random: Random(1))..credits = 0;
      final normal = run.battleSpoils(elite: false);
      expect(normal, [isA<CreditsSpoil>(), isA<CardSpoil>()]);
      expect(run.credits, 0, reason: 'nothing given before it is claimed');
      run.claim(normal.first);
      expect(run.credits, battleCredits);

      final elite = run.battleSpoils(elite: true);
      expect(elite, [isA<CreditsSpoil>(), isA<RelicSpoil>(), isA<CardSpoil>()]);
      expect(run.relics, isEmpty);
      run.claim(elite[1]);
      expect(run.relics, [(elite[1] as RelicSpoil).relic]);
      final cards = (elite[2] as CardSpoil).cards;
      expect(cards, hasLength(3));
      run.claim(elite[2], card: cards.last);
      expect(run.deck.last.def, cards.last);

      final boss = run.battleSpoils(elite: true, boss: true);
      expect(boss, [
        isA<CreditsSpoil>(),
        isA<CardSpoil>(),
        isA<BossRelicSpoil>(),
      ]);
      final relics = (boss.last as BossRelicSpoil).relics;
      expect(relics, hasLength(3));
      expect(relics.every((r) => r.rarity == Rarity.rare), isTrue);
      expect(relics, isNot(contains(run.relics.first)));
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
      expect(run.credits, 200 - chipPrice(def.rarity));
      expect(run.deck, hasLength(deckSize + 1));
      expect(shop.chips, isNot(contains(def)));
      final relic = shop.relics.first;
      run.credits = relicPrice(relic.rarity);
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
      expect(shop.chipCost(Chips.shot), 30);
      expect(shop.chipCost(Chips.overclock), 75);
      expect(shop.removalCost, 0);
      shop.removeChip(run.deck.first);
      expect(run.credits, 100);
    });
  });

  group('rarity', () {
    test('commons are offered most, rares least', () {
      final run = RunState(random: Random(3));
      final counts = {for (final r in Rarity.values) r: 0};
      for (var i = 0; i < 3000; i++) {
        final rarity = run.rollRewards(1).single.rarity;
        counts[rarity] = counts[rarity]! + 1;
      }
      expect(counts[Rarity.common], greaterThan(counts[Rarity.uncommon]!));
      expect(counts[Rarity.uncommon], greaterThan(counts[Rarity.rare]!));
      expect(counts[Rarity.rare], inInclusiveRange(150, 450));
    });

    test('elite rewards roll rares more often', () {
      int rares({required bool elite}) {
        final run = RunState(random: Random(4));
        var n = 0;
        for (var i = 0; i < 3000; i++) {
          if (run.rollRewards(1, elite: elite).single.rarity == Rarity.rare) {
            n++;
          }
        }
        return n;
      }

      expect(rares(elite: true), greaterThan(rares(elite: false) * 3 ~/ 2));
    });

    test('rolls are distinct and fall back when a rarity runs out', () {
      final run = RunState(random: Random(5));
      final all = run.rollRewards(Chips.all.length);
      expect(all.toSet(), hasLength(Chips.all.length));
      run.relics.addAll(Relics.all.where((r) => r != Relics.extraBattery));
      expect(run.rollRelics(3), [Relics.extraBattery]);
    });

    test('upgrades keep the rarity', () {
      expect(Chips.upgradeOf(Chips.overclock)!.rarity, Rarity.rare);
    });
  });
}
