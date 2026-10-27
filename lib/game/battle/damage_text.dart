import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../ui/theme.dart';

/// The damage of one hit, rising from the unit hit and fading out.
class DamageText extends PositionComponent {
  DamageText(this.amount, {required super.position, required this.color})
    : super(anchor: Anchor.bottomCenter, priority: 1000);

  final int amount;
  final Color color;

  /// Seconds on screen; it fades over the second half.
  static const double _lifetime = 0.7;

  /// Px risen over [_lifetime].
  static const double _rise = 18;

  double _age = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _lifetime) {
      removeFromParent();
      return;
    }
    position.y -= _rise * dt / _lifetime;
  }

  @override
  void render(Canvas canvas) {
    final opacity = 1 - max(0, _age / _lifetime * 2 - 1).toDouble();
    TextPaint(
      style: TextStyle(
        fontFamily: pixelFont,
        fontSize: 8,
        color: color.withValues(alpha: opacity),
        shadows: [
          Shadow(
            color: Pico.black.withValues(alpha: opacity),
            offset: const Offset(1, 1),
          ),
        ],
      ),
    ).render(canvas, '$amount', Vector2.zero(), anchor: Anchor.bottomCenter);
  }
}
