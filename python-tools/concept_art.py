#!/usr/bin/env python3
"""Concept-art generation for the heavy-fantasy project.

Generates a concept render from a text description via Replicate's HTTP API and
saves it under art-source/concepts/. Stdlib-only (urllib/json) so there's no new
dependency, matching the other python-tools generators.

WHY REPLICATE: pay-per-image (flux-schnell is ~$0.003 a render) rather than a
monthly subscription, and one well-documented endpoint. Swap the model with
--model if a better one lands; nothing else in here is model-specific.

THE HOUSE STYLE is a single locked suffix (STYLE) appended to every prompt. That
is the point of this tool: every render comes out of the same visual language, so
a batch reads as one world rather than four unrelated pictures. Edit STYLE in one
place and the whole look moves together.

Get a key at replicate.com/account/api-tokens, then put it in the gitignored .env:

    REPLICATE_API_TOKEN=r8_...

List the named shots without spending anything:

    python python-tools/concept_art.py --list

Render one of them:

    python python-tools/concept_art.py arrival

Render something new:

    python python-tools/concept_art.py --prompt "a drowned city seen through clear water from above" --name mirrored-lake

See the exact prompt that would be sent, without spending:

    python python-tools/concept_art.py valley --dry-run
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

API_ROOT = "https://api.replicate.com/v1"
DEFAULT_MODEL = "black-forest-labs/flux-schnell"
OUT_DIR = pathlib.Path("art-source/concepts")
POLL_SECONDS = 2
POLL_LIMIT = 90

# The locked visual language. Every prompt gets this appended.
STYLE = (
    "stylised anime fantasy game art, low-poly readable shapes, bold flat colour, "
    "strong silhouettes, one committed colour per scene, soft volumetric light, "
    "Ghibli warmth with Elden Ring scale, no text, no watermark, no UI"
)

# Named shots from the design document. Keep these in sync with the doc.
SHOTS = {
    "arrival": (
        "First-person view from a narrow rocky ledge high on a mountain at dawn, "
        "clouds forming BELOW the viewer, a vast valley far beneath filled with pink "
        "cherry blossom, a single impossibly tall ancient stone tower carved with "
        "glowing runes rising from the centre of that valley in the far distance, "
        "warm golden light, cinematic wide shot"
    ),
    "valley": (
        "A wide valley entirely filled with cherry blossom trees in full bloom, petals "
        "drifting through the air, a river winding through with petals on the water, a "
        "small village of wooden rooftops, an enormous ancient rune-carved stone spire "
        "rising from the village centre into the clouds, golden hour, saturated pink "
        "and warm gold palette"
    ),
    "crater": (
        "A small fresh impact crater in a field of pink blossom and long grass, petals "
        "settling into it, a figure in a modern grey hoodie standing up out of it, dust "
        "still hanging in the air, warm morning light, low angle"
    ),
    "cathedral": (
        "Interior of an ancient frozen observatory at the peak of an icy spire, enormous "
        "brass instruments still slowly turning, a hole in the domed roof showing an "
        "impossibly dense aurora and rearranging stars, blue-white and green palette, "
        "vast age and cold, tiny human figure for scale"
    ),
    "ashwood": (
        "An ancient forest at dusk with trees far too tall and too old, eternal twilight "
        "beneath the canopy, mushrooms and moss and bark glowing blue-green, a stone "
        "temple swallowed by enormous roots, shafts of dim light, deep teal palette"
    ),
    "void": (
        "A cracked wasteland where reality has fractured, dark rifts hanging in the air "
        "showing glimpses of somewhere else through them, impossible stars visible "
        "through the daytime sky, gravity visibly wrong in patches, desaturated with "
        "violent violet accents"
    ),
}


def load_token() -> str:
    """Read the token from the environment, falling back to the gitignored .env."""
    token = os.environ.get("REPLICATE_API_TOKEN", "").strip()
    if token:
        return token

    env_path = pathlib.Path(".env")
    if env_path.is_file():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("REPLICATE_API_TOKEN="):
                return line.split("=", 1)[1].strip().strip("'\"")

    sys.exit(
        "No REPLICATE_API_TOKEN found.\n"
        "  1. Get one at https://replicate.com/account/api-tokens\n"
        "  2. Add REPLICATE_API_TOKEN=r8_... to the gitignored .env\n"
        "Never commit the key."
    )


def post(url: str, token: str, body: dict, wait: bool) -> dict:
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    if wait:
        # Ask Replicate to hold the connection open until the render finishes.
        headers["Prefer"] = "wait"
    req = urllib.request.Request(
        url, data=json.dumps(body).encode("utf-8"), headers=headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def get(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def first_image_url(output) -> str | None:
    """Replicate returns either a URL string or a list of them, model depending."""
    if isinstance(output, str):
        return output
    if isinstance(output, list) and output:
        return output[0] if isinstance(output[0], str) else None
    return None


def render(prompt: str, name: str, model: str, aspect: str, token: str) -> pathlib.Path:
    url = f"{API_ROOT}/models/{model}/predictions"
    body = {"input": {"prompt": prompt, "aspect_ratio": aspect, "output_format": "png"}}

    try:
        result = post(url, token, body, wait=True)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:400]
        sys.exit(f"Replicate returned HTTP {exc.code}: {detail}")

    # `Prefer: wait` usually returns a finished prediction, but it can time out and
    # hand back a still-running one. Poll in that case rather than failing.
    polls = 0
    while result.get("status") in ("starting", "processing"):
        if polls >= POLL_LIMIT:
            sys.exit(f"Still running after {POLL_LIMIT * POLL_SECONDS}s. Prediction id: {result.get('id')}")
        time.sleep(POLL_SECONDS)
        polls += 1
        result = get(result["urls"]["get"], token)

    # Replicate has used both spellings across API versions; accept either.
    if result.get("status") not in ("succeeded", "successful"):
        sys.exit(f"Render {result.get('status')}: {result.get('error') or 'no detail given'}")

    image_url = first_image_url(result.get("output"))
    if not image_url:
        sys.exit(f"No image in the response. Raw output: {result.get('output')!r}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = OUT_DIR / f"{name}-{stamp}.png"
    with urllib.request.urlopen(image_url, timeout=120) as src:
        dest.write_bytes(src.read())
    return dest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("shot", nargs="?", help=f"named shot: {', '.join(SHOTS)}")
    parser.add_argument("--prompt", help="custom prompt instead of a named shot")
    parser.add_argument("--name", help="filename stem (required with --prompt)")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Replicate model (default {DEFAULT_MODEL})")
    parser.add_argument("--aspect", default="16:9", help="aspect ratio (default 16:9)")
    parser.add_argument("--list", action="store_true", help="list the named shots and exit")
    parser.add_argument("--dry-run", action="store_true", help="print the full prompt without spending")
    args = parser.parse_args()

    if args.list:
        for key, text in SHOTS.items():
            print(f"\n{key}\n  {text}")
        print(f"\nstyle suffix applied to all:\n  {STYLE}\n")
        return

    if args.prompt:
        if not args.name:
            sys.exit("--prompt needs --name for the filename")
        base, name = args.prompt, re.sub(r"[^a-z0-9-]+", "-", args.name.lower()).strip("-")
    elif args.shot:
        if args.shot not in SHOTS:
            sys.exit(f"Unknown shot {args.shot!r}. Known: {', '.join(SHOTS)}")
        base, name = SHOTS[args.shot], args.shot
    else:
        parser.error("give a named shot or --prompt")

    full = f"{base}. {STYLE}"

    if args.dry_run:
        print(f"model:  {args.model}\naspect: {args.aspect}\nname:   {name}\n\n{full}\n")
        return

    token = load_token()
    print(f"Rendering {name} via {args.model} ...")
    dest = render(full, name, args.model, args.aspect, token)
    print(f"Wrote {dest}")


if __name__ == "__main__":
    main()
