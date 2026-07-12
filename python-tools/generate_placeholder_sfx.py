"""
Generate placeholder combat/movement SFX using stdlib only.
Three 16-bit PCM mono WAVs at 44100 Hz:
  ding.wav     -- bright "clean hit / parry" ding (decaying inharmonic sine partials)
  footstep.wav -- soft low thump (sine burst + smoothed noise, fast decay)
  blink.wav    -- epic shadow-step teleport (charge whoosh -> bright bell + sub thump)
Output: godot-project/assets/audio/sfx/
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
BIT_DEPTH = 16  # samples packed as signed 16-bit little-endian
CHANNELS = 1


def write_wav(path: Path, samples: list[float]) -> None:
    """Write float samples in [-1.0, 1.0] as a 16-bit PCM mono WAV."""
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
    )
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(BIT_DEPTH // 8)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(frames)


def normalize(samples: list[float], peak: float) -> list[float]:
    """Scale so the loudest sample sits at `peak` of full scale."""
    loudest = max(abs(s) for s in samples)
    if loudest == 0.0:
        return samples
    gain = peak / loudest
    return [s * gain for s in samples]


def make_ding() -> list[float]:
    """Bright parry/clean-hit ding: a fundamental plus inharmonic bell-like
    partials (ratios chosen off the harmonic series so it reads as metal,
    not an organ tone), each with its own exponential decay. A ~2 ms linear
    attack removes the click at onset; the whole thing rings then fades."""
    duration = 0.28
    n = int(SAMPLE_RATE * duration)
    # (frequency multiplier, relative amplitude, decay rate per second)
    partials = [
        (1.00, 1.00, 12.0),   # fundamental ~1500 Hz, rings longest
        (2.76, 0.55, 18.0),   # inharmonic partial, dies faster
        (5.40, 0.30, 26.0),   # highest shimmer, dies fastest
    ]
    fundamental = 1500.0
    attack_samples = int(SAMPLE_RATE * 0.002)  # ~2 ms fast attack

    samples: list[float] = []
    for i in range(n):
        t = i / SAMPLE_RATE
        s = 0.0
        for ratio, amp, decay in partials:
            s += amp * math.exp(-decay * t) * math.sin(2.0 * math.pi * fundamental * ratio * t)
        if i < attack_samples:
            s *= i / attack_samples
        samples.append(s)
    return normalize(samples, 0.85)


def make_footstep() -> list[float]:
    """Soft footstep thump: a ~95 Hz sine burst for body plus a short burst
    of white noise for the scuff. The noise is averaged with its neighbour
    (a crude one-pole-ish low-pass) so it reads as cloth-on-dirt rather than
    static. Very fast exponential decay keeps it percussive."""
    duration = 0.09
    n = int(SAMPLE_RATE * duration)
    rng = random.Random(42)  # deterministic output across runs

    # Pre-generate noise, then smooth by averaging adjacent samples (low-pass feel).
    noise = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    smoothed = [(noise[i] + noise[i - 1]) / 2.0 if i > 0 else noise[0] for i in range(n)]

    attack_samples = int(SAMPLE_RATE * 0.001)  # ~1 ms attack, softens the onset click
    samples: list[float] = []
    for i in range(n):
        t = i / SAMPLE_RATE
        thump = 0.9 * math.exp(-45.0 * t) * math.sin(2.0 * math.pi * 95.0 * t)
        scuff = 0.35 * math.exp(-70.0 * t) * smoothed[i]
        s = thump + scuff
        if i < attack_samples:
            s *= i / attack_samples
        samples.append(s)
    return normalize(samples, 0.55)


def make_blink() -> list[float]:
    """Shadow-blink teleport, EPIC read (not the old goofy vwip). Three stacked
    layers around a single ARRIVAL moment at ~40% through:
      1. Charge whoosh  -- a rising, swelling tone + noise that gathers energy
                           before the step (integrated phase, so click-free).
      2. Arrival bell   -- a bright inharmonic ping (bell-like partials off the
                           harmonic series -> "magic", not "organ") that snaps in
                           at the arrival and rings out.
      3. Sub thump      -- a low ~70 Hz sine kick at the arrival for weight/body,
                           so the step lands with impact instead of chirping.
    Plus an airy smoothed-noise sparkle tail on the re-entry. Contour: swell ->
    bright hit + low boom -> shimmer decay. Reads as a powerful phase-step."""
    duration = 0.34
    n = int(SAMPLE_RATE * duration)
    rng = random.Random(7)  # deterministic output across runs

    arrival = 0.40  # fraction where the charge resolves into the arrival hit
    bell_base = 880.0
    # (frequency multiplier, relative amplitude, decay rate per second)
    bell_partials = [
        (1.00, 1.00, 11.0),  # rings longest
        (2.03, 0.55, 17.0),  # inharmonic -> metallic/magical
        (3.87, 0.30, 25.0),  # top shimmer, dies fastest
    ]

    # Smoothed noise for the charge swell + re-entry sparkle (footstep low-pass).
    noise = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    smoothed = [(noise[i] + noise[i - 1]) / 2.0 if i > 0 else noise[0] for i in range(n)]

    attack_samples = int(SAMPLE_RATE * 0.003)   # ~3 ms attack, no onset click
    release_samples = int(SAMPLE_RATE * 0.040)  # ~40 ms release, no tail click

    samples: list[float] = []
    phase = 0.0
    for i in range(n):
        u = i / n  # normalized position 0..1
        s = 0.0

        # 1. Charge whoosh: rises 240 -> ~1500 Hz, swelling louder toward arrival.
        if u < arrival:
            v = u / arrival
            freq = 240.0 + 1300.0 * (v * v)
            phase += 2.0 * math.pi * freq / SAMPLE_RATE
            s += 0.42 * v * math.sin(phase)
            s += 0.38 * (v * v) * smoothed[i]
        else:
            phase += 2.0 * math.pi * 1500.0 / SAMPLE_RATE  # keep phase continuous

        # 2 + 3. Arrival bell + sub thump, timed from the arrival moment.
        if u >= arrival:
            ta = (u - arrival) * duration  # seconds since arrival
            bell = 0.0
            for ratio, amp, decay in bell_partials:
                bell += amp * math.exp(-decay * ta) * math.sin(2.0 * math.pi * bell_base * ratio * ta)
            s += 0.72 * bell
            s += 0.60 * math.exp(-26.0 * ta) * math.sin(2.0 * math.pi * 70.0 * ta)  # sub thump
            s += 0.16 * math.exp(-15.0 * ta) * smoothed[i]                          # airy sparkle

        if i < attack_samples:
            s *= i / attack_samples
        if i >= n - release_samples:
            s *= (n - i) / release_samples
        samples.append(s)
    return normalize(samples, 0.82)


def main() -> None:
    out_dir = Path(__file__).resolve().parent.parent / "godot-project" / "assets" / "audio" / "sfx"
    for name, samples in (
        ("ding.wav", make_ding()),
        ("footstep.wav", make_footstep()),
        ("blink.wav", make_blink()),
    ):
        path = out_dir / name
        write_wav(path, samples)
        print(f"Wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
