import '../battle/battle_state.dart' show ObstacleKind, Status;
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
  });

  final List<GridPos> pattern;
  final int stunTicks;
  final int push;
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

  final int fromColumn;

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
  const SpawnObstacleEffect(this.kind, {this.amount, this.count = 1});

  final ObstacleKind kind;

  /// How many mines (Campo Minado).
  final int count;

  /// Overrides the kind's default: rock HP, mine damage, or how many ticks
  /// a turret, reflector or tesla coil lasts.
  final int? amount;
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
    this.element = Element.neutral,
    this.pose = ChipPose.shoot,
    this.exhaust = false,
    this.upgraded = false,
    this.rarity = Rarity.common,
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
  final Element element;
  final ChipPose pose;

  /// Single use per battle: once used, the card leaves the battle's deck
  /// instead of going to the discard pile.
  final bool exhaust;

  /// The "+" version from a campfire (see `Chips.upgradeOf`). It keeps the
  /// [id] of the card it came from.
  final bool upgraded;

  /// How often it is offered and its shop price.
  final Rarity rarity;
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
