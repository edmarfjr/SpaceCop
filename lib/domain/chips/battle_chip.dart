import '../battle/battle_state.dart' show ObstacleKind, Status;
import '../battle/enemies.dart' show EnemyKind;
import '../battle/panels.dart';
import '../element.dart';
import '../grid.dart';
import '../rarity.dart';

export '../rarity.dart' show Rarity;

/// Broad category, used by the UI (card color) and by future rules
/// (e.g. "attack chips cost +1 in this elite fight").
enum ChipType { attack, support, recovery }

/// What kind of gear the card is. Damage families keep a chain going (3 of
/// the same in a row); the others leave the chain as it is.
enum ChipFamily {
  projectile,
  explosive,
  energy,
  melee,
  equipment,
  consumable,
  tactical;

  /// Name shown in game.
  String get label => switch (this) {
    ChipFamily.projectile => 'Projétil',
    ChipFamily.explosive => 'Explosivo',
    ChipFamily.energy => 'Energia',
    ChipFamily.melee => 'Corpo-a-corpo',
    ChipFamily.equipment => 'Equipamento',
    ChipFamily.consumable => 'Consumível',
    ChipFamily.tactical => 'Tático',
  };

  /// Builds and keeps chains.
  bool get chains => switch (this) {
    ChipFamily.projectile ||
    ChipFamily.explosive ||
    ChipFamily.energy ||
    ChipFamily.melee => true,
    _ => false,
  };
}

/// Who the chip is aimed at.
enum ChipTarget {
  /// Affects the user (heal, buffs).
  self,

  /// Travels along the user's row and hits the first opponent in it.
  row,
}

/// What a chip does when used. Sealed so the battle must handle every case.
sealed class ChipEffect {
  const ChipEffect();
}

/// Fires a projectile along the row. On impact, every cell in [pattern]
/// takes damage. Offsets are relative to the impact cell, written from the
/// player's point of view (+x = away from the shooter).
class ProjectileEffect extends ChipEffect {
  const ProjectileEffect({
    this.pattern = const [GridPos(0, 0)],
    this.farBonus = 0,
  });

  final List<GridPos> pattern;

  /// Extra damage when the first target stands in the back column (Rifle
  /// de Precisão).
  final int farBonus;
}

class HealEffect extends ChipEffect {
  const HealEffect(this.amount);

  final int amount;
}

/// Adds damage to the next projectile fired.
class DamageBoostEffect extends ChipEffect {
  const DamageBoostEffect(this.amount);

  final int amount;
}

/// Extra energy for the current hand only.
class EnergyBurstEffect extends ChipEffect {
  const EnergyBurstEffect(this.amount);

  final int amount;
}

/// Raises the energy restored on each refill until the battle ends.
class EnergyMaxEffect extends ChipEffect {
  const EnergyMaxEffect(this.amount);

  final int amount;
}

/// The gauge fills [percent]% faster until the battle ends.
class GaugeSpeedEffect extends ChipEffect {
  const GaugeSpeedEffect(this.percent);

  final int percent;
}

/// [count] single shots down the row, [gapTicks] apart.
class BurstEffect extends ChipEffect {
  const BurstEffect(this.count, {this.gapTicks = 4});

  final int count;
  final int gapTicks;
}

/// Instant hit on the cells of [pattern], relative to the user (+x = in
/// front), stunning whoever it hits for [stunTicks] and pushing them
/// [push] panels away. With [crack] the panels hit crack.
class MeleeEffect extends ChipEffect {
  const MeleeEffect({
    this.pattern = const [GridPos(1, -1), GridPos(1, 0), GridPos(1, 1)],
    this.stunTicks = 0,
    this.push = 0,
    this.crack = false,
    this.slash = false,
    this.inflict,
    this.tipPush = 0,
    this.tipPull = 0,
    this.recoil = 0,
    this.lifesteal = false,
  });

  final List<GridPos> pattern;
  final int stunTicks;
  final int push;

  /// Panels pushed, only for whoever stands on the last panel of
  /// [pattern] (Arma de Haste).
  final int tipPush;

  /// Panels pulled toward the user, only for whoever stands on the last
  /// panel of [pattern] (Chicote de Energia).
  final int tipPull;

  /// Panels the user steps back after the blow (Salto Acrobático).
  final int recoil;

  /// The user heals half the damage dealt (Lâmina Vampírica).
  final bool lifesteal;
  final bool crack;

  /// Given to whoever is hit, for its default time (Lâmina Térmica burns).
  final Status? inflict;

  /// Shown as one vertical slash on the panel in front instead of an
  /// explosion on each panel hit (Espada).
  final bool slash;
}

/// Lobbed [distance] panels in front of the user, wherever the enemies
/// are. On landing every cell of [pattern] (relative to the landing panel)
/// takes damage, the landing panel turns into [panel] if one is given and
/// gets a smoke cloud for [smokeTicks] if positive, and whoever is hit is
/// stunned for [stunTicks] and Wet for [wetTicks] if positive.
class GrenadeEffect extends ChipEffect {
  const GrenadeEffect({
    this.distance = 3,
    this.pattern = const [
      GridPos(0, 0),
      GridPos(1, 0),
      GridPos(-1, 0),
      GridPos(0, 1),
      GridPos(0, -1),
    ],
    this.panel,
    this.smokeTicks = 0,
    this.stunTicks = 0,
    this.wetTicks = 0,
    this.shieldTicks = 0,
    this.crack = false,
    this.homing = false,
    this.backColumn = false,
    this.implode = false,
  });

  final int distance;
  final List<GridPos> pattern;
  final PanelState? panel;
  final int smokeTicks;
  final int stunTicks;
  final int wetTicks;

  /// Front shields in the blast stay down this long (Pulso EMP).
  final int shieldTicks;

  /// Every panel of the blast cracks (Bomba de Fissura).
  final bool crack;

  /// Lands on the enemy with the least HP instead (Foguete Teleguiado).
  final bool homing;

  /// Lands on the middle of the back column instead, after a warning, and
  /// every panel of [pattern] takes full damage (Morteiro).
  final bool backColumn;

  /// Whoever is caught off the center is pulled 1 panel toward it
  /// (Granada de Gravidade).
  final bool implode;
}

/// Projectile that, on hitting, also hits another enemy for the same
/// damage: one next to the target with [adjacent] (Arco Voltaico), any
/// other otherwise (Ricochete).
class BounceEffect extends ChipEffect {
  const BounceEffect({this.adjacent = false});

  final bool adjacent;
}

/// Thrown [distance] panels ahead, where it lies as a Dinamite: [fuse]
/// later it blows up in a cross, half damage off the center (TNT).
class DynamiteEffect extends ChipEffect {
  /// [fuse] in ticks: 2 s.
  const DynamiteEffect({this.distance = 3, this.fuse = 60});

  final int distance;
  final int fuse;
}

/// Sticks to the first enemy of the row; [delay] later it blows up in a
/// cross wherever that enemy is (Carga C4).
class StickyBombEffect extends ChipEffect {
  const StickyBombEffect(this.delay);

  final int delay;
}

/// The next [count] shooting cards land straight on the enemy with the
/// least HP (Mira Assistida).
class HomingEffect extends ChipEffect {
  const HomingEffect(this.count);

  final int count;
}

/// Projectile that cracks the panel under the first target it hits.
class CrackEffect extends ChipEffect {
  const CrackEffect();
}

/// Projectile that pushes the first target hit [steps] cells away from the
/// user, optionally applying [status].
class PushEffect extends ChipEffect {
  const PushEffect(this.steps, {this.status});

  final int steps;
  final Status? status;
}

/// Projectile that pushes the first target hit 1 panel back; one already
/// at the back takes a collision and is thrown 1 panel forward. The spear
/// then sticks in the impact panel, or in the last panel of the row on a
/// miss (Lança): enemies can't walk through it, shots fly past.
class SpearEffect extends ChipEffect {
  const SpearEffect();
}

/// Projectile that drags the first target hit to the front enemy column
/// (x = 3). A target already there is stunned instead.
class PullEffect extends ChipEffect {
  const PullEffect({this.stunTicks = 0});

  /// The target is also stunned this long, if positive.
  final int stunTicks;
}

/// Projectile that gives the first target hit [status] for [ticks]
/// (Vinha Neural roots, Mira Laser marks).
class StatusShotEffect extends ChipEffect {
  const StatusShotEffect(this.status, this.ticks, {this.panel});

  final Status status;
  final int ticks;

  /// The target's panel turns into this (Raio Congelante: Gelo).
  final PanelState? panel;
}

/// Every enemy on the field gets [status] for [ticks] (Análise de Combate,
/// Interferência).
class StatusAllEffect extends ChipEffect {
  const StatusAllEffect(this.status, this.ticks);

  final Status status;
  final int ticks;
}

/// Projectile cards deal [amount] more until the battle ends (Munição
/// Especial).
class ProjectileBonusEffect extends ChipEffect {
  const ProjectileBonusEffect(this.amount);

  final int amount;
}

/// Pulls every enemy of the user's row [steps] panels forward, front one
/// first; whoever runs into something collides (Feixe Trator).
class TractorEffect extends ChipEffect {
  const TractorEffect({this.steps = 1});

  final int steps;
}

/// Projectile whose damage is multiplied by its place in the chain: 1st,
/// 2nd or 3rd card (Pulso Ressonante).
class ChainScaleEffect extends ChipEffect {
  const ChainScaleEffect();
}

/// The next chaining card counts as the family of the chain in progress
/// (Coringa).
class WildcardEffect extends ChipEffect {
  const WildcardEffect();
}

/// The next [count] attacks deal [amount] more (Adrenalina).
class AttackChargesEffect extends ChipEffect {
  const AttackChargesEffect(this.count, this.amount);

  final int count;
  final int amount;
}

/// The next chip used counts twice in the chain (Sobrecarga).
class ChainSurgeEffect extends ChipEffect {
  const ChainSurgeEffect();
}

/// The next chip used runs twice; only the first pays energy (Overclock).
class RepeatNextEffect extends ChipEffect {
  const RepeatNextEffect();
}

/// Instant hit on every cell of the user's row from column [fromColumn] on.
class RowStrikeEffect extends ChipEffect {
  const RowStrikeEffect({this.fromColumn = 3, this.panel});

  /// The whole row ahead of the player (Melta).
  const RowStrikeEffect.ahead() : fromColumn = null, panel = null;

  /// First column hit; null: the one in front of the player.
  final int? fromColumn;

  /// The first enemy's panel turns into this (Laser de Fusão: Lava).
  final PanelState? panel;
}

/// For at most [ticks], cancels the next damage the user would take.
class BarrierEffect extends ChipEffect {
  const BarrierEffect(this.ticks, {this.charges = 1});

  final int ticks;

  /// How many hits it cancels before it goes down (Gerador de Domo).
  final int charges;
}

/// The user dashes to the front of their side, then hits like [melee]
/// (Investida).
class DashEffect extends ChipEffect {
  const DashEffect(this.melee);

  final MeleeEffect melee;
}

/// Heals [heal] and clears every harmful status (Kit de Reparos).
class CleanseEffect extends ChipEffect {
  const CleanseEffect(this.heal);

  final int heal;
}

/// The user gets [status] for [ticks] (Nanobots: Regenerando).
class SelfStatusEffect extends ChipEffect {
  const SelfStatusEffect(this.status, this.ticks);

  final Status status;
  final int ticks;
}

/// Draws [count] cards into the hand, up to [maxHand] (Recarga Tática).
class DrawEffect extends ChipEffect {
  const DrawEffect(this.count);

  final int count;
}

/// Turns every panel on the user's side into [state] (holes excluded).
class PanelChangeEffect extends ChipEffect {
  const PanelChangeEffect(this.state);

  final PanelState state;
}

/// The front enemy column becomes the player's for [ticks]. Enemies standing
/// in it take [hitDamage] and are pushed back 1 panel; a panel one of them
/// still stands on stays theirs.
class AreaStealEffect extends ChipEffect {
  const AreaStealEffect(this.ticks, {required this.hitDamage});

  final int ticks;
  final int hitDamage;
}

/// Places a rock, mine, turret, reflector or tesla coil. Where depends on
/// the kind.
class SpawnObstacleEffect extends ChipEffect {
  const SpawnObstacleEffect(
    this.kind, {
    this.amount,
    this.count = 1,
    this.status,
  });

  final ObstacleKind kind;

  /// What a turret's shots inflict (Torre Incendiária).
  final Status? status;

  /// How many mines (Campo Minado).
  final int count;

  /// Overrides the kind's default: rock HP, mine damage, or how many ticks
  /// a turret, reflector or tesla coil lasts.
  final int? amount;
}

/// Projectile dealing [bonus] more to a target under [threshold] of its
/// max HP (Tiro de Execução).
class ExecuteEffect extends ChipEffect {
  const ExecuteEffect({this.threshold = 0.3, this.bonus = 20});

  final double threshold;
  final int bonus;
}

/// Projectile dealing [step] more for each time the card was used before
/// in this battle (Bala Acumulativa).
class StackingShotEffect extends ChipEffect {
  const StackingShotEffect(this.step);

  final int step;
}

/// Projectile that stuns a Wet target for [stunTicks] (Descarga
/// Estática).
class WetShockEffect extends ChipEffect {
  const WetShockEffect(this.stunTicks);

  final int stunTicks;
}

/// Projectile; on a Wet target the hit jumps to every other Wet enemy
/// (Condutor).
class ConductorEffect extends ChipEffect {
  const ConductorEffect();
}

/// Projectile that keeps an Etéreo it hits solid for [ticks] (Ancoragem
/// Quântica).
class AnchorEffect extends ChipEffect {
  const AnchorEffect(this.ticks);

  final int ticks;
}

/// Instant hit on every enemy of [kind], anywhere (Sobrecarga de Rede).
class KindStrikeEffect extends ChipEffect {
  const KindStrikeEffect(this.kind);

  final EnemyKind kind;
}

/// Instant hit on the first enemy of each row (Laser de Varredura).
class SweepEffect extends ChipEffect {
  const SweepEffect();
}

/// Every Burning enemy takes the card's damage and stops burning
/// (Detonador).
class DetonateEffect extends ChipEffect {
  const DetonateEffect();
}

/// For [ticks], the next hit on the user is cancelled and the first enemy
/// of their row takes the card's damage (Aparar).
class ParryEffect extends ChipEffect {
  const ParryEffect(this.ticks);

  final int ticks;
}

/// [count] copies of the card [chipId] join the hand for this battle only
/// (Kit de Munição).
class AddCardsEffect extends ChipEffect {
  const AddCardsEffect(this.chipId, this.count);

  final String chipId;
  final int count;
}

/// The last card used comes back from the discard pile to the hand
/// (Cápsula de Reciclagem).
class RecycleEffect extends ChipEffect {
  const RecycleEffect();
}

/// The energy left at the end of this hand carries to the next (Bateria
/// Reserva).
class CarryEnergyEffect extends ChipEffect {
  const CarryEnergyEffect();
}

/// Every card of the next hand costs [amount] less (Estabilizador).
class DiscountNextHandEffect extends ChipEffect {
  const DiscountNextHandEffect(this.amount);

  final int amount;
}

/// The enemy panels of the user's row turn into [state] (Spray
/// Congelante).
class EnemyRowPanelEffect extends ChipEffect {
  const EnemyRowPanelEffect(this.state);

  final PanelState state;
}

/// Cracked panels and holes on the user's side turn back to normal
/// (Plataforma de Reparo).
class RepairPanelsEffect extends ChipEffect {
  const RepairPanelsEffect();
}

/// The user's panel fills the gauge [percent]% faster while they stand on
/// it, for [ticks] (Placa de Recarga).
class ChargePadEffect extends ChipEffect {
  const ChargePadEffect(this.ticks, {this.percent = 50});

  final int ticks;
  final int percent;
}

/// Every enemy is pushed [steps] panels back, back ones first (Ordem de
/// Retirada).
class PushAllEffect extends ChipEffect {
  const PushAllEffect({this.steps = 1});

  final int steps;
}

/// For [ticks], the damage the user takes is halved (Leitura de Padrão).
class GuardEffect extends ChipEffect {
  const GuardEffect(this.ticks);

  final int ticks;
}

/// Heals [urgent] when the user has under [threshold] of their max HP,
/// else [normal] (Seringa de Emergência).
class EmergencyHealEffect extends ChipEffect {
  const EmergencyHealEffect({
    this.threshold = 0.3,
    this.urgent = 25,
    this.normal = 5,
  });

  final double threshold;

  /// Healed under [threshold].
  final int urgent;

  /// Healed otherwise.
  final int normal;
}

/// Does nothing when used, and hurts the player when drawn (Sussurro).
class WhisperEffect extends ChipEffect {
  const WhisperEffect();
}

/// Does nothing; it only wastes a slot of the hand (chip Bug).
class NoEffect extends ChipEffect {
  const NoEffect();
}

/// Immutable chip design (the "card"). Never mutated during a battle.
/// How the player is drawn using a chip: firing (attack frame and muzzle
/// flash), or swinging / tossing (the melee frame).
enum ChipPose {
  shoot,
  melee,

  /// Lobbed at its target cell; the effect happens when it lands.
  toss,
}

/// Extra look of a card in battle. Purely visual.
enum ChipFx {
  none,

  /// Lightning from the hand to the shot, then from target to target on a
  /// jump (Arco Voltaico).
  bolt,

  /// A beam from the hand down the row in the card's element color: while
  /// a burst lasts, in place of its shots (Feixe Contínuo), or a flash
  /// through the whole row on a row strike (Melta, Lança Trovão...).
  beam,

  /// Explosions in the card's element color (the grenades).
  blast,

  /// Blue explosions (Pulso EMP).
  pulse,

  /// A white streak from the target to whoever the shot bounces to
  /// (Ricochete).
  tracer,

  /// A short slash on each panel hit, slanted toward it (Foice).
  cut,

  /// Shakes the screen on impact (Martelo Sísmico, Punho Hidráulico,
  /// Morteiro).
  quake,

  /// A smoke trail behind the shot or the lob (Míssil, Foguete
  /// Teleguiado).
  smoke,

  /// A white streak down the row as it fires (Rifle de Precisão).
  sniper,

  /// Drawn as a flying spear instead of a bullet (Lança).
  spear,

  /// Static over the enemies while it lasts (Interferência).
  glitch,

  /// Rings out of the hand, one per place in the chain (Pulso Ressonante).
  rings,
}

class ChipDef {
  const ChipDef({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.family,
    required this.type,
    required this.target,
    required this.effect,
    this.damage = 0,
    this.pose = ChipPose.shoot,
    this.exhaust = false,
    this.upgraded = false,
    this.rarity = Rarity.common,
    this.fx = ChipFx.none,
  });

  final String id;
  final String name;
  final String description;

  /// Energy spent to use the chip in battle (0 to 3).
  final int cost;
  final ChipFamily family;
  final ChipType type;
  final ChipTarget target;
  final ChipEffect effect;
  final int damage;
  final ChipPose pose;

  /// Color and sound of the card's shots and blasts, from what it inflicts
  /// or the panel it leaves. Purely cosmetic: cards have no element.
  Element get tint => switch (effect) {
    StatusShotEffect(status: Status.burning) ||
    MeleeEffect(inflict: Status.burning) ||
    PushEffect(status: Status.burning) ||
    SpawnObstacleEffect(status: Status.burning) ||
    GrenadeEffect(panel: PanelState.lava) ||
    RowStrikeEffect(panel: PanelState.lava) => Element.fire,
    StatusShotEffect(status: Status.wet) ||
    PushEffect(status: Status.wet) ||
    GrenadeEffect(panel: PanelState.ice) ||
    GrenadeEffect(wetTicks: > 0) => Element.aqua,
    StatusShotEffect(status: Status.rooted) ||
    PanelChangeEffect(state: PanelState.grass) => Element.wood,
    StatusShotEffect(status: Status.stunned) ||
    MeleeEffect(inflict: Status.stunned) ||
    MeleeEffect(stunTicks: > 0) ||
    GrenadeEffect(stunTicks: > 0) ||
    PullEffect(stunTicks: > 0) => Element.elec,
    _ => Element.neutral,
  };

  /// Single use per battle: once used, the card leaves the battle's deck
  /// instead of going to the discard pile.
  final bool exhaust;

  /// The "+" version from a campfire (see `Chips.upgradeOf`). It keeps the
  /// [id] of the card it came from.
  final bool upgraded;

  /// How often it is offered and its shop price.
  final Rarity rarity;

  final ChipFx fx;
}

/// One copy of a chip in the player's deck.
///
/// Copies of the same [def] are distinct objects so the deck can move each
/// one between piles independently (and later hold per-copy upgrades).
class ChipCard {
  ChipCard(this.def) : uid = _nextUid++;

  static int _nextUid = 0;

  final int uid;
  final ChipDef def;

  @override
  String toString() => '${def.id}#$uid';
}
