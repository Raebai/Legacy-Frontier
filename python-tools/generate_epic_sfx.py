"""
Generate the LAYER + FOOTSTEP sound set that makes the combat mix read BIG.

Why a second generator instead of extending generate_placeholder_sfx.py: that
script owns the one-sound-per-event roster (cast/beam/cannon/...), and most of
those filenames now hold REAL clips from the TomMusic fantasy pack. Overwriting
them would clobber the maker's licensed audio. Everything here is PURELY
ADDITIVE — new filenames that nothing referenced before — so re-running either
script can never destroy the other's output.

Two families:

1. LAYER STEMS (sub_boom / rumble / crack). The maker's note was "not epic
   enough". A one-shot sample fired alone reads small no matter how loud it is,
   because a real detonation is three events: a CRACK (contact), a BODY (boom)
   and a TAIL (the room answering). The pack clips already carry crack+body, so
   what is missing is (a) low end under the hit and (b) a tail after it. These
   stems are those two missing thirds, plus a crack for the few sounds that
   genuinely have no attack (holy is a pure swell). Sfx.gd rides them UNDER the
   real clip automatically, per key, so no spell script has to change.
2. FOOTSTEPS (step / land). The existing footstep.wav is a 0.5 s stereo "Dirt
   Walk" pack clip fired on every foot-plant — at running cadence (a plant every
   ~0.12-0.2 s) that stacks 3+ copies of a half-second crunch into mush. These
   are single, ~80 ms, deliberately SMALL steps in four variants, plus a real
   landing thump that is a different sound rather than a pitched-down step.

Sub/rumble are written at 22050 Hz on purpose: they carry nothing above ~1 kHz,
so the extra bandwidth would be bytes spent on silence. Everything else stays at
the folder's 44100 Hz. All output is 16-bit PCM mono, deterministic (every
stochastic layer seeds its own random.Random).
"""

from __future__ import annotations

import math
import random
import struct
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

# Reuse the existing synth toolkit verbatim rather than re-deriving it — same
# de_click / normalize / mix semantics means these stems sit in the same world
# as the sounds they layer under.
from generate_placeholder_sfx import (  # noqa: E402
    SAMPLE_RATE,
    Samples,
    de_click,
    mix,
    noise,
    normalize,
    sub_kick,
    sweep,
    tone,
    transient,
)

# Low-frequency stems don't need 44.1k — 22050 halves the file for content that
# lives entirely below ~1 kHz.
LOW_RATE = 11025 * 2  # 22050 Hz


def write_wav_at(path: Path, samples: Samples, rate: int) -> None:
    """Like generate_placeholder_sfx.write_wav but with a caller-chosen rate."""
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
    )
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(frames)


def _resample_ratio() -> float:
    """The synth primitives are hard-wired to SAMPLE_RATE. Rather than fork them,
    low-rate stems are synthesized at 44.1k and decimated — the content is band-
    limited well under the 11 kHz Nyquist of 22050 Hz, so plain decimation is
    inaudible here and keeps one code path."""
    return SAMPLE_RATE / float(LOW_RATE)


def decimate(samples: Samples) -> Samples:
    """44100 -> 22050 by averaging sample pairs (a 2-tap anti-alias, enough for
    content that is already low-passed into the sub range)."""
    step = int(round(_resample_ratio()))
    return [
        sum(samples[i : i + step]) / float(len(samples[i : i + step]))
        for i in range(0, len(samples) - step + 1, step)
    ]


# ---------------------------------------------------------------------------
# LAYER STEMS — the missing low end and the missing tail
# ---------------------------------------------------------------------------

def make_sub_boom(variant: int) -> Samples:
    """The WEIGHT layer. A ~1 s sine that drops 58 -> 28 Hz — below where the
    pack clips have any energy, so it adds body without muddying their midrange.
    A quiet second harmonic keeps it audible on laptop/phone speakers that
    physically cannot reproduce 30 Hz (the ear reconstructs the missing
    fundamental from the harmonic). 12 ms attack so it never adds a click of its
    own — the crack of the sound it rides under is the attack."""
    f0 = 58.0 - variant * 6.0
    deep = sub_kick(f0, 28.0, 1.0, 3.2, 1.0)
    harm = sub_kick(f0 * 2.0, 56.0, 0.7, 5.0, 0.22)
    return normalize(de_click(mix(deep, harm), 12.0, 90.0), 0.92)


def make_rumble(variant: int) -> Samples:
    """The TAIL layer — what makes a blast sound like it happened somewhere
    rather than in a vacuum. Heavily low-passed noise (5 averaging passes = a
    dull roar, no hiss) with a slow 90 ms swell and a long decay, over a low
    drone. Rides ~60 ms behind the hit so it reads as the room answering, not as
    part of the impact."""
    seed = 900 + variant
    dur = 1.3
    roar = noise(dur, 3.4, 1.0, seed, lowpass=5)
    drone = sweep(52.0, 34.0, dur, 4.0, 0.55, curve=1.0)
    n = len(roar)
    swell = int(SAMPLE_RATE * 0.09)
    out: Samples = []
    for i in range(n):
        env = min(1.0, i / swell) if swell else 1.0
        out.append(env * (0.8 * roar[i] + 0.45 * drone[i]))
    return normalize(de_click(out, 4.0, 140.0), 0.85)


def make_crack(variant: int) -> Samples:
    """The ATTACK layer for sounds that have none. `holy` is a pure swell and
    `charge_up` fades in — without a transient the ear never registers the exact
    frame the thing happened, which is most of why a big spell can feel soft.
    ~40 ms: raw noise burst + a high ping + a short snap tail."""
    seed = 950 + variant
    t = transient(1.0, seed, bright=6800.0 - variant * 900.0)
    snap = noise(0.04, 260.0, 0.55, seed + 1, lowpass=1)
    ping = tone(3400.0 - variant * 500.0, 0.035, 190.0, 0.35)
    return normalize(de_click(mix(t, snap, ping), 0.4, 6.0), 0.94)


# ---------------------------------------------------------------------------
# FOOTSTEPS — deliberately small
# ---------------------------------------------------------------------------

def make_step(variant: int) -> Samples:
    """One SMALL step. ~80 ms so it is completely over before the next plant at
    sprint cadence (~0.12 s) — the mush the old 0.5 s walk-loop clip caused is a
    length problem first and a level problem second.

    Three parts, same as any impact but shrunk: a 6 ms scuff tick (contact), a
    low thump body, a whisper of grit. The four variants walk the body pitch and
    the noise seed so consecutive steps are audibly different footfalls rather
    than one sample stuttering; Sfx.gd adds pitch + level jitter on top."""
    seed = 1000 + variant
    body_hz = 104.0 + (variant - 1.5) * 13.0  # 84 / 97 / 110 / 123 Hz
    tick = noise(0.006, 700.0, 0.30, seed, lowpass=1)
    thump = tone(body_hz, 0.075, 76.0, 0.85)
    grit = noise(0.055, 95.0, 0.34, seed + 7, lowpass=2)
    return normalize(de_click(mix(tick, thump, grit), 0.4, 9.0), 0.62)


def make_land(variant: int) -> Samples:
    """Landing from a jump — a DIFFERENT sound, not a pitched-down step. Heavier
    body, a real sub under it (you feel a landing), and a scuff of debris after.
    ~0.3 s, which is fine because a landing is a one-off, never a cadence."""
    seed = 1010 + variant
    t = transient(0.55, seed, bright=2600.0)
    thump = tone(74.0 - variant * 6.0, 0.16, 30.0, 0.95)
    sub = sub_kick(96.0, 42.0, 0.26, 12.0, 0.7)
    scuff = noise(0.22, 22.0, 0.42, seed + 3, lowpass=3)
    return normalize(de_click(mix(t, thump, sub, scuff), 0.8, 24.0), 0.88)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# key -> (maker, variant_count, sample_rate)
SOUND_SET: dict[str, tuple] = {
    "sub_boom": (make_sub_boom, 2, LOW_RATE),
    "rumble": (make_rumble, 2, LOW_RATE),
    "crack": (make_crack, 2, SAMPLE_RATE),
    "step": (make_step, 4, SAMPLE_RATE),
    "land": (make_land, 2, SAMPLE_RATE),
}


def main() -> None:
    out_dir = Path(__file__).resolve().parent.parent / "godot-project" / "assets" / "audio" / "sfx"
    total_bytes = 0
    count = 0
    for key, (maker, variants, rate) in SOUND_SET.items():
        for v in range(variants):
            samples = maker(v)
            if rate != SAMPLE_RATE:
                samples = decimate(samples)
            path = out_dir / f"{key}_{v + 1}.wav"
            write_wav_at(path, samples, rate)
            size = path.stat().st_size
            total_bytes += size
            count += 1
            print(f"Wrote {path.name} ({size} bytes @ {rate} Hz)")
    print(f"Done: {count} SFX files, {total_bytes / 1024.0:.1f} KiB total.")


if __name__ == "__main__":
    main()
