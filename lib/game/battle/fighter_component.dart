import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/text.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/chips/battle_chip.dart';
import '../../domain/run/relics.dart';
import '../../ui/theme.dart';
import '../sprites.dart';
import 'grid_component.dart';
import 'projectile_layer.dart';

/// Renders one [Fighter] with its cart sprite and glides it toward its
/// simulated cell.
class FighterComponent extends PositionComponent with ParentIsA<GridComponent> {
  FighterComponent(this.fighter, this.sprites)
    : super(anchor: Anchor.bottomCenter) {
    size = _idleSprite.srcSize * _scale;
  }

  final Fighter fighter;
  final GameSprites sprites;

  /// The view is 2x the cart's 128px. Every sprite uses this same scale, so
  /// an art pixel is the same size everywhere; bigger units are bigger in
  /// the art itself.
  static const double _scale = 2;

  Sprite get _idleSprite {
    return switch (fighter) {
      EnemyFighter(:final def, :final stage, :final pose) => sprites.enemy(
        def,
        stage: stage,
        pose: pose,
      ),
      Obstacle(:final kind) => sprites.obstacle(kind),
      _ => sprites.playerIdle,
    };
  }

  bool get _attacking {
    final f = fighter;
    return f is PlayerFighter && f.attackCooldown > 0;
  }

  /// Firing gets the muzzle flash; swings and tosses don't.
  bool get _shooting {
    final f = fighter;
    return _attacking && f is PlayerFighter && f.pose == ChipPose.shoot;
  }

  /// White for 3 ticks, normal for 3, twice, starting on the hit.
  bool get _flashing {
    final ticks = fighter.hurtTicks;
    return ticks > 0 && ((hurtFlashTicks - ticks) ~/ 3).isEven;
  }

  static final _hurtPaint = Paint()
    ..colorFilter = const ColorFilter.mode(Pico.white, BlendMode.srcATop);

  /// A phased Etéreo is drawn see-through.
  static final _phasedPaint = Paint()..color = const Color(0x80FFFFFF);

  /// Seconds each energy shield frame stays on screen.
  static const _shieldFrameTime = 0.1;

  /// The attack sign shows over an enemy this long before its attack lands.
  static const _signTicks = ticksPerSecond ~/ 2;
  static const _signFrameTime = 0.1;

  /// Time since mount, for looped effects.
  double _clock = 0;

  static const _turretFlashTicks = 4;
  static final _lifeBack = Paint()..color = Pico.darkBlue;
  static final _lifeFill = Paint()..color = Pico.blue;

  /// Visor de Combate: the bar beside an enemy filling up to its next
  /// attack, red once it is close.
  static final _readyFill = Paint()..color = Pico.orange;
  static final _readyNear = Paint()..color = Pico.red;

  static final _hpText = TextPaint(
    style: const TextStyle(
      fontFamily: pixelFont,
      fontSize: 8,
      color: Pico.white,
    ),
  );

  /// Multi-cell enemies stand on their lowest row, centered on its cells.
  Vector2 get _target {
    final f = fighter;
    if (f is! EnemyFighter) return parent.cellFeet(f.pos);
    final cells = f.cells.toList();
    final bottom = cells.map((c) => c.y).reduce(max);
    final feet = [
      for (final c in cells)
        if (c.y == bottom) parent.cellFeet(c),
    ];
    return feet.reduce((a, b) => a + b) / feet.length.toDouble();
  }

  /// Drawn in row order, with each row's projectiles right after it.
  int get _rowPriority {
    final f = fighter;
    final row = f is EnemyFighter
        ? f.cells.map((c) => c.y).reduce(max)
        : f.pos.y;
    return ProjectileLayer.priorityOf(row);
  }

  @override
  void onMount() {
    super.onMount();
    position = _target;
    priority = _rowPriority;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;
    position.lerp(_target, min(1, dt * 20));
    final rowPriority = _rowPriority;
    if (priority != rowPriority) priority = rowPriority;
  }

  @override
  void render(Canvas canvas) {
    if (fighter.hidden) return;
    final sprite = switch (fighter) {
      EnemyFighter(:final def, :final stage, :final pose, attackFrame: true) =>
        sprites.enemy(def, attacking: true, stage: stage, pose: pose),
      EnemyFighter(:final def, :final stage, :final pose) => sprites.enemy(
        def,
        stage: stage,
        pose: pose,
      ),
      _ when _shooting => sprites.playerAttack,
      _ when _attacking => sprites.playerMelee,
      _ => _idleSprite,
    };
    // Digging in or climbing out: the sprite slides below its feet line.
    final buried = switch (fighter) {
      EnemyFighter(:final buried) => buried,
      _ => 0.0,
    };
    canvas
      ..save()
      ..clipRect(Offset.zero & size.toSize());
    sprite.render(
      canvas,
      position: Vector2(0, size.y * buried),
      size: size,
      overridePaint: _flashing
          ? _hurtPaint
          : fighter is EnemyFighter && (fighter as EnemyFighter).phased
          ? _phasedPaint
          : null,
    );
    canvas.restore();
    // Energy shield: the player's barrier, or an enemy nothing can hurt.
    final shielded = switch (fighter) {
      PlayerFighter(:final barrierTicks) => barrierTicks > 0,
      final EnemyFighter enemy =>
        enemy.invulnerable || parent.battle.prismGuarded(enemy),
      _ => false,
    };
    // Front shield: only straight shots from the front stop on it.
    final f = fighter;
    if (!shielded &&
        f is EnemyFighter &&
        f.def.frontShield &&
        f.shieldDown == 0) {
      final frames = sprites.frontShield;
      final frame = frames[(_clock / _shieldFrameTime).floor() % frames.length];
      frame.render(
        canvas,
        position: Vector2(0, size.y / 2),
        size: frame.srcSize * _scale,
        anchor: Anchor.centerLeft,
      );
    }
    if (shielded) {
      final frames = sprites.energyShield;
      final frame = frames[(_clock / _shieldFrameTime).floor() % frames.length];
      final shieldSize = frame.srcSize * _scale;
      frame.render(
        canvas,
        position: size / 2,
        size: shieldSize,
        anchor: Anchor.center,
      );
    }
    if (fighter case Obstacle(
      kind: ObstacleKind.turret,
      :final fireTimer,
      :final ticksLeft,
      :final lifetime,
    )) {
      // Flash at the barrel right after each shot.
      if (fireTimer > ticksPerSecond - _turretFlashTicks) {
        sprites.muzzle.render(
          canvas,
          position: Vector2(size.x, size.y * 0.25),
          size: sprites.muzzle.srcSize * _scale,
        );
      }
      // Time left, as a bar under the turret.
      final bar = Rect.fromLTWH(0, size.y + 1, size.x, 2);
      canvas
        ..drawRect(bar, _lifeBack)
        ..drawRect(
          Rect.fromLTWH(
            bar.left,
            bar.top,
            bar.width * ticksLeft / lifetime,
            bar.height,
          ),
          _lifeFill,
        );
    }
    if (_shooting) {
      sprites.muzzle.render(
        canvas,
        position: Vector2(size.x - 4, 10),
        size: sprites.muzzle.srcSize * _scale,
      );
    }
    // Enemies show their life in the HUD, on the right.
    if (fighter is Obstacle) {
      _hpText.render(
        canvas,
        '${fighter.hp}',
        Vector2(size.x / 2, -2),
        anchor: Anchor.bottomCenter,
      );
    }
    // Attack sign over the head, the last half second before an attack.
    if (fighter case final EnemyFighter enemy) {
      final left = parent.battle.ticksToAttack(enemy);
      if (left != null && left <= _signTicks) {
        final frames = sprites.attackSign;
        final frame = frames[(_clock / _signFrameTime).floor() % frames.length];
        frame.render(
          canvas,
          position: Vector2(size.x / 2, 6),
          size: frame.srcSize * _scale,
          anchor: Anchor.bottomCenter,
        );
      }
    }
    // Visor de Combate: how close the next attack is, as a vertical bar
    // on the enemy's left (its right edge may sit under the HUD), filling
    // from the bottom.
    if (fighter case final EnemyFighter enemy
        when !enemy.def.part && parent.battle.hasRelic(Relics.combatVisor)) {
      final ready = enemy.def.behavior.readiness(enemy);
      if (ready != null) {
        final bar = Rect.fromLTWH(-3, 2, 2, size.y - 4);
        canvas
          ..drawRect(bar, _lifeBack)
          ..drawRect(
            Rect.fromLTRB(
              bar.left,
              bar.bottom - bar.height * ready,
              bar.right,
              bar.bottom,
            ),
            ready >= 0.8 ? _readyNear : _readyFill,
          );
      }
    }
    // Active statuses, in a row above the head.
    var x = 0.0;
    for (final status in fighter.statuses.keys) {
      sprites
          .status(status)
          .render(canvas, position: Vector2(x, -10), size: Vector2.all(8));
      x += 9;
    }
  }
}
