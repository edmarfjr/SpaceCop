import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/rarity.dart';
import 'package:starcop/domain/run/events.dart';
import 'package:starcop/domain/run/relics.dart';
import 'package:starcop/domain/run/run_state.dart';

void main() {
  test('a run starts in act 1 and moves on to a new map', () {
    final run = RunState(random: Random(1))
      ..hp = 20
      ..current = null;
    final firstMap = run.map;
    run.enter(run.availableNodes.first);
    run.nextAct();
    expect(run.act, 2);
    expect(run.map, isNot(same(firstMap)));
    expect(run.current, isNull);
    expect(run.hp, 20 + (80 * actHeal).round());
    run.nextAct();
    expect(run.lastAct, isTrue);
  });

  Set<EnemyDef> rolled(Encounter Function(Random) roll) {
    final random = Random(2);
    return {
      for (var i = 0; i < 300; i++)
        for (final spawn in roll(random).spawns) spawn.def,
    };
  }

  test('normal battles come from the act pool', () {
    expect(rolled((r) => Encounters.normal(r)), Enemies.basics.toSet());
    expect(rolled((r) => Encounters.normal(r, act: 2)), {
      ...Enemies.ruinsBasics,
      Enemies.scarab,
    });
    expect(
      rolled((r) => Encounters.normal(r, act: 3)),
      Enemies.shadowBasics.toSet(),
    );
  });

  test('the Curandeiro never fights alone', () {
    final random = Random(3);
    for (var i = 0; i < 300; i++) {
      final spawns = Encounters.normal(random, act: 2).spawns;
      if (spawns.any((s) => s.def == Enemies.etHealer)) {
        expect(spawns.length, greaterThan(1));
      }
    }
  });

  test('elites and bosses by act', () {
    expect(rolled((r) => Encounters.elite(r, act: 2)), {
      Enemies.etRider,
      Enemies.ruinGolem,
      Enemies.priestess,
      Enemies.portal,
      Enemies.etShieldBearer,
    });
    expect(rolled((r) => Encounters.elite(r, act: 3)), {
      Enemies.predator,
      Enemies.stalker,
    });
    expect(
      Encounters.boss(Random(), act: 1).spawns.first.def,
      isIn([Enemies.tank, Enemies.colonel, Enemies.argos]),
    );
    expect(
      Encounters.boss(Random(), act: 2).spawns.first.def,
      isIn([Enemies.tribeKing, Enemies.highPriest, Enemies.serpent]),
    );
    expect(
      Encounters.boss(Random(), act: 3).spawns.single.def,
      Enemies.voidEye,
    );
  });

  test('the boss is picked with the map, a new one each act', () {
    final run = RunState(random: Random(6));
    expect(Encounters.bossesOf(1), contains(run.bossEncounter));
    expect(run.boss, run.bossEncounter.spawns.first.def);
    run.nextAct();
    expect(Encounters.bossesOf(2), contains(run.bossEncounter));
    run.nextAct();
    expect(run.boss, Enemies.voidEye);
  });

  test('normal enemies and elites go through the whole bag first', () {
    final run = RunState(random: Random(7));
    final elites = {
      for (var i = 0; i < Encounters.elitesOf(1).length; i++)
        run.eliteEncounter().spawns.first.def,
    };
    expect(elites, hasLength(Encounters.elitesOf(1).length));
    final drawn = <EnemyDef>[];
    while (drawn.length < Enemies.basics.length) {
      drawn.addAll(run.normalEncounter().spawns.map((s) => s.def));
    }
    expect(
      drawn.take(Enemies.basics.length).toSet(),
      Enemies.basics.toSet(),
    );
    run.nextAct();
    expect(run.drawnNormals, isEmpty);
    expect(run.drawnElites, isEmpty);
  });

  test('events never repeat; act 3 gets the act 1 ones left', () {
    final run = RunState(random: Random(8));
    final act1 = {for (var i = 0; i < 4; i++) run.drawEvent()!};
    expect(act1, hasLength(4));
    run.nextAct();
    final act2 = {for (final _ in Events.ruins) run.drawEvent()!};
    expect(act2, Events.ruins.toSet());
    expect(run.drawEvent(), isNull);
    run.nextAct();
    final act3 = <EventDef>{};
    for (var event = run.drawEvent(); event != null; event = run.drawEvent()) {
      act3.add(event);
    }
    expect(act3, Events.all.toSet().difference(act1));
  });

  test('relics offered once are never offered again', () {
    final run = RunState(random: Random(9));
    final seen = <RelicDef>{};
    for (var offered = run.rollRelics(3);
        offered.isNotEmpty;
        offered = run.rollRelics(3)) {
      expect(offered.any(seen.contains), isFalse);
      seen.addAll(offered);
    }
    expect(seen, Relics.all.toSet());
  });

  test('cards go through their rarity before repeating', () {
    final run = RunState(random: Random(10));
    final rares = Chips.all.where((c) => c.rarity == Rarity.rare).toList();
    final offered = <ChipDef>[];
    while (offered.length + 3 <= rares.length) {
      offered.addAll(run.rollRewards(3, boss: true));
    }
    expect(offered.toSet(), hasLength(offered.length));
    expect(run.rollRewards(3, boss: true), hasLength(3));
  });

  test('bosses offer only rare cards', () {
    final run = RunState(random: Random(4));
    for (var i = 0; i < 20; i++) {
      for (final chip in run.rollRewards(3, boss: true)) {
        expect(chip.rarity, Rarity.rare);
      }
    }
  });
}
