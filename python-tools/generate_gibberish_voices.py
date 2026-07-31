"""
Generate the GIBBERISH VOICE bank — the Animal-Crossing-style "animalese" blips
that every character in THE TOWER speaks with.

WHY SYNTHESISED AND NOT RECORDED
--------------------------------
The spec is explicit: "Gibberish voices, Animal Crossing style, procedurally
pitched. No recording, no localisation, more characterful on a stick figure than
real VO." Three consequences fall out of that, and all three are why this file
exists instead of a folder of takes:

  * NO LICENCE SURFACE. Everything here is synthesised from scratch with the
    stdlib — no pack, no attribution, no "is this clearing?" question later.
    `assets/audio/CREDITS.md` section 3 already covers generated material.
  * NO LOCALISATION. A stick figure that says nothing in particular says it in
    every language.
  * TINY. Sixteen ~110 ms mono clips at 22050 Hz is about 70 KB of WAV, and
    Godot 4.6 imports WAV as QOA, so the shipped cost is a rounding error next
    to one music track.

WHAT A "VOICE" ACTUALLY IS HERE
-------------------------------
A syllable, not a word. Each clip is one glottal pulse-train run through two
resonant formant filters — the cheapest thing that reads as a MOUTH rather than
as a synth beep. Four vowel BANKS give the roster its consonant-free alphabet:

    a  open   (F1 730, F2 1090)  — the loud, shouty one
    e  mid    (F1 530, F2 1840)  — the neutral talker
    i  close  (F1 270, F2 2290)  — bright, small, panicky
    u  back   (F1 300,  F2 870)  — dark, low, grumbling

Four variants per bank, each with a different pitch glide (rising = a question,
falling = a statement, flat = filler) so a run of syllables never machine-guns
one sample.

PER-CHARACTER IDENTITY IS NOT BAKED IN HERE. It comes from playback: the game
picks a bank and a base pitch per entity (see `scripts/combat/Gibberish.gd`) and
re-pitches these same 16 clips. Sixteen assets, unlimited voices — which is the
whole reason to synthesise rather than record.

Deterministic: every stochastic layer seeds its own random.Random, so re-running
this produces byte-identical output.

Run:  python python-tools/generate_gibberish_voices.py
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

# 22050 is deliberate. A voice syllable carries nothing above ~5 kHz once it has
# been through the formant filters, so the upper half of a 44.1k band would be
# bytes spent on silence.
SAMPLE_RATE = 22050

OUT_DIR = Path(__file__).resolve().parent.parent / "godot-project" / "assets" / "audio" / "voice"

Samples = list[float]


# --------------------------------------------------------------------- output
def write_wav(path: Path, samples: Samples) -> int:
    """16-bit PCM mono. Returns bytes written."""
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767.0)) for s in samples
    )
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(frames)
    return path.stat().st_size


def _n(dur: float) -> int:
    return int(SAMPLE_RATE * dur)


def normalize(samples: Samples, peak: float) -> Samples:
    hi = max((abs(s) for s in samples), default=0.0)
    if hi <= 1e-9:
        return samples
    k = peak / hi
    return [s * k for s in samples]


def de_click(samples: Samples, attack_ms: float = 3.0, release_ms: float = 12.0) -> Samples:
    """Ramp the head and tail so a clip cannot start or stop on a discontinuity."""
    a = max(1, _n(attack_ms / 1000.0))
    r = max(1, _n(release_ms / 1000.0))
    out = list(samples)
    for i in range(min(a, len(out))):
        out[i] *= i / a
    for i in range(min(r, len(out))):
        out[len(out) - 1 - i] *= i / r
    return out


# --------------------------------------------------------------------- synth
def glottal_train(f0_start: float, f0_end: float, dur: float, seed: int) -> Samples:
    """
    The excitation: a train of short, slightly noisy pulses at a gliding f0.

    A pure impulse train through a formant filter sounds like a robot; real
    glottal closure is a soft asymmetric pulse. This approximates it with a
    half-cosine burst a few samples wide, plus a whisper of breath noise so the
    resonators have something broadband to ring on.
    """
    rng = random.Random(seed)
    n = _n(dur)
    out = [0.0] * n
    pulse_w = max(2, _n(0.0014))
    phase = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        # Log-ish glide reads more natural than a straight line.
        f0 = f0_start * math.pow(f0_end / f0_start, t)
        phase += f0 / SAMPLE_RATE
        if phase >= 1.0:
            phase -= 1.0
            for k in range(pulse_w):
                if i + k < n:
                    # Half-cosine pulse, asymmetric decay.
                    w = 0.5 - 0.5 * math.cos(math.pi * (k / pulse_w))
                    out[i + k] += w * (1.0 - k / (pulse_w * 1.6))
        out[i] += rng.uniform(-0.02, 0.02)  # breath
    return out


def resonator(samples: Samples, freq: float, bandwidth: float, gain: float) -> Samples:
    """Classic two-pole formant resonator (Klatt-style)."""
    r = math.exp(-math.pi * bandwidth / SAMPLE_RATE)
    theta = 2.0 * math.pi * freq / SAMPLE_RATE
    a1 = 2.0 * r * math.cos(theta)
    a2 = -(r * r)
    b0 = (1.0 - r) * math.sqrt(1.0 - 2.0 * r * math.cos(2.0 * theta) + r * r)
    y1 = 0.0
    y2 = 0.0
    out: Samples = []
    for x in samples:
        y = b0 * x + a1 * y1 + a2 * y2
        y2 = y1
        y1 = y
        out.append(y * gain)
    return out


def envelope(samples: Samples, attack: float, hold: float) -> Samples:
    """
    Fast attack, short hold, exponential fall. The attack is what makes a blip
    read as a consonant onset without there being a consonant.
    """
    n = len(samples)
    a = max(1, _n(attack))
    h = _n(hold)
    out: Samples = []
    for i, s in enumerate(samples):
        if i < a:
            g = i / a
        elif i < a + h:
            g = 1.0
        else:
            g = math.exp(-4.2 * (i - a - h) / max(1, n - a - h))
        out.append(s * g)
    return out


# --------------------------------------------------------------------- banks
# (name, F1, F2, F1 bandwidth, F2 bandwidth, F2 gain)
BANKS: list[tuple[str, float, float, float, float, float]] = [
    ("a", 730.0, 1090.0, 80.0, 90.0, 0.55),
    ("e", 530.0, 1840.0, 70.0, 110.0, 0.42),
    ("i", 270.0, 2290.0, 60.0, 130.0, 0.34),
    ("u", 300.0, 870.0, 60.0, 80.0, 0.48),
]

# (glide start multiplier, glide end multiplier, duration, hold)
#   flat        — filler, the middle of a sentence
#   rising      — a question, or surprise
#   falling     — a statement landing
#   short-drop  — a clipped grunt
VARIANTS: list[tuple[float, float, float, float]] = [
    (1.00, 1.00, 0.115, 0.030),
    (0.88, 1.22, 0.130, 0.026),
    (1.18, 0.86, 0.125, 0.030),
    (1.05, 0.92, 0.090, 0.018),
]

## Base f0 the clips are RENDERED at. Playback re-pitches from here, so this is
## a deliberately neutral mid-voice: the pitch bands in Gibberish.gd multiply
## around it, and a rendered f0 near the middle of the used range keeps the
## worst-case resampling artefact small in both directions.
BASE_F0 = 190.0


def make_syllable(bank_index: int, variant_index: int) -> Samples:
    _name, f1, f2, bw1, bw2, g2 = BANKS[bank_index]
    g_start, g_end, dur, hold = VARIANTS[variant_index]
    seed = 7000 + bank_index * 17 + variant_index
    src = glottal_train(BASE_F0 * g_start, BASE_F0 * g_end, dur, seed)
    # Two formants in parallel, not in series: series stacking buries F2 under
    # F1's rolloff and every vowel collapses toward the same muddy "uh".
    voiced = resonator(src, f1, bw1, 1.0)
    upper = resonator(src, f2, bw2, g2)
    mixed = [voiced[i] + upper[i] for i in range(len(src))]
    shaped = envelope(mixed, attack=0.006, hold=hold)
    return de_click(normalize(shaped, 0.82))


def main() -> None:
    total = 0
    written = 0
    for b, bank in enumerate(BANKS):
        for v in range(len(VARIANTS)):
            path = OUT_DIR / f"gib_{bank[0]}_{v + 1}.wav"
            total += write_wav(path, make_syllable(b, v))
            written += 1
    print(f"Wrote {written} gibberish syllables to {OUT_DIR} ({total} bytes total)")


if __name__ == "__main__":
    main()
