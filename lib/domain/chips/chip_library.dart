import '../battle/battle_state.dart';
import '../battle/panels.dart';
import '../element.dart';
import '../grid.dart';
import 'battle_chip.dart';

/// Every card in the game. Ported from the `--cartas` tab of the cart.
abstract final class Chips {
  static const shot = ChipDef(
    id: 'shot',
    name: 'Tiro Rápido',
    description: 'Acerta o primeiro inimigo da linha.',
    cost: 0,
    family: ChipFamily.projectile,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 5,
    effect: ProjectileEffect(),
  );

  static const cannon = ChipDef(
    id: 'cannon',
    name: 'Tiro Mirado',
    description: 'Acerta o primeiro inimigo da linha.',
    cost: 1,
    family: ChipFamily.projectile,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 15,
    effect: ProjectileEffect(),
  );

  static const smg = ChipDef(
    id: 'smg',
    name: 'SMG',
    description: 'Rajada de 3 tiros na linha.',
    cost: 1,
    family: ChipFamily.projectile,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 5,
    effect: BurstEffect(3),
  );

  static const shotgun = ChipDef(
    id: 'shotgun',
    name: 'Escopeta',
    description: 'Atravessa: acerta o alvo e a célula atrás dele.',
    cost: 1,
    family: ChipFamily.projectile,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 10,
    effect: ProjectileEffect(pattern: [GridPos(0, 0), GridPos(1, 0)]),
  );

  static const vShot = ChipDef(
    id: 'vshot',
    name: 'Plasma',
    description: 'Acerta o alvo e as diagonais atrás dele.',
    cost: 1,
    family: ChipFamily.energy,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 10,
    element: Element.elec,
    effect: ProjectileEffect(
      pattern: [GridPos(0, 0), GridPos(1, 1), GridPos(1, -1)],
    ),
  );

  static const melta = ChipDef(
    id: 'melta',
    name: 'Melta',
    description: 'Acerta as 3 colunas inimigas da sua linha.',
    cost: 1,
    family: ChipFamily.energy,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 10,
    element: Element.fire,
    effect: RowStrikeEffect(),
  );

  static const missile = ChipDef(
    id: 'missile',
    name: 'Míssil',
    description: 'Explode em cruz no primeiro alvo da linha.',
    cost: 2,
    family: ChipFamily.explosive,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 15,
    effect: ProjectileEffect(
      pattern: [
        GridPos(0, 0),
        GridPos(1, 0),
        GridPos(-1, 0),
        GridPos(0, 1),
        GridPos(0, -1),
      ],
    ),
  );

  static const baton = ChipDef(
    id: 'baton',
    name: 'Cacetete',
    description: 'Golpeia o painel à frente e atordoa por 2 s.',
    cost: 1,
    family: ChipFamily.melee,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 10,
    element: Element.elec,
    effect: MeleeEffect(pattern: [GridPos(1, 0)], stunTicks: 2 * ticksPerSecond),
    pose: ChipPose.melee,
  );

  static const sword = ChipDef(
    id: 'sword',
    name: 'Espada',
    description: 'Golpeia os 3 painéis à frente.',
    cost: 1,
    family: ChipFamily.melee,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 20,
    effect: MeleeEffect(slash: true),
    pose: ChipPose.melee,
  );

  static const shoulderBash = ChipDef(
    id: 'shoulder_bash',
    name: 'Ombrada',
    description: 'Golpeia o painel à frente e empurra o alvo 1 painel.',
    cost: 1,
    family: ChipFamily.melee,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 15,
    effect: MeleeEffect(pattern: [GridPos(1, 0)], push: 1),
    pose: ChipPose.melee,
  );

  static const energyWhip = ChipDef(
    id: 'energy_whip',
    name: 'Chicote de Energia',
    description: 'Golpeia os 2 painéis à frente na sua linha.',
    cost: 1,
    family: ChipFamily.melee,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 15,
    element: Element.elec,
    effect: MeleeEffect(pattern: [GridPos(1, 0), GridPos(2, 0)]),
    pose: ChipPose.melee,
  );

  static const seismicHammer = ChipDef(
    id: 'seismic_hammer',
    name: 'Martelo Sísmico',
    description: 'Golpeia o painel à frente e o racha.',
    cost: 2,
    family: ChipFamily.melee,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 30,
    effect: MeleeEffect(pattern: [GridPos(1, 0)], crack: true),
    pose: ChipPose.melee,
  );

  static const grenade = ChipDef(
    id: 'grenade',
    name: 'Granada',
    description: 'Lançada no 3º painel à frente: explode em cruz. Uso único.',
    cost: 2,
    family: ChipFamily.explosive,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 25,
    effect: GrenadeEffect(),
    pose: ChipPose.toss,
    exhaust: true,
  );

  static const incendiaryGrenade = ChipDef(
    id: 'incendiary_grenade',
    name: 'Granada Incendiária',
    description:
        'Lançada no 3º painel à frente: explode em cruz e o centro vira Lava. '
        'Uso único.',
    cost: 2,
    family: ChipFamily.explosive,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 15,
    element: Element.fire,
    effect: GrenadeEffect(panel: PanelState.lava),
    pose: ChipPose.toss,
    exhaust: true,
  );

  static const smokeGrenade = ChipDef(
    id: 'smoke_grenade',
    name: 'Granada de Fumaça',
    description:
        'Lançada no 3º painel à frente: explode em cruz e deixa Fumaça por '
        '10 s. Quem está na Fumaça não ataca. Uso único.',
    cost: 2,
    family: ChipFamily.explosive,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 10,
    effect: GrenadeEffect(smokeTicks: smokeDurationTicks),
    pose: ChipPose.toss,
    exhaust: true,
  );

  static const stunGrenade = ChipDef(
    id: 'stun_grenade',
    name: 'Granada Atordoante',
    description:
        'Lançada no 3º painel à frente: explode em cruz e atordoa quem for '
        'atingido por 2 s. Uso único.',
    cost: 2,
    family: ChipFamily.explosive,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 5,
    element: Element.elec,
    effect: GrenadeEffect(stunTicks: 2 * ticksPerSecond),
    pose: ChipPose.toss,
    exhaust: true,
  );

  static const recover = ChipDef(
    id: 'recover',
    name: 'Primeiros Socorros',
    description: 'Recupera 10 de vida. Uso único.',
    cost: 2,
    family: ChipFamily.consumable,
    rarity: Rarity.uncommon,
    type: ChipType.recovery,
    target: ChipTarget.self,
    effect: HealEffect(10),
    exhaust: true,
  );

  static const atkBoost = ChipDef(
    id: 'atk_boost',
    name: 'Bala Oca',
    description: 'O próximo ataque causa +10 de dano.',
    cost: 1,
    family: ChipFamily.tactical,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: DamageBoostEffect(10),
  );

  static const energyDrink = ChipDef(
    id: 'energy_drink',
    name: 'Energético',
    description: '+2 de Energia nesta mão.',
    cost: 1,
    family: ChipFamily.tactical,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: EnergyBurstEffect(2),
  );

  static const energyTank = ChipDef(
    id: 'energy_tank',
    name: 'Tanque de Energia',
    description: '+1 de Energia máxima até o fim da luta. Uso único.',
    cost: 2,
    family: ChipFamily.consumable,
    rarity: Rarity.rare,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: EnergyMaxEffect(1),
    exhaust: true,
  );

  static const powerGenerator = ChipDef(
    id: 'power_generator',
    name: 'Gerador de Energia',
    description: 'O gauge enche 20% mais rápido até o fim da luta. Uso único.',
    cost: 2,
    family: ChipFamily.consumable,
    rarity: Rarity.rare,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: GaugeSpeedEffect(20),
    exhaust: true,
  );

  static const cracker = ChipDef(
    id: 'cracker',
    name: 'Rachador',
    description: 'Racha o painel do primeiro alvo da linha.',
    cost: 2,
    family: ChipFamily.projectile,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 20,
    effect: CrackEffect(),
    pose: ChipPose.melee,
  );

  static const bubblePush = ChipDef(
    id: 'bubble_push',
    name: 'Bolha Empurradora',
    description: 'Molha e empurra o alvo 1 painel.',
    cost: 1,
    family: ChipFamily.projectile,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 10,
    element: Element.aqua,
    effect: PushEffect(1, status: Status.wet),
  );

  static const crossFlame = ChipDef(
    id: 'cross_flame',
    name: 'Chama Cruzada',
    description:
        'Lançada no primeiro inimigo da linha, por cima de obstáculos: '
        'explode em cruz. Queima Grama.',
    cost: 2,
    family: ChipFamily.explosive,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 15,
    element: Element.fire,
    effect: ProjectileEffect(
      pattern: [
        GridPos(0, 0),
        GridPos(1, 0),
        GridPos(-1, 0),
        GridPos(0, 1),
        GridPos(0, -1),
      ],
    ),
    pose: ChipPose.toss,
  );

  static const thunderLance = ChipDef(
    id: 'thunder_lance',
    name: 'Lança Trovão',
    description: 'Acerta as 3 colunas inimigas da sua linha.',
    cost: 2,
    family: ChipFamily.energy,
    rarity: Rarity.rare,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 20,
    element: Element.elec,
    effect: RowStrikeEffect(),
  );

  static const barrier = ChipDef(
    id: 'barrier',
    name: 'Escudo de Energia',
    description: 'Anula o próximo dano. Dura até 5 s.',
    cost: 2,
    family: ChipFamily.equipment,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: BarrierEffect(5 * ticksPerSecond),
  );

  static const mirror = ChipDef(
    id: 'mirror',
    name: 'Escudo Refletor',
    description:
        'Escudo à sua frente por 5 s: devolve tiros inimigos com o dobro '
        'do dano.',
    cost: 2,
    family: ChipFamily.equipment,
    rarity: Rarity.uncommon,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: SpawnObstacleEffect(ObstacleKind.reflector),
  );

  static const seedGrass = ChipDef(
    id: 'seed_grass',
    name: 'Semear Grama',
    description: 'Seus painéis viram Grama por 15 s.',
    cost: 1,
    family: ChipFamily.tactical,
    rarity: Rarity.uncommon,
    type: ChipType.support,
    target: ChipTarget.self,
    element: Element.wood,
    effect: PanelChangeEffect(PanelState.grass),
  );

  static const areaSteal = ChipDef(
    id: 'area_steal',
    name: 'Avanço',
    description:
        'A coluna inimiga da frente é sua por 10 s. Quem estiver nela leva 5 '
        'e é empurrado.',
    cost: 2,
    family: ChipFamily.tactical,
    rarity: Rarity.rare,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: AreaStealEffect(10 * ticksPerSecond, hitDamage: 5),
  );

  // Keeps the old id, so saved runs still load it.
  static const barricade = ChipDef(
    id: 'rock',
    name: 'Barricada',
    description:
        'Barricada de 40 HP à sua frente. Bloqueia tiros inimigos; '
        'dá para andar por ela.',
    cost: 1,
    family: ChipFamily.equipment,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: SpawnObstacleEffect(ObstacleKind.barricade),
    pose: ChipPose.toss,
  );

  static const mine = ChipDef(
    id: 'mine',
    name: 'Mina',
    description: 'Mina escondida no lado inimigo: 40 de dano.',
    cost: 1,
    family: ChipFamily.equipment,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    effect: SpawnObstacleEffect(ObstacleKind.mine),
    pose: ChipPose.toss,
  );

  static const turret = ChipDef(
    id: 'turret',
    name: 'Drone',
    description: 'Drone de 30 HP que atira 5 Elétrico por segundo por 10 s.',
    cost: 2,
    family: ChipFamily.equipment,
    rarity: Rarity.rare,
    type: ChipType.attack,
    target: ChipTarget.self,
    element: Element.elec,
    effect: SpawnObstacleEffect(ObstacleKind.turret),
  );

  static const hook = ChipDef(
    id: 'hook',
    name: 'Gancho',
    description:
        'Puxa o primeiro alvo da linha para a frente e o atordoa por 2 s.',
    cost: 1,
    family: ChipFamily.tactical,
    type: ChipType.support,
    target: ChipTarget.row,
    effect: PullEffect(stunTicks: 2 * ticksPerSecond),
    pose: ChipPose.melee,
  );

  static const cryoGrenade = ChipDef(
    id: 'cryo_grenade',
    name: 'Criogranada',
    description:
        'Lançada no 3º painel à frente: explode em cruz, molha quem for '
        'atingido e o centro vira Gelo. Uso único.',
    cost: 2,
    family: ChipFamily.explosive,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 10,
    element: Element.aqua,
    effect: GrenadeEffect(panel: PanelState.ice, wetTicks: wetTicks),
    pose: ChipPose.toss,
    exhaust: true,
  );

  static const emp = ChipDef(
    id: 'emp',
    name: 'Pulso EMP',
    description:
        'Lançado no 3º painel à frente: pulso em cruz que derruba escudos '
        'frontais por 3 s. Uso único.',
    cost: 2,
    family: ChipFamily.energy,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 10,
    element: Element.elec,
    effect: GrenadeEffect(shieldTicks: 3 * ticksPerSecond),
    pose: ChipPose.toss,
    exhaust: true,
  );

  static const neuralVine = ChipDef(
    id: 'neural_vine',
    name: 'Vinha Neural',
    description: 'Acerta o primeiro inimigo da linha e o enraíza por 3 s.',
    cost: 1,
    family: ChipFamily.projectile,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 15,
    element: Element.wood,
    effect: StatusShotEffect(Status.rooted, 3 * ticksPerSecond),
  );

  static const laserSight = ChipDef(
    id: 'laser_sight',
    name: 'Mira Laser',
    description:
        'Marca o primeiro inimigo da linha: por 5 s ele leva +5 de cada '
        'acerto.',
    cost: 0,
    family: ChipFamily.tactical,
    type: ChipType.support,
    target: ChipTarget.row,
    effect: StatusShotEffect(Status.marked, markTicks),
  );

  static const overcharge = ChipDef(
    id: 'overcharge',
    name: 'Sobrecarga',
    description:
        'A próxima carta de Projétil, Explosivo, Energia ou Corpo-a-corpo '
        'conta 2 vezes na corrente.',
    cost: 1,
    family: ChipFamily.tactical,
    rarity: Rarity.uncommon,
    type: ChipType.support,
    target: ChipTarget.self,
    element: Element.elec,
    effect: ChainSurgeEffect(),
  );

  static const tractorBeam = ChipDef(
    id: 'tractor_beam',
    name: 'Feixe Trator',
    description:
        'Puxa 1 painel todos os inimigos da sua linha. Quem bater em algo '
        'sofre colisão.',
    cost: 2,
    family: ChipFamily.tactical,
    rarity: Rarity.uncommon,
    type: ChipType.support,
    target: ChipTarget.row,
    effect: TractorEffect(),
  );

  static const teslaCoil = ChipDef(
    id: 'tesla_coil',
    name: 'Bobina Tesla',
    description:
        'Bobina de 30 HP na frente do seu lado: dá um choque de 5 Elétrico '
        'no primeiro inimigo da linha a cada 1 s, por 8 s.',
    cost: 2,
    family: ChipFamily.equipment,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    element: Element.elec,
    effect: SpawnObstacleEffect(ObstacleKind.tesla),
  );

  static const overclock = ChipDef(
    id: 'overclock',
    name: 'Overclock',
    description:
        'A próxima carta é usada 2 vezes; a segunda não gasta Energia. Uso '
        'único.',
    cost: 1,
    family: ChipFamily.consumable,
    rarity: Rarity.rare,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: RepeatNextEffect(),
    exhaust: true,
  );

  static const sniper = ChipDef(
    id: 'sniper',
    name: 'Rifle de Precisão',
    description:
        'Acerta o primeiro inimigo da linha; +15 se ele estiver na coluna do '
        'fundo.',
    cost: 2,
    family: ChipFamily.projectile,
    rarity: Rarity.rare,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 30,
    effect: ProjectileEffect(farBonus: 15),
  );

  static const incendiaryRound = ChipDef(
    id: 'incendiary_round',
    name: 'Bala Incendiária',
    description: 'Acerta o primeiro inimigo da linha e o deixa Queimando.',
    cost: 1,
    family: ChipFamily.projectile,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 10,
    element: Element.fire,
    effect: StatusShotEffect(Status.burning, burnTicks),
  );

  static const piercingShot = ChipDef(
    id: 'piercing_shot',
    name: 'Tiro Perfurante',
    description: 'Atravessa a linha: acerta as 3 colunas inimigas.',
    cost: 1,
    family: ChipFamily.projectile,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 12,
    effect: RowStrikeEffect(),
  );

  static const tranqDart = ChipDef(
    id: 'tranq_dart',
    name: 'Dardo Tranquilizante',
    description: 'Acerta o primeiro inimigo da linha e o atordoa por 1 s.',
    cost: 1,
    family: ChipFamily.projectile,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 5,
    effect: StatusShotEffect(Status.stunned, ticksPerSecond),
  );

  static const fragGrenade = ChipDef(
    id: 'frag_grenade',
    name: 'Granada de Fragmentação',
    description:
        'Lançada no 3º painel à frente: explode num quadrado 3x3. Uso único.',
    cost: 2,
    family: ChipFamily.explosive,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 15,
    effect: GrenadeEffect(pattern: _square),
    pose: ChipPose.toss,
    exhaust: true,
  );

  static const mortar = ChipDef(
    id: 'mortar',
    name: 'Morteiro',
    description: 'Lançado no 4º painel à frente: explode em cruz. Uso único.',
    cost: 2,
    family: ChipFamily.explosive,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 20,
    effect: GrenadeEffect(distance: 4),
    pose: ChipPose.toss,
    exhaust: true,
  );

  static const fissureBomb = ChipDef(
    id: 'fissure_bomb',
    name: 'Bomba de Fissura',
    description:
        'Lançada no 3º painel à frente: explode na coluna e racha os 3 '
        'painéis. Uso único.',
    cost: 1,
    family: ChipFamily.explosive,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 10,
    effect: GrenadeEffect(pattern: _column, crack: true),
    pose: ChipPose.toss,
    exhaust: true,
  );

  static const fusionLaser = ChipDef(
    id: 'fusion_laser',
    name: 'Laser de Fusão',
    description:
        'Acerta as 3 colunas inimigas da sua linha; o painel do primeiro '
        'inimigo vira Lava.',
    cost: 2,
    family: ChipFamily.energy,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 15,
    element: Element.fire,
    effect: RowStrikeEffect(panel: PanelState.lava),
  );

  static const freezeRay = ChipDef(
    id: 'freeze_ray',
    name: 'Raio Congelante',
    description:
        'Acerta o primeiro inimigo da linha, o Molha e o painel dele vira '
        'Gelo.',
    cost: 1,
    family: ChipFamily.energy,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 10,
    element: Element.aqua,
    effect: StatusShotEffect(Status.wet, wetTicks, panel: PanelState.ice),
  );

  static const steadyBeam = ChipDef(
    id: 'steady_beam',
    name: 'Feixe Contínuo',
    description: 'Rajada de 4 disparos Elétricos na linha.',
    cost: 2,
    family: ChipFamily.energy,
    rarity: Rarity.rare,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 5,
    element: Element.elec,
    effect: BurstEffect(4),
  );

  static const dagger = ChipDef(
    id: 'dagger',
    name: 'Adaga',
    description: 'Golpeia o painel à frente.',
    cost: 0,
    family: ChipFamily.melee,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 6,
    effect: MeleeEffect(pattern: [GridPos(1, 0)]),
    pose: ChipPose.melee,
  );

  static const thermalBlade = ChipDef(
    id: 'thermal_blade',
    name: 'Lâmina Térmica',
    description: 'Golpeia os 3 painéis à frente e deixa os alvos Queimando.',
    cost: 1,
    family: ChipFamily.melee,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 15,
    element: Element.fire,
    effect: MeleeEffect(slash: true, inflict: Status.burning),
    pose: ChipPose.melee,
  );

  static const scythe = ChipDef(
    id: 'scythe',
    name: 'Foice',
    description: 'Golpeia os 2 painéis diagonais à frente.',
    cost: 1,
    family: ChipFamily.melee,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 15,
    effect: MeleeEffect(pattern: [GridPos(1, -1), GridPos(1, 1)]),
    pose: ChipPose.melee,
  );

  static const hydraulicFist = ChipDef(
    id: 'hydraulic_fist',
    name: 'Punho Hidráulico',
    description: 'Golpeia o painel à frente e empurra o alvo 3 painéis.',
    cost: 2,
    family: ChipFamily.melee,
    rarity: Rarity.rare,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 25,
    effect: MeleeEffect(pattern: [GridPos(1, 0)], push: 3),
    pose: ChipPose.melee,
  );

  static const fireTurret = ChipDef(
    id: 'fire_turret',
    name: 'Torre Incendiária',
    description:
        'Torre de 30 HP que atira 5 de Fogo a cada 2 s por 10 s; quem é '
        'atingido fica Queimando.',
    cost: 2,
    family: ChipFamily.equipment,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    element: Element.fire,
    effect: SpawnObstacleEffect(ObstacleKind.turret),
  );

  static const minefield = ChipDef(
    id: 'minefield',
    name: 'Campo Minado',
    description: '2 minas escondidas no lado inimigo: 25 de dano cada.',
    cost: 2,
    family: ChipFamily.equipment,
    rarity: Rarity.rare,
    type: ChipType.attack,
    target: ChipTarget.self,
    effect: SpawnObstacleEffect(ObstacleKind.mine, amount: 25, count: 2),
    pose: ChipPose.toss,
  );

  static const stimulant = ChipDef(
    id: 'stimulant',
    name: 'Estimulante',
    description: '+3 de Energia nesta mão. Uso único.',
    cost: 1,
    family: ChipFamily.consumable,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: EnergyBurstEffect(3),
    exhaust: true,
  );

  static const specialAmmo = ChipDef(
    id: 'special_ammo',
    name: 'Munição Especial',
    description:
        'Suas cartas de Projétil causam +3 de dano até o fim da luta. Uso '
        'único.',
    cost: 1,
    family: ChipFamily.consumable,
    rarity: Rarity.rare,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: ProjectileBonusEffect(3),
    exhaust: true,
  );

  static const combatScan = ChipDef(
    id: 'combat_scan',
    name: 'Análise de Combate',
    description: 'Marca todos os inimigos por 3 s: cada acerto causa +5.',
    cost: 1,
    family: ChipFamily.tactical,
    rarity: Rarity.uncommon,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: StatusAllEffect(Status.marked, 3 * ticksPerSecond),
  );

  static const jammer = ChipDef(
    id: 'jammer',
    name: 'Interferência',
    description: 'Atordoa todos os inimigos por 1 s.',
    cost: 1,
    family: ChipFamily.tactical,
    rarity: Rarity.uncommon,
    type: ChipType.support,
    target: ChipTarget.self,
    element: Element.elec,
    effect: StatusAllEffect(Status.stunned, ticksPerSecond),
  );

  static const dash = ChipDef(
    id: 'dash',
    name: 'Investida',
    description:
        'Avança até a frente do seu lado e golpeia o painel à frente.',
    cost: 1,
    family: ChipFamily.melee,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 20,
    effect: DashEffect(MeleeEffect(pattern: [GridPos(1, 0)])),
    pose: ChipPose.melee,
  );

  static const medicDrone = ChipDef(
    id: 'medic_drone',
    name: 'Drone Médico',
    description: 'Drone de 20 HP que cura 2 de vida por segundo por 8 s.',
    cost: 2,
    family: ChipFamily.equipment,
    rarity: Rarity.uncommon,
    type: ChipType.recovery,
    target: ChipTarget.self,
    effect: SpawnObstacleEffect(ObstacleKind.medic),
  );

  static const domeGenerator = ChipDef(
    id: 'dome_generator',
    name: 'Gerador de Domo',
    description: 'Anula os 3 próximos danos. Dura até 10 s.',
    cost: 2,
    family: ChipFamily.equipment,
    rarity: Rarity.rare,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: BarrierEffect(10 * ticksPerSecond, charges: 3),
  );

  static const repairKit = ChipDef(
    id: 'repair_kit',
    name: 'Kit de Reparos',
    description: 'Recupera 5 de vida e remove os status negativos. Uso único.',
    cost: 1,
    family: ChipFamily.consumable,
    rarity: Rarity.uncommon,
    type: ChipType.recovery,
    target: ChipTarget.self,
    effect: CleanseEffect(5),
    exhaust: true,
  );

  static const nanobots = ChipDef(
    id: 'nanobots',
    name: 'Nanobots',
    description: 'Regenera 1 de vida por segundo por 15 s. Uso único.',
    cost: 2,
    family: ChipFamily.consumable,
    rarity: Rarity.rare,
    type: ChipType.recovery,
    target: ChipTarget.self,
    effect: SelfStatusEffect(Status.regen, regenTicks),
    exhaust: true,
  );

  static const tacticalReload = ChipDef(
    id: 'tactical_reload',
    name: 'Recarga Tática',
    description: 'Compra 2 cartas (até 7 na mão).',
    cost: 1,
    family: ChipFamily.tactical,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: DrawEffect(2),
  );

  static const resonance = ChipDef(
    id: 'resonance',
    name: 'Pulso Ressonante',
    description:
        'Acerta o primeiro inimigo da linha: dano × a posição na corrente '
        '(1ª, 2ª ou 3ª carta).',
    cost: 1,
    family: ChipFamily.energy,
    rarity: Rarity.uncommon,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 5,
    element: Element.elec,
    effect: ChainScaleEffect(),
  );

  static const wildcard = ChipDef(
    id: 'wildcard',
    name: 'Coringa',
    description:
        'A próxima carta de Projétil, Explosivo, Energia ou Corpo-a-corpo '
        'conta como da família da corrente atual.',
    cost: 1,
    family: ChipFamily.tactical,
    rarity: Rarity.rare,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: WildcardEffect(),
  );

  static const adrenaline = ChipDef(
    id: 'adrenaline',
    name: 'Adrenalina',
    description: 'Os 3 próximos ataques causam +5 de dano. Uso único.',
    cost: 0,
    family: ChipFamily.consumable,
    rarity: Rarity.uncommon,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: AttackChargesEffect(3, 5),
    exhaust: true,
  );

  static const _square = [
    GridPos(-1, -1),
    GridPos(0, -1),
    GridPos(1, -1),
    GridPos(-1, 0),
    GridPos(0, 0),
    GridPos(1, 0),
    GridPos(-1, 1),
    GridPos(0, 1),
    GridPos(1, 1),
  ];

  static const _column = [GridPos(0, -1), GridPos(0, 0), GridPos(0, 1)];

  /// Junk from events (Enfermaria Clandestina, Hangar de Contrabando).
  /// Never offered as a reward.
  static const bug = ChipDef(
    id: 'bug',
    name: 'Bug',
    description: 'Não faz nada.',
    cost: 0,
    family: ChipFamily.tactical,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: NoEffect(),
  );

  /// The "+" version of [def], or null if it can't be upgraded (already
  /// upgraded, Bug).
  static ChipDef? upgradeOf(ChipDef def) =>
      def.upgraded ? null : _upgrades[def.id];

  /// Copy of [base] marked as upgraded, with a "+" name and the changes.
  static ChipDef _up(
    ChipDef base, {
    int? damage,
    int? cost,
    String? description,
    ChipEffect? effect,
  }) => ChipDef(
    id: base.id,
    name: '${base.name}+',
    description: description ?? base.description,
    cost: cost ?? base.cost,
    family: base.family,
    type: base.type,
    target: base.target,
    effect: effect ?? base.effect,
    damage: damage ?? base.damage,
    element: base.element,
    pose: base.pose,
    exhaust: base.exhaust,
    upgraded: true,
    rarity: base.rarity,
  );

  static final Map<String, ChipDef> _upgrades = {
    for (final up in [
      _up(shot, damage: 10),
      _up(cannon, damage: 25),
      _up(
        smg,
        description: 'Rajada de 4 tiros na linha.',
        effect: const BurstEffect(4),
      ),
      _up(shotgun, damage: 15),
      _up(vShot, damage: 15),
      _up(melta, damage: 15),
      _up(missile, damage: 20),
      _up(
        baton,
        damage: 15,
        description: 'Golpeia os 3 painéis à frente e atordoa por 3 s.',
        effect: const MeleeEffect(stunTicks: 3 * ticksPerSecond),
      ),
      _up(sword, damage: 30),
      _up(shoulderBash, damage: 20),
      _up(energyWhip, damage: 20),
      _up(seismicHammer, damage: 40),
      _up(grenade, damage: 35),
      _up(incendiaryGrenade, damage: 25),
      _up(
        stunGrenade,
        description:
            'Lançada no 3º painel à frente: explode em cruz e atordoa quem '
            'for atingido por 3 s. Uso único.',
        effect: const GrenadeEffect(stunTicks: 3 * ticksPerSecond),
      ),
      _up(
        smokeGrenade,
        description:
            'Lançada no 3º painel à frente: explode em cruz e deixa Fumaça '
            'por 15 s. Quem está na Fumaça não ataca. Uso único.',
        effect: const GrenadeEffect(smokeTicks: 15 * ticksPerSecond),
      ),
      _up(
        recover,
        description: 'Recupera 15 de vida. Uso único.',
        effect: const HealEffect(15),
      ),
      _up(
        atkBoost,
        description: 'O próximo ataque causa +20 de dano.',
        effect: const DamageBoostEffect(20),
      ),
      _up(energyDrink, cost: 0),
      _up(energyTank, cost: 1),
      _up(
        powerGenerator,
        description:
            'O gauge enche 30% mais rápido até o fim da luta. Uso único.',
        effect: const GaugeSpeedEffect(30),
      ),
      _up(cracker, damage: 30),
      _up(
        bubblePush,
        damage: 15,
        description: 'Molha e empurra o alvo 2 painéis.',
        effect: const PushEffect(2, status: Status.wet),
      ),
      _up(crossFlame, damage: 20),
      _up(thunderLance, cost: 1),
      _up(
        barrier,
        description: 'Anula o próximo dano. Dura até 8 s.',
        effect: const BarrierEffect(8 * ticksPerSecond),
      ),
      _up(
        mirror,
        description:
            'Escudo à sua frente por 8 s: devolve tiros inimigos com o dobro '
            'do dano.',
        effect: const SpawnObstacleEffect(
          ObstacleKind.reflector,
          amount: 8 * ticksPerSecond,
        ),
      ),
      _up(seedGrass, cost: 0),
      _up(
        areaSteal,
        description:
            'A coluna inimiga da frente é sua por 15 s. Quem estiver nela leva '
            '10 e é empurrado.',
        effect: const AreaStealEffect(15 * ticksPerSecond, hitDamage: 10),
      ),
      _up(
        barricade,
        description:
            'Barricada de 60 HP à sua frente. Bloqueia tiros inimigos; '
            'dá para andar por ela.',
        effect: const SpawnObstacleEffect(ObstacleKind.barricade, amount: 60),
      ),
      _up(
        mine,
        description: 'Mina escondida no lado inimigo: 60 de dano.',
        effect: const SpawnObstacleEffect(ObstacleKind.mine, amount: 60),
      ),
      _up(
        turret,
        description:
            'Drone de 30 HP que atira 5 Elétrico por segundo por 15 s.',
        effect: const SpawnObstacleEffect(
          ObstacleKind.turret,
          amount: 15 * ticksPerSecond,
        ),
      ),
      _up(hook, cost: 0),
      _up(cryoGrenade, damage: 20),
      _up(emp, damage: 20),
      _up(neuralVine, damage: 25),
      _up(
        laserSight,
        description:
            'Marca o primeiro inimigo da linha: por 8 s ele leva +5 de cada '
            'acerto.',
        effect: const StatusShotEffect(Status.marked, 8 * ticksPerSecond),
      ),
      _up(overcharge, cost: 0),
      _up(
        tractorBeam,
        description:
            'Puxa 2 painéis todos os inimigos da sua linha. Quem bater em '
            'algo sofre colisão.',
        effect: const TractorEffect(steps: 2),
      ),
      _up(
        teslaCoil,
        description:
            'Bobina de 30 HP na frente do seu lado: dá um choque de 5 '
            'Elétrico no primeiro inimigo da linha a cada 1 s, por 12 s.',
        effect: const SpawnObstacleEffect(
          ObstacleKind.tesla,
          amount: 12 * ticksPerSecond,
        ),
      ),
      _up(overclock, cost: 0),
      _up(sniper, damage: 40),
      _up(incendiaryRound, damage: 15),
      _up(piercingShot, damage: 18),
      _up(
        tranqDart,
        description: 'Acerta o primeiro inimigo da linha e o atordoa por 2 s.',
        effect: const StatusShotEffect(Status.stunned, 2 * ticksPerSecond),
      ),
      _up(fragGrenade, damage: 20),
      _up(mortar, damage: 30),
      _up(fissureBomb, damage: 15),
      _up(fusionLaser, damage: 20),
      _up(freezeRay, damage: 15),
      _up(steadyBeam, damage: 7),
      _up(dagger, damage: 10),
      _up(thermalBlade, damage: 20),
      _up(scythe, damage: 20),
      _up(hydraulicFist, damage: 35),
      _up(
        fireTurret,
        description:
            'Torre de 30 HP que atira 5 de Fogo a cada 2 s por 15 s; quem é '
            'atingido fica Queimando.',
        effect: const SpawnObstacleEffect(
          ObstacleKind.turret,
          amount: 15 * ticksPerSecond,
        ),
      ),
      _up(
        minefield,
        description: '3 minas escondidas no lado inimigo: 25 de dano cada.',
        effect: const SpawnObstacleEffect(
          ObstacleKind.mine,
          amount: 25,
          count: 3,
        ),
      ),
      _up(
        stimulant,
        description: '+4 de Energia nesta mão. Uso único.',
        effect: const EnergyBurstEffect(4),
      ),
      _up(
        specialAmmo,
        description:
            'Suas cartas de Projétil causam +5 de dano até o fim da luta. Uso '
            'único.',
        effect: const ProjectileBonusEffect(5),
      ),
      _up(
        combatScan,
        description: 'Marca todos os inimigos por 5 s: cada acerto causa +5.',
        effect: const StatusAllEffect(Status.marked, 5 * ticksPerSecond),
      ),
      _up(jammer, cost: 0),
      _up(dash, damage: 25),
      _up(
        medicDrone,
        description: 'Drone de 20 HP que cura 2 de vida por segundo por 12 s.',
        effect: const SpawnObstacleEffect(
          ObstacleKind.medic,
          amount: 12 * ticksPerSecond,
        ),
      ),
      _up(
        domeGenerator,
        description: 'Anula os 4 próximos danos. Dura até 10 s.',
        effect: const BarrierEffect(10 * ticksPerSecond, charges: 4),
      ),
      _up(
        repairKit,
        description:
            'Recupera 10 de vida e remove os status negativos. Uso único.',
        effect: const CleanseEffect(10),
      ),
      _up(
        nanobots,
        description: 'Regenera 1 de vida por segundo por 20 s. Uso único.',
        effect: const SelfStatusEffect(Status.regen, 20 * ticksPerSecond),
      ),
      _up(tacticalReload, cost: 0),
      _up(resonance, damage: 7),
      _up(wildcard, cost: 0),
      _up(
        adrenaline,
        description: 'Os 3 próximos ataques causam +8 de dano. Uso único.',
        effect: const AttackChargesEffect(3, 8),
      ),
    ])
      up.id: up,
  };

  static const all = [
    shot,
    cannon,
    smg,
    shotgun,
    vShot,
    melta,
    missile,
    baton,
    sword,
    shoulderBash,
    energyWhip,
    seismicHammer,
    grenade,
    incendiaryGrenade,
    smokeGrenade,
    stunGrenade,
    recover,
    atkBoost,
    energyDrink,
    energyTank,
    powerGenerator,
    //cracker,
    //bubblePush,
    //crossFlame,
    //thunderLance,
    barrier,
    mirror,
    //seedGrass,
    areaSteal,
    barricade,
    mine,
    turret,
    hook,
    cryoGrenade,
    emp,
    neuralVine,
    laserSight,
    overcharge,
    tractorBeam,
    teslaCoil,
    overclock,
    sniper,
    incendiaryRound,
    piercingShot,
    tranqDart,
    fragGrenade,
    mortar,
    fissureBomb,
    fusionLaser,
    freezeRay,
    steadyBeam,
    dagger,
    thermalBlade,
    scythe,
    hydraulicFist,
    fireTurret,
    minefield,
    stimulant,
    specialAmmo,
    combatScan,
    jammer,
    dash,
    medicDrone,
    domeGenerator,
    repairKit,
    nanobots,
    tacticalReload,
    resonance,
    wildcard,
    adrenaline,
  ];

  /// Every card, offered or not (Bug), by id: what a saved deck
  /// is read back with.
  static final Map<String, ChipDef> _byId = {
    for (final def in const [
      shot,
      cannon,
      smg,
      shotgun,
      vShot,
      melta,
      missile,
      baton,
      sword,
      shoulderBash,
      energyWhip,
      seismicHammer,
      grenade,
      incendiaryGrenade,
      smokeGrenade,
      stunGrenade,
      recover,
      atkBoost,
      energyDrink,
      energyTank,
      powerGenerator,
      cracker,
      bubblePush,
      crossFlame,
      thunderLance,
      barrier,
      mirror,
      seedGrass,
      areaSteal,
      barricade,
      mine,
      turret,
      hook,
      cryoGrenade,
      emp,
      neuralVine,
      laserSight,
      overcharge,
      tractorBeam,
      teslaCoil,
      overclock,
      sniper,
      incendiaryRound,
      piercingShot,
      tranqDart,
      fragGrenade,
      mortar,
      fissureBomb,
      fusionLaser,
      freezeRay,
      steadyBeam,
      dagger,
      thermalBlade,
      scythe,
      hydraulicFist,
      fireTurret,
      minefield,
      stimulant,
      specialAmmo,
      combatScan,
      jammer,
      dash,
      medicDrone,
      domeGenerator,
      repairKit,
      nanobots,
      tacticalReload,
      resonance,
      wildcard,
      adrenaline,
      bug,
    ])
      def.id: def,
  };

  /// The card saved as [id], upgraded if [upgraded]; null if it no longer
  /// exists.
  static ChipDef? byId(String id, {bool upgraded = false}) =>
      upgraded ? _upgrades[id] : _byId[id];

  static List<ChipCard> starterDeck() => [
    for (var i = 0; i < 3; i++) ChipCard(shot), //ChipCard(shot),
    for (var i = 0; i < 2; i++) ChipCard(vShot), //ChipCard(vShot),
    for (var i = 0; i < 2; i++) ChipCard(shotgun), //ChipCard(shotgun),
    for (var i = 0; i < 2; i++) ChipCard(cannon), //ChipCard(cannon),
    ChipCard(smokeGrenade),
  ];
}
