import 'package:flutter/material.dart';

import '../../game/audio.dart';
import '../../game/star_cop_game.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/chip_picker.dart';

/// Pause icon in battle: the sound settings, and a button to resume (a
/// stray tap doesn't).
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay> {
  static const _volumeStep = 0.1;

  @override
  Widget build(BuildContext context) {
    final audio = GameAudio.instance;
    return ColoredBox(
      color: Pico.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('PAUSA', style: GbText.title),
            const SizedBox(height: 10),
            _VolumeRow(
              label: 'Música',
              volume: audio.musicVolume,
              onChange: (step) => setState(
                () => audio.setMusicVolume(
                  audio.musicVolume + step * _volumeStep,
                ),
              ),
            ),
            _VolumeRow(
              label: 'Efeitos',
              volume: audio.sfxVolume,
              onChange: (step) {
                setState(
                  () =>
                      audio.setSfxVolume(audio.sfxVolume + step * _volumeStep),
                );
                audio.play(Sfx.tap);
              },
            ),
            const SizedBox(height: 4),
            _TextButton(
              text: audio.muted ? 'Som: desligado' : 'Som: ligado',
              onTap: () => setState(audio.toggleMute),
            ),
            const SizedBox(height: 10),
            FilledButton(
              autofocus: true,
              onPressed: withTap(widget.game.closeMenus),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Label  -  70%  +".
class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.label,
    required this.volume,
    required this.onChange,
  });

  final String label;
  final double volume;

  /// Called with -1 or +1.
  final void Function(int step) onChange;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 48, child: Text(label, style: GbText.body)),
      _TextButton(text: '-', onTap: () => onChange(-1)),
      SizedBox(
        width: 32,
        child: Text(
          '${(volume * 100).round()}%',
          style: GbText.body,
          textAlign: TextAlign.center,
        ),
      ),
      _TextButton(text: '+', onTap: () => onChange(1)),
    ],
  );
}

/// Yellow text with some room around it to tap.
class _TextButton extends StatelessWidget {
  const _TextButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(text, style: GbText.body.copyWith(color: Pico.yellow)),
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
    onTap: withTap(game.closeMenus),
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
