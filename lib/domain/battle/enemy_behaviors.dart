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
  void onInterrupted(EnemyFighter enemy, BattleState battle) =>
      enemy.stage = 0;
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

/// Capanga Atirador: wanders its side and, once ready, lines up with the
/// player to shoot down its row. It stands still from the warning until the
/// shot leaves.
class GruntGunBehavior extends EnemyBehavior {
  const GruntGunBehavior();

  static const moveTicks = 40;
  static const cycleTicks = 3 * ticksPerSecond;

  @override
  void onBattleStart(EnemyFighter enemy) => enemy.timer = cycleTicks;

  @override
  void tick(EnemyFighter enemy, BattleState battle) {
    if (enemy.timer > 0) {
      enemy.timer--;
      _wander(enemy, battle, moveTicks);
      return;
    }
    if (_seekRow(enemy, battle, moveTicks)) return;
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
class GruntMeleeBehavior extends EnemyBehavior {
  const GruntMeleeBehavior();

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
      _wander(enemy, battle, moveTicks);
      return;
    }
    if (_seekRow(enemy, battle, moveTicks)) return;
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
      [aim],
      (enemy.pos.x - spot.x).abs() * walkStepTicks + minWarnTicks,
      TelegraphKind.damage,
      enemy,
    );
  }

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
    battle.schedule(
      enemy,
      [aim],
      minWarnTicks,
      () => battle.strike(aim, damage, Team.player, enemy.element),
    );
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
/// columns and cycles three attacks: a 3-shot burst, missiles on random
/// panels of the player's side and a charge down its row. The burst and the
/// charge are only triggered lined up with the player: it moves to the
/// player's row first, and fires missiles instead if it can't get there.
/// The charge is a real move: it cracks panels, sets off mines and falls
/// into holes (which ends the charge). The charge runs
/// over obstacles, hits the player and pushes them 1 panel back (a wall,
/// unit or hole behind them adds the usual collision or fall), leaves the
/// arena on the left and comes back on the right.
class TankBehavior extends EnemyBehavior {
  const TankBehavior();

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
    var next = enemy.attackTimer % 3;
    if (next != 1 && enemy.pos.y != battle.player.pos.y) {
      if (enemy.timer > -seekLimitTicks) {
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
            () =>
                battle.strike(cell, missileDamage, Team.player, enemy.element),
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
