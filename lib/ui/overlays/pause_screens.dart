import 'package:flutter/material.dart';

import '../../domain/chips/battle_chip.dart';
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
          const SizedBox(height: 8),
          for (final (i, (label, action)) in [
            ('Continuar', game.closeMenus),
            ('Ver deck', game.showDeck),
            ('Manual', game.openManualOverRun),
            ('Configurações', game.openSettings),
          ].indexed) ...[
            FilledButton(
              autofocus: i == 0,
              onPressed: withTap(action),
              child: Text(label),
            ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 4),
          FilledButton(
            onPressed: withTap(
              () => showDialog<void>(
                context: context,
                barrierColor: Pico.black.withValues(alpha: 0.6),
                builder: (_) => _AbandonDialog(game: game),
              ),
            ),
            child: Text(
              'Abandonar run',
              style: GbText.body.copyWith(color: Pico.coral),
            ),
          ),
        ],
      ),
    ),
  );
}

/// "Abandonar run?": the run ends with its report; focus on "Voltar".
class _AbandonDialog extends StatelessWidget {
  const _AbandonDialog({required this.game});

  final StarCopGame game;

  @override
  Widget build(BuildContext context) => VirtualScreen(
    size: wideScreen,
    child: Center(
      child: Container(
        width: 180,
        decoration: const ShapeDecoration(
          color: Pico.midnight,
          shape: BeveledRectangleBorder(
            side: BorderSide(color: Pico.coral),
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Pico.coral,
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 1),
                child: Text(
                  'ABANDONAR RUN?',
                  style: GbText.body.copyWith(color: Pico.midnight),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(4),
                child: Text(
                  'A run termina aqui, como uma derrota.',
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
                      onPressed: withTap(() => Navigator.of(context).pop()),
                      child: const Text('Voltar'),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: withTap(() {
                        Navigator.of(context).pop();
                        game.abandonRun();
                      }),
                      child: Text(
                        'Abandonar',
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
    return Scanlines(
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
/// In battle, tabs split it into the draw pile, the hand and the discard
/// pile (the draw pile grouped, so its order stays hidden). A tap anywhere
/// but the tabs closes it.
class DeckOverlay extends StatefulWidget {
  const DeckOverlay({super.key, required this.game});

  final StarCopGame game;

  @override
  State<DeckOverlay> createState() => _DeckOverlayState();
}

enum _DeckTab {
  draw('Compra'),
  hand('Mão'),
  discard('Descarte'),
  all('Deck');

  const _DeckTab(this.label);

  final String label;
}

class _DeckOverlayState extends State<DeckOverlay> {
  _DeckTab _tab = _DeckTab.draw;

  StarCopGame get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final deck = game.battleWorld?.battle.deck;
    List<ChipCard> cards(_DeckTab tab) => switch (tab) {
      _DeckTab.draw => deck!.drawPile,
      _DeckTab.hand => deck!.hand,
      _DeckTab.discard => deck!.discardPile,
      _DeckTab.all => game.run.deck,
    };
    final tab = deck == null ? _DeckTab.all : _tab;
    final shown = cards(tab);
    return GestureDetector(
      onTap: withTap(game.closeMenus),
      child: ColoredBox(
        color: Pico.darkBlue.withValues(alpha: 0.95),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              if (deck != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final t in _DeckTab.values)
                      GestureDetector(
                        onTap: withTap(() => setState(() => _tab = t)),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: buttonPadding,
                          decoration: BoxDecoration(
                            color: t == tab ? Pico.blue : Pico.midnight,
                            border: Border.all(color: petTitleBar),
                          ),
                          child: Text(
                            '${t.label} ${cards(t).length}',
                            style: GbText.body.copyWith(
                              color: t == tab ? Pico.midnight : Pico.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 4),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhuma carta aqui · toque para fechar',
                          style: GbText.small.copyWith(color: Pico.lightGray),
                        ),
                      )
                    : ChipPicker(
                        title: deck == null
                            ? 'Deck (${shown.length}) · toque para fechar'
                            : 'Toque fora das abas para fechar',
                        cards: shown,
                        sprites: game.sprites,
                        grouped: true,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
