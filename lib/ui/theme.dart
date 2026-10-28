import 'package:flutter/material.dart';

import '../domain/rarity.dart';

/// Design tokens. See DESIGN.md.
///
/// The Picotron palette (PICO-8's 16 colors plus 16 more): the only colors
/// used inside the screen, by Flutter and Flame alike.
abstract final class Pico {
  // 0-15, inherited from PICO-8.
  static const black = Color(0xFF000000);
  static const darkBlue = Color(0xFF1D2B53);
  static const darkPurple = Color(0xFF7E2553);
  static const darkGreen = Color(0xFF008751);
  static const brown = Color(0xFFAB5236);
  static const darkGray = Color(0xFF5F574F);
  static const lightGray = Color(0xFFC2C3C7);
  static const white = Color(0xFFFFF1E8);
  static const red = Color(0xFFFF004D);
  static const orange = Color(0xFFFFA300);
  static const yellow = Color(0xFFFFFF27);
  static const green = Color(0xFF00E756);
  static const blue = Color(0xFF29ADFF);
  static const lavender = Color(0xFF83769C);
  static const pink = Color(0xFFFF77A8);
  static const peach = Color(0xFFFFCCAA);

  // 16-31, Picotron only.
  static const onyx = Color(0xFF291814);
  static const midnight = Color(0xFF111D35);
  static const plum = Color(0xFF422136);
  static const forest = Color(0xFF125359);
  static const chocolate = Color(0xFF742F29);
  static const eggplant = Color(0xFF49333B);
  static const beige = Color(0xFFA28879);
  static const lemon = Color(0xFFF3EF7D);
  static const burgundy = Color(0xFFBE1250);
  static const pumpkin = Color(0xFFFF6C24);
  static const lime = Color(0xFFA8E72E);
  static const jade = Color(0xFF00B543);
  static const royal = Color(0xFF065AB5);
  static const mauve = Color(0xFF754665);
  static const coral = Color(0xFFFF6E59);
  static const salmon = Color(0xFFFF9D81);
}

/// The game's only font, `assets/fonts/pixel.ttf`.
const String pixelFont = 'Pixel';

/// Type scale in virtual px (the 256x192 screen).
abstract final class GbText {
  static const small = TextStyle(
    fontFamily: pixelFont,
    fontSize: 7,
    color: Pico.white,
    height: 1.1,
  );
  static const body = TextStyle(
    fontFamily: pixelFont,
    fontSize: 8,
    color: Pico.white,
    height: 1.15,
  );
  static const title = TextStyle(
    fontFamily: pixelFont,
    fontSize: 11,
    color: Pico.white,
    fontWeight: FontWeight.bold,
  );
}

/// Size of the virtual screen used by the menus.
const Size virtualScreen = Size(256, 192);

/// Wide virtual screen of the battle and the map, same as the Flame camera
/// (2:1, close to a phone held sideways).
const Size wideScreen = Size(384, 192);

/// Rarity of a card or relic: its label in the shop and the outline of a
/// card's name bar (common cards keep the frame's own).
Color rarityColor(Rarity rarity) => switch (rarity) {
  Rarity.common => Pico.lightGray,
  Rarity.uncommon => Pico.blue,
  Rarity.rare => Pico.orange,
};

/// Width of the focus border.
const double focusBorder = 1.5;

/// Inside every button: room enough that the focus border never touches
/// the text.
const EdgeInsets buttonPadding = EdgeInsets.symmetric(
  horizontal: 6,
  vertical: 3,
);

/// Compact Material theme for widgets inside the virtual screen: no minimum
/// sizes, no padded tap targets, small text.
ThemeData screenTheme(ThemeData base) {
  final buttonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.zero),
    padding: const WidgetStatePropertyAll(buttonPadding),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    // Compact density would take 4 px off [buttonPadding] on each side.
    visualDensity: VisualDensity.standard,
    textStyle: const WidgetStatePropertyAll(GbText.body),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.focused)
            ? Pico.yellow
            : Pico.lightGray,
        width: states.contains(WidgetState.focused) ? focusBorder : 0.5,
      ),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? Pico.darkGray : Pico.white,
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? Pico.darkPurple
          : Colors.transparent,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );
  return base.copyWith(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    tooltipTheme: const TooltipThemeData(textStyle: GbText.small),
  );
}

/// Lays [child] out in a virtual screen of [size] and scales it to fit.
class VirtualScreen extends StatelessWidget {
  const VirtualScreen({
    super.key,
    required this.child,
    this.size = virtualScreen,
  });

  final Widget child;
  final Size size;

  @override
  // Overlays get loose constraints; expand first so FittedBox scales up.
  Widget build(BuildContext context) => SizedBox.expand(
    child: FittedBox(
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
            padding: EdgeInsets.zero,
          ),
          child: Theme(
            data: screenTheme(Theme.of(context)),
            child: DefaultTextStyle(style: GbText.body, child: child),
          ),
        ),
      ),
    ),
  );
}
