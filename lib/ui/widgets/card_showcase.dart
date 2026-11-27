import 'dart:math';

import 'package:flame/components.dart' show Sprite, Vector2;
import 'package:flutter/material.dart';

import '../../domain/battle/battle_state.dart'
    show
        FlashKind,
        HitFlash,
        ObstacleKind,
        Status,
        Trail,
        Zap,
        ZapStyle,
        playerAttackCooldown,
        playerLob,
        ticksPerSecond;
import '../../domain/chips/battle_chip.dart';
import '../../domain/chips/chip_library.dart';
import '../../domain/element.dart' as el;
import '../../domain/grid.dart' show GridPos;
import '../../game/battle/chip_fx_layer.dart' show ChipFxLayer;
import '../../game/battle/damage_text.dart'
    show DamageText, GainText, HealBurst;
import '../../game/battle/projectile_layer.dart' show ProjectileLayer;
import '../../game/player_attack_art.dart';
import '../../game/sprites.dart';
import '../theme.dart';
import 'chip_card_view.dart';

/// The one place a card's use is shown outside battle: the player standing,
/// then using [def] the way the battle draws it (see [PlayerAttackArt]),
/// looped, at a bigger scale than the battle's. Used by the deck select,
/// and through [CardPreview] by the Compêndio and the run's deck.
class CardShowcase extends StatefulWidget {
  const CardShowcase({super.key, required this.sprites, required this.def});

  final GameSprites sprites;
  final ChipDef def;

  /// Art pixel size on screen.
  static const scale = 2.0;

  /// The box, in art pixels: room past the player for the weapon and beam.
  static const box = Size(80, 52);

  @override
  State<CardShowcase> createState() => _CardShowcaseState();
}

class _CardShowcaseState extends State<CardShowcase>
    with SingleTickerProviderStateMixin {
  /// Standing for the first half, attacking for the second.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  late PlayerAttackArt _art = PlayerAttackArt(widget.sprites, widget.def);

  @override
  void didUpdateWidget(CardShowcase old) {
    super.didUpdateWidget(old);
    if (old.def == widget.def && old.sprites == widget.sprites) return;
    _art = PlayerAttackArt(widget.sprites, widget.def);
    // A new card shows its attack right away.
    _loop
      ..value = 0.5
      ..repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scanlines(
    child: AnimatedBuilder(
      animation: _loop,
      builder: (context, _) => CustomPaint(
        size: CardShowcase.box * CardShowcase.scale,
        painter: _ShowcasePainter(
          sprites: widget.sprites,
          art: _art,
          t: _loop.value,
        ),
      ),
    ),
  );
}

/// A card zoomed in: shown big beside its [CardShowcase], over a dimmed
/// screen. A tap anywhere (or Esc) calls [onClose]. Shared by the Compêndio
/// and the run's deck view, so each only keeps which card is open.
class CardPreview extends StatelessWidget {
  const CardPreview({
    super.key,
    required this.def,
    required this.sprites,
    required this.onClose,
  });

  final ChipDef def;
  final GameSprites sprites;
  final VoidCallback onClose;

  /// The big card's width.
  static const cardWidth = 96.0;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      DismissIntent: CallbackAction<DismissIntent>(
        onInvoke: (_) {
          onClose();
          return null;
        },
      ),
    },
    child: Focus(
      autofocus: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: ColoredBox(
          color: Pico.black.withValues(alpha: 0.8),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChipCardView(
                  def: def,
                  sprites: sprites,
                  width: cardWidth,
                  focusable: false,
                ),
                const SizedBox(width: 8),
                CardShowcase(sprites: sprites, def: def),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Draws the showcase in art pixels. What the card puts on screen follows
/// the battle: the same streaks, rings, flashes and beams (drawn by the
/// battle's own layers' helpers), aimed at an imagined enemy [_foe].
class _ShowcasePainter extends CustomPainter {
  _ShowcasePainter({required this.sprites, required this.art, required this.t});

  final GameSprites sprites;
  final PlayerAttackArt art;

  /// Where in the loop, 0 to 1.
  final double t;

  static final _pixel = Paint()..filterQuality = FilterQuality.none;

  /// The player's left edge in the box, in art pixels.
  static const _left = 4.0;

  static const _center = 12.0;

  /// The box's right edge, from the player's left edge.
  static final _end = CardShowcase.box.width - _left;

  /// Seconds of the attack half of the loop, and of the whole loop.
  static const _attackSeconds = 0.7;
  static const _loopMs = 1400;

  /// When a shot or a lob gets to its panel, as a share of the attack.
  static const _arrival = 0.5;

  /// Peak of a lob over the straight line, in art pixels.
  static const _lobHeight = 8.0;

  /// The enemy shots and streaks go for, two panels ahead, and the one a
  /// hit jumps to, a row down; as the battle's (columns, rows) from the
  /// player.
  static const _foe = GridPos(2, 0);
  static const _nextFoe = GridPos(2, 1);

  /// Investida's ghost.
  static final _ghost = Paint()..filterQuality = FilterQuality.none;

  static final _smoke = Paint();

  /// A panel's middle, in art pixels from the player's left edge; [cell]
  /// counts columns ahead and rows down from the player, as in the battle.
  static Offset _cell(GridPos cell) =>
      Offset(12 + cell.x * _panel, 12 + cell.y * _panel);

  /// A panel's size in the showcase, in art pixels.
  static const _panel = 16.0;

  /// Ticks the player takes to glide back on a recoil, about as long as
  /// the battle's view takes.
  static const _glideTicks = 5;

  /// Where the player stands when using the card: a panel ahead per panel
  /// a recoil (Salto Acrobático) takes them back, so they land at the
  /// box's usual spot.
  Offset get _start => switch (art.def.effect) {
    MeleeEffect(:final recoil) when recoil > 0 => Offset(_panel * recoil, 0),
    _ => Offset.zero,
  };

  static Offset _offset(Vector2 v) => Offset(v.x, v.y);

  /// Battle ticks since [age] (0 to 1 over the attack) began.
  static int _ticks(double age) =>
      (age * _attackSeconds * ticksPerSecond).floor();

  void _draw(Canvas canvas, Sprite sprite, Offset at, {Paint? paint}) =>
      canvas.drawImageRect(
        sprite.image,
        sprite.src,
        at & sprite.src.size,
        paint ?? _pixel,
      );

  /// Draws [sprite] centered on [at].
  void _drawCentered(Canvas canvas, Sprite sprite, Offset at, {Paint? paint}) =>
      _draw(
        canvas,
        sprite,
        at - Offset(sprite.src.width / 2, sprite.src.height / 2),
        paint: paint,
      );

  /// Runs [draw] in the battle's pixels (2 per art pixel), for the battle
  /// layers' helpers.
  static void _inBattlePixels(Canvas canvas, void Function() draw) {
    canvas
      ..save()
      ..scale(0.5);
    draw();
    canvas.restore();
  }

  static Vector2 _battle(Offset art) => Vector2(art.dx, art.dy) * 2;

  /// When the card's hits land, as a share of the attack.
  double get _hitAt => switch (art.def) {
    ChipDef(lobs: true) => _arrival,
    final ChipDef def when def.firesShots => _arrival,
    _ => 0,
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..scale(CardShowcase.scale);
    if (t < 0.5) {
      canvas.translate(_left, _center);
      _draw(canvas, sprites.playerIdle, _start);
      canvas.restore();
      return;
    }
    final age = (t - 0.5) * 2;
    final def = art.def;
    // Martelo Sísmico and the like shake the picture on the hit.
    if (def.fx == ChipFx.quake && age >= _hitAt && age < _hitAt + 0.25) {
      canvas.translate((t * 60).floor().isEven ? 1 : -1, 0);
    }
    canvas.translate(_left, _center);
    final ticks = _ticks(age);
    // A new shape for the bolts every 60 ms, like the battle's.
    final shape = Random((t * _loopMs / 60).floor());
    _player(canvas, ticks);
    // The blow lands from where the card was used, before any recoil.
    canvas
      ..save()
      ..translate(_start.dx, _start.dy);
    _effects(canvas, age, ticks, shape);
    canvas.restore();
    _onPlayer(canvas, age);
    canvas.restore();
  }

  /// What shows over the player in battle: the heal's green crosses and
  /// amount ("+X"), the Energy a card gives ("+X En.", "+X En. Max"), or
  /// the attack bonus it leaves for the next attacks ("+X").
  void _onPlayer(Canvas canvas, double age) {
    final effect = art.def.effect;
    final heals = switch (effect) {
      HealEffect() || CleanseEffect() || EmergencyHealEffect() => true,
      SelfStatusEffect(status: Status.regen) => true,
      MeleeEffect(lifesteal: true) => true,
      _ => false,
    };
    // The amount, when the card says it (regen and lifesteal vary).
    final healed = switch (effect) {
      HealEffect(:final amount) => amount,
      CleanseEffect(:final heal) => heal,
      EmergencyHealEffect(:final normal) => normal,
      _ => null,
    };
    final energy = GainText.energyOf(effect);
    final bonus = switch (effect) {
      DamageBoostEffect(:final amount) => amount,
      AttackChargesEffect(:final amount) => amount,
      _ => 0,
    };
    if (!heals && energy == null && bonus == 0) return;
    final seconds = age * _attackSeconds;
    // In the battle's pixels, where the texts are sized: the player's
    // 24px frame is 48 there, its feet's middle at (24, 48).
    _inBattlePixels(canvas, () {
      // A gain rising from over the head, like a damage number.
      void gain(String text, Color color) {
        if (seconds >= DamageText.lifetime) return;
        final t = seconds / DamageText.lifetime;
        DamageText.paintText(
          canvas,
          text,
          Vector2(24, -DamageText.defaultRise * t),
          color,
          t,
          8,
        );
      }

      if (heals) {
        HealBurst.paint(canvas, Vector2(24, 48), Vector2.all(48), seconds);
      }
      if (healed != null) gain(GainText.heal(healed), GainText.healColor);
      if (energy != null) gain(energy, GainText.energyColor);
      if (bonus > 0) {
        DamageText.paintText(
          canvas,
          '+$bonus',
          Vector2(24, 12),
          Pico.yellow,
          0,
          12,
        );
      }
    });
  }

  /// The attack frame and what is in the fist. Investida dashes a panel
  /// ahead and the Salto Acrobático glides back one after its blow, both
  /// leaving a fading ghost where they were, like the battle's trail.
  void _player(Canvas canvas, int ticks) {
    var at = Offset.zero;
    Offset? ghost;
    if (art.def.effect is DashEffect) {
      at = const Offset(_panel, 0);
      ghost = Offset.zero;
    } else if (_start != Offset.zero) {
      at = Offset.lerp(_start, Offset.zero, min(1, ticks / _glideTicks))!;
      ghost = _start;
    }
    if (ghost != null) {
      final fade = 1 - ticks / Trail.lifetime;
      if (fade > 0) {
        _ghost.color = Pico.blue.withValues(alpha: 0.5 * fade);
        _draw(canvas, sprites.playerIdle, ghost, paint: _ghost);
      }
    }
    // Drawn in the battle's order: body, then what's in the fist.
    _draw(canvas, art.body, at);
    final held = art.held;
    final heldAt = art.heldAt;
    if (held != null && heldAt != null) {
      _draw(canvas, held, at + _offset(heldAt));
    }
  }

  void _effects(Canvas canvas, double age, int ticks, Random shape) {
    final def = art.def;
    final effect = def.effect;
    // Like the muzzle flash, from the end of what is in the fist.
    final hand = _offset(art.emitter);
    final foe = _cell(_foe);
    // Down its own row, a streak stays level with the hand.
    final foeLevel = Offset(foe.dx, hand.dy);

    if (art.muzzleAt case final at?
        when ticks < playerAttackCooldown &&
            def.fx != ChipFx.beam &&
            def.fx != ChipFx.bolt) {
      _draw(canvas, art.muzzle, _offset(at));
    }

    // Streaks out of the hand, as the card is used.
    if (ticks < Zap.lifetime) {
      switch (effect) {
        case KindStrikeEffect():
          _zap(canvas, ZapStyle.bolt, hand, foeLevel, shape, def.corFx);
        case SweepEffect():
          for (final row in const [-1, 0, 1]) {
            final to = _cell(GridPos(_foe.x, row));
            _zap(
              canvas,
              ZapStyle.laser,
              hand,
              row == 0 ? foeLevel : to,
              shape,
              def.corFx,
            );
          }
        case TractorEffect():
          _zap(canvas, ZapStyle.tractor, hand, foeLevel, shape, def.corFx);
        case MeleeEffect(:final pattern) when def.fx == ChipFx.bolt:
          // Sparks to every panel hit (Cacetete, Chicote).
          for (final cell in pattern) {
            final to = _cell(cell);
            _zap(
              canvas,
              ZapStyle.bolt,
              hand,
              cell.y == 0 ? Offset(to.dx, hand.dy) : to,
              shape,
              def.corFx,
            );
          }
        default:
          break;
      }
    }

    if (def.fx == ChipFx.rings) {
      _inBattlePixels(
        canvas,
        () => ChipFxLayer.drawRings(canvas, _battle(hand), 3, ticks),
      );
    }

    if (def.fx == ChipFx.glitch && ticks < 2 * Zap.lifetime) {
      final body = Rect.fromCenter(center: foe, width: 24, height: 24);
      _inBattlePixels(
        canvas,
        () => ChipFxLayer.drawStatic(
          canvas,
          Rect.fromLTRB(
            body.left * 2,
            body.top * 2,
            body.right * 2,
            body.bottom * 2,
          ),
          shape,
        ),
      );
    }

    if (def.fx == ChipFx.beam) _beam(canvas, hand, age, effect);

    switch (effect) {
      case MeleeEffect(:final pattern, :final slash, :final slashH):
        _melee(canvas, pattern, slash: slash, slashH: slashH, ticks: ticks);
      case DashEffect(
        melee: MeleeEffect(:final pattern, :final slash, :final slashH),
      ):
        // From the panel it dashed to.
        _melee(
          canvas,
          [for (final cell in pattern) cell + const GridPos(1, 0)],
          slash: slash,
          slashH: slashH,
          ticks: ticks,
        );
      case RowStrikeEffect():
        for (var x = 1; x <= 3; x++) {
          _blast(canvas, _cell(GridPos(x, 0)), ticks, onFoe: x == _foe.x);
        }
      case KindStrikeEffect() || SweepEffect():
        for (final row in effect is SweepEffect ? const [-1, 0, 1] : [0]) {
          _blast(canvas, _cell(GridPos(_foe.x, row)), ticks, onFoe: true);
        }
      case SpawnObstacleEffect(:final kind):
        _summon(canvas, kind);
      default:
        if (def.lobs) {
          _lob(canvas, hand, age, shape);
        } else if (def.firesShots) {
          _shot(canvas, hand, foeLevel, age, shape);
        } else if (def.fx == ChipFx.sniper && ticks < Zap.lifetime) {
          _zap(
            canvas,
            ZapStyle.tracer,
            hand,
            Offset(foeLevel.dx, hand.dy),
            shape,
            def.corFx,
          );
        }
    }
  }

  /// The Holograma's look in battle: see-through and blue.
  static final _hologram = Paint()
    ..filterQuality = FilterQuality.none
    ..colorFilter = ColorFilter.mode(
      Pico.blue.withValues(alpha: 0.5),
      BlendMode.srcATop,
    )
    ..color = const Color(0xB0FFFFFF);

  /// A mine on its panel, see-through like the battle's.
  static final _mine = Paint()
    ..filterQuality = FilterQuality.none
    ..color = Pico.white.withValues(alpha: 0.6);

  /// What the card lays, standing on the panel ahead as the battle draws
  /// it once there; nothing is drawn flying to it. A mine lies on the
  /// floor, the size of a panel's mark.
  void _summon(Canvas canvas, ObstacleKind kind) {
    final x = _cell(_foe).dx;
    if (kind == ObstacleKind.mine) {
      final mine = sprites.chip(Chips.mine);
      canvas.drawImageRect(
        mine.image,
        mine.src,
        Rect.fromCenter(center: Offset(x, 16), width: 16, height: 16),
        _mine,
      );
      return;
    }
    final sprite = sprites.obstacle(kind, element: art.def.tint);
    // Feet on the player's feet line, the box's bottom.
    _draw(
      canvas,
      sprite,
      Offset(
        x - sprite.src.width / 2,
        CardShowcase.box.height / 2 - sprite.src.height,
      ),
      paint: kind == ObstacleKind.decoy ? _hologram : null,
    );
  }

  void _zap(
    Canvas canvas,
    ZapStyle style,
    Offset from,
    Offset to,
    Random shape,
    Color corFx,
  ) => _inBattlePixels(
    canvas,
    () => ChipFxLayer.drawZap(
      canvas,
      style,
      _battle(from),
      _battle(to),
      shape,
      corFx,
    ),
  );

  /// A blow on [pattern]'s panels: a hit flash on the enemy, or the
  /// Foice's cuts, the sword's vertical slash in front ([slash]) or the
  /// polearm's horizontal one across the 2 panels in front ([slashH]).
  void _melee(
    Canvas canvas,
    List<GridPos> pattern, {
    required bool slash,
    required bool slashH,
    required int ticks,
  }) {
    final def = art.def;
    final front = GridPos(pattern.first.x, 0);
    final tint = ProjectileLayer.tintOf(
      slashH ? FlashKind.slashH : FlashKind.slash,
      def.tint == el.Element.neutral ? null : def.tint,
    );
    if (slash && ticks < HitFlash.lifetime) {
      _drawCentered(canvas, sprites.slash, _cell(front), paint: tint);
    }
    if (slashH && ticks < HitFlash.lifetime) {
      // Centered between its panel and the next, as in battle.
      final at = (_cell(front) + _cell(front + const GridPos(1, 0))) / 2;
      _drawCentered(canvas, sprites.slashH, at, paint: tint);
    }
    for (final cell in pattern) {
      if (def.fx == ChipFx.cut && ticks < HitFlash.lifetime) {
        _cut(canvas, cell);
      }
      // The battle draws no flash under a slash or a cut.
      //if (!slash && !slashH && def.fx != ChipFx.cut) {
      if (def.fx == ChipFx.quake) {
        _blast(
          canvas,
          _cell(cell) + Offset(0, 4),
          ticks,
          onFoe: cell == _meleeFoe(pattern),
        );
      }
    }
  }

  /// Half the slash on [cell], leaning toward it, as the battle's.
  void _cut(Canvas canvas, GridPos cell) {
    final at = _cell(cell);
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(cell.y < 0 ? -0.6 : (cell.y > 0 ? 0.6 : 0));
    _drawCentered(canvas, sprites.cut, Offset.zero);
    canvas.restore();
  }

  /// The imagined enemy a blow of [pattern] hits: right in front of the
  /// player's row (the panel ahead nearest them), or none if the blow
  /// misses their row.
  static GridPos? _meleeFoe(List<GridPos> pattern) {
    GridPos? foe;
    for (final cell in pattern) {
      if (cell.y == 0 && (foe == null || cell.x < foe.x)) foe = cell;
    }
    return foe;
  }

  /// The 4-frame hit flash on [at], [ticks] after the hit, in the colors
  /// the card's flashes take. As in battle, it shows only where the hit
  /// lands on someone ([onFoe]: an imagined enemy stands there), or on
  /// every panel for an explosion ([ChipDef.explodes]).
  void _blast(Canvas canvas, Offset at, int ticks, {bool onFoe = false}) {
    final def = art.def;
    if (!onFoe && !def.explodes) return;
    if (ticks < 0 || ticks >= HitFlash.lifetime) return;
    final kind = def.fx == ChipFx.pulse ? FlashKind.pulse : FlashKind.explosion;
    final element = def.fx == ChipFx.blast ? def.tint : null;
    final frames = sprites.explosion;
    final frame = (ticks * frames.length ~/ HitFlash.lifetime).clamp(
      0,
      frames.length - 1,
    );
    _drawCentered(
      canvas,
      frames[frame],
      at,
      paint: ProjectileLayer.tintOf(kind, element),
    );
  }

  /// A shot from the hand to [to], then what its hit does there.
  /// The Gancho, as in battle: no shot, its chain reaches from the
  /// weapon's end to [to], hits (a flash there), stays on the target being
  /// pulled in, then winds back into the hand.
  void _hook(Canvas canvas, Offset hand, Offset to, double age, Random shape) {
    final Offset end;
    if (age < _arrival) {
      end = Offset.lerp(hand, to, age / _arrival)!;
    } else {
      // Like the battle's chain zap: holds its first half, winds back its
      // second.
      final held = (age - _arrival) / (1 - _arrival);
      end = Offset.lerp(to, hand, (held * 2 - 1).clamp(0.0, 1.0))!;
      _blast(canvas, _cell(_foe), _ticks(age - _arrival), onFoe: true);
    }
    _zap(canvas, ZapStyle.chain, hand, end, shape, art.def.corFx);
  }

  void _shot(Canvas canvas, Offset hand, Offset to, double age, Random shape) {
    final def = art.def;
    if (def.effect is PullEffect) {
      _hook(canvas, hand, to, age, shape);
      return;
    }
    if (age < _arrival) {
      final f = age / _arrival;
      final at = Offset.lerp(hand, to, f)!;
      if (def.fx == ChipFx.smoke) _smokeTrail(canvas, hand, to, f);
      // The beam covers its own shots.
      if (def.fx != ChipFx.beam && def.fx != ChipFx.bolt) {
        _drawCentered(
          canvas,
          def.fx == ChipFx.spear
              ? sprites.spear
              : sprites.shot[(age * 10).floor() % 2],
          at,
        );
      }
      // Arco Voltaico: lightning from the hand to the shot.
      if (def.fx == ChipFx.bolt) {
        _zap(canvas, ZapStyle.bolt, hand, at, shape, def.corFx);
      }
      if (def.fx == ChipFx.sniper && age < _arrival / 2) {
        _zap(
          canvas,
          ZapStyle.tracer,
          hand,
          Offset(_end, hand.dy),
          shape,
          def.corFx,
        );
      }
      return;
    }
    final ticks = _ticks(age - _arrival);
    final foe = _cell(_foe);
    final next = _cell(_nextFoe);
    final pattern = switch (def.effect) {
      ProjectileEffect(:final pattern) => pattern,
      _ => const [GridPos(0, 0)],
    };
    for (final cell in pattern) {
      _blast(
        canvas,
        _cell(_foe + cell) + Offset(0, -3),
        ticks,
        onFoe: cell == const GridPos(0, 0),
      );
    }
    if (ticks >= Zap.lifetime) return;
    switch (def.effect) {
      // Ricochete, Arco Voltaico, Condutor: the hit jumps on.
      case BounceEffect() || ConductorEffect()
          when def.fx == ChipFx.bolt || def.fx == ChipFx.tracer:
        _zap(
          canvas,
          def.fx == ChipFx.bolt ? ZapStyle.bolt : ZapStyle.tracer,
          foe,
          next,
          shape,
          def.corFx,
        );
        _blast(canvas, next, ticks, onFoe: true);
      default:
        break;
    }
  }

  /// A ball (a rocket, with smoke) arcing from the hand to the panel in
  /// front of [_foe], then the blast there.
  void _lob(Canvas canvas, Offset hand, double age, Random shape) {
    final def = art.def;
    final landing = _cell(_foe);
    Offset at(double f) =>
        Offset.lerp(hand, landing, f)! -
        Offset(0, _lobHeight * 4 * f * (1 - f));
    if (age < _arrival) {
      final f = age / _arrival;
      if (def.fx == ChipFx.smoke) {
        for (var i = 1; i <= 3; i++) {
          final back = f - i * 0.1;
          if (back > 0) _puff(canvas, at(back), i / 4);
        }
      }
      // What the battle throws with this card, turned the same way.
      final lob = playerLob(def);
      final here = at(f);
      canvas
        ..save()
        ..translate(here.dx, here.dy)
        ..rotate(
          ProjectileLayer.lobTurn(
            lob,
            _battle(hand),
            _battle(landing),
            f,
            tumbles: sprites.tumbles(lob, chip: def),
            height: _lobHeight * 2,
          ),
        );
      _drawCentered(canvas, sprites.lobbed(lob, chip: def), Offset.zero);
      canvas.restore();
      return;
    }
    // Rocks, mines and the TNT are only laid there.
    final pattern = switch (def.effect) {
      GrenadeEffect(:final pattern) => pattern,
      ProjectileEffect(:final pattern) => pattern,
      _ => null,
    };
    if (pattern == null) return;
    final ticks = _ticks(age - _arrival);
    for (final cell in pattern) {
      _blast(
        canvas,
        _cell(_foe + cell),
        ticks,
        onFoe: cell == const GridPos(0, 0),
      );
    }
  }

  /// Smoke puffs behind a shot at [f] of its way from [from] to [to].
  void _smokeTrail(Canvas canvas, Offset from, Offset to, double f) {
    for (var i = 1; i <= 3; i++) {
      final back = f - i * 0.1;
      if (back > 0) _puff(canvas, Offset.lerp(from, to, back)!, i / 4);
    }
  }

  /// A gray puff [age] (0 to 1) into its life: it swells as it fades.
  void _puff(Canvas canvas, Offset at, double age) {
    _smoke.color = Pico.lightGray.withValues(alpha: 1 - age);
    final size = (2 + 3 * age).roundToDouble();
    canvas.drawRect(
      Rect.fromCenter(center: at, width: size, height: size),
      _smoke,
    );
  }

  /// Down the row from the hand in the card's color, like the battle's:
  /// swells in, flickers, thins out. A row strike's goes through.
  void _beam(Canvas canvas, Offset hand, double age, ChipEffect effect) {
    final end = effect is RowStrikeEffect ? _end : _cell(_foe).dx;
    final swell = min(1.0, min(age, 1 - age) * 6 + 0.2);
    final flicker = (t * 40).floor().isEven ? 0.5 : 0.0;
    final (outer, middle, inner) = ChipFxLayer.beamColors[art.def.tint]!;
    // The battle's half heights, in art pixels.
    for (final (i, (paint, half)) in [
      (outer, 4.0),
      (middle, 2.5),
      (inner, 1.0),
    ].indexed) {
      final h = (half + (i < 2 ? flicker : 0)) * swell;
      canvas
        ..drawCircle(hand + Offset(3, 0), h * 1.25, paint)
        ..drawCircle(Offset(end, hand.dy), h * 1.25, paint)
        ..drawRect(
          Rect.fromLTRB(hand.dx + 3, hand.dy - h, end, hand.dy + h),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_ShowcasePainter old) => old.t != t || old.art != art;
}
