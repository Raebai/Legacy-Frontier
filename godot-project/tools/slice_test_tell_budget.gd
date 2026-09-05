# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_tell_budget.gd
#
# THE TELL LAYER'S THREE CONTRACTS, PINNED.
#
# `Telegraph` is the fairness contract of the whole game: every attack in the
# roster announces itself through one of its eight styles, and a tell you cannot
# read is not difficulty, it is a cheat. It shipped with NO `graphics_quality`
# gate and NO cost instrumentation — so on the device the spec targets it was both
# the most important thing on screen and the only effect layer that never got
# cheaper. Three things are asserted here, and each one is a thing that breaks
# silently:
#
#   1. IT DEGRADES. Every style must issue strictly less work at
#      `graphics_quality = LOW` than at HIGH. An effect that ignores the flag is a
#      bug on a phone and looks perfect on the desk it was written at. (This is
#      the test that would have failed against the file as it stood: the old build
#      had no `_low` at all, so `set("_low", true)` was a silent no-op — see
#      `tools/_tell_before.gd`, which is kept precisely so that claim is checkable.)
#   2. IT DOES NOT GET QUIETER. A cheap tell must claim the SAME GROUND as an
#      expensive one — same drawn reach, same danger footprint. "Cheaper" that
#      shrinks the danger picture is a difficulty change wearing an optimisation's
#      clothes, and the phone is the last place to ship one.
#   3. COLOUR CARRIES ELEMENT. Three styles used to paint hard-coded orange-red
#      over an accent-coloured ring, so a violet mage's zone, a green summoner's
#      zone and a red brute's zone were three outlines around one identical middle.
#      The ramps are pure functions now and this asserts they track their accent's
#      hue instead of overwriting it.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──────────
# A dead member read is NOT a failure in GDScript: it logs an error, ABORTS the
# enclosing function and hands back the return type's zero. So failures accumulate
# on the MEMBER `_fails` and every test records a COMPLETION SENTINEL as its last
# line — a test that aborts part-way fails the suite BY ABSENCE.
#
# ⚠ AND THE OTHER VACUITY TRAP. "LOW is cheaper than HIGH" is trivially true of a
# style that drew nothing in either. `_test_low_still_draws_the_tell` asserts a
# MINIMUM amount of work per style so an empty picture cannot pass as a cheap one.
extends SceneTree

const TELL: GDScript = preload("res://scripts/combat/Telegraph.gd")
const SIGNAL_SCRIPT: GDScript = preload("res://scripts/combat/CasterSignal.gd")
const BOLT_SCRIPT: GDScript = preload("res://scripts/combat/SpellBoltVisual.gd")
const DECAL_SCRIPT: GDScript = preload("res://scripts/combat/ScorchDecal.gd")

const TESTS: Array[String] = [
	"every_style_degrades_at_low",
	"low_still_draws_the_tell",
	"low_claims_the_same_ground",
	"colour_ramps_follow_the_accent",
	"every_style_states_a_consequence",
	"the_low_plan_is_monotone",
	"the_rest_of_the_tell_layer_degrades",
]

## The nine real configurations, matching `tools/probe_tell_cost.gd` so the suite
## and the bench cannot disagree about what a tell is. Sizes and windups are the
## game's own (Enemy's tuning block, Hero's swing tell), not invented.
const CONFIGS: Array[Dictionary] = [
	{"name": "ZONE brute", "style": 0, "r": 40.0, "w": 0.60, "tether": true},
	{"name": "ZONE mage", "style": 0, "r": 70.0, "w": 0.85, "tether": true},
	{"name": "MUZZLE caster", "style": 1, "r": 18.0, "w": 0.70, "reach": 130.0},
	{"name": "LANE charger", "style": 2, "line": true, "len": 300.0, "wid": 34.0, "w": 0.70},
	{"name": "DART assassin", "style": 3, "r": 26.0, "w": 0.35, "tether": true},
	{"name": "GATHER summoner", "style": 4, "r": 24.0, "w": 0.80},
	{"name": "BOMB bomber", "style": 5, "r": 78.0, "w": 0.90},
	{"name": "FIST hero melee", "style": 6, "line": true, "len": 58.0, "wid": 10.4, "w": 0.077},
	{"name": "CRESCENT blade", "style": 7, "line": true, "len": 58.0, "wid": 10.4, "w": 0.077},
	# The cones, with the geometry their DAMAGE queries use:
	# `Hero._on_melee_hit_frame` (MELEE_RANGE 58, MELEE_ARC_DOT 0.30 -> 72.5 deg) and
	# `Hero._resolve_uppercut` (70, -0.20 -> 101.5 deg).
	# ⚠ "CONE frost" (118, 0.50 -> 60.0 deg) IS NO LONGER A SHIPPING SHAPE. The
	# Cryomancer's primary was that wedge until the maker called it "weird and too
	# big"; it is a shard volley behind a `Style.LANE` corridor now
	# (`Hero._primary_frost_shards`), whose draw cost is bounded by the "LANE charger"
	# row above (len 300 / wid 34 — the real lane is 300 x 69, same two segments).
	# The row is KEPT rather than deleted: it is the only WIDE full-weight cone in the
	# table, so it is what pins the boundary-drawing cost of `Style.CONE` at reach,
	# and deleting it would silently drop that ceiling. It is a style benchmark, not a
	# claim about what the game draws.
	# The melee row is drawn LIGHT and the two full-weight rows FULL,
	# which is the legibility split `Telegraph.CONE_LIGHT_ALPHA` argues for; both weights
	# are measured here so a change to either shows up as a number.
	# ⚠ STYLE 6 (FIST), NOT 8 — THIS ROW IS THE TELL THE GAME ACTUALLY SHIPS. The
	# melee swing publishes a FIST figure over a CONE-shaped tell, so measuring a bare
	# CONE here would measure a picture no player ever sees and would miss the one
	# saving that matters (the fist's lane hint is suppressed under a cone).
	{"name": "FIST melee cone", "style": 6, "cone": true, "reach": 58.0,
		"half": 1.2661, "wid": 10.4, "light": true, "w": 0.077,
		# A light cone draws no boundary, so the fist figure alone IS the picture. See the
		# ruling at the floors below.
		"min_low_calls": 3.0, "min_low_segments": 3.0},
	{"name": "CONE uppercut", "style": 8, "cone": true, "reach": 70.0, "half": 1.7722, "w": 0.10},
	{"name": "CONE frost", "style": 8, "cone": true, "reach": 118.0, "half": 1.0472, "w": 0.10},
]

const PHASE: float = 0.6

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _stage: Node2D = null
var _source: Node2D = null
## Filled by `_measure_all` before any test runs: name -> {high: {...}, low: {...}}.
var _work: Dictionary = {}


## ⚠ DRIVEN FROM `_process`, NOT `_init`. A `SceneTree` script's `_init` runs before
## `root` exists, so `root.add_child` there is a no-op against a null parent and every
## drawn figure comes back empty — the trap `slice_test_hero_tells` records.
## ⚠ `_process` MUST NOT `await`. A `SceneTree._process` that awaits stops being a
## function returning bool and becomes a coroutine returning a signal object — the
## engine then reads the return as "keep running", the body never resumes past the
## first await, and the suite exits having printed NEITHER a pass line NOR a fail
## line. Which is a failure by this repo's convention, but a silent one: the first
## cut of this file did exactly that and looked like a clean run with no output.
## So the driver stays synchronous and kicks off the coroutine, which owns `quit`.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false     # keep the loop alive so `await process_frame` can resolve


func _run() -> void:
	# ⚠ HEADLESS HAS NO WINDOW AND THEREFORE NO ASPECT: `get_visible_rect()` falls
	# back to a SQUARE 640x640. Put the root into the shipping shape first.
	root.size = Vector2i(1366, 768)
	_stage = Node2D.new()
	root.add_child(_stage)
	_source = Node2D.new()
	_stage.add_child(_source)
	_source.position = Vector2(-90.0, -30.0)
	await _measure_all()
	_test_every_style_degrades_at_low()
	_test_low_still_draws_the_tell()
	_test_low_claims_the_same_ground()
	_test_colour_ramps_follow_the_accent()
	_test_every_style_states_a_consequence()
	_test_the_low_plan_is_monotone()
	await _test_the_rest_of_the_tell_layer_degrades()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	_source.free()
	_stage.free()
	if _fails > 0:
		printerr("Tell budget tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Tell budget tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ---------------------------------------------------------------- measurement
## Build every config at both qualities and record what one `_draw` costs.
##
## ⚠ THE WORK IS COUNTED, NOT TIMED, for the reason `MagicCircle`'s counter block
## states at length: a headless frame absorbs work into idle time until it crosses
## the pacing budget, so a millisecond figure here is a coin toss while a primitive
## count is exactly linear in the thing being asserted.
func _measure_all() -> void:
	for c: Dictionary in CONFIGS:
		var row: Dictionary = {}
		for low: bool in [false, true]:
			row["low" if low else "high"] = await _measure_one(c, low)
		_work[String(c["name"])] = row


func _measure_one(c: Dictionary, low: bool) -> Dictionary:
	var t: Node2D = TELL.new()
	_stage.add_child(t)
	t.set("style", int(c["style"]))
	t.set("accent", Color(0.62, 0.52, 1.0, 1.0))
	# `_ready` reads the live Tuning autoload, which a `--script` run does not have,
	# so the flag is set AFTER the node enters the tree or `_ready` would stamp HIGH
	# back over it. A DECLARED property, so this is not a silent no-op — the
	# SpawnTell idiom, and the whole reason the LOW branch is assertable headlessly.
	t.set("_low", low)
	if bool(c.get("tether", false)):
		t.set("source", _source)
	if float(c.get("reach", 0.0)) > 0.0:
		t.set("aim_dir", Vector2.RIGHT)
		t.set("reach", float(c["reach"]))
	var windup: float = float(c["w"])
	if bool(c.get("cone", false)):
		t.call("start_cone", float(c["reach"]), float(c["half"]), 0.35, windup,
			float(c.get("wid", 0.0)), bool(c.get("light", false)))
	elif bool(c.get("line", false)):
		t.call("start_line", float(c["len"]), float(c["wid"]), 0.35, windup)
	else:
		t.call("start", float(c["r"]), windup)
	# Frozen by assignment rather than by `advance()`: advancing would also fire the
	# tell and free the node mid-measurement.
	t.set("_elapsed", windup * PHASE)
	t.set_process(false)
	TELL.reset_work()
	t.queue_redraw()
	await process_frame
	await process_frame
	var w: Dictionary = TELL.work_stats()
	t.free()
	return w


func _stat(name: String, quality: String, key: String) -> float:
	var row: Dictionary = _work.get(name, {}) as Dictionary
	var q: Dictionary = row.get(quality, {}) as Dictionary
	return float(q.get(key, 0.0))


# --------------------------------------------------------------------- tests
## Contract 1. Every style must do measurably less work on the phone. "Less work"
## is EITHER fewer draw commands OR fewer segments — a style like FIST is already
## five commands of flat geometry and has no segments to shed, so demanding both
## would be demanding a picture change rather than a cost one.
func _test_every_style_degrades_at_low() -> void:
	var checked: int = 0
	for c: Dictionary in CONFIGS:
		var n: String = String(c["name"])
		var hc: float = _stat(n, "high", "calls")
		var hs: float = _stat(n, "high", "segments")
		var lc: float = _stat(n, "low", "calls")
		var ls: float = _stat(n, "low", "segments")
		_expect(lc < hc or ls < hs,
			"%s is cheaper at LOW (calls %.0f->%.0f, segments %.0f->%.0f) — a style that ignores the flag is a bug on a phone"
				% [n, hc, lc, hs, ls])
		_expect(lc <= hc and ls <= hs,
			"%s never gets MORE expensive at LOW (calls %.0f->%.0f, segments %.0f->%.0f)"
				% [n, hc, lc, hs, ls])
		checked += 1
	# Vacuity guard: a table that lost its rows would pass the loop above silently.
	# ⚠ `CONFIGS.size()`, NOT A LITERAL. This guard exists to catch a table that LOST
	# rows; written as a hard 9 it also fired every time the table legitimately GREW,
	# which trains the next reader to edit the number rather than to read the failure.
	_expect(checked == CONFIGS.size(),
		"all %d tell configurations were measured (%d)" % [CONFIGS.size(), checked])
	_completes("every_style_degrades_at_low")


## Contract 1's other half. "Cheaper" must not mean "gone". Every style still has to
## issue a real figure at LOW — the numbers here are floors, not targets, chosen well
## under the measured LOW values so a genuine future saving does not trip them.
func _test_low_still_draws_the_tell() -> void:
	for c: Dictionary in CONFIGS:
		var n: String = String(c["name"])
		# ⚠ THE FLOOR IS PER-ROW NOW, AND ONE ROW DELIBERATELY SITS UNDER 4. A cone
		# drawn at the LIGHT weight is a boundary and nothing else — the rim arc and the
		# two limit rays, two commands — because a 66-90 degree wedge published three
		# times a second at a spell tell's weight would be the loudest thing in a fight
		# the maker has called *"too much going on"*. That is a chosen picture, not a
		# missing one, so the row states its own floor rather than the floor being bent
		# down for everybody. See `Telegraph.CONE_LIGHT_ALPHA`.
		# ⚠ THE MELEE FLOORS DROPPED TO 3, AND THAT IS A RULING RATHER THAN A REGRESSION.
		# A LIGHT cone now draws NO boundary at all. Measured, that boundary was an 86 px,
		# 174-degree ARCANE-magenta arc wrapped around the Swordsaint — the maker's *"goofy
		# large pink barrier thing in its left click attack"* — and the same object at 58 px
		# on the Brawler, which they read as a deflect shield on an offensive verb. So the
		# strike figure (the fist, the crescent) is the whole read, and 3 commands IS the
		# picture rather than a missing one. The floor is stated per row so the general
		# "every style still draws something at LOW" rule is not bent down for everybody.
		var floor_calls: float = float(c.get("min_low_calls", 4.0))
		var floor_segs: float = float(c.get("min_low_segments", 4.0))
		_expect(_stat(n, "low", "calls") >= floor_calls,
			"%s still draws a figure at LOW (%.0f draw commands, floor %.0f)"
				% [n, _stat(n, "low", "calls"), floor_calls])
		_expect(_stat(n, "low", "segments") >= floor_segs,
			"%s still has geometry at LOW (%.0f segments, floor %.0f)"
				% [n, _stat(n, "low", "segments"), floor_segs])
		_expect(_stat(n, "low", "tells") >= 1.0,
			"%s's _draw actually ran at LOW (a headless frame that never drew would pass every count above)" % n)
	_completes("low_still_draws_the_tell")


## Contract 2. The cheap picture must claim exactly the same ground as the
## expensive one. `reach` is the furthest any primitive got from the tell's own
## origin, so a LOW build that shrank a ring or shortened a lane shows up here as a
## smaller number — which is the failure mode that matters, because it silently
## makes the phone's version of the game harder to read AND easier to mis-dodge.
func _test_low_claims_the_same_ground() -> void:
	for c: Dictionary in CONFIGS:
		var n: String = String(c["name"])
		var hr: float = _stat(n, "high", "reach")
		var lr: float = _stat(n, "low", "reach")
		_expect(absf(hr - lr) < 0.5,
			"%s claims the same ground at LOW (%.1f px vs %.1f) — cheaper, never quieter" % [n, lr, hr])
		_expect(hr > 0.0, "%s drew something at a measurable distance from its origin" % n)
	_completes("low_claims_the_same_ground")


## Contract 3. The three ramps that used to be hard-coded orange-red must now be
## built from the accent. Asserted by HUE ORDERING rather than by exact values, so
## a future re-tune of a ramp's shape is free while a return to a literal colour
## fails: fed a green accent, the fill's green channel must dominate.
func _test_colour_ramps_follow_the_accent() -> void:
	var green := Color(0.20, 0.90, 0.35, 1.0)
	var violet := Color(0.62, 0.30, 1.00, 1.0)
	for t: float in [0.0, 0.5, 1.0]:
		var zf: Color = TELL.zone_fill(green, t)
		_expect(zf.g > zf.r and zf.g > zf.b,
			"zone fill at t=%.1f is GREEN for a green caster (r%.2f g%.2f b%.2f) — it used to be orange whatever the accent"
				% [t, zf.r, zf.g, zf.b])
		var bf: Color = TELL.bomb_fill(violet, t)
		_expect(bf.b > bf.g,
			"bomb fill at t=%.1f follows a violet accent (r%.2f g%.2f b%.2f)" % [t, bf.r, bf.g, bf.b])
	# The ramp SHAPE is the charge read and must survive: washed out early, hot late.
	_expect(TELL.zone_fill(green, 0.0).a < TELL.zone_fill(green, 1.0).a,
		"the zone fill still ramps up in opacity as the tell fills (the charge read)")
	_expect(TELL.zone_fill(green, 0.0).s < TELL.zone_fill(green, 1.0).s,
		"the zone fill still saturates as the tell fills (pale early, hot late)")
	_expect(TELL.bomb_fill(violet, 0.0).a < TELL.bomb_fill(violet, 1.0).a,
		"the fuse's fill still ramps up as the fuse burns")
	var cd: Color = TELL.bomb_countdown(green)
	_expect(cd.g > cd.r and cd.g > cd.b,
		"the fuse's countdown sweep follows the accent (r%.2f g%.2f b%.2f)" % [cd.r, cd.g, cd.b])
	_expect(cd.v >= green.v,
		"the countdown sweep is the HOTTEST line in the bomb figure, not a second hue")
	var lf: Color = TELL.lane_flash(green, 1.0)
	_expect(lf.g > lf.r and lf.g > lf.b,
		"the charge lane's payoff flash follows the accent (r%.2f g%.2f b%.2f)" % [lf.r, lf.g, lf.b])
	_completes("colour_ramps_follow_the_accent")


## Rule 2 made explicit: every style must state what it PROMISES. A style added
## tomorrow with no row is a tell whose meaning nobody wrote down, and the whole
## point of the vocabulary is that the player learns a fixed small set of shapes.
##
## ⚠ EIGHT SHAPES / THREE WORDS BECAME NINE / FOUR, AND THE COUNT WAS RAISED
## DELIBERATELY RATHER THAN THE CODE BENT TO KEEP IT GREEN. `Style.CONE` was added
## because three attacks (the melee swing, the Brawler uppercut, the Cryomancer frost
## cone) all query `SpellTargets.in_cone` and none of them could DRAW a cone — the
## melee tell was a lane 10.2-11.1x narrower in angle than the swing that damages.
## A fourth word, "wedge", came with it, because the dodge a wedge asks for is neither
## a ground zone's (leave in any direction) nor a corridor's (step off the line): it is
## get behind it or out of it. Teaching the player a word for a shape they must dodge
## differently is the vocabulary working, not the vocabulary growing.
func _test_every_style_states_a_consequence() -> void:
	var styles: Dictionary = TELL.Style
	_expect(styles.size() == 9, "the Style enum is the nine-shape vocabulary (%d)" % styles.size())
	var seen: Dictionary = {}
	for name: String in styles:
		var s: int = int(styles[name])
		_expect(TELL.STYLE_CONSEQUENCE.has(s),
			"Style.%s states its consequence (an unlisted style is a tell nobody defined)" % name)
		var word: String = String(TELL.STYLE_CONSEQUENCE.get(s, ""))
		_expect(word in ["ground", "corridor", "blow", "wedge"],
			"Style.%s's consequence is one of the four the player is taught ('%s')" % [name, word])
		seen[word] = true
	_expect(seen.size() == 4,
		"all four consequences are in use (%d) — a vocabulary with an unused word is one the player never learns"
			% seen.size())
	_completes("every_style_states_a_consequence")


## The LOW plan is arithmetic, so it is checkable without a tree at all. Each knob
## must move the right way AND stop at a floor: "cheaper" with no floor eventually
## means "blank", which is contract 1's other half stated as a pure function.
func _test_the_low_plan_is_monotone() -> void:
	_expect(TELL.ghosts_for(true) < TELL.ghosts_for(false),
		"the crescent trails fewer ghosts at LOW (%d vs %d)" % [TELL.ghosts_for(true), TELL.ghosts_for(false)])
	_expect(TELL.ghosts_for(true) >= 1,
		"...but still trails at least one, or the cut appeared rather than travelled")
	_expect(TELL.crescent_steps(true) < TELL.crescent_steps(false),
		"the crescent tessellates less finely at LOW")
	_expect(TELL.crescent_steps(true) >= 8, "...and is still a curve, not a triangle")
	_expect(TELL.tether_pulses(true) < TELL.tether_pulses(false),
		"the caster tether carries fewer pulses at LOW")
	_expect(TELL.tether_pulses(true) >= 1,
		"...but at least one, or the tether stops stating a direction")
	_expect(TELL.chevron_spacing(true) > TELL.chevron_spacing(false),
		"the charge lane spaces its chevrons wider at LOW (fewer over the same lane)")
	_expect(TELL.fist_knuckles(false) and not TELL.fist_knuckles(true),
		"the fist keeps its knuckle flare on the desk and drops it on the phone")
	for full: int in [8, 10, 16]:
		_expect(TELL.ticks_for(full, true) < full, "%d runic ticks thin at LOW" % full)
		_expect(TELL.ticks_for(full, true) >= 4,
			"...to no fewer than four, or the ring stops reading as arcane")
	# A ring must never be tessellated finer at LOW than at HIGH, at any size the
	# game actually draws one at.
	for r: float in [12.0, 18.0, 24.0, 40.0, 70.0, 78.0]:
		_expect(TELL.seg_for(48, r, true) <= TELL.seg_for(48, r, false),
			"a %.0f px ring is no finer at LOW than at HIGH" % r)
		_expect(TELL.seg_for(48, r, true) >= 12,
			"a %.0f px ring is still round at LOW (%d segments)" % [r, TELL.seg_for(48, r, true)])
	_completes("the_low_plan_is_monotone")


## THE TELL IS NOT THE ONLY THING ON SCREEN DURING A WINDUP. Three more layers ride
## the same beat and all three ignored `graphics_quality` outright:
##
##   CasterSignal    one per enemy windup — the charge glow on the BODY. Seven
##                   archetype windups all spawn one, so on a busy floor it is one
##                   of these per winding-up enemy on top of the tell itself.
##   SpellBoltVisual the most numerous drawn object in the game: nine wake commands
##                   plus three nested halos plus the per-element figure, several
##                   times a second, per caster.
##   ScorchDecal     the only layer whose cost is PERMANENT — a decal draws once and
##                   is then re-submitted every frame for the rest of the session.
##
## Asserted through their pure plan functions and constants rather than a renderer,
## for the reason the header gives.
func _test_the_rest_of_the_tell_layer_degrades() -> void:
	_expect(SIGNAL_SCRIPT.motes_for(true) < SIGNAL_SCRIPT.motes_for(false),
		"the caster's charge glow sheds motes at LOW (%d vs %d)"
			% [SIGNAL_SCRIPT.motes_for(true), SIGNAL_SCRIPT.motes_for(false)])
	_expect(SIGNAL_SCRIPT.motes_for(true) >= 2,
		"...but keeps enough to still read as spiralling INWARD, which is the message")
	for r: float in [10.0, 13.0, 16.0]:
		_expect(SIGNAL_SCRIPT.ring_segments(r, true) <= SIGNAL_SCRIPT.ring_segments(r, false),
			"the contracting ring is no finer at LOW at r=%.0f" % r)
	var bolt_consts: Dictionary = BOLT_SCRIPT.get_script_constant_map()
	_expect(int(bolt_consts["WAKE_SEGMENTS_LOW"]) < int(bolt_consts["WAKE_SEGMENTS"]),
		"the bolt's wake samples fewer stations at LOW (%d vs %d)"
			% [int(bolt_consts["WAKE_SEGMENTS_LOW"]), int(bolt_consts["WAKE_SEGMENTS"])])
	_expect(int(bolt_consts["WAKE_SEGMENTS_LOW"]) >= 5,
		"...and is still a cubic taper rather than a wedge")
	var decal_consts: Dictionary = DECAL_SCRIPT.get_script_constant_map()
	_expect(int(decal_consts["MAX_DECALS_LOW"]) < int(decal_consts["MAX_DECALS"]),
		"the floor holds fewer permanent decals at LOW (%d vs %d)"
			% [int(decal_consts["MAX_DECALS_LOW"]), int(decal_consts["MAX_DECALS"])])
	_expect(int(decal_consts["MAX_DECALS_LOW"]) >= 16,
		"...but enough that the arena still visibly wrecks, which is the whole system")
	# ⚠ AND THE BOLT MUST STILL DRAW, in both modes, for every element. The wake is
	# now ONE polygon built by index arithmetic; an off-by-one there produces a
	# self-intersecting outline, which Godot draws as garbage rather than erroring.
	var built: Array[Node2D] = []
	for low: bool in [false, true]:
		for effect: String in ["fire", "frost", "lightning", "shadow", "earth",
				"holy", "wind", "arcane"]:
			var b: Node2D = BOLT_SCRIPT.new()
			_stage.add_child(b)
			b.set("_low", low)
			b.call("set_shape", effect)
			b.call("set_tint", Color(0.6, 0.8, 1.0, 1.0))
			b.queue_redraw()
			built.append(b)
	await process_frame
	await process_frame
	var alive: int = 0
	for b: Node2D in built:
		if is_instance_valid(b):
			alive += 1
			b.free()
	_expect(alive == 16, "all sixteen bolts (8 elements x 2 qualities) survived a draw (%d)" % alive)
	_completes("the_rest_of_the_tell_layer_degrades")
