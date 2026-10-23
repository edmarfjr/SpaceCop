import 'package:flutter/services.dart';

/// Light vibration for a tap on a button, card or map node.
void tapFeedback() => HapticFeedback.lightImpact();

/// Short, stronger vibration when the player takes damage.
void hurtFeedback() => HapticFeedback.heavyImpact();

/// [action] preceded by [tapFeedback]. Null stays null, so disabled buttons
/// stay disabled.
VoidCallback? withTap(VoidCallback? action) => action == null
    ? null
    : () {
        tapFeedback();
        action();
      };
