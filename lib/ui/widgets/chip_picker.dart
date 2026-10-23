import 'package:flutter/material.dart';

import '../../domain/chips/battle_chip.dart';
import '../../game/sprites.dart';
import '../feedback.dart';
import '../theme.dart';
import 'chip_card_view.dart';

/// Lets the player pick one chip of the deck (remove, duplicate...).
/// Shared by the shop and the events. "Cancelar" (or Esc) calls [onCancel].
class ChipPicker extends StatelessWidget {
  const ChipPicker({
    super.key,
    required this.title,
    required this.cards,
    required this.sprites,
    this.onPick,
    this.onCancel,
    this.grouped = false,
  });

  final String title;
  final List<ChipCard> cards;
  final GameSprites sprites;

  /// Null shows the deck read-only.
  final ValueChanged<ChipCard>? onPick;
  final VoidCallback? onCancel;

  /// Groups equal chips into one bigger card with a count ("x4"). Picking
  /// a group picks its first copy.
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final pick = onPick;
    final cancel = onCancel;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: GbText.body),
        const SizedBox(height: 4),
        Flexible(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              alignment: WrapAlignment.center,
              children: grouped
                  ? [
                      for (final (i, MapEntry(key: def, value: count))
                          in _counts.entries.indexed)
                        _grouped(def, count, autofocus: i == 0),
                    ]
                  : [
                      for (var i = 0; i < cards.length; i++)
                        ChipCardView(
                          def: cards[i].def,
                          sprites: sprites,
                          width: 40,
                          autofocus: i == 0,
                          onTap: pick == null ? null : () => pick(cards[i]),
                        ),
                    ],
            ),
          ),
        ),
        if (cancel != null)
          TextButton(onPressed: withTap(cancel), child: const Text('Cancelar')),
      ],
    );
    if (cancel == null) return content;
    return Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            cancel();
            return null;
          },
        ),
      },
      child: content,
    );
  }

  /// Copies of each chip, in deck order.
  Map<ChipDef, int> get _counts {
    final counts = <ChipDef, int>{};
    for (final card in cards) {
      counts.update(card.def, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Widget _grouped(ChipDef def, int count, {bool autofocus = false}) {
    final pick = onPick;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChipCardView(
          def: def,
          sprites: sprites,
          width: 64,
          autofocus: autofocus,
          onTap: pick == null
              ? null
              : () => pick(cards.firstWhere((c) => c.def == def)),
        ),
        Text(
          'x$count',
          style: GbText.body.copyWith(
            color: Pico.yellow,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
