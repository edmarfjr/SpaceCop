import '../battle/battle_state.dart';
import '../grid.dart';

enum RelicKind {
  /// Works on the map, shop or energy.
  global,

  /// Hooks into battles.
  combat,
}

/// Passive item kept for the whole run. Every hook is optional and called
/// by the [BattleState] (or read by the [RunState]) when it applies.
class RelicDef {
  const RelicDef({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    this.onBattleStart,
    this.modifyDamage,
    this.onCollision,
    this.onChainComplete,
    this.onHandRefill,
  });

  final String id;
  final String name;
  final String description;
  final RelicKind kind;

  final void Function(BattleState battle)? onBattleStart;

  /// Adjusts the damage of a chip the player is about to use.
  final int Function(BattleState battle, int damage)? modifyDamage;

  /// A collision the player caused (push, pull).
  final void Function(BattleState battle, Collision collision)? onCollision;

  /// A 3-chip element chain was completed.
  final void Function(BattleState battle)? onChainComplete;

  /// The gauge filled and a new hand was drawn.
  final void Function(BattleState battle)? onHandRefill;
}

void _extraEnergy(BattleState battle) => battle.energyMax++;

void _peekTop(BattleState battle) =>
    battle.peekOpen = battle.deck.peek(2).isNotEmpty;

/// The player's front column in its row: the next panel ahead isn't
/// theirs, even after Roubo de Área moved the line.
int _frontLine(BattleState battle, int damage) =>
    battle.ownerAt(battle.player.pos + const GridPos(1, 0)) != Team.player
    ? (damage * 1.2).round()
    : damage;

void _hardCrash(BattleState battle, Collision collision) {
  collision
    ..damage += 20
    ..stunTicks += ticksPerSecond;
}

void _fastGauge(BattleState battle) => battle.boostNextGauge = true;

abstract final class Relics {
  static const extraBattery = RelicDef(
    id: 'extra_battery',
    name: 'Bateria Extra',
    description: '+1 de Energia base.',
    kind: RelicKind.global,
    onBattleStart: _extraEnergy,
  );

  static const sortedFolder = RelicDef(
    id: 'sorted_folder',
    name: 'Pasta Ordenada',
    description:
        'Na recarga, mostra as 2 próximas cartas; mande 1 para o fundo do deck.',
    kind: RelicKind.global,
    onHandRefill: _peekTop,
  );

  static const memberCard = RelicDef(
    id: 'member_card',
    name: 'Cartão de Sócio',
    description: 'Loja 25% mais barata; remover carta é grátis.',
    kind: RelicKind.global,
  );

  static const frontLine = RelicDef(
    id: 'front_line',
    name: 'Linha de Frente',
    description:
        'Cartas usadas na coluna mais à frente do seu lado causam +20% de dano.',
    kind: RelicKind.combat,
    modifyDamage: _frontLine,
  );

  static const collisionCore = RelicDef(
    id: 'collision_core',
    name: 'Núcleo de Colisão',
    description: 'Colisões que você causa: +20 de dano e +1 s atordoado.',
    kind: RelicKind.combat,
    onCollision: _hardCrash,
  );

  static const chainTrigger = RelicDef(
    id: 'chain_trigger',
    name: 'Gatilho de Corrente',
    description:
        'Corrente de 3 completa: o próximo gauge enche 50% mais rápido.',
    kind: RelicKind.combat,
    onChainComplete: _fastGauge,
  );

  static const iceBoots = RelicDef(
    id: 'ice_boots',
    name: 'Botas de Gelo',
    description:
        'Você não desliza no Gelo e não abre Buraco ao sair do Rachado.',
    kind: RelicKind.combat,
  );

  static const all = [
    extraBattery,
    sortedFolder,
    memberCard,
    frontLine,
    collisionCore,
    chainTrigger,
    iceBoots,
  ];
}
