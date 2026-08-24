# Run: godot --headless --path godot-project --script tools/slice7_test_botmatch.gd
# BOT vs BOT, WATCHABLE — asserts `scenes/combat/BotMatch.tscn` against the real
# scenes: it stands up TWO bot-driven heroes (not one, not a player), both carry the
# shipped `BotController`, both are hostile to each other, a `ClipDirector` is bound
# to the camera, and — the one that bites — the showcase STATICS are cleared on the
# way out so a bot match cannot leak two bots into the versus duel.
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
	"two_bots_no_player", "both_are_hostile", "director_is_bound",
	"statics_cleared_on_exit", "matchup_is_not_a_mirror", "follow_cta_is_centred",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _match: Node = null
var _arena: Node = null


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_build()
	_test_two_bots_no_player()
	_test_both_are_hostile()
	_test_director_is_bound()
	_test_matchup_is_not_a_mirror()
	_test_follow_cta_is_centred()
	_test_statics_cleared()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("BotMatch tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("BotMatch tests: all PASS")
		quit(0)
	return true


func _build() -> void:
	_match = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(_match)
	for child: Node in _match.get_children():
		if child.has_method("clip_director"):
			_arena = child
			return


## TWO fighters, and NEITHER of them is the player. This is the whole ask — "bots to
## fight each other" — and the assertion that catches the mode falling back to the
## duel, which builds one bot and one human-driven hero.
func _test_two_bots_no_player() -> void:
	var heroes: Array[Node] = get_nodes_in_group("hero")
	_expect(heroes.size() == 2, "two fighters on the stage, not %d" % heroes.size())
	var driven: int = 0
	for h: Node in heroes:
		# ⚠ THE MARKER IS `Hero.controller`, not a `bot_driven` flag. There is no such
		# flag anywhere in this codebase; `SpellHandoff` once asked heroes for one and
		# every call silently aborted, because `bool(null)` is an illegal conversion
		# that kills the enclosing function. A null controller means a HUMAN.
		if h.get("controller") != null:
			driven += 1
	_expect(driven == 2, "both fighters are bot-driven (got %d)" % driven)
	_completes("two_bots_no_player")


## Damage in this codebase routes by faction. Two heroes both defaulted to `enemy`
## would swing at each other all day and connect with nothing — a silent empty room
## that reads as "the bots are passive".
func _test_both_are_hostile() -> void:
	for h: Node in get_nodes_in_group("hero"):
		var hostile: Variant = h.get("hostile_group")
		_expect(String(hostile) == "hero",
			"a showcase fighter is hostile to `hero` (got `%s`)" % hostile)
	_completes("both_are_hostile")


## The camera operator exists and owns a camera. Without it the mode is just the old
## fixed pair framing with a menu bolted on.
func _test_director_is_bound() -> void:
	if _arena == null:
		_expect(false, "the bot match instantiated the versus arena")
		return
	var d: Object = _arena.call("clip_director")
	_expect(d != null, "a ClipDirector was built")
	if d == null:
		return
	_expect(d.get("camera") != null, "...and it has a camera to drive")
	_expect(d.has_method("heat") and d.has_method("is_hot"),
		"...and publishes the two questions a capture tool asks")
	_completes("director_is_bound")


## ⚠ THE CALL TO ACTION IS ACTUALLY IN THE MIDDLE OF THE FRAME.
##
## This test exists because the first version was NOT, and nothing caught it. It was
## built with `set_anchors_preset(PRESET_FULL_RECT)`, which moves the anchors and leaves
## the OFFSETS alone — so the Label kept a 0x0 rect and rendered hard against the
## top-left corner, where centred alignment inside an empty box centres nothing. The
## full suite went 176/176 green over it; the fault was only visible in a rendered
## frame, twenty-five minutes of shoot later.
##
## So the assertion is on the LABEL'S RECT rather than on its alignment flags: the flags
## were correct the whole time and said nothing about where the text landed.
func _test_follow_cta_is_centred() -> void:
	if _match == null:
		_expect(false, "the bot match exists")
		return
	var card: Node = _find_by_name(_match, "Follow")
	_expect(card != null, "the result card carries a Follow label")
	var lab := card as Label
	if lab == null:
		return
	_expect(lab.text.length() > 0, "...with something written on it")
	# A full-rect Label inherits its parent's size; a zero-size one is the bug.
	var sz: Vector2 = lab.size
	_expect(sz.x > 100.0 and sz.y > 100.0,
		"...sized to the frame (%.0fx%.0f), not collapsed to a corner" % [sz.x, sz.y])
	_expect(lab.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
		and lab.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
		"...and centred within it")
	_completes("follow_cta_is_centred")


## Depth-first search by node name — the result card is built in code, so there is no
## scene path to reach it by.
func _find_by_name(root: Node, want: String) -> Node:
	if root.name == want:
		return root
	for ch: Node in root.get_children():
		var hit: Node = _find_by_name(ch, want)
		if hit != null:
			return hit
	return null


## The two fighters are different classes. A mirror match is a legal thing to WATCH
## but it is the pairing most likely to stall (identical spacing bands, identical
## reads), so the shipped default must not be one.
func _test_matchup_is_not_a_mirror() -> void:
	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	if script == null:
		return
	_expect(int(script.get("class_a")) != int(script.get("class_b")),
		"the default matchup is not a mirror")
	_expect(int(script.get("fighter_hp")) > 0, "fighters have a real HP pool")
	_completes("matchup_is_not_a_mirror")


## ⚠ THE ONE THAT BITES. `showcase_a` / `showcase_b` / `showcase_directed` /
## `showcase_hp_override` are STATICS: they outlive the node, the scene and the
## scene change that leaves it. Walking out of a bot match without clearing them
## hands the versus duel two bots and no player, with the cause two scenes back.
func _test_statics_cleared() -> void:
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script == null or _match == null:
		return
	_expect(int(arena_script.get("showcase_a")) >= 0,
		"the showcase statics are set while the match is live")
	_match.free()      # immediate, so _exit_tree runs before the assertions below
	_match = null
	_arena = null
	_expect(int(arena_script.get("showcase_a")) < 0, "showcase_a is cleared on exit")
	_expect(int(arena_script.get("showcase_b")) < 0, "showcase_b is cleared on exit")
	_expect(not bool(arena_script.get("showcase_directed")),
		"the directed-camera flag is cleared on exit")
	_expect(int(arena_script.get("showcase_hp_override")) == 0,
		"the HP override is cleared on exit")
	_completes("statics_cleared_on_exit")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true
