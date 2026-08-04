"""Find and run the visual capture tools in godot-project/tools/.

There are ~65 of them. They render frames to PNG so a human can LOOK at a thing
that no assertion can settle — does the Tier 3 crown read at arm's length, does
the clash spark where the blades meet, does the boss silhouette survive at
640x360. They are the only instrument in this repo that answers a question about
how the game LOOKS.

Nobody could find them, and each one needed a slightly different incantation
remembered correctly, including one that is easy to get wrong in a way that
silently produces blank images. So:

    python python-tools/run_capture.py --list             # every tool + what it shows
    python python-tools/run_capture.py --list boss        # filtered
    python python-tools/run_capture.py director           # run one (substring match)
    python python-tools/run_capture.py clash --open       # run one, then open the folder
    python python-tools/run_capture.py --where            # where the PNGs land
    python python-tools/run_capture.py --write-index      # regenerate docs/capture-tools.md

⚠ THE TRAP THIS SCRIPT EXISTS TO REMOVE. Capture tools need the **GUI** binary.
Under `--headless` Godot uses the DUMMY renderer: every tool runs, every tool
reports success, and every PNG it writes is empty. That failure looks exactly
like a pass. This script always picks the GUI binary, and refuses to be talked
out of it.

The second trap: some tools are `SceneTree` scripts run with `--script`, and
some are `.tscn` scenes run as a positional argument — because a `--script` run
DOES NOT REGISTER AUTOLOADS, so anything that needs a real `GameState` or `Sfx`
has to be a scene. The right form is parsed out of each tool's own header.

Stdlib only.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# Windows default cp1252 stdout chokes on the em-dashes these headers are full of.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
GODOT_PROJECT = REPO_ROOT / "godot-project"
TOOLS_DIR = GODOT_PROJECT / "tools"
INDEX_DOC = REPO_ROOT / "docs" / "capture-tools.md"

# ⚠ Was a hardcoded `PROJECT_NAME = "Legacy Frontier"`, which the rename to Ashpire
# left pointing at a directory the engine had stopped writing to. Every "PNGs land
# in ..." line this tool printed named the wrong folder. Derived now.
from godot_paths import user_data_dir  # noqa: E402

# ── Which binary ────────────────────────────────────────────────────────────
# The GUI build, NOT the `_console` one used by run_all_tests.py. The console
# build is a headless-friendly variant; captures want a real window and a real
# renderer.
GUI_BINARY = REPO_ROOT / "godot-engine" / "Godot_v4.6.2-stable_win64.exe"

# ── Which files are capture tools ───────────────────────────────────────────
# `*_capture.gd` is the dominant convention (65 files). A handful of visual
# tools predate it; they are named explicitly rather than by widening the regex,
# so a future `*_capture.gd` cannot be missed and a future test suite cannot be
# swept in.
CAPTURE_RE = re.compile(r"capture$", re.IGNORECASE)
EXTRA_CAPTURES = [
    "class_spell_demo",
    "debris_demo",
    "floor_sim",
    "bot_clip_capture",
]
# Never a capture, whatever it is called.
NEVER = re.compile(r"(?:^|_)test_|^_|_probe(_stub)?$|_check$")

SCENE_RE = re.compile(r"(res://tools/[\w/]+\.tscn)")




class Tool:
    def __init__(self, path: Path, summary: str, scene: str | None):
        self.path = path
        self.name = path.stem
        self.summary = summary
        self.scene = scene

    @property
    def rel(self) -> str:
        """Path as Godot wants it for `--script`: relative to the project root.

        NOT `path.name` — some tools live in a sub-directory (`tools/director/`)
        and a flattened name resolves to nothing, which Godot reports as an empty
        run rather than as an error.
        """
        return self.path.relative_to(GODOT_PROJECT).as_posix()

    @property
    def how(self) -> str:
        return f"scene {self.scene}" if self.scene else f"--script {self.rel}"

    def argv(self) -> list[str]:
        base = [str(GUI_BINARY), "--path", str(GODOT_PROJECT)]
        if self.scene:
            return base + [self.scene]
        return base + ["--script", self.rel]


def header_lines(text: str) -> list[str]:
    """The leading comment block: everything before the first line of real code."""
    out: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("#"):
            out.append(line.lstrip("#").strip())
            continue
        if line == "":
            if out:
                continue
            continue
        break
    return out


def summarise(text: str) -> str:
    """One line saying what the tool SHOWS.

    Prefers the first prose line of the header comment. Skips the `Run:` recipe
    and the rule lines around it, which are the same in every file and therefore
    say nothing about which tool this is.
    """
    for line in header_lines(text):
        if not line:
            continue
        low = line.lower()
        if low.startswith(("run:", "godot", "output", "usage:", "run with", "run this")):
            continue
        if "gui binary" in low or "--headless" in low or "res://tools/" in low:
            continue
        if set(line) <= set("=-─ "):
            continue
        if "godot_v4" in low or low.startswith("--"):
            continue
        return line
    # Fall back to the first `##` doc comment on the class.
    m = re.search(r"^##\s*(.+)$", text, re.MULTILINE)
    return m.group(1).strip() if m else "(no description in the file header)"


def find_scene(text: str, path: Path) -> str | None:
    """The `.tscn` this tool is run as, if it is a scene rather than a script.

    Read out of the header's own recipe first (the file is the authority on how
    to run itself). Falls back to a same-stem `.tscn` beside it, then to None,
    which means `--script`.
    """
    m = SCENE_RE.search(text)
    if m:
        return m.group(1)
    for cand in (path.with_suffix(".tscn"), path.parent / (_pascal(path.stem) + ".tscn")):
        if cand.exists():
            return "res://" + cand.relative_to(GODOT_PROJECT).as_posix()
    return None


def _pascal(snake: str) -> str:
    return "".join(p.title() for p in snake.split("_"))


def discover() -> list[Tool]:
    tools: list[Tool] = []
    for path in sorted(TOOLS_DIR.rglob("*.gd")):
        stem = path.stem
        if NEVER.search(stem):
            continue
        if not (CAPTURE_RE.search(stem) or stem in EXTRA_CAPTURES):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        tools.append(Tool(path, summarise(text), find_scene(text, path)))
    return tools


def cmd_list(tools: list[Tool], needle: str | None) -> int:
    sel = [t for t in tools if not needle or needle.lower() in t.name.lower()]
    if not sel:
        print(f"no capture tool matches {needle!r}")
        return 1
    width = max(len(t.name) for t in sel)
    for t in sel:
        print(f"  {t.name:<{width}}  {t.summary}")
    print(f"\n{len(sel)} of {len(tools)} capture tools.  PNGs land in:\n  {user_data_dir()}")
    return 0


def cmd_run(tools: list[Tool], needle: str, timeout: int, open_after: bool) -> int:
    matches = [t for t in tools if needle.lower() in t.name.lower()]
    if not matches:
        print(f"no capture tool matches {needle!r} — try --list")
        return 1
    if len(matches) > 1:
        exact = [t for t in matches if t.name == needle]
        if len(exact) != 1:
            print(f"{needle!r} matches {len(matches)}: {', '.join(t.name for t in matches)}")
            return 1
        matches = exact
    tool = matches[0]
    if not GUI_BINARY.exists():
        print(f"error: GUI binary not found at {GUI_BINARY}")
        print("Captures CANNOT use the console/headless build — it renders nothing.")
        return 2

    out_root = user_data_dir()
    started = time.time()
    print(f"running {tool.name}  ({tool.how})")
    try:
        proc = subprocess.run(tool.argv(), capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"TIMEOUT after {timeout}s — some capture tools wait on frames; try --timeout")
        return 3

    for line in (proc.stdout or "").splitlines():
        if "saved" in line.lower() or line.startswith("["):
            print("  " + line)
    err = [l for l in (proc.stderr or "").splitlines()
           if "SCRIPT ERROR" in l or "Parse Error" in l]
    for line in err:
        print("  ! " + line)

    fresh = sorted(
        (p for p in out_root.rglob("*.png") if p.stat().st_mtime >= started - 1),
        key=lambda p: p.stat().st_mtime,
    )
    if fresh:
        print(f"\n{len(fresh)} frame(s) written:")
        for p in fresh:
            print(f"  {p}")
    else:
        print("\nNO FRAMES WRITTEN. Either the tool draws nothing, or it was run with the")
        print("wrong binary. This script uses the GUI build; a headless run is always blank.")
    if open_after and fresh and sys.platform == "win32":
        os.startfile(fresh[0].parent)  # noqa: S606
    return 0 if proc.returncode == 0 else 4


def cmd_write_index(tools: list[Tool]) -> int:
    lines = [
        "# The capture tools — an index",
        "",
        "**Generated. Do not hand-edit — run `python python-tools/run_capture.py",
        "--write-index` instead.** The summaries below are each tool's own first",
        "header line, so a tool that describes itself badly here describes itself",
        "badly in its own file, which is where to fix it.",
        "",
        "These are the only instrument in this repo that answers a question about how",
        "the game LOOKS. Everything else asserts about state.",
        "",
        "## How to run one",
        "",
        "```",
        "python python-tools/run_capture.py --list          # everything, with descriptions",
        "python python-tools/run_capture.py boss            # run it (substring match)",
        "python python-tools/run_capture.py boss --open     # ...and open the output folder",
        "```",
        "",
        "⚠ **They need the GUI binary, never `--headless`.** Headless uses the dummy",
        "renderer: every tool runs, every tool reports success, and every PNG is blank.",
        "The runner always picks the GUI build so this cannot happen by accident.",
        "",
        f"Frames land in `{user_data_dir()}`.",
        "",
        "## The tools",
        "",
        "| tool | shows | run as |",
        "|---|---|---|",
    ]
    for t in tools:
        how = "scene" if t.scene else "script"
        summary = t.summary.replace("|", "\\|")
        lines.append(f"| `{t.name}` | {summary} | {how} |")
    lines.append("")
    lines.append(f"_{len(tools)} tools._")
    lines.append("")
    INDEX_DOC.parent.mkdir(parents=True, exist_ok=True)
    INDEX_DOC.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {INDEX_DOC}  ({len(tools)} tools)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tool", nargs="?", help="substring of a capture tool name to run")
    ap.add_argument("--list", nargs="?", const="", metavar="FILTER",
                    help="list capture tools (optionally filtered) and exit")
    ap.add_argument("--where", action="store_true", help="print the output directory and exit")
    ap.add_argument("--write-index", action="store_true",
                    help="regenerate docs/capture-tools.md from the tools themselves")
    ap.add_argument("--open", action="store_true", help="open the output folder afterwards")
    ap.add_argument("--timeout", type=int, default=300)
    args = ap.parse_args()

    if args.where:
        print(user_data_dir())
        return 0
    tools = discover()
    if args.write_index:
        return cmd_write_index(tools)
    if args.list is not None:
        return cmd_list(tools, args.list or None)
    if not args.tool:
        return cmd_list(tools, None)
    return cmd_run(tools, args.tool, args.timeout, args.open)


if __name__ == "__main__":
    raise SystemExit(main())
