# BRING BACK THE DEFLECT — for the walls, the squall and the statue.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice_test_owned_spell_deflect.gd
#
# Maker's ask, verbatim: *"bring back the deflect"*.
#
# ⚠ COUNT FIRST. `SpellDeflect.gd` is not missing, dead or unwired — it is a large,
# finished, well-tested system with a 22-file blast radius and its own counter
# (`SpellDeflect.deflect_count`) added precisely because "the machinery is all
# there" is not evidence that it runs. So the honest question was never "does the
# deflect exist" but "which spells reach it", and the answer, counted rather than
# assumed, was: 21 files call `SpellDeflect.resolve`, and of the spells in this
# agent's ownership exactly ONE of them (ShadowRoot) was among them.
#
# That is what this suite is about. Four of the biggest single hits in these files —
# the ice wall's shard burst (18), the rock wall's plow (40), the blizzard's encase
# shatter (34) and the statue's throw (96) — went straight past a raised guard as if
# it were not there. A player who correctly reads a wall about to burst in their
# face and presses parry on the right frame was told "no".
#
# THE MEASUREMENT IS SYMMETRIC ON PURPOSE. Every case fires the same spell twice,
# once at a GUARDED dummy and once at an UNGUARDED one, and asserts BOTH halves:
#   * guarded   -> hp unchanged AND `deflect_count` went up
#   * unguarded -> hp went down
# The second half is what stops this suite passing vacuously the day a spell stops
# hitting anything at all — "nobody took damage" would otherwise look like a
# flawless parry, which is exactly the shape of failure this codebase keeps finding.
#
# ⚠ NO class_name FOR THE SPELL SCRIPTS. Their raise paths name the `Sfx` autoload,
# which is not a global identifier at compile time in a `--script` harness; naming
# them here fails the WHOLE file with "Identifier not found: Sfx". Load by path.
# `SpellDeflect` itself is safe to name — it is a pure RefCounted with no autoload
# in its own compile graph, and every existing deflect suite names it directly.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_spell_buttons.gd for the write-up) ──
# Failures accumulate on the MEMBER `_fails` so a mid-test abort cannot discard
# them, and every test records that it reached its own last line. A test missing
# from `_completed` fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"baseline_the_guard_works_at_all",
	"ice_wall_shatter_is_deflectable",
	"rock_wall_plow_is_deflectable",
	"blizzard_encase_shatter_is_deflectable",
]

const ICE_WALL_PATH: String = "res://scripts/combat/IceWall.gd"
const ROCK_WALL_PATH: String = "res://scripts/combat/RockWall.gd"
const ZONE_SPELL_PATH: String = "res://scripts/combat/ZoneSpell.gd"

## Far from the arena origin: these spectacles park at (0, 0) and draw in world
## coordinates, so anything staged at the origin would pass for a detector that
## wrongly read transforms.
const STAGE := Vector2(600.0, 0.0)
const DUMMY_HP: int = 900

var _fails: int = 0
var _completed: Dictionary = {}

var _ice: GDScript = null
var _rock: GDScript = null
var _zone: GDScript = null
var _arena: Node2D = null


## A body that answers everything a spectacle's damage loop asks of a fighter, and
## nothing it does not. `parrying` is the one knob each test flips.
##
## `take_damage` takes the TINT overload deliberately: `SpellTargets.hurt` sniffs
## the arity and calls the two-argument form when it exists, so a one-argument stub
## would exercise a different branch than a real Hero/Enemy does.
class Dummy extends Node2D:
	var hp: int = DUMMY_HP
	var parrying: bool = false
	var deflected: int = 0
	var statuses: int = 0

	func take_damage(amount: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
		hp -= amount

	func is_parrying() -> bool:
		return parrying

	func parry_freshness() -> float:
		return 1.0

	func on_spell_deflected(_dir: Vector2) -> void:
		deflected += 1

	func apply_status(_element: int, _hard: bool = true) -> void:
		statuses += 1

	func apply_knockback(_v: Vector2) -> void:
		pass


func _initialize() -> void:
	root.size = Vector2i(1366, 768)
	create_timer(180.0).timeout.connect(func() -> void:
		printerr("FAIL: harness watchdog fired — a test coroutine died before the end")
		quit(1))
	_run()


func _run() -> void:
	await process_frame
	_ice = load(ICE_WALL_PATH) as GDScript
	_rock = load(ROCK_WALL_PATH) as GDScript
	_zone = load(ZONE_SPELL_PATH) as GDScript
	_arena = Node2D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_test_baseline_the_guard_works_at_all()
	await _test_ice_wall_shatter_is_deflectable()
	await _test_rock_wall_plow_is_deflectable()
	await _test_blizzard_encase_shatter_is_deflectable()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Owned-spell deflect tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Owned-spell deflect tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ---- harness ----------------------------------------------------------------

## A dummy standing at `where`, in the faction group every spectacle here scans.
func _dummy(where: Vector2, guarding: bool) -> Dummy:
	var d := Dummy.new()
	d.parrying = guarding
	_arena.add_child(d)
	d.global_position = where
	d.add_to_group("enemy")
	return d


func _clear() -> void:
	for child: Node in _arena.get_children():
		child.free()


## The shared shape of every case below: run `fire` against a guarded dummy and
## against an unguarded one, and report both halves.
##
## Returns nothing and asserts everything, because the interesting failure is not
## "it returned false" but WHICH of the two halves broke — a spell that stopped
## hitting anybody and a spell that ignores the guard look identical from a bool.
func _both_ways(label: String, fire: Callable) -> void:
	# --- guarded
	SpellDeflect.reset_counts()
	var guarded: Dummy = _dummy(STAGE, true)
	await fire.call(guarded)
	var blocked: int = SpellDeflect.deflect_count
	var guarded_loss: int = DUMMY_HP - guarded.hp
	_clear()
	# --- unguarded
	SpellDeflect.reset_counts()
	var open_body: Dummy = _dummy(STAGE, false)
	await fire.call(open_body)
	var open_loss: int = DUMMY_HP - open_body.hp
	var leaked: int = SpellDeflect.deflect_count
	_clear()
	print("[count] %-24s guarded: %d deflects, %d dmg | unguarded: %d deflects, %d dmg"
		% [label, blocked, guarded_loss, leaked, open_loss])
	_expect(open_loss > 0,
		"%s actually HITS an unguarded body (took %d — a spell that hits nobody would "
			% [label, open_loss] + "make the guarded half pass vacuously)")
	_expect(blocked > 0, "%s reaches SpellDeflect at all (0 deflects counted)" % label)
	_expect(guarded_loss == 0,
		"%s is fully eaten by a raised guard (still took %d)" % [label, guarded_loss])
	_expect(leaked == 0,
		"%s counts no deflect against a body that was not guarding (%d)" % [label, leaked])


# ---- the tests --------------------------------------------------------------

## THE INSTRUMENT CHECK, and it is not ceremony. Every assertion below is of the
## form "the counter went up", and a counter that can never go up would make all of
## them fail for a reason that has nothing to do with the spells. So: prove the
## guard, the dummy and the counter work together on the one path that was already
## wired, before asking anything of the ones that were not.
func _test_baseline_the_guard_works_at_all() -> void:
	SpellDeflect.reset_counts()
	var d: Dummy = _dummy(STAGE, true)
	var dealt: int = SpellDeflect.resolve(d, 50, Vector2.RIGHT, STAGE)
	_expect(dealt == 0, "a raised guard zeroes an ordinary spell hit (got %d)" % dealt)
	_expect(SpellDeflect.deflect_count == 1,
		"...and the counter sees it (%d)" % SpellDeflect.deflect_count)
	_expect(d.deflected == 1, "...and the victim is told to strike the pose")
	d.parrying = false
	var through: int = SpellDeflect.resolve(d, 50, Vector2.RIGHT, STAGE)
	_expect(through == 50, "an unguarded body takes the whole hit (got %d)" % through)
	_expect(SpellDeflect.deflect_count == 1, "...and the counter does NOT move")
	_clear()
	_completes("baseline_the_guard_works_at_all")


## THE ICE WALL'S SHARD BURST. Now also the payoff of the wall's second beat (a
## punched ice wall detonates — see IceWall's header), which makes reaching the
## guard more important than it was when the burst was only an expiry event: the
## spell is now something a player AIMS at you.
func _test_ice_wall_shatter_is_deflectable() -> void:
	await _both_ways("ice wall shatter", func(_d: Dummy) -> void:
		var w: Node2D = _ice.new()
		_arena.add_child(w)
		w.set("element_id", Elements.Element.ICE)
		w.set("spell_tier", SpellTier.Tier.HEAVY)
		# Raised so the wall STANDS ON the dummy's tile: the burst centre is the wall's
		# own mid-height, and SHATTER_RADIUS is 120, so a body at the base is inside it.
		w.call("raise_wall", STAGE - Vector2(90.0, 0.0), Vector2.RIGHT)
		w.call("shatter"))
	_completes("ice_wall_shatter_is_deflectable")


## THE ROCK WALL'S PLOW — the heaviest thing the two-beat can do to you, and the one
## the maker is most likely to be standing in front of, since the whole point of the
## second beat is to send the wall at somebody.
func _test_rock_wall_plow_is_deflectable() -> void:
	await _both_ways("rock wall plow", func(_d: Dummy) -> void:
		var w: Node2D = _rock.new()
		_arena.add_child(w)
		w.set("element_id", Elements.Element.EARTH)
		w.set("spell_tier", SpellTier.Tier.HEAVY)
		# Raised well to the LEFT of the dummy and shoved right, so the plow band
		# sweeps onto the body rather than starting on top of it — the realistic case,
		# and the one where `_eject_bodies_from_wall` cannot pre-empt the test by
		# shoving the dummy out of the raise footprint.
		w.call("raise_wall", STAGE - Vector2(390.0, 0.0), Vector2.RIGHT)
		w.call("shove", Vector2.RIGHT)
		# Long enough for the 820 px/s slide to cross the ~210 px gap, with slack.
		for i in 60:
			await process_frame
			if not is_instance_valid(w):
				break)
	_completes("rock_wall_plow_is_deflectable")


## THE BLIZZARD'S PAYOFF. Chip ticks and the encase shatter are two different
## promises and only the second one is a HIT — see the note in ZoneSpell's rework
## header — so this drives the field long enough to fill the rime meter and burst
## the casing, which is the 34-damage beat the field exists for.
func _test_blizzard_encase_shatter_is_deflectable() -> void:
	await _both_ways("blizzard encase shatter", func(_d: Dummy) -> void:
		var z: Node2D = _zone.new()
		_arena.add_child(z)
		z.set("element_id", Elements.Element.ICE)
		z.set("spell_tier", SpellTier.Tier.HEAVY)
		z.call("open", STAGE, Color(0.6, 0.85, 1.0), 135.0, 8, "frost", 4.2)
		# RIME_TO_ENCASE (1.4 s) + ENCASE_HOLD (0.8 s) plus slack, measured against
		# the FIELD'S OWN clock rather than a frame count: the headless loop is
		# uncapped, so "N frames" is not a duration here.
		while is_instance_valid(z) and float(z.get("_elapsed")) < 2.8:
			await process_frame)
	_completes("blizzard_encase_shatter_is_deflectable")
