#!/usr/bin/env python3
"""Find the wishlist form at Kit and wire the landing page to it. One command.

    python python-tools/kit_setup.py            # list the forms the key can see
    python python-tools/kit_setup.py --wire     # patch site/index.html with the id
    python python-tools/kit_setup.py --wire --form-id 1234567     # pick explicitly

Needs `KIT_API_KEY` in the gitignored `.env`, alongside `UPLOAD_POST_API_KEY`.
Get one at Kit: Account Settings -> Developer Settings -> V4 Keys -> Add a new key.
API keys are NOT plan-restricted — Kit's own docs: *"creators on any plan can generate
API keys"* — so this works on the free tier.

⚠ THE KEY NEVER GOES NEAR THE WEBSITE, and that is the whole reason this is a build
step rather than something the page does at runtime. `site/index.html` is served to
strangers; anything in it is public. So the page posts to Kit's PUBLIC form endpoint
(`app.kit.com/forms/<id>/subscriptions`), which is designed to be called by anonymous
browsers and needs no credential. This script is the only thing that holds the key, it
runs on your machine, and all it writes into the page is a form id that is public
anyway.

⚠ IT IS THE NUMERIC `id`, NOT THE `uid`, AND THEY ARE BOTH IN THE RESPONSE. Kit returns
both on every form: `id` (an integer) is what the HTML form action takes; `uid` (a
string) is for the JavaScript embed. Pasting the uid into the action produces a form
that looks perfectly fine and silently accepts nothing — the failure this whole design
is arranged to avoid.

⚠ AND THERE IS NO `POST /forms`. Kit's API can list forms, add subscribers and read
counts, but it cannot CREATE a form — so the one irreducible manual step is making the
form once in Kit's UI. Everything after that is this command.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGE = ROOT / "site" / "index.html"
ENV_FILE = ROOT / ".env"
ENV_KEY = "KIT_API_KEY"

API_BASE = "https://api.kit.com/v4"
## ⚠ NOT `Authorization: Bearer`. That is Kit's OAuth path; an API key goes in its own
## header, and sending it as a bearer token answers 401 with nothing that says why.
AUTH_HEADER = "X-Kit-Api-Key"
## What the page's <form action> is built from. Public by design.
PUBLIC_FORM_ACTION = "https://app.kit.com/forms/{id}/subscriptions"

PLACEHOLDER = "REPLACE_WITH_KIT_FORM_ID"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def load_key() -> str | None:
    """Environment first, then the gitignored .env — same shape as publish_clip."""
    key = os.environ.get(ENV_KEY, "").strip()
    if key:
        return key
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith(f"{ENV_KEY}="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def list_forms(key: str) -> list[dict]:
    """Every form on the account, with the subscriber count where Kit will give it."""
    url = f"{API_BASE}/forms?include=subscriber_count"
    req = urllib.request.Request(url, headers={AUTH_HEADER: key,
                                               "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8", "replace")).get("forms", []) or []
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:300]
        if e.code == 401:
            sys.exit(f"Kit refused the key (401). Check {ENV_KEY} in .env — it must be "
                     f"a V4 key from Account Settings -> Developer Settings.\n  {body}")
        sys.exit(f"Kit answered HTTP {e.code}: {body}")
    except Exception as e:                                   # noqa: BLE001
        sys.exit(f"could not reach Kit: {type(e).__name__}: {e}")


def wire(form_id: int) -> int:
    """Put the form id into both signup forms on the page."""
    if not PAGE.exists():
        print(f"no page at {PAGE}")
        return 1
    html = PAGE.read_text(encoding="utf-8")
    # ⚠ ONLY INSIDE AN action="" ATTRIBUTE. A blanket string replace also rewrote the
    # placeholder where it appeared in JavaScript as the sentinel the guard looked
    # for, which disabled the form permanently the moment it was wired. Anchoring on
    # the attribute means this tool can only ever change a destination, never code.
    attr = re.compile(r'(action="https://app\.kit\.com/forms/)' +
                      re.escape(PLACEHOLDER) + r'(/subscriptions")')
    hits = len(attr.findall(html))
    if not hits:
        current = "already wired" if "app.kit.com/forms/" in html else "not found"
        print(f"  the placeholder is not in the page ({current}).")
        if "app.kit.com/forms/" in html:
            for match in sorted(set(re.findall(r"app\.kit\.com/forms/(\d+)/", html))):
                print(f"  the page currently posts to form {match}")
            print("  to change it, edit site/index.html by hand — this script only "
                  "fills a placeholder,\n  so it can never silently repoint a live "
                  "signup form at a different list.")
        return 1
    PAGE.write_text(attr.sub(rf"\g<1>{form_id}\g<2>", html), encoding="utf-8")
    print(f"  wired {hits} form(s) to {PUBLIC_FORM_ACTION.format(id=form_id)}")
    print(f"  rewrote {PAGE.relative_to(ROOT)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wire", action="store_true",
                    help="patch site/index.html. Without it, this only lists.")
    ap.add_argument("--form-id", type=int,
                    help="which form to use. Only needed if you have more than one.")
    args = ap.parse_args()

    key = load_key()
    if not key:
        print(f"\n{ENV_KEY} is not set.\n")
        print("  1. Kit -> Account Settings -> Developer Settings -> V4 Keys -> "
              "Add a new key")
        print(f"  2. add a line to {ENV_FILE.name} (gitignored):  {ENV_KEY}=kit_...")
        return 1

    forms = [f for f in list_forms(key) if not f.get("archived")]
    print()
    if not forms:
        print("  Kit has no forms on this account yet — and the API cannot create one.")
        print("  Make one at https://app.kit.com/forms (any style; only its id is used),")
        print("  then run this again.")
        return 1

    print(f"  {len(forms)} form(s) on this Kit account:\n")
    for f in forms:
        subs = f.get("subscriber_count")
        print(f"    id {f.get('id'):<10} {str(f.get('name'))[:34]:<36} "
              f"{'' if subs is None else str(subs) + ' subscriber(s)'}")
        print(f"       action  {PUBLIC_FORM_ACTION.format(id=f.get('id'))}")

    if not args.wire:
        print(f"\n  Nothing written. Add --wire to put "
              f"{'this' if len(forms) == 1 else 'one of these'} into the page.")
        return 0

    if args.form_id:
        chosen = next((f for f in forms if f.get("id") == args.form_id), None)
        if not chosen:
            print(f"\n  no form with id {args.form_id} on this account.")
            return 1
    elif len(forms) == 1:
        chosen = forms[0]
    else:
        # Refuse to guess. Picking the wrong list is invisible until somebody looks
        # for signups in a list that never receives any.
        print("\n  More than one form and none named. Re-run with --form-id <id>.")
        return 1

    print()
    return wire(int(chosen["id"]))


if __name__ == "__main__":
    raise SystemExit(main())
