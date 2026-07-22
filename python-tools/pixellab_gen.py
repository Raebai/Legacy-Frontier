#!/usr/bin/env python3
"""PixelLab pixel-art generation pipeline for Legacy Frontier.

Generates a single pixel-art PNG from a text description via the PixelLab v2 API
(`/create-image-pixflux`, synchronous) and saves it under art-source/generated/.
Stdlib-only (urllib/json/base64) so there's no new dependency, matching the other
python-tools generators.

FREE-TIER BUDGET: the trial gives a fixed number of GENERATIONS (not USD). This
tool prints the remaining generations after every call so we spend deliberately —
one image per invocation, on purpose. Check the budget any time without spending:

    python python-tools/pixellab_gen.py --balance

Generate one sprite (transparent background by default — good for game overlays):

    python python-tools/pixellab_gen.py "a wise old chronicler in a blue robe holding a glowing tome, warm, front-facing portrait" --name raebai --size 128

The API key is read from the gitignored .env (PIXELLAB_API_KEY=...) or the env var.
Never commit the key.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

API_BASE = "https://api.pixellab.ai/v2"
REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "art-source" / "generated"
ENV_PATH = REPO_ROOT / ".env"


def _load_key() -> str:
    key = os.environ.get("PIXELLAB_API_KEY", "").strip()
    if not key and ENV_PATH.exists():
        for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("PIXELLAB_API_KEY="):
                key = line.split("=", 1)[1].strip()
                break
    if not key:
        sys.exit("ERROR: PIXELLAB_API_KEY not set (add it to .env or the environment).")
    return key


def _request(method: str, path: str, key: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(f"{API_BASE}{path}", data=data, method=method)
    req.add_header("Authorization", f"Bearer {key}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        sys.exit(f"ERROR: PixelLab {method} {path} -> HTTP {exc.code}: {detail}")
    except urllib.error.URLError as exc:
        sys.exit(f"ERROR: could not reach PixelLab ({exc.reason}).")


def _remaining_gens(key: str) -> str:
    bal = _request("GET", "/balance", key)
    sub = bal.get("subscription", {}) or {}
    gens = sub.get("generations")
    usd = (bal.get("credits", {}) or {}).get("usd", 0.0)
    if gens is not None:
        return f"{gens:g} trial generations remaining (usd ${usd:g})"
    return f"usd ${usd:g}"


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate a pixel-art sprite via PixelLab.")
    ap.add_argument("description", nargs="?", help="text prompt for the sprite")
    ap.add_argument("--name", default="sprite", help="output filename stem (art-source/generated/<name>.png)")
    ap.add_argument("--size", type=int, default=128, help="square size in px (32..400; area <= 400x400)")
    ap.add_argument("--width", type=int, help="override width (else --size)")
    ap.add_argument("--height", type=int, help="override height (else --size)")
    ap.add_argument("--bg", action="store_true", help="keep a background (default: transparent, no_background=true)")
    ap.add_argument("--palette", help="optional palette hint")
    ap.add_argument("--balance", action="store_true", help="just print the remaining budget and exit (free, no spend)")
    args = ap.parse_args()

    key = _load_key()

    if args.balance:
        print(f"[pixellab] {_remaining_gens(key)}")
        return

    if not args.description:
        ap.error("a description is required (or use --balance)")

    w = args.width or args.size
    h = args.height or args.size
    body: dict = {
        "description": args.description,
        "image_size": {"width": w, "height": h},
        "no_background": not args.bg,
    }
    if args.palette:
        body["palette"] = args.palette

    print(f"[pixellab] before: {_remaining_gens(key)}")
    print(f"[pixellab] generating '{args.name}' ({w}x{h}): {args.description!r}")
    result = _request("POST", "/create-image-pixflux", key, body)

    b64 = (result.get("image", {}) or {}).get("base64")
    if not b64:
        sys.exit(f"ERROR: no image in response: {json.dumps(result)[:400]}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{args.name}.png"
    out.write_bytes(base64.b64decode(b64))
    print(f"[pixellab] saved {out} ({out.stat().st_size} bytes)")
    print(f"[pixellab] after:  {_remaining_gens(key)}")


if __name__ == "__main__":
    main()
