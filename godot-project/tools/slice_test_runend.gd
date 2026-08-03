# Run: godot --headless --path godot-project --script tools/slice_test_runend.gd
#
# THE RUN-END CEREMONY, THE LEAVE-PORTAL CONFIRM, AND THE FRIENDLY-FIRE DIAL.
#
# What this pins, and why each line of it was a real bug:
#
#   * **A run ends on the ceremony, not the parked town.** Winning AND losing both
#     used to `change_scene` into `scenes/Main.tscn` — the v0.0 AI-NPC hub, which
#     needs an Ollama server on 127.0.0.1:11434 and therefore cannot work on a phone
#     at all. There was no victory screen anywhere in the tower, and no route back to
#     the title from anything but the credits.
#   * **The persistent climb is untouched by that move.** `_floor`, `_highest_floor`,
#     `_falls` and `tower_conquered` are written BEFORE the ceremony, exactly as
#     before. The hub was never what made the climb persist.
#   * **A run that never started cannot reach the ceremony.** The F6 sandbox, a boss
#     rush, and a free-play stage with nobody on it all have no run to summarise, and
#     a death there must not bounce anyone to a results card.
#   * **The run-ending portal asks first.** Two portals with opposite consequences
#     spawned together and neither had a confirmation.
#   * **Friendly fire has exactly ONE switch and a player-facing row.** It shipped as
#     a static bool reachable only from the debug director.
extends SceneTree

# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion
# sentinel, so a test aborted by a dead property read fails BY ABSENCE rather than
# reading as "zero failures".

const TESTS: Array[String] = [
	"the_ceremony_replaces_the_hub",
	"the_hub_survives_as_an_opt_in",
	"both_endings_are_classified",
	"a_victory_card_shows_the_victory",
	"a_wipe_card_shows_the_wipe",
	"an_unstarted_run_has_no_ceremony",
	"the_climb_is_written_before_the_ceremony",
	"the_card_fits_a_phone",
	"nothing_on_the_critical_path_loads_the_parked_hub",
	"the_leave_portal_confirms",
	"friendly_fire_is_one_switch",
	"the_dial_reaches_the_bolt",
	"the_read_never_guesses",
	"the_read_is_banked_and_shown",
	"the_pause_menu_carries_the_dial",
]

var _fails: int = 0
var _completed: Dictionary = {}

const GS_PATH: String = "res://scripts/GameState.gd"
const ARENA_PATH: String = "res://scripts/combat/Arena.gd"
const NET_PATH: String = "res://scripts/Net.gd"
const SUMMARY_SCENE: String = "res://scenes/ui/RunSummary.tscn"

const BASE_W: float = 640.0
const BASE_H: float = 360.0
const MIN_TAP_H: float = 28.0


func _init() -> void:
	var GS: GDScript = load(GS_PATH) as GDScript
	_test_the_ceremony_replaces_the_hub(GS)
	_test_the_hub_survives_as_an_opt_in(GS)
	_test_both_endings_are_classified(GS)
	_test_a_victory_card_shows_the_victory(GS)
	_test_a_wipe_card_shows_the_wipe(GS)
	_test_an_unstarted_run_has_no_ceremony(GS)
	_test_the_climb_is_written_before_the_ceremony(GS)
	_test_nothing_on_the_critical_path_loads_the_parked_hub()
	_test_the_leave_portal_confirms()
	_test_friendly_fire_is_one_switch()
	_test_the_dial_reaches_the_bolt()
	_test_the_read_is_banked_and_shown(GS)
	# The rest need a live tree: a Control reports no meaningful size until it has
	# been through a layout pass.
	await process_frame
	# ⚠ GROUP MEMBERSHIP IS FLUSHED AT IDLE. `add_to_group` in `_init` leaves
	# `is_in_group()` true while `get_nodes_in_group()` still answers EMPTY, so a
	# teammate lookup run before the first frame silently finds nobody.
	await _test_the_read_never_guesses()
	await _test_the_card_fits_a_phone(GS)
	await _test_the_pause_menu_carries_the_dial()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Run-end tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Run-end tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _source(path: String) -> String:
	# CRLF-NORMALISED — see the same fix in `slice_test_death.gd` / `slice_test_netspell.gd`.
	# This repo's working-tree .gd files are CRLF (`core.autocrlf=true`, no
	# `.gitattributes`), so every `\n`-bearing needle below silently finds nothing.
	#
	# It bites this suite in a second, nastier way: `_code_only()` strips comments with
	# `line.substr(0, hash_at)`, which removes the trailing `\r` from COMMENT lines but
	# not from CODE lines. The mixed result made the `body.find("\nfunc ")` boundary
	# search skip `func visit_hub` (preceded by a comment, so it ends in a bare `\n`)
	# and overshoot by 1105 chars — swallowing `visit_hub`, which legitimately names
	# HUB_SCENE twice, and failing `end_run` for a reference that is not in it.
	return FileAccess.get_file_as_string(path).replace("\r\n", "\n")


## Source with comments stripped at the first `#` on each line. Every file involved
## here EXPLAINS at length why the hub was moved off the critical path, so a naive
## grep for `Main.tscn` hits the explanation rather than any live code.
func _code_only(path: String) -> String:
	var out: String = ""
	for line: String in _source(path).split("\n"):
		var hash_at: int = line.find("#")
		out += (line if hash_at < 0 else line.substr(0, hash_at)) + "\n"
	return out


func _walk(from: Node, out: Array, want: String) -> void:
	if (want == "Button" and from is Button) or (want == "CheckButton" and from is CheckButton):
		out.append(from)
	for c: Node in from.get_children():
		_walk(c, out, want)


# ═══════════════════════════════════════════════════ where a run ends
func _test_the_ceremony_replaces_the_hub(GS: GDScript) -> void:
	_expect(ResourceLoader.exists(SUMMARY_SCENE), "the run-summary scene exists")
	_expect(String(GS.SUMMARY_SCENE) == SUMMARY_SCENE, "GameState points at it")
	_expect(ResourceLoader.exists(String(GS.TITLE_SCENE)), "…and at a real title scene")
	var src: String = _code_only(GS_PATH)
	# THE line. `end_run` finished on `_change_scene(HUB_SCENE)` for every terminal
	# state of the game, victory included. Scoped to that function's own body, because
	# `visit_hub` is ALLOWED to name the hub — that is what makes it the opt-in.
	var body: String = src.substr(src.find("func end_run("))
	# ⚠ THE NEEDLE IS AN ESCAPE, NOT A LITERAL LINE BREAK. It used to be written as a
	# real newline inside the quotes, which means the needle inherits THIS FILE'S line
	# terminator — CRLF here — while the haystack is normalised source. `find` then
	# returned -1, `substr(0, -1)` handed back the whole rest of the file, the slice
	# swallowed `visit_hub` (which is ALLOWED to name HUB_SCENE), and the suite failed
	# `end_run` for a reference that is not in it. The shipped code was correct
	# throughout. Measured: sliced body 1105 chars vs the correct 559.
	body = body.substr(0, body.find("\nfunc "))
	_expect(not body.contains("HUB_SCENE"),
		"end_run no longer walks into the parked hub")
	_expect(body.contains("_change_scene(SUMMARY_SCENE"),
		"…it ends on the ceremony instead")
	_completes("the_ceremony_replaces_the_hub")


## PARK, DO NOT DELETE — and do not force anybody through it either. The hub is
## still on disk, still loadable, and still fed by `_pending_ingest`; it is simply
## reachable by choice rather than by losing.
func _test_the_hub_survives_as_an_opt_in(GS: GDScript) -> void:
	_expect(ResourceLoader.exists(String(GS.HUB_SCENE)), "the hub scene is parked, not deleted")
	var gs: Node = GS.new()
	_expect(gs.has_method("visit_hub"), "there is an explicit opt-in route to it")
	_expect(gs.has_method("go_to_title"), "…and a route to the title that did not exist at all")
	# `visit_hub` is the ONLY thing in GameState allowed to name the hub scene now.
	var src: String = _code_only(GS_PATH)
	_expect(src.count("HUB_SCENE") <= 3,
		"the hub is named only where it is declared and opted into (found %d)" % src.count("HUB_SCENE"))
	gs.free()
	_completes("the_hub_survives_as_an_opt_in")


# ═══════════════════════════════════════════════════ both endings
func _test_both_endings_are_classified(GS: GDScript) -> void:
	var win: Dictionary = GS.build_outcome(5, 40, true, false, ["Fire"], 5, "Ascendant", 0, 0, 5, 5)
	var wipe: Dictionary = GS.build_outcome(3, 12, false, true, ["Ice"], 2, "Ranked", 4, 0, 5, 5)
	var walk: Dictionary = GS.build_outcome(2, 8, false, false, [], 1, "Climber", 0, 0, 4, 5)
	_expect(RunSummary.classify(win) == RunSummary.Outcome.CONQUERED, "a conquer reads as a VICTORY")
	_expect(RunSummary.classify(wipe) == RunSummary.Outcome.WIPED, "a party wipe reads as a GAME OVER")
	_expect(RunSummary.classify(walk) == RunSummary.Outcome.WALKED, "walking out alive is its own beat")
	# ⚠ DEATH IS ASKED FIRST ON PURPOSE. A party that wipes ON the guardian floor can
	# carry boss_killed=true from an earlier floor's guardian; classifying on the boss
	# flag first would congratulate a corpse.
	var died_on_boss: Dictionary = GS.build_outcome(5, 30, true, true, [], 3, "Ranked", 1, 0, 5, 5)
	_expect(RunSummary.classify(died_on_boss) == RunSummary.Outcome.WIPED,
		"dying with a guardian already felled is still a game over")
	# Each beat has a headline and a line, and they are different from each other.
	var heads: Dictionary = {}
	for k: int in [RunSummary.Outcome.CONQUERED, RunSummary.Outcome.WIPED, RunSummary.Outcome.WALKED]:
		var h: String = String(RunSummary.HEADLINES.get(k, ""))
		_expect(h != "", "outcome %d has a headline" % k)
		_expect(String(RunSummary.SUBLINES.get(k, "")) != "", "outcome %d has a line" % k)
		heads[h] = true
	_expect(heads.size() == 3, "the three endings do not share a headline")
	_completes("both_endings_are_classified")


func _test_a_victory_card_shows_the_victory(GS: GDScript) -> void:
	var win: Dictionary = GS.build_outcome(5, 40, true, false, ["Fire"], 5, "Ascendant", 0, 0, 5, 5)
	_expect(bool(win.get("conquered", false)), "a conquer is recorded on the outcome itself")
	var flat: String = _flatten(RunSummary.stat_rows(win))
	_expect(flat.contains("floor|5 / 5"), "the card shows the floor out of the tower (%s)" % flat)
	_expect(flat.contains("guardian|felled"), "…that the guardian went down")
	_expect(flat.contains("kills|40"), "…the kill count")
	_expect(flat.contains("rank|Ascendant"), "…and the rank you earned")
	_expect(not flat.contains("falls|"), "a clean run does not print a falls row")
	_completes("a_victory_card_shows_the_victory")


func _test_a_wipe_card_shows_the_wipe(GS: GDScript) -> void:
	var wipe: Dictionary = GS.build_outcome(3, 12, false, true, [], 2, "Ranked", 4, 0, 5, 5)
	var flat: String = _flatten(RunSummary.stat_rows(wipe))
	_expect(flat.contains("floor|3 / 5"), "the card names the floor you died on (%s)" % flat)
	_expect(flat.contains("falls|4"), "…and the running fall count the town clocks")
	_expect(flat.contains("your best|floor 5"), "…without losing your best (the climb is monotonic)")
	_expect(not flat.contains("guardian|"), "no guardian row when you never felled one")
	_completes("a_wipe_card_shows_the_wipe")


func _flatten(rows: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for r: Array in rows:
		parts.append("%s|%s" % [String(r[0]), String(r[1])])
	return " ; ".join(parts)


## ⚠ THE FREE-PLAY / SANDBOX GUARD. "Players must be able to drop onto a stage with
## no bots and just play" — and a stage with no run behind it has nothing to
## summarise. A death there must not produce a results card, must not tick the fall
## counter and must not write a save.
func _test_an_unstarted_run_has_no_ceremony(GS: GDScript) -> void:
	var gs: Node = GS.new()
	gs._run_active = false
	gs._floor = 3
	gs._falls = 0
	gs.end_run(true)
	_expect((gs.last_run as Dictionary).is_empty(), "end_run on no run records nothing")
	gs.game_over()
	_expect(gs._falls == 0, "…and a sandbox death does not tick the fall counter")
	_expect(gs._floor == 3, "…nor move the climb")
	# The arena's own guard: the party-wipe verdict is gated on RUN mode.
	var arena: String = _code_only(ARENA_PATH)
	_expect(arena.contains("if _run_mode and not _wipe_handled:"),
		"Arena only reaches the wipe verdict inside a run")
	gs.free()
	_completes("an_unstarted_run_has_no_ceremony")


## The whole point of the resolution: moving where a run ENDS cost the climb nothing.
func _test_the_climb_is_written_before_the_ceremony(GS: GDScript) -> void:
	var gs: Node = GS.new()
	gs.active_tower = GS.build_default_tower()
	gs._run_active = true
	gs._floor = 4
	gs._highest_floor = 4
	gs._falls = 1
	gs.game_over()
	_expect(gs._falls == 2, "a wipe still ticks the fall counter")
	_expect(gs._highest_floor >= 4, "…and never rolls your best backwards")
	_expect(gs._floor == int(DeathRules.resume_floor_after_game_over(4, gs.total_floors())),
		"…and the resume floor still follows DeathRules, not the ceremony")
	var o: Dictionary = gs.last_run
	_expect(int(o.get("floor_reached", 0)) == 4, "the card is handed the floor you died on")
	_expect(int(o.get("falls", 0)) == 2, "…and the fall count")
	_expect(int(o.get("total_floors", 0)) == gs.total_floors(), "…and the size of the tower")
	gs.free()
	_completes("the_climb_is_written_before_the_ceremony")


## No route a PLAYER can take may end in the parked hub by default. The one that may
## is the explicit button, and it is not on any of these paths.
func _test_nothing_on_the_critical_path_loads_the_parked_hub() -> void:
	var arena: String = _code_only(ARENA_PATH)
	_expect(not arena.contains("res://scenes/Main.tscn"),
		"Arena's pause-exit no longer loads the parked hub")
	var net: String = _code_only(NET_PATH)
	_expect(not net.contains("res://scenes/Main.tscn"),
		"a dropped host no longer strands the client in the parked hub")
	_completes("nothing_on_the_critical_path_loads_the_parked_hub")


# ═══════════════════════════════════════════════════ the two portals
## Two portals with OPPOSITE consequences spawn together on every non-final cleared
## floor. The gold one ends the run for the whole party, and it used to do that on
## contact — no confirmation, seconds after a fight, on a virtual stick.
func _test_the_leave_portal_confirms() -> void:
	var src: String = _source(ARENA_PATH)
	var code: String = _code_only(ARENA_PATH)
	_expect(src.contains("LEAVE THE TOWER"),
		"the run-ending portal says what it costs (it used to say RETURN TO TOWN)")
	for m: String in ["_show_leave_confirm", "_confirm_leave", "_cancel_leave", "_build_return_portal"]:
		_expect(code.contains("func %s(" % m), "Arena has `%s()`" % m)
	# The teeth: contact must reach the CONFIRM, never the run-ender directly.
	var handler: String = code.substr(code.find("func _on_return_taken("))
	handler = handler.substr(0, handler.find("\nfunc _show_leave_confirm"))
	_expect(handler.contains("_show_leave_confirm()"), "touching it opens the confirm")
	_expect(not handler.contains("return_to_hub()") and not handler.contains("request_return()"),
		"…and touching it alone cannot end the run")
	# …and the run-ender is behind the button.
	_expect(code.contains("func _confirm_leave() -> void:"), "the confirm owns the ending")
	# The climb portal is deliberately NOT confirmed — taking it by accident costs
	# nothing you were not already doing.
	var climb: String = code.substr(code.find("func _on_portal_taken("))
	_expect(climb.contains("request_advance()") or climb.contains("advance_floor()"),
		"the climb portal still advances instantly")
	_completes("the_leave_portal_confirms")


# ═══════════════════════════════════════════════════ friendly fire
## ONE SWITCH. The pause menu and the director both write `SpellCaster.friendly_fire`;
## a mirrored bool anywhere would let them disagree, and the first symptom of that is
## a player turning it "off" and still deleting their friend.
func _test_friendly_fire_is_one_switch() -> void:
	var was: bool = SpellCaster.friendly_fire
	SpellCaster.friendly_fire = true
	_expect(FriendlyFire.enabled(), "enabled() reads the shared static")
	_expect(not FriendlyFire.blocks_bolt(), "…and a bolt gets through while it is on")
	FriendlyFire.set_enabled(false)
	_expect(SpellCaster.friendly_fire == false, "set_enabled writes the SAME static")
	_expect(not FriendlyFire.enabled(), "…and reads back off")
	_expect(FriendlyFire.blocks_bolt(), "…and the bolt is blocked")
	FriendlyFire.set_enabled(was)
	_expect(SpellCaster.friendly_fire == was, "restored")
	_completes("friendly_fire_is_one_switch")


## ⚠ THE HALF OF THE DIAL THAT WAS MISSING. Flipping the static re-points every
## SPECTACLE at a faction group, but `Spell._damage_hero` permits a hero hit through
## its OWN clause and never consults it — so "off" meant "off, except for the attack
## every class throws constantly". `Net.deal_damage` is where that is closed.
func _test_the_dial_reaches_the_bolt() -> void:
	var net: String = _code_only(NET_PATH)
	_expect(net.contains("FriendlyFire.blocks_bolt()"),
		"the damage router asks the dial before applying a hero-on-hero bolt")
	_expect(net.contains("_announce_friendly_fire"),
		"…and announces the hit when the dial is on")
	var n: Node = (load(NET_PATH) as GDScript).new()
	_expect(n.has_method("_client_friendly_fire"),
		"the read crosses the wire (it renders on the ATTACKER's peer otherwise)")
	var props: Dictionary = {}
	for p: Dictionary in n.get_property_list():
		props[String(p.get("name", ""))] = true
	_expect(props.has("_friendly_hits"),
		"Net counts rendered reads — the smoke test's only proof the wire delivers")
	n.free()
	_completes("the_dial_reaches_the_bolt")


## A read that sometimes blames your friend for an enemy's hit is worse than silence.
## Nothing here infers: with `Net.MAX_PLAYERS == 2` the attacker is exactly "the
## other live hero", and any other party size answers null rather than picking one.
func _test_the_read_never_guesses() -> void:
	await process_frame
	_expect(not FriendlyFire.report(null, null, 10), "no victim -> no read")
	var a := Node2D.new()
	var b := Node2D.new()
	var c := Node2D.new()
	root.add_child(a)
	root.add_child(b)
	root.add_child(c)
	a.add_to_group(&"hero")
	await process_frame
	_expect(FriendlyFire.other_hero(self, a) == null, "a party of ONE has no teammate to blame")
	b.add_to_group(&"hero")
	await process_frame
	_expect(FriendlyFire.other_hero(self, a) == b, "a party of two identifies the attacker exactly")
	_expect(FriendlyFire.other_hero(self, b) == a, "…from either side")
	_expect(not FriendlyFire.report(a, a, 10), "you cannot friendly-fire yourself")
	var stranger := Node2D.new()
	root.add_child(stranger)
	_expect(not FriendlyFire.report(a, stranger, 10), "…and only a HERO can be blamed")
	c.add_to_group(&"hero")
	await process_frame
	_expect(FriendlyFire.other_hero(self, a) == null,
		"a party of THREE refuses to guess rather than blaming the wrong friend")
	a.queue_free()
	b.queue_free()
	c.queue_free()
	stranger.queue_free()
	_completes("the_read_never_guesses")


## The tally is the acknowledgement that survives the fight: friendly fire is called
## the social engine and NOTHING counted it, so nobody could ever be shown the bill.
func _test_the_read_is_banked_and_shown(GS: GDScript) -> void:
	var gs: Node = GS.new()
	_expect(gs.has_method("notify_friendly_fire"), "GameState banks friendly-fire damage")
	gs.call("notify_friendly_fire", 30)
	gs.call("notify_friendly_fire", 12)
	gs.call("notify_friendly_fire", -5)   # never negative
	_expect(int(gs.call("friendly_damage")) == 42, "…and adds it up (got %d)" % int(gs.call("friendly_damage")))
	var run: Dictionary = GS.build_outcome(3, 9, false, false, [], 1, "Climber", 0, 42, 3, 5)
	_expect(int(run.get("friendly_damage", 0)) == 42, "the outcome carries it")
	_expect(_flatten(RunSummary.stat_rows(run)).contains("friendly fire|42 to each other"),
		"…and the card shows it")
	# A clean co-op run does not get a row it did not earn.
	var clean: Dictionary = GS.build_outcome(3, 9, false, false, [], 1, "Climber", 0, 0, 3, 5)
	_expect(not _flatten(RunSummary.stat_rows(clean)).contains("friendly fire"),
		"…and stays quiet when nobody hit anybody")
	gs.free()
	_completes("the_read_is_banked_and_shown")


# ═══════════════════════════════════════════════════ it has to fit a phone
func _test_the_card_fits_a_phone(GS: GDScript) -> void:
	# Worst case for height: a wipe deep in the tower with every optional row on —
	# elements, friendly fire, a best-floor above where you died, and falls.
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs != null:
		gs.set("last_run", GS.build_outcome(
			4, 37, true, true, ["Fire", "Shadow"], 3, "Ranked", 6, 214, 5, 5))
	var card: Control = (load(SUMMARY_SCENE) as PackedScene).instantiate()
	root.add_child(card)
	card.size = Vector2(BASE_W, BASE_H)
	await process_frame
	await process_frame
	var col: Variant = card.get("_col")
	_expect(col != null, "the card exposes its column for measurement")
	if col != null:
		var needed: Vector2 = (col as Control).get_combined_minimum_size()
		_expect(needed.y <= BASE_H, "the whole card fits 360 px of height (needs %.0f)" % needed.y)
		_expect(needed.x <= BASE_W, "…and 640 px of width (needs %.0f)" % needed.x)
	var buttons: Array = []
	_walk(card, buttons, "Button")
	_expect(buttons.size() >= 2, "the card offers a way onward (found %d buttons)" % buttons.size())
	var labels: Array[String] = []
	for b: Button in buttons:
		labels.append(b.text)
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"'%s' is at least %.0f px tall (got %.0f)" % [b.text, MIN_TAP_H, b.custom_minimum_size.y])
		_expect(b.focus_mode == Control.FOCUS_NONE, "'%s' takes no focus ring" % b.text)
	var joined: String = " | ".join(labels)
	_expect(joined.contains("CLIMB AGAIN"), "…straight back into the tower (has: %s)" % joined)
	_expect(joined.contains("Title"), "…and back to the title, which had no route at all before")
	card.queue_free()
	_completes("the_card_fits_a_phone")


func _test_the_pause_menu_carries_the_dial() -> void:
	var pm := PauseMenu.new()
	root.add_child(pm)
	pm.build("Leave the Tower")
	await process_frame
	var checks: Array = []
	_walk(pm, checks, "CheckButton")
	var found: CheckButton = null
	for c: CheckButton in checks:
		if c.text == "Friendly Fire":
			found = c
	_expect(found != null,
		"Settings has a Friendly Fire row (it was director-only, i.e. absent from every export)")
	if found != null:
		var was: bool = SpellCaster.friendly_fire
		found.button_pressed = not was          # emits `toggled`
		_expect(SpellCaster.friendly_fire == (not was), "the row writes the shared static")
		found.button_pressed = was
		_expect(SpellCaster.friendly_fire == was, "…both ways")
	pm.queue_free()
	_completes("the_pause_menu_carries_the_dial")
