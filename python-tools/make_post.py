#!/usr/bin/env python3
"""THE POST — one command from nothing to a file you can put on TikTok.

    python python-tools/make_post.py --a 6 --b 8      # STORMCALLER vs SWORDSAINT
    python python-tools/make_post.py --random         # roll the matchup
    python python-tools/make_post.py --batch 5        # five different fights
    python python-tools/make_post.py --no-shoot       # re-cut the audio, keep the fight

WHAT IT PRODUCES, per matchup, in `content/posts/`:

    <a>_vs_<b>.mp4            the post — voice-over, fight, music. Ready to upload.
    <a>_vs_<b>.nomusic.mp4    the same cut with the bed removed. See below.

WHY THERE ARE TWO FILES, AND WHY THE SECOND ONE IS NOT AN AFTERTHOUGHT.
The ask was "trending fighting audio in the background". A real trending sound
CANNOT be muxed into an mp4 — those are commercial masters, licensed by TikTok
for use inside TikTok, attached at publish time. And burning one in would be the
wrong move even if it were legal: attaching a sound in the TikTok editor is what
puts the post on that sound's page and into its recommendation graph. That IS the
reach. A video that merely sounds like the trend is attached to nothing.

So: `.mp4` is postable as-is with an original bed that owes nobody anything.
`.nomusic.mp4` keeps the voice-over and the fight's own audio and leaves the
music hole open, so the real trending sound goes on in the TikTok editor where it
counts. Upload that one, hit Sounds, pick the trend, balance to taste.

⚠ ONE HUMAN STEP UNLOCKS THE THIRD OPTION. With a TikTok account connected
(`tiktok_connect`), `tiktok_music_trending` lists TikTok's own Commercial Music
Library and `tiktok_publish` attaches a chosen track by id at publish — licensed,
automatic, no editor. There is no connected account today, so that path is
documented and not depended on.

THE MIX, and why each number is what it is:

  VOICE   sits on top, untouched. It is the hook and the first 2 seconds decide
          whether anything else gets watched.
  MUSIC   -9 dB, and SIDECHAINED to the voice, so it steps back the moment the
          announcer speaks and returns on its own. The bed is also ARRANGED to be
          thin for its first two bars (see generate_battle_music.py), so the duck
          has little work to do and never sounds like a hand on a fader.
  FIGHT   0 dB, also sidechained to the voice but at a gentler ratio — the game's
          own SFX roster is the product, so it ducks for the announcer and for
          nothing else.
  MASTER  loudnorm to -14 LUFS / -1 dBTP, which is what the short-form platforms
          normalise to. Delivering louder than that does not make it louder; it
          makes the platform turn it down and take the dynamics with it.

⚠ THE VOICE-OVER IS ASSEMBLED, NOT GENERATED PER CLIP. Eleven banked words cover
all 72 ordered matchups. See python-tools/vo_bank.py.

Needs ffmpeg on PATH. Stdlib + the repo's own tools.
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import vo_bank  # noqa: E402
from godot_paths import user_data_dir  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLS = REPO_ROOT / "python-tools"
POSTS = REPO_ROOT / "content" / "posts"
MUSIC_DIR = REPO_ROOT / "content" / "music"

# ⚠ THE SAME ORDER AS Hero.HeroClass / make_clip.CLASSES, WHICH IS *NOT* THE
# ALPHABETICAL ORDER vo_bank.CLASSES uses. vo_bank is keyed by NAME, so the two
# lists never have to agree — but a future edit that starts passing an INDEX
# between them would be silently wrong, and would file a Warlock bout under a
# Cleric's name. Keep the crossing here, in one place, spelled out.
CLASSES = ["ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
           "CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT"]

# 9:16. Rendered natively at this size rather than cropped out of a wide frame —
# the director takes its own portrait framing from the viewport aspect.
RENDER_W, RENDER_H = 1080, 1920

# Where the announcer starts, in clip seconds. The VS card holds for 1.2 s of clip
# time (`directed_clip_capture._intro_clip_seconds`), so a small offset puts the
# names on the card and lets the question spill into the opening exchange.
VO_AT = 0.12

# ⚠ IF THE LINE WOULD EAT MORE OF THE CLIP THAN THIS, DROP THE QUESTION.
# "<A> versus <B> — who will win?" is 5.9 s at the banked pace, and the median bot
# duel delivers an 11-13 s clip. At that ratio the announcer is still talking
# halfway through the fight. `--no-tail` cuts it to ~3.9 s. Overridable both ways.
VO_MAX_SHARE = 0.45

# ── THE COMPOSITION ────────────────────────────────────────────────────────
# ⚠ WHY THE NATIVE 9:16 FRAME IS CROPPED RATHER THAN SHOWN WHOLE, MEASURED off a
# real 1080x1920 render: the fighters sit on a ground line ~56% down and about
# EIGHTY PERCENT of the canvas is empty — sky above, then a dark sub-floor slab,
# then the parallax backdrop repeating BENEATH the terrain. `ClipDirector` has no
# portrait branch at all (the portrait work in commit b01bbd8 landed on
# `VersusArena`'s showcase camera, which is a different camera and not the one the
# clip engine films through), so in a tall viewport it frames as if it were 16:9
# and the extra height is spent on basement.
#
# These two numbers keep the band that has the fight in it: a generous run of sky,
# because that is where the sigils, beams and meteors live, down to just under the
# ground line. Everything below is cut.
# ⚠ THE BAND STARTS AT THE VERY TOP. The first cut began at 0.10 and took the
# health plates and the round clock with it — they sit along the top edge of the
# game's frame, and losing them is losing the only thing that says this is a real
# fight with a scoreline rather than a screensaver.
BAND_TOP = 0.0         # start of the kept band, as a fraction of frame height
BAND_HEIGHT = 0.78     # how much of the frame to keep (the rest is sub-floor)

# ⚠ AND THE CROP DOES NOT MAKE THE FIGHTERS BIGGER — nothing in post can.
# `ClipDirector._fit_zoom` solves a shot that CONTAINS BOTH fighters, and they
# spawn 560 world px apart, so the horizontal fit pins the zoom and a rig lands at
# ~2.6% of a 9:16 canvas whichever way it is shot or cropped. Cropping tighter
# would enlarge them and throw the far fighter out of frame — which is the honest
# trade and the reason it is not done here. The real lever is direction: a
# vertical clip should commit to a subject and let a distant fighter leave. That
# is ClipDirector work, it is called out as unattempted in b01bbd8's own message,
# and three earlier passes at "the fighters are specks" failed by attacking the
# margins and the zoom ceiling instead. It is NOT attempted here either.
# ⚠ THE FONT IS COPIED AND REFERENCED BY A BARE FILENAME, and that is not fussiness.
# `drawtext`'s option parser splits on `:`, so a Windows path detonates on the drive
# letter. Both documented escapes were tried against this ffmpeg and neither worked:
#   fontfile=C\\:/Windows/...  -> "No option name near '/Windows/Fonts/impact.ttf...'"
#   fontfile='C:/Windows/...'  -> the same; quotes are stripped before the split
# What works is having no colon in the string at all, so the font is copied beside
# the output and ffmpeg is run with its CWD set there.
#
# ⚠ AND THE FAILURE MODE IF THE COPY IS SKIPPED IS SILENT. ffmpeg does not error on
# a missing fontfile — it falls back to fontconfig, prints "Cannot load default
# config file", writes NO output, and exits 0. That reads as success to anything
# checking a return code, which is how the first attempt at this "passed" twice.
FONT_SRC = Path("C:/Windows/Fonts/impact.ttf")
FONT = "impact.ttf"


def fit_fontsize(text: str, target_w: int = 940, cap: int = 96) -> int:
    """Largest point size at which `text` still fits inside `target_w`.

    ⚠ MEASURED, NOT ESTIMATED, because a fixed size does not survive the roster.
    "STORMCALLER  vs  SWORDSAINT" is 27 characters and "CLERIC  vs  BRAWLER" is 19;
    at a flat 86pt the first overflowed 1080 px and was delivered with its first
    and last letters sliced off by the frame edge. Guessing a size from a
    characters-wide rule would be wrong too — Impact is proportional, and `I` and
    `W` differ by a factor of four. So the string is actually measured.

    Falls back to a conservative constant if Pillow or the font is missing, which
    is the one case where a slightly small title beats a broken render."""
    try:
        from PIL import ImageFont
        probe = ImageFont.truetype(str(FONT_SRC), 100)
        width = probe.getbbox(text)[2] - probe.getbbox(text)[0]
        if width <= 0:
            return 64
        return max(28, min(cap, int(100 * target_w / width)))
    except Exception:
        return 54


def ff(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    exe = shutil.which("ffmpeg")
    if exe is None:
        raise SystemExit("ffmpeg is not on PATH.  winget install Gyan.FFmpeg")
    proc = subprocess.run([exe, "-y", "-loglevel", "error", *args],
                          capture_output=True, text=True,
                          encoding="utf-8", errors="replace",
                          cwd=None if cwd is None else str(cwd))
    if proc.returncode != 0:
        # ⚠ PRINT WHAT FFMPEG SAID. `check=True` raises with the full 3000-character
        # command line and NONE of the actual complaint, which is the only part that
        # tells you what to fix.
        raise SystemExit("ffmpeg failed:\n" + (proc.stderr or "").strip()[-1500:])
    return proc


def last_motion(path: Path, dur: float, floor: float = 0.15) -> float | None:
    """When the picture last actually MOVED, in seconds. None if it never settles.

    ⚠ THE FAULT THIS EXISTS FOR, MEASURED BY LOOKING: a delivered clip whose final
    NINE SECONDS were an empty stage. A ring-out carried the loser off the world
    edge, the camera followed, and the shot held on nothing. The shoot reported
    success, the encoder wrapped all of it, and the only thing that caught it was
    a contact sheet.

    ⚠ ffmpeg's `freezedetect` CANNOT SEE THIS FAULT, and that is why this function
    is hand-rolled after all. Run against that exact 24.5 s file at -58dB/0.7s it
    reported NOTHING — because the stage is not frozen. Every biome carries weather
    (ash, leaves, snow, embers), so an empty stage still has drifting particles and
    a scrolling parallax. The picture is BUSY and EMPTY at the same time, which is
    precisely the state a freeze detector is blind to.

    So the measure is motion RELATIVE TO THIS CLIP'S OWN FIGHT. Mean absolute
    frame-to-frame difference on 5 fps greyscale thumbnails, then: find the last
    moment reaching `floor` of the clip's 75th-percentile motion. Weather drifting
    over a still camera measures a few percent of what two fighters trading ults
    does, so the gap is wide and the threshold is not delicate.

    ⚠ AND IT DOES NOT TRIM STILLNESS, which is the opposite fault and the more
    tempting rule to write. The result card is a STILL IMAGE and it is the payoff —
    `directed_clip_capture` calls it one of "the two frames anybody actually
    shares". A rule of the form "cut where nothing moves" deletes the ending. This
    finds the last motion and the caller keeps a hold AFTER it."""
    exe = shutil.which("ffmpeg")
    w, h = 96, 171
    raw = subprocess.run(
        [exe, "-v", "error", "-i", str(path),
         "-vf", f"fps=5,scale={w}:{h},format=gray", "-f", "rawvideo", "-"],
        capture_output=True).stdout
    step = w * h
    frames = [raw[i:i + step] for i in range(0, len(raw) - step + 1, step)]
    if len(frames) < 6:
        return None
    diffs = []
    for a, b in zip(frames, frames[1:]):
        diffs.append(sum(abs(x - y) for x, y in zip(a, b)) / step)
    ordered = sorted(diffs)
    busy = ordered[int(len(ordered) * 0.75)]
    if busy <= 0.0:
        return None
    gate = busy * floor
    for i in range(len(diffs) - 1, -1, -1):
        if diffs[i] >= gate:
            # +1 because diffs[i] is the motion BETWEEN frame i and i+1, and the
            # motion is over at the later of the two.
            return (i + 1) / 5.0
    return None


def probe_duration(path: Path) -> float:
    exe = shutil.which("ffprobe")
    if exe is None:
        raise SystemExit("ffprobe is not on PATH (it ships with ffmpeg).")
    out = subprocess.run(
        [exe, "-v", "error", "-show_entries", "format=duration",
         "-of", "json", str(path)],
        check=True, capture_output=True, text=True).stdout
    return float(json.loads(out)["format"]["duration"])


# ---------------------------------------------------------------------------

def shoot(a: int, b: int, hp: int, seconds: float, timeout: int) -> Path | None:
    """Delegate to make_clip.py rather than re-implementing the shoot.

    ⚠ THE SHOOT LIVES IN EXACTLY ONE PLACE ON PURPOSE. Every trap it knows about —
    the GUI-vs-headless dummy renderer, `--fixed-fps 60` against the 3x fast-forward,
    the user:// directory derived from project.godot instead of hardcoded — was paid
    for by a bug that shipped. A second copy of the invocation here would be a second
    place for all of them to come back."""
    argv = [sys.executable, str(TOOLS / "make_clip.py"),
            "--a", str(a), "--b", str(b),
            "--width", str(RENDER_W), "--height", str(RENDER_H),
            "--share-width", str(RENDER_W),
            "--hp", str(hp), "--seconds", str(seconds),
            "--out", "post_shoot", "--timeout", str(timeout)]
    print(f"  shooting {CLASSES[a]} vs {CLASSES[b]} at {RENDER_W}x{RENDER_H} ...")
    proc = subprocess.run(argv, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    for line in (proc.stdout or "").splitlines():
        if "resolved at" in line or "DONE" in line or line.startswith("wrote "):
            print("    " + line.strip())
    got = user_data_dir() / "clips" / f"{CLASSES[a].lower()}_vs_{CLASSES[b].lower()}.mp4"
    if not got.exists():
        print(f"    ! no clip at {got}")
        print((proc.stdout or "")[-1500:])
        return None
    return got


def build_vo(a: int, b: int, with_tail: bool) -> Path:
    """Assemble the announcer line from the banked words."""
    line, name = vo_bank.assemble(
        CLASSES[a].capitalize(), CLASSES[b].capitalize(),
        (vo_bank.GAP_BEFORE_CONNECTOR, vo_bank.GAP_AFTER_CONNECTOR,
         vo_bank.GAP_BEFORE_TAIL),
        with_tail)
    dst = POSTS / "_vo" / f"{name}.wav"
    dst.parent.mkdir(parents=True, exist_ok=True)
    vo_bank.wavkit.write_wav16(dst, line, vo_bank.wavkit.TARGET_RATE)
    return dst


def build_music(seconds: float) -> Path:
    """Generate the bed at EXACTLY the clip's length.

    Generating to length rather than looping a fixed file means the authored
    arrangement lands where it was meant to: the thin intro under the voice-over,
    the drop on the fight. A loop of a 60 s file trimmed to 12 s would put the drop
    wherever the trim happened to fall."""
    # ⚠ THE NAME CARRIES A DECIMAL AND THE CACHE CHECK BELOW IS WHY. Rounding the
    # filename to whole seconds while testing the duration to 0.3 s means a 13.4 s
    # clip writes `bed_13s.wav`, then fails its own cache test next run (13.0 vs
    # 13.4) and silently regenerates over the top every single time.
    dst = MUSIC_DIR / f"bed_{seconds:.1f}s.wav"
    if dst.exists() and abs(probe_duration(dst) - seconds) < 0.3:
        return dst
    subprocess.run([sys.executable, str(TOOLS / "generate_battle_music.py"),
                    "--seconds", f"{seconds:.2f}", "--out", str(dst)],
                   check=True, capture_output=True, text=True)
    return dst


def mux(clip: Path, vo: Path, music: Path | None, out: Path, dur: float,
        music_db: float, game_db: float, vo_db: float, title: str) -> None:
    """Lay the three audio layers under the picture and master the result.

    ⚠ EVERY STREAM IS FORCED TO 48 kHz STEREO FIRST. `sidechaincompress` requires
    both of its inputs to agree on rate and layout, and the three sources here do
    not: the movie's track is 48 kHz stereo, the bank and the bed are 44.1 kHz
    mono. Without the aresample/aformat pair the filter simply refuses to build,
    and the error names the filter rather than the mismatch.

    ⚠ AND THE VOICE IS SPLIT THREE WAYS. It is consumed as a sidechain twice and
    mixed once; a filter input can only be used once, so `asplit` is not optional
    tidiness, it is the reason the graph is valid."""
    fmt = "aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo"
    # The picture: keep the band with the fight in it, lay it over a blurred and
    # darkened copy of itself blown up to fill 9:16, and put the matchup in the
    # space that frees up. The blur is not decoration — it is what stops the bands
    # reading as a broken export, and it is the format every gameplay clip on the
    # platform already uses.
    band_h = int(1920 * BAND_HEIGHT)          # the kept band, at 1080 wide
    pad = (1920 - band_h) // 2                # the strip freed above and below it
    vf = (
        f"[0:v]split=2[bg][fg];"
        f"[bg]crop=iw:ih*{BAND_HEIGHT}:0:ih*{BAND_TOP},"
        f"scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,"
        f"gblur=sigma=42,eq=brightness=-0.20:saturation=1.20[bgb];"
        f"[fg]crop=iw:ih*{BAND_HEIGHT}:0:ih*{BAND_TOP},scale=1080:-2[fgs];"
        f"[bgb][fgs]overlay=(W-w)/2:(H-h)/2[comp];"
        # ⚠ THE TITLE GOES IN THE BOTTOM STRIP, NOT THE TOP ONE. The health plates
        # and the round clock live along the top edge of the game's own frame, and
        # a title up there lands on them. The bottom strip is genuinely empty.
        f"[comp]drawtext=fontfile='{FONT}':text='{title}':"
        f"fontcolor=white:fontsize={fit_fontsize(title)}:x=(w-text_w)/2:"
        f"y={1920 - pad // 2 - 60}:"
        f"shadowcolor=black@0.8:shadowx=6:shadowy=6[vout]"
    )
    delay_ms = int(VO_AT * 1000)

    chains = [
        # The voice: placed, padded to full length so the mix cannot end early,
        # then split for its two sidechain duties plus the audible copy.
        f"[1:a]{fmt},volume={vo_db}dB,adelay={delay_ms}|{delay_ms},"
        f"apad=whole_dur={dur:.3f},atrim=0:{dur:.3f},asetpts=N/SR/TB,"
        f"asplit=3[vo_a][vo_b][vo_mix]",
        # The fight's own audio, ducked GENTLY — it is the product, and it steps
        # aside for the announcer and for nothing else.
        f"[0:a]{fmt},volume={game_db}dB[game]",
        "[game][vo_a]sidechaincompress=threshold=0.05:ratio=5:attack=12:"
        "release=320:makeup=1[game_d]",
    ]
    if music is not None:
        chains += [
            # The bed: trimmed to length, faded out under the result card so the
            # post does not end on a hard cut, and ducked HARDER than the fight.
            f"[2:a]{fmt},atrim=0:{dur:.3f},asetpts=N/SR/TB,"
            f"afade=t=out:st={max(dur - 1.4, 0.1):.3f}:d=1.4,"
            f"volume={music_db}dB[mus]",
            "[mus][vo_b]sidechaincompress=threshold=0.03:ratio=11:attack=8:"
            "release=380:makeup=1[mus_d]",
            "[mus_d][game_d][vo_mix]amix=inputs=3:normalize=0:duration=first[mixed]",
        ]
    else:
        # ⚠ THE VOICE STILL HAS TO BE CONSUMED. `asplit=3` created three outputs
        # and ffmpeg fails the graph on an unused pad, so the no-music mix takes
        # vo_b through a null rather than dropping it.
        chains += [
            "[vo_b]anull[vo_dead]",
            "[vo_dead]volume=0[vo_muted]",
            "[game_d][vo_mix][vo_muted]amix=inputs=3:normalize=0:duration=first[mixed]",
        ]
    # -14 LUFS / -1 dBTP is what the short-form platforms normalise to. Delivering
    # hotter does not arrive louder; it arrives turned down, with the dynamics gone.
    chains.append("[mixed]loudnorm=I=-14:TP=-1.0:LRA=11,"
                  "alimiter=level_in=1:limit=0.97[aout]")

    # The font must sit in the directory ffmpeg is given as its CWD — see FONT.
    out.parent.mkdir(parents=True, exist_ok=True)
    if FONT_SRC.exists() and not (out.parent / FONT).exists():
        shutil.copy2(FONT_SRC, out.parent / FONT)

    argv = ["-i", str(clip), "-i", str(vo)]
    if music is not None:
        argv += ["-i", str(music)]
    argv += ["-filter_complex", vf + ";" + ";".join(chains),
             "-map", "[vout]", "-map", "[aout]",
             "-c:v", "libx264", "-preset", "medium", "-crf", "20",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
             "-movflags", "+faststart", str(out)]
    ff(*argv, cwd=out.parent)


# ---------------------------------------------------------------------------

def verify(path: Path) -> str:
    """Measure the DELIVERED file and say what it actually is.

    ⚠ EVERY INSTRUMENT IN THIS PIPELINE HAS LIED AT LEAST ONCE, and each time the
    reason was that it reported an INTENTION instead of an ARTEFACT. The shoot said
    "1080x1920" while writing 1366x768. It said "11.9s" while writing 24.5s. Both
    logs were internally consistent and both were wrong. So this reads the finished
    mp4 back off disk and reports four things nobody has to take on trust:
    resolution, duration, integrated loudness and true peak.

    ⚠ IT STILL CANNOT TELL YOU IF IT IS GOOD. It cannot hear the announcer over the
    bed, and it cannot see whether the fighters read at arm's length. Those need
    the maker."""
    exe = shutil.which("ffmpeg")
    proc = subprocess.run(
        [exe, "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    lufs = peak = "?"
    tail = (proc.stderr or "").splitlines()
    for i, line in enumerate(tail):
        if "Integrated loudness" in line:
            for nxt in tail[i:i + 4]:
                if "I:" in nxt:
                    lufs = nxt.split("I:")[1].strip()
                    break
        if "True peak" in line:
            for nxt in tail[i:i + 4]:
                if "Peak:" in nxt:
                    peak = nxt.split("Peak:")[1].strip()
                    break
    exe2 = shutil.which("ffprobe")
    dims = subprocess.run(
        [exe2, "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True).stdout.strip().replace(",", "x")
    return f"{dims}  {probe_duration(path):.1f}s  {lufs}  peak {peak}"


def one(a: int, b: int, args: argparse.Namespace) -> Path | None:
    stem = f"{CLASSES[a].lower()}_vs_{CLASSES[b].lower()}"
    title = f"{CLASSES[a]}  vs  {CLASSES[b]}"
    print(f"\n{'=' * 60}\n{CLASSES[a]} vs {CLASSES[b]}\n{'=' * 60}")

    clip = user_data_dir() / "clips" / f"{stem}.mp4"
    if not args.no_shoot or not clip.exists():
        clip = shoot(a, b, args.hp, args.seconds, args.timeout)
        if clip is None:
            return None
    else:
        print(f"  reusing {clip.name}")

    dur = probe_duration(clip)

    # Cut trailing dead air BEFORE anything is timed against the length — the
    # voice-over budget, the music bed and the fade all key off `dur`, and each
    # of them would otherwise be sized for seconds of empty stage.
    trimmed = None
    if not args.no_trim:
        froze = last_motion(clip, dur)
        if froze is not None and froze + args.hold < dur - 0.25:
            trimmed = POSTS / "_cut" / f"{stem}.mp4"
            trimmed.parent.mkdir(parents=True, exist_ok=True)
            new_dur = froze + args.hold
            ff("-i", str(clip), "-t", f"{new_dur:.3f}",
               "-c", "copy", "-movflags", "+faststart", str(trimmed))
            print(f"  trimmed {dur:.1f}s -> {new_dur:.1f}s "
                  f"({dur - new_dur:.1f}s of dead stage cut)")
            clip, dur = trimmed, probe_duration(trimmed)

    with_tail = not args.no_tail
    if with_tail and not args.tail:
        probe = build_vo(a, b, True)
        if probe_duration(probe) > dur * VO_MAX_SHARE:
            with_tail = False
            print(f"  the full line is {probe_duration(probe):.1f}s of a {dur:.1f}s "
                  f"clip — dropping \"who will win?\" (--tail to keep it)")
    vo = build_vo(a, b, with_tail)
    vo_dur = probe_duration(vo)
    print(f"  clip {dur:.1f}s   voice {vo_dur:.1f}s"
          f"{' (with the question)' if with_tail else ''}")

    POSTS.mkdir(parents=True, exist_ok=True)
    music = None if args.no_music else (Path(args.music) if args.music
                                        else build_music(dur))
    out = POSTS / f"{stem}.mp4"
    nomusic = POSTS / f"{stem}.nomusic.mp4"

    if music is not None:
        mux(clip, vo, music, out, dur, args.music_db, args.game_db,
            args.vo_db, title)
        print(f"  -> {out.name}  ({out.stat().st_size / 1_048_576:.1f} MB)  "
              f"post as-is")
        print(f"     {verify(out)}")
    mux(clip, vo, None, nomusic, dur, args.music_db, args.game_db,
        args.vo_db, title)
    print(f"  -> {nomusic.name}  ({nomusic.stat().st_size / 1_048_576:.1f} MB)  "
          f"add the trending sound in the TikTok editor")
    print(f"     {verify(nomusic)}")
    return out if music is not None else nomusic


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", type=int, default=6, help="left fighter (0-8)")
    ap.add_argument("--b", type=int, default=8, help="right fighter (0-8)")
    ap.add_argument("--random", action="store_true", help="roll one matchup")
    ap.add_argument("--batch", type=int, default=0,
                    help="make N posts, each a different rolled matchup")
    ap.add_argument("--hp", type=int, default=420)
    ap.add_argument("--seconds", type=float, default=24.0, help="clip length cap")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--no-shoot", action="store_true",
                    help="re-cut the audio over an already-shot fight")
    ap.add_argument("--music", help="use this audio file as the bed instead")
    ap.add_argument("--no-music", action="store_true",
                    help="only produce the .nomusic cut")
    ap.add_argument("--music-db", type=float, default=-9.0)
    ap.add_argument("--game-db", type=float, default=0.0)
    ap.add_argument("--vo-db", type=float, default=0.0)
    ap.add_argument("--no-tail", action="store_true",
                    help="never say \"who will win?\"")
    ap.add_argument("--tail", action="store_true",
                    help="always say it, however short the clip")
    ap.add_argument("--no-trim", action="store_true",
                    help="keep the tail even if the picture has frozen")
    ap.add_argument("--hold", type=float, default=1.4,
                    help="seconds to keep after the last motion (the result card)")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    if shutil.which("ffmpeg") is None:
        print("ffmpeg is not on PATH.  winget install Gyan.FFmpeg")
        return 2

    rng = random.Random(args.seed or None)
    pairs: list[tuple[int, int]] = []
    if args.batch > 0:
        seen: set[tuple[int, int]] = set()
        while len(pairs) < args.batch:
            p = (rng.randrange(len(CLASSES)), rng.randrange(len(CLASSES)))
            if p[0] != p[1] and p not in seen:
                seen.add(p)
                pairs.append(p)
    elif args.random:
        while True:
            p = (rng.randrange(len(CLASSES)), rng.randrange(len(CLASSES)))
            if p[0] != p[1]:
                pairs = [p]
                break
    else:
        pairs = [(args.a, args.b)]

    made = [one(a, b, args) for a, b in pairs]
    made = [m for m in made if m is not None]
    print(f"\n{len(made)}/{len(pairs)} post(s) in {POSTS}")
    if made:
        print("\nTO POST WITH THE TRENDING SOUND (the one that actually travels):")
        print("  upload the .nomusic.mp4, tap Sounds, pick the trend, balance it")
        print("  against the original audio. That attaches the post to the sound's")
        print("  page — which a burned-in copy cannot do, and is the whole point.")
    return 0 if made else 1


if __name__ == "__main__":
    raise SystemExit(main())
