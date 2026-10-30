import 'dart:math';

import 'package:flame/components.dart' show Sprite;
import 'package:flutter/material.dart';

import '../../domain/chips/battle_chip.dart';
import '../../domain/chips/chip_library.dart';
import '../../domain/map/run_map.dart';
import '../../domain/run/events.dart';
import '../../domain/run/relics.dart';
import '../../domain/run/run_state.dart';
import '../../game/audio.dart';
import '../../game/star_cop_game.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/chip_card_view.dart';
import '../widgets/chip_picker.dart';
import '../widgets/sheet_sprite.dart';

/// Full-screen panel shared by the non-battle nodes. The title and buttons
/// stay put; a [ChipPicker] child scrolls only its cards.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Pico.darkBlue,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: GbText.title, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            for (final child in children)
              child is ChipPicker ? Flexible(child: child) : child,
          ],
        ),
      ),
    ),
  );
}

/// After a won battle, like Slay the Spire's: a box listing the spoils;
/// tapping one takes it, the card and boss relic ones open their choice
/// first. Whatever is left when moving on is lost.
class RewardOverlay extends StatefulWidget {
  const RewardOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<RewardOverlay> createState() => _RewardOverlayState();
}

class _RewardOverlayState extends State<RewardOverlay> {
  /// The card or boss relic choice open over the list.
  Spoil? _open;

  StarCopGame get game => widget.game;

  void _take(Spoil spoil, {ChipDef? card, RelicDef? relic}) => setState(() {
    game.takeSpoil(spoil, card: card, relic: relic);
    _open = null;
  });

  void _back() {
    GameAudio.instance.play(Sfx.cancel);
    setState(() => _open = null);
  }

  @override
  Widget build(BuildContext context) => switch (_open) {
    final CardSpoil spoil => CardReward(
      title: 'Escolha uma carta',
      cards: spoil.cards,
      game: game,
      onPick: (card) => _take(spoil, card: card),
      onSkip: _back,
    ),
    final BossRelicSpoil spoil => RelicChoice(
      title: 'Escolha uma relíquia de chefe',
      relics: spoil.relics,
      game: game,
      onPick: (relic) => _take(spoil, relic: relic),
      onSkip: _back,
    ),
    _ => _list(),
  };

  Widget _list() {
    final spoils = game.spoils;
    return _Panel(
      title: 'Espólios!',
      children: [
        Container(
          width: 200,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Pico.black,
            border: Border.all(color: Pico.lightGray, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (spoils.isEmpty)
                Text(
                  'Nada mais a pegar.',
                  textAlign: TextAlign.center,
                  style: GbText.small.copyWith(color: Pico.darkGray),
                ),
              for (final (i, spoil) in spoils.indexed)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
                  child: _spoilButton(spoil, autofocus: i == 0),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: withTap(game.showDeck),
              child: const Text('Ver deck'),
            ),
            const SizedBox(width: 8),
            TextButton(
              autofocus: spoils.isEmpty,
              onPressed: withTap(game.finishNode),
              child: Text(spoils.isEmpty ? 'Continuar' : 'Pular recompensas'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _spoilButton(Spoil spoil, {required bool autofocus}) {
    final sprites = game.sprites;
    final (icon, text) = switch (spoil) {
      CreditsSpoil(:final amount) => (sprites.credits, '$amount Créditos'),
      RelicSpoil(:final relic) => (sprites.relic(relic), relic.name),
      CardSpoil() => (sprites.deckIcon, 'Adicione uma carta ao seu deck'),
      BossRelicSpoil() => (
        sprites.node(NodeType.boss),
        'Escolha uma relíquia de chefe',
      ),
    };
    return OutlinedButton(
      autofocus: autofocus,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        backgroundColor: Pico.forest,
        padding: buttonPadding,
      ),
      onPressed: withTap(
        () => switch (spoil) {
          CardSpoil() || BossRelicSpoil() => setState(() => _open = spoil),
          _ => _take(spoil),
        },
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 12,
            child: FittedBox(child: SheetSprite(sprite: icon, scale: 1)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: GbText.small)),
        ],
      ),
    );
  }
}

/// Picking one of a few cards for the deck, or skipping: the battle
/// spoils' card choice and the events' ones.
class CardReward extends StatelessWidget {
  const CardReward({
    super.key,
    required this.title,
    required this.cards,
    required this.game,
    required this.onPick,
    required this.onSkip,
  });

  final String title;
  final List<ChipDef> cards;
  final StarCopGame game;
  final ValueChanged<ChipDef> onPick;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => _Panel(
    title: title,
    children: [
      Wrap(
        spacing: 6,
        children: [
          for (final (i, def) in cards.indexed)
            ChipCardView(
              def: def,
              sprites: game.sprites,
              width: 76,
              autofocus: i == 0,
              onTap: () => onPick(def),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: withTap(game.showDeck),
            child: const Text('Ver deck'),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onSkip, child: const Text('Pular')),
        ],
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
          onPressed: withTap(game.run.canRest ? game.restHere : null),
          child: Text(
            game.run.canRest ? 'Descansar (+30%)' : 'Descansar (Reator)',
          ),
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
        // Nothing to do here: let the player move on.
        if (!game.run.canRest && upgradeable.isEmpty) ...[
          const SizedBox(height: 4),
          TextButton(
            autofocus: true,
            onPressed: withTap(game.finishNode),
            child: const Text('Seguir'),
          ),
        ],
      ],
    );
  }
}

/// Shop node, laid out like Slay the Spire's: 5 cards on top, the removal
/// service beside them, 3 relic icons below. Tapping an item only selects
/// it and shows what it is; Confirmar buys it.
class ShopOverlay extends StatefulWidget {
  const ShopOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<ShopOverlay> createState() => _ShopOverlayState();
}

/// Selection value for the removal service.
const _removalService = #removal;

class _ShopOverlayState extends State<ShopOverlay> {
  bool _removing = false;

  /// A [ChipDef], a [RelicDef] or [_removalService].
  Object? _selected;

  StarCopGame get game => widget.game;

  void _select(Object item) => setState(() => _selected = item);

  int? _priceOf(Object? item) {
    final shop = game.shop!;
    return switch (item) {
      ChipDef() => shop.chipCost(item),
      RelicDef() => shop.relicCost(item),
      _removalService when shop.canRemove && game.run.deck.isNotEmpty =>
        shop.removalCost,
      _ => null,
    };
  }

  VoidCallback? get _confirm {
    final item = _selected;
    final price = _priceOf(item);
    if (price == null || game.run.credits < price) return null;
    final shop = game.shop!;
    return () => setState(() {
      switch (item) {
        case ChipDef():
          if (shop.buyChip(item)) GameAudio.instance.play(Sfx.buy);
          _selected = null;
        case RelicDef():
          if (shop.buyRelic(item)) GameAudio.instance.play(Sfx.buy);
          _selected = null;
          game.checkPickups();
        default:
          _removing = true;
      }
    });
  }

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
              if (shop.removeChip(card)) GameAudio.instance.play(Sfx.buy);
              _removing = false;
              _selected = null;
            }),
            onCancel: () => setState(() => _removing = false),
          ),
        ],
      );
    }
    Widget price(int cost) => Text(
      '$cost C',
      style: GbText.small.copyWith(
        color: run.credits < cost ? Pico.red : Pico.yellow,
      ),
    );
    return ColoredBox(
      color: Pico.darkBlue,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Loja', style: GbText.title),
                const Spacer(),
                SheetSprite(sprite: game.sprites.credits, scale: 0.4),
                Text(' ${run.credits}', style: GbText.body),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, def) in shop.chips.indexed) ...[
                  if (i > 0) const SizedBox(width: _shopGap),
                  Column(
                    children: [
                      // The card view draws no selection of its own.
                      _Selectable(
                        selected: _selected == def,
                        child: ChipCardView(
                          def: def,
                          sprites: game.sprites,
                          width: _shopCardWidth,
                          autofocus: i == 0,
                          dimmed: run.credits < shop.chipCost(def),
                          onTap: () => _select(def),
                        ),
                      ),
                      price(shop.chipCost(def)),
                    ],
                  ),
                ],
                const Spacer(),
                _RemovalService(
                  selected: _selected == _removalService,
                  available: shop.canRemove,
                  price: shop.canRemove ? price(shop.removalCost) : null,
                  onTap: () => _select(_removalService),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: withTap(game.finishNode),
                    child: const Text('Sair'),
                  ),
                  const SizedBox(width: 8),
                  for (final relic in shop.relics) ...[
                    GestureDetector(
                      onTap: withTap(() => _select(relic)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Selectable(
                            selected: _selected == relic,
                            child: SheetSprite(
                              sprite: game.sprites.relic(relic),
                              scale: 3,
                            ),
                          ),
                          price(shop.relicCost(relic)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: _ShopInfo(item: _selected)),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: withTap(_confirm),
                    child: const Text('Confirmar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card width in the shop: 5 of them fill the row beside the removal box.
const double _shopCardWidth = 50;
const double _shopGap = 6;

/// Yellow outline around the selected shop item.
class _Selectable extends StatelessWidget {
  const _Selectable({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(
      border: Border.all(
        color: selected ? Pico.yellow : Colors.transparent,
        width: focusBorder,
      ),
    ),
    child: child,
  );
}

/// The card removal service, a box as tall as the cards.
class _RemovalService extends StatelessWidget {
  const _RemovalService({
    required this.selected,
    required this.available,
    required this.price,
    required this.onTap,
  });

  final bool selected;
  final bool available;
  final Widget? price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: withTap(onTap),
    child: Column(
      children: [
        Container(
          width: _shopCardWidth + 8,
          height: _shopCardWidth * 1.5,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Pico.midnight,
            border: Border.all(
              color: selected ? Pico.yellow : Pico.lightGray,
              width: selected ? focusBorder : 0.5,
            ),
          ),
          child: Text(
            available ? 'Remover\numa carta\ndo deck' : 'Serviço\nusado',
            textAlign: TextAlign.center,
            style: GbText.small.copyWith(
              color: available ? Pico.white : Pico.darkGray,
            ),
          ),
        ),
        price ?? const Text('', style: GbText.small),
      ],
    ),
  );
}

/// What the selected shop item is.
class _ShopInfo extends StatelessWidget {
  const _ShopInfo({required this.item});

  final Object? item;

  @override
  Widget build(BuildContext context) {
    final (name, rarity, text) = switch (item) {
      ChipDef(:final name, :final rarity, :final description) => (
        name,
        rarity,
        description,
      ),
      RelicDef(:final name, :final rarity, :final description) => (
        name,
        rarity,
        description,
      ),
      _removalService => ('Remover carta', null, 'Tira uma carta do deck.'),
      _ => ('', null, 'Toque num item para ver o que é.'),
    };
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: Pico.lightGray, width: 0.5),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (name.isNotEmpty)
              TextSpan(
                text: rarity == null ? '$name\n' : '$name ',
                style: const TextStyle(color: Pico.yellow),
              ),
            if (rarity != null)
              TextSpan(
                text: '(${rarity.label})\n',
                style: TextStyle(color: rarityColor(rarity)),
              ),
            TextSpan(text: text),
          ],
        ),
        style: GbText.small,
      ),
    );
  }
}

/// Event screen, laid out like Slay the Spire's: the title on a banner, the
/// event's picture on the left, its text and options on the right.
class _EventScene extends StatelessWidget {
  const _EventScene({
    required this.title,
    required this.text,
    required this.options,
    this.picture,
  });

  final String title;
  final String text;
  final List<Widget> options;

  /// The event's art; null shows a placeholder.
  final Sprite? picture;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Pico.darkBlue,
    child: Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(6, 4, 6, 0),
          padding: const EdgeInsets.symmetric(vertical: 2),
          color: Pico.eggplant,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: GbText.title.copyWith(color: Pico.yellow),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: _EventPicture(sprite: picture),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          color: Pico.black,
                          child: SingleChildScrollView(
                            child: Text(text, style: GbText.body),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final option in options)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: option,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The event's art at the biggest whole scale that fits, so its pixels stay
/// square; a placeholder for events without art yet.
class _EventPicture extends StatelessWidget {
  const _EventPicture({this.sprite});

  final Sprite? sprite;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Pico.black,
      border: Border.all(color: Pico.lightGray, width: 0.5),
    ),
    child: switch (sprite) {
      final sprite? => LayoutBuilder(
        builder: (context, box) => SheetSprite(
          sprite: sprite,
          scale: max(
            1,
            (box.biggest.shortestSide / sprite.srcSize.x).floor(),
          ).toDouble(),
        ),
      ),
      null => Text(
        'imagem',
        style: GbText.small.copyWith(color: Pico.darkGray),
      ),
    },
  );
}

/// One option bar of an event: "[label]" then what it gives (green) and
/// what it costs (coral).
class _EventOptionButton extends StatelessWidget {
  const _EventOptionButton({
    required this.label,
    this.reward = '',
    this.cost = '',
    this.onPressed,
    this.autofocus = false,
  });

  final String label;
  final String reward;
  final String cost;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return OutlinedButton(
      autofocus: autofocus,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        backgroundColor: Pico.forest,
        padding: buttonPadding,
      ),
      onPressed: withTap(onPressed),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '[$label]'),
            if (reward.isNotEmpty)
              TextSpan(
                text: ' $reward.',
                style: TextStyle(color: enabled ? Pico.green : null),
              ),
            if (cost.isNotEmpty)
              TextSpan(
                text: ' $cost.',
                style: TextStyle(color: enabled ? Pico.coral : null),
              ),
          ],
        ),
        style: GbText.small,
      ),
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
    final event = game.event;
    final cards = game.eventCards;
    if (cards != null) {
      return CardReward(
        title: cards.title,
        cards: cards.cards,
        game: game,
        onPick: game.pickEventCard,
        onSkip: () => game.pickEventCard(null),
      );
    }
    final choice = game.eventChoice;
    if (choice != null && choice.offers.every((o) => o.relic != null)) {
      return RelicChoice(
        title: choice.title,
        relics: [for (final offer in choice.offers) offer.relic!],
        game: game,
        onPick: (relic) =>
            game.pickOffer(choice.offers.firstWhere((o) => o.relic == relic)),
      );
    }
    if (choice != null) {
      return _EventScene(
        title: event?.title ?? '',
        picture: event == null ? null : game.sprites.event(event),
        text: choice.title,
        options: [
          for (final (i, offer) in choice.offers.indexed)
            _EventOptionButton(
              label: offer.label,
              reward: offer.description,
              autofocus: i == 0,
              onPressed: () => game.pickOffer(offer),
            ),
        ],
      );
    }
    final pick = game.eventPick;
    if (pick != null) {
      return _Panel(
        title: event?.title ?? '',
        children: [
          ChipPicker(
            title: pick.title,
            cards: pick.cards(game.run),
            sprites: game.sprites,
            grouped: true,
            onPick: game.resolvePick,
            // Skipping a follow-up pick just ends the event.
            onCancel: game.finishNode,
          ),
        ],
      );
    }
    if (event == null) return const SizedBox.shrink();
    final picking = _picking;
    if (picking != null) {
      return _Panel(
        title: picking.label,
        children: [
          ChipPicker(
            title: 'Escolha uma carta do deck',
            cards: picking.pickableCards(game.run),
            sprites: game.sprites,
            grouped: true,
            onPick: (card) => game.resolveEvent(picking, card),
            onCancel: () => setState(() => _picking = null),
          ),
        ],
      );
    }
    return _EventScene(
      title: event.title,
      picture: game.sprites.event(event),
      text: event.text,
      options: [
        for (final (i, option) in event.options.indexed)
          _EventOptionButton(
            label: option.label,
            reward: option.reward,
            cost: option.cost,
            autofocus: i == 0,
            onPressed: !option.available(game.run)
                ? null
                : () => option.pick == EventPick.deckChip
                      ? setState(() => _picking = option)
                      : game.resolveEvent(option),
          ),
      ],
    );
  }
}

/// Picking one relic: the icons side by side, the selected one's text in a
/// box below, and a button to take it ([onSkip], if any, adds one to skip).
class RelicChoice extends StatefulWidget {
  const RelicChoice({
    super.key,
    required this.title,
    required this.relics,
    required this.game,
    required this.onPick,
    this.onSkip,
  });

  final String title;
  final List<RelicDef> relics;
  final StarCopGame game;
  final ValueChanged<RelicDef> onPick;
  final VoidCallback? onSkip;

  @override
  State<RelicChoice> createState() => _RelicChoiceState();
}

class _RelicChoiceState extends State<RelicChoice> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final relics = widget.relics;
    final selected = relics[_selected];
    return ColoredBox(
      color: Pico.darkBlue,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Column(
          children: [
            Text(widget.title, style: GbText.title),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (i, relic) in relics.indexed)
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
                        sprite: widget.game.sprites.relic(relic),
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
                        text: '${selected.name}: ',
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: withTap(() => widget.onPick(selected)),
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
                if (widget.onSkip case final skip?) ...[
                  const SizedBox(width: 8),
                  TextButton(onPressed: skip, child: const Text('Pular')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The title screen: a new run, or the saved one.
class MenuOverlay extends StatelessWidget {
  const MenuOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'STAR COP',
    children: [
      const SizedBox(height: 10),
      if (game.savedRun != null) ...[
        FilledButton(
          autofocus: true,
          onPressed: withTap(game.continueRun),
          child: const Text('Continuar'),
        ),
        const SizedBox(height: 6),
      ],
      FilledButton(
        autofocus: game.savedRun == null,
        onPressed: withTap(game.startNewRun),
        child: const Text('Novo jogo'),
      ),
      const SizedBox(height: 6),
      FilledButton(
        onPressed: withTap(game.openCompendium),
        child: const Text('Compêndio'),
      ),
    ],
  );
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

/// Over any screen: the choices a relic just taken asks for, one at a time
/// (a card of the deck to duplicate, remove, transform or upgrade; a card
/// reward).
class PickupOverlay extends StatefulWidget {
  const PickupOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<PickupOverlay> createState() => _PickupOverlayState();
}

class _PickupOverlayState extends State<PickupOverlay> {
  StarCopGame get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final step = game.run.pending.firstOrNull;
    return switch (step) {
      null => const SizedBox.shrink(),
      final DeckPickStep step => _Panel(
        title: 'Relíquia',
        children: [
          ChipPicker(
            title: step.title,
            cards: step.cards(game.run),
            sprites: game.sprites,
            grouped: true,
            onPick: (card) => setState(() => game.resolvePickup(card: card)),
          ),
        ],
      ),
      final CardRewardStep step => CardReward(
        // A new key per step, so its cards don't keep the last one's focus.
        key: ObjectKey(step),
        title: step.title,
        cards: step.cards,
        game: game,
        onPick: (def) => setState(() => game.resolvePickup(reward: def)),
        onSkip: () => setState(() => game.resolvePickup()),
      ),
    };
  }
}
