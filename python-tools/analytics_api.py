#!/usr/bin/env python3
"""THE READ SIDE of the same vendor `publish_clip.py` writes to. Sends nothing, ever.

`publish_clip` is the write path: it hands a video to Upload-Post. This is the read
path: it asks Upload-Post what happened to the videos it already sent. They are kept
apart on purpose — every function in this file is a GET, so nothing here can post,
cancel, or spend an upload, and a bug in an analysis tool cannot reach an audience.

    from analytics_api import cached_posts, live_post_metrics
    posts = cached_posts("StickSpire", key)

⚠ THE METRIC KEYS ARE NOT A FIXED SCHEMA AND MUST NOT BE READ AS ONE. The vendor
passes through only what the platform actually answered for: a field TikTok did not
report is OMITTED, never returned as `0`. So `m.get("views", 0)` silently turns "we
don't know" into "nobody watched" — which is the difference between a missing metric and
a failed post, and it is the exact shape of mistake that makes an optimiser confidently
wrong. Use `present()` / `pick()` below, which distinguish absent from zero.

⚠ INSTAGRAM AND TIKTOK DO NOT ANSWER THE SAME QUESTIONS, and the gap decides what this
whole pipeline can learn:

    Instagram (per post)  views, likes, comments, shares, saves         — outcomes only
    TikTok    (per post)  the above PLUS retention[] (a % still-watching curve, second
                          by second), full_video_watched_rate, average_time_watched,
                          impression_sources (For You vs Following vs Search),
                          audience_types (new vs returning viewers)

That TikTok block is the only thing in the entire stack that can answer "was the opening
shot wrong" from ONE post instead of from a statistically-powered comparison across
dozens. It is the strongest argument for connecting TikTok, stronger than the extra
audience.

RATE LIMITS THAT ARE REAL
  * `live_post_metrics` (per-post, straight from the platform): 100 requests / 5 min.
  * `cached_posts` (the vendor's own snapshot store): NOT subject to that limit, because
    it never touches the platform. Prefer it for anything that loops.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from publish_clip import API_BASE, ENV_KEY, load_key  # noqa: E402,F401

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# The per-post live endpoint is the metered one. Sleep a beat between calls rather than
# discovering the limit as a 429 halfway through a backfill.
LIVE_CALL_SPACING_S = 3.2          # 100 calls / 5 min == one per 3.0s; leave headroom
DEFAULT_TIMEOUT = 30


class ApiError(RuntimeError):
    """A call that did not answer. Carries the status so a caller can tell apart
    'this platform is not connected' (404) from 'the key is wrong' (401) from
    'the vendor is down' (5xx) — three failures that want three different reactions."""

    def __init__(self, message: str, status: int = 0, body: str = "") -> None:
        super().__init__(message)
        self.status = status
        self.body = body


def _get(path: str, key: str | None, params: dict[str, Any] | None = None,
         timeout: int = DEFAULT_TIMEOUT, retries: int = 2) -> dict:
    """One GET, with the auth header this vendor wants and a short retry on 5xx/timeout.

    ⚠ RETRIES ARE ONLY SAFE BECAUSE EVERYTHING IN THIS FILE IS A GET. Never lift this
    helper into the upload path — retrying a POST that already succeeded posts twice.
    """
    url = f"{API_BASE}{path}"
    if params:
        clean = {k: v for k, v in params.items() if v is not None}
        if clean:
            url = f"{url}?{urllib.parse.urlencode(clean)}"
    headers = {"Authorization": f"Apikey {key}"} if key else {}
    last: Exception | None = None
    for attempt in range(retries + 1):
        req = urllib.request.Request(url, method="GET", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")[:400]
            # 4xx is an answer, not a hiccup — retrying a 401 just spends time being
            # told the same thing. Only server-side failures are worth a second look.
            if e.code < 500:
                raise ApiError(f"HTTP {e.code} on {path}", e.code, body) from e
            last = ApiError(f"HTTP {e.code} on {path}", e.code, body)
        except json.JSONDecodeError as e:
            raise ApiError(f"{path} answered something that is not JSON", 0,
                           str(e)) from e
        except Exception as e:                                   # noqa: BLE001
            last = ApiError(f"{type(e).__name__} on {path}: {e}")
        if attempt < retries:
            time.sleep(1.5 * (attempt + 1))
    raise last if last else ApiError(f"{path} failed for no stated reason")


# ─────────────────────────────────────────────────────────────────────────────────────
# reading metrics without inventing them
# ─────────────────────────────────────────────────────────────────────────────────────

def present(metrics: dict, name: str) -> bool:
    """Did the platform actually answer for this metric? See the module warning."""
    return isinstance(metrics, dict) and metrics.get(name) is not None


def pick(metrics: dict, *names: str) -> float | None:
    """The first metric the platform DID answer for, or None if it answered for none.

    `pick(m, "views", "impressions", "reach")` is how to ask for "how many people saw
    this" across platforms that each call it something different — Instagram's primary
    is `reach`, YouTube's is `impressions`, TikTok's is `views`. Returning None rather
    than 0 keeps "not reported" out of the averages.
    """
    for n in names:
        if present(metrics, n):
            try:
                return float(metrics[n])
            except (TypeError, ValueError):
                continue
    return None


# The platform's own headline number for reach, per the vendor's platform-metrics
# endpoint. Hard-coded as a fallback so a report still renders when that call fails.
PRIMARY_REACH = {
    "instagram": ("views", "reach", "impressions"),
    "tiktok": ("views", "reach", "impressions"),
    "youtube": ("views", "impressions"),
    "x": ("impressions",),
    "threads": ("views", "impressions"),
    "facebook": ("reach", "impressions"),
    "bluesky": ("impressions",),
    "reddit": ("impressions",),
    "pinterest": ("impressions",),
}


def reach_of(platform: str, metrics: dict) -> float | None:
    """"How many people saw it", asked in whatever word this platform uses."""
    return pick(metrics, *PRIMARY_REACH.get(platform, ("views", "impressions", "reach")))


def engagement_of(metrics: dict) -> float | None:
    """Likes + comments + shares + saves, counting only what was actually reported.

    Returns None when the platform reported none of them — an engagement of 0 and an
    engagement of unknown are different facts and only one of them is bad news.
    """
    parts = [metrics.get(k) for k in ("likes", "comments", "shares", "saves")
             if present(metrics, k)]
    if not parts:
        return None
    total = 0.0
    for p in parts:
        try:
            total += float(p)
        except (TypeError, ValueError):
            pass
    return total


# ─────────────────────────────────────────────────────────────────────────────────────
# the endpoints
# ─────────────────────────────────────────────────────────────────────────────────────

def profile_analytics(profile: str, platforms: list[str], key: str) -> dict:
    """Account-level numbers: followers, reach, likes, demographics, time series.

    ⚠ Instagram withholds `follower_demographics` below ~100 followers and
    `engaged_audience_demographics` below ~100 engaged accounts, answering `{}` rather
    than erroring. An empty demographics block early on is the threshold, not a bug.
    """
    return _get(f"/analytics/{urllib.parse.quote(profile)}", key,
                {"platforms": ",".join(platforms)})


def total_impressions(profile: str, key: str, start: str | None = None,
                      end: str | None = None, breakdown: bool = True,
                      platform: str | None = None) -> dict:
    """Impressions across the window, optionally broken out per platform and per day."""
    return _get(f"/uploadposts/total-impressions/{urllib.parse.quote(profile)}", key,
                {"start_date": start, "end_date": end,
                 "breakdown": "true" if breakdown else None, "platform": platform})


def cached_posts(profile: str, key: str, platform: str | None = None,
                 since: str | None = None, until: str | None = None,
                 page_size: int = 200, max_pages: int = 25) -> list[dict]:
    """EVERY post in the window, from the vendor's snapshot cache, following the cursor.

    The workhorse. Unmetered (it reads the vendor's store, not the platform), so this is
    what a nightly pull should use. Each row carries `post_id`, `platform`, `date`,
    `metrics`, `post_url` and `upload_timestamp`.

    ⚠ `since` DEFAULTS TO 30 DAYS AGO AT THE VENDOR, which is why this repo keeps its
    own dated snapshots: past 30 days the vendor's answer shortens and the history is
    gone unless something wrote it down.
    """
    out: list[dict] = []
    cursor: str | None = None
    for _ in range(max_pages):
        page = _get("/uploadposts/post-analytics/cached", key,
                    {"user": profile, "platform": platform, "since": since,
                     "until": until, "limit": page_size, "cursor": cursor})
        rows = page.get("posts") or []
        out.extend(rows)
        cursor = page.get("next_cursor")
        if not page.get("has_more") or not cursor or not rows:
            break
    return out


def live_post_metrics(platform_post_id: str, platform: str, profile: str,
                      key: str) -> dict:
    """The RICH per-post read, straight from the platform. TikTok's retention lives here.

    ⚠ METERED: 100 calls / 5 minutes. Callers that loop must space themselves — use
    `LIVE_CALL_SPACING_S`. `cached_posts` covers the same ground for the plain counters
    without touching the limit; this call is worth spending only where the extra fields
    exist, which today means TikTok.
    """
    return _get("/uploadposts/post-analytics", key,
                {"platform_post_id": platform_post_id, "platform": platform,
                 "user": profile})


def post_analytics_by_request(request_id: str, key: str,
                              platform: str | None = None) -> dict:
    """Metrics for one upload, addressed by the id the UPLOAD answered with.

    This is the join that makes attribution possible: the ledger records a job/request id
    at post time, and this maps it back to the platform's own post id and metrics — so a
    number can be traced to the exact clip that produced it, rather than guessed at by
    matching dates.
    """
    return _get(f"/uploadposts/post-analytics/{urllib.parse.quote(request_id)}", key,
                {"platform": platform} if platform else None)


## ⚠ 100 IS A HARD CEILING, NOT A DEFAULT. `limit=101` answers
## `400 {"error":"Invalid limit"}` — so a caller that asks for "everything" by passing a
## big number gets nothing at all rather than a truncated list, which is the worst of
## the two failure modes because it looks like "no posts yet".
HISTORY_MAX_LIMIT = 100


def upload_history(key: str, want: int = 500, page_size: int = HISTORY_MAX_LIMIT
                   ) -> list[dict]:
    """Every upload this key has made, vendor-side, following the pages.

    ⚠ THIS IS THE ATTRIBUTION SPINE. Each row carries `request_id`, `platform_post_id`,
    `post_url` AND `post_title` — and because the caption is built from the clip's stem,
    the title is what maps a number on Instagram back to a file on this disk. It also
    carries `prevalidation_metadata` (duration, fps, width, height), so the clip's own
    properties come along for free without probing the file.
    """
    page_size = max(1, min(int(page_size), HISTORY_MAX_LIMIT))
    out: list[dict] = []
    page = 1
    while len(out) < want:
        data = _get("/uploadposts/history", key, {"limit": page_size, "page": page})
        rows = data if isinstance(data, list) else next(
            (data[f] for f in ("history", "uploads", "posts", "results")
             if isinstance(data.get(f), list)), [])
        out.extend(rows)
        total = data.get("total") if isinstance(data, dict) else None
        if len(rows) < page_size or (isinstance(total, int) and len(out) >= total):
            break
        page += 1
    return out


def audience(profile: str, key: str, platform: str = "tiktok",
             benchmark_category: str | None = None) -> dict:
    """Who is watching and WHEN — the follower-activity-by-hour block is the point.

    ⚠ TIKTOK ONLY today. It is the honest way to set a posting time: the alternative is
    reading a listicle about "the best time to post", which is a statement about somebody
    else's audience. Until TikTok is connected, posting times here are a guess and this
    file will say so rather than dress the guess up.
    """
    return _get("/uploadposts/audience", key,
                {"platform": platform, "benchmark_category": benchmark_category})


def suggestions(key: str, query: str, platform: str = "tiktok",
                kind: str = "hashtags") -> list[dict]:
    """Hashtag or keyword suggestions AROUND A SEED TERM. `kind` is hashtags|keywords.

    ⚠ TIKTOK ONLY, AND `q` IS REQUIRED. Asking for Instagram answers
    *"'instagram' does not support suggestions yet. Supported: tiktok"*, and omitting the
    seed answers *"q is required"* — so this is not a "what is trending in general" feed,
    it is "what is trending NEAR this word". Which is the more useful question anyway:
    the general trending list is dominated by whatever the whole app is doing today, and
    none of it is about stick figures fighting.

    Hashtags come back with a `view_count`, and that is the part worth reading. A tag
    with billions of views is not a distribution channel for a small account, it is a
    place to be buried — the useful band is the mid-tail, which `insights.py` filters for
    rather than taking the top rows.
    """
    data = _get("/uploadposts/suggestions", key,
                {"platform": platform, "type": kind, "q": query})
    rows = data.get(kind) or data.get(f"{kind}[]") or data.get("results") or []
    return rows if isinstance(rows, list) else []


def tiktok_trending_music(key: str, profile: str, limit: int = 50) -> list[dict]:
    """TikTok's COMMERCIAL MUSIC LIBRARY trending tracks — attachable by id at publish.

    ⚠ THIS IS NOT THE CHART SOUNDS, AND THE DIFFERENCE IS THE WHOLE POINT. The viral
    audio on the For You page is licensed for in-app use only and can be attached ONLY
    by a human picking it in the editor; a baked-in copy carries no sound id, gets filed
    as a new "original sound" nobody browses, and takes on the rights risk for nothing.
    The Commercial Music Library is a different, cleared catalogue — over a million
    tracks — and a track id from it CAN be sent with an automated upload. So this is the
    only trending-audio lever that automation is allowed to pull.

    ⚠ Needs `profile`, and that profile needs a LIVE TikTok connection — with none it
    answers *"has no TikTok connection that supports this endpoint"*, which is a setup
    state, not an error to retry.
    """
    data = _get("/uploadposts/tiktok/music/trending", key,
                {"profile": profile, "limit": limit})
    for field in ("music", "musics", "tracks", "results", "data"):
        rows = data.get(field)
        if isinstance(rows, list):
            return rows
    return data if isinstance(data, list) else []


def platform_metrics_config() -> dict:
    """Which metric each platform treats as its headline. Public — needs no key."""
    return _get("/uploadposts/platform-metrics", None)


def main() -> int:
    """A smoke test: prove the key reads, and print what the account can currently see."""
    import argparse
    ap = argparse.ArgumentParser(description="read-only probe of the analytics API")
    ap.add_argument("profile", nargs="?", help="profile to probe (default: all linked)")
    args = ap.parse_args()

    key = load_key()
    if not key:
        print(f"{ENV_KEY} is not set.")
        return 1

    import publish_clip as pc
    data = pc.fetch_profiles(key)
    if data is None:
        return 1
    profiles = data.get("profiles", []) or []
    print(f"\nplan {data.get('plan', '?')}   "
          f"profiles {len(profiles)}/{data.get('limit', '?')}\n")

    for prof in profiles:
        name = str(prof.get("username", ""))
        if args.profile and name != args.profile:
            continue
        linked = [p for p, info in (prof.get("social_accounts") or {}).items() if info]
        print(f"  {name}   linked: {', '.join(linked) or '(nothing)'}")
        if not linked:
            continue
        try:
            rows = cached_posts(name, key)
            print(f"      {len(rows)} post(s) in the vendor's 30-day cache")
            for r in rows[:5]:
                m = r.get("metrics") or {}
                plat = str(r.get("platform"))
                reach = reach_of(plat, m)
                print(f"        {str(r.get('date'))[:10]}  {plat:<10} "
                      f"{'?' if reach is None else int(reach):>7} seen   "
                      f"{r.get('post_id')}")
        except ApiError as e:
            print(f"      analytics unavailable: {e}"
                  + ("   (analytics is a PAID-PLAN feature)" if e.status in (402, 403)
                     else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
