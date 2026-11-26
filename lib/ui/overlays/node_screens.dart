import 'dart:math';

import 'package:flame/components.dart' show Sprite, Vector2;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../domain/battle/battle_state.dart'
    show
        FlashKind,
        HitFlash,
        ObstacleKind,
        Status,
        Trail,
        Zap,
        ZapStyle,
        playerAttackCooldown,
        playerLob,
        ticksPerSecond;
import '../../domain/chips/battle_chip.dart';
import '../../domain/chips/chip_library.dart';
import '../../domain/element.dart' as el;
import '../../domain/grid.dart' show GridPos;
import '../../domain/map/run_map.dart';
import '../../domain/run/events.dart';
import '../../domain/run/relics.dart';
import '../../domain/run/run_state.dart';
import '../../domain/run/shop.dart' show removalPriceStep;
import '../../game/audio.dart';
import '../../game/battle/chip_fx_layer.dart' show ChipFxLayer;
import '../../game/battle/damage_text.dart' show DamageText, HealBurst;
import '../../game/battle/projectile_layer.dart' show ProjectileLayer;
import '../../game/player_attack_art.dart';
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
            // System heading: a PET title bar, in capitals.
            header ?? _TitleBar(title),
            const SizedBox(height: 6),
            for (final child in children)
              child is ChipPicker ? Flexible(child: child) : child,
          ],
        ),
      ),
    ),
  );
}

/// A PET window with a small title bar ("> DECK") over [child]. With
/// [expand], [child] fills the window's height.
class _PetWindow extends StatelessWidget {
  const _PetWindow({
    required this.title,
    required this.child,
    this.decoration = petWindow,
    this.expand = false,
  });

  final String title;
  final Widget child;
  final ShapeDecoration decoration;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: const EdgeInsets.all(4), child: child);
    return Container(
      decoration: decoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: petTitleBar,
            padding: const EdgeInsets.fromLTRB(4, 1, 4, 0),
            child: Text(title, style: GbText.small, maxLines: 1),
          ),
          expand ? Expanded(child: body) : body,
        ],
      ),
    );
  }
}

/// A screen's title on the PET title bar, in capitals (as [_Panel]'s).
/// With [expand], the bar takes the whole width it is given, its title
/// centered on it; it needs a bounded width then (not straight in a Row).
class _TitleBar extends StatelessWidget {
  const _TitleBar(this.title, {this.expand = false});

  final String title;
  final bool expand;

  @override
  Widget build(BuildContext context) => Container(
    width: expand ? double.infinity : null,
    alignment: expand ? Alignment.center : null,
    color: petTitleBar,
    padding: const EdgeInsets.fromLTRB(8, 2, 8, 1),
    child: Text(
      title.toUpperCase(),
      style: GbText.title,
      textAlign: expand ? TextAlign.center : null,
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
                const _TitleBar('Loja'),
                const Spacer(),
                // The wallet, in a small PET window.
                Container(
                  decoration: petWindow,
                  padding: const EdgeInsets.fromLTRB(4, 1, 6, 1),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SheetSprite(sprite: game.sprites.credits, scale: 0.4),
                      Text(
                        ' ${run.credits} C',
                        style: GbText.body.copyWith(color: Pico.yellow),
                      ),
                    ],
                  ),
                ),
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
                          // Each relic on its own PET pad.
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: _selected == relic
                                ? petWindowFramed(
                                    Pico.yellow,
                                    width: focusBorder,
                                  )
                                : petWindow,
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
        SizedBox(
          width: _shopCardWidth + 8,
          height: _shopCardWidth * 1.5,
          child: _PetWindow(
            title: '> SERVIÇO',
            expand: true,
            decoration: selected
                ? petWindowFramed(Pico.yellow, width: focusBorder)
                : petWindow,
            child: Center(
              child: Text(
                available ? 'Remover\numa carta\ndo deck' : 'Serviço\nusado',
                textAlign: TextAlign.center,
                style: GbText.small.copyWith(
                  color: available ? Pico.white : Pico.darkGray,
                ),
              ),
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
      _removalService => (
        'Remover carta',
        null,
        'Tira uma carta do deck. Fica $removalPriceStep C mais cara a cada '
            'remoção.',
      ),
      _ => ('', null, 'Toque num item para ver o que é.'),
    };
    // The item's name goes on the window's title bar.
    return _PetWindow(
      title: name.isEmpty ? '> INFO' : '> ${name.toUpperCase()}',
      expand: true,
      child: Text.rich(
        TextSpan(
          children: [
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
        /* Positioned(
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
        ),*/
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

  /// The card tapped in the deck's box, shown in the showcase; null shows
  /// the deck's first card, the one on its button.
  ChipDef? _card;

  /// Shows deck [i], from the showcase's default card.
  void _showDeck(int i) => setState(() {
    if (i != _index) _card = null;
    _index = i;
  });

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

  /// [_PetWindow]'s padding.
  static const _boxPadding = 4.0;
  static const _boxWidth = _cardWidth * 3 + _cardGap * 2 + _boxPadding * 2 + 2;

  @override
  Widget build(BuildContext context) {
    final deck = Chips.starterDecks[_index];
    final shown = _card ?? deck.cards.first.$1;
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
                        _TitleBar(deck.name, expand: true),
                        const SizedBox(height: 3),
                        Text(deck.tagline, style: GbText.small),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Center(
                            child: _CardShowcase(
                              sprites: game.sprites,
                              def: shown,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: _boxWidth,
                    child: _PetWindow(
                      title:
                          '> DECK · ${deck.cards.fold(0, (n, c) => n + c.$2)}'
                          ' CARTAS',
                      expand: true,
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
                                    selected: def == shown,
                                    onTap: () => setState(() => _card = def),
                                  ),
                                  // The card in the showcase.
                                  if (def == shown)
                                    const Positioned.fill(
                                      child: IgnorePointer(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border.fromBorderSide(
                                              BorderSide(
                                                color: Pico.green,
                                                width: focusBorder,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
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
                                            color: Pico.white,
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
                        if (focused) _showDeck(i);
                      },
                      // PET buttons; the deck shown keeps a yellow frame
                      // when the focus is elsewhere.
                      style: ButtonStyle(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.all(2),
                        ),
                        side: i == _index
                            ? WidgetStateProperty.resolveWith(
                                (states) => BorderSide(
                                  color: states.contains(WidgetState.focused)
                                      ? Pico.white
                                      : Pico.yellow,
                                  width: focusBorder,
                                ),
                              )
                            : null,
                      ),
                      onPressed: withTap(() {
                        _focus[i].requestFocus();
                        _showDeck(i);
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

/// The deck select's illustration: the player standing, then using [def]
/// the way the battle draws it (see [PlayerAttackArt]), looped, at a bigger
/// scale than the battle's.
class _CardShowcase extends StatefulWidget {
  const _CardShowcase({required this.sprites, required this.def});

  final GameSprites sprites;
  final ChipDef def;

  /// Art pixel size on screen.
  static const scale = 2.0;

  /// The box, in art pixels: room past the player for the weapon and beam.
  static const box = Size(80, 52);

  @override
  State<_CardShowcase> createState() => _CardShowcaseState();
}

class _CardShowcaseState extends State<_CardShowcase>
    with SingleTickerProviderStateMixin {
  /// Standing for the first half, attacking for the second.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  late PlayerAttackArt _art = PlayerAttackArt(widget.sprites, widget.def);

  @override
  void didUpdateWidget(_CardShowcase old) {
    super.didUpdateWidget(old);
    if (old.def == widget.def && old.sprites == widget.sprites) return;
    _art = PlayerAttackArt(widget.sprites, widget.def);
    // A new card shows its attack right away.
    _loop
      ..value = 0.5
      ..repeat();
  }

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
        size: _CardShowcase.box * _CardShowcase.scale,
        painter: _ShowcasePainter(
          sprites: widget.sprites,
          art: _art,
          t: _loop.value,
        ),
      ),
    ),
  );
}

/// Draws the showcase in art pixels. What the card puts on screen follows
/// the battle: the same streaks, rings, flashes and beams (drawn by the
/// battle's own layers' helpers), aimed at an imagined enemy [_foe].
class _ShowcasePainter extends CustomPainter {
  _ShowcasePainter({required this.sprites, required this.art, required this.t});

  final GameSprites sprites;
  final PlayerAttackArt art;

  /// Where in the loop, 0 to 1.
  final double t;

  static final _pixel = Paint()..filterQuality = FilterQuality.none;

  /// The player's left edge in the box, in art pixels.
  static const _left = 4.0;

  static const _center = 12.0;

  /// The box's right edge, from the player's left edge.
  static final _end = _CardShowcase.box.width - _left;

  /// Seconds of the attack half of the loop, and of the whole loop.
  static const _attackSeconds = 0.7;
  static const _loopMs = 1400;

  /// When a shot or a lob gets to its panel, as a share of the attack.
  static const _arrival = 0.5;

  /// Peak of a lob over the straight line, in art pixels.
  static const _lobHeight = 8.0;

  /// The enemy shots and streaks go for, two panels ahead, and the one a
  /// hit jumps to, a row down; as the battle's (columns, rows) from the
  /// player.
  static const _foe = GridPos(2, 0);
  static const _nextFoe = GridPos(2, 1);

  /// Investida's ghost.
  static final _ghost = Paint()..filterQuality = FilterQuality.none;

  static final _smoke = Paint();

  /// A panel's middle, in art pixels from the player's left edge; [cell]
  /// counts columns ahead and rows down from the player, as in the battle.
  static Offset _cell(GridPos cell) =>
      Offset(12 + cell.x * _panel, 12 + cell.y * _panel);

  /// A panel's size in the showcase, in art pixels.
  static const _panel = 16.0;

  /// Ticks the player takes to glide back on a recoil, about as long as
  /// the battle's view takes.
  static const _glideTicks = 5;

  /// Where the player stands when using the card: a panel ahead per panel
  /// a recoil (Salto Acrobático) takes them back, so they land at the
  /// box's usual spot.
  Offset get _start => switch (art.def.effect) {
    MeleeEffect(:final recoil) when recoil > 0 => Offset(_panel * recoil, 0),
    _ => Offset.zero,
  };

  static Offset _offset(Vector2 v) => Offset(v.x, v.y);

  /// Battle ticks since [age] (0 to 1 over the attack) began.
  static int _ticks(double age) =>
      (age * _attackSeconds * ticksPerSecond).floor();

  void _draw(Canvas canvas, Sprite sprite, Offset at, {Paint? paint}) =>
      canvas.drawImageRect(
        sprite.image,
        sprite.src,
        at & sprite.src.size,
        paint ?? _pixel,
      );

  /// Draws [sprite] centered on [at].
  void _drawCentered(Canvas canvas, Sprite sprite, Offset at, {Paint? paint}) =>
      _draw(
        canvas,
        sprite,
        at - Offset(sprite.src.width / 2, sprite.src.height / 2),
        paint: paint,
      );

  /// Runs [draw] in the battle's pixels (2 per art pixel), for the battle
  /// layers' helpers.
  static void _inBattlePixels(Canvas canvas, void Function() draw) {
    canvas
      ..save()
      ..scale(0.5);
    draw();
    canvas.restore();
  }

  static Vector2 _battle(Offset art) => Vector2(art.dx, art.dy) * 2;

  /// When the card's hits land, as a share of the attack.
  double get _hitAt => switch (art.def) {
    ChipDef(lobs: true) => _arrival,
    final ChipDef def when def.firesShots => _arrival,
    _ => 0,
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..scale(_CardShowcase.scale);
    if (t < 0.5) {
      canvas.translate(_left, _center);
      _draw(canvas, sprites.playerIdle, _start);
      canvas.restore();
      return;
    }
    final age = (t - 0.5) * 2;
    final def = art.def;
    // Martelo Sísmico and the like shake the picture on the hit.
    if (def.fx == ChipFx.quake && age >= _hitAt && age < _hitAt + 0.25) {
      canvas.translate((t * 60).floor().isEven ? 1 : -1, 0);
    }
    canvas.translate(_left, _center);
    final ticks = _ticks(age);
    // A new shape for the bolts every 60 ms, like the battle's.
    final shape = Random((t * _loopMs / 60).floor());
    _player(canvas, ticks);
    // The blow lands from where the card was used, before any recoil.
    canvas
      ..save()
      ..translate(_start.dx, _start.dy);
    _effects(canvas, age, ticks, shape);
    canvas.restore();
    _onPlayer(canvas, age);
    canvas.restore();
  }

  /// What shows over the player in battle: the heal's green crosses, or
  /// the attack bonus the card leaves for the next attacks ("+X").
  void _onPlayer(Canvas canvas, double age) {
    final effect = art.def.effect;
    final heals = switch (effect) {
      HealEffect() || CleanseEffect() || EmergencyHealEffect() => true,
      SelfStatusEffect(status: Status.regen) => true,
      MeleeEffect(lifesteal: true) => true,
      _ => false,
    };
    final bonus = switch (effect) {
      DamageBoostEffect(:final amount) => amount,
      AttackChargesEffect(:final amount) => amount,
      _ => 0,
    };
    if (!heals && bonus == 0) return;
    // In the battle's pixels, where the texts are sized: the player's
    // 24px frame is 48 there, its feet's middle at (24, 48).
    _inBattlePixels(canvas, () {
      if (heals) {
        HealBurst.paint(
          canvas,
          Vector2(24, 48),
          Vector2.all(48),
          age * _attackSeconds,
        );
      }
      if (bonus > 0) {
        DamageText.paintText(
          canvas,
          '+$bonus',
          Vector2(24, 12),
          Pico.yellow,
          0,
        );
      }
    });
  }

  /// The attack frame and what is in the fist. Investida dashes a panel
  /// ahead and the Salto Acrobático glides back one after its blow, both
  /// leaving a fading ghost where they were, like the battle's trail.
  void _player(Canvas canvas, int ticks) {
    var at = Offset.zero;
    Offset? ghost;
    if (art.def.effect is DashEffect) {
      at = const Offset(_panel, 0);
      ghost = Offset.zero;
    } else if (_start != Offset.zero) {
      at = Offset.lerp(_start, Offset.zero, min(1, ticks / _glideTicks))!;
      ghost = _start;
    }
    if (ghost != null) {
      final fade = 1 - ticks / Trail.lifetime;
      if (fade > 0) {
        _ghost.color = Pico.blue.withValues(alpha: 0.5 * fade);
        _draw(canvas, sprites.playerIdle, ghost, paint: _ghost);
      }
    }
    // Drawn in the battle's order: body, then what's in the fist.
    _draw(canvas, art.body, at);
    final held = art.held;
    final heldAt = art.heldAt;
    if (held != null && heldAt != null) {
      _draw(canvas, held, at + _offset(heldAt));
    }
  }

  void _effects(Canvas canvas, double age, int ticks, Random shape) {
    final def = art.def;
    final effect = def.effect;
    // Like the muzzle flash, from the end of what is in the fist.
    final hand = _offset(art.emitter);
    final foe = _cell(_foe);
    // Down its own row, a streak stays level with the hand.
    final foeLevel = Offset(foe.dx, hand.dy);

    if (art.muzzleAt case final at?
        when ticks < playerAttackCooldown &&
            def.fx != ChipFx.beam &&
            def.fx != ChipFx.bolt) {
      _draw(canvas, art.muzzle, _offset(at));
    }

    // Streaks out of the hand, as the card is used.
    if (ticks < Zap.lifetime) {
      switch (effect) {
        case KindStrikeEffect():
          _zap(canvas, ZapStyle.bolt, hand, foeLevel, shape, def.corFx);
        case SweepEffect():
          for (final row in const [-1, 0, 1]) {
            final to = _cell(GridPos(_foe.x, row));
            _zap(
              canvas,
              ZapStyle.laser,
              hand,
              row == 0 ? foeLevel : to,
              shape,
              def.corFx,
            );
          }
        case TractorEffect():
          _zap(canvas, ZapStyle.tractor, hand, foeLevel, shape, def.corFx);
        case MeleeEffect(:final pattern) when def.fx == ChipFx.bolt:
          // Sparks to every panel hit (Cacetete, Chicote).
          for (final cell in pattern) {
            final to = _cell(cell);
            _zap(
              canvas,
              ZapStyle.bolt,
              hand,
              cell.y == 0 ? Offset(to.dx, hand.dy) : to,
              shape,
              def.corFx,
            );
          }
        default:
          break;
      }
    }

    if (def.fx == ChipFx.rings) {
      _inBattlePixels(
        canvas,
        () => ChipFxLayer.drawRings(canvas, _battle(hand), 3, ticks),
      );
    }

    if (def.fx == ChipFx.glitch && ticks < 2 * Zap.lifetime) {
      final body = Rect.fromCenter(center: foe, width: 24, height: 24);
      _inBattlePixels(
        canvas,
        () => ChipFxLayer.drawStatic(
          canvas,
          Rect.fromLTRB(
            body.left * 2,
            body.top * 2,
            body.right * 2,
            body.bottom * 2,
          ),
          shape,
        ),
      );
    }

    if (def.fx == ChipFx.beam) _beam(canvas, hand, age, effect);

    switch (effect) {
      case MeleeEffect(:final pattern, :final slash):
        _melee(canvas, pattern, slash: slash, ticks: ticks);
      case DashEffect(melee: MeleeEffect(:final pattern, :final slash)):
        // From the panel it dashed to.
        _melee(
          canvas,
          [for (final cell in pattern) cell + const GridPos(1, 0)],
          slash: slash,
          ticks: ticks,
        );
      case RowStrikeEffect():
        for (var x = 1; x <= 3; x++) {
          _blast(canvas, _cell(GridPos(x, 0)), ticks);
        }
      case KindStrikeEffect() || SweepEffect():
        for (final row in effect is SweepEffect ? const [-1, 0, 1] : [0]) {
          _blast(canvas, _cell(GridPos(_foe.x, row)), ticks);
        }
      case SpawnObstacleEffect(:final kind):
        _summon(canvas, kind);
      default:
        if (def.lobs) {
          _lob(canvas, hand, age, shape);
        } else if (def.firesShots) {
          _shot(canvas, hand, foeLevel, age, shape);
        } else if (def.fx == ChipFx.sniper && ticks < Zap.lifetime) {
          _zap(
            canvas,
            ZapStyle.tracer,
            hand,
            Offset(foeLevel.dx, hand.dy),
            shape,
            def.corFx,
          );
        }
    }
  }

  /// The Holograma's look in battle: see-through and blue.
  static final _hologram = Paint()
    ..filterQuality = FilterQuality.none
    ..colorFilter = ColorFilter.mode(
      Pico.blue.withValues(alpha: 0.5),
      BlendMode.srcATop,
    )
    ..color = const Color(0xB0FFFFFF);

  /// A mine on its panel, see-through like the battle's.
  static final _mine = Paint()
    ..filterQuality = FilterQuality.none
    ..color = Pico.white.withValues(alpha: 0.6);

  /// What the card lays, standing on the panel ahead as the battle draws
  /// it once there; nothing is drawn flying to it. A mine lies on the
  /// floor, the size of a panel's mark.
  void _summon(Canvas canvas, ObstacleKind kind) {
    final x = _cell(_foe).dx;
    if (kind == ObstacleKind.mine) {
      final mine = sprites.chip(Chips.mine);
      canvas.drawImageRect(
        mine.image,
        mine.src,
        Rect.fromCenter(center: Offset(x, 16), width: 16, height: 16),
        _mine,
      );
      return;
    }
    final sprite = sprites.obstacle(kind, element: art.def.tint);
    // Feet on the player's feet line, the box's bottom.
    _draw(
      canvas,
      sprite,
      Offset(
        x - sprite.src.width / 2,
        _CardShowcase.box.height / 2 - sprite.src.height,
      ),
      paint: kind == ObstacleKind.decoy ? _hologram : null,
    );
  }

  void _zap(
    Canvas canvas,
    ZapStyle style,
    Offset from,
    Offset to,
    Random shape,
    Color corFx,
  ) => _inBattlePixels(
    canvas,
    () => ChipFxLayer.drawZap(
      canvas,
      style,
      _battle(from),
      _battle(to),
      shape,
      corFx,
    ),
  );

  /// A blow on [pattern]'s panels: a hit flash on each, plus the Foice's
  /// cuts or the sword's slash in front.
  void _melee(
    Canvas canvas,
    List<GridPos> pattern, {
    required bool slash,
    required int ticks,
  }) {
    final def = art.def;
    if (slash && ticks < HitFlash.lifetime) {
      final front = pattern.first.x;
      _drawCentered(
        canvas,
        sprites.slash,
        _cell(GridPos(front, 0)),
        paint: ProjectileLayer.tintOf(
          FlashKind.slash,
          def.tint == el.Element.neutral ? null : def.tint,
        ),
      );
    }
    for (final cell in pattern) {
      if (def.fx == ChipFx.cut && ticks < HitFlash.lifetime) {
        _cut(canvas, cell);
      }
      _blast(canvas, _cell(cell) + Offset(0, -3), ticks);
    }
  }

  /// Half the slash on [cell], leaning toward it, as the battle's.
  void _cut(Canvas canvas, GridPos cell) {
    final at = _cell(cell);
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(cell.y < 0 ? 0.6 : (cell.y > 0 ? -0.6 : 0));
    _drawCentered(canvas, sprites.cut, Offset.zero);
    canvas.restore();
  }

  /// The 4-frame hit flash on [at], [ticks] after the hit, in the colors
  /// the card's flashes take.
  void _blast(Canvas canvas, Offset at, int ticks) {
    if (ticks < 0 || ticks >= HitFlash.lifetime) return;
    final def = art.def;
    final kind = def.fx == ChipFx.pulse ? FlashKind.pulse : FlashKind.explosion;
    final element = def.fx == ChipFx.blast ? def.tint : null;
    final frames = sprites.explosion;
    final frame = (ticks * frames.length ~/ HitFlash.lifetime).clamp(
      0,
      frames.length - 1,
    );
    _drawCentered(
      canvas,
      frames[frame],
      at,
      paint: ProjectileLayer.tintOf(kind, element),
    );
  }

  /// A shot from the hand to [to], then what its hit does there.
  /// The Gancho, as in battle: no shot, its chain reaches from the
  /// weapon's end to [to], hits (a flash there), stays on the target being
  /// pulled in, then winds back into the hand.
  void _hook(Canvas canvas, Offset hand, Offset to, double age, Random shape) {
    final Offset end;
    if (age < _arrival) {
      end = Offset.lerp(hand, to, age / _arrival)!;
    } else {
      // Like the battle's chain zap: holds its first half, winds back its
      // second.
      final held = (age - _arrival) / (1 - _arrival);
      end = Offset.lerp(to, hand, (held * 2 - 1).clamp(0.0, 1.0))!;
      _blast(canvas, _cell(_foe), _ticks(age - _arrival));
    }
    _zap(canvas, ZapStyle.chain, hand, end, shape, art.def.corFx);
  }

  void _shot(Canvas canvas, Offset hand, Offset to, double age, Random shape) {
    final def = art.def;
    if (def.effect is PullEffect) {
      _hook(canvas, hand, to, age, shape);
      return;
    }
    if (age < _arrival) {
      final f = age / _arrival;
      final at = Offset.lerp(hand, to, f)!;
      if (def.fx == ChipFx.smoke) _smokeTrail(canvas, hand, to, f);
      // The beam covers its own shots.
      if (def.fx != ChipFx.beam && def.fx != ChipFx.bolt) {
        _drawCentered(
          canvas,
          def.fx == ChipFx.spear
              ? sprites.spear
              : sprites.shot[(age * 10).floor() % 2],
          at,
        );
      }
      // Arco Voltaico: lightning from the hand to the shot.
      if (def.fx == ChipFx.bolt) {
        _zap(canvas, ZapStyle.bolt, hand, at, shape, def.corFx);
      }
      if (def.fx == ChipFx.sniper && age < _arrival / 2) {
        _zap(
          canvas,
          ZapStyle.tracer,
          hand,
          Offset(_end, hand.dy),
          shape,
          def.corFx,
        );
      }
      return;
    }
    final ticks = _ticks(age - _arrival);
    final foe = _cell(_foe);
    final next = _cell(_nextFoe);
    final pattern = switch (def.effect) {
      ProjectileEffect(:final pattern) => pattern,
      _ => const [GridPos(0, 0)],
    };
    for (final cell in pattern) {
      _blast(canvas, _cell(_foe + cell) + Offset(0, -3), ticks);
    }
    if (ticks >= Zap.lifetime) return;
    switch (def.effect) {
      // Ricochete, Arco Voltaico, Condutor: the hit jumps on.
      case BounceEffect() || ConductorEffect()
          when def.fx == ChipFx.bolt || def.fx == ChipFx.tracer:
        _zap(
          canvas,
          def.fx == ChipFx.bolt ? ZapStyle.bolt : ZapStyle.tracer,
          foe,
          next,
          shape,
          def.corFx,
        );
        _blast(canvas, next, ticks);
      default:
        break;
    }
  }

  /// A ball (a rocket, with smoke) arcing from the hand to the panel in
  /// front of [_foe], then the blast there.
  void _lob(Canvas canvas, Offset hand, double age, Random shape) {
    final def = art.def;
    final landing = _cell(_foe);
    Offset at(double f) =>
        Offset.lerp(hand, landing, f)! -
        Offset(0, _lobHeight * 4 * f * (1 - f));
    if (age < _arrival) {
      final f = age / _arrival;
      if (def.fx == ChipFx.smoke) {
        for (var i = 1; i <= 3; i++) {
          final back = f - i * 0.1;
          if (back > 0) _puff(canvas, at(back), i / 4);
        }
      }
      // What the battle throws with this card, turned the same way.
      final lob = playerLob(def);
      final here = at(f);
      canvas
        ..save()
        ..translate(here.dx, here.dy)
        ..rotate(
          ProjectileLayer.lobTurn(
            lob,
            _battle(hand),
            _battle(landing),
            f,
            tumbles: sprites.tumbles(lob, chip: def),
            height: _lobHeight * 2,
          ),
        );
      _drawCentered(canvas, sprites.lobbed(lob, chip: def), Offset.zero);
      canvas.restore();
      return;
    }
    // Rocks, mines and the TNT are only laid there.
    final pattern = switch (def.effect) {
      GrenadeEffect(:final pattern) => pattern,
      ProjectileEffect(:final pattern) => pattern,
      _ => null,
    };
    if (pattern == null) return;
    final ticks = _ticks(age - _arrival);
    for (final cell in pattern) {
      _blast(canvas, _cell(_foe + cell), ticks);
    }
  }

  /// Smoke puffs behind a shot at [f] of its way from [from] to [to].
  void _smokeTrail(Canvas canvas, Offset from, Offset to, double f) {
    for (var i = 1; i <= 3; i++) {
      final back = f - i * 0.1;
      if (back > 0) _puff(canvas, Offset.lerp(from, to, back)!, i / 4);
    }
  }

  /// A gray puff [age] (0 to 1) into its life: it swells as it fades.
  void _puff(Canvas canvas, Offset at, double age) {
    _smoke.color = Pico.lightGray.withValues(alpha: 1 - age);
    final size = (2 + 3 * age).roundToDouble();
    canvas.drawRect(
      Rect.fromCenter(center: at, width: size, height: size),
      _smoke,
    );
  }

  /// Down the row from the hand in the card's color, like the battle's:
  /// swells in, flickers, thins out. A row strike's goes through.
  void _beam(Canvas canvas, Offset hand, double age, ChipEffect effect) {
    final end = effect is RowStrikeEffect ? _end : _cell(_foe).dx;
    final swell = min(1.0, min(age, 1 - age) * 6 + 0.2);
    final flicker = (t * 40).floor().isEven ? 0.5 : 0.0;
    final (outer, middle, inner) = ChipFxLayer.beamColors[art.def.tint]!;
    // The battle's half heights, in art pixels.
    for (final (i, (paint, half)) in [
      (outer, 4.0),
      (middle, 2.5),
      (inner, 1.0),
    ].indexed) {
      final h = (half + (i < 2 ? flicker : 0)) * swell;
      canvas
        ..drawCircle(hand + Offset(3, 0), h, paint)
        ..drawCircle(Offset(end, hand.dy), h, paint)
        ..drawRect(
          Rect.fromLTRB(hand.dx + 3, hand.dy - h, end, hand.dy + h),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_ShowcasePainter old) => old.t != t || old.art != art;
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
      ('Tempo', run.playTime),
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
