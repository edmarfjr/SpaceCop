import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart' show Sprite;
import 'package:flutter/material.dart';

import '../../domain/map/run_map.dart';
import '../../domain/run/relics.dart';
import '../../domain/run/run_state.dart';
import '../../game/star_cop_game.dart';
import '../../game/sprites.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/sheet_sprite.dart';
import 'battle_hud.dart' show HudIconButton;

/// Slay the Spire style map, floor 0 at the bottom and the boss on top.
/// Only nodes in [RunState.availableNodes] are tappable (and focusable, for
/// the keyboard); the leftmost one starts focused.
///
/// Spans the width of the wide screen and is taller than it: only some
/// floors show at once, the rest is reached by dragging. It opens scrolled
/// to the floor the player can enter.
///
/// Left/right cycle through the available nodes, wrapping around, instead
/// of Flutter's geometric focus search, which skips nodes on the map.
class MapOverlay extends StatefulWidget {
  const MapOverlay({super.key, required this.game});

  final StarCopGame game;

  static const _nodeSize = 20.0;

  /// Vertical distance between floors, in virtual px.
  static const _floorStep = 28.0;

  @override
  State<MapOverlay> createState() => _MapOverlayState();
}

class _MapOverlayState extends State<MapOverlay> {
  late final List<MapNode> _available = List.of(widget.game.run.availableNodes)
    ..sort((a, b) => a.x.compareTo(b.x));
  late final List<FocusNode> _focus = [
    for (final node in _available) FocusNode(debugLabel: 'map ${node.x}'),
  ];

  StarCopGame get game => widget.game;

  /// Relic whose icon is being held down: its description shows meanwhile.
  RelicDef? _held;

  /// Node being held down: what it is shows meanwhile.
  MapNode? _heldNode;

  /// The node legend, toggled by its "?" button.
  bool _legend = false;

  ScrollController? _scroll;

  @override
  void dispose() {
    for (final node in _focus) {
      node.dispose();
    }
    _scroll?.dispose();
    super.dispose();
  }

  void _cycle(TraversalDirection direction) {
    if (_focus.isEmpty) return;
    final step = switch (direction) {
      TraversalDirection.right || TraversalDirection.down => 1,
      TraversalDirection.left || TraversalDirection.up => -1,
    };
    final current = _focus.indexWhere((f) => f.hasFocus);
    final next = current < 0 ? 0 : (current + step) % _focus.length;
    _focus[next].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final run = game.run;
    final available = _available;

    return ColoredBox(
      color: Pico.black,
      child: Stack(
        children: [
          _body(run, available),
          Positioned(
            top: 2,
            right: 2,
            child: Row(
              children: [
                _LegendButton(
                  open: _legend,
                  onTap: () => setState(() => _legend = !_legend),
                ),
                const SizedBox(width: 4),
                HudIconButton(icon: game.sprites.pauseIcon, onTap: game.pause),
              ],
            ),
          ),
          if (_legend)
            Positioned(
              top: 24,
              right: 2,
              child: _Legend(sprites: game.sprites),
            ),
          if (_heldNode case final node?)
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Center(
                child: _NodeInfo(
                  type: node.type!,
                  sprite: node.type == NodeType.boss
                      ? game.sprites.bossNode(run.boss)
                      : game.sprites.node(node.type!),
                  bossName: run.boss.name,
                ),
              ),
            ),
          if (_held case final relic?)
            Positioned(
              top: 18,
              left: 0,
              right: 0,
              child: Center(
                child: _RelicInfo(relic: relic, sprites: game.sprites),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(RunState run, List<MapNode> available) => Column(
    children: [
      Padding(
        // Room on the right for the legend and pause buttons.
        padding: const EdgeInsets.fromLTRB(2, 2, 52, 2),
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: petWindow,
          child: Row(
            children: [
              Container(
                color: Pico.orange,
                padding: const EdgeInsets.fromLTRB(3, 1, 3, 0),
                child: Text(
                  'ATO ${run.act}',
                  style: GbText.small.copyWith(color: Pico.midnight),
                ),
              ),
              const SizedBox(width: 6),
              Text('HP', style: GbText.small.copyWith(color: Pico.lightGray)),
              const SizedBox(width: 2),
              SizedBox(
                width: 40,
                child: LinearProgressIndicator(
                  value: run.hp / run.maxHp,
                  minHeight: 5,
                  color: run.hp * 4 < run.maxHp ? Pico.red : Pico.green,
                  backgroundColor: Pico.chocolate,
                ),
              ),
              const SizedBox(width: 3),
              Text('${run.hp}/${run.maxHp}', style: GbText.small),
              const SizedBox(width: 4),
              TextButton(
                onPressed: withTap(game.showDeck),
                child: Text('Deck ${run.deck.length}', style: GbText.small),
              ),
              const SizedBox(width: 4),
              SheetSprite(sprite: game.sprites.credits, scale: 0.75),
              Text(' ${run.credits}', style: GbText.small),
              // Many relics scroll sideways instead of overflowing.
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final relic in run.relics)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPressStart: (_) =>
                              setState(() => _held = relic),
                          onLongPressEnd: (_) => setState(() => _held = null),
                          onLongPressCancel: () => setState(() => _held = null),
                          // The padding makes the icon easier to hold.
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(3, 2, 1, 2),
                            // Bigger art shrinks to the usual 16 px.
                            child: SizedBox.square(
                              dimension: 16,
                              child: FittedBox(
                                child: SheetSprite(
                                  sprite: game.sprites.relic(relic),
                                  scale: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) {
            const height = MapOverlay._floorStep * (RunMap.floorCount + 2);
            Offset center(MapNode n) => Offset(
              box.maxWidth * (n.x + 1) / (RunMap.columns + 1),
              height - MapOverlay._floorStep * (n.floor + 1),
            );
            // The floor to enter sits in the lower part of the view.
            final floor = available.firstOrNull?.floor ?? 0;
            _scroll ??= ScrollController(
              initialScrollOffset:
                  (height -
                          MapOverlay._floorStep * (floor + 1) -
                          box.maxHeight * 0.75)
                      .clamp(0, max(0, height - box.maxHeight)),
            );

            final nodes = [...run.map.usedNodes, run.map.boss];
            return Actions(
              actions: {
                DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
                  onInvoke: (intent) {
                    _cycle(intent.direction);
                    return null;
                  },
                ),
              },
              child: ScrollConfiguration(
                // Mouse drags scroll too (desktop and web).
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: PointerDeviceKind.values.toSet(),
                  scrollbars: false,
                ),
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: SizedBox(
                    height: height,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _EdgePainter(
                              run.map,
                              center,
                              current: run.current,
                              available: available,
                            ),
                          ),
                        ),
                        for (final node in nodes)
                          Positioned(
                            left: center(node).dx - MapOverlay._nodeSize / 2,
                            top: center(node).dy - MapOverlay._nodeSize / 2,
                            child: _NodeButton(
                              onHold: (held) => setState(
                                () => _heldNode = held ? node : null,
                              ),
                              node: node,
                              sprite: node.type == NodeType.boss
                                  ? game.sprites.bossNode(run.boss)
                                  : game.sprites.node(node.type!),
                              isCurrent: node == run.current,
                              focusNode: available.contains(node)
                                  ? _focus[available.indexOf(node)]
                                  : null,
                              autofocus: node == available.firstOrNull,
                              onTap: available.contains(node)
                                  ? () => game.selectNode(node)
                                  : null,
                            ),
                          ),
                        // "Você está aqui": the player beside her node.
                        if (run.current case final current?)
                          Positioned(
                            left: center(current).dx + MapOverlay._nodeSize / 2,
                            top: center(current).dy - 18,
                            child: IgnorePointer(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SheetSprite(
                                    sprite: game.sprites.playerIdle,
                                    scale: 1,
                                  ),
                                  Container(
                                    color: Pico.yellow,
                                    padding: const EdgeInsets.fromLTRB(
                                      2,
                                      1,
                                      2,
                                      0,
                                    ),
                                    child: Text(
                                      'VOCÊ',
                                      style: GbText.small.copyWith(
                                        color: Pico.midnight,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

/// Name and description of a held relic, over the top of the map.
class _RelicInfo extends StatelessWidget {
  const _RelicInfo({required this.relic, required this.sprites});

  final RelicDef relic;
  final GameSprites sprites;

  @override
  Widget build(BuildContext context) => Container(
    width: 200,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Pico.midnight,
      border: Border.all(color: Pico.yellow, width: focusBorder),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Row(
      children: [
        SheetSprite(sprite: sprites.relic(relic), scale: 2),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(relic.name, style: GbText.body.copyWith(color: Pico.yellow)),
              Text(relic.description, style: GbText.small),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NodeButton extends StatefulWidget {
  const _NodeButton({
    required this.node,
    required this.sprite,
    required this.isCurrent,
    required this.onHold,
    this.focusNode,
    this.autofocus = false,
    this.onTap,
  });

  final MapNode node;
  final Sprite sprite;
  final bool isCurrent;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onTap;

  /// Holding any node shows what it is: true when held, false on release.
  final ValueChanged<bool> onHold;

  @override
  State<_NodeButton> createState() => _NodeButtonState();
}

class _NodeButtonState extends State<_NodeButton>
    with SingleTickerProviderStateMixin {
  bool _focused = false;

  /// The border of the nodes the player can pick blinks yellow and white,
  /// so the next step stands out; the node itself stays fully lit. Built
  /// in [initState], not lazily: a lazy one first touched by [dispose]
  /// would look up the deactivated tree for its ticker.
  late final AnimationController _blink;

  /// Opacity of the nodes that can't be picked, except the current one.
  static const _idleOpacity = 0.45;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    if (widget.onTap != null) _blink.repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final active = onTap != null;
    Widget node(Color border) => Container(
      width: MapOverlay._nodeSize,
      height: MapOverlay._nodeSize,
      decoration: BoxDecoration(
        // Black behind the icon, so the grid doesn't cross it.
        color: Pico.black,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: border, width: 1),
      ),
      alignment: Alignment.center,
      child: SheetSprite(sprite: widget.sprite, scale: 2),
    );
    Widget holdable(Widget child) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => widget.onHold(true),
      onLongPressEnd: (_) => widget.onHold(false),
      onLongPressCancel: () => widget.onHold(false),
      child: child,
    );
    if (!active) {
      if (widget.isCurrent) return holdable(node(Pico.white));
      return holdable(
        Opacity(opacity: _idleOpacity, child: node(Colors.transparent)),
      );
    }
    final button = GestureDetector(
      onTap: withTap(onTap),
      onLongPressStart: (_) => widget.onHold(true),
      onLongPressEnd: (_) => widget.onHold(false),
      onLongPressCancel: () => widget.onHold(false),
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, _) =>
            node(Color.lerp(Pico.yellow, Pico.white, _blink.value)!),
      ),
    );
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onTap();
            return null;
          },
        ),
      },
      child: button,
    );
  }
}

/// Paths that stop [_inset] short of each node's center: solid
/// [Pico.blue] where the player has been, solid [Pico.yellow] from her
/// node to the ones she can pick, dashed white elsewhere.
class _EdgePainter extends CustomPainter {
  _EdgePainter(
    this.map,
    this.center, {
    required this.current,
    required this.available,
  });

  static const _inset = 10.0;
  static const _dash = 4.0;
  static const _gap = 3.0;

  final RunMap map;
  final Offset Function(MapNode) center;
  final MapNode? current;
  final List<MapNode> available;

  @override
  void paint(Canvas canvas, Size size) {
    Paint pen(Color color) => Paint()
      ..color = color
      ..strokeWidth = 1
      ..isAntiAlias = false;
    final dashed = pen(Pico.white);
    final walked = pen(Pico.blue);
    final next = pen(Pico.yellow);
    for (final node in map.usedNodes) {
      for (final to in map.nextOf(node)) {
        final from = center(node);
        final delta = center(to) - from;
        final length = delta.distance;
        if (length <= 2 * _inset) continue;
        final dir = delta / length;
        final solid = node.visited && to.visited
            ? walked
            : node == current && available.contains(to)
            ? next
            : null;
        if (solid != null) {
          canvas.drawLine(
            from + dir * _inset,
            from + dir * (length - _inset),
            solid,
          );
          continue;
        }
        for (var d = _inset; d < length - _inset; d += _dash + _gap) {
          final end = min(d + _dash, length - _inset);
          canvas.drawLine(from + dir * d, from + dir * end, dashed);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_EdgePainter oldDelegate) =>
      oldDelegate.map != map || oldDelegate.current != current;
}

/// Battle Network's jack-in, over a battle that just started: 12 bands in
/// two colors cover the screen with the word in the middle, then withdraw
/// to alternating sides, in 8 steps with no easing, like pixel art. The
/// battle waits for the player meanwhile. Skipped when the system asks
/// for less motion.
class JackInOverlay extends StatefulWidget {
  const JackInOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<JackInOverlay> createState() => _JackInOverlayState();
}

class _JackInOverlayState extends State<JackInOverlay>
    with SingleTickerProviderStateMixin {
  static const _bands = 12;
  static const _steps = 8;

  /// The word holds for the first part, then the bands withdraw.
  static const _hold = 0.4;

  late final AnimationController _play =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.game.endJackIn();
      });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.game.endJackIn(),
      );
    } else if (!_play.isAnimating && !_play.isCompleted) {
      _play.forward();
    }
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (light, dark, word) = widget.game.jackIn;
    // Absorbs taps and swipes until the battle shows.
    return AbsorbPointer(
      child: AnimatedBuilder(
        animation: _play,
        builder: (context, _) {
          final t = _play.value;
          // Covered while holding; then 1 → 0 in whole steps.
          final cover = t < _hold
              ? 1.0
              : 1 - ((t - _hold) / (1 - _hold) * _steps).ceil() / _steps;
          return LayoutBuilder(
            builder: (context, box) {
              final band = box.maxHeight / _bands;
              return Stack(
                children: [
                  for (var i = 0; i < _bands; i++)
                    Positioned(
                      top: i * band,
                      height: band,
                      width: box.maxWidth * cover,
                      // Even bands withdraw to the left, odd ones right.
                      left: i.isEven ? 0 : box.maxWidth * (1 - cover),
                      child: ColoredBox(color: i.isEven ? light : dark),
                    ),
                  if (t < _hold)
                    Center(
                      child: Text(
                        word,
                        style: GbText.title.copyWith(
                          color: Pico.midnight,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// The map's background: a [mapGrid] line every [mapGridStep] px, like the
/// battle's data grid.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = mapGrid
      ..isAntiAlias = false;
    for (var x = 0.0; x < size.width; x += mapGridStep) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += mapGridStep) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// Name and what a node holds, for the legend and a held node.
(String, String) _describeNode(NodeType type, String bossName) =>
    switch (type) {
      NodeType.battle => ('Batalha', 'Capangas. Dá Créditos e uma carta.'),
      NodeType.elite => (
        'Elite',
        'Inimigos fortes. Dá uma relíquia e cartas melhores.',
      ),
      NodeType.event => ('Evento', 'Uma escolha, com ganho e custo.'),
      NodeType.rest => ('Descanso', 'Recupera HP ou melhora uma carta.'),
      NodeType.shop => ('Loja', 'Cartas, relíquias e remoção de carta.'),
      NodeType.boss => ('Chefe', '$bossName. Fim do ato.'),
    };

/// Same box as [HudIconButton], with a "?" that opens the legend.
class _LegendButton extends StatelessWidget {
  const _LegendButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: withTap(onTap),
    child: Container(
      width: 22,
      height: 20,
      decoration: BoxDecoration(
        color: open ? Pico.blue : Pico.darkBlue,
        border: Border.all(color: Pico.lightGray, width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.center,
      child: Text(
        '?',
        style: GbText.title.copyWith(color: open ? Pico.midnight : Pico.white),
      ),
    ),
  );
}

/// What each node icon is, under the "?" button.
class _Legend extends StatelessWidget {
  const _Legend({required this.sprites});

  final GameSprites sprites;

  @override
  Widget build(BuildContext context) => Container(
    width: 84,
    decoration: petWindow,
    clipBehavior: Clip.hardEdge,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: petTitleBar,
          padding: const EdgeInsets.fromLTRB(4, 1, 4, 0),
          child: const Text('LEGENDA', style: GbText.small),
        ),
        for (final type in [
          NodeType.battle,
          NodeType.elite,
          NodeType.event,
          NodeType.rest,
          NodeType.shop,
        ])
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Row(
              children: [
                SheetSprite(sprite: sprites.node(type), scale: 1),
                const SizedBox(width: 4),
                Text(_describeNode(type, '').$1, style: GbText.small),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            'Segure um nó para ver o que ele dá.',
            style: GbText.small.copyWith(color: Pico.lightGray),
          ),
        ),
      ],
    ),
  );
}

/// A held node: its icon, name and what it gives.
class _NodeInfo extends StatelessWidget {
  const _NodeInfo({
    required this.type,
    required this.sprite,
    required this.bossName,
  });

  final NodeType type;
  final Sprite sprite;
  final String bossName;

  @override
  Widget build(BuildContext context) {
    final (name, text) = _describeNode(type, bossName);
    return Container(
      width: 200,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Pico.midnight,
        border: Border.all(color: Pico.yellow, width: focusBorder),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          SheetSprite(sprite: sprite, scale: 2),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: GbText.body.copyWith(color: Pico.yellow)),
                Text(text, style: GbText.small),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
