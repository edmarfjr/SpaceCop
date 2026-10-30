import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../domain/map/run_map.dart';
import '../../domain/run/relics.dart';
import '../../domain/run/run_state.dart';
import '../../game/star_cop_game.dart';
import '../../game/sprites.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/sheet_sprite.dart';

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
        padding: const EdgeInsets.all(2),
        child: 
        Container(
          decoration: BoxDecoration(
            color: Pico.darkBlue,
            //border: Border.all(color: Pico.yellow, width: 1),
            //borderRadius: BorderRadius.circular(1),
          ),
          child:Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Ato ${run.act} · HP ${run.hp}/${run.maxHp} · ',
              style: GbText.small,
            ),
            TextButton(
              onPressed: withTap(game.showDeck),
              child: Text('Deck ${run.deck.length}', style: GbText.small),
            ),
            const Text(' · ', style: GbText.small),
            SheetSprite(sprite: game.sprites.credits, scale: 1),
            Text(': ${run.credits}', style: GbText.small),
            // Many relics scroll sideways instead of overflowing.
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: 
                Row(
                  children: [
                    for (final relic in run.relics)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPressStart: (_) => setState(() => _held = relic),
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
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _EdgePainter(run.map, center),
                          ),
                        ),
                        for (final node in nodes)
                          Positioned(
                            left: center(node).dx - MapOverlay._nodeSize / 2,
                            top: center(node).dy - MapOverlay._nodeSize / 2,
                            child: _NodeButton(
                              node: node,
                              sprites: game.sprites,
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
    required this.sprites,
    required this.isCurrent,
    this.focusNode,
    this.autofocus = false,
    this.onTap,
  });

  final MapNode node;
  final GameSprites sprites;
  final bool isCurrent;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onTap;

  @override
  State<_NodeButton> createState() => _NodeButtonState();
}

class _NodeButtonState extends State<_NodeButton>
    with SingleTickerProviderStateMixin {
  bool _focused = false;

  /// Nodes the player can pick blink, so the next step stands out. Built
  /// in [initState], not lazily: a lazy one first touched by [dispose]
  /// would look up the deactivated tree for its ticker.
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      lowerBound: 0.3,
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
    final button = GestureDetector(
      onTap: withTap(onTap),
      child: Container(
        width: MapOverlay._nodeSize,
        height: MapOverlay._nodeSize,
        decoration: BoxDecoration(
          //color: widget.node.visited
          //    ? Pico.lightGray
          //    : Pico.darkGray,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active
                ? Pico.yellow
                : widget.isCurrent
                ? Pico.white
                : Colors.transparent,
            width: 1,//_focused ? focusBorder : 0.75,
          ),
        ),
        alignment: Alignment.center,
        child: SheetSprite(
          sprite: widget.sprites.node(widget.node.type!),
          scale: 2,
        ),
      ),
    );
    if (onTap == null) return button;
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
      child: FadeTransition(opacity: _blink, child: button),
    );
  }
}

/// Dashed paths that stop [_inset] short of each node's center.
class _EdgePainter extends CustomPainter {
  _EdgePainter(this.map, this.center);

  static const _inset = 10.0;
  static const _dash = 4.0;
  static const _gap = 3.0;

  final RunMap map;
  final Offset Function(MapNode) center;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Pico.lavender
      ..strokeWidth = 1;
    for (final node in map.usedNodes) {
      for (final next in map.nextOf(node)) {
        final from = center(node);
        final delta = center(next) - from;
        final length = delta.distance;
        if (length <= 2 * _inset) continue;
        final dir = delta / length;
        for (var d = _inset; d < length - _inset; d += _dash + _gap) {
          final end = min(d + _dash, length - _inset);
          canvas.drawLine(from + dir * d, from + dir * end, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_EdgePainter oldDelegate) => oldDelegate.map != map;
}
