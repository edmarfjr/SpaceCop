import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/run/relics.dart';
import 'package:starcop/domain/run/run_state.dart';

void main() {
  /// Through JSON text, like the real save.
  RunState roundTrip(RunState run) => RunState.fromJson(
    jsonDecode(jsonEncode(run.toJson())) as Map<String, Object?>,
  );

  test('a saved run comes back the same', () {
    final run = RunState(random: Random(7))
      ..act = 2
      ..maxHp = 90
      ..hp = 41
      ..credits = 123
      ..energyBaseBonus = 1
      ..nextBattleEnergy = 1
      ..openingStunTicks = 60
      ..relics.addAll([Relics.armor, Relics.capacitor]);
    run.deck
      ..add(ChipCard(Chips.bug))
      ..add(ChipCard(Chips.storm));
    run.upgrade(run.deck.first);
    run.enter(run.availableNodes.first);
    run.enter(run.availableNodes.first);

    final loaded = roundTrip(run);
    expect(loaded.act, 2);
    expect(loaded.maxHp, 90);
    expect(loaded.hp, 41);
    expect(loaded.credits, 123);
    expect(loaded.energyBaseBonus, 1);
    expect(loaded.nextBattleEnergy, 1);
    expect(loaded.openingStunTicks, 60);
    expect(loaded.relics, [Relics.armor, Relics.capacitor]);
    expect(
      loaded.deck.map((c) => (c.def.id, c.def.upgraded)),
      run.deck.map((c) => (c.def.id, c.def.upgraded)),
    );
    expect(loaded.deck.first.def.name, run.deck.first.def.name);
    expect(
      (loaded.current!.floor, loaded.current!.x),
      (run.current!.floor, run.current!.x),
    );
    expect(
      loaded.availableNodes.map((n) => (n.floor, n.x)),
      run.availableNodes.map((n) => (n.floor, n.x)),
    );
    expect(
      loaded.map.usedNodes.map((n) => (n.floor, n.x, n.type, n.visited)),
      run.map.usedNodes.map((n) => (n.floor, n.x, n.type, n.visited)),
    );
  });

  test('a run saved on the boss keeps it as the current node', () {
    final run = RunState(random: Random(8));
    run.current = run.map.boss..visited = true;
    final loaded = roundTrip(run);
    expect(loaded.current, same(loaded.map.boss));
    expect(loaded.map.boss.visited, isTrue);
  });

  test('a fresh run saves with no current node', () {
    final loaded = roundTrip(RunState(random: Random(9)));
    expect(loaded.current, isNull);
    expect(loaded.deck, hasLength(Chips.starterDeck().length));
  });
}
