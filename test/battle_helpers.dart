import 'dart:math';

import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/element.dart';
import 'package:starcop/domain/grid.dart';

/// Harmless target: 100 HP, shoots for [shotDamage] (0 by default).
EnemyDef dummyOf(Element element, {int shotDamage = 0}) => EnemyDef(
  name: 'Alvo',
  hp: 100,
  moveTicks: 30,
  attackTicks: 60,
  shotDamage: shotDamage,
  element: element,
);

/// Single-target shot of [element], 10 damage, free.
/// Plain shot of [element]. Its family defaults to one that doesn't chain,
/// so repeated shots keep their plain damage.
ChipDef shotOf(
  Element element, {
  int damage = 10,
  ChipFamily family = ChipFamily.tactical,
}) => ChipDef(
  id: 'test_${element.name}_${family.name}',
  name: 'Teste',
  description: '',
  cost: 0,
  family: family,
  type: ChipType.attack,
  target: ChipTarget.row,
  damage: damage,
  element: element,
  effect: const ProjectileEffect(),
);

/// Battle with the player at (1, 1). The first tick (which draws the hand)
/// has already run.
BattleState battleWith(List<ChipDef> chips, {List<EnemySpawn>? spawns}) =>
    BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [for (final def in chips) ChipCard(def)],
      encounter: Encounter(
        spawns ?? [EnemySpawn(dummyOf(Element.neutral), const GridPos(3, 1))],
      ),
      random: Random(5),
    )..tick();

void wait(
  BattleState battle,
  int ticks, [
  PlayerInput input = PlayerInput.none,
]) {
  for (var i = 0; i < ticks; i++) {
    battle.tick(input);
  }
}

/// Uses the first chip in hand with [def] and waits out the attack cooldown,
/// long enough for a point-blank shot to land.
void use(BattleState battle, ChipDef def) {
  battle.selectChip(battle.hand.indexWhere((c) => c.def == def));
  battle.tick(const PlayerInput(useChip: true));
  wait(battle, playerAttackCooldown);
}

EnemySpawn dummyAt(int x, int y) =>
    EnemySpawn(dummyOf(Element.neutral), GridPos(x, y));
