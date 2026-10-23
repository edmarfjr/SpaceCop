import '../battle/battle_state.dart';
import '../battle/panels.dart';
import '../element.dart';
import '../grid.dart';
import 'battle_chip.dart';

/// Every card in the game. Ported from the `--cartas` tab of the cart.
abstract final class Chips {
  static const shot = ChipDef(
    id: 'shot',
    name: 'Revolver',
    description: 'Acerta o primeiro inimigo da linha.',
    cost: 0,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 5,
    effect: ProjectileEffect(),
  );

  static const cannon = ChipDef(
    id: 'cannon',
    name: 'Canhão',
    description: 'Acerta o primeiro inimigo da linha.',
    cost: 1,
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
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 5,
    effect: BurstEffect(3),
  );

  static const shotgun = ChipDef(
    id: 'shotgun',
    name: 'Bala Perfurante',
    description: 'Atravessa: acerta o alvo e a célula atrás dele.',
    cost: 1,
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
    description: 'Golpeia os 3 painéis à frente e atordoa por 2 s.',
    cost: 1,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 10,
    element: Element.elec,
    effect: MeleeEffect(stunTicks: 2 * ticksPerSecond),
    pose: ChipPose.melee,
  );

  static const sword = ChipDef(
    id: 'sword',
    name: 'Espada',
    description: 'Golpeia os 3 painéis à frente.',
    cost: 1,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 20,
    effect: MeleeEffect(),
    pose: ChipPose.melee,
  );

  static const recover = ChipDef(
    id: 'recover',
    name: 'Primeiros Socorros',
    description: 'Recupera 5 de vida. Uso único.',
    cost: 2,
    type: ChipType.recovery,
    target: ChipTarget.self,
    effect: HealEffect(5),
    exhaust: true,
  );

  static const atkBoost = ChipDef(
    id: 'atk_boost',
    name: 'Bala Oca',
    description: 'O próximo ataque causa +10 de dano.',
    cost: 1,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: DamageBoostEffect(10),
  );

  static const energyDrink = ChipDef(
    id: 'energy_drink',
    name: 'Energético',
    description: '+2 de Energia nesta mão.',
    cost: 1,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: EnergyBurstEffect(2),
  );

  static const energyTank = ChipDef(
    id: 'energy_tank',
    name: 'Tanque de Energia',
    description: '+1 de Energia máxima até o fim da luta. Uso único.',
    cost: 2,
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
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 10,
    element: Element.aqua,
    effect: PushEffect(1, status: Status.wet),
  );

  static const crossFlame = ChipDef(
    id: 'cross_flame',
    name: 'Chama Cruzada',
    description: 'Explode em cruz no alvo. Queima Grama.',
    cost: 2,
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
    cost: 3,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 15,
    element: Element.elec,
    effect: RowStrikeEffect(),
  );

  static const barrier = ChipDef(
    id: 'barrier',
    name: 'Escudo de Energia',
    description: 'Anula o próximo dano. Dura até 5 s.',
    cost: 2,
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
    type: ChipType.support,
    target: ChipTarget.self,
    effect: SpawnObstacleEffect(ObstacleKind.reflector),
  );

  static const seedGrass = ChipDef(
    id: 'seed_grass',
    name: 'Semear Grama',
    description: 'Seus painéis viram Grama por 15 s.',
    cost: 1,
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
    type: ChipType.support,
    target: ChipTarget.self,
    effect: AreaStealEffect(10 * ticksPerSecond, hitDamage: 5),
  );

  static const rock = ChipDef(
    id: 'rock',
    name: 'Rocha',
    description: 'Rocha de 40 HP à sua frente. Bloqueia tiros.',
    cost: 1,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: SpawnObstacleEffect(ObstacleKind.rock),
    pose: ChipPose.toss,
  );

  static const mine = ChipDef(
    id: 'mine',
    name: 'Mina',
    description: 'Mina escondida no lado inimigo: 40 de dano.',
    cost: 1,
    type: ChipType.attack,
    target: ChipTarget.self,
    effect: SpawnObstacleEffect(ObstacleKind.mine),
    pose: ChipPose.toss,
  );

  static const turret = ChipDef(
    id: 'turret',
    name: 'Drone',
    description: 'Drone que atira 5 Elétrico por segundo por 10 s.',
    cost: 3,
    type: ChipType.attack,
    target: ChipTarget.self,
    element: Element.elec,
    effect: SpawnObstacleEffect(ObstacleKind.turret),
  );

  static const hook = ChipDef(
    id: 'hook',
    name: 'Gancho',
    description: 'Puxa o primeiro alvo da linha para a frente.',
    cost: 1,
    type: ChipType.support,
    target: ChipTarget.row,
    effect: PullEffect(),
    pose: ChipPose.melee,
  );

  /// Junk from the Nave à Deriva event. Never offered as a reward.
  static const bug = ChipDef(
    id: 'bug',
    name: 'Bug',
    description: 'Não faz nada.',
    cost: 0,
    type: ChipType.support,
    target: ChipTarget.self,
    effect: NoEffect(),
  );

  static const storm = ChipDef(
    id: 'storm',
    name: 'Tempestade',
    description: 'Molha o lado inimigo e cai 20 Elétrico em cada painel.',
    cost: 0,
    type: ChipType.attack,
    target: ChipTarget.self,
    damage: 20,
    element: Element.elec,
    effect: StormEffect(),
  );

  static const avalanche = ChipDef(
    id: 'avalanche',
    name: 'Avalanche',
    description: 'Rocha rola pela linha, racha os painéis e empurra o alvo.',
    cost: 0,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 40,
    effect: AvalancheEffect(),
    pose: ChipPose.toss,
  );

  static const magnetTrap = ChipDef(
    id: 'magnet_trap',
    name: 'Armadilha Magnética',
    description: 'Puxa o primeiro inimigo da linha e detona.',
    cost: 0,
    type: ChipType.attack,
    target: ChipTarget.row,
    damage: 50,
    effect: MagnetTrapEffect(),
    pose: ChipPose.melee,
  );

  /// Chips that fuse when held together, and what they become. Fusions are
  /// never drawn: they only exist for the moment they are used.
  static const fusions = [
    (bubblePush, thunderLance, storm),
    (cracker, rock, avalanche),
    (hook, mine, magnetTrap),
  ];

  static final fusionPairs = [for (final (a, b, _) in fusions) (a, b)];

  /// What [a] and [b] fuse into, in either order. Upgraded cards fuse like
  /// their base card.
  static ChipDef? fusionOf(ChipDef a, ChipDef b) {
    for (final (x, y, result) in fusions) {
      if ((a.id == x.id && b.id == y.id) || (a.id == y.id && b.id == x.id)) {
        return result;
      }
    }
    return null;
  }

  /// The "+" version of [def], or null if it can't be upgraded (already
  /// upgraded, Bug, fusions).
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
    type: base.type,
    target: base.target,
    effect: effect ?? base.effect,
    damage: damage ?? base.damage,
    element: base.element,
    pose: base.pose,
    exhaust: base.exhaust,
    upgraded: true,
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
      _up(
        recover,
        description: 'Recupera 10 de vida. Uso único.',
        effect: const HealEffect(10),
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
      _up(thunderLance, cost: 2),
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
        rock,
        description: 'Rocha de 60 HP à sua frente. Bloqueia tiros.',
        effect: const SpawnObstacleEffect(ObstacleKind.rock, amount: 60),
      ),
      _up(
        mine,
        description: 'Mina escondida no lado inimigo: 60 de dano.',
        effect: const SpawnObstacleEffect(ObstacleKind.mine, amount: 60),
      ),
      _up(
        turret,
        description: 'Drone que atira 5 Elétrico por segundo por 15 s.',
        effect: const SpawnObstacleEffect(
          ObstacleKind.turret,
          amount: 15 * ticksPerSecond,
        ),
      ),
      _up(hook, cost: 0),
    ])
      up.id: up,
  };

  static const all = [
    shot,
    smg,
    shotgun,
    vShot,
    melta,
    missile,
    baton,
    sword,
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
    rock,
    mine,
    turret,
    hook,
  ];

  /// Same starter deck as the cart: 4 Revolvers, 2 Plasmas, 2 Balas
  /// Perfurantes, 2 Canhões.
  static List<ChipCard> starterDeck() => [
    for (var i = 0; i < 4; i++) ChipCard(shot),
    for (var i = 0; i < 2; i++) ChipCard(vShot),
    for (var i = 0; i < 2; i++) ChipCard(shotgun),
    for (var i = 0; i < 2; i++) ChipCard(cannon),
  ];
}
