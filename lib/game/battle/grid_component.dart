import 'dart:ui';

import 'package:flame/components.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/chips/chip_library.dart';
import '../../domain/grid.dart';
import '../../ui/theme.dart';
import '../sprites.dart';

/// Draws the 6x3 panels and converts grid coordinates to local pixels.
///
/// The player's cell lives in [BattleState] (the simulation); this component
/// is the single place that knows how a [GridPos] maps to the screen, so
/// fighters and projectiles are added as its children and use [cellCenter].
class GridComponent extends PositionComponent {
  GridComponent({required this.battle, required this.sprites, super.position})
    : super(
        size: Vector2(
          cellSize.x * gridColumns,
          cellSize.y * (gridRows - 1) + panelSize.y,
        ),
      );

  final BattleState battle;
  final GameSprites sprites;

  /// Top-left of the grid in the battle screen: centered horizontally
  /// ((384 - 240) / 2), between the status and the hand.
  static final Vector2 origin = Vector2(72, 40);

  /// Cart cells are 20x14 at 128px; doubled for a 256px-wide view.
  static final Vector2 cellSize = Vector2(40, 28);

  /// Panels are taller than a cell (cart: 20x20 over a 14px row step), so
  /// each row overlaps the one behind it for a pseudo-3D look.
  static final Vector2 panelSize = Vector2(40, 40);

  /// Where fighters stand, measured from the cell's top edge.
  static const double footOffset = 16;

  /// Mines are drawn faded: only the player knows where they are.
  static final _mine = Paint()..color = Pico.white.withValues(alpha: 0.6);

  Vector2 cellTopLeft(GridPos pos) =>
      Vector2(pos.x * cellSize.x, pos.y * cellSize.y);

  Vector2 cellCenter(GridPos pos) => cellTopLeft(pos) + cellSize / 2;

  /// Point where a fighter on [pos] has its feet.
  Vector2 cellFeet(GridPos pos) =>
      cellTopLeft(pos) + Vector2(cellSize.x / 2, footOffset);

  Rect cellRect(GridPos pos) => Rect.fromLTWH(
    pos.x * cellSize.x,
    pos.y * cellSize.y,
    cellSize.x,
    cellSize.y,
  );

  @override
  void render(Canvas canvas) {
    // Back row first so front panels overlap it, like the cart's draw order.
    for (var y = 0; y < gridRows; y++) {
      for (var x = 0; x < gridColumns; x++) {
        final pos = GridPos(x, y);
        final topLeft = cellTopLeft(pos);
        final panel = battle.panelAt(pos);
        // The panel's state, then the owner's frame over it.
        sprites
            .panel(panel.state)
            .render(canvas, position: topLeft, size: panelSize);
        sprites
            .panelFrame(battle.ownerAt(pos))
            .render(canvas, position: topLeft, size: panelSize);
        if (panel.mine) {
          sprites
              .chip(Chips.mine)
              .render(
                canvas,
                position: cellCenter(pos),
                size: Vector2.all(16),
                anchor: Anchor.center,
                overridePaint: _mine,
              );
        }
      }
    }
  }
}
