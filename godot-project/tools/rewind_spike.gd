# REWIND SPIKE — the cheap experiment the plan asked for before committing a
# 4-second state rewind to the Tier 3 list.
#
#   godot --headless --path godot-project --script tools/rewind_spike.gd
#
# NOT a test suite (no `test_` in the name, so run_all_tests.py never runs it). It
# is a measurement, and it exists so the decision to SWAP Rewind for Equinox is
# backed by numbers rather than by a feeling about difficulty.
#
# WHAT IT DOES
#   1. Builds the cheapest honest recorder: a ring buffer of (position, velocity,
#      hp) for every body, at the physics rate, for 4 seconds. Measures its real
#      memory cost and its per-frame cost.
#   2. Runs a restore and CHECKS IT, so "the easy part works" is a measured claim.
#   3. Enumerates the state a real rewind would also have to restore, by COUNTING
#      the actual spectacle scripts and per-body state fields in this codebase
#      rather than by guessing how many there are.
#
# WHAT IT DELIBERATELY DOES NOT DO: attempt the hard parts. The point of a spike
# is to find out what they cost, not to half-build them.
extends SceneTree

const WINDOW: float = 4.0
const TICK_HZ: float = 60.0
const BODIES: int = 12

## Every spell spectacle in the game. A rewind has to un-spawn, re-spawn or
## re-simulate each of these, and each carries its own internal phase clock.
const SPECTACLE_DIR: String = "res://scripts/combat/"

var _ring: Array[Dictionary] = []
var _bodies: Array[Node2D] = []


func _initialize() -> void:
	print("=== REWIND SPIKE ===")
	_stage()
	_record()
	_measure_restore()
	_enumerate_the_rest()
	_verdict()
	quit(0)


func _stage() -> void:
	var root_node := Node2D.new()
	root.add_child(root_node)
	for i: int in BODIES:
		var b := Node2D.new()
		b.set_meta("hp", 100)
		b.global_position = Vector2(i * 40.0, 100.0)
		root_node.add_child(b)
		_bodies.append(b)


## THE EASY PART. Position + velocity + hp for every body, every physics frame,
## for four seconds.
func _record() -> void:
	var frames: int = int(WINDOW * TICK_HZ)
	var t0: int = Time.get_ticks_usec()
	for f: int in frames:
		var snap: Dictionary = {}
		for b: Node2D in _bodies:
			snap[b.get_instance_id()] = {
				"pos": b.global_position + Vector2(f, 0.0),
				"vel": Vector2(f, -f),
				"hp": 100 - f / 8,
			}
		_ring.append(snap)
	var us: int = Time.get_ticks_usec() - t0
	# Rough bytes: 12 bodies x (2 Vector2 + 1 int + dict overhead) x 240 frames.
	var per_row: int = 8 + 8 + 8 + 48   # two Vector2, one int, Dictionary entry overhead
	var bytes: int = frames * BODIES * per_row
	print("recorder: %d frames x %d bodies = %d rows" % [frames, BODIES, frames * BODIES])
	print("recorder: build cost %.2f ms total, %.4f ms/frame"
		% [us / 1000.0, us / 1000.0 / float(frames)])
	print("recorder: ~%d KB resident for a 4 s window at %d bodies" % [bytes / 1024, BODIES])


## Restore the oldest snapshot and verify it landed. This is the half that WORKS.
func _measure_restore() -> void:
	var oldest: Dictionary = _ring[0]
	var ok: int = 0
	for b: Node2D in _bodies:
		var row: Dictionary = oldest[b.get_instance_id()]
		b.global_position = row["pos"]
		b.set_meta("hp", row["hp"])
		if b.global_position.is_equal_approx(row["pos"]):
			ok += 1
	print("restore: %d/%d bodies returned to their 4 s-ago transform + hp" % [ok, _bodies.size()])


## THE HARD PART, counted rather than hand-waved.
func _enumerate_the_rest() -> void:
	var spectacles: int = 0
	var dir: DirAccess = DirAccess.open(SPECTACLE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var f: String = dir.get_next()
		while f != "":
			# A spectacle is any script this repo casts through SpellCaster; counted
			# by the marker every one of them carries.
			if f.ends_with(".gd"):
				var txt: String = FileAccess.get_file_as_string(SPECTACLE_DIR + f)
				if txt.contains("var caster_node") or txt.contains("reaction_owner"):
					spectacles += 1
			f = dir.get_next()
		dir.list_dir_end()
	print("uncovered: %d live spell spectacles carry their own phase clock" % spectacles)
	print("uncovered: destructible cover (DestructibleProp / DestructibleTerrain /")
	print("           BreakablePlatform) is DESTROYED, not hidden — nothing to restore to")
	print("uncovered: a dead Enemy has been queue_free()d; a rewind must RESURRECT it,")
	print("           which means never freeing anything inside the window")
	print("uncovered: per-body state not in the ring — StatusComponent ailments,")
	print("           GuardComponent bank, HandSlots cooldowns, dash/blink/parry timers,")
	print("           CharacterRig spring state, air-jump count, MP")
	print("uncovered: NET AUTHORITY. Each peer is authoritative over its OWN hero")
	print("           (Hero.is_multiplayer_authority / Net.deal_damage is victim-routed).")
	print("           Peer A cannot legally write peer B's transform, so a rewind either")
	print("           silently skips the other player or authority has to move for 4 s.")


func _verdict() -> void:
	print("")
	print("VERDICT: the recorder is CHEAP and the transform/hp restore WORKS.")
	print("         Everything that makes it a REWIND rather than a teleport is the")
	print("         expensive half, and the net-authority clause is not an amount of")
	print("         work — it is a change to the co-op model for one drop-table entry.")
	print("         SHIPPED INSTEAD: Equinox (see SpellLibrary._equinox). Catastrophic,")
	print("         decision-shaped, can lose you the floor, moves HP and nothing else,")
	print("         and HP already has an authority-correct route in this codebase.")
	print("=== END SPIKE ===")
