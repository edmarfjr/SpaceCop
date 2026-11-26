import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/battle/bestiary.dart';
import '../domain/battle/enemies.dart';

/// How many battles the player has fought against each enemy, across runs:
/// what unlocks its entry in the Compêndio. Saved with shared_preferences;
/// starts empty until [init].
class BestiaryProgress {
  BestiaryProgress._();

  static final instance = BestiaryProgress._();

  static const _key = 'bestiary';

  SharedPreferences? _prefs;
  final Map<String, int> _fights = {};

  Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_key);
      if (text == null) return;
      final saved = jsonDecode(text) as Map<String, Object?>;
      for (final MapEntry(:key, :value) in saved.entries) {
        if (value is int) _fights[key] = value;
      }
    } catch (e) {
      debugPrint('Bestiary not loaded: $e');
    }
  }

  /// Battles fought against [entry]'s enemy.
  int fights(FoeEntry entry) => _fights[entry.id] ?? 0;

  bool unlocked(FoeEntry entry) => fights(entry) >= entry.tier.unlockFights;

  /// A battle against [encounter] started: each enemy in it counts once.
  void recordBattle(Encounter encounter) {
    final ids = {
      for (final spawn in encounter.spawns) Bestiary.of(spawn.def)?.id,
    }..remove(null);
    if (ids.isEmpty) return;
    for (final id in ids) {
      _fights[id!] = (_fights[id] ?? 0) + 1;
    }
    _prefs?.setString(_key, jsonEncode(_fights));
  }
}
