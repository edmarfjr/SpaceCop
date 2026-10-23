import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';

/// Draws one game [Sprite], pixel-perfect, in Flutter UI.
class SheetSprite extends StatelessWidget {
  const SheetSprite({super.key, required this.sprite, this.scale = 2});

  final Sprite sprite;
  final double scale;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: sprite.src.size * scale,
    painter: _SheetPainter(sprite),
  );
}

class _SheetPainter extends CustomPainter {
  _SheetPainter(this.sprite);

  final Sprite sprite;

  static final _paint = Paint()..filterQuality = FilterQuality.none;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    sprite.image,
    sprite.src,
    Offset.zero & size,
    _paint,
  );

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.sprite.image != sprite.image || old.sprite.src != sprite.src;
}
