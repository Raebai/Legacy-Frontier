# NINE CLASSES, NINE MOVEMENT VERBS — and a stat table that is not nine copies of 100.
#
# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#          --script tools/slice_test_class_movement.gd
#
# THE MAKER'S RULING: "we cannot have any recolours — I want all the classes to be
# different and unique and not similar at all." The thing that was actually identical
# was HOW THEY MOVE: `SPEED`, `DASH_SPEED` and `JUMP_VELOCITY` were global, there was no
# `hp` key in `CLASS_CONFIG` at all, and five of the nine had byte-identical melee. This
# suite is the pin on all three.
#
# ⚠ THE HEADLINE ASSERTION IS DESIGNED TO FAIL ON THE PRE-CHANGE CODE, and that is how
# it earns its keep. `verbs_are_all_distinct` reads `Hero.movement_verb_name()`, which
# resolves `_cfg.get("move_verb", "dash")`. Before the change no class carries the key,
# so all nine answer "dash" — 1 unique value out of 9, and the test reports exactly
# that. Verified by `git stash`: the suite fails 1 assertion on HEAD~ and passes here.
#
# ⚠ ASSERT THE OBSERVABLE CHANNEL, NOT THE INTENDED ONE. Distance is not read off the
# constants; a real `Hero` is instanced into a real tree with a real floor, `_start_dash`
# is pressed, physics is stepped until the travel ends, and the DISPLACEMENT is
# measured. A config table that says "520" while the body moves 60 px would pass a
# config test and fail this one. (The standing lesson from the walk bug: three fixes
# survived because the tests read what the gait INTENDED while the sim smeared what
# actually rendered.)
#
# ⚠ NON-VACUOUSNESS. "No teleport ever landed illegally" is trivially true of a
# teleport that never happens, so every legality sweep COUNTS what it performed and
# fails at zero, and every verb must clear a real minimum displacement — a movement
# button that does nothing would otherwise satisfy most of this file.
#
# ⚠ TEST IDIOM (full write-up in tools/slice_test_loadout.gd). A dead member read
# ABORTS the enclosing function and hands the caller the type's zero, which the
# `failed += _test_x()` idiom reads as "no failures" — it silently disabled 64 suites
# once. So failures accumulate on the MEMBER `_fails`, and every test's last line
# records a COMPLETION SENTINEL. A test missing from `_completed` fails BY ABSENCE,
# whichever member moved house, with nobody having to predict it in advance.
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

## Every test that must run to completion. A name missing from `_completed` at the end
## means that test aborted part-way.
const TESTS: Array[String] = [
	"verbs_are_all_distinct",
	"every_verb_is_reachable_from_the_dash_button",
	"travel_is_measurably_different",
	"grounded_verbs_stay_on_the_ground_plane",
	"iframes_are_a_per_class_decision",
	"teleport_verbs_always_land_legally",
	"no_thrall_degrades_safely",
	"thrall_swap_trades_places",
	"stat_table_has_no_duplicates",
	"class_hp_composes_with_gear",
	"melee_profiles_are_all_distinct",
	"level_growth_actually_moves_the_stats",
]

## Hero members reached DYNAMICALLY (Hero.gd has no class_name, so every `hero.max_hp`
## is a runtime lookup). Listed once so a relocation is NAMED rather than merely
## caught by the sentinel.
const HERO_MEMBERS: Array[String] = [
	"hp", "max_hp", "is_dashing", "velocity", "facing",
	"_aim_dir", "_move_dir", "_dash_cooldown_timer", "_dash_verb",
	"_melee_cd", "_melee_damage", "_melee_range", "_melee_knockback", "_melee_arc_dot",
	"_base_max_hp", "_surge_armor_timer",   # `_recall_timer` deleted with the Arcanist recall
]
const HERO_METHODS: Array[String] = [
	"configure_class", "movement_verb_name", "movement_verb_distance",
	"movement_verb_iframe_fraction", "set_loadout", "_start_dash", "_dash_invulnerable",
	"_class_speed",
]
## Stand-in for another agent's minion; see the header of that file for why the swap
## test cannot use a bare Node2D.
const THRALL_STUB_PATH: String = "res://tools/_thrall_stub.gd"

const CLASS_COUNT: int = 9
const CLASS_LABELS: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut",
	"Cleric", "Cryomancer", "Stormcaller", "Warlock", "Swordsaint",
]
## Indices, named so an assertion reads as a claim about a CLASS rather than about a 6.
const ARCANIST: int = 0
const SHADOWBLADE: int = 1
const BRAWLER: int = 2
const JUGGERNAUT: int = 3
const CLERIC: int = 4
const CRYOMANCER: int = 5
const STORMCALLER: int = 6
const WARLOCK: int = 7
const SWORDSAINT: int = 8

## The floor the measurement rig stands on. Wide enough that no verb in the roster can
## run off the end of it (the longest travel is the Stormcaller's 260 px teleport).
const FLOOR_W: float = 2400.0
const FLOOR_Y: float = 400.0
const START_X: float = 600.0
## A hero is 18 px tall in Hero.tscn; park it just above the floor plate.
const START_Y: float = FLOOR_Y - 10.0
## The travel loop's runaway guard. The longest verb is the 0.55 s ice slide = 33
## physics ticks at 60 Hz; 240 is ~4 s and is only ever reached by a bug.
const TRAVEL_FRAME_CAP: int = 240
## Nobody's movement button may be a no-op. Comfortably under the shortest real verb
## (the Juggernaut surge, ~99 px) and comfortably over Hero.BLINK_MIN_TRAVEL.
const MIN_USEFUL_TRAVEL: float = 40.0

## The walled room the teleport-legality sweep runs inside, built the way
## `Arena._apply_room_size` builds one: four full-span walls CENTRED on the edges.
const ROOM_W: float = 960.0
const ROOM_H: float = 480.0
const WALL_T: float = 16.0
const HERO_HALF: float = 9.0

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _floor: StaticBody2D = null
var _room: Node2D = null
## Non-vacuousness counters — see the header.
var _teleports_performed: int = 0


## ⚠ ALWAYS returns false. In a SceneTree script a `true` return QUITS the main loop,
## and `_run()` is async (it must await physics frames before any body has moved or any
## shape query sees the room). Returning true would tear the tree down before the first
## await resumed and the suite would exit 0 having printed neither PASS nor FAIL — a
## green run that tested nothing. `_run()` ends the process itself.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


## ⚠ PIN THE CLIMBER AT LEVEL 1, OR THIS SUITE TESTS THE TESTER'S SAVE FILE.
##
## Hero stats compose LEVEL GROWTH (`Progression`) on top of the class table, and
## `GameState._ready` loads the real `user://climber.json` — whose node IS on the
## tree under `--script`, even though the autoload IDENTIFIER is not. So on any
## machine whose owner has actually played, every stat below silently drifts by
## their level.
##
## This cost a debugging cycle when it first bit: the suite went red with
## "max_hp == its own base (148 vs 145)" on a save carrying 123 xp, i.e. a level-2
## Juggernaut. The dangerous half is not the red — it is that the suite would have
## gone GREEN again the moment the save was reset, so a genuine class-table
## regression could hide behind whatever level the tester happened to be.
##
## The CLASS TABLE is what is under test here, so the level is pinned to the one
## value at which growth is exactly the identity. Growth's own behaviour is
## asserted separately, by `_test_level_growth_actually_moves_the_stats` below and
## by `tools/slice_test_progression.gd`.
func _pin_level_one() -> void:
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs == null:
		return
	gs.set("_xp", 0)
	if gs.has_method("clear_party_level"):
		gs.call("clear_party_level")


func _run() -> void:
	_pin_level_one()
	_build_floor()
	await physics_frame
	await physics_frame

	await _test_verbs_are_all_distinct()
	await _test_every_verb_is_reachable_from_the_dash_button()
	await _test_travel_is_measurably_different()
	await _test_grounded_verbs_stay_on_the_ground_plane()
	await _test_iframes_are_a_per_class_decision()
	await _test_teleport_verbs_always_land_legally()
	await _test_no_thrall_degrades_safely()
	await _test_thrall_swap_trades_places()
	await _test_stat_table_has_no_duplicates()
	await _test_class_hp_composes_with_gear()
	await _test_melee_profiles_are_all_distinct()
	await _test_level_growth_actually_moves_the_stats()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Class movement tests: %d FAILED" % _fails)
		quit(1)
		return
	print("Class movement tests: all PASS")
	quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------- the rig
func _build_floor() -> void:
	_floor = StaticBody2D.new()
	_floor.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(FLOOR_W, 40.0)
	cs.shape = rect
	_floor.add_child(cs)
	_floor.global_position = Vector2(START_X, FLOOR_Y + 20.0)
	root.add_child(_floor)


## A minion standing in for another agent's, built to the PUBLISHED CONTRACT and
## nothing else: the group, the owner meta, and the liveness fields.
func _make_thrall(owner_hero: Node, at: Vector2) -> Node2D:
	var t := Node2D.new()
	t.set_script(load(THRALL_STUB_PATH))
	t.add_to_group(&"thrall")
	t.set_meta(&"thrall_owner", owner_hero)
	root.add_child(t)
	t.global_position = at
	return t


func _make_hero(cls: int) -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.call("configure_class", cls)
	return hero


## Assert the dynamically-reached members and methods are all still THERE, by name.
## The completion sentinel already catches a relocation; this says WHICH one moved.
func _require_surface(hero: Object) -> void:
	if hero == null:
		_expect(false, "Hero exists (cannot check its surface)")
		return
	var present: Dictionary = {}
	for p: Dictionary in hero.get_property_list():
		present[String(p["name"])] = true
	for n: String in HERO_MEMBERS:
		_expect(present.has(n),
			"Hero still declares `%s` (moved or renamed — assertions reading it are dead)" % n)
	for m: String in HERO_METHODS:
		_expect(hero.has_method(m),
			"Hero still has method `%s()` (renamed — assertions calling it are dead)" % m)


## Park a hero at the start mark, pointing RIGHT, at rest and off cooldown.
##
## `_aim_dir` is set LAST and the press happens in the same synchronous block, because
## `_physics_process` re-resolves aim from the mouse every tick and a headless mouse
## sits at the origin — a teleport measured a frame later would fire toward (0, 0).
func _park(hero: CharacterBody2D) -> void:
	hero.global_position = Vector2(START_X, START_Y)
	hero.set("velocity", Vector2.ZERO)
	hero.set("facing", Vector2.RIGHT)
	hero.set("_move_dir", Vector2.RIGHT)
	hero.set("_dash_cooldown_timer", 0.0)
	hero.set("_aim_dir", Vector2.RIGHT)


## Press the movement button and return the DISPLACEMENT it produced — measured off
## `global_position`, which is the channel the player actually sees, not off the config
## the press was supposed to read.
func _press_move(hero: CharacterBody2D) -> Vector2:
	_park(hero)
	await physics_frame
	_park(hero)  # a physics tick may have applied gravity; re-seat before the press
	var start: Vector2 = hero.global_position
	hero.call("_start_dash")
	var guard: int = 0
	while bool(hero.get("is_dashing")) and guard < TRAVEL_FRAME_CAP:
		await physics_frame
		guard += 1
	_expect(guard < TRAVEL_FRAME_CAP,
		"a movement verb ended inside %d physics frames (it never released the body)"
			% TRAVEL_FRAME_CAP)
	return hero.global_position - start


# ------------------------------------------------------------------- 1. THE VERBS
## THE HEADLINE. Nine classes, nine verbs, no two the same. This is the assertion that
## fails on the pre-change code (no `move_verb` key anywhere -> all nine answer "dash").
func _test_verbs_are_all_distinct() -> void:
	var hero: CharacterBody2D = _make_hero(0)
	_require_surface(hero)
	var seen: Dictionary = {}
	var verbs: Array[String] = []
	for cls: int in CLASS_COUNT:
		hero.call("configure_class", cls)
		var v: String = String(hero.call("movement_verb_name"))
		verbs.append(v)
		_expect(v != "" and v != "dash",
			"%s has a movement verb of its own (got '%s' — the shared-dash fallback means the class table forgot the key)"
				% [CLASS_LABELS[cls], v])
		_expect(not seen.has(v),
			"%s's verb '%s' is unique (also used by %s — this is the recolour the ruling forbids)"
				% [CLASS_LABELS[cls], v, String(seen.get(v, "?"))])
		seen[v] = CLASS_LABELS[cls]
	_expect(seen.size() == CLASS_COUNT,
		"all %d classes have a distinct movement verb (got %d unique across %s)"
			% [CLASS_COUNT, seen.size(), str(verbs)])
	hero.queue_free()
	await physics_frame
	_completes("verbs_are_all_distinct")


## MOBILE-FIRST (D-011). `TouchControls` ships exactly ONE movement button and its
## action is `dash`; `blast`, `blink` and `nova` have no touch affordance at all (its
## own header calls that a live design consequence). So a verb reachable only from a
## key the pad does not draw would be desktop-only. This asserts the pad still carries
## the button, and that the button is the one the buffer dispatches — i.e. every one of
## the nine is on a phone by construction rather than by hope.
func _test_every_verb_is_reachable_from_the_dash_button() -> void:
	_expect(InputMap.has_action(&"dash"), "the `dash` action exists in the input map")
	var pad := TouchControls.new()
	var found: bool = false
	for row: Dictionary in pad.call("_button_layout"):
		if String(row.get("action", "")) == "dash":
			found = true
	_expect(found,
		"TouchControls still draws a button bound to `dash` — it is the ONLY movement button on the pad, so losing it makes all nine verbs unreachable on a phone")
	pad.free()
	# ...and the button routes to the dispatcher. `BUFFERED_ACTIONS` is the list the
	# press path consumes; a verb behind an action missing from it would never fire.
	# Read out of the script CONSTANT MAP, not with `get()` — a GDScript const is not a
	# property, so `hero.get("BUFFERED_ACTIONS")` would answer null and the assertion
	# would fail for a reason that has nothing to do with the claim.
	var hero: CharacterBody2D = _make_hero(0)
	var consts: Dictionary = hero.get_script().get_script_constant_map()
	var buffered: Variant = consts.get("BUFFERED_ACTIONS")
	_expect(buffered is Array and (buffered as Array).has(&"dash"),
		"Hero.BUFFERED_ACTIONS still carries `dash` (the press path that reaches _start_dash)")
	hero.queue_free()
	await physics_frame
	_completes("every_verb_is_reachable_from_the_dash_button")


# --------------------------------------------------------------- 2. THE TRAVEL
## Measured, not declared. Nine presses, nine displacements, and they must not be nine
## copies of the same number.
func _test_travel_is_measurably_different() -> void:
	var hero: CharacterBody2D = _make_hero(0)
	var dist: Array[float] = []
	for cls: int in CLASS_COUNT:
		hero.call("configure_class", cls)
		var d: Vector2 = await _press_move(hero)
		var travel: float = absf(d.x)
		dist.append(travel)
		_expect(travel >= MIN_USEFUL_TRAVEL,
			"%s's movement button actually moves the body (measured %.1f px, floor is %.0f — a dead button is the failure mode this catches)"
				% [CLASS_LABELS[cls], travel, MIN_USEFUL_TRAVEL])
	# Distinctness on the DRAWN channel: bucket to 4 px so float noise cannot fake a
	# difference, then demand nearly all nine buckets are their own.
	var buckets: Dictionary = {}
	for t: float in dist:
		buckets[int(round(t / 4.0))] = true
	_expect(buckets.size() >= 7,
		"at least 7 of the 9 classes travel a visibly different distance (got %d distinct 4px buckets across %s)"
			% [buckets.size(), str(dist)])
	# The two the maker named by hand, as an ordering claim rather than a magic number:
	# "the lightning one ... blinks ... a slightly longer distance", and the tank is the
	# one that gives mobility up.
	# ⚠ THE `* 2.0` IS GONE, AND IT WAS OVERRULED RATHER THAN RELAXED. Maker: *"make
	# juggernaut better like make it be able to dash up and faster and further"*. The
	# surge was 99 px — the shortest verb in the roster, on the slowest body in it — and
	# is now 146. The ORDERING claim the maker actually made ("the lightning one blinks
	# a slightly longer distance") is what survives; the doubling was this test's own
	# reading of "the tank gives mobility up", and the tank has now been told not to.
	_expect(dist[STORMCALLER] > dist[JUGGERNAUT],
		"the Stormcaller's lightning blink still out-ranges the Juggernaut's surge (%.1f vs %.1f)"
			% [dist[STORMCALLER], dist[JUGGERNAUT]])
	_expect(dist[STORMCALLER] > dist[SWORDSAINT],
		"the Stormcaller out-ranges the Swordsaint's committed step (%.1f vs %.1f)"
			% [dist[STORMCALLER], dist[SWORDSAINT]])
	# ...and the published estimate the BOTS size their gap-closes with must agree with
	# what the body actually did, or every bot plans with the Arcanist's numbers.
	for cls: int in CLASS_COUNT:
		hero.call("configure_class", cls)
		var claimed: float = float(hero.call("movement_verb_distance"))
		_expect(claimed > 0.0 and absf(claimed - dist[cls]) <= maxf(40.0, dist[cls] * 0.5),
			"%s's published movement_verb_distance (%.1f) is in the right ballpark as the measured travel (%.1f) — the bots size gap-closes with it"
				% [CLASS_LABELS[cls], claimed, dist[cls]])
	hero.queue_free()
	await physics_frame
	_completes("travel_is_measurably_different")


## ⚠ THE RULING REVERSED, AND THIS TEST NOW ASSERTS THE OPPOSITE OF ITS OLD SELF.
## `charge` / `surge` / `ice_slide` used to flatten to horizontal whatever the stick
## said — a shoulder charge aimed at the sky is a strange shoulder charge. Maker, on
## the Cryomancer: "why can't cryomancer dash upwards, please fix — and remove that
## weird dash thing it does where it goes sideways." The Ice Slide was one of the
## three, so up-right came out as a flat skid to the right.
##
## EVERY class travels along the movement vector now, and this is where that is
## pinned: `Hero.GROUNDED_VERBS` is empty, and if anything ever puts a verb back into
## it without a new ruling, this goes red rather than a class quietly losing its
## vertical again.
func _test_grounded_verbs_stay_on_the_ground_plane() -> void:
	var hero: CharacterBody2D = _make_hero(0)
	for cls: int in [BRAWLER, JUGGERNAUT, CRYOMANCER]:
		hero.call("configure_class", cls)
		_park(hero)
		await physics_frame
		_park(hero)
		hero.set("_move_dir", Vector2(0.6, -0.8).normalized())  # aimed steeply UP
		hero.call("_start_dash")
		var dir: Vector2 = hero.get("_dash_dir")
		_expect(absf(dir.y) > 0.5,
			"%s keeps its vertical when aimed up — no verb is flattened now (got %s)"
				% [CLASS_LABELS[cls], str(dir)])
		var guard: int = 0
		while bool(hero.get("is_dashing")) and guard < TRAVEL_FRAME_CAP:
			await physics_frame
			guard += 1
	# The Shadowblade, which never flattened, is unchanged — the contrast this test
	# used to draw is now the rule, and it is kept as a regression on the air dash.
	hero.call("configure_class", SHADOWBLADE)
	_park(hero)
	await physics_frame
	_park(hero)
	hero.set("_move_dir", Vector2(0.6, -0.8).normalized())
	hero.call("_start_dash")
	var air_dir: Vector2 = hero.get("_dash_dir")
	_expect(absf(air_dir.y) > 0.3,
		"the Shadowblade's air dash keeps its vertical angle (got %s) — it is the one verb that flies"
			% str(air_dir))
	var g2: int = 0
	while bool(hero.get("is_dashing")) and g2 < TRAVEL_FRAME_CAP:
		await physics_frame
		g2 += 1
	hero.queue_free()
	await physics_frame
	_completes("grounded_verbs_stay_on_the_ground_plane")


## I-frames are now a DECISION per class rather than a side effect of one shared code
## path. Two verbs deliberately have none: pressing them is a commitment.
func _test_iframes_are_a_per_class_decision() -> void:
	var hero: CharacterBody2D = _make_hero(0)
	var fractions: Array[float] = []
	for cls: int in CLASS_COUNT:
		hero.call("configure_class", cls)
		fractions.append(float(hero.call("movement_verb_iframe_fraction")))
	_expect(fractions[BRAWLER] == 0.0,
		"the Brawler's shoulder charge has NO i-frames (got %.2f) — it is a commitment"
			% fractions[BRAWLER])
	_expect(fractions[JUGGERNAUT] == 0.0,
		"the Juggernaut's surge has NO i-frames (got %.2f) — armour is not invulnerability"
			% fractions[JUGGERNAUT])
	_expect(fractions[SHADOWBLADE] > fractions[SWORDSAINT],
		"the Shadowblade dodges more of its verb than the Swordsaint does (%.2f vs %.2f)"
			% [fractions[SHADOWBLADE], fractions[SWORDSAINT]])
	var unique: Dictionary = {}
	for f: float in fractions:
		unique[snappedf(f, 0.01)] = true
	_expect(unique.size() >= 4,
		"the roster spans at least 4 distinct i-frame fractions (got %d across %s)"
			% [unique.size(), str(fractions)])
	# ...and the number is REAL, not just published: press each and read the live gate.
	for cls: int in [BRAWLER, JUGGERNAUT, SHADOWBLADE, ARCANIST]:
		hero.call("configure_class", cls)
		_park(hero)
		await physics_frame
		_park(hero)
		hero.call("_start_dash")
		var invuln: bool = bool(hero.call("_dash_invulnerable"))
		var want: bool = float(hero.call("movement_verb_iframe_fraction")) > 0.0
		_expect(invuln == want,
			"%s is %s at the first frame of its verb, matching its declared fraction"
				% [CLASS_LABELS[cls], "invulnerable" if want else "hittable"])
		var guard: int = 0
		while bool(hero.get("is_dashing")) and guard < TRAVEL_FRAME_CAP:
			await physics_frame
			guard += 1
	hero.queue_free()
	await physics_frame
	_completes("iframes_are_a_per_class_decision")


# ---------------------------------------------------------------- 3. TELEPORTS
## Every verb that TELEPORTS must land somewhere `blink_to`/`_safe_blink_destination`
## approved: not inside a solid, not outside the room. Swept over many aims from many
## spots, INSIDE a real walled room, and the sweep counts what it performed so an
## invariant that only holds because nothing happened cannot pass.
func _test_teleport_verbs_always_land_legally() -> void:
	_build_room()
	await physics_frame
	await physics_frame
	var hero: CharacterBody2D = _make_hero(STORMCALLER)
	# ⚠ THE ARCANIST IS NO LONGER A TELEPORT CLASS. Its verb was RECALL — an outbound
	# step whose SECOND press teleported you back to an anchor — and the maker had it
	# deleted on 2026-08-04 ("get rid of that its just a repeat of blink"). Its verb
	# is now ARCANE PHASE, a travelled step, so it belongs to the travel tests above
	# and has no business in a legality sweep for teleports.
	for cls: int in [STORMCALLER, WARLOCK]:
		hero.call("configure_class", cls)
		for sx: int in 5:
			for sy: int in 3:
				var at := Vector2(
					lerpf(60.0, ROOM_W - 60.0, float(sx) / 4.0),
					lerpf(60.0, ROOM_H - 60.0, float(sy) / 2.0))
				for a: int in 8:
					var ang: float = TAU * float(a) / 8.0
					hero.global_position = at
					hero.set("velocity", Vector2.ZERO)
					hero.set("_dash_cooldown_timer", 0.0)
					hero.set("_move_dir", Vector2(cos(ang), 0.0))
					hero.set("_aim_dir", Vector2(cos(ang), sin(ang)))
					hero.call("_start_dash")
					if bool(hero.get("is_dashing")):
						# Spent the press as a travelled dash rather than a teleport.
						# Legal, and not this sweep's subject — let it finish, move on.
						hero.set("is_dashing", false)
						continue
					var p: Vector2 = hero.global_position
					if at.distance_to(p) < 1.0:
						continue  # REFUSED and refunded — nothing teleported, so it is
						# not evidence either way. Counting it would let the sweep
						# satisfy its own non-vacuousness floor with pure refusals.
					_teleports_performed += 1
					_expect(_inside_room(p),
						"%s's teleport landed inside the room (at %s from %s)"
							% [CLASS_LABELS[cls], str(p), str(at)])
					_expect(not _in_solid(p),
						"%s's teleport did not land inside a collider (at %s from %s)"
							% [CLASS_LABELS[cls], str(p), str(at)])
	_expect(_teleports_performed > 60,
		"the legality sweep actually performed teleports (%d) — an invariant that holds over an empty result set is not an invariant"
			% _teleports_performed)
	hero.queue_free()
	_tear_down_room()
	await physics_frame
	_completes("teleport_verbs_always_land_legally")


# ------------------------------------------------------------- 4. THRALL SWAP
## THE DEGRADATION, pinned. A Warlock who has not summoned anything must still get a
## movement button: a short vetted blink, or a clean refuse-and-refund. What it must
## NEVER do is strand the body, teleport to the origin, or crash.
func _test_no_thrall_degrades_safely() -> void:
	var hero: CharacterBody2D = _make_hero(WARLOCK)
	_expect(get_nodes_in_group(&"thrall").is_empty(),
		"the no-thrall test really has no thralls in the tree")
	for a: int in 8:
		var ang: float = TAU * float(a) / 8.0
		_park(hero)
		await physics_frame
		_park(hero)
		hero.set("_aim_dir", Vector2(cos(ang), sin(ang)))
		var before: Vector2 = hero.global_position
		var cd_before: float = float(hero.get("_dash_cooldown_timer"))
		hero.call("_start_dash")
		var after: Vector2 = hero.global_position
		var moved: float = before.distance_to(after)
		var cd_after: float = float(hero.get("_dash_cooldown_timer"))
		_expect(after.is_finite() and after.length() < 100000.0,
			"a thrall-less swap left the body somewhere real (got %s)" % str(after))
		_expect(not bool(hero.get("is_dashing")),
			"a thrall-less swap resolves instantly rather than leaving the body in a travel state")
		if moved < 1.0:
			# The refusal branch: nothing spent, so it can be re-aimed and pressed again.
			_expect(is_equal_approx(cd_after, cd_before),
				"a REFUSED thrall swap is also REFUNDED (cooldown went %.2f -> %.2f)"
					% [cd_before, cd_after])
		else:
			_expect(moved > 24.0,
				"the thrall-less fallback blink travels a useful distance (%.1f px)" % moved)
			_expect(cd_after > 0.0,
				"a thrall-less swap that DID move charged its cooldown")
	hero.queue_free()
	await physics_frame
	_completes("no_thrall_degrades_safely")


## The contract itself: group `thrall`, meta `thrall_owner` -> the raiser. A stub
## standing in for another agent's minion, because that is exactly what the contract is
## for. Also asserts the negative — somebody ELSE's thrall is not a free taxi.
func _test_thrall_swap_trades_places() -> void:
	var hero: CharacterBody2D = _make_hero(WARLOCK)
	var other: CharacterBody2D = _make_hero(WARLOCK)
	other.global_position = Vector2(START_X - 300.0, START_Y)
	_park(hero)
	await physics_frame
	_park(hero)

	# 1. A thrall owned by SOMEBODY ELSE must be ignored.
	var theirs: Node2D = _make_thrall(other, Vector2(START_X + 240.0, START_Y))
	await physics_frame
	var before_foreign: Vector2 = hero.global_position
	var pin: Vector2 = theirs.global_position
	hero.set("_dash_cooldown_timer", 0.0)
	hero.set("_aim_dir", Vector2.RIGHT)
	hero.call("_start_dash")
	_expect(theirs.global_position.distance_to(pin) < 1.0,
		"another Warlock's thrall is NOT moved by our swap (it moved %.1f px)"
			% theirs.global_position.distance_to(pin))
	_expect(before_foreign.distance_to(hero.global_position) < THRALL_FALLBACK_CEILING,
		"with only a foreign thrall in reach the press degraded to the short fallback, not a swap across the room (travelled %.1f px)"
			% before_foreign.distance_to(hero.global_position))

	# 2. OUR thrall: positions are traded, both ends land legally.
	var mine: Node2D = _make_thrall(hero, Vector2(START_X + 320.0, START_Y))
	_park(hero)
	await physics_frame
	_park(hero)
	var hero_before: Vector2 = hero.global_position
	var thrall_before: Vector2 = hero_before + Vector2(320.0, -40.0)
	mine.global_position = thrall_before
	hero.set("_dash_cooldown_timer", 0.0)
	hero.call("_start_dash")
	_expect(hero.global_position.distance_to(thrall_before) < 8.0,
		"the Warlock arrived where its thrall was (wanted %s, got %s)"
			% [str(thrall_before), str(hero.global_position)])
	_expect(mine.global_position.distance_to(hero_before) < 8.0,
		"the thrall arrived where the Warlock was (wanted %s, got %s)"
			% [str(hero_before), str(mine.global_position)])
	_expect(float(hero.get("_dash_cooldown_timer")) > 0.0,
		"a completed swap charges its cooldown")

	# 3. A DEAD thrall is not a destination.
	_park(hero)
	await physics_frame
	_park(hero)
	mine.global_position = hero.global_position + Vector2(300.0, 0.0)
	mine.set("hp", 0)
	_expect(int(mine.get("hp")) == 0,
		"the dead-thrall fixture really is at 0 hp (a `set()` on an undeclared property is a SILENT no-op — see _thrall_stub.gd)")
	var before_dead: Vector2 = hero.global_position
	hero.set("_dash_cooldown_timer", 0.0)
	hero.call("_start_dash")
	_expect(before_dead.distance_to(hero.global_position) < THRALL_FALLBACK_CEILING,
		"a thrall at 0 hp is not a swap destination (travelled %.1f px, which is a swap not a fallback)"
			% before_dead.distance_to(hero.global_position))

	mine.queue_free()
	theirs.queue_free()
	hero.queue_free()
	other.queue_free()
	await physics_frame
	_completes("thrall_swap_trades_places")


## The longest a NON-swap press may travel. The fallback blink is 115 px and the
## refusal is 0; a real swap in these fixtures is 300+. Derived as "comfortably above
## the fallback, comfortably below the fixture distance" rather than guessed.
const THRALL_FALLBACK_CEILING: float = 160.0


# ------------------------------------------------------------------ 5. THE STATS
## No two classes may have the same body. HP had no key at all before this change and
## every hero in the game was 100.
func _test_stat_table_has_no_duplicates() -> void:
	var hero: CharacterBody2D = _make_hero(0)
	var hps: Dictionary = {}
	var speeds: Dictionary = {}
	var hp_list: Array[int] = []
	var speed_list: Array[float] = []
	for cls: int in CLASS_COUNT:
		hero.call("configure_class", cls)
		var mx: int = int(hero.get("max_hp"))
		var sp: float = float(hero.call("_class_speed"))
		hp_list.append(mx)
		speed_list.append(sp)
		_expect(not hps.has(mx),
			"%s's max HP (%d) is its own (shared with %s)"
				% [CLASS_LABELS[cls], mx, String(hps.get(mx, "?"))])
		_expect(not speeds.has(snappedf(sp, 0.1)),
			"%s's walk speed (%.1f) is its own (shared with %s)"
				% [CLASS_LABELS[cls], sp, String(speeds.get(snappedf(sp, 0.1), "?"))])
		hps[mx] = CLASS_LABELS[cls]
		speeds[snappedf(sp, 0.1)] = CLASS_LABELS[cls]
	_expect(hps.size() == CLASS_COUNT,
		"all %d classes have a distinct max HP (got %d unique across %s)"
			% [CLASS_COUNT, hps.size(), str(hp_list)])
	_expect(speeds.size() == CLASS_COUNT,
		"all %d classes have a distinct walk speed (got %d unique across %s)"
			% [CLASS_COUNT, speeds.size(), str(speed_list)])
	# The shape of the roster, as claims rather than as numbers: the tank is the
	# toughest AND the slowest, the assassin the frailest AND (near) the fastest.
	_expect(hp_list[JUGGERNAUT] == hp_list.max(),
		"the Juggernaut is the toughest body in the roster (%d)" % hp_list[JUGGERNAUT])
	_expect(speed_list[JUGGERNAUT] == speed_list.min(),
		"the Juggernaut is the slowest body in the roster (%.1f)" % speed_list[JUGGERNAUT])
	_expect(hp_list[SHADOWBLADE] == hp_list.min(),
		"the Shadowblade is the frailest body in the roster (%d)" % hp_list[SHADOWBLADE])
	_expect(speed_list[SHADOWBLADE] == speed_list.max(),
		"the Shadowblade is the quickest body in the roster (%.1f)" % speed_list[SHADOWBLADE])
	# ...and the spread stays DEFENSIBLE. This is a co-op brawler; a table where one
	# class is twice the body of another has removed a choice rather than made one.
	_expect(float(hp_list.max()) / float(hp_list.min()) <= 2.0,
		"the HP spread stays inside 2x (got %.2fx — %d to %d)"
			% [float(hp_list.max()) / float(hp_list.min()), hp_list.min(), hp_list.max()])
	_expect(speed_list.max() / speed_list.min() <= 1.6,
		"the speed spread stays inside 1.6x (got %.2fx)"
			% (speed_list.max() / speed_list.min()))
	hero.queue_free()
	await physics_frame
	_completes("stat_table_has_no_duplicates")


## ⚠ THE TRAP THE BRIEF NAMED. `_base_max_hp` is what gear scales FROM. A per-class base
## that gear OVERWRITES (or that gear compounds because the base was seeded from an
## already-scaled value) is the failure this pins: the hat must MULTIPLY the class
## number, and re-applying the same loadout must be idempotent.
func _test_class_hp_composes_with_gear() -> void:
	var hero: CharacterBody2D = _make_hero(JUGGERNAUT)
	var base: int = int(hero.get("max_hp"))
	_expect(base == int(hero.get("_base_max_hp")),
		"a freshly configured class starts with max_hp == its own base (%d vs %d)"
			% [base, int(hero.get("_base_max_hp"))])
	_expect(base > 100,
		"the Juggernaut's base HP comes from its class row, not from BASE_MAX_HP (got %d)" % base)
	hero.call("set_loadout", "head", "hat")
	var geared: int = int(hero.get("max_hp"))
	_expect(geared != base,
		"the HP hat actually changes max HP (%d -> %d)" % [base, geared])
	_expect(int(hero.get("_base_max_hp")) == base,
		"gear did NOT overwrite the class base (%d, was %d) — the base is what the next recompute scales from"
			% [int(hero.get("_base_max_hp")), base])
	# Idempotent: re-applying the same piece must not compound.
	hero.call("set_loadout", "head", "hat")
	_expect(int(hero.get("max_hp")) == geared,
		"re-applying the same gear is idempotent (%d -> %d)" % [geared, int(hero.get("max_hp"))])
	# ...and the ratio is the CLASS's, not a flat number: a frailer class with the same
	# hat must end up frailer still.
	hero.call("configure_class", SHADOWBLADE)
	hero.call("set_loadout", "head", "hat")
	var frail: int = int(hero.get("max_hp"))
	_expect(frail < geared,
		"the same hat on the frailest class still yields less HP than on the tank (%d vs %d) — gear scales the class, it does not replace it"
			% [frail, geared])
	# A spawner that imposes its own pool AFTER configure_class still wins (BotMatch's
	# CLASS_VITALITY, VersusArena's showcase HP all rely on this ordering).
	hero.call("configure_class", JUGGERNAUT)
	hero.set("max_hp", 190)
	hero.set("hp", 190)
	_expect(int(hero.get("max_hp")) == 190,
		"an external max_hp override written AFTER configure_class still holds (%d)"
			% int(hero.get("max_hp")))
	hero.queue_free()
	await physics_frame
	_completes("class_hp_composes_with_gear")


## Five of the nine used to have byte-identical melee. The tuple that matters is
## (cadence, damage, reach, shove, arc), read off the CONFIGURED body rather than off
## the table, because `equip_weapon` writes some of it.
func _test_melee_profiles_are_all_distinct() -> void:
	var hero: CharacterBody2D = _make_hero(0)
	var seen: Dictionary = {}
	var rows: Array[String] = []
	for cls: int in CLASS_COUNT:
		hero.call("configure_class", cls)
		var key: String = "%0.3f|%d|%0.1f|%0.1f|%0.3f" % [
			float(hero.get("_melee_cd")), int(hero.get("_melee_damage")),
			float(hero.get("_melee_range")), float(hero.get("_melee_knockback")),
			float(hero.get("_melee_arc_dot")),
		]
		rows.append("%s=%s" % [CLASS_LABELS[cls], key])
		_expect(not seen.has(key),
			"%s's melee profile is its own (byte-identical to %s: %s)"
				% [CLASS_LABELS[cls], String(seen.get(key, "?")), key])
		seen[key] = CLASS_LABELS[cls]
	_expect(seen.size() == CLASS_COUNT,
		"all %d classes swing differently (got %d unique profiles across %s)"
			% [CLASS_COUNT, seen.size(), str(rows)])
	hero.queue_free()
	await physics_frame
	_completes("melee_profiles_are_all_distinct")


# ------------------------------------------------------------- the walled room
## Built exactly the way `Arena._apply_room_size` builds one: four full-span walls
## CENTRED on the edges, so each straddles the boundary by half its thickness.
func _build_room() -> void:
	_room = Node2D.new()
	root.add_child(_room)
	var spans: Array[Array] = [
		[Vector2(ROOM_W * 0.5, 0.0), Vector2(ROOM_W, WALL_T)],            # top
		[Vector2(ROOM_W * 0.5, ROOM_H), Vector2(ROOM_W, WALL_T)],         # bottom
		[Vector2(0.0, ROOM_H * 0.5), Vector2(WALL_T, ROOM_H)],            # left
		[Vector2(ROOM_W, ROOM_H * 0.5), Vector2(WALL_T, ROOM_H)],         # right
	]
	for s: Array in spans:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = s[1]
		cs.shape = rect
		body.add_child(cs)
		body.global_position = s[0]
		_room.add_child(body)


func _tear_down_room() -> void:
	if _room != null:
		_room.queue_free()
		_room = null


func _inside_room(p: Vector2) -> bool:
	return p.x > WALL_T * 0.5 - HERO_HALF and p.x < ROOM_W - WALL_T * 0.5 + HERO_HALF \
		and p.y > WALL_T * 0.5 - HERO_HALF and p.y < ROOM_H - WALL_T * 0.5 + HERO_HALF


## Would a hero-sized box at `p` overlap solid geometry? Uses the same 18x18 footprint
## Hero.tscn carries and the same layer-1 mask `Hero.BLINK_WALL_MASK` vets against.
func _in_solid(p: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = root.world_2d.direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(HERO_HALF * 2.0, HERO_HALF * 2.0)
	q.shape = box
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.transform = Transform2D(0.0, p)
	return not space.intersect_shape(q, 1).is_empty()


## THE POSITIVE COUNTERPART TO `_pin_level_one`. Pinning the level everywhere would
## make growth invisible to this suite, and "no class stat ever changed" is trivially
## satisfied by growth that does nothing at all — the same vacuous-invariant trap
## that let three bugs delete an entire ledge skyline behind a green geometry suite.
##
## So: raise the climber to a real level, rebuild a hero, and require the stats to
## have MOVED — in the direction that class's own Growth row says they should, and
## nowhere else.
func _test_level_growth_actually_moves_the_stats() -> void:
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs == null:
		_expect(false, "GameState is on the tree (growth cannot be tested without it)")
		return  # deliberately NOT completed
	# A level-1 Juggernaut, measured.
	gs.set("_xp", 0)
	var lo: CharacterBody2D = _make_hero(JUGGERNAUT)
	await physics_frame
	var hp_low: int = int(lo.get("max_hp"))
	var dmg_low: int = int(lo.get("_melee_damage"))
	var lo_melee_cd: float = float(lo.get("_melee_cd"))
	# CAPTURED BEFORE THE BODY IS FREED, and before the level moves. Re-deriving the
	# level-1 speed later by building another hero would read it AT THE NEW LEVEL, and
	# since the Juggernaut's SWIFTNESS is 0 the comparison would come out equal for the
	# wrong reason — a vacuous pass dressed as a real one.
	var spd_low: float = float(lo.call("_class_speed"))
	var base_low: int = int(lo.get("_base_max_hp"))
	lo.queue_free()
	await physics_frame

	# THE SAME CLASS, TEN LEVELS UP. Driven through the real XP curve rather than by
	# writing a level, so this also proves `level_for_xp` and the Hero read agree.
	gs.set("_xp", Progression.total_xp_for_level(10))
	_expect(int(gs.call("level")) == 10, "the climber is actually level 10 (got %d)" % int(gs.call("level")))
	_expect(int(gs.call("power_level")) == 10, "...and solo power level follows it")
	var hi: CharacterBody2D = _make_hero(JUGGERNAUT)
	await physics_frame
	# The Juggernaut's row is VIT 4 / POW 2 / FOC 1 / SWI 0 / WARD 3.
	_expect(int(hi.get("max_hp")) > hp_low,
		"VITALITY 4 raises the Juggernaut's max hp by level 10 (%d -> %d)" % [hp_low, int(hi.get("max_hp"))])
	_expect(int(hi.get("_melee_damage")) > dmg_low,
		"POWER 2 raises its melee damage (%d -> %d)" % [dmg_low, int(hi.get("_melee_damage"))])
	# FOCUS 1 shortens the melee gate. A DURATION, so growth makes it SMALLER — the one
	# axis whose direction is inverted, and therefore the one most likely to be wired
	# the wrong way round without anybody noticing.
	_expect(float(hi.get("_melee_cd")) < float(lo_melee_cd),
		"FOCUS 1 shortens the melee cooldown (%.4f -> %.4f)" % [lo_melee_cd, float(hi.get("_melee_cd"))])
	# ⚠ SWIFTNESS 0 MEANS 0. A class with a zero in the table must NOT drift. This is
	# what proves growth is read PER AXIS from that class's row, rather than applied as
	# one blanket multiplier that merely looks right on the axes that are non-zero.
	_expect(is_equal_approx(float(hi.call("_class_speed")), spd_low),
		"SWIFTNESS 0 means the Juggernaut never gets quicker, at any level (%.2f vs %.2f)"
		% [float(hi.call("_class_speed")), spd_low])
	# THE BASE IS UNTOUCHED. Growth scales FROM the class table and must never re-base
	# it, or the next recompute compounds — the exact trap `class_hp_composes_with_gear`
	# exists to pin, now re-asserted with a second multiplier in the chain.
	_expect(int(hi.get("_base_max_hp")) == base_low,
		"the class BASE is unchanged by levelling (%d vs %d) — growth scaled max_hp, it did not re-base it"
		% [int(hi.get("_base_max_hp")), base_low])
	hi.queue_free()
	await physics_frame
	# Leave the tree at level 1 for anything that runs after this.
	gs.set("_xp", 0)
	_completes("level_growth_actually_moves_the_stats")
