import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/battle/enemies.dart';
import '../../domain/battle/panels.dart';
import '../../domain/chips/battle_chip.dart';
import '../../domain/chips/chip_library.dart';
import '../../domain/element.dart' as el;
import '../../domain/grid.dart';
import '../../domain/map/run_map.dart';
import '../../domain/run/events.dart';
import '../../domain/run/relics.dart';
import '../../game/sprites.dart';
import '../../game/star_cop_game.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/chip_card_view.dart';
import '../widgets/sheet_sprite.dart';

/// One page of the manual, drawn from the game's sprites.
typedef _PageBuilder = Widget Function(GameSprites sprites);

/// A chapter of the manual: its title (shown over each of its pages and in
/// the index) and its pages.
class _Chapter {
  const _Chapter(this.title, this.pages);

  final String title;
  final List<_PageBuilder> pages;
}

/// Manual, opened from the title screen: an old game booklet, one page at
/// a time. The first page is the index; arrows, a sideways swipe or the
/// left/right keys turn the page, Esc goes back to the menu.
class ManualOverlay extends StatefulWidget {
  const ManualOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<ManualOverlay> createState() => _ManualOverlayState();
}

class _ManualOverlayState extends State<ManualOverlay> {
  late final List<_Chapter> _chapters = _book();

  /// Every page in order, with its chapter.
  late final List<(_Chapter, _PageBuilder)> _pages = [
    for (final chapter in _chapters)
      for (final page in chapter.pages) (chapter, page),
  ];

  int _page = 0;

  StarCopGame get game => widget.game;

  void _turn(int step) {
    final next = (_page + step).clamp(0, _pages.length - 1);
    if (next == _page) return;
    menuTapFeedback();
    setState(() => _page = next);
  }

  void _open(_Chapter chapter) =>
      setState(() => _page = _pages.indexWhere((p) => p.$1 == chapter));

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _turn(-1);
      case LogicalKeyboardKey.arrowRight:
        _turn(1);
      case LogicalKeyboardKey.escape:
        game.backToMenu();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final (chapter, page) = _pages[_page];
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: Pico.darkBlue,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    chapter.title,
                    style: GbText.title.copyWith(color: Pico.yellow),
                  ),
                  const Spacer(),
                  Text(
                    '${_page + 1}/${_pages.length}',
                    style: GbText.small.copyWith(color: Pico.lightGray),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    autofocus: true,
                    onPressed: withTap(game.backToMenu),
                    child: const Text('Voltar'),
                  ),
                ],
              ),
              Container(height: 1, color: Pico.red),
              const SizedBox(height: 4),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v.abs() > 100) _turn(v < 0 ? 1 : -1);
                  },
                  child: _page == 0 ? _index() : page(game.sprites),
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _page == 0 ? null : () => _turn(-1),
                    child: const Text('< Anterior'),
                  ),
                  const Spacer(),
                  if (_page != 0)
                    TextButton(
                      onPressed: withTap(() => setState(() => _page = 0)),
                      child: const Text('Índice'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _page == _pages.length - 1
                        ? null
                        : () => _turn(1),
                    child: const Text('Próxima >'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _index() {
    final chapters = _chapters.skip(1).toList();
    final half = (chapters.length + 1) ~/ 2;
    Widget column(Iterable<_Chapter> list) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final chapter in list)
            TextButton(
              onPressed: withTap(() => _open(chapter)),
              child: Text(
                '${_pages.indexWhere((p) => p.$1 == chapter) + 1}  '
                '${chapter.title}',
              ),
            ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [column(chapters.take(half)), column(chapters.skip(half))],
    );
  }
}

// ------------------------------------------------------------------ layout

/// Text with *starred* stretches in yellow, the booklet's bold.
Widget _text(String text, {TextStyle style = GbText.body}) {
  final parts = text.split('*');
  return Text.rich(
    TextSpan(
      children: [
        for (final (i, part) in parts.indexed)
          TextSpan(
            text: part,
            style: i.isOdd ? style.copyWith(color: Pico.yellow) : null,
          ),
      ],
    ),
    style: style,
  );
}

/// Paragraphs, one under the other.
Widget _lines(List<String> lines) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (final line in lines) ...[_text(line), const SizedBox(height: 4)],
  ],
);

/// The usual page: an illustration on the left, the text on the right.
Widget _spread(Widget art, List<String> lines, {double artWidth = 110}) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    SizedBox(
      width: artWidth,
      child: Center(child: art),
    ),
    const SizedBox(width: 8),
    Expanded(child: _lines(lines)),
  ],
);

/// An icon with its explanation, in a list.
Widget _item(Widget icon, String text, {double iconWidth = 20}) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: iconWidth,
        child: Center(child: icon),
      ),
      const SizedBox(width: 4),
      Expanded(child: _text(text)),
    ],
  ),
);

/// A colored label: card family, rarity or enemy type.
Widget _tag(String label, Color color) =>
    Text(label, style: GbText.small.copyWith(color: color));

/// [items] in a grid of [columns], [rows] high, filling the page.
Widget _grid(List<Widget> items, {int columns = 2}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (var i = 0; i < items.length; i += columns)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = i; j < i + columns; j++)
              Expanded(
                child: j < items.length ? items[j] : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
  ],
);

/// [list] cut into pages of [size].
List<List<T>> _chunks<T>(List<T> list, int size) => [
  for (var i = 0; i < list.length; i += size)
    list.sublist(i, (i + size).clamp(0, list.length)),
];

/// A small battlefield: the grid with a few panels changed, the player and
/// two enemies, like the real one at 1× art scale.
class _MiniField extends StatelessWidget {
  const _MiniField(this.sprites);

  final GameSprites sprites;

  static const _top = 16.0;
  static final _states = {
    GridPos(1, 1): PanelState.grass,
    GridPos(2, 0): PanelState.ice,
    GridPos(0, 2): PanelState.cracked,
    GridPos(3, 2): PanelState.lava,
  };

  @override
  Widget build(BuildContext context) {
    final units = {
      1: (1, sprites.playerIdle),
      0: (4, sprites.enemy(Enemies.gruntGun)),
      2: (5, sprites.enemy(Enemies.gruntDuck)),
    };
    return SizedBox(
      width: 120,
      height: _top + 2 * 14 + 20,
      child: Stack(
        children: [
          for (var y = 0; y < gridRows; y++) ...[
            for (var x = 0; x < gridColumns; x++) ...[
              Positioned(
                left: x * 20,
                top: _top + y * 14,
                child: SheetSprite(
                  sprite: sprites.panel(
                    _states[GridPos(x, y)] ?? PanelState.normal,
                  ),
                  scale: 1,
                ),
              ),
              Positioned(
                left: x * 20,
                top: _top + y * 14,
                child: SheetSprite(
                  sprite: sprites.panelFrame(GridPos(x, y).homeSide),
                  scale: 1,
                ),
              ),
            ],
            if (units[y] case (final x, final sprite))
              Positioned(
                left: x * 20 + 10 - sprite.src.width / 2,
                top: _top + y * 14 + 8 - sprite.src.height,
                child: SheetSprite(sprite: sprite, scale: 1),
              ),
          ],
        ],
      ),
    );
  }
}

/// A panel with the player's frame on top, as it looks in battle.
Widget _panel(GameSprites s, PanelState state) => Stack(
  children: [
    SheetSprite(sprite: s.panel(state), scale: 1),
    SheetSprite(sprite: s.panelFrame(Team.player), scale: 1),
  ],
);

Widget _cardEntry(GameSprites s, ChipDef def) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ChipCardView(def: def, sprites: s, width: 36, focusable: false),
    const SizedBox(width: 4),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(def.name, style: GbText.body),
          Row(
            children: [
              _tag(def.family.label, familyColor(def.family)),
              const SizedBox(width: 4),
              _tag(def.rarity.label, rarityColor(def.rarity)),
            ],
          ),
          const SizedBox(height: 2),
          Text(def.description, style: GbText.small),
        ],
      ),
    ),
  ],
);

Widget _relicEntry(GameSprites s, RelicDef relic, {bool boss = false}) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    SheetSprite(sprite: s.relic(relic), scale: 1),
    const SizedBox(width: 4),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(relic.name, style: GbText.body)),
              const SizedBox(width: 4),
              boss
                  ? _tag('Chefe', Pico.red)
                  : _tag(relic.rarity.label, rarityColor(relic.rarity)),
            ],
          ),
          Text(relic.description, style: GbText.small),
        ],
      ),
    ),
  ],
);

Widget _enemyEntry(GameSprites s, (EnemyDef, String) entry) {
  final (def, text) = entry;
  final sprite = s.enemy(def);
  final scale = (40 / sprite.src.height).clamp(0.0, 1.0);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SheetSprite(sprite: sprite, scale: scale),
        ),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(def.name, style: GbText.body),
            _tag('HP ${def.hp} · ${def.kind.label}', Pico.lightGray),
            const SizedBox(height: 2),
            Text(text, style: GbText.small),
          ],
        ),
      ),
    ],
  );
}

Widget _eventEntry(GameSprites s, EventDef event) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (s.event(event) case final sprite?)
      SheetSprite(sprite: sprite, scale: 0.5),
    const SizedBox(width: 4),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.title, style: GbText.body),
          Text(event.text, style: GbText.small),
        ],
      ),
    ),
  ],
);

// ------------------------------------------------------------------ content

/// Each mission's enemies, in groups, with how they fight.
const _foes = [
  (
    'Missão 1 · Comuns',
    [
      (Enemies.gruntGun, 'Alinha com você e atira (10).'),
      (Enemies.gruntDuck, 'No fundo, rajadas de 3 tiros de 5.'),
      (Enemies.gruntMelee, 'Avança, corta e volta. Racha os painéis.'),
      (Enemies.gruntGrenade, 'Granada no seu painel, que vira Lava.'),
      (Enemies.gruntArtillery, 'Mísseis no seu painel. O aviso é longo.'),
      (Enemies.sentry, 'Sobe do chão, atira na linha e afunda.'),
    ],
  ),
  (
    'Missão 1 · Elites',
    [
      (Enemies.brute, 'Escudo frontal. Investe pela sua linha.'),
      (Enemies.digger, 'Cava, surge e fura seu painel.'),
      (Enemies.prism, 'Em dupla. Reflete tiros fora de linha.'),
      (Enemies.lavaGuard, 'Espalha Lava e varre sua linha com fogo.'),
    ],
  ),
  (
    'Missão 1 · Chefes',
    [
      (Enemies.tank, '2 painéis. Rajadas, morteiros e investidas.'),
      (
        Enemies.colonel,
        'Com 2 Guarda-costas. Rajada, tiro de precisão e molotov.',
      ),
      (
        Enemies.argos,
        'A IA da base. Com o núcleo aberto, Energia causa o triplo.',
      ),
    ],
  ),
  (
    'Missão 2 · Comuns',
    [
      (Enemies.etWarrior, 'Golpe de alcance 2. Foge depois.'),
      (Enemies.etGunner, 'Atira (10) e foge.'),
      (Enemies.etTrap, 'Enterrado: só Explosivo o atinge.'),
      (Enemies.etShaman, 'Deixa Esferas que soltam morteiros.'),
      (Enemies.etShieldBearer, 'Protege um aliado com o escudo.'),
      (Enemies.etHealer, 'Cura o aliado mais ferido. Atordoe-o.'),
      (Enemies.sentinel, 'Varre suas fileiras com laser.'),
      (Enemies.scarab, 'Em trio. Rasteja e explode.'),
    ],
  ),
  (
    'Missão 2 · Elites',
    [
      (Enemies.etRider, '2 painéis. Só investe pela sua linha.'),
      (Enemies.ruinGolem, 'Racha sua coluna. Acerte o punho.'),
      (Enemies.priestess, 'Teleporta e cria cópias frágeis.'),
      (Enemies.portal, 'Solta guerreiros. O anel bloqueia tiros.'),
    ],
  ),
  (
    'Missão 2 · Chefes',
    [
      (Enemies.tribeKing, 'Invulnerável enquanto houver Totens.'),
      (Enemies.highPriest, 'Runas no seu lado: pise nelas para apagar.'),
      (Enemies.serpent, 'Mergulha e surge sob você. Quebre os segmentos.'),
    ],
  ),
  (
    'Missão 3 · Comuns',
    [
      (Enemies.shadowGun, 'Alinha com você e atira (10).'),
      (Enemies.shadowFly, 'Teleporta e lança uma bola.'),
      (Enemies.shadowJumper, 'Sólida só durante o salto.'),
      (Enemies.shadowNest, 'Choca Carrapatos que explodem.'),
    ],
  ),
  (
    'Missão 3 · Elites e chefe',
    [
      (Enemies.predator, 'Some e corta sua coluna inteira.'),
      (Enemies.stalker, 'Investe pela sua linha, rachando o chão.'),
      (Enemies.voidEye, 'Ao se partir, solta Hemisférios e fica invulnerável.'),
    ],
  ),
];

const _events = [
  Events.armory,
  Events.informant,
  Events.securityTerminal,
  Events.vault,
  Events.shootingRange,
  Events.undercoverAgent,
  Events.clinic,
  Events.hangar,
];

List<_Chapter> _book() => [
  _Chapter('Índice', [(_) => const SizedBox.shrink()]),
  _Chapter('A missão', [
    (s) => _spread(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetSprite(sprite: s.playerIdle),
          SheetSprite(sprite: s.playerAttack),
        ],
      ),
      [
        'Você é uma *policial espacial*. Sem parceiro e sem reforços, '
            'vai desmontar uma organização criminosa.',
        'Cada partida tem *3 missões*. Em cada uma você sobe um mapa até '
            'o chefe no topo.',
        'Você luta com um *deck de cartas* que cresce a cada vitória. '
            'Se o HP chegar a zero, a operação recomeça do início.',
      ],
    ),
  ]),
  _Chapter('Controles', [
    (s) => _spread(SheetSprite(sprite: s.playerIdle, scale: 3), [
      '*Deslize o dedo* em qualquer lugar: a policial anda uma casa.',
      '*Continue arrastando* sem soltar para andar mais.',
      '*Toque numa carta* para usá-la.',
      'Dá para segurar uma carta com um dedo e deslizar com outro.',
    ]),
    (s) => _spread(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetSprite(sprite: s.deckIcon),
          const SizedBox(height: 6),
          SheetSprite(sprite: s.pauseIcon),
        ],
      ),
      [
        'Teclado: *setas* ou *WASD* movem. *X* ou *K* usa a carta. '
            '*Z* ou *J* passa para a próxima.',
        'Os ícones no topo mostram o *deck* e *pausam*. '
            'Toque em qualquer lugar para fechar.',
        'A cada mão nova a batalha *congela* até você agir: planeje.',
      ],
    ),
  ]),
  _Chapter('A batalha', [
    (s) => _spread(_MiniField(s), artWidth: 130, [
      'Grade de *6×3*. As 3 colunas da esquerda (moldura vermelha) '
          'são suas; você só anda por elas.',
      'A policial atira e golpeia sempre para a direita.',
      'Painéis em vermelho e o *sinal* piscando sobre o inimigo avisam '
          'onde e quando o ataque vai cair.',
    ]),
    (s) => _spread(
      ChipCardView(def: Chips.vShot, sprites: s, width: 56, focusable: false),
      [
        'A cada *10 s* o gauge enche: a mão vai para o descarte e você '
            'compra *5 cartas*.',
        'Cada mão traz *4 de Energia*. A carta custa o número azul; o '
            'vermelho é o dano. A Energia que sobra *não acumula*.',
        'Cartas de *uso único* saem do deck até o fim da luta.',
      ],
    ),
  ]),
  _Chapter('Elementos', [
    (s) => Column(
      children: [
        _item(
          SheetSprite(sprite: s.element(el.Element.fire)!),
          '*Fogo*: dobro em quem está na Grama, e a queima. '
          'Unidades de Fogo não se queimam na Lava.',
        ),
        _item(
          SheetSprite(sprite: s.element(el.Element.aqua)!),
          '*Aqua*: apaga a Lava. A Criogranada molha os alvos.',
        ),
        _item(
          SheetSprite(sprite: s.element(el.Element.elec)!),
          '*Elétrico*: dobro em alvo Molhado. No Gelo, atordoa 1 s.',
        ),
        _item(
          SheetSprite(sprite: s.element(el.Element.wood)!),
          '*Madeira*: +30% se usada de cima da Grama.',
        ),
      ],
    ),
  ]),
  _Chapter('Correntes', [
    (s) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _lines([
          'Cartas da *mesma família* com até *2 s* entre elas formam uma '
              'corrente: a 2ª causa *×1,25*, a 3ª *×1,5* e um status.',
        ]),
        for (final (family, status, name) in [
          (ChipFamily.projectile, Status.marked, 'Marcado'),
          (ChipFamily.explosive, Status.burning, 'Queimando'),
          (ChipFamily.energy, Status.stunned, 'Atordoado'),
          (ChipFamily.melee, Status.rooted, 'Enraizado'),
        ])
          _item(
            SheetSprite(sprite: s.status(status)),
            '${family.label}: a 3ª deixa o alvo *$name*.',
          ),
        _text(
          'Equipamento, Consumível e Tático não quebram a corrente.',
          style: GbText.small,
        ),
      ],
    ),
  ]),
  _Chapter('Inimigos e status', [
    (s) => _spread(SheetSprite(sprite: s.enemy(Enemies.tank)), [
      '*Máquina*: Projétil causa metade; Energia, o dobro.',
      '*Orgânico*: Explosivo causa ×1,5.',
      '*Etéreo*: Projétil e Corpo-a-corpo o atravessam, menos quando ele '
          'ataca ou por 2 s depois de um Explosivo.',
      'Escudos frontais só param *tiros retos* de frente. O Pulso EMP '
          'os derruba.',
    ]),
    (s) => Column(
      children: [
        for (final (status, text) in [
          (Status.burning, '*Queimando*: 3 de dano por segundo.'),
          (Status.wet, '*Molhado*: o próximo Elétrico causa o dobro.'),
          (Status.stunned, '*Atordoado*: não anda, não ataca.'),
          (Status.rooted, '*Enraizado*: não anda, mas ataca.'),
          (Status.marked, '*Marcado*: +5 de dano em cada acerto.'),
        ])
          _item(SheetSprite(sprite: s.status(status)), text),
      ],
    ),
  ]),
  _Chapter('Terreno', [
    (s) => _grid([
      for (final (state, text) in [
        (PanelState.cracked, '*Rachado*: quem sai dele abre um Buraco.'),
        (PanelState.hole, '*Buraco*: ninguém pisa. Tiros passam.'),
        (PanelState.ice, '*Gelo*: quem pisa desliza.'),
        (PanelState.grass, '*Grama*: cura 1 HP por segundo.'),
        (PanelState.lava, '*Lava*: 5 de dano por segundo.'),
        (PanelState.normal, 'Os painéis voltam ao normal com o tempo.'),
      ])
        _item(_panel(s, state), text, iconWidth: 20),
    ]),
    (s) => _spread(SheetSprite(sprite: s.obstacle(ObstacleKind.rock)), [
      'Bater em alguém ou na borda: *10* de dano e 0,5 s atordoado.',
      'Bater numa pedra: *30* de dano.',
      'Empurrado para um buraco: *20* de dano e 1 s atordoado.',
      'A *Barricada* bloqueia tiros inimigos, mas todos andam por ela.',
    ]),
  ]),
  _Chapter('O mapa', [
    (s) => _grid([
      for (final (type, text) in [
        (NodeType.battle, '*Combate*: 20 Créditos e uma carta.'),
        (NodeType.elite, '*Elite*: 40 Créditos e uma relíquia.'),
        (NodeType.event, '*Evento*: escolhas. Pode ter luta.'),
        (NodeType.rest, '*Fogueira*: descanse ou melhore.'),
        (NodeType.shop, '*Loja*: compre ou remova cartas.'),
        (NodeType.boss, '*Chefe*: escolha 1 entre 3 relíquias.'),
      ])
        _item(SheetSprite(sprite: s.node(type)), text, iconWidth: 32),
    ]),
    (s) => _spread(SheetSprite(sprite: s.node(NodeType.boss), scale: 3), [
      '16 andares. O primeiro é sempre combate; o último, uma fogueira '
          'antes do chefe. Arraste o mapa para ver tudo.',
      'Após cada vitória, escolha *1 entre 3 cartas* (ou nenhuma). '
          'Elites dão cartas melhores; o chefe, só raras.',
      'Vencido o chefe, você recupera *75%* do HP que faltava.',
    ]),
  ]),
  _Chapter('Fogueira e loja', [
    (s) => _spread(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChipCardView(
            def: Chips.cannon,
            sprites: s,
            width: 44,
            focusable: false,
          ),
          const SizedBox(width: 4),
          ChipCardView(
            def: Chips.upgradeOf(Chips.cannon)!,
            sprites: s,
            width: 44,
            focusable: false,
          ),
        ],
      ),
      [
        'Fogueira: *descanse* (30% do HP máximo) ou *melhore* uma carta, '
            'que ganha a versão "+".',
        'Loja: cartas por *40/65/100 C*, relíquias por *110/150/200 C* '
            '(comum/incomum/rara). Remover uma carta: *75 C*.',
      ],
    ),
  ]),
  _Chapter('Eventos', [
    for (final page in _chunks(_events, 4))
      (s) => _grid([for (final e in page) _eventEntry(s, e)]),
  ]),
  _Chapter('Cartas', [
    for (final page in _chunks(Chips.all, 4))
      (s) => _grid([for (final def in page) _cardEntry(s, def)]),
  ]),
  _Chapter('Relíquias', [
    for (final page in _chunks(Relics.all, 6))
      (s) => _grid([for (final relic in page) _relicEntry(s, relic)]),
    (s) => _grid([
      for (final relic in Relics.boss) _relicEntry(s, relic, boss: true),
    ]),
  ]),
  _Chapter('Inimigos', [
    for (final (group, foes) in _foes)
      for (final page in _chunks(foes, 4))
        (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group, style: GbText.body.copyWith(color: Pico.orange)),
            const SizedBox(height: 3),
            _grid([for (final foe in page) _enemyEntry(s, foe)]),
          ],
        ),
  ]),
  _Chapter('Dicas', [
    (s) => _spread(SheetSprite(sprite: s.playerAttack, scale: 3), [
      '*Saia da linha* quando o sinal piscar.',
      '*Gaste a Energia*: ela não passa para a próxima mão.',
      'Energia contra Máquinas, Explosivo contra Orgânicos e Etéreos.',
      '*Monte correntes* e use o chão: molhe antes de eletrocutar.',
      'Deck enxuto bate forte: remova cartas fracas na loja.',
    ]),
  ]),
];
