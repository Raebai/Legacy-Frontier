"""
Shrink the music bed — the single biggest size win left in the build.

THE NUMBERS (measured in this repo, 2026-07-31)
-----------------------------------------------
Shipping audio is about 45 MB. **36.4 MB of it — roughly 81% — is six MP3s**:

    boss_theme        9.4 MB   320 kbps
    unexplored_moon   8.3 MB   256 kbps
    lord_of_the_land  6.0 MB   192 kbps
    for_tomorrow      5.3 MB   256 kbps
    combat_theme      5.3 MB   256 kbps
    arcadia           4.0 MB   192 kbps

The 187 sound effects cost 4.0 MB *combined*, because Godot 4.6 imports WAV as
QOA. So the SFX are already fine and the music is the entire problem.

Re-encoding to ~96-112 kbps Ogg Vorbis saves roughly **17-20 MB, about 40% of
the whole build**. On a phone, mixing a bed 20-28 dB down under the SFX, 320 kbps
buys nothing an ear can find.

HOW IT LANDS IN THE GAME
------------------------
`Music.gd` still lists the `.mp3` paths. `Music._preferred_path()` prefers a
same-named `.ogg` sitting beside each one — so this script needs no code change
to take effect, and deleting the six `.ogg` files rolls the whole thing back.
That matters because this is a LOSSY-ON-LOSSY conversion and the only real test
is a pair of ears.

HONESTY NOTE
------------
**This has not been run in this repo. ffmpeg is not installed on this machine,
and nobody has heard the result.** The script refuses to run without ffmpeg
rather than pretending it worked. On Windows:  winget install Gyan.FFmpeg

Originals are copied to `audio-source/raw/music-originals/` first, which is
gitignored — so the source-quality files survive locally even though the repo
only ever needs one copy.

Run:
    python python-tools/compress_music.py            # 112 kbps (conservative)
    python python-tools/compress_music.py --bitrate 96
    python python-tools/compress_music.py --dry-run
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MUSIC_DIR = REPO_ROOT / "godot-project" / "assets" / "audio" / "music"
BACKUP_DIR = REPO_ROOT / "audio-source" / "raw" / "music-originals"

## The six tracks Music.gd's PLAYLISTS name. Listed explicitly rather than
## globbed so a stray experiment dropped in the folder is never silently
## re-encoded and shipped.
TRACKS: list[str] = [
    "arcadia",
    "lord_of_the_land",
    "for_tomorrow",
    "unexplored_moon",
    "combat_theme",
    "boss_theme",
]

## Conservative by default. This is lossy-on-lossy: the source is already an MP3,
## so the artefacts compound. 112 kbps Vorbis is roughly transparent for a music
## bed that never sits at the front of the mix; 96 saves a little more and is
## where a careful listener might start to hear the cymbals smear.
DEFAULT_BITRATE = 112


def have_ffmpeg() -> str | None:
    return shutil.which("ffmpeg")


def human(n: int) -> str:
    return f"{n / 1048576:.2f} MB"


def main() -> int:
    ap = argparse.ArgumentParser(description="Re-encode the music bed to Ogg Vorbis.")
    ap.add_argument("--bitrate", type=int, default=DEFAULT_BITRATE,
                    help=f"target kbps (default {DEFAULT_BITRATE})")
    ap.add_argument("--dry-run", action="store_true", help="report, change nothing")
    args = ap.parse_args()

    ffmpeg = have_ffmpeg()
    if ffmpeg is None and not args.dry_run:
        print(
            "ffmpeg not found on PATH — refusing to guess.\n"
            "  Windows:  winget install Gyan.FFmpeg\n"
            "  macOS:    brew install ffmpeg\n"
            "  Linux:    apt install ffmpeg\n"
            "Then re-run this script.",
            file=sys.stderr,
        )
        return 1

    before = 0
    after = 0
    for name in TRACKS:
        src = MUSIC_DIR / f"{name}.mp3"
        dst = MUSIC_DIR / f"{name}.ogg"
        if not src.exists():
            print(f"skip {name}: no {src.name}")
            continue
        size = src.stat().st_size
        before += size
        if args.dry_run:
            print(f"would encode {src.name} ({human(size)}) -> {dst.name} @ {args.bitrate}k")
            continue

        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        backup = BACKUP_DIR / src.name
        if not backup.exists():
            shutil.copy2(src, backup)

        cmd = [
            ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
            "-i", str(src),
            "-vn",                       # drop any embedded cover art
            "-c:a", "libvorbis",
            "-b:a", f"{args.bitrate}k",
            "-ar", "44100",
            str(dst),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            print(f"FAILED {src.name}: {proc.stderr.strip()}", file=sys.stderr)
            return 1
        out = dst.stat().st_size
        after += out
        print(f"{src.name} {human(size)} -> {dst.name} {human(out)}")

    if args.dry_run:
        print(f"\ntotal mp3: {human(before)}  (dry run — nothing written)")
        print("ffmpeg " + ("found: " + str(ffmpeg) if ffmpeg else "NOT FOUND"))
        return 0

    print(f"\nbefore {human(before)}  after {human(after)}  saved {human(before - after)}")
    print("originals copied to", BACKUP_DIR)
    print(
        "\nNEXT: import the project, then LISTEN to all six in game before deleting\n"
        "the .mp3 files. Music.gd prefers the .ogg automatically; removing the\n"
        "six .ogg files rolls the change back completely."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
