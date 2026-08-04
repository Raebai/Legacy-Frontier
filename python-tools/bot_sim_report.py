#!/usr/bin/env python3
"""Aggregate many `tools/bot_sim.gd` runs into the three questions worth asking.

    python python-tools/bot_sim_report.py [runs_dir] [--logs LOGDIR] [--top 15]

`runs_dir` defaults to Godot's user data, whose leaf is the project's
`config/name` and is therefore DERIVED, not spelled here — see godot_paths.py:
    %APPDATA%/Godot/app_userdata/<config/name>/bot_sim

It answers:
  1. WHICH PAIRING BREAKS MOST — anomalies grouped by class matchup, so a class
     that only misbehaves against one opponent is distinguishable from one that
     misbehaves against everybody.
  2. WHICH SPELL NEVER FIRES — every kit slot that was asked for with the gate
     open and did not come out, summed across runs. Reachability is the bug class
     that hides best: an unequippable spell looks exactly like a spell the bot
     chose not to use.
  3. WHICH ANOMALY IS MOST COMMON — the ranked kind table.

Plus a fourth the simulation itself cannot see: ENGINE ERRORS. A GDScript runtime
error prints to stderr and does not raise, so a run can be full of them and still
report a clean sweep. `--logs` points at a directory of captured run output; the
BEGIN/END markers `bot_sim.gd` prints let each error be attributed to the pairing
that was on screen when it fired.

Every row carries the seed it came from, because an anomaly you cannot replay is
a rumour rather than a bug report.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

# ⚠ Was hardcoded to "Legacy Frontier", which the rename to Ashpire left pointing at
# a directory the engine no longer writes — so this report ranked PRE-RENAME runs
# while looking exactly like a fresh one. Derived from project.godot now.
from godot_paths import user_data_dir  # noqa: E402

DEFAULT_RUNS = user_data_dir() / "bot_sim"

BEGIN_RE = re.compile(r"\[sim\] BEGIN match=(\d+) pairing=(\S+) seed=(\d+)")
ERROR_RE = re.compile(r"^(?:SCRIPT ERROR|ERROR|USER SCRIPT ERROR):\s*(.+)$")
AT_RE = re.compile(r"^\s+at: (.+)$")


def load_runs(folder: Path) -> list[dict]:
    runs = []
    for p in sorted(folder.glob("*.json")):
        try:
            runs.append({"path": p, **json.loads(p.read_text(encoding="utf-8"))})
        except (json.JSONDecodeError, OSError) as exc:
            print(f"  ! skipped {p.name}: {exc}")
    return runs


def scan_logs(folder: Path) -> tuple[Counter, dict[str, Counter]]:
    """Engine errors, and which pairing was live when each fired.

    The sim prints `[sim] BEGIN ... pairing=X` before every match, so walking a
    log top to bottom and remembering the last BEGIN attributes each error line
    to a matchup. Errors before the first BEGIN are filed under `setup`.
    """
    totals: Counter = Counter()
    by_pairing: dict[str, Counter] = defaultdict(Counter)
    for p in sorted(folder.glob("*")):
        if p.is_dir():
            continue
        pairing = "setup"
        pending: str | None = None
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            m = BEGIN_RE.search(line)
            if m:
                pairing = m.group(2)
                continue
            e = ERROR_RE.match(line)
            if e:
                pending = e.group(1).strip()
                continue
            a = AT_RE.match(line)
            if a and pending:
                # `message @ site` is the useful unit — the same message from two
                # call sites is two bugs, and collapsing them hides one.
                key = f"{pending}  @ {a.group(1).strip()}"
                totals[key] += 1
                by_pairing[pairing][key] += 1
                pending = None
    return totals, by_pairing


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs_dir", nargs="?", default=str(DEFAULT_RUNS))
    ap.add_argument("--logs", default=None, help="directory of captured run stdout/stderr")
    ap.add_argument("--top", type=int, default=15)
    args = ap.parse_args()

    folder = Path(args.runs_dir)
    if not folder.is_dir():
        raise SystemExit(f"no such directory: {folder}")
    runs = load_runs(folder)
    if not runs:
        raise SystemExit(f"no run JSON in {folder}")

    kinds: Counter = Counter()
    by_pairing: Counter = Counter()
    pairing_kinds: dict[str, Counter] = defaultdict(Counter)
    never_fired: dict[tuple[str, str], dict] = {}
    seeds: set[int] = set()
    matches = 0
    damage_zero = 0

    for run in runs:
        seeds.add(int(run.get("seed", 0)))
        matches += len(run.get("matches", []))
        for m in run.get("matches", []):
            if int(m.get("total_damage", 0)) <= 0:
                damage_zero += 1
        for a in run.get("anomalies", []):
            kind = a.get("kind", "?")
            pairing = a.get("pairing", "?")
            kinds[kind] += 1
            by_pairing[pairing] += 1
            pairing_kinds[pairing][kind] += 1
            if kind == "spell_never_fired":
                ctx = a.get("context", {})
                key = (str(ctx.get("class", "?")), str(ctx.get("spell", "?")))
                row = never_fired.setdefault(
                    key, {"attempts": 0, "fires": 0, "seeds": set(),
                          "blockers": set(), "slot_maps": set()})
                row["attempts"] += int(ctx.get("attempts", 0))
                row["fires"] += int(ctx.get("fires", 0))
                row["seeds"].add(int(a.get("seed", 0)))
                for b in ctx.get("blockers", []) or []:
                    row["blockers"].add(str(b))
                row["slot_maps"].add(str(ctx.get("slot_map", "?")))

    print("=" * 74)
    print(f"BOT SIM AGGREGATE — {len(runs)} run(s), {matches} match(es), "
          f"seeds {sorted(seeds)}")
    print("=" * 74)

    print(f"\n[1] WHICH PAIRING BREAKS MOST  (top {args.top})")
    if not by_pairing:
        print("    (no anomalies recorded)")
    for pairing, n in by_pairing.most_common(args.top):
        worst = ", ".join(f"{k}x{v}" for k, v in pairing_kinds[pairing].most_common(3))
        print(f"    {n:4d}  {pairing:<34} {worst}")

    print("\n[2] WHICH SPELL NEVER FIRES")
    if not never_fired:
        print("    (none — every asked-for slot came out at least once)")
    for (cls, spell), row in sorted(never_fired.items(),
                                    key=lambda kv: -kv[1]["attempts"]):
        why = ", ".join(sorted(row["blockers"])) or "no blocking state"
        print(f"    {cls:<12} {spell:<20} asked {row['attempts']:4d}  fired "
              f"{row['fires']:3d}   [{why}]")
        print(f"                 slotmap={'/'.join(sorted(row['slot_maps']))}  "
              f"repro seeds: {sorted(row['seeds'])}")

    print(f"\n[3] WHICH ANOMALY IS MOST COMMON  (top {args.top})")
    for kind, n in kinds.most_common(args.top):
        print(f"    {n:4d}  {kind}")
    print(f"\n    matches ending with ZERO damage exchanged: {damage_zero}/{matches}")

    if args.logs:
        logs = Path(args.logs)
        if logs.is_dir():
            totals, per_pairing = scan_logs(logs)
            print(f"\n[4] ENGINE ERRORS IN RUN OUTPUT  (top {args.top})")
            if not totals:
                print("    (none)")
            for msg, n in totals.most_common(args.top):
                where = [p for p, c in per_pairing.items() if msg in c]
                print(f"    {n:4d}  {msg}")
                print(f"          seen in: {', '.join(sorted(where)[:4])}")
        else:
            print(f"\n[4] ENGINE ERRORS — no such log directory: {logs}")

    print("\nReplay any finding:")
    for s in sorted(seeds):
        print(f"    ... --script tools/bot_sim.gd -- --seed={s} --mode=duel")


if __name__ == "__main__":
    main()
