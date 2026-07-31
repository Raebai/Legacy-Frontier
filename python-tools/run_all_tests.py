"""Run every headless GDScript test suite in godot-project/tools/ and summarise.

Each suite is a standalone `SceneTree` script invoked as its own Godot process:

    godot --headless --path godot-project --script tools/<suite>.gd

There is no built-in harness, so this script is it: discover the suites, run the
one-off `--import` that Godot needs after any new `class_name` (a recurring trap
in this repo), fan the suites out across worker processes, and parse the repo's
own pass/fail convention out of their output.

The convention (see tools/slice_test_loadout.gd and tools/slice_test_climb.gd):
  * green  -> stdout gets `<Name> tests: all PASS`
  * red    -> stderr gets `FAIL: <message>` lines, then `<Name> tests: N FAILED`
A suite that prints NEITHER line is treated as a FAILURE, not a pass. It almost
certainly crashed, aborted, or never reached its summary — and this repo has a
history of suites silently passing while testing nothing, so silence is guilty.

Usage:
    python python-tools/run_all_tests.py                  # run everything
    python python-tools/run_all_tests.py --list           # show what would run
    python python-tools/run_all_tests.py --filter climb   # substring match on name
    python python-tools/run_all_tests.py --jobs 4 --timeout 90
    python python-tools/run_all_tests.py --verbose        # full output of failures

Exit code is 0 only when every selected suite passed. Stdlib only.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


# Windows default cp1252 stdout chokes on em-dash / arrow markers. Force UTF-8
# unconditionally — harmless on macOS/Linux where the default is already utf-8.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


REPO_ROOT = Path(__file__).resolve().parent.parent
GODOT_PROJECT = REPO_ROOT / "godot-project"
TOOLS_DIR = GODOT_PROJECT / "tools"

DEFAULT_GODOT = REPO_ROOT / "godot-engine" / "Godot_v4.6.2-stable_win64_console.exe"


# ── Which .gd files in tools/ are test suites ────────────────────────────────
#
# tools/ mixes test suites with screenshot capture scripts, probes, sims and
# one-off checks. The rule below is deliberately narrow and easy to amend:
# a file is a suite iff its basename contains a `test_` segment, i.e. it either
# starts with `test_` or has `_test_` in it. That covers every convention in use
# (`slice1_test_*`, `slice_test_*`, `spike_test_*`, `m9_test_*`, `test_*`) and
# admits none of the capture/probe tooling.
#
# If a future suite is named outside that shape, widen INCLUDE_RE rather than
# special-casing it at the call site.
INCLUDE_RE = re.compile(r"(?:^|_)test_")

# Belt-and-braces: even if INCLUDE_RE is widened later, anything matching these
# is non-test tooling and must never be run as a suite. Matched against the
# basename (without extension).
EXCLUDE_RES = [
    re.compile(r"_capture$"),      # screenshot / clip capture scripts
    re.compile(r"^bot_sim"),       # bot simulation driver
    re.compile(r"_probe(_stub)?$"),  # interactive probes
    re.compile(r"_check$"),        # ad-hoc one-off checks
    re.compile(r"^screenshot$"),
    re.compile(r"^sim_"),          # sim_arena / sim_controller
    re.compile(r"^_"),             # private helpers, e.g. _netprobe
]

# The repo's own summary-line convention: `<label>: all PASS` on stdout, or
# `FAIL: <msg>` lines followed by `<label>: N FAILED` on stderr.
#
# Most suites label themselves "<Name> tests:" (e.g. `Climb spine tests: all PASS`)
# but a few use their bare filename (`slice6_test_circle_handoff: all PASS`), and
# one appends a count (`Gear tests: all PASS (7 pieces)`). Matching on the colon
# rather than the word "tests" covers all three shapes.
PASS_RE = re.compile(r"^.*:\s*all PASS\b.*$", re.MULTILINE)
FAIL_SUMMARY_RE = re.compile(r"^.*:\s*\d+\s+FAILED\b.*$", re.MULTILINE)
FAIL_LINE_RE = re.compile(r"^.*\bFAIL:\s.*$", re.MULTILINE)


PASSED = "PASS"
FAILED = "FAIL"
TIMEOUT = "TIMEOUT"
NO_RESULT = "NO-RESULT"


@dataclass
class Result:
    name: str
    status: str
    seconds: float
    exit_code: int | None
    summary: str          # the suite's own pass/fail line, when it printed one
    fail_lines: list[str]
    output: str           # merged stdout+stderr, kept for --verbose


def find_godot() -> Path:
    """Locate the Godot binary: $GODOT wins, else the vendored engine."""
    env = os.environ.get("GODOT")
    if env:
        p = Path(env)
        if not p.exists():
            sys.exit(f"error: $GODOT points at a missing file: {p}")
        return p
    if DEFAULT_GODOT.exists():
        return DEFAULT_GODOT
    # Fall back to any vendored console build, so a version bump doesn't break us.
    engine_dir = REPO_ROOT / "godot-engine"
    if engine_dir.is_dir():
        for cand in sorted(engine_dir.glob("Godot_v*_console.exe")):
            return cand
        for cand in sorted(engine_dir.glob("Godot_v*")):
            if cand.is_file() and cand.suffix in (".exe", ""):
                return cand
    sys.exit(
        f"error: could not find the Godot binary.\n"
        f"  looked for: {DEFAULT_GODOT}\n"
        f"  set the GODOT env var to override."
    )


def discover(filter_sub: str | None) -> list[str]:
    """Return sorted suite basenames (no extension) under tools/."""
    if not TOOLS_DIR.is_dir():
        sys.exit(f"error: tools directory not found: {TOOLS_DIR}")
    names: list[str] = []
    for path in sorted(TOOLS_DIR.glob("*.gd")):
        stem = path.stem
        if not INCLUDE_RE.search(stem):
            continue
        if any(rx.search(stem) for rx in EXCLUDE_RES):
            continue
        if filter_sub and filter_sub.lower() not in stem.lower():
            continue
        names.append(stem)
    return names


def run_import(godot: Path, verbose: bool) -> None:
    """One-off filesystem import. Required after any new `class_name` lands."""
    print("→ importing project (once) ...", flush=True)
    started = time.monotonic()
    proc = subprocess.run(
        [str(godot), "--headless", "--path", str(GODOT_PROJECT), "--import"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=600,
    )
    took = time.monotonic() - started
    print(f"  import finished in {took:.1f}s (exit {proc.returncode})", flush=True)
    if verbose and proc.returncode != 0:
        print(proc.stdout)
        print(proc.stderr)


def run_suite(godot: Path, name: str, timeout: int) -> Result:
    cmd = [
        str(godot),
        "--headless",
        "--path",
        str(GODOT_PROJECT),
        "--script",
        f"tools/{name}.gd",
    ]
    started = time.monotonic()
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or "") + (exc.stderr or "")
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
        return Result(name, TIMEOUT, time.monotonic() - started, None,
                      f"timed out after {timeout}s", [], out)
    took = time.monotonic() - started
    output = (proc.stdout or "") + "\n" + (proc.stderr or "")

    pass_hit = PASS_RE.search(output)
    fail_hit = FAIL_SUMMARY_RE.search(output)
    fail_lines = [ln.strip() for ln in FAIL_LINE_RE.findall(output)]

    if fail_hit:
        status, summary = FAILED, fail_hit.group(0).strip()
    elif pass_hit:
        status, summary = PASSED, pass_hit.group(0).strip()
    else:
        # No summary line at all — crashed, aborted, or never reached the end.
        # Guilty until proven innocent: this repo has had suites pass vacuously.
        status = NO_RESULT
        summary = "no pass/fail line printed (crashed or aborted?)"
    return Result(name, status, took, proc.returncode, summary, fail_lines, output)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Run all headless Godot test suites in godot-project/tools/.",
    )
    ap.add_argument("--filter", metavar="SUBSTRING",
                    help="only run suites whose name contains this substring")
    ap.add_argument("--jobs", "-j", type=int, default=0,
                    help="parallel workers (default: min(8, cpu_count))")
    ap.add_argument("--timeout", type=int, default=120,
                    help="per-suite timeout in seconds (default: 120)")
    ap.add_argument("--verbose", "-v", action="store_true",
                    help="print full captured output for every non-passing suite")
    ap.add_argument("--list", action="store_true",
                    help="list the suites that would run, then exit")
    ap.add_argument("--no-import", action="store_true",
                    help="skip the one-off --import step")
    args = ap.parse_args()

    suites = discover(args.filter)
    if not suites:
        print("no test suites matched.")
        return 1

    if args.list:
        for s in suites:
            print(s)
        print(f"\n{len(suites)} suite(s).")
        return 0

    godot = find_godot()
    jobs = args.jobs if args.jobs > 0 else min(8, os.cpu_count() or 4)

    print(f"godot:  {godot}")
    print(f"suites: {len(suites)}   jobs: {jobs}   timeout: {args.timeout}s")

    if not args.no_import:
        run_import(godot, args.verbose)

    wall_start = time.monotonic()
    results: list[Result] = []
    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = {pool.submit(run_suite, godot, s, args.timeout): s for s in suites}
        for fut in concurrent.futures.as_completed(futures):
            res = fut.result()
            results.append(res)
            done += 1
            mark = {PASSED: "ok  ", FAILED: "FAIL", TIMEOUT: "TIME", NO_RESULT: "????"}[res.status]
            print(f"[{done:3}/{len(suites)}] {mark} {res.name}  ({res.seconds:.1f}s)", flush=True)

    wall = time.monotonic() - wall_start
    results.sort(key=lambda r: r.name)

    passed = [r for r in results if r.status == PASSED]
    failed = [r for r in results if r.status == FAILED]
    timed_out = [r for r in results if r.status == TIMEOUT]
    no_result = [r for r in results if r.status == NO_RESULT]
    bad = failed + timed_out + no_result

    print("\n" + "=" * 72)
    print(f"suites: {len(results)}   passed: {len(passed)}   failed: {len(failed)}"
          f"   timed out: {len(timed_out)}   no-result: {len(no_result)}")
    print(f"wall time: {wall:.1f}s")
    print("=" * 72)

    if bad:
        print("\nNOT PASSING:")
        for r in bad:
            print(f"\n  {r.status}  {r.name}   ({r.seconds:.1f}s, exit {r.exit_code})")
            print(f"    {r.summary}")
            for line in r.fail_lines[:20]:
                print(f"    {line}")
            if len(r.fail_lines) > 20:
                print(f"    ... and {len(r.fail_lines) - 20} more FAIL line(s)")
            if args.verbose:
                print("    ---- captured output ----")
                for line in r.output.splitlines():
                    print(f"    | {line}")
        print()
        return 1

    print("\nall suites PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
