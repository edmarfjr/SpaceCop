import 'package:flutter/material.dart';

import '../../domain/chips/battle_chip.dart';
import '../../domain/chips/chip_library.dart';
import '../../domain/run/relics.dart';
import '../../game/audio.dart';
import '../../game/star_cop_game.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/chip_card_view.dart';
import '../widgets/sheet_sprite.dart';

/// How the card list is ordered, like Slay the Spire's compendium.
enum _Sort {
  rarity('Raridade'),
  type('Tipo'),
  cost('Custo'),
  name('A-Z');

  const _Sort(this.label);

  final String label;

  int compare(ChipDef a, ChipDef b) => switch (this) {
    _Sort.rarity => a.rarity.index.compareTo(b.rarity.index),
    _Sort.type => a.type.index.compareTo(b.type.index),
    _Sort.cost => a.cost.compareTo(b.cost),
    _Sort.name => 0,
  };
}

/// Compêndio, opened from the title screen: every card, by family and
/// sortable, and every relic, by rarity.
class CompendiumOverlay extends StatefulWidget {
  const CompendiumOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<CompendiumOverlay> createState() => _CompendiumOverlayState();
}

class _CompendiumOverlayState extends State<CompendiumOverlay> {
  bool _showRelics = false;

  /// Cards tab: the family shown (all if null), the order, and whether the
  /// "+" versions are shown instead.
  ChipFamily? _family;
  _Sort _sort = _Sort.rarity;
  bool _ascending = true;
  bool _upgraded = false;

  /// The card shown big over the list.
  ChipDef? _zoomed;

  /// Relics tab: the one whose text is shown.
  RelicDef? _relic;

  StarCopGame get game => widget.game;

  void _set(VoidCallback change) {
    GameAudio.instance.play(Sfx.tap);
    setState(change);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Pico.darkBlue,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Column(
        children: [
          Row(
            children: [
              _tab('Cartas', !_showRelics, () => _showRelics = false),
              const SizedBox(width: 4),
              _tab('Relíquias', _showRelics, () => _showRelics = true),
              const Spacer(),
              TextButton(
                autofocus: true,
                onPressed: withTap(game.backToMenu),
                child: const Text('Voltar'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(child: _showRelics ? _relics() : _cards()),
        ],
      ),
    ),
  );

  /// A tab or filter: [selected] ones are filled.
  Widget _tab(
    String label,
    bool selected,
    VoidCallback onTap, {
    Color color = Pico.white,
  }) => GestureDetector(
    onTap: () => _set(onTap),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? Pico.eggplant : Pico.midnight,
        border: Border.all(
          color: selected ? Pico.yellow : Pico.darkGray,
          width: selected ? 1 : 0.5,
        ),
      ),
      child: Text(label, style: GbText.small.copyWith(color: color)),
    ),
  );

  // ---------------------------------------------------------------- cards

  List<ChipDef> get _shownCards {
    final cards = [
      for (final def in Chips.all)
        if (_family == null || def.family == _family)
          _upgraded ? Chips.upgradeOf(def) ?? def : def,
    ];
    return cards..sort((a, b) {
      final order = _sort.compare(a, b);
      final byName = order != 0 ? order : a.name.compareTo(b.name);
      return _ascending ? byName : -byName;
    });
  }

  Widget _cards() {
    final cards = _shownCards;
    return Stack(
      children: [
        Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _tab('Todas', _family == null, () => _family = null),
                  for (final family in ChipFamily.values) ...[
                    const SizedBox(width: 3),
                    _tab(
                      family.label,
                      _family == family,
                      () => _family = family,
                      color: familyColor(family),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                for (final sort in _Sort.values) ...[
                  _tab(
                    _sort == sort
                        ? '${sort.label} ${_ascending ? '+' : '-'}'
                        : sort.label,
                    _sort == sort,
                    // Tapping the current order flips it.
                    () => _sort == sort
                        ? _ascending = !_ascending
                        : (_sort = sort, _ascending = true),
                  ),
                  const SizedBox(width: 3),
                ],
                const Spacer(),
                _tab(
                  '${_upgraded ? '[x]' : '[ ]'} Ver aprimoramento',
                  _upgraded,
                  () => _upgraded = !_upgraded,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final def in cards)
                      ChipCardView(
                        def: def,
                        sprites: game.sprites,
                        width: 44,
                        onTap: () => _set(() => _zoomed = def),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_zoomed case final def?)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _set(() => _zoomed = null),
              child: ColoredBox(
                color: Pico.black.withValues(alpha: 0.8),
                child: Center(
                  child: ChipCardView(
                    def: def,
                    sprites: game.sprites,
                    width: 96,
                    focusable: false,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- relics

  static final _sections = [
    (
      'Comum',
      'Relíquias fracas, fáceis de achar.',
      [
        for (final r in Relics.all)
          if (r.rarity == Rarity.common) r,
      ],
      Rarity.common,
    ),
    (
      'Incomum',
      'Mais fortes, aparecem menos que as comuns.',
      [
        for (final r in Relics.all)
          if (r.rarity == Rarity.uncommon) r,
      ],
      Rarity.uncommon,
    ),
    (
      'Rara',
      'Únicas e poderosas, raramente vistas.',
      [
        for (final r in Relics.all)
          if (r.rarity == Rarity.rare) r,
      ],
      Rarity.rare,
    ),
    (
      'Chefe',
      'Só nos espólios de um chefe: bônus forte com desvantagem.',
      Relics.boss,
      null,
    ),
  ];

  Widget _relics() {
    final relic = _relic;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (title, text, relics, rarity) in _sections) ...[
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$title: ',
                          style: GbText.body.copyWith(
                            color: rarity == null
                                ? Pico.red
                                : rarityColor(rarity),
                          ),
                        ),
                        TextSpan(text: text),
                      ],
                    ),
                    style: GbText.small,
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      for (final r in relics)
                        GestureDetector(
                          onTap: () => _set(() => _relic = r),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: r == relic
                                    ? Pico.yellow
                                    : Colors.transparent,
                              ),
                            ),
                            child: SheetSprite(
                              sprite: game.sprites.relic(r),
                              scale: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 112,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Pico.black,
            border: Border.all(color: Pico.lightGray, width: 0.5),
          ),
          child: relic == null
              ? Text(
                  'Toque numa relíquia para ver o que ela faz.',
                  style: GbText.small.copyWith(color: Pico.darkGray),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      SheetSprite(sprite: game.sprites.relic(relic), scale: 3),
                      const SizedBox(height: 4),
                      Text(
                        relic.name,
                        textAlign: TextAlign.center,
                        style: GbText.body.copyWith(
                          color: Relics.boss.contains(relic)
                              ? Pico.red
                              : rarityColor(relic.rarity),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(relic.description, style: GbText.small),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
