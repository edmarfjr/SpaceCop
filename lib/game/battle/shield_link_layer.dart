import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/battle/enemies.dart';
import '../../ui/theme.dart';
import 'fighter_component.dart';
import 'grid_component.dart';

/// Lightning from the top of every shield source (the Rei's totems, the
/// Olho do Abismo's Hemisférios) to the enemy it keeps invulnerable, and
/// between guarded Capangas Infiltradores, over every fighter.
class ShieldLinkLayer extends Component with ParentIsA<GridComponent> {
  ShieldLinkLayer(this.battle, this.viewOf) : super(priority: 1000);

  final BattleState battle;

  /// The view drawing [Fighter], if it has one yet.
  final FighterComponent? Function(Fighter fighter) viewOf;

  /// Enemies that shield another one while they stand.
  static const sources = {
    Enemies.totem,
    Enemies.ragingTotem,
    Enemies.hemisphere,
  };

  /// Kinks along each bolt.
  static const _segments = 6;

  /// Seconds before the bolts take a new shape.
  static const _reshapeTime = 0.08;

  /// The art is drawn at 2x: bolts bend and snap on whole art pixels.
  static const double _pixel = 2;

  static final _glow = Paint()
    ..color = Pico.blue
    ..strokeWidth = 2 * _pixel
    ..strokeCap = StrokeCap.square
    ..style = PaintingStyle.stroke;
  static final _core = Paint()
    ..color = Pico.white
    ..strokeWidth = _pixel
    ..strokeCap = StrokeCap.square
    ..style = PaintingStyle.stroke;

  final _random = Random();
  double _clock = 0;
  int _seed = 0;

  @override
  void update(double dt) {
    _clock += dt;
    if (_clock >= _reshapeTime) {
      _clock = 0;
      _seed = _random.nextInt(1 << 30);
    }
  }

  @override
  void render(Canvas canvas) {
    final shape = Random(_seed);
    // Each guarded twin pair once, middle to middle.
    for (final enemy in battle.enemies) {
      final twin = enemy.partner;
      if (twin == null ||
          battle.enemies.indexOf(twin) < battle.enemies.indexOf(enemy) ||
          !battle.prismGuarded(enemy)) {
        continue;
      }
      final (a, b) = (viewOf(enemy), viewOf(twin));
      if (a == null || b == null) continue;
      _draw(canvas, _middle(a), _middle(b), shape);
    }
    final shielded = [
      for (final e in battle.enemies)
        if (e.invulnerable && !e.hidden) e,
    ];
    if (shielded.isEmpty) return;
    for (final source in battle.enemies) {
      if (!sources.contains(source.def) || source.hidden) continue;
      final from = viewOf(source);
      if (from == null) continue;
      for (final target in shielded) {
        final to = viewOf(target);
        if (to == null) continue;
        // From the totem's top to the middle of the boss.
        _draw(
          canvas,
          from.position - Vector2(0, from.size.y),
          _middle(to),
          shape,
        );
      }
    }
  }

  Vector2 _middle(FighterComponent view) =>
      view.position - Vector2(0, view.size.y / 2);

  void _draw(Canvas canvas, Vector2 a, Vector2 b, Random shape) {
    final path = _bolt(a, b, shape);
    canvas
      ..drawPath(path, _glow)
      ..drawPath(path, _core);
  }

  /// A jagged line from [a] to [b], bent sideways at each kink.
  Path _bolt(Vector2 a, Vector2 b, Random shape) {
    double snap(double v) => (v / _pixel).roundToDouble() * _pixel;
    final along = b - a;
    final side = Vector2(-along.y, along.x)..normalize();
    final path = Path()..moveTo(snap(a.x), snap(a.y));
    for (var i = 1; i < _segments; i++) {
      final bend = (shape.nextInt(5) - 2) * _pixel * 2;
      final p = a + along * (i / _segments) + side * bend;
      path.lineTo(snap(p.x), snap(p.y));
    }
    return path..lineTo(snap(b.x), snap(b.y));
  }
}
