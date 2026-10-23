import '../grid.dart';
import 'battle_state.dart' show ticksPerSecond;

enum PanelState { normal, cracked, hole, ice, grass, lava }

/// Cracked panels heal after this long with nobody on them.
const int crackedTicks = 15 * ticksPerSecond;
const int holeTicks = 10 * ticksPerSecond;
const int iceTicks = 8 * ticksPerSecond;
const int grassTicks = 15 * ticksPerSecond;

const int grassHeal = 1;
const int lavaDamage = 5;

/// Electric hit on a unit standing on ice.
const int iceStunTicks = ticksPerSecond;

/// Wood chip used from grass, or a Fire unit attacking from lava: +30%.
const double terrainBoost = 1.3;

/// One panel of the grid. The battle owns a 6x3 matrix of these.
class Panel {
  Panel(this.owner);

  PanelState state = PanelState.normal;

  /// Side the panel currently belongs to (see [GridPos.homeSide]).
  Team owner;

  /// Ticks until [owner] goes back to the home side; 0 = permanent.
  int ownerTimer = 0;

  /// Damage of the hidden mine here, which explodes on whoever steps on it;
  /// 0 = no mine.
  int mineDamage = 0;

  bool get mine => mineDamage > 0;

  /// Ticks until the panel turns back to [PanelState.normal]. Unused for
  /// normal and lava, which never revert on their own.
  int timer = 0;

  /// Nobody can stand on a hole; projectiles fly over it.
  bool get walkable => state != PanelState.hole;

  /// Default return time for [state], or 0 if it never reverts.
  static int defaultTicks(PanelState state) => switch (state) {
    PanelState.cracked => crackedTicks,
    PanelState.hole => holeTicks,
    PanelState.ice => iceTicks,
    PanelState.grass => grassTicks,
    PanelState.normal || PanelState.lava => 0,
  };
}
