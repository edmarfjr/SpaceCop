import 'dart:math';

import '../element.dart';
import '../grid.dart';
import 'enemy_behaviors.dart';

/// What an enemy is made of, which sets how much each card family hurts it
/// (see `BattleState.damage`).
enum EnemyKind {
  /// Armored: Projétil does half, Energia double.
  machine,

  /// Flesh: Explosivo does +50%.
  organic,

  /// Phased out of normal matter: Projétil and Corpo-a-corpo pass through
  /// it, except while it attacks or for a moment after an Explosivo hit.
  ethereal;

  /// Name shown in game.
  String get label => switch (this) {
    EnemyKind.machine => 'Máquina',
    EnemyKind.organic => 'Orgânico',
    EnemyKind.ethereal => 'Etéreo',
  };
}

/// Enemy stats. Timings are in simulation ticks (30 per second).
class EnemyDef {
  const EnemyDef({
    required this.name,
    required this.hp,
    this.moveTicks = 30,
    this.attackTicks = 60,
    this.shotDamage = 0,
    this.shotStepTicks = 20,
    this.element = Element.neutral,
    this.kind = EnemyKind.organic,
    this.behavior = const MobileCannonBehavior(),
    this.footprint = const [GridPos(0, 0)],
    this.pushable = true,
    this.summon = false,
    this.frontShield = false,
    this.prism = false,
  });

  final String name;
  final int hp;

  /// Pause after each step.
  final int moveTicks;

  /// Length of the attack animation; the shot fires at the midpoint.
  final int attackTicks;
  final int shotDamage;

  /// Ticks the enemy shot waits on each cell (lower = faster).
  final int shotStepTicks;
  final Element element;
  final EnemyKind kind;

  /// The AI. Stateless; per-unit state lives on the `EnemyFighter`.
  final EnemyBehavior behavior;

  /// Cells occupied, relative to the unit's position.
  final List<GridPos> footprint;
  final bool pushable;

  /// Spawned by another enemy; doesn't count toward winning the battle.
  final bool summon;

  /// Blocks straight projectile hits on its front (Brute).
  final bool frontShield;

  /// Reflects straight projectiles unless lined up with its partner (Dupla
  /// Prisma).
  final bool prism;
}

class EnemySpawn {
  const EnemySpawn(this.def, this.pos);

  final EnemyDef def;
  final GridPos pos;
}

class Encounter {
  const Encounter(this.spawns);

  final List<EnemySpawn> spawns;
}

abstract final class Enemies {
  /// The cart's only enemy: `'10,15,12,10,30,60,30'` -> move 30, attack 60,
  /// hp 30. Shot damage 5 is the cart's `m_atq` default.
  static const mobileCannon = EnemyDef(
    name: 'Canhão Móvel',
    kind: EnemyKind.machine,
    hp: 30,
    moveTicks: 30,
    attackTicks: 60,
    shotDamage: 5,
  );

  static const root = EnemyDef(
    name: 'Raiz',
    hp: 40,
    element: Element.wood,
    pushable: false,
    behavior: RootBehavior(),
  );

  static const bubbler = EnemyDef(
    name: 'Bolhador',
    hp: 35,
    element: Element.aqua,
    behavior: BubblerBehavior(),
  );

  static const cannon = EnemyDef(
    name: 'Canhão Fixo',
    kind: EnemyKind.machine,
    hp: 50,
    pushable: false,
    behavior: CannonBehavior(),
  );

  static const brute = EnemyDef(
    name: 'Capanga Bruto',
    hp: 80,
    moveTicks: 20,
    frontShield: true,
    behavior: BruteBehavior(),
  );

  static const digger = EnemyDef(
    name: 'Capanga Engenheiro',
    hp: 70,
    element: Element.wood,
    behavior: DiggerBehavior(),
  );

  static const prism = EnemyDef(
    name: 'Capanga Infiltrador',
    hp: 40,
    shotDamage: 10,
    shotStepTicks: 12,
    prism: true,
    behavior: PrismBehavior(),
  );

  static const lavaGuard = EnemyDef(
    name: 'Guardião de Lava',
    hp: 90,
    element: Element.fire,
    behavior: LavaGuardBehavior(),
  );

  static const colossus = EnemyDef(
    name: 'Colosso Sísmico',
    kind: EnemyKind.machine,
    hp: 300,
    footprint: [GridPos(0, 0), GridPos(0, 1)],
    pushable: false,
    behavior: ColossusBehavior(),
  );

  /// The Colossus's weak point; damage to it goes to the body, doubled.
  static const colossusFist = EnemyDef(
    name: 'Punho',
    kind: EnemyKind.machine,
    hp: 1,
    pushable: false,
    summon: true,
    behavior: FistBehavior(),
  );

  static const maestro = EnemyDef(
    name: 'Maestro Elemental',
    kind: EnemyKind.ethereal,
    hp: 350,
    element: Element.fire,
    pushable: false,
    behavior: MaestroBehavior(),
  );

  static const note = EnemyDef(
    name: 'Nota',
    kind: EnemyKind.ethereal,
    hp: 20,
    pushable: false,
    summon: true,
    behavior: IdleBehavior(),
  );

  // Capangas of the criminal organization: the first mission's basic
  // enemies.

  static const gruntGun = EnemyDef(
    name: 'Capanga Atirador',
    hp: 40,
    shotDamage: 10,
    shotStepTicks: 8,
    behavior: GruntGunBehavior(),
  );

  static const gruntDuck = EnemyDef(
    name: 'Capanga Atirador Agachado',
    hp: 50,
    shotDamage: 5,
    shotStepTicks: 8,
    behavior: GruntDuckBehavior(),
  );

  static const gruntMelee = EnemyDef(
    name: 'Capanga Corpo-a-Corpo',
    hp: 50,
    behavior: GruntMeleeBehavior(),
  );

  static const gruntGrenade = EnemyDef(
    name: 'Capanga Granada',
    hp: 40,
    behavior: GruntGrenadeBehavior(),
  );

  static const gruntArtillery = EnemyDef(
    name: 'Capanga Artilharia',
    hp: 60,
    pushable: false,
    behavior: GruntArtilleryBehavior(),
  );

  static const sentry = EnemyDef(
    name: 'Torreta',
    kind: EnemyKind.machine,
    hp: 40,
    shotDamage: 10,
    shotStepTicks: 8,
    pushable: false,
    behavior: SentryBehavior(),
  );

  /// The first mission's boss. Two panels wide: [pos] is the front one.
  static const tank = EnemyDef(
    name: 'Tanque de Guerra',
    kind: EnemyKind.machine,
    hp: 300,
    shotDamage: 10,
    shotStepTicks: 6,
    pushable: false,
    footprint: [GridPos(0, 0), GridPos(1, 0)],
    behavior: TankBehavior(),
  );

  // ETs: the second mission's enemies, a tribe living in ancient ruins.

  static const etWarrior = EnemyDef(
    name: 'ET Guerreiro',
    hp: 45,
    behavior: GruntMeleeBehavior(reach: 2, wanderTicks: 20, flee: true),
  );

  static const etGunner = EnemyDef(
    name: 'ET Atirador',
    hp: 40,
    shotDamage: 10,
    shotStepTicks: 8,
    behavior: GruntGunBehavior(wanderTicks: 20, flee: true),
  );

  static const etTrap = EnemyDef(
    name: 'ET Emboscador',
    hp: 50,
    behavior: TrapBehavior(),
  );

  static const etShaman = EnemyDef(
    name: 'ET Xamã',
    hp: 50,
    behavior: ShamanBehavior(),
  );

  /// Left by the ET Xamã; doesn't count toward winning.
  static const energySphere = EnemyDef(
    name: 'Esfera de Energia',
    kind: EnemyKind.machine,
    hp: 20,
    pushable: false,
    summon: true,
    behavior: SphereBehavior(),
  );

  /// Two panels wide, like the Tanque: [pos] is the front one.
  static const etRider = EnemyDef(
    name: 'ET Montado',
    hp: 100,
    pushable: false,
    footprint: [GridPos(0, 0), GridPos(1, 0)],
    behavior: TankBehavior(chargeOnly: true),
  );

  static const etShieldBearer = EnemyDef(
    name: 'ET Escudeiro',
    hp: 60,
    shotDamage: 10,
    shotStepTicks: 8,
    frontShield: true,
    behavior: ShieldBearerBehavior(),
  );

  static const etHealer = EnemyDef(
    name: 'ET Curandeiro',
    hp: 40,
    behavior: HealerBehavior(),
  );

  static const sentinel = EnemyDef(
    name: 'Sentinela Ancestral',
    kind: EnemyKind.machine,
    hp: 60,
    pushable: false,
    behavior: SentinelBehavior(),
  );

  static const scarab = EnemyDef(
    name: 'Escaravelho Mecânico',
    kind: EnemyKind.machine,
    hp: 15,
    behavior: TickBehavior(),
  );

  // Second mission elites.

  /// The Colosso's moves, scaled down to an elite.
  static const ruinGolem = EnemyDef(
    name: 'Golem das Ruínas',
    kind: EnemyKind.machine,
    hp: 200,
    footprint: [GridPos(0, 0), GridPos(0, 1)],
    pushable: false,
    behavior: ColossusBehavior(),
  );

  static const priestess = EnemyDef(
    name: 'Sacerdotisa ET',
    hp: 120,
    behavior: PriestessBehavior(),
  );

  /// The Sacerdotisa's copies: any hit dispels them.
  static const illusion = EnemyDef(
    name: 'Sacerdotisa ET',
    hp: 1,
    summon: true,
    behavior: IdleBehavior(),
  );

  static const portal = EnemyDef(
    name: 'Portal Ancestral',
    kind: EnemyKind.machine,
    hp: 180,
    pushable: false,
    frontShield: true,
    behavior: PortalBehavior(),
  );

  /// The second mission's boss. Two panels wide: [pos] is the front one.
  static const tribeKing = EnemyDef(
    name: 'Rei da Tribo',
    hp: 350,
    pushable: false,
    footprint: [GridPos(0, 0), GridPos(1, 0)],
    behavior: TribeKingBehavior(),
  );

  static const totem = EnemyDef(
    name: 'Totem Ancestral',
    kind: EnemyKind.machine,
    hp: 30,
    pushable: false,
    summon: true,
    behavior: IdleBehavior(),
  );

  /// The Rei's totems in Fúria.
  static const ragingTotem = EnemyDef(
    name: 'Totem Ancestral',
    kind: EnemyKind.machine,
    hp: 50,
    pushable: false,
    summon: true,
    behavior: IdleBehavior(),
  );

  /// Called by the Rei: don't count toward winning.
  static const tribeWarrior = EnemyDef(
    name: 'ET Guerreiro',
    hp: 45,
    summon: true,
    behavior: GruntMeleeBehavior(reach: 2, wanderTicks: 20, flee: true),
  );

  static const tribeGunner = EnemyDef(
    name: 'ET Atirador',
    hp: 40,
    shotDamage: 10,
    shotStepTicks: 8,
    summon: true,
    behavior: GruntGunBehavior(wanderTicks: 20, flee: true),
  );

  // Etéreos: the third mission's enemies.

  static const shadowGun = EnemyDef(
    name: 'Sombra Atiradora',
    kind: EnemyKind.ethereal,
    hp: 40,
    shotDamage: 10,
    shotStepTicks: 8,
    behavior: GruntGunBehavior(),
  );

  static const shadowFly = EnemyDef(
    name: 'Sombra Alada',
    kind: EnemyKind.ethereal,
    hp: 30,
    behavior: ShadowFlyBehavior(),
  );

  static const shadowJumper = EnemyDef(
    name: 'Sombra Saltadora',
    kind: EnemyKind.ethereal,
    hp: 45,
    behavior: ShadowJumperBehavior(),
  );

  static const shadowNest = EnemyDef(
    name: 'Ninho',
    kind: EnemyKind.ethereal,
    hp: 40,
    pushable: false,
    behavior: NestBehavior(),
  );

  /// Hatched by the Ninho; doesn't count toward winning.
  static const shadowTick = EnemyDef(
    name: 'Carrapato',
    kind: EnemyKind.ethereal,
    hp: 10,
    summon: true,
    behavior: TickBehavior(),
  );

  static const predator = EnemyDef(
    name: 'Predador',
    kind: EnemyKind.ethereal,
    hp: 120,
    behavior: PredatorBehavior(),
  );

  static const stalker = EnemyDef(
    name: 'Espreitador',
    kind: EnemyKind.ethereal,
    hp: 150,
    pushable: false,
    behavior: StalkerBehavior(),
  );

  /// Normal battles of each act. Canhão Móvel, Raiz, Bolhador and Canhão
  /// Fixo are out of them for now.
  static List<EnemyDef> basicsOf(int act) => switch (act) {
    2 => ruinsBasics,
    3 => shadowBasics,
    _ => basics,
  };

  static const ruinsBasics = [
    etWarrior,
    etGunner,
    etTrap,
    etShaman,
    etShieldBearer,
    etHealer,
    sentinel,
  ];

  static const shadowBasics = [shadowGun, shadowFly, shadowJumper, shadowNest];

  static const basics = [
    gruntGun,
    gruntDuck,
    gruntMelee,
    gruntGrenade,
    gruntArtillery,
    sentry,
  ];
}

abstract final class Encounters {
  /// Column the enemy may stand in, at least: the fixed and back-line ones
  /// stay at the back.
  static int _minX(EnemyDef def) => switch (def) {
    Enemies.gruntArtillery || Enemies.cannon || Enemies.sentinel => 5,
    Enemies.gruntDuck ||
    Enemies.sentry ||
    Enemies.bubbler ||
    Enemies.etHealer ||
    Enemies.shadowNest => 4,
    _ => playerColumns,
  };

  /// One or two basic enemies of [act] on distinct cells. In the ruins the
  /// Escaravelhos come three at a time, and the Curandeiro never alone.
  static Encounter normal(Random random, {int act = 1}) {
    final pool = Enemies.basicsOf(act);
    if (act == 2 && random.nextInt(6) == 0) {
      return const Encounter([
        EnemySpawn(Enemies.scarab, GridPos(4, 0)),
        EnemySpawn(Enemies.scarab, GridPos(5, 1)),
        EnemySpawn(Enemies.scarab, GridPos(4, 2)),
      ]);
    }
    final spawns = <EnemySpawn>[];
    final count = 1 + random.nextInt(2);
    while (spawns.length < count) {
      final def = pool[random.nextInt(pool.length)];
      if (def == Enemies.etHealer && count == 1) continue;
      final minX = _minX(def);
      final pos = GridPos(
        minX + random.nextInt(gridColumns - minX),
        random.nextInt(gridRows),
      );
      if (spawns.any((s) => s.pos == pos)) continue;
      spawns.add(EnemySpawn(def, pos));
    }
    return Encounter(spawns);
  }

  static Encounter elite(Random random, {int act = 1}) => switch (act) {
    2 => switch (random.nextInt(4)) {
      0 => Encounter([
        EnemySpawn(Enemies.etRider, GridPos(4, random.nextInt(gridRows))),
      ]),
      1 => const Encounter([EnemySpawn(Enemies.ruinGolem, GridPos(4, 0))]),
      2 => const Encounter([EnemySpawn(Enemies.priestess, GridPos(4, 1))]),
      _ => const Encounter([
        EnemySpawn(Enemies.portal, GridPos(5, 1)),
        EnemySpawn(Enemies.etShieldBearer, GridPos(4, 1)),
      ]),
    },
    3 =>
      random.nextBool()
          ? const Encounter([EnemySpawn(Enemies.predator, GridPos(4, 1))])
          : const Encounter([EnemySpawn(Enemies.stalker, GridPos(4, 1))]),
    _ => switch (random.nextInt(4)) {
      0 => Encounter([
        EnemySpawn(Enemies.brute, GridPos(4, random.nextInt(gridRows))),
      ]),
      1 => const Encounter([EnemySpawn(Enemies.digger, GridPos(4, 1))]),
      2 => const Encounter([
        EnemySpawn(Enemies.prism, GridPos(4, 0)),
        EnemySpawn(Enemies.prism, GridPos(5, 2)),
      ]),
      _ => const Encounter([EnemySpawn(Enemies.lavaGuard, GridPos(5, 1))]),
    },
  };

  /// Each act's boss. The third act has no boss of its own yet: the two
  /// Etéreo elites together stand in.
  static Encounter boss(Random random, {int act = 1}) => switch (act) {
    2 => const Encounter([EnemySpawn(Enemies.tribeKing, GridPos(4, 1))]),
    3 => const Encounter([
      EnemySpawn(Enemies.predator, GridPos(4, 0)),
      EnemySpawn(Enemies.stalker, GridPos(5, 2)),
    ]),
    _ => const Encounter([EnemySpawn(Enemies.tank, GridPos(4, 1))]),
  };
}
