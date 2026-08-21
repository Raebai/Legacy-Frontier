#!/usr/bin/env python3
"""The VOICE-OVER WORD BANK — generate the words once, stitch every matchup forever.

    python python-tools/vo_bank.py --plan              # what to generate, and why
    python python-tools/vo_bank.py --ingest raw/*.mp3  # fold generated audio into the bank
    python python-tools/vo_bank.py --list              # what the bank holds / still needs
    python python-tools/vo_bank.py shadowblade cryomancer
    python python-tools/vo_bank.py --all               # every ordered pairing

WHY A BANK AND NOT ONE GENERATION PER CLIP
------------------------------------------
Nine classes make **72 ordered pairings**. Generating "Shadowblade versus
Cryomancer — who will win?" as a single line means 72 generations, 72 chances for
the narrator to drift in tone, and a full re-generation every time a class is
renamed or a tenth is added.

Banking the WORDS instead means **eleven clips cover all seventy-two**: nine class
names, one "versus", one "who will win". Adding a tenth class costs ONE clip and
unlocks EIGHTEEN new pairings. Renaming one costs one clip. The narrator cannot
drift between matchups because it is literally the same recording of "versus"
every time — which is the thing that makes a series sound like a series.

    9 names + "versus" + "who will win"  =  11 clips  ->  72 matchups
    one line per matchup                 =  72 clips  ->  72 matchups

⚠ THE TRAP THIS FILE EXISTS TO REMOVE: RAW CONCATENATION STAGGERS.
Text-to-speech returns each word with its own leading silence (often 80-200 ms of
it), its own trailing tail, and its own loudness. Glue those together untouched and
the rhythm limps — long pause before one name, none before the next, and the second
half louder than the first. It sounds like three clips stapled together, because it
is. So every part is **onset-trimmed, tail-trimmed, fade-edged and level-matched**
on the way into the bank, and the gaps between words are AUTHORED here rather than
inherited from whatever the model happened to emit. That is the whole difference
between "a word bank" and "three files played in a row".

PROSODY POSITIONS (optional, and deliberately not required to start).
A name in the first slot rises slightly; a name before a pause falls slightly. The
bank supports `<class>.lead` and `<class>.tail` variants for that, and falls back to
the plain `<class>` clip when a variant is absent. Start with the eleven neutral
clips, LISTEN, and only spend on the nine tail variants if the neutral read sounds
mechanical. Do not buy prosody you cannot hear.

⚠ THIS IS A MARKETING ASSET AND IT LIVES OUTSIDE THE GAME.
The bank sits in `content/vo/`, NOT in `godot-project/`, so it can never be swept
into an export pack. The characters' in-game voice is `Gibberish` (Animal-Crossing
animalese) and stays that way on purpose — see python-tools/generate_gibberish_voices.py:
no licence surface, no localisation, more characterful on a stick figure than real VO.
The epic narrator is burned into the CLIP in post. It never enters the build.

Stdlib + wavkit. ffmpeg is used only to decode non-WAV input on ingest.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wavkit  # noqa: E402  (local module, path set above)

# Windows' default cp1252 stdout chokes on the em-dashes and arrows below. The
# repo has been bitten by this in inspect_npc_memory.py and playtest_notes.py.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
BANK_DIR = REPO_ROOT / "content" / "vo" / "bank"
OUT_DIR = REPO_ROOT / "content" / "vo" / "out"
## The un-conditioned TTS output, kept so a part can be re-derived without a re-generation.
RAW_DIR = REPO_ROOT / "content" / "vo" / "raw"

# ⚠ ORDER AND SPELLING MUST TRACK ClassInfo.gd / Hero.CLASS_NAMES (0 Arcanist .. 8
# Swordsaint). A name that drifts here produces a clip that says the wrong class,
# which is the one error nobody notices until it is posted.
CLASSES: list[str] = [
    "Arcanist",
    "Brawler",
    "Cleric",
    "Cryomancer",
    "Juggernaut",
    "Shadowblade",
    "Stormcaller",
    "Swordsaint",
    "Warlock",
]

# The two fixed parts every line shares.
CONNECTOR_SLUG = "versus"
CONNECTOR_TEXT = "versus"
TAIL_SLUG = "who_will_win"
TAIL_TEXT = "who will win?"

# ── AUTHORED RHYTHM ─────────────────────────────────────────────────────────
# Silence inserted BETWEEN parts, in seconds. These are the knobs that make the
# line breathe; they are authored rather than inherited because TTS gaps are
# whatever the model felt like. Tuned by ear, overridable from the CLI.
GAP_BEFORE_CONNECTOR = 0.10   # Shadowblade ^ versus
GAP_AFTER_CONNECTOR = 0.10    # versus ^ Cryomancer
GAP_BEFORE_TAIL = 0.34        # Cryomancer ^ who will win?   (the beat that sells it)

# Edge fades, in seconds. Without these a hard trim clicks on every splice.
EDGE_FADE = 0.008
# Silence below this amplitude is considered leading/trailing dead air.
TRIM_THRESHOLD = 0.02
# Every part is normalised to this peak so no word is louder than its neighbours.
PART_PEAK = 0.85
# The assembled line is normalised once more, a touch below full scale.
LINE_PEAK = 0.92


def slug(name: str) -> str:
    """`Shadowblade` -> `shadowblade`. The bank is keyed by slug, not display name."""
    return name.strip().lower().replace(" ", "_")


# ---------------------------------------------------------------------------
# Plan — what to generate
# ---------------------------------------------------------------------------

def cmd_plan() -> int:
    """Print the exact lines to feed a text-to-speech batch, and the filename each
    must come back as. The filename is the contract: `--ingest` keys off it."""
    print("VO WORD BANK — GENERATION PLAN")
    print("=" * 74)
    print(f"{len(CLASSES)} classes + 2 fixed parts = {len(CLASSES) + 2} clips")
    print(f"covering {len(CLASSES) * (len(CLASSES) - 1)} ordered matchups\n")
    print("Generate each line SEPARATELY, with the same voice and the same")
    print("delivery. Save each as the filename shown; then run --ingest.\n")
    print(f"{'FILENAME':<28} {'SPOKEN TEXT'}")
    print("-" * 74)
    for name in CLASSES:
        print(f"{slug(name) + '.wav':<28} {name}")
    print(f"{CONNECTOR_SLUG + '.wav':<28} {CONNECTOR_TEXT}")
    print(f"{TAIL_SLUG + '.wav':<28} {TAIL_TEXT}")
    print("-" * 74)
    print("\nOPTIONAL prosody variants — only if the neutral read sounds mechanical:")
    print(f"  <class>.lead.wav   spoken as a sentence opener (slight rise)")
    print(f"  <class>.tail.wav   spoken before a pause (slight fall)")
    print("The assembler falls back to the neutral clip when a variant is absent,")
    print("so the bank works fully without ever generating one.")
    print(f"\nDrop generated files anywhere, then:  --ingest <paths...>")
    print(f"Bank lives at: {BANK_DIR}")
    return 0


# ---------------------------------------------------------------------------
# Ingest — fold generated audio into the bank
# ---------------------------------------------------------------------------

def _decode_to_wav(src: Path, dst: Path) -> None:
    """Decode any audio file to 44.1k mono 16-bit WAV via ffmpeg.

    wavkit reads WAV only, and text-to-speech services return mp3 by default, so
    this is the one place a non-stdlib tool is needed. It is a decode, not a
    dependency of the runtime pipeline: a WAV input skips ffmpeg entirely.
    """
    if shutil.which("ffmpeg") is None:
        raise SystemExit(
            f"ffmpeg not found on PATH, and {src.name} is not a WAV.\n"
            "Either install ffmpeg or request WAV output from the voice model."
        )
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src),
         "-ac", "1", "-ar", str(wavkit.TARGET_RATE), str(dst)],
        check=True,
    )


def _trim_silence(samples: list[float], rate: int) -> list[float]:
    """Strip leading and trailing dead air.

    ⚠ THIS IS THE FUNCTION THAT MAKES CONCATENATION WORK. Generated speech carries
    80-200 ms of leading silence that varies per clip; left in, the pause before
    each word is whatever the model felt like and the line limps. Trimming here
    means the ONLY silence in the finished line is the silence this file authored.
    """
    start = wavkit.find_onset(samples, rate, TRIM_THRESHOLD)
    # Tail: find the onset of the reversed signal, then map back to a forward index.
    reversed_start = wavkit.find_onset(samples[::-1], rate, TRIM_THRESHOLD)
    end = len(samples) - reversed_start
    if end <= start:
        return samples  # all quiet — hand it back rather than returning nothing
    return samples[start:end]


# ── HOW MANY WORDS IS THIS PART ACTUALLY SAYING? ────────────────────────────
# ⚠ THIS EXISTS BECAUSE EVERY PUBLISHED CLIP SAID THE WRONG LINE FOR WEEKS.
# `versus.wav` came back from the TTS as TWO words — it had read a "/" out loud as
# "slash" — so the connector was literally "slash versus", and since the connector is
# in EVERY matchup, all 72 lines said "<A>, slash, versus, <B>". Nothing caught it:
# the file was the right name, the right length-ish, correctly trimmed and correctly
# levelled. The maker caught it by listening to a finished post.
#
# A part's WORD COUNT is checkable without listening, so now it is checked. One word is
# one run of voiced audio separated by real silence.
def voiced_runs(samples: list[float], rate: int,
                floor: float = 0.035, gap_ms: int = 90) -> list[tuple[float, float]]:
    """Spans of voiced audio, in seconds. A gap longer than `gap_ms` splits a word."""
    win = max(1, rate // 200)                       # 5 ms RMS window
    level: list[float] = []
    for i in range(0, len(samples) - win, win):
        chunk = samples[i:i + win]
        level.append((sum(x * x for x in chunk) / len(chunk)) ** 0.5)
    if not level:
        return []
    peak = max(level) or 1.0
    loud = [v > floor * peak for v in level]
    runs: list[tuple[float, float]] = []
    start: int | None = None
    quiet = 0
    need = max(1, gap_ms // 5)
    for i, v in enumerate(loud):
        if v:
            if start is None:
                start = i
            quiet = 0
        elif start is not None:
            quiet += 1
            if quiet >= need:
                runs.append((start * win / rate, (i - quiet) * win / rate))
                start = None
    if start is not None:
        runs.append((start * win / rate, len(loud) * win / rate))
    return [(a, b) for a, b in runs if b - a > 0.045]


# What each part is supposed to SAY, in words. Class names and the connector are one
# word; the tail is "who will win?", which the narrator runs as two breath groups.
EXPECTED_RUNS: dict[str, int] = {TAIL_SLUG: 2}


def expected_runs(key: str) -> int:
    return EXPECTED_RUNS.get(key.split(".")[0], 1)


def cmd_check() -> int:
    """Assert every banked part says the number of words it is supposed to."""
    bad = 0
    print("VO BANK CHECK")
    print("-" * 74)
    for path in sorted(BANK_DIR.glob("*.wav")):
        samples, rate = wavkit.read_mono(path)
        runs = voiced_runs(samples, rate)
        want = expected_runs(path.stem)
        ok = len(runs) == want
        bad += 0 if ok else 1
        note = "" if ok else f"   *** says {len(runs)} words, expected {want} ***"
        print(f"  {path.stem:<24} {len(samples) / rate:5.2f}s  words={len(runs)}{note}")
    print("-" * 74)
    if bad:
        print(f"{bad} part(s) wrong. Every matchup line that uses one is wrong too.")
        print("Repair with:  python python-tools/vo_bank.py --repair <slug> --keep <n>")
        return 1
    print("all parts say what they should")
    return 0


def cmd_repair(key: str, keep: int) -> int:
    """Re-bank one part from its raw source, keeping only voiced run `keep`.

    For the case the check catches: the TTS said something extra and the intended word
    is one of the runs. `--keep -1` takes the last, which is the usual shape (the model
    reads a stray character BEFORE the word it was asked for).
    """
    src = RAW_DIR / f"{key}.wav"
    if not src.exists():
        print(f"  x no raw source at {src}")
        return 1
    samples, rate = wavkit.read_mono(src)
    if rate != wavkit.TARGET_RATE:
        samples = wavkit.resample(samples, rate, wavkit.TARGET_RATE)
        rate = wavkit.TARGET_RATE
    runs = voiced_runs(samples, rate)
    if not runs:
        print(f"  x {key}: no voiced audio in the raw file")
        return 1
    try:
        a, b = runs[keep]
    except IndexError:
        print(f"  x {key}: run {keep} does not exist (found {len(runs)})")
        return 1
    # A hair either side so the consonant is not clipped off the front or back.
    pad = 0.035
    lo = max(0, int((a - pad) * rate))
    hi = min(len(samples), int((b + pad) * rate))
    cut = samples[lo:hi]
    cut = _trim_silence(cut, rate)
    cut = wavkit.fade(cut, rate, EDGE_FADE, EDGE_FADE)
    cut = wavkit.normalise(cut, PART_PEAK)
    dst = BANK_DIR / f"{key}.wav"
    wavkit.write_wav16(dst, cut, rate)
    print(f"  ok {key}: kept run {keep} of {len(runs)} "
          f"({a:.2f}-{b:.2f}s) -> {len(cut) / rate:.2f}s")
    return 0


def cmd_ingest(paths: list[str]) -> int:
    BANK_DIR.mkdir(parents=True, exist_ok=True)
    tmp = BANK_DIR / "_decode.tmp.wav"
    count = 0
    for raw in paths:
        src = Path(raw)
        if not src.exists():
            print(f"  ✗ missing: {src}")
            continue
        # The bank key is the source filename minus its extension, so the plan's
        # filenames ARE the contract.
        key = src.name
        for ext in (".wav", ".mp3", ".m4a", ".ogg", ".flac"):
            if key.lower().endswith(ext):
                key = key[: -len(ext)]
                break
        if src.suffix.lower() == ".wav":
            samples, rate = wavkit.read_mono(src)
        else:
            _decode_to_wav(src, tmp)
            samples, rate = wavkit.read_mono(tmp)
        if rate != wavkit.TARGET_RATE:
            samples = wavkit.resample(samples, rate, wavkit.TARGET_RATE)
        samples = _trim_silence(samples, wavkit.TARGET_RATE)
        samples = wavkit.fade(samples, wavkit.TARGET_RATE, EDGE_FADE, EDGE_FADE)
        samples = wavkit.normalise(samples, PART_PEAK)
        dst = BANK_DIR / f"{key}.wav"
        wavkit.write_wav16(dst, samples, wavkit.TARGET_RATE)
        dur = len(samples) / wavkit.TARGET_RATE
        print(f"  ✓ {key:<24} {dur:5.2f}s  ->  {dst.name}")
        count += 1
    if tmp.exists():
        tmp.unlink()
    print(f"\n{count} part(s) banked at {BANK_DIR}")
    return 0 if count else 1


# ---------------------------------------------------------------------------
# List — what is present, what is missing
# ---------------------------------------------------------------------------

def _have(key: str) -> bool:
    return (BANK_DIR / f"{key}.wav").exists()


def cmd_list() -> int:
    print(f"BANK: {BANK_DIR}")
    if not BANK_DIR.exists():
        print("  (empty — run --plan, generate the clips, then --ingest)")
        return 1
    missing: list[str] = []
    print("\n  part                     neutral  lead  tail")
    print("  " + "-" * 46)
    for name in CLASSES:
        s = slug(name)
        n = "  ✓  " if _have(s) else "  —  "
        ld = " ✓ " if _have(f"{s}.lead") else " · "
        tl = " ✓ " if _have(f"{s}.tail") else " · "
        print(f"  {name:<24} {n}    {ld}  {tl}")
        if not _have(s):
            missing.append(s)
    for s in (CONNECTOR_SLUG, TAIL_SLUG):
        n = "  ✓  " if _have(s) else "  —  "
        print(f"  {s:<24} {n}")
        if not _have(s):
            missing.append(s)
    print("  " + "-" * 46)
    print("  ✓ present   — MISSING (blocks assembly)   · optional variant absent")
    if missing:
        print(f"\n  {len(missing)} required part(s) missing: {', '.join(missing)}")
        return 1
    total = len(CLASSES) * (len(CLASSES) - 1)
    print(f"\n  bank complete — {total} matchups assemblable")
    return 0


# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------

def _load_part(key: str, position: str = "") -> list[float]:
    """Load a banked part, preferring a prosody variant when one exists.

    The fallback is what lets the bank be useful at eleven clips instead of
    twenty: ask for `shadowblade.lead`, get the neutral `shadowblade` if the
    variant was never generated.
    """
    if position:
        variant = BANK_DIR / f"{key}.{position}.wav"
        if variant.exists():
            samples, rate = wavkit.read_mono(variant)
            return samples if rate == wavkit.TARGET_RATE else wavkit.resample(samples, rate)
    path = BANK_DIR / f"{key}.wav"
    if not path.exists():
        raise SystemExit(
            f"missing bank part '{key}'.\n"
            f"Run:  python python-tools/vo_bank.py --list"
        )
    samples, rate = wavkit.read_mono(path)
    return samples if rate == wavkit.TARGET_RATE else wavkit.resample(samples, rate)


def _silence(seconds: float) -> list[float]:
    return [0.0] * int(seconds * wavkit.TARGET_RATE)


def assemble(a: str, b: str, gaps: tuple[float, float, float],
             with_tail: bool = True) -> tuple[list[float], str]:
    """Stitch `<A> versus <B> — who will win?` from banked parts."""
    ka, kb = slug(a), slug(b)
    g1, g2, g3 = gaps
    line: list[float] = []
    line += _load_part(ka, "lead")
    line += _silence(g1)
    line += _load_part(CONNECTOR_SLUG)
    line += _silence(g2)
    line += _load_part(kb, "tail")
    if with_tail:
        line += _silence(g3)
        line += _load_part(TAIL_SLUG)
    line = wavkit.normalise(line, LINE_PEAK)
    return line, f"{ka}_vs_{kb}"


def cmd_assemble(a: str, b: str, gaps: tuple[float, float, float],
                 with_tail: bool, out: str | None) -> int:
    line, name = assemble(a, b, gaps, with_tail)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dst = Path(out) if out else OUT_DIR / f"{name}.wav"
    dst.parent.mkdir(parents=True, exist_ok=True)
    wavkit.write_wav16(dst, line, wavkit.TARGET_RATE)
    print(f"  ✓ {name}  {len(line) / wavkit.TARGET_RATE:.2f}s  ->  {dst}")
    return 0


def cmd_all(gaps: tuple[float, float, float], with_tail: bool) -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    made = 0
    for a in CLASSES:
        for b in CLASSES:
            if a == b:
                continue  # a class never fights itself
            line, name = assemble(a, b, gaps, with_tail)
            wavkit.write_wav16(OUT_DIR / f"{name}.wav", line, wavkit.TARGET_RATE)
            made += 1
    print(f"  ✓ {made} matchup lines written to {OUT_DIR}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Build matchup voice-over lines from a bank of spoken words.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("pair", nargs="*", metavar="CLASS",
                    help="two class names to assemble, e.g. shadowblade cryomancer")
    ap.add_argument("--plan", action="store_true", help="print what to generate")
    ap.add_argument("--ingest", nargs="+", metavar="FILE",
                    help="fold generated audio files into the bank")
    ap.add_argument("--list", action="store_true", dest="do_list",
                    help="show which parts the bank holds")
    ap.add_argument("--all", action="store_true", help="assemble every ordered pairing")
    ap.add_argument("-o", "--out", help="output path for a single assembly")
    ap.add_argument("--no-tail", action="store_true",
                    help="omit 'who will win?' (name-vs-name only)")
    ap.add_argument("--gap", type=float, default=GAP_BEFORE_CONNECTOR,
                    help=f"gap before 'versus' (default {GAP_BEFORE_CONNECTOR})")
    ap.add_argument("--gap2", type=float, default=GAP_AFTER_CONNECTOR,
                    help=f"gap after 'versus' (default {GAP_AFTER_CONNECTOR})")
    ap.add_argument("--check", action="store_true",
                    help="assert every banked part says the right number of words")
    ap.add_argument("--repair", metavar="SLUG",
                    help="re-bank one part from raw, keeping only one voiced run")
    ap.add_argument("--keep", type=int, default=-1,
                    help="which voiced run --repair keeps (default -1, the last)")
    ap.add_argument("--tail-gap", type=float, default=GAP_BEFORE_TAIL,
                    help=f"gap before the question (default {GAP_BEFORE_TAIL})")
    args = ap.parse_args()

    gaps = (args.gap, args.gap2, args.tail_gap)

    if args.check:
        return cmd_check()
    if args.repair:
        return cmd_repair(args.repair, args.keep)
    if args.plan:
        return cmd_plan()
    if args.ingest:
        return cmd_ingest(args.ingest)
    if args.do_list:
        return cmd_list()
    if args.all:
        return cmd_all(gaps, not args.no_tail)
    if len(args.pair) == 2:
        return cmd_assemble(args.pair[0], args.pair[1], gaps, not args.no_tail, args.out)

    ap.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
