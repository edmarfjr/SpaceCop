import 'package:flutter/material.dart';

import '../../game/audio.dart';
import '../../game/settings.dart';
import '../../game/star_cop_game.dart';
import '../feedback.dart';
import '../theme.dart';
import '../widgets/chip_picker.dart';

/// Pause icon in battle: a button to resume (a stray tap doesn't) and one
/// to the settings.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Pico.black.withValues(alpha: 0.7),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('PAUSA', style: GbText.title),
          const SizedBox(height: 10),
          FilledButton(
            autofocus: true,
            onPressed: withTap(game.closeMenus),
            child: const Text('Continuar'),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: withTap(game.openSettings),
            child: const Text('Configurações'),
          ),
        ],
      ),
    ),
  );
}

/// From the menu or the pause: sound volumes, mute and the language.
class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  static const _volumeStep = 0.1;

  @override
  Widget build(BuildContext context) {
    final audio = GameAudio.instance;
    final settings = GameSettings.instance;
    return ColoredBox(
      color: Pico.darkBlue,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CONFIGURAÇÕES', style: GbText.title),
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
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  child: Text('Idioma', style: GbText.body),
                ),
                for (final language in GameLanguage.values)
                  _TextButton(
                    text: language.label,
                    selected: language == settings.language.value,
                    onTap: () {
                      menuTapFeedback();
                      setState(() => settings.setLanguage(language));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              autofocus: true,
              onPressed: withTap(widget.game.closeSettings),
              child: const Text('Voltar'),
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

/// Yellow text with some room around it to tap; gray when [selected] is
/// false (one option of a choice that isn't the current one).
class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.text,
    required this.onTap,
    this.selected = true,
  });

  final String text;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        text,
        style: GbText.title.copyWith(
          color: selected ? Pico.yellow : Pico.darkGray,
          fontSize: 14,
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
