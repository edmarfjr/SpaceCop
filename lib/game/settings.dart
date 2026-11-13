import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Languages the game can be shown in. Only stored for now: the texts are
/// still hard-coded in Portuguese until the game is translated.
enum GameLanguage {
  pt('Português'),
  en('English');

  const GameLanguage(this.label);

  /// The language's name in itself.
  final String label;
}

/// Player settings other than sound (see GameAudio), saved with
/// shared_preferences. Works with the defaults until [init].
class GameSettings {
  GameSettings._();

  static final instance = GameSettings._();

  SharedPreferences? _prefs;

  final ValueNotifier<GameLanguage> language = ValueNotifier(GameLanguage.pt);

  Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('language');
      language.value = GameLanguage.values.firstWhere(
        (l) => l.name == code,
        orElse: () => language.value,
      );
    } catch (e) {
      debugPrint('Settings not loaded: $e');
    }
  }

  void setLanguage(GameLanguage value) {
    language.value = value;
    _prefs?.setString('language', value.name);
  }
}
