import 'dart:math';

import '../element.dart';
import '../grid.dart';
import 'battle_state.dart';
import 'enemies.dart';
import 'panels.dart';

/// Shortest warning any attack gets.
const int minWarnTicks = ticksPerSecond ~/ 2;

/// Warning used by the basic enemies.
const int basicWarnTicks = ticksPerSecond;

/// Enemy AI, shared by every unit of an [EnemyDef]. Stateless: per-unit
/// state lives on the [EnemyFighter] (timers, [EnemyFighter.stage]).
///
/// [tick] is skipped while the enemy is stunned, which freezes its timers.
abstract class EnemyBehavior {
  const EnemyBehavior();

  void tick(EnemyFighter enemy, BattleState battle);

  /// Called once for each enemy the battle starts with. Attack timers start
  /// full here, so nobody attacks the moment the battle begins. Behaviors
  /// whose timers count up from 0 need nothing.
  void onBattleStart(EnemyFighter enemy) {}

  /// Ticks [EnemyFighter.timer] counts down from before the next attack;
  /// null when the behavior doesn't run on such a cycle.
  int? attackCycle(EnemyFighter enemy) => null;

  /// How close the next attack is, 0 (just attacked) to 1 (attacking);
  /// null when it can't tell. Drawn as a bar by the Visor de Combate.
  double? readiness(EnemyFighter enemy) {
    final total = attackCycle(enemy);
    if (total == null) return null;
    if (enemy.attacking) return 1;
    return (1 - enemy.timer / total).clamp(0, 1).toDouble();
  }

  /// Called after the player takes column [x] with Roubo de Área.
  void onAreaStolen(EnemyFighter enemy, BattleState battle, int x) {}

  /// Called every tick [enemy] is stunned, after its pending attacks were
  /// cancelled: drop any wind-up so nothing fires once the stun ends.
  void onInterrupted(EnemyFighter enemy, BattleState battle) {
    if (enemy.state != EnemyState.attacking) return;
    enemy
      ..state = EnemyState.idle
      ..attackTimer = 0;
  }
}

/// Cells in [enemy]'s row between it and the left edge.
List<GridPos> _rowAhead(EnemyFighter enemy) => [
  for (var x = enemy.pos.x - 1; x >= 0; x--) GridPos(x, enemy.pos.y),
];

List<GridPos> _column(int x) => [
  for (var y = 0; y < gridRows; y++) GridPos(x, y),
];

/// Every panel currently owned by [team].
List<GridPos> _side(BattleState battle, Team team) => [
  for (var x = 0; x < gridColumns; x++)
    for (var y = 0; y < gridRows; y++)
      if (battle.ownerAt(GridPos(x, y)) == team) GridPos(x, y),
];

/// Cracks [cells]; those already cracked collapse into holes, dropping
/// whoever stands on them (see [BattleState.collapse]).
void _crack(BattleState battle, List<GridPos> cells) {
  final cracked = [
    for (final cell in cells)
      if (battle.panelAt(cell).state == PanelState.cracked) cell,
  ];
  for (final cell in cells) {
    if (battle.panelAt(cell).state case PanelState.hole || PanelState.cracked) {
      continue;
    }
    battle.setPanel(cell, PanelState.cracked);
  }
  battle.collapse(cracked);
}

class IdleBehavior extends EnemyBehavior {
  const IdleBehavior();

  @override
  void tick(EnemyFighter enemy, BattleState battle) {}
}

/// Port of `i_move_ou_ataca` / `m_segue_sobe_desce`: line up with the
/// player's row, then shoot. The row is outlined until the shot leaves.
class MobileCannonBehavior extends EnemyBehavior {
  const MobileCannonBehavior();

  @override
  void onBattleStart(EnemyFighter enemy) =>
      enemy.moveTimer = enemy.def.moveTicks;

  @override
  double? readiness(EnemyFighter enemy) => enemy.attacking
      ? 1
      : (1 - enemy.moveTimer / enemy.def.moveTicks).clamp(0, 1).toDouble();

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    final def = enemy.def;
    final player = battle.player;
    switch (enemy.state) {
      case EnemyState.idle:
        if (enemy.moveTimer > 0) {
          enemy.moveTimer--;
        } else if (enemy.pos.y == player.pos.y) {
          enemy
            ..attackTimer = def.attackTicks
            ..state = EnemyState.attacking;
          battle.warn(
            _rowAhead(enemy),
            def.attackTicks ~/ 2,
            TelegraphKind.damage,
            enemy,
          );
        } else {
          enemy.state = EnemyState.moving;
        }
      case EnemyState.moving:
        battle.tryMove(enemy, GridPos(0, (player.pos.y - enemy.pos.y).sign));
        enemy
          ..moveTimer = def.moveTicks
          ..state = EnemyState.idle;
      case EnemyState.attacking:
        enemy.attackTimer--;
        if (enemy.attackTimer == def.attackTicks ~/ 2) battle.enemyShot(enemy);
        if (enemy.attackTimer <= 0) enemy.state = EnemyState.idle;
    }
  }
}

/// Raiz: never moves; hits the whole column the player stands in.
class RootBehavior extends EnemyBehavior {
  const RootBehavior();

  static const cycleTicks = 3 * ticksPerSecond;
  static const damage = 15;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    final cells = _column(battle.player.pos.x);
    battle.schedule(enemy, cells, basicWarnTicks, lob: Lob.ball, () {
      for (final cell in cells) {
        battle.strike(cell, damage, Team.player, enemy.element);
      }
    });
  }
}

/// Bolhador: wanders columns 4-5 and lobs a bubble at the player's panel,
/// which freezes into ice.
class BubblerBehavior extends EnemyBehavior {
  const BubblerBehavior();

  static const moveTicks = 45;
  static const cycleTicks = 3 * ticksPerSecond;
  static const damage = 10;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.moveTimer-- <= 0) {
      enemy.moveTimer = moveTicks;
      final steps = [
        const GridPos(1, 0),
        const GridPos(-1, 0),
        const GridPos(0, 1),
        const GridPos(0, -1),
      ]..shuffle(battle.random);
      for (final step in steps) {
        if ((enemy.pos + step).x >= 4 && battle.tryMove(enemy, step)) break;
      }
    }
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    final aim = battle.player.pos;
    battle.schedule(enemy, [aim], basicWarnTicks, lob: Lob.ball, () {
      battle.strike(aim, damage, Team.player, enemy.element);
      if (battle.panelAt(aim).walkable) battle.setPanel(aim, PanelState.ice);
    });
  }
}

/// Canhão Fixo: if the player stays one second in its row, an instant beam
/// hits the first thing in the way. A rock soaks it.
class CannonBehavior extends EnemyBehavior {
  const CannonBehavior();

  static const aimTicks = ticksPerSecond;
  static const cooldownTicks = 2 * ticksPerSecond;
  static const damage = 20;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cooldownTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cooldownTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer > 0) {
      enemy.timer--;
      return;
    }
    if (battle.player.pos.y != enemy.pos.y) {
      enemy
        ..attackTimer = 0
        ..state = EnemyState.idle;
      return;
    }
    final row = _rowAhead(enemy);
    battle.warn(row, 2, TelegraphKind.damage, enemy);
    enemy.state = EnemyState.attacking;
    if (++enemy.attackTimer < aimTicks) return;
    enemy
      ..attackTimer = 0
      ..timer = cooldownTicks
      ..state = EnemyState.idle
      ..attackPose = attackPoseTicks;
    for (final cell in row) {
      final unit = battle.unitAt(cell);
      if (unit == null || unit.team == Team.enemy) continue;
      battle.strike(cell, damage, Team.player, enemy.element);
      return;
    }
  }
}

/// Brute: follows the player's row and, every 4 s, charges down it. The
/// charge leaves its front shield down for a while: the window to hit it.
class BruteBehavior extends EnemyBehavior {
  const BruteBehavior();

  static const chargeEvery = 4 * ticksPerSecond;
  static const warnTicks = 45;
  static const damage = 25;

  @override
  double? readiness(EnemyFighter enemy) =>
      enemy.attacking ? 1 : (enemy.timer / chargeEvery).clamp(0, 1).toDouble();

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage == 1) return;
    if (++enemy.timer >= chargeEvery) {
      enemy
        ..timer = 0
        ..stage = 1;
      final cells = _rowAhead(enemy);
      battle.schedule(enemy, cells, warnTicks, () {
        for (final cell in cells) {
          battle.strike(cell, damage, Team.player, enemy.element);
        }
        enemy
          ..stage = 0
          ..shieldDown = shieldDownTicks;
      });
      return;
    }
    if (enemy.moveTimer-- > 0) return;
    final dy = (battle.player.pos.y - enemy.pos.y).sign;
    if (dy != 0) battle.tryMove(enemy, GridPos(0, dy));
    enemy.moveTimer = enemy.def.moveTicks;
  }

  @override
  void onInterrupted(EnemyFighter enemy, BattleState battle) => enemy.stage = 0;
}

/// Escavador: hides underground (untouchable), pops up on a random panel
/// of its side and throws a pickaxe that cracks, then holes, the player's
/// panel. Popping up on a cracked panel makes it fall.
///
/// Digging in and climbing out take [digTicks] each: it stands still and
/// can be hit meanwhile ([EnemyFighter.buried] drives the animation).
class DiggerBehavior extends EnemyBehavior {
  const DiggerBehavior();

  static const underTicks = 2 * ticksPerSecond;
  static const upTicks = ticksPerSecond;
  static const digTicks = 10;

  // Phases, kept in [EnemyFighter.stage].
  static const _up = 0;
  static const _diggingIn = 1;
  static const _under = 2;
  static const _climbingOut = 3;

  /// Starts above ground, so the player sees it, and digs in later.
  @override
  void onBattleStart(EnemyFighter enemy) => enemy
    ..stage = _up
    ..timer = underTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) {
      enemy.buried = switch (enemy.stage) {
        _diggingIn => 1 - enemy.timer / digTicks,
        _climbingOut => enemy.timer / digTicks,
        _ => enemy.buried,
      };
      return;
    }
    switch (enemy.stage) {
      case _up:
        enemy
          ..stage = _diggingIn
          ..timer = digTicks;
      case _diggingIn:
        enemy
          ..stage = _under
          ..hidden = true
          ..buried = 1
          ..timer = underTicks;
      case _under:
        final spots = [
          for (final cell in _side(battle, Team.enemy))
            if (battle.panelAt(cell).walkable && battle.unitAt(cell) == null)
              cell,
        ];
        if (spots.isEmpty) return;
        enemy
          ..pos = spots[battle.random.nextInt(spots.length)]
          ..hidden = false;
        if (battle.panelAt(enemy.pos).state == PanelState.cracked) {
          battle
            ..fall(enemy)
            ..setPanel(enemy.pos, PanelState.hole);
          enemy
            ..hidden = true
            ..timer = underTicks;
          return;
        }
        enemy
          ..stage = _climbingOut
          ..hidden = false
          ..buried = 1
          ..timer = digTicks;
      case _climbingOut:
        enemy
          ..stage = _up
          ..buried = 0
          ..timer = upTicks;
        final aim = battle.player.pos;
        battle.schedule(
          enemy,
          [aim],
          upTicks,
          () => _crack(battle, [aim]),
          kind: TelegraphKind.terrain,
          lob: Lob.pickaxe,
        );
    }
  }
}

/// Dupla Prisma: the twins mirror each other's vertical moves and shoot
/// down their rows. Damage rules live in [BattleState.damage].
class PrismBehavior extends EnemyBehavior {
  const PrismBehavior();

  static const moveTicks = 45;
  static const cycleTicks = 3 * ticksPerSecond;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    final twin = enemy.partner;
    final alone = twin == null || twin.isDead;
    final leads =
        alone || battle.enemies.indexOf(enemy) < battle.enemies.indexOf(twin);
    // Mirrored moves wait for both twins to be done attacking.
    final busy = enemy.attacking || (!alone && twin.attacking);
    if (leads && !busy && enemy.moveTimer-- <= 0) {
      enemy.moveTimer = moveTicks;
      for (final dy in [1, -1]..shuffle(battle.random)) {
        if (alone) {
          if (battle.tryMove(enemy, GridPos(0, dy))) break;
        } else if (battle.canEnter(enemy, enemy.pos + GridPos(0, dy)) &&
            battle.canEnter(twin, twin.pos + GridPos(0, -dy))) {
          battle
            ..tryMove(enemy, GridPos(0, dy))
            ..tryMove(twin, GridPos(0, -dy));
          break;
        }
      }
    }
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    battle.schedule(
      enemy,
      _rowAhead(enemy),
      basicWarnTicks,
      () => battle.enemyShot(enemy),
    );
  }
}

/// Guardião de Lava: every 3 s turns one panel of the player's side into
/// lava (burns them), and sweeps columns 1-2 of the player's row with fire.
class LavaGuardBehavior extends EnemyBehavior {
  const LavaGuardBehavior();

  static const lavaEvery = 3 * ticksPerSecond;
  static const flameEvery = 4 * ticksPerSecond;
  static const damage = 20;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy
    ..timer = lavaEvery
    ..moveTimer = flameEvery;

  @override
  int? attackCycle(EnemyFighter enemy) => lavaEvery;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- <= 0) {
      enemy.timer = lavaEvery;
      final spots = [
        for (final cell in _side(battle, Team.player))
          if (battle.panelAt(cell).state
              case PanelState.normal ||
                  PanelState.cracked ||
                  PanelState.ice ||
                  PanelState.grass)
            cell,
      ];
      if (spots.isNotEmpty) {
        final cell = spots[battle.random.nextInt(spots.length)];
        battle.schedule(
          enemy,
          [cell],
          minWarnTicks,
          () => battle.setPanel(cell, PanelState.lava),
          kind: TelegraphKind.terrain,
          lob: Lob.ball,
        );
      }
    }
    if (enemy.moveTimer-- > 0) return;
    enemy.moveTimer = flameEvery;
    final y = battle.player.pos.y;
    final cells = [GridPos(1, y), GridPos(2, y)];
    battle.schedule(enemy, cells, ticksPerSecond, lob: Lob.ball, () {
      final amount = battle.boosted(enemy, damage, Element.fire);
      for (final cell in cells) {
        battle.strike(cell, amount, Team.player, Element.fire);
      }
    });
  }
}

/// Colosso Sísmico: hammers the player's column, cracking it (holes on the
/// second hit), and leaves its fist stuck in column 3 as a weak point.
/// Below half HP it steals column 2, holes last 20 s and it attacks 25%
/// faster.
class ColossusBehavior extends EnemyBehavior {
  const ColossusBehavior();

  static const hammerEvery = 3 * ticksPerSecond;
  static const fistTicks = 2 * ticksPerSecond;
  static const damage = 20;
  static const ragingHoleTicks = 20 * ticksPerSecond;
  static const stealStunTicks = ticksPerSecond;

  @override
  double? readiness(EnemyFighter enemy) => enemy.attacking
      ? 1
      : (enemy.timer / (enemy.stage == 1 ? hammerEvery * 3 ~/ 4 : hammerEvery))
            .clamp(0, 1)
            .toDouble();

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage == 0 && enemy.hp * 2 < enemy.maxHp) {
      enemy.stage = 1;
      battle
        ..holeReturnTicks = ragingHoleTicks
        ..setColumnOwner(playerColumns - 1, Team.enemy);
      for (final cell in _column(playerColumns - 1)) {
        final unit = battle.unitAt(cell);
        if (unit != null && unit.team == Team.player) {
          battle.displace(unit, -1, 0, 1);
        }
      }
    }
    final every = enemy.stage == 1 ? hammerEvery * 3 ~/ 4 : hammerEvery;
    if (++enemy.timer < every) return;
    enemy.timer = 0;
    final cells = _column(battle.player.pos.x);
    final fistAt = GridPos(playerColumns, battle.player.pos.y);
    battle.schedule(enemy, cells, ticksPerSecond, lob: Lob.ball, () {
      for (final cell in cells) {
        battle.strike(cell, damage, Team.player, enemy.element);
      }
      _crack(battle, cells);
      if (battle.unitAt(fistAt) == null) {
        battle.summon(Enemies.colossusFist, fistAt, linkedTo: enemy).timer =
            fistTicks;
      }
    });
  }

  /// Taking back column 2 stuns the Colossus.
  @override
  void onAreaStolen(EnemyFighter enemy, BattleState battle, int x) {
    if (x < playerColumns) {
      enemy.applyStatus(Status.stunned, stealStunTicks);
    }
  }
}

/// The Colossus's fist: sits still until its time runs out or the body dies.
class FistBehavior extends EnemyBehavior {
  const FistBehavior();

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (--enemy.timer <= 0 || (enemy.linkedTo?.isDead ?? true)) enemy.hp = 0;
  }
}

/// Maestro Elemental: cycles Fire > Wood > Elec > Aqua every 10 s and
/// reshapes its side to match, warning 2 s ahead. Below half HP it hides
/// behind two Notes that strike 6 of the player's 9 panels in sequence.
class MaestroBehavior extends EnemyBehavior {
  const MaestroBehavior();

  static const switchEvery = 10 * ticksPerSecond;
  static const switchWarn = 2 * ticksPerSecond;
  static const cycle = [Element.fire, Element.wood, Element.elec, Element.aqua];
  static const attackEvery = 3 * ticksPerSecond;
  static const attackDamage = 15;
  static const volleyEvery = 5 * ticksPerSecond;
  static const volleyStagger = 10;
  static const noteDamage = 15;
  static const notesReturn = 15 * ticksPerSecond;

  static PanelState panelFor(Element element) => switch (element) {
    Element.fire => PanelState.lava,
    Element.wood => PanelState.grass,
    Element.aqua => PanelState.ice,
    Element.elec || Element.neutral => PanelState.normal,
  };

  @override
  double? readiness(EnemyFighter enemy) => enemy.attacking
      ? 1
      : (enemy.moveTimer / attackEvery).clamp(0, 1).toDouble();

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    // Element cycle.
    enemy.timer++;
    final side = _side(battle, Team.enemy);
    if (enemy.timer == switchEvery - switchWarn) {
      battle.warn(side, switchWarn, TelegraphKind.terrain);
    }
    if (enemy.timer >= switchEvery) {
      enemy
        ..timer = 0
        ..element = cycle[(cycle.indexOf(enemy.element) + 1) % cycle.length];
      for (final cell in side) {
        if (battle.panelAt(cell).walkable) {
          battle.setPanel(cell, panelFor(enemy.element), 0);
        }
      }
    }

    // Single-panel attack of the current element.
    if (++enemy.moveTimer >= attackEvery) {
      enemy.moveTimer = 0;
      final aim = battle.player.pos;
      battle.schedule(
        enemy,
        [aim],
        basicWarnTicks,
        () => battle.strike(aim, attackDamage, Team.player, enemy.element),
        lob: Lob.ball,
      );
    }

    // Second phase: Notes.
    if (enemy.stage == 0 && enemy.hp * 2 < enemy.maxHp) {
      enemy.stage = 1;
      _summonNotes(enemy, battle);
    }
    if (enemy.stage == 0) return;
    final notesAlive = battle.enemies.any(
      (e) => e.def == Enemies.note && !e.isDead,
    );
    if (enemy.invulnerable && !notesAlive) enemy.attackTimer = 0;
    enemy.invulnerable = notesAlive;
    enemy.attackTimer++;
    if (!notesAlive) {
      if (enemy.attackTimer >= notesReturn) _summonNotes(enemy, battle);
    } else if (enemy.attackTimer >= volleyEvery) {
      enemy.attackTimer = 0;
      final cells = _side(battle, Team.player)..shuffle(battle.random);
      final hit = cells.skip(3).toList();
      for (var i = 0; i < hit.length; i++) {
        final cell = hit[i];
        battle.schedule(
          enemy,
          [cell],
          basicWarnTicks + i * volleyStagger,
          () => battle.strike(cell, noteDamage, Team.player, Element.neutral),
          lob: Lob.ball,
        );
      }
    }
  }

  void _summonNotes(EnemyFighter enemy, BattleState battle) {
    enemy
      ..attackTimer = 0
      ..invulnerable = true;
    final spots = [
      for (final cell in _column(playerColumns))
        if (battle.panelAt(cell).walkable && battle.unitAt(cell) == null) cell,
    ]..shuffle(battle.random);
    for (final cell in spots.take(2)) {
      battle.summon(Enemies.note, cell);
    }
  }
}

/// Free panels of the enemy side, for units that reposition themselves.
List<GridPos> _freeEnemyPanels(BattleState battle) => [
  for (final cell in _side(battle, Team.enemy))
    if (battle.panelAt(cell).walkable && battle.unitAt(cell) == null) cell,
];

/// One random step on its own side every [moveTicks]; skipped while the
/// unit attacks (see [BattleState.tryMove]).
void _wander(EnemyFighter enemy, BattleState battle, int moveTicks) {
  if (enemy.moveTimer-- > 0) return;
  enemy.moveTimer = moveTicks;
  final steps = [
    const GridPos(1, 0),
    const GridPos(-1, 0),
    const GridPos(0, 1),
    const GridPos(0, -1),
  ]..shuffle(battle.random);
  for (final step in steps) {
    if (battle.tryMove(enemy, step)) break;
  }
}

/// [count] enemy shots down [enemy]'s row, [gapTicks] apart, after one
/// warning.
void _burst(
  EnemyFighter enemy,
  BattleState battle, {
  int count = 3,
  int gapTicks = 8,
}) {
  final row = _rowAhead(enemy);
  for (var i = 0; i < count; i++) {
    battle.schedule(
      enemy,
      row,
      basicWarnTicks + i * gapTicks,
      () => battle.enemyShot(enemy),
      telegraph: i == 0,
    );
  }
}

/// Ready to attack but not in the player's row: steps toward it every
/// [moveTicks] instead of wandering. False when already lined up.
bool _seekRow(EnemyFighter enemy, BattleState battle, int moveTicks) {
  final dy = (battle.player.pos.y - enemy.pos.y).sign;
  if (dy == 0) return false;
  if (enemy.moveTimer-- <= 0) {
    enemy.moveTimer = moveTicks;
    battle.tryMove(enemy, GridPos(0, dy));
  }
  return true;
}

/// One step every [moveTicks] away from the player: off their row, toward
/// the back. Used by the ETs after they attack.
void _flee(EnemyFighter enemy, BattleState battle, int moveTicks) {
  if (enemy.moveTimer-- > 0) return;
  enemy.moveTimer = moveTicks;
  final player = battle.player.pos;
  int distance(GridPos p) => (p.y - player.y).abs() * 2 + p.x;
  final steps = [
    const GridPos(1, 0),
    const GridPos(-1, 0),
    const GridPos(0, 1),
    const GridPos(0, -1),
  ]..shuffle(battle.random);
  steps.sort(
    (a, b) => distance(enemy.pos + b).compareTo(distance(enemy.pos + a)),
  );
  for (final step in steps) {
    if (distance(enemy.pos + step) <= distance(enemy.pos)) break;
    if (battle.tryMove(enemy, step)) break;
  }
}

/// Capanga Atirador: wanders its side and, once ready, lines up with the
/// player to shoot down its row. It stands still from the warning until the
/// shot leaves.
///
/// With [flee] (ET Atirador) it spends the first half of its cooldown
/// running away from the player instead of wandering.
class GruntGunBehavior extends EnemyBehavior {
  const GruntGunBehavior({this.wanderTicks = moveTicks, this.flee = false});

  static const moveTicks = 40;
  static const cycleTicks = 3 * ticksPerSecond;

  /// Pause between steps.
  final int wanderTicks;
  final bool flee;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer > 0) {
      enemy.timer--;
      flee && enemy.timer > cycleTicks ~/ 2
          ? _flee(enemy, battle, wanderTicks)
          : _wander(enemy, battle, wanderTicks);
      return;
    }
    if (_seekRow(enemy, battle, wanderTicks)) return;
    enemy.timer = cycleTicks;
    battle.schedule(
      enemy,
      _rowAhead(enemy),
      basicWarnTicks,
      () => battle.enemyShot(enemy),
    );
  }
}

/// Capanga Atirador Agachado: never moves; fires a burst of 3 shots.
class GruntDuckBehavior extends EnemyBehavior {
  const GruntDuckBehavior();

  static const cycleTicks = 4 * ticksPerSecond;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    _burst(enemy, battle);
  }
}

/// Capanga Corpo-a-Corpo: wanders and, once ready, lines up with the player.
/// Then it walks, panel by panel and with its walking frame, to the panel
/// right of where the player stood at that moment, into the player's area if
/// needed; its steps crack panels and set off mines like any move, and a
/// hole on the way makes it fall and give up. Half a second after arriving
/// it slashes the panel on its left, switching to its attack frame only
/// then, and goes back to the panel it came from. Once the slash lands it goes back to a free
/// panel of its side.
///
/// ET Guerreiro: [reach] 2 (it also hits the panel behind the player's),
/// faster steps and, with [flee], the first half of its cooldown spent
/// running away from the player.
class GruntMeleeBehavior extends EnemyBehavior {
  const GruntMeleeBehavior({
    this.reach = 1,
    this.wanderTicks = moveTicks,
    this.flee = false,
  });

  /// Panels hit, from the player's toward the left edge.
  final int reach;

  /// Pause between steps while wandering.
  final int wanderTicks;
  final bool flee;

  static const moveTicks = 40;
  static const cycleTicks = 4 * ticksPerSecond;

  /// Tried again this soon when there is no panel right of the player.
  static const retryTicks = ticksPerSecond ~/ 2;
  static const damage = 20;

  /// Ticks per panel while walking to the player.
  static const walkStepTicks = 3;

  // Phases, kept in [EnemyFighter.stage].
  static const _wandering = 0;
  static const _walking = 1;

  /// Attacked (or gave up): back home once the attack is over.
  static const _returning = 2;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage == _walking) {
      _walk(enemy, battle);
      return;
    }
    if (enemy.stage == _returning) {
      if (enemy.attacking) return;
      final home = enemy.home;
      final spots = _freeEnemyPanels(battle);
      final back = home != null && spots.contains(home)
          ? home
          : spots.isEmpty
          ? null
          : spots[battle.random.nextInt(spots.length)];
      if (back == null) return;
      enemy
        ..pos = back
        ..home = null
        ..aim = null
        ..stage = _wandering;
      return;
    }
    if (enemy.timer > 0) {
      enemy.timer--;
      flee && enemy.timer > cycleTicks ~/ 2
          ? _flee(enemy, battle, wanderTicks)
          : _wander(enemy, battle, wanderTicks);
      return;
    }
    if (_seekRow(enemy, battle, wanderTicks)) return;
    final aim = battle.player.pos;
    final spot = aim + const GridPos(1, 0);
    if (!spot.inBounds) {
      enemy.timer = retryTicks;
      return;
    }
    enemy
      ..timer = cycleTicks
      ..home = enemy.pos
      ..aim = aim
      ..moveTimer = walkStepTicks - 1
      ..stage = _walking;
    battle.warn(
      _reached(aim),
      (enemy.pos.x - spot.x).abs() * walkStepTicks + minWarnTicks,
      TelegraphKind.damage,
      enemy,
    );
  }

  /// The panels its slash covers, aimed at [aim].
  List<GridPos> _reached(GridPos aim) => [
    for (var i = 0; i < reach; i++)
      if (aim + GridPos(-i, 0) case final cell when cell.inBounds) cell,
  ];

  /// Stunned on the way: gives up and goes home.
  @override
  void onInterrupted(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage == _walking) enemy.stage = _returning;
  }

  /// One panel toward the spot right of [EnemyFighter.aim] every
  /// [walkStepTicks]; on arrival the slash is scheduled.
  void _walk(EnemyFighter enemy, BattleState battle) {
    if (enemy.moveTimer-- > 0) return;
    enemy.moveTimer = walkStepTicks - 1;
    final aim = enemy.aim!;
    final spot = aim + const GridPos(1, 0);
    if (enemy.pos != spot) {
      final next = enemy.pos + GridPos((spot.x - enemy.pos.x).sign, 0);
      if (!battle.panelAt(next).walkable) {
        battle.fall(enemy);
        enemy.stage = _returning;
        return;
      }
      if (battle.unitAt(next) != null) {
        enemy.stage = _returning;
        return;
      }
      battle.stepOver(enemy, next);
      if (enemy.pos != spot) return;
    }
    enemy.stage = _returning;
    final cells = _reached(aim);
    battle.schedule(enemy, cells, minWarnTicks, () {
      for (final cell in cells) {
        battle.strike(cell, damage, Team.player, enemy.element);
      }
    });
  }
}

/// Capanga Granada: wanders and lobs a grenade at the player's panel, which
/// catches fire (lava).
class GruntGrenadeBehavior extends EnemyBehavior {
  const GruntGrenadeBehavior();

  static const moveTicks = 40;
  static const cycleTicks = 7 * ticksPerSecond ~/ 2;
  static const damage = 10;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    _wander(enemy, battle, moveTicks);
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    final aim = battle.player.pos;
    battle.schedule(enemy, [aim], basicWarnTicks, lob: Lob.ball, () {
      battle.strike(aim, damage, Team.player, enemy.element);
      if (battle.panelAt(aim).walkable) battle.setPanel(aim, PanelState.lava);
    });
  }
}

/// Capanga Artilharia: never moves; fires a missile at the player's panel,
/// with a longer warning than the others.
class GruntArtilleryBehavior extends EnemyBehavior {
  const GruntArtilleryBehavior();

  static const cycleTicks = 4 * ticksPerSecond;
  static const warnTicks = 3 * ticksPerSecond ~/ 2;
  static const damage = 25;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    final aim = battle.player.pos;
    battle.schedule(
      enemy,
      [aim],
      warnTicks,
      () => battle.strike(aim, damage, Team.player, enemy.element),
      lob: Lob.ball,
    );
  }
}

/// Torreta: never moves; hides in the floor (untouchable), rises, shoots
/// down its row and sinks again. Rising and sinking reuse the Escavador's
/// animation ([EnemyFighter.buried]).
class SentryBehavior extends EnemyBehavior {
  const SentryBehavior();

  static const hiddenTicks = 2 * ticksPerSecond;
  static const riseTicks = DiggerBehavior.digTicks;

  // Phases, kept in [EnemyFighter.stage].
  static const _hidden = 0;
  static const _rising = 1;
  static const _up = 2;
  static const _sinking = 3;

  /// Starts risen, so the player sees it, and sinks [hiddenTicks] later.
  @override
  void onBattleStart(EnemyFighter enemy) => enemy
    ..stage = _up
    ..timer = hiddenTicks;

  /// One summoned mid-battle (ARGOS's Torres): it climbs out of the floor
  /// and fires right away. Left alone it would wait in [_hidden] without
  /// being hidden, blocked by itself on its own panel.
  static void emerge(EnemyFighter enemy) => enemy
    ..stage = _rising
    ..timer = riseTicks
    ..buried = 1;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    switch (enemy.stage) {
      case _hidden:
        if (enemy.timer-- > 0) return;
        // Someone stands on it, or the panel was taken: wait.
        if (battle.unitAt(enemy.pos) != null ||
            battle.ownerAt(enemy.pos) != Team.enemy) {
          return;
        }
        enemy
          ..hidden = false
          ..stage = _rising
          ..timer = riseTicks;
      case _rising:
        enemy.buried = --enemy.timer / riseTicks;
        if (enemy.timer > 0) return;
        enemy.stage = _up;
        battle.schedule(
          enemy,
          _rowAhead(enemy),
          basicWarnTicks,
          () => battle.enemyShot(enemy),
        );
      case _up:
        if (enemy.attacking || enemy.timer-- > 0) return;
        enemy
          ..stage = _sinking
          ..timer = riseTicks;
      case _sinking:
        enemy.buried = 1 - --enemy.timer / riseTicks;
        if (enemy.timer > 0) return;
        enemy
          ..hidden = true
          ..stage = _hidden
          ..timer = hiddenTicks;
    }
  }
}

/// Tanque de Guerra: two panels wide, patrols up and down the back two
/// columns and cycles three attacks: a 3-shot burst, mortars on random
/// panels of the player's side (they crack, cracked ones become holes) and
/// a charge down its row. The burst and the
/// charge are only triggered lined up with the player: it moves to the
/// player's row first, and fires missiles instead if it can't get there.
/// The charge is a real move: it cracks panels, sets off mines and falls
/// into holes (which ends the charge). The charge runs
/// over obstacles, hits the player and pushes them 1 panel back (a wall,
/// unit or hole behind them adds the usual collision or fall), leaves the
/// arena on the left and comes back on the right.
///
/// ET Montado ([chargeOnly]): only the charge, and it keeps trying to line
/// up instead of falling back to missiles.
class TankBehavior extends EnemyBehavior {
  const TankBehavior({this.chargeOnly = false});

  final bool chargeOnly;

  static const moveTicks = 45;

  /// Faster steps while lining up with the player for an attack.
  static const seekTicks = 10;

  /// Gives up lining up after this long and fires missiles instead.
  static const seekLimitTicks = 2 * ticksPerSecond;
  static const attackEvery = 3 * ticksPerSecond;
  static const missiles = 3;
  static const missileStagger = 10;
  static const missileDamage = 20;
  static const chargeWarnTicks = ticksPerSecond;

  /// Extra ticks spent on each panel while charging (1 = a panel every 2
  /// ticks).
  static const chargeStepTicks = 1;

  /// Whatever it runs over, the player included.
  static const chargeDamage = 30;

  /// Off the field between leaving on the left and coming back.
  static const awayTicks = 20;

  // Charge phases, kept in [EnemyFighter.stage]. The next attack is
  // [EnemyFighter.attackTimer] % 3.
  static const _ready = 0;
  static const _windingUp = 1;
  static const _charging = 2;

  /// Charging, but the player was already run over.
  static const _chargingHit = 3;
  static const _away = 4;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = attackEvery;

  @override
  int? attackCycle(EnemyFighter enemy) => attackEvery;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    switch (enemy.stage) {
      case _windingUp:
        return;
      case _charging || _chargingHit:
        _charge(enemy, battle);
        return;
      case _away:
        if (enemy.timer-- > 0) return;
        _comeBack(enemy, battle);
        return;
    }
    if (enemy.timer > 0) {
      enemy.timer--;
      if (!enemy.attacking && enemy.moveTimer-- <= 0) {
        enemy.moveTimer = moveTicks;
        for (final dy in [1, -1]..shuffle(battle.random)) {
          if (battle.tryMove(enemy, GridPos(0, dy))) break;
        }
      }
      return;
    }
    // [EnemyFighter.timer] goes negative while lining up.
    var next = chargeOnly ? 2 : enemy.attackTimer % 3;
    if (next != 1 && enemy.pos.y != battle.player.pos.y) {
      if (chargeOnly || enemy.timer > -seekLimitTicks) {
        enemy.timer--;
        _seekRow(enemy, battle, seekTicks);
        return;
      }
      next = 1;
    }
    enemy
      ..timer = attackEvery
      ..attackTimer = next + 1;
    switch (next) {
      case 0:
        _burst(enemy, battle);
      case 1:
        final cells = _side(battle, Team.player)..shuffle(battle.random);
        for (final (i, cell) in cells.take(missiles).indexed) {
          battle.schedule(
            enemy,
            [cell],
            basicWarnTicks + i * missileStagger,
            () {
              battle.strike(cell, missileDamage, Team.player, enemy.element);
              _crack(battle, [cell]);
            },
            lob: Lob.ball,
          );
        }
      case _:
        enemy.stage = _windingUp;
        battle.schedule(enemy, _rowAhead(enemy), chargeWarnTicks, () {
          enemy
            ..stage = _charging
            ..state = EnemyState.attacking
            ..moveTimer = chargeStepTicks;
        });
    }
  }

  /// Column of [pos] when the tank is back at the right edge.
  static const _homeX = gridColumns - 2;

  /// A stun before the charge starts calls it off; a charge already under
  /// way only pauses.
  @override
  void onInterrupted(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage == _windingUp) enemy.stage = _ready;
  }

  /// One panel to the left every [chargeStepTicks], hitting what is there.
  void _charge(EnemyFighter enemy, BattleState battle) {
    enemy.attackPose = attackPoseTicks;
    if (enemy.moveTimer-- > 0) return;
    enemy.moveTimer = chargeStepTicks;
    if (enemy.pos.x == 0) {
      _leave(enemy);
      return;
    }
    final cell = enemy.pos + const GridPos(-1, 0);
    if (!battle.panelAt(cell).walkable) {
      battle.fall(enemy);
      _leave(enemy);
      return;
    }
    // Hit before moving in, so the tank itself doesn't hide the target.
    switch (battle.unitAt(cell)) {
      case final PlayerFighter player when enemy.stage != _chargingHit:
        enemy.stage = _chargingHit;
        battle
          ..strike(cell, chargeDamage, Team.player, enemy.element)
          ..displace(player, -1, 0, 1);
      case PlayerFighter():
        break;
      case _?:
        battle.strike(cell, chargeDamage, Team.player, enemy.element);
      case null:
        break;
    }
    battle.stepOver(enemy, cell);
  }

  /// Off the arena (out on the left, or down a hole) until it comes back.
  /// Moved back to the right while hidden, so the sprite doesn't glide
  /// across the arena when it reappears.
  void _leave(EnemyFighter enemy) => enemy
    ..pos = GridPos(_homeX, enemy.pos.y)
    ..hidden = true
    ..state = EnemyState.idle
    ..stage = _away
    ..timer = awayTicks;

  /// Back on the right: its row if free, else any free row of the back two
  /// columns.
  void _comeBack(EnemyFighter enemy, BattleState battle) {
    for (final y in [enemy.pos.y, for (var y = 0; y < gridRows; y++) y]) {
      final cell = GridPos(_homeX, y);
      final free = [
        cell,
        cell + const GridPos(1, 0),
      ].every((c) => battle.panelAt(c).walkable && battle.unitAt(c) == null);
      if (free) {
        enemy
          ..pos = cell
          ..hidden = false
          ..stage = _ready;
        return;
      }
    }
  }
}

/// Panels between [a] and [b], walking.
int _steps(GridPos a, GridPos b) => (a.x - b.x).abs() + (a.y - b.y).abs();

/// ET Escudeiro: holds an ancient shield that stops straight shots from
/// the front ([EnemyDef.frontShield]). It keeps in front of an ally when it
/// can and, lined up with the player, fires a shot every [cycleTicks].
class ShieldBearerBehavior extends EnemyBehavior {
  const ShieldBearerBehavior();

  static const moveTicks = 40;
  static const cycleTicks = 4 * ticksPerSecond;

  /// The shield stays down this long after the shot leaves.
  static const openTicks = ticksPerSecond;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer > 0) enemy.timer--;
    if (enemy.timer <= 0 && enemy.pos.y == battle.player.pos.y) {
      // The shield drops to fire, and stays down a moment after.
      enemy
        ..timer = cycleTicks
        ..shieldDown = basicWarnTicks + openTicks;
      battle.schedule(
        enemy,
        _rowAhead(enemy),
        basicWarnTicks,
        () => battle.enemyShot(enemy),
      );
      return;
    }
    if (enemy.attacking || enemy.moveTimer-- > 0) return;
    enemy.moveTimer = moveTicks;
    // The panel in front of the ally closest to it, if one is free.
    final guard = [
      for (final ally in battle.enemies)
        if (ally != enemy && !ally.def.frontShield && !ally.isDead)
          if (ally.pos + const GridPos(-1, 0) case final spot
              when spot == enemy.pos ||
                  (battle.ownerAt(spot) == Team.enemy &&
                      battle.panelAt(spot).walkable &&
                      battle.unitAt(spot) == null))
            spot,
    ]..sort((a, b) => _steps(a, enemy.pos).compareTo(_steps(b, enemy.pos)));
    if (guard.isEmpty) {
      _wander(enemy, battle, 0);
      return;
    }
    final to = guard.first;
    if (to == enemy.pos) return;
    final step = to.x != enemy.pos.x
        ? GridPos((to.x - enemy.pos.x).sign, 0)
        : GridPos(0, (to.y - enemy.pos.y).sign);
    battle.tryMove(enemy, step);
  }
}

/// ET Curandeiro: wanders and, every [cycleTicks], channels for
/// [castTicks] (a stun calls it off) and heals the most hurt ally by
/// [heal].
class HealerBehavior extends EnemyBehavior {
  const HealerBehavior();

  static const moveTicks = 40;
  static const cycleTicks = 5 * ticksPerSecond;
  static const castTicks = ticksPerSecond;
  static const heal = 15;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) {
      _wander(enemy, battle, moveTicks);
      return;
    }
    enemy.timer = cycleTicks;
    final hurt = [
      for (final ally in battle.enemies)
        if (!ally.isDead && ally.hp < ally.maxHp) ally,
    ]..sort((a, b) => (a.hp / a.maxHp).compareTo(b.hp / b.maxHp));
    if (hurt.isEmpty) return;
    final target = hurt.first;
    battle.schedule(enemy, const [], castTicks, telegraph: false, () {
      if (target.isDead) return;
      target.hp = (target.hp + heal).clamp(0, target.maxHp);
      enemy.attackPose = attackPoseTicks;
    });
  }
}

/// Sentinela Ancestral: never moves; every [cycleTicks] sweeps the next
/// row of the player's side (top to bottom, then again) with a laser.
class SentinelBehavior extends EnemyBehavior {
  const SentinelBehavior();

  static const cycleTicks = 3 * ticksPerSecond;
  static const warnTicks = ticksPerSecond;
  static const damage = 15;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    final row = enemy.stage % gridRows;
    enemy.stage++;
    final cells = [
      for (final cell in _side(battle, Team.player))
        if (cell.y == row) cell,
    ];
    battle.schedule(enemy, cells, warnTicks, () {
      for (final cell in cells) {
        battle.strike(cell, damage, Team.player, enemy.element);
      }
    });
  }
}

/// Sacerdotisa ET: every [cycleTicks] blinks to a free panel and conjures
/// [illusions] copies of herself on others (the old ones fade). She casts
/// first, a lob at the player; the copies cast the same [lateTicks] later.
/// Copies die to any hit without hurting her.
class PriestessBehavior extends EnemyBehavior {
  const PriestessBehavior();

  static const cycleTicks = 4 * ticksPerSecond;
  static const illusions = 2;
  static const castDelay = ticksPerSecond;
  static const lateTicks = 20;
  static const damage = 15;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = ticksPerSecond;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    for (final copy in battle.enemies) {
      if (copy.def == Enemies.illusion) copy.hp = 0;
    }
    final free = _freeEnemyPanels(battle)..shuffle(battle.random);
    if (free.isNotEmpty) enemy.pos = free.removeLast();
    _cast(enemy, battle, castDelay);
    for (final spot in free.take(illusions)) {
      _cast(
        battle.summon(Enemies.illusion, spot),
        battle,
        castDelay + lateTicks,
      );
    }
  }

  static void _cast(EnemyFighter caster, BattleState battle, int ticks) {
    final aim = battle.player.pos;
    battle.schedule(
      caster,
      [aim],
      ticks,
      lob: Lob.ball,
      () => battle.strike(aim, damage, Team.player, caster.element),
    );
  }
}

/// Portal Ancestral: never moves. Opens every [spawnEvery] and lets out an
/// ET Guerreiro or ET Atirador (at most [maxOut] at once). Its energy ring
/// ([EnemyDef.frontShield]) stops shots from the front, except for
/// [openTicks] after each opening.
class PortalBehavior extends EnemyBehavior {
  const PortalBehavior();

  static const spawnEvery = 5 * ticksPerSecond;
  static const openTicks = 2 * ticksPerSecond;
  static const maxOut = 2;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = spawnEvery;

  @override
  int? attackCycle(EnemyFighter enemy) => spawnEvery;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    enemy
      ..timer = spawnEvery
      ..shieldDown = openTicks
      ..attackPose = attackPoseTicks;
    final out = battle.enemies.where(
      (e) => e.def == Enemies.etWarrior || e.def == Enemies.etGunner,
    );
    if (out.length >= maxOut) return;
    final free = _freeEnemyPanels(battle);
    if (free.isEmpty) return;
    final front = enemy.pos + const GridPos(-1, 0);
    battle.summon(
      battle.random.nextBool() ? Enemies.etWarrior : Enemies.etGunner,
      free.contains(front) ? front : free[battle.random.nextInt(free.length)],
    );
  }
}

/// Rei da Tribo: two panels wide, drifts toward the player's row and cycles
/// three attacks every [attackEvery]:
/// - Onda Crescente: a crescent sweeps the player's side column by column,
///   on every row but one (warned free);
/// - Raio do Cajado: lightning on 3 panels of the player's side; the staff
///   then overheats and he takes double damage for
///   [overheatTicks];
/// - Chamado da Tribo: an ET Guerreiro or ET Atirador joins him.
/// He starts behind 2 Totens and can't be hurt while one stands; they come
/// back [totemReturn] after the last falls. Below half HP (Fúria) he takes
/// column 2, attacks faster, sends two crescents and his totems are tougher.
class TribeKingBehavior extends EnemyBehavior {
  const TribeKingBehavior();

  static const moveTicks = 60;
  static const attackEvery = 3 * ticksPerSecond;
  static const crescentWarn = ticksPerSecond;
  static const crescentStagger = 6;
  static const crescentDamage = 25;
  static const lightningBolts = 3;
  static const lightningWarn = ticksPerSecond;
  static const lightningDamage = 20;
  static const overheatTicks = 2 * ticksPerSecond;
  static const totemReturn = 15 * ticksPerSecond;

  // [EnemyFighter.stage]: 0 calm, 1 Fúria. The next attack is
  // [EnemyFighter.attackTimer] % 3; [EnemyFighter.moveTimer] paces moves
  // and [EnemyFighter.timer] the attacks.

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = attackEvery;

  @override
  int? attackCycle(EnemyFighter enemy) =>
      enemy.stage == 1 ? attackEvery * 3 ~/ 4 : attackEvery;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    _guard(enemy, battle);
    if (enemy.stage == 0 && enemy.hp * 2 < enemy.maxHp) _rage(enemy, battle);
    if (!enemy.attacking && enemy.moveTimer-- <= 0) {
      enemy.moveTimer = moveTicks;
      final dy = (battle.player.pos.y - enemy.pos.y).sign;
      if (dy != 0) battle.tryMove(enemy, GridPos(0, dy));
    }
    if (enemy.attacking || enemy.timer-- > 0) return;
    enemy.timer = enemy.stage == 1 ? attackEvery * 3 ~/ 4 : attackEvery;
    switch (enemy.attackTimer++ % 3) {
      case 0:
        _crescent(enemy, battle, 0);
        if (enemy.stage == 1) _crescent(enemy, battle, ticksPerSecond);
      case 1:
        _lightning(enemy, battle);
      case _:
        final free = _freeEnemyPanels(battle);
        if (free.isEmpty) return;
        battle.summon(
          battle.random.nextBool() ? Enemies.tribeWarrior : Enemies.tribeGunner,
          free[battle.random.nextInt(free.length)],
        );
        enemy.attackPose = attackPoseTicks;
    }
  }

  /// Invulnerable while a totem stands; new totems [totemReturn] after the
  /// last one fell. [EnemyFighter.shieldDown] counts that wait.
  void _guard(EnemyFighter enemy, BattleState battle) {
    final standing = battle.enemies.any(
      (e) => e.def == Enemies.totem || e.def == Enemies.ragingTotem,
    );
    if (enemy.invulnerable && !standing) enemy.shieldDown = totemReturn;
    enemy.invulnerable = standing;
    if (standing || enemy.shieldDown > 0) return;
    _plantTotems(enemy, battle);
  }

  static void _plantTotems(EnemyFighter enemy, BattleState battle) {
    final free = _freeEnemyPanels(battle)..shuffle(battle.random);
    for (final spot in free.take(2)) {
      battle.summon(
        enemy.stage == 1 ? Enemies.ragingTotem : Enemies.totem,
        spot,
      );
    }
    enemy.invulnerable = free.isNotEmpty;
  }

  void _rage(EnemyFighter enemy, BattleState battle) {
    enemy.stage = 1;
    battle.setColumnOwner(playerColumns - 1, Team.enemy);
    for (final cell in _column(playerColumns - 1)) {
      final unit = battle.unitAt(cell);
      if (unit != null && unit.team == Team.player) {
        battle.displace(unit, -1, 0, 1);
      }
    }
  }

  /// One crescent, [delay] ticks late: all rows but a free one, from the
  /// front column of the player's side to the back.
  void _crescent(EnemyFighter enemy, BattleState battle, int delay) {
    final free = battle.random.nextInt(gridRows);
    final columns = {
      for (final cell in _side(battle, Team.player)) cell.x,
    }.toList()..sort((a, b) => b.compareTo(a));
    for (final (i, x) in columns.indexed) {
      final cells = [
        for (var y = 0; y < gridRows; y++)
          if (y != free) GridPos(x, y),
      ];
      battle.schedule(
        enemy,
        cells,
        crescentWarn + delay + i * crescentStagger,
        () {
          for (final cell in cells) {
            battle.strike(cell, crescentDamage, Team.player, enemy.element);
          }
        },
      );
    }
  }

  void _lightning(EnemyFighter enemy, BattleState battle) {
    final cells = (_side(
      battle,
      Team.player,
    )..shuffle(battle.random)).take(lightningBolts).toList();
    battle.schedule(enemy, cells, lightningWarn, () {
      for (final cell in cells) {
        battle.strike(cell, lightningDamage, Team.player, Element.elec);
      }
      enemy.exposedTicks = overheatTicks;
    });
  }
}

// Etéreos (third mission). Phased out of normal matter: Projétil and
// Corpo-a-corpo pass through them except while they attack (see
// [EnemyFighter.phased]).

/// Sombra Alada: every [cycleTicks] blinks to a free panel of its side and
/// lobs a ball at the player's panel.
class ShadowFlyBehavior extends EnemyBehavior {
  const ShadowFlyBehavior();

  static const cycleTicks = 3 * ticksPerSecond;
  static const damage = 10;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    final spots = _freeEnemyPanels(battle);
    if (spots.isNotEmpty) {
      enemy.pos = spots[battle.random.nextInt(spots.length)];
    }
    final aim = battle.player.pos;
    battle.schedule(
      enemy,
      [aim],
      basicWarnTicks,
      lob: Lob.ball,
      () => battle.strike(aim, damage, Team.player, enemy.element),
    );
  }
}

/// Sombra Saltadora: the Capanga Corpo-a-Corpo's attack, but it stays solid
/// from the moment it leaps until it is back home.
class ShadowJumperBehavior extends GruntMeleeBehavior {
  const ShadowJumperBehavior();

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    super.tick(enemy, battle);
    if (enemy.stage != GruntMeleeBehavior._wandering) enemy.materialTicks = 2;
  }
}

/// Ninho: never moves; every [cycleTicks] hatches a Carrapato in front of
/// it (at most [maxTicks] alive), and stays solid for a moment after.
class NestBehavior extends EnemyBehavior {
  const NestBehavior();

  static const cycleTicks = 4 * ticksPerSecond;
  static const maxTicks = 3;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    final alive = battle.enemies.where((e) => e.def == Enemies.shadowTick);
    if (alive.length >= maxTicks) return;
    final front = enemy.pos + const GridPos(-1, 0);
    final free = _freeEnemyPanels(battle);
    final spot = free.contains(front)
        ? front
        : free.isEmpty
        ? null
        : free[battle.random.nextInt(free.length)];
    if (spot == null) return;
    battle.summon(Enemies.shadowTick, spot);
    enemy
      ..attackPose = attackPoseTicks
      ..materialTicks = ticksPerSecond;
  }
}

/// Carrapato: crawls one panel per [stepTicks] down its row toward the
/// player, into their side. Next to anything in its way it stops and blows
/// up after a short warning, then dies. Always solid while it crawls.
class TickBehavior extends EnemyBehavior {
  const TickBehavior();

  static const stepTicks = ticksPerSecond;
  static const damage = 15;

  // Phases, kept in [EnemyFighter.stage].
  static const _exploding = 1;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    enemy.materialTicks = 2;
    if (enemy.stage == _exploding || enemy.moveTimer-- > 0) return;
    enemy.moveTimer = stepTicks;
    final next = enemy.pos + const GridPos(-1, 0);
    if (!next.inBounds || !battle.panelAt(next).walkable) {
      enemy.hp = 0;
      return;
    }
    final blocker = battle.unitAt(next);
    if (blocker == null) {
      battle.stepOver(enemy, next);
      return;
    }
    if (blocker.team == Team.enemy) return;
    enemy.stage = _exploding;
    battle.schedule(enemy, [next], minWarnTicks, () {
      battle.strike(next, damage, Team.player, enemy.element);
      enemy.hp = 0;
    });
  }

  /// Stunned while about to blow up: it fizzles out.
  @override
  void onInterrupted(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage == _exploding) enemy.hp = 0;
  }
}

/// Predador: vanishes (untouchable) for [hiddenTicks], reappears on its
/// side in the player's row and, after a short warning, slashes the whole
/// column the player stands in. It stays solid for [recoverTicks] after.
class PredatorBehavior extends EnemyBehavior {
  const PredatorBehavior();

  static const visibleTicks = 2 * ticksPerSecond;
  static const hiddenTicks = 2 * ticksPerSecond;
  static const recoverTicks = ticksPerSecond;
  static const damage = 25;

  // Phases, kept in [EnemyFighter.stage].
  static const _visible = 0;
  static const _hidden = 1;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = visibleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.attacking || enemy.timer-- > 0) return;
    if (enemy.stage == _visible) {
      enemy
        ..stage = _hidden
        ..hidden = true
        ..timer = hiddenTicks;
      return;
    }
    final row = battle.player.pos.y;
    final free = _freeEnemyPanels(battle);
    final inRow = free.where((c) => c.y == row).toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    final spot = inRow.isNotEmpty
        ? inRow.first
        : free.isEmpty
        ? enemy.pos
        : free[battle.random.nextInt(free.length)];
    enemy
      ..pos = spot
      ..hidden = false
      ..stage = _visible
      ..timer = visibleTicks;
    final cells = _column(battle.player.pos.x);
    battle.schedule(enemy, cells, minWarnTicks, () {
      for (final cell in cells) {
        battle.strike(cell, damage, Team.player, enemy.element);
      }
      enemy.materialTicks = recoverTicks;
    });
  }

  /// Stunned while hidden would leave it stuck out of reach: it shows up.
  @override
  void onInterrupted(EnemyFighter enemy, BattleState battle) {
    if (!enemy.hidden) return;
    enemy
      ..hidden = false
      ..stage = _visible
      ..timer = visibleTicks;
  }
}

/// Espreitador: follows the player's row and, every [chargeEvery], charges
/// down it, cracking the panels it runs over. Solid while charging and for
/// [recoverTicks] after.
class StalkerBehavior extends EnemyBehavior {
  const StalkerBehavior();

  static const chargeEvery = 4 * ticksPerSecond;
  static const warnTicks = 45;
  static const recoverTicks = ticksPerSecond;
  static const damage = 30;

  @override
  double? readiness(EnemyFighter enemy) =>
      enemy.attacking ? 1 : (enemy.timer / chargeEvery).clamp(0, 1).toDouble();

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.attacking) return;
    if (++enemy.timer >= chargeEvery) {
      enemy.timer = 0;
      final cells = _rowAhead(enemy);
      battle.schedule(enemy, cells, warnTicks, () {
        for (final cell in cells) {
          battle.strike(cell, damage, Team.player, enemy.element);
        }
        _crack(battle, cells);
        enemy.materialTicks = recoverTicks;
      });
      return;
    }
    if (enemy.moveTimer-- > 0) return;
    final dy = (battle.player.pos.y - enemy.pos.y).sign;
    if (dy != 0) battle.tryMove(enemy, GridPos(0, dy));
    enemy.moveTimer = enemy.def.moveTicks;
  }
}

// ETs (second mission): a tribe of small aliens using the ruins' old tech
// like magic.

/// ET Emboscador: wanders burrowed (only Explosivo hurts it; shots fly
/// over it). Every [cycleTicks] it dives toward the panel the player stands
/// on, bursts out there after a warning and stays exposed for
/// [exposedTicks] (attack frame, hit by anything), then burrows again back
/// home.
class TrapBehavior extends EnemyBehavior {
  const TrapBehavior();

  static const moveTicks = 30;
  static const cycleTicks = 4 * ticksPerSecond;
  static const warnTicks = ticksPerSecond;
  static const exposedTicks = ticksPerSecond;
  static const damage = 20;

  // Phases, kept in [EnemyFighter.stage].
  static const _burrowed = 0;
  static const _diving = 1;
  static const _exposed = 2;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy
    ..burrowed = true
    ..timer = cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    switch (enemy.stage) {
      case _diving:
        return;
      case _exposed:
        enemy.attackPose = enemy.timer;
        if (enemy.timer-- > 0) return;
        enemy
          ..attackPose = 0
          ..burrowed = true
          ..stage = _burrowed
          ..timer = cycleTicks;
        final home = enemy.home;
        final free = _freeEnemyPanels(battle);
        final back = home != null && free.contains(home)
            ? home
            : free.isEmpty
            ? null
            : free[battle.random.nextInt(free.length)];
        if (back != null) enemy.pos = back;
        enemy.home = null;
        return;
    }
    if (enemy.timer-- > 0) {
      _wander(enemy, battle, moveTicks);
      return;
    }
    final aim = battle.player.pos;
    enemy
      ..stage = _diving
      ..home = enemy.pos;
    battle.schedule(enemy, [aim], warnTicks, () {
      battle.strike(aim, damage, Team.player, enemy.element);
      if (battle.unitAt(aim) case final PlayerFighter player) {
        battle.displace(player, -1, 0, 1);
      }
      if (battle.unitAt(aim) == null && battle.panelAt(aim).walkable) {
        enemy.pos = aim;
      }
      enemy
        ..burrowed = false
        ..stage = _exposed
        ..timer = exposedTicks;
    });
  }

  /// Stunned while diving: it stays burrowed where it is.
  @override
  void onInterrupted(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage != _diving) return;
    enemy
      ..stage = _burrowed
      ..timer = cycleTicks;
  }
}

/// ET Xamã: wanders and, every [cycleTicks], leaves an energy sphere on its
/// panel and steps off it. The sphere fires the mortars (see
/// [SphereBehavior]).
class ShamanBehavior extends EnemyBehavior {
  const ShamanBehavior();

  static const moveTicks = 40;
  static const cycleTicks = 5 * ticksPerSecond;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) {
      _wander(enemy, battle, moveTicks);
      return;
    }
    final free = _freeEnemyPanels(battle);
    if (free.isEmpty) {
      enemy.timer = moveTicks;
      return;
    }
    enemy
      ..timer = cycleTicks
      ..attackPose = attackPoseTicks;
    final spot = enemy.pos;
    enemy.pos = free[battle.random.nextInt(free.length)];
    battle.summon(Enemies.energySphere, spot);
  }
}

/// Esfera de Energia: an enemy turret. Fires [shots] mortars at wherever
/// the player stands, [gapTicks] apart, then fades away.
class SphereBehavior extends EnemyBehavior {
  const SphereBehavior();

  static const shots = 3;
  static const gapTicks = 20;
  static const damage = 10;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    if (enemy.stage == shots) {
      if (!enemy.attacking) enemy.hp = 0;
      return;
    }
    enemy
      ..timer = gapTicks
      ..stage += 1;
    final aim = battle.player.pos;
    battle.schedule(
      enemy,
      [aim],
      basicWarnTicks,
      lob: Lob.ball,
      () => battle.strike(aim, damage, Team.player, enemy.element),
    );
  }
}

/// Olho do Abismo: the third mission's boss, two panels by two. Phased like
/// any Etéreo: only solid while it attacks. Every [attackEvery] it cycles:
/// - Olhar Abissal: a beam down the player's row and column;
/// - Chuva de Fragmentos: [shards] shards on panels of the player's side;
/// - Ninhada: [broodSize] Carrapatos.
/// Below [splitAt] of its HP (Cisão) it sheds two Hemisférios and can't be
/// hurt while one lives. With both gone it reels, stunned and taking double
/// damage for [reelTicks], then wakes up (Despertar): solid for good,
/// faster, and every gaze comes with a second one.
class VoidEyeBehavior extends EnemyBehavior {
  const VoidEyeBehavior();

  static const moveTicks = 60;
  static const attackEvery = 3 * ticksPerSecond;
  static const gazeWarn = ticksPerSecond;
  static const gazeDamage = 20;
  static const shards = 5;
  static const shardStagger = 8;
  static const shardDamage = 12;
  static const broodSize = 2;
  static const splitAt = 0.6;
  static const reelTicks = 3 * ticksPerSecond;

  // Phases, kept in [EnemyFighter.stage]; the sprite strip follows them.
  static const _eye = 0;
  static const _split = 1;
  static const _awake = 2;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = attackEvery;

  @override
  int? attackCycle(EnemyFighter enemy) =>
      enemy.stage == _awake ? attackEvery * 7 ~/ 10 : attackEvery;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    switch (enemy.stage) {
      case _eye when enemy.hp < enemy.maxHp * splitAt:
        _cleave(enemy, battle);
      case _split:
        final halves = battle.enemies.any((e) => e.def == Enemies.hemisphere);
        enemy.invulnerable = halves;
        if (!halves) {
          enemy
            ..stage = _awake
            ..exposedTicks = reelTicks
            ..materialTicks = reelTicks
            ..applyStatus(Status.stunned, reelTicks);
          return;
        }
      case _awake:
        enemy.materialTicks = 2;
    }
    if (!enemy.attacking && enemy.moveTimer-- <= 0) {
      enemy.moveTimer = moveTicks;
      final y = battle.player.pos.y;
      final dy = y < enemy.pos.y
          ? -1
          : y > enemy.pos.y + 1
          ? 1
          : 0;
      if (dy != 0) battle.tryMove(enemy, GridPos(0, dy));
    }
    if (enemy.attacking || enemy.timer-- > 0) return;
    enemy.timer = enemy.stage == _awake ? attackEvery * 7 ~/ 10 : attackEvery;
    switch (enemy.attackTimer++ % 3) {
      case 0:
        _gaze(enemy, battle, battle.player.pos, 0);
        if (enemy.stage == _awake) {
          final side = _side(battle, Team.player);
          _gaze(
            enemy,
            battle,
            side[battle.random.nextInt(side.length)],
            ticksPerSecond ~/ 2,
          );
        }
      case 1:
        final cells = (_side(
          battle,
          Team.player,
        )..shuffle(battle.random)).take(shards);
        for (final (i, cell) in cells.indexed) {
          battle.schedule(
            enemy,
            [cell],
            basicWarnTicks + i * shardStagger,
            lob: Lob.ball,
            () => battle.strike(cell, shardDamage, Team.player, enemy.element),
          );
        }
      case _:
        final free = _freeEnemyPanels(battle)..shuffle(battle.random);
        for (final spot in free.take(broodSize)) {
          battle.summon(Enemies.shadowTick, spot);
        }
        enemy.attackPose = attackPoseTicks;
    }
  }

  /// Cisão: two Hemisférios break off; it can't be hurt while one lives.
  void _cleave(EnemyFighter enemy, BattleState battle) {
    enemy.stage = _split;
    final free = _freeEnemyPanels(battle)..shuffle(battle.random);
    for (final spot in free.take(2)) {
      battle.summon(Enemies.hemisphere, spot);
    }
    enemy.invulnerable = free.isNotEmpty;
  }

  /// A beam down [aim]'s row and column of the player's side, [delay]
  /// ticks after the usual warning.
  void _gaze(EnemyFighter enemy, BattleState battle, GridPos aim, int delay) {
    final cells = [
      for (final cell in _side(battle, Team.player))
        if (cell.x == aim.x || cell.y == aim.y) cell,
    ];
    battle.schedule(enemy, cells, gazeWarn + delay, () {
      for (final cell in cells) {
        battle.strike(cell, gazeDamage, Team.player, enemy.element);
      }
    });
  }
}

/// Hemisfério: a piece of the Olho do Abismo. Never moves; fires down its
/// row every [cycleTicks].
class HemisphereBehavior extends EnemyBehavior {
  const HemisphereBehavior();

  static const cycleTicks = 3 * ticksPerSecond;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  int? attackCycle(EnemyFighter enemy) => cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer-- > 0) return;
    enemy.timer = cycleTicks;
    battle.schedule(
      enemy,
      _rowAhead(enemy),
      basicWarnTicks,
      () => battle.enemyShot(enemy),
    );
  }
}

/// Coronel Inimigo: another boss of the first mission. Drifts toward the
/// player's row behind his Guarda-costas (a new one comes [guardReturn]
/// after one falls) and cycles three attacks every [attackEvery]:
/// - Rajada: sweeps the player's side column by column, front to back,
///   sparing one row per column; then he reloads, taking double damage
///   for [reloadTicks];
/// - Contrato: a sniper hits the player's panel after [contractWarn];
/// - Coquetel Molotov: a cross of lava around the player.
/// Below half HP he puts up 2 barricades in front of him, attacks faster
/// and the Contrato marks a second panel.
class ColonelBehavior extends EnemyBehavior {
  const ColonelBehavior();

  static const moveTicks = 50;
  static const attackEvery = 3 * ticksPerSecond;
  static const guards = 2;
  static const guardReturn = 12 * ticksPerSecond;
  static const sweepWarn = ticksPerSecond;
  static const sweepStagger = 8;
  static const sweepDamage = 15;
  static const reloadTicks = 45;
  static const contractWarn = 45;
  static const contractDamage = 25;
  static const molotovWarn = ticksPerSecond;
  static const molotovDamage = 15;
  static const barricades = 2;
  static const barricadeHp = 40;

  // Frames of his strip, kept in [EnemyFighter.pose].
  static const idlePose = 0;
  static const shootPose = 1;
  static const reloadPose = 2;
  static const radioPose = 3;
  static const throwPose = 4;
  static const furyPose = 5;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = attackEvery;

  @override
  int? attackCycle(EnemyFighter enemy) =>
      enemy.stage == 1 ? attackEvery * 7 ~/ 10 : attackEvery;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage == 0 && enemy.hp < enemy.maxHp / 2) _fury(enemy, battle);
    _callGuards(enemy, battle);
    if (enemy.exposedTicks > 0) {
      enemy.pose = reloadPose;
      return;
    }
    if (!enemy.attacking) {
      enemy.pose = enemy.stage == 1 ? furyPose : idlePose;
      if (enemy.moveTimer-- <= 0) {
        enemy.moveTimer = moveTicks;
        final dy = (battle.player.pos.y - enemy.pos.y).sign;
        if (dy != 0) battle.tryMove(enemy, GridPos(0, dy));
      }
    }
    if (enemy.attacking || enemy.timer-- > 0) return;
    enemy.timer = enemy.stage == 1 ? attackEvery * 7 ~/ 10 : attackEvery;
    switch (enemy.attackTimer++ % 3) {
      case 0:
        _sweep(enemy, battle);
      case 1:
        _contract(enemy, battle);
      case _:
        _molotov(enemy, battle);
    }
  }

  /// A new Guarda-costas [guardReturn] after one falls.
  void _callGuards(EnemyFighter enemy, BattleState battle) {
    final standing = battle.enemies
        .where((e) => e.def == Enemies.colonelGuard && !e.isDead)
        .length;
    if (standing >= guards) {
      enemy.summonTimer = 0;
      return;
    }
    if (enemy.summonTimer == 0) {
      enemy.summonTimer = guardReturn;
      return;
    }
    if (--enemy.summonTimer > 0) return;
    final front = enemy.pos + const GridPos(-1, 0);
    final free = _freeEnemyPanels(battle);
    if (free.isEmpty) return;
    battle.summon(
      Enemies.colonelGuard,
      free.contains(front) ? front : free[battle.random.nextInt(free.length)],
    );
  }

  /// Fury: barricades on free panels of the column in front of him.
  void _fury(EnemyFighter enemy, BattleState battle) {
    enemy.stage = 1;
    final spots = [
      for (final cell in _column(enemy.pos.x - 1))
        if (battle.ownerAt(cell) == Team.enemy &&
            battle.panelAt(cell).walkable &&
            battle.unitAt(cell) == null)
          cell,
    ]..shuffle(battle.random);
    for (final spot in spots.take(barricades)) {
      battle.obstacles.add(
        Obstacle(ObstacleKind.rock, pos: spot, hp: barricadeHp),
      );
    }
  }

  /// Rajada: column by column from the front, one row spared in each.
  void _sweep(EnemyFighter enemy, BattleState battle) {
    enemy.pose = shootPose;
    final columns = {for (final c in _side(battle, Team.player)) c.x}.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final (i, x) in columns.indexed) {
      final spared = battle.random.nextInt(gridRows);
      final cells = [
        for (final cell in _column(x))
          if (cell.y != spared && battle.ownerAt(cell) == Team.player) cell,
      ];
      final last = i == columns.length - 1;
      battle.schedule(enemy, cells, sweepWarn + i * sweepStagger, () {
        for (final cell in cells) {
          battle.strike(cell, sweepDamage, Team.player, enemy.element);
        }
        if (last) enemy.exposedTicks = reloadTicks;
      });
    }
  }

  /// Contrato: the player's panel, and another one in Fury.
  void _contract(EnemyFighter enemy, BattleState battle) {
    enemy.pose = radioPose;
    final cells = [battle.player.pos];
    if (enemy.stage == 1) {
      final others = _side(battle, Team.player)
        ..remove(battle.player.pos)
        ..shuffle(battle.random);
      cells.addAll(others.take(1));
    }
    battle.schedule(enemy, cells, contractWarn, () {
      for (final cell in cells) {
        battle.strike(cell, contractDamage, Team.player, enemy.element);
      }
    });
  }

  /// Coquetel Molotov: a cross around the player turns to lava.
  void _molotov(EnemyFighter enemy, BattleState battle) {
    enemy.pose = throwPose;
    final center = battle.player.pos;
    final cross = [
      for (final offset in const [
        GridPos(0, 0),
        GridPos(1, 0),
        GridPos(-1, 0),
        GridPos(0, 1),
        GridPos(0, -1),
      ])
        if (center + offset case final cell
            when cell.inBounds && battle.ownerAt(cell) == Team.player)
          cell,
    ];
    battle.warn(cross, molotovWarn, TelegraphKind.damage, enemy);
    battle.schedule(
      enemy,
      [center],
      molotovWarn,
      () {
        for (final cell in cross) {
          battle.strike(cell, molotovDamage, Team.player, Element.fire);
          if (battle.panelAt(cell).walkable) {
            battle.setPanel(cell, PanelState.lava);
          }
        }
      },
      lob: Lob.molotov,
      telegraph: false,
    );
  }
}

/// ARGOS: the base's security AI, two panels by two; it never moves. Every
/// [attackEvery] it runs the next step of a 4-step cycle:
/// - Grade Laser: a pattern of the player's side (2 of the 3 rows, 2 of
///   the columns or a checkerboard), always leaving panels free;
/// - Bloqueio: takes the player's front column for [lockTicks], pushing
///   the player back;
/// - Torres: [turrets] Torres de Defesa on free panels of its side, at most
///   [maxTurrets] standing;
/// - its core opens for [openTicks] ([EnemyFighter.shieldDown]): Energia
///   hurts it [argosOpenEnergyMultiplier]x.
/// Below [alertAt] of its HP (Protocolo de Contenção) a second grid follows
/// the first and the lock takes two columns.
class ArgosBehavior extends EnemyBehavior {
  const ArgosBehavior();

  static const attackEvery = 3 * ticksPerSecond;
  static const laserWarn = ticksPerSecond;
  static const laserDamage = 20;

  /// Ticks between the end of the first grid and the second one's warning.
  static const laserGap = 10;
  static const lockWarn = ticksPerSecond;
  static const lockTicks = 6 * ticksPerSecond;
  static const turrets = 2;
  static const maxTurrets = 4;
  static const openTicks = 2 * ticksPerSecond;
  static const alertAt = 0.4;

  // Frames of its strip, kept in [EnemyFighter.pose]; the alert ones (Protocolo
  // de Contenção) follow at +[_alert].
  static const closedPose = 0;
  static const chargingPose = 1;
  static const openPose = 2;
  static const _alert = 3;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = attackEvery;

  @override
  int? attackCycle(EnemyFighter enemy) => attackEvery;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage == 0 && enemy.hp < enemy.maxHp * alertAt) enemy.stage = 1;
    final alert = enemy.stage == 1 ? _alert : 0;
    enemy.pose =
        (enemy.shieldDown > 0
            ? openPose
            : enemy.attacking
            ? chargingPose
            : closedPose) +
        alert;
    if (enemy.shieldDown > 0 || enemy.attacking || enemy.timer-- > 0) return;
    enemy.timer = attackEvery;
    switch (enemy.attackTimer++ % 4) {
      case 0:
        _laser(enemy, battle, again: enemy.stage == 1);
      case 1:
        _lock(enemy, battle);
      case 2:
        _turrets(enemy, battle);
      case _:
        enemy
          ..shieldDown = openTicks
          ..pose = openPose + alert;
    }
  }

  /// One random pattern of the player's side; [again] chains a second one.
  void _laser(EnemyFighter enemy, BattleState battle, {required bool again}) {
    final side = _side(battle, Team.player);
    final columns = {for (final c in side) c.x}.toList()
      ..shuffle(battle.random);
    final spared = battle.random.nextInt(gridRows);
    final parity = battle.random.nextInt(2);
    final cells = switch (battle.random.nextInt(3)) {
      0 => [
        for (final c in side)
          if (c.y != spared) c,
      ],
      1 => [
        for (final c in side)
          if (c.x != columns.first) c,
      ],
      _ => [
        for (final c in side)
          if ((c.x + c.y) % 2 == parity) c,
      ],
    };
    battle.schedule(enemy, cells, laserWarn, () {
      for (final cell in cells) {
        battle.strike(cell, laserDamage, Team.player, Element.elec);
      }
      if (again) {
        battle.schedule(
          enemy,
          const [],
          laserGap,
          () => _laser(enemy, battle, again: false),
          telegraph: false,
        );
      }
    });
  }

  /// Bloqueio: the front column of the player's side (two in alert, always
  /// leaving one); whoever stands there is pushed back.
  void _lock(EnemyFighter enemy, BattleState battle) {
    final columns = {for (final c in _side(battle, Team.player)) c.x}.toList()
      ..sort((a, b) => b.compareTo(a));
    if (columns.length < 2) return;
    final taken = columns.take(enemy.stage == 1 ? 2 : 1).toList();
    final cells = [for (final x in taken) ..._column(x)];
    battle.schedule(enemy, cells, lockWarn, kind: TelegraphKind.terrain, () {
      // Pushed back across panels still theirs, then the columns go.
      final back = taken.last - 1;
      for (final unit in List.of(battle.units)) {
        if (unit.team != Team.player || unit.pos.x <= back) continue;
        battle.displace(unit, -1, 0, unit.pos.x - back, force: true);
      }
      for (final x in taken) {
        battle.setColumnOwner(x, Team.enemy, lockTicks);
      }
    });
  }

  void _turrets(EnemyFighter enemy, BattleState battle) {
    final standing = battle.enemies
        .where((e) => e.def == Enemies.argosTurret && !e.isDead)
        .length;
    final free = _freeEnemyPanels(battle)..shuffle(battle.random);
    for (final spot in free.take(min(turrets, maxTurrets - standing))) {
      SentryBehavior.emerge(battle.summon(Enemies.argosTurret, spot));
    }
    enemy.attackPose = attackPoseTicks;
  }
}

/// Sumo-Sacerdote Xul: another boss of the second mission. Blinks to a
/// free panel of his side every [blinkTicks] and cycles three spells every
/// [attackEvery]:
/// - Ritual das Runas: [runeCount] runes light up on the player's side
///   ([BattleState.runes]); stepping on one puts it out. After
///   [ritualTicks] each rune still lit hurts the whole side for
///   [runeDamage]. Then he is exhausted, taking double damage for
///   [exhaustTicks];
/// - Transmutação: [transmuteCells] panels of the player's side turn to ice
///   or grass;
/// - Troca de Lugar: the player is moved to another panel of their side.
/// Below half HP (Ascensão) the ritual lights one more rune, and one of
/// them moves every [runeMoveTicks].
class HighPriestBehavior extends EnemyBehavior {
  const HighPriestBehavior();

  static const blinkTicks = 4 * ticksPerSecond;
  static const attackEvery = 105;
  static const runeCount = 3;
  static const ritualTicks = 4 * ticksPerSecond;

  /// The side lights up red this long before the runes go off.
  static const ritualWarn = ticksPerSecond;
  static const runeDamage = 20;
  static const runeMoveTicks = ticksPerSecond;
  static const exhaustTicks = 2 * ticksPerSecond;
  static const transmuteCells = 3;
  static const spellWarn = ticksPerSecond;

  // Frames of his strip, kept in [EnemyFighter.pose].
  static const idlePose = 0;
  static const castPose = 1;
  static const blinkPose = 2;
  static const exhaustedPose = 3;

  /// The blink pose shows this long after each blink.
  static const _blinkShow = 6;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy
    ..timer = attackEvery
    ..moveTimer = blinkTicks - _blinkShow;

  @override
  int? attackCycle(EnemyFighter enemy) => attackEvery;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.stage == 0 && enemy.hp < enemy.maxHp / 2) enemy.stage = 1;
    if (enemy.exposedTicks > 0) {
      enemy.pose = exhaustedPose;
      return;
    }
    if (enemy.countdown > 0) {
      enemy.pose = castPose;
      _ritualTick(enemy, battle);
      return;
    }
    enemy.pose = enemy.attacking
        ? castPose
        : enemy.moveTimer > blinkTicks - _blinkShow &&
              enemy.moveTimer <= blinkTicks
        ? blinkPose
        : idlePose;
    if (!enemy.attacking && enemy.moveTimer-- <= 0) {
      enemy.moveTimer = blinkTicks;
      final free = _freeEnemyPanels(battle);
      if (free.isNotEmpty) {
        enemy.pos = free[battle.random.nextInt(free.length)];
      }
    }
    if (enemy.attacking || enemy.timer-- > 0) return;
    enemy.timer = attackEvery;
    switch (enemy.attackTimer++ % 3) {
      case 0:
        _ritual(enemy, battle);
      case 1:
        _transmute(enemy, battle);
      case _:
        _swap(enemy, battle);
    }
  }

  void _ritual(EnemyFighter enemy, BattleState battle) {
    final spots = [
      for (final cell in _side(battle, Team.player))
        if (cell != battle.player.pos && battle.panelAt(cell).walkable) cell,
    ]..shuffle(battle.random);
    battle.runes.addAll(spots.take(runeCount + enemy.stage));
    enemy
      ..countdown = ritualTicks
      ..pose = castPose;
  }

  void _ritualTick(EnemyFighter enemy, BattleState battle) {
    final left = --enemy.countdown;
    if (left == ritualWarn && battle.runes.isNotEmpty) {
      battle.warn(_side(battle, Team.player), ritualWarn);
    }
    if (enemy.stage == 1 && left % runeMoveTicks == 0) _moveRune(battle);
    if (left > 0) return;
    final lit = battle.runes.length;
    battle.runes.clear();
    if (lit > 0) {
      for (final cell in _side(battle, Team.player)) {
        battle.strike(cell, runeDamage * lit, Team.player, enemy.element);
      }
    }
    enemy.exposedTicks = exhaustTicks;
  }

  /// One rune steps to a panel next to it, of the player's side and free of
  /// runes.
  void _moveRune(BattleState battle) {
    if (battle.runes.isEmpty) return;
    final rune = battle.runes.elementAt(
      battle.random.nextInt(battle.runes.length),
    );
    final steps = [
      for (final step in const [
        GridPos(1, 0),
        GridPos(-1, 0),
        GridPos(0, 1),
        GridPos(0, -1),
      ])
        if (rune + step case final to
            when to.inBounds &&
                battle.ownerAt(to) == Team.player &&
                battle.panelAt(to).walkable &&
                to != battle.player.pos &&
                !battle.runes.contains(to))
          to,
    ];
    if (steps.isEmpty) return;
    battle.runes
      ..remove(rune)
      ..add(steps[battle.random.nextInt(steps.length)]);
  }

  void _transmute(EnemyFighter enemy, BattleState battle) {
    final cells = [
      for (final cell in _side(battle, Team.player))
        if (battle.panelAt(cell).walkable) cell,
    ]..shuffle(battle.random);
    final picked = cells.take(transmuteCells).toList();
    battle.schedule(enemy, picked, spellWarn, kind: TelegraphKind.terrain, () {
      for (final cell in picked) {
        if (!battle.panelAt(cell).walkable) continue;
        battle.setPanel(
          cell,
          battle.random.nextBool() ? PanelState.ice : PanelState.grass,
        );
      }
    });
  }

  /// Troca de Lugar: the player lands on the warned panel, if still free.
  void _swap(EnemyFighter enemy, BattleState battle) {
    final free = [
      for (final cell in _side(battle, Team.player))
        if (cell != battle.player.pos &&
            battle.panelAt(cell).walkable &&
            battle.unitAt(cell) == null)
          cell,
    ];
    if (free.isEmpty) return;
    final to = free[battle.random.nextInt(free.length)];
    battle.schedule(enemy, [to], spellWarn, kind: TelegraphKind.terrain, () {
      if (battle.ownerAt(to) == Team.player &&
          battle.panelAt(to).walkable &&
          battle.unitAt(to) == null) {
        battle.player.pos = to;
      }
    });
  }
}

/// Serpente Ancestral: another boss of the second mission. A head with
/// [segments] segments ([EnemyFighter.body]) that follow it panel by
/// panel on its side; they take shots for it, and each one broken hurts
/// the head for [segmentLoss]. Cycles three attacks every [attackEvery]:
/// - Mergulho: dives (it can't be hit), bursts out under the player's
///   panel for [diveDamage] and comes back up exposed (double damage) for
///   [exposeTicks];
/// - Sopro de Areia: smoke on [sandCells] panels of the player's side,
///   which can't use cards from there;
/// - Investida: a beam down the head's row.
/// Below [furyAt] of its HP it moves faster and dives twice.
class SerpentBehavior extends EnemyBehavior {
  const SerpentBehavior();

  static const segments = 4;
  static const moveTicks = 30;
  static const furyMoveTicks = 20;
  static const attackEvery = 3 * ticksPerSecond;
  static const segmentLoss = 15;
  static const diveWarn = 45;
  static const diveDamage = 25;
  static const exposeTicks = 45;

  /// Ticks between the two dives in fury.
  static const diveGap = 15;
  static const sandCells = 3;
  static const sandTicks = 5 * ticksPerSecond;
  static const beamWarn = ticksPerSecond;
  static const beamDamage = 20;
  static const furyAt = 0.4;

  // Frames of the head's strip, kept in [EnemyFighter.pose].
  static const idlePose = 0;
  static const attackPose = 1;
  static const exposedPose = 2;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = attackEvery;

  @override
  int? attackCycle(EnemyFighter enemy) => attackEvery;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.home == null) _grow(enemy, battle);
    _shed(enemy, battle);
    if (enemy.stage == 0 && enemy.hp < enemy.maxHp * furyAt) enemy.stage = 1;
    enemy.pose = enemy.exposedTicks > 0
        ? exposedPose
        : enemy.attacking
        ? attackPose
        : idlePose;
    if (enemy.hidden || enemy.attacking) return;
    if (enemy.moveTimer-- <= 0) {
      enemy.moveTimer = enemy.stage == 1 ? furyMoveTicks : moveTicks;
      _slither(enemy, battle);
    }
    if (enemy.timer-- > 0) return;
    enemy.timer = attackEvery;
    switch (enemy.attackTimer++ % 3) {
      case 0:
        _dive(enemy, battle, again: enemy.stage == 1);
      case 1:
        _sand(enemy, battle);
      case _:
        _beam(enemy, battle);
    }
  }

  /// The body, laid behind the head on free panels of its side.
  void _grow(EnemyFighter enemy, BattleState battle) {
    enemy.home = enemy.pos;
    var last = enemy.pos;
    for (var i = 0; i < segments; i++) {
      final spot = _nextTo(battle, last, back: true);
      if (spot == null) break;
      final segment = battle.summon(
        i == segments - 1 ? Enemies.serpentTail : Enemies.serpentBody,
        spot,
      );
      enemy.body.add(segment);
      last = spot;
    }
  }

  /// Broken segments leave the body and hurt the head.
  void _shed(EnemyFighter enemy, BattleState battle) {
    final broken = enemy.body.where((s) => s.isDead).toList();
    if (broken.isEmpty) return;
    enemy.body.removeWhere((s) => s.isDead);
    for (final _ in broken) {
      battle.damage(enemy, segmentLoss);
    }
  }

  /// A free panel of the enemy side next to [from], the back ones first
  /// when [back].
  GridPos? _nextTo(BattleState battle, GridPos from, {bool back = false}) {
    final steps = [
      if (back) const GridPos(1, 0),
      const GridPos(0, 1),
      const GridPos(0, -1),
      const GridPos(-1, 0),
      if (!back) const GridPos(1, 0),
    ];
    for (final step in steps) {
      final to = from + step;
      if (to.inBounds &&
          battle.ownerAt(to) == Team.enemy &&
          battle.panelAt(to).walkable &&
          battle.unitAt(to) == null) {
        return to;
      }
    }
    return null;
  }

  /// One step of the head, toward the player's row when it can; each
  /// segment takes the panel of the one before it.
  void _slither(EnemyFighter enemy, BattleState battle) {
    final dy = (battle.player.pos.y - enemy.pos.y).sign;
    final options = [
      for (final step in [
        if (dy != 0) GridPos(0, dy),
        ...[
          const GridPos(-1, 0),
          const GridPos(1, 0),
          const GridPos(0, 1),
          const GridPos(0, -1),
        ]..shuffle(battle.random),
      ])
        if (enemy.pos + step case final to
            when to.inBounds &&
                battle.ownerAt(to) == Team.enemy &&
                battle.panelAt(to).walkable &&
                battle.unitAt(to) == null)
          to,
    ];
    if (options.isEmpty) return;
    var trail = enemy.pos;
    enemy.pos = options.first;
    for (final segment in enemy.body) {
      final was = segment.pos;
      segment.pos = trail;
      trail = was;
    }
  }

  void _setHidden(EnemyFighter enemy, bool hidden) {
    enemy.hidden = hidden;
    for (final segment in enemy.body) {
      segment.hidden = hidden;
    }
  }

  /// Mergulho: down, out under the player's panel, back up exposed.
  void _dive(EnemyFighter enemy, BattleState battle, {required bool again}) {
    final aim = battle.player.pos;
    _setHidden(enemy, true);
    battle.schedule(enemy, [aim], diveWarn, () {
      battle.strike(aim, diveDamage, Team.player, enemy.element);
      if (again) {
        battle.schedule(
          enemy,
          const [],
          diveGap,
          () => _dive(enemy, battle, again: false),
          telegraph: false,
        );
        return;
      }
      _setHidden(enemy, false);
      enemy.exposedTicks = exposeTicks;
    });
  }

  void _sand(EnemyFighter enemy, BattleState battle) {
    final others = _side(battle, Team.player)
      ..remove(battle.player.pos)
      ..shuffle(battle.random);
    final cells = [battle.player.pos, ...others.take(sandCells - 1)];
    battle.schedule(enemy, cells, spellWarn, kind: TelegraphKind.terrain, () {
      for (final cell in cells) {
        battle.panelAt(cell).smokeTicks = sandTicks;
      }
    });
  }

  static const spellWarn = ticksPerSecond;

  void _beam(EnemyFighter enemy, BattleState battle) {
    final cells = [
      for (final cell in _rowAhead(enemy))
        if (battle.ownerAt(cell) == Team.player) cell,
    ];
    battle.schedule(enemy, cells, beamWarn, () {
      for (final cell in cells) {
        battle.strike(cell, beamDamage, Team.player, Element.elec);
      }
    });
  }
}
