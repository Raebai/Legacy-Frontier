#!/usr/bin/env python3
"""ONE POST PER ACCOUNT PER DAY — QUEUED AT THE VENDOR, not run from this machine.

    python python-tools/daily_post.py --topup 30          # dry run: fill 30 days
    python python-tools/daily_post.py --topup 30 --live   # actually fill them
    python python-tools/daily_post.py --list              # what the VENDOR is holding
    python python-tools/daily_post.py --verify            # did they actually GO OUT?
    python python-tools/daily_post.py --status            # the local ledger
    python python-tools/daily_post.py --cancel-all --live # unqueue everything

⚠ THE POSTING DOES NOT HAPPEN HERE, AND THAT IS THE POINT. Maker: *"I want it to just
run every single day no need for me to login like thats the whole point of the API
right"*. Right — and a Windows scheduled task was the wrong answer to it. That approach
needed the laptop AWAKE, PLUGGED IN and LOGGED ON at the same minute every day forever,
and failed silently on any morning it was not: one closed lid, one lost day, no error.

`scheduled_date` makes an upload a DEPOSIT instead of a publish. The video and its
caption go to Upload-Post now and their servers publish it on the date given, up to 365
days out. Once a day is queued, this machine is irrelevant to it — off, asleep, logged
out, reinstalled.

⚠ SO ONLY ONE MECHANISM MAY EXIST AT A TIME. A local daily task AND a vendor-side queue
would both fire and post twice. Any scheduled task on this machine must run `--topup`,
which REFILLS a queue, and must never run anything that posts.

── WHY `--topup` REPLACED `--schedule`, AND WHY THAT IS THE RELIABILITY STORY ──────────
`--schedule 7` queued the next seven days unconditionally: run it twice and you got two
posts a day, so it could only be run deliberately, by a human who remembered. That put a
human back in a loop the whole design exists to remove.

`--topup 30` asks the VENDOR what it is already holding and fills only the gaps. It is
idempotent — running it twice in an hour queues nothing the second time — which is what
makes it safe to automate. And because it maintains a THIRTY DAY queue rather than
tomorrow's post, the local task can miss a fortnight of runs without a single missed
post. That inverts the old failure mode: the laptop is no longer a dependency of daily
posting, it is a dependency of daily posting CONTINUING SOME WEEKS FROM NOW.

── ⚠ IT DOES NOT SHOOT ANYTHING, AND THAT IS THE WHOLE DESIGN ──────────────────────────
The obvious build is "render a fresh fight each morning and post it", and it is the
wrong one on this machine for three separate reasons, any one of which is enough:

  * A SHOOT NEEDS A REAL RENDERER. `make_post` runs Godot WITHOUT `--headless`, because
    a null rendering driver produces blank frames that save successfully. So it needs a
    GPU, a session, and the machine awake — at 9am, unattended, every day.
  * A SHOOT REWRITES project.godot. `make_clip._render_size` patches the window override
    and restores it in a `finally`. A crash mid-shoot leaves the maker's project on a
    clip-shaped window, and a shoot that fires while they are playing fights them for it.
  * A SHOOT CAN FAIL THE QUALITY GATE. Roughly one bout in three comes back a
    demolition. An unattended shoot would either post it anyway or post nothing.

So the render stays a deliberate, watched act and this script only ever DELIVERS. When
the pool runs low it says so, loudly, in days of runway rather than in file counts.

── CROSS-PLATFORM IS FREE; CROSS-ACCOUNT IS NOT ────────────────────────────────────────
One account entry now carries a LIST of platforms and they go out in a single upload
call. The duplicate-content pattern that trips spam detection is the same clip on two
accounts of the SAME platform — not one account's Reel also being on its own TikTok,
which is what every creator alive does. So two clips a day covers four accounts.

── ⚠ AND IT ROTATES, BECAUSE A CONSTANT TEACHES NOTHING ────────────────────────────────
Every post used to carry the identical hashtag line at the identical minute, which means
no quantity of analytics could ever say whether either helped: there was no contrast to
measure. `hashtag_variants` and `post_times` are cycled by DAY INDEX — deterministic, so
a re-run picks the same variant, and balanced, so thirty days spreads evenly over three
variants instead of clustering. The variant is written into the ledger at queue time,
which is what lets `insights.py` compare them a month from now.

── AND IT POSTS THE BEDDED FILE, NEVER THE `.nomusic` COMPANION ────────────────────────
The companion exists so a trending sound can be attached by hand in the app — but
Instagram has no draft state, so an automated upload is LIVE the moment it lands and no
hand ever reaches it. Posting the silent cut automatically publishes a silent fight.

THE LEDGER (`content/posted.json`) is what stops a repeat. It records, per account,
which clips have gone out, which are queued, and which variant each got.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))

import publish_clip as pc  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
POSTS = ROOT / "content" / "posts"
LEDGER = ROOT / "content" / "posted.json"
ACCOUNTS_FILE = ROOT / "content" / "daily_accounts.json"
QUEUE_ORDER = ROOT / "content" / "queue_order.json"
WEIGHTS_FILE = ROOT / "content" / "variant_weights.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

## Warn here. Two accounts a day means the pool empties twice as fast as it looks.
LOW_WATER_DAYS = 5
## ⚠ THE CLOCK IS RESOLVED HERE, NOT AT THE VENDOR. The API accepts an IANA `timezone`
## alongside the date, but that leaves the interpretation to somebody else's code on the
## one field where being an hour wrong is visible to an audience. Converting to a
## UTC instant with a `Z` and sending no timezone is unambiguous — and `zoneinfo` gets
## the BST/GMT switch right, which a fixed +1 offset would silently break in October.
POST_TZ = "Europe/London"
## The day counter that drives variant rotation. Fixed, so the rotation is reproducible
## across runs and machines rather than depending on when the tool happens to be run.
ROTATION_EPOCH = date(2026, 1, 1)


def title_of(stem: str) -> str:
    """`warlock_vs_cleric` -> `WARLOCK vs CLERIC`. The caption's whole first line.

    ⚠ SHORT ON PURPOSE. Maker: *"going forward just the hashtags and the title is good
    enough for now"*.

    ⚠ AND IT IS LOAD-BEARING FOR ATTRIBUTION. `insights.clip_stem_of` reads this line
    back to work out which file produced a given number on Instagram. Change the format
    and every per-clip finding silently becomes unattributed — the tool prints an
    `unmatched` count so the breakage surfaces, but the history is still lost.
    """
    parts = stem.split("_vs_")
    if len(parts) == 2:
        return f"{parts[0].upper()} vs {parts[1].upper()}"
    return stem.replace("_", " ").upper()


def day_index(when: date) -> int:
    """Days since the rotation epoch. The index every variant cycle is taken modulo."""
    return (when - ROTATION_EPOCH).days


def pool() -> list[Path]:
    """Every postable clip, in the order the queue should drain.

    `content/queue_order.json` (written by `insights.py --rank`) wins when it exists, so
    what the analytics learned actually reaches the schedule. Anything not named in it
    follows, sorted by NAME — a re-cut bumps a clip's mtime and would otherwise silently
    jump the queue under a schedule that is meant to be predictable.
    """
    clips = sorted(p for p in POSTS.glob("*.mp4")
                   if ".nomusic" not in p.name and ".portrait" not in p.name)
    if not QUEUE_ORDER.exists():
        return clips
    try:
        order = json.loads(QUEUE_ORDER.read_text(encoding="utf-8")).get("order", [])
    except (json.JSONDecodeError, OSError):
        return clips
    rank = {stem: i for i, stem in enumerate(order)}
    return sorted(clips, key=lambda p: (rank.get(p.stem, len(rank)), p.stem))


def load_ledger() -> dict:
    if not LEDGER.exists():
        return {"posted": {}, "scheduled": []}
    try:
        data = json.loads(LEDGER.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        # A corrupt ledger must not be read as "nothing has been posted" — that would
        # repost the whole back catalogue. Refuse instead.
        sys.exit(f"{LEDGER} is unreadable. Fix or delete it deliberately; refusing to "
                 f"treat it as an empty history.")
    data.setdefault("posted", {})
    data.setdefault("scheduled", [])
    return data


def save_ledger(data: dict) -> None:
    """Atomic, so a crash mid-write cannot leave a ledger that reposts everything."""
    tmp = LEDGER.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    tmp.replace(LEDGER)


def load_accounts() -> list[dict]:
    """The rota, normalised so old and new config shapes both read.

    `platform: "instagram"` becomes `platforms: ["instagram"]`; a single `hashtags` line
    becomes a one-entry variant list; a single `post_time` becomes a one-entry time list.
    A one-entry list rotates to itself, so an un-migrated config keeps behaving exactly
    as it did — it just stops teaching anything, which is the status quo anyway.
    """
    if not ACCOUNTS_FILE.exists():
        sys.exit(f"{ACCOUNTS_FILE} is missing. Copy content/daily_accounts.example.json "
                 f"and fill it in.")
    accounts = json.loads(ACCOUNTS_FILE.read_text(encoding="utf-8"))["accounts"]
    for a in accounts:
        a["platforms"] = [str(p).lower() for p in
                          (a.get("platforms") or [a.get("platform")]) if p]
        a["hashtag_variants"] = list(a.get("hashtag_variants")
                                     or ([a["hashtags"]] if a.get("hashtags") else [""]))
        a["post_times"] = list(a.get("post_times")
                               or [a.get("post_time", "10:00")])
        # A second entry for the same profile is a second upload CALL. That is how
        # YouTube gets its own short title and its own 9:16 file without dragging
        # Instagram's and TikTok's captions down to YouTube's 100-character title
        # limit — one call carries one `title`, so the strictest platform in it wins.
        a["same_clip_as"] = a.get("same_clip_as")     # reuse that profile's clip today
        a["clip_suffix"] = a.get("clip_suffix", "")   # e.g. ".portrait"
        a["caption"] = a.get("caption", "full")       # "full" | "title"
    return accounts


def load_weights() -> dict:
    """Per-variant weights written by `insights.py --apply`, or {} if there are none."""
    if not WEIGHTS_FILE.exists():
        return {}
    try:
        return json.loads(WEIGHTS_FILE.read_text(encoding="utf-8")).get("accounts", {})
    except (json.JSONDecodeError, OSError):
        return {}


def weighted_schedule(weights: list[float], length: int = 20) -> list[int]:
    """A deterministic, balanced sequence of variant indices honouring `weights`.

    ⚠ NOT A RANDOM DRAW. A random pick would make a dry run and the live run that
    follows it disagree about what is going out, which would make the preview a lie —
    and over thirty days it would cluster badly enough to confound the very comparison
    the rotation exists to enable. Largest-remainder apportionment gives each variant
    its exact share of the cycle, and the round-robin emission keeps the same variant
    off consecutive days.
    """
    n = len(weights)
    if n <= 1:
        return [0] * length
    raw = [w * length for w in weights]
    counts = [int(x) for x in raw]
    for i in sorted(range(n), key=lambda i: -(raw[i] - counts[i]))[:length - sum(counts)]:
        counts[i] += 1
    seq: list[int] = []
    while len(seq) < length and any(counts):
        for i in range(n):
            if counts[i] > 0:
                seq.append(i)
                counts[i] -= 1
                if len(seq) == length:
                    break
    return seq or [0] * length


def _pick_variant(options: list, weights_by_value: dict, i: int):
    """One option for day `i`, weighted by what the analytics have learned so far.

    Uniform until there is evidence, and never fully exclusive after it — see
    `insights.variant_weights` for how a weight is earned and why it has a floor.
    Unknown values fall back to an equal share, so editing a variant's text resets
    only that variant rather than corrupting the whole schedule.
    """
    if not weights_by_value or len(options) <= 1:
        return options[i % len(options)], i % len(options)
    raw = [max(float(weights_by_value.get(o, 0.0)), 0.0) for o in options]
    total = sum(raw)
    if total <= 0:
        return options[i % len(options)], i % len(options)
    seq = weighted_schedule([r / total for r in raw])
    idx = seq[i % len(seq)]
    return options[idx], idx


def variant_for(acct: dict, when: date, weights: dict | None = None
                ) -> tuple[str, str, int]:
    """(hashtags, HH:MM, hashtag-variant index) for this account on this day.

    ⚠ THE TWO CYCLES ARE DELIBERATELY DIFFERENT LENGTHS in a well-built config (3 tag
    sets against 4 or 5 times). Equal-length cycles stay in lockstep forever, so tag-set
    A is only ever seen at 09:12 and the two effects can never be told apart — a
    confound built at config time that no amount of later analysis can undo.

    ⚠ AND THE WEIGHTS ONLY EVER TILT THE CYCLE, NEVER COLLAPSE IT. The moment a
    schedule stops showing a variant it stops learning about it, and the account is
    locked to whatever was ahead on the day the evidence happened to clear the bar.
    Every variant keeps a floor share for as long as it is in the config.
    """
    i = day_index(when)
    mine = (weights or {}).get(acct["profile"], {})
    tags, tag_idx = _pick_variant(acct["hashtag_variants"],
                                  mine.get("hashtags", {}), i)
    time_s, _ = _pick_variant(acct["post_times"], mine.get("post_times", {}), i)
    return tags, time_s, tag_idx


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


def pick(ledger: dict, taken: set[str]) -> Path | None:
    """The next clip nobody has posted, nobody has queued, and nobody is taking now."""
    used = spoken_for(ledger) | taken
    for clip in pool():
        if clip.stem not in used:
            return clip
    return None


def slot(when: date, hhmm: str) -> tuple[str, str]:
    """(what the vendor is told, what a human reads) for a post on a given local day."""
    hh, mm = (int(x) for x in hhmm.split(":"))
    local = datetime(when.year, when.month, when.day, hh, mm,
                     tzinfo=ZoneInfo(POST_TZ))
    return (local.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            local.strftime("%a %d %b %H:%M %Z"))


def local_date_of(iso_utc: str) -> date | None:
    """The vendor stores what we sent (a UTC instant); a rota is written in local days.

    ⚠ THE CONVERSION HAS TO HAPPEN OR `--topup` DOUBLE-BOOKS. A post queued for 09:00
    London in winter is 09:00Z, and one queued for 09:00 London in summer is 08:00Z —
    compare the vendor's UTC date against a local date and one day in the year reads as
    unfilled when it is not, which posts twice on that day.
    """
    try:
        text = str(iso_utc).replace("Z", "+00:00")
        dt = datetime.fromisoformat(text)
    except (TypeError, ValueError):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(ZoneInfo(POST_TZ)).date()


def vendor_holdings(key: str) -> dict[tuple[str, date], list[dict]]:
    """{(profile, local date): [rows]} for everything the vendor is holding.

    The authoritative answer to "is this day already covered". The local ledger records
    what we ASKED for; this records what they ACCEPTED, and a `--cancel-all` from another
    machine, a vendor-side deletion or a failed queue attempt makes those differ.

    ⚠ A LIST, NOT ONE ROW, and the difference is load-bearing now that a profile can
    have more than one entry a day. The flagship posts once to Instagram and TikTok and
    once more to YouTube; keyed by profile and date alone, queueing either one would
    mark the whole day covered and the other would never go out. `covers()` asks the
    narrower question the schedule actually needs answered.
    """
    out: dict[tuple[str, date], list[dict]] = {}
    for row in pc.list_scheduled(key):
        day = local_date_of(row.get("scheduled_date"))
        profile = str(row.get("profile_username") or "")
        if day and profile:
            out.setdefault((profile, day), []).append(row)
    return out


def covers(rows: list[dict], wanted: list[str]) -> bool:
    """Is every platform this entry wants already queued for that profile that day?"""
    got: set[str] = set()
    for row in rows or []:
        got |= {str(p).lower() for p in (row.get("platforms") or [])}
    return bool(wanted) and set(wanted) <= got


def linked_platforms(key: str) -> dict[str, set[str]]:
    """{profile: {platform, ...}} for everything actually connected right now."""
    data = pc.fetch_profiles(key) or {}
    return {str(p.get("username", "")):
            {name for name, info in (p.get("social_accounts") or {}).items() if info}
            for p in data.get("profiles", []) or []}


def reconcile(ledger: dict, key: str, verbose: bool = True) -> int:
    """Move fired posts from `scheduled` to `posted`, and free the ones that failed.

    ⚠ NOTHING USED TO DO THIS, and the omission compounds quietly. A queued row stayed
    in `scheduled` forever, so `--status` showed posts as pending weeks after they went
    out, and a FAILED post kept its clip marked as spoken-for — permanently retiring a
    fight that was never actually published. Reconciling on every run keeps the ledger a
    description of reality rather than of intent.
    """
    still_held = {str(r.get("job_id")) for r in pc.list_scheduled(key)}
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    kept, moved, freed = [], 0, 0
    for row in ledger.get("scheduled", []):
        job = str(row.get("job_id") or "")
        if not job or job in still_held or row["when_utc"] > now:
            kept.append(row)                       # not due, or still queued
            continue
        state = str(pc.job_status(job, key).get("status", "?"))
        if state in ("completed", "success", "done"):
            ledger["posted"].setdefault(row["profile"], {})[row["clip"]] = \
                row["when_utc"]
            moved += 1
        elif state in ("failed", "not_found", "cancelled"):
            # Freed: the clip goes back in the pool so a failure costs a day, not a fight.
            freed += 1
            if verbose:
                print(f"  ! {row['when_local']} {row['profile']} {row['clip']}: "
                      f"{state} — the clip is back in the pool")
        else:
            kept.append(row)                       # still processing; ask again later
    ledger["scheduled"] = kept
    if moved or freed:
        # ⚠ SAVED EVEN UNDER A DRY RUN, and that is not a violation of the dry-run
        # contract. `--live` gates what leaves this machine; reconciling changes nothing
        # out there, it just stops the ledger claiming a post is still pending three
        # weeks after it went out. Left unsaved, a dry run would rediscover and reprint
        # the same six every time and `--status` would never catch up.
        save_ledger(ledger)
        if verbose:
            print(f"  reconciled: {moved} published, {freed} failed and freed")
    return freed


def runway(accounts: list[dict], ledger: dict) -> tuple[int, float]:
    """(clips not spoken for, days of posting those cover)."""
    left = len(pool()) - len(spoken_for(ledger))
    per_day = max(len(accounts), 1)
    return left, left / per_day


def cmd_topup(days: int, accounts: list[dict], ledger: dict, key: str,
              live: bool) -> int:
    """Fill every unqueued day in the next `days`, and nothing else.

    Idempotent by construction: it queues against the gaps in the VENDOR's holdings, so
    a second run within the hour finds no gaps and sends nothing. That property is the
    entire reason this is safe to put on a timer.
    """
    reconcile(ledger, key)
    held = vendor_holdings(key)
    today = datetime.now(ZoneInfo(POST_TZ)).date()

    # ⚠ A CONFIGURED PLATFORM THAT IS NOT LINKED FAILS THE WHOLE UPLOAD, not just its
    # own destination — one call carries every platform for that profile, so naming an
    # unconnected TikTok would also stop the Instagram post that shares the call. So the
    # config is intersected with what is actually connected RIGHT NOW. That is what lets
    # `tiktok` sit in the config before the account exists: the day it is connected, the
    # next top-up starts including it with no edit here.
    linked = linked_platforms(key)
    for acct in accounts:
        wanted = acct["platforms"]
        have = [p for p in wanted if p in linked.get(acct["profile"], set())]
        missing = [p for p in wanted if p not in have]
        if missing:
            print(f"  note: {acct['profile']} has no {', '.join(missing)} connected — "
                  f"skipping {'it' if len(missing) == 1 else 'them'} for now")
        acct["platforms"] = have
    accounts = [a for a in accounts if a["platforms"]]
    if not accounts:
        print("\n  Nothing to post to: no configured platform is actually connected.")
        print("  Link an account at upload-post.com, then re-run.")
        return 1

    weights = load_weights()
    if weights:
        print(f"  using learned variant weights from "
              f"{WEIGHTS_FILE.relative_to(ROOT)}")

    # A second entry for the same profile is a second upload CALL, which is how
    # YouTube gets its own short title and its own 9:16 file without dragging
    # Instagram's and TikTok's captions down to YouTube's 100-character title limit
    # (one call carries one `title`, so the strictest platform in it wins).
    #
    # An entry with `same_clip_as` REUSES the clip that profile already took today
    # rather than consuming another. Leaders are processed first because a follower
    # cannot resolve until its leader has picked.
    leaders = [a for a in accounts if not a.get("same_clip_as")]
    followers = [a for a in accounts if a.get("same_clip_as")]

    queued = failures = skipped = 0
    for offset in range(1, days + 1):
        when = today + timedelta(days=offset)
        taken: set[str] = set()
        chosen_today: dict[str, Path] = {}
        for acct in leaders + followers:
            profile = acct["profile"]
            if covers(held.get((profile, when), []), acct["platforms"]):
                skipped += 1
                continue
            if acct.get("same_clip_as"):
                clip = chosen_today.get(acct["same_clip_as"])
                if clip is None:
                    # Leader skipped or ran dry. A rider with nothing to ride is not
                    # a failure, it is simply nothing to do.
                    continue
            else:
                clip = pick(ledger, taken)
            if clip is None:
                print(f"\n  {when} {profile}: OUT OF CLIPS — everything on disk is "
                      f"already posted or already queued.")
                failures += 1
                continue
            if not acct.get("same_clip_as"):
                taken.add(clip.stem)
                chosen_today[profile] = clip

            # A suffixed variant (the 9:16 cut) must EXIST or the entry sits this day
            # out. Sending the landscape file to YouTube would publish a normal video
            # rather than a Short, which reads as a mistake and is worse than posting
            # nothing there.
            send_clip = clip
            if acct.get("clip_suffix"):
                send_clip = clip.with_name(clip.stem + acct["clip_suffix"] + ".mp4")
                if not send_clip.exists():
                    print(f"\n  {when} {profile}: no {send_clip.name} yet - skipping. "
                          f"Build them with python python-tools/make_portrait.py")
                    continue

            tags, hhmm, vidx = variant_for(acct, when, weights)
            when_utc, when_local = slot(when, hhmm)
            # NO NEWLINE IN A "title" CAPTION: it becomes YouTube's video TITLE,
            # and a title is one line. The two-line shape that suits Instagram
            # arrives there mangled or truncated.
            caption = (title_of(clip.stem) + acct.get("title_suffix", "")
                       if acct.get("caption") == "title"
                       else f"{title_of(clip.stem)}\n\n{tags}".strip())
            clip = send_clip
            # Per-platform tuning the vendor accepts but does not default well:
            # YouTube's categoryId is "22" (People & Blogs) unless told otherwise, and
            # its description defaults to the title, wasting the one field on that
            # platform that can carry a link anywhere.
            target = pc.Target(profile=profile, platforms=acct["platforms"],
                               caption=caption, draft=bool(acct.get("draft", False)),
                               extra=dict(acct.get("extra") or {}))
            payloads = pc.build_requests(clip, [target], caption, 0)
            payloads[0]["scheduled_date"] = when_utc
            payloads[0].pop("schedule_offset_minutes", None)

            print(f"\n  {when_local:<22} {profile}  "
                  f"[{', '.join(acct['platforms'])}]")
            print(f"      {clip.name}  ({clip.stat().st_size / 1e6:.1f} MB)")
            print(f"      {caption.splitlines()[0]}")
            if tags:
                print(f"      variant #{vidx % len(acct['hashtag_variants'])}: {tags}")

            row = {"profile": profile, "clip": clip.stem,
                   "platforms": acct["platforms"], "when_utc": when_utc,
                   "when_local": when_local, "job_id": "",
                   "hashtags": tags, "post_time": hhmm}
            if not live:
                # A dry run must still reserve the clip in memory, or every day of the
                # preview would show the same fight and the preview would be a lie.
                ledger["scheduled"].append(row)
                queued += 1
                continue
            results: list[dict] = []
            if pc.send(payloads, key, results=results) == 0:
                row["job_id"] = results[0]["job_id"] if results else ""
                ledger["scheduled"].append(row)
                queued += 1
            else:
                failures += 1

    if live:
        save_ledger(ledger)

    left, days_left = runway(accounts, ledger)
    print()
    print(f"  {skipped} day(s) already covered, {queued} newly queued, "
          f"{failures} failed")
    print(f"  {left} clip(s) unspoken-for = {days_left:.1f} day(s) of runway")
    if days_left < LOW_WATER_DAYS:
        need = days * len(accounts) - len(pool()) + len(spoken_for(ledger))
        print(f"\n  ⚠ SHOOT MORE. Covering {days} days on {len(accounts)} account(s) "
              f"needs about {max(need, 0)} more clip(s).")
        print(f"    python python-tools/make_post.py --a <class> --b <class> --takes 3")
    if not live:
        print("\n  DRY RUN — nothing was queued. Add --live.")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--topup", type=int, metavar="DAYS",
                    help="ensure the vendor holds a post for every day in the next N; "
                         "idempotent, so it is the one safe to automate")
    ap.add_argument("--schedule", type=int, metavar="DAYS",
                    help="deprecated alias for --topup (it used to queue "
                         "unconditionally, which double-posted on a second run)")
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
    clips = pool()

    if args.status:
        used = spoken_for(ledger)
        left, days_left = runway(accounts, ledger)
        print()
        print(f"{len(clips)} clip(s) on disk, {left} unspoken-for "
              f"({days_left:.1f} days of runway)")
        print()
        for a in accounts:
            done = ledger["posted"].get(a["profile"], {})
            queued = [r for r in ledger["scheduled"] if r["profile"] == a["profile"]]
            print(f"  {a['profile']:<20} [{', '.join(a['platforms'])}]   "
                  f"posted {len(done):>2}   queued {len(queued):>2}")
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
                  f"{','.join(r.get('platforms') or []):<20} "
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
            print(f"  {r['when_local']:<22} {r['profile']:<20} {state:<12}{flag}")
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

    days = args.topup or args.schedule
    if not days:
        print("Nothing asked for. Try --topup 30, --status, --list or --verify.")
        return 1
    if args.schedule and not args.topup:
        print("  note: --schedule now behaves as --topup (it fills gaps rather than "
              "queueing unconditionally, so a repeat run cannot double-post).")
    return cmd_topup(days, accounts, ledger, key, args.live)


if __name__ == "__main__":
    raise SystemExit(main())
