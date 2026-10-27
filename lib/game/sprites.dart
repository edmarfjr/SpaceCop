import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import '../domain/battle/battle_state.dart';
import '../domain/battle/enemies.dart';
import '../domain/battle/panels.dart';
import '../domain/chips/battle_chip.dart';
import '../domain/chips/chip_library.dart';
import '../domain/element.dart' as el;
import '../domain/grid.dart';
import '../domain/map/run_map.dart';
import '../domain/run/events.dart';
import '../domain/run/relics.dart';

/// Where each piece of art lives under `assets/images/`. One file per
/// element. Every file must be in [all], or drawing it throws (and the rest
/// of the frame is not drawn).
///
/// Render-only data, so it lives here and not in the domain.
abstract final class SpriteFiles {
  /// Three 24x24 frames: idle, shooting, melee / toss.
  static const player = 'actors/plr.png';

  static const _fallback = 'actors/inimigos_canhaoMovel.png';

  /// Frames side by side, square: idle (also moving), attack. The older art
  /// is 16x16, the capangas, Colosso and Maestro 24x24 (the capanga strips
  /// have 6 empty frames after those two), the tank 40x40.
  static const enemies = <EnemyDef, String>{
    Enemies.gruntGun: 'actors/inimigos_gruntGun.png',
    Enemies.gruntDuck: 'actors/inimigos_gruntDuck.png',
    Enemies.gruntMelee: 'actors/inimigos_gruntMellee.png',
    Enemies.gruntGrenade: 'actors/inimigos_gruntGran.png',
    Enemies.gruntArtillery: 'actors/inimigos_gruntArt.png',
    Enemies.sentry: 'actors/inimigos_turret.png',
    Enemies.tank: 'actors/Tank.png',
    Enemies.mobileCannon: _fallback,
    Enemies.brute: 'actors/inimigos_gruntBrute.png',
    Enemies.cannon: 'actors/inimigos_canhaoFixo.png',
    Enemies.root: 'actors/inimigos_toco.png',
    Enemies.bubbler: 'actors/inimigos_peixe.png',
    Enemies.digger: 'actors/inimigos_gruntDigger.png',
    Enemies.prism: 'actors/inimigos_gruntStealth.png',
    Enemies.lavaGuard: 'actors/inimigos_Artilharia.png',
    Enemies.colossus: 'actors/bosses_colosso.png',
    Enemies.colossusFist: 'actors/inimigos_punho.png',
    Enemies.maestro: 'actors/bosses_maestro.png',
    Enemies.note: 'actors/inimigos_nota.png',
  };

  /// Projectiles and effects, 16x16 frames side by side.
  static const shot = 'projeteis/tiro.png';
  static const ball = 'projeteis/bola.png';
  static const pickaxe = 'projeteis/picareta.png';
  static const explosion = 'projeteis/explosao.png';

  /// Smoke cloud over a panel, 2 frames of 16x16 looped.
  static const smoke = 'projeteis/nuvem.png';

  /// Espada's vertical slash: one 16x48 frame, 3 rows tall.
  static const slash = 'projeteis/slash3Vertical.png';

  /// Energy shield, square frames looped (player's barrier, Brute).
  static const energyShield = 'projeteis/eShld.png';

  /// Warning sign over an enemy about to attack, 2 frames blinking.
  static const attackSign = 'actors/sign.png';

  /// 32x32 frame every chip card is drawn on.
  static const chipFrame = 'chips/chip.png';

  /// Same frame for upgraded ("+") cards.
  static const chipFrameUpgraded = 'chips/chipEvo.png';

  static const obstacles = <ObstacleKind, String>{
    ObstacleKind.rock: 'chips/pedra.png',
    ObstacleKind.turret: 'obstacles/drone.png',
    ObstacleKind.reflector: 'chips/stasisGen.png',
    // TODO(art): placeholder until the coil has its own sprite.
    ObstacleKind.tesla: 'chips/turret.png',
  };

  static final chips = <String, String>{
    Chips.shot.id: 'chips/revolver.png',
    Chips.smg.id: 'chips/smg.png',
    Chips.shotgun.id: 'chips/shotgun.png',
    Chips.cannon.id: 'chips/revolver.png',
    Chips.vShot.id: 'chips/plasmaPistol.png',
    Chips.melta.id: 'chips/melta.png',
    Chips.missile.id: 'chips/missilItem.png',
    Chips.baton.id: 'chips/stunIten.png',
    Chips.sword.id: 'chips/sword.png',
    Chips.grenade.id: 'chips/granada.png',
    Chips.incendiaryGrenade.id: 'chips/granadaIncend.png',
    Chips.smokeGrenade.id: 'chips/granadaFumaca.png',
    Chips.stunGrenade.id: 'chips/granadaFlash.png',
    Chips.recover.id: 'chips/hp.png',
    Chips.atkBoost.id: 'chips/hollowBlt.png',
    Chips.energyDrink.id: 'chips/energDrink.png',
    Chips.energyTank.id: 'chips/etank.png',
    Chips.powerGenerator.id: 'chips/pwrGen.png',
    Chips.cracker.id: 'chips/martelo.png',
    Chips.bubblePush.id: 'chips/bolha.png',
    Chips.crossFlame.id: 'chips/explosao.png',
    Chips.thunderLance.id: 'chips/raio.png',
    Chips.barrier.id: 'chips/energyShield.png',
    Chips.mirror.id: 'chips/stasisGen.png',
    Chips.seedGrass.id: 'chips/broto.png',
    Chips.areaSteal.id: 'chips/boot.png',
    Chips.rock.id: 'chips/pedra.png',
    Chips.mine.id: 'chips/mina.png',
    Chips.turret.id: 'chips/droneItn.png',
    Chips.hook.id: 'chips/hook.png',
    Chips.bug.id: 'chips/bug.png',
    Chips.magnetTrap.id: 'chips/explosao.png',
    // TODO(art): Tempestade and Avalanche borrow one of their parts.
    Chips.storm.id: 'chips/raio.png',
    Chips.avalanche.id: 'chips/pedra.png',
    // TODO(art): placeholders borrowed from unused or related art.
    Chips.cryoGrenade.id: 'chips/granada.png',
    Chips.emp.id: 'chips/ramPlus.png',
    Chips.neuralVine.id: 'chips/broto.png',
    Chips.laserSight.id: 'icons/target.png',
    Chips.overcharge.id: 'chips/ramUp.png',
    Chips.tractorBeam.id: 'chips/exoArm.png',
    Chips.teslaCoil.id: 'chips/turret.png',
    Chips.overclock.id: 'chips/spdLdr.png',
  };

  /// Frame drawn over every panel, by the side that owns it.
  static const panelFrames = <Team, String>{
    Team.player: 'panels/panel_panelPlr.png',
    Team.enemy: 'panels/panel_panelEnemy.png',
  };

  static const panels = <PanelState, String>{
    PanelState.normal: 'panels/panel_panel.png',
    PanelState.cracked: 'panels/panel_panelRachado.png',
    PanelState.hole: 'panels/panel_panelBuraco.png',
    PanelState.ice: 'panels/panel_panelGelo.png',
    PanelState.grass: 'panels/panel_panelGrama.png',
    PanelState.lava: 'panels/panel_panelLava.png',
  };

  static const elements = <el.Element, String>{
    el.Element.fire: 'icons/fogo.png',
    el.Element.aqua: 'icons/agua.png',
    el.Element.elec: 'icons/raio.png',
    el.Element.wood: 'icons/folha.png',
  };

  static const statuses = <Status, String>{
    Status.burning: 'icons/fogo.png',
    Status.wet: 'icons/agua.png',
    Status.stunned: 'icons/stun.png',
    Status.rooted: 'icons/raiz.png',
    Status.marked: 'icons/target.png',
  };

  static const credits = 'chips/cred.png';
  static const muzzle = 'projeteis/muzzle.png';

  static final relics = <String, String>{
    Relics.extraBattery.id: 'relics/ram.png',
    Relics.sortedFolder.id: 'relics/pasta.png',
    Relics.memberCard.id: 'relics/cartao.png',
    Relics.frontLine.id: 'relics/bandeira.png',
    Relics.collisionCore.id: 'relics/circulos.png',
    Relics.chainTrigger.id: 'relics/corrente.png',
    Relics.iceBoots.id: 'relics/bota.png',
  };

  /// Event art, 80x80, by event title. Events without one show a
  /// placeholder.
  static final events = <String, String>{
    Events.armory.title: 'events/arsenalDesprotegido.png',
    Events.informant.title: 'events/celaInformante.png',
    Events.securityTerminal.title: 'events/terminalSeguranca.png',
    Events.vault.title: 'events/cofre.png',
  };

  static const nodes = <NodeType, String>{
    NodeType.battle: 'icons/enemy.png',
    NodeType.event: 'icons/event.png',
    NodeType.elite: 'icons/elite.png',
    NodeType.rest: 'icons/fogueira.png',
    NodeType.shop: 'icons/bau.png',
    NodeType.boss: 'icons/boss.png',
  };

  static Set<String> get all => {
    player,
    credits,
    muzzle,
    chipFrame,
    chipFrameUpgraded,
    shot,
    ball,
    pickaxe,
    explosion,
    slash,
    smoke,
    energyShield,
    attackSign,
    ...enemies.values,
    ...obstacles.values,
    ...chips.values,
    ...panels.values,
    ...panelFrames.values,
    ...elements.values,
    ...statuses.values,
    ...relics.values,
    ...events.values,
    ...nodes.values,
  };
}

/// Every sprite of the game, loaded once by [StarCopGame.onLoad]. Flutter
/// widgets draw them too (see `SheetSprite`).
class GameSprites {
  GameSprites._(this._images);

  static Future<GameSprites> load(Images images) async => GameSprites._({
    for (final path in SpriteFiles.all) path: await images.load(path),
  });

  final Map<String, Image> _images;

  Sprite _file(String path) => Sprite(_images[path]!);

  Sprite _frame(String path, int index, double size) => Sprite(
    _images[path]!,
    srcPosition: Vector2(index * size, 0),
    srcSize: Vector2.all(size),
  );

  late final Sprite playerIdle = _frame(SpriteFiles.player, 0, 24);
  late final Sprite playerAttack = _frame(SpriteFiles.player, 1, 24);
  late final Sprite playerMelee = _frame(SpriteFiles.player, 2, 24);

  /// Muzzle flash, drawn in front of the player while shooting and at the
  /// Drone's barrel.
  late final Sprite muzzle = Sprite(
    _images[SpriteFiles.muzzle]!,
    srcPosition: Vector2(0, 0),
    srcSize: Vector2.all(8),
  );

  /// Cropped to the coin: the file has a lot of empty border.
  late final Sprite credits = Sprite(
    _images[SpriteFiles.credits]!,
    srcPosition: Vector2(0, 0),
    srcSize: Vector2(16, 16),
  );

  /// Moving shot, 2 frames looped.
  late final List<Sprite> shot = [
    for (var i = 0; i < 2; i++) _frame(SpriteFiles.shot, i, 16),
  ];
  late final Sprite ball = _file(SpriteFiles.ball);
  late final Sprite chipFrame = _file(SpriteFiles.chipFrame);
  late final Sprite chipFrameUpgraded = _file(SpriteFiles.chipFrameUpgraded);
  late final Sprite pickaxe = _file(SpriteFiles.pickaxe);

  /// Hits and area attacks, 4 frames played once.
  /// Energy shield loop; frame size read from the file's height.
  late final List<Sprite> attackSign = [
    for (var i = 0; i < 2; i++) _frame(SpriteFiles.attackSign, i, 16),
  ];

  late final List<Sprite> energyShield = () {
    final image = _images[SpriteFiles.energyShield]!;
    final size = image.height.toDouble();
    return [
      for (var i = 0; i < image.width ~/ image.height; i++)
        _frame(SpriteFiles.energyShield, i, size),
    ];
  }();

  late final Sprite slash = _file(SpriteFiles.slash);

  late final List<Sprite> smoke = [
    for (var i = 0; i < 2; i++) _frame(SpriteFiles.smoke, i, 16),
  ];

  late final List<Sprite> explosion = [
    for (var i = 0; i < 4; i++) _frame(SpriteFiles.explosion, i, 16),
  ];

  /// [def]'s idle frame, or its attack frame when [attacking].
  Sprite enemy(EnemyDef def, {bool attacking = false}) {
    final path = SpriteFiles.enemies[def] ?? SpriteFiles._fallback;
    final frame = _images[path]!.height.toDouble();
    return _frame(path, attacking ? 1 : 0, frame);
  }

  Sprite obstacle(ObstacleKind kind) => _file(SpriteFiles.obstacles[kind]!);

  Sprite chip(ChipDef def) =>
      _file(SpriteFiles.chips[def.id] ?? SpriteFiles.chips[Chips.shot.id]!);

  Sprite panel(PanelState state) => _file(SpriteFiles.panels[state]!);

  Sprite panelFrame(Team side) => _file(SpriteFiles.panelFrames[side]!);

  /// Null for Neutral, which has no icon.
  Sprite? element(el.Element element) =>
      switch (SpriteFiles.elements[element]) {
        final path? => _file(path),
        null => null,
      };

  Sprite status(Status status) => _file(SpriteFiles.statuses[status]!);

  Sprite relic(RelicDef relic) => _file(SpriteFiles.relics[relic.id]!);

  Sprite? event(EventDef event) => switch (SpriteFiles.events[event.title]) {
    final path? => _file(path),
    null => null,
  };

  Sprite node(NodeType type) => _file(SpriteFiles.nodes[type]!);
}
