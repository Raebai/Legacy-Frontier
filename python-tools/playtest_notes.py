"""Read, export and archive the notes the director writes during a playtest.

The director (F2 / F9, or the NOTES tab) appends timestamped, context-stamped
lines to `user://playtest-notes.md` while the game is running. That file lives in
Godot's user-data directory, which is outside the repo — deliberately, so notes
survive a `git clean`, a branch switch and a crash. This script is how they get
back in.

    python python-tools/playtest_notes.py                 # show them
    python python-tools/playtest_notes.py --count         # just how many
    python python-tools/playtest_notes.py --export        # copy into docs/, dated
    python python-tools/playtest_notes.py --export --archive
                                                          # ...and start a fresh page

Why exporting is a separate step rather than the director writing into `docs/`:
a review session is not a commit. Notes are raw, contradictory and often wrong
five minutes later; they become a document when a human decides they have. Until
then they are scratch.

⚠ `--archive` MOVES the live file (it does not delete it) into a timestamped
sibling, so nothing is ever destroyed by a flag. Stdlib only.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from datetime import datetime
from pathlib import Path

# Windows default cp1252 stdout chokes on the em-dashes and flags in the notes.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
DOCS = REPO_ROOT / "docs"
NOTES_NAME = "playtest-notes.md"

# ⚠ Was a hardcoded `PROJECT_NAME = "Legacy Frontier"`, which the rename to Ashpire
# left pointing at a stale directory — so this tool read the notes the maker wrote
# BEFORE the rename and silently ignored every one written since. Derived now.
from godot_paths import user_data_dir  # noqa: E402


def notes_path() -> Path:
    return user_data_dir() / NOTES_NAME


def entry_count(text: str) -> int:
    """Entries, not lines: each note is a `- \\`timestamp\\`` line plus a body line."""
    return sum(1 for line in text.splitlines() if line.startswith("- `"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--export", action="store_true",
                    help="copy the notes into docs/playtest-notes-<date>.md")
    ap.add_argument("--archive", action="store_true",
                    help="after exporting, move the live file aside so the next session starts clean")
    ap.add_argument("--count", action="store_true", help="print the entry count and exit")
    ap.add_argument("--where", action="store_true", help="print the live notes path and exit")
    args = ap.parse_args()

    path = notes_path()
    if args.where:
        print(path)
        return 0
    if not path.exists():
        print(f"no notes yet — nothing at {path}")
        print("The director writes here: F2 (freeze + type) or F9 (flag without stopping).")
        return 1

    text = path.read_text(encoding="utf-8", errors="replace")
    n = entry_count(text)
    if args.count:
        print(n)
        return 0

    if args.export:
        stamp = datetime.now().strftime("%Y-%m-%d")
        out = DOCS / f"playtest-notes-{stamp}.md"
        # Same-day re-export APPENDS rather than overwriting: a review session is
        # usually more than one sitting, and silently replacing the morning's
        # notes with the afternoon's is the one failure this whole system exists
        # to prevent.
        if out.exists():
            prev = out.read_text(encoding="utf-8", errors="replace")
            body = text.split("\n\n", 2)[-1]           # drop the header on the re-export
            out.write_text(prev.rstrip() + "\n\n" + body, encoding="utf-8")
            print(f"appended {n} entr{'y' if n == 1 else 'ies'} to {out}")
        else:
            DOCS.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, out)
            print(f"exported {n} entr{'y' if n == 1 else 'ies'} to {out}")
        if args.archive:
            stampt = datetime.now().strftime("%Y%m%d-%H%M%S")
            moved = path.with_name(f"playtest-notes-{stampt}.md")
            shutil.move(str(path), str(moved))
            print(f"archived the live file to {moved} — the next session starts fresh")
        return 0

    print(f"{path}   ({n} entr{'y' if n == 1 else 'ies'})")
    print("-" * 72)
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
