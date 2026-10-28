import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/chips/battle_chip.dart';
import '../../domain/grid.dart';
import '../star_cop_game.dart';
import '../../ui/feedback.dart';
import '../../ui/theme.dart';
import 'battle_sounds.dart';
import 'damage_text.dart';
import 'fighter_component.dart';
import 'grid_component.dart';
import 'projectile_layer.dart';
import 'shield_link_layer.dart';

/// Flame side of one battle: steps [battle] at a fixed rate, turns keys and
/// touch into [PlayerInput] and keeps one [FighterComponent] per living
/// fighter.
///
/// Touch: swipe moves, tapping a chip uses it (held: fusion charge).
/// Keyboard: arrows/WASD move, X/K use chip, Z/J cycle chip.
class BattleWorld extends World
    with KeyboardHandler, HasGameReference<StarCopGame> {
  BattleWorld({required this.battle, required this.onFinished});

  final BattleState battle;

  /// Called once, about a second after the battle is won or lost.
  final void Function(BattleState battle) onFinished;

  /// Bumped every simulation tick so Flutter overlays can rebuild.
  final ValueNotifier<int> revision = ValueNotifier(0);

  static const double _step = 1 / ticksPerSecond;
  static const double _endDelay = 1;

  late final GridComponent _grid;
  final Map<Fighter, FighterComponent> _views = {};
  double _accumulator = 0;
  double _endTimer = 0;
  bool _finished = false;

  /// Seconds of screen shake left, after the player is hurt.
  double _shake = 0;
  static const double _shakeTime = 0.25;

  /// Px the grid moves at most while shaking.
  static const double _shakeAmplitude = 3;
  final _random = Random();
  final _sounds = BattleSounds();

  int _keyDx = 0;
  int _keyDy = 0;
  bool _usePressed = false;
  bool _useHeld = false;
  bool _cyclePressed = false;

  /// A touch can land while the player is still in a move or attack
  /// cooldown, which ignores input; it is kept for this many ticks instead
  /// of being lost.
  static const int _touchBufferTicks = 8;

  (int, int) _swipe = (0, 0);
  int _swipeTicks = 0;

  /// Kept by reference: a refill between the tap and the tick reorders the
  /// hand.
  ChipCard? _tapped;
  int _tappedTicks = 0;
  bool _touchHeld = false;

  /// One cell in direction ([dx], [dy]).
  void swipe(int dx, int dy) {
    _swipe = (dx, dy);
    _swipeTicks = _touchBufferTicks;
  }

  /// Uses [card] on the next tick that can; held down it charges a fusion
  /// until [releaseChip].
  void pressChip(ChipCard card) {
    _tapped = card;
    _tappedTicks = _touchBufferTicks;
    _touchHeld = true;
  }

  void releaseChip() => _touchHeld = false;

  @override
  Future<void> onLoad() async {
    _grid = GridComponent(
      battle: battle,
      sprites: game.sprites,
      position: GridComponent.origin,
    );
    await add(_grid);
    await _grid.addAll([
      ProjectileLayer.ground(battle, game.sprites),
      for (var row = 0; row < gridRows; row++)
        ProjectileLayer.row(battle, game.sprites, row),
      ShieldLinkLayer(battle, (fighter) => _views[fighter]),
    ]);
    _syncViews();
  }

  @override
  void onRemove() {
    revision.dispose();
    super.onRemove();
  }

  /// The damage number over [target]; hurting the player also shakes the
  /// screen and vibrates.
  void _showHit(Fighter target, int amount) {
    final view = _views[target];
    final head = view == null
        ? _grid.cellCenter(target.pos)
        : view.position - Vector2(0, view.size.y);
    _grid.add(
      DamageText(
        amount,
        position: head + Vector2(_random.nextDouble() * 8 - 4, 0),
        color: target is PlayerFighter ? Pico.red : Pico.white,
      ),
    );
    if (target is PlayerFighter) {
      hurtFeedback();
      _shake = _shakeTime;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_shake > 0) {
      _shake -= dt;
      _grid.position = _shake <= 0
          ? GridComponent.origin.clone()
          : GridComponent.origin +
                (Vector2.random(_random) - Vector2.all(0.5)) *
                    (2 * _shakeAmplitude);
    }
    if (game.halted || battle.peekOpen) return;
    if (battle.isOver) {
      _endTimer += dt;
      if (!_finished && _endTimer >= _endDelay) {
        _finished = true;
        onFinished(battle);
      }
      return;
    }

    // Fixed timestep: same behaviour at 60 Hz, 120 Hz or a stuttering frame.
    _accumulator = min(_accumulator + dt, 0.25);
    var ticked = false;
    while (_accumulator >= _step) {
      _accumulator -= _step;
      var (dx, dy) = (_keyDx, _keyDy);
      if (dx == 0 && dy == 0 && _swipeTicks > 0) (dx, dy) = _swipe;
      var useChip = _usePressed;
      final tapped = _tapped;
      if (tapped != null && _tappedTicks > 0 && battle.hand.contains(tapped)) {
        battle.selectChip(battle.hand.indexOf(tapped));
        useChip = true;
      }
      final from = battle.player.pos;
      battle.tick(
        PlayerInput(
          dx: dx,
          dy: dy,
          useChip: useChip,
          holdUse: _useHeld || _touchHeld,
          cycleChip: _cyclePressed,
        ),
      );
      for (final hit in battle.hits) {
        _showHit(hit.target, hit.amount);
      }
      _sounds.afterTick(battle);
      _usePressed = _cyclePressed = false;
      // Consumed once it moved, or once the chip left the hand or began
      // charging.
      _swipeTicks = battle.player.pos != from ? 0 : _swipeTicks - 1;
      if (tapped != null &&
          (!battle.hand.contains(tapped) || battle.chargingCard == tapped)) {
        _tapped = null;
      }
      _tappedTicks--;
      ticked = true;
    }
    if (!ticked) return;

    _syncViews();
    revision.value++;
  }

  void _syncViews() {
    final alive = battle.units.toSet();
    for (final fighter in alive) {
      _views.putIfAbsent(fighter, () {
        final view = FighterComponent(fighter, game.sprites);
        _grid.add(view);
        return view;
      });
    }
    _views.removeWhere((fighter, view) {
      if (alive.contains(fighter)) return false;
      view.removeFromParent();
      return true;
    });
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    bool held(List<LogicalKeyboardKey> keys) => keys.any(keysPressed.contains);

    _keyDx =
        (held([LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD])
            ? 1
            : 0) -
        (held([LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA]) ? 1 : 0);
    _keyDy =
        (held([LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS])
            ? 1
            : 0) -
        (held([LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW]) ? 1 : 0);

    _useHeld = held([LogicalKeyboardKey.keyX, LogicalKeyboardKey.keyK]);
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.keyX || key == LogicalKeyboardKey.keyK) {
        _usePressed = true;
      } else if (key == LogicalKeyboardKey.keyZ ||
          key == LogicalKeyboardKey.keyJ) {
        _cyclePressed = true;
      }
    }
    return true;
  }
}
