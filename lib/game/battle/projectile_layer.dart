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
/// Projectiles are short-lived and numerous, so one layer that reads the
/// simulation is simpler than syncing a component per shot.
class ProjectileLayer extends Component with ParentIsA<GridComponent> {
  ProjectileLayer(this.battle, this.sprites) : super(priority: 2);

  final BattleState battle;
  final GameSprites sprites;

  /// Art is drawn at 2x, like the fighters.
  static final Vector2 _size = Vector2.all(32);

  /// Peak height of a lob, in px above the straight line.
  static const double _lobHeight = 28;

  static final _danger = Paint()
    ..color = Pico.red
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  static final _terrain = Paint()
    ..color = Pico.blue
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  int _frame = 0;

  @override
  void update(double dt) => _frame++;

  @override
  void render(Canvas canvas) {
    for (final telegraph in battle.telegraphs) {
      canvas.drawRect(
        parent.cellRect(telegraph.pos).deflate(2),
        telegraph.kind == TelegraphKind.damage ? _danger : _terrain,
      );
    }
    for (final shot in battle.projectiles) {
      // Enemy shots keep the cart's outline on the threatened panel.
      if (shot.team != Team.player) {
        canvas.drawRect(parent.cellRect(shot.pos).deflate(2), _danger);
      }
      sprites.shot[_frame ~/ 6 % 2].render(
        canvas,
        position: parent.cellCenter(shot.pos),
        size: _size,
        anchor: Anchor.center,
      );
    }
    for (final lob in battle.lobs) {
      final from = parent.cellCenter(lob.from.pos);
      final to = parent.cellCenter(lob.to);
      final t = 1 - lob.ticksLeft / lob.flightTicks;
      final at =
          from + (to - from) * t - Vector2(0, _lobHeight * 4 * t * (1 - t));
      canvas
        ..save()
        ..translate(at.x, at.y);
      if (lob.lob == Lob.pickaxe) canvas.rotate(-t * 2 * pi);
      (lob.lob == Lob.pickaxe ? sprites.pickaxe : sprites.ball).render(
        canvas,
        size: _size,
        anchor: Anchor.center,
      );
      canvas.restore();
    }
    for (final flash in battle.flashes) {
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
}
