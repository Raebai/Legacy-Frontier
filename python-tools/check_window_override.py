#!/usr/bin/env python3
"""Assert the COMMITTED window override is the authored one, not a render resolution.

    python python-tools/check_window_override.py

⚠ WHY THIS EXISTS. `make_clip.render_size_override` edits
`window/size/window_width_override` / `_height_override` in project.godot to the capture
resolution for the duration of a shoot and restores them on exit. So any `git add -A`
while a shoot is running commits **1920x1080 as the real window size**. This has now
happened three times: once as commit 65df4cc ("put the window override back to
1366x768"), and twice more in one evening.

And it PROPAGATES rather than merely sitting there. The batch scripts run
`git checkout godot-project/project.godot` between pairs to undo a killed shoot — which
restores the bad value *from HEAD* — and the next shoot then overrides from, and
restores to, 1920x1080. After that the maker opens the game at the render resolution and
nothing anywhere says why.

It is invisible in review (two digits in a generated-looking config file), it survives
every test (the suites run headless and never read the override), and the working tree
looks clean because the shoot restored the file. Exactly the profile of a bug that keeps
coming back, so it gets a check rather than another comment.

Deliberately NOT part of `run_all_tests.py`: this is repo hygiene, not a game
assertion, and it should be runnable in a fraction of a second before a push.

Exit 0 if the committed values are correct, 1 otherwise.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRACKED = "godot-project/project.godot"

# The authored desktop window. If the maker deliberately changes this, change it here in
# the same commit — that is the point of pinning it.
EXPECT = {"window_width_override": 1366, "window_height_override": 768}


def committed_text() -> str:
    """Read the file as HEAD has it, not as the working tree has it — a live shoot owns
    the working copy, and the working copy is not what ships."""
    out = subprocess.run(
        ["git", "show", f"HEAD:{TRACKED}"],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if out.returncode != 0:
        print(f"! could not read HEAD:{TRACKED}\n{out.stderr.strip()}")
        raise SystemExit(2)
    return out.stdout


def main() -> int:
    text = committed_text()
    bad = []
    for key, want in EXPECT.items():
        m = re.search(rf"^window/size/{key}\s*=\s*(\d+)", text, re.MULTILINE)
        if m is None:
            bad.append(f"{key}: MISSING from the committed project.godot")
            continue
        got = int(m.group(1))
        if got != want:
            bad.append(f"{key}: committed {got}, expected {want}")
    if bad:
        print("WINDOW OVERRIDE CHECK: FAIL")
        for line in bad:
            print(f"  {line}")
        print("\nA clip shoot rewrites these and restores them on exit, so this almost")
        print("certainly means something ran `git add -A` while a shoot was live.")
        print("Fix without touching the working tree (a shoot may still own it):")
        print("  blob=$(git show <good-commit>:godot-project/project.godot | "
              "git hash-object -w --stdin)")
        print(f"  git update-index --cacheinfo 100644,$blob,{TRACKED}")
        return 1
    print(f"WINDOW OVERRIDE CHECK: ok ({EXPECT['window_width_override']}x"
          f"{EXPECT['window_height_override']} committed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
