# Run: godot --headless --path godot-project --script tools/slice_test_shell.gd
#
# Covers THE GAME SHELL — the Lobby (the boot scene) and the Credits screen.
#
# The headline behaviour under test is the one the spec forced: **"Play Solo"
# starts a RUN.** It used to `change_scene_to_file("res://scenes/Main.tscn")` —
# the old hub, whose NPCs talk to a hardcoded Ollama server at 127.0.0.1:11434.
# The spec cuts that permanently, and on a phone it could never have worked
# anyway (loopback is the device's own localhost). So:
#
#   * the button must reach `GameState.enter_run()` and nothing else;
#   * the lobby must not name Ollama or the deleted Conversation stack;
#   * and CLIMB must stay ABOVE the town button, so the fast path is always the
#     first thing a thumb lands on.
#
# ⚠ THE HUB IS NO LONGER "PARKED". This file used to assert the opposite — that
# `Conversation.tscn` still existed and its autoload was still registered, because
# `Conversation` was a bare global in `Player.gd` and `NPC.gd` and unregistering it
# stopped `Main.tscn` loading. Both references are gone and the whole LLM stack is
# deleted; `scenes/Main.tscn` came back as THE TOWN, the game's front door. What
# replaced that test lives in `tools/slice_test_town.gd`, which pins the deletion
# and the town's geometry together.
#
# Plus the two things a title screen quietly breaks on: fitting the 640×360 base
# viewport, and having tap targets a thumb can hit.
#
# And the credits, which are a LICENSING OBLIGATION rather than a nicety — the
# Pepper Sound Pack readme asks for attribution in writing, and that pack is
# under every melee hit in the game. The exact line is pinned here so a future
# layout tidy cannot quietly drop it.
extends SceneTree

# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion
# sentinel, so a test aborted by a dead property read fails BY ABSENCE.

const TESTS: Array[String] = [
	"lobby_scene_is_the_boot_scene",
	"play_solo_starts_a_run",
	"lobby_names_no_hub_and_no_ollama",
	"climb_stays_above_the_town",
	"lobby_fits_the_base_viewport",
	"tap_targets_are_thumb_sized",
	"discovery_starts_and_stops_with_the_join_screen",
	"discovered_hosts_become_buttons",
	"a_crowded_network_cannot_break_the_layout",
	"manual_address_survives_as_the_fallback",
	"credits_carry_the_required_attribution",
	"credits_screen_renders_it",
	"credits_flag_the_unsettled_licences",
]

var _fails: int = 0
var _completed: Dictionary = {}

const LOBBY_SCENE: String = "res://scenes/ui/Lobby.tscn"
const CREDITS_SCENE: String = "res://scenes/ui/Credits.tscn"
const LOBBY_SCRIPT: String = "res://scripts/ui/Lobby.gd"
const CREDITS_MD: String = "res://assets/audio/CREDITS.md"

## Godot's base viewport, from project.godot. Everything the lobby draws has to
## live inside this in LANDSCAPE.
const BASE_W: float = 640.0
const BASE_H: float = 360.0

## Minimum tappable height in base units. At 640×360 upscaled to any real phone
## this is a comfortable thumb; below it, misses start.
const MIN_TAP_H: float = 28.0

var _lobby: Control = null


func _init() -> void:
	_test_lobby_scene_is_the_boot_scene()
	_test_lobby_names_no_hub_and_no_ollama()
	_test_climb_stays_above_the_town()
	_test_credits_carry_the_required_attribution()
	# The rest need a live tree: autoloads land on the first idle frame, and a
	# Control reports no meaningful size until it has been through a layout pass.
	await process_frame
	await _test_play_solo_starts_a_run()
	await _test_lobby_fits_the_base_viewport()
	_test_tap_targets_are_thumb_sized()
	await _test_discovery_starts_and_stops_with_the_join_screen()
	await _test_discovered_hosts_become_buttons()
	await _test_a_crowded_network_cannot_break_the_layout()
	_test_manual_address_survives_as_the_fallback()
	await _test_credits_screen_renders_it()
	_test_credits_flag_the_unsettled_licences()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Shell tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Shell tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## Source with comments removed. The lobby's header EXPLAINS at length why the
## hub and its Ollama server are parked, so a naive grep for "11434" or
## "Conversation" hits the explanation rather than any live code. Stripping at
## the first `#` on each line is crude but exact for this codebase: no string
## literal in these files contains one.
func _code_only(path: String) -> String:
	var out: String = ""
	for line: String in _source(path).split("\n"):
		var hash_at: int = line.find("#")
		out += (line if hash_at < 0 else line.substr(0, hash_at)) + "\n"
	return out


## Build the lobby once and keep it — several tests read the same live instance,
## and building it three times would connect three sets of Net signals.
func _get_lobby() -> Control:
	if _lobby != null and is_instance_valid(_lobby):
		return _lobby
	var packed: PackedScene = load(LOBBY_SCENE)
	_lobby = packed.instantiate()
	root.add_child(_lobby)
	return _lobby


func _walk(from: Node, out: Array, want: String) -> void:
	if from.get_class() == want or (want == "Button" and from is Button):
		out.append(from)
	for c: Node in from.get_children():
		_walk(c, out, want)


# ---------------------------------------------------------------------------
# The boot path
# ---------------------------------------------------------------------------

func _test_lobby_scene_is_the_boot_scene() -> void:
	# If this ever stops being the main scene, F5 goes back to opening a spike
	# sandbox instead of the game — which is the state Phase 0 of the mobile plan
	# existed to fix.
	var main_scene: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	_expect(main_scene == LOBBY_SCENE,
		"run/main_scene is the lobby (got '%s')" % main_scene)
	_expect(ResourceLoader.exists(LOBBY_SCENE), "the lobby scene exists")
	_expect(ResourceLoader.exists(CREDITS_SCENE), "the credits scene exists")
	_completes("lobby_scene_is_the_boot_scene")


func _test_play_solo_starts_a_run() -> void:
	# THE test. Swap the real GameState autoload for a recorder, press the
	# button, and assert what the button actually did — rather than trusting a
	# grep. The real autoload is removed first because the real `enter_run` would
	# change scene straight into the arena, which is not what this is measuring.
	var real: Node = root.get_node_or_null(^"GameState")
	_expect(real != null, "the real GameState autoload is registered")
	if real != null:
		# The real thing must genuinely offer the entry point we rerouted to.
		_expect(real.has_method("enter_run"), "GameState.enter_run() exists")
		var arena: String = String(real.get("ARENA_SCENE"))
		_expect(arena != "" and ResourceLoader.exists(arena),
			"GameState points at a real arena scene ('%s')" % arena)
		root.remove_child(real)

	var stub := _GameStateStub.new()
	stub.name = "GameState"
	root.add_child(stub)
	await process_frame

	var lobby: Control = _get_lobby()
	lobby.set("_selected_class", 3)
	lobby.call("_play_solo")

	_expect(stub.entered == 1, "Play Solo called enter_run() exactly once (got %d)" % stub.entered)
	_expect(stub.selected_class == 3, "and carried the picked class through (got %d)" % stub.selected_class)
	_expect(stub.hub_loads == 0, "and never asked for the hub")
	_completes("play_solo_starts_a_run")


func _test_lobby_names_no_hub_and_no_ollama() -> void:
	var src: String = _code_only(LOBBY_SCRIPT)
	_expect(not src.is_empty(), "the lobby script reads")
	# The PORT, not the address: the co-op join field legitimately defaults to
	# 127.0.0.1, which is two phones on a LAN and not a model server.
	_expect(not src.contains("11434"), "the lobby names no Ollama port")
	_expect(not src.contains("/api/chat"), "the lobby calls no chat endpoint")
	_expect(src.contains("enter_run"), "the lobby starts a run")
	# And nothing on the boot path may reach the DELETED memory stack.
	for sym: String in ["Conversation.", "MemoryUtils", "MemoryConsolidator", "EntityStats"]:
		_expect(not src.contains(sym), "the lobby does not touch '%s'" % sym)
	_completes("lobby_names_no_hub_and_no_ollama")


## THE FAST PATH IS FIRST. The town is back and it is a good front door, but the
## maker's verdict on the last one was "just another layer that doesn't add any
## value" — so CLIMB must be built BEFORE the town button, and must still go
## straight to a run. This is the assertion that catches a well-meaning reorder.
func _test_climb_stays_above_the_town() -> void:
	var src: String = _code_only(LOBBY_SCRIPT)
	# ⚠ MATCHES "ENTER THE TOWER", NOT "CLIMB". The label changed on 2026-08-04
	# (maker: "there should be an Enter the tower button"), and the CLAIM this
	# guards is unchanged: the one verb that starts the game is built before the
	# detour to the town. Only the string moved.
	var climb_at: int = src.find("ENTER THE TOWER")
	var town_at: int = src.find("The Town")
	_expect(climb_at >= 0, "the lobby has an ENTER THE TOWER button")
	_expect(town_at >= 0, "and a town button")
	_expect(climb_at >= 0 and town_at > climb_at,
		"ENTER THE TOWER is built before the town button (climb@%d, town@%d)" % [climb_at, town_at])
	_expect(ResourceLoader.exists("res://scenes/Main.tscn"), "the town scene exists")
	_expect(not ResourceLoader.exists("res://scenes/Conversation.tscn"),
		"and the LLM overlay it used to carry is deleted")
	_completes("climb_stays_above_the_town")


# ---------------------------------------------------------------------------
# It has to fit a phone
# ---------------------------------------------------------------------------

func _test_lobby_fits_the_base_viewport() -> void:
	var lobby: Control = _get_lobby()
	lobby.size = Vector2(BASE_W, BASE_H)
	# Worst case is HOSTING: that is the only state with the extra "Start Run"
	# row, and it is exactly the state nobody checks on a small screen.
	var start_btn: Variant = lobby.get("_start_btn")
	if start_btn != null:
		(start_btn as Control).visible = true
	await process_frame
	await process_frame
	var col: Variant = lobby.get("_col")
	_expect(col != null, "the lobby exposes its button column for measurement")
	if col == null:
		_completes("lobby_fits_the_base_viewport")
		return
	var needed: Vector2 = (col as Control).get_combined_minimum_size()
	# The specific failure this guards: somebody adds one more row and the
	# bottom button walks off a 360 px screen, which nobody notices on a desktop
	# window that happens to be 768 tall.
	_expect(needed.y <= BASE_H,
		"the whole panel fits 360 px of height (needs %.0f)" % needed.y)
	_expect(needed.x <= BASE_W,
		"the panel fits 640 px of width (needs %.0f)" % needed.x)
	_completes("lobby_fits_the_base_viewport")


func _test_tap_targets_are_thumb_sized() -> void:
	var lobby: Control = _get_lobby()
	var buttons: Array = []
	_walk(lobby, buttons, "Button")
	_expect(buttons.size() >= 5,
		"the lobby still offers every action (found %d buttons)" % buttons.size())
	var labels: Array[String] = []
	for b: Button in buttons:
		labels.append(b.text)
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"'%s' is at least %.0f px tall (got %.0f)" % [b.text, MIN_TAP_H, b.custom_minimum_size.y])
		# A focus ring left over from keyboard navigation reads as a rendering
		# bug on a touchscreen.
		_expect(b.focus_mode == Control.FOCUS_NONE, "'%s' takes no focus ring" % b.text)
	var joined: String = " | ".join(labels)
	for wanted: String in ["Host Co-op", "Join", "Start Run", "Credits"]:
		_expect(joined.contains(wanted), "the lobby still has '%s' (has: %s)" % [wanted, joined])
	_expect(joined.contains("ENTER THE TOWER"),
		"and the one button that matters (has: %s)" % joined)
	# The class picker must be derived from the real roster, never a literal —
	# a hardcoded `% 8` once made the 9th class silently unreachable.
	_expect(not _code_only(LOBBY_SCRIPT).contains("% 8"), "the class picker is not a hardcoded count")
	_expect(_code_only(LOBBY_SCRIPT).contains("ClassInfo.count()"), "it derives from the roster")
	_completes("tap_targets_are_thumb_sized")


# ---------------------------------------------------------------------------
# LAN discovery — "two phones in one room"
# ---------------------------------------------------------------------------
#
# `Net` owns the protocol (a UDP broadcast beacon started automatically by
# `host()`, a listener, a TTL, and `hosts_changed`). This is the LAST MILE: the
# list has to appear, be tappable, tear down when you leave, and — the part that
# is easy to get wrong — never be allowed to decide how tall the panel is.
#
# Driven against a stub `Net` rather than a real socket, because a suite that
# needs a second machine on the same wifi is a suite nobody runs.

## Swap the lobby's Net for a recorder. The lobby reads `_net` on every call, so
## this is a clean seam; the connections made to the real autoload in `_ready`
## are left alone and are harmless.
func _with_stub_net() -> _NetStub:
	var lobby: Control = _get_lobby()
	var stub := _NetStub.new()
	stub.name = "NetStub"
	root.add_child(stub)
	lobby.set("_net", stub)
	return stub


func _test_discovery_starts_and_stops_with_the_join_screen() -> void:
	var lobby: Control = _get_lobby()
	var stub: _NetStub = _with_stub_net()
	lobby.call("_open_join")
	await process_frame
	_expect(stub.started == 1, "opening the join screen starts discovery (got %d)" % stub.started)
	_expect(stub.is_connected(&"hosts_changed", Callable(lobby, "_redraw_hosts")),
		"and listens for the host list changing")
	_expect(bool((lobby.get("_join_col") as Control).visible), "the join screen is showing")
	_expect(not bool((lobby.get("_col") as Control).visible), "and the title screen is not")

	lobby.call("_close_join")
	await process_frame
	# A bound UDP socket and a per-frame pump on an autoload that outlives this
	# scene is exactly the sort of leak that only shows up as battery drain.
	_expect(stub.stopped >= 1, "leaving it stops discovery (got %d)" % stub.stopped)
	_expect(not stub.is_connected(&"hosts_changed", Callable(lobby, "_redraw_hosts")),
		"and disconnects the signal")
	_expect(bool((lobby.get("_col") as Control).visible), "the title screen is back")

	# Every other way out of the lobby must tear it down too.
	lobby.call("_open_join")
	await process_frame
	var before: int = stub.stopped
	lobby.call("_on_join_ok")
	_expect(stub.stopped > before, "a successful join stops discovery")
	_completes("discovery_starts_and_stops_with_the_join_screen")


func _test_discovered_hosts_become_buttons() -> void:
	var lobby: Control = _get_lobby()
	var stub: _NetStub = _with_stub_net()
	stub.hosts = [
		{"ip": "192.168.1.44", "port": 24565, "name": "ARI-PHONE"},
		{"ip": "192.168.1.9", "port": 24999, "name": "OTHER-PHONE"},
	]
	lobby.call("_open_join")
	stub.hosts_changed.emit()
	await process_frame

	var rows: Array = []
	_walk(lobby.get("_host_list"), rows, "Button")
	_expect(rows.size() == 2, "both hosts drew a button (got %d)" % rows.size())
	var joined: String = ""
	for b: Button in rows:
		joined += b.text + " | "
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"a host row is thumb-sized (got %.0f)" % b.custom_minimum_size.y)
		_expect(b.focus_mode == Control.FOCUS_NONE, "a host row takes no focus ring")
	_expect(joined.contains("ARI-PHONE"), "the host's NAME is what you tap (got %s)" % joined)

	# Tapping one must join THAT host, at THAT port. The port comes off the
	# beacon, not off a constant — hardcoding DEFAULT_PORT breaks the moment
	# anyone hosts on a second port, which is how you test two sessions on one
	# machine.
	lobby.set("_selected_class", 5)
	(rows[1] as Button).pressed.emit()
	_expect(stub.join_ip == "192.168.1.9", "tapping a host joins that host (got '%s')" % stub.join_ip)
	_expect(stub.join_port == 24999, "at the port it advertised (got %d)" % stub.join_port)
	_expect(stub.join_class == 5, "carrying the picked class (got %d)" % stub.join_class)

	# A host that walks away expires by TTL with NO signal, so the list must also
	# be swept. Without the poll it would leave a dead button whose only possible
	# outcome is a failed join.
	stub.hosts = []
	lobby.set("_poll_t", 0.0)
	lobby.call("_process", 0.2)
	await process_frame
	var after: Array = []
	_walk(lobby.get("_host_list"), after, "Button")
	_expect(after.is_empty(), "a host that left is swept off the list (got %d rows)" % after.size())
	lobby.call("_close_join")
	_completes("discovered_hosts_become_buttons")


func _test_a_crowded_network_cannot_break_the_layout() -> void:
	# THE LAYOUT PROMISE. The host list is the one control on this screen whose
	# length is decided by other people's machines. It lives in a ScrollContainer
	# with a fixed minimum height, so nine hosts must measure exactly the same as
	# one — this asserts that rather than trusting it.
	var lobby: Control = _get_lobby()
	var stub: _NetStub = _with_stub_net()
	stub.hosts = []
	lobby.call("_open_join")
	await process_frame
	await process_frame
	var join_col: Control = lobby.get("_join_col")
	var empty_h: float = join_col.get_combined_minimum_size().y
	_expect(empty_h <= BASE_H, "the empty join screen fits 360 px (needs %.0f)" % empty_h)

	var many: Array = []
	for i in 9:
		many.append({"ip": "10.0.0.%d" % i, "port": 24565, "name": "A VERY LONG HOST NAME %d" % i})
	stub.hosts = many
	stub.hosts_changed.emit()
	await process_frame
	await process_frame
	# NOT VACUOUS: prove the nine rows are really parented at the moment the panel
	# is measured. Without this the equality below would pass just as happily if
	# the list had quietly failed to draw anything at all.
	var drawn: Array = []
	_walk(lobby.get("_host_list"), drawn, "Button")
	_expect(drawn.size() == 9,
		"all nine hosts are on screen while this is measured (got %d)" % drawn.size())
	var full_h: float = join_col.get_combined_minimum_size().y
	_expect(full_h <= BASE_H,
		"NINE hosts still fit 360 px of height (needs %.0f)" % full_h)
	_expect(is_equal_approx(full_h, empty_h),
		"the panel height does not depend on how many games are nearby (%.0f vs %.0f)"
			% [empty_h, full_h])
	_expect(join_col.get_combined_minimum_size().x <= BASE_W,
		"and a long host name does not widen it past 640 px")
	lobby.call("_close_join")
	_completes("a_crowded_network_cannot_break_the_layout")


func _test_manual_address_survives_as_the_fallback() -> void:
	# Broadcast is blocked on plenty of guest wifi. A typed address is the
	# difference between "co-op is broken" and "co-op needs one more tap", so it
	# must never be dropped as redundant once discovery works.
	var lobby: Control = _get_lobby()
	var stub: _NetStub = _with_stub_net()
	var ip_edit: Variant = lobby.get("_ip_edit")
	_expect(ip_edit != null, "the manual address field still exists")
	(ip_edit as LineEdit).text = "10.1.2.3"
	lobby.set("_selected_class", 2)
	lobby.call("_join")
	_expect(stub.join_ip == "10.1.2.3", "typing an address still joins it (got '%s')" % stub.join_ip)
	_expect(stub.join_class == 2, "carrying the picked class")

	# And when the network refuses to be searched at all, the player is told to
	# use it rather than left staring at an empty list that reads as "nobody is
	# playing".
	stub.start_result = ERR_CANT_CREATE
	stub.started = 0
	lobby.call("_close_join")
	lobby.call("_open_join")
	var msg: String = String((lobby.get("_join_status") as Label).text)
	_expect(msg.to_lower().contains("address"),
		"a network that cannot be searched points at the fallback (said: '%s')" % msg)
	lobby.call("_close_join")
	_completes("manual_address_survives_as_the_fallback")


# ---------------------------------------------------------------------------
# The licence
# ---------------------------------------------------------------------------

func _test_credits_carry_the_required_attribution() -> void:
	var script: GDScript = load("res://scripts/ui/Credits.gd")
	var consts: Dictionary = script.get_script_constant_map()
	var pepper: String = String(consts.get("PEPPER_LINE", ""))
	# The readme asks for "Pepper" to be credited. The pack is under every melee
	# swing, punch, kick, block, guard break, hurt, fall, dash and footstep in
	# the game — so this is the licence being satisfied, not a nicety.
	_expect(pepper.contains("Pepper"), "the credited name is Pepper (got '%s')" % pepper)
	_expect(pepper.contains("Keisan") or pepper.contains("Boulanger"),
		"the author is named too (got '%s')" % pepper)
	var roll: Array = consts.get("ROLL", [])
	var found: bool = false
	for entry: Array in roll:
		if String(entry[1]) == pepper:
			found = true
	_expect(found, "the Pepper line is actually on the roll, not just declared")
	# The source of truth for all of this must still be in the repo.
	var md: String = _source(CREDITS_MD)
	_expect(md.contains("Pepper"), "assets/audio/CREDITS.md still records the obligation")
	_completes("credits_carry_the_required_attribution")


func _test_credits_screen_renders_it() -> void:
	# Declaring the line in a constant is not the same as a player being able to
	# read it. This builds the real screen and looks for the text on a Label.
	var screen: Control = (load(CREDITS_SCENE) as PackedScene).instantiate()
	root.add_child(screen)
	await process_frame
	var labels: Array = []
	_walk(screen, labels, "Label")
	var credits_script: GDScript = load("res://scripts/ui/Credits.gd")
	var pepper: String = String(credits_script.get_script_constant_map().get("PEPPER_LINE", ""))
	var on_screen: bool = false
	for l: Label in labels:
		if l.text == pepper:
			on_screen = true
	_expect(on_screen, "the attribution is rendered on the credits screen")
	_expect(labels.size() >= 20, "the roll is actually built (%d labels)" % labels.size())
	var backs: Array = []
	_walk(screen, backs, "Button")
	_expect(backs.size() >= 1, "there is a way back out")
	_expect(screen.has_signal(&"closed"), "it tells its owner when it closes")
	# The Lobby has to be able to reach it, or the obligation is satisfied by a
	# screen nobody can open.
	_expect(_code_only(LOBBY_SCRIPT).contains(CREDITS_SCENE),
		"the lobby can open the credits screen")
	screen.free()
	_completes("credits_screen_renders_it")


func _test_credits_flag_the_unsettled_licences() -> void:
	# Two provenance gaps are pre-existing and are the maker's call. A credits
	# screen that pretends they do not exist is worse than one that says so, and
	# the flag is the only thing keeping them from being forgotten before a
	# store build.
	var script: GDScript = load("res://scripts/ui/Credits.gd")
	var roll: Array = script.get_script_constant_map().get("ROLL", [])
	var warns: String = ""
	for entry: Array in roll:
		if String(entry[0]) == "warn":
			warns += String(entry[1]) + " | "
	_expect(warns.contains("TomMusic"),
		"the unconfirmed TomMusic licence is flagged (warns: %s)" % warns)
	_expect(warns.to_lower().contains("music"),
		"the undocumented music provenance is flagged (warns: %s)" % warns)
	_completes("credits_flag_the_unsettled_licences")


## Stands in for the Net autoload. Only the surface the join screen touches —
## deliberately duck-typed the same way the lobby reaches for it, so this cannot
## drift into testing a fantasy API. Real discovery needs a second machine on the
## same wifi, and a suite that needs that is a suite nobody runs.
class _NetStub:
	extends Node
	signal hosts_changed
	signal lobby_changed
	signal server_started
	signal join_ok
	signal join_failed

	const DEFAULT_PORT: int = 24565

	var hosts: Array = []
	var started: int = 0
	var stopped: int = 0
	var start_result: int = OK
	var join_ip: String = ""
	var join_class: int = -1
	var join_port: int = -1

	func start_discovery() -> int:
		if start_result == OK:
			started += 1
		return start_result

	func stop_discovery() -> void:
		stopped += 1

	func discovered_hosts() -> Array:
		return hosts

	func join(ip: String = DEFAULT_PORT_IP, my_class: int = 0, port: int = DEFAULT_PORT) -> int:
		join_ip = ip
		join_class = my_class
		join_port = port
		return OK

	const DEFAULT_PORT_IP: String = "127.0.0.1"

	func is_host() -> bool:
		return false

	func is_active() -> bool:
		return false

	func peers() -> Array:
		return []


## Stands in for the GameState autoload so the button press can be OBSERVED
## rather than followed into a real scene change.
class _GameStateStub:
	extends Node
	var entered: int = 0
	var hub_loads: int = 0
	var selected_class: int = -1

	func enter_run() -> void:
		entered += 1

	## If anything ever routes back through the hub, this counts it.
	func return_to_hub() -> void:
		hub_loads += 1
