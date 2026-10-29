#!/usr/bin/env python3
"""Generate music loops (PRD §11.5, v1.3: epic / heroic style).

Minor-key anthems: driving drums with tom fills and war-drum booms, a
pulsing saw bass, wide saw power-chord pads, a brass-like lead melody,
16th-note arpeggios and a light reverb. Seamless loops, deterministic.

Output: assets/audio/music/<name>.wav, 22.05 kHz, mono, 16-bit.
  menu_loop      heroic, mid-tempo, ~32 s
  battle_loop_a  epic, fast, ~32 s
  battle_loop_b  epic, fast, ~32 s
  battle_loop_c  epic, fast, ~32 s
  results_jingle triumphant fanfare, ~4 s (one-shot)
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from synth import lowpass_fast, normalize, note_freq, osc, reverb, saturate, write_wav  # noqa: E402

SR = 22050
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "music"

MINOR = [0, 2, 3, 5, 7, 8, 10]
MAJOR = [0, 2, 4, 5, 7, 9, 11]


def scale_note(root, degree, scale=MINOR):
    octave, idx = divmod(degree, 7)
    return root + 12 * octave + scale[idx]


def env(n, attack, release_frac, sustain_level=1.0):
    e = np.ones(n) * sustain_level
    a = max(1, int(attack * SR))
    e[:a] = np.linspace(0, sustain_level, a)
    r = int(n * release_frac)
    if r > 0:
        e[n - r:] *= np.linspace(1, 0, r) ** 1.4
    return e


def saw_stack(midi, dur, detune=0.006, voices=2, attack=0.02, release_frac=0.3, seed=0):
    """Detuned saws (pads / brass)."""
    n = max(1, int(dur * SR))
    out = np.zeros(n)
    for v in range(voices):
        f = note_freq(midi) * (1.0 + detune * (v - (voices - 1) / 2.0))
        out += osc("saw", np.full(n, f), SR)
    return out / voices * env(n, attack, release_frac)


def brass(midi, dur, seed=0):
    """Brass-like lead: saw with a filter 'swell' and vibrato."""
    n = max(1, int(dur * SR))
    t = np.arange(n) / SR
    f = note_freq(midi) * (1.0 + 0.008 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t * 3, 0, 1))
    x = osc("saw", f, SR) * 0.7 + osc("square", f * 0.5, SR, 0.5) * 0.3
    x = lowpass_fast(x, 2600, SR)
    return x * env(n, 0.03, 0.35)


def drum(kind, seed):
    rng = np.random.default_rng(seed)
    if kind == "kick":
        n = int(0.32 * SR)
        t = np.arange(n) / SR
        f = 120 * np.exp(-t * 22) + 42
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
        click = rng.uniform(-1, 1, n) * np.exp(-t * 300) * 0.3
        return saturate(x + click, 1.6)
    if kind == "boom":  # war drum / timpani hit
        n = int(0.9 * SR)
        t = np.arange(n) / SR
        f = 70 * np.exp(-t * 4) + 38
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 3.5)
        x += lowpass_fast(rng.uniform(-1, 1, n), 400, SR) * np.exp(-t * 12) * 0.6
        return saturate(x, 1.8)
    if kind == "snare":
        n = int(0.25 * SR)
        t = np.arange(n) / SR
        x = rng.uniform(-1, 1, n) * np.exp(-t * 18) * 0.7
        x += np.sin(2 * np.pi * 185 * t) * np.exp(-t * 25) * 0.5
        return lowpass_fast(x, 6000, SR)
    if kind == "tom":
        n = int(0.3 * SR)
        t = np.arange(n) / SR
        f = 160 * np.exp(-t * 8) + 90
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 10)
    if kind == "crash":
        n = int(1.4 * SR)
        t = np.arange(n) / SR
        x = rng.uniform(-1, 1, n) * np.exp(-t * 2.6)
        return lowpass_fast(x, 9000, SR) * 0.35 - lowpass_fast(x, 2500, SR) * 0.25
    n = int(0.06 * SR)  # hat
    t = np.arange(n) / SR
    x = rng.uniform(-1, 1, n) * np.exp(-t * 70)
    return (x - lowpass_fast(x, 5000, SR)) * 0.5


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
        rest = x[first:]
        while len(rest) > 0:
            k = min(n, len(rest))
            buf[:k] += rest[:k] * gain
            rest = rest[k:]


def heroic_melody(rng, progression, bars, steps):
    """Phrase A (4 bars), A' (rising ending), B (climbing), A — long notes,
    leaps of fourths/fifths, landing on chord tones on strong beats."""
    rhythms = [[4, 2, 2, 4, 4], [2, 2, 4, 8], [6, 2, 4, 4], [4, 4, 8], [3, 3, 2, 4, 4]]

    def phrase(seed, climb):
        r = np.random.default_rng(seed)
        notes = []
        deg = 7
        for bar in range(4):
            chord = progression[bar % len(progression)]
            rhythm = rhythms[int(r.integers(0, len(rhythms)))]
            st = 0
            for i, ln in enumerate(rhythm):
                if st >= steps:
                    break
                ln = min(ln, steps - st)
                if i == 0:
                    targets = [chord + 7, chord + 9, chord + 11, chord + 4]
                    deg = min(targets, key=lambda d: abs(d - deg - climb * bar))
                else:
                    deg += int(r.choice([-1, 1, 2, -2, 3, 4, -3, 0]))
                    deg = int(np.clip(deg, 4, 14))
                notes.append((bar, st, ln, deg))
                st += ln
        return notes

    seed = int(rng.integers(0, 1 << 30))
    a = phrase(seed, 0)
    b = phrase(seed + 7, 1)
    a2 = [(bar, st, ln, d + (2 if bar == 3 and st == 0 else 0)) for bar, st, ln, d in a]
    out = []
    for block, ph in enumerate([a, a2, b, a]):
        for bar, st, ln, d in ph:
            out.append((block * 4 + bar, st, ln, d))
    return [nt for nt in out if nt[0] < bars]


def render_epic(name, bpm, bars, root, progression, seed, intensity):
    """intensity 0..1: 0 = menu (heroic, calmer), 1 = battle."""
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar_len = beat * 4
    steps = 16
    step = bar_len / steps
    total = int(round(bar_len * bars * SR))
    b_drum = np.zeros(total)
    b_bass = np.zeros(total)
    b_pad = np.zeros(total)
    b_lead = np.zeros(total)
    b_arp = np.zeros(total)
    for bar in range(bars):
        chord = progression[bar % len(progression)]
        t0 = bar * bar_len
        # Power-chord pad (root, fifth, octave) for the whole bar.
        for d, g in [(0, 1.0), (4, 0.8), (7, 0.6)]:
            midi = scale_note(root - 12, chord + d)
            place(b_pad, saw_stack(midi, bar_len * 1.02, 0.008, 2, 0.08, 0.15), int(t0 * SR), g)
        # Driving bass: 8ths (battle) / quarters (menu), octave jump on offbeats.
        div = 8 if intensity > 0.5 else 4
        for i in range(div):
            midi = scale_note(root - 24, chord) + (12 if (i % 2 == 1 and intensity > 0.5) else 0)
            ln = bar_len / div
            x = saw_stack(midi, ln * 0.9, 0.003, 2, 0.004, 0.4)
            place(b_bass, x, int((t0 + i * ln) * SR))
        # 16th arpeggio (battle) / 8th (menu).
        arp_div = 16 if intensity > 0.5 else 8
        pattern = [0, 4, 7, 9, 7, 4, 2, 4]
        for i in range(arp_div):
            midi = scale_note(root + 12, chord + pattern[i % len(pattern)])
            ln = bar_len / arp_div
            n = int(ln * 0.8 * SR)
            x = osc("square", np.full(n, note_freq(midi)), SR, 0.25) * env(n, 0.002, 0.7)
            place(b_arp, x, int((t0 + i * ln) * SR))
        # Drums.
        for s in range(steps):
            t = int((t0 + s * step) * SR)
            if intensity > 0.5:
                if s in (0, 6, 8, 10) or (s == 14 and bar % 2 == 1):
                    place(b_drum, drum("kick", seed + s), t, 0.9)
                if s in (4, 12):
                    place(b_drum, drum("snare", seed + 50 + s + bar), t, 0.8)
                if s % 2 == 0:
                    place(b_drum, drum("hat", seed + 100 + s + bar), t, 0.5 if s % 4 else 0.8)
            else:
                if s in (0, 10):
                    place(b_drum, drum("kick", seed + s), t, 0.7)
                if s == 8:
                    place(b_drum, drum("snare", seed + 50 + bar), t, 0.5)
                if s % 4 == 2:
                    place(b_drum, drum("hat", seed + 100 + s + bar), t, 0.4)
        # War-drum boom on every bar start; crash at each 4-bar phrase.
        place(b_drum, drum("boom", seed + 200 + bar), int(t0 * SR), 0.9 if intensity > 0.5 else 0.7)
        if bar % 4 == 0:
            place(b_drum, drum("crash", seed + 300 + bar), int(t0 * SR), 0.9 if intensity > 0.5 else 0.6)
        # Tom fill at the end of every 4th bar.
        if bar % 4 == 3:
            for k, s in enumerate([12, 13, 14, 15]):
                tom = drum("tom", seed + 400 + k)
                pitch_idx = np.arange(len(tom)) * (1.0 + 0.15 * (3 - k))
                tom = np.interp(np.clip(pitch_idx, 0, len(tom) - 1), np.arange(len(tom)), tom)
                place(b_drum, tom, int((t0 + s * step) * SR), 0.9)
    # Brass lead melody.
    for bar, st, ln, d in heroic_melody(rng, progression, bars, steps):
        midi = scale_note(root, d)
        x = brass(midi, step * ln * 0.97, seed + bar)
        place(b_lead, x, int((bar * bar_len + st * step) * SR))
    pad = lowpass_fast(b_pad, 1800 if intensity > 0.5 else 1400, SR)
    bass = lowpass_fast(b_bass, 700, SR)
    arp = lowpass_fast(b_arp, 3000, SR)
    music = pad * 0.20 + bass * 0.42 + arp * (0.09 if intensity > 0.5 else 0.06) + b_lead * 0.36
    music = reverb(music, SR, room=0.4, wet=0.3, wrap=True)[:total]
    mixb = saturate(music * 0.9 + b_drum * (0.55 if intensity > 0.5 else 0.42), 1.3)
    write_wav(OUT / f"{name}.wav", normalize(mixb, 0.8), SR)
    return total / SR


def render_jingle():
    """Triumphant brass fanfare with drum roll and a final boom."""
    beat = 0.16
    notes = [(60, 0, 1), (60, 1, 1), (60, 2, 1), (67, 3, 3), (65, 6, 1), (67, 7, 1), (72, 8, 10)]
    total = int(4.0 * SR)
    buf = np.zeros(total + 3 * SR)
    for midi, start, ln in notes:
        for octave_gain in [(0, 0.5), (12, 0.25)]:
            x = brass(midi + octave_gain[0], beat * ln)
            s = int(start * beat * SR)
            buf[s:s + len(x)] += x * octave_gain[1]
    for d in (0, 4, 7, 12):
        x = saw_stack(48 + d, 2.6, 0.008, 2, 0.05, 0.6)
        s = int(8 * beat * SR)
        buf[s:s + len(x)] += lowpass_fast(x, 1800, SR) * 0.18
    for i in range(16):
        k = drum("snare", 500 + i) * (0.25 + 0.5 * i / 16)
        s = int(i * beat * 0.5 * SR)
        buf[s:s + len(k)] += k
    for kind, pos, g in [("boom", 8, 1.0), ("crash", 8, 0.8)]:
        k = drum(kind, 600)
        s = int(pos * beat * SR)
        buf[s:s + len(k)] += k * g
    buf = reverb(buf[:total], SR, room=0.45, wet=0.35)[:total]
    n = int(0.4 * SR)
    buf[-n:] *= np.linspace(1, 0, n)
    write_wav(OUT / "results_jingle.wav", normalize(saturate(buf, 1.2), 0.8), SR)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Progressions (degrees in natural minor): 0=i 5=VI 2=III 6=VII 3=iv 4=v
    d = render_epic("menu_loop", 96, 13, 57, [0, 5, 2, 6], seed=11, intensity=0.0)
    print(f"menu_loop {d:.1f}s")
    d = render_epic("battle_loop_a", 140, 19, 57, [0, 5, 2, 6], seed=21, intensity=1.0)
    print(f"battle_loop_a {d:.1f}s")
    d = render_epic("battle_loop_b", 136, 18, 52, [0, 3, 5, 4], seed=31, intensity=1.0)
    print(f"battle_loop_b {d:.1f}s")
    d = render_epic("battle_loop_c", 144, 19, 55, [0, 6, 5, 6], seed=41, intensity=1.0)
    print(f"battle_loop_c {d:.1f}s")
    render_jingle()
    print("results_jingle 4.0s")


if __name__ == "__main__":
    main()
