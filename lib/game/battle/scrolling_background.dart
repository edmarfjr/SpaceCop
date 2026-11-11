import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../star_cop_game.dart';

/// Battle backdrop: [tile] repeated over the whole view, scrolling
/// diagonally. The offset moves in whole pixels so the pixel art doesn't
/// shimmer. Stops while the battle is halted (pause, deck view).
class ScrollingBackground extends Component
    with HasGameReference<StarCopGame> {
  ScrollingBackground(this.tile, {this.speedX = 8, this.speedY = 8})
    : super(priority: -100);

  /// Must be seamless: its edges meet when repeated.
  final Image tile;

  /// Px per second; equal values scroll at 45°.
  final double speedX;
  final double speedY;

  double _time = 0;
  final _paint = Paint()..filterQuality = FilterQuality.none;

  static const _view = Rect.fromLTWH(
    0,
    0,
    StarCopGame.viewWidth,
    StarCopGame.viewHeight,
  );

  @override
  void update(double dt) {
    if (!game.halted) _time += dt;
  }

  @override
  void render(Canvas canvas) {
    final dx = (_time * speedX).floorToDouble() % tile.width;
    final dy = (_time * speedY).floorToDouble() % tile.height;
    final matrix = Float64List(16)
      ..[0] = 1
      ..[5] = 1
      ..[10] = 1
      ..[15] = 1
      ..[12] = dx
      ..[13] = dy;
    _paint.shader = ImageShader(
      tile,
      TileMode.repeated,
      TileMode.repeated,
      matrix,
      filterQuality: FilterQuality.none,
    );
    canvas.drawRect(_view, _paint);
  }
}
