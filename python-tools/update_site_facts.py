#!/usr/bin/env python3
"""Rewrite the landing page's numbers from the accounts, so they cannot drift into fiction.

    python python-tools/update_site_facts.py            # show what would change
    python python-tools/update_site_facts.py --write    # rewrite site/index.html

⚠ THIS EXISTS BECAUSE OF WHAT IS *NOT* ON THAT PAGE. The section it feeds is headed
"No reviews yet. Here are the numbers." — because nobody has reviewed this game and all
eight posts to date carry zero comments, checked through the API. A testimonial invented
to fill that space would be the one thing on the page a visitor could catch as a lie,
and it is the thing they would remember.

The honest substitute is only honest while it is TRUE. A number typed into HTML by hand
is accurate for about a week and then quietly becomes a claim nobody is checking — which
is the same failure as the fake quote, arriving more slowly. So the page carries a
provenance stamp saying when these were read, and this script is the only thing that
writes them.

⚠ IMPRESSIONS ARE NOT PEOPLE, and the label says so. `total-impressions` counts TIMES
SHOWN, not humans; summing per-post `reach` instead would double-count everybody who saw
more than one fight. Neither is "people who saw the game", so the page does not say that.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analytics_api as api  # noqa: E402
import publish_clip as pc  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
PAGE = ROOT / "site" / "index.html"
CLIPS = ROOT / "content" / "posts"


def gather(key: str) -> dict:
    """Every figure on the page, read from somewhere that can be checked."""
    # Ask which profiles the key can see rather than reading a config file, so a
    # profile added at the vendor is counted without anything here being edited.
    data = pc.fetch_profiles(key) or {}
    profiles = [str(p.get("username", "")) for p in data.get("profiles", []) or []]
    month_start = datetime.now(timezone.utc).replace(day=1).strftime("%Y-%m-%d")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    impressions = 0
    for profile in profiles:
        try:
            data = api.total_impressions(profile, key, start=month_start, end=today,
                                         breakdown=False)
            impressions += int(data.get("total_impressions") or 0)
        except api.ApiError as e:
            print(f"  ! {profile}: {e}")

    posts = [r for r in api.upload_history(key) if r.get("success")]
    clips = [p for p in CLIPS.glob("*.mp4") if ".nomusic" not in p.name]

    return {
        "reach": f"{impressions:,}",
        "clips": str(len(clips)),
        "posts": str(len(posts)),
        "people": "1",
        # `%-d` is not portable to Windows, so strip the pad by hand.
        "stamp": "Read from the accounts on "
                 + datetime.now(timezone.utc).strftime("%d %b %Y").lstrip("0")
                 + " — not chosen.",
    }


def apply(html: str, facts: dict) -> tuple[str, list[str]]:
    """Swap each value in place, leaving every word around it alone.

    Anchored on `data-fact="..."`, which is why those attributes are on the page at
    all: matching on the numbers themselves would rewrite whichever `17` it found
    first, and matching on surrounding prose would break the moment the prose is
    edited.
    """
    changes: list[str] = []
    for name, value in facts.items():
        if name == "stamp":
            pattern = re.compile(r'(data-fact="stamp"[^>]*>)(.*?)(</p>)', re.S)
        else:
            # The number sits between the tag and the <small> that explains it.
            pattern = re.compile(rf'(data-fact="{name}"[^>]*>)(.*?)(<small>)', re.S)
        match = pattern.search(html)
        if not match:
            changes.append(f"  ! no slot found for '{name}' — page structure changed")
            continue
        if match.group(2).strip() == value:
            continue
        changes.append(f"  {name}: {match.group(2).strip()!r} -> {value!r}")
        html = html[:match.start(2)] + value + html[match.end(2):]
    return html, changes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true",
                    help="rewrite site/index.html. Without it, nothing is touched.")
    args = ap.parse_args()

    key = pc.load_key()
    if not key:
        print(f"{pc.ENV_KEY} is not set — the numbers can only come from the accounts.")
        return 1
    if not PAGE.exists():
        print(f"no page at {PAGE}")
        return 1

    print("\nreading the accounts...")
    facts = gather(key)
    for name, value in facts.items():
        print(f"  {name:<8} {value}")

    html = PAGE.read_text(encoding="utf-8")
    updated, changes = apply(html, facts)

    print()
    if not changes:
        print("the page already says exactly this. Nothing to do.")
        return 0
    for line in changes:
        print(line)
    if not args.write:
        print("\nDRY RUN — nothing written. Add --write.")
        return 0
    # newline="": site/index.html is pinned eol=lf and is deployed as-is.
    PAGE.write_text(updated, encoding="utf-8", newline="")
    print(f"\nrewrote {PAGE.relative_to(ROOT)}. Redeploy for it to be public:")
    print("  npx wrangler pages deploy site --project-name stickspire")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
