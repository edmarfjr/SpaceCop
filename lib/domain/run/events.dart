import 'dart:math';

import '../battle/battle_state.dart' show ticksPerSecond;
import '../battle/enemies.dart';
import '../grid.dart';
import '../chips/battle_chip.dart';
import '../chips/chip_library.dart';
import 'relics.dart';
import 'run_state.dart';

/// What an option asks of the player before it applies.
enum EventPick {
  none,

  /// One chip of the deck, passed to [EventOption.apply].
  deckChip,
}

/// What happens after an option applies, besides going back to the map.
sealed class EventFollowUp {
  const EventFollowUp();
}

/// Pick one of [offers].
class OfferChoice extends EventFollowUp {
  const OfferChoice(this.title, this.offers);

  final String title;
  final List<EventOffer> offers;
}

/// Pick one of [cards] for the deck, on the card reward screen; it can be
/// skipped.
class CardChoice extends EventFollowUp {
  const CardChoice(this.title, this.cards);

  final String title;
  final List<ChipDef> cards;
}

class EventOffer {
  const EventOffer(this.label, this.apply, {this.description = '', this.relic});

  final String label;

  /// What the offer does, shown under [label].
  final String description;

  /// The relic this offer gives, for its icon.
  final RelicDef? relic;
  final void Function(RunState run) apply;
}

/// Fight right away. [onWin] replaces the battle's usual rewards; null
/// keeps them (an [elite] fight pays like an elite node).
class StartFight extends EventFollowUp {
  const StartFight({required this.elite, this.onWin, this.encounter});

  final bool elite;

  /// The enemies to fight; null rolls the act's usual ones.
  final Encounter Function(RunState run)? encounter;

  /// What winning gives instead of the usual rewards; it may return null
  /// when there is nothing left to offer.
  final OfferChoice? Function(RunState run)? onWin;
}

/// Pick one card of the deck that passes [pickable], then [apply] it.
class PickCard extends EventFollowUp {
  const PickCard(this.title, this.apply, {this.pickable});

  final String title;
  final bool Function(ChipDef def)? pickable;
  final EventFollowUp? Function(RunState run, ChipCard picked) apply;

  List<ChipCard> cards(RunState run) => [
    for (final card in run.deck)
      if (pickable?.call(card.def) ?? true) card,
  ];
}

class EventOption {
  const EventOption({
    required this.label,
    required this.apply,
    this.cost = '',
    this.reward = '',
    this.pick = EventPick.none,
    this.pickable,
    this.price = 0,
  });

  final String label;
  final String cost;
  final String reward;
  final EventPick pick;

  /// With [EventPick.deckChip], which cards may be picked (all if null).
  final bool Function(ChipDef def)? pickable;

  /// Créditos the option needs; [apply] pays them.
  final int price;

  /// Deck cards this option can be applied to.
  List<ChipCard> pickableCards(RunState run) => [
    for (final card in run.deck)
      if (pickable?.call(card.def) ?? true) card,
  ];

  /// Options are disabled without a card to pick or the Créditos to pay.
  bool available(RunState run) =>
      run.credits >= price &&
      (pick == EventPick.none || pickableCards(run).isNotEmpty);

  /// [picked] is set when [pick] is [EventPick.deckChip].
  final EventFollowUp? Function(RunState run, ChipCard? picked) apply;
}

class EventDef {
  const EventDef({
    required this.title,
    required this.text,
    required this.options,
  });

  final String title;
  final String text;
  final List<EventOption> options;
}

/// What a "?" node turns out to be once entered.
enum UnknownRoom { event, battle, elite, shop }

/// 55% event, 20% normal battle, 10% elite, 15% shop.
UnknownRoom rollUnknownRoom(Random random) => switch (random.nextInt(100)) {
  < 55 => UnknownRoom.event,
  < 75 => UnknownRoom.battle,
  < 85 => UnknownRoom.elite,
  _ => UnknownRoom.shop,
};

/// HP costs never kill: the run keeps at least 1 HP.
void _payHp(RunState run, int amount) => run.hp = max(1, run.hp - amount);

EventFollowUp? _disconnect(RunState run, ChipCard? _) => null;

/// 1 of 2 relics the run doesn't own yet; null if none is left.
OfferChoice? relicChoice(RunState run) {
  final pool = run.rollRelics(2);
  if (pool.isEmpty) return null;
  return OfferChoice('Escolha uma relíquia', [
    for (final relic in pool)
      EventOffer(
        relic.name,
        (run) => run.relics.add(relic),
        description: relic.description,
        relic: relic,
      ),
  ]);
}

/// A message with a single button, to show what an option did.
OfferChoice _notice(String text) =>
    OfferChoice(text, [EventOffer('Continuar', (_) {})]);

bool _upgradeable(ChipDef def) => Chips.upgradeOf(def) != null;

bool _upgradeableAttack(ChipDef def) =>
    def.type == ChipType.attack && _upgradeable(def);

/// A random card of [cost] for the deck; returns it.
ChipDef _addRandom(RunState run, int cost) {
  final pool = Chips.all.where((c) => c.cost == cost).toList();
  final def = pool[run.random.nextInt(pool.length)];
  run.deck.add(ChipCard(def));
  return def;
}

// Arsenal Desprotegido.

EventFollowUp? _loot(RunState run, ChipCard? _) {
  _payHp(run, 10);
  final pool = Chips.all.where((c) => c.type == ChipType.attack).toList()
    ..shuffle(run.random);
  return CardChoice('Escolha uma arma', pool.take(3).toList());
}

EventFollowUp? _dismantle(RunState run, ChipCard? picked) {
  run.deck.remove(picked);
  run.credits += 40;
  return null;
}

// Cela do Informante.

EventFollowUp? _freeInformant(RunState run, ChipCard? _) =>
    const StartFight(elite: false, onWin: relicChoice);

EventFollowUp? _upgradePicked(RunState run, ChipCard? picked) {
  if (picked != null) run.upgrade(picked);
  return null;
}

// Terminal de Segurança.

EventFollowUp? _hack(RunState run, ChipCard? _) {
  if (run.random.nextBool()) return const StartFight(elite: true);
  run.credits += 75;
  return _notice('Acesso liberado: +75 Créditos');
}

EventFollowUp? _copyFiles(RunState run, ChipCard? _) {
  run.energyBaseBonus--;
  final relic = run.randomRelic(kind: RelicKind.combat);
  if (relic == null) return null;
  run.relics.add(relic);
  return _notice('Você encontrou: ${relic.name}');
}

// Cofre da Organização.

EventFollowUp? _forceVault(RunState run, ChipCard? _) {
  _payHp(run, 15);
  run.credits += 100;
  return null;
}

bool _explosive(ChipDef def) =>
    def.id == Chips.missile.id || def.id == Chips.mine.id;

EventFollowUp? _blowVault(RunState run, ChipCard? picked) {
  run.deck.remove(picked);
  run.credits += 150;
  return null;
}

// Campo de Tiro.

EventFollowUp? _practice(RunState run, ChipCard? picked) {
  _payHp(run, 10);
  return _upgradePicked(run, picked);
}

EventFollowUp? _hardPractice(RunState run, ChipCard? picked) {
  _payHp(run, 20);
  _upgradePicked(run, picked);
  if (!run.deck.any((c) => _upgradeableAttack(c.def))) return null;
  return PickCard(
    'Escolha a segunda carta',
    _upgradeSecond,
    pickable: _upgradeableAttack,
  );
}

EventFollowUp? _upgradeSecond(RunState run, ChipCard picked) =>
    _upgradePicked(run, picked);

// Agente Infiltrada.

EventFollowUp? _takeGear(RunState run, ChipCard? _) => relicChoice(run);

EventFollowUp? _cover(RunState run, ChipCard? picked) {
  run.rest();
  return _upgradePicked(run, picked);
}

EventFollowUp? _sendAway(RunState run, ChipCard? _) {
  final pool = Chips.all.where((c) => c.rarity == Rarity.rare).toList();
  run.deck.add(ChipCard(pool[run.random.nextInt(pool.length)]));
  return null;
}

// Enfermaria Clandestina.

const int _clinicHeal = 30;
const int _implantMaxHp = 10;

EventFollowUp? _medChamber(RunState run, ChipCard? _) {
  run
    ..hp = min(run.maxHp, run.hp + _clinicHeal)
    ..deck.add(ChipCard(Chips.bug));
  return null;
}

EventFollowUp? _stealSupplies(RunState run, ChipCard? _) {
  run.deck
    ..add(ChipCard(Chips.recover))
    ..add(ChipCard(Chips.recover));
  return null;
}

EventFollowUp? _implant(RunState run, ChipCard? _) {
  run
    ..energyBaseBonus += 1
    ..maxHp -= _implantMaxHp
    ..hp = min(run.hp, run.maxHp);
  return null;
}

// Hangar de Contrabando.

const int _boxPrice = 60;

EventFollowUp? _mysteryBox(RunState run, ChipCard? _) {
  run.credits -= _boxPrice;
  final relic = run.random.nextBool() ? run.randomRelic() : null;
  if (relic == null) {
    run.deck.add(ChipCard(Chips.bug));
    return _notice('A caixa só tinha sucata: você recebe Bug');
  }
  run.relics.add(relic);
  return _notice('Dentro da caixa: ${relic.name}');
}

bool _tradeable(ChipDef def) => def.rarity != Rarity.rare;

/// The picked card becomes a random card of a higher rarity.
EventFollowUp? _trade(RunState run, ChipCard? picked) {
  if (picked == null) return null;
  final pool = Chips.all
      .where((c) => c.rarity.index > picked.def.rarity.index)
      .toList();
  final def = pool[run.random.nextInt(pool.length)];
  run.deck[run.deck.indexOf(picked)] = ChipCard(def);
  return _notice('${picked.def.name} virou ${def.name}');
}

// Triturador de Evidências.

const int _shredHp = 8;

EventFollowUp? _shred(RunState run, ChipCard? picked) {
  _shredOne(run, picked);
  if (run.deck.isEmpty) return null;
  return const PickCard('Destruir mais 1 carta? (−8 HP)', _shredSecond);
}

EventFollowUp? _shredSecond(RunState run, ChipCard picked) {
  _shredOne(run, picked);
  return null;
}

void _shredOne(RunState run, ChipCard? picked) {
  if (picked == null) return;
  _payHp(run, _shredHp);
  run.deck.remove(picked);
}

EventFollowUp? _recoverDocument(RunState run, ChipCard? _) {
  final def = _addRandom(run, 2);
  return _notice('Você recuperou: ${def.name}');
}

// Refeitório dos Capangas.

/// The next battle's enemies start stunned this long.
const int sabotageStunTicks = 2 * ticksPerSecond;

EventFollowUp? _sabotage(RunState run, ChipCard? _) {
  run.openingStunTicks = sabotageStunTicks;
  return null;
}

EventFollowUp? _ambush(RunState run, ChipCard? _) =>
    const StartFight(elite: true, onWin: ambushWon);

/// Refeitório's ambush was won: 50 Créditos and 1 of 2 relics.
OfferChoice? ambushWon(RunState run) {
  run.credits += 50;
  return relicChoice(run);
}

// The second mission: the ruins of an ancient civilization, home of a
// tribe of small aliens.

// Mural dos Ancestrais.

EventFollowUp? _decipher(RunState run, ChipCard? _) {
  final pool = Chips.all.where((c) => c.family == ChipFamily.energy).toList()
    ..shuffle(run.random);
  return CardChoice('Escolha uma carta de Energia', pool.take(3).toList());
}

const int _symbolsCredits = 60;

EventFollowUp? _copySymbols(RunState run, ChipCard? _) {
  if (run.hasRelic(Relics.decoder)) {
    run.credits += _symbolsCredits;
    return _notice('Você já entende os símbolos: +$_symbolsCredits Créditos');
  }
  run.relics.add(Relics.decoder);
  return _notice('Você encontrou: ${Relics.decoder.name}');
}

// Altar da Oferenda.

const int _bloodMaxHp = 10;

EventFollowUp? _offerBlood(RunState run, ChipCard? _) {
  run
    ..maxHp -= _bloodMaxHp
    ..hp = min(run.hp, run.maxHp);
  final pool = [
    for (final r in Relics.all)
      if (r.rarity == Rarity.rare && !run.hasRelic(r)) r,
  ];
  final relic = pool.isEmpty
      ? run.randomRelic()
      : pool[run.random.nextInt(pool.length)];
  if (relic == null) return null;
  run.relics.add(relic);
  return _notice('O altar lhe concede: ${relic.name}');
}

EventFollowUp? _offerCard(RunState run, ChipCard? picked) {
  run.deck.remove(picked);
  if (!run.deck.any((c) => _upgradeable(c.def))) return null;
  return const PickCard(
    'Escolha a carta a melhorar',
    _upgradeSecond,
    pickable: _upgradeable,
  );
}

// Fonte Luminosa.

EventFollowUp? _drink(RunState run, ChipCard? _) {
  run
    ..hp = run.maxHp
    ..deck.add(ChipCard(Chips.bug));
  return null;
}

EventFollowUp? _fillFlask(RunState run, ChipCard? _) {
  final pool = Chips.all
      .where(
        (c) => c.family == ChipFamily.consumable && c.rarity == Rarity.rare,
      )
      .toList();
  final def = pool[run.random.nextInt(pool.length)];
  run.deck.add(ChipCard(def));
  return _notice('Você leva: ${def.name}');
}

// Ninho do Escaravelho.

const int _nestCredits = 100;
const int _grabPartHp = 15;

Encounter _scarabNest(RunState run) => const Encounter([
  EnemySpawn(Enemies.scarab, GridPos(4, 0)),
  EnemySpawn(Enemies.scarab, GridPos(5, 1)),
  EnemySpawn(Enemies.scarab, GridPos(4, 2)),
]);

EventFollowUp? _disarmNest(RunState run, ChipCard? _) =>
    const StartFight(elite: false, encounter: _scarabNest, onWin: nestWon);

/// Ninho do Escaravelho's swarm was beaten: [_nestCredits] Créditos.
OfferChoice? nestWon(RunState run) {
  run.credits += _nestCredits;
  return _notice('Peças valiosas no ninho: +$_nestCredits Créditos');
}

EventFollowUp? _grabPart(RunState run, ChipCard? _) {
  _payHp(run, _grabPartHp);
  if (run.hasRelic(Relics.superconductor)) {
    run.credits += _symbolsCredits;
    return _notice('Uma bobina repetida: +$_symbolsCredits Créditos');
  }
  run.relics.add(Relics.superconductor);
  return _notice('Você arrancou: ${Relics.superconductor.name}');
}

// Prisioneiro da Tribo.

const int _cageShockHp = 10;
const int _intelCredits = 60;

EventFollowUp? _freePrisoner(RunState run, ChipCard? _) {
  _payHp(run, _cageShockHp);
  return relicChoice(run);
}

EventFollowUp? _tradeIntel(RunState run, ChipCard? _) {
  run.credits += _intelCredits;
  return null;
}

// Câmara de Estase.

const int _stasisShockHp = 20;

Encounter _stasisGuards(RunState run) => const Encounter([
  EnemySpawn(Enemies.sentinel, GridPos(5, 0)),
  EnemySpawn(Enemies.sentinel, GridPos(5, 2)),
]);

EventFollowUp? _forceStasis(RunState run, ChipCard? _) =>
    const StartFight(elite: true, encounter: _stasisGuards, onWin: relicChoice);

EventFollowUp? _hackStasis(RunState run, ChipCard? _) {
  final relic = run.random.nextBool() ? run.randomRelic() : null;
  if (relic == null) {
    _payHp(run, _stasisShockHp);
    return _notice('A cápsula dá um choque: −$_stasisShockHp HP');
  }
  run.relics.add(relic);
  return _notice('A cápsula se abre: ${relic.name}');
}

// Festa da Colheita.

const int _feastCredits = 40;

/// Base energy added to the next battle only (Festa da Colheita).
const int danceEnergy = 1;

EventFollowUp? _lootFeast(RunState run, ChipCard? _) {
  run.credits += _feastCredits;
  final pool = Chips.all.where((c) => c.rarity == Rarity.common).toList()
    ..shuffle(run.random);
  return CardChoice('Escolha uma carta', pool.take(3).toList());
}

EventFollowUp? _dance(RunState run, ChipCard? _) {
  run
    ..rest()
    ..nextBattleEnergy += danceEnergy;
  return null;
}

// Forja Ancestral.

const int _forgeHp = 10;

EventFollowUp? _forge(RunState run, ChipCard? picked) {
  _payHp(run, _forgeHp);
  _upgradePicked(run, picked);
  if (!run.deck.any((c) => _upgradeable(c.def))) return null;
  return const PickCard(
    'Escolha a segunda carta',
    _upgradeSecond,
    pickable: _upgradeable,
  );
}

bool _projectile(ChipDef def) => def.family == ChipFamily.projectile;

EventFollowUp? _smelt(RunState run, ChipCard? picked) {
  run.deck.remove(picked);
  if (run.deck.any((c) => _projectile(c.def))) {
    return const PickCard(
      'Escolha o segundo Projétil',
      _smeltSecond,
      pickable: _projectile,
    );
  }
  return meleeChoice(run);
}

EventFollowUp? _smeltSecond(RunState run, ChipCard picked) {
  run.deck.remove(picked);
  return meleeChoice(run);
}

/// 3 of the Corpo-a-corpo cards above Comum (Forja Ancestral).
CardChoice meleeChoice(RunState run) => CardChoice(
  'Escolha uma arma forjada',
  ([
    for (final def in Chips.all)
      if (def.family == ChipFamily.melee && def.rarity != Rarity.common) def,
  ]..shuffle(run.random)).take(3).toList(),
);

// Oráculo do Totem.

const int _kneelMaxHp = 5;

Encounter _totemGuards(RunState run) => const Encounter([
  EnemySpawn(Enemies.etWarrior, GridPos(4, 0)),
  EnemySpawn(Enemies.etShaman, GridPos(5, 1)),
  EnemySpawn(Enemies.etWarrior, GridPos(4, 2)),
]);

EventFollowUp? _destroyTotem(RunState run, ChipCard? _) =>
    const StartFight(elite: false, encounter: _totemGuards, onWin: relicChoice);

EventFollowUp? _askOracle(RunState run, ChipCard? _) => relicChoice(run);

EventFollowUp? _kneel(RunState run, ChipCard? _) {
  run
    ..maxHp += _kneelMaxHp
    ..hp += _kneelMaxHp;
  return null;
}

// Ponte Quebrada.

const int _fallHp = 25;
const int _jumpCredits = 50;

EventFollowUp? _jump(RunState run, ChipCard? _) {
  if (run.random.nextInt(10) < 3) {
    _payHp(run, _fallHp);
    return _notice('Você escorrega e cai: −$_fallHp HP');
  }
  run.credits += _jumpCredits;
  final def = _addRandom(run, 1 + run.random.nextInt(2));
  return _notice('Do outro lado: +$_jumpCredits Créditos e ${def.name}');
}

EventFollowUp? _buildBridge(RunState run, ChipCard? picked) {
  run.deck.remove(picked);
  if (run.deck.isEmpty) return null;
  return const PickCard('Usar mais 1 carta?', _buildSecond);
}

EventFollowUp? _buildSecond(RunState run, ChipCard picked) {
  run.deck.remove(picked);
  return null;
}

abstract final class Events {
  // The first mission: the criminal organization's base.

  static const armory = EventDef(
    title: 'Arsenal Desprotegido',
    text: 'Um depósito de armas da organização, com o guarda cochilando.',
    options: [
      EventOption(
        label: 'Saquear o arsenal',
        cost: '−10 HP (o alarme dispara)',
        reward: '1 carta de ataque entre 3',
        apply: _loot,
      ),
      EventOption(
        label: 'Desmontar uma arma',
        cost: 'Remove 1 carta',
        reward: '+40 Créditos',
        pick: EventPick.deckChip,
        apply: _dismantle,
      ),
      EventOption(label: 'Sair de fininho', apply: _disconnect),
    ],
  );

  static const informant = EventDef(
    title: 'Cela do Informante',
    text: 'Um prisioneiro acena da cela: diz que conhece os segredos da base.',
    options: [
      EventOption(
        label: 'Libertar o informante',
        cost: 'Luta contra os guardas, sem carta de recompensa',
        reward: '1 relíquia entre 2',
        apply: _freeInformant,
      ),
      EventOption(
        label: 'Interrogar',
        reward: 'Melhora 1 carta',
        pick: EventPick.deckChip,
        pickable: _upgradeable,
        apply: _upgradePicked,
      ),
      EventOption(label: 'Ignorar', apply: _disconnect),
    ],
  );

  static const securityTerminal = EventDef(
    title: 'Terminal de Segurança',
    text: 'Um terminal da segurança, logado e sem ninguém por perto.',
    options: [
      EventOption(
        label: 'Hackear',
        cost: '50%: o alarme chama uma elite',
        reward: '50%: +75 Créditos',
        apply: _hack,
      ),
      EventOption(
        label: 'Copiar os arquivos',
        cost: '−1 de Energia base',
        reward: '1 relíquia de combate',
        apply: _copyFiles,
      ),
      EventOption(label: 'Desligar o terminal', apply: _disconnect),
    ],
  );

  static const vault = EventDef(
    title: 'Cofre da Organização',
    text: 'O cofre onde a gangue guarda o dinheiro sujo.',
    options: [
      EventOption(
        label: 'Arrombar na força',
        cost: '−15 HP',
        reward: '+100 Créditos',
        apply: _forceVault,
      ),
      EventOption(
        label: 'Usar um explosivo',
        cost: 'Gasta 1 Míssil ou Mina do deck',
        reward: '+150 Créditos',
        pick: EventPick.deckChip,
        pickable: _explosive,
        apply: _blowVault,
      ),
      EventOption(label: 'Deixar o cofre', apply: _disconnect),
    ],
  );

  static const shootingRange = EventDef(
    title: 'Campo de Tiro',
    text: 'O campo de tiro onde os capangas treinam. Está vazio agora.',
    options: [
      EventOption(
        label: 'Treinar a pontaria',
        cost: '−10 HP',
        reward: 'Melhora 1 carta de ataque',
        pick: EventPick.deckChip,
        pickable: _upgradeableAttack,
        apply: _practice,
      ),
      EventOption(
        label: 'Treino intenso',
        cost: '−20 HP',
        reward: 'Melhora 2 cartas de ataque',
        pick: EventPick.deckChip,
        pickable: _upgradeableAttack,
        apply: _hardPractice,
      ),
      EventOption(label: 'Só observar', apply: _disconnect),
    ],
  );

  static const undercoverAgent = EventDef(
    title: 'Agente Infiltrada',
    text: 'Uma colega da polícia, disfarçada de capanga, puxa você num canto.',
    options: [
      EventOption(
        label: 'Pegar o equipamento dela',
        reward: '1 relíquia entre 2',
        apply: _takeGear,
      ),
      EventOption(
        label: 'Pedir cobertura',
        reward: 'Recupera 30% do HP e melhora 1 carta',
        pick: EventPick.deckChip,
        pickable: _upgradeable,
        apply: _cover,
      ),
      EventOption(
        label: 'Mandar ela sair dali',
        reward: '1 carta Rara aleatória',
        apply: _sendAway,
      ),
    ],
  );

  static const clinic = EventDef(
    title: 'Enfermaria Clandestina',
    text: 'A enfermaria da gangue, com uma câmara médica ainda ligada.',
    options: [
      EventOption(
        label: 'Usar a câmara médica',
        cost: 'Recebe a carta Bug (efeito colateral)',
        reward: 'Recupera 30 HP',
        apply: _medChamber,
      ),
      EventOption(
        label: 'Roubar suprimentos',
        reward: '2 Primeiros Socorros',
        apply: _stealSupplies,
      ),
      EventOption(
        label: 'Instalar um implante',
        cost: '−10 de HP máximo',
        reward: '+1 de Energia base',
        apply: _implant,
      ),
    ],
  );

  static const hangar = EventDef(
    title: 'Hangar de Contrabando',
    text: 'Caixas de contrabando empilhadas ao lado de uma nave de carga.',
    options: [
      EventOption(
        label: 'Abrir uma caixa misteriosa',
        cost: '60 Créditos',
        reward: '50%: 1 relíquia; 50%: a carta Bug',
        price: _boxPrice,
        apply: _mysteryBox,
      ),
      EventOption(
        label: 'Trocar mercadoria',
        cost: '1 carta Comum ou Incomum',
        reward: '1 carta aleatória de raridade maior',
        pick: EventPick.deckChip,
        pickable: _tradeable,
        apply: _trade,
      ),
      EventOption(label: 'Sair', apply: _disconnect),
    ],
  );

  static const shredder = EventDef(
    title: 'Triturador de Evidências',
    text: 'A gangue tritura aqui tudo o que poderia incriminá-la.',
    options: [
      EventOption(
        label: 'Destruir arquivos',
        cost: '−8 HP por carta',
        reward: 'Remove até 2 cartas',
        pick: EventPick.deckChip,
        apply: _shred,
      ),
      EventOption(
        label: 'Recuperar um documento',
        reward: '1 carta aleatória de custo 2',
        apply: _recoverDocument,
      ),
      EventOption(label: 'Sair', apply: _disconnect),
    ],
  );

  static const messHall = EventDef(
    title: 'Refeitório dos Capangas',
    text: 'Os capangas comem distraídos, de costas para a porta.',
    options: [
      EventOption(
        label: 'Sabotar a comida',
        reward: 'Na próxima luta, os inimigos começam atordoados por 2 s',
        apply: _sabotage,
      ),
      EventOption(
        label: 'Atacar de surpresa',
        cost: 'Luta contra uma elite, sem carta de recompensa',
        reward: '1 relíquia entre 2 + 50 Créditos',
        apply: _ambush,
      ),
      EventOption(label: 'Sair', apply: _disconnect),
    ],
  );

  static const all = [
    armory,
    informant,
    securityTerminal,
    vault,
    shootingRange,
    undercoverAgent,
    clinic,
    hangar,
    shredder,
    messHall,
  ];

  // The second mission: the ruins.

  static const mural = EventDef(
    title: 'Mural dos Ancestrais',
    text: 'Uma parede inteira gravada com a história da civilização antiga.',
    options: [
      EventOption(
        label: 'Decifrar',
        reward: '1 carta de Energia entre 3',
        apply: _decipher,
      ),
      EventOption(
        label: 'Copiar os símbolos',
        reward: 'Decodificador (ou +60 Créditos)',
        apply: _copySymbols,
      ),
      EventOption(label: 'Sair', apply: _disconnect),
    ],
  );

  static const altar = EventDef(
    title: 'Altar da Oferenda',
    text: 'Um pedestal com a marca de uma mão. A inscrição pede um tributo.',
    options: [
      EventOption(
        label: 'Oferecer sangue',
        cost: '−10 de HP máximo',
        reward: '1 relíquia Rara',
        apply: _offerBlood,
      ),
      EventOption(
        label: 'Oferecer uma carta',
        cost: 'Remove 1 carta',
        reward: 'Melhora outra carta',
        pick: EventPick.deckChip,
        apply: _offerCard,
      ),
      EventOption(label: 'Sair', apply: _disconnect),
    ],
  );

  static const fountain = EventDef(
    title: 'Fonte Luminosa',
    text: 'Um líquido brilhante que os ETs bebem em seus rituais.',
    options: [
      EventOption(
        label: 'Beber',
        cost: 'Recebe a carta Bug (alucinação)',
        reward: 'Recupera todo o HP',
        apply: _drink,
      ),
      EventOption(
        label: 'Encher um frasco',
        reward: '1 carta Consumível Rara',
        apply: _fillFlask,
      ),
      EventOption(label: 'Sair', apply: _disconnect),
    ],
  );

  static const scarabNest = EventDef(
    title: 'Ninho do Escaravelho',
    text: 'Mecanismos antigos zumbem numa câmara cheia de casulos de metal.',
    options: [
      EventOption(
        label: 'Desativar o ninho',
        cost: 'Luta contra 3 Escaravelhos, sem carta de recompensa',
        reward: '+100 Créditos',
        apply: _disarmNest,
      ),
      EventOption(
        label: 'Arrancar uma peça',
        cost: '−15 HP',
        reward: 'Bobina Supercondutora (ou +60 Créditos)',
        apply: _grabPart,
      ),
      EventOption(label: 'Sair', apply: _disconnect),
    ],
  );

  static const prisoner = EventDef(
    title: 'Prisioneiro da Tribo',
    text: 'Um ET de outra tribo, preso numa jaula de energia, pede ajuda.',
    options: [
      EventOption(
        label: 'Libertar',
        cost: '−10 HP (a jaula dá choque)',
        reward: '1 relíquia entre 2',
        apply: _freePrisoner,
      ),
      EventOption(
        label: 'Trocar informação',
        reward: '+60 Créditos',
        apply: _tradeIntel,
      ),
      EventOption(label: 'Deixar', apply: _disconnect),
    ],
  );

  static const stasis = EventDef(
    title: 'Câmara de Estase',
    text: 'Uma cápsula antiga, ainda ligada, guarda um equipamento intacto.',
    options: [
      EventOption(
        label: 'Abrir na força',
        cost: 'Luta contra 2 Sentinelas, sem carta de recompensa',
        reward: '1 relíquia entre 2',
        apply: _forceStasis,
      ),
      EventOption(
        label: 'Hackear',
        cost: '50%: −20 HP',
        reward: '50%: 1 relíquia',
        apply: _hackStasis,
      ),
      EventOption(label: 'Sair', apply: _disconnect),
    ],
  );

  static const harvestFeast = EventDef(
    title: 'Festa da Colheita',
    text: 'A tribo dança em volta de uma fogueira, distraída com o ritual.',
    options: [
      EventOption(
        label: 'Saquear',
        reward: '+40 Créditos e 1 carta Comum entre 3',
        apply: _lootFeast,
      ),
      EventOption(
        label: 'Juntar-se à dança',
        reward: 'Recupera 30% do HP; +1 de Energia na próxima luta',
        apply: _dance,
      ),
      EventOption(
        label: 'Sabotar',
        reward: 'Na próxima luta, os inimigos começam atordoados por 2 s',
        apply: _sabotage,
      ),
    ],
  );

  static const forge = EventDef(
    title: 'Forja Ancestral',
    text: 'Uma bigorna de plasma que ainda funciona depois de milênios.',
    options: [
      EventOption(
        label: 'Forjar',
        cost: '−10 HP',
        reward: 'Melhora 2 cartas',
        pick: EventPick.deckChip,
        pickable: _upgradeable,
        apply: _forge,
      ),
      EventOption(
        label: 'Fundir',
        cost: 'Remove até 2 cartas de Projétil',
        reward: '1 carta Corpo-a-corpo Incomum',
        pick: EventPick.deckChip,
        pickable: _projectile,
        apply: _smelt,
      ),
      EventOption(label: 'Sair', apply: _disconnect),
    ],
  );

  static const oracle = EventDef(
    title: 'Oráculo do Totem',
    text: 'Um totem fala com voz metálica. Os ETs acham que é um deus.',
    options: [
      EventOption(
        label: 'Perguntar sobre o futuro',
        reward: '1 relíquia entre 2',
        apply: _askOracle,
      ),
      EventOption(
        label: 'Destruir o totem',
        cost: 'Luta contra os guardiões, sem carta de recompensa',
        reward: '1 relíquia entre 2',
        apply: _destroyTotem,
      ),
      EventOption(label: 'Ajoelhar', reward: '+5 de HP máximo', apply: _kneel),
    ],
  );

  static const brokenBridge = EventDef(
    title: 'Ponte Quebrada',
    text: 'Uma passarela sobre o abismo, com painéis soltos e instáveis.',
    options: [
      EventOption(
        label: 'Pular',
        cost: '30%: cai e perde 25 HP',
        reward: '70%: +50 Créditos e 1 carta',
        apply: _jump,
      ),
      EventOption(
        label: 'Construir com cartas',
        reward: 'Remove até 2 cartas',
        pick: EventPick.deckChip,
        apply: _buildBridge,
      ),
      EventOption(label: 'Voltar', apply: _disconnect),
    ],
  );

  /// The events of [act]; the ruins have their own.
  static List<EventDef> of(int act) => act == 2 ? ruins : all;

  static const ruins = [
    mural,
    altar,
    fountain,
    scarabNest,
    prisoner,
    stasis,
    harvestFeast,
    forge,
    oracle,
    brokenBridge,
  ];
}
