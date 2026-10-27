"""Generates the game's chiptune sound effects and placeholder music.

Standard library only. Run from the repo root:

    python tools/gen_audio.py

Writes 22 kHz mono 16-bit WAVs to assets/audio/sfx/ and assets/audio/music/.
The file names must match lib/game/audio.dart (Sfx and Music).
Sounds are built sfxr-style: one oscillator with a pitch slide, vibrato,
arpeggio and an attack/sustain/decay envelope, several layers summed.
"""

import math
import os
import random
import struct
import wave

RATE = 22050
ROOT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')


# ------------------------------------------------------------------ synth

def osc(wave_, phase, duty, noise_state):
    """One sample of [wave_] at [phase] (0..1)."""
    if wave_ == 'square':
        return 1.0 if phase < duty else -1.0
    if wave_ == 'saw':
        return 2.0 * phase - 1.0
    if wave_ == 'tri':
        return 4.0 * phase - 1.0 if phase < 0.5 else 3.0 - 4.0 * phase
    if wave_ == 'sine':
        return math.sin(2 * math.pi * phase)
    if wave_ == 'noise':
        return noise_state[0]
    raise ValueError(wave_)


def tone(wave_='square', freq=440.0, slide=0.0, duty=0.5, duty_slide=0.0,
         attack=0.0, sustain=0.05, decay=0.1, punch=0.0, vib=(0.0, 0.0),
         arp=(), vol=1.0, delay=0.0, min_freq=30.0, seed=1):
    """sfxr-like voice.

    slide: octaves per second. vib: (depth in semitones, Hz).
    arp: ((time, semitones), ...) pitch jumps from the start.
    punch: extra volume at the start of the sustain, fading out.
    """
    rnd = random.Random(seed)
    length = attack + sustain + decay
    n = int((delay + length) * RATE)
    out = [0.0] * n
    phase = 0.0
    noise_state = [rnd.uniform(-1, 1)]
    start = int(delay * RATE)
    for i in range(start, n):
        t = (i - start) / RATE
        semis = 0.0
        for at, s in arp:
            if t >= at:
                semis = s
        f = freq * 2 ** (slide * t + semis / 12)
        if vib[0]:
            f *= 2 ** (vib[0] * math.sin(2 * math.pi * vib[1] * t) / 12)
        f = max(f, min_freq)
        prev = phase
        phase = (phase + f / RATE) % 1.0
        if wave_ == 'noise' and phase < prev:
            noise_state[0] = rnd.uniform(-1, 1)
        if t < attack:
            env = t / attack
        elif t < attack + sustain:
            env = 1.0 + punch * (1 - (t - attack) / sustain)
        else:
            env = max(0.0, 1 - (t - attack - sustain) / decay) if decay else 0
        d = min(0.95, max(0.05, duty + duty_slide * t))
        out[i] = osc(wave_, phase, d, noise_state) * env * vol
    return out


def mix(*layers):
    n = max(len(layer) for layer in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def seq(*parts):
    """Concatenates [parts] one after another."""
    out = []
    for part in parts:
        out.extend(part)
    return out


def write(path, samples, peak=0.9):
    top = max(1e-9, max(abs(s) for s in samples))
    gain = peak / top if top > peak else 1.0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(
            struct.pack('<h', int(max(-1, min(1, s * gain)) * 32767))
            for s in samples))


def note(name):
    """'C#5' -> Hz."""
    names = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
    semi = names[name[0]]
    rest = name[1:]
    if rest.startswith('#'):
        semi += 1
        rest = rest[1:]
    elif rest.startswith('b'):
        semi -= 1
        rest = rest[1:]
    midi = 12 * (int(rest) + 1) + semi
    return 440.0 * 2 ** ((midi - 69) / 12)


# -------------------------------------------------------------------- sfx

def arp_notes(names, step, wave_='square', duty=0.5, decay=0.05, vol=0.5,
              vib=(0.0, 0.0)):
    return seq(*[
        tone(wave_, note(n), duty=duty, sustain=step, decay=decay, vol=vol,
             vib=vib)[:int(step * RATE)] if i < len(names) - 1 else
        tone(wave_, note(n), duty=duty, sustain=step, decay=decay * 4,
             vol=vol, vib=vib)
        for i, n in enumerate(names)
    ])


SFX = {
    # Battle: the player's cards.
    'shot': lambda: mix(
        tone('square', 1100, slide=-5, duty=0.5, sustain=0.02, decay=0.09,
             punch=0.6, vol=0.5),
        tone('noise', 4000, sustain=0.0, decay=0.04, vol=0.25)),
    'shot_fire': lambda: mix(
        tone('noise', 1800, slide=-3, sustain=0.05, decay=0.2, punch=0.5,
             vol=0.6),
        tone('saw', 300, slide=-2, sustain=0.03, decay=0.12, vol=0.35)),
    'shot_aqua': lambda: mix(
        tone('sine', 300, slide=5, sustain=0.06, decay=0.08, vol=0.7),
        tone('tri', 600, slide=4, sustain=0.03, decay=0.06, vol=0.3,
             delay=0.05)),
    'shot_elec': lambda: mix(
        tone('square', 1400, duty=0.125, vib=(9, 45), sustain=0.08,
             decay=0.1, vol=0.45),
        tone('noise', 6000, sustain=0.04, decay=0.08, vol=0.25)),
    'shot_wood': lambda: mix(
        tone('tri', 260, slide=-2, sustain=0.04, decay=0.1, punch=0.8,
             vol=0.8),
        tone('noise', 2500, sustain=0.0, decay=0.03, vol=0.3)),
    'melee': lambda: mix(
        tone('noise', 5000, slide=-3, attack=0.02, sustain=0.03, decay=0.12,
             vol=0.6),
        tone('saw', 700, slide=-4, sustain=0.02, decay=0.08, vol=0.25)),
    'toss': lambda: tone('square', 320, slide=2.5, duty=0.25, sustain=0.1,
                         decay=0.06, vol=0.45),
    'support': lambda: arp_notes(['C5', 'E5', 'G5', 'C6'], 0.045,
                                 duty=0.25, vol=0.4),
    'heal': lambda: arp_notes(['C5', 'E5', 'G5', 'C6', 'E6'], 0.07,
                              wave_='tri', vol=0.6, vib=(0.3, 7)),
    'fusion': lambda: seq(
        tone('saw', 180, slide=3, duty=0.5, sustain=0.35, decay=0.0,
             vol=0.35, vib=(0.5, 14)),
        mix(tone('square', note('C6'), duty=0.25, sustain=0.05, decay=0.3,
                 vol=0.4),
            tone('square', note('G6'), duty=0.5, sustain=0.05, decay=0.3,
                 vol=0.25))),
    'chain2': lambda: arp_notes(['E6', 'G6'], 0.04, duty=0.25, vol=0.35),
    'chain3': lambda: arp_notes(['E6', 'G6', 'B6', 'E7'], 0.04, duty=0.25,
                                vol=0.35),
    'explosion': lambda: mix(
        tone('noise', 900, slide=-2.5, sustain=0.05, decay=0.35, punch=0.8,
             vol=0.8),
        tone('square', 90, slide=-1.5, sustain=0.03, decay=0.15, vol=0.3)),
    'slash': lambda: tone('noise', 7000, slide=-4, attack=0.01, sustain=0.02,
                          decay=0.1, vol=0.6),
    # Battle: hits and outcomes.
    'hit_enemy': lambda: mix(
        tone('noise', 2000, sustain=0.01, decay=0.06, punch=1, vol=0.5),
        tone('square', 300, slide=-4, duty=0.5, sustain=0.01, decay=0.06,
             vol=0.35)),
    'hit_player': lambda: mix(
        tone('square', 200, slide=-2.5, duty=0.5, sustain=0.06, decay=0.18,
             punch=0.5, vol=0.5),
        tone('noise', 1200, slide=-1, sustain=0.04, decay=0.12, vol=0.45)),
    'block': lambda: mix(
        tone('square', 1300, duty=0.5, sustain=0.01, decay=0.12, vol=0.35),
        tone('square', 1950, duty=0.25, sustain=0.01, decay=0.09, vol=0.25)),
    'stun': lambda: tone('square', 1200, slide=-1.5, duty=0.25,
                         vib=(3, 12), sustain=0.2, decay=0.1, vol=0.35),
    'enemy_death': lambda: mix(
        tone('noise', 1200, slide=-2, sustain=0.1, decay=0.45, punch=0.6,
             vol=0.6),
        arp_notes(['G5', 'D5', 'G4', 'D4'], 0.05, duty=0.5, vol=0.3)),
    'enemy_shot': lambda: tone('square', 700, slide=-3, duty=0.25,
                               sustain=0.03, decay=0.08, vol=0.35),
    'telegraph': lambda: seq(
        tone('square', 1760, duty=0.5, sustain=0.035, decay=0.0, vol=0.25),
        [0.0] * int(0.035 * RATE),
        tone('square', 1760, duty=0.5, sustain=0.035, decay=0.01, vol=0.25)),
    'new_hand': lambda: mix(
        tone('noise', 6000, sustain=0.0, decay=0.03, vol=0.2),
        tone('noise', 6000, sustain=0.0, decay=0.03, vol=0.2, delay=0.05),
        arp_notes(['G5', 'D6'], 0.06, wave_='tri', vol=0.6)),
    'win': lambda: arp_notes(['C5', 'E5', 'G5', 'C6', 'G5', 'C6', 'E6'],
                             0.1, duty=0.25, decay=0.08, vol=0.45),
    'lose': lambda: arp_notes(['G4', 'F#4', 'F4', 'E4'], 0.28, duty=0.5,
                              decay=0.15, vol=0.45, vib=(0.4, 6)),
    # UI.
    'tap': lambda: tone('square', 1200, duty=0.25, sustain=0.015,
                        decay=0.02, vol=0.25),
    'confirm': lambda: arp_notes(['A5', 'E6'], 0.05, duty=0.25, vol=0.35),
    'cancel': lambda: arp_notes(['E5', 'A4'], 0.05, duty=0.25, vol=0.35),
    'buy': lambda: arp_notes(['B5', 'E6'], 0.06, duty=0.5, decay=0.08,
                             vol=0.35),
    'reward': lambda: arp_notes(['C6', 'E6', 'G6', 'C7'], 0.05, duty=0.125,
                                vol=0.35),
    'deck': lambda: mix(*[
        tone('noise', 5000, sustain=0.0, decay=0.025, vol=0.35,
             delay=0.04 * i, seed=i + 1) for i in range(4)]),
    'pause': lambda: arp_notes(['E6', 'B5', 'E6'], 0.05, duty=0.5, vol=0.3),
    'node': lambda: tone('square', 520, slide=4, duty=0.25, sustain=0.06,
                         decay=0.05, vol=0.35),
    'upgrade': lambda: mix(
        tone('saw', 300, slide=3, sustain=0.2, decay=0.05, vol=0.25),
        arp_notes(['C6', 'G6', 'C7'], 0.08, duty=0.125, vol=0.3)),
}


# ------------------------------------------------------------------ music

CHORDS = {
    'Em': ['E', 'G', 'B'], 'C': ['C', 'E', 'G'], 'D': ['D', 'F#', 'A'],
    'B': ['B', 'D#', 'F#'], 'Dm': ['D', 'F', 'A'], 'Bb': ['Bb', 'D', 'F'],
    'A': ['A', 'C#', 'E'], 'Am': ['A', 'C', 'E'], 'F': ['F', 'A', 'C'],
    'G': ['G', 'B', 'D'],
}


def voice(wave_, freq, length, duty=0.5, vol=0.3, decay=0.0, vib=(0, 0)):
    """A note held for [length] s with a short release."""
    rel = min(0.02, length / 4)
    s = tone(wave_, freq, duty=duty, attack=0.004,
             sustain=max(0.0, length - rel - 0.004), decay=rel, vol=vol,
             vib=vib)
    if decay:
        for i in range(len(s)):
            s[i] *= max(0.0, 1 - i / RATE / decay)
    return s


def drum(kind):
    if kind == 'k':
        return tone('square', 150, slide=-6, duty=0.5, sustain=0.02,
                    decay=0.08, vol=0.5)
    if kind == 's':
        return mix(tone('noise', 3000, sustain=0.01, decay=0.12, vol=0.35),
                   tone('tri', 220, slide=-3, sustain=0.01, decay=0.05,
                        vol=0.3))
    return tone('noise', 9000, sustain=0.0, decay=0.025, vol=0.12)


def song(bpm, bars, chords, lead, lead_wave='square', lead_duty=0.25,
         lead_vol=0.22, bass='eighths', drums=('k...s...k...s...',
                                              '..h...h...h...h.'),
         arp=False):
    """bars: count; chords: one per bar; lead: 16 tokens per bar, a note
    name, '.' (hold) or '-' (rest)."""
    step = 60 / bpm / 4
    total = int(bars * 16 * step * RATE)
    out = [0.0] * total

    def put(samples, at):
        i0 = int(at * RATE)
        for i, v in enumerate(samples):
            if i0 + i < total:
                out[i0 + i] += v

    # Lead: a note lasts through its following holds.
    tokens = ' '.join(lead).split()
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        j = i + 1
        while j < len(tokens) and tokens[j] == '.':
            j += 1
        if tok not in '.-':
            put(voice(lead_wave, note(tok), (j - i) * step, duty=lead_duty,
                      vol=lead_vol, vib=(0.15, 6)), i * step)
        i = j

    for bar, chord in enumerate(chords):
        base = bar * 16 * step
        tones = CHORDS[chord]
        root = note(tones[0] + '2')
        if bass == 'eighths':
            for k in range(8):
                f = root * (2 if k % 2 else 1)
                put(voice('tri', f, step * 2, vol=0.45), base + k * 2 * step)
        elif bass == 'sixteenths':
            for k in range(16):
                f = root * (2 if k % 4 == 2 else 1)
                put(voice('tri', f, step, vol=0.45), base + k * step)
        else:  # half notes
            for k in range(2):
                put(voice('tri', root, step * 8, vol=0.45),
                    base + k * 8 * step)
        if arp:
            names = [t + '4' for t in tones] + [tones[0] + '5']
            for k in range(16):
                put(voice('square', note(names[k % 4]), step, duty=0.125,
                          vol=0.07, decay=step), base + k * step)
        for pattern in drums:
            for k, c in enumerate(pattern):
                if c != '.':
                    put(drum(c), base + k * step)
    return out


MUSIC = {
    'map': lambda: song(
        96, 8, ['Am', 'F', 'C', 'G'] * 2,
        ['A4 . . . C5 . . . E5 . . . D5 . C5 .',
         'A4 . . . F4 . . . A4 . . . C5 . . .',
         'G4 . . . C5 . . . E5 . . . G5 . E5 .',
         'D5 . . . B4 . . . G4 . . . - . . .',
         'E5 . . . A5 . . . G5 . E5 . C5 . . .',
         'F5 . . . E5 . . . C5 . . . A4 . . .',
         'C5 . . . E5 . . . G5 . . . E5 . D5 .',
         'B4 . . . D5 . . . G4 . . . - . . .'],
        lead_wave='tri', lead_vol=0.35, bass='halves',
        drums=('k.......k.......', '....h.......h...'), arp=True),
    'battle': lambda: song(
        140, 8, ['Em', 'C', 'D', 'B'] * 2,
        ['E5 . . B4 . . E5 . G5 . F#5 . E5 . D5 .',
         'E5 . . C5 . . E5 . G5 . A5 . G5 . E5 .',
         'F#5 . . D5 . . F#5 . A5 . B5 . A5 . F#5 .',
         'D#5 . . B4 . . D#5 . F#5 . . . - . . .',
         'E5 . . B4 . . E5 . G5 . F#5 . E5 . D5 .',
         'E5 . . C5 . . E5 . G5 . A5 . G5 . E5 .',
         'F#5 . . D5 . . F#5 . A5 . B5 . A5 . F#5 .',
         'F#5 . G5 . A5 . B5 . . . D#5 . F#5 . B5 .'],
        drums=('k.....k.k.......', '..h...h...h...h.', '....s.......s...')),
    'boss': lambda: song(
        150, 8, ['Dm', 'Dm', 'Bb', 'A'] * 2,
        ['D5 . D5 . A4 . D5 . F5 . E5 . D5 . C#5 .',
         'D5 . . . A5 . . . G5 . F5 . E5 . F5 .',
         'D5 . Bb4 . F5 . D5 . Bb5 . A5 . G5 . F5 .',
         'E5 . . . C#5 . . . A4 . C#5 . E5 . G5 .',
         'D5 . D5 . A4 . D5 . F5 . E5 . D5 . C#5 .',
         'D5 . . . A5 . . . G5 . F5 . E5 . F5 .',
         'D5 . Bb4 . F5 . D5 . Bb5 . A5 . G5 . F5 .',
         'A5 . . . G5 . F5 . E5 . C#5 . A4 . . .'],
        lead_duty=0.5, lead_vol=0.2, bass='sixteenths',
        drums=('k..k..k.k..k..k.', '....s.......s..s', 'h.h.h.h.h.h.h.h.')),
    'shop': lambda: song(
        112, 8, ['C', 'Am', 'F', 'G'] * 2,
        ['E5 . G5 . C6 . G5 . E5 . G5 . C6 . . .',
         'E5 . A5 . C6 . A5 . E5 . A5 . C6 . . .',
         'F5 . A5 . C6 . A5 . D6 . C6 . A5 . F5 .',
         'G5 . B5 . D6 . B5 . G5 . . . - . . .',
         'E5 . G5 . C6 . G5 . E5 . G5 . C6 . . .',
         'E5 . A5 . C6 . A5 . E5 . A5 . C6 . . .',
         'F5 . A5 . C6 . A5 . D6 . C6 . A5 . F5 .',
         'G5 . A5 . B5 . D6 . C6 . . . - . . .'],
        lead_duty=0.125, lead_vol=0.2,
        drums=('k.......k.......', '....s.......s...', '..h...h...h...h.')),
}


def main():
    for name, make in SFX.items():
        write(os.path.join(ROOT, 'sfx', name + '.wav'), make())
    for name, make in MUSIC.items():
        write(os.path.join(ROOT, 'music', name + '.wav'), make(), peak=0.7)
    print(f'{len(SFX)} sfx, {len(MUSIC)} music tracks')


if __name__ == '__main__':
    main()
