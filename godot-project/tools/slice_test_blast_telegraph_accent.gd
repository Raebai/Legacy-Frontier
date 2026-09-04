# Run: godot --headless --path godot-project --script tools/slice_test_blast_telegraph_accent.gd
#
# RULE 1 OF THE TELL LAYER, PINNED FOR `BlastSpell`: COLOUR CARRIES ELEMENT.
#
# `Telegraph` was audited and rebuilt so that `accent` is the whole colour statement and
# no style paints a hard-coded hue over it. That only buys anything if the SPELLS
# actually set `accent` — and `BlastSpell` did not, so the fire punch, the ground slam,
# `MeteorFist` and the mage AoE all warned in the same danger red no matter what they
# were made of. This file is what stops that coming back.
#
# ⚠ AND IT PINS THE GUARD, NOT JUST THE FEATURE. `Elements.color` falls back to ARCANE
# MAGENTA for an unrecognised element, and `BlastSpell.element_id` defaults to -1, so the
# obvious one-line fix would have repainted every unelemented blast from danger red to
# magenta — announcing "arcane" on a spell with no element. `Net.gd:986` really can hand
# -1 through from a replicated payload. Both halves are asserted: an elemented blast
# follows its element, an unelemented one keeps `Telegraph.RING_COLOR`.
#
# ⚠ HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the enclosing
# function and hands back the type's zero, which that idiom reads as "no failures".
# Failures accumulate on the MEMBER `_fails`; every test records a COMPLETION SENTINEL as
# its last line, so an aborted test fails BY ABSENCE.
#
# ⚠ `_initialize`, NOT `_process`. A SceneTree script's `_process` quits the tree the
# moment it returns true, and these tests need frames to elapse.
extends SceneTree

const BLAST_SCENE_PATH: String = "res://scenes/combat/BlastSpell.tscn"

const TESTS: Array[String] = [
	"an_elemented_blast_warns_in_its_own_element",
	"an_unelemented_blast_keeps_the_shared_danger_red",
	"the_ring_is_still_drawn_at_the_radius_that_damages",
]

## Every element the roster actually casts, so a fire punch and an ice slam are proven
## to differ rather than merely assumed to.
const ELEMENTS: Array[int] = [
	Elements.Element.FIRE, Elements.Element.ICE, Elements.Element.LIGHTNING,
	Elements.Element.SHADOW, Elements.Element.ARCANE, Elements.Element.EARTH,
	Elements.Element.HOLY, Elements.Element.WIND,
]

var _fails: int = 0
var _completed: Dictionary = {}


func _initialize() -> void:
	_go()


func _go() -> void:
	await process_frame
	for t: String in TESTS:
		await call(t)
	for t: String in TESTS:
		_expect(_completed.has(t), "%s ran to completion" % t)
	print("slice_test_blast_telegraph_accent: %s (%d failure(s))"
		% ["all PASS" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL: %s" % what)


func _done(t: String) -> void:
	_completed[t] = true


## A blast placed through the REAL public entry (`detonate_at`, the one that builds a
## telegraph), with its telegraph handed back. `detonate_now` is deliberately not used —
## it builds no telegraph at all, which is the whole reason it exists.
func _telegraph_for(element: int) -> Telegraph:
	var scene: PackedScene = load(BLAST_SCENE_PATH) as PackedScene
	if scene == null:
		return null
	var blast: Node2D = scene.instantiate() as Node2D
	root.add_child(blast)
	var opts: Dictionary = {"damage": 60, "radius": 66.0, "windup": 4.0}
	if element >= 0:
		opts["element_id"] = element
	blast.call("configure", opts)
	blast.call("detonate_at", Vector2(700.0, 700.0))
	for child: Node in blast.get_children():
		var t: Telegraph = child as Telegraph
		if t != null:
			return t
	return null


func an_elemented_blast_warns_in_its_own_element() -> void:
	await process_frame
	var seen: Dictionary = {}
	for e: int in ELEMENTS:
		var t: Telegraph = _telegraph_for(e)
		_expect(t != null, "detonate_at built a telegraph for element %d" % e)
		if t == null:
			continue
		var want: Color = Elements.color(e)
		_expect(t.accent.is_equal_approx(want),
			"element %d warned in %s, its signature colour is %s"
				% [e, str(t.accent), str(want)])
		seen[str(t.accent)] = true
		t.get_parent().queue_free()
	# THE POINT, stated as the property that was actually broken: eight elements must
	# not warn in one colour. A per-element assert alone would still pass if
	# `Elements.color` collapsed.
	_expect(seen.size() >= 6,
		"the eight elements produced only %d distinct telegraph colour(s)" % seen.size())
	_done("an_elemented_blast_warns_in_its_own_element")


func an_unelemented_blast_keeps_the_shared_danger_red() -> void:
	await process_frame
	# The magenta trap. `Elements.color(-1)` is ARCANE magenta, NOT a neutral, so this
	# asserts against the fallback explicitly rather than against "some colour".
	_expect(Elements.color(-1).is_equal_approx(Elements.color(Elements.Element.ARCANE)),
		"Elements.color(-1) no longer falls back to ARCANE — the guard's reason has "
		+ "changed and its comment in BlastSpell.detonate_at is now wrong")
	var t: Telegraph = _telegraph_for(-1)
	_expect(t != null, "detonate_at built a telegraph for an unelemented blast")
	if t != null:
		_expect(t.accent.is_equal_approx(Telegraph.RING_COLOR),
			"an unelemented blast warned in %s; it must keep the shared danger red %s"
				% [str(t.accent), str(Telegraph.RING_COLOR)])
		_expect(not t.accent.is_equal_approx(Elements.color(-1)),
			"an unelemented blast warned in ARCANE MAGENTA — the guard is gone and every "
			+ "elementless blast now announces an element it does not have")
		t.get_parent().queue_free()
	_done("an_unelemented_blast_keeps_the_shared_danger_red")


## The colour channel is what changed; the geometry must not have. The windup is the
## dodge budget and the ring is the promise about where the damage lands, so a colour
## fix that moved the ring would be far worse than the bug it fixed.
func the_ring_is_still_drawn_at_the_radius_that_damages() -> void:
	await process_frame
	var scene: PackedScene = load(BLAST_SCENE_PATH) as PackedScene
	_expect(scene != null, "the blast scene loaded")
	if scene == null:
		_done("the_ring_is_still_drawn_at_the_radius_that_damages")
		return
	for r: float in [66.0, 98.0]:
		var blast: Node2D = scene.instantiate() as Node2D
		root.add_child(blast)
		blast.call("configure",
			{"damage": 60, "radius": r, "windup": 4.0, "element_id": Elements.Element.FIRE})
		blast.call("detonate_at", Vector2(700.0, 700.0))
		var t: Telegraph = null
		for child: Node in blast.get_children():
			if child is Telegraph:
				t = child as Telegraph
				break
		_expect(t != null, "a telegraph was built for radius %.0f" % r)
		if t != null:
			_expect(is_equal_approx(float(t.get(&"_radius")), r),
				"the ring is drawn at %.1f for a blast that damages at %.1f"
					% [float(t.get(&"_radius")), r])
		blast.queue_free()
	_done("the_ring_is_still_drawn_at_the_radius_that_damages")
