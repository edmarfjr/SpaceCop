import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starcop/domain/battle/battle_state.dart';
import 'package:starcop/domain/battle/enemies.dart';
import 'package:starcop/domain/chips/battle_chip.dart';
import 'package:starcop/domain/chips/chip_library.dart';
import 'package:starcop/domain/grid.dart';

BattleState _battle(EnemySpawn spawn, {ChipDef card = Chips.shot}) =>
    BattleState(
      playerHp: 100,
      playerMaxHp: 100,
      deckCards: [ChipCard(card)],
      encounter: Encounter([spawn]),
      random: Random(1),
    );

void main() {
  test('a Carga C4 still blows up on an enemy that went underground', () {
    final battle = _battle(
      const EnemySpawn(Enemies.etTrap, GridPos(4, 1)),
      card: Chips.c4,
    );
    // Stage 1 (diving) keeps TrapBehavior idle, so it stays in the row.
    final enemy = battle.enemies.single
      ..burrowed = false
      ..stage = 1;
    final hp = enemy.hp;
    battle.tick(); // draws the hand
    battle.tick(const PlayerInput(useChip: true));
    expect(battle.stickies, hasLength(1));
    // Goes underground (both ways) before the blast.
    enemy
      ..hidden = true
      ..burrowed = true;
    for (var i = 0; i < 4 * ticksPerSecond; i++) {
      battle.tick();
    }
    expect(enemy.hp, lessThan(hp));
    expect(enemy.hidden, isTrue);
    expect(battle.unitAt(enemy.pos), isNull);
  });

  test('burrowed ET Emboscador is hurt by a mine it sets off, once', () {
    final battle = _battle(const EnemySpawn(Enemies.etTrap, GridPos(4, 1)));
    final trap = battle.enemies.single..burrowed = true;
    final hp = trap.hp;
    battle.panelAt(const GridPos(4, 2)).mineDamage = 15;

    battle.stepOver(trap, const GridPos(4, 2));

    expect(trap.hp, hp - 15);
    expect(trap.burrowed, isTrue);
    expect(battle.panelAt(const GridPos(4, 2)).mine, isFalse);
    battle.setOffMines(trap);
    expect(trap.hp, hp - 15);
  });

  test('burrowed and hidden enemies still ignore ordinary hits', () {
    final battle = _battle(const EnemySpawn(Enemies.etTrap, GridPos(4, 1)));
    final trap = battle.enemies.single..burrowed = true;
    final hp = trap.hp;
    battle.damage(trap, 10);
    expect(trap.hp, hp);
    trap
      ..burrowed = false
      ..hidden = true;
    battle.damage(trap, 10);
    expect(trap.hp, hp);
    expect(battle.unitAt(trap.pos), isNull);
  });

  test('hidden enemy on a mine panel is hurt when it is set off', () {
    final battle = _battle(const EnemySpawn(Enemies.digger, GridPos(4, 1)));
    final digger = battle.enemies.single..hidden = true;
    final hp = digger.hp;
    battle.panelAt(digger.pos).mineDamage = 20;

    battle.setOffMines(digger);

    expect(digger.hp, hp - 20);
    expect(digger.hidden, isTrue);
  });
}
