/// Battle grid constants and coordinates.
///
/// Pure Dart: shared by the simulation, the Flame renderer and the Flutter UI.
library;

/// 6 columns x 3 rows, like the PICO-8 cart.
const int gridColumns = 6;
const int gridRows = 3;

/// Columns `0 until playerColumns` belong to the player, the rest to enemies.
const int playerColumns = 3;

enum Team { player, enemy }

/// Immutable cell coordinate. `x` grows toward the enemy side, `y` downward.
class GridPos {
  const GridPos(this.x, this.y);

  final int x;
  final int y;

  GridPos operator +(GridPos other) => GridPos(x + other.x, y + other.y);

  bool get inBounds => x >= 0 && x < gridColumns && y >= 0 && y < gridRows;

  /// Side this cell starts the battle on. Columns can change hands during a
  /// battle, so live ownership is `BattleState.ownerAt`.
  Team get homeSide => x < playerColumns ? Team.player : Team.enemy;

  @override
  bool operator ==(Object other) =>
      other is GridPos && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}
