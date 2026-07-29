#!/usr/bin/env python3
"""Encode a Godot PNG frame sequence into a watchable animated GIF (and APNG).

    python python-tools/frames_to_gif.py <frames_dir> [--out FILE] [--fps 30]
                                         [--width 720] [--colors 128] [--skip N]

WHY GIF AND NOT A VIDEO FILE. ffmpeg is not installed on this machine, and
Godot's own `--write-movie` MovieWriter emits UNCOMPRESSED AVI — about half a
gigabyte for seven seconds at 1365x768, with nothing available to transcode it.
Pillow is installed, so a PNG sequence is the only route that ends in a single
file somebody can double-click. GIF plays inline in a browser, in Slack, in
Discord and on GitHub, which is exactly where a clip like this needs to go.

An APNG is written alongside it when `--apng` is passed: same frames, true colour
instead of a 128-entry palette, at roughly 3-4x the size. Worth it when the shot
is full of element-tinted glow that a palette flattens into banding.

THE SIZE PROBLEM AND HOW IT IS HANDLED. A 300-frame GIF at full resolution is
enormous. Three levers, in the order they cost the least quality:
  1. downscale to --width (default 720) with LANCZOS,
  2. quantise to --colors using a MEDIANCUT palette computed from a sample of
     frames rather than from frame 0 alone (a palette built from one frame turns
     every later spell colour into the nearest wrong thing),
  3. drop frames with --skip.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - environment guard
    sys.exit("Pillow is required: py -m pip install Pillow")


def load_frames(folder: Path, skip: int, width: int,
                start: int = 0, end: int = 0) -> list[Image.Image]:
    """Read f####.png in name order, trimmed to [start, end), downscaled to `width`.

    The trim exists because a capture and a CLIP are not the same thing. A run
    records whatever the bots did for as long as the camera rolled; the watchable
    part is a window inside that, and choosing the window is an editorial act that
    belongs here rather than in the capture (re-running a two-minute render to
    move an in-point is a bad trade).
    """
    paths = sorted(folder.glob("*.png"))
    if not paths:
        sys.exit(f"no PNG frames in {folder}")
    paths = paths[start:(end or len(paths))]
    if not paths:
        sys.exit(f"trim [{start}:{end}] selected no frames")
    if skip > 1:
        paths = paths[::skip]
    frames: list[Image.Image] = []
    for p in paths:
        img = Image.open(p).convert("RGB")
        if width and img.width > width:
            height = round(img.height * width / img.width)
            img = img.resize((width, height), Image.LANCZOS)
        frames.append(img)
    return frames


def build_palette(frames: list[Image.Image], colors: int) -> Image.Image:
    """Compute ONE palette from frames sampled across the whole clip.

    Quantising each frame independently makes the palette jump every frame and
    the clip shimmer; quantising everything to frame 0's palette loses every
    colour that only appears later — which in this game is most of them, because
    the spells are the colour. So the palette comes from a vertical strip-stack
    of ~12 frames spread evenly through the sequence.
    """
    step = max(1, len(frames) // 12)
    sample = frames[::step][:12] or frames[:1]
    w = sample[0].width
    stack = Image.new("RGB", (w, sample[0].height * len(sample)))
    for i, f in enumerate(sample):
        stack.paste(f, (0, f.height * i))
    return stack.quantize(colors=colors, method=Image.MEDIANCUT)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("frames_dir")
    ap.add_argument("--out", default=None, help="output .gif path")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--width", type=int, default=720)
    ap.add_argument("--colors", type=int, default=128)
    ap.add_argument("--skip", type=int, default=1, help="keep every Nth frame")
    ap.add_argument("--start", type=int, default=0, help="first frame index to keep")
    ap.add_argument("--end", type=int, default=0, help="stop before this index (0 = to the end)")
    ap.add_argument("--apng", action="store_true", help="also write a true-colour APNG")
    args = ap.parse_args()

    folder = Path(args.frames_dir)
    out = Path(args.out) if args.out else folder.with_suffix(".gif")
    out.parent.mkdir(parents=True, exist_ok=True)

    frames = load_frames(folder, args.skip, args.width, args.start, args.end)
    print(f"loaded {len(frames)} frames at {frames[0].width}x{frames[0].height}")

    palette = build_palette(frames, args.colors)
    quantised = [f.quantize(palette=palette, dither=Image.FLOYDSTEINBERG) for f in frames]

    duration_ms = max(20, round(1000 / max(args.fps, 1)))
    quantised[0].save(
        out, save_all=True, append_images=quantised[1:],
        duration=duration_ms, loop=0, optimize=True, disposal=2,
    )
    print(f"wrote {out}  ({out.stat().st_size / 1_048_576:.1f} MB, "
          f"{len(frames)} frames @ {args.fps} fps)")

    if args.apng:
        apng = out.with_suffix(".png")
        frames[0].save(apng, save_all=True, append_images=frames[1:],
                       duration=duration_ms, loop=0)
        print(f"wrote {apng}  ({apng.stat().st_size / 1_048_576:.1f} MB, true colour)")


if __name__ == "__main__":
    main()
