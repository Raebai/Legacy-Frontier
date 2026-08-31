#!/usr/bin/env python3
"""Hand a finished clip to every social account, through ONE API call per account.

    python python-tools/publish_clip.py content/posts/stormcaller_vs_cryomancer.mp4 \
        --caption "Stormcaller vs Cryomancer" --dry-run

WHY THIS EXISTS
---------------
The clip pipeline (`make_post.py`) already renders a finished MP4 with voice-over and
music. What it could not do is get that file onto TikTok, Instagram Reels, YouTube
Shorts, X, Reddit and Bluesky without six manual uploads. This is that step.

⚠ THE ARCHITECTURE DECISION THAT MATTERS, AND IT IS NOT ABOUT WHICH VENDOR IS NICEST.
Posting video to TikTok via API requires an app that has passed TikTok's Content Posting
audit. There are two ways to satisfy that and only one of them is available to a solo
dev in an afternoon:

  * AN OAUTH AGGREGATOR (Upload-Post, Ayrshare, Blotato, Buffer). Accounts connect
    through the VENDOR'S already-audited TikTok app, so you inherit their approval and
    do no audit at all.
  * SELF-HOSTING (Postiz, Mixpost). You register your own TikTok app and must pass the
    audit yourself. Postiz self-hosters are currently being REJECTED for reasons inside
    Postiz's own UI that a user cannot fix (github.com/gitroomhq/postiz-app#1563).

Unaudited direct-post is not a soft limitation: posts are forced to SELF_ONLY (private)
and capped at ~5 users per 24h. So this targets an aggregator, and defaults to
Upload-Post — see `docs/content-pipeline.md` for the full comparison and the pricing.

⚠ IT ASKS FOR A DRAFT BY DEFAULT — AND ONLY TIKTOK HAS ONE. Video published through
ANY API cannot use the platform's licensed music library; trending audio is attachable
in-app only. TikTok has an INBOX for exactly this, so `MEDIA_UPLOAD` lands the video
there for a human to finish, which is why it is the default.

INSTAGRAM HAS NO DRAFT STATE AT ALL. Meta's Content Publishing API is create-a-container
then `media_publish` — there is nowhere for an unfinished post to sit, so `post_mode` is
ignored and the Reel goes LIVE. This file used to print "DRAFT" for Instagram regardless
and reported two already-public posts as drafts. Maker: *"they arent drafts they have
been posted"*. `_mode_label` now answers per platform. Treat an Instagram upload as
irreversible, because it is.

SAFETY
------
⚠ NOTHING LEAVES THIS MACHINE WITHOUT AN EXPLICIT `--live`. The default is a dry run
that prints exactly what WOULD be sent, to which accounts, and stops. That is deliberate
and should stay that way: publishing is irreversible and reaches other people, and a
posting script that defaults to posting is one typo away from spamming six accounts.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The provider's REST base. Swapping vendors means changing this file and nothing else —
# the pipeline calls `publish()` and does not know who is on the other end.
API_BASE = "https://api.upload-post.com/api"
UPLOAD_ENDPOINT = f"{API_BASE}/upload"
## Read-only. Lists the profiles the key can see and which platforms each has linked.
USERS_ENDPOINT = f"{API_BASE}/uploadposts/users"
## ⚠ THE VENDOR CAN HOLD A POST UNTIL A DATE, AND THAT CHANGES THE WHOLE ARCHITECTURE.
## `scheduled_date` (ISO-8601, up to 365 days out) plus `timezone` (IANA) makes the
## upload a DEPOSIT rather than a publish: their servers do the posting, so the machine
## that queued it can be asleep, off, or logged out when the post goes live. A local
## cron only ever simulated this, and simulated it badly — it needed the laptop awake,
## plugged in, and logged on at exactly the right minute, every day, forever.
SCHEDULE_ENDPOINT = f"{API_BASE}/uploadposts/schedule"
## ⚠ THE ONLY WAY TO KNOW A SCHEDULED POST ACTUALLY WENT OUT. Queueing answers 202 and
## the vendor then holds the video for days — everything up to that point proves the
## DEPOSIT was taken, not that anything was published. This endpoint takes the `job_id`
## and reports per-platform outcomes once the scheduled time has passed. Without it the
## only failure detector is a human noticing an empty feed.
STATUS_ENDPOINT = f"{API_BASE}/uploadposts/status"

# Where the key lives. NEVER hard-code it and never commit it — `.env` is gitignored.
# ⚠ FORCE UTF-8 ON STDOUT. Windows consoles default to cp1252, and a caption is the
# one thing here most likely to carry an em dash or an emoji — which printed as `?` in
# the dry run. The caption SENT was always fine (the JSON is read as UTF-8 and the body
# is encoded explicitly); it was only the preview that lied. But a preview you cannot
# trust to show what will be posted defeats the point of having a dry run.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ENV_KEY = "UPLOAD_POST_API_KEY"
ENV_FILE = ROOT / ".env"

# ⚠ PER-PLATFORM CAPTION LIMITS, and they are not decoration. A caption over the limit
# is rejected by the platform AFTER the upload has consumed its rate-limit slot, so it
# costs a post to find out. Trimmed locally instead.
CAPTION_LIMITS = {
    "tiktok": 2200,
    "instagram": 2200,
    "youtube": 100,      # the TITLE limit — Shorts takes its title from here
    "x": 280,
    "reddit": 300,       # the post TITLE
    "bluesky": 300,
}

# ⚠ POSTING THE IDENTICAL CLIP TO SEVERAL ACCOUNTS ON ONE PLATFORM IS THE PATTERN THAT
# TRIPS SPAM DETECTION — not the automation itself, which the official APIs sanction.
# So a multi-account run staggers and varies rather than firing six identical posts.
DEFAULT_STAGGER_MINUTES = 25


@dataclass
class Target:
    """One profile, and every platform that profile should post this clip to at once.

    ⚠ CROSS-PLATFORM IS ONE CALL; CROSS-ACCOUNT IS NOT. The vendor takes a repeated
    `platform[]` field, so a single upload can land the same video on this profile's
    Instagram AND its TikTok — and it SHOULD, because the duplicate-content pattern that
    trips spam detection is the same clip on two accounts of the SAME platform, not the
    same clip on one account's two platforms. Every creator alive cross-posts a Reel to
    TikTok; nobody runs two Instagram accounts posting identical videos.

    That distinction halves the clip supply problem: two clips a day covers four
    accounts, not two.
    """
    profile: str          # the aggregator's profile name (one per account)
    platforms: list[str]  # one upload call, one or more destinations
    caption: str = ""
    draft: bool = True
    scheduled_offset_min: int = 0
    extra: dict = field(default_factory=dict)

    def __post_init__(self) -> None:
        if isinstance(self.platforms, str):        # tolerate the pre-multi shape
            self.platforms = [self.platforms]
        self.platforms = [p.lower() for p in self.platforms if p]

    @property
    def platform(self) -> str:
        """The first destination. Kept so single-platform callers read unchanged."""
        return self.platforms[0] if self.platforms else ""


def load_key() -> str | None:
    """Read the API key from the environment, falling back to a gitignored .env."""
    key = os.environ.get(ENV_KEY, "").strip()
    if key:
        return key
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith(f"{ENV_KEY}="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def fetch_profiles(key: str, timeout: int = 25) -> dict | None:
    """Ask the aggregator what is actually connected. Sends nothing, posts nothing."""
    import urllib.error
    import urllib.request
    req = urllib.request.Request(USERS_ENDPOINT, method="GET",
                                 headers={"Authorization": f"Apikey {key}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        print(f"  the API refused the key: HTTP {e.code}")
        return None
    except Exception as e:                                   # noqa: BLE001
        print(f"  could not reach the API: {type(e).__name__}: {e}")
        return None


def list_scheduled(key: str, timeout: int = 25) -> list[dict]:
    """Every post the VENDOR is holding for a future date. The only honest source of
    truth about what will go out — a local ledger records what we asked for, not what
    they accepted."""
    import urllib.error
    import urllib.request
    req = urllib.request.Request(SCHEDULE_ENDPOINT, method="GET",
                                 headers={"Authorization": f"Apikey {key}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8", "replace")).get(
                "scheduled_posts", []) or []
    except urllib.error.HTTPError as e:
        print(f"  could not list the schedule: HTTP {e.code} {e.read()[:200]!r}")
        return []
    except Exception as e:                                   # noqa: BLE001
        print(f"  could not reach the schedule endpoint: {type(e).__name__}: {e}")
        return []


def job_status(job_id: str, key: str, timeout: int = 25) -> dict:
    """What became of one queued job. `status` is pending/queued/processing/completed/
    failed/not_found, with a per-platform `results` list once it has run."""
    import urllib.error
    import urllib.request
    from urllib.parse import urlencode
    url = f"{STATUS_ENDPOINT}?{urlencode({'job_id': job_id})}"
    req = urllib.request.Request(url, method="GET",
                                 headers={"Authorization": f"Apikey {key}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        return {"status": f"http_{e.code}"}
    except Exception as e:                                   # noqa: BLE001
        return {"status": f"unreachable ({type(e).__name__})"}


def cancel_scheduled(job_id: str, key: str, timeout: int = 25) -> bool:
    """Cancel one queued job. Deletes the vendor-side asset with it."""
    import urllib.error
    import urllib.request
    req = urllib.request.Request(f"{SCHEDULE_ENDPOINT}/{job_id}", method="DELETE",
                                 headers={"Authorization": f"Apikey {key}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status == 200
    except Exception as e:                                   # noqa: BLE001
        print(f"  could not cancel {job_id}: {e}")
        return False


def cmd_check(targets_path: Path) -> int:
    """What is linked, and does the targets file agree with it?

    ⚠ THIS EXISTS BECAUSE A PROFILE NAME IS A STRING TYPED IN TWO PLACES. The targets
    file names a profile; the aggregator has its own. They are matched by exact string
    at upload time, so a mismatch does not fail loudly at the top — it fails per target,
    after the video has been read and sent, with an error about a profile rather than
    about your spelling. Cheaper to ask first.
    """
    key = load_key()
    if not key:
        print(f"No API key. Put {ENV_KEY}=... in {ENV_FILE.name} (it is gitignored).")
        return 1
    data = fetch_profiles(key)
    if data is None:
        return 1

    profiles = data.get("profiles", []) or []
    plan, limit = data.get("plan", "?"), data.get("limit", "?")
    print(f"\nplan {plan}   profiles {len(profiles)}/{limit}\n")

    linked: set[tuple[str, str]] = set()
    for prof in profiles:
        name = str(prof.get("username", ""))
        accounts = prof.get("social_accounts", {}) or {}
        print(f"  profile {name!r}" + ("   [BLOCKED]" if prof.get("blocked") else ""))
        any_linked = False
        for platform, info in accounts.items():
            # An unconnected platform comes back as an empty string, not a missing key.
            if not info:
                continue
            any_linked = True
            handle = info.get("handle") or info.get("display_name") or "?"                 if isinstance(info, dict) else str(info)
            reauth = isinstance(info, dict) and info.get("reauth_required")
            print(f"      {platform:<10} {handle}" + ("   ⚠ NEEDS RE-AUTH" if reauth else ""))
            linked.add((name, platform))
        if not any_linked:
            print("      (nothing linked yet)")

    if not targets_path.exists():
        print(f"\nNo targets file at {targets_path} — nothing to cross-check.")
        return 0

    targets = load_targets(targets_path)
    print(f"\n  {targets_path.name} asks for {len(targets)} destination(s):")
    problems = 0
    for t in targets:
        for platform in t.platforms:
            ok = (t.profile, platform) in linked
            if not ok:
                problems += 1
            print(f"      {platform:<10} as {t.profile:<12} " +
                  ("ok" if ok else "*** NOT LINKED — this target would fail ***"))
    if problems:
        print(f"\n  {problems} target(s) point at something that is not connected. "
              f"Fix the profile name or link the account before --live.")
        return 1
    print("\n  every target is linked. --live would post to all of them.")
    return 0


def trim_caption(caption: str, platform: str | list[str]) -> str:
    """Fit the caption to the platform, cutting on a word boundary rather than mid-word.

    ⚠ WITH SEVERAL PLATFORMS IN ONE CALL THE STRICTEST ONE WINS, because there is only
    one `title` field on the wire. YouTube's 100-character title limit against TikTok's
    2200 is not a rounding difference — send a 300-character caption to a call that
    includes YouTube and the whole upload is rejected after the video has been sent.
    """
    platforms = [platform] if isinstance(platform, str) else list(platform)
    limit = min((CAPTION_LIMITS.get(p, 2200) for p in platforms), default=2200)
    if len(caption) <= limit:
        return caption
    cut = caption[: limit - 1]
    if " " in cut:
        cut = cut.rsplit(" ", 1)[0]
    return cut + "…"


## ⚠ WHICH PLATFORMS ACTUALLY HAVE A DRAFT. Not a style choice — a fact about the
## upstream APIs, and getting it wrong misreports what a --live run just did to somebody
## else's audience.
##
## TikTok has an INBOX: `MEDIA_UPLOAD` lands the video in the app for a human to finish,
## which is the whole reason this tool defaults to it. INSTAGRAM HAS NO SUCH THING —
## Meta's Content Publishing API is create-a-container then `media_publish`, and there
## is no draft state anywhere in it, so `post_mode` is simply ignored and the Reel goes
## live. This tool printed "DRAFT (you add the sound in-app)" for Instagram anyway and
## reported two posts as drafts that were already public. Maker: *"they arent drafts
## they have been posted"*.
DRAFT_CAPABLE: frozenset = frozenset({"tiktok"})


def _mode_label(platform: str, post_mode: str) -> str:
    """What will ACTUALLY happen to this upload, per platform."""
    if post_mode != "MEDIA_UPLOAD":
        return "PUBLISH IMMEDIATELY"
    if platform in DRAFT_CAPABLE:
        return "DRAFT (you finish it in-app)"
    return "PUBLISH IMMEDIATELY (%s has no draft)" % platform


def build_requests(clip: Path, targets: list[Target], caption: str,
                   stagger: int) -> list[dict]:
    """Turn one clip plus a target list into the exact payloads that would be sent.

    Pure: it touches no network and no disk beyond stat-ing the clip, which is what
    makes the dry run an honest preview rather than a different code path.
    """
    out: list[dict] = []
    seen_per_platform: dict[str, int] = {}
    for t in targets:
        # ⚠ THE STAGGER COUNTS PER PLATFORM, NOT PER TARGET, and with multi-platform
        # targets it takes the WORST case. Two profiles both posting to Instagram are
        # the pair that must not fire together; that one of them also posts to TikTok
        # changes nothing about the Instagram collision.
        n = max((seen_per_platform.get(p, 0) for p in t.platforms), default=0)
        for p in t.platforms:
            seen_per_platform[p] = seen_per_platform.get(p, 0) + 1
        text = trim_caption(t.caption or caption, t.platforms)
        payload = {
            "user": t.profile,
            "platform": list(t.platforms),
            "video": str(clip),
            "title": text,
            # Draft/inbox rather than straight to the feed — see the module docstring.
            "post_mode": "MEDIA_UPLOAD" if t.draft else "DIRECT_POST",
        }
        delay = t.scheduled_offset_min or (n * stagger)
        if delay:
            payload["schedule_offset_minutes"] = delay
        payload.update(t.extra)
        out.append(payload)
    return out


def load_targets(path: Path) -> list[Target]:
    """Read the account list. See `content/targets.example.json` for the shape."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    targets: list[Target] = []
    for row in raw.get("targets", []):
        # `platforms: [...]` is the current shape; a bare `platform: "..."` is the
        # original one and still reads, so an old targets file keeps working.
        plats = row.get("platforms") or [row["platform"]]
        targets.append(Target(
            profile=row["profile"],
            platforms=[str(p).lower() for p in plats],
            caption=row.get("caption", ""),
            draft=bool(row.get("draft", True)),
            scheduled_offset_min=int(row.get("schedule_offset_minutes", 0)),
            extra=row.get("extra", {}),
        ))
    return targets


def send(payloads: list[dict], key: str, timeout: int = 300,
         results: list[dict] | None = None) -> int:
    """Actually post. Only ever reached with --live; see the safety note above.

    ⚠ 202 IS A SUCCESS, NOT A SURPRISE. A scheduled upload answers `202 Accepted` with
    a `job_id` rather than `200 OK`; treating any non-200 as a failure would have marked
    every scheduled post as failed and re-queued the lot on the next run. `results`
    collects the decoded body per payload so the caller can record that job_id — without
    it a scheduled post is fire-and-forget and there is no way to list or cancel it.
    """
    import urllib.error
    import urllib.request

    failures = 0
    for p in payloads:
        video = Path(p.pop("video"))
        if not video.exists():
            print(f"  ! {video} is gone")
            failures += 1
            continue
        # multipart, hand-rolled to keep this dependency-free like the rest of the tools
        boundary = "----lfclip" + os.urandom(8).hex()
        parts: list[bytes] = []
        # ⚠ A LIST BECOMES REPEATED `name[]` FIELDS, NOT A JSON STRING. This is the
        # difference between a post and an HTTP 400, and it cost the first real upload:
        # `json.dumps(["instagram"])` put the literal text `["instagram"]` into a field
        # called `platform`, and the API answered *"At least one platform is required in
        # form data"* — which is true, because it never saw one. Their documented shape
        # is `-F 'platform[]=tiktok'`, once per platform.
        #
        # ⚠ AND THE DRY RUN COULD NOT HAVE CAUGHT IT. `build_requests` is pure and is
        # shared with the preview, so the preview was honest about WHAT was being sent
        # and silent about HOW — the encoding lives only on this path, which --live is
        # the first thing to execute. A preview that stops short of the wire format is
        # not a preview of the request.
        for k, v in p.items():
            if isinstance(v, (list, tuple)):
                for item in v:
                    parts.append(
                        f"--{boundary}\r\nContent-Disposition: form-data; "
                        f"name=\"{k}[]\"\r\n\r\n{item}\r\n".encode("utf-8"))
                continue
            val = json.dumps(v) if isinstance(v, dict) else str(v)
            parts.append(
                f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n"
                f"{val}\r\n".encode("utf-8"))
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"video\"; "
            f"filename=\"{video.name}\"\r\nContent-Type: video/mp4\r\n\r\n".encode("utf-8"))
        parts.append(video.read_bytes())
        parts.append(f"\r\n--{boundary}--\r\n".encode("utf-8"))
        body = b"".join(parts)
        req = urllib.request.Request(
            UPLOAD_ENDPOINT, data=body, method="POST",
            headers={
                "Authorization": f"ApiKey {key}",
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            })
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read().decode("utf-8", "replace")
                try:
                    body = json.loads(raw)
                except json.JSONDecodeError:
                    body = {"raw": raw[:200]}
                job = body.get("job_id") or ""
                when = p.get("scheduled_date", "")
                note = f"  scheduled {when}  job {job}" if job else ""
                print(f"  -> {','.join(p.get('platform') or [])} as {p.get('user')}: "
                      f"HTTP {r.status}{note}")
                if results is not None:
                    results.append({"user": p.get("user"), "job_id": job,
                                    "scheduled_date": when, "status": r.status})
        except urllib.error.HTTPError as e:
            print(f"  ! {','.join(p.get('platform') or [])} as {p.get('user')}: HTTP {e.code} "
                  f"{e.read()[:300]!r}")
            failures += 1
        except Exception as e:  # noqa: BLE001 — a network tool reports, it does not raise
            print(f"  ! {','.join(p.get('platform') or [])} as {p.get('user')}: {e}")
            failures += 1
    return failures


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("clip", type=Path, nargs="?",
                    help="the finished .mp4 (not needed with --check)")
    ap.add_argument("--targets", type=Path, default=ROOT / "content" / "targets.json",
                    help="account list (see content/targets.example.json)")
    ap.add_argument("--caption", default="", help="caption used where a target has none")
    ap.add_argument("--stagger", type=int, default=DEFAULT_STAGGER_MINUTES,
                    help="minutes between accounts on the SAME platform")
    ap.add_argument("--publish", action="store_true",
                    help="DIRECT_POST instead of uploading as a draft. ⚠ a published "
                         "clip cannot carry a trending sound — see the module docstring")
    ap.add_argument("--check", action="store_true",
                    help="ask the API what is linked and cross-check the targets file; "
                         "sends nothing")
    ap.add_argument("--live", action="store_true",
                    help="⚠ actually send. Without this it is a dry run and nothing "
                         "leaves the machine")
    args = ap.parse_args()

    # --check is a read-only question about the account setup, so it runs before any
    # of the clip handling below and needs no clip at all.
    if args.check:
        return cmd_check(args.targets)
    if args.clip is None:
        ap.error("a clip is required (or use --check)")

    if not args.clip.exists():
        print(f"no clip at {args.clip}")
        return 2
    if not args.targets.exists():
        print(f"no target list at {args.targets}\n"
              f"copy content/targets.example.json to {args.targets} and fill it in")
        return 2

    targets = load_targets(args.targets)
    if not targets:
        print("the target list is empty")
        return 2
    if args.publish:
        for t in targets:
            t.draft = False

    size_mb = args.clip.stat().st_size / 1e6
    payloads = build_requests(args.clip, targets, args.caption, args.stagger)

    print(f"\n{args.clip.name}  ({size_mb:.1f} MB)  ->  {len(payloads)} destination(s)")
    for p in payloads:
        when = p.get("schedule_offset_minutes", 0)
        delay = f"  +{when}min" if when else ""
        print(f"  as {p['user']}{delay}")
        # One line per platform: the same post_mode means different things on each, and
        # a preview that collapses them hides that TikTok will wait in an inbox while
        # Instagram is already public.
        for platform in p["platform"]:
            print(f"      {platform:<10} {_mode_label(platform, p['post_mode'])}")
        print(f"      \"{p['title'][:70]}\"")

    if not args.live:
        print("\nDRY RUN — nothing was sent. Add --live to actually upload.")
        return 0

    key = load_key()
    if not key:
        print(f"\n{ENV_KEY} is not set. Put it in {ENV_FILE} (gitignored) or the "
              f"environment.\nNothing sent.")
        return 2
    print("\nsending...")
    failed = send(payloads, key)
    print(f"done — {len(payloads) - failed}/{len(payloads)} accepted")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
