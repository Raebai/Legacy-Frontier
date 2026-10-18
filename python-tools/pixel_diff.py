#!/usr/bin/env python3
"""Pixel-diff two capture PNGs, and refuse to grade a blank one.

The editor loop this repo needs is: change something, run the game, capture a
frame, and compare it against the last frame to see whether what you changed is
what moved. The comparison is this file.

⚠ THE GUARD THAT IS THE POINT OF THIS TOOL. A naive differ reports "0.00%
different — identical" for two blank images, which is exactly what you get when a
capture ran under `--headless` (the dummy renderer draws nothing, every tool still
reports success, every PNG is empty). That reading is indistinguishable from a
clean pass, and this project has been burned by precisely that shape of lie more
than once. So before any comparison, each input must prove it contains a drawn
image: enough distinct colours and enough spread to not be a flat fill. A blank
input is exit code 2 and a named refusal, never a pass.

    python python-tools/pixel_diff.py a.png b.png
    python python-tools/pixel_diff.py a.png b.png --out proof/run/diff.png
    python python-tools/pixel_diff.py --snapshot boss_p1 boss_p2 boss_p3
    python python-tools/pixel_diff.py --against-baseline boss_p1

Exit codes, so this can stand in as a guard in a script:
    0  both images are drawn, and they match within tolerance
    1  both images are drawn, and they differ
    2  an input is unusable (missing, blank, or a different size)

Stdlib + Pillow, matching the other image tools here (clip_review, frames_to_gif).
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

from PIL import Image

from godot_paths import user_data_dir

# Windows cp1252 stdout chokes on the arrows and dashes below.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
BASELINE_DIR = REPO_ROOT / "proof" / "_baseline"

# ── The blank-image guard ───────────────────────────────────────────────────
# A real Stickspire frame is white line-art over a painted silhouette backdrop:
# hundreds of distinct colours at minimum, usually thousands. A dummy-renderer
# PNG is one colour. The thresholds sit far below any real frame and far above
# any flat fill, so neither a dark biome nor a bright one trips them.
MIN_DISTINCT_COLOURS = 24
MIN_DYNAMIC_RANGE = 24  # max luma minus min luma, 0-255


def _luma(px: tuple[int, int, int]) -> float:
    return 0.2126 * px[0] + 0.7152 * px[1] + 0.0722 * px[2]


class Blank(Exception):
    """An input that cannot be graded, with the reason a human needs."""


def load_drawn(path: Path) -> Image.Image:
    """Load a PNG as RGB, or raise Blank naming why it is not a drawn frame."""
    if not path.exists():
        raise Blank(f"{path} does not exist — the capture did not write it")
    if path.stat().st_size == 0:
        raise Blank(f"{path} is a zero-byte file")

    img = Image.open(path).convert("RGB")
    colours = img.getcolors(maxcolors=1 << 24)
    if colours is None:  # more colours than the cap: definitively not blank
        return img

    distinct = len(colours)
    lumas = [_luma(c) for _, c in colours]
    dynamic_range = max(lumas) - min(lumas)

    if distinct < MIN_DISTINCT_COLOURS or dynamic_range < MIN_DYNAMIC_RANGE:
        raise Blank(
            f"{path.name} is not a drawn frame: {distinct} distinct colour(s), "
            f"luma range {dynamic_range:.0f}/255.\n"
            f"    That is the signature of a capture run under --headless (the dummy\n"
            f"    renderer draws nothing and still reports success). Re-run the\n"
            f"    capture with the GUI binary via run_capture.py, which refuses to\n"
            f"    use the console build."
        )
    return img


def diff(
    path_a: Path,
    path_b: Path,
    out: Path | None,
    tolerance: int,
    fail_over_pct: float,
) -> int:
    """Compare two drawn frames. Returns the process exit code."""
    try:
        a = load_drawn(path_a)
        b = load_drawn(path_b)
    except Blank as e:
        print(f"UNUSABLE: {e}")
        return 2

    if a.size != b.size:
        print(
            f"UNUSABLE: sizes differ — {path_a.name} is {a.size[0]}x{a.size[1]}, "
            f"{path_b.name} is {b.size[0]}x{b.size[1]}. "
            "A resolution change makes a per-pixel diff meaningless."
        )
        return 2

    pa, pb = a.load(), b.load()
    w, h = a.size
    total = w * h

    changed = 0
    max_delta = 0
    sum_delta = 0
    heat = Image.new("RGB", (w, h)) if out else None
    hp = heat.load() if heat else None

    for y in range(h):
        for x in range(w):
            ra, ga, ba = pa[x, y]
            rb, gb, bb = pb[x, y]
            d = max(abs(ra - rb), abs(ga - gb), abs(ba - bb))
            sum_delta += d
            if d > max_delta:
                max_delta = d
            if d > tolerance:
                changed += 1
            if hp is not None:
                # Amplified so a 3-value shift is visible to an eye, not just a
                # number. Red channel carries the delta; unchanged pixels stay a
                # dim grey copy of the original so the diff is readable in place.
                amp = min(255, d * 8)
                base = (ra + ga + ba) // 9
                hp[x, y] = (max(amp, base), base, base)

    pct = 100.0 * changed / total
    mean = sum_delta / total

    print(f"A:  {path_a}")
    print(f"B:  {path_b}")
    print(f"    {w}x{h}, {total:,} px — both inputs confirmed drawn (not blank)")
    print(
        f"    changed: {changed:,} px ({pct:.3f}%) over tolerance {tolerance}; "
        f"max delta {max_delta}, mean delta {mean:.3f}"
    )

    if heat and out:
        out.parent.mkdir(parents=True, exist_ok=True)
        heat.save(out)
        print(f"    heatmap -> {out}")

    if pct > fail_over_pct:
        print(f"DIFFERENT: {pct:.3f}% of pixels moved (over the {fail_over_pct}% gate).")
        return 1
    print(f"MATCH: within the {fail_over_pct}% gate.")
    return 0


def resolve(name: str) -> Path:
    """A bare capture name means the PNG the engine just wrote to user://."""
    p = Path(name)
    if p.suffix == ".png" and (p.exists() or p.is_absolute() or len(p.parts) > 1):
        return p
    return Path(user_data_dir()) / (name if name.endswith(".png") else f"{name}.png")


def snapshot(names: list[str]) -> int:
    """Copy the current user:// captures into the committed baseline folder."""
    BASELINE_DIR.mkdir(parents=True, exist_ok=True)
    rc = 0
    for n in names:
        src = resolve(n)
        try:
            load_drawn(src)  # never baseline a blank frame
        except Blank as e:
            print(f"REFUSED: {e}")
            rc = 2
            continue
        dst = BASELINE_DIR / src.name
        shutil.copy2(src, dst)
        print(f"baseline <- {src.name} ({dst.stat().st_size:,} bytes)")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("images", nargs="*", help="two PNGs, or capture names under user://")
    ap.add_argument("--out", type=Path, help="write a diff heatmap PNG here")
    ap.add_argument(
        "--tolerance", type=int, default=2,
        help="per-channel delta a pixel may move and still count as unchanged (default 2)",
    )
    ap.add_argument(
        "--fail-over", type=float, default=0.5, metavar="PCT",
        help="exit 1 when more than this %% of pixels changed (default 0.5)",
    )
    ap.add_argument("--snapshot", action="store_true", help="copy captures into the baseline")
    ap.add_argument("--against-baseline", action="store_true", help="diff a capture vs its baseline")
    args = ap.parse_args()

    if args.snapshot:
        if not args.images:
            print("--snapshot needs at least one capture name")
            return 2
        return snapshot(args.images)

    if args.against_baseline:
        if len(args.images) != 1:
            print("--against-baseline takes exactly one capture name")
            return 2
        cur = resolve(args.images[0])
        base = BASELINE_DIR / cur.name
        if not base.exists():
            print(f"No baseline for {cur.name}. Record one: --snapshot {args.images[0]}")
            return 2
        return diff(base, cur, args.out, args.tolerance, args.fail_over)

    if len(args.images) != 2:
        ap.print_help()
        return 2
    return diff(resolve(args.images[0]), resolve(args.images[1]),
                args.out, args.tolerance, args.fail_over)


if __name__ == "__main__":
    sys.exit(main())
