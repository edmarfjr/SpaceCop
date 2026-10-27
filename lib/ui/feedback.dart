import 'package:flutter/services.dart';

import '../game/audio.dart';

/// Light vibration for a tap on a button, card or map node.
void tapFeedback() => HapticFeedback.lightImpact();

/// [tapFeedback] plus the tap blip, for menus. A more specific sound played
/// by the action replaces the blip.
void menuTapFeedback() {
  tapFeedback();
  GameAudio.instance.play(Sfx.tap);
}

/// Stronger vibration when the player takes damage.
void hurtFeedback() => HapticFeedback.vibrate();

/// [action] preceded by [menuTapFeedback]. Null stays null, so disabled
/// buttons stay disabled.
VoidCallback? withTap(VoidCallback? action) => action == null
    ? null
    : () {
        menuTapFeedback();
        action();
      };
