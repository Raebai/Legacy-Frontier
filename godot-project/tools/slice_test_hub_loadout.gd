# THE HUB IS WHERE YOU EQUIP, AND THE CHOICE HAS TO SURVIVE THE SESSION.
#
# Maker: *"no need to equip weapons in the tower it should be like equippable in
# the hub and changing the weapon"*.
#
# The first half was already true — `FloorBuilder.build_props` stopped spawning
# weapon pickups when it turned out a hardcoded "sword" was being handed to classes
# whose own card says they do not carry one. The second half was NOT: the Armory pad
# wrote `GameState.loadout`, `Hero._apply_gamestate_loadout` re-read it after every
# class setup, and **nothing ever wrote it to disk**. So the choice survived walking
# into the tower and did not survive quitting, which makes "equippable in the hub" a
# thing you re-do every session. Nothing asserted the round trip.
#
#   godot --headless --path godot-project --script tools/slice_test_hub_loadout.gd
extends SceneTree

## ⚠ LOADED BY PATH, NOT NAMED. `GameState` is an AUTOLOAD, not a `class_name`, and
## naming it in source makes the compiler resolve it at compile time — where the
## autoload does not exist yet under a `--script` main loop. The whole suite then
## fails with `Identifier not found: GameState` and every test reports as aborted.
## Same trap `slice1_test_nova.gd` documents for `Sfx`. Statics work fine off the
## loaded GDScript.
const GAMESTATE_PATH: String = "res://scripts/GameState.gd"


func _gs() -> GDScript:
	return load(GAMESTATE_PATH) as GDScript

const TESTS: Array[String] = [
	"a_hub_loadout_survives_a_save_and_load",
	"an_old_save_without_a_loadout_still_loads",
	"a_save_cannot_carry_junk_into_the_rig",
	"the_tower_never_spawns_a_weapon",
]

var _failures: Array[String] = []
var _ran: Dictionary = {}
var _started: bool = false


func _process(_d: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false


func _run() -> void:
	_test_a_hub_loadout_survives_a_save_and_load()
	_test_an_old_save_without_a_loadout_still_loads()
	_test_a_save_cannot_carry_junk_into_the_rig()
	_test_the_tower_never_spawns_a_weapon()
	for n: String in TESTS:
		if not _ran.has(n):
			_failures.append("test `%s` is registered but never ran to completion" % n)
	if _failures.is_empty():
		print("Hub loadout tests: all PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("FAIL: %s" % f)
		print("Hub loadout tests: %d FAILED" % _failures.size())
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _completes(n: String) -> void:
	_ran[n] = true


## ⚠ THROUGH THE REAL PAYLOAD BUILDER AND THE REAL PARSER, not by poking the var.
## The bug was that the writer never carried the field; a test that set `loadout`
## and read it straight back would have passed the whole time.
func _test_a_hub_loadout_survives_a_save_and_load() -> void:
	var chosen: Dictionary = {"weapon": "hammer", "head": "hood", "body": "robe"}
	var payload: Dictionary = _gs().build_climber_save(
		3, 7, 1, false, 0, 120, [], [], 0, [], chosen)
	_expect(payload.has("loadout"), "the climber save actually carries a loadout key")
	# Round-trip through JSON, because that is what disk does and it is where the
	# int/float trap lives that this file's own parser warns about.
	var raw: Variant = JSON.parse_string(JSON.stringify(payload))
	_expect(typeof(raw) == TYPE_DICTIONARY, "the payload survives JSON")
	var state: Dictionary = _gs().parse_climber_save(raw as Dictionary)
	var back: Dictionary = state.get("loadout", {})
	for slot: String in ["weapon", "head", "body"]:
		_expect(String(back.get(slot, "")) == String(chosen[slot]),
			"slot '%s' came back as '%s' (wanted '%s')"
			% [slot, String(back.get(slot, "")), String(chosen[slot])])
	_completes("a_hub_loadout_survives_a_save_and_load")


## Every save written before this existed has no `loadout` key. That is not a
## migration — an absent loadout IS "the class defaults win" — and it must not error.
func _test_an_old_save_without_a_loadout_still_loads() -> void:
	var old: Dictionary = {
		"version": 2, "current_floor": 4, "highest_floor": 9, "falls": 2,
		"tower_conquered": false, "rank_power": 0, "xp": 300,
		"unlocked_nodes": [], "unlocked_classes": [0, 1],
	}
	var state: Dictionary = _gs().parse_climber_save(old)
	_expect(state.has("loadout"), "an old save still yields a loadout key")
	_expect((state["loadout"] as Dictionary).is_empty(),
		"...and it is EMPTY, which is what 'the class default wins' looks like")
	_expect(int(state["current_floor"]) == 4, "the rest of the old save is untouched")
	_completes("an_old_save_without_a_loadout_still_loads")


## ⚠ THE SANITISER IS NOT DEFENSIVE NOISE. `loadout` is fed straight to
## `rig.set_equipment`, which validates NOTHING and accepts any slot string — so a
## hand-edited or future-versioned save could otherwise put an arbitrary key into
## the rig's equipment dictionary and have it drawn (or not) forever.
func _test_a_save_cannot_carry_junk_into_the_rig() -> void:
	var junk: Dictionary = {
		"weapon": "sword", "cape": "red", "head": 7, "body": "", "": "x",
	}
	var clean: Dictionary = _gs().sanitize_loadout(junk)
	_expect(String(clean.get("weapon", "")) == "sword", "a real slot survives")
	_expect(not clean.has("cape"), "an unknown slot is dropped")
	_expect(not clean.has("head"), "a non-string value is dropped")
	_expect(not clean.has("body"), "an empty value is dropped rather than stored")
	_expect(not clean.has(""), "the empty key is dropped")
	_expect(_gs().sanitize_loadout("not a dict").is_empty(),
		"a non-dictionary yields an empty loadout instead of erroring")
	_completes("a_save_cannot_carry_junk_into_the_rig")


## THE FIRST HALF OF THE ASK, pinned so it cannot come back. A weapon must be chosen
## at the hub Armory and nowhere else — the tower hands out spells, not swords.
func _test_the_tower_never_spawns_a_weapon() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://scripts/combat/FloorBuilder.gd")
	_expect(src != "", "FloorBuilder is readable")
	_expect(not src.contains("WEAPON_PICKUP_SCENE.instantiate"),
		"the tower does not instantiate a weapon pickup")
	_expect(not src.contains("preload(\"res://scenes/combat/WeaponPickup.tscn\")"),
		"...and does not even preload one — a dead preload still drags the scene "
		+ "into every headless suite's compile graph")
	_completes("the_tower_never_spawns_a_weapon")
