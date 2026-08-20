"""Fill the two real holes in the SFX roster: a WRONG sound, and thin pools.

Run:  python python-tools/generate_missing_sfx.py

WHY A THIRD GENERATOR. `generate_placeholder_sfx.py` owns the one-sound-per-event
roster and most of those filenames now hold licensed clips from the maker's packs;
`generate_epic_sfx.py` owns the layer stems and footsteps. Overwriting either
would clobber work. Everything here is PURELY ADDITIVE — new filenames nothing
referenced before — so any of the three can be re-run in any order.

WHAT AN AUDIT OF `Sfx.STREAMS` ACTUALLY FOUND (120 pools, 262 references):

  * ONE POOL IS PLAYING SOMEBODY ELSE'S SOUND. `cannon` and `holy_pillar` both
    point at holy_pillar_1.wav / holy_pillar_2.wav. A holy pillar is a rising
    choral swell; a cannon is a percussive artillery hit. They are not neighbours
    and the substitution is audible. This is the one flagged in the resume queue.

    (The other eleven shared files are FINE and deliberately left alone: `beam` ->
    beam_arcane, `ice` -> ice_wall, `earth` -> earth_wall and `footstep` -> step
    are generic aliases of a specific sound, which is a different thing from two
    unrelated events colliding.)

  * FIFTEEN POOLS HAVE A SINGLE SAMPLE, so they machine-gun the identical
    waveform on repeat. Not all fifteen matter — `ult_unmaking` fires once a
    fight. The ones that matter are the ones that fire in bursts, because
    repetition is only audible when it repeats: `blink` (every dash of two
    classes), `shadow_cast`, `gib` (every kill, and kills cluster), `ding`,
    `beam_start` / `beam_end` (every beam, and beams are re-cast constantly).

⚠ 16-BIT PCM, WHICH IS NOT A STYLE CHOICE. Three of the maker's own files were
24-bit WAVE_FORMAT_EXTENSIBLE, which Godot silently refuses to import — it writes
an .md5 and no .sample, so the sound simply never plays and nothing says why.
`write_wav_at` from the epic generator writes 16-bit PCM mono, which imports.

Every layer seeds its own random.Random, so re-running produces byte-identical
files rather than a fresh diff.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from generate_epic_sfx import write_wav_at  # noqa: E402
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

OUT = Path(__file__).resolve().parent.parent / "godot-project" / "assets" / "audio" / "sfx"


def _pad(samples: Samples, seconds: float) -> Samples:
    """Right-pad with silence so layers of different lengths can be mixed."""
    want = int(SAMPLE_RATE * seconds)
    return samples + [0.0] * max(0, want - len(samples))


# ---------------------------------------------------------------------------
# CANNON — the one that was playing the wrong sound
# ---------------------------------------------------------------------------

def make_cannon(variant: int) -> Samples:
    """ARTILLERY, not a choir. Three events in the order a real gun makes them:

      1. the CRACK of the charge going off (a bright transient, ~5 ms),
      2. the BODY — a fast pitch drop through the low mids, which is what gives
         a cannon its "whump" rather than a "boom",
      3. a short dirty TAIL so it lands somewhere with walls.

    Deliberately shorter and drier than `blast`: a cannon is a SHOT, and the
    holy_pillar clip it has been borrowing is a 1.5 s swell — which is most of
    why the substitution was noticeable even to someone not listening for it.
    """
    seed = 1400 + variant
    crack = transient(0.95, seed, bright=5200.0 - variant * 700.0)
    # The barrel. Two detuned drops so it has girth without a single clean pitch.
    body_a = sweep(190.0 - variant * 18.0, 44.0, 0.55, 7.0, 0.85, curve=2.6)
    body_b = sweep(132.0 - variant * 12.0, 38.0, 0.62, 6.0, 0.55, curve=2.2)
    # Weight under it, kept below where the body lives so it does not muddy.
    weight = sub_kick(64.0 - variant * 5.0, 30.0, 0.70, 5.5, 0.7)
    # Powder smoke — mid noise, gone fast.
    smoke = noise(0.30, 14.0, 0.42, seed + 1, lowpass=2)
    tail = noise(0.55, 6.5, 0.20, seed + 2, lowpass=4)
    dur = 0.75
    out = mix(*[_pad(layer, dur) for layer in (crack, body_a, body_b, weight, smoke, tail)])
    return normalize(de_click(out, 0.4, 60.0), 0.95)


# ---------------------------------------------------------------------------
# THE POOLS THAT FIRE IN BURSTS
# ---------------------------------------------------------------------------

def make_blink(variant: int) -> Samples:
    """A short displacement: air closing, not a whoosh. ~120 ms, because it
    fires on every dash of two classes and anything longer smears across a
    dash chain."""
    seed = 1500 + variant
    inrush = sweep(2600.0 + variant * 400.0, 620.0, 0.09, 26.0, 0.55, curve=2.0)
    snap = transient(0.5, seed, bright=8200.0 - variant * 600.0)
    hush = noise(0.12, 30.0, 0.34, seed + 1, lowpass=2)
    ring = tone(1180.0 + variant * 220.0, 0.10, 40.0, 0.22)
    dur = 0.14
    out = mix(*[_pad(x, dur) for x in (inrush, snap, hush, ring)])
    return normalize(de_click(out, 0.6, 30.0), 0.82)


def make_shadow_cast(variant: int) -> Samples:
    """Downward and swallowed — shadow takes energy out of the room. An inverted
    sweep under low-passed noise, with no bright transient at all, so it sits
    opposite the storm and holy casts in the mix."""
    seed = 1600 + variant
    fall = sweep(520.0 - variant * 60.0, 96.0, 0.42, 6.5, 0.72, curve=1.7)
    breath = noise(0.46, 8.0, 0.40, seed, lowpass=4)
    under = sub_kick(52.0, 33.0, 0.44, 6.0, 0.42)
    dur = 0.52
    out = mix(*[_pad(x, dur) for x in (fall, breath, under)])
    return normalize(de_click(out, 14.0, 90.0), 0.80)


def make_gib(variant: int) -> Samples:
    """A kill. Wet burst then scatter — this one plays on every death and deaths
    CLUSTER, which is exactly when one repeated waveform gives the game away."""
    seed = 1700 + variant
    burst = noise(0.10, 34.0, 0.85, seed, lowpass=1)
    thud = sweep(240.0, 58.0, 0.22, 13.0, 0.62, curve=2.4)
    scatter = noise(0.34, 11.0, 0.34, seed + 1, lowpass=2)
    dur = 0.40
    out = mix(*[_pad(x, dur) for x in (burst, thud, scatter)])
    return normalize(de_click(out, 0.5, 55.0), 0.88)


def make_ding(variant: int) -> Samples:
    """A pickup/confirm. Two-partial bell, tuned a fifth apart on the second
    variant so a double pickup reads as two events rather than a stutter."""
    root = 880.0 if variant == 0 else 1320.0
    a = tone(root, 0.34, 9.0, 0.70)
    b = tone(root * 2.01, 0.30, 13.0, 0.30)
    c = tone(root * 3.02, 0.18, 22.0, 0.13)
    dur = 0.38
    return normalize(de_click(mix(*[_pad(x, dur) for x in (a, b, c)]), 1.0, 70.0), 0.72)


def make_beam_start(variant: int) -> Samples:
    """The beam striking up: a fast rise that ARRIVES, so the sustain loop has
    something to begin under."""
    seed = 1800 + variant
    rise = sweep(180.0, 1500.0 + variant * 260.0, 0.20, 2.2, 0.62, curve=0.7)
    air = noise(0.22, 12.0, 0.34, seed, lowpass=2)
    hit = transient(0.42, seed + 1, bright=6400.0)
    dur = 0.26
    out = mix(*[_pad(x, dur) for x in (rise, air, hit)])
    return normalize(de_click(out, 3.0, 60.0), 0.84)


def make_beam_end(variant: int) -> Samples:
    """The beam letting go: the same shape backwards, shorter, with a snap-off
    so the sustain does not just stop mid-sample."""
    seed = 1850 + variant
    fall = sweep(1400.0 + variant * 200.0, 210.0, 0.20, 7.0, 0.58, curve=1.9)
    snap = transient(0.34, seed, bright=5200.0)
    dust = noise(0.24, 14.0, 0.24, seed + 1, lowpass=3)
    dur = 0.28
    out = mix(*[_pad(x, dur) for x in (fall, snap, dust)])
    return normalize(de_click(out, 0.8, 70.0), 0.78)


JOBS = [
    # (filename, factory, variant) — cannon replaces a borrowed sound; the rest
    # are ADDITIONAL variants for pools that currently hold exactly one sample.
    ("cannon_1.wav", make_cannon, 0),
    ("cannon_2.wav", make_cannon, 1),
    ("blink_2.wav", make_blink, 0),
    ("blink_3.wav", make_blink, 1),
    ("shadow_cast_2.wav", make_shadow_cast, 0),
    ("shadow_cast_3.wav", make_shadow_cast, 1),
    ("gib_2.wav", make_gib, 0),
    ("gib_3.wav", make_gib, 1),
    ("ding_2.wav", make_ding, 0),
    ("ding_3.wav", make_ding, 1),
    ("beam_start_2.wav", make_beam_start, 0),
    ("beam_end_2.wav", make_beam_end, 0),
]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, factory, variant in JOBS:
        path = OUT / name
        samples = factory(variant)
        write_wav_at(path, samples, SAMPLE_RATE)
        print(f"  wrote {name:22s} {len(samples) / SAMPLE_RATE:.2f}s")
    print(f"{len(JOBS)} files -> {OUT}")


if __name__ == "__main__":
    main()
