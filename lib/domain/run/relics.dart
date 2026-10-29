import '../battle/battle_state.dart';
import '../battle/enemies.dart';
import '../chips/battle_chip.dart';
import '../grid.dart';

enum RelicKind {
  /// Works on the map, shop or energy.
  global,

  /// Hooks into battles.
  combat,
}

/// Passive item kept for the whole run. Every hook is optional and called
/// by the [BattleState] (or read by the [RunState]) when it applies.
class RelicDef {
  const RelicDef({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    this.rarity = Rarity.common,
    this.onBattleStart,
    this.modifyDamage,
    this.onCollision,
    this.onChainComplete,
    this.onHandRefill,
    this.modifyHit,
    this.onHit,
    this.onChipUsed,
    this.maxHp = 0,
  });

  final String id;
  final String name;
  final String description;
  final RelicKind kind;

  /// How often it is offered and its shop price.
  final Rarity rarity;

  /// Max HP gained (or lost) when the relic is taken.
  final int maxHp;

  final void Function(BattleState battle)? onBattleStart;

  /// Adjusts the damage of [chip], which the player is about to use.
  final int Function(BattleState battle, ChipDef chip, int damage)?
  modifyDamage;

  /// Adjusts the damage multiplier of a hit of [family] on [target], after
  /// the enemy kind (0 = the hit passes through).
  final double Function(
    BattleState battle,
    EnemyFighter target,
    ChipFamily family,
    double multiplier,
  )?
  modifyHit;

  /// A hit of [family] landed on [target], before its statuses react.
  final void Function(
    BattleState battle,
    EnemyFighter target,
    ChipFamily family,
  )?
  onHit;

  /// [chip] was used and paid for.
  final void Function(BattleState battle, ChipDef chip)? onChipUsed;

  /// A collision the player caused (push, pull).
  final void Function(BattleState battle, Collision collision)? onCollision;

  /// A 3-chip chain was completed.
  final void Function(BattleState battle)? onChainComplete;

  /// The gauge filled and a new hand was drawn.
  final void Function(BattleState battle)? onHandRefill;
}

void _extraEnergy(BattleState battle) => battle.energyMax++;

void _peekTop(BattleState battle) =>
    battle.peekOpen = battle.deck.peek(2).isNotEmpty;

/// The player's front column in its row: the next panel ahead isn't
/// theirs, even after Roubo de Área moved the line.
int _frontLine(BattleState battle, ChipDef chip, int damage) =>
    battle.ownerAt(battle.player.pos + const GridPos(1, 0)) != Team.player
    ? (damage * 1.2).round()
    : damage;

void _hardCrash(BattleState battle, Collision collision) {
  collision
    ..damage += 20
    ..stunTicks += ticksPerSecond;
}

void _fastGauge(BattleState battle) => battle.boostNextGauge = true;

int _piercingAmmo(BattleState battle, ChipDef chip, int damage) =>
    chip.family == ChipFamily.projectile && damage > 0 ? damage + 3 : damage;

int _doubleCharge(BattleState battle, ChipDef chip, int damage) =>
    chip.family == ChipFamily.explosive && damage > 0 ? damage + 5 : damage;

void _refundProjectile(BattleState battle, ChipDef chip) {
  if (chip.family != ChipFamily.projectile || battle.projectileRefunded) {
    return;
  }
  battle
    ..energy += chip.cost
    ..projectileRefunded = true;
}

void _symbiote(BattleState battle, ChipDef chip) {
  if (chip.family == ChipFamily.consumable) battle.heal(5);
}

void _superconduct(BattleState battle, EnemyFighter target, ChipFamily family) {
  if (family == ChipFamily.energy && target.has(Status.wet)) {
    target.applyStatus(Status.stunned, ticksPerSecond);
  }
}

double _monoBlade(
  BattleState battle,
  EnemyFighter target,
  ChipFamily family,
  double multiplier,
) => family == ChipFamily.melee && target.has(Status.stunned)
    ? multiplier * 1.5
    : multiplier;

double _decoder(
  BattleState battle,
  EnemyFighter target,
  ChipFamily family,
  double multiplier,
) => target.def.kind == EnemyKind.machine ? multiplier * 1.25 : multiplier;

double _phaseTuner(
  BattleState battle,
  EnemyFighter target,
  ChipFamily family,
  double multiplier,
) => family == ChipFamily.projectile && target.phased ? 0.5 : multiplier;

void _armorPlate(BattleState battle) =>
    battle.spawnObstacle(ObstacleKind.rock, null);

abstract final class Relics {
  static const extraBattery = RelicDef(
    id: 'extra_battery',
    name: 'Bateria Extra',
    description: '+1 de Energia base.',
    kind: RelicKind.global,
    rarity: Rarity.rare,
    onBattleStart: _extraEnergy,
  );

  static const sortedFolder = RelicDef(
    id: 'sorted_folder',
    name: 'Pasta Ordenada',
    description:
        'Na recarga, mostra as 2 próximas cartas; mande 1 para o fundo do deck.',
    kind: RelicKind.global,
    rarity: Rarity.uncommon,
    onHandRefill: _peekTop,
  );

  static const memberCard = RelicDef(
    id: 'member_card',
    name: 'Cartão de Sócio',
    description: 'Loja 25% mais barata; remover carta é grátis.',
    kind: RelicKind.global,
    rarity: Rarity.uncommon,
  );

  static const frontLine = RelicDef(
    id: 'front_line',
    name: 'Linha de Frente',
    description:
        'Cartas usadas na coluna mais à frente do seu lado causam +20% de dano.',
    kind: RelicKind.combat,
    modifyDamage: _frontLine,
  );

  static const collisionCore = RelicDef(
    id: 'collision_core',
    name: 'Núcleo de Colisão',
    description: 'Colisões que você causa: +20 de dano e +1 s atordoado.',
    kind: RelicKind.combat,
    onCollision: _hardCrash,
  );

  static const chainTrigger = RelicDef(
    id: 'chain_trigger',
    name: 'Gatilho de Corrente',
    description:
        'Corrente de 3 completa: o próximo gauge enche 50% mais rápido.',
    kind: RelicKind.combat,
    rarity: Rarity.uncommon,
    onChainComplete: _fastGauge,
  );

  static const iceBoots = RelicDef(
    id: 'ice_boots',
    name: 'Botas de Gelo',
    description:
        'Você não desliza no Gelo e não abre Buraco ao sair do Rachado.',
    kind: RelicKind.combat,
  );

  static const piercingAmmo = RelicDef(
    id: 'piercing_ammo',
    name: 'Munição Perfurante',
    description: 'Cartas de Projétil causam +3 de dano.',
    kind: RelicKind.combat,
    modifyDamage: _piercingAmmo,
  );

  static const extendedMag = RelicDef(
    id: 'extended_mag',
    name: 'Carregador Estendido',
    description: 'A 1ª carta de Projétil de cada mão devolve a Energia gasta.',
    kind: RelicKind.combat,
    rarity: Rarity.rare,
    onChipUsed: _refundProjectile,
  );

  static const doubleCharge = RelicDef(
    id: 'double_charge',
    name: 'Carga Dupla',
    description: 'Cartas de Explosivo causam +5 de dano.',
    kind: RelicKind.combat,
    modifyDamage: _doubleCharge,
  );

  /// Read by the battle where an Explosivo lands.
  static const shortFuse = RelicDef(
    id: 'short_fuse',
    name: 'Pavio Curto',
    description: 'Explosivos racham o painel onde explodem.',
    kind: RelicKind.combat,
    rarity: Rarity.uncommon,
  );

  static const superconductor = RelicDef(
    id: 'superconductor',
    name: 'Bobina Supercondutora',
    description: 'Energia em alvo Molhado também atordoa por 1 s.',
    kind: RelicKind.combat,
    rarity: Rarity.uncommon,
    onHit: _superconduct,
  );

  /// Read by the battle on each refill.
  static const capacitor = RelicDef(
    id: 'capacitor',
    name: 'Capacitor',
    description:
        'Na recarga, até 2 de Energia que sobrou passam para a mão nova.',
    kind: RelicKind.combat,
    rarity: Rarity.rare,
  );

  /// Read by the battle on each melee hit.
  static const servoArm = RelicDef(
    id: 'servo_arm',
    name: 'Servo-braço',
    description: 'Golpes de Corpo-a-corpo empurram o alvo 1 painel.',
    kind: RelicKind.combat,
    rarity: Rarity.uncommon,
  );

  static const monoBlade = RelicDef(
    id: 'mono_blade',
    name: 'Lâmina Monomolecular',
    description: 'Corpo-a-corpo causa +50% de dano em alvo atordoado.',
    kind: RelicKind.combat,
    rarity: Rarity.uncommon,
    modifyHit: _monoBlade,
  );

  /// Read by the battle when it places gear.
  static const engineeringKit = RelicDef(
    id: 'engineering_kit',
    name: 'Kit de Engenharia',
    description: 'Drone, Bobina Tesla e os escudos duram 50% mais.',
    kind: RelicKind.combat,
    rarity: Rarity.uncommon,
  );

  static const armorPlate = RelicDef(
    id: 'armor_plate',
    name: 'Placa Blindada',
    description: 'Começa cada luta com uma Rocha à sua frente.',
    kind: RelicKind.combat,
    onBattleStart: _armorPlate,
  );

  /// Read by the battle when the player is hit.
  static const armor = RelicDef(
    id: 'armor',
    name: 'Armadura',
    description: 'Anula o primeiro dano que você sofre em cada luta.',
    kind: RelicKind.combat,
    rarity: Rarity.rare,
  );

  /// Read by the battle when a single-use card is used.
  static const tacticalPack = RelicDef(
    id: 'tactical_pack',
    name: 'Mochila Tática',
    description:
        'A 1ª carta de uso único de cada luta vai para o descarte em vez de '
        'sair.',
    kind: RelicKind.combat,
    rarity: Rarity.rare,
  );

  static const symbiote = RelicDef(
    id: 'symbiote',
    name: 'Simbionte',
    description: 'Cada carta Consumível usada cura 5.',
    kind: RelicKind.combat,
    onChipUsed: _symbiote,
  );

  static const phaseTuner = RelicDef(
    id: 'phase_tuner',
    name: 'Sintonizador de Fase',
    description: 'Projéteis acertam Etéreos em fase com 50% do dano.',
    kind: RelicKind.combat,
    rarity: Rarity.uncommon,
    modifyHit: _phaseTuner,
  );

  static const decoder = RelicDef(
    id: 'decoder',
    name: 'Decodificador',
    description: '+25% de dano contra Máquinas.',
    kind: RelicKind.combat,
    rarity: Rarity.uncommon,
    modifyHit: _decoder,
  );

  /// Read by the run when it rolls rewards.
  static const luckyChip = RelicDef(
    id: 'lucky_chip',
    name: 'Chip da Sorte',
    description: 'Cartas raras aparecem com o dobro da chance.',
    kind: RelicKind.global,
    rarity: Rarity.rare,
  );

  // Boss relics: offered only by a boss's spoils, a strong bonus with a
  // drawback.

  /// Read by the campfire.
  static const unstableReactor = RelicDef(
    id: 'unstable_reactor',
    name: 'Reator Instável',
    description: '+1 de Energia base. Não pode descansar na fogueira.',
    kind: RelicKind.global,
    onBattleStart: _extraEnergy,
  );

  /// Read by the run when it rolls a battle's spoils.
  static const etCrown = RelicDef(
    id: 'et_crown',
    name: 'Coroa do Rei ET',
    description:
        '+1 de Energia base. Recompensas de batalha oferecem 2 cartas em vez '
        'de 3.',
    kind: RelicKind.global,
    onBattleStart: _extraEnergy,
  );

  /// Read by the battle when the player moves.
  static const heavyExoskeleton = RelicDef(
    id: 'heavy_exoskeleton',
    name: 'Exoesqueleto Pesado',
    description: '+1 de Energia base. Você se move 50% mais devagar.',
    kind: RelicKind.combat,
    onBattleStart: _extraEnergy,
  );

  /// Read by the battle when it draws a hand and fills the gauge.
  static const neuralImplant = RelicDef(
    id: 'neural_implant',
    name: 'Implante Neural',
    description: 'Mão de 6 cartas. O medidor enche 25% mais devagar.',
    kind: RelicKind.combat,
  );

  /// Read by the run when it gains Créditos.
  static const armoredVault = RelicDef(
    id: 'armored_vault',
    name: 'Cofre Blindado',
    description: '+1 de Energia base. Você não ganha mais Créditos.',
    kind: RelicKind.global,
    onBattleStart: _extraEnergy,
  );

  /// Read by the battle screen, which draws the bars.
  static const combatVisor = RelicDef(
    id: 'combat_visor',
    name: 'Visor de Combate',
    description:
        'Mostra ao lado dos inimigos quanto falta para o próximo ataque. '
        '−15 de HP máximo.',
    kind: RelicKind.combat,
    maxHp: -15,
  );

  static const boss = [
    unstableReactor,
    etCrown,
    heavyExoskeleton,
    neuralImplant,
    armoredVault,
    combatVisor,
  ];

  /// The relic saved as [id]; null if it no longer exists.
  static RelicDef? byId(String id) =>
      [...all, ...boss].where((r) => r.id == id).firstOrNull;

  static const all = [
    extraBattery,
    sortedFolder,
    memberCard,
    frontLine,
    collisionCore,
    chainTrigger,
    iceBoots,
    piercingAmmo,
    extendedMag,
    doubleCharge,
    shortFuse,
    superconductor,
    capacitor,
    servoArm,
    monoBlade,
    engineeringKit,
    armorPlate,
    armor,
    tacticalPack,
    symbiote,
    phaseTuner,
    decoder,
    luckyChip,
  ];
}
