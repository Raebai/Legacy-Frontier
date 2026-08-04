#!/usr/bin/env python3
"""Where Godot keeps this project's `user://`, derived rather than hardcoded.

⚠ THIS FILE EXISTS BECAUSE A HARDCODED NAME SILENTLY BROKE THE CLIP PIPELINE.

Godot derives `user://` from `application/config/name` in project.godot. When the
game was renamed "Legacy Frontier" -> "Ashpire", the *engine* immediately started
writing to a new directory while four Python tools kept the old name as a
constant. The failure mode is the nastiest kind this project keeps meeting:

    make_clip.py  ->  Godot writes frames to   .../Ashpire/clips/directed
                  ->  the encoder reads        .../Legacy Frontier/clips/directed

Both directories EXIST (the rename migration copied the old one across) and both
contain a folder of that name, so the encoder found frames, encoded them, printed
a size and a success line — and produced a video of a fight that happened before
the rename. A stale clip is indistinguishable from a fresh one at a glance, so
this could have gone unnoticed for as long as nobody counted the frames.

The rename note in docs/NEXT-SESSION.md says plainly: "If the name is ever
changed again, this happens again. There is no code migration." This is that
code. One parse of project.godot, and the tools follow the engine wherever it
goes.

Stdlib only, on purpose — every consumer of this is a stdlib(+Pillow) tool and
none of them should grow a dependency to find a folder.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GODOT_PROJECT = REPO_ROOT / "godot-project"

# Only used if project.godot cannot be read at all. Deliberately the CURRENT name:
# a fallback that is silently wrong is what this module exists to prevent, so if
# this ever fires it should at least fire toward the truth as of writing.
_FALLBACK_NAME = "Ashpire"

_NAME_RE = re.compile(r'^\s*config/name\s*=\s*"([^"]*)"', re.MULTILINE)


def project_name(project_dir: Path | None = None) -> str:
    """Read `application/config/name` out of project.godot.

    Godot sanitises this into a directory name, but only for characters that are
    illegal in a path; ordinary names (including ones with spaces, as "Legacy
    Frontier" was) are used verbatim, which is why a plain read is correct here.
    """
    root = project_dir if project_dir is not None else GODOT_PROJECT
    cfg = root / "project.godot"
    try:
        text = cfg.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return _FALLBACK_NAME
    m = _NAME_RE.search(text)
    if m is None or not m.group(1).strip():
        return _FALLBACK_NAME
    return m.group(1)


def user_data_dir(project_dir: Path | None = None) -> Path:
    """The platform's `user://` for this project, on the engine's own rules."""
    name = project_name(project_dir)
    if sys.platform == "win32":
        return Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / name
    if sys.platform == "darwin":
        return (Path.home() / "Library" / "Application Support" / "Godot"
                / "app_userdata" / name)
    return Path.home() / ".local" / "share" / "godot" / "app_userdata" / name


if __name__ == "__main__":
    print(f"project name : {project_name()}")
    d = user_data_dir()
    print(f"user:// dir  : {d}")
    print(f"exists       : {d.is_dir()}")
