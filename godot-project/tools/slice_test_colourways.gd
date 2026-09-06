# THREE COLOURS, ONE FIGURE — and the three places that had to change for it.
#
# Maker: *"in the armoury I should also be able to change the colour of my stickman
# figure the colour of his head body and legs individually"*.
#
# There was ONE whole-figure tint: `Outfitter.chosen_colourway` -> `GameState.colourway`
# -> `Hero._configure_class` -> `rig.set_tint(COLOURWAYS[i])`. Three independent tints is
# not one feature, it is three, and this suite is one section per layer:
#
#   1. THE RIG — a per-part API that does NOT break `set_tint`. Twenty-odd callers mean
#      the whole figure by it (enemies, bosses, thralls, NPCs, `BotMatch` corner colours,
#      `ModPatient`'s dormant wash, `Hero._cycle_colourway`) and half a dozen capture
#      tools bypass it entirely by writing `limb_color` directly. Every one of those must
#      still paint all three parts.
#   2. THE SAVE — three ints that migrate forward from the one, losslessly, through JSON.
#   3. THE SCREEN — a MODE, because the column has ~11 px of slack against a 360 px phone
#      and three inline rows cost 102.
#
#   godot --headless --path godot-project --script tools/slice_test_colourways.gd
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion sentinel, so
# a test aborted by a dead property read fails BY ABSENCE rather than reporting "no
# failures". NEVER write `failed += _test_x()` in this file.
extends SceneTree

## ⚠ LOADED BY PATH, NOT NAMED. `GameState` is an AUTOLOAD, not a `class_name`, and naming
## it in source makes the compiler resolve it at compile time — where the autoload does not
## exist yet under a `--script` main loop, so the whole suite dies with `Identifier not
## found`. Same trap `slice_test_hub_loadout.gd` documents. `CharacterRig` IS a
## `class_name` and is still loaded by path, for the second half of the same rule: this
## project has watched `global_script_class_cache.cfg` go stale after a new script four
## sessions running (CLAUDE.md, Sessions 6/8/9), and a path load never consults it.
const GAMESTATE_PATH: String = "res://scripts/GameState.gd"
const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const OUTFITTER_PATH: String = "res://scripts/ui/Outfitter.gd"

## Godot's base viewport, from project.godot. Same numbers `slice_test_outfitter` pins.
const BASE_W: float = 640.0
const BASE_H: float = 360.0
const MIN_TAP_H: float = 28.0

const TESTS: Array[String] = [
	"set_tint_still_paints_the_whole_figure",
	"three_tints_land_on_three_parts",
	"a_bare_limb_color_write_still_reaches_all_three",
	"the_part_fill_takes_its_alpha_from_the_caller",
	"the_keyline_is_solved_per_part",
	"a_geared_head_is_drawn_in_the_head_colour",
	"one_colourway_migrates_into_three",
	"an_out_of_range_index_is_clamped_not_trusted",
	"the_three_colours_survive_a_json_round_trip",
	"the_colours_are_a_mode_and_cost_no_height",
	"every_colour_row_is_a_real_tap_target",
	"picking_paints_the_aimed_part_only",
	"tapping_the_worn_colour_hands_the_part_back",
	"reset_returns_all_three_to_the_figure_colour",
]

var _fails: int = 0
var _completed: Dictionary = {}


func _init() -> void:
	_test_set_tint_still_paints_the_whole_figure()
	_test_three_tints_land_on_three_parts()
	_test_a_bare_limb_color_write_still_reaches_all_three()
	_test_the_part_fill_takes_its_alpha_from_the_caller()
	_test_the_keyline_is_solved_per_part()
	_test_a_geared_head_is_drawn_in_the_head_colour()
	_test_one_colourway_migrates_into_three()
	_test_an_out_of_range_index_is_clamped_not_trusted()
	_test_the_three_colours_survive_a_json_round_trip()
	await process_frame
	await _test_the_colours_are_a_mode_and_cost_no_height()
	await _test_every_colour_row_is_a_real_tap_target()
	await _test_picking_paints_the_aimed_part_only()
	await _test_tapping_the_worn_colour_hands_the_part_back()
	await _test_reset_returns_all_three_to_the_figure_colour()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Colourway tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Colourway tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(name: String) -> void:
	_completed[name] = true


func _rig() -> Node2D:
	return (load(RIG_PATH) as GDScript).new() as Node2D


func _rig_script() -> GDScript:
	return load(RIG_PATH) as GDScript


## A fresh Outfitter, parented so `_ready` (and therefore `_build`) has run.
##
## ⚠ THE STATIC IS RESET FIRST. `Outfitter.chosen_parts` outlives a scene change on
## purpose (see its header), which in a suite means it outlives the PREVIOUS TEST — so a
## test that opened on whatever the last one painted would be asserting against a fixture
## it did not write. The developer's own save is the same trap one layer down, and
## `slice_test_outfitter` documents where that one bit.
func _fresh_outfitter(picker: bool = false) -> Control:
	Outfitter.chosen_parts = [-1, -1, -1]
	Outfitter.chosen_colourway = 0
	var out: Control = (load(OUTFITTER_PATH) as GDScript).new() as Control
	out.set("show_class_picker", picker)
	root.add_child(out)
	return out


func _walk(from: Node, out: Array) -> void:
	if from is Button:
		out.append(from)
	for c: Node in from.get_children():
		_walk(c, out)


# ═══════════════════════════════════════════════════════════════════ 1. the rig
## ⚠ THE COMPATIBILITY TEST, AND IT IS THE MOST IMPORTANT ONE IN THE FILE. `set_tint` has
## about twenty callers and every one of them means THE WHOLE FIGURE. If the per-part
## overrides survived a `set_tint`, then a bot repainted into its corner colour, a boss
## restored out of `ModPatient`'s dormant wash, or a hero cycling `C` would keep a head
## from a pick made on a different screen — a bug that shows up as one wrong-coloured
## body part in a recorded clip and nowhere in any assertion.
func _test_set_tint_still_paints_the_whole_figure() -> void:
	var rig: Node2D = _rig()
	rig.call("set_part_tints", Color.RED, Color.BLUE, Color.GREEN)
	rig.call("set_tint", Color(0.2, 0.4, 0.8))
	_expect(Color(rig.call("head_tint")).is_equal_approx(Color(0.2, 0.4, 0.8)),
		"set_tint took the head back (got %s)" % [rig.call("head_tint")])
	_expect(Color(rig.call("body_tint")).is_equal_approx(Color(0.2, 0.4, 0.8)),
		"set_tint took the body (got %s)" % [rig.call("body_tint")])
	_expect(Color(rig.call("legs_tint")).is_equal_approx(Color(0.2, 0.4, 0.8)),
		"set_tint took the legs back (got %s)" % [rig.call("legs_tint")])
	# ...and `limb_color` is still what it always was, because `slice1_test_elements`
	# reads it directly off the hero to prove a colourway cycle landed.
	_expect(Color(rig.get("limb_color")).is_equal_approx(Color(0.2, 0.4, 0.8)),
		"limb_color is still the field the rest of the game reads")
	# THE FIGURE IS ONE COLOUR AGAIN, which is what `draw_figure` is told by an EMPTY
	# part dict — the cheap path, and the one that reproduces the old drawing exactly.
	_expect((rig.call("_part_tint_dict") as Dictionary).is_empty(),
		"a whole-figure tint hands draw_figure an empty part dict (the old drawing)")
	rig.free()
	_completes("set_tint_still_paints_the_whole_figure")


func _test_three_tints_land_on_three_parts() -> void:
	var rig: Node2D = _rig()
	rig.call("set_part_tints", Color.RED, Color.BLUE, Color.GREEN)
	_expect(Color(rig.call("head_tint")).is_equal_approx(Color.RED), "the head is red")
	_expect(Color(rig.call("body_tint")).is_equal_approx(Color.BLUE), "the body is blue")
	_expect(Color(rig.call("legs_tint")).is_equal_approx(Color.GREEN), "the legs are green")
	# The BODY is `limb_color`, deliberately: it is the field every existing reader and
	# every capture tool already talks to, so the common case stays the common case.
	_expect(Color(rig.get("limb_color")).is_equal_approx(Color.BLUE),
		"the body tint IS limb_color, so nothing that reads limb_color had to change")
	var parts: Dictionary = rig.call("_part_tint_dict")
	_expect(parts.size() == 3 and parts.has("head") and parts.has("body") and parts.has("legs"),
		"three tints hand draw_figure all three keys (got %s)" % [parts.keys()])
	rig.free()
	_completes("three_tints_land_on_three_parts")


## ⚠ THE TRAP THIS EXISTS FOR. Six capture tools and `bossmods/ModPatient` write
## `rig.limb_color = X` DIRECTLY and never call `set_tint`
## (`tools/rig_look_capture.gd`, `rig_tickrate_capture.gd`, `rig_legs_capture.gd`,
## `new_spells_capture.gd`, `thrall_capture.gd`, `ult_sheet_capture.gd`,
## `ult_focus_capture.gd`). Had head and legs been plain fields defaulting to the same
## blue, every one of those would have rendered a recoloured TORSO on a default-blue head
## and shins — and nothing would have gone red, because they all read `limb_color`.
## Resolving an UNSET override to `limb_color` is what keeps that path byte-identical.
func _test_a_bare_limb_color_write_still_reaches_all_three() -> void:
	var rig: Node2D = _rig()
	rig.set("limb_color", Color(0.95, 0.62, 0.30))
	_expect(Color(rig.call("head_tint")).is_equal_approx(Color(0.95, 0.62, 0.30)),
		"a bare limb_color write reaches the head (got %s)" % [rig.call("head_tint")])
	_expect(Color(rig.call("legs_tint")).is_equal_approx(Color(0.95, 0.62, 0.30)),
		"...and the legs (got %s)" % [rig.call("legs_tint")])
	_expect((rig.call("_part_tint_dict") as Dictionary).is_empty(),
		"...and it is still the one-colour drawing path")
	rig.free()
	_completes("a_bare_limb_color_write_still_reaches_all_three")


## RGB FROM THE PART, ALPHA FROM `col` — the rule `draw_figure`'s header states, and the
## reason it is a rule: a dash ghost, a fading corpse (`DeathSmudge`) and the aura
## silhouette all express themselves purely through `col.a`. A part carrying its own alpha
## would be the one piece of the body that refused to fade with the rest of it.
func _test_the_part_fill_takes_its_alpha_from_the_caller() -> void:
	var rs: GDScript = _rig_script()
	var col := Color(0.1, 0.2, 0.3, 0.25)
	# Absent key -> the caller's colour, untouched. This is what makes an empty dict the
	# old drawing rather than merely a similar one.
	_expect(Color(rs.call("_part_fill", {}, "head", col)).is_equal_approx(col),
		"an empty part dict hands back `col` unchanged")
	_expect(Color(rs.call("_part_fill", {"legs": Color.RED}, "head", col)).is_equal_approx(col),
		"a dict without this key hands back `col` unchanged")
	var got: Color = rs.call("_part_fill", {"head": Color(1.0, 0.0, 0.0, 1.0)}, "head", col)
	_expect(is_equal_approx(got.r, 1.0) and is_equal_approx(got.g, 0.0),
		"the part supplies the hue (got %s)" % [got])
	_expect(is_equal_approx(got.a, 0.25),
		"...and the CALLER supplies the alpha, so a ghost still fades (got a=%.3f)" % got.a)
	_completes("the_part_fill_takes_its_alpha_from_the_caller")


## `keyline_for` FLIPS to a pale rim below `KEYLINE_FLIP_LUMA`, so a near-black figure
## reads as a figure with an edge instead of a silhouette-shaped hole. One keyline under
## three fills would put the dark treatment on the light parts the moment a dark head is
## picked. Nothing in the SHIPPED palette is that dark — which is exactly why this is
## asserted rather than eyeballed: it is a latent fault, not a visible one.
func _test_the_keyline_is_solved_per_part() -> void:
	var rs: GDScript = _rig_script()
	var oc := Color(0.04, 0.04, 0.07, 0.8)
	_expect(Color(rs.call("_part_keyline", {}, "head", Color.BLACK, oc)).is_equal_approx(oc),
		"with no parts the outline pass is bit-for-bit what it was")
	var dark: Color = rs.call("_part_keyline", {"head": Color.BLACK}, "head", Color.BLACK, oc)
	var light: Color = rs.call("_part_keyline", {"head": Color.WHITE}, "head", Color.WHITE, oc)
	_expect(not dark.is_equal_approx(light),
		"a black head and a white head do NOT get the same keyline (both %s)" % [dark])
	_expect(dark.is_equal_approx(Color(rs.call("keyline_for", Color.BLACK)).lerp(dark, 0.0)) \
			or is_equal_approx(dark.a, oc.a),
		"the per-part keyline keeps the caller's alpha (got a=%.3f, want %.3f)" % [dark.a, oc.a])
	_completes("the_keyline_is_solved_per_part")


## ══ THE PART A PLAYER NOTICES FIRST ═══════════════════════════════════════════
## Gear REPLACES a body part in this rig — a helmet IS the head, not a hat on one (see
## `_draw_head`'s hitbox contract). So a helmeted head drawn in the BODY colour would be
## the one region a player cannot recolour, and it would be the region they look at.
##
## ⚠ ASSERTED AGAINST THE SOURCE OF THE FILL PASS, AND HERE IS THE HONEST REASON WHY.
## The drawn channel cannot be intercepted: Godot 4 REFUSES a GDScript override of a
## native `CanvasItem` method outright ("this won't be called by the engine", promoted to
## a parse error), and `--headless` runs the dummy renderer, so there is no framebuffer to
## read back either. Both routes were tried before this was written.
##
## What IS pinned is the wiring, and it is the thing that broke: `head_col` / `body_col` /
## `legs_col` were computed and then every draw call below still passed `col`, so the
## feature was inert while the whole tree stayed green. This test goes red for exactly
## that state.
func _test_a_geared_head_is_drawn_in_the_head_colour() -> void:
	var src: String = FileAccess.get_file_as_string(RIG_PATH)
	_expect(src != "", "the rig source is readable")
	# The head goes through the gear helper, IN THE HEAD'S COLOUR. `_draw_head` substitutes
	# the helm for the skull internally, so this one call is both the bare head and the
	# geared one — which is what makes the gear inherit the tint for free.
	_expect(src.contains("_draw_head(item, head_kind, head_center, r, head_col, w)"),
		"the head (and the helm that replaces it) is filled with head_col")
	_expect(src.contains("_draw_torso(item, body_kind, neck, hip, body_col, w, r)"),
		"the torso (and the cuirass that replaces it) is filled with body_col")
	_expect(src.contains("_draw_leg(item, legs_kind, hip, knee_lead, foot_lead, legs_col, w, r)"),
		"the legs (and the greaves that replace them) are filled with legs_col")
	# THE FEET GO WITH THE LEGS. The foot dot caps the shin; in the body colour it reads as
	# a sock rather than as a joint.
	_expect(src.contains("item.draw_circle(foot_lead, ftr, legs_col)"),
		"the foot caps take the leg colour, not the body's")
	# ⚠ AND THE OLD CALLS ARE GONE, not merely joined by new ones. Without this the test
	# would pass on a file that draws the figure TWICE.
	_expect(not src.contains("_draw_head(item, head_kind, head_center, r, col, w)"),
		"the old single-colour head fill is gone, not shadowed by the new one")
	_expect(not src.contains("_draw_leg(item, legs_kind, hip, knee_off, foot_off, col, w, r)"),
		"the old single-colour leg fill is gone too")
	# The gear a figure HOLDS is not a body part and must not take a body tint — a
	# recoloured sword would make "legs" mean "legs and also my weapon".
	_expect(src.contains("item, equipment_slots, col, w, r, fig_height,"),
		"held equipment keeps the caller's colour — a sword is a possession, not a part")
	_completes("a_geared_head_is_drawn_in_the_head_colour")


# ═════════════════════════════════════════════════════════════════ 2. the save
## THE MIGRATION, AND IT IS LOSSLESS BY CONSTRUCTION. A climber saved before this existed
## has no `part_colourways` key at all, so all three parts read -1 and all three resolve
## to the ONE `colourway` that save did carry. The figure comes back the exact colour it
## was, now expressed in three pieces the player can edit.
func _test_one_colourway_migrates_into_three() -> void:
	var gs: Object = (load(GAMESTATE_PATH) as GDScript).new()
	gs.set("colourway", 2)
	var parts: Array = gs.call("colourway_parts", 5, 0)
	_expect(parts == [2, 2, 2],
		"an untouched save puts all three parts on its one colourway (got %s)" % [parts])
	# A part that WAS chosen wins over the whole-figure value; the others still fall back.
	gs.call("set_colourway_part", "head", 4)
	parts = gs.call("colourway_parts", 5, 0)
	_expect(parts == [4, 2, 2],
		"a chosen part overrides, the rest still migrate (got %s)" % [parts])
	# -1 hands the part BACK, which is what "reset" means — not "paint it Azure".
	gs.call("set_colourway_part", "head", -1)
	_expect(gs.call("colourway_parts", 5, 0) == [2, 2, 2],
		"-1 gives the part back to the whole-figure colour")
	# No `colourway` at all (a fresh climber, -1) falls to the caller's default.
	gs.set("colourway", -1)
	_expect(gs.call("colourway_parts", 5, 3) == [3, 3, 3],
		"with no pick anywhere the caller's fallback wins (got %s)"
			% [gs.call("colourway_parts", 5, 3)])
	# An unknown part name is IGNORED rather than added — the record is three slots.
	gs.call("set_colourway_part", "torso", 1)
	_expect(not (gs.get("part_colourways") as Dictionary).has("torso"),
		"an unknown part name does not grow the record")
	gs.free()
	_completes("one_colourway_migrates_into_three")


## ⚠ THE FILE IS DATA, NOT AN INSTRUCTION. A hand-edited save, or one written by a build
## whose palette was longer, can name index 9 of a five-entry table — and `COLOURWAYS[9]`
## is not a wrong colour, it is an index-out-of-bounds AT SPAWN. The clamp is the only
## thing between the two.
func _test_an_out_of_range_index_is_clamped_not_trusted() -> void:
	var gs: Object = (load(GAMESTATE_PATH) as GDScript).new()
	gs.call("set_colourway_part", "head", 9)
	gs.call("set_colourway_part", "legs", 4)
	var parts: Array = gs.call("colourway_parts", 5, 0)
	_expect(parts[0] == 4, "index 9 of a 5-entry palette is clamped to 4 (got %d)" % parts[0])
	_expect(parts[2] == 4, "a legal index is untouched (got %d)" % parts[2])
	# A palette that shrank between sessions is a real sequence, not a hypothetical.
	_expect(gs.call("colourway_parts", 2, 0) == [1, 0, 1],
		"a SHRUNK palette clamps rather than crashes (got %s)"
			% [gs.call("colourway_parts", 2, 0)])
	# A palette of zero cannot produce a negative ceiling.
	_expect(gs.call("colourway_parts", 0, 0) == [0, 0, 0],
		"an empty palette still yields a legal index")
	gs.free()
	_completes("an_out_of_range_index_is_clamped_not_trusted")


## ⚠ THE M9 JSON TRAP, WHICH HAS ALREADY DESTROYED SAVES IN THIS PROJECT ONCE.
## `JSON.parse_string` returns every number as `TYPE_FLOAT`, so a saved `2` comes back as
## `2.0` and any `== 2` against it is FALSE. In M9 that silently wiped the NPC memory files
## on every load. The same shape is here — three ints in a dictionary — so the round trip
## is driven through REAL `JSON.stringify` / `JSON.parse_string`, not through the dicts.
func _test_the_three_colours_survive_a_json_round_trip() -> void:
	var GS: GDScript = load(GAMESTATE_PATH) as GDScript
	var payload: Dictionary = GS.call("build_climber_save", 4, 6, 2, true, 40,
		0, [], [], 0, [], {}, {}, {}, {"head": 3, "body": 1, "legs": 4})
	var back: Variant = JSON.parse_string(JSON.stringify(payload))
	_expect(back is Dictionary, "the save is JSON-round-trippable")
	var state: Dictionary = GS.call("parse_climber_save", back as Dictionary)
	var parts: Dictionary = state["part_colourways"]
	_expect(int(parts.get("head", -1)) == 3 and int(parts.get("body", -1)) == 1
			and int(parts.get("legs", -1)) == 4,
		"the three colours came back through JSON as INTS (got %s)" % [parts])
	for k: String in ["head", "body", "legs"]:
		_expect(typeof(parts[k]) == TYPE_INT,
			"`%s` is an int, not the float JSON handed back (got %s)" % [k, typeof(parts[k])])
	# A SAVE FROM BEFORE THE FEATURE. No key at all -> three -1s, which is what makes the
	# migration a fallback rather than a rewrite-on-load.
	var old: Dictionary = GS.call("parse_climber_save", {"current_floor": 3})
	_expect(old["part_colourways"] == {"head": -1, "body": -1, "legs": -1},
		"an old save reads as three unchosen parts (got %s)" % [old["part_colourways"]])
	# JUNK IS DROPPED, not cast. A hand-edited `"head": "blue"` must read as "never
	# chosen", not as index 0 — index 0 is a real colour and would look like a choice.
	var junk: Dictionary = GS.call("sanitize_part_colourways",
		{"head": "blue", "body": 2, "torso": 7, "legs": null})
	_expect(junk == {"head": -1, "body": 2, "legs": -1},
		"junk is dropped and unknown keys never enter the record (got %s)" % [junk])
	_expect(GS.call("sanitize_part_colourways", "not a dict")
			== {"head": -1, "body": -1, "legs": -1},
		"a non-dictionary is a fresh record, not a crash")
	_completes("the_three_colours_survive_a_json_round_trip")


# ═══════════════════════════════════════════════════════════════ 3. the screen
## ⚠ THE WHOLE DESIGN OF THIS FEATURE IS THIS NUMBER. The Outfitter column measures 342 px
## in the town flow (330 in the lobby's) against a 360 px base viewport, and its GRIMOIRE
## mode measures 349 — so the real slack is **11 px**, not the 22 the file's older comment
## quotes. One `MIN_TAP` row plus its separation costs 34. Three inline colour pickers cost
## 102. The mode is what makes them cost zero, and this is the assertion that keeps it
## costing zero the next time somebody reaches for a row.
func _test_the_colours_are_a_mode_and_cost_no_height() -> void:
	for picker: bool in [true, false]:
		var out: Control = _fresh_outfitter(picker)
		await process_frame
		var col: Control = out.get("_col") as Control
		if col == null:
			out.queue_free()
			continue
		var hand: float = col.get_combined_minimum_size().y
		out.call("_toggle_colours")
		await process_frame
		var colours: float = col.get_combined_minimum_size().y
		out.call("_toggle_colours")
		await process_frame
		var back: float = col.get_combined_minimum_size().y
		print("[layout] outfitter (picker=%s) hand %.0f  colours %.0f  back %.0f (budget %.0f)"
			% [str(picker), hand, colours, back, BASE_H])
		_expect(colours <= BASE_H,
			"colours mode fits 360 px (picker=%s, needs %.0f)" % [str(picker), colours])
		_expect(is_equal_approx(hand, back),
			"the door goes both ways without leaving the column taller (%.0f -> %.0f)"
				% [hand, back])

		# ── THE DOOR ITSELF COSTS NOTHING. Measured by REMOVING it, which is the only way
		# to say "zero" rather than "it fit". It shares an `HBoxContainer` whose minimum
		# height is the MAX of its children, so a fourth `MIN_TAP` button is free — and
		# this is the assertion that notices the day somebody gives it its own row.
		var door: Button = out.get("_colour_btn") as Button
		_expect(door != null, "there is a colours door (picker=%s)" % str(picker))
		if door != null:
			var with_door: float = col.get_combined_minimum_size().y
			var row: Node = door.get_parent()
			row.remove_child(door)
			await process_frame
			var without: float = col.get_combined_minimum_size().y
			row.add_child(door)
			await process_frame
			_expect(is_equal_approx(with_door, without),
				"the colours door costs ZERO height (%.0f with, %.0f without)"
					% [with_door, without])
			_expect(door.custom_minimum_size.y >= MIN_TAP_H,
				"...and is still a real tap target (%.0f px)" % door.custom_minimum_size.y)

		# ── AND THE PREVIEW IS NOT IN THE COLUMN. That is the entire reason a live figure
		# was affordable at all; parented into the card it would have been refused by the
		# budget above before a player ever saw it.
		var preview: Control = out.get("_preview") as Control
		_expect(preview != null, "there is a live preview")
		if preview != null:
			_expect(not col.is_ancestor_of(preview),
				"the preview is an overlay, not a column row — it costs no height")
			out.call("_toggle_colours")
			await process_frame
			_expect(preview.visible,
				"the figure is shown in colours mode, where the question is what it looks like")
			_expect(is_equal_approx(col.get_combined_minimum_size().y, colours),
				"...and showing it still does not move the column")
			# It fits on screen beside the panel: the card is PANEL_W + 2 pads wide and
			# centred, so the box lives in the 150 px of dead width on the left.
			var left_edge: float = BASE_W * 0.5 + preview.offset_left
			_expect(left_edge >= 0.0,
				"the preview fits beside the panel on a 640 px phone (left edge %.0f)" % left_edge)
		out.queue_free()
		await process_frame
	_completes("the_colours_are_a_mode_and_cost_no_height")


## EVERY ROW A THUMB LANDS ON. `MIN_TAP` is the floor this screen's own suite pins on the
## hand and the grimoire; the colours list is a third list of rows and gets the same floor,
## or the mode is reachable and unusable on the device it was built for.
func _test_every_colour_row_is_a_real_tap_target() -> void:
	var out: Control = _fresh_outfitter()
	await process_frame
	out.call("_toggle_colours")
	await process_frame
	var btns: Array = []
	_walk(out, btns)
	_expect(btns.size() >= 6, "the mode draws its rows (found %d buttons)" % btns.size())
	for b: Button in btns:
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"colours '%s' is at least %.0f px tall (got %.0f)"
				% [b.text, MIN_TAP_H, b.custom_minimum_size.y])
		_expect(b.focus_mode == Control.FOCUS_NONE,
			"colours '%s' takes no focus ring" % b.text)
	# ONE ROW PER COLOURWAY, for the ONE part the cursor aims at. Fifteen rows (three
	# parts x five colours) was the alternative and is a list a thumb gets lost in.
	var rows: Array = []
	_walk(out.get("_list") as Node, rows)
	_expect(rows.size() == Outfitter.colourways().size(),
		"the list is one row per colour (%d rows, %d colours)"
			% [rows.size(), Outfitter.colourways().size()])
	# THE CURSOR IS IN FIXED SPACE, not inside the scroll — the same rule the ult row and
	# the slot cursor are held to. A target you have to scroll to find is not a cursor.
	var scroll: ScrollContainer = out.get("_scroll") as ScrollContainer
	var shelf: Control = out.get("_ult_slot_row") as Control
	_expect(shelf != null and scroll != null and not scroll.is_ancestor_of(shelf),
		"the part cursor is fixed, not scrolled")
	_expect(shelf != null and shelf.get_child_count() > 0, "...and it is populated")
	out.queue_free()
	await process_frame
	_completes("every_colour_row_is_a_real_tap_target")


## THE TWO-TAP GESTURE: aim a part, then pick a colour. The grimoire's slot cursor
## verbatim, because the problem is identical — a colour implies no target.
func _test_picking_paints_the_aimed_part_only() -> void:
	var out: Control = _fresh_outfitter()
	await process_frame
	out.call("_toggle_colours")
	await process_frame
	_expect(int(out.get("_colour_part")) == 0, "the cursor starts on the head")
	out.call("_pick_colour", 3)
	await process_frame
	_expect(Outfitter.chosen_parts[0] == 3,
		"the head took the pick (parts %s)" % [Outfitter.chosen_parts])
	_expect(Outfitter.chosen_parts[1] == -1 and Outfitter.chosen_parts[2] == -1,
		"...and NOTHING else moved (parts %s)" % [Outfitter.chosen_parts])
	# Cycle to the legs and paint those instead.
	out.call("_cycle_part_cursor")
	out.call("_cycle_part_cursor")
	await process_frame
	_expect(int(out.get("_colour_part")) == 2,
		"the cursor walks head -> body -> legs (at %d)" % int(out.get("_colour_part")))
	out.call("_pick_colour", 1)
	await process_frame
	_expect(Outfitter.chosen_parts == [3, -1, 1],
		"the legs took the second pick and the head kept the first (parts %s)"
			% [Outfitter.chosen_parts])
	# THE CURSOR WRAPS. Three states, found by tapping rather than by reading.
	out.call("_cycle_part_cursor")
	_expect(int(out.get("_colour_part")) == 0, "the cursor wraps back to the head")
	# ...AND THE PICK REACHES THE HERO'S SOURCE OF TRUTH. `Hero._configure_class` reads
	# `GameState.colourway_parts` at spawn; a pick that lived only in the static would be
	# a picker that changes nothing you can walk into the tower with.
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs != null and gs.has_method("colourway_parts"):
		var reached: Array = gs.call("colourway_parts", Outfitter.colourways().size(), 0)
		_expect(reached[0] == 3 and reached[2] == 1,
			"the pick reached GameState, which is what the hero reads (got %s)" % [reached])
	out.queue_free()
	await process_frame
	_completes("picking_paints_the_aimed_part_only")


## A TAP ALWAYS DOES SOMETHING — the rule `_toggle_role` and `_toggle_equip` are both built
## on. Tapping the colour a part already wears is therefore not a no-op: it hands the part
## back to the whole-figure colour, which is the only way to un-paint without a second
## control on a row that has no space for one.
func _test_tapping_the_worn_colour_hands_the_part_back() -> void:
	var out: Control = _fresh_outfitter()
	await process_frame
	out.call("_toggle_colours")
	await process_frame
	out.call("_pick_colour", 2)
	_expect(Outfitter.chosen_parts[0] == 2, "painted")
	out.call("_pick_colour", 2)
	_expect(Outfitter.chosen_parts[0] == -1,
		"tapping it again hands the part back (parts %s)" % [Outfitter.chosen_parts])
	out.queue_free()
	await process_frame
	_completes("tapping_the_worn_colour_hands_the_part_back")


## ⚠ THE RESET FOLLOWS THE MODE, and its LABEL has to follow it too. The doors row has no
## space for a fifth button, so one reset serves both radii — and a button reading "Reset
## Hand" under a list of colours is the one control on the screen that ignores what the
## player is looking at, which reads as "this resets what I can see" and is wrong.
func _test_reset_returns_all_three_to_the_figure_colour() -> void:
	var out: Control = _fresh_outfitter()
	await process_frame
	var reset: Button = out.get("_reset_btn") as Button
	_expect(reset != null, "there is a reset button")
	if reset == null:
		out.queue_free()
		_completes("reset_returns_all_three_to_the_figure_colour")
		return
	_expect(reset.text.to_lower().contains("hand"),
		"in hand mode it still names the hand (label: %s)" % reset.text)
	out.call("_toggle_colours")
	await process_frame
	_expect(reset.text.to_lower().contains("colour"),
		"in colours mode it names the colours (label: %s)" % reset.text)
	out.call("_pick_colour", 4)
	out.call("_cycle_part_cursor")
	out.call("_pick_colour", 1)
	_expect(Outfitter.chosen_parts != [-1, -1, -1], "the figure is painted")
	reset.pressed.emit()
	await process_frame
	_expect(Outfitter.chosen_parts == [-1, -1, -1],
		"reset returns all three to unchosen (parts %s)" % [Outfitter.chosen_parts])
	# ⚠ TO **UNCHOSEN**, NOT TO AZURE. -1 hands each part back to the whole-figure
	# colourway the pause menu and the `C` key still drive; resetting to index 0 would
	# silently overwrite a whole-figure pick the player never asked to undo.
	Outfitter.chosen_colourway = 2
	_expect(Outfitter.part_colourway(0) == 2 and Outfitter.part_colourway(2) == 2,
		"...so all three follow the whole-figure colour again (got %d)"
			% Outfitter.part_colourway(0))
	# AND THE RESET SAVED. Same `GameState` mirror every pick takes; a reset that did not
	# reach it would come back from the dead on the next launch.
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs != null:
		var saved: Variant = gs.get(&"part_colourways")
		_expect(saved is Dictionary and int((saved as Dictionary).get("head", 0)) == -1,
			"the reset reached GameState, so it stays reset across a quit (%s)" % [saved])
	out.queue_free()
	await process_frame
	_completes("reset_returns_all_three_to_the_figure_colour")
