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

⚠ AND IT UPLOADS AS A DRAFT BY DEFAULT, ON PURPOSE. Video published through ANY API
cannot use the platform's licensed music library — trending audio can only be applied
in-app. The maker's stated workflow is *"I will add the music etc."*, which is the same
constraint arriving from the other direction. `--publish` exists, but draft is the
default because a clip that posts itself is a clip that can never carry a trending
sound, and on short-form the sound is half the reach.

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

# Where the key lives. NEVER hard-code it and never commit it — `.env` is gitignored.
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
    """One account on one platform."""
    profile: str          # the aggregator's profile name (one per account)
    platform: str
    caption: str = ""
    draft: bool = True
    scheduled_offset_min: int = 0
    extra: dict = field(default_factory=dict)


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


def trim_caption(caption: str, platform: str) -> str:
    """Fit the caption to the platform, cutting on a word boundary rather than mid-word."""
    limit = CAPTION_LIMITS.get(platform, 2200)
    if len(caption) <= limit:
        return caption
    cut = caption[: limit - 1]
    if " " in cut:
        cut = cut.rsplit(" ", 1)[0]
    return cut + "…"


def build_requests(clip: Path, targets: list[Target], caption: str,
                   stagger: int) -> list[dict]:
    """Turn one clip plus a target list into the exact payloads that would be sent.

    Pure: it touches no network and no disk beyond stat-ing the clip, which is what
    makes the dry run an honest preview rather than a different code path.
    """
    out: list[dict] = []
    seen_per_platform: dict[str, int] = {}
    for t in targets:
        n = seen_per_platform.get(t.platform, 0)
        seen_per_platform[t.platform] = n + 1
        text = trim_caption(t.caption or caption, t.platform)
        payload = {
            "user": t.profile,
            "platform": [t.platform],
            "video": str(clip),
            "title": text,
            # Draft/inbox rather than straight to the feed — see the module docstring.
            "post_mode": "MEDIA_UPLOAD" if t.draft else "DIRECT_POST",
        }
        # The second and later accounts on the SAME platform are staggered, because
        # simultaneous identical posts are the spam signal.
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
        targets.append(Target(
            profile=row["profile"],
            platform=row["platform"].lower(),
            caption=row.get("caption", ""),
            draft=bool(row.get("draft", True)),
            scheduled_offset_min=int(row.get("schedule_offset_minutes", 0)),
            extra=row.get("extra", {}),
        ))
    return targets


def send(payloads: list[dict], key: str, timeout: int = 300) -> int:
    """Actually post. Only ever reached with --live; see the safety note above."""
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
        for k, v in p.items():
            val = json.dumps(v) if isinstance(v, (list, dict)) else str(v)
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
                print(f"  -> {p.get('platform')} as {p.get('user')}: HTTP {r.status}")
        except urllib.error.HTTPError as e:
            print(f"  ! {p.get('platform')} as {p.get('user')}: HTTP {e.code} "
                  f"{e.read()[:300]!r}")
            failures += 1
        except Exception as e:  # noqa: BLE001 — a network tool reports, it does not raise
            print(f"  ! {p.get('platform')} as {p.get('user')}: {e}")
            failures += 1
    return failures


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("clip", type=Path, help="the finished .mp4")
    ap.add_argument("--targets", type=Path, default=ROOT / "content" / "targets.json",
                    help="account list (see content/targets.example.json)")
    ap.add_argument("--caption", default="", help="caption used where a target has none")
    ap.add_argument("--stagger", type=int, default=DEFAULT_STAGGER_MINUTES,
                    help="minutes between accounts on the SAME platform")
    ap.add_argument("--publish", action="store_true",
                    help="DIRECT_POST instead of uploading as a draft. ⚠ a published "
                         "clip cannot carry a trending sound — see the module docstring")
    ap.add_argument("--live", action="store_true",
                    help="⚠ actually send. Without this it is a dry run and nothing "
                         "leaves the machine")
    args = ap.parse_args()

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
        mode = "DRAFT (you add the sound in-app)" if p["post_mode"] == "MEDIA_UPLOAD" \
            else "PUBLISH IMMEDIATELY"
        delay = f"  +{when}min" if when else ""
        print(f"  {p['platform'][0]:<10} as {p['user']:<18} {mode}{delay}")
        print(f"             \"{p['title'][:70]}\"")

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
