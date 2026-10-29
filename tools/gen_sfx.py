#!/usr/bin/env python3
"""Generate all SFX (PRD §11.5): soft, round, cute 'bloopy' sounds.

sfxr-style synthesis (square/saw/noise oscillators, envelopes, pitch
slides) with fixed seeds, so regeneration is byte-identical.
Output: assets/audio/sfx/<name>.wav, 44.1 kHz, mono, 16-bit.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from synth import fade_edges, mix, normalize, note_freq, seq, tone, write_wav  # noqa: E402

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
    "pistol": lambda: mix(blip(900, 260, 0.12, duty=0.5, cutoff=3000), noise_burst(0.07, 4000, 1500, cutoff=3000, seed=9), sr=SR),
    "smg": lambda: mix(blip(1000, 420, 0.07, duty=0.5, cutoff=3200), noise_burst(0.05, 4000, 2000, cutoff=3000, seed=10), sr=SR),
    "shotgun": lambda: mix(noise_burst(0.3, 2500, 300, cutoff=2200, seed=11), blip(220, 70, 0.22, "sine", cutoff=1500), sr=SR),
    "sniper": lambda: mix(blip(1600, 200, 0.35, duty=0.5, cutoff=3500, curve=0.4), noise_burst(0.2, 3000, 600, cutoff=2600, seed=12), sr=SR),
    "rocket_launch": lambda: mix(noise_burst(0.45, 600, 2200, cutoff=1800, seed=13, attack=0.02), blip(140, 300, 0.4, "saw", cutoff=900), sr=SR),
    "explosion": lambda: mix(noise_burst(0.8, 1200, 80, cutoff=1300, seed=14, curve=0.5), blip(120, 40, 0.6, "sine", cutoff=600), sr=SR),
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


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in SOUNDS.items():
        x = normalize(fade_edges(fn(), SR), 0.7)
        write_wav(OUT / f"{name}.wav", x, SR)
    print(f"{len(SOUNDS)} sfx written to {OUT}")


if __name__ == "__main__":
    main()
