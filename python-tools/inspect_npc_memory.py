"""Audit NPC conversation transcripts and persisted memory state.

Reads the v0.5 four-layer memory shape (long_term_summary, short_term,
relationships, stats) from Godot's user-data directory and pretty-prints it
for voice-drift / consolidation / verification analysis.

Usage:
    python python-tools/inspect_npc_memory.py                # list available NPCs
    python python-tools/inspect_npc_memory.py raebai         # full transcript + shape
    python python-tools/inspect_npc_memory.py mirelle --shape  # shape only, skip transcript
    python python-tools/inspect_npc_memory.py --all          # transcripts for every NPC

Cross-platform: resolves Godot's user-data path per OS. Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


# Windows default cp1252 stdout chokes on em-dash / arrow markers. Force UTF-8
# unconditionally — harmless on macOS/Linux where the default is already utf-8.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


PROJECT_NAME = "Legacy Frontier"


def memory_dir() -> Path:
    """Resolve the npc_memory directory in the platform-specific user-data root."""
    if sys.platform == "win32":
        return Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / PROJECT_NAME / "npc_memory"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / PROJECT_NAME / "npc_memory"
    # Linux / other Unix
    return Path.home() / ".local" / "share" / "godot" / "app_userdata" / PROJECT_NAME / "npc_memory"


def list_saves(d: Path) -> list[Path]:
    """List <npc_id>.json saves in d, excluding backup (.bak.json) and tmp files."""
    return sorted(
        p for p in d.iterdir()
        if p.suffix == ".json"
        and not p.name.endswith(".bak.json")
        and not p.name.endswith(".tmp")
    )


def load_save(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def show_shape(npc_id: str, data: dict) -> None:
    print(f"=== {npc_id} ===")
    print(f"  version:           {data.get('version')}")
    short_term = data.get("short_term", [])
    print(f"  short_term:        {len(short_term)} messages")
    long_term = data.get("long_term_summary", "")
    if long_term:
        excerpt = long_term[:80] + ("..." if len(long_term) > 80 else "")
        print(f"  long_term_summary: {len(long_term)} chars — \"{excerpt}\"")
    else:
        print(f"  long_term_summary: (empty — populated by M10 consolidation)")
    rels = data.get("relationships", {})
    if rels:
        print(f"  relationships:")
        for entity, rel in rels.items():
            facts = rel.get("key_facts", [])
            inbox = rel.get("gossip_inbox", [])
            print(f"    {entity}: valence={rel.get('valence')}, "
                  f"key_facts={facts}, gossip_inbox={len(inbox)} item(s)")
    else:
        print(f"  relationships:     (empty)")
    stats = data.get("stats", {})
    print(f"  stats:             {stats}")


def show_transcript(data: dict) -> None:
    short_term = data.get("short_term", [])
    if not short_term:
        print()
        print("  (no transcript — short_term is empty)")
        return
    print()
    print(f"--- Transcript ({len(short_term)} turns) ---")
    for i, m in enumerate(short_term):
        role = m.get("role", "?")
        content = m.get("content", "")
        marker = "→" if role == "user" else "←"
        # Wrap long lines at column 80 for terminal readability, indent
        # continuation lines under the content column.
        prefix = f"  {i:>3} {marker} [{role:>9}]"
        wrap_indent = " " * len(prefix)
        words = content.split(" ")
        line = ""
        first = True
        for w in words:
            if len(line) + len(w) + 1 > 78:
                print(f"{prefix if first else wrap_indent} {line}")
                line = w
                first = False
            else:
                line = w if not line else line + " " + w
        if line:
            print(f"{prefix if first else wrap_indent} {line}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit NPC conversation transcripts and persisted memory state.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="See python-tools/inspect_npc_memory.py docstring for examples.",
    )
    parser.add_argument(
        "npc_id",
        nargs="?",
        help="NPC id (e.g. raebai, mirelle). Omit to list available NPCs.",
    )
    parser.add_argument(
        "--shape",
        action="store_true",
        help="Show layered shape only, skip transcript.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Show shape + transcript for every NPC. Overrides npc_id.",
    )
    parser.add_argument(
        "--memory-dir",
        help="Override the default user-data memory directory (e.g. for testing).",
    )
    args = parser.parse_args()

    d = Path(args.memory_dir) if args.memory_dir else memory_dir()
    if not d.exists():
        print(f"Memory dir not found: {d}", file=sys.stderr)
        return 1

    saves = list_saves(d)
    if not saves:
        print(f"No NPC saves in {d}")
        return 0

    if args.all:
        for p in saves:
            data = load_save(p)
            show_shape(p.stem, data)
            if not args.shape:
                show_transcript(data)
            print()
        return 0

    if args.npc_id is None:
        print(f"Available NPCs in {d}:")
        for p in saves:
            data = load_save(p)
            print(f"  {p.stem}  (v{data.get('version', '?')}, "
                  f"{len(data.get('short_term', []))} turns, "
                  f"{len(data.get('long_term_summary', ''))} chars long_term)")
        print()
        print(f"Run with an npc_id (e.g. `python {Path(sys.argv[0]).name} raebai`) "
              f"to see a full transcript.")
        return 0

    target = d / f"{args.npc_id}.json"
    if not target.exists():
        print(f"No save for npc_id '{args.npc_id}' at {target}", file=sys.stderr)
        print(f"Available: {[p.stem for p in saves]}", file=sys.stderr)
        return 1

    data = load_save(target)
    show_shape(args.npc_id, data)
    if not args.shape:
        show_transcript(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
