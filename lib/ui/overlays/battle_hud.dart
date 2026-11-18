import 'package:flame/components.dart' show Sprite;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/battle/battle_state.dart';
import '../../game/battle/battle_world.dart';
import '../../game/star_cop_game.dart';
import '../../game/sprites.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/chip_card_view.dart';
import '../widgets/sheet_sprite.dart';

/// HP, gauge, Energy and the current hand, drawn by Flutter over the grid.
///
/// Lives in the 384x192 battle screen: the player's status in the top left
/// corner, the enemies' bars on the right, chain info over the grid and the
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
          // The column left of the grid: status, selected card, piles.
          Positioned(
            top: 2,
            left: 2,
            width: _gridLeft - 6,
            child: IgnorePointer(child: _PlayerStatus(battle: battle)),
          ),
          Positioned(
            bottom: 2,
            left: 2,
            width: _gridLeft - 6,
            child: IgnorePointer(child: _Piles(battle: battle)),
          ),
          // Old layout: enemy names and life bars on the right of the grid.
          // The life bar is now drawn under each enemy's sprite
          // (FighterComponent).
          // Positioned(
          //   top: 26,
          //   left: _gridLeft + _gridWidth + 4,
          //   right: 2,
          //   child: IgnorePointer(child: _EnemyBars(battle: battle)),
          // ),
          // Above the tallest sprites of the grid's top row. While the
          // battle waits for the player, the prompt takes the line.
          Positioned(
            top: 3,
            left: _gridLeft,
            width: _gridWidth,
            child: IgnorePointer(
              child: battle.waitingForPlayer
                  ? Text(
                      'AGUARDANDO · mova ou use uma carta',
                      textAlign: TextAlign.center,
                      style: GbText.small.copyWith(color: Pico.yellow),
                    )
                  : _Info(battle: battle),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Row(
              children: [
                HudIconButton(
                  icon: game.sprites.deckIcon,
                  onTap: game.showDeck,
                ),
                const SizedBox(width: 4),
                HudIconButton(icon: game.sprites.pauseIcon, onTap: game.pause),
              ],
            ),
          ),
          Positioned(
            bottom: 2,
            right: 2,
            child: _Hand(world: world, sprites: game.sprites),
          ),
          _HeldCard(world: world, sprites: game.sprites),
          // Under a quarter of the max HP, the screen's edge pulses red.
          if (battle.player.hp * 4 < battle.player.maxHp &&
              (battle.ticks ~/ ticksPerSecond).isEven)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: petAlert, width: 2),
                  ),
                ),
              ),
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
/// A raw [Listener] (no gesture arena), so touching a chip with one finger
/// doesn't cancel a swipe with the other.
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

/// Pause and deck, top right (the map shows pause too).
class HudIconButton extends StatelessWidget {
  const HudIconButton({super.key, required this.icon, required this.onTap});

  /// 8x8 art, drawn at 2x like everything else.
  final Sprite icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: withTap(onTap),
    child: Container(
      width: 22,
      height: 20,
      decoration: BoxDecoration(
        color: Pico.darkBlue,
        border: Border.all(color: Pico.lightGray, width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.center,
      child: SheetSprite(sprite: icon, scale: 2),
    ),
  );
}

/// Top left corner, a PET window: HP big, Energy under it, the gauge
/// last. Hurt, the HP shakes in red and the HP lost rises over it; under a
/// quarter of the max HP, the number blinks red.
class _PlayerStatus extends StatefulWidget {
  const _PlayerStatus({required this.battle});

  final BattleState battle;

  @override
  State<_PlayerStatus> createState() => _PlayerStatusState();
}

class _PlayerStatusState extends State<_PlayerStatus> {
  /// Half a blink of the full gauge, in ticks.
  static const _gaugeBlinkTicks = ticksPerSecond ~/ 8;

  /// Half a blink of the HP when low, in ticks.
  static const _lowBlinkTicks = ticksPerSecond ~/ 3;

  /// How long the HP lost stays up, in ticks.
  static const _lossTicks = ticksPerSecond;

  late int _lastHp = widget.battle.player.hp;

  /// HP lost by the last hits close together, and when the last one landed.
  int _lost = 0;
  int _lostAt = -_lossTicks;

  BattleState get battle => widget.battle;

  @override
  void didUpdateWidget(_PlayerStatus old) {
    super.didUpdateWidget(old);
    final hp = battle.player.hp;
    if (hp < _lastHp) {
      final chained = battle.ticks - _lostAt < _lossTicks;
      _lost = (chained ? _lost : 0) + _lastHp - hp;
      _lostAt = battle.ticks;
    }
    _lastHp = hp;
  }

  @override
  Widget build(BuildContext context) {
    final player = battle.player;
    final hurt = player.hurtTicks > 0;
    final low = player.hp * 4 < player.maxHp;
    final sinceLoss = battle.ticks - _lostAt;
    final hpColor = hurt || (low && (battle.ticks ~/ _lowBlinkTicks).isEven)
        ? Pico.red
        : Pico.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 3),
      decoration: hurt || low ? _alertWindow : petWindow,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'HP ',
                    style: GbText.small.copyWith(color: Pico.lightGray),
                  ),
                  Transform.translate(
                    // Shakes a pixel every other tick while hurt.
                    offset: Offset(hurt && player.hurtTicks.isOdd ? 1 : 0, 0),
                    child: Text(
                      '${player.hp}',
                      style: GbText.title.copyWith(color: hpColor),
                    ),
                  ),
                  Text(
                    '/${player.maxHp}',
                    style: GbText.small.copyWith(color: Pico.lightGray),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _RamBar(battle: battle),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'CARGA',
                    style: GbText.small.copyWith(
                      color: battle.gaugeFull ? Pico.yellow : Pico.lightGray,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: battle.gauge / gaugeTicks,
                      minHeight: 5,
                      // Full: blinks yellow and white, 4 times a second.
                      color: !battle.gaugeFull
                          ? Pico.red
                          : (battle.ticks ~/ _gaugeBlinkTicks).isEven
                          ? Pico.yellow
                          : Pico.white,
                      backgroundColor: Pico.chocolate,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_lost > 0 && sinceLoss < _lossTicks)
            Positioned(
              right: 0,
              // Rises 6 px over its second on screen.
              top: -sinceLoss * 6 / _lossTicks,
              child: Text(
                '-$_lost',
                style: GbText.body.copyWith(color: Pico.red),
              ),
            ),
        ],
      ),
    );
  }

  /// [petWindow] with the [petAlert] frame.
  static const _alertWindow = ShapeDecoration(
    color: Pico.midnight,
    shape: BeveledRectangleBorder(
      side: BorderSide(color: petAlert),
      borderRadius: BorderRadius.only(
        topRight: Radius.circular(4),
        bottomLeft: Radius.circular(4),
      ),
    ),
  );
}

/// Bottom left, a PET window with the draw and discard piles. When the
/// next hand will need the discard pile, it says it gets shuffled back.
class _Piles extends StatelessWidget {
  const _Piles({required this.battle});

  final BattleState battle;

  @override
  Widget build(BuildContext context) {
    final deck = battle.deck;
    final reshuffles =
        deck.drawPile.length < handSize && deck.discardPile.isNotEmpty;
    Widget row(String label, int count) => Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GbText.small.copyWith(color: Pico.lightGray),
          ),
        ),
        Text('$count', style: GbText.small),
      ],
    );
    return Container(
      decoration: petWindow,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row('COMPRA', deck.drawPile.length),
          row('DESCARTE', deck.discardPile.length),
          if (reshuffles)
            Text(
              'Embaralha na próxima mão',
              style: GbText.small.copyWith(color: Pico.yellow),
            ),
        ],
      ),
    );
  }
}

/// Right of the grid: each enemy's name, kind and life bar. Enemies sharing
/// a name are numbered ("Capanga Atirador 2").
///
/// Unused for now: the life bar moved under the enemy's sprite.
// ignore: unused_element
class _EnemyBars extends StatelessWidget {
  const _EnemyBars({required this.battle});

  final BattleState battle;

  @override
  Widget build(BuildContext context) {
    final seen = <String, int>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final enemy in battle.enemies)
          if (!enemy.isDead && !enemy.def.part) ...[
            Text(
              switch (seen.update(
                enemy.def.name,
                (n) => n + 1,
                ifAbsent: () => 1,
              )) {
                1 => enemy.def.name,
                final n => '${enemy.def.name} $n',
              },
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GbText.small.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              enemy.def.kind.label,
              style: GbText.small.copyWith(color: Pico.lightGray),
            ),
            const SizedBox(height: 1),
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: Pico.darkBlue,
                border: Border.all(color: Pico.white, width: 0.5),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (enemy.hp / enemy.maxHp).clamp(0, 1),
                heightFactor: 1,
                child: const ColoredBox(color: Pico.red),
              ),
            ),
            const SizedBox(height: 4),
          ],
      ],
    );
  }
}

/// Selected chip's text, then piles, bonus and chain.
class _Info extends StatelessWidget {
  const _Info({required this.battle});

  final BattleState battle;

  @override
  Widget build(BuildContext context) {
    return Text(
      [
        if (battle.damageBonus > 0) '+${battle.damageBonus}',
        if (battle.chainCount > 0)
          'Corrente ${battle.chainFamily!.label} x${battle.chainCount}',
        if (battle.chainSurge) 'Sobrecarga',
        if (battle.overclocked) 'Overclock',
      ].join(' · '),
      textAlign: TextAlign.center,
      style: GbText.small.copyWith(color: Pico.lightGray),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The hand, in a row. Touching a chip holds it (the battle stands still
/// and [_HeldCard] shows it enlarged); lifting the finger on it uses it.
/// Raw [Listener]s, like the swipe.
class _Hand extends StatelessWidget {
  const _Hand({required this.world, required this.sprites});

  /// 54 px tall: fits between the grid (bottom at y 136) and the bottom
  /// edge.
  static const double cardWidth = 36;
  static const _cardSize = Size(cardWidth, cardWidth * 1.5);

  /// Each card's slot: the card and the 1 px gap on its left.
  static const double slot = cardWidth + 1;

  final BattleWorld world;
  final GameSprites sprites;

  @override
  Widget build(BuildContext context) {
    final battle = world.battle;
    final selected = battle.selectedChip;
    // Empty until the gauge fills and deals a new hand: say so, instead of
    // leaving the corner blank.
    if (battle.hand.isEmpty) {
      return Container(
        width: 112,
        height: 54,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(border: Border.all(color: Pico.yellow)),
        child: Text(
          'MÃO VAZIA\nnova mão quando a CARGA encher',
          textAlign: TextAlign.center,
          style: GbText.small.copyWith(color: Pico.yellow),
        ),
      );
    }
    return Row(
      children: [
        for (final card in battle.hand)
          Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Listener(
              onPointerDown: (_) {
                tapFeedback();
                world.holdChip(card);
              },
              // Used only when lifted on the card; sliding off cancels.
              onPointerUp: (e) => world.releaseChip(
                card,
                use: (Offset.zero & _cardSize).contains(e.localPosition),
              ),
              onPointerCancel: (_) => world.releaseChip(card, use: false),
              child: ChipCardView(
                def: card.def,
                sprites: sprites,
                width: cardWidth,
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

/// The held card, enlarged above its place in the hand so its text can be
/// read. Lifting the finger on the small card uses it.
class _HeldCard extends StatelessWidget {
  const _HeldCard({required this.world, required this.sprites});

  final BattleWorld world;
  final GameSprites sprites;

  static const double width = 80;

  /// Hand inset from the screen's bottom-right corner.
  static const double _margin = 2;

  @override
  Widget build(BuildContext context) {
    final card = world.held;
    final hand = world.battle.hand;
    final i = card == null ? -1 : hand.indexOf(card);
    if (i < 0) return const SizedBox.shrink();
    // Center over the small card, kept on screen.
    final fromRight = _margin + (hand.length - i - 0.5) * _Hand.slot;
    final right = (fromRight - width / 2).clamp(_margin, double.infinity);
    return Positioned(
      right: right,
      bottom: _margin + _Hand.cardWidth * 1.5 + 4,
      child: IgnorePointer(
        child: ChipCardView(
          def: card!.def,
          sprites: sprites,
          width: width,
          focusable: false,
          dimmed: !world.battle.canAfford(card),
        ),
      ),
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
                onPressed: withTap(() => _close(battle.dismissPeek)),
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
              // A card just gave Energy: the pips glow white.
              border: Border.all(
                color: battle.energyGlowTicks > 0 ? Pico.white : Pico.blue,
                width: battle.energyGlowTicks > 0 ? 1 : 0.5,
              ),
            ),
          ),
      ],
    );
  }
}
