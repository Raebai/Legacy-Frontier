"""
Generate combat/movement SFX using stdlib only (no numpy/scipy).

Design principle (per docs/references/stick-fight-feel-study.md §5): every impact
is layered from THREE parts so it reads as a physical event, not a beep —
  1. TRANSIENT / attack  — a bright click/crack/snap (<30 ms) that sells contact.
  2. BODY                — the tone/character (thud, boom, zap) 50-150 ms.
  3. TAIL                — a short decay/debris/sparkle that gives it size.
Big events (blast) add a 4th SUB-BASS layer (~40-90 Hz pitch-dropping sine) for
weight on real speakers. Each impact sound is written as 2-3 VARIANTS (different
noise seed + slight pitch jitter) so repeated hits don't machine-gun the same
sample — Sfx.gd rotates them and adds ±pitch on top.

All output is 16-bit PCM mono WAV at 44100 Hz into godot-project/assets/audio/sfx/.
Deterministic: every stochastic layer seeds its own random.Random(n).
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
TAU = 2.0 * math.pi

Samples = list[float]


# ---------------------------------------------------------------------------
# WAV IO
# ---------------------------------------------------------------------------

def write_wav(path: Path, samples: Samples) -> None:
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


def normalize(samples: Samples, peak: float) -> Samples:
    """Scale so the loudest sample sits at `peak` of full scale."""
    loudest = max((abs(s) for s in samples), default=0.0)
    if loudest == 0.0:
        return samples
    gain = peak / loudest
    return [s * gain for s in samples]


# ---------------------------------------------------------------------------
# Shared synth primitives (the layering toolkit)
# ---------------------------------------------------------------------------

def _n(dur: float) -> int:
    return int(SAMPLE_RATE * dur)


def mix(*layers: Samples) -> Samples:
    """Sum layers of possibly different lengths (pad to the longest)."""
    length = max((len(l) for l in layers), default=0)
    out = [0.0] * length
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def de_click(samples: Samples, attack_ms: float = 1.5, release_ms: float = 8.0) -> Samples:
    """Linear fade the head/tail so onsets/offsets never click."""
    length = len(samples)
    a = max(1, _n(attack_ms / 1000.0))
    r = max(1, _n(release_ms / 1000.0))
    for i in range(min(a, length)):
        samples[i] *= i / a
    for i in range(min(r, length)):
        samples[length - 1 - i] *= i / r
    return samples


def tone(freq: float, dur: float, decay: float, amp: float = 1.0, phase0: float = 0.0) -> Samples:
    """A single exponentially-decaying sine."""
    length = _n(dur)
    return [
        amp * math.exp(-decay * (i / SAMPLE_RATE)) * math.sin(TAU * freq * (i / SAMPLE_RATE) + phase0)
        for i in range(length)
    ]


def partials(base: float, spec: list[tuple[float, float, float]], dur: float) -> Samples:
    """Inharmonic partial stack -> metallic/energetic body & tail.
    `spec` = list of (freq_multiplier, amplitude, decay_per_second)."""
    length = _n(dur)
    out = [0.0] * length
    for ratio, amp, decay in spec:
        f = base * ratio
        for i in range(length):
            t = i / SAMPLE_RATE
            out[i] += amp * math.exp(-decay * t) * math.sin(TAU * f * t)
    return out


def noise(dur: float, decay: float, amp: float = 1.0, seed: int = 0, lowpass: int = 1) -> Samples:
    """Exponentially-decaying noise. `lowpass` = number of adjacent-average
    passes (0 = raw white crack, 3 = soft airy hiss)."""
    length = _n(dur)
    rng = random.Random(seed)
    raw = [rng.uniform(-1.0, 1.0) for _ in range(length)]
    for _ in range(max(0, lowpass)):
        raw = [(raw[i] + raw[i - 1]) / 2.0 if i > 0 else raw[0] for i in range(length)]
    return [amp * math.exp(-decay * (i / SAMPLE_RATE)) * raw[i] for i in range(length)]


def sweep(f0: float, f1: float, dur: float, decay: float, amp: float = 1.0, curve: float = 2.0) -> Samples:
    """Pitch sweep f0->f1 via integrated phase (click-free)."""
    length = _n(dur)
    out: Samples = []
    phase = 0.0
    for i in range(length):
        u = i / length if length else 0.0
        f = f0 + (f1 - f0) * (u ** curve)
        phase += TAU * f / SAMPLE_RATE
        t = i / SAMPLE_RATE
        out.append(amp * math.exp(-decay * t) * math.sin(phase))
    return out


def sub_kick(f0: float, f1: float, dur: float, decay: float, amp: float = 1.0) -> Samples:
    """Deep pitch-dropping sine (weight layer for big hits)."""
    return sweep(f0, f1, dur, decay, amp, curve=1.0)


def transient(amp: float, seed: int, bright: float = 6000.0) -> Samples:
    """A very short (~14 ms) bright crack: raw noise + a high sine ping.
    This is the 'contact' layer that grabs attention."""
    dur = 0.014
    length = _n(dur)
    crack = noise(dur, 500.0, amp, seed, lowpass=0)
    ping = tone(bright, dur, 260.0, amp * 0.5)
    return [crack[i] + ping[i] for i in range(length)]


def whoosh(dur: float, seed: int, amp: float = 0.7, sweep_hz: tuple[float, float] = (900.0, 300.0)) -> Samples:
    """Air swish: soft noise under a rise-then-fall (hann) envelope, no
    transient. For melee windups / dashes."""
    length = _n(dur)
    body = noise(dur, 0.0, 1.0, seed, lowpass=3)
    swept = sweep(sweep_hz[0], sweep_hz[1], dur, 0.0, 1.0, curve=1.4)
    out: Samples = []
    for i in range(length):
        u = i / length if length else 0.0
        env = math.sin(math.pi * u)  # 0 -> 1 -> 0
        out.append(amp * env * (0.75 * body[i] + 0.25 * swept[i]))
    return out


# ---------------------------------------------------------------------------
# Impact sounds (transient + body + tail, with variants)
# ---------------------------------------------------------------------------

def make_spell_impact(variant: int) -> Samples:
    """Arcane bolt hit: a crisp electric zap. Transient crack -> a short tonal
    zap body (inharmonic so it reads energetic, not musical) -> sparkle tail."""
    seed = 100 + variant
    base = 500.0 + variant * 45.0
    t = transient(0.7, seed, bright=7000.0 - variant * 400.0)
    body = mix(
        tone(base, 0.09, 40.0, 0.7),
        partials(base * 1.3, [(1.0, 0.5, 44.0), (1.9, 0.3, 60.0)], 0.08),
    )
    tail = noise(0.13, 20.0, 0.28, seed + 1, lowpass=2)
    return normalize(de_click(mix(t, body, tail), 0.5, 10.0), 0.82)


def make_melee_hit(variant: int) -> Samples:
    """Fist/weapon connect: hard snap transient -> low thud body -> tight tail.
    Punchier and lower than the spell zap so melee reads as blunt force."""
    seed = 200 + variant
    t = transient(0.85, seed, bright=4200.0)
    body = mix(
        tone(165.0 - variant * 10.0, 0.08, 42.0, 0.9),
        tone(92.0, 0.10, 30.0, 0.5),
    )
    tail = noise(0.06, 42.0, 0.24, seed + 3, lowpass=1)
    return normalize(de_click(mix(t, body, tail), 0.8, 8.0), 0.9)


def make_enemy_death(variant: int) -> Samples:
    """Death/destruction: a descending tone that deflates + a crumble tail +
    a little sub for body. Reads as 'thing comes apart'."""
    seed = 300 + variant
    down = sweep(300.0 - variant * 20.0, 90.0, 0.34, 6.0, 0.7, curve=1.5)
    crumble = noise(0.30, 9.0, 0.42, seed, lowpass=2)
    sub = sub_kick(80.0, 48.0, 0.24, 11.0, 0.5)
    return normalize(de_click(mix(down, crumble, sub), 1.0, 14.0), 0.82)


def make_hero_hurt(variant: int) -> Samples:
    """Player takes damage: a short filtered 'oof' — a low body tone under a
    band of soft noise, with a tiny transient so it lands on the frame."""
    seed = 400 + variant
    t = transient(0.35, seed, bright=3000.0)
    body = tone(210.0 - variant * 25.0, 0.12, 18.0, 0.6)
    grit = noise(0.13, 20.0, 0.5, seed + 2, lowpass=2)
    return normalize(de_click(mix(t, body, grit), 1.0, 12.0), 0.78)


def make_blast(variant: int) -> Samples:
    """Big AoE detonation: bright crack transient -> booming inharmonic body ->
    deep SUB-BASS pitch-drop for weight -> a long lingering rumble/debris tail
    (permanence). The loudest, heaviest sound in the kit."""
    seed = 500 + variant
    t = transient(0.9, seed, bright=5000.0)
    boom = partials(120.0 - variant * 8.0, [(1.0, 1.0, 10.0), (1.7, 0.5, 16.0), (2.5, 0.3, 22.0)], 0.42)
    sub = sub_kick(95.0, 38.0, 0.5, 6.0, 1.0)
    rumble = noise(0.6, 5.0, 0.5, seed + 4, lowpass=3)  # lingers ~0.6 s
    return normalize(de_click(mix(t, boom, sub, rumble), 1.0, 30.0), 0.97)


def make_cast(variant: int) -> Samples:
    """Spell cast start: a rising magical shimmer — a pitch sweep up + a soft
    bell + airy noise. No hard transient (it's a wind-up, not a hit)."""
    seed = 600 + variant
    rise = sweep(300.0, 1200.0 + variant * 120.0, 0.22, 8.0, 0.5, curve=2.0)
    bell = partials(660.0, [(1.0, 0.4, 12.0), (2.4, 0.2, 20.0)], 0.2)
    air = noise(0.2, 10.0, 0.2, seed, lowpass=2)
    return normalize(de_click(mix(rise, bell, air), 4.0, 16.0), 0.72)


def make_melee_swing(variant: int) -> Samples:
    """Punch/kick windup whoosh — pure air, no contact."""
    seed = 700 + variant
    return normalize(de_click(whoosh(0.14, seed, 0.7, (1000.0 - variant * 150.0, 320.0)), 4.0, 16.0), 0.6)


# ---------------------------------------------------------------------------
# Movement / cue sounds (single, kept from the original synth)
# ---------------------------------------------------------------------------

def make_ding() -> Samples:
    """Bright parry/clean-hit ding: a fundamental plus inharmonic bell-like
    partials (ratios off the harmonic series so it reads as metal, not an
    organ), each with its own exponential decay. ~2 ms attack removes the
    onset click; the whole thing rings then fades."""
    fundamental = 1500.0
    body = partials(fundamental, [(1.00, 1.00, 12.0), (2.76, 0.55, 18.0), (5.40, 0.30, 26.0)], 0.28)
    return normalize(de_click(body, 2.0, 10.0), 0.85)


def make_footstep() -> Samples:
    """Soft footstep thump: a ~95 Hz sine body plus a short scuff of low-passed
    noise. Very fast decay keeps it percussive."""
    thump = tone(95.0, 0.09, 45.0, 0.9)
    scuff = noise(0.09, 70.0, 0.35, 42, lowpass=1)
    return normalize(de_click(mix(thump, scuff), 1.0, 6.0), 0.55)


def make_blink() -> Samples:
    """Shadow-blink teleport, epic read. Charge whoosh swells -> a bright
    inharmonic arrival bell + a low sub thump land the step -> airy sparkle
    tail. Contour: swell -> bright hit + boom -> shimmer."""
    duration = 0.34
    n = _n(duration)
    rng = random.Random(7)
    arrival = 0.40
    bell_base = 880.0
    bell_partials = [(1.00, 1.00, 11.0), (2.03, 0.55, 17.0), (3.87, 0.30, 25.0)]
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    smoothed = [(raw[i] + raw[i - 1]) / 2.0 if i > 0 else raw[0] for i in range(n)]
    attack_samples = _n(0.003)
    release_samples = _n(0.040)
    samples: Samples = []
    phase = 0.0
    for i in range(n):
        u = i / n
        s = 0.0
        if u < arrival:
            v = u / arrival
            freq = 240.0 + 1300.0 * (v * v)
            phase += TAU * freq / SAMPLE_RATE
            s += 0.42 * v * math.sin(phase)
            s += 0.38 * (v * v) * smoothed[i]
        else:
            phase += TAU * 1500.0 / SAMPLE_RATE
        if u >= arrival:
            ta = (u - arrival) * duration
            bell = 0.0
            for ratio, amp, decay in bell_partials:
                bell += amp * math.exp(-decay * ta) * math.sin(TAU * bell_base * ratio * ta)
            s += 0.72 * bell
            s += 0.60 * math.exp(-26.0 * ta) * math.sin(TAU * 70.0 * ta)
            s += 0.16 * math.exp(-15.0 * ta) * smoothed[i]
        if i < attack_samples:
            s *= i / attack_samples
        if i >= n - release_samples:
            s *= (n - i) / release_samples
        samples.append(s)
    return normalize(samples, 0.82)


# ---------------------------------------------------------------------------
# Anime ABILITY sounds — one per ability family (charge-up, beam, cannon, zap,
# ice, earth, holy, nova). The maker's "cool anime sound effects ... charge up
# for a beam ... crazy cannon abilities" ask, synthesized from the same toolkit.
# ---------------------------------------------------------------------------

def make_charge_up(variant: int) -> Samples:
    """Anime beam/ult CHARGE-UP: a long swelling rise — pitch sweeps UP while the
    amplitude swells, over a shimmering bell + building airy hiss. The 'powering
    up' before a beam/ultimate fires."""
    seed = 800 + variant
    dur = 0.9
    n = _n(dur)
    rise = sweep(180.0, 900.0 + variant * 80.0, dur, 0.0, 1.0, curve=2.2)
    shimmer = partials(440.0, [(1.0, 0.3, 1.5), (2.01, 0.2, 2.0), (3.0, 0.15, 2.5)], dur)
    air = noise(dur, 0.0, 1.0, seed, lowpass=3)
    out = [((i / n) ** 2) * (0.5 * rise[i] + 0.3 * shimmer[i] + 0.25 * air[i]) for i in range(n)]
    return normalize(de_click(out, 6.0, 40.0), 0.72)


def make_beam(variant: int) -> Samples:
    """Magic BEAM discharge (Zoltraak): a sharp fire transient + a bright sustained
    laser tone + a downward sweep. The 'PSHOOM' of a screen-crossing beam."""
    seed = 810 + variant
    t = transient(0.8, seed, bright=6500.0)
    laser = mix(
        tone(1400.0 - variant * 100.0, 0.28, 8.0, 0.6),
        partials(700.0, [(1.0, 0.4, 6.0), (2.5, 0.25, 10.0), (4.0, 0.15, 14.0)], 0.28),
    )
    swoosh = sweep(1800.0, 500.0, 0.3, 5.0, 0.4, curve=1.5)
    tail = noise(0.3, 8.0, 0.25, seed + 2, lowpass=1)
    return normalize(de_click(mix(t, laser, swoosh, tail), 1.0, 22.0), 0.9)


def make_cannon(variant: int) -> Samples:
    """The 'crazy cannon' ULTIMATE boom — bigger + deeper than blast: a massive
    crack, a huge inharmonic boom, a very deep long sub, a long rolling tail."""
    seed = 820 + variant
    t = transient(1.0, seed, bright=4500.0)
    boom = partials(85.0 - variant * 5.0, [(1.0, 1.0, 7.0), (1.6, 0.6, 11.0), (2.4, 0.35, 16.0)], 0.6)
    sub = sub_kick(110.0, 30.0, 0.7, 4.0, 1.0)
    roll = noise(0.8, 3.5, 0.55, seed + 4, lowpass=3)
    return normalize(de_click(mix(t, boom, sub, roll), 1.0, 45.0), 1.0)


def make_zap(variant: int) -> Samples:
    """Lightning ZAP (chidori / chain): a crackling electric snap — sharp transient +
    fast raw high crackle + a buzzing inharmonic body."""
    seed = 830 + variant
    t = transient(0.9, seed, bright=8000.0 - variant * 300.0)
    crackle = noise(0.22, 30.0, 0.6, seed, lowpass=0)  # raw = electric
    buzz = mix(
        tone(2200.0, 0.14, 30.0, 0.4),
        partials(900.0, [(1.0, 0.4, 22.0), (2.7, 0.3, 30.0), (4.3, 0.2, 40.0)], 0.14),
    )
    return normalize(de_click(mix(t, crackle, buzz), 0.5, 16.0), 0.88)


def make_ice(variant: int) -> Samples:
    """ICE crystal shatter/form: a bright glassy inharmonic tinkle + a frosty
    crackle. Reads crystalline + cold."""
    seed = 840 + variant
    t = transient(0.6, seed, bright=9000.0)
    glass = partials(1800.0, [(1.0, 0.5, 10.0), (1.5, 0.35, 14.0), (2.3, 0.25, 18.0), (3.1, 0.15, 24.0)], 0.3)
    tinkle = noise(0.3, 12.0, 0.3, seed + 1, lowpass=1)
    return normalize(de_click(mix(t, glass, tinkle), 0.5, 18.0), 0.82)


def make_earth(variant: int) -> Samples:
    """EARTH rumble: a heavy low thud + a gravelly crumble + a deep sub — rock/
    stone erupting."""
    seed = 850 + variant
    t = transient(0.7, seed, bright=2500.0)
    thud = tone(75.0, 0.3, 12.0, 0.9)
    gravel = noise(0.4, 7.0, 0.55, seed, lowpass=2)
    sub = sub_kick(70.0, 34.0, 0.35, 8.0, 0.7)
    return normalize(de_click(mix(t, thud, gravel, sub), 1.0, 26.0), 0.9)


def make_holy(variant: int = 0) -> Samples:
    """HOLY radiant chord: a bright shimmering bell chord + an airy rising swell —
    divine / angelic."""
    seed = 860 + variant
    chord = partials(523.0, [(1.0, 0.5, 3.0), (1.5, 0.4, 4.0), (2.0, 0.35, 5.0), (3.0, 0.2, 6.0)], 0.5)
    shimmer = sweep(800.0, 2000.0, 0.5, 2.0, 0.3, curve=2.0)
    air = noise(0.5, 4.0, 0.25, seed, lowpass=3)
    return normalize(de_click(mix(chord, shimmer, air), 8.0, 45.0), 0.78)


def make_nova(variant: int) -> Samples:
    """NOVA expanding pulse: a swell-in then a released whoomph + deep sub — the
    'get off me' shockwave."""
    seed = 870 + variant
    n = _n(0.4)
    swell = sweep(200.0, 700.0, 0.4, 0.0, 1.0, curve=2.0)
    sub = sub_kick(120.0, 40.0, 0.4, 5.0, 0.9)
    air = noise(0.4, 6.0, 0.4, seed, lowpass=2)
    out = [math.sin(math.pi * (i / n)) * (0.5 * swell[i] + 0.3 * air[i]) + 0.6 * sub[i] for i in range(n)]
    return normalize(de_click(out, 3.0, 22.0), 0.9)


# ---------------------------------------------------------------------------
# Main — write single cues + multi-variant impacts
# ---------------------------------------------------------------------------

# key -> (maker, variant_count). variant_count == 1 writes "<key>.wav";
# >1 writes "<key>_1.wav".."<key>_N.wav" (Sfx.gd rotates through them).
SOUND_SET: dict[str, tuple] = {
    "spell_impact": (make_spell_impact, 3),
    "melee_hit": (make_melee_hit, 3),
    "melee_swing": (make_melee_swing, 2),
    "enemy_death": (make_enemy_death, 2),
    "hero_hurt": (make_hero_hurt, 2),
    "blast": (make_blast, 2),
    "cast": (make_cast, 2),
    "ding": (make_ding, 1),
    "footstep": (make_footstep, 1),
    "blink": (make_blink, 1),
    # Anime ability sounds (one per ability family).
    "charge_up": (make_charge_up, 2),
    "beam": (make_beam, 2),
    "cannon": (make_cannon, 2),
    "zap": (make_zap, 2),
    "ice": (make_ice, 2),
    "earth": (make_earth, 2),
    "holy": (make_holy, 1),
    "nova": (make_nova, 2),
}


def main() -> None:
    out_dir = Path(__file__).resolve().parent.parent / "godot-project" / "assets" / "audio" / "sfx"
    total = 0
    for key, (maker, count) in SOUND_SET.items():
        if count == 1:
            path = out_dir / f"{key}.wav"
            write_wav(path, maker())
            print(f"Wrote {path.name} ({path.stat().st_size} bytes)")
            total += 1
        else:
            for v in range(count):
                path = out_dir / f"{key}_{v + 1}.wav"
                write_wav(path, maker(v))
                print(f"Wrote {path.name} ({path.stat().st_size} bytes)")
                total += 1
    print(f"Done: {total} SFX files.")


if __name__ == "__main__":
    main()
