#!/usr/bin/env bash
# Co-op loopback smoke test: launch a headless host + client and check that the two
# processes actually AGREE about the world. Run from the repo root.
#   bash python-tools/coop_smoketest.sh
#
# This is the only thing in the repo that can prove convergence. A single SceneTree
# has one MultiplayerAPI, so a --script suite can be a host or a client but never
# both, and "the other phone agrees" is unobservable from inside one. Every claim
# below needs two processes:
#   heroes / enemies  — the party and the host-authoritative mobs exist on both
#   enemy_twins       — a client SEES the tell and the bolt that can hit it
#   HERO_SPELLS       — your friend's magic is visible (the friendly-fire social loop)
#   BOSS_FX           — the climax of the floor renders on both screens
#   BOSS_ROSTER       — a NEW-roster boss (not just the Ashen Guardian) is visible.
#                       BOSS_FX went green on the Guardian alone while the Scribble,
#                       the Cartographer and the Illuminator shipped with zero network
#                       references — so on most floors a client watched a boss attack
#                       invisibly. This asks for a `circle` twin, which only
#                       TowerBoss.summon_circle can produce.
#   BOSS_MODS         — a modifier RIDER is visible. Asks for a `zone` twin, which only
#                       ModVoidTouched can produce. Riders attach deterministically on
#                       both peers (the seeded roll travels in the spawn dict), but the
#                       ongoing visuals were host-only.
#   floor_sync        — the client follows the host up the tower
#   COVER             — a crate an ENEMY broke is broken on both phones. Enemy attack
#                       twins are visual_only, so this used to be host-only: you took
#                       cover behind something your teammate could not see.
#   PICKUP            — the drop race is scored ONCE. Collection used to resolve
#                       locally, so a photo finish could award the same spell twice.
#   REVIVE            — a GHOST can be picked up across the wire. The client downs its
#                       own hero, waits for `downed` to replicate, asks the host, and
#                       the host's single award comes back and is applied here. Under
#                       the 2026-08-01 death rule ("a life in ghost form until your
#                       teammate revives you") this is the only exit from being dead —
#                       if it does not cross, a co-op run ends the first time anybody
#                       dies, and no single-process suite can tell you that.
#
# The `[NET] VERDICT ... => PASS` line printed by the CLIENT is the answer; the rows
# above it are for reading when it says FAIL.
set -u
G="./godot-engine/Godot_v4.6.2-stable_win64_console.exe"
OUT="${TMPDIR:-/tmp}"
"$G" --headless --path godot-project -- --server  > "$OUT/coop_host.log"   2>&1 &
HP=$!
sleep 3
"$G" --headless --path godot-project -- --client 127.0.0.1 > "$OUT/coop_client.log" 2>&1 &
CP=$!
# Long enough for the CLIENT's whole schedule (Net.CLI_FINAL_SAMPLE is 8.0 s after
# join_ok, and the revive leg can re-down + retry inside that). Trim this and the
# verdict line simply never gets printed, which the RESULT block below reads as FAIL.
sleep 14
kill "$HP" "$CP" 2>/dev/null
wait 2>/dev/null
echo "=== HOST ===";   grep "\[NET\]" "$OUT/coop_host.log"
echo "=== CLIENT ==="; grep "\[NET\]" "$OUT/coop_client.log"
echo "=== RESULT ==="
if grep -q "VERDICT.*=> PASS" "$OUT/coop_client.log"; then
	grep -E "VERDICT|boss_fx_kinds" "$OUT/coop_client.log"
	exit 0
fi
echo "FAIL — the client's verdict line (or the client itself) is missing:"
grep -E "VERDICT|boss_fx_kinds" "$OUT/coop_client.log" || echo "  no VERDICT printed at all"
exit 1
