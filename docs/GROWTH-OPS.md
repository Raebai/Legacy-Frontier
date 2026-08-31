# GROWTH OPS — the daily posting machine, end to end

Everything about getting a STICKSPIRE clip in front of people every day: what runs
by itself, what you have to click once, and what you have to pay for.

Related: [`content-pipeline.md`](content-pipeline.md) (how a clip is made and why the
vendor is an aggregator), [`content-strategy.md`](content-strategy.md) (why any of
this).

---

## ⚠ READ THIS FIRST — the queue is empty

**The vendor is holding zero scheduled posts. The last one went out on 27 August.**
Everything below is set up correctly; nothing is queued because the free plan's ten
uploads for August are spent. Step 1 fixes it, step 8 refills it.

The good news from the same check: **the posts that did fire are working.**

| | flagship | arena |
|---|---|---|
| impressions this month | 4,666 | 2,170 |
| best post | 344 reached | 149 reached |
| trend | still climbing daily | still climbing daily |

Eight posts, all delivered, no failures. This is not a system that needs rebuilding.
It needs a plan that permits more than ten uploads a month, and clips to fill it.

---

## 1. What to pay for

**Upload-Post Basic. $24/month, or $16/month billed annually.**

Dashboard and billing: **<https://app.upload-post.com>**

| | Free (now) | Basic |
|---|---|---|
| profiles | 2 | 5 |
| uploads | **10 / month** | unlimited |
| TikTok | **not included** | included |
| analytics | included | included |
| scheduling | included | included |

Two accounts posting daily needs ~60 uploads a month. Ten is the whole constraint.

**TikTok is the bigger reason to upgrade, and it is not about the extra audience.**
TikTok is the only platform that returns a per-post **retention curve** — the share of
viewers still watching at each second. That answers *"was the opening shot wrong"* from
a single post. Instagram returns view and like counts and nothing else, so on Instagram
alone the only way to learn anything is a statistical comparison across dozens of posts.
Connecting TikTok changes the optimiser from "wait a month for a verdict" to "this clip
lost half its audience at 3 seconds."

**Recommendation: pay monthly ($24) for the first month, switch to annual after.**
Annual saves $96/year and is the right end state, but paying $192 up front before
TikTok posting has been proven end-to-end is the wrong order. One month of caution
costs $8.

**Everything else is free and stays free:**

| | cost | why this one |
|---|---|---|
| Cloudflare Pages | £0 | static hosting, custom domain later, no card |
| Kit (ex-ConvertKit) | £0 to 10,000 subscribers | sends the actual launch email |
| domain | deferred | `stickspire.pages.dev` today, `stickspire.com` (~£9/yr at Cloudflare Registrar, sold at cost) whenever you want it |

**Total: $24 this month, then $16/month.**

---

## 2. Set up TikTok — ⚠ the account type is permanent-ish

Register both TikTok accounts as **Personal / Creator. Never Business.**

A TikTok *Business* account is locked to the Commercial Music Library. It cannot use
trending or chart sounds, **there is no toggle**, and the only way back is converting
the account to Personal. Pick wrong here and it is not a setting you fix later, it is an
account you convert.

Sign up (do this twice, in two browsers or a private window):
**<https://www.tiktok.com/signup>**

    TikTok   @stick.spire        (flagship)   Personal/Creator
    TikTok   @stickspire.arena   (volume)     Personal/Creator

Then connect each at **<https://app.upload-post.com>** → Manage Users, to the matching profile:

- `StickSpire` → TikTok `@stick.spire`
- `StickSpire_Arena` → TikTok `@stickspire.arena`

**Nothing in this repo needs editing when you do.** `tiktok` is already in the config
for both profiles, and the tooling skips a platform that is not connected yet and starts
including it the moment it is. Confirm with:

    python python-tools/publish_clip.py --check

---

## 3. The music question, answered once

You will want to attach a trending sound. Here is the whole truth so it does not come
up again:

- **Chart/viral sounds cannot be attached by any API, on any platform, ever.** They are
  in-app only. Baking the audio into the file does not attach the sound — fingerprinting
  is rights enforcement, not attribution, so the outcomes are mute / takedown / region
  block / lost monetisation, and the post is filed as a new "original sound" nobody
  browses. You would take the legal risk and get none of the discovery.
- **What automation CAN use:** the game's own music bed (already in every clip), and
  **TikTok's Commercial Music Library by track id** — over a million cleared tracks,
  just not the viral ones. `insights.py --recommend` lists the trending ones once TikTok
  is connected.

Both accounts are set to publish automatically (`"draft": false`) so a post never
depends on you opening an app. If you decide you want to hand-finish the flagship's
TikTok with a trending sound, set `"draft": true` on that profile in
`content/daily_accounts.json` — but understand the trade: the post then sits in the
TikTok inbox until you open the app, and on any day you do not, it does not post.

---

## 4. Wire up the wishlist (5 minutes)

**Sign up: <https://app.kit.com/users/signup>** — free, no card, no approval wait.

1. Make a form: <https://app.kit.com/forms> → New → Form → Inline. Any style; you will
   not use their design, only their endpoint.
2. Get an API key: <https://app.kit.com/account_settings/developer_settings> →
   **V4 Keys** → Add a new key. Put it in the gitignored `.env`:

       KIT_API_KEY=kit_...

3. Wire the page to it:

       python python-tools/kit_setup.py            # list the forms on the account
       python python-tools/kit_setup.py --wire     # patch site/index.html

That is the whole step. Kit's API keys are **not** plan-restricted — their docs say
*"creators on any plan can generate API keys"* — so this works on the free tier.

⚠ **There is no `POST /forms`.** Kit's API lists forms, adds subscribers and reads
counts, but cannot create a form. Making it once in the UI is the one irreducible click.

⚠ **The API key never goes near the website.** `site/index.html` is served to strangers,
so anything in it is public. The page posts to Kit's PUBLIC form endpoint
(`app.kit.com/forms/<id>/subscriptions`), which anonymous browsers are meant to call and
which needs no credential. `kit_setup.py` holds the key, runs on your machine, and
writes only a form id — which is public anyway.

⚠ **It is the numeric `id`, not the `uid`.** Kit returns both on every form: `id` is
what the HTML form action takes, `uid` is for the JavaScript embed. Paste the uid and
you get a form that looks perfectly fine and silently accepts nothing. `kit_setup.py`
picks the right one.

**Until this step is done the form disables itself and says so.** It will not take an
address it cannot store — a wishlist that silently drops signups is worse than no
wishlist, because the visitor believes they signed up and nobody finds out for a month.

Optional but worth it: in Kit, set the form's **incentive email** to a one-line
confirmation. That is what people get after signing up.

## 5. Put the site online (10 minutes)

The whole site is `site/` — one HTML file and nine files in total, **645 KB**, no build
step and no framework.

**Sign up (free, no card): <https://dash.cloudflare.com/sign-up>**

### Option A — drag and drop, no terminal

1. **<https://dash.cloudflare.com>** → Workers & Pages → Create → Pages →
   **Upload assets**
2. Project name `stickspire`. Drag the **`site` folder** in. Deploy.
3. You now have **`https://stickspire.pages.dev`**. That is the bio link.

### Option B — one command, and I can run it after the first time

    npx wrangler login                  # opens a browser once, you approve
    npx wrangler pages deploy site --project-name stickspire

Wrangler is already available (v4.127.1 via npx, Node v24 installed). After you have
logged in once, every future redeploy is that second line and nothing else — so a
re-cut clip or a numbers refresh goes live without you touching a dashboard.

### After the first deploy, check three things

1. Open the site on your phone. The form should say **"Not wired"** until step 4 is
   done — that is correct, not a bug.
2. Paste the URL into a DM or a Discord channel. You should get the ember card, not a
   grey box. If it is grey, the `og:image` is not resolving.
3. Open the browser console. **It must be empty.** A Content-Security-Policy violation
   there is the one failure that would silently stop signups reaching Kit.

### What `_headers` does

Cloudflare reads `site/_headers` at deploy time (it is never served). It sets a
year-long immutable cache on `/assets/*` — safe because every asset that can change is
requested with a `?v=` query — and `must-revalidate` on the HTML, which carries those
`?v=` numbers and must never be stale.

It also sets a CSP whose two load-bearing directives are `form-action` and
`connect-src`, both pinned to `app.kit.com`. That means no injected script can quietly
repoint your signup form at somebody else's endpoint. **If the wishlist ever stops
working after a deploy, that line is the first suspect** — check the console before
touching the JavaScript. It was tested in a real browser before shipping: the Kit
request goes through, every other host is blocked.

### When you buy a domain

Cloudflare Registrar sells at cost (~£9/yr for `.com`, no cheap-first-year-then-triple
pricing). Add it under the Pages project → Custom domains, then update the
`stickspire.pages.dev` references in `site/index.html` (`canonical`, `og:url`),
`site/robots.txt` and `site/sitemap.xml`.

---

## 6. The bios

Character limits are strict and different per platform. These are counted.

Each value below is ONE line — copy the whole line, it will not wrap in the field.
Counts are measured, not estimated.

**Instagram — @stick.spire**  (name ≤30, bio ≤150)

```
STICKSPIRE — indie game
```
```
A stick-figure spell brawler about climbing a tower that keeps taking floors back. One person, in Godot. New fight every day.
```
```
https://stickspire.pages.dev
```
<sub>name 23/30 · bio 125/150</sub>

**Instagram — @stickspire.arena**  (name ≤30, bio ≤150)

```
STICKSPIRE Arena
```
```
Every matchup in STICKSPIRE, one fight a day. Nine classes, one tower, no recolours. The game ⬇
```
```
https://stickspire.pages.dev
```
<sub>name 16/30 · bio 95/150</sub>

**TikTok — @stick.spire**  (name ≤30, bio ≤**80**)

```
STICKSPIRE
```
```
Stick-figure spell brawler. One tower, nine classes. Wishlist ⬇
```
<sub>name 10/30 · bio 63/80</sub>

**TikTok — @stickspire.arena**  (name ≤30, bio ≤**80**)

```
STICKSPIRE Arena
```
```
A STICKSPIRE fight every day. Nine classes, one tower. ⬇
```
<sub>name 16/30 · bio 56/80</sub>

**YouTube — @stickspire**  (channel description)

```
STICKSPIRE is a stick-figure spell brawler about climbing a tower that keeps taking floors back. Nine classes, each with a signature spell and its own way of moving. Co-op or alone, friendly fire always on.

Made by one person in Godot. New fight posted daily.

Wishlist: https://stickspire.pages.dev
```

⚠ **TikTok's bio is 80 characters** — the Instagram lines will be truncated mid-word if
pasted there. And **only one link** is allowed on each, which is why the site exists:
it is the one place all five accounts can point.

---

## 7. Upload the logo

Every file is in `content/brand/`, already at the exact size each platform wants.
Regenerate the whole set with `python python-tools/build_social_kit.py`.

| Where | File |
|---|---|
| Instagram profile picture (both accounts) | `avatar_1024.png` |
| TikTok profile picture (both accounts) | `avatar_1024.png` |
| YouTube profile picture | `avatar_1024.png` |
| YouTube channel banner | `yt_channel_art.png` |
| X / Twitter header | `x_header_1500x500.png` |
| website favicon + link preview | already in `site/assets/` |
| a pinned "what is this" post | `ig_post_1080.png` |
| a story | `ig_story_1080x1920.png` |

Upload the **1024px** avatar everywhere, even where the platform displays it at 40px —
every one of them downscales better than it upscales.

`legibility_row.png` shows the mark at 32px / 40px / 110px, magnified so you can see
what actually survives. It holds: the cleft tower and the ember read at all three. What
disappears below ~64px is the dashed ring, which is decoration rather than identity.

---

## 8. Turn the machine on

Once the plan is upgraded and TikTok is connected:

```
# 1. confirm the API agrees with what you think is connected
python python-tools/publish_clip.py --check

# 2. see what WOULD be queued (this sends nothing)
python python-tools/daily_post.py --topup 30

# 3. actually queue it
python python-tools/daily_post.py --topup 30 --live

# 4. register the daily task that keeps it topped up
powershell -ExecutionPolicy Bypass -File python-tools\install_daily_task.ps1
```

---

## How it actually runs

**The posting does not happen on this laptop, and that is the point.** Upload-Post takes
a `scheduled_date` up to 365 days out. Queueing a post is a *deposit*: the video and its
caption go to their servers now, and their servers publish it on the day. Once a day is
queued, this machine is irrelevant to it — off, asleep, logged out, reinstalled.

So the daily task does **not** post. It runs four steps:

1. `insights.py --pull` — snapshot what every post has done so far
2. `insights.py --rank --apply` — re-order the unposted clips from what that shows
3. `daily_post.py --topup 30 --live` — refill the queue to 30 days
4. `daily_post.py --verify` — check that yesterday's posts actually went out

Step 3 is **idempotent**: it asks the vendor what it already holds and fills only the
gaps, so running it twice queues nothing the second time. That is what makes it safe on
a timer — and because it maintains a *thirty-day* queue rather than tomorrow's post, the
task can fail or not run for a fortnight without costing a single post.

⚠ **This is why the previous Windows task was deleted and this one is not the same
mistake.** That one *posted*: it needed the laptop awake, plugged in and logged on at the
same minute every morning, forever, and failed silently otherwise — one closed lid, one
lost day, no error anywhere. This one refills a queue. The laptop stopped being a
dependency of posting; it is now only a dependency of posting *continuing a month from
now*.

⚠ **Never run both a local posting task and the vendor queue.** They would both fire.

**If something fails,** the task writes `content/ALERT.txt` and the detail lands in
`content/daily_post.log`. There is no email alert — there is no mail server here, and a
toast on a locked laptop is a notification nobody receives.

---

## The optimiser — what it can and cannot tell you

    python python-tools/insights.py            # pull, report, recommend, rank
    python python-tools/insights.py --report   # just the leaderboard

It reads Upload-Post's analytics API, joins each number back to the clip that produced
it (the caption's first line is the clip's name, so the join is exact rather than
guessed), and keeps its own dated snapshots — the vendor's cache only reaches back 30
days, and comparing a post at 12 hours old against one at 3 weeks is answered by the
calendar rather than by the content.

**It will refuse to tell you things it does not know, and that is the feature.** Two
posts a day is six a week, and view counts are long-tailed enough that one clip catching
a For You page moves an average more than every deliberate choice made that month. So:

- **FINDINGS** — only differences that clear 2 sigma with at least 5 posts on each side.
- **WATCHING** — differences that are visible but are not evidence. Explicitly labelled.
- **ACTIONABLE NOW** — things true of a *single* post, needing no comparison:
  a retention curve that collapses at 3 seconds; a post that reached 6 when the median
  is 146 (a delivery fault, not a content verdict).
- **TRENDING** — mid-tail hashtags and attachable Commercial-Music-Library tracks.
  TikTok-gated.

**⚠ It could not learn anything until now, and the reason was not the analytics.** Every
post carried the identical hashtags at the identical minute. There is no learning from a
constant — there was no contrast to measure. So the config now rotates: three hashtag
*families* (animation people / gamedev people / general gaming — different audiences,
not reshuffles of the same words) against four and five posting times. The cycle lengths
are deliberately coprime, because equal-length cycles stay in lockstep forever and
confound the two effects permanently. Which variant each post got is written into the
ledger at queue time. Give it three weeks and the FINDINGS section starts filling in.

It **already** found one thing worth acting on: `cryomancer_vs_brawler` reached 6 against
a median of 146. That is not a boring fight, it is a delivery problem — nobody saw it to
be bored. It is also the longest clip on record at 39.6s, which is exactly the sort of
one-post story worth *not* telling; clip length went in as a tracked split instead, and
it will either clear the bar over the next month or quietly not.

---

## ⚠ The real constraint: clips, not the plan

    17 clips on disk, 9 unspoken-for = 4.5 days of runway

Paying for unlimited uploads does not create clips. At two clips a day:

| | clips needed per month |
|---|---|
| 2 profiles daily, each cross-posted to IG **and** TikTok | **~60** |

The cross-posting is the one piece of good news: the same clip on one profile's
Instagram *and* its TikTok is fine — the pattern that trips spam detection is the same
clip on two accounts of the *same* platform. So four accounts run on two clips a day,
not four.

A shoot is ~25 minutes a take and roughly one bout in three fails the quality gate, so
sixty clips is not an evening. The realistic shape is a **batch**: start a run of shoots
before bed, review them in the morning, keep the ones that pass.

    python python-tools/make_post.py --a stormcaller --b cleric --takes 3

⚠ A shoot **rewrites `window/size/window_*_override` in project.godot** for its duration
and restores it in a `finally`. So do not play the game during a shoot, and if one is
killed hard, check with `python python-tools/check_window_override.py`.

**Until the pool is bigger, `--topup 30` will queue what it can and then say
`OUT OF CLIPS` for the remaining days.** That is not a failure — it is the schedule
telling you the truth about how far it can see.

---

## Troubleshooting

| Symptom | What it means |
|---|---|
| `has no tiktok connected — skipping it` | expected until step 2. The config is right; the account is not linked yet. |
| `OUT OF CLIPS` | shoot more. Not a bug. |
| `HTTP 400 ... At least one platform is required` | a JSON array was sent where the API wants repeated `platform[]` fields. Already fixed; if it returns, look there. |
| `202` from an upload | **success.** Scheduled uploads answer 202, not 200. |
| a post shows `success: false` in `--verify` | read the platform's own `status` field, not `success`. Every result carries a falsy `success` until it has actually run. |
| the queue looks doubled | you ran a local posting task as well as the vendor queue. Only one may exist. |
| Instagram post has the wrong caption | **no API can edit a published caption.** Fix it in the app. |
| an Instagram post you want back | there is no draft state and no unpublish. Treat every IG upload as irreversible. |
