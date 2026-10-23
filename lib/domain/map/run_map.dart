import 'dart:math';

/// Node kinds. Types 1..5 of the cart, inferred from its map sprites 64..68
/// (creature, "?", horned creature, campfire, bag), plus the boss on top.
enum NodeType { battle, event, elite, rest, shop, boss }

class MapNode {
  MapNode(this.x, this.floor);

  final int x;
  final int floor;

  /// Null means no path goes through this cell.
  NodeType? type;

  /// Columns reachable on the next floor.
  final Set<int> next = {};

  bool visited = false;

  bool get isUsed => type != null;
}

/// Slay the Spire style map: [columns] x [floorCount] cells, a boss on top.
class RunMap {
  RunMap(this.floors, this.boss);

  static const int columns = 7;
  static const int floorCount = 16;

  /// `floors[floor][x]`. Unused cells have `type == null`.
  final List<List<MapNode>> floors;
  final MapNode boss;

  Iterable<MapNode> get usedNodes =>
      floors.expand((floor) => floor).where((n) => n.isUsed);

  List<MapNode> get startNodes => floors.first.where((n) => n.isUsed).toList();

  List<MapNode> nextOf(MapNode node) {
    if (node.type == NodeType.boss) return const [];
    if (node.floor == floorCount - 1) return [boss];
    return [for (final x in node.next) floors[node.floor + 1][x]];
  }
}

/// Port of `gera_mapa`: [paths] random walks from the bottom floor upward,
/// each step going to x-1, x or x+1 without crossing an existing edge.
class MapGenerator {
  MapGenerator({Random? random, this.paths = 6}) : _random = random ?? Random();

  final Random _random;
  final int paths;

  RunMap generate() {
    final floors = [
      for (var f = 0; f < RunMap.floorCount; f++)
        [for (var x = 0; x < RunMap.columns; x++) MapNode(x, f)],
    ];

    for (var p = 0; p < paths; p++) {
      var x = _random.nextInt(RunMap.columns);
      for (var f = 0; f < RunMap.floorCount; f++) {
        final node = floors[f][x];
        node.type ??= _rollType(f);
        if (f == RunMap.floorCount - 1) break;
        final nx = _nextColumn(floors[f], x);
        node.next.add(nx);
        x = nx;
      }
    }

    return RunMap(
      floors,
      MapNode(RunMap.columns ~/ 2, RunMap.floorCount)..type = NodeType.boss,
    );
  }

  /// Same weights as the cart: 45 / 22 / 17 / 11 / 5. First floor is always
  /// a battle, last floor is always a rest (campfire before the boss).
  NodeType _rollType(int floor) {
    if (floor == 0) return NodeType.battle;
    if (floor == RunMap.floorCount - 1) return NodeType.rest;
    final roll = _random.nextInt(100);
    if (roll < 45) return NodeType.battle;
    if (roll < 67) return NodeType.event;
    if (roll < 84) return NodeType.elite;
    if (roll < 95) return NodeType.rest;
    return NodeType.shop;
  }

  /// Iterative replacement for the cart's recursive `vizi_valid`: straight up
  /// can never cross, so it is the guaranteed fallback.
  int _nextColumn(List<MapNode> floor, int x) {
    final candidates = [
      x - 1,
      x,
      x + 1,
    ].where((c) => c >= 0 && c < RunMap.columns).toList()..shuffle(_random);
    for (final c in candidates) {
      if (!_crosses(floor, x, c)) return c;
    }
    return x;
  }

  /// A diagonal x -> c crosses the neighbour's diagonal c -> x.
  bool _crosses(List<MapNode> floor, int x, int c) =>
      c != x && floor[c].next.contains(x);
}
