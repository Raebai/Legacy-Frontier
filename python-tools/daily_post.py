#!/usr/bin/env python3
"""ONE POST PER ACCOUNT PER DAY — QUEUED AT THE VENDOR, not run from this machine.

    python python-tools/daily_post.py --schedule 7          # dry run: next 7 days
    python python-tools/daily_post.py --schedule 7 --live   # actually queue them
    python python-tools/daily_post.py --list                # what the VENDOR is holding
    python python-tools/daily_post.py --cancel-all --live   # unqueue everything
    python python-tools/daily_post.py --status              # the local ledger

⚠ THE POSTING DOES NOT HAPPEN HERE, AND THAT IS THE POINT. Maker: *"I want it to just
run every single day no need for me to login like thats the whole point of the API
right"*. Right — and a Windows scheduled task was the wrong answer to it. That approach
needed the laptop AWAKE, PLUGGED IN and LOGGED ON at the same minute every day forever,
and failed silently on any morning it was not: one closed lid, one lost day, no error.

`scheduled_date` makes an upload a DEPOSIT instead of a publish. The video and its
caption go to Upload-Post now and their servers publish it on the date given, up to 365
days out. Once a day is queued, this machine is irrelevant to it — off, asleep, logged
out, reinstalled. Queueing a week takes one run.

⚠ SO ONLY ONE MECHANISM MAY EXIST AT A TIME. A local daily task AND a vendor-side queue
would both fire and post twice. The Windows task is deleted; if it is ever restored,
this must not be scheduling.

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
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
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
## ⚠ THE CLOCK IS RESOLVED HERE, NOT AT THE VENDOR. The API accepts an IANA `timezone`
## alongside the date, but that leaves the interpretation to somebody else's code on the
## one field where being an hour wrong is visible to an audience. Converting to a
## UTC instant with a `Z` and sending no timezone is unambiguous — and `zoneinfo` gets
## the BST/GMT switch right, which a fixed +1 offset would silently break in October.
POST_TZ = "Europe/London"


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


def spoken_for(ledger: dict) -> set[str]:
    """Every clip already public OR already sitting in the vendor's queue.

    ⚠ BOTH, and the second half is the one that bites. A clip queued for Thursday has
    not been posted yet, so a ledger that only tracked `posted` would happily queue it
    again for Friday — and the duplicate would only surface when both went live.
    """
    used: set[str] = set()
    for by_acct in ledger.get("posted", {}).values():
        used |= set(by_acct.keys())
    for row in ledger.get("scheduled", []):
        used.add(row["clip"])
    return used


def pick(account: str, ledger: dict, taken: set[str]) -> Path | None:
    """The next clip nobody has posted, nobody has queued, and nobody is taking now."""
    used = spoken_for(ledger) | taken
    for clip in pool():
        if clip.stem in used:
            continue
        return clip
    return None


def slot(day_offset: int, hhmm: str) -> tuple[str, str]:
    """(what the vendor is told, what a human reads) for a post `day_offset` days out."""
    hh, mm = (int(x) for x in hhmm.split(":"))
    local = (datetime.now(ZoneInfo(POST_TZ)) + timedelta(days=day_offset)).replace(
        hour=hh, minute=mm, second=0, microsecond=0)
    utc = local.astimezone(timezone.utc)
    return utc.strftime("%Y-%m-%dT%H:%M:%SZ"), local.strftime("%a %d %b %H:%M %Z")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--schedule", type=int, metavar="DAYS",
                    help="queue this many days at the vendor, starting tomorrow")
    ap.add_argument("--live", action="store_true",
                    help="actually talk to the API. Without it everything is a dry run.")
    ap.add_argument("--status", action="store_true", help="the local ledger")
    ap.add_argument("--list", action="store_true", help="what the VENDOR is holding")
    ap.add_argument("--verify", action="store_true",
                    help="did the queued posts actually GO OUT? asks per job_id")
    ap.add_argument("--cancel-all", action="store_true",
                    help="cancel every queued post and forget them locally")
    args = ap.parse_args()

    accounts = load_accounts()
    ledger = load_ledger()
    ledger.setdefault("scheduled", [])
    clips = pool()

    if args.status:
        used = spoken_for(ledger)
        print()
        print(f"{len(clips)} clip(s) on disk, {len(clips) - len(used)} unspoken-for")
        print()
        for a in accounts:
            done = ledger["posted"].get(a["profile"], {})
            queued = [r for r in ledger["scheduled"] if r["profile"] == a["profile"]]
            print(f"  {a['profile']:<20} posted {len(done):>2}   queued {len(queued):>2}")
            for stem, when in sorted(done.items(), key=lambda kv: kv[1]):
                print(f"      posted    {when[:10]}  {stem}")
            for r in sorted(queued, key=lambda r: r["when_utc"]):
                print(f"      queued    {r['when_local']:<22}  {r['clip']}")
        return 0

    key = pc.load_key()
    if not key:
        print(f"{pc.ENV_KEY} is not set. Nothing to do.")
        return 1

    if args.list:
        rows = pc.list_scheduled(key)
        print()
        print(f"the vendor is holding {len(rows)} scheduled post(s)")
        print()
        for r in sorted(rows, key=lambda r: str(r.get("scheduled_date"))):
            title = str(r.get("title") or "").splitlines()
            print(f"  {str(r.get('scheduled_date'))[:16]:<18} "
                  f"{str(r.get('profile_username')):<20} "
                  f"{','.join(r.get('platforms') or []):<11} "
                  f"{title[0][:32] if title else ''}")
            print(f"      job {r.get('job_id')}")
        return 0

    if args.verify:
        # Everything before this point proves a deposit was TAKEN. This is the only
        # thing that proves anything was PUBLISHED.
        rows = [r for r in ledger["scheduled"] if r.get("job_id")]
        if not rows:
            print("nothing queued with a job_id to verify.")
            return 0
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        print()
        bad = 0
        for r in sorted(rows, key=lambda r: r["when_utc"]):
            st = pc.job_status(r["job_id"], key)
            state = str(st.get("status", "?"))
            due = r["when_utc"] <= now
            # A job still sitting in a pre-run state AFTER its time is the failure this
            # exists to catch — it is silent everywhere else.
            flag = ""
            if due and state in ("pending", "queued", "processing", "in_progress"):
                flag = "   <-- OVERDUE, has not run"
                bad += 1
            elif state == "failed":
                flag = "   <-- FAILED"
                bad += 1
            elif not due:
                flag = "   (not due yet)"
            print(f"  {r['when_local']:<22} {r['profile']:<20} {state:<12}"
                  f"{flag}")
            print(f"      {r['clip']}")
            # ⚠ READ THE PLATFORM'S OWN `status`, NOT `success`. Every result carries
            # `success: false` until it has actually run, so inferring FAIL from a
            # falsy success marked all six queued jobs as failures — an alerting tool
            # that cries wolf on healthy state is worse than no alerting at all.
            for res in st.get("results", []) or []:
                pstate = str(res.get("status", "?"))
                mark = {"completed": "ok  ", "failed": "FAIL",
                        "retryable": "retry"}.get(pstate, "    ")
                detail = res.get("message") or ""
                stamp = res.get("upload_timestamp") or ""
                print(f"      {mark} {res.get('platform')}: {pstate}"
                      f"{'  ' + detail if detail else ''}"
                      f"{'  ' + stamp if stamp else ''}")
        print()
        print(f"{len(rows)} queued, {bad} needing attention")
        return 1 if bad else 0

    if args.cancel_all:
        rows = pc.list_scheduled(key)
        print()
        print(f"{len(rows)} scheduled post(s) would be cancelled")
        for r in rows:
            print(f"  {str(r.get('scheduled_date'))[:16]}  {r.get('profile_username')}"
                  f"  job {r.get('job_id')}")
        if not args.live:
            print()
            print("DRY RUN - nothing cancelled. Add --live.")
            return 0
        gone = 0
        for r in rows:
            if pc.cancel_scheduled(str(r.get("job_id")), key):
                gone += 1
        ledger["scheduled"] = []
        save_ledger(ledger)
        print(f"cancelled {gone}/{len(rows)}; local queue cleared")
        return 0 if gone == len(rows) else 1

    if not args.schedule:
        print("Nothing asked for. Try --schedule 7, --status, or --list.")
        return 1

    failures = 0
    queued_any = False
    for day in range(1, args.schedule + 1):
        taken: set[str] = set()
        for acct in accounts:
            profile = acct["profile"]
            clip = pick(profile, ledger, taken)
            if clip is None:
                print()
                print(f"  day +{day} {profile}: OUT OF CLIPS - every fight on disk is "
                      f"already posted or already queued.")
                failures += 1
                continue
            taken.add(clip.stem)
            when_utc, when_local = slot(day, acct.get("post_time", "10:00"))
            caption = f"{title_of(clip.stem)}\n\n{acct['hashtags']}"
            target = pc.Target(profile=profile, platform=acct["platform"],
                               caption=caption, draft=bool(acct.get("draft", True)))
            payloads = pc.build_requests(clip, [target], caption, 0)
            # The vendor holds it until this instant. Sent as UTC with a Z and no
            # `timezone` field, so there is nothing left for either side to interpret.
            payloads[0]["scheduled_date"] = when_utc
            payloads[0].pop("schedule_offset_minutes", None)
            print()
            print(f"  {when_local:<22} {profile}")
            print(f"      {clip.name}  ({clip.stat().st_size / 1e6:.1f} MB)")
            print(f"      {title_of(clip.stem)}")
            if not args.live:
                # A dry run must still reserve the clip, or every day of the preview
                # would show the same fight and the preview would be a lie.
                ledger["scheduled"].append({"profile": profile, "clip": clip.stem,
                                            "when_utc": when_utc,
                                            "when_local": when_local, "job_id": ""})
                continue
            results: list[dict] = []
            if pc.send(payloads, key, results=results) == 0:
                ledger["scheduled"].append({
                    "profile": profile, "clip": clip.stem, "when_utc": when_utc,
                    "when_local": when_local,
                    "job_id": results[0]["job_id"] if results else ""})
                queued_any = True
            else:
                failures += 1

    if queued_any:
        save_ledger(ledger)

    left = len(clips) - len(spoken_for(ledger))
    if left <= LOW_WATER_DAYS * len(accounts):
        print()
        print(f"  ! {left} clip(s) left unspoken-for - about "
              f"{left // max(len(accounts), 1)} more day(s) of queue. "
              f"Shoot more: python python-tools/make_post.py --a N --b M")

    if not args.live:
        print()
        print("DRY RUN - nothing was queued. Add --live to actually schedule.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
