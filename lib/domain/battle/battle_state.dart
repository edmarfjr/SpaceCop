import 'dart:math';

import '../chips/battle_chip.dart';
import '../chips/chip_library.dart';
import '../deck/deck.dart';
import '../element.dart';
import '../grid.dart';
import '../run/relics.dart';
import 'enemies.dart';
import 'panels.dart';

/// Simulation rate. Cart timings (PICO-8 frames at 30 fps) port 1:1.
const int ticksPerSecond = 30;

/// Ticks to fill the gauge (cart: `turn_tmr` up to 300).
const int gaugeTicks = 300;
const int playerMoveCooldown = 5;

/// [playerMoveCooldown] with the Exoesqueleto Pesado: 50% slower.
const int heavyMoveCooldown = 8;

/// Percent the Implante Neural slows the gauge down.
const int neuralGaugeSlow = 25;
const int playerAttackCooldown = 10;

/// Cards drawn from the top of the deck on each refill.
const int handSize = 5;

/// Energy available per hand before any bonus.
const int baseEnergy = 4;

/// Player shots move one cell per tick; enemy shots use [EnemyDef.shotStepTicks].
const int projectileLifetime = 180;

/// Two units crashing into each other (or one into a wall).
const int collisionDamage = 10;
const int collisionStunTicks = ticksPerSecond ~/ 2;

/// A rock is heavier: collisions involving one hurt more.
const int rockCollisionDamage = 30;

/// Pushed into a hole.
const int fallDamage = 20;
const int fallStunTicks = ticksPerSecond;

/// A chain is kept by using a chip of the same family within this window.
const int chainWindowTicks = 2 * ticksPerSecond;

/// Card family against enemy type (see `BattleState._kindMultiplier`).
const double machineProjectileMultiplier = 0.5;
const double machineEnergyMultiplier = 2;
const double organicExplosiveMultiplier = 1.5;

/// Energia on ARGOS while its core is open, instead of
/// [machineEnergyMultiplier].
const double argosOpenEnergyMultiplier = 3;

/// An Etéreo hit by an Explosivo stays solid this long.
const int materializeTicks = 2 * ticksPerSecond;

/// Capacitor: energy left over that carries into the next hand, at most.
const int capacitorCarry = 2;

/// Kit de Engenharia: how much longer gear lasts.
const double engineeringKitBonus = 1.5;

/// Damage of the 2nd and 3rd chip of a chain.
const double chain2Multiplier = 1.25;
const double chain3Multiplier = 1.5;

/// Holding Use this long with a fusion pair in hand fuses them.
const int fusionChargeTicks = ticksPerSecond ~/ 2;

/// Pulled while already in the front enemy column.
const int pullStunTicks = ticksPerSecond;

const int rockHp = 40;
const int mineDamage = 40;
const int turretHp = 20;
const int turretTicks = 10 * ticksPerSecond;
const int turretShotDamage = 5;

/// How long the Escudo Refletor stands in front of the player.
const int reflectorTicks = 5 * ticksPerSecond;

/// Bobina Tesla: zaps the first enemy of its row every second.
const int teslaHp = 30;
const int teslaTicks = 8 * ticksPerSecond;
const int teslaZapDamage = 5;

/// Mira Laser: a marked unit takes this much more from each hit.
const int markBonus = 5;
const int markTicks = 5 * ticksPerSecond;

/// Damage to the Colossus's fist reaches the body multiplied by this.
const int weakPointMultiplier = 2;

/// How long the player's tossed chips fly. Shorter than the attack
/// cooldown, so a toss lands before the player can act again.
const int playerTossTicks = 9;

/// How long a lobbed ball or pickaxe flies before it lands.
const int lobFlightTicks = 18;

/// How long a unit flashes after taking damage.
const int hurtFlashTicks = 12;

/// An enemy keeps its attack pose this long after its attack lands.
const int attackPoseTicks = 8;

/// Brute shield stays down this long after a collision.
const int shieldDownTicks = 2 * ticksPerSecond;

enum BattlePhase { fighting, won, lost }

enum Status {
  /// Takes [burnDamage] every second.
  burning,

  /// The next Elec hit deals double damage and removes it.
  wet,

  /// Can't move, attack or use chips.
  stunned,

  /// Can't move.
  rooted,

  /// Takes [markBonus] more from each hit (Mira Laser).
  marked,
}

const int burnTicks = 3 * ticksPerSecond;
const int burnDamage = 3;
const int wetTicks = 5 * ticksPerSecond;
const int rootTicks = 2 * ticksPerSecond;

/// How a hit reached its target. Shields and reflectors only stop
/// [straight] projectile hits.
enum HitKind {
  /// The impact cell of a projectile.
  straight,

  /// Any other cell of a projectile's pattern (diagonals, spread).
  spread,

  /// Everything that isn't a projectile: strikes, terrain, collisions.
  area,
}

enum ObstacleKind { rock, mine, turret, reflector, tesla }

/// Red outlines warn of damage, blue ones of terrain changes.
enum TelegraphKind { damage, terrain }

/// What a [BattleEvent] reports.
enum BattleEventKind {
  /// The player used [BattleEvent.chip] (once per run of its effect).
  chipUsed,

  /// The player fused two cards into [BattleEvent.chip].
  fusion,

  /// A chain reached [BattleEvent.amount] chips (2 or 3).
  chain,

  /// An attack by [BattleEvent.unit] started warning its panels.
  telegraph,

  /// [BattleEvent.unit] fired a straight shot.
  enemyShot,

  /// A [HitFlash] appeared.
  explosion,
  slash,

  /// A hit on [BattleEvent.unit] was stopped: barrier, shield, prism or
  /// reflector.
  blocked,

  /// [BattleEvent.unit], an enemy, died.
  death,

  /// The gauge filled and a new hand was drawn.
  newHand,
  won,
  lost,
}

/// Something that happened during the last [BattleState.tick], for sounds
/// and effects. Damage dealt is in [BattleState.hits] instead.
class BattleEvent {
  const BattleEvent(this.kind, {this.chip, this.unit, this.amount = 0});

  final BattleEventKind kind;
  final ChipDef? chip;
  final Fighter? unit;
  final int amount;
}

/// A panel an enemy attack is about to hit, drawn ahead of time.
class Telegraph {
  Telegraph(this.pos, this.kind, this.ticksLeft, [this.owner]);

  final GridPos pos;
  final TelegraphKind kind;
  int ticksLeft;

  /// The attacker, so a stun can take its warnings away.
  final Fighter? owner;
}

/// A collision about to be applied. Relics can make it hurt more.
class Collision {
  Collision(this.damage, this.stunTicks);

  int damage;
  int stunTicks;
}

/// What an enemy throws at the targeted panels of a scheduled attack.
/// Purely visual: it lands on the tick the attack resolves.
enum Lob { none, ball, pickaxe, molotov }

/// An enemy attack waiting for its telegraph to run out.
class _Scheduled {
  _Scheduled(this.owner, this.ticksLeft, this.action, this.lob, this.cells)
    : flightTicks = min(ticksLeft, lobFlightTicks);

  final Fighter? owner;
  final int flightTicks;
  int ticksLeft;
  final void Function() action;
  final Lob lob;
  final List<GridPos> cells;
}

/// One [Lob] in the air, for the renderer: thrown by [from] at [to],
/// landing in [ticksLeft] of its [flightTicks].
typedef LobView = ({
  Lob lob,
  Fighter from,
  GridPos to,
  int ticksLeft,
  int flightTicks,
});

/// Input for one tick. Directions are held keys; the booleans are presses.
class PlayerInput {
  const PlayerInput({
    this.dx = 0,
    this.dy = 0,
    this.useChip = false,
    this.holdUse = false,
    this.cycleChip = false,
  });

  static const none = PlayerInput();

  final int dx;
  final int dy;
  final bool useChip;

  /// Use is still held down (fusion charge).
  final bool holdUse;
  final bool cycleChip;

  /// Any move or card input; ends [BattleState.waitingForPlayer].
  bool get acts => dx != 0 || dy != 0 || useChip || holdUse || cycleChip;
}

/// Anything that stands on a panel: the player, enemies and obstacles.
class Fighter {
  Fighter({
    required this.team,
    required this.pos,
    required this.hp,
    required this.maxHp,
    this.element = Element.neutral,
  });

  /// Null for neutral units (rocks), which block both sides.
  final Team? team;
  Element element;
  GridPos pos;
  int hp;
  final int maxHp;

  /// Counts down after taking damage; the renderer uses it to flash.
  int hurtTicks = 0;

  /// Ticks left on each active status.
  final Map<Status, int> statuses = {};

  bool get isDead => hp <= 0;

  /// Whether pushes and pulls can move this unit.
  bool get pushable => true;

  /// Underground or otherwise off the field: can't be hit or blocked.
  bool get hidden => false;

  /// Whether this unit stands on [cell]. Multi-cell units override it.
  bool occupies(GridPos cell) => cell == pos;

  bool has(Status status) => statuses.containsKey(status);

  /// Re-applying keeps the longer of the two durations.
  void applyStatus(Status status, int ticks) {
    statuses[status] = max(statuses[status] ?? 0, ticks);
  }

  void takeDamage(int amount) {
    hp = max(0, hp - amount);
    hurtTicks = hurtFlashTicks;
  }
}

class PlayerFighter extends Fighter {
  PlayerFighter({required super.pos, required super.hp, required super.maxHp})
    : super(team: Team.player);

  int moveCooldown = 0;
  int attackCooldown = 0;

  /// Pose of the last chip used, drawn while [attackCooldown] runs.
  ChipPose pose = ChipPose.shoot;

  /// While positive, the next damage is cancelled.
  int barrierTicks = 0;
}

enum EnemyState { idle, moving, attacking }

class EnemyFighter extends Fighter {
  EnemyFighter(this.def, GridPos pos)
    : super(
        team: Team.enemy,
        pos: pos,
        hp: def.hp,
        maxHp: def.hp,
        element: def.element,
      );

  final EnemyDef def;

  /// Set while the behavior winds up or fires an attack by itself (Canhão Móvel,
  /// Canhão Fixo). Attacks scheduled through [BattleState.schedule] count
  /// on their own: see [attacking].
  EnemyState state = EnemyState.idle;
  int moveTimer = 0;
  int attackTimer = 0;

  /// Free-form AI state for [EnemyDef.behavior]: a phase counter and a
  /// second timer.
  int stage = 0;
  int timer = 0;

  /// Attacks this unit scheduled that haven't landed yet, and ticks left of
  /// the attack pose once the last one lands.
  int pendingAttacks = 0;
  int attackPose = 0;

  /// Winding up or executing an attack: it can't move meanwhile, and is
  /// drawn with its attack frame.
  bool get attacking =>
      state == EnemyState.attacking || pendingAttacks > 0 || attackPose > 0;

  @override
  bool hidden = false;
  bool invulnerable = false;

  /// How far into the ground the unit is drawn, 0 (standing) to 1, while it
  /// digs in or climbs out. Visual only: it can still be hit.
  double buried = 0;
  int shieldDown = 0;

  /// Etéreo: ticks left solid after an Explosivo hit.
  int materialTicks = 0;

  /// Dug into the floor (ET Emboscador): only Explosivo hurts it, and
  /// shots fly over it.
  bool burrowed = false;

  /// Ticks left taking double damage (Rei da Tribo's overheated staff).
  int exposedTicks = 0;

  /// Frame of an enemy drawn by pose (see `SpriteFiles.poseStrips`), set by
  /// its behavior.
  int pose = 0;

  /// Ticks until the next summon, 0 while none is due (the Coronel's
  /// Guarda-costas).
  int summonTimer = 0;

  /// A countdown the behavior runs on its own, 0 when idle (the
  /// Sumo-Sacerdote's Ritual das Runas).
  int countdown = 0;

  /// Segments that follow this unit, head first (Serpente Ancestral).
  final List<EnemyFighter> body = [];

  /// Etéreo out of phase: Projétil and Corpo-a-corpo pass through. It is
  /// solid while it attacks and for [materialTicks].
  bool get phased =>
      def.kind == EnemyKind.ethereal && materialTicks == 0 && !attacking;

  /// Body this unit is a weak point of (the Colossus's fist).
  EnemyFighter? linkedTo;

  /// Mirrored twin (Dupla Prisma).
  EnemyFighter? partner;

  /// Panel to go back to after an attack away from it, and the panel the
  /// attack aims at, picked when it is triggered (Capanga Corpo-a-Corpo).
  GridPos? home;
  GridPos? aim;

  /// Whether to draw the attack frame: only as an attack lands, never
  /// while it winds up.
  bool get attackFrame => attackPose > 0;

  @override
  bool get pushable => def.pushable;

  Iterable<GridPos> get cells => def.footprint.map((o) => pos + o);

  @override
  bool occupies(GridPos cell) => cells.contains(cell);
}

/// Rock or turret placed by a chip. Mines live on [Panel.mine] instead,
/// since nothing stands on them.
class Obstacle extends Fighter {
  Obstacle(
    this.kind, {
    required super.pos,
    required super.hp,
    super.team,
    this.ticksLeft = 0,
  }) : lifetime = ticksLeft,
       super(maxHp: hp);

  final ObstacleKind kind;

  /// Removed when this reaches 0; 0 from the start means it never expires.
  int ticksLeft;

  /// [ticksLeft] it started with, for the life bar.
  final int lifetime;
  int fireTimer = ticksPerSecond;
}

class Projectile {
  Projectile({
    required this.team,
    required this.pos,
    required this.dir,
    required this.stepTicks,
    required this.damage,
    required this.pattern,
    this.element = Element.neutral,
    this.family,
    this.onHit,
    this.status,
  }) : stepTimer = stepTicks;

  final Team team;
  GridPos pos;

  /// +1 travels toward the enemy side, -1 toward the player side.
  final int dir;
  final int stepTicks;
  final int damage;
  final List<GridPos> pattern;
  final Element element;

  /// Family of the card that fired it; null for enemy and object shots.
  final ChipFamily? family;

  /// Extra effect on the unit at the impact cell (push, pull, crack).
  final ChipEffect? onHit;

  /// Applied to everything hit (third chip of a chain).
  final Status? status;
  int stepTimer;
  int ttl = projectileLifetime;
  bool spent = false;
}

/// How a [HitFlash] is drawn.
enum FlashKind {
  explosion,

  /// A vertical sword slash centered on [HitFlash.pos], 3 rows tall.
  slash,
}

/// A cell that was just hit. Purely visual.
class HitFlash {
  HitFlash(this.pos, [this.kind = FlashKind.explosion]);

  /// Long enough for the 4-frame explosion.
  static const int lifetime = 12;

  final GridPos pos;
  final FlashKind kind;
  int ticksLeft = lifetime;
}

/// The whole battle as a deterministic, Flame-free simulation.
///
/// Call [tick] at [ticksPerSecond]. Rendering and input live in the Flame
/// layer, which only reads this state and feeds [PlayerInput].
class BattleState {
  BattleState({
    required int playerHp,
    required int playerMaxHp,
    required Iterable<ChipCard> deckCards,
    required Encounter encounter,
    Random? random,
    this.relics = const [],
    int energyBaseBonus = 0,
    int openingStunTicks = 0,
    this.pauseOnNewHand = false,
  }) : energyMax = baseEnergy + energyBaseBonus,
       player = PlayerFighter(
         pos: const GridPos(1, 1),
         hp: playerHp,
         maxHp: playerMaxHp,
       ),
       random = random ?? Random(),
       deck = Deck(deckCards, random: random) {
    for (final spawn in encounter.spawns) {
      final enemy = EnemyFighter(spawn.def, spawn.pos);
      spawn.def.behavior.onBattleStart(enemy);
      if (openingStunTicks > 0) {
        enemy.applyStatus(Status.stunned, openingStunTicks);
      }
      enemies.add(enemy);
    }
    final prisms = enemies.where((e) => e.def.prism).toList();
    if (prisms.length == 2) {
      prisms[0].partner = prisms[1];
      prisms[1].partner = prisms[0];
    }
    for (final relic in relics) {
      relic.onBattleStart?.call(this);
    }
  }

  /// The run's relics; their hooks are called throughout the battle.
  final List<RelicDef> relics;

  bool hasRelic(RelicDef relic) => relics.contains(relic);

  final PlayerFighter player;
  final List<EnemyFighter> enemies = [];
  final List<Obstacle> obstacles = [];

  /// Lit runes on the player's side (Sumo-Sacerdote): stepping on one puts
  /// it out.
  final Set<GridPos> runes = {};
  final List<Projectile> projectiles = [];
  final List<HitFlash> flashes = [];

  /// Damage dealt during the last [tick], for the renderer's numbers and
  /// the player's hurt feedback.
  final List<({Fighter target, int amount})> hits = [];

  /// Everything else that happened during the last [tick].
  final List<BattleEvent> events = [];
  final List<Telegraph> telegraphs = [];
  final List<_Scheduled> _scheduled = [];
  final Random random;

  /// How long holes last. The Colossus stretches it in its second phase.
  int holeReturnTicks = holeTicks;

  /// `panels[x][y]`.
  final List<List<Panel>> panels = [
    for (var x = 0; x < gridColumns; x++)
      [for (var y = 0; y < gridRows; y++) Panel(GridPos(x, y).homeSide)],
  ];

  /// Ticks simulated so far. Per-second effects fire on multiples of
  /// [ticksPerSecond].
  int ticks = 0;

  /// Chips usable in real time are [Deck.hand]; used ones go to the discard.
  final Deck deck;

  BattlePhase phase = BattlePhase.fighting;

  /// Starts full, like the cart (`turn_tmr=300`), so the first hand is drawn
  /// on the first tick.
  int gauge = gaugeTicks;
  int selectedIndex = 0;

  /// Bonus added to the next projectile (cart: `dmg_bonus`).
  int damageBonus = 0;

  /// Energy restored on every refill. Grows with [EnergyMaxEffect].
  int energyMax;

  /// Energy left to spend in the current hand.
  int energy = 0;

  /// Temporary Energy granted by [EnergyBurstEffect]; reset on every refill.
  int energyBonus = 0;

  /// Family of the running chain and how many chips it has (0 = none).
  ChipFamily? chainFamily;
  int chainCount = 0;
  int _chainTicks = 0;

  /// Status the chip being used applies (3rd chip of a chain).
  Status? _chainStatus;

  /// Card being charged into a fusion and for how long.
  ChipCard? chargingCard;
  int _chargeTicks = 0;

  /// The current gauge fills 50% faster (Gatilho de Corrente).
  bool gaugeBoosted = false;

  /// [gaugeBoosted] for the gauge after the next refill.
  bool boostNextGauge = false;

  /// Extra gauge speed, in percent, for the rest of the battle (Gerador de
  /// Energia).
  int gaugeSpeedBonus = 0;

  /// The next chip counts twice in the chain (Sobrecarga).
  bool chainSurge = false;

  /// The next chip runs twice (Overclock).
  bool overclocked = false;

  /// Carregador Estendido already refunded a Projétil in this hand.
  bool projectileRefunded = false;

  /// Mochila Tática already saved a single-use card in this battle.
  bool packUsed = false;

  /// The Armadura already stopped this battle's first hit.
  bool armorUsed = false;

  /// Hundredths of a gauge tick not filled yet: each tick adds 100 plus
  /// the speed bonuses.
  int _gaugeProgress = 0;

  /// Pasta Ordenada: the HUD offers to send one of [peekCards] to the
  /// bottom of the deck. The battle doesn't tick until the player picks one
  /// or keeps the order ([dismissPeek]).
  bool peekOpen = false;

  List<ChipCard> get peekCards => peekOpen ? deck.peek(2) : const [];

  void sendToBottom(ChipCard card) {
    if (!peekCards.contains(card)) return;
    deck.sendToBottom(card);
    peekOpen = false;
  }

  void dismissPeek() => peekOpen = false;

  bool get gaugeFull => gauge >= gaugeTicks;

  /// Every new hand (the start of each turn) freezes the battle until the
  /// player moves or uses a card, to give time to plan.
  final bool pauseOnNewHand;

  /// Frozen by [pauseOnNewHand].
  bool waitingForPlayer = false;
  bool get isOver => phase == BattlePhase.won || phase == BattlePhase.lost;

  List<ChipCard> get hand => deck.hand;

  ChipCard? get selectedChip =>
      hand.isEmpty ? null : hand[selectedIndex.clamp(0, hand.length - 1)];

  void selectChip(int index) {
    if (index >= 0 && index < hand.length) selectedIndex = index;
  }

  bool canAfford(ChipCard card) => card.def.cost <= energy;

  // ---------------------------------------------------------------- panels

  Panel panelAt(GridPos pos) => panels[pos.x][pos.y];

  Team ownerAt(GridPos pos) => panelAt(pos).owner;

  /// Changes a panel; [ticks] defaults to [Panel.defaultTicks].
  void setPanel(GridPos pos, PanelState state, [int? ticks]) {
    panelAt(pos)
      ..state = state
      ..timer =
          ticks ??
          (state == PanelState.hole
              ? holeReturnTicks
              : Panel.defaultTicks(state));
  }

  /// Gives column [x] to [team] for [ticks] (0 = for good).
  void setColumnOwner(int x, Team team, [int ticks = 0]) {
    for (var y = 0; y < gridRows; y++) {
      panels[x][y]
        ..owner = team
        ..ownerTimer = team == GridPos(x, y).homeSide ? 0 : ticks;
    }
  }

  // ----------------------------------------------------------------- units

  Iterable<Fighter> get units => [player, ...enemies, ...obstacles];

  /// Living, visible unit standing on [pos], of any team.
  Fighter? unitAt(GridPos pos) {
    for (final unit in units) {
      if (!unit.isDead && !unit.hidden && unit.occupies(pos)) return unit;
    }
    return null;
  }

  /// Whether [unit] may step onto [pos]: in bounds, on its own side, not a
  /// hole and not occupied, for every cell of its footprint. Neutral units
  /// ignore sides.
  bool canEnter(Fighter unit, GridPos pos) {
    final footprint = unit is EnemyFighter ? unit.def.footprint : null;
    final cells = footprint?.map((offset) => pos + offset) ?? [pos];
    // A wide unit stepping sideways may overlap its own current cells.
    final wide = (footprint?.length ?? 1) > 1;
    return cells.every(
      (cell) =>
          cell.inBounds &&
          (unit.team == null || ownerAt(cell) == unit.team) &&
          panelAt(cell).walkable &&
          switch (unitAt(cell)) {
            null => true,
            final other => wide && other == unit,
          },
    );
  }

  /// Every full gauge: discard the whole hand, draw [handSize] chips (one
  /// more with the Implante Neural) from the top of the deck and restore
  /// energy.
  void _refillHand() {
    if (!gaugeFull) return;
    deck
      ..discardHand()
      ..draw(hasRelic(Relics.neuralImplant) ? handSize + 1 : handSize);
    final carried = hasRelic(Relics.capacitor)
        ? min(energy, capacitorCarry)
        : 0;
    energy = energyMax + carried;
    energyBonus = 0;
    projectileRefunded = false;
    selectedIndex = 0;
    gauge = 0;
    waitingForPlayer = pauseOnNewHand;
    events.add(const BattleEvent(BattleEventKind.newHand));
    gaugeBoosted = boostNextGauge;
    boostNextGauge = false;
    for (final relic in relics) {
      relic.onHandRefill?.call(this);
    }
  }

  // ------------------------------------------------------------------ tick

  void tick([PlayerInput input = PlayerInput.none]) {
    hits.clear();
    events.clear();
    if (phase != BattlePhase.fighting) return;
    if (waitingForPlayer) {
      if (!input.acts) return;
      waitingForPlayer = false;
    }

    ticks++;
    _gaugeProgress +=
        100 +
        gaugeSpeedBonus +
        (gaugeBoosted ? 50 : 0) -
        (hasRelic(Relics.neuralImplant) ? neuralGaugeSlow : 0);
    for (; _gaugeProgress >= 100; _gaugeProgress -= 100) {
      if (!gaugeFull) gauge++;
    }
    if (_chainTicks > 0 && --_chainTicks == 0) chainCount = 0;
    _refillHand();
    _updatePlayer(input);
    runes.remove(player.pos);
    _updateEnemies();
    _updateObstacles();
    _updateProjectiles();
    _updateTelegraphs();
    _updatePanels();

    for (final unit in units) {
      if (unit.hurtTicks > 0) unit.hurtTicks--;
      _updateStatuses(unit);
    }
    for (final flash in flashes) {
      // Not counted down yet: added this tick.
      if (flash.ticksLeft == HitFlash.lifetime) {
        events.add(
          BattleEvent(
            flash.kind == FlashKind.slash
                ? BattleEventKind.slash
                : BattleEventKind.explosion,
          ),
        );
      }
      flash.ticksLeft--;
    }
    flashes.removeWhere((f) => f.ticksLeft <= 0);
    for (final enemy in enemies) {
      if (enemy.isDead) {
        events.add(BattleEvent(BattleEventKind.death, unit: enemy));
      }
    }
    enemies.removeWhere((e) => e.isDead);
    obstacles.removeWhere((o) => o.isDead);

    if (player.isDead) {
      phase = BattlePhase.lost;
      events.add(const BattleEvent(BattleEventKind.lost));
    } else if (enemies.every((e) => e.def.summon)) {
      enemies.clear();
      phase = BattlePhase.won;
      events.add(const BattleEvent(BattleEventKind.won));
    }
  }

  void _updateTelegraphs() {
    for (final telegraph in telegraphs) {
      telegraph.ticksLeft--;
    }
    telegraphs.removeWhere((t) => t.ticksLeft <= 0);
    for (final action in List.of(_scheduled)) {
      if (--action.ticksLeft > 0) continue;
      _scheduled.remove(action);
      final owner = action.owner;
      if (owner is EnemyFighter) {
        owner.pendingAttacks--;
        owner.attackPose = attackPoseTicks;
      }
      // Attacks from inside a smoke cloud fizzle.
      if (owner != null && (owner.isDead || inSmoke(owner))) continue;
      action.action();
    }
  }

  /// Ticks until the next attack [enemy] scheduled lands, or null if it has
  /// none pending.
  int? ticksToAttack(EnemyFighter enemy) {
    int? next;
    for (final s in _scheduled) {
      if (s.owner == enemy && (next == null || s.ticksLeft < next)) {
        next = s.ticksLeft;
      }
    }
    return next;
  }

  /// Outlines [cells] for [ticks] without doing anything else.
  ///
  /// The [owner]'s warnings go away if it is stunned (see [_interrupt]).
  void warn(
    Iterable<GridPos> cells,
    int ticks, [
    TelegraphKind kind = TelegraphKind.damage,
    Fighter? owner,
  ]) {
    // Attacks that keep refreshing their warning (aimed beams) report it
    // only once.
    if (kind == TelegraphKind.damage &&
        (owner == null ||
            !telegraphs.any(
              (t) => t.owner == owner && t.kind == TelegraphKind.damage,
            ))) {
      events.add(BattleEvent(BattleEventKind.telegraph, unit: owner));
    }
    for (final cell in cells) {
      if (cell.inBounds) telegraphs.add(Telegraph(cell, kind, ticks, owner));
    }
  }

  /// Telegraphs [cells] and runs [action] when the warning runs out, unless
  /// [owner] died in the meantime.
  ///
  /// With a [lob], the owner throws it at each cell so it lands as the
  /// attack resolves. The player's throws aren't telegraphed ([telegraph]).
  void schedule(
    Fighter? owner,
    Iterable<GridPos> cells,
    int ticks,
    void Function() action, {
    TelegraphKind kind = TelegraphKind.damage,
    Lob lob = Lob.none,
    bool telegraph = true,
  }) {
    if (telegraph) warn(cells, ticks, kind, owner);
    _scheduled.add(_Scheduled(owner, ticks, action, lob, cells.toList()));
    if (owner is EnemyFighter) owner.pendingAttacks++;
  }

  /// The player lobs a ball at [cell]; [land] runs when it gets there.
  void _toss(GridPos cell, void Function() land) => schedule(
    player,
    [cell],
    playerTossTicks,
    land,
    lob: Lob.ball,
    telegraph: false,
  );

  /// Where a tossed attack lands: the first target in the player's row, or
  /// the far end of it.
  GridPos _tossTarget() {
    for (var x = player.pos.x + 1; x < gridColumns; x++) {
      final cell = GridPos(x, player.pos.y);
      if (_targetAt(cell, Team.enemy) != null) return cell;
    }
    return GridPos(gridColumns - 1, player.pos.y);
  }

  /// Lobs in flight: each is thrown [lobFlightTicks] before it lands (or
  /// as soon as it is scheduled, if the warning is shorter).
  Iterable<LobView> get lobs sync* {
    for (final s in _scheduled) {
      final owner = s.owner;
      if (s.lob == Lob.none || owner == null || s.ticksLeft > s.flightTicks) {
        continue;
      }
      for (final cell in s.cells) {
        yield (
          lob: s.lob,
          from: owner,
          to: cell,
          ticksLeft: s.ticksLeft,
          flightTicks: s.flightTicks,
        );
      }
    }
  }

  /// Counts every status down and drops it at zero. Burning hurts once per
  /// second, starting one second after it is applied.
  void _updateStatuses(Fighter fighter) {
    for (final status in List.of(fighter.statuses.keys)) {
      final left = fighter.statuses[status]! - 1;
      if (status == Status.burning && left % ticksPerSecond == 0) {
        damage(fighter, burnDamage);
      }
      if (left <= 0) {
        fighter.statuses.remove(status);
      } else {
        fighter.statuses[status] = left;
      }
    }
  }

  /// Panel and ownership timers, plus grass healing and lava burning once
  /// per second.
  void _updatePanels() {
    for (var x = 0; x < gridColumns; x++) {
      for (var y = 0; y < gridRows; y++) {
        final pos = GridPos(x, y);
        final panel = panelAt(pos);
        if (panel.smokeTicks > 0) panel.smokeTicks--;
        if (panel.ownerTimer > 0 && --panel.ownerTimer == 0) {
          panel.owner = pos.homeSide;
          final intruder = unitAt(pos);
          if (intruder != null &&
              intruder.team != null &&
              intruder.team != panel.owner) {
            displace(intruder, intruder.team == Team.player ? -1 : 1, 0, 1);
          }
        }
        final unit = unitAt(pos);
        if (panel.state == PanelState.cracked && unit != null) {
          panel.timer = crackedTicks;
        } else if (panel.timer > 0 && --panel.timer == 0) {
          panel.state = PanelState.normal;
        }
        if (unit == null || ticks % ticksPerSecond != 0) continue;
        if (panel.state == PanelState.grass) {
          unit.hp = min(unit.maxHp, unit.hp + grassHeal);
        } else if (panel.state == PanelState.lava &&
            unit.element != Element.fire) {
          damage(unit, lavaDamage);
        }
      }
    }
  }

  // ---------------------------------------------------------------- player

  void _updatePlayer(PlayerInput input) {
    if (player.barrierTicks > 0) player.barrierTicks--;
    if (player.has(Status.stunned)) {
      chargingCard = null;
      return;
    }
    if (player.attackCooldown > 0) {
      player.attackCooldown--;
      return;
    }
    // Fusion charge: the player stands still until Use is released or the
    // charge completes.
    if (chargingCard case final card?) {
      final partner = fusionPartner(card);
      if (!hand.contains(card) || partner == null) {
        chargingCard = null;
      } else if (!input.holdUse) {
        chargingCard = null;
        if (canAfford(card)) _useChip(card);
      } else if (++_chargeTicks >= fusionChargeTicks) {
        chargingCard = null;
        if (card.def.cost + partner.def.cost <= energy) {
          _fuse(card, partner);
        } else if (canAfford(card)) {
          _useChip(card);
        }
      }
      return;
    }
    if (player.moveCooldown > 0) {
      player.moveCooldown--;
    } else if ((input.dx != 0 || input.dy != 0) && !player.has(Status.rooted)) {
      _tryMovePlayer(input.dx, input.dy);
    }
    if (input.cycleChip && hand.isNotEmpty) {
      selectedIndex = (selectedIndex + 1) % hand.length;
    }
    final chip = selectedChip;
    if (!input.useChip || chip == null || inSmoke(player)) return;
    if (fusionPartner(chip) != null) {
      chargingCard = chip;
      _chargeTicks = 1; // The press itself is the first held tick.
    } else if (canAfford(chip)) {
      _useChip(chip);
    }
  }

  /// Another card in hand that fuses with [card], if any.
  ChipCard? fusionPartner(ChipCard card) {
    for (final other in hand) {
      if (other != card && Chips.fusionOf(card.def, other.def) != null) {
        return other;
      }
    }
    return null;
  }

  /// Uses both cards as their fusion, paying the energy of both.
  void _fuse(ChipCard card, ChipCard partner) {
    final fusion = Chips.fusionOf(card.def, partner.def)!;
    events.add(BattleEvent(BattleEventKind.fusion, chip: fusion));
    final twice = overclocked;
    overclocked = false;
    _activate(fusion);
    if (twice) _activate(fusion);
    energy -= card.def.cost + partner.def.cost;
    deck
      ..discard(card)
      ..discard(partner);
    selectedIndex = hand.isEmpty ? 0 : selectedIndex % hand.length;
    player.attackCooldown = playerAttackCooldown;
  }

  /// Restores [amount] of the player's HP, up to the max.
  void heal(int amount) => player.hp = min(player.maxHp, player.hp + amount);

  /// Chain bookkeeping for a chip of [family] about to be used. Returns the
  /// damage multiplier ([chain2Multiplier], [chain3Multiplier]). The 3rd
  /// chip also sets [_chainStatus] and completes the chain. After Sobrecarga
  /// ([chainSurge]) the chip counts twice. Families that don't chain leave
  /// the chain, its window and Sobrecarga untouched.
  double _advanceChain(ChipFamily family) {
    _chainStatus = null;
    if (!family.chains) return 1;
    final step = chainSurge ? 2 : 1;
    chainSurge = false;
    if (chainCount > 0 && family == chainFamily) {
      chainCount += step;
    } else {
      chainFamily = family;
      chainCount = step;
    }
    _chainTicks = chainWindowTicks;
    if (chainCount >= 2) {
      events.add(
        BattleEvent(BattleEventKind.chain, amount: min(chainCount, 3)),
      );
    }
    switch (chainCount) {
      case 2:
        return chain2Multiplier;
      case >= 3:
        _chainStatus = switch (family) {
          ChipFamily.projectile => Status.marked,
          ChipFamily.explosive => Status.burning,
          ChipFamily.energy => Status.stunned,
          _ => Status.rooted,
        };
        chainCount = 0;
        for (final relic in relics) {
          relic.onChainComplete?.call(this);
        }
        return chain3Multiplier;
      default:
        return 1;
    }
  }

  void _tryMovePlayer(int dx, int dy) {
    // One axis per step, horizontal first, like holding a d-pad.
    final step = dx != 0 ? GridPos(dx.sign, 0) : GridPos(0, dy.sign);
    if (tryMove(player, step)) {
      player.moveCooldown = hasRelic(Relics.heavyExoskeleton)
          ? heavyMoveCooldown
          : playerMoveCooldown;
    }
  }

  /// Voluntary one-cell move. Fails when rooted, mid-attack or the cell
  /// can't be entered.
  bool tryMove(Fighter unit, GridPos step) {
    final target = unit.pos + step;
    if (unit.has(Status.rooted) ||
        (unit is EnemyFighter && unit.attacking) ||
        !canEnter(unit, target)) {
      return false;
    }
    _moveUnit(unit, target, step);
    return true;
  }

  void _useChip(ChipCard card) {
    final def = card.def;
    final twice = overclocked;
    overclocked = false;
    _activate(def);
    if (twice) _activate(def);
    energy -= def.cost;
    if (def.exhaust && !(hasRelic(Relics.tacticalPack) && !packUsed)) {
      deck.exhaust(card);
    } else {
      if (def.exhaust) packUsed = true;
      deck.discard(card);
    }
    selectedIndex = hand.isEmpty ? 0 : selectedIndex % hand.length;
    player.attackCooldown = playerAttackCooldown;
    for (final relic in relics) {
      relic.onChipUsed?.call(this, def);
    }
  }

  /// Runs [def]'s effect for the player. Damage goes through terrain, chain
  /// and relic bonuses, in that order.
  void _activate(ChipDef def) {
    events.add(BattleEvent(BattleEventKind.chipUsed, chip: def));
    player.pose = def.pose;
    final chain = _advanceChain(def.family);
    var damage = boosted(player, def.damage + damageBonus, def.element);
    damage = (damage * chain).round();
    for (final relic in relics) {
      damage = relic.modifyDamage?.call(this, def, damage) ?? damage;
    }
    final status = _chainStatus;
    switch (def.effect) {
      case ProjectileEffect(:final pattern) when def.pose == ChipPose.toss:
        final shot = Projectile(
          team: Team.player,
          pos: _tossTarget(),
          dir: 1,
          stepTicks: 0,
          damage: damage,
          pattern: pattern,
          element: def.element,
          family: def.family,
          status: status,
        );
        damageBonus = 0;
        _toss(shot.pos, () => _impact(shot, Team.enemy));
      case ProjectileEffect(:final pattern):
        _fire(def, damage, pattern: pattern, status: status);
      case GrenadeEffect(
        :final distance,
        :final pattern,
        :final panel,
        :final smokeTicks,
        :final stunTicks,
        :final wetTicks,
        :final shieldTicks,
      ):
        final target = player.pos + GridPos(distance, 0);
        final shot = Projectile(
          team: Team.player,
          pos: target,
          dir: 1,
          stepTicks: 0,
          damage: damage,
          pattern: pattern,
          element: def.element,
          family: def.family,
          status: status,
        );
        damageBonus = 0;
        _toss(target, () {
          // Who is in the blast, before the hit can push or kill them.
          final caught = {
            if (stunTicks > 0 || wetTicks > 0 || shieldTicks > 0)
              for (final offset in pattern)
                ?_targetAt(target + offset, Team.enemy),
          };
          // The pulse drops shields first, so they don't stop its own hit.
          for (final unit in caught) {
            if (unit is EnemyFighter && unit.def.frontShield) {
              unit.shieldDown = max(unit.shieldDown, shieldTicks);
            }
          }
          _impact(shot, Team.enemy);
          for (final unit in caught) {
            if (stunTicks > 0) unit.applyStatus(Status.stunned, stunTicks);
            if (wetTicks > 0) unit.applyStatus(Status.wet, wetTicks);
          }
          if (panel != null && target.inBounds && panelAt(target).walkable) {
            setPanel(target, panel);
          }
          if (smokeTicks > 0 && target.inBounds) {
            panelAt(target).smokeTicks = smokeTicks;
          }
        });
      case CrackEffect() || PushEffect() || PullEffect() || StatusShotEffect():
        _fire(def, damage, onHit: def.effect, status: status);
      case HealEffect(:final amount):
        heal(amount);
      case DamageBoostEffect(:final amount):
        damageBonus += amount;
      case EnergyBurstEffect(:final amount):
        energy += amount;
        energyBonus += amount;
      case EnergyMaxEffect(:final amount):
        energyMax += amount;
      case GaugeSpeedEffect(:final percent):
        gaugeSpeedBonus += percent;
      case BurstEffect(:final count, :final gapTicks):
        _fire(def, damage, status: status);
        for (var i = 1; i < count; i++) {
          schedule(
            player,
            const [],
            i * gapTicks,
            () => _fire(def, damage, status: status),
            telegraph: false,
          );
        }
      case MeleeEffect(
        :final pattern,
        :final stunTicks,
        :final push,
        :final crack,
        :final slash,
      ):
        final struck = <Fighter>{};
        final front = player.pos + const GridPos(1, 0);
        if (slash && front.inBounds) {
          flashes.add(HitFlash(front, FlashKind.slash));
        }
        for (final offset in pattern) {
          strike(
            player.pos + offset,
            damage,
            Team.enemy,
            def.element,
            family: def.family,
            status: status,
            struck: struck,
            flash: !slash,
          );
        }
        final steps = push + (hasRelic(Relics.servoArm) ? 1 : 0);
        for (final unit in struck) {
          if (_passesThrough(unit, def.family)) continue;
          if (stunTicks > 0) unit.applyStatus(Status.stunned, stunTicks);
          if (steps > 0 && !unit.isDead) {
            displace(unit, 1, 0, steps, byPlayer: true);
          }
        }
        if (crack) {
          for (final offset in pattern) {
            final cell = player.pos + offset;
            if (cell.inBounds && panelAt(cell).state == PanelState.normal) {
              setPanel(cell, PanelState.cracked);
            }
          }
        }
        damageBonus = 0;
      case RowStrikeEffect(:final fromColumn):
        for (var x = fromColumn; x < gridColumns; x++) {
          strike(
            GridPos(x, player.pos.y),
            damage,
            Team.enemy,
            def.element,
            family: def.family,
            status: status,
          );
        }
        damageBonus = 0;
      case BarrierEffect(:final ticks):
        player.barrierTicks = _lasting(ticks);
      case PanelChangeEffect(:final state):
        for (var x = 0; x < gridColumns; x++) {
          for (var y = 0; y < gridRows; y++) {
            final pos = GridPos(x, y);
            if (ownerAt(pos) == Team.player && panelAt(pos).walkable) {
              setPanel(pos, state);
            }
          }
        }
      case AreaStealEffect(:final ticks, :final hitDamage):
        _stealArea(ticks, hitDamage);
      case SpawnObstacleEffect(:final kind, :final amount):
        spawnObstacle(kind, amount, tossed: def.pose == ChipPose.toss);
      // An empty case would fall through to the next one.
      case NoEffect():
        break;
      case StormEffect():
        for (final enemy in enemies) {
          if (!enemy.hidden && ownerAt(enemy.pos) == Team.enemy) {
            enemy.applyStatus(Status.wet, wetTicks);
          }
        }
        final struck = <Fighter>{};
        for (var x = 0; x < gridColumns; x++) {
          for (var y = 0; y < gridRows; y++) {
            final cell = GridPos(x, y);
            if (ownerAt(cell) == Team.enemy) {
              strike(
                cell,
                damage,
                Team.enemy,
                def.element,
                family: def.family,
                status: status,
                struck: struck,
              );
            }
          }
        }
        damageBonus = 0;
      case AvalancheEffect():
        for (var x = player.pos.x + 1; x < gridColumns; x++) {
          final cell = GridPos(x, player.pos.y);
          if (_targetAt(cell, Team.enemy) case final target?) {
            strike(
              cell,
              damage,
              Team.enemy,
              def.element,
              status: status,
              family: def.family,
            );
            displace(target, 1, 0, 1, byPlayer: true);
            break;
          }
          if (panelAt(cell).walkable) setPanel(cell, PanelState.cracked);
        }
        damageBonus = 0;
      case TractorEffect(:final steps):
        final row = player.pos.y;
        final pulled = [
          for (final enemy in enemies)
            if (!enemy.hidden &&
                enemy.pos.x > player.pos.x &&
                enemy.cells.any((c) => c.y == row))
              enemy,
        ]..sort((a, b) => a.pos.x.compareTo(b.pos.x));
        for (final enemy in pulled) {
          displace(enemy, -1, 0, steps, byPlayer: true, force: true);
        }
      case ChainSurgeEffect():
        chainSurge = true;
      case RepeatNextEffect():
        overclocked = true;
      case MagnetTrapEffect():
        for (var x = player.pos.x + 1; x < gridColumns; x++) {
          final unit = unitAt(GridPos(x, player.pos.y));
          if (unit is! EnemyFighter) continue;
          _pull(unit);
          strike(
            unit.pos,
            damage,
            Team.enemy,
            def.element,
            status: status,
            family: def.family,
          );
          break;
        }
        damageBonus = 0;
    }
  }

  /// Player shot along the row, one cell per tick.
  void _fire(
    ChipDef def,
    int damage, {
    List<GridPos> pattern = const [GridPos(0, 0)],
    ChipEffect? onHit,
    Status? status,
  }) {
    projectiles.add(
      Projectile(
        team: Team.player,
        pos: player.pos + const GridPos(1, 0),
        dir: 1,
        stepTicks: 0,
        damage: damage,
        pattern: pattern,
        element: def.element,
        family: def.family,
        onHit: onHit,
        status: status,
      ),
    );
    damageBonus = 0;
  }

  /// Takes the first column with an enemy-owned panel. Enemies standing in
  /// it take [hitDamage] and are pushed back; panels still occupied after
  /// the push stay the enemy's.
  void _stealArea(int ticks, int hitDamage) {
    final x = _frontEnemyColumn();
    if (x == null) return;
    for (var y = 0; y < gridRows; y++) {
      final unit = unitAt(GridPos(x, y));
      if (unit == null || unit.team != Team.enemy) continue;
      damage(unit, hitDamage);
      displace(unit, 1, 0, 1, byPlayer: true);
    }
    for (var y = 0; y < gridRows; y++) {
      final cell = GridPos(x, y);
      if (unitAt(cell)?.team == Team.enemy) continue;
      panelAt(cell)
        ..owner = Team.player
        ..ownerTimer = ticks;
    }
    for (final enemy in List.of(enemies)) {
      enemy.def.behavior.onAreaStolen(enemy, this, x);
    }
  }

  int? _frontEnemyColumn() {
    for (var x = 0; x < gridColumns; x++) {
      for (var y = 0; y < gridRows; y++) {
        if (ownerAt(GridPos(x, y)) == Team.enemy) return x;
      }
    }
    return null;
  }

  /// [tossed] rocks and mines are lobbed at their cell and only appear
  /// when they land there (if it is still free).
  ///
  /// [amount] overrides the kind's default (see [SpawnObstacleEffect]).
  /// [ticks] of player gear, longer with Kit de Engenharia.
  int _lasting(int ticks) => hasRelic(Relics.engineeringKit)
      ? (ticks * engineeringKitBonus).round()
      : ticks;

  void spawnObstacle(ObstacleKind kind, int? amount, {bool tossed = false}) {
    void place(GridPos pos, void Function() put) =>
        tossed ? _toss(pos, put) : put();
    bool free(GridPos pos) =>
        pos.inBounds && panelAt(pos).walkable && unitAt(pos) == null;
    switch (kind) {
      case ObstacleKind.rock:
        final pos = player.pos + const GridPos(1, 0);
        if (!free(pos)) return;
        place(pos, () {
          if (free(pos)) {
            obstacles.add(Obstacle(kind, pos: pos, hp: amount ?? rockHp));
          }
        });
      case ObstacleKind.reflector:
        final pos = player.pos + const GridPos(1, 0);
        if (!free(pos)) return;
        obstacles.add(
          Obstacle(
            kind,
            pos: pos,
            hp: 1,
            team: Team.player,
            ticksLeft: _lasting(amount ?? reflectorTicks),
          ),
        );
      case ObstacleKind.turret:
        // Back of the player's row; if the player stands there, the first
        // free panel in front of them.
        GridPos? pos;
        for (var x = 0; x < gridColumns && pos == null; x++) {
          if (canEnter(player, GridPos(x, player.pos.y))) {
            pos = GridPos(x, player.pos.y);
          }
        }
        if (pos == null) return;
        obstacles.add(
          Obstacle(
            kind,
            pos: pos,
            hp: turretHp,
            team: Team.player,
            ticksLeft: _lasting(amount ?? turretTicks),
          ),
        );
      case ObstacleKind.tesla:
        // The frontmost free panel of the player's side in their row; behind
        // them if they stand at the front.
        GridPos? pos;
        for (var x = gridColumns - 1; x >= 0 && pos == null; x--) {
          final cell = GridPos(x, player.pos.y);
          if (canEnter(player, cell)) pos = cell;
        }
        if (pos == null) return;
        obstacles.add(
          Obstacle(
            kind,
            pos: pos,
            hp: teslaHp,
            team: Team.player,
            ticksLeft: _lasting(amount ?? teslaTicks),
          ),
        );
      case ObstacleKind.mine:
        final spots = [
          for (var x = playerColumns; x < gridColumns; x++)
            for (var y = 0; y < gridRows; y++)
              if (GridPos(x, y) case final pos
                  when panelAt(pos).walkable &&
                      !panelAt(pos).mine &&
                      unitAt(pos) == null)
                pos,
        ];
        if (spots.isEmpty) return;
        final pos = spots[random.nextInt(spots.length)];
        place(pos, () {
          if (panelAt(pos).walkable) {
            panelAt(pos).mineDamage = amount ?? mineDamage;
          }
        });
    }
  }

  // ------------------------------------------------------------- movement

  /// Every voluntary step goes through here: a cracked panel left behind
  /// becomes a hole, and stepping onto ice keeps the unit sliding along [dir]
  /// until the next cell can't be entered.
  void _moveUnit(Fighter unit, GridPos to, GridPos dir) {
    _step(unit, to);
    if (panelAt(unit.pos).state != PanelState.ice || _iceProof(unit)) return;
    while (canEnter(unit, unit.pos + dir)) {
      _step(unit, unit.pos + dir);
    }
  }

  /// Moves [unit] one cell, cracking what it leaves and setting off mines
  /// where it lands.
  ///
  /// Wide units crack only the panels they really leave and set off mines
  /// only on the panels they newly reach.
  void _step(Fighter unit, GridPos to) {
    final from = _cellsAt(unit, unit.pos);
    final into = _cellsAt(unit, to);
    if (!_iceProof(unit)) {
      for (final cell in from) {
        if (!into.contains(cell) && panelAt(cell).state == PanelState.cracked) {
          setPanel(cell, PanelState.hole);
        }
      }
    }
    unit.pos = to;
    for (final cell in into) {
      final panel = panelAt(cell);
      if (from.contains(cell) || !panel.mine) continue;
      final amount = panel.mineDamage;
      panel.mineDamage = 0;
      flashes.add(HitFlash(cell));
      damage(unit, amount);
    }
  }

  /// Whether any cell [unit] covers has a smoke cloud: it can't attack.
  bool inSmoke(Fighter unit) => _cellsAt(
    unit,
    unit.pos,
  ).any((cell) => cell.inBounds && panelAt(cell).smoky);

  /// Cells [unit] covers when standing at [pos].
  List<GridPos> _cellsAt(Fighter unit, GridPos pos) => unit is EnemyFighter
      ? [for (final offset in unit.def.footprint) pos + offset]
      : [pos];

  /// An attack move (Tanque's charge, Capanga Corpo-a-Corpo's lunge): one
  /// step that ignores sides and occupants but, like any step, cracks what
  /// it leaves and sets off mines. Holes are the caller's business.
  void stepOver(Fighter unit, GridPos to) => _step(unit, to);

  /// Forced movement (push, pull, knock-back), resolved cell by cell:
  /// - free cell on the unit's side: move in, and keep going if steps remain;
  /// - occupied cell: both units collide;
  /// - edge or the other side: the unit hits the wall;
  /// - hole: the unit falls and returns to where it started;
  /// - ice: the unit slides on, ignoring the step count.
  ///
  /// Units several panels big check every cell they would cover.
  /// [byPlayer] marks collisions the player caused, for relics; [force]
  /// moves units that are not [Fighter.pushable] (pulls).
  void displace(
    Fighter unit,
    int dx,
    int dy,
    int steps, {
    bool byPlayer = false,
    bool force = false,
  }) {
    if ((!unit.pushable && !force) || unit.isDead) return;
    final origin = unit.pos;
    final dir = GridPos(dx, dy);
    var left = steps;
    var sliding = false;
    while (left > 0 || sliding) {
      final next = unit.pos + dir;
      final cells = _cellsAt(unit, next);
      if (cells.any(
        (c) => !c.inBounds || (unit.team != null && ownerAt(c) != unit.team),
      )) {
        _collide(unit, null, byPlayer);
        return;
      }
      final other = cells
          .map(unitAt)
          .firstWhere((u) => u != null && u != unit, orElse: () => null);
      if (other != null) {
        _collide(unit, other, byPlayer);
        return;
      }
      if (cells.any((c) => !panelAt(c).walkable)) {
        unit.pos = origin;
        fall(unit);
        return;
      }
      _step(unit, next);
      if (panelAt(next).state == PanelState.ice && !_iceProof(unit)) {
        sliding = true;
      }
      left--;
    }
  }

  /// Botas de Gelo: the player neither slides nor breaks cracked panels.
  bool _iceProof(Fighter unit) =>
      unit is PlayerFighter && hasRelic(Relics.iceBoots);

  void fall(Fighter unit) {
    damage(unit, fallDamage);
    unit.applyStatus(Status.stunned, fallStunTicks);
  }

  /// Turns [cells] into holes at once. Whoever stands on one falls: takes
  /// [fallDamage], climbs out on a neighbouring panel of its side (any free
  /// panel of its side if no neighbour is free) and is stunned.
  void collapse(Iterable<GridPos> cells) {
    final victims = [for (final cell in cells) ?unitAt(cell)];
    for (final cell in cells) {
      setPanel(cell, PanelState.hole);
    }
    for (final unit in victims.toSet()) {
      if (unit.pushable) {
        final landing = _landingFor(unit);
        if (landing != null) _step(unit, landing);
      }
      fall(unit);
    }
  }

  GridPos? _landingFor(Fighter unit) {
    const sides = [
      GridPos(0, -1),
      GridPos(0, 1),
      GridPos(-1, 0),
      GridPos(1, 0),
    ];
    for (final side in sides) {
      if (canEnter(unit, unit.pos + side)) return unit.pos + side;
    }
    for (var x = 0; x < gridColumns; x++) {
      for (var y = 0; y < gridRows; y++) {
        if (canEnter(unit, GridPos(x, y))) return GridPos(x, y);
      }
    }
    return null;
  }

  /// [unit] crashes into [other], or into a wall when [other] is null.
  void _collide(Fighter unit, Fighter? other, bool byPlayer) {
    final heavy = [
      unit,
      other,
    ].any((u) => u is Obstacle && u.kind == ObstacleKind.rock);
    final collision = Collision(
      heavy ? rockCollisionDamage : collisionDamage,
      collisionStunTicks,
    );
    if (byPlayer) {
      for (final relic in relics) {
        relic.onCollision?.call(this, collision);
      }
    }
    for (final hit in [unit, ?other]) {
      damage(hit, collision.damage);
      hit.applyStatus(Status.stunned, collision.stunTicks);
      if (hit is EnemyFighter && hit.def.frontShield) {
        hit.shieldDown = shieldDownTicks;
      }
    }
  }

  /// Drags [target] to the front column of its side (wherever stolen
  /// panels put it); stuns it if already there. Pulls every unit, even
  /// those that can't be pushed.
  void _pull(Fighter target) {
    var distance = 0;
    while (_cellsAt(
      target,
      target.pos + GridPos(-distance - 1, 0),
    ).every((c) => c.inBounds && ownerAt(c) == target.team)) {
      distance++;
    }
    if (distance == 0) {
      target.applyStatus(Status.stunned, pullStunTicks);
    } else {
      displace(target, -1, 0, distance, byPlayer: true, force: true);
    }
  }

  // --------------------------------------------------------------- damage

  /// Attacker-side terrain bonus: Wood chips from grass and Fire units on
  /// lava hit 30% harder.
  int boosted(Fighter user, int damage, Element element) {
    final state = panelAt(user.pos).state;
    final boosted =
        (state == PanelState.grass && element == Element.wood) ||
        (state == PanelState.lava && user.element == Element.fire);
    return boosted ? (damage * terrainBoost).round() : damage;
  }

  /// Instant hit on [cell] against [opponent] (and neutral units).
  ///
  /// Attacks covering several cells share a [struck] set so a multi-cell
  /// unit is only hit once.
  void strike(
    GridPos cell,
    int amount,
    Team opponent,
    Element element, {
    ChipFamily? family,
    Status? status,
    Set<Fighter>? struck,
    bool flash = true,
  }) {
    if (!cell.inBounds) return;
    if (flash) flashes.add(HitFlash(cell));
    final target = _targetAt(cell, opponent);
    if (target != null && (struck?.add(target) ?? true)) {
      final through = _passesThrough(target, family);
      damage(
        target,
        amount + _markBonus(target),
        element: element,
        family: family,
      );
      if (status != null && !through) {
        target.applyStatus(status, statusTicks(status));
      }
    }
    _scorch(cell, element);
  }

  /// A Capanga Infiltrador whose twin lives on another row: projectiles
  /// can't hurt it.
  bool prismGuarded(EnemyFighter enemy) {
    final twin = enemy.partner;
    return enemy.def.prism &&
        twin != null &&
        !twin.isDead &&
        twin.pos.y != enemy.pos.y;
  }

  /// Target-side modifiers, then the hit:
  /// - invulnerable enemies ignore it; weak points pass it on doubled;
  /// - prisms reflect straight shots unless lined up with their twin;
  /// - a front shield stops straight shots coming from the player's side;
  /// - the Escudo Refletor can't be hurt; the player's barrier cancels the
  ///   hit;
  /// - the card [family] against the enemy's kind ([_kindMultiplier]); a
  ///   phased Etéreo lets it through, and an Explosivo makes it solid;
  /// - Elec on a Wet target doubles it again and dries the target;
  /// - Elec on a unit standing on ice stuns it;
  /// - Fire on a unit standing on grass doubles it.
  void damage(
    Fighter target,
    int amount, {
    Element element = Element.neutral,
    ChipFamily? family,
    HitKind kind = HitKind.area,
    Projectile? shot,
  }) {
    if (target is EnemyFighter) {
      if (target.invulnerable || target.hidden) return;
      if (target.linkedTo case final body?) {
        damage(
          body,
          amount * weakPointMultiplier,
          element: element,
          family: family,
        );
        return;
      }
      if (kind != HitKind.area && prismGuarded(target)) {
        if (kind == HitKind.straight && shot != null) {
          projectiles.add(
            Projectile(
              team: Team.enemy,
              pos: target.pos + const GridPos(-1, 0),
              dir: -1,
              stepTicks: 4,
              damage: shot.damage,
              pattern: const [GridPos(0, 0)],
              element: shot.element,
            ),
          );
        }
        events.add(BattleEvent(BattleEventKind.blocked, unit: target));
        return;
      }
      if (target.def.frontShield &&
          target.shieldDown == 0 &&
          kind == HitKind.straight &&
          shot?.dir == 1) {
        events.add(BattleEvent(BattleEventKind.blocked, unit: target));
        return;
      }
    }
    if (target is Obstacle && target.kind == ObstacleKind.reflector) {
      events.add(BattleEvent(BattleEventKind.blocked, unit: target));
      return;
    }
    var total = amount;
    if (target is EnemyFighter &&
        target.burrowed &&
        family != ChipFamily.explosive) {
      events.add(BattleEvent(BattleEventKind.blocked, unit: target));
      return;
    }
    if (target is EnemyFighter && family != null) {
      final multiplier = _kindMultiplier(target, family);
      if (multiplier == 0) {
        events.add(BattleEvent(BattleEventKind.blocked, unit: target));
        return;
      }
      total = (total * multiplier).round();
      if (target.def.kind == EnemyKind.ethereal &&
          family == ChipFamily.explosive) {
        target.materialTicks = materializeTicks;
      }
      for (final relic in relics) {
        relic.onHit?.call(this, target, family);
      }
    }
    if (target is EnemyFighter && target.exposedTicks > 0) total *= 2;
    final panel = panelAt(target.pos).state;
    if (element == Element.elec) {
      if (target.has(Status.wet)) {
        total *= 2;
        target.statuses.remove(Status.wet);
      }
      if (panel == PanelState.ice) {
        target.applyStatus(Status.stunned, iceStunTicks);
      }
    }
    if (element == Element.fire && panel == PanelState.grass) total *= 2;
    if (target is PlayerFighter && target.barrierTicks > 0) {
      target.barrierTicks = 0;
      events.add(BattleEvent(BattleEventKind.blocked, unit: target));
      return;
    }
    if (target is PlayerFighter &&
        total > 0 &&
        !armorUsed &&
        hasRelic(Relics.armor)) {
      armorUsed = true;
      events.add(BattleEvent(BattleEventKind.blocked, unit: target));
      return;
    }
    target.takeDamage(total);
    if (total > 0) hits.add((target: target, amount: total));
  }

  /// How much a card of [family] hurts [target]: by what it is made of,
  /// then the relics. 0 when the hit passes through a phased Etéreo.
  double _kindMultiplier(EnemyFighter target, ChipFamily family) {
    var multiplier = _kindBase(target, family);
    for (final relic in relics) {
      multiplier =
          relic.modifyHit?.call(this, target, family, multiplier) ?? multiplier;
    }
    return multiplier;
  }

  double _kindBase(EnemyFighter target, ChipFamily family) => switch ((
    target.def.kind,
    family,
  )) {
    (EnemyKind.machine, ChipFamily.projectile) => machineProjectileMultiplier,
    // ARGOS with its core open ([EnemyFighter.shieldDown]).
    (EnemyKind.machine, ChipFamily.energy)
        when target.def == Enemies.argos && target.shieldDown > 0 =>
      argosOpenEnergyMultiplier,
    (EnemyKind.machine, ChipFamily.energy) => machineEnergyMultiplier,
    (EnemyKind.organic, ChipFamily.explosive) => organicExplosiveMultiplier,
    (EnemyKind.ethereal, ChipFamily.projectile || ChipFamily.melee)
        when target.phased =>
      0,
    _ => 1,
  };

  /// A hit of [family] on [target] goes through it untouched: no damage,
  /// status or push (a phased Etéreo).
  bool _passesThrough(Fighter target, ChipFamily? family) =>
      target is EnemyFighter &&
      ((target.burrowed && family != ChipFamily.explosive) ||
          (family != null && _kindMultiplier(target, family) == 0));

  /// Mira Laser's extra damage on a marked target.
  int _markBonus(Fighter target) => target.has(Status.marked) ? markBonus : 0;

  /// Escudo Refletor: [shot] bounces off [reflector] and flies back down
  /// the row, doubled.
  void _reflect(Obstacle reflector, Projectile shot) {
    shot.spent = true;
    events.add(BattleEvent(BattleEventKind.blocked, unit: reflector));
    flashes.add(HitFlash(reflector.pos));
    projectiles.add(
      Projectile(
        team: Team.player,
        pos: reflector.pos + const GridPos(1, 0),
        dir: 1,
        stepTicks: 0,
        damage: shot.damage * 2,
        pattern: const [GridPos(0, 0)],
        element: shot.element,
        family: shot.family,
      ),
    );
  }

  /// Panel side effects of an attack landing on [cell]: Fire burns grass
  /// away and Aqua puts lava out.
  void _scorch(GridPos cell, Element element) {
    final state = panelAt(cell).state;
    if ((element == Element.fire && state == PanelState.grass) ||
        (element == Element.aqua && state == PanelState.lava)) {
      setPanel(cell, PanelState.normal);
    }
  }

  // --------------------------------------------------------------- enemies

  void _updateEnemies() {
    for (final enemy in List.of(enemies)) {
      if (enemy.shieldDown > 0) enemy.shieldDown--;
      if (enemy.materialTicks > 0) enemy.materialTicks--;
      if (enemy.exposedTicks > 0) enemy.exposedTicks--;
      if (enemy.attackPose > 0) enemy.attackPose--;
      if (enemy.isDead) continue;
      if (enemy.has(Status.stunned)) {
        _interrupt(enemy);
        continue;
      }
      enemy.def.behavior.tick(enemy, this);
    }
  }

  /// A stun cancels every attack [enemy] hasn't landed yet, with its
  /// warnings, and its behavior drops the wind-up.
  void _interrupt(EnemyFighter enemy) {
    _scheduled.removeWhere((s) => s.owner == enemy);
    telegraphs.removeWhere((t) => t.owner == enemy);
    enemy.pendingAttacks = 0;
    enemy.def.behavior.onInterrupted(enemy, this);
  }

  /// Straight enemy shot from the cell in front of [enemy].
  void enemyShot(
    EnemyFighter enemy, {
    int? damage,
    int? stepTicks,
    Element? element,
  }) {
    if (inSmoke(enemy)) return;
    events.add(BattleEvent(BattleEventKind.enemyShot, unit: enemy));
    enemy.attackPose = attackPoseTicks;
    final shotElement = element ?? enemy.element;
    projectiles.add(
      Projectile(
        team: Team.enemy,
        pos: enemy.pos + const GridPos(-1, 0),
        dir: -1,
        stepTicks: stepTicks ?? enemy.def.shotStepTicks,
        damage: boosted(enemy, damage ?? enemy.def.shotDamage, shotElement),
        pattern: const [GridPos(0, 0)],
        element: shotElement,
      ),
    );
  }

  /// Adds an enemy mid-battle (Colossus fist, Maestro notes).
  EnemyFighter summon(EnemyDef def, GridPos pos, {EnemyFighter? linkedTo}) {
    final unit = EnemyFighter(def, pos)..linkedTo = linkedTo;
    enemies.add(unit);
    return unit;
  }

  /// Obstacles with a lifetime expire; every second turrets fire an Elec
  /// shot down their row and tesla coils zap the first enemy of theirs.
  void _updateObstacles() {
    for (final obstacle in obstacles) {
      if (obstacle.ticksLeft > 0 && --obstacle.ticksLeft == 0) {
        obstacle.hp = 0;
      }
      final shooter =
          obstacle.kind == ObstacleKind.turret ||
          obstacle.kind == ObstacleKind.tesla;
      if (!shooter || obstacle.isDead || inSmoke(obstacle)) continue;
      if (--obstacle.fireTimer > 0) continue;
      obstacle.fireTimer = ticksPerSecond;
      if (obstacle.kind == ObstacleKind.tesla) {
        _zap(obstacle);
        continue;
      }
      projectiles.add(
        Projectile(
          team: Team.player,
          pos: obstacle.pos + const GridPos(1, 0),
          dir: 1,
          stepTicks: 0,
          damage: turretShotDamage,
          pattern: const [GridPos(0, 0)],
          element: Element.elec,
        ),
      );
    }
  }

  /// Bobina Tesla: an instant Elec hit on the first target of its row.
  void _zap(Obstacle coil) {
    for (var x = coil.pos.x + 1; x < gridColumns; x++) {
      final cell = GridPos(x, coil.pos.y);
      if (_targetAt(cell, Team.enemy) == null) continue;
      strike(cell, teslaZapDamage, Team.enemy, Element.elec);
      return;
    }
  }

  // ----------------------------------------------------------- projectiles

  void _updateProjectiles() {
    for (final shot in List.of(projectiles)) {
      final opponent = shot.team == Team.player ? Team.enemy : Team.player;
      // A phased Etéreo lets the shot fly on through it.
      if (_targetAt(shot.pos, opponent) case final target?
          when !_passesThrough(target, shot.family)) {
        _impact(shot, opponent);
        continue;
      }
      if (shot.stepTimer > 0) {
        shot.stepTimer--;
      } else {
        shot
          ..stepTimer = shot.stepTicks
          ..pos = shot.pos + GridPos(shot.dir, 0);
      }
      shot.ttl--;
      if (shot.pos.x < 0 || shot.pos.x >= gridColumns || shot.ttl <= 0) {
        shot.spent = true;
      }
    }
    projectiles.removeWhere((p) => p.spent);
  }

  /// Damage is applied once, on the impact tick, only to the opposing team
  /// and neutral units.
  void _impact(Projectile shot, Team opponent) {
    if (_targetAt(shot.pos, opponent) case final Obstacle reflector
        when reflector.kind == ObstacleKind.reflector) {
      _reflect(reflector, shot);
      return;
    }
    shot.spent = true;
    if (shot.family == ChipFamily.explosive &&
        hasRelic(Relics.shortFuse) &&
        shot.pos.inBounds &&
        panelAt(shot.pos).state == PanelState.normal) {
      setPanel(shot.pos, PanelState.cracked);
    }
    final struck = <Fighter>{};
    for (final offset in shot.pattern) {
      final cell = shot.pos + GridPos(offset.x * shot.dir, offset.y);
      if (!cell.inBounds) continue;
      flashes.add(HitFlash(cell));
      final straight = offset == const GridPos(0, 0);
      final target = _targetAt(cell, opponent);
      if (target != null && struck.add(target)) {
        final through = _passesThrough(target, shot.family);
        damage(
          target,
          shot.damage + _markBonus(target),
          element: shot.element,
          family: shot.family,
          kind: straight ? HitKind.straight : HitKind.spread,
          shot: shot,
        );
        if (!through) {
          if (shot.status case final status?) {
            target.applyStatus(status, statusTicks(status));
          }
          if (straight) _applyOnHit(shot, target);
        }
      }
      _scorch(cell, shot.element);
    }
  }

  void _applyOnHit(Projectile shot, Fighter target) {
    switch (shot.onHit) {
      case CrackEffect():
        setPanel(target.pos, PanelState.cracked);
      case PushEffect(:final steps, :final status):
        if (status != null) target.applyStatus(status, statusTicks(status));
        displace(
          target,
          shot.dir,
          0,
          steps,
          byPlayer: shot.team == Team.player,
        );
      case PullEffect(:final stunTicks):
        _pull(target);
        if (stunTicks > 0) target.applyStatus(Status.stunned, stunTicks);
      case StatusShotEffect(:final status, :final ticks):
        target.applyStatus(status, ticks);
      default:
    }
  }

  /// Unit a shot or strike aimed at [opponent] would hit on [pos]: an
  /// opponent or a neutral blocker.
  Fighter? _targetAt(GridPos pos, Team opponent) {
    final unit = unitAt(pos);
    if (unit == null || (unit.team != null && unit.team != opponent)) {
      return null;
    }
    return unit;
  }
}

/// Default duration of [status] when a chip applies it.
int statusTicks(Status status) => switch (status) {
  Status.burning => burnTicks,
  Status.wet => wetTicks,
  Status.stunned => ticksPerSecond,
  Status.rooted => rootTicks,
  Status.marked => markTicks,
};
