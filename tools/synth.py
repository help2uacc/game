"""Tiny sfxr-style synthesis helpers (standard library + NumPy only)."""
import wave
from pathlib import Path

import numpy as np


def osc(wave_type: str, freq, sr: int, duty: float = 0.5, rng=None) -> np.ndarray:
    """freq: array of instantaneous frequencies (Hz) per sample."""
    phase = np.cumsum(freq / sr)
    frac = phase % 1.0
    if wave_type == "sine":
        return np.sin(2 * np.pi * phase)
    if wave_type == "square":
        return np.where(frac < duty, 1.0, -1.0)
    if wave_type == "saw":
        return 2.0 * frac - 1.0
    if wave_type == "tri":
        return 4.0 * np.abs(frac - 0.5) - 1.0
    if wave_type == "noise":
        rng = rng or np.random.default_rng(0)
        # sample-and-hold noise clocked by freq -> pitched noise like sfxr
        steps = np.floor(phase * 2).astype(np.int64)
        vals = rng.uniform(-1, 1, steps.max() + 2)
        return vals[steps]
    raise ValueError(wave_type)


def envelope(n: int, sr: int, attack: float, sustain: float, release: float, punch: float = 0.0) -> np.ndarray:
    a = int(attack * sr)
    s = int(sustain * sr)
    r = max(1, n - a - s)
    env = np.concatenate([
        np.linspace(0, 1, max(1, a), endpoint=False),
        np.ones(s) * (1.0 + punch),
        np.linspace(1.0, 0.0, r) ** 2,
    ])
    return env[:n] if len(env) >= n else np.pad(env, (0, n - len(env)))


def lowpass(x: np.ndarray, cutoff: float, sr: int) -> np.ndarray:
    """One-pole low-pass for a soft, round tone."""
    if cutoff >= sr / 2:
        return x
    dt = 1.0 / sr
    rc = 1.0 / (2 * np.pi * cutoff)
    alpha = dt / (rc + dt)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def lowpass_fast(x: np.ndarray, cutoff: float, sr: int) -> np.ndarray:
    """FFT-based gentle low-pass (vectorised, for long buffers)."""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / sr)
    spec *= 1.0 / np.sqrt(1.0 + (freqs / cutoff) ** 4)
    return np.fft.irfft(spec, len(x))


def tone(dur, f0, f1=None, wave_type="square", sr=44100, duty=0.5, attack=0.005, sustain=0.0,
         release=None, curve=1.0, vibrato=0.0, vib_speed=0.0, cutoff=6000.0, seed=0, punch=0.0):
    n = int(dur * sr)
    t = np.linspace(0, 1, n, endpoint=False)
    f1 = f0 if f1 is None else f1
    freq = f0 + (f1 - f0) * (t ** curve)
    if vibrato:
        freq = freq * (1.0 + vibrato * np.sin(2 * np.pi * vib_speed * t * dur))
    rng = np.random.default_rng(seed)
    x = osc(wave_type, freq, sr, duty, rng)
    if release is None:
        release = max(0.0, dur - attack - sustain)
    x *= envelope(n, sr, attack, sustain, release, punch)
    if cutoff:
        x = lowpass_fast(x, cutoff, sr)
    return x


def mix(*parts, offsets=None, sr=44100):
    offsets = offsets or [0.0] * len(parts)
    n = max(int(o * sr) + len(p) for p, o in zip(parts, offsets))
    out = np.zeros(n)
    for p, o in zip(parts, offsets):
        s = int(o * sr)
        out[s:s + len(p)] += p
    return out


def seq(*parts):
    return np.concatenate(parts)


def normalize(x, peak=0.8):
    m = np.max(np.abs(x)) if len(x) else 0
    if m <= 0:
        return x
    return x * (peak / m)


def fade_edges(x, sr, ms=3.0):
    n = int(sr * ms / 1000)
    if len(x) > 2 * n and n > 0:
        x = x.copy()
        x[:n] *= np.linspace(0, 1, n)
        x[-n:] *= np.linspace(1, 0, n)
    return x


def write_wav(path: Path, x: np.ndarray, sr: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(x, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def note_freq(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def highpass_fast(x: np.ndarray, cutoff: float, sr: int) -> np.ndarray:
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / sr)
    spec *= 1.0 / np.sqrt(1.0 + (cutoff / np.maximum(freqs, 1.0)) ** 4)
    return np.fft.irfft(spec, len(x))


def reverb(x: np.ndarray, sr: int, room: float = 0.35, wet: float = 0.25, wrap: bool = False) -> np.ndarray:
    """Cheap multi-tap feedback reverb (deterministic). `wrap` keeps loops seamless."""
    taps = [(0.029, 0.6), (0.037, 0.55), (0.053, 0.5), (0.071, 0.45), (0.089, 0.4), (0.113, 0.33)]
    n = len(x)
    out = np.zeros(n + (0 if wrap else int(sr * 1.5)))
    out[:n] += x
    tail = np.zeros_like(out)
    for delay, gain in taps:
        d = int(delay * sr * (1.0 + room))
        g = gain * room
        y = x.copy()
        for k in range(1, 6):
            shift = d * k
            amp = g ** k
            if amp < 0.002:
                break
            if wrap:
                tail += np.roll(np.pad(y, (0, len(out) - n)), shift) * amp
            else:
                if shift < len(tail):
                    seg = y[: len(tail) - shift]
                    tail[shift:shift + len(seg)] += seg * amp
    tail = lowpass_fast(tail, 4000, sr)
    return out * (1.0 - wet * 0.3) + tail * wet


def saturate(x: np.ndarray, drive: float = 2.0) -> np.ndarray:
    """Soft clipping for punch and grit."""
    return np.tanh(x * drive) / np.tanh(drive)
