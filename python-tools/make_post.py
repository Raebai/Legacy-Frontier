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
  MUSIC   -13 dB, and SIDECHAINED to the voice, so it steps back the moment the
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
import hashlib
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
# ⚠ THE BED POOL — DROP A FILE IN, IT JOINS THE SHUFFLE. No code change, no list to
# edit. Maker: *"Ive added 6 epic tracks that you can shuffle between ... I will add to
# the tracks list in future"*. Anything with an audio extension in here is a candidate.
#
# It lives under `Effects/`, which is GITIGNORED — correct, because these are licensed
# third-party masters and do not belong in the repo. The consequence is that a fresh
# clone has an empty pool, so `pick_bed` says so plainly rather than failing obscurely.
BED_DIR = REPO_ROOT / "Effects" / "background-audio"
BED_EXTS = {".mp3", ".wav", ".ogg", ".m4a", ".flac", ".aac", ".opus"}
## What every bed is normalised to before `--music-db` is applied on top.
##
## ⚠ THIS IS NOT TIDINESS, IT IS THE WHOLE FEATURE. Measured across the first six
## tracks the integrated loudness ranged -8.5 to -16.1 LUFS — a 7.6 dB spread. On a
## fixed `--music-db` that makes the quietest track nearly inaudible and the loudest one
## a co-star, decided at random by whichever file the shuffle picked. Normalising first
## is what lets "quiet" mean one thing on every clip.
BED_TARGET_LUFS = -20.0

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

# ── LANDSCAPE ─────────────────────────────────────────────────────────────
# ⚠ AND LANDSCAPE IS NOT JUST A DIFFERENT NUMBER — IT IS THE FRAMING THE ENGINE
# ALREADY HAS. Maker: *"clips must render LANDSCAPE, exactly as the bot fights look"*.
#
# Read the note on BAND_TOP/BAND_HEIGHT below: `ClipDirector` HAS NO PORTRAIT BRANCH.
# In a tall viewport it frames as though it were 16:9 and spends the extra height on
# empty sky and sub-floor — which is why the portrait path has to crop a band back
# out and lay it over a blurred copy of itself, and why the fighters end up at ~2.6%
# of the canvas. In 16:9 none of that applies: the director's own framing IS the
# frame, so landscape needs no band, no blur bed and no pillarbox, and the fighters
# are as big as the shot ever makes them.
#
# ⚠ THIS IS NOW THE DEFAULT. It was briefly a flag, because "render landscape" and
# "put TikTok audio on it" pointed opposite ways. Maker settled it 2026-08-19:
# *"landscape content on tiktok and instagram is still possible and what we will be
# doing for now"*. So landscape is the default and `--portrait` is the opt-out; the
# 9:16 path is kept whole rather than deleted because the decision is explicitly
# "for now".
LANDSCAPE_W, LANDSCAPE_H = 1920, 1080

# Where the announcer starts, in clip seconds. The VS card holds for 1.2 s of clip
# time (`directed_clip_capture._intro_clip_seconds`), so a small offset puts the
# names on the card and lets the question spill into the opening exchange.
VO_AT = 0.12
## Breath between the last word and the bell. Short — the point is that the fight starts
## AS the line finishes, not after a pause.
# ⚠ 0.35 -> 0.12. Maker: *"have them start a little earlier"*. This is the pause
# between the announcer finishing and the bell. It was set when the hold did not work
# at all (see the intro-clock fix), so it had never actually been seen; with the hold
# landing, a third of a second of dead air after the last word reads as a stall.
INTRO_TAIL_BEAT = 0.12

# ⚠ IF THE LINE WOULD EAT MORE OF THE CLIP THAN THIS, DROP THE QUESTION.
# "<A> versus <B> — who will win?" is 5.9 s at the banked pace, and the median bot
# duel delivers an 11-13 s clip. At that ratio the announcer is still talking
# halfway through the fight. `--no-tail` cuts it to ~3.9 s. Overridable both ways.
VO_MAX_SHARE = 0.45

# ── THE MATCHUP CARD ───────────────────────────────────────────────────────
# When it arrives, how long it holds, how long it takes to leave. Sized to the
# ANNOUNCER rather than picked: the line runs ~3.9 s without the question and ~5.9 s
# with it, and a card that leaves while the voice is still naming the fighters reads
# as a glitch.
T_IN = 0.15
T_HOLD = 3.4
T_FADE = 0.6
T_OUT = T_IN + T_HOLD
# A ramp in, a hold, a ramp out — evaluated per frame by drawtext against `t`.
TITLE_ALPHA = (
    f"if(lt(t,{T_IN}),0,"
    f"if(lt(t,{T_IN + 0.35}),(t-{T_IN})/0.35,"
    f"if(lt(t,{T_OUT}),1,"
    f"max(0,1-(t-{T_OUT})/{T_FADE}))))"
)

# ── THE VOICE ──────────────────────────────────────────────────────────────
# ⚠ MAKER: "the voice audio needs to be wau more epic". The banked read is a clean
# dry recording, and dry is the opposite of epic — a trailer voice is not a louder
# voice, it is a voice in a BIG ROOM with weight underneath it. This is the cheap
# half, applied in post to the assembled line, and it needs no re-generation:
#   * a hall reverb, so the words have a space around them rather than sitting flat
#     on the front of the speaker;
#   * a shelf lift under 120 Hz for chest, and a small presence lift at 4 kHz so it
#     still cuts through a fight on a phone speaker;
#   * heavy compression, which is what makes a trailer read as CLOSE and inevitable.
# ⚠ THE OTHER HALF IS THE PERFORMANCE, AND POST CANNOT FAKE IT. If this is still not
# epic enough it wants a new bank read by a trailer voice — 11 clips, see vo_bank.py.
VO_FX = ("highpass=f=70,"
         "equalizer=f=110:width_type=h:width=90:g=4.5,"
         "equalizer=f=4000:width_type=h:width=1800:g=3.0,"
         "acompressor=threshold=0.08:ratio=6:attack=6:release=180:makeup=2.2,"
         "aecho=0.85:0.75:70|140:0.28|0.16")

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

def shoot(a: int, b: int, hp: int, seconds: float, timeout: int,
          landscape: bool = False, intro: float = 0.0) -> Path | None:
    """Delegate to make_clip.py rather than re-implementing the shoot.

    ⚠ THE SHOOT LIVES IN EXACTLY ONE PLACE ON PURPOSE. Every trap it knows about —
    the GUI-vs-headless dummy renderer, `--fixed-fps 60` against the 3x fast-forward,
    the user:// directory derived from project.godot instead of hardcoded — was paid
    for by a bug that shipped. A second copy of the invocation here would be a second
    place for all of them to come back."""
    # The shoot resolution IS the orientation — the director frames off the
    # viewport aspect, so this is what makes a landscape clip landscape rather
    # than a portrait one letterboxed in post.
    w, h = (LANDSCAPE_W, LANDSCAPE_H) if landscape else (RENDER_W, RENDER_H)
    argv = [sys.executable, str(TOOLS / "make_clip.py"),
            "--a", str(a), "--b", str(b),
            "--width", str(w), "--height", str(h),
            "--share-width", str(w),
            "--hp", str(hp), "--seconds", str(seconds),
            # The stare-down holds for the length of the voice-over, so the line lands
            # before the fight rather than over it — see `--intro` on make_clip.
            "--intro", f"{intro:.2f}",
            "--out", "post_shoot", "--timeout", str(timeout)]
    print(f"  shooting {CLASSES[a]} vs {CLASSES[b]} at {w}x{h} ...")
    proc = subprocess.run(argv, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    verdict = ""
    for line in (proc.stdout or "").splitlines():
        if "resolved at" in line or "DONE" in line or line.startswith("wrote "):
            print("    " + line.strip())
        # ⚠ THE FIGHT JUDGES ITSELF AND THIS IS WHERE WE READ IT. `BotMatch` prints one
        # `[fight]` line per bout from `FightScore` — see that class for what "cool"
        # means and why a demolition is worth re-rolling rather than publishing.
        # ⚠ STRIPPED FIRST. `make_clip` re-prints every forwarded line with a two-space
        # indent, so `startswith("[fight]")` never matched and the verdict was lost at
        # the LAST of three layers it had to survive. Same class of fault as the two
        # already fixed below it: the gate was emitting, forwarding, and still reporting
        # nothing.
        if line.strip().startswith("[fight]"):
            verdict = line.strip()
            print("    " + verdict)
    shoot.last_verdict = verdict
    got = user_data_dir() / "clips" / f"{CLASSES[a].lower()}_vs_{CLASSES[b].lower()}.mp4"
    if not got.exists():
        print(f"    ! no clip at {got}")
        print((proc.stdout or "")[-1500:])
        return None
    return got


def probe_fps(path: Path) -> float:
    """The clip's real frame rate. Needed because the conform rate is DERIVED from it."""
    exe = shutil.which("ffprobe")
    if exe is None:
        return 60.0
    out = subprocess.run(
        [exe, "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=r_frame_rate", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True).stdout.strip()
    if "/" in out:
        num, den = out.split("/", 1)
        try:
            return float(num) / max(float(den), 1e-6)
        except ValueError:
            return 60.0
    try:
        return float(out)
    except ValueError:
        return 60.0


def build_vo(a: int, b: int, with_tail: bool) -> Path:
    """Assemble the announcer line from the banked words."""
    line, name = vo_bank.assemble(
        CLASSES[a].capitalize(), CLASSES[b].capitalize(),
        (vo_bank.GAP_BEFORE_CONNECTOR, vo_bank.GAP_AFTER_CONNECTOR,
         vo_bank.GAP_BEFORE_TAIL),
        with_tail)
    # ⚠ THE TAIL STATE IS IN THE FILENAME, OR THE TWO BUILDS CLOBBER EACH OTHER.
    # `assemble` names a line after the MATCHUP only, so the with-tail and names-only
    # builds resolved to the same path — and since the hold is now measured from a
    # names-only build made moments after the full one, the second write silently
    # replaced the first. The delivered clip then carried the SHORT line and
    # "who will win?" was missing from the post entirely, while the log cheerfully
    # printed "(with the question)". Caught by reading the voice duration back: 2.2s is
    # the names, 3.4s is the whole line.
    dst = POSTS / "_vo" / f"{name}{'' if with_tail else '_names'}.wav"
    dst.parent.mkdir(parents=True, exist_ok=True)
    vo_bank.wavkit.write_wav16(dst, line, vo_bank.wavkit.TARGET_RATE)
    return dst


def pool_beds() -> list[Path]:
    """Every track currently in the bed pool, in a stable order."""
    if not BED_DIR.exists():
        return []
    return sorted((f for f in BED_DIR.iterdir()
                   if f.is_file() and f.suffix.lower() in BED_EXTS),
                  key=lambda f: f.name.lower())


def pick_bed(stem: str) -> Path | None:
    """Choose this matchup's bed from the pool.

    ⚠ DETERMINISTIC FROM THE MATCHUP, NOT RANDOM PER RUN, and that is a workflow
    decision rather than a purity one. `--no-shoot` re-cuts an existing fight all the
    time — for the audio fixes, for a caption change — and a bed that reshuffled on
    every re-cut would mean the clip you approved is not the clip you post. Seeding on
    the stem gives a stable answer per matchup, spreads 72 matchups across the pool,
    and reshuffles by itself when a track is added. `--music <file>` pins it outright.
    """
    beds = pool_beds()
    if not beds:
        return None
    # Hashed rather than `hash()`: Python salts str hashing per process, so `hash()`
    # would silently reintroduce the per-run randomness this exists to avoid.
    digest = hashlib.sha1(stem.encode("utf-8")).digest()
    return beds[int.from_bytes(digest[:4], "big") % len(beds)]


def prepare_bed(track: Path, seconds: float) -> Path | None:
    """Cut `track` to length and normalise it to `BED_TARGET_LUFS`.

    ⚠ ONE PASS, AND HERE IS WHAT THAT ACTUALLY BUYS — measured on the first six tracks
    over a 25 s cut, rather than assumed:

        native    -10.8 .. -19.1 LUFS   (8.3 dB spread)
        prepared  -17.6 .. -19.8 LUFS   (2.2 dB spread)

    So it removes about three quarters of the disagreement, not all of it. Two-pass
    would tighten the tail, and is not worth a second decode for a bed that then gets
    attenuated 13 dB and sidechained under the voice — but 2.2 dB is the honest figure
    and the reason to revisit this if a track ever sounds out of place.

    A 1.2 s fade-in stops the bed from arriving as a step under the announcer's first
    word; the fade-OUT is applied later in `mux`, which is the only place that knows
    where the result card lands."""
    exe = shutil.which("ffmpeg")
    if exe is None:
        return None
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    dst = MUSIC_DIR / f"pool_{track.stem[:40]}_{seconds:.1f}s.wav"
    if dst.exists() and abs(probe_duration(dst) - seconds) < 0.3:
        return dst
    r = subprocess.run(
        [exe, "-v", "error", "-y", "-t", f"{seconds:.3f}", "-i", str(track),
         "-af", f"loudnorm=I={BED_TARGET_LUFS}:TP=-2.0:LRA=11,"
                f"afade=t=in:st=0:d=1.2,aresample=48000",
         "-ac", "2", "-c:a", "pcm_s16le", str(dst)],
        capture_output=True, text=True)
    if r.returncode != 0 or not dst.exists():
        print(f"  ⚠ could not prepare the bed from {track.name}: "
              f"{r.stderr.strip().splitlines()[-1] if r.stderr.strip() else 'unknown'}")
        return None
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


def _portrait_vf(card: str) -> str:
    """The 9:16 composition: keep the band with the fight in it, lay it over a
    blurred and darkened copy of itself blown up to fill the frame, then hand the
    result to the shared title card.

    The blur is not decoration — it is what stops the bands reading as a broken
    export, and it is the format every gameplay clip on the platform already uses.
    See the BAND_TOP/BAND_HEIGHT note for why a band is needed at all: the director
    has no portrait branch, so a tall frame is mostly sky and sub-floor."""
    return (
        f"[0:v]split=2[bg][fg];"
        f"[bg]crop=iw:ih*{BAND_HEIGHT}:0:ih*{BAND_TOP},"
        f"scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,"
        f"gblur=sigma=42,eq=brightness=-0.20:saturation=1.20[bgb];"
        f"[fg]crop=iw:ih*{BAND_HEIGHT}:0:ih*{BAND_TOP},scale=1080:-2[fgs];"
        f"[bgb][fgs]overlay=(W-w)/2:(H-h)/2[comp];"
    ) + card

def ends_on_a_still(path: Path, window: float = 1.5) -> float:
    """Mean frame-to-frame motion over the LAST `window` seconds of a finished clip.

    ⚠ THE QUALITY GATE SCORES THE FIGHT, NOT THE CLIP. `FightScore` asks whether the
    BOUT was worth watching — lead changes, ultimates, how much health the winner kept
    — and every one of those questions can be answered YES about a fight whose ending
    was never filmed. Maker, on a clip the gate had passed at 70.4: *"stormcaller vs
    cryomancer didnt finish properly"*. It stopped on the killing frame, because the
    capture's frame budget ran out before the result card had its beat.

    A clip that keeps its ending closes on the result card, which is nearly a still
    frame; a clip cut on the action closes mid-swing. So the two cases separate cleanly
    on MOTION, and nothing else here could see the difference. Measured across four
    delivered clips: three that held their card scored 0.21-0.84, the one that was cut
    scored 2.96.

    Returns the mean absolute frame-to-frame difference, or -1.0 if it cannot be read.
    """
    exe = shutil.which("ffmpeg")
    if exe is None:
        return -1.0
    total = probe_duration(path)
    if total <= window:
        return -1.0
    w, h = 96, 54
    raw = subprocess.run(
        [exe, "-v", "error", "-ss", f"{total - window:.2f}", "-i", str(path),
         "-frames:v", "45", "-vf", f"scale={w}:{h}", "-pix_fmt", "gray",
         "-f", "rawvideo", "-"], capture_output=True).stdout
    size = w * h
    frames = [raw[i * size:(i + 1) * size] for i in range(len(raw) // size)]
    if len(frames) < 2:
        return -1.0
    diffs = [sum(abs(a - b) for a, b in zip(frames[i], frames[i + 1])) / size
             for i in range(len(frames) - 1)]
    return sum(diffs) / len(diffs)


def mux(args_ns: argparse.Namespace, clip: Path, vo: Path, music: Path | None, out: Path, dur: float,
        music_db: float, game_db: float, vo_db: float, title: str,
        landscape: bool = False) -> None:
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
    # The title card is identical in both orientations, so it is written once and
    # appended to whichever composition ran.
    # ⚠ NO SLAB BEHIND THE TITLE. Maker: *"remove that very bar behind the words"*.
    # It was a full-width black@0.45 box, added so the words would read over a bright
    # sky. The shadow below does that job on its own — `shadowcolor=black@0.85` with a
    # 6 px offset gives every glyph its own backing, which is legible over anything the
    # stage can put behind it WITHOUT laying a letterbox across the fight for two
    # seconds. The bar was solving a real problem the wrong way round: it hid the thing
    # the clip exists to show.
    # ⚠ NO TITLE CARD. Maker: *"there is no need for the double heading at the start
    # remove the white one the game already has one"*. `BotMatch` opens every bout on
    # its own VS card — the one the stare-down is held for — and this drew a SECOND
    # heading in white Impact over the top of it. Two titles saying the same thing, one
    # of them belonging to the video rather than the game.
    #
    # The whole drawtext is kept below rather than deleted because the sizing, the
    # alpha ramp and the shadow were all tuned against real footage and none of that
    # reasoning is recoverable from a blank line. `--title-card` puts it back.
    card = f"[comp]null[vout]"
    if getattr(args_ns, "title_card", False):
        card = (
        f"[comp]drawtext=fontfile='{FONT}':text='{title}':"
        f"fontcolor=white:fontsize={fit_fontsize(title)}:x=(w-text_w)/2:"
        f"y=(h-text_h)/2:alpha='{TITLE_ALPHA}':"
        # Heavier shadow now that it is the ONLY thing separating the words from the
        # picture behind them.
        f"shadowcolor=black@0.95:shadowx=7:shadowy=7:"
        f"enable='between(t,{T_IN},{T_OUT + T_FADE})'[vout]"
        )
    if landscape:
        # NO band, NO blur bed, NO pillarbox. Everything the portrait path does
        # below is compensation for a director that has no portrait branch; in 16:9
        # its framing IS the frame, so the picture passes through untouched.
        vf = (
            f"[0:v]scale={LANDSCAPE_W}:{LANDSCAPE_H}:force_original_aspect_ratio=increase,"
            f"crop={LANDSCAPE_W}:{LANDSCAPE_H}[comp];" + card
        )
    else:
        vf = _portrait_vf(card)
    delay_ms = int(VO_AT * 1000)

    chains = [
        # The voice: placed, padded to full length so the mix cannot end early,
        # then split for its two sidechain duties plus the audible copy.
        f"[1:a]{fmt},{VO_FX},volume={vo_db}dB,adelay={delay_ms}|{delay_ms},"
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
             # THE DELIVERY ENCODE — the only one a viewer sees, and the only one
             # that should trade quality for size. `slow` over `medium` because a
             # shoot already costs ~25 minutes; a few more seconds here is free.
             "-c:v", "libx264", "-preset", "slow", "-crf", "18",
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

    # ⚠ PLANNED OUTSIDE THE SHOOT BRANCH, because `--no-shoot` re-cuts an existing
    # fight and still needs a line to mux. Building it here also means the stare-down
    # hold and the muxed audio are the same file by construction.
    if getattr(args, "vo", None):
        vo_planned = Path(args.vo).resolve()
        planned_tail = True          # a supplied line is whatever it is
        # A supplied line cannot be split into names + question, so it holds in full.
        hold_source = vo_planned
    else:
        # The tail decision has to be made BEFORE the shoot, because it changes the
        # length being held for — but it normally reads the FINISHED clip, which does
        # not exist yet. Estimating from the requested seconds is conservative: the
        # intro hold and the result beat only make the real clip longer, so this errs
        # toward dropping the question rather than toward talking over the fight.
        planned_tail = not args.no_tail
        if planned_tail and not args.tail:
            est_dur = float(args.seconds) / max(float(args.speed), 0.01)
            if probe_duration(build_vo(a, b, True)) > est_dur * VO_MAX_SHARE:
                planned_tail = False
                print("  the full line is too long a share of this clip — "
                      "dropping \"who will win?\" (--tail to keep it)")
        vo_planned = build_vo(a, b, planned_tail)
        # ⚠ THE BELL FOLLOWS THE NAMES, NOT THE WHOLE LINE. Maker: *"the fight should
        # start after the juggernaut vs stormcaller name and then it can say who will
        # win as the fight has started"*. Holding for the FULL line meant the question
        # was dead air over two men standing still, and the question is the one part
        # that WANTS a fight under it — it is asking about something the viewer should
        # already be watching. So the hold is measured from the names alone and the
        # muxed audio still carries the tail, which then lands over the opening
        # exchange. Built separately rather than subtracted, because the gap before the
        # question is authored (`GAP_BEFORE_TAIL`) and guessing it here would drift.
        hold_source = build_vo(a, b, False) if planned_tail else vo_planned

    if not args.no_shoot or not clip.exists():
        # ⚠ THE VOICE-OVER IS MEASURED BEFORE THE SHOOT, because it decides how long
        # the fighters stay frozen. Maker: *"make the audio ... quicker so that it says
        # that as the stick men are frozen and once complete the fight starts"*. The
        # announcer used to talk over the opening exchange, which asked a viewer to
        # parse a sentence and a fight simultaneously in the first two seconds.
        # ⚠ AND IT ONLY EVER WORKED WHEN A LINE WAS HANDED IN ON THE COMMAND LINE.
        # `intro_hold` was computed from `--vo` and from nothing else, but `make_post`
        # BUILDS its own line from the word bank when `--vo` is absent — which is every
        # normal invocation. So the default path measured nothing, held for 0.0s, and
        # the announcer talked straight over the opening exchange. The maker asked for
        # this twice; the second report was *"it needs to say that as the stick men are
        # standing still and then the fight starts"*.
        intro_hold = probe_duration(hold_source) + INTRO_TAIL_BEAT
        print(f"  holding the stare-down {intro_hold:.1f}s for the names"
              + (" (the question lands over the fight)" if planned_tail else ""))

        # ⚠ RE-ROLL A BORING FIGHT RATHER THAN PUBLISHING IT. Maker: *"ensure that the
        # fights recorded are cool — have a threshold for good fights vs boring ones"*.
        # Measured over 72 bouts, 44% ended under five seconds and 31% were won with the
        # winner still above 80% health; those are demolitions, and a pipeline that
        # shoots the first roll publishes them. `FightScore` is the judge.
        clip = None
        for attempt in range(1, max(1, args.takes) + 1):
            clip = shoot(a, b, args.hp, args.seconds, args.timeout,
                         landscape=not bool(getattr(args, "portrait", False)),
                         intro=intro_hold)
            v = getattr(shoot, "last_verdict", "")
            if clip is None:
                break
            if not v:
                # ⚠ NO VERDICT MEANS THE FIGHT NEVER ENDED, AND THAT IS THE WORST TAKE
                # OF ALL — NOT A NEUTRAL ONE. `BotMatch` prints `[fight]` from
                # `_decide()`, so a missing line is not a broken pipe: it is a bout that
                # ran out the `--seconds` budget with nobody knocked out. The clip then
                # just STOPS mid-swing, with no KO and no result card — which is
                # exactly the "boring" the gate exists to catch. Treating it as
                # "keeping this take" published the one outcome the maker complained
                # about. Observed on 2 of 5 shoots in a single batch.
                if attempt < max(1, args.takes):
                    print(f"    re-rolling (take {attempt} never resolved — no KO "
                          f"inside {args.seconds:.0f}s)")
                    continue
                print(f"    ⚠ kept take {attempt} anyway — it never resolved inside "
                      f"{args.seconds:.0f}s, so it ends mid-fight. Raise --seconds.")
                break
            if "PASS" in v.split("  ")[0]:
                if attempt > 1:
                    print(f"    kept take {attempt}")
                break
            if attempt < max(1, args.takes):
                print(f"    re-rolling (take {attempt} rejected)")
            else:
                print(f"    ⚠ kept take {attempt} anyway — {args.takes} takes all "
                      f"scored below the bar. Lower --takes or accept the matchup.")
        if clip is None:
            return None
    else:
        print(f"  reusing {clip.name}")

    dur = probe_duration(clip)

    # Cut trailing dead air BEFORE anything is timed against the length — the
    # voice-over budget, the music bed and the fade all key off `dur`, and each
    # of them would otherwise be sized for seconds of empty stage.
    # ⚠ SLOW IT DOWN, AND CONFORM TO 30 fps. Maker: "the clip speed as it feels sped
    # up". It is NOT sped up in the encode — read off the round clock at four video
    # timestamps, 5 s of video carries 4 s of game clock, and the shortfall is hitstop
    # (`Juice.hit_stop` sets `Engine.time_scale = 0.05`, and `BotMatch._clock += delta`
    # is scaled by it). Game time and movie time are 1:1. But "not sped up" and "does
    # not READ sped up" are different claims, and only the second one matters here:
    #
    #   * THE CLIP IS 60 fps. Short-form is 30, and doubled temporal resolution reads
    #     as unnaturally fast — the same effect that makes 60 fps film look wrong.
    #     Conforming to 30 changes no timing at all, only the smoothness.
    #   * AND THERE IS NO DELIBERATE SLOW-DOWN. A fight edit is almost never cut at
    #     1.0x; the shot is slowed so the eye can follow it. `--speed` does that, and
    #     it is applied to the CLIP before the announcer is laid over it so the voice
    #     stays in sync with the picture it is describing.
    if args.speed != 1.0 or args.fps != 0:
        slowed = POSTS / "_cut" / f"{stem}.speed.mp4"
        slowed.parent.mkdir(parents=True, exist_ok=True)
        # ⚠ AND THE CONFORM RATE IS DERIVED, BECAUSE A FIXED 30 WAS THE JUDDER.
        # Maker: *"I dont want the recording to be laggy either make sure its smooth"*.
        #
        # The capture is 60 fps. `setpts = 1/speed * PTS` stretches the timestamps, so
        # at the default 0.80x the CONTENT rate becomes 60 * 0.80 = 48 fps. Forcing
        # `-r 30` on top of that is an 8:5 decimation: 37.5% of frames thrown away on a
        # five-frame cycle. The output timestamps stay perfectly even (measured: 33.3 ms
        # gaps, 798 of them) which is why this hides from a timestamp check — but the
        # evenly-spaced frames are sampling UNEVENLY-SPACED MOMENTS, and that is judder.
        #
        # Measured on a delivered clip by frame-to-frame motion, which is where it
        # actually shows: grouping the per-frame motion by phase, the spread between
        # phases peaks at PERIOD 5 (2.77 against a mean step of 5.48) — exactly the 8:5
        # signature, and about a 50% swing in how far the picture moves each frame.
        #
        # Conforming to the content rate instead maps one source frame to one output
        # frame, evenly. Nothing is dropped and nothing is duplicated, so there is no
        # cadence to see. It also costs nothing in "reads too fast": the conform never
        # changed timing, only smoothness, and 48 is below the 60 that prompted the
        # original 30. `--fps N` still forces a specific rate; `--fps -1` disables the
        # conform entirely.
        conform = args.fps
        if conform == 0:
            conform = int(round(probe_fps(clip) * args.speed))
        rate = ["-r", str(conform)] if conform > 0 else []
        ff("-i", str(clip),
           "-filter_complex",
           f"[0:v]setpts={1.0 / args.speed:.5f}*PTS[v];"
           # `atempo` is pitch-preserving and only accepts 0.5..2.0, which every
           # sane --speed is inside. The game's own SFX drop in pitch if you resample
           # instead, and a slowed roar that has also gone flat sounds broken.
           f"[0:a]atempo={args.speed:.5f}[a]",
           "-map", "[v]", "-map", "[a]",
           # Intermediate — see the note in make_clip. Only the mux below delivers.
           *rate, "-c:v", "libx264", "-preset", "medium", "-crf", "14",
           "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", str(slowed))
        clip = slowed
        dur = probe_duration(clip)
        print(f"  {args.speed:.2f}x speed"
              + (f", conformed to {conform} fps" if conform > 0 else "")
              + f" -> {dur:.1f}s")

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

    # ⚠ THE LINE IS THE ONE THE STARE-DOWN WAS HELD FOR. It was decided and built
    # before the shoot (see the block above) precisely so that the freeze and the audio
    # describe the same file. Re-deciding `with_tail` here against the finished duration
    # would be the bug all over again: the fighters would stand still for a sentence
    # that no longer exists, or start moving during one that does.
    with_tail = planned_tail
    vo = vo_planned
    # ⚠ A SUPPLIED LINE WINS OVER THE BANK. `build_vo` stitches "<A> versus <B> — who
    # will win?" from banked WORDS separated by measured silences, which is robust and
    # audibly assembled. A single full-line read is the upgrade, and it needs no code
    # beyond letting the caller hand one in.
    # ⚠ RESOLVED, because ffmpeg is not run from this cwd. A relative --vo path parsed
    # fine, measured fine, drove the intro hold fine, and then ffmpeg could not open it
    # — after a two-minute shoot had already happened.
    vo_dur = probe_duration(vo)
    print(f"  clip {dur:.1f}s   voice {vo_dur:.1f}s"
          f"{' (with the question)' if with_tail else ''}")

    POSTS.mkdir(parents=True, exist_ok=True)
    # ⚠ THE BED IS BACK ON BY DEFAULT, AND FROM A POOL. Maker, 2026-08-22: *"Ive added
    # 6 epic tracks that you can shuffle between they are all copyright free and usable
    # keep them in the background of the fight quietly"*. That reverses the earlier
    # *"remove the background audio ... I will add the audio myself"*, which is why the
    # old comment is quoted here rather than deleted — the flag it justified still
    # exists, the default under it has moved.
    #
    # Order: an explicit --music wins, then --music-bed for the procedural generator,
    # then the pool, then nothing. `--no-music` short-circuits the lot.
    # The `.nomusic.mp4` companion still ships with the hole open for in-app trending
    # audio — see docs/content-pipeline.md §4. This bed is for the accounts that post
    # hands-off.
    music = None
    if not args.no_music:
        if args.music:
            music = Path(args.music)
        elif args.music_bed:
            music = build_music(dur)
        else:
            track = pick_bed(stem)
            if track is None:
                print(f"  no bed — {BED_DIR.relative_to(REPO_ROOT)} is empty "
                      f"(drop audio files in and they join the shuffle)")
            else:
                music = prepare_bed(track, dur)
                if music is not None:
                    print(f"  bed: {track.stem[:52]}  "
                          f"(normalised to {BED_TARGET_LUFS:.0f} LUFS, "
                          f"then {args.music_db:+.0f} dB, ducked under the voice)")
    out = POSTS / f"{stem}.mp4"
    mux(args, clip, vo, music, out, dur, args.music_db, args.game_db, args.vo_db, title,
        landscape=not bool(getattr(args, "portrait", False)))
    print(f"  -> {out.name}  ({out.stat().st_size / 1_048_576:.1f} MB)")
    # ⚠ THE COMPANION IS BUILT HERE, AND UNTIL NOW IT WAS ONLY PROMISED. The module
    # docstring has described `<a>_vs_<b>.nomusic.mp4` as a shipped output since the
    # bed landed, `--no-music`'s own help text refers to it as *"the .nomusic companion"*
    # — and no line of code ever wrote one. Every flagship clip that was supposed to
    # get a hand-attached trending sound in the TikTok editor had only the bedded file
    # to work from, which is the one case where the bed is in the way.
    #
    # It is a SECOND ENCODE, not a strip: the bed is sidechained into the mix and
    # mastered with it, so there is no music track to remove afterwards. Re-muxing from
    # the same picture with `music=None` is the only honest way to get the hole back.
    # That costs one more delivery encode per clip; `--no-companion` skips it, and it is
    # skipped automatically when there was no bed to begin with (the post IS the
    # companion then, and writing a byte-identical twin would only invite posting the
    # wrong one).
    companion = None
    if music is not None and not args.no_companion:
        companion = POSTS / f"{stem}.nomusic.mp4"
        mux(args, clip, vo, None, companion, dur, args.music_db, args.game_db,
            args.vo_db, title,
            landscape=not bool(getattr(args, "portrait", False)))
        print(f"  -> {companion.name}  "
              f"({companion.stat().st_size / 1_048_576:.1f} MB)  "
              f"— music hole open, for a trending sound attached in-app")
    # DID IT KEEP ITS ENDING? See `ends_on_a_still`. Reported rather than enforced:
    # the clip is already encoded by here, and the honest thing is to say so and let
    # the caller decide, not to silently bin a fight that may have been excellent right
    # up to the frame it was cut on.
    tail_motion = ends_on_a_still(out)
    if tail_motion > 1.5:
        print(f"     ⚠ THIS CLIP DOES NOT FINISH — it ends mid-action (tail motion "
              f"{tail_motion:.2f}, a held result card reads under ~1.0). The capture "
              f"budget cut the result card off. Re-shoot it with a larger --seconds.")
    print(f"     {verify(out)}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", type=int, default=6, help="left fighter (0-8)")
    ap.add_argument("--b", type=int, default=8, help="right fighter (0-8)")
    ap.add_argument("--random", action="store_true", help="roll one matchup")
    ap.add_argument("--batch", type=int, default=0,
                    help="make N posts, each a different rolled matchup")
    ap.add_argument("--portrait", action="store_true",
                    help="render the 9:16 band-over-blur composition instead of the "
                         "default 1920x1080 (see LANDSCAPE_W)")
    ap.add_argument("--vo", type=Path,
                    help="use this WAV as the voice-over instead of the stitched word "
                         "bank. A full LINE read (e.g. Higgsfield seed_audio) sounds "
                         "far better than banked words joined with silences — see "
                         "content/vo/lines/")
    ap.add_argument("--takes", type=int, default=3,
                    help="shoot up to this many bouts and keep the first that passes "
                         "the FightScore bar (1 = keep whatever the first roll gives)")
    ap.add_argument("--hp", type=int, default=420)
    # ⚠ 24 -> 32, BECAUSE THE FIGHTS GOT LONGER. This is a cap, not a target: the
    # capture closes the shot as soon as the result card has had its beat, and dead
    # stage on the end is trimmed after, so a short bout still yields a short clip and
    # raising this costs those nothing. What it buys is the long ones. Once the bots
    # started casting their ultimate again, `swordsaint_vs_arcanist` stopped resolving
    # inside 24 s at all — it ran out the clock and ended mid-swing, which is the exact
    # outcome the quality gate exists to reject. The identical matchup at 34 s resolved
    # in 16.8 s and scored 75.0. A budget that causes the failure it is then blamed for
    # is not a budget.
    ap.add_argument("--seconds", type=float, default=32.0, help="clip length cap")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--no-shoot", action="store_true",
                    help="re-cut the audio over an already-shot fight")
    ap.add_argument("--music", help="use this audio file as the bed")
    ap.add_argument("--music-bed", action="store_true",
                    help="add the generated battle bed (OFF by default)")
    ap.add_argument("--no-music", action="store_true",
                    help="ship without any bed (the .nomusic companion always has none)")
    ap.add_argument("--no-companion", action="store_true",
                    help="skip the .nomusic.mp4 twin (saves one delivery encode)")
    # ⚠ -9 -> -13. Maker: *"keep it quiet ... but again keep it quiet and to the
    # point"*, said twice in one sentence, which is not an accident. -9 was chosen for a
    # bed that was meant to be noticed. This one sits under the fight, and the fight's
    # own SFX roster is the product. Applied ON TOP of BED_TARGET_LUFS, so the two
    # numbers do different jobs: the LUFS target makes every track agree, this decides
    # how far under the fight they all sit.
    ap.add_argument("--music-db", type=float, default=-13.0)
    ap.add_argument("--game-db", type=float, default=0.0)
    ap.add_argument("--vo-db", type=float, default=0.0)
    ap.add_argument("--no-tail", action="store_true",
                    help="never say \"who will win?\"")
    ap.add_argument("--tail", action="store_true",
                    help="always say it, however short the clip")
    # ⚠ 0.80 IS A DELIBERATE EDIT DECISION, NOT A CORRECTION. The capture is 1:1 with
    # game time (measured off the round clock). This slows the delivered clip so the
    # eye can follow a fight that the maker found "hard to follow" — the same reason
    # every fight edit on the platform is cut under 1.0x.
    ap.add_argument("--speed", type=float, default=0.80,
                    help="playback speed of the fight (1.0 = as captured)")
    ap.add_argument("--fps", type=int, default=0,
                    help="conform rate; 0 derives it from the capture x --speed so no "
                         "frame is dropped or duplicated, -1 disables the conform")
    ap.add_argument("--title-card", action="store_true",
                    help="draw the matchup title over the opening; off because the "
                         "game already opens on its own VS card")
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
        # ⚠ THIS USED TO SAY "No music bed", WHICH STOPPED BEING TRUE when the pool
        # landed and the default flipped back on. It was the last line of every run —
        # the one place a reader would take at face value — and it described the
        # opposite of what had just been written to disk.
        if args.no_music:
            print("\nNo music bed — add the sound in the TikTok editor, which is also")
            print("what attaches the post to that sound's page. The announcer and the")
            print("fight's own audio are already in the file.")
        else:
            print("\n.mp4 is postable as-is — announcer, fight, and a bed that owes")
            print("nobody anything. Post .nomusic.mp4 instead when you want a TRENDING")
            print("sound: attach it in the app, which is what puts the post on that")
            print("sound's page. That reach is the only reason to do it by hand.")
    return 0 if made else 1


if __name__ == "__main__":
    raise SystemExit(main())
