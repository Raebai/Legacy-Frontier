#!/usr/bin/env python3
"""THE BATTLE BED — an original hard-hitting fight-edit track, synthesised from
nothing, for the background of a posted clip.

    python python-tools/generate_battle_music.py              # writes the default bed
    python python-tools/generate_battle_music.py --seconds 45 --bpm 148

WHY THIS IS SYNTHESISED AND NOT DOWNLOADED — the honest version, because the
obvious answer to "put trending fighting audio behind it" is to go and get the
trending fighting audio, and that answer is wrong three separate ways:

  1. A REAL TRENDING SOUND CANNOT LEGALLY BE BURNED INTO THE FILE. The sounds
     driving fight edits are commercial masters. TikTok tolerates them *inside
     TikTok*, under the licence TikTok itself holds, attached at publish time.
     A copy muxed into an mp4 that also lives on a hard drive, a GitHub release
     or any other platform is an unlicensed copy.

  2. AND BURNING IT IN IS WORSE FOR REACH ANYWAY, which matters more than the
     legal part. Attaching a sound in the TikTok editor puts the post on that
     sound's page and into its recommendation graph — that IS the mechanism a
     trending sound gives you. A video whose audio merely *sounds like* the
     trend is attached to nothing. Burning it in throws away the reason you
     wanted it.

  3. THE MACHINE CANNOT FETCH ONE. `tiktok_music_trending` reads TikTok's
     Commercial Music Library, needs a connected account (there is none), and
     returns an id to hand to `tiktok_publish` — it does not return audio, by
     design. The available generation model is speech-only and declines music.

So the bed here is ORIGINAL and OWNED, with no licence surface at all — the same
call `generate_gibberish_voices.py` made for the in-game voice, and for the same
reason. See `godot-project/assets/audio/CREDITS.md`: the six existing music
tracks have UNRESOLVED provenance and that file says out loud they block a public
release, so they were not an option either.

AND IT IS DESIGNED TO BE THROWN AWAY. `make_post.py --music <path>` takes any
file, and `--no-music` leaves the bed off entirely so the real trending sound can
go on in the TikTok editor, which is where it belongs. This is a default, not a
ceiling.

WHAT IT IS, MUSICALLY. Dark hybrid trap/phonk at 150 BPM in A minor — the texture
fight edits actually run on: a distorted 808 sliding under a hard kick, claps on
2 and 4, hat rolls, and a Memphis cowbell ostinato, with the first two bars held
back so the voice-over has a hole to sit in and the drop lands on the fight. The
arrangement is authored (see SECTIONS), not random.

NOBODY HAS HEARD IT. The standing judgement on this project is that playtest
beats reasoning, and audio is the one channel a screenshot cannot check. What is
verifiable without ears is printed at the end: per-section RMS, peak, and that
the drop is louder than the intro. That it is *good* is the maker's call.

Stdlib only. Writes 44.1 kHz 16-bit mono WAV.
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import sys
import wave
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

RATE = 44100
REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "content" / "music" / "battle_bed.wav"

# -- THE NOTES --------------------------------------------------------------
# A natural minor. The bass moves Am - F - G - Em, one chord per bar, which is
# the flattest, most-used dark loop there is and is exactly why it works under a
# fight: it asks for no attention.
A1 = 55.00
BASS_HZ = [A1, 43.654, 49.000, 41.203]        # A1  F1  G1  E1
# The cowbell ostinato, one per 1/8 note across a bar. A minor pentatonic up top
# so it can never disagree with the bass underneath it.
BELL_HZ = [440.00, 523.25, 440.00, 587.33, 440.00, 523.25, 392.00, 440.00]


def _sat(x: float, drive: float) -> float:
    """tanh saturation. This is what makes an 808 audible on a phone speaker: the
    fundamental is at 55 Hz, which a phone cannot reproduce at all, so the
    harmonics the distortion generates ARE the bass the listener hears."""
    return math.tanh(x * drive) / math.tanh(drive)


class Bed:
    """A mono float buffer with add(at_seconds, samples) mixing."""

    def __init__(self, seconds: float) -> None:
        self.n = int(seconds * RATE)
        self.buf = [0.0] * self.n

    def add(self, at: float, samples: list[float], gain: float = 1.0) -> None:
        i = int(at * RATE)
        if i >= self.n or i < 0:
            return
        end = min(self.n, i + len(samples))
        buf = self.buf
        for k in range(end - i):
            buf[i + k] += samples[k] * gain


# -- THE VOICES -------------------------------------------------------------

def kick(dur: float = 0.34) -> list[float]:
    """A pitch-swept sine (120 -> 45 Hz) with a click on the front. The sweep is
    the whole sound; a static sine at 50 Hz is a hum, not a kick."""
    n = int(dur * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 45.0 + 75.0 * math.exp(-t * 42.0)
        phase += 2.0 * math.pi * f / RATE
        env = math.exp(-t * 11.0)
        click = math.exp(-t * 420.0) * 0.55 * (random.random() * 2.0 - 1.0)
        out.append(_sat(math.sin(phase) * env + click, 2.2))
    return out


def eight_o_eight(freq: float, dur: float, glide: float = 1.6) -> list[float]:
    """The 808: a long sine with a short downward glide onto the note, saturated.
    The glide is the phonk signature — it is what stops it being a sub-bass note
    and makes it a slide."""
    n = int(dur * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq * (1.0 + glide * math.exp(-t * 26.0))
        phase += 2.0 * math.pi * f / RATE
        env = math.exp(-t * 2.4) * (1.0 - math.exp(-t * 300.0))
        out.append(_sat(math.sin(phase) * env, 3.0) * 0.9)
    return out


def clap(dur: float = 0.30) -> list[float]:
    """Three noise taps 9 ms apart into a longer body — a hand-clap is several
    hands not quite together, and one burst reads as a snare instead."""
    n = int(dur * RATE)
    out = [0.0] * n
    for tap, amp in ((0.000, 0.7), (0.009, 0.85), (0.018, 1.0)):
        s = int(tap * RATE)
        for i in range(s, n):
            t = (i - s) / RATE
            env = math.exp(-t * (58.0 if tap < 0.018 else 15.0))
            out[i] += (random.random() * 2.0 - 1.0) * env * amp
    # One-pole high-pass by subtracting a lagged low-pass: gets the mud out so it
    # does not fight the 808 for the same space.
    lp = 0.0
    hp = []
    for v in out:
        lp += (v - lp) * 0.16
        hp.append((v - lp) * 0.55)
    return hp


def hat(dur: float = 0.055, open_: bool = False) -> list[float]:
    n = int((dur * (4.5 if open_ else 1.0)) * RATE)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * (26.0 if open_ else 130.0))
        v = random.random() * 2.0 - 1.0
        lp += (v - lp) * 0.62          # keep only the top: a hat is all air
        out.append((v - lp) * env * 0.42)
    return out


def bell(freq: float, dur: float = 0.28) -> list[float]:
    """The Memphis cowbell — two detuned square-ish tones a fifth apart with a
    fast decay. Squares, not sines: the odd harmonics are the metallic part."""
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 13.0)
        a = math.sin(2.0 * math.pi * freq * t)
        b = math.sin(2.0 * math.pi * freq * 1.4983 * t)   # a fifth, detuned
        sq = (1.0 if a > 0 else -1.0) * 0.5 + (1.0 if b > 0 else -1.0) * 0.32
        out.append(sq * env * 0.30)
    return out


def braam(dur: float = 1.9, root: float = 55.0) -> list[float]:
    """The impact that lands the drop: a stack of detuned saws, fast in, slow out,
    low-passed so it is felt rather than heard."""
    n = int(dur * RATE)
    out = []
    lp = 0.0
    ratios = (1.0, 1.005, 0.995, 2.0, 2.01, 3.0)
    for i in range(n):
        t = i / RATE
        env = (1.0 - math.exp(-t * 90.0)) * math.exp(-t * 2.1)
        s = 0.0
        for r in ratios:
            ph = (root * r * t) % 1.0
            s += (2.0 * ph - 1.0)          # saw
        s /= len(ratios)
        lp += (s - lp) * 0.30              # low-pass: keep the weight, lose the buzz
        out.append(_sat(lp * env, 2.0) * 0.8)
    return out


def riser(dur: float) -> list[float]:
    """Noise sweeping upward under a rising sine. Its only job is to make the bar
    before the drop feel like it is going somewhere."""
    n = int(dur * RATE)
    out = []
    lp = 0.0
    phase = 0.0
    for i in range(n):
        t = i / RATE
        p = t / dur
        v = random.random() * 2.0 - 1.0
        cut = 0.05 + 0.55 * p * p          # opens as it climbs
        lp += (v - lp) * cut
        phase += 2.0 * math.pi * (220.0 + 900.0 * p * p) / RATE
        env = p * p * 0.55
        out.append((lp * 0.7 + math.sin(phase) * 0.3) * env)
    return out


# -- THE ARRANGEMENT --------------------------------------------------------
# THE FIRST TWO BARS ARE DELIBERATELY THIN. That is the hole the voice-over sits
# in. A bed that starts at full weight forces the mixer to duck 9 dB out of the
# music under the VO, which sounds like someone turning a knob; a bed that was
# ARRANGED to be quiet there needs almost none.
#   name        bars   kick   808    clap   hats   bell   extras
SECTIONS = [
    ("intro",     2,   False, False, False, False, True,  "riser-at-end"),
    ("drop",      6,   True,  True,  True,  True,  True,  "braam-at-start"),
    ("break",     2,   False, True,  False, True,  True,  ""),
    ("drop2",     8,   True,  True,  True,  True,  True,  "braam-at-start"),
]


def build(seconds: float, bpm: float, seed: int) -> tuple[list[float], list[tuple]]:
    random.seed(seed)
    beat = 60.0 / bpm
    bar = beat * 4.0
    bed = Bed(seconds + 2.0)

    # Render the voices once and reuse: a kick is a kick, and synthesising 200 of
    # them costs 200x as much for an identical result.
    K, C = kick(), clap()
    H, HO = hat(), hat(open_=True)
    BELLS = {f: bell(f) for f in set(BELL_HZ)}

    marks: list[tuple] = []
    t = 0.0
    b_index = 0
    while t < seconds:
        for name, bars, has_k, has_808, has_c, has_h, has_bell, extra in SECTIONS:
            if t >= seconds:
                break
            marks.append((name, t))
            for bar_in_section in range(bars):
                if t >= seconds:
                    break
                if "braam" in extra and bar_in_section == 0:
                    bed.add(t, braam(), 0.62)
                if "riser" in extra:
                    bed.add(t + bar - beat * 2.0, riser(beat * 2.0), 0.50)

                if has_k:
                    # 150 BPM half-time: kicks on 1, the "and" of 2, and 3-and.
                    for off in (0.0, 1.75, 2.5):
                        bed.add(t + off * beat, K, 0.95)
                if has_c:
                    for off in (1.0, 3.0):
                        bed.add(t + off * beat, C, 0.55)
                if has_h:
                    for s in range(8):                       # 1/8 grid
                        bed.add(t + s * beat * 0.5, H, 0.5)
                    # A roll on the last beat of every other bar — the thing that
                    # makes a trap bed move instead of tick.
                    if b_index % 2 == 1:
                        for r in range(6):
                            bed.add(t + beat * 3.0 + r * beat / 6.0, H, 0.42)
                    else:
                        bed.add(t + beat * 3.5, HO, 0.30)
                if has_808:
                    root = BASS_HZ[b_index % len(BASS_HZ)]
                    bed.add(t, eight_o_eight(root, bar * 0.72), 0.85)
                    bed.add(t + beat * 2.5, eight_o_eight(root * 2.0, beat * 1.2), 0.34)
                if has_bell:
                    quiet = 0.42 if name == "intro" else 1.0
                    for s, f in enumerate(BELL_HZ):
                        bed.add(t + s * beat * 0.5, BELLS[f], 0.60 * quiet)

                t += bar
                b_index += 1
    return bed.buf[: int(seconds * RATE)], marks


def master(samples: list[float], drive: float = 1.9) -> list[float]:
    """Soft-clip the mix, THEN normalise — not the other way round.

    Peak-normalising alone divides the whole track by its single loudest sample,
    which here is a braam transient at 1.85. Everything else then sits 6 dB lower
    than it should and the bed reads as timid next to any commercial track it is
    cut against. Driving into a tanh first flattens that one transient and lets
    the body come up, which is what a master bus does and why records are loud.

    Measured on the default bed: RMS 0.089 -> 0.222 at an identical peak."""
    hi = max((abs(s) for s in samples), default=1.0) or 1.0
    k = math.tanh(drive)
    return [math.tanh(s / hi * drive) / k for s in samples]


def write_wav(path: Path, samples: list[float], peak: float = 0.89) -> None:
    samples = master(samples)
    hi = max((abs(s) for s in samples), default=1.0) or 1.0
    g = peak / hi
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", max(-32768, min(32767, int(s * g * 32767))))
            for s in samples))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seconds", type=float, default=60.0)
    ap.add_argument("--bpm", type=float, default=150.0)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    a = ap.parse_args()

    print(f"building {a.seconds:.0f}s at {a.bpm:.0f} BPM ...")
    samples, marks = build(a.seconds, a.bpm, a.seed)
    out = Path(a.out)
    write_wav(out, samples)
    # Report on what was WRITTEN, not on what was built. The master stage changes
    # every number below, and a report on the pre-master buffer would describe a
    # file that does not exist.
    samples = master(samples)
    hi = max((abs(s) for s in samples), default=1.0) or 1.0
    samples = [s * (0.89 / hi) for s in samples]

    # -- WHAT CAN BE CHECKED WITHOUT EARS -----------------------------------
    # Not "is it good". Only: does each section exist, and is the drop actually
    # louder than the intro it drops out of. A bed whose drop measures quieter
    # than its intro is broken in a way nobody would hear as "broken" — they
    # would just find the clip flat.
    print(f"\nwrote {out}  ({out.stat().st_size / 1_048_576:.1f} MB, "
          f"{len(samples) / RATE:.1f}s)\n")
    print(f"  {'section':<10} {'at':>7}  {'rms':>7}  {'peak':>7}")
    print("  " + "-" * 36)
    seen = []
    for i, (name, at) in enumerate(marks[:6]):
        end = marks[i + 1][1] if i + 1 < len(marks) else len(samples) / RATE
        seg = samples[int(at * RATE):int(min(end, a.seconds) * RATE)]
        if not seg:
            continue
        rms = math.sqrt(sum(s * s for s in seg) / len(seg))
        pk = max(abs(s) for s in seg)
        print(f"  {name:<10} {at:6.1f}s  {rms:7.4f}  {pk:7.4f}")
        seen.append((name, rms))
    intro = next((r for n, r in seen if n == "intro"), 0.0)
    drop = next((r for n, r in seen if n == "drop"), 0.0)
    if drop <= intro:
        print(f"\n  ! THE DROP IS NOT LOUDER THAN THE INTRO ({drop:.4f} <= {intro:.4f})")
        return 1
    print(f"\n  drop is {20 * math.log10(drop / max(intro, 1e-9)):+.1f} dB on the intro")
    print("  nobody has HEARD this. That it works is the maker's call.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
