import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/chips/battle_chip.dart';
import '../../game/sprites.dart';
import '../feedback.dart';
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

  /// Size of the `chips/chip.png` frame, in its pixels.
  static const _frame = Size(32, 48);

  /// Regions of the frame, in its pixels: the name bar, the black art
  /// window, the cost (blue) and damage (red) circles, the element icon
  /// between them, and the description box.
  static const _name = Rect.fromLTWH(3, 3, 26, 3);
  static const _nameOutline = Rect.fromLTWH(2, 2, 28, 5);
  static const _art = Rect.fromLTWH(5, 14, 22, 13);
  static const _left = Rect.fromLTWH(1, 8, 6, 6);
  static const _right = Rect.fromLTWH(25, 8, 6, 6);
  static const _element = Rect.fromLTWH(13, 8, 6, 6);
  static const _description = Rect.fromLTWH(3, 28, 26, 17);

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final art = widget.sprites.chip(def);
    final onTap = widget.onTap;
    //final highlight = widget.selected || _focused;
    // The card is [width] wide and as tall as the frame's proportion.
    final scale = widget.width / _frame.width;

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
      onTap: withTap(onTap),
      child: Opacity(
        opacity: widget.dimmed ? 0.45 : 1,
        child: SizedBox(
          width: widget.width,
          height: _frame.height * scale,
          child: Stack(
            children: [
              SheetSprite(
                sprite: def.upgraded
                    ? widget.sprites.chipFrameUpgraded
                    : widget.sprites.chipFrame,
                scale: scale,
              ),
              if (def.rarity != Rarity.common)
                at(
                  _nameOutline,
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: rarityColor(def.rarity),
                        width: scale,
                      ),
                    ),
                  ),
                ),
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
                    // fitted to the window.
                    scale:
                        scale *
                        min(
                          1.25,
                          min(
                            _art.width / art.srcSize.x,
                            _art.height / art.srcSize.y,
                          ),
                        ),
                  ),
                ),
              ),
              at(_left, Center(child: fitted('${def.cost}', 5 * scale * 0.8))),
              if (def.damage > 0)
                at(
                  _right,
                  Center(child: fitted('${def.damage}', 5 * scale * 0.8)),
                ),
              if (widget.sprites.element(def.element) case final icon?)
                at(
                  _element,
                  Center(
                    child: SheetSprite(
                      sprite: icon,
                      scale: scale * _element.width / icon.srcSize.x,
                    ),
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
            menuTapFeedback();
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
