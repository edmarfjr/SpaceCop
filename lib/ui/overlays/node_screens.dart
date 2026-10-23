import 'package:flutter/material.dart';

import '../../domain/chips/battle_chip.dart';
import '../../domain/chips/chip_library.dart';
import '../../domain/run/events.dart';
import '../../game/star_cop_game.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/chip_card_view.dart';
import '../widgets/chip_picker.dart';
import '../widgets/sheet_sprite.dart';

/// Full-screen panel shared by the non-battle nodes, in the 256x192 virtual
/// screen. Scrolls if a screen ever outgrows it.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Pico.darkBlue,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: GbText.title, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// After a won battle: add one of three chips to the deck, or skip.
class RewardOverlay extends StatelessWidget {
  const RewardOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Escolha uma carta',
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetSprite(sprite: game.sprites.credits, scale: 0.4),
          Text(
            ' +${game.rewardCredits}',
            style: GbText.small.copyWith(color: Pico.yellow),
          ),
          if (game.rewardRelic case final relic?) ...[
            const SizedBox(width: 6),
            SheetSprite(sprite: game.sprites.relic(relic), scale: 1),
            Text(
              ' ${relic.name}',
              style: GbText.small.copyWith(color: Pico.yellow),
            ),
          ],
        ],
      ),
      if (game.rewardRelic case final relic?)
        Text(
          relic.description,
          textAlign: TextAlign.center,
          style: GbText.small.copyWith(color: Pico.lightGray),
        ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        children: [
          for (final (i, def) in game.rewardOptions.indexed)
            ChipCardView(
              def: def,
              sprites: game.sprites,
              width: 76,
              autofocus: i == 0,
              onTap: () => game.pickReward(def),
            ),
        ],
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: withTap(() => game.pickReward(null)),
        child: const Text('Pular'),
      ),
    ],
  );
}

/// Campfire: rest, or upgrade one card instead.
class RestOverlay extends StatefulWidget {
  const RestOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<RestOverlay> createState() => _RestOverlayState();
}

class _RestOverlayState extends State<RestOverlay> {
  bool _upgrading = false;

  StarCopGame get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final upgradeable = game.run.upgradeable;
    if (_upgrading) {
      // The picker shows each card as it will be once upgraded.
      final previews = [
        for (final card in upgradeable) ChipCard(Chips.upgradeOf(card.def)!),
      ];
      return _Panel(
        title: 'Melhorar carta',
        children: [
          ChipPicker(
            title: 'Escolha a carta a melhorar',
            cards: previews,
            sprites: game.sprites,
            grouped: true,
            onPick: (preview) =>
                game.upgradeHere(upgradeable[previews.indexOf(preview)]),
            onCancel: () => setState(() => _upgrading = false),
          ),
        ],
      );
    }
    return _Panel(
      title: 'Descanso',
      children: [
        Text('HP ${game.run.hp}/${game.run.maxHp}'),
        const SizedBox(height: 6),
        FilledButton(
          autofocus: true,
          onPressed: withTap(game.restHere),
          child: const Text('Descansar (+30%)'),
        ),
        const SizedBox(height: 4),
        FilledButton(
          onPressed: withTap(
            upgradeable.isEmpty
                ? null
                : () => setState(() => _upgrading = true),
          ),
          child: const Text('Melhorar uma carta'),
        ),
      ],
    );
  }
}

/// Shop node: buy chips and a relic, or pay to remove a chip.
class ShopOverlay extends StatefulWidget {
  const ShopOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<ShopOverlay> createState() => _ShopOverlayState();
}

class _ShopOverlayState extends State<ShopOverlay> {
  bool _removing = false;

  StarCopGame get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final shop = game.shop;
    if (shop == null) return const SizedBox.shrink();
    final run = game.run;
    if (_removing) {
      return _Panel(
        title: 'Remover carta (${shop.removalCost} C)',
        children: [
          ChipPicker(
            title: 'Escolha a carta a remover',
            cards: run.deck,
            sprites: game.sprites,
            grouped: true,
            onPick: (card) => setState(() {
              shop.removeChip(card);
              _removing = false;
            }),
            onCancel: () => setState(() => _removing = false),
          ),
        ],
      );
    }
    final relic = shop.relic;
    return _Panel(
      title: 'Loja',
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetSprite(sprite: game.sprites.credits, scale: 0.4),
            Text(' ${run.credits}', style: GbText.small),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            for (final (i, def) in shop.chips.indexed)
              Column(
                children: [
                  ChipCardView(
                    def: def,
                    sprites: game.sprites,
                    width: 76,
                    autofocus: i == 0,
                    dimmed: run.credits < shop.chipCost,
                    onTap: () => setState(() => shop.buyChip(def)),
                  ),
                  Text(
                    '${shop.chipCost} C',
                    style: GbText.small.copyWith(color: Pico.yellow),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (relic != null)
          OutlinedButton(
            onPressed: withTap(
              run.credits < shop.relicCost
                  ? null
                  : () => setState(shop.buyRelic),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetSprite(sprite: game.sprites.relic(relic), scale: 1),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${relic.name} · ${shop.relicCost} C\n${relic.description}',
                    textAlign: TextAlign.center,
                    style: GbText.small,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: withTap(
                run.credits < shop.removalCost || run.deck.isEmpty
                    ? null
                    : () => setState(() => _removing = true),
              ),
              child: Text('Remover carta · ${shop.removalCost} C'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: withTap(game.finishNode),
              child: const Text('Sair'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Event node: pick an option; some ask for a chip of the deck first, some
/// end in a choice between offers.
class EventOverlay extends StatefulWidget {
  const EventOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<EventOverlay> createState() => _EventOverlayState();
}

class _EventOverlayState extends State<EventOverlay> {
  EventOption? _picking;

  StarCopGame get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final choice = game.eventChoice;
    if (choice != null && choice.offers.every((o) => o.relic != null)) {
      return _RelicChoice(choice: choice, game: game);
    }
    if (choice != null) {
      return _Panel(
        title: choice.title,
        children: [
          for (final (i, offer) in choice.offers.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: OutlinedButton(
                autofocus: i == 0,
                onPressed: withTap(() => game.pickOffer(offer)),
                child: Text(
                  [
                    offer.label,
                    if (offer.description.isNotEmpty) offer.description,
                  ].join('\n'),
                  textAlign: TextAlign.center,
                  style: GbText.small,
                ),
              ),
            ),
        ],
      );
    }
    final event = game.event;
    if (event == null) return const SizedBox.shrink();
    final picking = _picking;
    if (picking != null) {
      return _Panel(
        title: picking.label,
        children: [
          ChipPicker(
            title: 'Escolha uma carta do deck',
            cards: game.run.deck,
            sprites: game.sprites,
            grouped: true,
            onPick: (card) => game.resolveEvent(picking, card),
            onCancel: () => setState(() => _picking = null),
          ),
        ],
      );
    }
    return _Panel(
      title: event.title,
      children: [
        Text(
          event.text,
          textAlign: TextAlign.center,
          style: GbText.small.copyWith(color: Pico.lightGray),
        ),
        const SizedBox(height: 4),
        for (final (i, option) in event.options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: OutlinedButton(
              autofocus: i == 0,
              onPressed: withTap(
                option.pick == EventPick.deckChip && game.run.deck.isEmpty
                    ? null
                    : () => option.pick == EventPick.deckChip
                          ? setState(() => _picking = option)
                          : game.resolveEvent(option),
              ),
              child: Text(
                [
                  option.label,
                  if (option.cost.isNotEmpty) 'Custo: ${option.cost}',
                  if (option.reward.isNotEmpty) 'Ganho: ${option.reward}',
                ].join('\n'),
                textAlign: TextAlign.center,
                style: GbText.small,
              ),
            ),
          ),
      ],
    );
  }
}

/// Picking one relic: the icons side by side, the selected one's text in a
/// box below, and a button to take it.
class _RelicChoice extends StatefulWidget {
  const _RelicChoice({required this.choice, required this.game});

  final OfferChoice choice;
  final StarCopGame game;

  @override
  State<_RelicChoice> createState() => _RelicChoiceState();
}

class _RelicChoiceState extends State<_RelicChoice> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final offers = widget.choice.offers;
    final selected = offers[_selected];
    return ColoredBox(
      color: Pico.darkBlue,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Column(
          children: [
            Text(widget.choice.title, style: GbText.title),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (i, offer) in offers.indexed)
                  GestureDetector(
                    onTap: withTap(() => setState(() => _selected = i)),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: i == _selected
                              ? Pico.lightGray
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: SheetSprite(
                        sprite: widget.game.sprites.relic(offer.relic!),
                        scale: 4,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  border: Border.all(color: Pico.lightGray, width: 2),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${selected.label}: ',
                        style: const TextStyle(color: Pico.yellow),
                      ),
                      TextSpan(text: selected.description),
                    ],
                  ),
                  style: GbText.body,
                ),
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: withTap(() => widget.game.pickOffer(selected)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Pico.burgundy,
                  border: Border.all(color: Pico.yellow, width: 2),
                ),
                child: const Text('ESCOLHER', style: GbText.body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) => _Panel(
    title: game.phase.value == GamePhase.victory ? 'Vitória!' : 'Game Over',
    children: [
      FilledButton(
        autofocus: true,
        onPressed: withTap(game.startNewRun),
        child: const Text('Nova run'),
      ),
    ],
  );
}
