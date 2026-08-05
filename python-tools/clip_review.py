#!/usr/bin/env python3
"""Score a delivered clip on the three ways it stops being watchable — and prove it.

    python python-tools/clip_review.py                       # every mp4 in user://clips
    python python-tools/clip_review.py brawler_vs_juggernaut # one of them
    python python-tools/clip_review.py --sheet               # ...and a contact sheet

WHY THIS EXISTS. "Make the clips more epic" is not actionable and cannot be
regression-tested, so every previous pass at it was somebody's taste against
somebody else's. Three faults were found by LOOKING at delivered frames, and all
three are countable, which means they can be measured before and after instead of
argued about:

  BLOWOUT   a spell paints a near-opaque disc over most of the frame and both
            fighters vanish inside it. Measured on a real frame: two overlapping
            HDR fills covering the picture. Counted as "share of pixels this bright"
            because bloom is what turns an HDR fill into a flat blob, and bloom is
            exactly what a luminance histogram sees.
  DEAD AIR  the camera solves a zoom that contains both fighters, they separate, and
            the shot goes so wide that neither is legible — measured at ~4% of frame
            height against ~60% empty sky. Counted as DETAIL: the share of pixels
            sitting on an edge. ⚠ THIS ONE IS A PROXY AND IS LABELLED AS ONE. Pixels
            cannot tell a fighter from a crate, so a frame full of background
            furniture scores as busy. The TRUE measure is the camera's own solved
            zoom, which only the engine knows and which the director now records
            into `clip.json`. Read that first; this is the corroboration.
  STILLNESS the clip holds on a frozen frame. Counted as the share of frames whose
            mean absolute difference from the previous frame is under a threshold.

⚠ THE THRESHOLDS ARE CALIBRATED, NOT CHOSEN. See CALIBRATION below: each one was
set by reading the value off frames that were judged by eye first, so the number
agrees with the verdict a human already reached rather than inventing its own.

⚠ AND IT READS THE DELIVERED MP4, not the game's internal state. Every previous
instrument in this pipeline lied at least once — the encoder read a directory from
before the app rename, the frame picker assumed 60 fps of render — and each time the
reason was that it measured an intention instead of an artefact. This measures the
file that would be posted.

Needs ffmpeg on PATH. Stdlib + Pillow.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import shutil
import sys
import tempfile
from pathlib import Path

from godot_paths import user_data_dir

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent

# ── CALIBRATION ─────────────────────────────────────────────────────────────────
# BLOWOUT_LUMA / BLOWOUT_SHARE: read off the frame at 0:36 of
# brawler_vs_juggernaut.mp4, which is two overlapping HDR fills and in which neither
# fighter can be found by eye. That frame measures 0.286 at luma 200, so the gate is
# under it. ⚠ REPORTED AS A COUNT, NOT A SHARE OF THE CLIP. The first version gated
# on "over 2% of frames" and stayed silent on a clip that had the fault — because a
# blowout lasts a handful of frames out of 625, which is 1.6%. It only has to happen
# ONCE to be the thing a viewer remembers.
BLOWOUT_LUMA = 200          # 0-255; a bloomed HDR fill lands well above this
BLOWOUT_SHARE = 0.22        # ...over this share of ONE frame

# ⚠ AND BRIGHTNESS ALONE IS NOT THE FAULT — THIS TOOL NEARLY DELETED THE BEST
# EFFECT IN THE GAME. `ImpactFrame.Style.INVERT` is a true screen negative: a dark
# scene becomes a bright one, so it scores 0.688 bright and trips every brightness
# gate ever written. It is not a blowout. It is the picture, intact, made wrong —
# the maker's words on seeing it were "it looks like time has stopped".
#
# What actually separates them is DETAIL, measured on three frames judged by eye:
#     old white-out    bright 0.286   detail 0.139   <- flat; both fighters gone
#     the inversion    bright 0.688   detail 0.189   <- MORE detail than a close-up
#     normal close-up  bright 0.000   detail 0.153
#
# So a blowout is bright AND FLAT. An inversion is bright and sharp, and is left
# alone. Getting this wrong is the exact failure this file's header warns about:
# an instrument that measures an intention rather than the artefact.
BLOWOUT_FLAT_MAX = 0.15     # detail at or under this, while bright, = the picture is gone

# ⚠ THE FIRST VERSION OF THIS METRIC WAS WRONG AND SAID SO CONFIDENTLY. It counted
# pixels differing from the frame's modal value, which on a two-tone picture is
# almost all of them: the dead wide shot I had already judged by eye scored 62.7%
# "ink" against a 5.5% threshold — it would have passed the very frame it was
# calibrated on. Replaced with edge density, measured on three frames judged first:
#     dead wide shot   0.086
#     close exchange   0.153
#     blowout disc     0.139
# so 0.11 sits between the fault and the good frame. The separation is 1.8x, which
# is a signal, not a proof — hence "proxy" above.
EDGE_LUMA = 24              # gradient magnitude that counts as an edge
DETAIL_MIN = 0.11

# STILL_MAD: mean-absolute-difference between consecutive frames.
STILL_MAD = 1.6

SAMPLE_W = 320              # analyse downscaled; the faults are all large-scale


def _frames(mp4: Path, tmp: Path) -> list[Path]:
    ff = shutil.which("ffmpeg")
    if ff is None:
        print("error: ffmpeg is not on PATH")
        return []
    subprocess.run(
        [ff, "-y", "-v", "error", "-i", str(mp4),
         "-vf", f"scale={SAMPLE_W}:-1", str(tmp / "s%05d.png")],
        check=True)
    return sorted(tmp.glob("s*.png"))


def score(mp4: Path) -> dict | None:
    try:
        from PIL import Image, ImageFilter
    except ImportError:
        print("error: Pillow is not installed (pip install pillow)")
        return None
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        frames = _frames(mp4, tmp)
        if not frames:
            return None
        blowout = 0
        dead = 0
        still = 0
        prev = None
        worst_blow = (0.0, -1)
        worst_dead = (1.0, -1)
        for i, fp in enumerate(frames):
            im = Image.open(fp).convert("L")
            px = list(im.getdata())
            n = float(len(px))
            # BLOWOUT — share of the frame that is bloomed-bright.
            bright = sum(1 for v in px if v >= BLOWOUT_LUMA) / n
            # INK — share of the frame that differs from the frame's own mode. The
            # mode is the background (sky/ground gradient); everything the viewer is
            # actually looking at is the deviation from it.
            edges = list(im.filter(ImageFilter.FIND_EDGES).getdata())
            detail = sum(1 for v in edges if v >= EDGE_LUMA) / n
            # BRIGHT **AND FLAT**. See the CALIBRATION block: bright-and-sharp is the
            # INVERT frame, which is a feature.
            if bright >= BLOWOUT_SHARE and detail <= BLOWOUT_FLAT_MAX:
                blowout += 1
                if bright > worst_blow[0]:
                    worst_blow = (bright, i)
            if detail < DETAIL_MIN:
                dead += 1
            if detail < worst_dead[0]:
                worst_dead = (detail, i)
            # STILLNESS
            if prev is not None:
                mad = sum(abs(a - b) for a, b in zip(px, prev)) / n
                if mad < STILL_MAD:
                    still += 1
            prev = px
        total = float(len(frames))
        return {
            "clip": mp4.name,
            "frames": len(frames),
            "blowout_share": round(blowout / total, 3),
            "dead_share": round(dead / total, 3),
            "still_share": round(still / total, 3),
            "worst_blowout": {"share": round(worst_blow[0], 3), "frame": worst_blow[1]},
            "blowout_frames": blowout,
            "worst_detail": {"detail": round(worst_dead[0], 3), "frame": worst_dead[1]},
        }


def sheet(mp4: Path, out: Path, cols: int = 5, rows: int = 4) -> bool:
    """A contact sheet, because a number says a clip is bad and a picture says how."""
    ff = shutil.which("ffmpeg")
    if ff is None:
        return False
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
         "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", str(mp4)],
        capture_output=True, text=True)
    try:
        n = int((probe.stdout or "0").strip() or 0)
    except ValueError:
        n = 0
    step = max(1, n // (cols * rows)) if n else 20
    subprocess.run(
        [ff, "-y", "-v", "error", "-i", str(mp4),
         "-vf", f"select='not(mod(n\\,{step}))',scale=320:-1,tile={cols}x{rows}",
         "-frames:v", "1", str(out)], check=True)
    return out.exists()


def verdict(s: dict) -> list[str]:
    out: list[str] = []
    if s["blowout_frames"] >= 1:
        out.append(f"BLOWOUT  {s['blowout_frames']} frame(s) are mostly a bright fill "
                   f"(worst {s['worst_blowout']['share']:.0%} of frame "
                   f"{s['worst_blowout']['frame']}) — the fighters are inside it")
    if s["dead_share"] > 0.10:
        out.append(f"DEAD AIR {s['dead_share']:.0%} of frames are low-detail wide shots "
                   f"(thinnest {s['worst_detail']['detail']:.1%} at frame "
                   f"{s['worst_detail']['frame']}) — proxy; check clip.json zoom")
    if s["still_share"] > 0.20:
        out.append(f"STILL    {s['still_share']:.0%} of frames barely change")
    if not out:
        out.append("clean on all three counts")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("clips", nargs="*", help="clip stems (default: every mp4)")
    ap.add_argument("--sheet", action="store_true", help="also write a contact sheet")
    ap.add_argument("--json", help="write the scores to this path")
    args = ap.parse_args()

    root = user_data_dir() / "clips"
    if args.clips:
        paths = [root / (c if c.endswith(".mp4") else c + ".mp4") for c in args.clips]
    else:
        paths = sorted(root.glob("*.mp4"))
    paths = [p for p in paths if p.exists()]
    if not paths:
        print(f"no clips in {root}")
        return 1

    scores = []
    for p in paths:
        s = score(p)
        if s is None:
            return 2
        scores.append(s)
        print(f"\n{p.name}  ({s['frames']} frames)")
        for line in verdict(s):
            print("  " + line)
        if args.sheet:
            out = p.with_name(p.stem + "_sheet.png")
            if sheet(p, out):
                print(f"  sheet -> {out}")
    if args.json:
        Path(args.json).write_text(json.dumps(scores, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
