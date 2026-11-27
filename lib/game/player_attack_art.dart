import 'package:flame/components.dart';

import '../domain/chips/battle_chip.dart';
import 'sprites.dart';

/// The player's attack frame while using [def], laid out in art pixels from
/// the sprite's top-left corner: the body, what the fist holds and where
/// the muzzle flash goes.
///
/// The one source for that layout, shared by the battle's
/// `FighterComponent` and the deck select's showcase; each draws it at its
/// own scale and in its own order.
class PlayerAttackArt {
  PlayerAttackArt(GameSprites sprites, this.def)
    : body = sprites.playerPose(def.pose),
      held = sprites.held(def),
      muzzle = sprites.muzzle,
      _barrelTip = sprites.barrelTip(def);

  final ChipDef def;

  /// The pose's frame (see `GameSprites.playerPose`).
  final Sprite body;

  /// The card's weapon or gun; null for cards used bare-handed.
  final Sprite? held;

  final Sprite muzzle;

  /// Where the gun fires from, in the gun's art pixels.
  final Vector2? _barrelTip;

  /// The fist in each attack frame that holds something, in art pixels.
  /// Only these poses draw what the card holds (`SpriteFiles.held`).
  static final _fists = <ChipPose, Vector2>{
    ChipPose.melee: Vector2(22, 9),
    // The hand at the end of the arm swung down to the right.
    ChipPose.melee2: Vector2(20, 15),
    ChipPose.shoot: Vector2(15, 9),
  };

  /// Where the fist grips what it holds, in the held art's pixels, for
  /// poses that don't hold it by its left edge's middle row (guns, and
  /// blades drawn level): melee2 holds the weapon art drawn diagonally by
  /// its handle, at the top-left corner (the sword's handle crosses its
  /// guard at (1, 1)).
  static final _grips = <ChipPose, Vector2>{ChipPose.melee2: Vector2(1, 1)};

  /// The flash's own pixel that touches the barrel: its left edge, on the
  /// row of the burst's point.
  static final _muzzleRoot = Vector2(0, 3);

  /// The flash in front of a bare hand, for shots without a gun.
  static final _bareMuzzle = Vector2(21.5, 5.5);

  /// Where beams, bolts, streaks and rings leave a bare hand, in art
  /// pixels: just past the front of the 24px frame, level with the fist.
  /// With something in the fist they leave its end ([emitter]).
  static final hand = Vector2(26, 9);

  /// Where beams, bolts, streaks and rings leave the player, in art
  /// pixels, like the muzzle flash: the gun's barrel tip, the far end of a
  /// melee weapon (its right edge, middle row), or [hand] when nothing is
  /// held.
  Vector2 get emitter {
    final at = heldAt;
    final item = held;
    if (at == null || item == null) return hand;
    if (_barrelTip case final tip?) return at + tip;
    return at + Vector2(item.srcSize.x, (item.srcSize.y ~/ 2).toDouble());
  }

  /// Firing gets the muzzle flash; swings and tosses don't.
  bool get shoots => def.pose == ChipPose.shoot;

  /// Top-left corner of [held], its grip on the fist: the pose's own grip
  /// ([_grips]), or its left edge's middle row. Null when nothing is held.
  Vector2? get heldAt {
    final fist = _fists[def.pose];
    final item = held;
    if (fist == null || item == null) return null;
    final grip =
        _grips[def.pose] ?? Vector2(0, (item.srcSize.y ~/ 2).toDouble());
    return fist - grip;
  }

  /// Top-left corner of the muzzle flash: from the gun's tip, or in front
  /// of the bare hand without one. Only Projectile cards flash: null for
  /// the others (energy shots, blows) and for poses that don't fire.
  Vector2? get muzzleAt {
    if (!shoots || def.family != ChipFamily.projectile) {
      if (def.fx != ChipFx.muzzle) return null;
    }
    final at = heldAt;
    final tip = _barrelTip;
    if (at == null || tip == null) return _bareMuzzle;
    return at + tip - _muzzleRoot;
  }
}
