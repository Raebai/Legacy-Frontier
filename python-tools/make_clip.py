#!/usr/bin/env python3
"""Shoot a bot-vs-bot match and encode it — one command, one shareable file.

    python python-tools/make_clip.py                       # the default matchup
    python python-tools/make_clip.py --a 2 --b 3           # BRAWLER vs JUGGERNAUT
    python python-tools/make_clip.py --a 6 --b 5 --hp 320  # a longer bout

WHY THIS EXISTS. Making a clip was three commands with three traps in them: use the
GUI binary or every PNG is blank, remember which of ~69 capture tools films a fight,
then remember an encoder incantation whose defaults produce a file too big to post.
The content engine is only an engine if shooting a clip is one line.

WHAT COMES OUT, and the honest ranking of it:

  MP4 (H.264)  — if `ffmpeg` is on PATH. ~0.3-0.8 MB for five seconds at 720p, plays
                 inline everywhere, and is the ONLY format any of the short-form
                 platforms actually want. This is the format to want.
  GIF          — the fallback, via Pillow. The same five seconds is 7-12 MB with a
                 96-128 colour palette and visible banding on the spell glow, because
                 a palettised format cannot hold an element-tinted bloom.

⚠ SO THE SINGLE BIGGEST WIN AVAILABLE TO THE VIDEO QUALITY OF THIS PROJECT IS
INSTALLING FFMPEG, and it is a human step nobody has taken: `winget install
Gyan.FFmpeg`, restart the shell, done. Godot's own `--write-movie` is not an
alternative — it emits UNCOMPRESSED AVI, about half a gigabyte for seven seconds,
with nothing on the machine able to transcode it. Everything upstream of the encoder
is already ready: the capture renders 1920x1080 PNGs.

⚠ AND THE CLIP HAS NO SOUND, in any format. A PNG sequence carries no audio track, so
every clip this project has ever produced is silent — while the game underneath it has
a 248-key SFX roster, per-weight ducking and a music bed. Recording the game's audio
alongside the frames is not something a frame-grab loop can do; it needs either a real
`MovieWriter` (which is the uncompressed-AVI path) or an OS-level capture. Named here
because "the sound effects need to be improved" cannot be judged from a clip that has
never carried any.

Stdlib + Pillow only.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
GODOT_PROJECT = REPO_ROOT / "godot-project"
# ⚠ THE GUI BUILD, NEVER THE `_console` ONE. Under `--headless` Godot uses the DUMMY
# renderer: the tool runs, reports success, and writes blank PNGs. That failure looks
# exactly like a pass. See python-tools/run_capture.py, which exists for this reason.
GUI_BINARY = REPO_ROOT / "godot-engine" / "Godot_v4.6.2-stable_win64.exe"
PROJECT_NAME = "Legacy Frontier"

CLASSES = ["ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
           "CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT"]


def user_data_dir() -> Path:
    if sys.platform == "win32":
        return Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / PROJECT_NAME
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / PROJECT_NAME
    return Path.home() / ".local" / "share" / "godot" / "app_userdata" / PROJECT_NAME


def shoot(args: argparse.Namespace) -> Path:
    argv = [
        str(GUI_BINARY), "--path", str(GODOT_PROJECT),
        "--script", "tools/directed_clip_capture.gd", "--",
        f"--a={args.a}", f"--b={args.b}", f"--difficulty={args.difficulty}",
        f"--hp={args.hp}", f"--seconds={args.seconds}", f"--fps={args.fps}",
        f"--width={args.width}", f"--height={args.height}", f"--out={args.out}",
    ]
    print(f"shooting {CLASSES[args.a]} vs {CLASSES[args.b]} ...")
    proc = subprocess.run(argv, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=args.timeout)
    for line in (proc.stdout or "").splitlines():
        if line.startswith("[clip]"):
            print("  " + line)
    for line in (proc.stderr or "").splitlines():
        if "SCRIPT ERROR" in line or "Parse Error" in line:
            print("  ! " + line)
    return user_data_dir() / "clips" / args.out


def encode_mp4(frames: Path, out: Path, fps: int, width: int) -> bool:
    """H.264 via ffmpeg. `yuv420p` + an even width because half the players in the
    world refuse anything else, and `-crf 20` because a stick figure on a flat
    background is cheap to encode and there is no reason to be stingy."""
    ff = shutil.which("ffmpeg")
    if ff is None:
        return False
    even = width - (width % 2)
    subprocess.run([
        ff, "-y", "-framerate", str(fps), "-i", str(frames / "f%04d.png"),
        "-vf", f"scale={even}:-2:flags=lanczos", "-c:v", "libx264",
        "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p", str(out),
    ], check=True)
    return True


def encode_gif(frames: Path, out: Path, fps: int, width: int, colors: int) -> None:
    subprocess.run([
        sys.executable, str(REPO_ROOT / "python-tools" / "frames_to_gif.py"),
        str(frames), "--fps", str(fps), "--width", str(width),
        "--colors", str(colors), "--out", str(out),
    ], check=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", type=int, default=6, help="left fighter's class id (0-8)")
    ap.add_argument("--b", type=int, default=5, help="right fighter's class id (0-8)")
    ap.add_argument("--difficulty", type=int, default=3)
    # 260 -> 500: at 260 the median bot duel is 8.7s and 14% of clips are over
    # before the director's is_hot() latches. Measured, 36 bouts per row on the
    # real BotMatch:  hp 260 -> p10 3.5 / median 8.7 / p90 15.4, 14% under 5s;
    #                 hp 500 -> p10 9.7 / median 15.7 / p90 25.6, 0% under 5s.
    # 500 is the first setting where every clip has an approach, an exchange and
    # a finish. A CAPTURE parameter only — it changes nothing about how it plays.
    ap.add_argument("--hp", type=int, default=500,
                    help="shared HP pool; BotMatch.CLASS_VITALITY scales it per class")
    # 16 -> 28 so the budget covers the p90 fight instead of truncating it.
    ap.add_argument("--seconds", type=float, default=28.0, help="max clip length")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--width", type=int, default=1920, help="RENDER width")
    ap.add_argument("--height", type=int, default=1080)
    ap.add_argument("--share-width", type=int, default=720, help="ENCODED width")
    ap.add_argument("--colors", type=int, default=96, help="GIF palette size")
    ap.add_argument("--out", default="directed", help="subfolder under user://clips")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--no-shoot", action="store_true", help="re-encode existing frames")
    args = ap.parse_args()

    if not GUI_BINARY.exists():
        print(f"error: GUI binary not found at {GUI_BINARY}")
        return 2
    if not (0 <= args.a < len(CLASSES)) or not (0 <= args.b < len(CLASSES)):
        print(f"error: class ids must be 0..{len(CLASSES) - 1}")
        return 2

    frames = user_data_dir() / "clips" / args.out
    if not args.no_shoot:
        frames = shoot(args)
    if not frames.is_dir() or not any(frames.glob("*.png")):
        print(f"NO FRAMES in {frames}. If the run reported success anyway, it was the")
        print("headless binary — the dummy renderer draws nothing.")
        return 3

    stem = frames.parent / f"{CLASSES[args.a].lower()}_vs_{CLASSES[args.b].lower()}"
    mp4 = stem.with_suffix(".mp4")
    if encode_mp4(frames, mp4, args.fps, args.share_width):
        print(f"\nwrote {mp4}  ({mp4.stat().st_size / 1_048_576:.1f} MB)")
        print("that is the file to post.")
        return 0
    gif = stem.with_suffix(".gif")
    encode_gif(frames, gif, args.fps, args.share_width, args.colors)
    print("\nffmpeg is NOT installed, so this is a GIF — several times the size of the")
    print("MP4 it should be, with a palettised version of the spell colour.")
    print("  winget install Gyan.FFmpeg    (then reopen the shell and re-run)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
