#!/usr/bin/env python3
"""Every image the STICKSPIRE accounts need, derived from the drawn mark.

⚠ WHY THIS IS A SCRIPT AND NOT A FOLDER OF HAND-MADE FILES. The mark is CODE
(`GameLogo.gd`, stamped by `tools/render_logo.gd`), which is what lets it survive a
rename — and it survived one on 2026-08-22. A hand-exported PNG set would have gone
stale the moment `TITLE` changed. Re-run this after `render_logo.gd` and the whole kit
follows the game.

WHAT EACH SIZE IS FOR, AND WHY IT IS THAT SIZE:

  avatar_512 / _1024      profile picture, every platform. OPAQUE, because all three
                          composite a transparent PNG against a background of their own
                          choosing, and all three crop it to a CIRCLE — so the mark is
                          scaled until the inscribed circle lands on its own outer ring
                          rather than biting inside it.
  yt_channel_art          2560x1440 is the file YouTube wants, but only the middle
                          1546x423 is guaranteed visible — TV crops least, phones crop
                          most. Everything meaningful goes in that band; the rest is
                          bleed. Getting this wrong is the classic YouTube banner bug.
  yt_thumbnail            1280x720, the 16:9 slot. Left clear on purpose: a thumbnail
                          wants a FRAME OF THE FIGHT with the mark as a corner stamp,
                          not a logo on a field, so this is the stamp on transparency
                          to composite over a still.
  ig_post                 1080x1080. The square feed unit.
  ig_story                1080x1920. Also the Reels cover and the TikTok end card.
  x_header                1500x500.
  favicon_32 / _180       browser tab and iOS home screen, for whenever a site exists.

Run:  python python-tools/build_social_kit.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BRAND = REPO / "godot-project" / "assets" / "brand"
# ⚠ OUTSIDE THE GODOT PROJECT, DELIBERATELY. Anything under `godot-project/` is
# imported by the engine — the first build of this kit created twelve entries in
# `.godot/imported/` for artwork the game never loads. The game keeps what
# `render_logo.gd` stamps; the social kit is a deliverable, so it lives with the other
# deliverables in `content/`.
OUT = REPO / "content" / "brand"

# The brand paper, straight off GameLogo.PAPER = Color(0.055, 0.052, 0.075).
PAPER = "0x0E0D13"
MARK = BRAND / "avatar_1024.png"           # the circular mark, no text
LOCKUP = BRAND / "logo_wordmark_1024.png"  # mark ABOVE the wordmark (tall/square use)
LOCKUP_H_NAME = "lockup_horizontal.png"    # mark BESIDE the wordmark (wide use)

## YouTube ships a 2560x1440 file but only guarantees this middle band is visible —
## TV crops least, phone crops most. Art outside it is bleed, not design.
YT_SAFE = (1546, 423)


def ff(args: list[str]) -> None:
    exe = shutil.which("ffmpeg")
    if exe is None:
        sys.exit("ffmpeg is not on PATH")
    r = subprocess.run([exe, "-v", "error", "-y", *args], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"ffmpeg failed:\n{r.stderr.strip()}")


def _place(pos: str) -> str:
    """Overlay coordinates. `c` centres; `br` tucks into the bottom-right with margin."""
    return {"c": "(W-w)/2:(H-h)/2",
            "br": "W-w-56:H-h-56"}[pos]


def canvas(dst: Path, w: int, h: int, art: Path, art_h: int,
           bg: str | None = PAPER, pos: str = "c") -> None:
    """`art` scaled to `art_h` tall, placed on a `w`x`h` field."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if bg is None:
        # Transparent field — for stamps that get composited over footage.
        ff(["-f", "lavfi", "-i", f"color=c=black@0.0:s={w}x{h}:r=1,format=rgba",
            "-i", str(art),
            "-filter_complex", f"[1:v]scale=-1:{art_h}:flags=lanczos[a];"
                               f"[0:v][a]overlay={_place(pos)}:format=auto",
            "-frames:v", "1", str(dst)])
    else:
        ff(["-f", "lavfi", "-i", f"color=c={bg}:s={w}x{h}",
            "-i", str(art),
            "-filter_complex", f"[1:v]scale=-1:{art_h}:flags=lanczos[a];"
                               f"[0:v][a]overlay={_place(pos)}:format=auto,format=rgb24",
            "-frames:v", "1", str(dst)])


def verify(p: Path) -> str:
    """⚠ A BLANK PNG SAVES JUST FINE. Count distinct greys, not exit codes."""
    exe = shutil.which("ffmpeg")
    raw = subprocess.run([exe, "-v", "error", "-i", str(p), "-vf", "scale=64:64",
                          "-pix_fmt", "gray", "-f", "rawvideo", "-"],
                         capture_output=True).stdout
    exe2 = shutil.which("ffprobe")
    dims = subprocess.run([exe2, "-v", "error", "-select_streams", "v:0",
                           "-show_entries", "stream=width,height", "-of", "csv=p=0",
                           str(p)], capture_output=True, text=True).stdout.strip()
    tones = len(set(raw))
    return f"{dims:<12} {p.stat().st_size/1024:6.0f} KB  tones={tones:3d} " + \
           ("ok" if tones > 15 else "*** LOOKS BLANK ***")


def _assert_yt_safe(banner: Path) -> None:
    """Nothing meaningful may sit outside YouTube's guaranteed-visible band.

    ⚠ THIS GUARD EXISTS BECAUSE THE FIRST BUILD FAILED IT — the vertical lockup at
    760px overflowed the 423px band, so a phone would have cropped to a headless tower
    with no name.

    ⚠ AND THE FIRST VERSION OF THE GUARD ITSELF WAS WRONG, which is the more useful
    warning. It cropped to the safe band and to the full frame, scaled BOTH to 200px
    wide, and compared ink counts — two different pixel densities, so the ratio was
    meaningless. It reported "247% of the artwork is inside" and printed `ok` anyway.
    A number over 100% should have been impossible; a guard that can report an
    impossible number and still pass is not measuring anything.

    So: ONE decode, ONE coordinate space. The whole banner is read at a fixed small
    size and the safe band is a rectangle within that same buffer."""
    exe = shutil.which("ffmpeg")
    W, H = 256, 144                      # the whole banner, one decode
    raw = subprocess.run([exe, "-v", "error", "-i", str(banner),
                          "-vf", f"scale={W}:{H}", "-pix_fmt", "gray",
                          "-f", "rawvideo", "-"], capture_output=True).stdout
    if len(raw) < W * H:
        print("  ⚠ could not read yt_channel_art back")
        return
    # The safe band expressed in this same buffer's pixels.
    bw = round(YT_SAFE[0] / 2560 * W)
    bh = round(YT_SAFE[1] / 1440 * H)
    x0, y0 = (W - bw) // 2, (H - bh) // 2
    # PAPER is 14/13/19, so anything materially brighter is artwork.
    total = inside = 0
    for y in range(H):
        for x in range(W):
            if raw[y * W + x] > 45:
                total += 1
                if x0 <= x < x0 + bw and y0 <= y < y0 + bh:
                    inside += 1
    if total == 0:
        print("  ⚠ yt_channel_art has no artwork at all")
        return
    share = 100.0 * inside / total
    ok = share > 99.0
    print(f"  yt safe-band: {share:.1f}% of the artwork sits inside "
          f"{YT_SAFE[0]}x{YT_SAFE[1]}  " + ("ok" if ok else "*** OUTSIDE THE SAFE BAND ***"))


def _alpha_bands(src: Path) -> list[tuple[int, int]]:
    """Rows of `src` that contain anything, grouped into contiguous bands.

    ⚠ MEASURED, NOT HARDCODED, AND THAT IS A BUG FIX. The first version carried the
    crop rectangles as literals — mark y87..721, text y883..956 — read off the wordmark
    as it looked the day this was written. The mark was then redrawn (the cast circle
    became the cleft tower) and those numbers silently described the wrong pixels: the
    crop would have sliced through the new art and the failure would have looked like a
    design choice rather than a stale constant. Reading the alpha channel costs one
    decode and cannot go stale.
    """
    exe = shutil.which("ffmpeg")
    W = H = 1024
    raw = subprocess.run([exe, "-v", "error", "-i", str(src), "-vf",
                          f"scale={W}:{H},format=rgba,extractplanes=a",
                          "-pix_fmt", "gray", "-f", "rawvideo", "-"],
                         capture_output=True).stdout
    rows = [y for y in range(H) if max(raw[y * W:(y + 1) * W], default=0) > 40]
    if not rows:
        sys.exit(f"{src.name} looks empty — run tools/render_logo.gd first")
    bands, start, prev = [], rows[0], rows[0]
    for y in rows[1:]:
        if y - prev > 6:
            bands.append((start, prev))
            start = y
        prev = y
    bands.append((start, prev))
    return bands


def build_horizontal_lockup() -> Path:
    """Mark BESIDE the wordmark, for wide canvases.

    `render_logo.gd` draws the mark ABOVE the text, which is right for a square and
    wrong for a 2560x1440 banner whose usable band is 423px tall. Rather than add a
    second layout to the drawing code, the two halves are cut out of the stamped
    wordmark — their row bands are cleanly separated, and located by measurement.
    """
    dst = OUT / LOCKUP_H_NAME
    dst.parent.mkdir(parents=True, exist_ok=True)
    bands = _alpha_bands(LOCKUP)
    if len(bands) < 2:
        sys.exit(f"expected a mark band and a text band in {LOCKUP.name}, "
                 f"found {len(bands)}")
    (mark_y0, mark_y1), (text_y0, text_y1) = bands[0], bands[-1]
    mark_h, text_h = mark_y1 - mark_y0 + 1, text_y1 - text_y0 + 1
    print(f"  lockup source: mark rows {mark_y0}-{mark_y1}, "
          f"text rows {text_y0}-{text_y1}")

    mark_tmp, text_tmp = OUT / "_mark.png", OUT / "_text.png"
    ff(["-i", str(LOCKUP), "-vf", f"crop=1024:{mark_h}:0:{mark_y0}", str(mark_tmp)])
    ff(["-i", str(LOCKUP), "-vf", f"crop=1024:{text_h}:0:{text_y0}", str(text_tmp)])
    ff(["-f", "lavfi", "-i", "color=c=black@0.0:s=1900x520:r=1,format=rgba",
        "-i", str(mark_tmp), "-i", str(text_tmp),
        "-filter_complex",
        "[1:v]scale=-1:460:flags=lanczos[m];[2:v]scale=-1:108:flags=lanczos[t];"
        "[0:v][m]overlay=(460-overlay_w)/2:(H-h)/2[a];[a][t]overlay=520:(H-h)/2",
        "-frames:v", "1", str(dst)])
    mark_tmp.unlink(missing_ok=True)
    text_tmp.unlink(missing_ok=True)
    return dst


## The sizes a profile picture is ACTUALLY seen at, which are not the size it is
## uploaded at. A 1024px avatar that reads beautifully in a folder is irrelevant; these
## three are where the decision is really made.
##   32  — the comment/notification row, and the browser tab
##   40  — the avatar above a Reel or a TikTok in the feed, the most common size by far
##   110 — the profile page header, the only place anyone looks at it deliberately
LEGIBILITY_SIZES = (32, 40, 110)
LEGIBILITY_ZOOM = 6


def _legibility_sheet() -> None:
    """Shrink the mark to feed sizes, then blow it back up so the survivors are visible.

    ⚠ THIS IS THE ONLY HONEST WAY TO JUDGE AN AVATAR, and looking at the 1024px master
    is how a mark with fine detail gets approved and then disappears in production. The
    downscale is lanczos (what a platform does); the upscale back is NEAREST, so no
    interpolation invents detail that the small version does not contain. What you see
    in this sheet is exactly the information a viewer's eye receives.
    """
    src = OUT / "avatar_1024.png"
    if not src.exists():
        return
    parts = []
    for size in LEGIBILITY_SIZES:
        dst = OUT / f"legibility_{size}px.png"
        ff(["-i", str(src), "-vf",
            f"scale={size}:{size}:flags=lanczos,"
            f"scale={size * LEGIBILITY_ZOOM}:{size * LEGIBILITY_ZOOM}:flags=neighbor",
            "-frames:v", "1", str(dst)])
        parts.append(dst)
        print(f"  legibility_{size}px.png       {verify(dst)}")
    # One row, so the three are compared against each other rather than in sequence.
    row = OUT / "legibility_row.png"
    widths = [s * LEGIBILITY_ZOOM for s in LEGIBILITY_SIZES]
    gap, pad = 40, 40
    total_w = sum(widths) + gap * (len(widths) - 1) + pad * 2
    total_h = max(widths) + pad * 2
    args = ["-f", "lavfi", "-i",
            f"color=c=0x0e0d13:s={total_w}x{total_h}:r=1,format=rgba"]
    for p in parts:
        args += ["-i", str(p)]
    chain, x = "", pad
    for i, w in enumerate(widths):
        src_label = f"[{i + 1}:v]"
        prev = "[0:v]" if i == 0 else f"[s{i - 1}]"
        out_label = f"[s{i}]" if i < len(widths) - 1 else ""
        chain += f"{prev}{src_label}overlay={x}:{(total_h - w) // 2}{out_label};"
        x += w + gap
    ff(args + ["-filter_complex", chain.rstrip(";"), "-frames:v", "1", str(row)])
    print(f"  legibility_row.png          {verify(row)}   "
          f"({', '.join(str(s) + 'px' for s in LEGIBILITY_SIZES)}, left to right)")


def main() -> int:
    if not MARK.exists() or not LOCKUP.exists():
        sys.exit(f"missing source art in {BRAND} — run tools/render_logo.gd first")
    OUT.mkdir(parents=True, exist_ok=True)
    LOCKUP_H = build_horizontal_lockup()

    jobs = [
        # ── profile pictures. Mark only: at the ~100px a profile renders at, text is
        # not small, it is absent.
        ("avatar_1024.png",        1024, 1024, MARK,     1108, PAPER, "c"),
        ("avatar_512.png",          512,  512, MARK,      554, PAPER, "c"),

        # ── YouTube channel art.
        # ⚠ THE FIRST ATTEMPT PUT THE WORDMARK OUTSIDE THE SAFE BAND. The vertical
        # lockup at 760px tall overflowed 423, so the phone crop would have shown a
        # headless tower and no name — the classic YouTube banner bug, caught by
        # drawing the safe rectangle over the render and looking at it. A wide canvas
        # also wants a WIDE lockup; a vertical stack squeezed to 423 is small for no
        # reason. 360 tall keeps the whole thing inside 1546x423 with margin.
        ("yt_channel_art.png",     2560, 1440, LOCKUP_H,  360, PAPER, "c"),

        # ── a corner STAMP on transparency, to composite over a frame of the fight.
        # A thumbnail wants the fight as its picture and the mark as a signature; a
        # logo centred on a flat field is the thing nobody clicks.
        ("yt_thumbnail_stamp.png", 1280,  720, LOCKUP_H,  110, None,  "br"),

        ("ig_post_1080.png",       1080, 1080, LOCKUP,    880, PAPER, "c"),
        ("ig_story_1080x1920.png", 1080, 1920, LOCKUP,    980, PAPER, "c"),
        ("x_header_1500x500.png",  1500,  500, LOCKUP_H,  300, PAPER, "c"),
        ("lockup_wide_1900.png",   1900,  520, LOCKUP_H,  460, PAPER, "c"),

        ("favicon_180.png",         180,  180, MARK,      195, PAPER, "c"),
        ("favicon_32.png",           32,   32, MARK,       35, PAPER, "c"),

        # ── the website's link preview. 1200x630 is what every platform crops from
        # when a URL is pasted into a post, a DM or a Discord channel — without it the
        # link renders as a bare grey box, which is the first impression the bio link
        # makes on everyone who has not already decided to click.
        ("og_image_1200x630.png",  1200,  630, LOCKUP_H,  330, PAPER, "c"),
    ]
    print(f"building the kit into {OUT.relative_to(REPO)}\n")
    for name, w, h, art, art_h, bg, pos in jobs:
        dst = OUT / name
        canvas(dst, w, h, art, art_h, bg, pos)
        print(f"  {name:<26} {verify(dst)}")
    print()
    _assert_yt_safe(OUT / "yt_channel_art.png")
    _legibility_sheet()
    print(f"\n{len(jobs)} files. Source of truth is GameLogo.gd -> tools/render_logo.gd.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
