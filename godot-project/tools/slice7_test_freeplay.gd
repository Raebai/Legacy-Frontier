# Run: godot --headless --path godot-project --script tools/slice7_test_freeplay.gd
# FREE PLAY — the stage with no bots on it. Asserts the mode against the REAL
# scenes: `FreePlay.tscn` builds, it stands up exactly one hero and no opponent,
# ring-out cannot eliminate it, class swaps live, dummies appear and vanish, and —
# the one that actually bites — the `VersusArena.free_play` STATIC is cleared on the
# way out so the duel and the capture tools are not poisoned by a mode that left.
#
# ⚠ THE HOUSE RULE, AND WHY THIS FILE IS SHAPED THIS WAY. Never
# `failed += _test_x()`. Reading a member that has MOVED is not a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller the return type's zero — which that idiom reads as "no failures". It
# silently disabled 64 suites in this project once. So failures accumulate on the
# MEMBER `_fails` and every test records a COMPLETION SENTINEL as its last line: a
# test that dies half-way fails the suite BY ABSENCE, whichever member moved and
# with nobody having had to predict it.
#
# Scenes are load()ed BY PATH at runtime, never preloaded and never named through
# `class_name`, because a `--script` harness registers no autoloads and a
# parse-time compile of the Hero/arena chain reaches `Sfx` / `Rank` / `Juice`.
extends SceneTree

const FREE_SCENE: String = "res://scenes/combat/FreePlay.tscn"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"

## Every test that must run to completion. A name missing from `_completed` means
## that test aborted part-way.
const TESTS: Array[String] = [
	"scene_builds", "one_hero_no_foe", "ringout_never_eliminates",
	"class_swaps_live", "dummies_toggle", "static_cleared_on_exit",
	"duel_still_default",
]

## Members this suite reaches DYNAMICALLY on the arena and the hero. The sentinel
## says "something died"; this says WHICH.
const ARENA_METHODS: Array[String] = [
	"free_hero", "pause_menu", "set_dummy_count", "dummy_count",
	"reset_free_stage", "flash_banner",
]
const HERO_MEMBERS: Array[String] = ["hp", "max_hp", "hostile_group", "controller"]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _free: Node = null
var _arena: Node = null


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_scene_builds()
	_test_one_hero_no_foe()
	_test_ringout_never_eliminates()
	_test_class_swaps_live()
	_test_dummies_toggle()
	_test_static_cleared_on_exit()
	_test_duel_still_default()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Free play tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Free play tests: all PASS")
		quit(0)
	return true


# ==========================================================================

## The scene instantiates and the arena underneath it comes up in FREE mode.
func _test_scene_builds() -> void:
	_free = (load(FREE_SCENE) as PackedScene).instantiate()
	root.add_child(_free)
	_expect(_free != null, "FreePlay.tscn instantiates")
	_arena = _find_arena(_free)
	_expect(_arena != null, "free play instantiates the versus arena as a child")
	if _arena == null:
		return
	for m: String in ARENA_METHODS:
		_expect(_arena.has_method(m), "VersusArena still publishes `%s()`" % m)
	_completes("scene_builds")


## ONE hero, and nothing hostile to it. This is the whole ask — "no bots" — and it
## is the assertion that catches free play accidentally inheriting the duel's
## second fighter.
func _test_one_hero_no_foe() -> void:
	if _arena == null:
		return
	var heroes: Array[Node] = get_nodes_in_group("hero")
	_expect(heroes.size() == 1,
		"exactly one hero on the stage, not %d" % heroes.size())
	_expect(get_nodes_in_group("enemy").is_empty(),
		"no enemies: %d found" % get_nodes_in_group("enemy").size())
	var hero: Node = _arena.call("free_hero") as Node
	_expect(hero != null, "the arena publishes its free-play hero")
	if hero == null:
		return
	for m: String in HERO_MEMBERS:
		_expect(_has_prop(hero, m), "Hero still declares `%s`" % m)
	# NO CONTROLLER. That is what makes this hero read the real `Input` — i.e. what
	# makes it YOURS. A controller here would mean a bot wearing the player's body.
	_expect(hero.get("controller") == null,
		"the free-play hero has no bot controller (it is driven by real Input)")
	_completes("one_hero_no_foe")


## Falling off the rim costs nothing. `STOCKS` is 3 on this stage and a curious
## player will find the edge inside a minute; burning a stock per fall would end
## the sandbox three jumps in.
func _test_ringout_never_eliminates() -> void:
	if _arena == null:
		return
	var hero: Node = _arena.call("free_hero") as Node
	if hero == null:
		return
	var before: Vector2 = (hero as Node2D).global_position
	# Drive the ring-out path directly — the same entry point `StageHazard` uses.
	for _i: int in 6:
		_arena.call("_on_fighter_fell", hero)
	_expect(is_instance_valid(hero) and not hero.is_queued_for_deletion(),
		"six ring-outs later the hero is still alive")
	_expect(get_nodes_in_group("hero").size() == 1,
		"...and still on the stage")
	_expect(int(hero.get("hp")) > 0, "...and at full health, not eliminated")
	_expect(before != Vector2.INF, "position was readable before the fall")
	_completes("ringout_never_eliminates")


## Class swaps WITHOUT a reload, and without rewriting the player's saved Lobby
## pick. Both halves matter: the first is the reason the mode exists, the second is
## the bug where trying nine classes in a sandbox silently re-rolls what you climb
## with.
func _test_class_swaps_live() -> void:
	if _free == null or _arena == null:
		return
	var hero: Node = _arena.call("free_hero") as Node
	if hero == null or not hero.has_method("configure_class"):
		return
	var gs: Node = root.get_node_or_null(^"/root/GameState")
	var saved: Variant = gs.get("selected_class") if gs != null else null
	var before: Variant = hero.get("_hero_class")
	_free.call("_cycle_class")
	var after: Variant = hero.get("_hero_class")
	_expect(before != after, "cycling the class actually changed the hero's class")
	# The kit came with it — a class swap that leaves the old spells behind is the
	# failure this catches.
	var sig: Variant = hero.call("signature_at", 0)
	_expect(sig != null, "the new class has a damage-slot spell")
	if gs != null:
		_expect(gs.get("selected_class") == saved,
			"free play did NOT rewrite GameState.selected_class")
	_completes("class_swaps_live")


## Dummies appear, count up, and wrap back to an empty stage.
func _test_dummies_toggle() -> void:
	if _arena == null:
		return
	_arena.call("set_dummy_count", 0)
	_expect(get_nodes_in_group("free_dummy").is_empty(), "zero dummies means an empty stage")
	_arena.call("set_dummy_count", 2)
	_expect(get_nodes_in_group("free_dummy").size() == 2,
		"two dummies stood up, got %d" % get_nodes_in_group("free_dummy").size())
	for d: Node in get_nodes_in_group("free_dummy"):
		# A dummy is hittable and harmless: physics off so it cannot mirror the real
		# `Input` the player is pressing, and on a team the player is hostile to.
		_expect(not (d as Node2D).is_physics_processing(),
			"a dummy does not run physics (else it mirrors the player's own buttons)")
		_expect(int(d.get("hp")) > 1000, "a dummy has a practice-range health pool")
	_arena.call("set_dummy_count", 0)
	# queue_free is deferred, so the count is checked by validity rather than by the
	# group, which does not shrink until the frame ends.
	var still_live: int = 0
	for d: Node in get_nodes_in_group("free_dummy"):
		if is_instance_valid(d) and not d.is_queued_for_deletion():
			still_live += 1
	_expect(still_live == 0, "clearing the count frees every dummy")
	_completes("dummies_toggle")


## ⚠ THE ONE THAT ACTUALLY BITES. `VersusArena.free_play` is a STATIC: it outlives
## the node, the scene and the scene change. Leaving free play without clearing it
## hands the versus duel and every capture tool an arena that builds one hero and no
## opponent — a silent failure two scenes away from its cause.
func _test_static_cleared_on_exit() -> void:
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script == null or _free == null:
		return
	_expect(bool(arena_script.get("free_play")),
		"the static is set while free play is live")
	_free.free()          # immediate, so _exit_tree runs before the assertion below
	_free = null
	_arena = null
	_expect(not bool(arena_script.get("free_play")),
		"leaving free play CLEARS VersusArena.free_play")
	_completes("static_cleared_on_exit")


## ...and with the static clear, the arena is back to being a duel by default. This
## is the regression half of the test above: it asserts the state the rest of the
## game depends on, not merely that one flag went false.
func _test_duel_still_default() -> void:
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script == null:
		return
	_expect(not bool(arena_script.get("free_play")), "free_play is off")
	_expect(int(arena_script.get("showcase_a")) < 0,
		"showcase is off, so `_is_duel()` is true — the shipped default")
	_completes("duel_still_default")


# ==========================================================================

## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort survives the abort.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Property existence by NAME, off the property list — `Object.get` on a missing
## member returns null, which is indistinguishable from a member that is legitimately
## null.
func _has_prop(obj: Object, name: String) -> bool:
	for p: Dictionary in obj.get_property_list():
		if String(p.get("name", "")) == name:
			return true
	return false


func _find_arena(node: Node) -> Node:
	for child: Node in node.get_children():
		if child.has_method("free_hero"):
			return child
	return null
