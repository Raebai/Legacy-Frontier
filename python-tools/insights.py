#!/usr/bin/env python3
"""WHAT THE POSTS DID, AND WHAT TO CHANGE TOMORROW BECAUSE OF IT.

    python python-tools/insights.py --pull          # fetch + snapshot (run nightly)
    python python-tools/insights.py --report        # the leaderboard and the trend
    python python-tools/insights.py --recommend     # ranked actions, with the evidence
    python python-tools/insights.py --rank          # reorder tomorrow's posting queue
    python python-tools/insights.py --apply         # write the safe changes back

⚠ THE HARD PART IS NOT FETCHING THE NUMBERS, IT IS REFUSING TO OVER-READ THEM. Two
posts a day is six posts a week, and view counts are long-tailed: one clip landing on a
For You page moves the average more than every deliberate choice made that month. An
"optimiser" that reports the top performer's hashtags as a finding is a random number
generator with a confident voice. So every comparison here carries n, the delta AND the
sigma, and NOTHING is offered as a recommendation below 2 sigma — under that bar the
observation is printed in a `WATCHING` block that explicitly says it is not evidence.

⚠ AND A CONSTANT TEACHES NOTHING. Every post from an account currently carries the
identical hashtag line, so no quantity of analytics can ever say whether those hashtags
help — there is no contrast to measure. Learning requires deliberately VARYING something
and recording which variant each post got, which is what `--rank`/`--apply` set up:
hashtag sets and posting minutes rotate, the assignment is written into the ledger at
queue time, and three weeks later the comparison is real. Without that rotation this
file can only ever describe, never explain.

WHAT CAN BE LEARNED WITHOUT STATISTICS AT ALL
  TikTok returns a per-post RETENTION CURVE — the share of viewers still watching at
  each second. That answers "did the opening shot work" from a SINGLE post: if half the
  audience is gone by second three, the first three seconds are the problem and no
  p-value is needed to say so. Instagram does not return it. This is the strongest
  reason to connect TikTok, and it is why `--report` leads with retention where it has
  it and with a much more cautious table where it does not.

THE STORE
  `content/analytics/posts.json`     one row per upload, with a SNAPSHOT HISTORY
  `content/analytics/profiles.json`  dated account-level snapshots
  Kept locally because the vendor's own cache only reaches back 30 days. Snapshots are
  append-only: they are what makes "views at 72 hours old" comparable between a post
  from Tuesday and a post from last month, and comparing a 1-day-old post to a 3-week-old
  one is the single easiest way to conclude something false.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analytics_api as api  # noqa: E402
import publish_clip as pc  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "content" / "analytics"
POSTS_DB = STORE / "posts.json"
PROFILES_DB = STORE / "profiles.json"
QUEUE_ORDER = ROOT / "content" / "queue_order.json"
ACCOUNTS_FILE = ROOT / "content" / "daily_accounts.json"
CLIPS = ROOT / "content" / "posts"

POST_TZ = "Europe/London"

## The age every cross-post comparison is normalised to. 72h is a compromise: long
## enough that a Reel has finished its first distribution push, short enough that a post
## queued last week still qualifies. Posts younger than this are shown but never compared.
COMPARE_AGE_H = 72.0
COMPARE_TOLERANCE_H = 36.0

## The bar a difference must clear before this file will call it a finding rather than a
## coincidence. 2.0 is ~95% two-sided; MIN_PER_ARM stops a 2-vs-2 split from clearing it
## on noise alone, which it otherwise regularly does.
SIGMA_BAR = 2.0
MIN_PER_ARM = 5

## How hard to pull a sparse group's average back toward the global average before
## ranking on it. With k=5, a class seen once counts for one sixth of its own mean —
## which is the correct amount of confidence to have after one post.
SHRINK_K = 5.0

## What to ask the vendor's suggestion engine about. It needs a seed term — it answers
## "what is trending NEAR this word", not "what is trending" — so these are the words
## this account is actually competing in.
SEED_TERMS = ("stickman", "stickfight", "indiegame")

## ⚠ THE USEFUL HASHTAG BAND IS THE MIDDLE, and this is the whole reason the suggestion
## list is filtered rather than printed. #gaming has tens of billions of views: posting
## into it with 5 followers is not distribution, it is being buried within seconds by
## accounts with a million. A tag small enough that a good clip can rank in it, and big
## enough that anybody browses it, is worth more than either extreme.
MID_TAIL_MIN = 10_000
MID_TAIL_MAX = 5_000_000


# ─────────────────────────────────────────────────────────────────────────────────────
# the store
# ─────────────────────────────────────────────────────────────────────────────────────

def _load(path: Path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        sys.exit(f"{path} is unreadable ({e}). Fix or delete it deliberately — "
                 f"treating it as empty would throw away the snapshot history.")


def _save(path: Path, data) -> None:
    """Atomic. A crash mid-write must not cost the accumulated history."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(path)


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def parse_ts(value: str | None) -> datetime | None:
    """The vendor answers timestamps in at least three shapes. Accept all of them."""
    if not value:
        return None
    text = str(value).strip().replace("Z", "+00:00")
    for fmt in (None, "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            dt = datetime.fromisoformat(text) if fmt is None \
                else datetime.strptime(text, fmt)
        except ValueError:
            continue
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    return None


# ─────────────────────────────────────────────────────────────────────────────────────
# features — what varied between one post and another
# ─────────────────────────────────────────────────────────────────────────────────────

STEM_RE = re.compile(r"^([a-z]+)\s+vs\s+([a-z]+)", re.IGNORECASE)


def clip_stem_of(title: str) -> str:
    """`STORMCALLER vs CRYOMANCER\\n\\n#tags` -> `stormcaller_vs_cryomancer`.

    The join between a vendor row and a file on disk. It works because `daily_post`
    builds the caption's first line from the stem and nothing else — so the caption is,
    by construction, a lossless encoding of which clip this was. If the caption format
    ever stops leading with the matchup, this join breaks silently and every per-clip
    finding below becomes unattributed; that is the tripwire, and `--report` prints an
    `unmatched` count so the breakage is visible rather than quiet.
    """
    first = (title or "").splitlines()[0].strip()
    m = STEM_RE.match(first)
    if m:
        return f"{m.group(1).lower()}_vs_{m.group(2).lower()}"
    return re.sub(r"[^a-z0-9]+", "_", first.lower()).strip("_")


def hashtags_of(title: str) -> list[str]:
    return sorted({t.lower() for t in re.findall(r"#(\w+)", title or "")})


def features(row: dict) -> dict:
    """Everything about a post that could plausibly explain how it did.

    ⚠ THE POINT OF SPELLING THESE OUT IS TO MAKE THEM COMPARABLE, NOT TO IMPLY THEY ARE
    CAUSES. `hour` is when it was posted; `fighters` is who was in it; `duration_s` is
    how long it ran. Each is a column a split can be taken on later. None of them is
    evidence until a split over it clears the sigma bar.
    """
    title = row.get("post_title") or row.get("post_caption") or ""
    stem = clip_stem_of(title)
    meta = row.get("prevalidation_metadata") or {}
    posted = parse_ts(row.get("upload_timestamp"))
    local = posted.astimezone(ZoneInfo(POST_TZ)) if posted else None
    fighters = stem.split("_vs_") if "_vs_" in stem else []
    return {
        "clip": stem,
        "fighters": sorted(fighters),
        "profile": row.get("profile_username"),
        "platform": row.get("platform"),
        "hashtags": hashtags_of(title),
        "hashtag_set": ",".join(hashtags_of(title)),
        "hour": local.hour if local else None,
        "weekday": local.strftime("%a") if local else None,
        "duration_s": meta.get("duration"),
        "fps": meta.get("fps"),
        "width": meta.get("width"),
        "height": meta.get("height"),
        "orientation": ("landscape" if (meta.get("width") or 0) >= (meta.get("height") or 1)
                        else "portrait") if meta.get("width") else None,
    }


# ─────────────────────────────────────────────────────────────────────────────────────
# pull
# ─────────────────────────────────────────────────────────────────────────────────────

## A post older than this with at least this many readings is treated as finished: its
## curve is flat and re-reading it only spends the metered rate limit.
SETTLED_AGE_DAYS = 30
SETTLED_MIN_SNAPSHOTS = 3


def settled(rec: dict) -> bool:
    """Has this post stopped moving enough that another reading buys nothing?"""
    posted = parse_ts(rec.get("posted_at"))
    if not posted:
        return False
    old = (now_utc() - posted).days >= SETTLED_AGE_DAYS
    return old and len(rec.get("snapshots") or []) >= SETTLED_MIN_SNAPSHOTS


def pull(key: str, deep: bool = True, verbose: bool = True) -> dict:
    """Fetch everything readable and fold it into the local store.

    Safe to run as often as you like: each run APPENDS a snapshot rather than replacing
    one, and re-running an hour later just adds a denser sampling of the same curve.
    """
    db = _load(POSTS_DB, {"posts": {}})
    posts = db.setdefault("posts", {})
    stamp = now_utc().strftime("%Y-%m-%dT%H:%M:%SZ")

    history = api.upload_history(key)
    if verbose:
        print(f"  {len(history)} upload(s) known to the vendor")

    for row in history:
        rid = row.get("request_id")
        if not rid:
            continue
        rec = posts.setdefault(rid, {"request_id": rid, "snapshots": []})
        rec["posted_at"] = row.get("upload_timestamp")
        rec["profile"] = row.get("profile_username")
        rec["platform"] = row.get("platform")
        rec["title"] = row.get("post_title") or row.get("post_caption") or ""
        rec["post_url"] = row.get("post_url")
        rec["platform_post_id"] = row.get("platform_post_id")
        rec["ok"] = bool(row.get("success"))
        rec["error"] = row.get("error_message")
        rec["features"] = features(row)

    if deep:
        # ⚠ SPACED, BECAUSE THE PER-POST READ IS THE METERED ONE. 100 calls per 5
        # minutes; a backfill of a few months of posts would blow through that and start
        # getting 429s halfway, leaving the store half-updated with no sign of why.
        fresh = 0
        for rid, rec in posts.items():
            if not rec.get("ok"):
                continue
            if settled(rec):
                # ⚠ BOUNDED ON PURPOSE. This loop sleeps 3.2s per post to stay under
                # 100 calls / 5 min, so it costs five minutes per hundred posts and
                # grows forever. A post a month old with several readings has stopped
                # moving — re-reading it spends the rate limit re-learning a number that
                # will not change, at the expense of the recent posts that are still
                # accruing views and are the only ones a decision depends on.
                continue
            try:
                data = api.post_analytics_by_request(rid, key)
            except api.ApiError as e:
                if verbose and e.status not in (404,):
                    print(f"    ! {rid[:8]}: {e}")
                continue
            for platform, block in (data.get("platforms") or {}).items():
                metrics = block.get("post_metrics") or {}
                if not metrics:
                    continue
                rec["platform"] = platform
                rec["post_url"] = block.get("post_url") or rec.get("post_url")
                rec["platform_post_id"] = (block.get("platform_post_id")
                                           or rec.get("platform_post_id"))
                snaps = rec.setdefault("snapshots", [])
                # One snapshot per pull. Identical readings still get recorded — a flat
                # stretch is data about a post that stopped being shown.
                snaps.append({"at": stamp, "metrics": metrics})
                fresh += 1
            time.sleep(api.LIVE_CALL_SPACING_S)
        if verbose:
            print(f"  {fresh} post metric snapshot(s) taken")

    _save(POSTS_DB, db)

    # ── account level
    prof_db = _load(PROFILES_DB, {"snapshots": []})
    linked = fetch_linked(key)
    for profile, platforms in linked.items():
        entry = {"at": stamp, "profile": profile, "platforms": {}}
        for platform in platforms:
            try:
                data = api.profile_analytics(profile, [platform], key)
            except api.ApiError as e:
                if verbose:
                    print(f"    ! {profile}/{platform} analytics: {e}")
                continue
            block = data.get(platform) or {}
            # The time series is long and repeats every pull; the scalars are the part
            # worth keeping forever.
            entry["platforms"][platform] = {
                k: v for k, v in block.items() if not isinstance(v, (list, dict))}
            demo = block.get("follower_demographics")
            if demo:
                entry["platforms"][platform]["follower_demographics"] = demo
        if entry["platforms"]:
            prof_db["snapshots"].append(entry)
    _save(PROFILES_DB, prof_db)
    if verbose:
        print(f"  stored -> {POSTS_DB.relative_to(ROOT)}, "
              f"{PROFILES_DB.relative_to(ROOT)}")
    return db


def fetch_linked(key: str) -> dict[str, list[str]]:
    """{profile: [platform, ...]} for everything actually connected right now."""
    data = pc.fetch_profiles(key) or {}
    out: dict[str, list[str]] = {}
    for prof in data.get("profiles", []) or []:
        name = str(prof.get("username", ""))
        out[name] = [p for p, info in (prof.get("social_accounts") or {}).items() if info]
    return out


# ─────────────────────────────────────────────────────────────────────────────────────
# reading the store
# ─────────────────────────────────────────────────────────────────────────────────────

def age_hours(rec: dict, at: str) -> float | None:
    posted, taken = parse_ts(rec.get("posted_at")), parse_ts(at)
    if not posted or not taken:
        return None
    return (taken - posted).total_seconds() / 3600.0


def latest_metrics(rec: dict) -> tuple[dict, float | None]:
    """The most recent snapshot, and how old the post was when it was taken."""
    snaps = rec.get("snapshots") or []
    if not snaps:
        return {}, None
    last = max(snaps, key=lambda s: s["at"])
    return last.get("metrics") or {}, age_hours(rec, last["at"])


def metrics_at_age(rec: dict, target_h: float = COMPARE_AGE_H,
                   tol_h: float = COMPARE_TOLERANCE_H) -> dict | None:
    """This post's numbers when it was ~`target_h` old, or None if never measured then.

    ⚠ THIS IS THE FUNCTION THAT MAKES COMPARISONS LEGITIMATE. A post keeps accruing
    views for days, so "which post did better" asked of a 12-hour-old post and a
    3-week-old post is answered by the calendar, not by the content. Everything that
    feeds a split goes through here; anything with no snapshot near the target age is
    dropped from the comparison and counted as `unaged` so the exclusion is visible.
    """
    best, best_gap = None, None
    for snap in rec.get("snapshots") or []:
        age = age_hours(rec, snap["at"])
        if age is None:
            continue
        gap = abs(age - target_h)
        if gap <= tol_h and (best_gap is None or gap < best_gap):
            best, best_gap = snap.get("metrics") or {}, gap
    return best


def reach_of(rec: dict, metrics: dict) -> float | None:
    return api.reach_of(str(rec.get("platform") or ""), metrics)


# ─────────────────────────────────────────────────────────────────────────────────────
# statistics, done narrowly and honestly
# ─────────────────────────────────────────────────────────────────────────────────────

def welch(a: list[float], b: list[float]) -> tuple[float, float, float]:
    """(mean difference, standard error, sigma) for two independent samples.

    Welch rather than Student because the two arms will not have equal variance or equal
    n — a hashtag variant used on the flagship and one used on the volume account differ
    in both. Returns sigma 0.0 when either arm is too small to have a variance, which the
    caller must treat as "no evidence", never as "no difference".
    """
    if len(a) < 2 or len(b) < 2:
        return (_mean(b) - _mean(a) if a and b else 0.0), 0.0, 0.0
    ma, mb = _mean(a), _mean(b)
    va, vb = _var(a), _var(b)
    se = math.sqrt(va / len(a) + vb / len(b))
    if se == 0:
        return mb - ma, 0.0, 0.0
    return mb - ma, se, (mb - ma) / se


def _mean(xs: list[float]) -> float:
    return sum(xs) / len(xs) if xs else 0.0


def _var(xs: list[float]) -> float:
    if len(xs) < 2:
        return 0.0
    m = _mean(xs)
    return sum((x - m) ** 2 for x in xs) / (len(xs) - 1)


def logv(x: float) -> float:
    """Compare on a log scale. View counts are long-tailed — one clip that got picked up
    is worth ten that were not, and on a linear scale that single post decides every
    average it appears in. log1p makes "twice as many views" the unit instead."""
    return math.log1p(max(x, 0.0))


def shrunk_mean(values: list[float], global_mean: float, k: float = SHRINK_K) -> float:
    """A group's average, pulled toward the global average in proportion to how little
    of it there is. One observation should barely move a ranking, and this is the
    arithmetic that enforces that rather than a comment asking the reader to remember."""
    n = len(values)
    if n == 0:
        return global_mean
    return (n * _mean(values) + k * global_mean) / (n + k)


# ─────────────────────────────────────────────────────────────────────────────────────
# report
# ─────────────────────────────────────────────────────────────────────────────────────

def rows_for_report(db: dict) -> list[dict]:
    out = []
    for rec in (db.get("posts") or {}).values():
        if not rec.get("ok"):
            continue
        metrics, age = latest_metrics(rec)
        if not metrics:
            continue
        out.append({
            "rec": rec, "metrics": metrics, "age_h": age,
            "reach": reach_of(rec, metrics),
            "eng": api.engagement_of(metrics),
            "f": rec.get("features") or {},
        })
    return sorted(out, key=lambda r: (r["reach"] or -1), reverse=True)


def retention_read(metrics: dict) -> str | None:
    """The one thing a single post CAN prove, when the platform reports it.

    TikTok's `retention` is a list of {second, percentage}. The share still watching at
    three seconds is the hook; below ~50% the opening shot is losing the audience before
    the fight has started, and that is a statement about THIS clip needing no comparison
    group at all.
    """
    curve = metrics.get("retention")
    if not isinstance(curve, list) or not curve:
        return None
    def at(sec: int) -> float | None:
        for point in curve:
            try:
                if int(point.get("second")) == sec:
                    return float(point.get("percentage"))
            except (TypeError, ValueError):
                continue
        return None
    three, ten = at(3), at(10)
    parts = []
    if three is not None:
        verdict = "HOOK IS LOSING THEM" if three < 0.5 else "hook holds"
        parts.append(f"{three:.0%} still watching at 3s ({verdict})")
    if ten is not None:
        parts.append(f"{ten:.0%} at 10s")
    full = metrics.get("full_video_watched_rate")
    if full is not None:
        parts.append(f"{float(full):.0%} watched it all")
    avg = metrics.get("average_time_watched")
    if avg is not None:
        parts.append(f"avg {float(avg):.1f}s")
    return "  ·  ".join(parts) if parts else None


def report(db: dict, prof_db: dict) -> int:
    rows = rows_for_report(db)
    if not rows:
        print("\nNothing measured yet. Run --pull first (and post something).")
        return 1

    print()
    print("POSTS, best seen first")
    print(f"  {'posted':<12} {'profile':<18} {'plat':<10} {'seen':>7} {'eng':>5} "
          f"{'len':>6} {'age':>6}  clip")
    unmatched = 0
    for r in rows:
        rec, f = r["rec"], r["f"]
        clip = f.get("clip") or "?"
        if not (CLIPS / f"{clip}.mp4").exists():
            unmatched += 1
            clip += "   (no file on disk)"
        dur = f.get("duration_s")
        print(f"  {str(rec.get('posted_at'))[:10]:<12} "
              f"{str(rec.get('profile')):<18} {str(rec.get('platform')):<10} "
              f"{'?' if r['reach'] is None else int(r['reach']):>7} "
              f"{'?' if r['eng'] is None else int(r['eng']):>5} "
              f"{('%.0fs' % float(dur)) if dur else '?':>6} "
              f"{('%.0fh' % r['age_h']) if r['age_h'] is not None else '?':>6}  {clip}")
        note = retention_read(r["metrics"])
        if note:
            print(f"        {note}")

    if unmatched:
        print(f"\n  ⚠ {unmatched} post(s) could not be matched to a clip on disk. "
              f"Attribution for those is guesswork — see clip_stem_of().")

    # ── account trend
    snaps = prof_db.get("snapshots") or []
    if snaps:
        print()
        print("ACCOUNTS")
        by_profile: dict[str, list[dict]] = defaultdict(list)
        for s in snaps:
            by_profile[s["profile"]].append(s)
        for profile, entries in sorted(by_profile.items()):
            entries.sort(key=lambda s: s["at"])
            first, last = entries[0], entries[-1]
            for platform, block in (last.get("platforms") or {}).items():
                was = ((first.get("platforms") or {}).get(platform) or {})
                fol, fol0 = block.get("followers"), was.get("followers")
                delta = (f"  ({fol - fol0:+d} since {first['at'][:10]})"
                         if isinstance(fol, (int, float))
                         and isinstance(fol0, (int, float)) and len(entries) > 1 else "")
                print(f"  {profile:<18} {platform:<10} "
                      f"{int(fol) if fol is not None else '?'} followers{delta}")

    # ── how much evidence exists at all
    aged = [r for r in rows if metrics_at_age(r["rec"]) is not None]
    print()
    print(f"EVIDENCE  {len(rows)} measured post(s), {len(aged)} of them with a reading "
          f"near {COMPARE_AGE_H:.0f}h old")
    if len(aged) < MIN_PER_ARM * 2:
        print(f"  Not enough for any comparison yet — a split needs {MIN_PER_ARM} posts "
              f"per side.\n  Nightly --pull builds this up; it is a matter of days, not "
              f"of effort.")
    return 0


# ─────────────────────────────────────────────────────────────────────────────────────
# recommend
# ─────────────────────────────────────────────────────────────────────────────────────

def split_finding(name: str, arm_a: str, values_a: list[float],
                  arm_b: str, values_b: list[float]) -> dict:
    """One comparison, carrying enough context that the reader can dismiss it."""
    delta, se, sigma = welch(values_a, values_b)
    powered = (len(values_a) >= MIN_PER_ARM and len(values_b) >= MIN_PER_ARM
               and abs(sigma) >= SIGMA_BAR)
    # Back out of log space so the size of the effect is readable as "x times".
    ratio = math.exp(delta) if abs(delta) < 20 else float("inf")
    return {"name": name, "a": arm_a, "b": arm_b, "na": len(values_a),
            "nb": len(values_b), "delta": delta, "sigma": sigma, "ratio": ratio,
            "powered": powered}


def comparisons(db: dict) -> list[dict]:
    """Every split worth taking over the data that exists, powered or not."""
    pool = []
    for rec in (db.get("posts") or {}).values():
        if not rec.get("ok"):
            continue
        m = metrics_at_age(rec)
        if m is None:
            continue
        reach = reach_of(rec, m)
        if reach is None:
            continue
        pool.append((rec.get("features") or {}, logv(reach)))

    out: list[dict] = []
    if len(pool) < 4:
        return out

    def by(key: str) -> dict[str, list[float]]:
        groups: dict[str, list[float]] = defaultdict(list)
        for f, v in pool:
            val = f.get(key)
            if val is None or val == "":
                continue
            groups[str(val)].append(v)
        return groups

    for key, label in (("hashtag_set", "hashtag set"), ("weekday", "weekday"),
                       ("profile", "account"), ("orientation", "orientation")):
        groups = by(key)
        names = sorted(groups, key=lambda g: -len(groups[g]))[:4]
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                out.append(split_finding(label, names[i], groups[names[i]],
                                         names[j], groups[names[j]]))

    # ⚠ CLIP LENGTH, BUCKETED — and this split exists because of a specific temptation.
    # The worst-reaching post to date is also the longest by a wide margin (39.6s against
    # a median near 22s), and the story writes itself: "the algorithm punished the long
    # one". That story is built on ONE post. Rather than tell it, the length goes in here
    # as a column, and it will either clear the sigma bar over the next few weeks or it
    # will quietly not.
    lengths: dict[str, list[float]] = defaultdict(list)
    for f, v in pool:
        d = f.get("duration_s")
        if d is None:
            continue
        lengths["under 25s" if float(d) < 25 else "25s and over"].append(v)
    if len(lengths) == 2:
        a, b = "under 25s", "25s and over"
        out.append(split_finding("clip length", b, lengths[b], a, lengths[a]))

    # Posting hour, bucketed — comparing 09:00 to 09:01 is not a question anyone has.
    buckets: dict[str, list[float]] = defaultdict(list)
    for f, v in pool:
        h = f.get("hour")
        if h is None:
            continue
        buckets["morning (<12)" if h < 12 else
                "afternoon (12-17)" if h < 18 else "evening (18+)"].append(v)
    names = sorted(buckets, key=lambda g: -len(buckets[g]))[:3]
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            out.append(split_finding("posting time", names[i], buckets[names[i]],
                                     names[j], buckets[names[j]]))

    # A fighter appearing in the clip, versus not appearing.
    fighters = {f for feats, _ in pool for f in (feats.get("fighters") or [])}
    for fighter in sorted(fighters):
        with_f = [v for f, v in pool if fighter in (f.get("fighters") or [])]
        without = [v for f, v in pool if fighter not in (f.get("fighters") or [])]
        out.append(split_finding("fighter in the clip", f"no {fighter}", without,
                                 fighter, with_f))
    return out


def recommend(db: dict, key: str | None) -> int:
    print()
    found = comparisons(db)
    powered = [c for c in found if c["powered"]]
    watching = [c for c in found if not c["powered"] and c["na"] and c["nb"]]

    print("FINDINGS  (cleared %.0f sigma with %d+ posts each side)"
          % (SIGMA_BAR, MIN_PER_ARM))
    if not powered:
        print("  none yet. That is the correct answer today, not a failure of the tool —")
        print("  six posts cannot distinguish a good hashtag from a lucky one.")
    for c in sorted(powered, key=lambda c: -abs(c["sigma"])):
        direction = "beat" if c["delta"] > 0 else "lost to"
        print(f"  {c['name']}: '{c['b']}' {direction} '{c['a']}' by "
              f"{c['ratio']:.2f}x  (n={c['nb']}/{c['na']}, {abs(c['sigma']):.1f} sigma)")

    print()
    print("WATCHING  (a difference is visible but it is NOT evidence yet)")
    for c in sorted(watching, key=lambda c: -abs(c["sigma"]))[:6]:
        why = ("too few posts" if min(c["na"], c["nb"]) < MIN_PER_ARM
               else f"only {abs(c['sigma']):.1f} sigma")
        print(f"  {c['name']}: '{c['b']}' vs '{c['a']}' = {c['ratio']:.2f}x  "
              f"(n={c['nb']}/{c['na']}, {why})")
    if not watching:
        print("  nothing to watch yet.")

    # ── the things that need no statistics
    print()
    print("ACTIONABLE NOW  (true of a single post, no comparison needed)")
    said_something = False
    rows = rows_for_report(db)

    for r in rows:
        note = retention_read(r["metrics"])
        if note and "LOSING THEM" in note:
            said_something = True
            print(f"  {r['f'].get('clip')}: {note}")
            print("      -> the first 3 seconds are the problem. Re-SHOOT (the opening "
                  "shot is baked in at render; a re-cut cannot reach it).")

    # ⚠ A POST THAT GOT ALMOST NO REACH IS A DELIVERY FAULT, NOT A CONTENT VERDICT.
    # When every sibling post lands 140-340 and one lands 6, the interesting question is
    # not "was that fight boring" — nobody saw it to be bored. It is: was the upload
    # transcoded badly, was the audio stripped, did the platform suppress it. Flagged
    # separately from performance for exactly that reason.
    seen = sorted(r["reach"] for r in rows if r["reach"] is not None)
    if len(seen) >= 4:
        median = seen[len(seen) // 2]
        for r in rows:
            if r["reach"] is not None and median > 0 and r["reach"] < 0.2 * median:
                said_something = True
                print(f"  {r['f'].get('clip')}: only {int(r['reach'])} reached vs a "
                      f"median of {int(median)} — that is a DELIVERY problem, not a "
                      f"content one.")
                print(f"      -> open {r['rec'].get('post_url')} and check it plays "
                      f"with sound; compare its aspect/codec against a normal post.")

    # ⚠ THE ENGAGEMENT BAR IS DELIBERATELY LOW. Set at 1% this fired on almost every
    # post, which is a tool that cries wolf — Reels routinely sit near 1% engagement on
    # reach for a new account, so "below 1%" describes the baseline rather than a fault.
    for r in rows:
        if r["reach"] and r["eng"] is not None and r["reach"] > 150:
            rate = r["eng"] / r["reach"]
            if rate < 0.005:
                said_something = True
                print(f"  {r['f'].get('clip')}: {int(r['reach'])} saw it, "
                      f"{int(r['eng'])} engaged ({rate:.1%}) — shown widely, ignored. "
                      f"The distribution is working and the clip is not.")
                break
    if not said_something:
        print("  nothing flagged.")
    print("  (Retention curves are TIKTOK-ONLY. Instagram does not report them, so this "
          "section\n   stays thin — and per-clip diagnosis stays impossible — until "
          "TikTok is connected.)")

    if key:
        print()
        print("TRENDING  (TikTok-gated: both of these need a connected TikTok account)")
        linked_tiktok = next((p for p, plats in fetch_linked(key).items()
                              if "tiktok" in plats), None)
        if not linked_tiktok:
            print("  no TikTok connected yet, so nothing here can be answered:")
            print("    · hashtag suggestions are TikTok-only at this vendor "
                  "('instagram does not support suggestions yet')")
            print("    · the Commercial Music Library needs a live TikTok connection")
            print("  Connect one and this block starts recommending tags and "
                  "attachable trending tracks.")
            return 0
        for seed in SEED_TERMS:
            try:
                tags = api.suggestions(key, seed, linked_tiktok, "tiktok", "hashtags")
            except api.ApiError as e:
                print(f"  suggestions for '{seed}' unavailable: {e}")
                continue
            mid = [t for t in tags if isinstance(t, dict)
                   and MID_TAIL_MIN <= float(t.get("view_count") or 0) <= MID_TAIL_MAX]
            if not mid:
                continue
            print(f"  near '{seed}' — mid-tail tags (big tags bury a small account, "
                  f"these do not):")
            for t in mid[:6]:
                print(f"      #{str(t.get('name')):<24} "
                      f"{int(float(t['view_count'])):>14,} views")
        try:
            music = api.tiktok_trending_music(key, linked_tiktok, limit=10)
            if music:
                print("  Commercial-Music-Library tracks trending now — these CAN be "
                      "attached automatically\n  (the viral chart sounds cannot; see "
                      "analytics_api.tiktok_trending_music):")
                for m in music[:6]:
                    title = m.get("title") or m.get("name") or "?"
                    print(f"      {str(title)[:44]:<46} "
                          f"id {m.get('id') or m.get('music_id')}")
        except api.ApiError as e:
            print(f"  trending music unavailable: {e}")
    return 0


# ─────────────────────────────────────────────────────────────────────────────────────
# rank — turn what is known into tomorrow's queue order
# ─────────────────────────────────────────────────────────────────────────────────────

def rank(db: dict, write: bool = False) -> int:
    """Order the unposted clips by what similar clips actually did.

    ⚠ THE SHRINKAGE IS THE WHOLE DESIGN. Scoring a clip by "how did the last clip with
    this fighter do" over one observation would reorder the entire queue on a single
    lucky post. Every group mean is pulled toward the global mean by SHRINK_K, so early
    on this returns very nearly the existing order — which is right, because early on
    nothing is known. It sharpens as the sample grows, without a threshold to tune.
    """
    pool: list[tuple[dict, float]] = []
    for rec in (db.get("posts") or {}).values():
        if not rec.get("ok"):
            continue
        m = metrics_at_age(rec) or latest_metrics(rec)[0]
        reach = reach_of(rec, m) if m else None
        if reach is None:
            continue
        pool.append((rec.get("features") or {}, logv(reach)))

    global_mean = _mean([v for _, v in pool]) if pool else 0.0
    by_fighter: dict[str, list[float]] = defaultdict(list)
    for f, v in pool:
        for fighter in f.get("fighters") or []:
            by_fighter[fighter].append(v)

    posted = {f.get("clip") for f, _ in pool}
    candidates = [p for p in sorted(CLIPS.glob("*.mp4"))
                  if ".nomusic" not in p.name and p.stem not in posted]

    scored = []
    for clip in candidates:
        fighters = clip.stem.split("_vs_") if "_vs_" in clip.stem else []
        parts = [shrunk_mean(by_fighter.get(f, []), global_mean) for f in fighters]
        scored.append((clip.stem, _mean(parts) if parts else global_mean,
                       sum(len(by_fighter.get(f, [])) for f in fighters)))
    scored.sort(key=lambda s: -s[1])

    print()
    print(f"QUEUE ORDER  ({len(scored)} unposted clip(s), scored on "
          f"{len(pool)} measured post(s))")
    if len(pool) < MIN_PER_ARM * 2:
        print("  ⚠ Barely any signal yet, so this is close to alphabetical ON PURPOSE. "
              "The shrinkage\n    refuses to reorder a queue on one lucky post.")
    for stem, score, n in scored:
        print(f"  {math.expm1(score):>8.0f} expected   {stem:<34} "
              f"(from {n} prior post(s) with these fighters)")

    if write:
        _save(QUEUE_ORDER, {"generated": now_utc().strftime("%Y-%m-%dT%H:%M:%SZ"),
                            "note": "daily_post.py drains in this order when present. "
                                    "Delete this file to fall back to alphabetical.",
                            "order": [s for s, _, _ in scored]})
        print(f"\n  wrote {QUEUE_ORDER.relative_to(ROOT)} — daily_post will drain in "
              f"this order.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pull", action="store_true", help="fetch and snapshot (read-only)")
    ap.add_argument("--shallow", action="store_true",
                    help="with --pull: skip the metered per-post reads")
    ap.add_argument("--report", action="store_true", help="the leaderboard and trend")
    ap.add_argument("--recommend", action="store_true", help="ranked actions + evidence")
    ap.add_argument("--rank", action="store_true", help="score the unposted clips")
    ap.add_argument("--apply", action="store_true",
                    help="with --rank: write content/queue_order.json")
    ap.add_argument("--all", action="store_true", help="pull, report, recommend, rank")
    args = ap.parse_args()

    if not any((args.pull, args.report, args.recommend, args.rank, args.all)):
        args.all = True

    key = pc.load_key()
    if (args.pull or args.all or args.recommend) and not key:
        print(f"{pc.ENV_KEY} is not set — cannot read anything from the vendor.")
        return 1

    if args.pull or args.all:
        print("\nPULLING")
        pull(key, deep=not args.shallow)

    db = _load(POSTS_DB, {"posts": {}})
    prof_db = _load(PROFILES_DB, {"snapshots": []})

    if args.report or args.all:
        report(db, prof_db)
    if args.recommend or args.all:
        recommend(db, key)
    if args.rank or args.all:
        rank(db, write=args.apply or args.all)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
