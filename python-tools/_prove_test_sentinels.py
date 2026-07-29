"""Proof harness for the completion-sentinel retrofit.

For each (suite, member-read) pair below it edits ONE assertion so it reads a
member that does not exist — exactly what happens when a field is renamed or moves
to another node — runs the suite headless, and restores the file.

The old idiom printed "all PASS" for this. The retrofit must instead FAIL and name
the test that aborted. Anything else means that suite's armour does not work.

Nothing under scripts/ is touched: the mutation is inside the test file, and the
runtime abort it triggers is the identical mechanism (invalid property access on a
base object aborts the enclosing function).
"""
from __future__ import annotations

import io
import os
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GODOT = os.path.join(ROOT, "godot-engine", "Godot_v4.6.2-stable_win64_console.exe")
TOOLS = os.path.join(ROOT, "godot-project", "tools")

# (suite, the exact text to mutate, the mutation, the test that must be named)
CASES: list[tuple[str, str, str, str]] = [
    # Mitigation arithmetic. `g` is a STATICALLY TYPED GuardComponent — the point
    # being that the type annotation does not stop the abort.
    ("slice6_test_guard.gd",
     "_expect(g.absorb == 30.0,",
     "_expect(g.absorb_MOVED == 30.0,",
     "replace_not_stack"),
    # Hero ability state, scene-instanced.
    ("slice1_test_blink.gd",
     "hero._blink_cooldown_timer == hero.BLINK_COOLDOWN,",
     "hero._blink_cooldown_timer_MOVED == hero.BLINK_COOLDOWN,",
     "blink_moves_along_facing"),
    # An ULT's balance constants, read off a runtime-load()ed GDScript.
    ("slice8_test_ults.gd",
     "float(conv.CONVERGE_TIME)",
     "float(conv.CONVERGE_TIME_MOVED)",
     "convergence_promises"),
    # A spectacle node's tuning, read off a scene-instanced Node2D.
    ("slice1_test_nova.gd",
     "inside.damage_taken == nova.NOVA_DAMAGE,",
     "inside.damage_taken == nova.NOVA_DAMAGE_MOVED,",
     "nova_damages_and_pushes_inside_only"),
    # The versus arena: tests that TAKE AN ARGUMENT (the shape the first pass of
    # the converter got wrong, so it is worth proving explicitly).
    ("slice3_test_versus.gd",
     "bots.size() == arena.BOT_COUNT,",
     "bots.size() == arena.BOT_COUNT_MOVED,",
     "match_setup"),
    # An `_initialize` + await runner, i.e. the physics-space suites.
    ("slice_test_spell_world.gd",
     "_expect(r[\"collider\"] == w, \"wall: collider is the wall\")",
     "_expect(r.collider_MOVED == w, \"wall: collider is the wall\")",
     "wall_stops_and_reports"),
    # A spell-shape suite driven off SpellDef data.
    ("slice7_test_ice_spike_line.gd",
     "spell.kind == SpellDef.Kind.METEOR,",
     "spell.kind_MOVED == SpellDef.Kind.METEOR,",
     "spell_def_wiring"),
    # The run loop / GameState statics, tests that take an argument.
    ("slice2_test_runloop.gd",
     "_expect(bool(o[\"died\"]) == true, \"died carried\")",
     "_expect(o.died_MOVED == true, \"died carried\")",
     "build_outcome"),
    # The three suites the original grep MISSED (every call is awaited), converted
    # for the same reason and proved the same way.
    ("slice_test_shadow_kit_world.gd",
     "int(d.get(\"_state\")) == 1, \"the blade STOPS (state STUCK) at the wall\"",
     "d._state_MOVED == 1, \"the blade STOPS (state STUCK) at the wall\"",
     "dagger_stops_at_a_wall"),
    ("slice_test_spell_targets.gd",
     "_expect(SpellTargets.hit_margin(f) > 3.0,",
     "_expect(f.hit_margin_MOVED > 3.0,",
     "silhouette_seam_duck_types"),
    ("slice3_test_spell_collision.gd",
     "_expect(not is_instance_valid(spell), \"bolt consumed by cover (did not pass through)\")",
     "_expect(not spell.is_valid_MOVED, \"bolt consumed by cover (did not pass through)\")",
     "terrain_stops_bolt"),
]


def run(suite: str) -> str:
    p = subprocess.run(
        [GODOT, "--path", os.path.join(ROOT, "godot-project"), "--headless",
         "--script", "tools/" + suite],
        capture_output=True, text=True, errors="replace", timeout=600,
    )
    return (p.stdout or "") + (p.stderr or "")


def main() -> None:
    passed = 0
    for suite, old, new, test_name in CASES:
        path = os.path.join(TOOLS, suite)
        original = open(path, encoding="utf-8").read()
        if old not in original:
            print("!! %-32s could not find the mutation point" % suite)
            continue
        open(path, "w", encoding="utf-8", newline="\n").write(original.replace(old, new, 1))
        try:
            out = run(suite)
        finally:
            open(path, "w", encoding="utf-8", newline="\n").write(original)
        sentinel = "test `%s` ran to completion" % test_name
        failed_loudly = "FAILED" in out and sentinel in out
        vacuous = "all PASS" in out
        print("%-32s %s" % (suite, "PROVED" if failed_loudly and not vacuous else "*** NOT PROVED ***"))
        for line in out.splitlines():
            if "FAIL:" in line or "FAILED" in line:
                print("        | " + line.strip()[:150])
        passed += int(failed_loudly and not vacuous)
    print("\n%d/%d suites proved" % (passed, len(CASES)))


if __name__ == "__main__":
    main()
