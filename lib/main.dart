import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/audio.dart';
import 'game/star_cop_game.dart';
import 'ui/overlays/battle_hud.dart';
import 'ui/overlays/map_overlay.dart';
import 'ui/overlays/node_screens.dart';
import 'ui/overlays/pause_screens.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape only. No-op on web and desktop.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Full screen: hides the status and navigation bars; a swipe from the
  // edge brings them back for a moment.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await GameAudio.instance.init();
  runApp(const StarCopApp());
}

class StarCopApp extends StatefulWidget {
  const StarCopApp({super.key});

  @override
  State<StarCopApp> createState() => _StarCopAppState();
}

class _StarCopAppState extends State<StarCopApp> {
  // Created once here so hot reload / rebuilds don't restart the run.
  final _game = StarCopGame();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, fontFamily: pixelFont),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GameWidget<StarCopGame>(
          game: _game,
          focusNode: _game.focusNode,
          overlayBuilderMap: {
            for (final MapEntry(:key, :value) in _overlays.entries)
              key: (context, game) => VirtualScreen(
                size: _wideOverlays.contains(key) ? wideScreen : virtualScreen,
                child: value(game),
              ),
          },
        ),
      ),
    ),
  );

  /// Laid out in the wide screen: the battle (over the Flame camera) and the
  /// map, the shop, the events and the reward (the card choice needs the
  /// width). The other menus use the 256x192 virtual screen.
  static const _wideOverlays = {
    Overlays.hud,
    Overlays.reward,
    Overlays.pause,
    Overlays.deck,
    Overlays.map,
    Overlays.shop,
    Overlays.event,
  };

  static final _overlays = <String, Widget Function(StarCopGame)>{
    Overlays.menu: (game) => MenuOverlay(game: game),
    Overlays.map: (game) => MapOverlay(game: game),
    Overlays.hud: (game) => BattleHud(game: game),
    Overlays.reward: (game) => RewardOverlay(game: game),
    Overlays.rest: (game) => RestOverlay(game: game),
    Overlays.shop: (game) => ShopOverlay(game: game),
    Overlays.event: (game) => EventOverlay(game: game),
    Overlays.gameOver: (game) => GameOverOverlay(game: game),
    Overlays.pause: (game) => PauseOverlay(game: game),
    Overlays.deck: (game) => DeckOverlay(game: game),
  };
}
