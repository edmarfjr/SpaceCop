import 'dart:math';

import '../battle/battle_state.dart' show ticksPerSecond;
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
  const StartFight({required this.elite, this.onWin});

  final bool elite;

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
  final pool = [
    for (final r in Relics.all)
      if (!run.relics.contains(r)) r,
  ]..shuffle(run.random);
  if (pool.isEmpty) return null;
  return OfferChoice('Escolha uma relíquia', [
    for (final relic in pool.take(2))
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
  return OfferChoice('Escolha uma arma', [
    for (final def in pool.take(3))
      EventOffer(
        def.name,
        (run) => run.deck.add(ChipCard(def)),
        description: def.description,
      ),
  ]);
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
  _addRandom(run, 3);
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

bool _tradeable(ChipDef def) => def.cost < 3;

/// The picked card becomes a random card of a higher cost.
EventFollowUp? _trade(RunState run, ChipCard? picked) {
  if (picked == null) return null;
  final pool = Chips.all.where((c) => c.cost > picked.def.cost).toList();
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
        reward: '1 carta aleatória de custo 3',
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
        cost: '1 carta de custo 0 a 2',
        reward: '1 carta aleatória de custo maior',
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
}
