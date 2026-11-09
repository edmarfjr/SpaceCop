import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/chips/battle_chip.dart' show ChipFx;
import '../../domain/element.dart';
import '../../domain/grid.dart';
import '../../ui/theme.dart';
import 'fighter_component.dart';
import '../sprites.dart';
import 'grid_component.dart';
import 'projectile_layer.dart';
import 'shield_link_layer.dart';

/// Card effects over every fighter (see [ChipFx]): lightning, beams and
/// streaks, plus what helps read the battle: the Carga C4 blinking on its
/// victim, a reticle on Marked enemies, the Mira Assistida's aim and the
/// barrier's charges.
class ChipFxLayer extends Component with ParentIsA<GridComponent> {
  ChipFxLayer(this.battle, this.sprites, this.viewOf) : super(priority: 1001);

  final BattleState battle;
  final GameSprites sprites;
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

  static final _red = Paint()..color = Pico.red;
  static final _white = Paint()..color = Pico.white;
  static final _blue = Paint()..color = Pico.blue;
  static final _reticle = Paint()
    ..color = Pico.red
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  /// Seconds a reticle takes to close on a newly Marked enemy.
  static const _lockTime = 0.25;

  final _random = Random();
  double _clock = 0;
  double _time = 0;
  int _seed = 0;

  /// Since when each enemy has been Marked, for its reticle.
  final _markedSince = <Fighter, double>{};

  /// Smoke puffs and fire sparks left behind by shots and lobs.
  final _particles = <_Particle>[];
  double _emit = 0;

  /// Seconds between two particles from the same shot.
  static const _emitEvery = 0.03;

  static final _ghost = Paint()..color = const Color(0x66FFFFFF);

  static final _chainLight = Paint()
    ..color = Pico.lightGray
    ..strokeWidth = 2;
  static final _chainDark = Paint()
    ..color = Pico.darkGray
    ..strokeWidth = 2;
  static final _tractorGlow = Paint()
    ..color = Pico.blue.withValues(alpha: 0.35)
    ..strokeWidth = 10;
  static final _tractorCore = Paint()
    ..color = Pico.blue
    ..strokeWidth = 2;
  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final _static = Paint();

  /// The player's HP last frame: a rise sends up green crosses.
  int? _lastHp;

  @override
  void update(double dt) {
    _time += dt;
    for (final enemy in battle.enemies) {
      if (enemy.has(Status.marked) && !enemy.hidden) {
        _markedSince.putIfAbsent(enemy, () => _time);
      }
    }
    _markedSince.removeWhere(
      (enemy, _) => !enemy.has(Status.marked) || enemy.isDead,
    );
    final hp = battle.player.hp;
    if (_lastHp case final last? when hp > last) {
      if (viewOf(battle.player) case final view?) {
        final middle = view.position - Vector2(0, view.size.y / 2);
        for (var i = 0; i < 3; i++) {
          _particles.add(_Particle.heal(middle, _random));
        }
      }
    }
    _lastHp = hp;
    for (final particle in _particles) {
      particle.age += dt;
    }
    _particles.removeWhere((p) => p.age >= p.life);
    _emit += dt;
    if (_emit >= _emitEvery) {
      _emit = 0;
      _emitParticles();
    }
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
      final to = _body(shot.pos);
      ShieldLinkLayer.drawBolt(canvas, hand, Vector2(to.x, hand.y), shape);
    }
    for (final zap in battle.zaps) {
      final from = switch (zap.from) {
        final GridPos pos => _body(pos),
        null => hand,
      };
      var to = _body(zap.to);
      // From the hand down its own row: level with the hand.
      if (zap.from == null && zap.to.y == battle.player.pos.y) {
        to = Vector2(to.x, from.y);
      }
      switch (zap.style) {
        case ZapStyle.bolt:
          ShieldLinkLayer.drawBolt(canvas, from, to, shape);
        case ZapStyle.tracer:
          canvas.drawLine(Offset(from.x, from.y), Offset(to.x, to.y), _tracer);
        case ZapStyle.chain:
          _drawChain(canvas, from, to);
        case ZapStyle.tractor:
          _drawTractor(canvas, from, to);
      }
    }
    for (final particle in _particles) {
      particle.render(canvas);
    }
    for (final trail in battle.trails) {
      _drawTrail(canvas, trail);
    }
    for (final ring in battle.rings) {
      _drawRings(canvas, hand, ring);
    }
    if (battle.glitchTicks > 0) {
      for (final enemy in battle.enemies) {
        if (!enemy.hidden) _drawStatic(canvas, enemy, shape);
      }
    }
    for (final beam in battle.beams) {
      _beam(canvas, hand, beam, shape);
    }
    for (final MapEntry(key: enemy, value: since) in _markedSince.entries) {
      _drawReticle(canvas, enemy, min(1, (_time - since) / _lockTime));
    }
    if (battle.homingShots > 0) {
      if (battle.weakestEnemy() case final target?) {
        _dashed(canvas, hand, _body(target.pos));
      }
    }
    for (final bomb in battle.stickies) {
      _drawBomb(canvas, bomb);
    }
    _drawCharges(canvas);
  }

  /// Smoke behind Míssil shots and Foguete lobs, sparks behind every Fire
  /// shot of the player's side (Bala Incendiária, Torre Incendiária).
  void _emitParticles() {
    for (final shot in battle.projectiles) {
      if (shot.team != Team.player) continue;
      final at = parent.cellCenter(shot.pos);
      if (shot.fx == ChipFx.smoke) {
        _particles.add(_Particle.smoke(at, _random));
      } else if (shot.element == Element.fire) {
        _particles.add(_Particle.spark(at, _random));
      }
    }
    for (final lob in battle.lobs) {
      if (lob.lob != Lob.rocket) continue;
      final t = 1 - lob.ticksLeft / lob.flightTicks;
      final at = ProjectileLayer.lobAt(
        parent.cellCenter(lob.from.pos),
        parent.cellCenter(lob.to),
        t,
      );
      _particles.add(_Particle.smoke(at, _random));
    }
  }

  /// Links alternating light and dark from [a] to [b] (Gancho).
  void _drawChain(Canvas canvas, Vector2 a, Vector2 b) {
    const link = 6.0;
    final along = b - a;
    final length = along.length;
    if (length == 0) return;
    final step = along / length;
    for (var d = 0.0, i = 0; d < length; d += link, i++) {
      final from = a + step * d;
      final to = a + step * min(length, d + link);
      canvas.drawLine(
        Offset(from.x, from.y),
        Offset(to.x, to.y),
        i.isEven ? _chainLight : _chainDark,
      );
    }
  }

  /// A see-through blue band from [a] to [b] (Feixe Trator).
  void _drawTractor(Canvas canvas, Vector2 a, Vector2 b) {
    final (from, to) = (Offset(a.x, a.y), Offset(b.x, b.y));
    canvas
      ..drawLine(from, to, _tractorGlow)
      ..drawLine(from, to, _tractorCore);
  }

  /// Rings growing out of the hand, one after the other, fading out.
  void _drawRings(Canvas canvas, Vector2 hand, Ring ring) {
    final age = Ring.lifetime - ring.ticksLeft;
    for (var i = 0; i < ring.count; i++) {
      final grown = age - i * 3;
      if (grown <= 0) continue;
      final t = grown / Ring.lifetime;
      _ring.color = Pico.blue.withValues(alpha: (1 - t).clamp(0, 1));
      canvas.drawCircle(Offset(hand.x, hand.y), 4 + grown * 3, _ring);
    }
  }

  /// A few bars of static across [enemy]'s sprite (Interferência).
  void _drawStatic(Canvas canvas, Fighter enemy, Random shape) {
    final view = viewOf(enemy);
    if (view == null) return;
    final left = view.position.x - view.size.x / 2;
    final top = view.position.y - view.size.y;
    for (var i = 0; i < 3; i++) {
      final y = top + (shape.nextInt((view.size.y ~/ 2).clamp(1, 99)) * 2);
      final x = left + shape.nextInt((view.size.x ~/ 4).clamp(1, 99)) * 2;
      final width = (4 + shape.nextInt(8) * 2).toDouble();
      _static.color = (shape.nextBool() ? Pico.white : Pico.lightGray)
          .withValues(alpha: 0.8);
      canvas.drawRect(Rect.fromLTWH(x, y, width, 2), _static);
    }
  }

  /// Fading ghosts of the player on each panel left behind by Investida.
  void _drawTrail(Canvas canvas, Trail trail) {
    final sprite = sprites.playerIdle;
    final alpha = trail.ticksLeft / Trail.lifetime;
    _ghost.color = Pico.blue.withValues(alpha: 0.5 * alpha);
    for (var x = trail.from.x; x < trail.to.x; x++) {
      sprite.render(
        canvas,
        position: parent.cellFeet(GridPos(x, trail.from.y)),
        size: sprite.srcSize * 2,
        anchor: Anchor.bottomCenter,
        overridePaint: _ghost,
      );
    }
  }

  /// Four red corners closing in on [enemy] as [lock] goes from 0 to 1.
  void _drawReticle(Canvas canvas, Fighter enemy, double lock) {
    final view = viewOf(enemy);
    if (view == null) return;
    final center = view.position - Vector2(0, view.size.y / 2);
    final half = 12 + 16 * (1 - lock);
    const arm = 6.0;
    for (final (sx, sy) in const [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
      final corner = Offset(center.x + sx * half, center.y + sy * half);
      canvas
        ..drawLine(corner, corner.translate(-sx * arm, 0), _reticle)
        ..drawLine(corner, corner.translate(0, -sy * arm), _reticle);
    }
  }

  /// A red dashed line from [a] to [b], marching toward [b].
  void _dashed(Canvas canvas, Vector2 a, Vector2 b) {
    const dash = 6.0;
    final along = b - a;
    final length = along.length;
    if (length == 0) return;
    final step = along / length;
    final shift = (_time * 24) % (dash * 2);
    for (var d = shift - dash * 2; d < length; d += dash * 2) {
      final from = a + step * max(0, d);
      final to = a + step * min(length, d + dash);
      if (d + dash <= 0) continue;
      canvas.drawLine(Offset(from.x, from.y), Offset(to.x, to.y), _reticle);
    }
  }

  /// A red light on the C4's victim, blinking faster as it runs out.
  void _drawBomb(Canvas canvas, StickyBomb bomb) {
    final view = viewOf(bomb.victim);
    final at = view == null
        ? parent.cellCenter(bomb.victim.pos)
        : view.position - Vector2(0, view.size.y / 2);
    final period = (bomb.ticksLeft ~/ 6).clamp(2, 10);
    if ((bomb.ticksLeft ~/ period).isOdd) return;
    canvas
      ..drawRect(
        Rect.fromCenter(center: Offset(at.x, at.y), width: 6, height: 6),
        _red,
      )
      ..drawRect(
        Rect.fromCenter(center: Offset(at.x, at.y), width: 2, height: 2),
        _white,
      );
  }

  /// One pip over the player's head per hit the barrier still cancels, when
  /// it can take more than one (Gerador de Domo).
  void _drawCharges(Canvas canvas) {
    final player = battle.player;
    if (player.barrierTicks <= 0 || player.barrierCharges <= 1) return;
    final view = viewOf(player);
    if (view == null) return;
    final top = view.position - Vector2(0, view.size.y + 4);
    final count = player.barrierCharges;
    for (var i = 0; i < count; i++) {
      final x = top.x - (count * 6 - 2) / 2 + i * 6;
      canvas.drawRect(Rect.fromLTWH(x, top.y, 4, 4), _blue);
    }
  }

  /// Down the row from the hand to the first enemy in it, or to the edge;
  /// it swells in, flickers, and thins out at the end.
  void _beam(Canvas canvas, Vector2 hand, Beam beam, Random shape) {
    final row = battle.player.pos.y;
    // Level with the gun barrel, like the line effects.
    final y = hand.y;
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

/// A square that drifts and fades: a smoke puff or a fire spark.
class _Particle {
  _Particle.smoke(Vector2 at, Random random)
    : position = at + Vector2(random.nextDouble() * 4 - 2, 0),
      velocity = Vector2(-10, -12),
      life = 0.45,
      color = Pico.lightGray,
      grows = true,
      plus = false;

  _Particle.heal(Vector2 at, Random random)
    : position = at + Vector2(random.nextDouble() * 24 - 12, 0),
      velocity = Vector2(0, -30 - random.nextDouble() * 10),
      life = 0.6,
      color = Pico.green,
      grows = false,
      plus = true;

  _Particle.spark(Vector2 at, Random random)
    : position = at,
      velocity = Vector2(
        -30 - random.nextDouble() * 30,
        random.nextDouble() * 40 - 30,
      ),
      life = 0.25,
      color = random.nextBool() ? Pico.orange : Pico.yellow,
      grows = false,
      plus = false;

  final Vector2 position;
  final Vector2 velocity;
  final double life;
  final Color color;

  /// Smoke swells as it fades; sparks shrink.
  final bool grows;

  /// Drawn as a "+" (a heal) instead of a square.
  final bool plus;
  double age = 0;

  static final _paint = Paint();

  void render(Canvas canvas) {
    final t = age / life;
    final at = position + velocity * age;
    if (plus) {
      _paint.color = color.withValues(alpha: 1 - t);
      final x = (at.x / 2).roundToDouble() * 2;
      final y = (at.y / 2).roundToDouble() * 2;
      canvas
        ..drawRect(
          Rect.fromCenter(center: Offset(x, y), width: 6, height: 2),
          _paint,
        )
        ..drawRect(
          Rect.fromCenter(center: Offset(x, y), width: 2, height: 6),
          _paint,
        );
      return;
    }
    final size = (grows ? 4 + 6 * t : 4 * (1 - t)).roundToDouble();
    if (size <= 0) return;
    _paint.color = color.withValues(alpha: 1 - t);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(
          (at.x / 2).roundToDouble() * 2,
          (at.y / 2).roundToDouble() * 2,
        ),
        width: size,
        height: size,
      ),
      _paint,
    );
  }
}
