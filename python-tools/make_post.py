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
INTRO_TAIL_BEAT = 0.35

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
        if line.startswith("[fight]"):
            verdict = line.strip()
            print("    " + verdict)
    shoot.last_verdict = verdict
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

def mux(clip: Path, vo: Path, music: Path | None, out: Path, dur: float,
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
        # ⚠ THE VOICE-OVER IS MEASURED BEFORE THE SHOOT, because it decides how long
        # the fighters stay frozen. Maker: *"make the audio ... quicker so that it says
        # that as the stick men are frozen and once complete the fight starts"*. The
        # announcer used to talk over the opening exchange, which asked a viewer to
        # parse a sentence and a fight simultaneously in the first two seconds.
        vo_probe = Path(args.vo) if getattr(args, "vo", None) else None
        intro_hold = 0.0
        if vo_probe is not None and vo_probe.exists():
            intro_hold = probe_duration(vo_probe) + INTRO_TAIL_BEAT
            print(f"  holding the stare-down {intro_hold:.1f}s for the voice-over")

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
                # No verdict line at all — an older capture path. Do not silently loop.
                print("    (no fight verdict reported; keeping this take)")
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
    if args.speed != 1.0 or args.fps > 0:
        slowed = POSTS / "_cut" / f"{stem}.speed.mp4"
        slowed.parent.mkdir(parents=True, exist_ok=True)
        rate = ["-r", str(args.fps)] if args.fps > 0 else []
        ff("-i", str(clip),
           "-filter_complex",
           f"[0:v]setpts={1.0 / args.speed:.5f}*PTS[v];"
           # `atempo` is pitch-preserving and only accepts 0.5..2.0, which every
           # sane --speed is inside. The game's own SFX drop in pitch if you resample
           # instead, and a slowed roar that has also gone flat sounds broken.
           f"[0:a]atempo={args.speed:.5f}[a]",
           "-map", "[v]", "-map", "[a]",
           *rate, "-c:v", "libx264", "-preset", "medium", "-crf", "18",
           "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", str(slowed))
        clip = slowed
        dur = probe_duration(clip)
        print(f"  {args.speed:.2f}x speed"
              + (f", conformed to {args.fps} fps" if args.fps > 0 else "")
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

    with_tail = not args.no_tail
    # A supplied line is whatever length it is — there is no "who will win?" tail to
    # drop from it, so the probe below (which BUILDS a bank line just to measure it)
    # would be both wasted work and a decision about a file it is not describing.
    if with_tail and not args.tail and not getattr(args, "vo", None):
        probe = build_vo(a, b, True)
        if probe_duration(probe) > dur * VO_MAX_SHARE:
            with_tail = False
            print(f"  the full line is {probe_duration(probe):.1f}s of a {dur:.1f}s "
                  f"clip — dropping \"who will win?\" (--tail to keep it)")
    # ⚠ A SUPPLIED LINE WINS OVER THE BANK. `build_vo` stitches "<A> versus <B> — who
    # will win?" from banked WORDS separated by measured silences, which is robust and
    # audibly assembled. A single full-line read is the upgrade, and it needs no code
    # beyond letting the caller hand one in.
    vo = Path(args.vo) if getattr(args, "vo", None) else build_vo(a, b, with_tail)
    vo_dur = probe_duration(vo)
    print(f"  clip {dur:.1f}s   voice {vo_dur:.1f}s"
          f"{' (with the question)' if with_tail else ''}")

    POSTS.mkdir(parents=True, exist_ok=True)
    # ⚠ NO BED UNLESS ASKED. Maker: "remove the background audio ... I will add the
    # audio myself". The generator and the ducking mixer both still work and
    # `--music-bed` puts it back; the shipped file is the announcer over the fight's
    # own audio, with the music hole deliberately left open.
    music = (Path(args.music) if args.music
             else build_music(dur) if args.music_bed else None)
    out = POSTS / f"{stem}.mp4"
    mux(clip, vo, music, out, dur, args.music_db, args.game_db, args.vo_db, title,
        landscape=not bool(getattr(args, "portrait", False)))
    print(f"  -> {out.name}  ({out.stat().st_size / 1_048_576:.1f} MB)")
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
    ap.add_argument("--seconds", type=float, default=24.0, help="clip length cap")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--no-shoot", action="store_true",
                    help="re-cut the audio over an already-shot fight")
    ap.add_argument("--music", help="use this audio file as the bed")
    ap.add_argument("--music-bed", action="store_true",
                    help="add the generated battle bed (OFF by default)")
    ap.add_argument("--music-db", type=float, default=-9.0)
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
    ap.add_argument("--fps", type=int, default=30,
                    help="output frame rate; 0 keeps the captured 60")
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
        print("\nNo music bed — add the sound in the TikTok editor, which is also")
        print("what attaches the post to that sound's page. The announcer and the")
        print("fight's own audio are already in the file.")
    return 0 if made else 1


if __name__ == "__main__":
    raise SystemExit(main())
