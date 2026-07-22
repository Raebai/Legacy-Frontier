#!/usr/bin/env bash
# Co-op loopback smoke test: launch a headless host + client, confirm they connect
# and BOTH enter the arena with 2 heroes. Run from the repo root.
#   bash python-tools/coop_smoketest.sh
set -u
G="./godot-engine/Godot_v4.6.2-stable_win64_console.exe"
OUT="${TMPDIR:-/tmp}"
"$G" --headless --path godot-project -- --server  > "$OUT/coop_host.log"   2>&1 &
HP=$!
sleep 3
"$G" --headless --path godot-project -- --client 127.0.0.1 > "$OUT/coop_client.log" 2>&1 &
CP=$!
sleep 10
kill "$HP" "$CP" 2>/dev/null
wait 2>/dev/null
echo "=== HOST ===";   grep "\[NET\]" "$OUT/coop_host.log"
echo "=== CLIENT ==="; grep "\[NET\]" "$OUT/coop_client.log"
echo "PASS if host sees a peer (total=2), both print heroes=2, the client's floor"
echo "follows the host to 2, AND the client's twins=2 (proves the attack-visual"
echo "tell/bolt RPC path delivers over the wire — a client sees what can hit it)."
