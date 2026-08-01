# Render THE RUN-END CEREMONY — both endings — so the maker can LOOK at them
# rather than read about them. GUI binary only; a `--headless` run uses the dummy
# renderer, reports success, and saves a blank PNG:
#
#   python python-tools/run_capture.py run_end
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/run_end_capture.gd
#
# ⚠ WHY THIS PHOTOGRAPHS THE CARD DIRECTLY RATHER THAN PLAYING A RUN. Reaching the
# victory beat by PLAYING means clearing five floors and a guardian; reaching the
# game-over beat means dying to a specific floor. Both are minutes per look, which
# is the exact price at which nobody looks. In-game the same two screens are one
# director tap away — F1 -> FLOOR -> "Trigger the death path" (game over) and
# F1 -> FLOOR -> F5 then "Force CLEARED" + the exit portal (victory) — and this is
# the still frame of what those produce.
#
# The scene reads `/root/GameState.last_run`, so each shot swaps in a stub carrying
# exactly the outcome being photographed. That is also the honest test of the card:
# every number on it comes from `GameState.build_outcome` and nothing else.
#
# Frame 1 — `user://run_end_victory.png`
#     CONQUERED. Gold, the whole tower inked in, guardian felled, top rank.
#     THE READ TEST: does beating the game look like beating the game?
# Frame 2 — `user://run_end_game_over.png`
#     RUBBED OUT. Ash red, the floors above where you died left blank, the fall
#     counter the town clocks, and — the line that matters after a wipe — proof the
#     climb is still yours ("your best: floor 5").
# Frame 3 — `user://run_end_walked.png`
#     PAGE LEFT OPEN. You took the LEAVE THE TOWER portal mid-climb. The third beat,
#     which is neither a win nor a loss and used to be indistinguishable from both.
# Frame 4 — `user://run_end_coop_friendly_fire.png`
#     A co-op card with the FRIENDLY FIRE row on it — the first time this game has
#     ever told the players what they did to each other.
extends SceneTree

const SUMMARY_SCENE: String = "res://scenes/ui/RunSummary.tscn"
## ⚠ LOADED BY PATH, NEVER NAMED. `GameState` resolves only as an autoload and a
## `--script` run registers none, so a bare `GS.build_outcome(...)` here would
## be a compile error for this whole file.
const GS_PATH: String = "res://scripts/GameState.gd"

## The four cards, as [file name, what it proves, outcome args]. Every outcome is
## built by `GameState.build_outcome` itself, so a shot cannot show a shape the game
## does not actually produce.
var _shots: Array = []

var _card: Control = null
var _stub: Node = null


func _initialize() -> void:
	var GS: GDScript = load(GS_PATH) as GDScript
	_shots = [
		["run_end_victory", "CONQUERED: the whole tower inked in, guardian felled",
			GS.build_outcome(5, 43, true, false, ["Fire", "Storm"], 5, "Ascendant", 0, 0, 5, 5)],
		["run_end_game_over", "RUBBED OUT: died on 4, and the climb is still yours",
			GS.build_outcome(4, 26, false, true, ["Shadow"], 3, "Ranked", 6, 0, 5, 5)],
		["run_end_walked", "PAGE LEFT OPEN: took the leave portal on floor 3",
			GS.build_outcome(3, 18, false, false, ["Ice"], 2, "Climber", 2, 0, 4, 5)],
		["run_end_coop_friendly_fire", "the FRIENDLY FIRE row: 214 damage, to each other",
			GS.build_outcome(4, 31, false, true, ["Fire", "Ice"], 3, "Ranked", 3, 214, 5, 5)],
	]
	_run()


func _run() -> void:
	# A FIXED WINDOW, so the four frames are comparable and so the card is judged at
	# something close to the shape a phone gives it (16:9 landscape).
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await process_frame
	for shot: Array in _shots:
		await _show(shot[2])
		await _shot(String(shot[0]), String(shot[1]))
		_teardown()
		# ⚠ queue_free LANDS AT THE END OF THE FRAME. Without this the next card was
		# built alongside a corpse still in the tree, and the second frame came out with
		# no UI at all and the page drawn at twice the window width.
		await process_frame
		await process_frame
	quit(0)


## Stand up the card with `outcome` in front of it.
##
## ⚠ THE STUB IS THE WHOLE TRICK. A `--script` run REGISTERS NO AUTOLOADS, so there
## is no real `GameState` to read `last_run` off — and the card, correctly, draws a
## neutral "no run" state when it finds none. A bare `Node` named `GameState` under
## the root is what `get_node_or_null(^"/root/GameState")` is looking for, and it
## lets each frame be photographed with a known outcome instead of a live one.
func _show(outcome: Dictionary) -> void:
	# ⚠ THE REAL AUTOLOAD WINS IF THERE IS ONE, AND THE FIRST VERSION OF THIS DID NOT
	# CHECK. `run_capture.py` launches the GUI binary, which DOES register autoloads
	# even under `--script` — so a second node also called "GameState" was silently
	# renamed by Godot, the card found the real (empty) autoload instead, and all four
	# frames photographed the same neutral no-run state while reporting success.
	var live: Node = root.get_node_or_null(^"GameState")
	if live != null:
		live.set("last_run", outcome)
	else:
		_stub = Node.new()
		_stub.name = "GameState"
		_stub.set_script(load("res://tools/_stub_run.gd"))
		_stub.set("last_run", outcome)
		root.add_child(_stub)
	_card = (load(SUMMARY_SCENE) as PackedScene).instantiate()
	root.add_child(_card)
	# The scene is anchored full-rect; ASSIGNING `size` on top of that fights the
	# anchors (Godot warns, then overrides) and was what blew the second frame up.
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ⚠ WAIT ON THE PAGE'S OWN CLOCK, NOT ON A FRAME COUNT. The page inks the climb in
	# over REVEAL_TIME seconds; a `--script` run has no frame cap, so 90 frames was
	# about 0.09 s of world time and every shot came out with the tower half drawn.
	var page: Node = _card.get("_paper")
	var guard: int = 0
	# The page stops processing the instant it is finished — so THAT is the signal.
	# Watching `_t` cross a number bigger than REVEAL_TIME hangs forever, because the
	# clock stops the moment it arrives.
	while page != null and page.is_processing() and guard < 3000:
		guard += 1
		await process_frame
	await process_frame


func _teardown() -> void:
	if _card != null and is_instance_valid(_card):
		root.remove_child(_card)
		_card.queue_free()
	_card = null
	if _stub != null and is_instance_valid(_stub):
		root.remove_child(_stub)
		_stub.queue_free()
	_stub = null


func _shot(shot_name: String, what: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("run_end_capture: no frame for %s" % shot_name)
		return
	var path: String = "user://%s.png" % shot_name
	img.save_png(path)
	print("run_end_capture: %s -> %s (%s)" % [
		shot_name, ProjectSettings.globalize_path(path), what])
