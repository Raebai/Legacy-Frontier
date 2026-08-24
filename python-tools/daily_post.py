#!/usr/bin/env python3
"""ONE POST PER ACCOUNT PER DAY, from the clips already on disk.

    python python-tools/daily_post.py              # dry run — says what it WOULD post
    python python-tools/daily_post.py --live       # actually post
    python python-tools/daily_post.py --status     # what is queued, what has gone out

⚠ IT DOES NOT SHOOT ANYTHING, AND THAT IS THE WHOLE DESIGN. The obvious build is
"render a fresh fight each morning and post it", and it is the wrong one on this
machine for three separate reasons, any one of which is enough:

  * A SHOOT NEEDS A REAL RENDERER. `make_post` runs Godot WITHOUT `--headless`, because
    a null rendering driver produces blank frames that save successfully. So it needs a
    GPU, a session, and the machine awake — at 9am, unattended, every day.
  * A SHOOT REWRITES project.godot. `make_clip._render_size` patches the window override
    and restores it in a `finally`. A crash mid-shoot leaves the maker's project on a
    clip-shaped window, and a shoot that fires while they are playing fights them for it.
  * A SHOOT CAN FAIL THE QUALITY GATE. Roughly one bout in three comes back a
    demolition. An unattended shoot would either post it anyway or post nothing.

So the render stays a deliberate, watched act and this script only ever DELIVERS. The
queue is the clips in `content/posts/`, each one already scored, watched and approved.
When it runs low the script says so, loudly, with days remaining.

⚠ AND IT POSTS THE BEDDED FILE, NEVER THE `.nomusic` COMPANION. The companion exists so
a trending sound can be attached by hand in the app — but Instagram has no draft state,
so an automated upload is LIVE the moment it lands and no hand ever reaches it. Posting
the silent cut automatically would publish a fight with no audio at all.

THE LEDGER (`content/posted.json`) is what stops a repeat. It records, per account,
which clips have gone out and when. Two accounts never get the same fight — the maker's
rule is volume, not mirroring, and identical posts across accounts on one platform is
also the exact pattern spam detection looks for.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import publish_clip as pc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
POSTS = ROOT / "content" / "posts"
LEDGER = ROOT / "content" / "posted.json"
ACCOUNTS_FILE = ROOT / "content" / "daily_accounts.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

## Warn here. Two accounts a day means the pool empties twice as fast as it looks.
LOW_WATER_DAYS = 3


def title_of(stem: str) -> str:
    """`warlock_vs_cleric` -> `WARLOCK vs CLERIC`. The caption's whole first line.

    ⚠ SHORT ON PURPOSE. Maker: *"going forward just the hashtags and the title is good
    enough for now"* — the descriptive sentence under the matchup was doing nothing a
    viewer needed and read as marketing copy under a video that speaks for itself.
    """
    parts = stem.split("_vs_")
    if len(parts) == 2:
        return f"{parts[0].upper()} vs {parts[1].upper()}"
    return stem.replace("_", " ").upper()


def pool() -> list[Path]:
    """Every postable clip, oldest first so the queue drains in a stable order.

    Sorted by NAME rather than mtime: a re-cut bumps a clip's mtime and would otherwise
    silently jump it to the back of the queue, changing the order under a schedule that
    is meant to be predictable.
    """
    return sorted(p for p in POSTS.glob("*.mp4") if ".nomusic" not in p.name)


def load_ledger() -> dict:
    if not LEDGER.exists():
        return {"posted": {}}
    try:
        return json.loads(LEDGER.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        # A corrupt ledger must not be read as "nothing has been posted" — that would
        # repost the whole back catalogue. Refuse instead.
        sys.exit(f"{LEDGER} is unreadable. Fix or delete it deliberately; refusing to "
                 f"treat it as an empty history.")


def save_ledger(data: dict) -> None:
    """Atomic, so a crash mid-write cannot leave a ledger that reposts everything."""
    tmp = LEDGER.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    tmp.replace(LEDGER)


def load_accounts() -> list[dict]:
    if not ACCOUNTS_FILE.exists():
        sys.exit(f"{ACCOUNTS_FILE} is missing. See the repo's example.")
    return json.loads(ACCOUNTS_FILE.read_text(encoding="utf-8"))["accounts"]


def pick(account: str, ledger: dict, taken: set[str]) -> Path | None:
    """The next clip this account has not had, that no other account is taking today."""
    done = set(ledger["posted"].get(account, {}).keys())
    for clip in pool():
        if clip.stem in done or clip.stem in taken:
            continue
        return clip
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--live", action="store_true",
                    help="actually post. Without it this is a dry run.")
    ap.add_argument("--status", action="store_true", help="show the queue and stop")
    args = ap.parse_args()
    # ⚠ AN OFF SWITCH THE SCHEDULED COMMAND CAN SEE. The .cmd wrapper hardcodes --live,
    # which means the exact line Task Scheduler runs cannot be rehearsed without
    # posting — so the wrapper would only ever be proven by a real post going out, or
    # not going out, tomorrow. This env var lets the identical command be executed end
    # to end (paths, interpreter, logging, exit code) with the upload suppressed.
    if os.environ.get("STICKSPIRE_DAILY_DRY", "").strip() == "1":
        args.live = False
        print("  [STICKSPIRE_DAILY_DRY=1 — upload suppressed for this run]")

    accounts = load_accounts()
    ledger = load_ledger()
    clips = pool()

    if args.status:
        print(f"\n{len(clips)} clip(s) in the pool\n")
        for a in accounts:
            done = ledger["posted"].get(a["profile"], {})
            left = [c for c in clips if c.stem not in done]
            print(f"  {a['profile']:<20} posted {len(done):>2}   "
                  f"{len(left):>2} left  ({len(left)} day(s))")
            for stem, when in sorted(done.items(), key=lambda kv: kv[1]):
                print(f"      {when[:10]}  {stem}")
        return 0

    key = pc.load_key() if args.live else None
    if args.live and not key:
        print(f"{pc.ENV_KEY} is not set. Nothing sent.")
        return 1

    today = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    taken: set[str] = set()
    failures = 0
    posted_any = False

    for i, acct in enumerate(accounts):
        profile = acct["profile"]
        clip = pick(profile, ledger, taken)
        if clip is None:
            print(f"  {profile}: NOTHING LEFT TO POST — every clip in the pool has "
                  f"already gone out on this account. Shoot more with make_post.py.")
            failures += 1
            continue
        taken.add(clip.stem)
        caption = f"{title_of(clip.stem)}\n\n{acct['hashtags']}"
        target = pc.Target(profile=profile, platform=acct["platform"],
                           caption=caption, draft=bool(acct.get("draft", True)))
        # ⚠ STAGGERED. Two accounts posting to one platform in the same second is the
        # spam signal, not the automation itself.
        target.scheduled_offset_min = i * int(acct.get("stagger_minutes", 0))
        payloads = pc.build_requests(clip, [target], caption, 0)
        mode = pc._mode_label(acct["platform"], payloads[0]["post_mode"])
        print(f"\n  {profile}  ->  {clip.name}  ({clip.stat().st_size / 1e6:.1f} MB)")
        print(f"      {acct['platform']}   {mode}")
        print(f"      {caption.splitlines()[0]}")
        if not args.live:
            continue
        if pc.send(payloads, key) == 0:
            ledger["posted"].setdefault(profile, {})[clip.stem] = today
            posted_any = True
        else:
            failures += 1

    if posted_any:
        save_ledger(ledger)

    # The runway warning, in days rather than in clips, because two accounts a day
    # empties a pool twice as fast as its length suggests.
    for acct in accounts:
        done = ledger["posted"].get(acct["profile"], {})
        left = len([c for c in clips if c.stem not in done])
        if left <= LOW_WATER_DAYS:
            print(f"\n  ⚠ {acct['profile']} has {left} day(s) of clips left. "
                  f"Shoot more: python python-tools/make_post.py --a N --b M")

    if not args.live:
        print("\nDRY RUN — nothing was sent. Add --live to actually post.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
