import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/run/run_state.dart';

/// The run in progress, kept between sessions. Written each time a node is
/// done; erased when the run ends.
abstract final class RunSave {
  static const _key = 'run';

  /// The saved run, or null if there is none or it can't be read.
  static Future<RunState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_key);
    if (text == null) return null;
    try {
      return RunState.fromJson(jsonDecode(text) as Map<String, Object?>);
    } on Object {
      // A save from an older version: start over rather than crash.
      await prefs.remove(_key);
      return null;
    }
  }

  static Future<void> write(RunState run) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(run.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
