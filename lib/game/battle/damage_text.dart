import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../ui/theme.dart';

/// A short text rising from a unit and fading out: the damage of one hit,
/// or one of the green crosses of a heal ([HealBurst]).
class DamageText extends PositionComponent {
  DamageText(
    this.text, {
    required super.position,
    required this.color,
    this.delay = 0,
    this.rise = defaultRise,
  }) : super(anchor: Anchor.bottomCenter, priority: 1000);

  final String text;
  final Color color;

  /// Seconds before it shows up and starts rising.
  final double delay;

  /// Px risen over [lifetime].
  final double rise;

  /// Seconds on screen; it fades over the second half.
  static const double lifetime = 0.7;
  static const double defaultRise = 18;

  double _age = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age < delay) return;
    if (_age >= delay + lifetime) {
      removeFromParent();
      return;
    }
    position.y -= rise * dt / lifetime;
  }

  @override
  void render(Canvas canvas) {
    if (_age < delay) return;
    paintText(canvas, text, Vector2.zero(), color, (_age - delay) / lifetime);
  }

  /// Draws [text] the way a [DamageText] looks [t] (0 to 1) into its life,
  /// its bottom middle on [at]; for the deck select's showcase too.
  static void paintText(
    Canvas canvas,
    String text,
    Vector2 at,
    Color color,
    double t,
  ) {
    final opacity = 1 - max(0, t * 2 - 1).toDouble();
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
    ).render(canvas, text, at, anchor: Anchor.bottomCenter);
  }
}

/// A heal: green "+" [DamageText]s rising over the healed unit's sprite,
/// one after the other, spread over its body. Shared by the battle and the
/// deck select's showcase.
abstract final class HealBurst {
  static const color = Pico.green;

  /// Seconds between one cross and the next.
  static const double stagger = 0.08;

  /// Px each cross rises, less than a damage number.
  static const double rise = 14;

  /// Where each cross starts, as shares of the body: across from its
  /// middle (-0.5 to 0.5) and up from its feet (0 to 1).
  static const spots = [(-0.25, 0.55), (0.2, 0.35), (-0.05, 0.75), (0.3, 0.6)];

  /// Seconds from the first cross to the last one fading out.
  static double get length =>
      stagger * (spots.length - 1) + DamageText.lifetime;

  /// The crosses over a body of [size] standing with its feet's middle on
  /// [feet], in the same pixels as both.
  static List<DamageText> over(Vector2 feet, Vector2 size) => [
    for (final (i, (across, up)) in spots.indexed)
      DamageText(
        '+',
        position: feet + Vector2(size.x * across, -size.y * up),
        color: color,
        delay: i * stagger,
        rise: rise,
      ),
  ];

  /// Draws the crosses [seconds] after the heal, as [over] places and
  /// moves them, without components (the showcase's painter).
  static void paint(Canvas canvas, Vector2 feet, Vector2 size, double seconds) {
    for (final (i, (across, up)) in spots.indexed) {
      final age = seconds - i * stagger;
      if (age < 0 || age >= DamageText.lifetime) continue;
      final t = age / DamageText.lifetime;
      DamageText.paintText(
        canvas,
        '+',
        feet + Vector2(size.x * across, -size.y * up - rise * t),
        color,
        t,
      );
    }
  }
}
