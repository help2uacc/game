#!/usr/bin/env python3
"""Generate music loops (PRD §11.5): simple chiptune melody + bass + light
percussion, seamless loops. Deterministic (fixed seeds).

Output: assets/audio/music/<name>.wav, 22.05 kHz, mono, 16-bit.
  menu_loop      calm, ~32 s
  battle_loop_a  upbeat, ~32 s
  battle_loop_b  upbeat, ~32 s
  battle_loop_c  upbeat, ~32 s
  results_jingle ~4 s (one-shot)
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from synth import lowpass_fast, normalize, note_freq, osc, write_wav  # noqa: E402

SR = 22050
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "music"

MAJOR = [0, 2, 4, 5, 7, 9, 11]


def voice(midi, dur, wave_type, duty=0.5, attack=0.01, release_frac=0.6, vib=0.0, seed=0):
    n = max(1, int(dur * SR))
    f = np.full(n, note_freq(midi))
    if vib:
        t = np.arange(n) / SR
        f *= 1.0 + vib * np.sin(2 * np.pi * 5.5 * t) * np.clip(t * 4, 0, 1)
    x = osc(wave_type, f, SR, duty, np.random.default_rng(seed))
    a = max(1, int(attack * SR))
    env = np.ones(n)
    env[:a] = np.linspace(0, 1, a)
    r = int(n * release_frac)
    if r > 0:
        env[n - r:] *= np.linspace(1, 0, r) ** 1.5
    return x * env


def drum(kind, seed):
    rng = np.random.default_rng(seed)
    if kind == "kick":
        n = int(0.18 * SR)
        t = np.arange(n) / SR
        f = 140 * np.exp(-t * 25) + 45
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 18)
        return x * 0.9
    if kind == "snare":
        n = int(0.14 * SR)
        t = np.arange(n) / SR
        x = rng.uniform(-1, 1, n) * np.exp(-t * 28) * 0.45
        x += np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.3
        return lowpass_fast(x, 3500, SR)
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    x = rng.uniform(-1, 1, n) * np.exp(-t * 80) * 0.18
    return x


def place(buf, x, start, gain=1.0):
    """Adds x into buf at sample `start`, wrapping around for seamless loops."""
    n = len(buf)
    s = start % n
    end = s + len(x)
    if end <= n:
        buf[s:end] += x * gain
    else:
        first = n - s
        buf[s:] += x[:first] * gain
        buf[:end - n] += x[first:] * gain


def scale_note(root, degree):
    octave, idx = divmod(degree, 7)
    return root + 12 * octave + MAJOR[idx]


def make_melody(rng, progression, bars, steps_per_bar, energetic):
    """Phrase-based melody: 4-bar phrase A, variation A', phrase B, A."""
    def phrase(seed_offset):
        r = np.random.default_rng(rng.integers(0, 1 << 30) + seed_offset)
        notes = []
        degree = 4 + int(r.integers(0, 3))
        for bar in range(4):
            chord_root = progression[bar % len(progression)]
            step = 0
            while step < steps_per_bar:
                length = int(r.choice([1, 2, 2, 3, 4] if energetic else [2, 2, 3, 4, 4]))
                length = min(length, steps_per_bar - step)
                if r.random() < (0.12 if energetic else 0.2):
                    notes.append((bar, step, length, None))
                else:
                    if step == 0:
                        # land on a chord tone at the start of a bar
                        targets = [chord_root, chord_root + 2, chord_root + 4, chord_root + 7]
                        degree = min(targets, key=lambda d: abs(d - degree))
                    else:
                        degree += int(r.choice([-2, -1, -1, 1, 1, 2, 0, 3, -3]))
                        degree = int(np.clip(degree, 0, 11))
                    notes.append((bar, step, length, degree))
                step += length
        return notes

    a = phrase(1)
    b = phrase(2)
    a2 = [(bar, st, ln, (d + (1 if bar == 3 and d is not None else 0)) if d is not None else None) for bar, st, ln, d in a]
    out = []
    for block, ph in enumerate([a, a2, b, a]):
        for bar, st, ln, d in ph:
            out.append((block * 4 + bar, st, ln, d))
    return [n for n in out if n[0] < bars]


def render_loop(name, bpm, bars, root, progression, seed, energetic, lead_wave="square", lead_duty=0.25):
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar_len = beat * 4
    total = int(round(bar_len * bars * SR))
    buf_lead = np.zeros(total)
    buf_bass = np.zeros(total)
    buf_arp = np.zeros(total)
    buf_drum = np.zeros(total)
    steps = 8
    step_len = bar_len / steps
    # Bass: root notes on each beat (energetic: octave bounce).
    for bar in range(bars):
        chord = progression[bar % len(progression)]
        for b in range(4):
            deg = chord if (not energetic or b % 2 == 0) else chord + 7
            midi = scale_note(root - 24, deg)
            x = voice(midi, beat * 0.9, "tri", attack=0.005, release_frac=0.5)
            place(buf_bass, x, int((bar * bar_len + b * beat) * SR))
        # Arpeggio (chord tones, 8ths) quietly.
        for s in range(steps):
            deg = chord + [0, 2, 4, 7][s % 4]
            x = voice(scale_note(root, deg), step_len * 0.8, "square", duty=0.125, attack=0.003, release_frac=0.8)
            place(buf_arp, x, int((bar * bar_len + s * step_len) * SR))
        # Drums.
        for s in range(steps):
            t = int((bar * bar_len + s * step_len) * SR)
            if energetic:
                if s in (0, 4) or (s == 6 and bar % 2 == 1):
                    place(buf_drum, drum("kick", seed + s), t)
                if s in (2, 6):
                    place(buf_drum, drum("snare", seed + 100 + s), t)
                place(buf_drum, drum("hat", seed + 200 + s + bar), t, 0.9 if s % 2 else 0.5)
            else:
                if s == 0:
                    place(buf_drum, drum("kick", seed + s), t, 0.6)
                if s == 4:
                    place(buf_drum, drum("snare", seed + 100), t, 0.4)
                if s % 2 == 0:
                    place(buf_drum, drum("hat", seed + 200 + s + bar), t, 0.5)
    # Lead melody.
    for bar, st, ln, d in make_melody(rng, progression, bars, steps, energetic):
        if d is None:
            continue
        midi = scale_note(root + 12, d)
        x = voice(midi, step_len * ln * 0.95, lead_wave, duty=lead_duty, attack=0.008, release_frac=0.45, vib=0.006)
        place(buf_lead, x, int((bar * bar_len + st * step_len) * SR))
    lead = lowpass_fast(buf_lead, 3200, SR)
    arpb = lowpass_fast(buf_arp, 2600, SR)
    bass = lowpass_fast(buf_bass, 1200, SR)
    mixb = lead * 0.32 + arpb * (0.1 if energetic else 0.08) + bass * 0.42 + buf_drum * (0.55 if energetic else 0.4)
    write_wav(OUT / f"{name}.wav", normalize(mixb, 0.75), SR)
    return total / SR


def render_jingle():
    beat = 0.18
    notes = [(72, 0, 1), (76, 1, 1), (79, 2, 1), (84, 3, 3), (83, 6, 1), (84, 7, 8)]
    total = int(4.0 * SR)
    buf = np.zeros(total + SR)
    for midi, start, ln in notes:
        x = voice(midi, beat * ln, "square", duty=0.25, attack=0.005, release_frac=0.5, vib=0.008)
        s = int(start * beat * SR)
        buf[s:s + len(x)] += x * 0.35
    for midi in (48, 55, 60, 64):
        x = voice(midi, 2.5, "tri", attack=0.01, release_frac=0.7)
        s = int(7 * beat * SR)
        buf[s:s + len(x)] += x * 0.25
    for i in range(8):
        k = drum("hat" if i < 7 else "snare", 300 + i)
        s = int(i * beat * SR)
        buf[s:s + len(k)] += k
    buf = lowpass_fast(buf[:total], 3500, SR)
    n = int(0.3 * SR)
    buf[-n:] *= np.linspace(1, 0, n)
    write_wav(OUT / "results_jingle.wav", normalize(buf, 0.75), SR)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # degrees: 0=I 5=vi 3=IV 4=V 1=ii
    d = render_loop("menu_loop", 90, 12, 60, [0, 5, 3, 4], seed=11, energetic=False, lead_wave="tri")
    print(f"menu_loop {d:.1f}s")
    d = render_loop("battle_loop_a", 120, 16, 62, [0, 4, 5, 3], seed=21, energetic=True)
    print(f"battle_loop_a {d:.1f}s")
    d = render_loop("battle_loop_b", 120, 16, 57, [5, 3, 0, 4], seed=31, energetic=True, lead_duty=0.5)
    print(f"battle_loop_b {d:.1f}s")
    d = render_loop("battle_loop_c", 128, 17, 64, [0, 3, 1, 4], seed=41, energetic=True, lead_wave="square", lead_duty=0.125)
    print(f"battle_loop_c {d:.1f}s")
    render_jingle()
    print("results_jingle 4.0s")


if __name__ == "__main__":
    main()
