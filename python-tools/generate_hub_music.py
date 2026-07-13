"""
Generate a mystic-forest HUB AMBIENCE loop using stdlib only (maker: "cool artsy
music in the background, mystic forest feel"). A slow, evolving A-minor pad —
detuned sine voices, each breathing on its own slow LFO, plus a soft high shimmer
and a whisper of filtered wind — written as a seamless-looping 16-bit PCM mono WAV.

Output: godot-project/assets/audio/music/hub_ambience.wav
The loop is made seamless with an equal-ish crossfade of a tail continuation over
the head, so AudioStreamWAV.LOOP_FORWARD has no click at the seam.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
LOOP_SECONDS = 20.0
XFADE_SECONDS = 0.6
OUT = Path(__file__).resolve().parent.parent / "godot-project/assets/audio/music/hub_ambience.wav"

# A-minor add9 voicing across a few octaves — warm, wistful, a touch mystic.
# (freq_hz, base_gain, lfo_rate_hz, lfo_phase, detune_hz)
VOICES = [
    (110.00, 0.55, 0.031, 0.0, 0.14),   # A2 root
    (164.81, 0.42, 0.043, 1.1, 0.18),   # E3
    (220.00, 0.40, 0.037, 2.3, 0.20),   # A3
    (261.63, 0.34, 0.052, 0.7, 0.22),   # C4 (the minor third)
    (329.63, 0.30, 0.047, 3.0, 0.25),   # E4
    (493.88, 0.16, 0.061, 1.7, 0.30),   # B4 (the add9 colour)
    (659.25, 0.10, 0.070, 0.4, 0.0),    # E5 shimmer (soft, tremolo below)
]


def _pad_sample(t: float) -> float:
    s = 0.0
    for freq, gain, lfo_rate, lfo_phase, detune in VOICES:
        # Slow amplitude LFO so each voice swells independently (breathing).
        env = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(2.0 * math.pi * lfo_rate * t + lfo_phase))
        # Two slightly-detuned sines = a wide, chorused voice.
        v = math.sin(2.0 * math.pi * freq * t)
        if detune > 0.0:
            v += math.sin(2.0 * math.pi * (freq + detune) * t)
            v *= 0.5
        # The high shimmer gets an extra faster tremolo so it twinkles.
        if freq > 600.0:
            v *= 0.5 + 0.5 * math.sin(2.0 * math.pi * 0.9 * t)
        s += gain * env * v
    return s


def make_hub_ambience() -> list[float]:
    rng = random.Random(7)  # deterministic wind
    loop_n = int(SAMPLE_RATE * LOOP_SECONDS)
    xfade_n = int(SAMPLE_RATE * XFADE_SECONDS)
    total_n = loop_n + xfade_n
    # A very quiet, heavily-smoothed noise "wind" bed for air/texture.
    wind = 0.0
    out: list[float] = []
    for i in range(total_n):
        t = i / SAMPLE_RATE
        target = rng.uniform(-1.0, 1.0)
        wind += (target - wind) * 0.0006  # one-pole lowpass -> a slow airy hush
        sample = _pad_sample(t) * 0.16 + wind * 0.015
        out.append(sample)
    # Seamless loop: crossfade the tail continuation (out[loop_n:]) over the head so
    # out[loop_n-1] -> out[0] connects smoothly.
    for i in range(xfade_n):
        w = i / xfade_n  # 0 at the seam-head, 1 by the end of the fade
        head = out[i]
        tail = out[loop_n + i]
        out[i] = head * w + tail * (1.0 - w)
    out = out[:loop_n]
    # Gentle normalise so the bed sits low (it's mixed under everything anyway).
    loudest = max(abs(s) for s in out) or 1.0
    gain = 0.72 / loudest
    return [s * gain for s in out]


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
    )
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(frames)


def main() -> None:
    samples = make_hub_ambience()
    write_wav(OUT, samples)
    print(f"Wrote {OUT} ({len(samples) / SAMPLE_RATE:.1f}s, {OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
