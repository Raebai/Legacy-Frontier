# Run: godot --headless --path godot-project --script tools/slice7_test_botmatch_rules.gd
# EQUAL FOOTING, CHARACTERFUL STATS — the maker's two requirements, which pull against
# each other, pinned against the REAL scene so neither can quietly become the other.
#
#   "it needs them to start equal ... but give them health etc based on their
#    characters, who they are"
#
# Resolved as: footing is mirrored and identical, stats are not. This suite asserts
# both halves, plus the third thing the maker asked for that nothing could deliver —
# a fight that can END. The two invisible reasons it could not are asserted directly,
# because both are one line away from coming back:
#   · the ring-out model must be OFF (with it on, hits pile onto `damage_pct` and HP
#     never moves, so nothing that watches HP can ever see a knockdown),
#   · the win condition must hang off `health_changed` and NOT off polling `hp <= 0`
#     (`Hero._die` heals to full in the same call as the fatal hit, so HP never rests
#     at zero for a single frame).
#
# ⚠ THE HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the
# enclosing function and hands back the type's zero, which that idiom reads as "no
# failures". Failures accumulate on the MEMBER `_fails`; every test records a
# COMPLETION SENTINEL as its last line, so an aborted test fails BY ABSENCE.
extends SceneTree

const MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"

const TESTS: Array[String] = [
	"footing_is_mirrored", "stats_differ_by_class", "vitality_covers_every_class",
	"ringout_model_is_off", "death_is_signal_driven", "a_bout_can_end",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _match: Node = null
var _fighters: Array[Node2D] = []


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_vitality_table()          # pure, no scene needed — run before the build
	_build()
	_test_footing()
	_test_stats()
	_test_ringout_off()
	_test_death_is_signal_driven()
	_test_bout_can_end()
	if _match != null:
		_match.free()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("BotMatch rules tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("BotMatch rules tests: all PASS")
		quit(0)
	return true


func _build() -> void:
	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	if script != null:
		# JUGGERNAUT vs SHADOWBLADE: the widest vitality gap on the table, so
		# "stats differ" is asserted where it is meant to be most visible.
		script.set("class_a", 3)
		script.set("class_b", 1)
		script.set("swap_sides", false)
		script.set("auto_rematch", false)
	_match = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(_match)
	for n: Node in get_nodes_in_group(&"hero"):
		if n is Node2D:
			_fighters.append(n as Node2D)


## MIRRORED, about the centre of the fight floor, on the same ground line. The stage's
## own showcase spawns are 520 / 1080 — a midpoint of 800, which is 80 px right of the
## flat ground's actual centre, so one fighter started nearer the stairs than the
## other did the mound. That is not "equal".
func _test_footing() -> void:
	if _fighters.size() != 2:
		_expect(false, "two fighters on the stage, not %d" % _fighters.size())
		return
	var a: Vector2 = _fighters[0].global_position
	var b: Vector2 = _fighters[1].global_position
	var centre: float = BotMatch.FLOOR_CENTRE_X
	_expect(is_equal_approx(a.y, b.y), "both start on the same ground line (%.0f / %.0f)"
		% [a.y, b.y])
	_expect(absf((centre - a.x) - (b.x - centre)) < 0.5,
		"both start the same distance from the centre of the floor (%.0f / %.0f about %.0f)"
		% [centre - a.x, b.x - centre, centre])
	_expect(a.x < b.x, "fighter A is the LEFT one, so side order matches tree order")
	_completes("footing_is_mirrored")


## ...and their health is NOT identical, because a Juggernaut with an assassin's
## health bar is not a Juggernaut.
func _test_stats() -> void:
	if _fighters.size() != 2:
		return
	var a: int = int(_fighters[0].get("max_hp"))
	var b: int = int(_fighters[1].get("max_hp"))
	_expect(a > b, "the JUGGERNAUT carries more health than the SHADOWBLADE (%d vs %d)"
		% [a, b])
	# ...but the SPREAD stays sane. Characterful is a multiplier on one shared pool,
	# not a licence for one fighter to have twice the other's bar.
	_expect(float(a) / maxf(float(b), 1.0) < 2.0,
		"...and not by so much that it stops being one fight (%d vs %d)" % [a, b])
	_completes("stats_differ_by_class")


## One row per class, and every row a real multiplier. A short table would silently
## hand every class past its end the fallback 1.0 — including whichever class gets
## added next.
func _test_vitality_table() -> void:
	var v: Array[float] = BotMatch.CLASS_VITALITY
	_expect(v.size() == BotMatch.CLASS_LABELS.size(),
		"one vitality row per class (%d rows, %d classes)"
		% [v.size(), BotMatch.CLASS_LABELS.size()])
	for i: int in v.size():
		_expect(v[i] > 0.5 and v[i] < 2.0,
			"%s's vitality is a scale factor, not a rewrite (%.2f)"
			% [BotMatch.CLASS_LABELS[i], v[i]])
	_completes("vitality_covers_every_class")


## ⚠ REASON ONE THAT FIGHTS NEVER ENDED. `VersusArena.showcase_ringout` ships TRUE and
## this scene has to turn it off: under the Smash model a hit accumulates `damage_pct`
## rather than draining HP, so a bout runs to 600% and nobody ever goes down.
func _test_ringout_off() -> void:
	var arena: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena == null:
		return
	_expect(not bool(arena.get("showcase_ringout")),
		"the bot match runs the HP-death model, not the ring-out model")
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		_expect(not bool(gs.get("ringout_mode")),
			"...and the live GameState agrees, so `Hero.take_damage` drains HP")
	_completes("ringout_model_is_off")


## ⚠ REASON TWO. `Hero._die()` outside a run runs `hp = max_hp` in the same call as
## the fatal hit, so `hp` is never observed at or below zero by any once-a-frame poll.
## The signal fires first, with the zero in it. This asserts the wiring EXISTS —
## `_test_bout_can_end` asserts it works.
func _test_death_is_signal_driven() -> void:
	if _fighters.size() != 2:
		return
	for f: Node2D in _fighters:
		_expect(f.has_signal("health_changed"), "a fighter publishes `health_changed`")
		if not f.has_signal("health_changed"):
			continue
		var listeners: Array = f.get_signal_connection_list("health_changed")
		var heard: bool = false
		for c: Dictionary in listeners:
			var cb: Callable = c["callable"]
			if cb.get_object() == _match:
				heard = true
		_expect(heard, "...and the match is listening to it (this IS the win condition)")
	_completes("death_is_signal_driven")


## The end-to-end claim, asserted without waiting for a real fight: drive the fatal
## signal by hand and the match must resolve, name a winner, and freeze.
func _test_bout_can_end() -> void:
	if _fighters.size() != 2 or _match == null:
		return
	_expect(not bool(_match.call("match_over")), "the bout is live before anybody falls")
	# The exact shape `Hero.take_damage` emits on the fatal frame.
	_fighters[1].emit_signal("health_changed", 0, int(_fighters[1].get("max_hp")))
	_expect(bool(_match.call("match_over")), "a fighter at zero ENDS the match")
	var r: Dictionary = _match.call("result")
	_expect(String(r.get("outcome", "")) == "KO", "...as a KO (got `%s`)" % r.get("outcome", ""))
	_expect(int(r.get("winner_side", -1)) == 0, "...won by the other fighter")
	_expect(String(r.get("winner", "")) == "JUGGERNAUT",
		"...named correctly (got `%s`)" % r.get("winner", ""))
	_expect(paused, "...and the stage is frozen on the killing frame")
	paused = false
	_completes("a_bout_can_end")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true
