/// Battle grid constants and coordinates.
///
/// Pure Dart: shared by the simulation, the Flame renderer and the Flutter UI.
library;

/// 3 rows, like the PICO-8 cart.
const int gridRows = 3;

/// The arena, left to right: 2 player columns, 2 neutral ones both sides
/// may walk on, 2 enemy columns.
const int playerColumns = 2;
const int neutralColumns = 2;
const int enemyColumns = 2;

const int gridColumns = playerColumns + neutralColumns + enemyColumns;

/// First column of the enemy side.
const int enemyColumn0 = playerColumns + neutralColumns;

/// [Team.neutral] only owns panels: both sides may walk on them.
enum Team { player, enemy, neutral }

/// Immutable cell coordinate. `x` grows toward the enemy side, `y` downward.
class GridPos {
  const GridPos(this.x, this.y);

  final int x;
  final int y;

  GridPos operator +(GridPos other) => GridPos(x + other.x, y + other.y);

  bool get inBounds => x >= 0 && x < gridColumns && y >= 0 && y < gridRows;

  /// Side this cell starts the battle on. Columns can change hands during a
  /// battle, so live ownership is `BattleState.ownerAt`.
  Team get homeSide => x < playerColumns
      ? Team.player
      : x < enemyColumn0
      ? Team.neutral
      : Team.enemy;

  @override
  bool operator ==(Object other) =>
      other is GridPos && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// Whether a unit of [unitTeam] may stand on a panel owned by [owner]:
/// on its own side or a neutral one. Units with no team (rocks) go anywhere.
bool canStand(Team? unitTeam, Team owner) =>
    unitTeam == null || owner == unitTeam || owner == Team.neutral;
