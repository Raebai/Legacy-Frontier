#!/usr/bin/env python3
"""Make a 9:16 cut of a finished clip, so YouTube files it as a SHORT and not a video.

    python python-tools/make_portrait.py                # every clip missing one
    python python-tools/make_portrait.py --only warlock_vs_cleric
    python python-tools/make_portrait.py --force        # rebuild even if present

⚠ A LANDSCAPE UPLOAD TO YOUTUBE IS NOT A SHORT, IT IS A NORMAL VIDEO. Shorts require
vertical or square and under three minutes. Our clips render 1920x1080 by an earlier
decision that is right for Instagram and TikTok, so sending them to YouTube unchanged
produces twenty-second normal videos — a format that gets essentially no distribution
and is the wrong shape for the one thing YouTube would be good at here. This closes
that gap without touching the render.

⚠ AND IT IS A RE-CUT, NOT A RE-SHOOT. The rule elsewhere in this pipeline is that a
picture change costs a ~25-minute shoot. That rule is about what the CAMERA saw:
reframing is a picture change the camera cannot help with. But 9:16 here is not a
reframe — the whole landscape frame is kept, at full width, over a blurred copy of
itself. Nothing is cropped away, so nothing needs re-rendering, and a clip converts in
about twenty seconds from the finished file.

⚠ THE BAND SITS ABOVE CENTRE ON PURPOSE. Shorts overlays its own caption, handle and
button column across the bottom of the frame. A dead-centre band puts the fight's feet
under that furniture; 40% from the top lands it in the eye-line and clear of it.

Output is `<stem>.portrait.mp4` beside the original. `daily_post.pool()` ignores it the
same way it ignores `.nomusic`, so a portrait cut can never be queued as if it were a
separate fight.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POSTS = ROOT / "content" / "posts"

SUFFIX = ".portrait"
W, H = 1080, 1920
## How far down the frame the sharp band sits, as a fraction of the leftover space.
## 0.5 is dead centre; 0.40 lifts it clear of the Shorts UI. See the note above.
BAND_Y = 0.40

## The blurred backdrop is also darkened, because at full brightness it competes with
## the band for attention and the eye does not settle on the fight.
FILTER = (
    f"[0:v]scale=-2:{H},crop={W}:{H},boxblur=30:2,eq=brightness=-0.12[bg];"
    f"[0:v]scale={W}:-2:flags=lanczos[fg];"
    f"[bg][fg]overlay=(W-w)/2:(H-h)*{BAND_Y},format=yuv420p[v]"
)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def sources() -> list[Path]:
    """Every postable clip — not the .nomusic companions, not existing portrait cuts."""
    return sorted(p for p in POSTS.glob("*.mp4")
                  if ".nomusic" not in p.name and SUFFIX not in p.name)


def portrait_path(clip: Path) -> Path:
    return clip.with_name(clip.stem + SUFFIX + ".mp4")


def convert(clip: Path, dst: Path) -> bool:
    # ⚠ WRITTEN TO A TEMP NAME AND RENAMED. ffmpeg killed halfway leaves a valid-looking
    # but truncated mp4, and the only thing that ever checks is "does the file exist" —
    # which would then upload a clip that stops mid-fight.
    tmp = dst.with_suffix(".tmp.mp4")
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(clip),
           "-filter_complex", FILTER, "-map", "[v]", "-map", "0:a?",
           # ⚠ crf 21 -> 17, AND THIS IS THE LAST-MILE ENCODE OF A FOURTH GENERATION.
           # The ladder to here is crf 14 (shoot) -> crf 14 (speed conform) -> crf 18
           # (delivery mux) -> this, all on top of a lossy MJPEG capture. By this point
           # the picture's quality budget is spent, and crf 21 was spending it hardest
           # on the ONE file a viewer actually watches. What compounding eats first is
           # thin high-contrast lines, which is the entire art style of this game.
           # `-pix_fmt` was absent from this pass altogether, so it never even stated
           # what it wanted and inherited whatever the source claimed.
           "-c:v", "libx264", "-preset", "medium", "-crf", "17",
           "-pix_fmt", "yuv420p", "-color_range", "tv", "-colorspace", "bt709",
           "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(tmp)]
    started = time.time()
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        tmp.unlink(missing_ok=True)
        print(f"  ! {clip.stem}: ffmpeg failed\n    {result.stderr.strip()[:200]}")
        return False
    tmp.replace(dst)
    print(f"  {clip.stem:<34} {dst.stat().st_size / 1e6:>5.1f} MB  "
          f"{time.time() - started:>4.0f}s")
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="one clip stem, rather than all of them")
    ap.add_argument("--force", action="store_true", help="rebuild ones that exist")
    args = ap.parse_args()

    clips = sources()
    if args.only:
        clips = [c for c in clips if c.stem == args.only]
        if not clips:
            print(f"no clip called {args.only!r} in {POSTS.relative_to(ROOT)}")
            return 1

    todo = [c for c in clips if args.force or not portrait_path(c).exists()]
    print()
    print(f"  {len(clips)} clip(s), {len(todo)} needing a portrait cut")
    if not todo:
        print("  nothing to do.")
        return 0
    print()
    made = sum(convert(c, portrait_path(c)) for c in todo)
    print()
    print(f"  {made}/{len(todo)} written as <stem>{SUFFIX}.mp4")
    if made != len(todo):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
