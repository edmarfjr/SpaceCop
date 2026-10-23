import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/battle/battle_state.dart';
import '../../game/battle/battle_world.dart';
import '../../game/star_cop_game.dart';
import '../../game/sprites.dart';
import '../theme.dart';
import '../widgets/chip_card_view.dart';

/// HP, gauge, Energy and the current hand, drawn by Flutter over the grid.
///
/// Lives in the 384x192 battle screen: status in y 0-40 over the grid, the
/// hand in a row at the bottom right (see DESIGN.md). Rebuilds
/// on [BattleWorld.revision] (once per simulation tick) and only reads the
/// battle; swipes and chip presses go back through the [BattleWorld].
class BattleHud extends StatelessWidget {
  const BattleHud({super.key, required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) {
    final world = game.battleWorld;
    if (world == null) return const SizedBox.shrink();
    final battle = world.battle;

    return ValueListenableBuilder<int>(
      valueListenable: world.revision,
      builder: (context, _, _) => Stack(
        children: [
          // Behind everything else, so the chips and icons get their taps.
          Positioned.fill(child: _SwipeArea(world: world)),
          Positioned(
            top: 2,
            left: _gridLeft,
            width: _gridWidth,
            child: _TopBar(battle: battle),
          ),
          Positioned(
            top: 14,
            left: _gridLeft,
            width: _gridWidth,
            child: _Info(battle: battle),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Row(
              children: [
                _IconButton(icon: Icons.style, onTap: game.showDeck),
                const SizedBox(width: 4),
                _IconButton(icon: Icons.pause, onTap: game.pause),
              ],
            ),
          ),
          Positioned(
            bottom: 2,
            right: 2,
            child: _Hand(world: world, sprites: game.sprites),
          ),
          // The battle waits for this choice, so it covers everything.
          if (battle.peekCards.isNotEmpty)
            Positioned.fill(
              child: _PeekPopup(world: world, sprites: game.sprites),
            ),
        ],
      ),
    );
  }

  /// The status lines up with the grid (`GridComponent.origin`, 6 cells of
  /// 40).
  static const double _gridLeft = 72;
  static const double _gridWidth = 240;
}

/// Swipe anywhere but the hand and icons: every [_step] px of drag in one
/// direction moves one cell, so a long drag keeps walking, at most one cell
/// per [_repeatDelay].
///
/// A raw [Listener] (no gesture arena), so holding a chip for a fusion with
/// one finger doesn't cancel a swipe with the other.
class _SwipeArea extends StatefulWidget {
  const _SwipeArea({required this.world});

  final BattleWorld world;

  @override
  State<_SwipeArea> createState() => _SwipeAreaState();
}

class _SwipeAreaState extends State<_SwipeArea> {
  /// About half a cell (cells are 40x28).
  static const double _step = 18;

  /// While the finger keeps dragging, the minimum time between two moves.
  /// The first move of a swipe is immediate.
  static const _repeatDelay = Duration(milliseconds: 300);

  int? _pointer;
  Offset _origin = Offset.zero;

  /// When this drag last moved the player; null until its first move.
  Duration? _lastStep;

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final delta = e.localPosition - _origin;
    if (delta.distance < _step) return;
    // Too soon: keep the origin, so the distance carries over to the next
    // event once the delay is over.
    final last = _lastStep;
    if (last != null && e.timeStamp - last < _repeatDelay) return;
    _lastStep = e.timeStamp;
    // Only the dominant axis, like a cross pad.
    final (dx, dy) = delta.dx.abs() > delta.dy.abs()
        ? (delta.dx.sign.toInt(), 0)
        : (0, delta.dy.sign.toInt());
    _origin = e.localPosition;
    HapticFeedback.selectionClick();
    widget.world.swipe(dx, dy);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (e) {
      if (_pointer != null) return;
      _pointer = e.pointer;
      _origin = e.localPosition;
      _lastStep = null;
    },
    onPointerMove: _move,
    onPointerUp: (e) {
      if (e.pointer == _pointer) _pointer = null;
    },
    onPointerCancel: (e) {
      if (e.pointer == _pointer) _pointer = null;
    },
  );
}

/// Pause and deck, top right.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 22,
      height: 20,
      decoration: BoxDecoration(
        color: Pico.darkBlue,
        border: Border.all(color: Pico.lightGray, width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Icon(icon, size: 12, color: Pico.white),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.battle});

  final BattleState battle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        'HP ${battle.player.hp}',
        style: GbText.body.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: LinearProgressIndicator(
          value: battle.gauge / gaugeTicks,
          minHeight: 4,
          color: battle.gaugeFull ? Pico.yellow : Pico.red,
          backgroundColor: Pico.black,
        ),
      ),
      const SizedBox(width: 6),
      _RamBar(battle: battle),
    ],
  );
}

/// Selected chip's text, then piles, bonus, chain and fusion charge.
class _Info extends StatelessWidget {
  const _Info({required this.battle});

  final BattleState battle;

  @override
  Widget build(BuildContext context) {
    final selected = battle.selectedChip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          selected?.def.description ?? '',
          style: GbText.small,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          'Compra ${battle.deck.drawPile.length} · Descarte ${battle.deck.discardPile.length}'
          '${battle.damageBonus > 0 ? ' · +${battle.damageBonus}' : ''}'
          '${battle.chainCount > 0 ? ' · Corrente ${battle.chainElement!.label} x${battle.chainCount}' : ''}'
          '${battle.chargingCard != null ? ' · Fundindo...' : ''}',
          style: GbText.small.copyWith(color: Pico.lightGray),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// The hand, in a row. Touching a chip uses it; holding one that
/// has a fusion partner charges the fusion. Raw [Listener]s, like the swipe.
class _Hand extends StatelessWidget {
  const _Hand({required this.world, required this.sprites});

  final BattleWorld world;
  final GameSprites sprites;

  @override
  Widget build(BuildContext context) {
    final battle = world.battle;
    final selected = battle.selectedChip;
    return Row(
      children: [
        for (final card in battle.hand)
          Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Listener(
              onPointerDown: (_) {
                HapticFeedback.selectionClick();
                world.pressChip(card);
              },
              onPointerUp: (_) => world.releaseChip(),
              onPointerCancel: (_) => world.releaseChip(),
              child: ChipCardView(
                def: card.def,
                sprites: sprites,
                width: 50,
                focusable: false,
                selected: card == selected,
                dimmed: !battle.canAfford(card),
              ),
            ),
          ),
      ],
    );
  }
}

/// Pasta Ordenada: the next two chips; tapping one sends it to the bottom
/// of the deck, "Manter ordem" leaves them. The battle is paused meanwhile.
class _PeekPopup extends StatelessWidget {
  const _PeekPopup({required this.world, required this.sprites});

  final BattleWorld world;
  final GameSprites sprites;

  /// The HUD rebuilds on ticks, which are paused: bump it by hand.
  void _close(VoidCallback choice) {
    choice();
    world.revision.value++;
  }

  @override
  Widget build(BuildContext context) {
    final battle = world.battle;
    return ColoredBox(
      color: Pico.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(4),
          color: Pico.darkBlue,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pasta Ordenada', style: GbText.body),
              const Text(
                'Toque numa carta para mandá-la ao fundo do deck',
                style: GbText.small,
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final card in battle.peekCards)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ChipCardView(
                        def: card.def,
                        sprites: sprites,
                        width: 56,
                        focusable: false,
                        onTap: () => _close(() => battle.sendToBottom(card)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              TextButton(
                onPressed: () => _close(battle.dismissPeek),
                child: const Text('Manter ordem'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One pip per Energy point: solid = left to spend, outline = spent this hand,
/// green = temporary bonus from Cache.
class _RamBar extends StatelessWidget {
  const _RamBar({required this.battle});

  final BattleState battle;

  @override
  Widget build(BuildContext context) {
    final total = battle.energyMax + battle.energyBonus;
    return Row(
      children: [
        Text(
          'EN ${battle.energy}',
          style: GbText.body.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 3),
        for (var i = 0; i < total; i++)
          Container(
            width: 4,
            height: 7,
            margin: const EdgeInsets.only(right: 1),
            decoration: BoxDecoration(
              color: i < battle.energy
                  ? (i >= battle.energyMax ? Pico.green : Pico.blue)
                  : null,
              border: Border.all(color: Pico.blue, width: 0.5),
            ),
          ),
      ],
    );
  }
}
