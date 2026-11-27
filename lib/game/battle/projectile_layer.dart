import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/chips/battle_chip.dart' show ChipFx;
import '../../domain/element.dart';
import '../../domain/grid.dart';
import '../../ui/theme.dart';
import '../sprites.dart';
import 'grid_component.dart';

/// Draws every projectile, lobbed attack and explosion straight from
/// [BattleState].
///
/// Projectiles are short-lived and numerous, so a layer that reads the
/// simulation is simpler than syncing a component per shot.
///
/// There is one layer per grid row, drawn right after the fighters of that
/// row ([priorityOf]), so a shot on an upper row goes behind a fighter
/// standing on a lower one. The [ground] layer, under every fighter, draws
/// the warnings on the panels.
class ProjectileLayer extends Component with ParentIsA<GridComponent> {
  ProjectileLayer.ground(this.battle, this.sprites)
    : row = null,
      super(priority: 0);

  ProjectileLayer.row(this.battle, this.sprites, int this.row)
    : super(priority: priorityOf(row) + 1);

  /// Priority of the fighters standing on [row]; deeper rows draw later.
  static int priorityOf(int row) => 10 * (row + 1);

  final BattleState battle;
  final GameSprites sprites;

  /// Row this layer draws; null for the ground layer.
  final int? row;

  /// Art is drawn at 2x, like the fighters.
  static final Vector2 _size = Vector2.all(32);

  /// Peak height of a lob, in px above the straight line.
  static const double lobHeight = 28;

  /// Where a lob is at [t] (0 to 1) of its flight from [from] to [to].
  static Vector2 lobAt(Vector2 from, Vector2 to, double t) =>
      from + (to - from) * t - Vector2(0, lobHeight * 4 * t * (1 - t));

  /// How a lobbed sprite is turned at [t] of its flight from [from] to
  /// [to]: a [Lob.rocket] points along the arc (its art points right), a
  /// tumbling one turns once forward, the rest stays upright. [height] is
  /// the arc's peak, for the direction.
  static double lobTurn(
    Lob lob,
    Vector2 from,
    Vector2 to,
    double t, {
    required bool tumbles,
    double height = lobHeight,
  }) {
    if (lob == Lob.rocket) {
      final along = to - from - Vector2(0, height * 4 * (1 - 2 * t));
      return atan2(along.y, along.x);
    }
    if (!tumbles) return 0;
    return (to.x >= from.x ? 1 : -1) * t * 2 * pi;
  }

  static final _danger = Paint()
    ..color = Pico.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final _terrain = Paint()
    ..color = Pico.lightGray
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  int _frame = 0;

  @override
  void update(double dt) => _frame++;

  @override
  void render(Canvas canvas) {
    final row = this.row;
    if (row == null) {
      _renderGround(canvas);
      return;
    }
    for (final shot in battle.projectiles) {
      // The beam covers its own shots.
      // The beam covers its own shots; the Gancho's hook is its chain.
      if (shot.pos.y != row || shot.fx == ChipFx.beam || shot.hooked) continue;
      (shot.fx == ChipFx.spear ? sprites.spear : sprites.shot[_frame ~/ 6 % 2])
          .render(
            canvas,
            position: parent.cellCenter(shot.pos) + Vector2(0, -8),
            size: _size,
            anchor: Anchor.center,
          );
    }
    for (final lob in battle.lobs) {
      if (lob.to.y != row || lob.lob == Lob.self) continue;
      final from = parent.cellCenter(lob.from.pos);
      final to = parent.cellCenter(lob.to);
      final t = 1 - lob.ticksLeft / lob.flightTicks;
      final at = lobAt(from, to, t);
      final enemy = switch (lob.from) {
        EnemyFighter(:final def) => def,
        _ => null,
      };
      final sprite = sprites.lobbed(lob.lob, chip: lob.chip, enemy: enemy);
      canvas
        ..save()
        ..translate(at.x, at.y)
        ..rotate(
          lobTurn(
            lob.lob,
            from,
            to,
            t,
            tumbles: sprites.tumbles(lob.lob, chip: lob.chip, enemy: enemy),
          ),
        );
      // 2x like the fighters: the grenades are smaller than a ball.
      sprite.render(canvas, size: sprite.srcSize * 2, anchor: Anchor.center);
      canvas.restore();
    }
    // Smoke clouds, over whoever stands in them.
    for (var x = 0; x < gridColumns; x++) {
      final pos = GridPos(x, row);
      if (!battle.panelAt(pos).smoky) continue;
      sprites.smoke[_frame ~/ 10 % 2].render(
        canvas,
        position: parent.cellCenter(pos),
        size: _size,
        anchor: Anchor.center,
      );
    }
    for (final flash in battle.flashes) {
      if (flash.pos.y != row) continue;
      final tint = _tint(flash);
      if (flash.kind == FlashKind.slash) {
        sprites.slash.render(
          canvas,
          position: parent.cellCenter(flash.pos),
          size: sprites.slash.srcSize * 2,
          anchor: Anchor.center,
          overridePaint: tint,
        );
        continue;
      }
      if (flash.kind == FlashKind.slashH) {
        // Across its panel and the next one, centered between them.
        final from = parent.cellCenter(flash.pos);
        final to = parent.cellCenter(flash.pos + const GridPos(1, 0));
        sprites.slashH.render(
          canvas,
          position: (from + to) / 2,
          size: sprites.slashH.srcSize * 2,
          anchor: Anchor.center,
          overridePaint: tint,
        );
        continue;
      }
      if (flash.kind == FlashKind.cut) {
        // Half the slash, leaning toward the panel it hits.
        final cut = sprites.cut;
        final at = parent.cellCenter(flash.pos);
        canvas
          ..save()
          ..translate(at.x, at.y)
          ..rotate(
            flash.pos.y < battle.player.pos.y
                ? -_cutAngle
                : flash.pos.y > battle.player.pos.y
                ? _cutAngle
                : 0,
          );
        cut.render(
          canvas,
          size: cut.srcSize * 2,
          anchor: Anchor.center,
          overridePaint: tint,
        );
        canvas.restore();
        continue;
      }
      final frame =
          (HitFlash.lifetime - flash.ticksLeft) *
          sprites.explosion.length ~/
          HitFlash.lifetime;
      sprites.explosion[frame.clamp(0, sprites.explosion.length - 1)].render(
        canvas,
        position: parent.cellCenter(flash.pos),
        size: _size,
        anchor: Anchor.center,
        overridePaint: tint,
      );
    }
  }

  /// Slant of a Foice cut, in radians.
  static const _cutAngle = 0.6;

  /// Recolors a flash: the element's color for tinted ones, blue for the
  /// Pulso EMP's. Fire keeps the art's own orange.
  static Paint? _tint(HitFlash flash) => tintOf(flash.kind, flash.element);

  /// The paint that recolors a flash of [kind] and [element]; null keeps
  /// the art's own colors.
  static Paint? tintOf(FlashKind kind, Element? element) {
    final color = kind == FlashKind.pulse
        ? Pico.blue
        : switch (element) {
            Element.aqua => Pico.blue,
            Element.elec => Pico.yellow,
            Element.wood => Pico.green,
            Element.fire =>
              kind == FlashKind.slash || kind == FlashKind.slashH
                  ? Pico.orange
                  : null,
            _ => null,
          };
    if (color == null) return null;
    return _tints.putIfAbsent(
      color,
      () => Paint()
        ..colorFilter = ColorFilter.mode(
          color.withValues(alpha: 0.7),
          BlendMode.srcATop,
        ),
    );
  }

  static final _tints = <Color, Paint>{};

  /// Outlines of the warned panels and of the panels enemy shots are on
  /// (the cart's warning), under the fighters.
  void _renderGround(Canvas canvas) {
    for (final telegraph in battle.telegraphs) {
      canvas.drawRect(
        parent.cellRect(telegraph.pos).deflate(2),
        telegraph.kind == TelegraphKind.damage ? _danger : _terrain,
      );
    }
    for (final shot in battle.projectiles) {
      if (shot.team != Team.player) {
        canvas.drawRect(parent.cellRect(shot.pos).deflate(2), _danger);
      }
    }
  }
}
