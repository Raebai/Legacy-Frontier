# Run: godot --headless --path godot-project --script tools/slice_test_hub_shoot.gd
#
# A TRIGGER RING IS NOT A WALL. `Spell._on_area_hit` routes `area.get_parent()` into
# the same funnel a real body hit uses, so any Area2D whose parent happens to be a
# StaticBody2D used to detonate the bolt on the "a platform stopped it" branch —
# hitstop, shake, an impact burst and a spray of rubble, off a proximity ring whose
# only job is to raise an `[E] Talk` prompt.
#
# The hub is built out of those rings (every townsperson, every pad, the tower door),
# which is the maker's report: "it lags when I try shoot an NPC or the teleportation
# rings in the hub". Measured in the town while holding the trigger, mean frame time
# was 30.76 ms with a 659.93 ms worst frame; after, 22.06 ms and 43.38 ms, level with
# shooting into empty air.
#
# ⚠ THE ASSERTION IS ABOUT THE BOLT'S SURVIVAL, NOT ABOUT THE RUBBLE. Counting debris
# would pass for the wrong reason on any build where the austerity thinner happened to
# grant zero chunks (`DebrisChunk.spawn_burst` scales by `vfx_austerity`). "Did the
# bolt die?" is the question the branch actually answers.
#
# ⚠ AND IT CARRIES ITS OWN CONTROL. A test that only proves a bolt survives a trigger
# ring would also pass if `_try_damage` had been broken into a no-op for everything —
# so the same bolt is fired at a REAL StaticBody2D through the body path, and that one
# MUST still die. One known-good and one known-broken case through the same predicate,
# or the suite is testing the instrument.
extends SceneTree

const SPELL: String = "res://scenes/combat/Spell.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	var parent := Node2D.new()
	root.add_child(parent)

	# ── the hub shape: a static body carrying a proximity Area2D child ──────────
	var post := StaticBody2D.new()
	parent.add_child(post)
	post.global_position = Vector2(400.0, 0.0)
	var ring := Area2D.new()
	post.add_child(ring)

	var bolt: Node = _bolt(parent, Vector2(400.0, 0.0))
	if bolt == null:
		printerr("FAIL: could not instance %s" % SPELL)
		quit(1)
		return true
	bolt.call("_on_area_hit", ring)
	failed += _expect(not bool(bolt.get("_dead")),
		"a bolt does NOT detonate on a trigger ring parented to a StaticBody2D")

	# ── the control: the same bolt, the same static body, through the BODY path ──
	var bolt2: Node = _bolt(parent, Vector2(400.0, 0.0))
	bolt2.call("_on_hit", post)
	failed += _expect(bool(bolt2.get("_dead")),
		"...but it DOES still die on that same static body hit as a body")

	if failed > 0:
		printerr("Hub-shoot tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Hub-shoot tests: all PASS")
		quit(0)
	return true


## A live bolt in the tree. `visual_only` is left false so the real branches run;
## `caster` is left null on purpose — the caster guard is a different rule and a
## non-null caster here would mask the branch under test.
func _bolt(parent: Node, at: Vector2) -> Node:
	var packed: PackedScene = load(SPELL)
	if packed == null:
		return null
	var b: Node = packed.instantiate()
	parent.add_child(b)
	(b as Node2D).global_position = at
	return b


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0
