import 'package:flutter/material.dart';

import '../../domain/battle/bestiary.dart';
import '../../domain/battle/enemies.dart';
import '../../domain/chips/battle_chip.dart';
import '../../domain/chips/chip_library.dart';
import '../../domain/run/relics.dart';
import '../../game/audio.dart';
import '../../game/bestiary_progress.dart';
import '../../game/star_cop_game.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/card_showcase.dart';
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

enum _Tab { cards, relics, enemies }

class _CompendiumOverlayState extends State<CompendiumOverlay> {
  _Tab _tabShown = _Tab.cards;

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

  /// Enemies tab: the one whose entry is shown.
  FoeEntry? _foe;

  StarCopGame get game => widget.game;

  void _set(VoidCallback change) {
    GameAudio.instance.play(Sfx.tap);
    setState(change);
  }

  @override
  Widget build(BuildContext context) => Scanlines(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Column(
        children: [
          Row(
            children: [
              _tab(
                'Cartas',
                _tabShown == _Tab.cards,
                () => _tabShown = _Tab.cards,
              ),
              const SizedBox(width: 4),
              _tab(
                'Relíquias',
                _tabShown == _Tab.relics,
                () => _tabShown = _Tab.relics,
              ),
              const SizedBox(width: 4),
              _tab(
                'Inimigos',
                _tabShown == _Tab.enemies,
                () => _tabShown = _Tab.enemies,
              ),
              const Spacer(),
              TextButton(
                autofocus: true,
                onPressed: withTap(game.backToMenu),
                child: const Text('Voltar'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: switch (_tabShown) {
              _Tab.cards => _cards(),
              _Tab.relics => _relics(),
              _Tab.enemies => _enemies(),
            },
          ),
        ],
      ),
    ),
  );

  /// A tab or filter: [selected] ones are filled.
  Widget _tab(
    String label,
    bool selected,
    VoidCallback onTap, {
    Color color = Pico.darkBlue,
  }) => GestureDetector(
    onTap: () => _set(onTap),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? Pico.blue : Pico.midnight,
        border: Border.all(
          color: selected ? Pico.white : Pico.lavender,
          width: selected ? 2 : 1,
        ),
      ),
      child: Text(label, style: GbText.small.copyWith(color: selected ? Pico.darkBlue : Pico.white,)),
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
                      color: Pico.white,//familyColor(family),
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
            child: CardPreview(
              def: def,
              sprites: game.sprites,
              onClose: () => _set(() => _zoomed = null),
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
      'Evento',
      'Só dadas por eventos: não caem nem são vendidas.',
      Relics.events,
      null,
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

  // --------------------------------------------------------------- enemies

  static Color _tierColor(FoeTier tier) => switch (tier) {
    FoeTier.common => Pico.white,
    FoeTier.elite => Pico.orange,
    FoeTier.boss => Pico.red,
  };

  static String _kindText(EnemyKind kind) => switch (kind) {
    EnemyKind.machine => 'Projétil faz metade; Energia, o dobro.',
    EnemyKind.organic => 'Projétil faz +50%; Energia, metade.',
    EnemyKind.ethereal =>
      'Projétil e Corpo-a-corpo o atravessam, e Explosivo faz metade, '
          'exceto enquanto ataca.',
  };

  /// [entry]'s sprite fitted in a [size] square; a dark silhouette until
  /// it is unlocked.
  Widget _foeSprite(FoeEntry entry, double size, {required bool unlocked}) {
    final sprite = game.sprites.enemy(entry.def);
    final longest = sprite.src.width > sprite.src.height
        ? sprite.src.width
        : sprite.src.height;
    final art = SheetSprite(sprite: sprite, scale: size / longest);
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: unlocked
            ? art
            : ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Pico.darkGray,
                  BlendMode.srcIn,
                ),
                child: art,
              ),
      ),
    );
  }

  Widget _enemies() {
    final progress = BestiaryProgress.instance;
    final known = Bestiary.all.where(progress.unlocked).length;
    final foe = _foe;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Registrados: $known/${Bestiary.all.length}',
                style: GbText.small.copyWith(color: Pico.lightGray),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final act in const [1, 2, 3]) ...[
                        Text(
                          'Missão $act',
                          style: GbText.body.copyWith(color: Pico.yellow),
                        ),
                        for (final entry in Bestiary.all)
                          if (entry.act == act) _foeRow(entry, entry == foe),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 120,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Pico.black,
            border: Border.all(color: Pico.lightGray, width: 0.5),
          ),
          child: foe == null
              ? Text(
                  'Toque num inimigo para ver sua ficha. Enfrente um inimigo '
                  '5 vezes (chefes: 1 vez) para registrá-lo.',
                  style: GbText.small.copyWith(color: Pico.darkGray),
                )
              : SingleChildScrollView(child: _foeSheet(foe)),
        ),
      ],
    );
  }

  /// One line of the list: sprite, name (or ??? while locked) and, while
  /// locked, the fights still needed.
  Widget _foeRow(FoeEntry entry, bool selected) {
    final progress = BestiaryProgress.instance;
    final unlocked = progress.unlocked(entry);
    final needed = entry.tier.unlockFights;
    return GestureDetector(
      onTap: () => _set(() => _foe = entry),
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: selected ? Pico.darkBlue : Colors.transparent,
          border: Border.all(
            color: selected ? Pico.yellow : Colors.transparent,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            _foeSprite(entry, 14, unlocked: unlocked),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                unlocked ? entry.def.name : '???',
                overflow: TextOverflow.ellipsis,
                style: GbText.small.copyWith(
                  color: unlocked ? _tierColor(entry.tier) : Pico.darkGray,
                ),
              ),
            ),
            if (unlocked)
              Text(
                entry.tier.label,
                style: GbText.small.copyWith(color: _tierColor(entry.tier)),
              )
            else
              Text(
                '${progress.fights(entry)}/$needed',
                style: GbText.small.copyWith(color: Pico.darkGray),
              ),
          ],
        ),
      ),
    );
  }

  /// The right panel: [entry]'s stats and how it fights, or how far it is
  /// from being unlocked.
  Widget _foeSheet(FoeEntry entry) {
    final progress = BestiaryProgress.instance;
    final fights = progress.fights(entry);
    final needed = entry.tier.unlockFights;
    if (!progress.unlocked(entry)) {
      return Column(
        children: [
          _foeSprite(entry, 48, unlocked: false),
          const SizedBox(height: 4),
          Text('???', style: GbText.body.copyWith(color: Pico.darkGray)),
          const SizedBox(height: 4),
          Text(
            needed == 1
                ? 'Enfrente este chefe para registrá-lo.'
                : 'Enfrente este inimigo $needed vezes para registrá-lo.',
            textAlign: TextAlign.center,
            style: GbText.small,
          ),
          const SizedBox(height: 2),
          Text(
            'Batalhas: $fights/$needed',
            style: GbText.small.copyWith(color: Pico.lightGray),
          ),
        ],
      );
    }
    final def = entry.def;
    final traits = [
      if (def.footprint.length > 1) 'Ocupa ${def.footprint.length} painéis.',
      if (!def.pushable) 'Não pode ser empurrado.',
      if (def.frontShield) 'Escudo frontal: bloqueia tiros de frente.',
      if (def.prism) 'Reflete tiros fora de linha com o parceiro.',
      if (def.lavaImmune) 'Imune a Lava.',
    ];
    Widget stat(String label, String value, {Color color = Pico.white}) =>
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label ',
                style: const TextStyle(color: Pico.lightGray),
              ),
              TextSpan(text: value, style: TextStyle(color: color)),
            ],
          ),
          style: GbText.small,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _foeSprite(entry, 48, unlocked: true)),
        const SizedBox(height: 4),
        Center(
          child: Text(
            def.name,
            textAlign: TextAlign.center,
            style: GbText.body.copyWith(color: _tierColor(entry.tier)),
          ),
        ),
        Center(
          child: Text(
            'Missão ${entry.act} · ${entry.tier.label}',
            style: GbText.small.copyWith(color: Pico.lightGray),
          ),
        ),
        const SizedBox(height: 4),
        stat('HP', '${def.hp}', color: Pico.green),
        stat('Tipo', def.kind.label),
        stat('Elemento', def.element.label),
        if (def.shotDamage > 0) stat('Tiro', '${def.shotDamage} de dano'),
        const SizedBox(height: 2),
        Text(
          _kindText(def.kind),
          style: GbText.small.copyWith(color: Pico.lavender),
        ),
        for (final trait in traits)
          Text('- $trait', style: GbText.small.copyWith(color: Pico.peach)),
        const SizedBox(height: 4),
        Text(entry.description, style: GbText.small),
        const SizedBox(height: 4),
        Text(
          'Enfrentado $fights ${fights == 1 ? 'vez' : 'vezes'}.',
          style: GbText.small.copyWith(color: Pico.darkGray),
        ),
      ],
    );
  }
}
