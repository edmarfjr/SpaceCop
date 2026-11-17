import 'dart:math';

import 'package:flame/components.dart' show Sprite;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../domain/chips/battle_chip.dart';
import '../../domain/chips/chip_library.dart';
import '../../domain/map/run_map.dart';
import '../../domain/run/events.dart';
import '../../domain/run/relics.dart';
import '../../domain/run/run_state.dart';
import '../../game/audio.dart';
import '../../game/sprites.dart';
import '../../game/star_cop_game.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/chip_card_view.dart';
import '../widgets/chip_picker.dart';
import '../widgets/sheet_sprite.dart';

/// Full-screen panel shared by the non-battle nodes. The title and buttons
/// stay put; a [ChipPicker] child scrolls only its cards.
class _Panel extends StatelessWidget {
  const _Panel({this.title = '', this.header, required this.children});

  final String title;

  /// Drawn instead of [title].
  final Widget? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scanlines(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header ??
                // System heading: a PET title bar, in capitals.
                Container(
                  color: petTitleBar,
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 1),
                  child: Text(
                    title.toUpperCase(),
                    style: GbText.title,
                    textAlign: TextAlign.center,
                  ),
                ),
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

  /// Spoils already taken: they stay on the list, struck out, so the
  /// player sees what she got.
  final List<(Sprite, String)> _taken = [];

  /// "Pular" with spoils left asks first.
  bool _confirmSkip = false;

  StarCopGame get game => widget.game;

  void _take(Spoil spoil, {ChipDef? card, RelicDef? relic}) => setState(() {
    final (icon, text) = _describe(spoil);
    _taken.add((
      icon,
      card != null
          ? 'Carta: ${card.name}'
          : relic != null
          ? 'Relíquia: ${relic.name}'
          : text,
    ));
    game.takeSpoil(spoil, card: card, relic: relic);
    _open = null;
  });

  void _skip() => game.spoils.isEmpty
      ? game.finishNode()
      : setState(() => _confirmSkip = true);

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
    _ =>
      _confirmSkip
          ? Stack(
              children: [
                _list(),
                Positioned.fill(child: _skipDialog()),
              ],
            )
          : _list(),
  };

  Widget _list() {
    final spoils = game.spoils;
    // Title pinned to the top, buttons to the bottom; the box stays centered
    // between them and scrolls if the spoils outgrow the space.
    return Scanlines(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            Text('', style: GbText.small, textAlign: TextAlign.center),
            Text(
              spoils.isEmpty
                  ? 'Espólios'
                  : 'Espólios · ${spoils.length} '
                        '${spoils.length == 1 ? 'restante' : 'restantes'}',
              style: GbText.title,
              textAlign: TextAlign.center,
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Container(
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
                        for (final (icon, text) in _taken)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: _takenRow(icon, text),
                          ),
                        if (spoils.isEmpty && _taken.isEmpty)
                          Text(
                            'Nada mais a ser pego.',
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
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: withTap(game.showDeck),
                  child: const Text('Ver deck'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  autofocus: spoils.isEmpty,
                  onPressed: withTap(_skip),
                  child: Text(spoils.isEmpty ? 'Continuar' : 'Pular restantes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (Sprite, String) _describe(Spoil spoil) {
    final sprites = game.sprites;
    return switch (spoil) {
      CreditsSpoil(:final amount) => (sprites.credits, '$amount Créditos'),
      RelicSpoil(:final relic) => (sprites.relic(relic), relic.name),
      CardSpoil() => (sprites.deckIcon, 'Adicione uma carta ao seu deck'),
      BossRelicSpoil() => (
        sprites.node(NodeType.boss),
        'Escolha uma relíquia de chefe',
      ),
    };
  }

  /// A taken spoil: dimmed, struck out, "PEGO" on the right.
  Widget _takenRow(Sprite icon, String text) => Opacity(
    opacity: 0.45,
    child: Container(
      padding: buttonPadding,
      decoration: BoxDecoration(
        border: Border.all(color: Pico.darkGray, width: 0.5),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 12,
            child: FittedBox(child: SheetSprite(sprite: icon, scale: 1)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GbText.small.copyWith(
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
          Text('PEGO', style: GbText.small.copyWith(color: Pico.green)),
        ],
      ),
    ),
  );

  /// Over the list: what skipping loses, focus on "Voltar".
  Widget _skipDialog() {
    final left = [for (final spoil in game.spoils) _describe(spoil).$2];
    return ColoredBox(
      color: Pico.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          width: 200,
          decoration: const ShapeDecoration(
            color: Pico.midnight,
            shape: BeveledRectangleBorder(
              side: BorderSide(color: Pico.orange),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Pico.orange,
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 1),
                child: Text(
                  'PULAR ESPÓLIOS?',
                  style: GbText.body.copyWith(color: Pico.midnight),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  'Estes serão perdidos:\n${left.join('\n')}',
                  style: GbText.small,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      autofocus: true,
                      onPressed: withTap(
                        () => setState(() => _confirmSkip = false),
                      ),
                      child: const Text('Voltar'),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: withTap(game.finishNode),
                      child: Text(
                        'Pular mesmo assim',
                        style: GbText.body.copyWith(color: Pico.coral),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _spoilButton(Spoil spoil, {required bool autofocus}) {
    final (icon, text) = _describe(spoil);
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

/// The upgrade screen, shared by the campfire and the events: each of
/// [cards] shown as it will be once upgraded; [onPick] gets the deck card.
class UpgradePicker extends StatelessWidget {
  const UpgradePicker({
    super.key,
    required this.game,
    required this.cards,
    required this.onPick,
    this.title = 'Escolha a carta a melhorar',
    this.onCancel,
  });

  final StarCopGame game;
  final List<ChipCard> cards;
  final ValueChanged<ChipCard> onPick;
  final String title;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final previews = [
      for (final card in cards) ChipCard(Chips.upgradeOf(card.def)!),
    ];
    return _Panel(
      title: 'Melhorar carta',
      children: [
        ChipPicker(
          title: title,
          cards: previews,
          sprites: game.sprites,
          grouped: true,
          onPick: (preview) => onPick(cards[previews.indexOf(preview)]),
          onCancel: onCancel,
        ),
      ],
    );
  }
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
      return UpgradePicker(
        game: game,
        cards: upgradeable,
        onPick: game.upgradeHere,
        onCancel: () => setState(() => _upgrading = false),
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
    return Scanlines(
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
                  Expanded(
                    child: _ShopInfo(
                      item: _selected,
                      missing: switch (_priceOf(_selected)) {
                        final price? when price > run.credits =>
                          price - run.credits,
                        _ => null,
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: withTap(_confirm),
                    child: Text(
                      _selected == _removalService ? 'Remover' : 'Comprar',
                    ),
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

/// What the selected shop item is and, when it can't be paid, how many
/// Créditos are missing.
class _ShopInfo extends StatelessWidget {
  const _ShopInfo({required this.item, this.missing});

  final Object? item;
  final int? missing;

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
            if (missing case final missing?)
              TextSpan(
                text: '\nFaltam $missing C',
                style: const TextStyle(color: Pico.coral),
              ),
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
  Widget build(BuildContext context) => Scanlines(
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
    if (pick != null && pick.upgrade) {
      return UpgradePicker(
        game: game,
        title: pick.title,
        cards: pick.cards(game.run),
        onPick: game.resolvePick,
        onCancel: game.finishNode,
      );
    }
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
    if (picking != null && picking.pick == EventPick.upgrade) {
      return UpgradePicker(
        game: game,
        cards: picking.pickableCards(game.run),
        onPick: (card) => game.resolveEvent(picking, card),
        onCancel: () => setState(() => _picking = null),
      );
    }
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
                : () => option.pick != EventPick.none
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
    return Scanlines(
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
/// While the game starts: the title and a bar filling as the art loads.
/// Looks like the page's own loader (web/index.html), shown before it.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, required this.progress});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) => _Panel(
    title: "STARCOP'S RAID",
    children: [
      const SizedBox(height: 10),
      const Text('Carregando...', style: GbText.body),
      const SizedBox(height: 6),
      Container(
        width: 120,
        height: 8,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(border: Border.all(color: Pico.white)),
        child: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, done, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: done,
              child: const ColoredBox(color: Pico.green),
            ),
          ),
        ),
      ),
    ],
  );
}

class MenuOverlay extends StatelessWidget {
  const MenuOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      if (game.savedRun != null) ('Continuar', game.continueRun),
      ('Novo jogo', game.startNewRun),
      ('Compêndio', game.openCompendium),
      ('Manual', game.openManual),
      ('Configurações', game.openSettings),
    ];
    return Stack(
      children: [
        _Panel(
          header: _AnimatedTitle(frames: game.sprites.titleFx),
          children: [
            // The options in a PET window.
            Container(
              width: 104,
              decoration: petWindow,
              clipBehavior: Clip.hardEdge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: petTitleBar,
                    padding: const EdgeInsets.fromLTRB(4, 1, 4, 0),
                    child: const Text('> MENU', style: GbText.small),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, (label, action)) in buttons.indexed) ...[
                          if (i > 0) const SizedBox(height: 3),
                          FilledButton(
                            autofocus: i == 0,
                            onPressed: withTap(action),
                            child: Text(label),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // The policewoman beside the window, standing on a platform.
        Positioned(
          left: 56,
          bottom: 40,
          child: IgnorePointer(
            child: Column(
              children: [
                SheetSprite(sprite: game.sprites.playerIdle, scale: 3),
                Container(width: 72, height: 4, color: petTitleBar),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// After "Novo jogo": pick one of [Chips.starterDecks] to start the run with.
class DeckSelectOverlay extends StatefulWidget {
  const DeckSelectOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<DeckSelectOverlay> createState() => _DeckSelectOverlayState();
}

class _DeckSelectOverlayState extends State<DeckSelectOverlay> {
  int _index = 0;

  /// Tapping a deck focuses it too, so the focus frame marks the deck shown.
  final _focus = [for (final _ in Chips.starterDecks) FocusNode()];

  StarCopGame get game => widget.game;

  @override
  void dispose() {
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  /// Card width in the list: twice the frame, so the art stays pixel-sharp.
  static const _cardWidth = 64.0;
  static const _cardGap = 2.0;
  static const _boxPadding = 3.0;
  static const _boxWidth = _cardWidth * 3 + _cardGap * 2 + _boxPadding * 2 + 2;

  @override
  Widget build(BuildContext context) {
    final deck = Chips.starterDecks[_index];
    return Scanlines(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(deck.name, style: GbText.title),
                        const SizedBox(height: 2),
                        Text(deck.tagline, style: GbText.small),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Center(
                            child: _DeckShowcase(
                              sprites: game.sprites,
                              style: _DeckAttack.values[_index],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: _boxWidth,
                    padding: const EdgeInsets.all(_boxPadding),
                    decoration: BoxDecoration(
                      color: Pico.midnight,
                      border: Border.all(color: Pico.white),
                    ),
                    child: SingleChildScrollView(
                      // A new deck starts its list from the top.
                      key: ValueKey(_index),
                      child: Wrap(
                        spacing: _cardGap,
                        runSpacing: _cardGap,
                        children: [
                          for (final (def, count) in deck.cards)
                            Stack(
                              children: [
                                ChipCardView(
                                  def: def,
                                  sprites: game.sprites,
                                  width: _cardWidth,
                                  focusable: false,
                                ),
                                if (count > 1)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: ColoredBox(
                                      color: Pico.black,
                                      child: Text(
                                        'x$count',
                                        style: GbText.small.copyWith(
                                          color: Pico.yellow,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: withTap(game.backToMenu),
                      child: const Text('Voltar'),
                    ),
                  ),
                ),
                for (final (i, option) in Chips.starterDecks.indexed) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Tooltip(
                    message: option.name,
                    child: OutlinedButton(
                      autofocus: i == 0,
                      focusNode: _focus[i],
                      onFocusChange: (focused) {
                        if (focused) setState(() => _index = i);
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Pico.black,
                        padding: const EdgeInsets.all(2),
                        side: BorderSide(
                          color: i == _index ? Pico.yellow : Pico.lightGray,
                        ),
                      ),
                      onPressed: withTap(() {
                        _focus[i].requestFocus();
                        setState(() => _index = i);
                      }),
                      child: SheetSprite(
                        sprite: game.sprites.chip(option.cards.first.$1),
                        scale: 1,
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: withTap(() => game.startRunWith(deck)),
                      child: const Text('Começar'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// How the player attacks in the deck select's showcase, one per deck of
/// [Chips.starterDecks], in order.
enum _DeckAttack { shoot, melee, laser }

/// The deck select's illustration: the player standing, then attacking
/// with the deck's kind of card, looped. Drawn like the battle's
/// FighterComponent, at twice its scale.
class _DeckShowcase extends StatefulWidget {
  const _DeckShowcase({required this.sprites, required this.style});

  final GameSprites sprites;
  final _DeckAttack style;

  /// Art pixel size on screen.
  static const scale = 3.0;

  /// The box, in art pixels: room past the player for the weapon and beam.
  static const box = Size(40, 24);

  @override
  State<_DeckShowcase> createState() => _DeckShowcaseState();
}

class _DeckShowcaseState extends State<_DeckShowcase>
    with SingleTickerProviderStateMixin {
  /// Standing for the first half, attacking for the second.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scanlines(
    child: AnimatedBuilder(
      animation: _loop,
      builder: (context, _) => CustomPaint(
        size: _DeckShowcase.box * _DeckShowcase.scale,
        painter: _ShowcasePainter(
          sprites: widget.sprites,
          style: widget.style,
          t: _loop.value,
        ),
      ),
    ),
  );
}

class _ShowcasePainter extends CustomPainter {
  _ShowcasePainter({
    required this.sprites,
    required this.style,
    required this.t,
  });

  final GameSprites sprites;
  final _DeckAttack style;

  /// Where in the loop, 0 to 1.
  final double t;

  static final _pixel = Paint()..filterQuality = FilterQuality.none;

  /// The player's left edge in the box, in art pixels.
  static const _left = 4.0;

  /// The fist in the swing frame, as in FighterComponent.
  static const _fist = Offset(22, 9);

  /// Gun barrel tip: the beam starts right on it, no muzzle flash between.
  static const _hand = Offset(23, 9);

  /// Laser layers: outer, middle and inner, with their half heights.
  static final _beam = [
    (Paint()..color = Pico.royal, 4.0),
    (Paint()..color = Pico.blue, 2.5),
    (Paint()..color = Pico.white, 1.0),
  ];

  void _draw(Canvas canvas, Sprite sprite, Offset at) => canvas.drawImageRect(
    sprite.image,
    sprite.src,
    at & sprite.src.size,
    _pixel,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(_DeckShowcase.scale)
      ..translate(_left, 0);
    final attack = t >= 0.5;
    if (!attack) {
      _draw(canvas, sprites.playerIdle, Offset.zero);
      canvas.restore();
      return;
    }
    switch (style) {
      case _DeckAttack.shoot:
        _draw(canvas, sprites.playerAttack, Offset.zero);
        // The flash only for the first moments of the shot.
        if (t < 0.65) _draw(canvas, sprites.muzzle, const Offset(21.5, 5.5));
      case _DeckAttack.melee:
        _draw(canvas, sprites.playerMelee, Offset.zero);
        final dagger = sprites.weapon(Chips.dagger)!;
        _draw(
          canvas,
          dagger,
          _fist - Offset(0, (dagger.src.height ~/ 2).toDouble()),
        );
      case _DeckAttack.laser:
        _draw(canvas, sprites.playerAttack, Offset.zero);
        // Swells in, flickers, thins out, like the battle's beams.
        final age = (t - 0.5) / 0.5;
        final swell = min(1.0, min(age, 1 - age) * 6 + 0.2);
        final flicker = (t * 40).floor().isEven ? 0.5 : 0.0;
        final end = _DeckShowcase.box.width - _left;
        for (final (i, (paint, half)) in _beam.indexed) {
          final h = (half + (i < 2 ? flicker : 0)) * swell;
          canvas
            ..drawCircle(_hand, h, paint)
            ..drawRect(
              Rect.fromLTRB(_hand.dx, _hand.dy - h, end, _hand.dy + h),
              paint,
            );
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShowcasePainter old) => old.t != t || old.style != style;
}

/// The menu's title: plays [frames] once as the menu opens, then holds the
/// last one. The frames are taller than the final title: the band it ends
/// on takes the layout room, the start of the animation spills over it.
class _AnimatedTitle extends StatefulWidget {
  const _AnimatedTitle({required this.frames});

  final List<Sprite> frames;

  static const _frameTime = Duration(milliseconds: 100);

  /// Rows of the frame the finished title sits on.
  static const _height = 44.0;

  @override
  State<_AnimatedTitle> createState() => _AnimatedTitleState();
}

class _AnimatedTitleState extends State<_AnimatedTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: _AnimatedTitle._frameTime * widget.frames.length,
  )..forward();

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = widget.frames;
    final size = frames.first.src.size;
    return SizedBox(
      width: size.width,
      height: _AnimatedTitle._height,
      child: OverflowBox(
        maxHeight: size.height,
        child: AnimatedBuilder(
          animation: _play,
          builder: (context, _) => SheetSprite(
            sprite:
                frames[min(
                  frames.length - 1,
                  (_play.value * frames.length).floor(),
                )],
            scale: 1,
          ),
        ),
      ),
    );
  }
}

/// Picks [DeckMultiPickStep.needed] cards of the deck: a tap toggles a
/// card, "Confirmar" goes once enough are picked.
class _MultiPick extends StatefulWidget {
  const _MultiPick({
    super.key,
    required this.step,
    required this.game,
    required this.onDone,
  });

  final DeckMultiPickStep step;
  final StarCopGame game;
  final ValueChanged<List<ChipCard>> onDone;

  @override
  State<_MultiPick> createState() => _MultiPickState();
}

class _MultiPickState extends State<_MultiPick> {
  final _picked = <ChipCard>{};

  @override
  Widget build(BuildContext context) {
    final run = widget.game.run;
    final needed = widget.step.needed(run);
    return _Panel(
      title: 'Relíquia',
      children: [
        ChipPicker(
          title: '${widget.step.title} (${_picked.length}/$needed)',
          cards: widget.step.cards(run),
          sprites: widget.game.sprites,
          selected: _picked,
          onPick: (card) => setState(() {
            if (!_picked.remove(card) && _picked.length < needed) {
              _picked.add(card);
            }
          }),
        ),
        const SizedBox(height: 4),
        FilledButton(
          onPressed: _picked.length == needed
              ? withTap(() => widget.onDone(_picked.toList()))
              : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) {
    final run = game.run;
    final won = game.phase.value == GamePhase.victory;
    final (banner, color) = won
        ? ('MISSÃO CUMPRIDA', Pico.green)
        : game.abandoned
        ? ('MISSÃO ABANDONADA', Pico.orange)
        : ('MISSÃO FALHOU', Pico.red);
    final floor = (run.current?.floor ?? -1) + 1;
    final stats = [
      ('Ato · andar', '${run.act} · $floor'),
      ('Batalhas vencidas', '${run.battlesWon}'),
      ('Inimigos derrotados', '${run.enemiesDefeated}'),
      ('Créditos ganhos', '${run.creditsEarned}'),
      ('Relíquias', '${run.relics.length}'),
      ('Carta mais usada', run.favoriteCard ?? '-'),
    ];
    Widget window(String title, Widget child) => Container(
      decoration: petWindow,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: petTitleBar,
            padding: const EdgeInsets.fromLTRB(4, 1, 4, 0),
            child: Text(title, style: GbText.small),
          ),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(4), child: child),
          ),
        ],
      ),
    );
    return Scanlines(
      color: Pico.midnight,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            color: color,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              banner,
              textAlign: TextAlign.center,
              style: GbText.title.copyWith(color: Pico.midnight),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: window(
                      'RELATÓRIO',
                      Column(
                        children: [
                          for (final (label, value) in stats)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(label, style: GbText.small),
                                  ),
                                  // Long card names give way to the label.
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 80,
                                    ),
                                    child: Text(
                                      value,
                                      textAlign: TextAlign.right,
                                      overflow: TextOverflow.ellipsis,
                                      style: GbText.small.copyWith(
                                        color: Pico.yellow,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: window(
                      'DECK FINAL · ${run.deck.length}',
                      SingleChildScrollView(
                        child: Wrap(
                          spacing: 3,
                          runSpacing: 3,
                          children: [
                            for (final card in run.deck)
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Pico.black,
                                  border: Border.all(
                                    color: card.def.upgraded
                                        ? Pico.yellow
                                        : petTitleBar,
                                  ),
                                ),
                                child: SizedBox.square(
                                  dimension: 16,
                                  child: FittedBox(
                                    child: SheetSprite(
                                      sprite: game.sprites.chip(card.def),
                                      scale: 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(
                  autofocus: true,
                  onPressed: withTap(game.startNewRun),
                  child: const Text('Nova run'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: withTap(game.backToMenu),
                  child: const Text('Menu'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
      final DeckMultiPickStep step => _MultiPick(
        // A new key per step, so a new choice starts with nothing picked.
        key: ObjectKey(step),
        step: step,
        game: game,
        onDone: (cards) => setState(() => game.resolvePickup(cards: cards)),
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
