# Run: godot --headless --path godot-project --script tools/probe_destructible_bot_fight.gd
#       [-- --seconds=30 --pairs=3 --hp=190 --difficulty=3]
#
# HOW MUCH STAGE IS LEFT AFTER TWO BOTS HAVE HAD A MINUTE WITH IT.
#
# This is THE tuning instrument for `DestructibleStage.CARVE_MIN_DAMAGE`. The budget
# question is not "does a hole open" — a unit test answers that — it is "after a real
# bout, is there a stage". Nothing about a screenshot tells you that, and reasoning
# about it from the damage table is exactly the sort of confident arithmetic that
# [[feedback_a_comment_is_not_an_implementation]] exists to warn about: the table says
# what a spell COULD do, the fight says how often it actually lands on rock.
#
# It boots the REAL `BotMatch` — the same scene the maker opens from Lobby -> Watch Bots
# and the same one the clip pipeline films — with `VersusArena.destructible_stage` on,
# and samples the stage every game-second.
#
# ⚠ THE CONTROLS COME FIRST, because a probe that reports "3% of the stage was removed"
# is indistinguishable from a probe whose fighters never cast anything.
#   * both fighters must still be alive and moving at the end, or have resolved a bout
#   * SOME rock must come off (a flat 0 means the wiring is dead, not that it is tuned)
#   * the refused-hit counter must be NON-ZERO (a flat 0 means the threshold is doing
#     nothing at all, which reads identical to a perfectly-tuned threshold from outside)
#
# ⚠ GAME SECONDS, NOT WALL SECONDS. Hit-stop drops `Engine.time_scale` to 0.05, so wall
# time runs far ahead of fight time; `get_process_delta_time()` is already scaled, which
# is why the clock here accumulates it rather than reading `Time.get_ticks_msec`.
# [[feedback_measure_the_channel_the_viewer_gets]].
extends SceneTree

const MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"

## Same hand-picked matchups `botmatch_sim` uses, and for the same reason: an
## opposed-element pair and a melee-vs-ranged pair say more about what actually lands on
## the ground than a random draw would.
const PAIRINGS: Array[Vector2i] = [
	Vector2i(6, 5),   # STORMCALLER vs CRYOMANCER
	Vector2i(2, 0),   # BRAWLER vs ARCANIST — the melee question
	Vector2i(3, 1),   # JUGGERNAUT vs SHADOWBLADE
	# ⚠ ADDED WHEN THE GROUND-AIMED SOURCES WERE WIRED, BECAUSE THE THREE ABOVE COULD
	# NOT SEE HALF OF THEM. Reading `SpellLibrary.SLOT_ROLES`, the carried spells that
	# now bite the floor are the Brawler's Shockwave Stomp + Meteor Fist, the
	# Juggernaut's Boulder Hurl + Fault Line, and the WARLOCK'S GRAVE TIDE — and no
	# pairing here held a Warlock, so Grave Tide was wired and then measured by nothing
	# at all. A source the budget instrument cannot see is a source with no budget.
	# Swordsaint opposite because it is the other kit holding an earth spell.
	Vector2i(7, 8),   # WARLOCK vs SWORDSAINT — the only pairing that casts Grave Tide
]
const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

## ⚠ THESE MIRROR `BotMatch`'s SHIPPED DEFAULTS, AND THE FIRST VERSION DID NOT.
## It ran 190 hp / 30 s, and that is not the fight anybody watches: `BotMatch.fighter_hp`
## is 440 and `round_seconds` is 75, which is what Lobby -> Watch Bots opens and what the
## clip pipeline films. At 190 hp the three bouts resolved in 5.5 s / 8.8 s / 1.4 s — the
## probe was answering "how much rock comes off in five seconds", then that answer was
## being read as "how much rock comes off in a bout". Same numbers at 440 hp: 9.7 s /
## 31.7 s / 12.4 s, and the middle bout's carve went 0.16% -> 0.76% on the extra time
## alone, with nothing about the wiring changed.
##
## The budget question is about the bout the maker SEES, so the default is the bout the
## maker sees. Pass `--hp=` / `--seconds=` to ask a different question deliberately.
var _seconds: float = 75.0
var _pairs: int = 4
var _hp: int = 440
var _difficulty: int = 3
## Run the identical bouts with the destructible stage OFF, as the control arm.
var _stage_off: bool = false
## Wall-clock escape hatch. Raised with the bout length: three 75 game-second bouts at
## the hit-stop time scale run well past the old 240 s, and a probe that silently gets
## cut off at the cap reports a PARTIAL carve as a final one.
var _wall_cap: float = 900.0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_seconds = maxf(a.substr(10).to_float(), 1.0)
		elif a.begins_with("--pairs="):
			_pairs = clampi(int(a.substr(8).to_int()), 1, PAIRINGS.size())
		elif a.begins_with("--hp="):
			_hp = maxi(a.substr(5).to_int(), 1)
		elif a.begins_with("--difficulty="):
			_difficulty = clampi(a.substr(13).to_int(), 0, 3)
		elif a == "--stage-off":
			_stage_off = true
	call_deferred("_go")


func _go() -> void:
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	var match_script: GDScript = load(MATCH_SCRIPT) as GDScript
	var scene: PackedScene = load(MATCH_SCENE) as PackedScene
	if arena_script == null or match_script == null or scene == null:
		printerr("[carve-budget] could not load the arena / match scripts")
		quit(1)
		return
	# The stage under test, pinned. Rolling a layout would compare three silhouettes.
	# ⚠ `--stage-off` RUNS THE SAME BOUTS WITH THE FLAG DOWN, and it is not a curiosity.
	# The steering-veto rate below is only meaningful as a COMPARISON: "bots held 40
	# times" says nothing on its own, because they hold on telegraphs and pits that have
	# been there since long before any of this. Carving is only implicated if the rate
	# MOVES. [[feedback_dont_narrate_underpowered_measurements]].
	arena_script.set("destructible_stage", not _stage_off)
	arena_script.set("stage_layout", 0)
	match_script.set("auto_rematch", false)
	match_script.set("difficulty", _difficulty)
	match_script.set("fighter_hp", _hp)
	match_script.set("round_seconds", _seconds + 5.0)

	print("[carve-budget] CARVE_MIN_DAMAGE=%d  radius %.1f..%.1f px  %.0f game-second bouts"
		% [DestructibleStage.CARVE_MIN_DAMAGE, DestructibleStage.CARVE_RADIUS_MIN,
			DestructibleStage.CARVE_RADIUS_MAX, _seconds])
	var any_carve: bool = false
	var any_refusal: bool = false
	for i: int in _pairs:
		var pair: Vector2i = PAIRINGS[i]
		match_script.set("class_a", pair.x)
		match_script.set("class_b", pair.y)
		match_script.set("swap_sides", i % 2 == 1)
		var row: Dictionary = await _one_bout(scene, pair)
		any_carve = any_carve or float(row.get("carved", 0.0)) > 0.0
		any_refusal = any_refusal or int(row.get("refused", 0)) > 0

	# ── the controls, stated as findings rather than assumed ──
	print("")
	if not any_carve:
		printerr("[carve-budget] CONTROL FAILED: not one cell came off in any bout."
			+ " Either the wiring is dead or nothing ever hit the ground. The budget"
			+ " numbers above are meaningless until this is non-zero.")
	if not any_refusal:
		# ⚠ NOT A FAILURE, AND IT USED TO BE PRINTED AS ONE. With the damage shelf retired
		# (`CARVE_MIN_DAMAGE` is 1) this counter is the ANTI-CASCADE ledger's, and the
		# ledger only fires when ONE source hits rock twice inside its own crater — a zone
		# burning on a spot, an ice-spike line standing, a beam held. A four-bout sample of
		# bot fights routinely contains none of those, so a zero here is a statement about
		# what the bots cast, not about whether the mechanism works.
		#
		# The mechanism is asserted where it can be forced:
		# `tools/slice_test_destructible_hitpoint.gd`, test 4, which drives 33 drifting
		# ticks into one spot and fails if the floor erodes. Reporting it as CONTROL FAILED
		# here trained the reader to ignore a line that will usually be zero.
		# [[feedback_harnesses_lie_verify_them]].
		print("[carve-budget] note: nothing was refused. With CARVE_MIN_DAMAGE at %d"
			% DestructibleStage.CARVE_MIN_DAMAGE
			+ " that counter is the anti-cascade ledger's, and no repeating ground source"
			+ " (zone / spike line / held beam) came up in these bouts. Expected.")
	quit(0)


func _one_bout(scene: PackedScene, pair: Vector2i) -> Dictionary:
	var node: Node = scene.instantiate()
	root.add_child(node)
	for _f: int in 6:
		await process_frame
	var stage: DestructibleStage = _find_stage()
	if stage == null and not _stage_off:
		printerr("[carve-budget] no DestructibleStage in the tree — is the flag on?")
		node.free()
		return {}
	var vetoes0: int = BotBrain.steer_vetoes
	var label: String = "%s vs %s" % [CLASS_NAMES[pair.x], CLASS_NAMES[pair.y]]
	if stage == null:
		print("\n[carve-budget] %s  (CONTROL ARM — destructible stage OFF)" % label)
	else:
		print("\n[carve-budget] %s  (stage: %d solid cells, %d shapes, %d blocks)"
			% [label, stage.solid_count(), stage.shape_count(), stage.block_count()])
	var clock: float = 0.0
	var next_mark: float = 5.0
	var wall0: float = float(Time.get_ticks_msec()) / 1000.0
	var over: bool = false
	while clock < _seconds:
		await process_frame
		if not is_instance_valid(node):
			break
		if stage != null and not is_instance_valid(stage):
			break
		clock += root.get_process_delta_time()
		if node.has_method("match_over") and bool(node.call("match_over")):
			over = true
			break
		if float(Time.get_ticks_msec()) / 1000.0 - wall0 > _wall_cap:
			break
		if clock >= next_mark and stage != null:
			next_mark += 5.0
			print("    t=%5.1fs  carved %5.2f%%  events %3d  refused %4d  shapes %3d"
				% [clock, stage.carved_fraction() * 100.0, stage.carve_events,
					stage.refused_hits + stage.repeat_refused_hits, stage.shape_count()])
	var row: Dictionary = {
		"carved": stage.carved_fraction() if stage != null else 0.0,
		"events": stage.carve_events if stage != null else 0,
		"refused": (stage.refused_hits + stage.repeat_refused_hits) if stage != null else 0,
	}
	var outcome: String = ""
	var match_seconds: float = clock
	if is_instance_valid(node) and node.has_method("result"):
		var r: Dictionary = node.call("result") as Dictionary
		outcome = "%s %s" % [String(r.get("outcome", "?")), String(r.get("winner", ""))]
		match_seconds = float(r.get("seconds", clock))
	print("    ---- %s | probe clock %.1f s | match clock %.1f s%s | %s"
		% [label, clock, match_seconds, " | BOUT ENDED" if over else "", outcome])
	if stage != null:
		print("    carved %.2f%% of the rock over %d carve event(s); %d hit(s) refused"
			% [stage.carved_fraction() * 100.0, stage.carve_events,
				stage.refused_hits + stage.repeat_refused_hits])
		print("    deepest hole %.0f px into a %.0f px column; widest severed run %.0f px"
			% [_deepest(stage), _column_depth(stage), _widest_gap(stage)])
		print("    rebuild: %.0f us total, worst frame %.0f us, %d block re-merge(s) deferred"
			% [float(stage.rebuild_usec_total), float(stage.rebuild_usec_worst),
				stage.deferred_rebuilds])
	# ⚠ THE STRANDING NUMBER, AND IT IS A RATE RATHER THAN A COUNT. Bouts here run
	# anywhere from 3 to 104 game-seconds, so a raw veto tally is mostly a measure of how
	# long the fight lasted. Per game-second is the only form in which the flag-on and
	# flag-off arms can be laid beside each other, and the comparison is the whole point:
	# bots hold on telegraphs and authored pits that predate all of this, so a veto rate
	# means nothing on its own and everything as a delta.
	var vetoes: int = BotBrain.steer_vetoes - vetoes0
	print("    steering vetoes: %d over %.1f s = %.2f/s (BotBrain._safest held the bot)"
		% [vetoes, maxf(match_seconds, 0.001),
			float(vetoes) / maxf(match_seconds, 0.001)])
	if is_instance_valid(node):
		node.free()
	paused = false
	await process_frame
	return row


func _find_stage() -> DestructibleStage:
	for n: Node in root.get_tree().get_nodes_in_group(DestructibleStage.GROUP_NAME):
		var s: DestructibleStage = n as DestructibleStage
		if s != null:
			return s
	return null


## How far below its ORIGINAL surface the rock has been eaten, at the worst column.
func _deepest(s: DestructibleStage) -> float:
	var worst: int = 0
	for cx: int in s.cols:
		var top: int = -1
		var cy: int = 0
		while cy < s.rows:
			if s.is_solid(cx, cy):
				break
			cy += 1
		if cy >= s.rows:
			continue  # this column is gone entirely; counted by `_widest_gap`
		# The original surface for this column.
		var oy: int = 0
		while oy < s.rows and not _was_rock(s, cx, oy):
			oy += 1
		if oy >= s.rows:
			continue
		top = cy - oy
		worst = maxi(worst, top)
	return float(worst) * DestructibleStage.CHUNK


## The width of the widest run of columns with NO rock left where rock used to be —
## i.e. a severed stage. 0 means nobody has punched through yet.
func _widest_gap(s: DestructibleStage) -> float:
	var run: int = 0
	var best: int = 0
	for cx: int in s.cols:
		var had: bool = false
		var has: bool = false
		for cy: int in s.rows:
			if _was_rock(s, cx, cy):
				had = true
			if s.is_solid(cx, cy):
				has = true
				break
		if had and not has:
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return float(best) * DestructibleStage.CHUNK


## The authored depth of the fight-floor column, for scale on the "deepest hole" line.
func _column_depth(_s: DestructibleStage) -> float:
	return 320.0


## ⚠ ASKS THE STAGE; DOES NOT RECONSTRUCT. The first version of this rebuilt the
## original silhouette from the authored terrace table with a +2 px sample offset, and
## the cell-edge rounding disagreed with the stage's own centre-sampled grid: it
## reported an 80 px deep hole on a bout in which NOTHING had been carved, in three runs
## running. Two grids, one truth. [[feedback_harnesses_lie_verify_them]].
func _was_rock(s: DestructibleStage, cx: int, cy: int) -> bool:
	return s.was_rock(cx, cy)
