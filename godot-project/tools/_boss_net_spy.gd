extends "res://scripts/Net.gd"
## RECORDING STAND-IN FOR THE `Net` AUTOLOAD, used by tools/slice_test_bossnet.gd.
##
## ── WHY IT EXTENDS THE REAL THING ────────────────────────────────────────────
## The first draft of this was a hand-written `Node` declaring only the two members
## `Boss._bfx` touches (`is_host` + `broadcast_boss_fx`). It did not survive one run:
## a boss entering a phase also calls `broadcast_boss_phase`, and laying a tell also
## calls `broadcast_telegraph`. In GDScript a call to a nonexistent method ABORTS the
## enclosing function, so `_enter_phase` and `lane_tell` died half-way and the attacks
## under test never happened — while the suite reported the *attacks* as broken. A
## stub NARROWER than reality lies exactly as badly as one wider than it (which is
## the `SpellHandoff` / `bot_driven` trap, from the other side).
##
## Subclassing makes drift impossible: every member a boss might reach for exists,
## because it is the shipped class. Only the wire is replaced.
##
## ── ⚠ WHY THIS IS ITS OWN FILE AND NOT AN INNER CLASS OF THE SUITE ───────────
## `--script` loads the suite BEFORE the engine registers autoload identifiers, so
## naming `res://scripts/Net.gd` at the suite's compile time drags Net's whole
## dependency chain (BeamSpell, MeteorSigil, ZoneSpell, ...) into that same early
## compile — where every one of them fails on `Identifier not found: Sfx`, and the
## suite dies reporting nonsense about missing `new()` methods on GDScript. Exactly
## the standing trap in the handoff notes, met from a new direction.
##
## Kept in its own file so the suite reaches it with a RUNTIME `load()`, by which
## point the autoloads exist. The leading underscore keeps `run_all_tests.py` from
## mistaking it for a suite (it excludes `^_`).

## Every `broadcast_boss_fx` this run: [{kind, data}, ...].
var calls: Array[Dictionary] = []
## Everything else that went to the wire (telegraphs, phases, props). Recorded
## rather than dropped so a failure is diagnosable rather than merely red.
var other: Array[String] = []


# ---- the two session predicates, answered "yes" so co-op paths are actually taken
func is_host() -> bool:
	return true


func is_active() -> bool:
	return true


# ---- the wire, replaced. There is no peer here, so nothing may reach `.rpc()`.
func broadcast_boss_fx(kind: String, data: Dictionary) -> void:
	calls.append({"kind": kind, "data": data})


func broadcast_boss_phase(_boss: Node, phase: int) -> void:
	other.append("phase:%d" % phase)


func broadcast_telegraph(_data: Dictionary) -> void:
	other.append("telegraph")


func broadcast_projectile(_data: Dictionary) -> void:
	other.append("projectile")


func broadcast_blast(_pos: Vector2, _element: int, _radius: float) -> void:
	other.append("blast")


func broadcast_burst(_pos: Vector2, _c1: Color, _c2: Color) -> void:
	other.append("burst")


func broadcast_hero_action(_kind: String, _data: Dictionary) -> void:
	other.append("hero_action")


func broadcast_prop_state(_prop: Node2D, _hp_now: int, _shattered: bool) -> void:
	other.append("prop")


func broadcast_floor_cleared() -> void:
	other.append("cleared")


## The kinds recorded so far, in order.
func kinds() -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in calls:
		out.append(String(c["kind"]))
	return out
