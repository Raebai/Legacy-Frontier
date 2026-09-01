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

✅ THE CLIP HAS SOUND NOW, and it did not for this project's entire life. This block
used to read "AND THE CLIP HAS NO SOUND, in any format... every clip this project has
ever produced is silent", and it was right: a PNG sequence carries no audio track, so a
248-key SFX roster, per-weight ducking and a music bed could not be judged from any
clip ever shot.

The default path is now Godot's own **Movie Maker** (`--write-movie`), which records a
PCM stereo track alongside the frames. Measured on the first take: 48 kHz, 2ch, mean
-18.1 dB / max -7.1 dB — a real mix, not an empty track.

⚠ IT IS NOT A SCREEN RECORDING, AND THAT DISTINCTION IS THE WHOLE POINT.
`--write-movie` FORCES `--fixed-fps`: the engine's delta is pinned, so every frame is
exactly 1/fps of movie however long it actually took to draw. An OS-level screen
grabber (OBS, ffmpeg gdigrab) captures whatever the machine managed in real time —
about 19 fps at 1080p — which is precisely the judder this pipeline just spent a fix
removing. Faster to set up, worse to watch.

The old objection to MovieWriter recorded here ("emits UNCOMPRESSED AVI, about half a
gigabyte for seven seconds, with nothing on the machine able to transcode it") was
STALE ON BOTH COUNTS: the built-in writer is MJPEG rather than raw, and ffmpeg is on
PATH now. `--silent` still runs the old frame-grab, which renders an offscreen
1920x1080 regardless of window size.

Stdlib + Pillow only.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

# ⚠ DERIVED FROM project.godot, NEVER HARDCODED. This module was a `PROJECT_NAME =
# "Legacy Frontier"` constant, and it stayed that way after the game was renamed to
# Ashpire — so the shoot wrote frames to one directory and the encoder read a
# DIFFERENT one that still existed from before the rename. The result was a clip of
# a fight from weeks earlier, encoded and announced as a success. See
# python-tools/godot_paths.py for the full account.
from godot_paths import user_data_dir

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
GODOT_PROJECT = REPO_ROOT / "godot-project"
# ⚠ THE GUI BUILD, NEVER THE `_console` ONE. Under `--headless` Godot uses the DUMMY
# renderer: the tool runs, reports success, and writes blank PNGs. That failure looks
# exactly like a pass. See python-tools/run_capture.py, which exists for this reason.
GUI_BINARY = REPO_ROOT / "godot-engine" / "Godot_v4.6.2-stable_win64.exe"

CLASSES = ["ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
           "CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT"]

# The engine's pinned render rate during a movie shoot, and therefore the AVI's
# frame rate and the unit `movie_in`/`movie_out` are counted in. It is NOT the
# director's save rate (`--fps`, default 30) and the two must never be swapped.
MOVIE_FPS = 60


import contextlib  # noqa: E402  (used by render_size_override below)

PROJECT_FILE = GODOT_PROJECT / "project.godot"


@contextlib.contextmanager
def render_size_override(width: int, height: int):
    """Force the MOVIE's output size, which NOTHING ELSE IN THIS FILE CAN DO.

    ⚠ `--resolution` DOES NOT WORK, AND EVERY MOVIE-PATH CLIP THIS PROJECT HAS
    EVER PRODUCED WAS 1366x768 NO MATTER WHAT WAS ASKED FOR. Measured, three
    times: asking for 1920x1080, 573x1019 and 1080x1017 on the command line all
    returned a 1366x768 AVI — which is exactly `window/size/window_*_override` in
    project.godot. MovieWriter fixes its output dimensions at engine start from
    that setting and never looks at the window again, so the script's own
    `_set_render_size()` (which runs later, and DOES resize the window and the
    root viewport) moves the game's framing without moving the recording.

    That combination is the worst of both: `directed_clip_capture` detected a
    PORTRAIT viewport and composed a portrait shot, and the recorder wrote it into
    a LANDSCAPE frame. The delivered file was 1080x608 with the fighters at ~3% of
    frame height, and the pipeline announced it as a success.

    So the size is set where MovieWriter actually reads it. The override is
    accepted even when the window cannot physically fit — verified by asking for
    1080x1920 on a 1707x1019 desktop and getting a 1080x1920 movie back.

    ⚠ THIS EDITS A TRACKED FILE, so it restores in a `finally` and REFUSES TO RUN
    if project.godot already has uncommitted changes. A crash mid-shoot must not
    leave the maker's project on a phone-shaped window, and a concurrent session
    sharing this checkout must not have its own edit reverted underneath it.

    ⚠ `newline=""` ON BOTH ENDS, AND IT IS LOAD-BEARING. `.gitattributes` pins
    project.godot to `eol=lf`, but `write_text` in text mode translates every `\n`
    to `os.linesep` — CRLF on Windows. So the "restore" wrote back a file that was
    byte-for-byte different from the one it read: same content, 230 line endings
    flipped. `git status` then showed ` M godot-project/project.godot` for ever
    after while `git diff` showed nothing, which cost more than one session a
    detour and got written into the handoff notes as an unexplained quirk (with
    the direction backwards - the restore made it CRLF, not LF). With
    `newline=""` the round trip is exact and the file stops churning.
    """
    original = PROJECT_FILE.read_text(encoding="utf-8", newline="")
    if (f"window_width_override={width}\n" in original
            and f"window_height_override={height}\n" in original):
        yield                                  # already right; touch nothing
        return
    dirty = subprocess.run(["git", "diff", "--quiet", "--", str(PROJECT_FILE)],
                           cwd=str(REPO_ROOT)).returncode != 0
    if dirty:
        raise SystemExit(
            "project.godot has uncommitted changes, and this shoot needs to edit "
            "it.\nCommit or stash them first — refusing to risk clobbering them.")
    patched = original
    for key, value in (("window_width_override", width),
                       ("window_height_override", height)):
        head, sep, tail = patched.partition(f"window/size/{key}=")
        if not sep:
            raise SystemExit(f"project.godot has no window/size/{key}")
        patched = head + sep + str(value) + tail[tail.index("\n"):]
    try:
        PROJECT_FILE.write_text(patched, encoding="utf-8", newline="")
        yield
    finally:
        PROJECT_FILE.write_text(original, encoding="utf-8", newline="")


def shoot_movie(args: argparse.Namespace) -> tuple[Path, int, int] | None:
    """Godot's OWN Movie Maker (`--write-movie`), which is strictly better than the
    frame-grab for the one thing the frame-grab structurally cannot do: **SOUND**.

    ⚠ EVERY CLIP THIS PROJECT HAD EVER PRODUCED WAS SILENT, and this file used to say
    so — a PNG sequence carries no audio track, so a 248-key SFX roster, per-weight
    ducking and a music bed could not be judged from any clip ever shot. Godot's
    built-in MJPEG-AVI writer records a PCM stereo track alongside the frames.
    Measured on the first take: 48 kHz, 2ch, mean -18.1 dB / max -7.1 dB — a real mix,
    not an empty track.

    ⚠ AND IT IS NOT A SCREEN RECORDING. `--write-movie` FORCES `--fixed-fps`, so the
    engine's delta is pinned and every frame is exactly 1/fps of movie no matter how
    long it actually took to draw. An OS-level screen grabber would capture whatever
    the machine managed in real time — which at 1080p is ~19 fps — and would put back
    exactly the judder this pipeline just spent a fix removing.

    The old objection in this file's header ("uncompressed AVI, half a gigabyte, with
    nothing on the machine able to transcode it") is STALE on both counts: the writer
    is MJPEG, not raw, and ffmpeg is on PATH now.

    The cost is real and worth stating: it records the whole PROCESS lifetime — boot,
    import, scene build — so a movie runs ~9 s longer than the clip inside it, and it
    captures the WINDOW rather than an offscreen 1920x1080 viewport. The trim is exact
    (see `movie_in`/`movie_out`), and the window is downscaled to `--share-width`
    anyway, so neither costs anything in the delivered file.
    """
    avi = user_data_dir() / "clips" / f"{args.out}.avi"
    avi.parent.mkdir(parents=True, exist_ok=True)
    argv = [
        str(GUI_BINARY), "--path", str(GODOT_PROJECT),
        # ⚠ 60, NOT `args.fps`, AND THE DIFFERENCE IS A FACTOR OF TWO IN EVERY
        # DURATION THE DIRECTOR REPORTS.
        #
        # `directed_clip_capture` saves one frame in `round(60 / fps)` and calls
        # `_saved / fps` the clip's length — an assumption that the engine renders
        # 60 fps. `--fixed-fps 30` pinned it to 30 instead, so the director skipped
        # every 2nd frame of a 30 fps stream and its clock ran at HALF real time,
        # while MovieWriter (which records every rendered frame) wrote all of them.
        #
        # Measured: a shoot that reported "DONE — 356 frames (11.9s)" delivered a
        # 24.5 s file, whose last NINE SECONDS were an empty stage — the director's
        # 3 s result-hold spent at half speed. `--seconds` was doubled the same way.
        # Nothing warned; the numbers in the log were self-consistent and wrong.
        "--write-movie", str(avi), "--fixed-fps", "60",
        # `--resolution` is INERT for the movie — see render_size_override().
        "--script", "tools/directed_clip_capture.gd", "--",
        f"--a={args.a}", f"--b={args.b}", f"--difficulty={args.difficulty}",
        f"--hp={args.hp}", f"--seconds={args.seconds}", f"--fps={args.fps}",
        f"--intro={args.intro}",
        f"--width={args.width}", f"--height={args.height}", f"--out={args.out}",
        f"--random={1 if args.random else 0}",
    ]
    what = "a rolled matchup" if args.random         else f"{CLASSES[args.a]} vs {CLASSES[args.b]}"
    print(f"shooting {what} (with sound) at {args.width}x{args.height} ...")
    with render_size_override(args.width, args.height):
        proc = subprocess.run(argv, capture_output=True, text=True,
                              encoding="utf-8", errors="replace",
                              timeout=args.timeout)
    m_in, m_out = -1, -1
    for line in (proc.stdout or "").splitlines():
        # ⚠ `[fight]` IS FORWARDED TOO, AND IT HAS TO BE. `BotMatch` prints one verdict
        # line per bout from `FightScore` — whether the fight was worth publishing — and
        # `make_post.py --takes N` re-rolls on it. This filter passed `[clip]` only, so
        # the verdict was swallowed one layer down and the re-roll fell through to its
        # "no verdict reported; keeping this take" fallback on EVERY shoot. The gate was
        # built, wired and reported nothing, which is the quietest way for a quality
        # gate to fail.
        if line.startswith("[fight]"):
            print("  " + line)
            continue
        if line.startswith("[clip]"):
            print("  " + line)
            if "movie_in" in line:
                m_in = int(line.rsplit(" ", 1)[1])
            elif "movie_out" in line:
                m_out = int(line.rsplit(" ", 1)[1])
            elif line.startswith("[clip] matchup "):
                # ⚠ NAME THE FILE AFTER THE FIGHT THAT HAPPENED. Under `--random` the
                # scene rolls the pair in its own `_ready`, so `args.a`/`args.b` are
                # the request and not the result — naming from them would file a
                # Warlock/Cleric bout as `stormcaller_vs_cryomancer.mp4`.
                bits = line.split()
                args.a, args.b = int(bits[2]), int(bits[3])
    for line in (proc.stderr or "").splitlines():
        if "SCRIPT ERROR" in line or "Parse Error" in line:
            print("  ! " + line)
    if not avi.exists() or m_in < 0 or m_out <= m_in:
        print(f"  ! movie capture produced nothing usable (in={m_in} out={m_out})")
        return None
    return avi, m_in, m_out


def encode_from_movie(avi: Path, out: Path, fps: int, width: int,
                      m_in: int, m_out: int) -> bool:
    """Trim the recorded movie to the clip window and transcode to H.264 + AAC.

    `-ss` BEFORE `-i` seeks on the input, which is fast and — because MJPEG is
    all-intra — frame-exact here, with none of the keyframe rounding that would make
    this approximate on an inter-coded source."""
    ff = shutil.which("ffmpeg")
    if ff is None:
        return False
    even = width - (width % 2)
    start = m_in / float(fps)
    dur = (m_out - m_in) / float(fps)
    subprocess.run([
        ff, "-y", "-ss", f"{start:.3f}", "-t", f"{dur:.3f}", "-i", str(avi),
        # ⚠ VISUALLY LOSSLESS, BECAUSE THIS FILE IS AN INTERMEDIATE.
        # `make_post` re-encodes it twice more (the speed conform, then the delivery
        # mux, which must re-encode because it draws the title card). Three lossy
        # generations at crf 20/18/20 compound, and what compounding eats first is
        # thin high-contrast lines — which is the entire art style of this game.
        # crf 14 here costs disk on a throwaway file and nothing else.
        "-vf", f"scale={even}:-2:flags=lanczos", "-c:v", "libx264",
        "-preset", "slow", "-crf", "14", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "160k", str(out),
    ], check=True)
    return True


def shoot(args: argparse.Namespace) -> Path:
    argv = [
        str(GUI_BINARY), "--path", str(GODOT_PROJECT),
        # ⚠ WITHOUT THIS THE CLIP PLAYS AT ~3x FAST-FORWARD, AND NOTHING SAYS SO.
        #
        # `directed_clip_capture.gd` decides which rendered frames to save with
        # `every = round(60 / fps)` — i.e. it ASSUMES the renderer delivers 60 fps and
        # that saving every 2nd frame gives 30 fps of game time. At 1920x1080 it does
        # not: the capture renders ~19 fps while physics still runs at 60 Hz, so every
        # 2nd saved frame samples the game at ~9.7 Hz and is then replayed at 30.
        #
        # MEASURED, by timestamping the same KO with two clocks out of `clip.json`
        # (the director's `knockdown_at` in game seconds vs the tool's own
        # frames-walked/60):  2.63x, 2.67x, and 3.09x on an unloaded machine. A 17.5 s
        # Brawler-vs-Juggernaut fight was delivered as a 7.4 s clip.
        #
        # `--fixed-fps 60` pins the engine's delta to 1/60 regardless of how long a
        # frame actually took to draw, which is exactly what an offline frame-grab
        # wants. Verified after: ratio 0.83x (hit-stop now correctly reads as slow-mo
        # rather than being eaten), and the share of near-identical still frames fell
        # from 60% to 8% on its own.
        "--fixed-fps", "60",
        "--script", "tools/directed_clip_capture.gd", "--",
        f"--a={args.a}", f"--b={args.b}", f"--difficulty={args.difficulty}",
        f"--hp={args.hp}", f"--seconds={args.seconds}", f"--fps={args.fps}",
        f"--intro={args.intro}",
        f"--width={args.width}", f"--height={args.height}", f"--out={args.out}",
        f"--random={1 if args.random else 0}",
    ]
    what = "a rolled matchup" if args.random         else f"{CLASSES[args.a]} vs {CLASSES[args.b]}"
    print(f"shooting {what} ...")
    proc = subprocess.run(argv, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=args.timeout)
    for line in (proc.stdout or "").splitlines():
        if line.startswith("[clip]") or line.startswith("[fight]"):
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
    # ⚠ A CONTENT ENGINE THAT ALWAYS SHOOTS THE SAME PAIR MAKES ONE CLIP N TIMES.
    # `--a 6 --b 5` is a sensible default for a repeatable shot and a terrible one
    # for a batch: nine classes, and every clip ever produced by this tool without
    # explicit ids has been STORMCALLER vs CRYOMANCER.
    ap.add_argument("--random", action="store_true",
                    help="roll the matchup (ignores --a/--b)")
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
    # ⚠ 600 -> 1800, AND IT FAILED SILENTLY AT 600. `--fixed-fps 60` pins the engine's
    # delta so the capture is correct, but it also means a full-length shoot renders
    # every one of ~1700 engine frames at 1920x1080 rather than skipping — which is
    # slower in WALL-CLOCK than the old (wrong) capture ever was.
    #
    # Measured: a Brawler-vs-Juggernaut shoot wrote 838 frames and was then killed by
    # this timeout. `subprocess.run` raises TimeoutExpired, the traceback went to a
    # stderr nobody was reading, and the batch simply moved on with no mp4 and no
    # message. A capture that dies without saying so is the same failure class as the
    # stale-directory bug above.
    #
    # ⚠ AND THE UNDERLYING REASON THAT FIGHT RAN LONG IS A BALANCE CHANGE: with the
    # re-tuned CLASS_VITALITY, a Brawler (1.30) and a Juggernaut (1.20) carry 650 and
    # 600 effective HP at `--hp 500`, and two melee classes cannot close that inside
    # the 28 s budget. For a melee mirror, pass a lower `--hp`.
    ap.add_argument("--intro", type=float, default=0.0,
                    help="hold the frozen VS card this long before the bell, so a "
                         "voice-over can finish before the fight starts (0 = as authored)")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--no-shoot", action="store_true", help="re-encode existing frames")
    ap.add_argument("--silent", action="store_true",
                    help="use the old PNG frame-grab path (no audio, offscreen 1080p)")
    ap.add_argument("--keep-avi", action="store_true",
                    help="keep the intermediate movie (it is large — MJPEG, ~3MB/s)")
    args = ap.parse_args()

    if not GUI_BINARY.exists():
        print(f"error: GUI binary not found at {GUI_BINARY}")
        return 2
    if not (0 <= args.a < len(CLASSES)) or not (0 <= args.b < len(CLASSES)):
        print(f"error: class ids must be 0..{len(CLASSES) - 1}")
        return 2

    stem_dir = user_data_dir() / "clips"

    # ── THE DEFAULT PATH: Godot's own Movie Maker, WITH SOUND. ──────────────────
    # Falls back to the silent frame-grab if the movie capture produces nothing
    # usable, rather than failing the run — a silent clip beats no clip.
    if not args.no_shoot and not args.silent and shutil.which("ffmpeg") is not None:
        shot = shoot_movie(args)
        # AFTER the shoot: `shoot_movie` rewrites args.a/args.b when the matchup was
        # rolled, so the name is the fight that happened.
        out_mp4 = stem_dir / f"{CLASSES[args.a].lower()}_vs_{CLASSES[args.b].lower()}.mp4"
        if shot is not None:
            avi, m_in, m_out = shot
            # ⚠ MOVIE_FPS, NOT `args.fps`. `movie_in`/`movie_out` are ENGINE frame
            # indices, and the engine is pinned to 60 (see shoot_movie). Dividing
            # them by the director's 30 fps SAVE rate doubled both the seek and the
            # duration, which is how a 12 s fight was trimmed to a 24.5 s file with
            # nine seconds of nothing on the end.
            if encode_from_movie(avi, out_mp4, MOVIE_FPS, args.share_width, m_in, m_out):
                print(f"\nwrote {out_mp4}  ({out_mp4.stat().st_size / 1_048_576:.1f} MB, with audio)")
                print("that is the file to post.")
                if not args.keep_avi:
                    avi.unlink(missing_ok=True)
                return 0
        print("  falling back to the silent frame-grab path ...")

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
