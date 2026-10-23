import 'dart:math';

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

/// Fight an elite right away; the reward is [duelWon] instead of a card.
class StartDuel extends EventFollowUp {
  const StartDuel();
}

class EventOption {
  const EventOption({
    required this.label,
    required this.apply,
    this.cost = '',
    this.reward = '',
    this.pick = EventPick.none,
  });

  final String label;
  final String cost;
  final String reward;
  final EventPick pick;

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

/// HP costs never kill: the run keeps at least 1 HP.
void _payHp(RunState run, int amount) => run.hp = max(1, run.hp - amount);

EventFollowUp? _extract(RunState run, ChipCard? _) {
  final pool = Chips.all.where((c) => c.cost == 3).toList();
  run.deck
    ..add(ChipCard(Chips.bug))
    ..add(ChipCard(pool[run.random.nextInt(pool.length)]));
  return null;
}

EventFollowUp? _debug(RunState run, ChipCard? picked) {
  _payHp(run, 15);
  run.deck.remove(picked);
  final relic = run.randomRelic(kind: RelicKind.combat);
  if (relic != null) run.relics.add(relic);
  return null;
}

EventFollowUp? _disconnect(RunState run, ChipCard? _) => null;

EventFollowUp? _duel(RunState run, ChipCard? _) => const StartDuel();

EventFollowUp? _betBattery(RunState run, ChipCard? _) {
  run.energyBaseBonus--;
  final pairs = List.of(Chips.fusionPairs)..shuffle(run.random);
  return OfferChoice('Escolha um par de fusão', [
    for (final (a, b) in pairs.take(2))
      EventOffer(
        '${a.name} + ${b.name}',
        (run) {
          run.deck
            ..add(ChipCard(a))
            ..add(ChipCard(b));
        },
        description: switch (Chips.fusionOf(a, b)) {
          final fusion? => 'Fundem em ${fusion.name}: ${fusion.description}',
          null => '',
        },
      ),
  ]);
}

EventFollowUp? _train(RunState run, ChipCard? picked) {
  _payHp(run, 10);
  if (picked != null) run.deck.add(ChipCard(picked.def));
  return null;
}

/// Arena Clandestina's duel was won: 100 Créditos and 1 of 2 relics.
OfferChoice duelWon(RunState run) {
  run.credits += 100;
  final pool = [
    for (final r in Relics.all)
      if (!run.relics.contains(r)) r,
  ]..shuffle(run.random);
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

abstract final class Events {
  static const driftingShip = EventDef(
    title: 'Nave à Deriva',
    text: 'Uma nave abandonada flutua no setor, com o porão cheio.',
    options: [
      EventOption(
        label: 'Saquear o porão',
        cost: 'Recebe a carta Bug',
        reward: '1 carta aleatória de custo 3',
        apply: _extract,
      ),
      EventOption(
        label: 'Consertar os sistemas',
        cost: '−15 HP',
        reward: 'Remove 1 carta + 1 relíquia de combate',
        pick: EventPick.deckChip,
        apply: _debug,
      ),
      EventOption(label: 'Seguir viagem', apply: _disconnect),
    ],
  );

  static const undergroundArena = EventDef(
    title: 'Arena Clandestina',
    text: 'Apostadores do submundo pagam bem por duelos fora do radar.',
    options: [
      EventOption(
        label: 'Aceitar o duelo',
        cost: 'Luta contra uma elite, sem carta de recompensa',
        reward: '1 relíquia entre 2 + 100 Créditos',
        apply: _duel,
      ),
      EventOption(
        label: 'Apostar a bateria',
        cost: '−1 de Energia base',
        reward: '1 entre 2 pares de fusão',
        apply: _betBattery,
      ),
      EventOption(
        label: 'Treinar no simulador',
        cost: '−10 HP',
        reward: 'Duplica 1 carta',
        pick: EventPick.deckChip,
        apply: _train,
      ),
    ],
  );

  static const all = [driftingShip, undergroundArena];
}
