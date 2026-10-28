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
import 'audio.dart';
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

  /// The event being visited, and the choice or card pick it is waiting
  /// on, if any.
  EventDef? event;
  OfferChoice? eventChoice;
  PickCard? eventPick;

  /// The current battle is an elite outside an elite node ("?" node,
  /// event): it pays like an elite node.
  bool _eliteFight = false;

  /// The current battle came from an event that gives this instead of the
  /// usual rewards.
  OfferChoice? Function(RunState run)? _fightReward;

  /// Pause or deck view open; the battle doesn't tick.
  bool get halted =>
      overlays.isActive(Overlays.pause) || overlays.isActive(Overlays.deck);

  void pause() {
    GameAudio.instance.play(Sfx.pause);
    overlays.add(Overlays.pause);
  }

  void showDeck() {
    GameAudio.instance.play(Sfx.deck);
    overlays.add(Overlays.deck);
  }

  void closeMenus() {
    GameAudio.instance.play(Sfx.cancel);
    overlays.removeAll([Overlays.pause, Overlays.deck]);
  }

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
    GameAudio.instance.play(Sfx.node);
    run.enter(node);
    switch (node.type!) {
      case NodeType.battle:
        _startBattle(Encounters.normal(run.random, act: run.act));
      case NodeType.elite:
        _startBattle(Encounters.elite(run.random, act: run.act));
      case NodeType.boss:
        _startBattle(Encounters.boss(run.random, act: run.act));
      case NodeType.rest:
        _goTo(GamePhase.rest);
      case NodeType.shop:
        shop = Shop(run);
        _goTo(GamePhase.shop);
      case NodeType.event:
        switch (rollUnknownRoom(run.random)) {
          case UnknownRoom.event:
            // TODO: events shouldn't repeat in a run; they still do while
            // there are only a few.
            final pool = Events.of(run.act);
            event = pool[run.random.nextInt(pool.length)];
            eventChoice = null;
            eventPick = null;
            _goTo(GamePhase.event);
          case UnknownRoom.battle:
            _startBattle(Encounters.normal(run.random, act: run.act));
          case UnknownRoom.elite:
            _eliteFight = true;
            _startBattle(Encounters.elite(run.random, act: run.act));
          case UnknownRoom.shop:
            shop = Shop(run);
            _goTo(GamePhase.shop);
        }
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
      energyBaseBonus: run.energyBaseBonus + run.nextBattleEnergy,
      openingStunTicks: run.openingStunTicks,
      pauseOnNewHand: true,
    );
    run
      ..openingStunTicks = 0
      ..nextBattleEnergy = 0;
    _goTo(
      GamePhase.battle,
      world: BattleWorld(battle: battle, onFinished: _onBattleFinished),
    );
  }

  void _onBattleFinished(BattleState battle) {
    run.hp = battle.player.hp;
    final eliteFight = _eliteFight;
    final fightReward = _fightReward;
    _eliteFight = false;
    _fightReward = null;
    if (battle.phase == BattlePhase.lost) {
      _goTo(GamePhase.gameOver);
    } else if (fightReward != null) {
      _showFollowUp(fightReward(run));
    } else if (run.current?.type == NodeType.boss && run.lastAct) {
      _goTo(GamePhase.victory);
    } else {
      final before = run.credits;
      // A boss before the last act pays like an elite; the next act starts
      // once its reward is picked.
      final elite =
          eliteFight ||
          switch (run.current?.type) {
            NodeType.elite || NodeType.boss => true,
            _ => false,
          };
      rewardRelic = run.winBattle(elite: elite);
      rewardCredits = run.credits - before;
      rewardOptions = run.rollRewards(
        3,
        elite: elite,
        boss: run.current?.type == NodeType.boss,
      );
      GameAudio.instance.play(Sfx.reward);
      _goTo(GamePhase.reward);
    }
  }

  /// Reward screen: [chip] null means "skip".
  void pickReward(ChipDef? chip) {
    GameAudio.instance.play(chip == null ? Sfx.cancel : Sfx.confirm);
    if (chip != null) run.deck.add(ChipCard(chip));
    finishNode();
  }

  /// Applies an event option once its chip (if any) was picked.
  void resolveEvent(EventOption option, [ChipCard? picked]) {
    GameAudio.instance.play(Sfx.confirm);
    _showFollowUp(option.apply(run, picked));
  }

  /// Card picked for the event's [eventPick].
  void resolvePick(ChipCard card) {
    final pick = eventPick;
    eventPick = null;
    GameAudio.instance.play(Sfx.confirm);
    if (pick != null) _showFollowUp(pick.apply(run, card));
  }

  void _showFollowUp(EventFollowUp? next) {
    eventChoice = null;
    eventPick = null;
    switch (next) {
      case null:
        finishNode();
      case final OfferChoice choice:
        eventChoice = choice;
        _goTo(GamePhase.event);
      case final PickCard pick:
        eventPick = pick;
        _goTo(GamePhase.event);
      case StartFight(:final elite, :final onWin, :final encounter):
        _eliteFight = elite;
        _fightReward = onWin;
        _startBattle(
          encounter?.call(run) ??
              (elite
                  ? Encounters.elite(run.random, act: run.act)
                  : Encounters.normal(run.random, act: run.act)),
        );
    }
  }

  void pickOffer(EventOffer offer) {
    GameAudio.instance.play(Sfx.confirm);
    offer.apply(run);
    eventChoice = null;
    finishNode();
  }

  void restHere() {
    GameAudio.instance.play(Sfx.heal);
    run.rest();
    finishNode();
  }

  /// The campfire's other choice: upgrade one card instead of resting.
  void upgradeHere(ChipCard card) {
    if (!run.upgrade(card)) return;
    GameAudio.instance.play(Sfx.upgrade);
    finishNode();
  }

  /// Back to the map after any non-battle node or reward.
  void finishNode() {
    if (run.current?.type == NodeType.boss && !run.lastAct) run.nextAct();
    _goTo(GamePhase.map);
  }

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
    GameAudio.instance.music(switch (next) {
      GamePhase.map || GamePhase.reward => Music.map,
      GamePhase.battle =>
        run.current?.type == NodeType.boss ? Music.boss : Music.battle,
      GamePhase.rest || GamePhase.shop || GamePhase.event => Music.shop,
      GamePhase.gameOver || GamePhase.victory => null,
    });
  }

  @override
  void onRemove() {
    focusNode.dispose();
    phase.dispose();
    super.onRemove();
  }
}
