#!/usr/bin/env python3
"""Generate all SFX (PRD §11.5): soft, round, cute 'bloopy' sounds.

sfxr-style synthesis (square/saw/noise oscillators, envelopes, pitch
slides) with fixed seeds, so regeneration is byte-identical.
Output: assets/audio/sfx/<name>.wav, 44.1 kHz, mono, 16-bit.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np  # noqa: E402

from synth import (fade_edges, highpass_fast, lowpass_fast, mix, normalize, note_freq, reverb,  # noqa: E402
                   saturate, seq, tone, write_wav)

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "sfx"


def T(*a, **k):
    k.setdefault("sr", SR)
    return tone(*a, **k)


def blip(f0, f1, dur, wave_type="square", duty=0.3, cutoff=3500, **k):
    return T(dur, f0, f1, wave_type, duty=duty, cutoff=cutoff, **k)


def noise_burst(dur, f0, f1, cutoff=3000, seed=1, **k):
    return T(dur, f0, f1, "noise", cutoff=cutoff, seed=seed, **k)


def chord(notes, dur, wave_type="square", duty=0.25, cutoff=3000, gap=0.0):
    parts = [T(dur, note_freq(n), None, wave_type, duty=duty, cutoff=cutoff, attack=0.004) for n in notes]
    return mix(*parts, offsets=[i * gap for i in range(len(parts))], sr=SR)


def arp(notes, step, wave_type="square", duty=0.3, cutoff=3500, tail=0.12):
    parts = [T(step + tail, note_freq(n), None, wave_type, duty=duty, cutoff=cutoff, attack=0.003) for n in notes]
    return mix(*parts, offsets=[i * step for i in range(len(parts))], sr=SR)


# ---------------------------------------------------------------- v1.3 dramatic weapons
def _noise(dur, seed):
    return np.random.default_rng(seed).uniform(-1, 1, int(dur * SR))


def _decay(n, rate):
    return np.exp(-np.arange(n) / SR * rate)


def gunshot(seed, crack=1.0, body_cut=3000, body_dur=0.25, body_rate=14.0, thump_f=140.0, thump_dur=0.22,
            thump_gain=1.0, grit=2.5, room=0.35, wet=0.35, mech=0.0):
    """Layered shot: sharp crack + gritty body + sub thump + optional
    mechanical clack, saturated, with a short echo/room tail."""
    n = int(body_dur * SR)
    c = highpass_fast(_noise(0.03, seed), 2500, SR) * _decay(int(0.03 * SR), 160) * crack
    body = lowpass_fast(_noise(body_dur, seed + 1), body_cut, SR) * _decay(n, body_rate)
    tn = int(thump_dur * SR)
    t = np.arange(tn) / SR
    f = thump_f * np.exp(-t * 18) + 38
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * _decay(tn, 12) * thump_gain
    parts = [c, body * 0.9, thump]
    offs = [0.0, 0.0, 0.0]
    if mech > 0:
        clack = tone(0.04, 2400, 1800, "square", sr=SR, duty=0.3, cutoff=6000) * mech
        parts.append(clack)
        offs.append(min(0.09, body_dur * 0.5))
    x = saturate(mix(*parts, offsets=offs, sr=SR), grit)
    return reverb(x, SR, room=room, wet=wet)


def explosion_sfx(seed):
    dur = 1.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 90 * np.exp(-t * 3) + 28
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 2.2) * 1.2
    rumble = lowpass_fast(_noise(dur, seed), 600, SR) * np.exp(-t * 2.5)
    blast = lowpass_fast(_noise(0.35, seed + 1), 5000, SR) * _decay(int(0.35 * SR), 9)
    rng = np.random.default_rng(seed + 2)
    debris = np.zeros(n)
    for _ in range(26):
        p = int(rng.uniform(0.08, 1.1) * SR)
        k = highpass_fast(_noise(0.02, int(rng.integers(0, 9999))), 1500, SR) * _decay(int(0.02 * SR), 200)
        debris[p:p + len(k)] += k * rng.uniform(0.1, 0.35)
    blast = np.pad(blast, (0, n - len(blast)))
    x = saturate(boom + rumble * 0.9 + blast * 0.9 + debris, 2.2)
    return reverb(x, SR, room=0.6, wet=0.45)


SOUNDS = {
    "ui_click": lambda: blip(900, 1300, 0.06, duty=0.4, cutoff=4000),
    "ui_back": lambda: blip(900, 500, 0.08, duty=0.4, cutoff=3500),
    "ui_toggle": lambda: seq(blip(700, 700, 0.04), blip(1050, 1050, 0.05)),
    "ready": lambda: arp([72, 76, 79], 0.06),
    "player_join": lambda: arp([67, 72, 76, 79], 0.055, wave_type="tri"),
    "player_leave": lambda: arp([79, 74, 67], 0.07, wave_type="tri"),
    "countdown_tick": lambda: blip(660, 660, 0.12, wave_type="tri", cutoff=5000),
    "round_start": lambda: mix(arp([72, 79, 84], 0.07), chord([72, 76, 79], 0.45, gap=0.0), offsets=[0, 0.2], sr=SR),
    "round_end": lambda: arp([79, 76, 72, 67], 0.09, wave_type="tri"),
    "match_win": lambda: mix(arp([72, 76, 79, 84, 88], 0.08), chord([72, 76, 79, 84], 0.8), offsets=[0, 0.4], sr=SR),
    "jump": lambda: blip(300, 620, 0.14, duty=0.35, curve=0.6),
    "double_jump": lambda: seq(blip(420, 760, 0.08, duty=0.3), blip(620, 1000, 0.1, duty=0.3)),
    "land": lambda: mix(noise_burst(0.08, 900, 300, cutoff=900, seed=3), blip(160, 90, 0.08, "sine", cutoff=2000), sr=SR),
    "footstep": lambda: noise_burst(0.04, 1500, 700, cutoff=1400, seed=4),
    "punch_swing": lambda: noise_burst(0.12, 2500, 600, cutoff=2500, seed=5, attack=0.03),
    "punch_hit": lambda: mix(blip(220, 110, 0.12, "sine", cutoff=2000), noise_burst(0.06, 2000, 800, cutoff=2200, seed=6), sr=SR),
    "pickup_weapon": lambda: seq(blip(500, 500, 0.05, duty=0.25), blip(750, 750, 0.09, duty=0.25)),
    "pickup_health": lambda: arp([76, 79, 83, 88], 0.05, wave_type="tri"),
    "pickup_armor": lambda: arp([67, 71, 74, 79], 0.05, duty=0.5),
    "throw": lambda: noise_burst(0.16, 1200, 3000, cutoff=3000, seed=7, attack=0.04),
    "thrown_hit": lambda: mix(blip(300, 120, 0.12, duty=0.5, cutoff=2000), noise_burst(0.08, 1500, 500, seed=8), sr=SR),
    "weapon_empty": lambda: seq(blip(400, 380, 0.04, duty=0.5, cutoff=2500), blip(300, 280, 0.06, duty=0.5, cutoff=2500)),
    "pistol": lambda: gunshot(9, crack=1.0, body_cut=3500, body_dur=0.22, thump_f=150, thump_gain=0.9, grit=2.6, room=0.35, wet=0.35, mech=0.25),
    "smg": lambda: gunshot(10, crack=0.9, body_cut=4200, body_dur=0.12, body_rate=26, thump_f=170, thump_dur=0.12, thump_gain=0.7, grit=2.8, room=0.25, wet=0.25),
    "shotgun": lambda: mix(gunshot(11, crack=1.2, body_cut=2600, body_dur=0.45, body_rate=7, thump_f=110, thump_dur=0.35, thump_gain=1.3, grit=3.2, room=0.5, wet=0.4),
                           tone(0.08, 900, 600, "square", sr=SR, duty=0.4, cutoff=4000) * 0.35, offsets=[0, 0.42], sr=SR),
    "sniper": lambda: mix(gunshot(12, crack=1.4, body_cut=5000, body_dur=0.6, body_rate=6, thump_f=120, thump_dur=0.4, thump_gain=1.2, grit=3.0, room=0.8, wet=0.55),
                          tone(0.5, 1800, 300, "saw", sr=SR, cutoff=3000, curve=0.35) * 0.25, sr=SR),
    "rocket_launch": lambda: reverb(saturate(mix(gunshot(13, crack=0.8, body_cut=1500, body_dur=0.3, thump_f=90, thump_gain=1.3, grit=2.0, wet=0.0),
                                         noise_burst(0.7, 500, 2600, cutoff=2400, seed=14, attack=0.03) * 0.8,
                                         tone(0.6, 110, 260, "saw", sr=SR, cutoff=900) * 0.5, sr=SR), 1.8), SR, room=0.5, wet=0.35),
    "explosion": lambda: explosion_sfx(15),
    "grenade_throw": lambda: seq(noise_burst(0.1, 900, 2400, cutoff=2500, seed=15), blip(800, 1100, 0.05, duty=0.25)),
    "grenade_bounce": lambda: blip(520, 380, 0.07, "tri", cutoff=3000),
    "hit": lambda: mix(blip(420, 200, 0.1, duty=0.5, cutoff=2600), noise_burst(0.05, 2500, 1200, cutoff=2500, seed=16), sr=SR),
    "armor_hit": lambda: mix(blip(1200, 900, 0.1, "tri", cutoff=5000), blip(1800, 1500, 0.08, "tri", cutoff=5000), sr=SR),
    "death": lambda: seq(blip(600, 300, 0.12, duty=0.4), blip(400, 150, 0.25, duty=0.4), noise_burst(0.15, 1500, 400, seed=17)),
    "fall_whoosh": lambda: noise_burst(0.6, 2500, 300, cutoff=1800, seed=18, attack=0.15),
    "lava_sizzle": lambda: noise_burst(0.5, 5000, 3000, cutoff=4500, seed=19, attack=0.01),
    "spike_hit": lambda: mix(blip(1100, 500, 0.12, "square", duty=0.15, cutoff=4000), noise_burst(0.06, 3000, 1500, seed=20), sr=SR),
    "crate_break": lambda: mix(noise_burst(0.3, 1800, 300, cutoff=1600, seed=21), blip(260, 120, 0.15, duty=0.5, cutoff=1500), sr=SR),
    "jump_pad": lambda: blip(200, 1100, 0.3, "square", duty=0.3, curve=0.5, vibrato=0.05, vib_speed=18),
    "spawn_pop": lambda: seq(blip(600, 1200, 0.06, "sine", cutoff=6000), blip(1200, 900, 0.06, "sine", cutoff=6000)),
    # v1.1: soft rising shimmer while a spawn point glows.
    "spawn_warn": lambda: arp([79, 83, 86, 91], 0.09, wave_type="tri", cutoff=5000, tail=0.25),
    "low_time_tick": lambda: blip(1000, 1000, 0.07, "square", duty=0.2, cutoff=4500),
}


# Shots and explosions are mastered louder (v1.3) and their reverb tails are
# cut to these lengths (s) so rapid fire does not pile up voices.
LOUD = {"pistol", "smg", "shotgun", "sniper", "rocket_launch", "explosion"}
MAX_LEN = {"pistol": 0.6, "smg": 0.32, "shotgun": 0.95, "sniper": 1.3, "rocket_launch": 1.4, "explosion": 2.3}


def trim(x, max_len):
    n = int(max_len * SR)
    if len(x) <= n:
        return x
    x = x[:n].copy()
    f = int(n * 0.25)
    x[-f:] *= np.linspace(1, 0, f) ** 2
    return x


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in SOUNDS.items():
        peak = 0.92 if name in LOUD else 0.7
        raw = fn()
        if name in MAX_LEN:
            raw = trim(raw, MAX_LEN[name])
        x = normalize(fade_edges(raw, SR, 8.0), peak)
        write_wav(OUT / f"{name}.wav", x, SR)
    print(f"{len(SOUNDS)} sfx written to {OUT}")


if __name__ == "__main__":
    main()
