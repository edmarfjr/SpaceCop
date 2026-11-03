import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/chips/battle_chip.dart' show ChipFx;
import '../../domain/element.dart';
import '../../domain/grid.dart';
import '../../ui/theme.dart';
import 'fighter_component.dart';
import 'grid_component.dart';
import 'shield_link_layer.dart';

/// Card effects over every fighter: the Arco Voltaico's lightning and the
/// Feixe Contínuo's beam (see [ChipFx]).
class ChipFxLayer extends Component with ParentIsA<GridComponent> {
  ChipFxLayer(this.battle, this.viewOf) : super(priority: 1001);

  final BattleState battle;
  final FighterComponent? Function(Fighter fighter) viewOf;

  /// Seconds before the bolts take a new shape and the beam flickers.
  static const _reshapeTime = 0.06;

  /// Half heights of the beam's layers, in screen px (2 per art pixel).
  static const double _beamGlow = 8;
  static const double _beamCore = 5;

  /// Outer, middle and inner colors of a beam of each element.
  static final _beamColors = {
    for (final MapEntry(:key, :value) in {
      Element.elec: (Pico.royal, Pico.blue, Pico.white),
      Element.fire: (Pico.red, Pico.orange, Pico.yellow),
      Element.aqua: (Pico.royal, Pico.blue, Pico.white),
      Element.wood: (Pico.darkGreen, Pico.green, Pico.lime),
      Element.neutral: (Pico.lavender, Pico.lightGray, Pico.white),
    }.entries)
      key: (
        Paint()..color = value.$1,
        Paint()..color = value.$2,
        Paint()..color = value.$3,
      ),
  };

  static final _tracer = Paint()
    ..color = Pico.white
    ..strokeWidth = 2
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
    final hand = _hand();
    if (hand == null) return;
    final shape = Random(_seed);
    for (final shot in battle.projectiles) {
      if (shot.fx != ChipFx.bolt) continue;
      ShieldLinkLayer.drawBolt(canvas, hand, _body(shot.pos), shape);
    }
    for (final zap in battle.zaps) {
      final from = switch (zap.from) {
        final GridPos pos => _body(pos),
        null => hand,
      };
      if (zap.tracer) {
        final to = _body(zap.to);
        canvas.drawLine(Offset(from.x, from.y), Offset(to.x, to.y), _tracer);
      } else {
        ShieldLinkLayer.drawBolt(canvas, from, _body(zap.to), shape);
      }
    }
    for (final beam in battle.beams) {
      _beam(canvas, hand, beam, shape);
    }
  }

  /// Down the row from the hand to the first enemy in it, or to the edge;
  /// it swells in, flickers, and thins out at the end.
  void _beam(Canvas canvas, Vector2 hand, Beam beam, Random shape) {
    final row = battle.player.pos.y;
    // Level with the shots and the explosions, not the raised gun.
    final y = parent.cellCenter(battle.player.pos).y;
    var end = parent.size.x;
    for (
      var x = battle.player.pos.x + 1;
      !beam.pierce && x < gridColumns;
      x++
    ) {
      final unit = battle.unitAt(GridPos(x, row));
      if (unit != null && unit.team == Team.enemy) {
        end = parent.cellCenter(GridPos(x, row)).x;
        break;
      }
    }
    final age = beam.lifetime - beam.ticksLeft;
    final swell = min(1.0, (min(age, beam.ticksLeft) + 1) / 3);
    final flicker = shape.nextBool() ? 2.0 : 0.0;
    double snap(double v) => (v / 2).roundToDouble() * 2;
    void band(double half, Paint paint) {
      final h = snap(half * swell);
      if (h <= 0) return;
      canvas.drawRect(
        Rect.fromLTRB(hand.x, snap(y) - h, end, snap(y) + h),
        paint,
      );
    }

    final (outer, middle, inner) = _beamColors[beam.element]!;
    band(_beamGlow + flicker, outer);
    band(_beamCore + flicker / 2, middle);
    band(2, inner);
    // A burst of sparks where it hits.
    if (end < parent.size.x) {
      for (var i = 0; i < 4; i++) {
        final spark = Vector2(
          end + shape.nextInt(5) * 2 - 4,
          y + shape.nextInt(9) * 2 - 8,
        );
        canvas.drawRect(
          Rect.fromLTWH(snap(spark.x), snap(spark.y), 4, 4),
          inner,
        );
      }
    }
  }

  /// The player's gun barrel: the middle of the muzzle flash.
  Vector2? _hand() {
    final view = viewOf(battle.player);
    if (view == null) return null;
    return view.position -
        Vector2(view.size.x / 2, view.size.y) +
        Vector2(view.size.x + 4, 18);
  }

  /// Middle of whoever stands on [pos]: their view if there is one, else
  /// a body's height over the cell's feet line.
  Vector2 _body(GridPos pos) {
    final unit = battle.unitAt(pos);
    final view = unit == null ? null : viewOf(unit);
    if (view != null) return view.position - Vector2(0, view.size.y / 2);
    return parent.cellFeet(pos) - Vector2(0, 20);
  }
}
