#!/usr/bin/env python3
"""Keep the clip pool topped up on its own, so the queue never says OUT OF CLIPS.

    python python-tools/auto_shoot.py                 # what it would shoot
    python python-tools/auto_shoot.py --live          # actually shoot
    python python-tools/auto_shoot.py --live --max 2  # a smaller bite

⚠ THIS IS THE THING THE POSTING SCRIPT DELIBERATELY REFUSED TO DO, and the reasons it
refused are all still true. They are handled here rather than wished away:

  1. A SHOOT NEEDS A REAL RENDERER. `make_post` runs Godot WITHOUT `--headless`,
     because a null rendering driver produces blank frames that SAVE SUCCESSFULLY. An
     unattended shoot on a locked or sleeping laptop is the exact case that produces a
     twenty-second black rectangle with a valid header and a plausible file size.
     Nothing downstream would notice: the file exists, the duration is right, and it
     would be queued and published. So every clip is MEASURED before it is kept - see
     `looks_rendered()` - and anything that reads as blank is deleted, not posted.
  2. A SHOOT REWRITES project.godot. `make_clip._render_size` patches the window
     override and restores it in a `finally`, but a hard kill leaves it patched. This
     refuses to start if the maker's editor is open, and checks the override is back
     afterwards.
  3. A SHOOT CAN FAIL THE QUALITY GATE. Roughly one bout in three is a demolition.
     `make_post --takes N` already re-rolls those; this deletes whatever still fails.

⚠ AND IT WILL NOT RUN WHILE GODOT IS OPEN. A shoot resizes the project window and
fights whoever is playing. If the maker is at their desk, the pool waits.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from itertools import combinations
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import daily_post as dp  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
POSTS = ROOT / "content" / "posts"

CLASSES = ["arcanist", "shadowblade", "brawler", "juggernaut", "cleric",
           "cryomancer", "stormcaller", "warlock", "swordsaint"]

## How deep a buffer to aim for. Two clips a day are consumed, so 14 days is 28 clips.
TARGET_DAYS = 14
## Ceiling per run. A take is roughly 25 minutes, so four is most of a night and the
## machine is free again by morning. Raising this does not make it faster, it makes it
## longer.
MAX_PER_RUN = 4
## Passed to make_post: how many bouts to roll before accepting one.
TAKES = 3

## ⚠ WHAT A BLANK RENDER LOOKS LIKE. A frame with no picture has almost no spread
## between its darkest and lightest pixel. Real footage of this game runs 150+ even in
## its dimmest scene; a null-renderer frame sits near zero. 40 is far below anything
## the game produces and far above anything a black frame does.
MIN_LUMA_SPREAD = 40.0
MIN_SECONDS = 8.0

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def godot_is_open() -> bool:
    """Is a Godot window up? If so the maker is working and we do not interfere."""
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Godot*"],
                             capture_output=True, text=True, timeout=30).stdout
        return "Godot" in out
    except Exception:                                        # noqa: BLE001
        return False        # cannot tell; the render check is the real safety net


def probe(path: Path) -> tuple[float, int, int] | None:
    """(duration, width, height) or None."""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
             "stream=width,height:format=duration", "-of", "json", str(path)],
            capture_output=True, text=True, timeout=60)
        d = json.loads(out.stdout)
        st = d["streams"][0]
        return float(d["format"]["duration"]), int(st["width"]), int(st["height"])
    except Exception:                                        # noqa: BLE001
        return None


def looks_rendered(path: Path) -> tuple[bool, str]:
    """Does this file contain PICTURE, or is it a plausible-looking blank?

    ⚠ THE ONLY CHECK THAT CATCHES THE WORST FAILURE MODE. Every other signal - the
    file exists, the size is reasonable, ffprobe reports a duration and a resolution -
    is equally true of a black rectangle produced by a headless renderer. This samples
    frames across the clip and measures the spread between the darkest and lightest
    pixel in each; a frame with no picture has almost none.
    """
    meta = probe(path)
    if meta is None:
        return False, "ffprobe could not read it"
    duration, w, h = meta
    if duration < MIN_SECONDS:
        return False, f"only {duration:.1f}s"
    if w < 640 or h < 360:
        return False, f"{w}x{h} is not a render"
    try:
        out = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(path), "-vf",
             "fps=1/4,signalstats,metadata=print:key=lavfi.signalstats.YMIN:file=-",
             "-f", "null", "-"],
            capture_output=True, text=True, timeout=180)
        blob = out.stdout + out.stderr
        # signalstats prints one metadata line per sampled frame; ask for the spread by
        # reading both extremes off the same pass.
        out2 = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(path), "-vf",
             "fps=1/4,signalstats,metadata=print:key=lavfi.signalstats.YMAX:file=-",
             "-f", "null", "-"],
            capture_output=True, text=True, timeout=180)
        mins = [float(x) for x in re.findall(r"YMIN=([\d.]+)", blob)]
        maxs = [float(x) for x in re.findall(r"YMAX=([\d.]+)", out2.stdout + out2.stderr)]
    except Exception as e:                                   # noqa: BLE001
        return False, f"could not measure it ({type(e).__name__})"
    if not mins or not maxs:
        return False, "no frames could be sampled"
    spread = max(hi - lo for lo, hi in zip(mins, maxs))
    if spread < MIN_LUMA_SPREAD:
        return False, f"blank picture (luma spread {spread:.0f})"
    return True, f"{duration:.0f}s, {w}x{h}, luma spread {spread:.0f}"


def existing_pairs() -> set[frozenset]:
    pairs = set()
    for clip in POSTS.glob("*.mp4"):
        if ".nomusic" in clip.name or ".portrait" in clip.name:
            continue
        parts = clip.stem.split("_vs_")
        if len(parts) == 2:
            pairs.add(frozenset(parts))
    return pairs


def next_matchups(count: int) -> list[tuple[int, int]]:
    """Pairs nobody has shot yet, so the library broadens instead of repeating.

    Thirty-six pairs exist among nine classes and seventeen are shot, so there is a
    long way to go before this has to repeat anything. When it does run out it starts
    again from the top rather than stopping - a second clip of a matchup is a different
    fight, and a repeated matchup beats an empty queue.
    """
    have = existing_pairs()
    fresh, seen = [], []
    for i, j in combinations(range(len(CLASSES)), 2):
        (fresh if frozenset({CLASSES[i], CLASSES[j]}) not in have else seen).append((i, j))
    return (fresh + seen)[:count]


def shoot(a: int, b: int, takes: int, timeout: int) -> bool:
    before = {p.name for p in POSTS.glob("*.mp4")}
    cmd = [sys.executable, str(ROOT / "python-tools" / "make_post.py"),
           "--a", str(a), "--b", str(b), "--takes", str(takes)]
    print(f"  shooting {CLASSES[a]} vs {CLASSES[b]} ...", flush=True)
    started = time.time()
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"    timed out after {timeout}s")
        return False
    made = [POSTS / n for n in
            {p.name for p in POSTS.glob("*.mp4")} - before
            if ".nomusic" not in n and ".portrait" not in n]
    if not made:
        tail = (r.stdout or r.stderr or "").strip().splitlines()[-3:]
        print(f"    produced nothing after {time.time() - started:.0f}s")
        for t in tail:
            print(f"      {t[:110]}")
        return False
    kept = 0
    for clip in made:
        ok, why = looks_rendered(clip)
        if ok:
            print(f"    kept    {clip.name}  ({why})")
            kept += 1
            continue
        # ⚠ DELETED, NOT LEFT LYING AROUND. A clip in content/posts/ is queueable by
        # definition, so a file that failed inspection must not survive the run.
        print(f"    DELETED {clip.name}  ({why})")
        clip.unlink(missing_ok=True)
        for sib in POSTS.glob(clip.stem + ".*"):
            sib.unlink(missing_ok=True)
    return kept > 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--live", action="store_true", help="actually shoot")
    ap.add_argument("--max", type=int, default=MAX_PER_RUN, help="ceiling for this run")
    ap.add_argument("--target-days", type=int, default=TARGET_DAYS)
    ap.add_argument("--takes", type=int, default=TAKES)
    ap.add_argument("--timeout", type=int, default=2700, help="seconds per matchup")
    ap.add_argument("--force", action="store_true",
                    help="shoot even though Godot is open. It will fight you.")
    args = ap.parse_args()

    accounts = dp.load_accounts()
    ledger = dp.load_ledger()
    left, days = dp.runway(accounts, ledger)
    per_day = max(len([a for a in accounts if not a.get("same_clip_as")]), 1)
    want = max(args.target_days * per_day - left, 0)
    todo = min(want, args.max)

    print()
    print(f"  {left} clip(s) unspoken-for = {days:.1f} day(s) of runway")
    print(f"  target {args.target_days} days at {per_day}/day, so {want} more wanted; "
          f"this run will do at most {args.max}")

    if not todo:
        print("\n  Pool is deep enough. Nothing to shoot.")
        return 0
    if godot_is_open() and not args.force:
        print("\n  Godot is open, so somebody is working. Not shooting - a render "
              "resizes\n  the project window and would fight them. It will try again "
              "next run.")
        return 0

    picks = next_matchups(todo)
    print()
    for a, b in picks:
        print(f"    would shoot  {CLASSES[a]} vs {CLASSES[b]}")
    if not args.live:
        print(f"\n  DRY RUN - nothing shot. Add --live. "
              f"Budget about {todo * 25} minutes.")
        return 0

    print()
    made = sum(shoot(a, b, args.takes, args.timeout) for a, b in picks)
    print()
    print(f"  {made}/{len(picks)} matchup(s) produced a usable clip")

    # A render patches project.godot and restores it in a `finally`; a hard kill does
    # not. Say so loudly rather than leaving the maker to find it at their next F5.
    check = subprocess.run([sys.executable,
                            str(ROOT / "python-tools" / "check_window_override.py")],
                           capture_output=True, text=True)
    print(f"  {check.stdout.strip() or check.stderr.strip()}")
    return 0 if made else 1


if __name__ == "__main__":
    raise SystemExit(main())
