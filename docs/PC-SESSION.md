# PC session: the standing prompt

Started by double-clicking `Stickspire.bat` in the repo root. This is the half of the build
that needs the editor, eyes, a phone or the maker. The cloud session (`docs/CLOUD-SESSION.md`)
does everything else twice a day. The two never take each other's queue.

## Every run, in order

1. Read `CLAUDE.md` (the Current Direction block), then `docs/NEXT-SESSION.md`, then
   `git log --oneline -20`. If there are uncommitted changes, commit them with a plain message
   and push `bot-fight-quality` first, so the cloud can see them. Never work on a dirty tree.
2. Read the design doc with the Claude Docs connector, three tabs:
   https://claude.ai/code/artifact/f551ee82-cf1e-4d29-bc2e-aa1b2c567045
   "Build board" for the PC queue's task rows (their Proof and Check columns), "Build log" for
   what the cloud did since you last ran. If the connector is missing, say so and stop.
3. Make sure the editor loop works before anything else: Godot-MCP-Native enabled in
   `godot-project/project.godot` (addon in `art-source/third_party/Godot-MCP-Native.zip`), the
   two HaD0Yun MCP addons disabled, and one proof that you can run the game, take a runtime
   screenshot and pixel-diff it against the last one. The first time this is task 1.2 on the
   board; after that it is a 30-second check.
4. Take the top unticked PC item in `docs/NEXT-SESSION.md`. Loop: change, run, capture with
   the matching tool from `python python-tools/run_capture.py --list` (GUI binary, never
   headless), look at the PNG or GIF, compare against the board's Proof column, fix, until it
   matches. The maker is not here to operate the editor; you are.
5. Write the proof to `proof/<date>-<task>/` with a `caption.md` (what it shows, what
   changed, how to reproduce). A visual task without a proof is not done.
6. Run `python python-tools/run_all_tests.py`. Do the board's Check for the task (the sabotage
   pass when it names a guard: break it, see it go RED naming the fault, restore).
7. Tick the item in `docs/NEXT-SESSION.md`, commit small with the evidence in the message and
   the trailers the harness gives you, push `bot-fight-quality`.
8. Append a row to the top of the Build log tab (date, lane, what changed, proof path, what
   it needs from the maker) with the Claude Docs connector.
9. If the maker is present, ask for the three lines (what felt good, what felt wrong, what
   you'd clip) and put them in the Build log row. If not, keep going to the next PC item
   until the maker stops you or the queue is empty.
10. At the end, `/obsidian-save` any ruling or lesson that cost real time into the vault's
    `Projects/Stickspire.md` (ASCII only, the hook bans em-dashes and curly quotes), then
    report in under 120 words: what changed, what is next, what needs the maker.

## Rules that do not bend

- Never decide anything in the Design tab's "Open decisions". Never buy anything.
- Never commit secrets, keystores, APKs, `art-source/` output or `proof/` files over 20 MB
  (make a GIF or a lower-res MP4 instead).
- Never say a thing works because the test is green; say what was played and seen.
- Do not touch the Unreal repo (Raebai/LegacyFrontier, no hyphen). It is archived.
