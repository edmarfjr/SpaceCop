import 'package:flutter/material.dart';

import '../../game/star_cop_game.dart';
import '../theme.dart';
import '../widgets/chip_picker.dart';

/// Pause icon in battle. A tap anywhere resumes.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: game.closeMenus,
    child: ColoredBox(
      color: Pico.black.withValues(alpha: 0.7),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('PAUSA', style: GbText.title),
            SizedBox(height: 4),
            Text('Toque para continuar', style: GbText.small),
          ],
        ),
      ),
    ),
  );
}

/// Deck icon in battle, or "Deck" on the map: the run's deck, read-only.
/// A tap anywhere closes it.
class DeckOverlay extends StatelessWidget {
  const DeckOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: game.closeMenus,
    child: ColoredBox(
      color: Pico.darkBlue.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ChipPicker(
          title: 'Deck (${game.run.deck.length}) · toque para fechar',
          cards: game.run.deck,
          sprites: game.sprites,
          grouped: true,
        ),
      ),
    ),
  );
}
