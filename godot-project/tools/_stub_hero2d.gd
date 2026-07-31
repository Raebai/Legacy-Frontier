# A hero-shaped STUB that is a Node2D, for the suites that need a hero with a
# POSITION — the handoff (which measures the distance between two of them) and the
# touch pad (which polls a hero for its button state).
#
# `tools/_stub_hero.gd` is the Node-only version used by the pure-data drop suite;
# this is that plus a transform and the two read-only HUD contracts. Kept separate
# rather than promoting the original, because the drop suite's whole point is that
# the grant ledger needs no tree and no transform, and giving its stub one would
# quietly weaken that claim.
#
# Every member here is DECLARED. `set()` on an undeclared property is a silent no-op
# in Godot 4, so a stub assembled from a bare Node2D plus `set(...)` would swallow
# the writes and make every assertion vacuously true — the exact shape of
# silent-green failure this repo has a scar from.
#
# Deliberately NOT a real `Hero.tscn`: Hero's `_ready` reaches autoloads, and
# `--script` harnesses register none.
#
# Leading underscore keeps `run_all_tests.py` from ever treating it as a suite.
extends Node2D

## The two members `SpellGrant._install` writes when a hero has no `receive_spell`.
var _signatures: Array = []
var _hand: HandSlots = null

## The per-instance input source `SpellHandoff._is_local_player` duck-types: null on
## the human path, a `BotController` on a bot. THE NAME MUST BE THE REAL ONE — a stub
## that declares members the shipped Hero does not is how a duck-typed seam gets to
## lie, and this file previously carried `bot_driven` / `_bot`, which exist NOWHERE in
## the codebase. The handoff read them, `bool(null)` aborted, and the mechanic was
## dead in the real game while green in the suite.
## `slice_test_handoff_pad.gd::local_player_marker_exists_on_a_real_hero` now checks
## this name against `Hero.tscn` so the stub can never again be more generous than
## reality.
var controller: Object = null


## The contract `TouchControls._sync_buttons` polls per spell pad. Only the keys the
## pad actually reads — a wider fake would be a second implementation of Hero's HUD
## contract, free to drift from the real one.
func spell_button_state(slot: int) -> Dictionary:
	var sig: SpellDef = null
	if _hand != null:
		var s: Variant = _hand.spell_at(slot)
		if s is SpellDef:
			sig = s as SpellDef
	return {
		"slot": slot, "key": "", "name": "" if sig == null else sig.display_name,
		"remaining": 0.0, "total": 0.0 if sig == null else maxf(sig.cooldown, 0.01),
		"ready": sig != null, "filled": sig != null, "pulse": 0.0, "selected": false,
	}


func touch_button_state(_action: StringName) -> Dictionary:
	return {"remaining": 0.0, "total": 0.0, "ready": true, "pulse": 0.0,
		"filled": true, "name": ""}
