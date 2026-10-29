import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/rarity.dart';
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
      Encounters.boss(Random(), act: 2).spawns.single.def,
      Enemies.tribeKing,
    );
    expect(
      Encounters.boss(Random(), act: 3).spawns.single.def,
      Enemies.voidEye,
    );
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
