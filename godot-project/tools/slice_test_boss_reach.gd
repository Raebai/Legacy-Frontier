# Run: godot --headless --path godot-project --script tools/slice_test_boss_reach.gd
#
# CAN A BOSS ANSWER HIGH GROUND? The suite for the safe-spot fix.
#
# Maker: "I really want the bosses to also be able to jump move around damage from
# wherever no way to just smurf them by sitting high up like make some of them able
# to fly for example and stuff."
#
# `tools/probe_boss_reach.gd` MEASURED what was true before a line was changed: the
# guardian did leap (apex 267 px, higher than the ledge) but the walk drive
# overwrote `velocity.x` every frame, so the solved ballistic horizontal was thrown
# away and the body pogoed under the ledge — 113 airborne frames producing 99 px of
# travel. This suite locks the repair in.
#
# ── WHAT EACH TEST WOULD LOOK LIKE IF THE FIX WERE REMOVED ────────────────────
# Verified by actually removing it, not by reasoning:
#   * `a_grounded_boss_lands_on_the_ledge` — `perch_frames` falls to 0 and the boss
#     ends on the floor. This is the test that goes RED.
#   * `a_flier_holds_the_heros_own_height` — the Illuminator rests on the floor.
#   * the three pure tests fail on their own predicates.
#
# ── VACUOUS-PASS ARMOUR (the house idiom, see tools/slice_test_boss.gd) ────────
# A dead member read is not a failure in GDScript: it logs, ABORTS the enclosing
# function and hands back a zero value. So every test records that it reached its own
# last line, and a sweep at the end fails BY ABSENCE.
#
# NOTE: everything boss-specific is reached by NAME (.get/.call), never `is Boss`, so
# this script carries no compile-time dependency on Boss.gd and its spell chain — the
# same reason slice_test_boss.gd does it.
extends SceneTree

const ENC: String = "res://scripts/combat/Encounter.gd"
const GS: String = "res://scripts/GameState.gd"
const WALL_THICKNESS: float = 16.0
## A third-tier FloorGen ledge sits roughly this far above the ground plane. Chosen
## to be inside `Enemy.LEAP_MAX_HEIGHT` (340) — the point of the test is the arc, not
## whether an unreachable height is unreachable.
const LEDGE_RISE: float = 250.0
## Long enough for a guardian to walk under the ledge, commit a leap and settle. The
## probe lands it well inside this.
const FRAMES: int = 420
## Frames a flier is allowed to still read as grounded after its intro ends, because
## `is_on_floor()` reports the previous frame's contact. Measured: it is one.
const LIFTOFF_FRAMES: int = 3

const TESTS: Array[String] = [
	"the_roster_names_which_artists_fly",
	"high_ground_is_detected_from_the_hero_alone",
	"a_stranded_boss_drops_the_moves_that_cannot_arrive",
	"a_grounded_boss_lands_on_the_ledge",
	"a_flier_holds_the_heros_own_height",
]

var _failed: int = 0
var _completed: Dictionary = {}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	the_roster_names_which_artists_fly()
	high_ground_is_detected_from_the_hero_alone()
	a_stranded_boss_drops_the_moves_that_cannot_arrive()
	await a_grounded_boss_lands_on_the_ledge()
	await process_frame
	await process_frame
	await a_flier_holds_the_heros_own_height()
	for t: String in TESTS:
		if not _completed.has(t):
			printerr("FAIL: ", t, " never reached its last line (it aborted)")
			_failed += 1
	if _failed == 0:
		print("Boss reach tests: all PASS")
	else:
		print("Boss reach tests: %d FAILED" % _failed)
	quit(1 if _failed > 0 else 0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_failed += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ───────────────────────────────────────────────────────────── the pure tests
## The roster is where "which bosses fly" is answered. Two things matter: that the
## column exists and disagrees between rows (a table that says the same thing about
## everything is not an identity column), and that the TITLE join works — that is the
## only handle a live boss node has on its own row.
func the_roster_names_which_artists_fly() -> void:
	var flying: Array[String] = []
	var grounded: Array[String] = []
	for id: String in BossRoster.ids():
		if BossRoster.flies(id):
			flying.append(id)
		else:
			grounded.append(id)
	_expect(not flying.is_empty(), "at least one artist on the roster flies")
	_expect(not grounded.is_empty(), "at least one artist on the roster does not")
	# The two the fiction picked. Named rather than counted: a future row must not be
	# able to satisfy "some of them fly" while silently grounding the Illuminator.
	_expect(BossRoster.flies(BossRoster.ILLUMINATOR), "the Illuminator flies")
	_expect(BossRoster.flies(BossRoster.CARTOGRAPHER), "the Cartographer flies")
	_expect(not BossRoster.flies(BossRoster.GUARDIAN), "the stone colossus does not fly")
	_expect(not BossRoster.flies(BossRoster.ETCHER),
		"the Etcher stays grounded so its breakable wind-up stays reachable")
	# THE JOIN. `Boss.boss_flies()` looks its row up by display name, so every row's
	# name must round-trip. A rename that broke this would silently ground a flier.
	for id2: String in BossRoster.ids():
		_expect(BossRoster.flies_for_title(BossRoster.display_name(id2)) == BossRoster.flies(id2),
			"'%s' answers the same by title as by id" % id2)
	_expect(not BossRoster.flies_for_title("A BOSS THAT IS NOT ON THE ROSTER"),
		"an unknown title degrades to grounded rather than aborting")
	_completes("the_roster_names_which_artists_fly")


## `_is_high_ground` is pure on purpose — the floor check is deliberately OUTSIDE it,
## the same idiom as `Enemy._wants_chase_jump`, so it can be driven by moving two
## nodes with no stepped physics and no room.
func high_ground_is_detected_from_the_hero_alone() -> void:
	var boss: Node2D = _bare_boss()
	if boss == null:
		return
	var hero := Node2D.new()
	hero.add_to_group("hero")
	root.add_child(hero)
	boss.set("_hero", hero)

	boss.global_position = Vector2(0.0, 0.0)
	hero.global_position = Vector2(0.0, 0.0)
	_expect(not bool(boss.call("_is_high_ground")), "level ground is not high ground")

	hero.global_position = Vector2(0.0, -40.0)   # a hop's worth up
	_expect(not bool(boss.call("_is_high_ground")),
		"a hop's worth above is not high ground (a plain jump answers it)")

	hero.global_position = Vector2(0.0, -250.0)  # a third-tier ledge
	_expect(bool(boss.call("_is_high_ground")), "a ledge overhead IS high ground")

	hero.global_position = Vector2(0.0, 250.0)   # hero BELOW
	_expect(not bool(boss.call("_is_high_ground")),
		"a hero below is never high ground")

	# ...and a boss with nobody to fight is not stranded, it is idle.
	boss.set("_hero", null)
	_expect(not bool(boss.call("_is_high_ground")), "no hero -> no high ground")

	hero.free()
	boss.free()
	_completes("high_ground_is_detected_from_the_hero_alone")


## While the hero is camped up there, the moves that plant on the FLOOR or detonate
## on the boss's own body are a turn thrown away. The filter drops those and keeps
## everything else — including every id it has never heard of, which is every
## subclass's whole kit.
func a_stranded_boss_drops_the_moves_that_cannot_arrive() -> void:
	var boss: Node2D = _bare_boss()
	if boss == null:
		return
	var kept: Array = boss.call("_reaching_attack_ids",
		["slam", "pillars", "beam", "summon", "nova", "meteor"])
	_expect(not kept.has("pillars"), "pillars plant on the floor and are dropped")
	_expect(not kept.has("summon"), "adds cannot climb and are dropped")
	_expect(not kept.has("nova"), "a nova on the boss's own body is dropped")
	_expect(kept.has("slam"), "the slam lands at the hero and is kept")
	_expect(kept.has("meteor"), "meteors fall on the hero and are kept")
	_expect(kept.has("beam"), "the beam can aim up now and is kept")

	# An artist whose ids this base has never seen keeps its ENTIRE kit. A filter that
	# deleted what it did not recognise would silently mute five of six bosses.
	var foreign: Array = ["straightedge", "compass", "lattice"]
	_expect(boss.call("_reaching_attack_ids", foreign).size() == foreign.size(),
		"unknown subclass attack ids are all kept")

	# ...and a phase that is ENTIRELY ground-locked still takes its turn rather than
	# standing there in silence.
	var all_locked: Array = ["pillars", "summon", "nova"]
	_expect(boss.call("_reaching_attack_ids", all_locked).size() == all_locked.size(),
		"a wholly ground-locked phase falls back to its own list instead of emptying")
	boss.free()
	_completes("a_stranded_boss_drops_the_moves_that_cannot_arrive")


# ─────────────────────────────────────────────────────── the physical tests
## THE ONE THAT WOULD HAVE CAUGHT THE BUG. A real guardian, a real room, one ledge
## 250 px up with a hero on it. `Enemy.compute_leap_velocity` solves a horizontal
## that LANDS ON the target; the walk drive used to overwrite it the next frame, so
## the body rose and came straight back down. This asserts it ends up standing at or
## above the ledge's surface — which it cannot do by rising alone.
func a_grounded_boss_lands_on_the_ledge() -> void:
	var room: Vector2 = _room()
	var ground: float = room.y - WALL_THICKNESS * 0.5
	var ledge_y: float = ground - LEDGE_RISE
	var arena := Node2D.new()
	root.add_child(arena)
	_build_walls(arena, room)
	_static_box(arena, Vector2(room.x * 0.5, ledge_y + 8.0), Vector2(200.0, 16.0))

	var hero := Node2D.new()
	hero.add_to_group("hero")
	hero.position = Vector2(room.x * 0.5, ledge_y - 24.0)
	arena.add_child(hero)

	var boss: Node2D = _spawn(arena, BossRoster.GUARDIAN)
	if boss == null:
		arena.queue_free()
		return

	var perched: int = 0
	var air_dx: float = 0.0
	var last_x: float = boss.position.x
	for i: int in FRAMES:
		await physics_frame
		if not is_instance_valid(boss):
			break
		if bool(boss.call("is_on_floor")):
			if boss.position.y < ledge_y:
				perched += 1
		else:
			air_dx += absf(boss.position.x - last_x)
		last_x = boss.position.x
	if not is_instance_valid(boss):
		_expect(false, "the guardian survived the measurement")
		arena.queue_free()
		return

	# The pogo signature: airborne frames that produce almost no travel. The measured
	# broken value was 99 px over the whole run; the repaired one was 275.
	_expect(air_dx > 180.0,
		"a committed leap keeps its solved horizontal (travelled %.1f px airborne)" % air_dx)
	_expect(perched > 0,
		"the guardian actually STANDS on the ledge (perched %d frames, final y %.1f, ledge %.1f)"
			% [perched, boss.position.y, ledge_y])
	arena.queue_free()
	_completes("a_grounded_boss_lands_on_the_ledge")


## SOME OF THEM FLY. The Illuminator, spawned through the shipped `Encounter` path,
## with the hero on a ledge it would have to leap to. It never touches the floor once
## the fight starts, and it climbs to the hero's own height rather than milling below.
func a_flier_holds_the_heros_own_height() -> void:
	var room: Vector2 = _room()
	var ground: float = room.y - WALL_THICKNESS * 0.5
	var ledge_y: float = ground - LEDGE_RISE
	var arena := Node2D.new()
	root.add_child(arena)
	_build_walls(arena, room)
	_static_box(arena, Vector2(room.x * 0.5, ledge_y + 8.0), Vector2(200.0, 16.0))

	var hero := Node2D.new()
	hero.add_to_group("hero")
	hero.position = Vector2(room.x * 0.5, ledge_y - 24.0)
	arena.add_child(hero)

	var boss: Node2D = _spawn(arena, BossRoster.ILLUMINATOR)
	if boss == null:
		arena.queue_free()
		return
	_expect(bool(boss.get("_flying")), "the Illuminator's body is a flying one")

	var best_dy: float = 1.0e9
	var grounded_in_fight: int = 0
	var fight_frames: int = 0
	for i: int in FRAMES:
		await physics_frame
		if not is_instance_valid(boss):
			break
		# Skip the intro: a flier stands through its own name card and lifts off with
		# P1, which is the readable transition. Only the FIGHT is being measured.
		if int(boss.call("current_phase")) < 1:
			continue
		fight_frames += 1
		# ...and skip the LIFTOFF. `is_on_floor()` reports the PREVIOUS frame's slide
		# contact, so the first fight frame still reads grounded from the intro pose it
		# was standing in — measured, it is exactly one frame. Asserting on it would be
		# asserting that a body teleports off the ground, which is not the claim; the
		# claim is that it does not REST there.
		if fight_frames <= LIFTOFF_FRAMES:
			continue
		best_dy = minf(best_dy, absf(boss.position.y - hero.position.y))
		if bool(boss.call("is_on_floor")):
			grounded_in_fight += 1
	if not is_instance_valid(boss):
		_expect(false, "the Illuminator survived the measurement")
		arena.queue_free()
		return

	_expect(grounded_in_fight == 0,
		"a flier never rests on the floor once the fight starts (%d frames grounded)"
			% grounded_in_fight)
	# FLY_ABOVE is 34, so it settles just over the hero's line. The tolerance is the
	# ease-in, not a licence to hover a screen away.
	_expect(best_dy < 80.0,
		"the flier reaches the hero's own height (closest %.1f px on y)" % best_dy)
	# ...and it stays in shot. Base viewport is 640x360 and `aspect="expand"` only
	# ever widens, so the vertical half-frame is the tight axis.
	_expect(absf(boss.position.y - hero.position.y) < 180.0,
		"the flier stays inside the framing camera's vertical half-shot")
	arena.queue_free()
	_completes("a_flier_holds_the_heros_own_height")


# ------------------------------------------------------------------- utilities
func _room() -> Vector2:
	var gs_script: GDScript = load(GS) as GDScript
	return (gs_script.default_layout() as Resource).room_size


## A boss with no room and no encounter, for driving the PURE predicates. It is
## `free()`d rather than `queue_free()`d by every caller so the next test's `_ready`
## cannot latch onto a corpse-to-be still sitting in group "hero"/"enemy".
func _bare_boss() -> Node2D:
	var scene: PackedScene = load(BossRoster.scene_path(BossRoster.GUARDIAN)) as PackedScene
	if scene == null:
		_expect(false, "the guardian scene loads")
		return null
	var b: Node2D = scene.instantiate() as Node2D
	root.add_child(b)
	return b


## Spawn through the SHIPPED path, so the position, scale, speed and roster wiring
## are the game's and not this file's invention.
func _spawn(arena: Node2D, boss_id: String) -> Node2D:
	var gs_script: GDScript = load(GS) as GDScript
	var enc_script: GDScript = load(ENC) as GDScript
	var layout: Resource = gs_script.default_layout()
	var enc: Node = enc_script.new()
	arena.add_child(enc)
	enc.configure(layout.spawn_rect_min, layout.spawn_rect_max, layout.min_spawn_dist_from_hero)
	enc.configure_places(layout)
	var b: Node2D = enc.spawn_boss(1.0, 1.0, boss_id) as Node2D
	if b == null:
		_expect(false, "'%s' spawned" % boss_id)
	return b


func _build_walls(arena: Node2D, room: Vector2) -> void:
	_static_box(arena, Vector2(room.x * 0.5, room.y - WALL_THICKNESS * 0.5),
		Vector2(room.x, WALL_THICKNESS))
	_static_box(arena, Vector2(room.x * 0.5, WALL_THICKNESS * 0.5),
		Vector2(room.x, WALL_THICKNESS))
	_static_box(arena, Vector2(WALL_THICKNESS * 0.5, room.y * 0.5),
		Vector2(WALL_THICKNESS, room.y))
	_static_box(arena, Vector2(room.x - WALL_THICKNESS * 0.5, room.y * 0.5),
		Vector2(WALL_THICKNESS, room.y))


func _static_box(parent: Node2D, at: Vector2, size: Vector2) -> void:
	var b := StaticBody2D.new()
	b.position = at
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	b.add_child(cs)
	parent.add_child(b)
