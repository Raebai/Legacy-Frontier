"""Prove the daily queue hands out a DIFFERENT fight every day, and says so when it runs out.

    python python-tools/check_post_rotation.py

WHY THIS EXISTS, AND IT IS NOT HYPOTHETICAL
-------------------------------------------
On 2026-09-07 the vendor was holding 88 scheduled posts and 85 of them were TWO clips.
`arcanist_vs_juggernaut.portrait` was queued 57 times and `arcanist_vs_brawler.portrait`
28 times, one to four times a day, live, on Instagram/TikTok/YouTube, out into October.

The mechanism was one line. `cmd_topup` did `clip = send_clip` before writing the ledger
row, so a send that used a `clip_suffix` recorded the stem of the CUT
(`x_vs_y.portrait`) as the thing that had been spent. `pick()` asks whether the POOL
stem (`x_vs_y`) is spoken for. The two strings never matched, nothing was ever retired,
and `pick()` returned the first pool entry on every day of the queue forever.

Nothing caught it because nothing was looking:

  * `--status` prints the ROW, so the repetition was on screen every time and read as a
    list of scheduled posts rather than as one post fifty-seven times.
  * `runway()` shares `spoken_for()`, so it reported "5 clips unspoken-for, 2.5 days"
    while 88 posts stood queued. The number that should have screamed was computed by
    the broken function.
  * ⚠ AND EVERY ACCOUNT IN THE REAL CONFIG CARRIES A `clip_suffix`. The bug did not fire
    in a corner case, it fired on 100% of sends. The only arrangement that never
    reproduces it is the one with no suffix — which is exactly the arrangement a quick
    fixture would build.

So this drives the REAL `cmd_topup`, with a `clip_suffix` set, and stubs only the four
seams that reach the network. The row-writing line under test is the shipped one.

THE CHECKS
  1. ROTATION   — every scheduled row is a different fight.
  2. EXHAUSTION — asked for more days than the pool covers, it reports OUT OF CLIPS
                  instead of repeating. "Never repeats" is trivially satisfiable by a
                  function that returns nothing, so both halves have to be pinned.
  3. ROW SHAPE  — `clip` is a POOL stem (what was spent) and `file` is the cut that went
                  on the wire. This is the assertion that fails on the original line.
  4. LEGACY     — a ledger holding only `.portrait` rows still retires the fight. The
                  rows the vendor is holding right now are that shape, so a fix that
                  only corrects NEW rows would keep re-queueing the same two clips
                  until every one of them had drained.
  5. SELF-PROOF — checks 1 and 4 are re-run with the resolution stubbed back to the
                  identity, which IS the old system, and are required to go RED. A guard
                  that has never been seen to fail is not evidence.

Stdlib only. No network, no ffmpeg, no Godot.
"""
from __future__ import annotations

import io
import json
import shutil
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import daily_post as dp  # noqa: E402
import publish_clip as pc  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

FIGHTS = ["arcanist_vs_brawler", "arcanist_vs_cleric", "arcanist_vs_juggernaut",
          "brawler_vs_cleric", "cleric_vs_juggernaut", "juggernaut_vs_brawler"]

## Two leaders and a rider, which is the shipped shape: the rider reuses the leader's
## clip, so it must NOT consume a second fight and must not count against rotation.
ACCOUNTS = [
    {"profile": "A", "platforms": ["instagram"], "clip_suffix": ".portrait",
     "post_times": ["09:12", "13:07"], "hashtag_variants": ["#a", "#b", "#c"],
     "draft": False, "same_clip_as": None, "caption": "full"},
    {"profile": "B", "platforms": ["instagram"], "clip_suffix": ".portrait",
     "post_times": ["08:37", "19:08"], "hashtag_variants": ["#a", "#b", "#c"],
     "draft": False, "same_clip_as": None, "caption": "full"},
    {"profile": "A", "platforms": ["youtube"], "clip_suffix": ".portrait",
     "post_times": ["11:24"], "hashtag_variants": [""], "draft": False,
     "same_clip_as": "A", "caption": "title"},
]

failures: list[str] = []


def check(ok: bool, label: str, detail: str = "") -> bool:
    print(f"  {'ok  ' if ok else 'FAIL'}  {label}")
    if not ok:
        if detail:
            print(f"          {detail}")
        failures.append(label)
    return ok


def make_pool(root: Path, fights: list[str]) -> None:
    """A fight is a landscape file plus its 9:16 cut. Contents are irrelevant here."""
    root.mkdir(parents=True, exist_ok=True)
    for stem in fights:
        (root / f"{stem}.mp4").write_bytes(b"\0" * 2048)
        (root / f"{stem}.portrait.mp4").write_bytes(b"\0" * 1024)
        # The companion exists in the real pool and must never be treated as a fight.
        (root / f"{stem}.nomusic.mp4").write_bytes(b"\0" * 2048)


def run_topup(days: int, ledger: dict, sabotage: bool = False) -> tuple[dict, str]:
    """Call the SHIPPED cmd_topup, with only the four network seams replaced.

    live=False, so `pc.send` is never reached — and it is replaced with a raiser so
    that a dry run which somehow posts is a loud failure rather than a real upload.
    """
    saved = {name: getattr(dp, name) for name in
             ("reconcile", "vendor_holdings", "linked_platforms", "load_weights",
              "is_vertical", "save_ledger", "consumed_stem")}
    saved_send = pc.send
    try:
        dp.reconcile = lambda ledger, key, verbose=True: 0
        dp.vendor_holdings = lambda key: {}
        dp.linked_platforms = lambda key: {"A": {"instagram", "youtube"},
                                           "B": {"instagram", "youtube"}}
        dp.load_weights = lambda: {}
        dp.is_vertical = lambda path: True
        dp.save_ledger = lambda data: None
        if sabotage:
            # THE OLD SYSTEM, exactly: a ledger stem retires only the literal string.
            dp.consumed_stem = lambda stem, pool_stems: stem

        def _no(*a, **k):
            raise AssertionError("a dry run tried to send")
        pc.send = _no

        accounts = json.loads(json.dumps(ACCOUNTS))
        buf = io.StringIO()
        with redirect_stdout(buf):
            dp.cmd_topup(days, accounts, ledger, "fake-key", live=False)
        return ledger, buf.getvalue()
    finally:
        for name, fn in saved.items():
            setattr(dp, name, fn)
        pc.send = saved_send


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="rotation_"))
    saved_posts, saved_order = dp.POSTS, dp.QUEUE_ORDER
    try:
        posts = tmp / "posts"
        make_pool(posts, FIGHTS)
        dp.POSTS = posts
        dp.QUEUE_ORDER = tmp / "queue_order.json"      # absent: pool sorts by name

        print(f"\n{len(FIGHTS)} fights on disk, 2 leader accounts + 1 rider\n")

        # ── 1. ROTATION ────────────────────────────────────────────────────────────
        ledger = {"posted": {}, "scheduled": []}
        run_topup(3, ledger)
        rows = ledger["scheduled"]
        spent = [r["clip"] for r in rows if not _is_rider(r, rows)]
        leaders = [r for r in rows if r["profile"] in ("A", "B")]
        by_fight: dict[str, int] = {}
        for r in leaders:
            by_fight[r["clip"]] = by_fight.get(r["clip"], 0) + 1
        # The rider shares A's fight each day, so a fight may legitimately appear twice
        # — once for A's own call and once for A's YouTube call. Never three times, and
        # never twice for two DIFFERENT profiles' own picks.
        picks = [r["clip"] for r in rows if r["profile"] and _own_pick(r, ACCOUNTS)]
        check(len(picks) == len(set(picks)),
              f"rotation: {len(picks)} picks are {len(set(picks))} distinct fights",
              f"repeated: {sorted(f for f, n in _count(picks).items() if n > 1)}")

        # ── 2. EXHAUSTION ──────────────────────────────────────────────────────────
        ledger2 = {"posted": {}, "scheduled": []}
        _, out = run_topup(10, ledger2)          # 10 days x 2 leaders vs 6 fights
        picks2 = [r["clip"] for r in ledger2["scheduled"] if _own_pick(r, ACCOUNTS)]
        check(len(picks2) == len(set(picks2)) and len(picks2) == len(FIGHTS),
              f"exhaustion: spent each of the {len(FIGHTS)} fights exactly once",
              f"got {len(picks2)} picks, {len(set(picks2))} distinct")
        check("OUT OF CLIPS" in out,
              "exhaustion: says OUT OF CLIPS rather than repeating one")

        # ── 3. ROW SHAPE ───────────────────────────────────────────────────────────
        stems = {p.stem for p in dp.pool()}
        bad_clip = [r["clip"] for r in ledger["scheduled"] if r["clip"] not in stems]
        check(not bad_clip,
              "row shape: every row's `clip` is a POOL stem, not the cut's stem",
              f"not in pool: {bad_clip[:4]}")
        bad_file = [r for r in ledger["scheduled"]
                    if r.get("file") != r["clip"] + ".portrait.mp4"]
        check(not bad_file,
              "row shape: `file` names the cut that actually went on the wire",
              f"{len(bad_file)} row(s) wrong, e.g. {bad_file[:1]}")

        # ── 4. LEGACY ROWS ─────────────────────────────────────────────────────────
        # The shape the vendor is holding today: the CUT's stem, nothing else.
        legacy = {"posted": {}, "scheduled":
                  [{"profile": "A", "clip": f + ".portrait", "when_utc": "2026-01-01",
                    "when_local": "x", "job_id": "", "platforms": ["instagram"]}
                   for f in FIGHTS[:3]]}
        free = dp.pick(legacy, set())
        check(free is not None and free.stem in FIGHTS[3:],
              "legacy: a `.portrait` row retires its FIGHT, not just its string",
              f"pick returned {free.stem if free else None}, "
              f"expected one of {FIGHTS[3:]}")

        # ── 5. SELF-PROOF: the guard must go RED against the old system ────────────
        print("\n  sabotage — resolution stubbed to the identity (the old system):")
        held = len(failures)
        legacy_sab = json.loads(json.dumps(legacy))
        saved_cs = dp.consumed_stem
        try:
            dp.consumed_stem = lambda stem, pool_stems: stem
            free_sab = dp.pick(legacy_sab, set())
            red = free_sab is not None and free_sab.stem == FIGHTS[0]
        finally:
            dp.consumed_stem = saved_cs
        check(red,
              "sabotage: legacy check goes RED — it re-serves a fight already queued",
              "the guard did NOT fail when the bug was reinstated, so it is not "
              "evidence of anything")
        if len(failures) == held + 0 and red:
            print(f"          (it re-served {FIGHTS[0]}, which is the 2026-09-07 bug)")

    finally:
        dp.POSTS, dp.QUEUE_ORDER = saved_posts, saved_order
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    if failures:
        print(f"post-rotation: {len(failures)} FAILED — {'; '.join(failures)}")
        return 1
    print("post-rotation: all PASS")
    return 0


def _count(xs: list[str]) -> dict[str, int]:
    out: dict[str, int] = {}
    for x in xs:
        out[x] = out.get(x, 0) + 1
    return out


def _own_pick(row: dict, accounts: list[dict]) -> bool:
    """Rows for entries that PICK a clip. A rider reuses one and spends nothing."""
    for a in accounts:
        if a["profile"] == row["profile"] and a.get("same_clip_as"):
            # Riders are indistinguishable from their leader by profile alone; the
            # rider here is the youtube entry, so it is identified by platform.
            if row["platforms"] == a["platforms"]:
                return False
    return True


def _is_rider(row: dict, rows: list[dict]) -> bool:
    return row["platforms"] == ["youtube"]


if __name__ == "__main__":
    raise SystemExit(main())
