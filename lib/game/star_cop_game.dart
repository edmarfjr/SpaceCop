import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import '../domain/battle/battle_state.dart';
import '../domain/battle/enemies.dart';
import '../domain/chips/battle_chip.dart';
import '../domain/chips/chip_library.dart';
import '../domain/map/run_map.dart';
import '../domain/run/events.dart';
import '../domain/run/relics.dart';
import '../domain/run/run_state.dart';
import '../domain/run/shop.dart';
import 'audio.dart';
import 'battle/battle_world.dart';
import 'bestiary_progress.dart';
import 'run_save.dart';
import 'sprites.dart';
import '../ui/theme.dart' show Pico;

/// Top-level screens. Only [battle] uses the Flame world; the others are
/// Flutter overlays over an empty world.
enum GamePhase {
  menu,
  deckSelect,
  compendium,
  manual,
  map,
  battle,
  reward,
  rest,
  shop,
  event,
  gameOver,
  victory,
}

/// Overlay keys registered in `GameWidget.overlayBuilderMap`.
abstract final class Overlays {
  static const menu = 'menu';
  static const deckSelect = 'deckSelect';
  static const compendium = 'compendium';
  static const manual = 'manual';

  /// Shown on top of any screen while a relic just taken asks for choices
  /// ([RunState.pending]).
  static const pickup = 'pickup';
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

  /// Sound and language, on top of the menu or the pause.
  static const settings = 'settings';

  /// Over a battle that just started: the jack-in bands withdraw.
  static const jackIn = 'jackIn';

  static String forPhase(GamePhase phase) => switch (phase) {
    GamePhase.menu => menu,
    GamePhase.deckSelect => deckSelect,
    GamePhase.compendium => compendium,
    GamePhase.manual => manual,
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

  final ValueNotifier<GamePhase> phase = ValueNotifier(GamePhase.menu);

  late RunState run;

  /// The run saved by an earlier session, offered by the menu.
  RunState? savedRun;

  late final GameSprites sprites;

  /// Share of the art loaded so far, for the loading screen.
  final loadProgress = ValueNotifier<double>(0);

  /// What the last battle left on the Espólios screen, not taken yet.
  List<Spoil> spoils = [];

  /// The shop being visited, while on [GamePhase.shop].
  Shop? shop;

  /// The event being visited, and the choice or card pick it is waiting
  /// on, if any.
  EventDef? event;
  OfferChoice? eventChoice;
  CardChoice? eventCards;
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

  /// The run's clock runs on its screens, not on the pause, the deck view,
  /// the settings or the manual opened from the pause.
  @override
  void update(double dt) {
    super.update(dt);
    switch (phase.value) {
      case GamePhase.map ||
              GamePhase.battle ||
              GamePhase.reward ||
              GamePhase.rest ||
              GamePhase.shop ||
              GamePhase.event
          when !halted &&
              !overlays.isActive(Overlays.settings) &&
              !overlays.isActive(Overlays.manual):
        run.playSeconds += dt;
      default:
    }
  }

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

  void openSettings() => overlays.add(Overlays.settings);

  void closeSettings() {
    GameAudio.instance.play(Sfx.cancel);
    overlays.remove(Overlays.settings);
  }

  BattleWorld? get battleWorld =>
      world is BattleWorld ? world as BattleWorld : null;

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    sprites = await GameSprites.load(
      images,
      onProgress: (done) => loadProgress.value = done,
    );
    savedRun = await RunSave.load();
    _goTo(GamePhase.menu);
  }

  /// Menu: pick the starting deck first; the saved run stays until one is
  /// picked.
  void startNewRun() => _goTo(GamePhase.deckSelect);

  void startRunWith(StarterDeck deck) {
    savedRun = null;
    abandoned = false;
    RunSave.clear();
    run = RunState(deck: deck.build());
    _goTo(GamePhase.map);
  }

  void openCompendium() => _goTo(GamePhase.compendium);

  void openManual() => _goTo(GamePhase.manual);

  /// From the pause: the manual on top, the run kept under it.
  void openManualOverRun() => overlays.add(Overlays.manual);

  /// The manual's "Voltar": back to the menu, or to the pause it was
  /// opened from.
  void closeManual() => phase.value == GamePhase.manual
      ? backToMenu()
      : overlays.remove(Overlays.manual);

  void backToMenu() => _goTo(GamePhase.menu);

  /// The run was given up from the pause ([GameOverOverlay] says so).
  bool abandoned = false;

  /// Pause, "Abandonar run": ends the run like a defeat, with its report.
  void abandonRun() {
    abandoned = true;
    _goTo(GamePhase.gameOver);
  }

  /// Menu: back to the saved run, on its map.
  void continueRun() {
    final saved = savedRun;
    if (saved == null) return;
    savedRun = null;
    run = saved;
    _goTo(GamePhase.map);
  }

  /// Entry point from the map overlay.
  void selectNode(MapNode node) {
    GameAudio.instance.play(Sfx.node);
    run.enter(node);
    switch (node.type!) {
      case NodeType.battle:
        _startBattle(run.normalEncounter());
      case NodeType.elite:
        _startBattle(run.eliteEncounter());
      case NodeType.boss:
        _startBattle(run.bossEncounter);
      case NodeType.rest:
        _goTo(GamePhase.rest);
      case NodeType.shop:
        shop = Shop(run);
        _goTo(GamePhase.shop);
      case NodeType.event:
        UnknownRoom roll() => rollUnknownRoom(
          run.random,
          noFights: run.hasRelic(Relics.routeRadar),
        );
        var room = roll();
        final drawn = room == UnknownRoom.event ? run.drawEvent() : null;
        // No event left in the run: the "?" is another room.
        while (room == UnknownRoom.event && drawn == null) {
          room = roll();
        }
        switch (room) {
          case UnknownRoom.event:
            event = drawn;
            eventChoice = null;
            eventCards = null;
            eventPick = null;
            _goTo(GamePhase.event);
          case UnknownRoom.battle:
            _startBattle(run.normalEncounter());
          case UnknownRoom.elite:
            _eliteFight = true;
            _startBattle(run.eliteEncounter());
          case UnknownRoom.shop:
            shop = Shop(run);
            _goTo(GamePhase.shop);
        }
    }
  }

  void _startBattle(Encounter encounter) {
    BestiaryProgress.instance.recordBattle(encounter);
    final boss = run.current?.type == NodeType.boss;
    final battle = BattleState(
      playerHp: run.hp,
      playerMaxHp: run.maxHp,
      deckCards: run.deck,
      encounter: encounter,
      random: run.random,
      relics: run.relics,
      energyBaseBonus:
          run.energyBaseBonus +
          run.nextBattleEnergy +
          (run.energyBattles > 0 ? 1 : 0),
      openingStunTicks: run.openingStunTicks,
      bossHpCut: boss ? run.bossHpCut : 0,
      openingBarrier: boss && run.bossBarrier,
      pauseOnNewHand: true,
    );
    run
      ..openingStunTicks = 0
      ..nextBattleEnergy = 0
      ..energyBattles = run.energyBattles > 0 ? run.energyBattles - 1 : 0;
    _goTo(
      GamePhase.battle,
      world: BattleWorld(battle: battle, onFinished: _onBattleFinished),
    );
    jackIn = boss
        ? (Pico.red, Pico.burgundy, run.boss.name.toUpperCase())
        : _eliteFight || run.current?.type == NodeType.elite
        ? (Pico.orange, Pico.pumpkin, 'ELITE BATTLE')
        : (Pico.blue, Pico.royal, 'BATTLE');
    overlays.add(Overlays.jackIn);
  }

  /// The jack-in's two band colors and its word, for the battle starting.
  (Color, Color, String) jackIn = (Pico.blue, Pico.royal, 'BATTLE');

  void endJackIn() => overlays.remove(Overlays.jackIn);

  void _onBattleFinished(BattleState battle) {
    run.endBattle(
      battle.player.hp,
      won: battle.phase == BattlePhase.won,
      phoenixUsed: battle.phoenixUsed,
      enemiesDefeated: battle.enemiesDefeated,
      cardUses: battle.cardUses,
    );
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
      // The next act starts once the boss's spoils are left behind.
      spoils = run.battleSpoils(
        elite: eliteFight || run.current?.type == NodeType.elite,
        boss: run.current?.type == NodeType.boss,
      );
      GameAudio.instance.play(Sfx.reward);
      _goTo(GamePhase.reward);
    }
  }

  /// Espólios: takes one item; a card or boss relic choice passes the
  /// picked one.
  void takeSpoil(Spoil spoil, {ChipDef? card, RelicDef? relic}) {
    GameAudio.instance.play(Sfx.confirm);
    run.claim(spoil, card: card, relic: relic);
    spoils.remove(spoil);
    checkPickups();
  }

  /// Opens the relic choices waiting in [RunState.pending], if any; steps
  /// with nothing to pick are dropped.
  void checkPickups() {
    final pending = run.pending;
    while (pending.isNotEmpty) {
      final step = pending.first;
      final empty = switch (step) {
        DeckPickStep() => step.cards(run).isEmpty,
        DeckMultiPickStep() => step.needed(run) == 0,
        CardRewardStep() => false,
      };
      if (!empty) break;
      pending.removeAt(0);
    }
    if (pending.isNotEmpty && !overlays.isActive(Overlays.pickup)) {
      overlays.add(Overlays.pickup);
    }
  }

  /// The current relic choice was made: [card] (or [cards]) picked from the
  /// deck, or [reward] (null skips it) taken from a card reward.
  void resolvePickup({ChipCard? card, List<ChipCard>? cards, ChipDef? reward}) {
    final step = run.pending.removeAt(0);
    switch (step) {
      case DeckPickStep():
        step.apply(run, card!);
        GameAudio.instance.play(Sfx.confirm);
      case DeckMultiPickStep():
        step.apply(run, cards!);
        GameAudio.instance.play(Sfx.confirm);
      case CardRewardStep():
        if (reward != null) run.deck.add(ChipCard(reward));
        GameAudio.instance.play(reward == null ? Sfx.cancel : Sfx.confirm);
    }
    checkPickups();
    if (run.pending.isEmpty) {
      overlays.remove(Overlays.pickup);
      if (phase.value == GamePhase.map) RunSave.write(run);
    }
  }

  /// Event card choice: [chip] null means "skip".
  void pickEventCard(ChipDef? chip) {
    GameAudio.instance.play(chip == null ? Sfx.cancel : Sfx.confirm);
    if (chip != null) run.deck.add(ChipCard(chip));
    eventCards = null;
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
    eventCards = null;
    eventPick = null;
    switch (next) {
      case null:
        finishNode();
      case final OfferChoice choice:
        eventChoice = choice;
        _goTo(GamePhase.event);
      case final CardChoice cards:
        eventCards = cards;
        _goTo(GamePhase.event);
      case final PickCard pick:
        eventPick = pick;
        _goTo(GamePhase.event);
      case StartFight(:final elite, :final onWin, :final encounter):
        _eliteFight = elite;
        _fightReward = onWin;
        _startBattle(
          encounter?.call(run) ??
              (elite ? run.eliteEncounter() : run.normalEncounter()),
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

  /// Back to the map after any non-battle node or reward; the run is saved
  /// here.
  void finishNode() {
    if (run.current?.type == NodeType.boss && !run.lastAct) run.nextAct();
    RunSave.write(run);
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
    if (next != GamePhase.menu &&
        next != GamePhase.deckSelect &&
        next != GamePhase.compendium &&
        next != GamePhase.manual) {
      checkPickups();
    }
    // A finished run can't be continued.
    if (next == GamePhase.gameOver || next == GamePhase.victory) {
      RunSave.clear();
    }
    GameAudio.instance.music(switch (next) {
      GamePhase.menu ||
      GamePhase.deckSelect ||
      GamePhase.compendium ||
      GamePhase.manual ||
      GamePhase.map ||
      GamePhase.reward => Music.map,
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
