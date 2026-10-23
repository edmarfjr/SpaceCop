import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/chips/battle_chip.dart';
import '../../game/sprites.dart';
import '../theme.dart';
import 'sheet_sprite.dart';

/// Visual card for one chip, shared by the hand, rewards, shop and pickers:
/// the `chips/chip.png` frame with the name in its top bar, the chip's art
/// in the black square, cost (left) and element and damage (right) beside
/// it, and the description below. Square, [width] virtual px a side.
///
/// Tappable cards are also focusable, so the pad can reach them in menus;
/// the battle hand turns that off ([focusable]) since touch plays there.
class ChipCardView extends StatefulWidget {
  const ChipCardView({
    super.key,
    required this.def,
    required this.sprites,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
    this.width = 44,
    this.focusable = true,
    this.autofocus = false,
  });

  final ChipDef def;
  final GameSprites sprites;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;
  final double width;
  final bool focusable;
  final bool autofocus;

  static Color colorFor(ChipType type) => switch (type) {
    ChipType.attack => Pico.red,
    ChipType.support => Pico.orange,
    ChipType.recovery => Pico.green,
  };

  @override
  State<ChipCardView> createState() => _ChipCardViewState();
}

class _ChipCardViewState extends State<ChipCardView> {
  bool _focused = false;

  /// Regions of the 32x32 `chips/chip.png` frame, in its pixels.
  static const _name = Rect.fromLTWH(6, 1, 20, 4);
  static const _art = Rect.fromLTWH(10, 6, 12, 12);
  static const _left = Rect.fromLTWH(3, 6, 9, 12);
  static const _right = Rect.fromLTWH(20.5, 6, 9, 12);
  static const _description = Rect.fromLTWH(6, 19, 20, 12);

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final art = widget.sprites.chip(def);
    final onTap = widget.onTap;
    //final highlight = widget.selected || _focused;
    // The frame is square: the card is [width] x [width].
    final scale = widget.width / 32;

    Widget at(Rect rect, Widget child) => Positioned.fromRect(
      rect: Rect.fromLTWH(
        rect.left * scale,
        rect.top * scale,
        rect.width * scale,
        rect.height * scale,
      ),
      child: child,
    );

    // Text is sized off the frame and shrinks further to fit its region.
    Widget fitted(String text, double size, {int? lines, Color? color}) =>
        FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: lines == null ? null : _description.width * scale,
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: lines,
              style: TextStyle(
                fontSize: size,
                height: 1.05,
                color: color ?? Pico.white,
                fontWeight: lines == null ? FontWeight.bold : null,
              ),
            ),
          ),
        );

    final card = GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: widget.dimmed ? 0.45 : 1,
        child: SizedBox.square(
          dimension: widget.width*1,
          child: Stack(
            children: [
              SheetSprite(sprite: widget.sprites.chipFrame, scale: scale*2),
              at(
                _name,
                Center(
                  child: fitted(def.name, 2 * scale, color: Pico.darkBlue),
                ),
              ),
              at(
                _art,
                Center(
                  child: SheetSprite(
                    sprite: art,
                    // Old 8px icons are drawn a bit larger; bigger art is
                    // fitted to the square.
                    scale: scale * min(1.25, _art.width / art.srcSize.x),
                  ),
                ),
              ),
              at(
                _left,
                Align(
                  alignment: Alignment.topCenter,
                  child:fitted('${def.cost}', 5 * scale * 0.8),
                ),
              ),
              at(
                _right,
                Column(
                  children: [
                    if (widget.sprites.element(def.element) case final icon?)
                      SheetSprite(sprite: icon, scale: scale * 0.75),
                    if (def.damage > 0)
                      fitted('${def.damage}', 5 * scale * 0.8),
                  ],
                ),
              ),
              at(
                _description,
                Center(child: fitted(def.description, 2 * scale, lines: 6)),
              ),
              // Selection / focus, and the chip type, as an outline.
              /*Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: highlight
                          ? Pico.yellow
                          : ChipCardView.colorFor(def.type),
                      width: highlight ? focusBorder : 0.75,
                    ),
                    borderRadius: BorderRadius.circular(0),
                  ),
                ),
              ),*/
            ],
          ),
        ),
      ),
    );
    if (onTap == null || !widget.focusable) return card;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onTap();
            return null;
          },
        ),
      },
      child: card,
    );
  }
}

/// Energy cost, top-left of the card.
class _CostBadge extends StatelessWidget {
  const _CostBadge({required this.cost, required this.size});

  final int cost;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
   // decoration: const BoxDecoration(color: Pico.blue, shape: BoxShape.circle),
    child: Text(
      '$cost',
      style: TextStyle(
        fontSize: size * 0.8,
        height: 1,
        color: Pico.white,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
