import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import '../domain/battle/battle_state.dart';
import '../domain/battle/enemies.dart';
import '../domain/chips/battle_chip.dart';
import '../domain/map/run_map.dart';
import '../domain/run/events.dart';
import '../domain/run/relics.dart';
import '../domain/run/run_state.dart';
import '../domain/run/shop.dart';
import 'battle/battle_world.dart';
import 'sprites.dart';

/// Top-level screens. Only [battle] uses the Flame world; the others are
/// Flutter overlays over an empty world.
enum GamePhase { map, battle, reward, rest, shop, event, gameOver, victory }

/// Overlay keys registered in `GameWidget.overlayBuilderMap`.
abstract final class Overlays {
  static const map = 'map';
  static const hud = 'hud';
  static const reward = 'reward';
  static const rest = 'rest';
  static const shop = 'shop';
  static const event = 'event';
  static const gameOver = 'gameOver';

  /// Shown on top of the phase overlay: the HUD icons pause or show the
  /// deck (the map shows it too); a tap closes them.
  static const pause = 'pause';
  static const deck = 'deck';

  static String forPhase(GamePhase phase) => switch (phase) {
    GamePhase.map => map,
    GamePhase.battle => hud,
    GamePhase.reward => reward,
    GamePhase.rest => rest,
    GamePhase.shop => shop,
    GamePhase.event => event,
    GamePhase.gameOver || GamePhase.victory => gameOver,
  };
}

/// Owns the run and drives the loop:
/// map -> node (battle / rest / ...) -> reward -> map ... -> boss -> victory.
class StarCopGame extends FlameGame with HasKeyboardHandlerComponents {
  StarCopGame()
    : super(
        camera: CameraComponent.withFixedResolution(
          width: viewWidth,
          height: viewHeight,
        ),
      );

  /// Same as `wideScreen` in ui/theme.dart.
  static const double viewWidth = 384;
  static const double viewHeight = 192;

  /// Shared with GameWidget so overlays can hand keyboard focus back.
  final FocusNode focusNode = FocusNode();

  final ValueNotifier<GamePhase> phase = ValueNotifier(GamePhase.map);

  late RunState run;

  late final GameSprites sprites;

  /// Chips offered on the reward screen after a battle.
  List<ChipDef> rewardOptions = const [];

  /// Credits and elite relic won by the last battle, for the reward screen.
  int rewardCredits = 0;
  RelicDef? rewardRelic;

  /// The shop being visited, while on [GamePhase.shop].
  Shop? shop;

  /// The event being visited, and the choice it is waiting on, if any.
  EventDef? event;
  OfferChoice? eventChoice;

  /// The current battle is Arena Clandestina's duel.
  bool _duel = false;

  /// Pause or deck view open; the battle doesn't tick.
  bool get halted =>
      overlays.isActive(Overlays.pause) || overlays.isActive(Overlays.deck);

  void pause() => overlays.add(Overlays.pause);

  void showDeck() => overlays.add(Overlays.deck);

  void closeMenus() => overlays.removeAll([Overlays.pause, Overlays.deck]);

  BattleWorld? get battleWorld =>
      world is BattleWorld ? world as BattleWorld : null;

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    sprites = await GameSprites.load(images);
    startNewRun();
  }

  void startNewRun() {
    run = RunState();
    _goTo(GamePhase.map);
  }

  /// Entry point from the map overlay.
  void selectNode(MapNode node) {
    run.enter(node);
    switch (node.type!) {
      case NodeType.battle:
        _startBattle(Encounters.normal(run.random));
      case NodeType.elite:
        _startBattle(Encounters.elite(run.random));
      case NodeType.boss:
        _startBattle(Encounters.boss(run.random));
      case NodeType.rest:
        _goTo(GamePhase.rest);
      case NodeType.shop:
        shop = Shop(run);
        _goTo(GamePhase.shop);
      case NodeType.event:
        event = Events.all[run.random.nextInt(Events.all.length)];
        eventChoice = null;
        _goTo(GamePhase.event);
    }
  }

  void _startBattle(Encounter encounter) {
    final battle = BattleState(
      playerHp: run.hp,
      playerMaxHp: run.maxHp,
      deckCards: run.deck,
      encounter: encounter,
      random: run.random,
      relics: run.relics,
      energyBaseBonus: run.energyBaseBonus,
    );
    _goTo(
      GamePhase.battle,
      world: BattleWorld(battle: battle, onFinished: _onBattleFinished),
    );
  }

  void _onBattleFinished(BattleState battle) {
    run.hp = battle.player.hp;
    if (battle.phase == BattlePhase.lost) {
      _goTo(GamePhase.gameOver);
    } else if (_duel) {
      _duel = false;
      eventChoice = duelWon(run);
      _goTo(GamePhase.event);
    } else if (run.current?.type == NodeType.boss) {
      _goTo(GamePhase.victory);
    } else {
      final before = run.credits;
      rewardRelic = run.winBattle(elite: run.current?.type == NodeType.elite);
      rewardCredits = run.credits - before;
      rewardOptions = run.rollRewards(3);
      _goTo(GamePhase.reward);
    }
  }

  /// Reward screen: [chip] null means "skip".
  void pickReward(ChipDef? chip) {
    if (chip != null) run.deck.add(ChipCard(chip));
    finishNode();
  }

  /// Applies an event option once its chip (if any) was picked.
  void resolveEvent(EventOption option, [ChipCard? picked]) {
    switch (option.apply(run, picked)) {
      case null:
        finishNode();
      case final OfferChoice choice:
        eventChoice = choice;
        _goTo(GamePhase.event);
      case StartDuel():
        _duel = true;
        _startBattle(Encounters.elite(run.random));
    }
  }

  void pickOffer(EventOffer offer) {
    offer.apply(run);
    eventChoice = null;
    finishNode();
  }

  void restHere() {
    run.rest();
    finishNode();
  }

  /// The campfire's other choice: upgrade one card instead of resting.
  void upgradeHere(ChipCard card) {
    if (run.upgrade(card)) finishNode();
  }

  /// Back to the map after any non-battle node or reward.
  void finishNode() => _goTo(GamePhase.map);

  void _goTo(GamePhase next, {World? world}) {
    this.world = world ?? World();
    // The game node takes the keyboard in battle; menus need it free so
    // their first item can autofocus.
    if (next == GamePhase.battle) {
      focusNode.requestFocus();
    } else {
      focusNode.unfocus();
    }
    overlays.removeAll(overlays.activeOverlays.toList());
    overlays.add(Overlays.forPhase(next));
    phase.value = next;
  }

  @override
  void onRemove() {
    focusNode.dispose();
    phase.dispose();
    super.onRemove();
  }
}
