import '../battle/battle_state.dart' show ObstacleKind, Status;
import '../battle/panels.dart';
import '../element.dart';
import '../grid.dart';

/// Broad category, used by the UI (card color) and by future rules
/// (e.g. "attack chips cost +1 in this elite fight").
enum ChipType { attack, support, recovery }

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
  const ProjectileEffect({this.pattern = const [GridPos(0, 0)]});

  final List<GridPos> pattern;
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
/// front), stunning whoever it hits for [stunTicks].
class MeleeEffect extends ChipEffect {
  const MeleeEffect({
    this.pattern = const [GridPos(1, -1), GridPos(1, 0), GridPos(1, 1)],
    this.stunTicks = 0,
  });

  final List<GridPos> pattern;
  final int stunTicks;
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
  const PullEffect();
}

/// Instant hit on every cell of the user's row from column [fromColumn] on.
class RowStrikeEffect extends ChipEffect {
  const RowStrikeEffect({this.fromColumn = 3});

  final int fromColumn;
}

/// For at most [ticks], cancels the next damage the user would take.
class BarrierEffect extends ChipEffect {
  const BarrierEffect(this.ticks);

  final int ticks;
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

/// Places a rock, mine, turret or reflector. Where depends on the kind.
class SpawnObstacleEffect extends ChipEffect {
  const SpawnObstacleEffect(this.kind, {this.amount});

  final ObstacleKind kind;

  /// Overrides the kind's default: rock HP, mine damage, or how many ticks
  /// a turret or reflector lasts.
  final int? amount;
}

/// Does nothing; it only wastes a slot of the hand (chip Bug).
class NoEffect extends ChipEffect {
  const NoEffect();
}

/// Fusion: Wet on the whole enemy side, then an Elec strike on every enemy
/// panel (Tempestade).
class StormEffect extends ChipEffect {
  const StormEffect();
}

/// Fusion: a rock rolls down the row, cracking the panels it crosses, and
/// hits the first target, pushing it 1 cell (Avalanche).
class AvalancheEffect extends ChipEffect {
  const AvalancheEffect();
}

/// Fusion: drags the first enemy of the row to column 3 and blows up on it
/// (Armadilha Magnética).
class MagnetTrapEffect extends ChipEffect {
  const MagnetTrapEffect();
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
    required this.type,
    required this.target,
    required this.effect,
    this.damage = 0,
    this.element = Element.neutral,
    this.pose = ChipPose.shoot,
    this.exhaust = false,
    this.upgraded = false,
  });

  final String id;
  final String name;
  final String description;

  /// Energy spent to use the chip in battle (0 to 3).
  final int cost;
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
