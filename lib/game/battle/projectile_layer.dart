import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../domain/battle/battle_state.dart';
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
  static const double _lobHeight = 28;

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
      if (shot.pos.y != row) continue;
      sprites.shot[_frame ~/ 6 % 2].render(
        canvas,
        position: parent.cellCenter(shot.pos),
        size: _size,
        anchor: Anchor.center,
      );
    }
    for (final lob in battle.lobs) {
      if (lob.to.y != row) continue;
      final from = parent.cellCenter(lob.from.pos);
      final to = parent.cellCenter(lob.to);
      final t = 1 - lob.ticksLeft / lob.flightTicks;
      final at =
          from + (to - from) * t - Vector2(0, _lobHeight * 4 * t * (1 - t));
      canvas
        ..save()
        ..translate(at.x, at.y);
      if (lob.lob case Lob.pickaxe || Lob.molotov) canvas.rotate(-t * 2 * pi);
      (switch (lob.lob) {
        Lob.pickaxe => sprites.pickaxe,
        Lob.molotov => sprites.molotov,
        _ => sprites.ball,
      }).render(canvas, size: _size, anchor: Anchor.center);
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
      if (flash.kind == FlashKind.slash) {
        sprites.slash.render(
          canvas,
          position: parent.cellCenter(flash.pos),
          size: sprites.slash.srcSize * 2,
          anchor: Anchor.center,
        );
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
      );
    }
  }

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
