# The content pipeline — fight to post

`publish_clip.py` has referenced this file since it was written and it never existed.
This is it.

```
make_post.py  ──►  content/posts/<a>_vs_<b>.mp4          ready to upload as-is
              └─►  content/posts/<a>_vs_<b>.nomusic.mp4  music hole left open
                        │
                        ▼
              publish_clip.py --dry-run        prints what WOULD be sent
              publish_clip.py --live           uploads as a DRAFT
                        │
                        ▼
              the platform's own app           add trending sound, publish
```

---

## 1. Which vendor, and why it is not a taste question

Posting video to TikTok through an API requires an app that has passed TikTok's
**Content Posting audit**. There are two ways to satisfy that, and only one is
available to a solo dev in an afternoon:

| Route | What you inherit | Reality |
|---|---|---|
| **OAuth aggregator** (Upload-Post, Ayrshare, Blotato, Buffer) | The vendor's already-audited TikTok app | You do no audit at all |
| **Self-hosting** (Postiz, Mixpost) | Nothing — you register your own TikTok app | You must pass the audit yourself |

Unaudited direct-post is not a soft limit. Posts are forced to `SELF_ONLY` (private)
and capped at roughly **5 users per 24h**, which is indistinguishable from broken.
So the pipeline targets an aggregator.

**Default: Upload-Post.** Verified 2026-08-20:

- **Free tier: 10 uploads/month, no credit card, no expiry.** It is a freemium tier,
  *not* a time-limited trial — so it does not start counting down the day you sign up.
- Paid plans from **$16/month billed annually** for higher limits and more profiles.
- Covers **TikTok and Instagram** plus YouTube, LinkedIn, Facebook, X, Threads,
  Pinterest, Reddit and Bluesky.
- Re-encodes to each platform's spec, so an upload does not bounce for being 1920x1080
  when a platform wanted something else.

⚠ **Four or five clips fits inside the free tier.** Do not pay for the first batch. The
$16 is worth it when the cadence is weekly and the account count grows, not before.

---

## 2. Setup, once

1. Sign up at **upload-post.com** and connect the TikTok and Instagram accounts. This is
   the one step that has to be done by a human in a browser — it is an OAuth consent,
   and it is the whole reason the audit is inherited.
2. Copy the API key.
3. Put it in the repo's gitignored `.env`:

   ```
   UPLOAD_POST_API_KEY=...
   ```

   ⚠ `.env` is gitignored and must stay that way. The key is read from the environment
   first and falls back to `.env`; it is never hard-coded and never committed.

---

## 3. Posting, per clip

```bash
# 1. See exactly what would be sent, to which accounts. Sends nothing.
python python-tools/publish_clip.py content/posts/stormcaller_vs_swordsaint.nomusic.mp4 \
    --caption "Stormcaller vs Swordsaint" --dry-run

# 2. Actually upload — as a DRAFT.
python python-tools/publish_clip.py content/posts/stormcaller_vs_swordsaint.nomusic.mp4 \
    --caption "Stormcaller vs Swordsaint" --live
```

⚠ **Nothing leaves the machine without an explicit `--live`.** The default is a dry run
that prints and stops. Publishing is irreversible and reaches other people; a posting
script that defaults to posting is one typo away from spamming every connected account.

---

## 4. Why it uploads a DRAFT, and why you want the `.nomusic` file

Video published through **any** API cannot use the platform's licensed music library.
Trending audio can only be attached inside the app. That is not an Upload-Post
limitation, it is how the licensing works.

And attaching the sound in-app is not a cosmetic step — it is what puts the post on that
sound's page and into its recommendation graph. **That is the reach.** A video that
merely *sounds like* a trend is attached to nothing.

So:

- **`<a>_vs_<b>.mp4`** — voice-over, fight audio, and an original bed that owes nobody
  anything. Postable as-is if you do not want to touch it.
- **`<a>_vs_<b>.nomusic.mp4`** — voice-over and the fight's own audio, music hole left
  open. **Upload this one**, then in the app: Sounds → pick the trend → balance.

The maker's own workflow (*"I will add the music etc."*) is the same constraint arriving
from the other direction, which is why draft-by-default is the setting and not a nag.

⚠ There is a third path if it ever matters: with a TikTok account connected,
TikTok's own **Commercial Music Library** can be queried and a track attached by id at
publish time — licensed, automatic, no editor. It is documented and deliberately not
depended on, because it needs a connected account this repo does not have.

---

## 5. Trending audio the maker picked out

Four were named and **the maker supplies the files** — they are commercial masters and
cannot live in this repo:

- kouun
- haddstrom
- mamma ma (ultra slowed)
- "do I clench my fists"

Attach them in-app per §4, not at render time.

---

## 6. The quality gate

`make_post.py --takes N` shoots up to N times and keeps the best fight, scored by
`FightScore` (see `BotMatch`). A fight that never changed hands, or that ended as a
demolition, is worth re-rolling rather than publishing.

⚠ **Check that a `[fight]` verdict line actually appears in the output.** The verdict has
to survive three layers — Godot's stdout → `make_clip.py` → `make_post.py` — and it has
been silently swallowed at each of them at least once. When it is lost, `make_post`
falls through to *"(no fight verdict reported; keeping this take)"* and `--takes` becomes
an expensive way to shoot once. That fallback line is the symptom; do not ignore it.
