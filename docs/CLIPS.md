# Making a post — one command

```
python python-tools/make_post.py --a 6 --b 8      # STORMCALLER vs SWORDSAINT
python python-tools/make_post.py --batch 5        # five rolled matchups
python python-tools/make_post.py --a 6 --b 8 --no-shoot   # re-cut audio, keep the fight
```

Class ids: `0 ARCANIST · 1 SHADOWBLADE · 2 BRAWLER · 3 JUGGERNAUT · 4 CLERIC ·
5 CRYOMANCER · 6 STORMCALLER · 7 WARLOCK · 8 SWORDSAINT`

Out comes two files per matchup, in `content/posts/`:

| file | what it is |
|---|---|
| `<a>_vs_<b>.mp4` | the post — announcer, fight, original battle bed. Upload as-is. |
| `<a>_vs_<b>.nomusic.mp4` | same cut, no bed. Upload this to add a **real trending sound** in the TikTok editor. |

## Which one to upload

**Use the `.nomusic` one when you want the trend.** A real trending sound cannot be
put inside the file — those are commercial masters, licensed by TikTok for use
inside TikTok, attached at publish. And burning one in would lose you the thing
you wanted it for: attaching the sound *in the editor* is what puts the post on
that sound's page and into its recommendation graph. A video that merely sounds
like the trend is attached to nothing.

So: upload `.nomusic.mp4` → Sounds → pick the trend → balance it against the
original audio. The announcer and the fight's own SFX are still in there.

**One human step opens a third route.** Connect a TikTok account
(`tiktok_connect`) and `tiktok_music_trending` lists TikTok's own Commercial Music
Library, with `tiktok_publish` attaching a chosen track by id at publish —
licensed, automatic, no editor. No account is connected today.

## The pieces

| tool | does |
|---|---|
| `make_post.py` | the whole thing: shoot → voice → trim → mix → master → compose |
| `make_clip.py` | shoots one fight and encodes it (`make_post` calls this) |
| `vo_bank.py` | 11 banked words → all 72 matchup lines |
| `generate_battle_music.py` | the battle bed. Original, owned, no licence surface |
| `clip_review.py` | scores a delivered clip for blowout / dead air / stillness |

Swap the bed for anything with `--music <path>`, or drop it with `--no-music`.

## The mix

Voice on top untouched (it is the hook). Music at −9 dB and **sidechained** to the
voice so it steps back when the announcer speaks. Fight audio at 0 dB, ducked more
gently — the SFX roster is the product. Master to **−14 LUFS / −1 dBTP**, which is
what the short-form platforms normalise to; delivering hotter just arrives turned
down with the dynamics gone.

The bed is *arranged* thin for its first two bars so the duck has almost nothing to
do, then drops on the fight.

---

## ⚠ Known gap — the fighters are small, and post cannot fix it

A rig lands at about **2.6% of the 9:16 canvas**. That is not the crop and not the
encoder: `ClipDirector._fit_zoom` solves a shot that CONTAINS BOTH fighters, they
spawn 560 world px apart, so the horizontal fit pins the zoom. Cropping tighter
would enlarge them and throw the far fighter out of frame.

The real lever is direction — a vertical clip should commit to a subject and let a
distant fighter leave frame. Commit `b01bbd8` names this as deliberately
unattempted, and three earlier passes at "the fighters are specks" failed by
attacking `FRAME_MARGIN` and `ZOOM_MAX` instead. **Not attempted here either.**

Related: `ClipDirector` has **no portrait branch at all**. The portrait framing work
in `b01bbd8` landed on `VersusArena`'s showcase camera, which is a different camera
from the one the clip engine films through. In a tall viewport the director frames
as if it were 16:9 and spends the extra height on sub-floor — which is why the
composition crops the bottom 22% away.

Also game-side: the HUD name plates **clip at the left and right edges** in
portrait. The HUD is laid out for a landscape viewport.

## ⚠ Three traps this pipeline has already fallen into

Each one reported success while producing a wrong file. Do not assume a green log.

1. **`--resolution` is inert for the movie.** MovieWriter fixes its output size at
   engine start from `window/size/window_*_override` in `project.godot` and never
   looks at the window again. Every movie-path clip was 1366×768 whatever was
   asked for — so the director composed a portrait shot and it got recorded into a
   landscape frame. `make_clip.render_size_override` now sets it where MovieWriter
   reads it, and restores in a `finally`.
2. **`--fixed-fps` must be 60.** `directed_clip_capture` saves one frame in
   `round(60/fps)` and calls `_saved/fps` the clip length — it assumes a 60 fps
   engine. At `--fixed-fps 30` its clock ran at half real time: a shoot reporting
   "11.9s" delivered 24.5s whose last **nine seconds were an empty stage**.
3. **`freezedetect` cannot see that dead air.** The stage is not frozen — every
   biome has weather, so an empty stage still has drifting particles. Busy and
   empty at once is exactly what a freeze detector is blind to. `last_motion()`
   measures motion relative to the clip's own fight instead.

**Nobody has heard the battle bed, and audio is the one channel a screenshot cannot
check.** What is verified is structural: per-section RMS, and that the drop measures
+21.8 dB on the intro.
