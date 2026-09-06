# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_realm.gd
#
# WHO YOU ARE, WHAT A PEER IS ALLOWED TO CALL ITSELF, AND WHETHER THE SCREEN THAT SHOWS
# BOTH FITS A PHONE.
#
# Three claims, and each one is here because the obvious implementation of it is
# silently wrong:
#
#   1. IDENTITY PERSISTS. ⚠ A test that sets a name and reads the same name back proves
#      NOTHING — the in-memory static answers correctly whether or not a byte reached
#      the disk. So every persistence test here WRITES, then calls
#      `PlayerProfile.forget_cache()` (the in-memory copy is dropped and the file
#      re-read), and only then asks. That is a restart, inside one process. It is the
#      same shape `slice_test_settings` uses, and it is there because `Settings` shipped
#      a version of this that passed while writing nothing.
#   2. A NAME OFF THE WIRE CANNOT REACH A LABEL INTACT. The dangerous input is not a
#      long name, it is `U+202E RIGHT-TO-LEFT OVERRIDE`: it reverses the rendering of
#      the text AFTER it, so a peer can make the row this game wrote as
#      "Rae — Stormcaller" read as something the sender chose. It is invisible, a length
#      check does not notice it, and neither does anything that only trims whitespace.
#   3. THE SCREEN FITS 360 px. ⚠ `project.godot` is 640x360 with `stretch/aspect=expand`,
#      which keeps the base HEIGHT and grows the width — so a taller phone gets a WIDER
#      logical viewport, never a shorter one. Height is the ceiling; width is a floor.
#      And headless has no window and therefore NO ASPECT RATIO: `get_visible_rect()`
#      falls back to a SQUARE 640x640, so every vertical assertion would be checked
#      against 280 px of height the player does not have. `root.size` is set to a real
#      16:9 window and `_test_the_harness_is_honest` fails the suite if that did not
#      take.
#
# ⚠ THIS SUITE NEVER TOUCHES `user://profile.json`. It points `PlayerProfile` at
# `user://profile_test.json` for its duration and deletes it at the end — otherwise
# running the tests would rename the maker.
#
# ⚠ THE RECEIPT FILTER IS DRIVEN ON THE REAL `/root/Net`, NOT GREPPED — and the reason
# that is possible is worth writing down, because it is easy to assume otherwise.
# **`--script` DOES register this project's autoloads.** All twelve are up (probed:
# MCPRuntime, Sfx, Music, Rank, GameState, Tuning, ClassSelect, Loadout, Net,
# SpellReactor, Perf, Screen). It is `--check-only --script scripts/Net.gd` — loading
# Net as the MAIN script — that fails, because that path compiles its chain before the
# autoload table exists; as an autoload it compiles fine. So the hostile strings below
# go through the actual RPC handlers on the actual singleton.
#
# ⚠ AND THAT CUTS BOTH WAYS: a real `GameState` is up, holding the MAKER'S OWN CLIMBER
# SAVE. Nothing here may call anything that writes it, and nothing here may call
# `visit_hub` — an earlier draft did, and it changed the scene out from under the suite.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead property read ABORTS the enclosing function and returns the type's zero, which
# `failed += _test_x()` reads as "no failures". So failures accumulate on the MEMBER
# `_fails` and every test records a completion sentinel as its last line: a test that
# aborts part-way is then missing from `_completed` and fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"the_harness_is_honest",
	"a_fresh_climber_is_never_nameless",
	"a_name_survives_a_restart",
	"a_corrupt_profile_is_a_default_not_a_crash",
	"a_control_character_cannot_reach_a_label",
	"a_bidi_override_cannot_reach_a_label",
	"a_long_name_is_capped_in_characters",
	"an_unnamed_peer_reads_as_its_number",
	"the_id_is_stable_across_a_restart",
	"the_record_is_pure_and_round_trips",
	"net_sanitises_on_receipt_not_only_on_send",
	"net_still_seats_exactly_two",
	"the_realm_screen_fits_the_base_viewport",
	"every_realm_row_clears_the_thumb_floor",
	"an_empty_seat_reads_as_an_invitation",
	"multiplayer_opens_the_realm_screen",
	"the_title_screen_gained_no_button",
	"local_play_is_not_a_network_path",
]

const PlayerProfile := preload("res://scripts/PlayerProfile.gd")

const REALM_SCRIPT: String = "res://scripts/ui/RealmScreen.gd"
const NET_SCRIPT: String = "res://scripts/Net.gd"
const LOBBY_SCENE: String = "res://scenes/ui/Lobby.tscn"

## Somewhere that is not the maker's real profile. See the header.
const TEST_PROFILE: String = "user://profile_test.json"

## The base viewport (`project.godot` window/size/viewport_{width,height}).
const BASE_W: float = 640.0
const BASE_H: float = 360.0

## ⚠ THE FLOOR IS A LITERAL AND `RealmScreen.MIN_TAP` IS NOT READ. `slice_test_settings`
## paid for this rule: its first draft asserted `h >= PauseMenu.ROW_H` — against the very
## constant the rows are built from — so lowering the constant moved the floor down with
## the buttons and the test stayed green through the exact regression it exists to catch.
## 30 px is the game-wide tap floor (`Outfitter.MIN_TAP`, `World.MIN_TAP`,
## `slice_test_shell`'s 28-px bound), written out here so the two are independent claims.
const MIN_TAP_PX: float = 30.0

## The title screen's two primaries. `slice_test_settings` owns this rule; it is
## re-asserted here because THIS change is the one that touched the MULTIPLAYER button,
## and a suite that changes a button should be the suite that proves it did not shrink it.
const MIN_PRIMARY_PX: float = 46.0

## Every button the title screen is allowed to show at once. ⚠ A SET, NOT A COUNT. The
## maker asked TWICE for the front door to have fewer, smaller buttons; a count would let
## somebody swap one for another, and a set says exactly which ones survived.
## ⚠ THE MARKER IS `›` (U+203A) AND NOT `▸` (U+25B8), WHICH IS ITSELF A FIXED BUG. The
## theme declares no Font, the repo ships none, so the fallback is Godot's Latin-1
## Open Sans subset and U+25B8 drew as a ZERO-WIDTH NOTHING with no error — on the two
## primary verbs of the front door. `tools/slice_test_font_coverage.gd` is the gate;
## this const is pinned to the fixed strings so a revert fails here too.
const TITLE_BUTTONS: Array[String] = [
	"SINGLE PLAYER  ›", "MULTIPLAYER  ›", "Watch Bots", "Credits",
]

var _fails: int = 0
var _completed: Dictionary = {}
## Reported at the end next to the pass line, because "it fits" is worth less than the
## number it fits by — and the number is what tells the next person how much room they
## have before they break it.
var _measured_h: float = -1.0


## ⚠ THERE IS NO `FakeGameState` HERE AND THAT IS A FINDING, NOT AN OMISSION. Every
## other UI suite in this repo installs one, which is correct for a suite that runs
## WITHOUT autoloads — but `--script` brings all twelve of this project's autoloads up
## (probed), so `/root/GameState` is already taken and a second node of that name is
## auto-renamed `@GameState@2`. The lookup then silently finds the REAL one, the fake is
## never consulted, and its fields read as their untouched defaults — which is exactly
## the vacuous pass this file's armour is about. It cost one red run to find; see
## `_test_local_play_is_not_a_network_path` for what is asserted instead.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# A real 16:9 window, or `stretch/aspect="expand"` never resolves — see the header.
	root.size = Vector2i(1366, 768)
	await process_frame
	await process_frame

	# ⚠ REDIRECT THE PROFILE BEFORE ANYTHING READS OR WRITES ONE, AND THEN CHECK THE
	# REDIRECT TOOK. `Settings` had this exact guard missing and passed while quietly
	# overwriting the maker's real file, because `Settings.reload()` resolved to the
	# ENGINE's `Script.reload()` and reset every static including the path override.
	# A harness that can silently point at the wrong file is a harness that lies.
	PlayerProfile.use_path(TEST_PROFILE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	PlayerProfile.forget_cache()
	if PlayerProfile.profile_path() != TEST_PROFILE:
		printerr(("FAIL: the profile was NOT redirected (still %s) — refusing to run, "
			+ "because these tests write a name and would rename the maker")
			% PlayerProfile.profile_path())
		printerr("Realm tests: 1 FAILED")
		quit(1)
		return

	_test_the_harness_is_honest()
	_test_a_fresh_climber_is_never_nameless()
	_test_a_name_survives_a_restart()
	_test_a_corrupt_profile_is_a_default_not_a_crash()
	_test_a_control_character_cannot_reach_a_label()
	_test_a_bidi_override_cannot_reach_a_label()
	_test_a_long_name_is_capped_in_characters()
	_test_an_unnamed_peer_reads_as_its_number()
	_test_the_id_is_stable_across_a_restart()
	_test_the_record_is_pure_and_round_trips()
	_test_net_sanitises_on_receipt()
	_test_net_still_seats_exactly_two()
	await _test_the_realm_screen_fits()
	await _test_every_realm_row_clears_the_thumb_floor()
	await _test_an_empty_seat_reads_as_an_invitation()
	await _test_multiplayer_opens_the_realm_screen()
	await _test_the_title_screen_gained_no_button()
	await _test_local_play_is_not_a_network_path()

	# Leave nothing behind: the file and the path override.
	PlayerProfile.forget_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE + ".tmp"))
	PlayerProfile.use_path(PlayerProfile.PATH)

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _measured_h >= 0.0:
		print("Realm screen measured %.0f px of the %.0f-px base viewport (%.0f px spare)"
			% [_measured_h, BASE_H, BASE_H - _measured_h])
	if _fails > 0:
		printerr("Realm tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Realm tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _walk(from: Node, out: Array, want: String) -> void:
	for c: Node in from.get_children():
		if c.is_class(want):
			out.append(c)
		_walk(c, out, want)


func _all(from: Node, want: String) -> Array:
	var out: Array = []
	_walk(from, out, want)
	return out


# ═══════════════════════════════════════════════════════════════ 0. the harness
func _test_the_harness_is_honest() -> void:
	var vp: Vector2 = root.get_visible_rect().size
	_expect(is_equal_approx(vp.x, BASE_W) and is_equal_approx(vp.y, BASE_H),
		("the viewport resolved to the real 640x360 base and not headless's square "
		+ "fallback (got %.0fx%.0f — set root.size and wait a frame)") % [vp.x, vp.y])
	_expect(ResourceLoader.exists(REALM_SCRIPT), "the realm screen is in this build")
	_completes("the_harness_is_honest")


# ═══════════════════════════════════════════════════════════════ 1. identity
## ⚠ THE CLAIM IS "NEVER EMPTY", NOT "HAS A DEFAULT". A blank name reads as a screen
## that failed to load, and the realm screen puts this string on the left-hand card
## before the player has typed anything at all.
func _test_a_fresh_climber_is_never_nameless() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	PlayerProfile.forget_cache()
	var n: String = PlayerProfile.display_name()
	_expect(n != "", "a first run has a name at all (got %s)" % JSON.stringify(n))
	_expect(n == PlayerProfile.DEFAULT_NAME,
		"and it is the stated default (got %s, want %s)" % [n, PlayerProfile.DEFAULT_NAME])
	_expect(not PlayerProfile.is_named(),
		("...but `is_named()` is FALSE, so `Net.host` still advertises the MACHINE name "
		+ "on the LAN — two unnamed hosts must not be two identical buttons"))
	_completes("a_fresh_climber_is_never_nameless")


## ⚠ THE `forget_cache()` IS THE TEST. Without it this asserts that a static variable
## remembers what was just assigned to it, which is true of every static variable.
func _test_a_name_survives_a_restart() -> void:
	PlayerProfile.set_display_name("Rae")
	PlayerProfile.forget_cache()          # ← the restart
	_expect(PlayerProfile.display_name() == "Rae",
		"a name written before a restart comes back off disk (got %s)"
		% PlayerProfile.display_name())
	_expect(PlayerProfile.is_named(), "...and counts as chosen rather than defaulted")
	_completes("a_name_survives_a_restart")


## A corrupt file is a nickname lost, not a game that will not start. It must not throw,
## must not blank the card, and must not leave the player unable to set a new name.
func _test_a_corrupt_profile_is_a_default_not_a_crash() -> void:
	var f: FileAccess = FileAccess.open(TEST_PROFILE, FileAccess.WRITE)
	_expect(f != null, "the suite can write a deliberately corrupt profile")
	if f == null:
		return
	f.store_string("{ this is not json, and the closing brace is missing")
	f.close()
	PlayerProfile.forget_cache()
	_expect(PlayerProfile.display_name() == PlayerProfile.DEFAULT_NAME,
		"a corrupt profile reads as the default (got %s)" % PlayerProfile.display_name())
	# The other half, and the one a "does it crash" test would miss: recovery has to be
	# WRITEABLE. A corrupt file that cannot be overwritten is a permanent default.
	PlayerProfile.set_display_name("Ari")
	PlayerProfile.forget_cache()
	_expect(PlayerProfile.display_name() == "Ari",
		"and a new name overwrites it (got %s)" % PlayerProfile.display_name())
	# A JSON value of the wrong TYPE is the other corruption shape, and it is the one
	# that survives a parse: `{"name": 7}` is valid JSON and would `str()` into "7".
	_expect(String(PlayerProfile.parse_profile_save({"name": 7, "id": 9})["name"]) == "",
		"a non-string name in a valid JSON file is refused rather than coerced")
	_completes("a_corrupt_profile_is_a_default_not_a_crash")


## ⚠ EVERY ONE OF THESE IS A LAYOUT BUG AS WELL AS A DATA ONE. A newline in a name turns
## a one-line row into a two-line one and silently re-measures the card that has to fit
## 360 px of height; a C1 control is "printable" as far as a length check cares.
func _test_a_control_character_cannot_reach_a_label() -> void:
	var dirty: String = "Ra\ne\tBx"
	var clean: String = PlayerProfile.sanitize_name(dirty)
	for i: int in clean.length():
		var c: int = clean.unicode_at(i)
		_expect(c >= 0x20 and c != 0x7F and not (c >= 0x80 and c <= 0x9F),
			"no control character survives sanitising (U+%04X did, in %s)"
			% [c, JSON.stringify(clean)])
	# ⚠ TAB AND NEWLINE BECOME A SPACE RATHER THAN VANISHING. Deleting them turns
	# "Ra\ne" into "Rae", which quietly invents a name nobody typed.
	_expect(clean.contains("Ra e"),
		"a newline becomes a word break rather than being deleted (got %s)"
		% JSON.stringify(clean))
	_expect(PlayerProfile.sanitize_name("  \n\t  ") == "",
		"a name that is nothing but whitespace comes back empty, for a reader to default")
	_expect(PlayerProfile.sanitize_name("a    b") == "a b",
		"runs of spaces collapse, so leading whitespace cannot be used to sort to the top")
	_expect(PlayerProfile.sanitize_name("  Rae  ") == "Rae", "and the edges are stripped")
	_completes("a_control_character_cannot_reach_a_label")


## ⚠ THE INTERESTING ONE. `U+202E RIGHT-TO-LEFT OVERRIDE` reverses the rendering of
## everything after it, so a peer's name can rewrite the text NEXT TO IT — the
## "— Stormcaller" this game wrote, not the part the sender typed. It is invisible, so
## it cannot be eyeballed, and `length()` does not notice it either.
func _test_a_bidi_override_cannot_reach_a_label() -> void:
	# ⚠ BUILT WITH `String.chr`, NOT WRITTEN AS LITERALS, AND THE REASON IS ITSELF
	# EVIDENCE. Godot 4's own parser REFUSES a source file containing one of these:
	# *"Invisible text direction control character present in the string, escape it"*.
	# The engine treats an unescaped bidi override in a string as a hazard worth failing
	# the compile over — and a name arriving off a UDP socket gets no such parser.
	var attacks: Array[String] = [
		"Rae" + String.chr(0x202E) + "reklawmrots",   # RIGHT-TO-LEFT OVERRIDE
		String.chr(0x202D) + "Rae",                   # LEFT-TO-RIGHT OVERRIDE
		String.chr(0x200F) + "Rae",                   # RIGHT-TO-LEFT MARK
		String.chr(0x2066) + "Rae" + String.chr(0x2069),  # FIRST STRONG ISOLATE
		"Rae" + String.chr(0xFEFF),                   # ZERO WIDTH NO-BREAK SPACE
		"Rae" + String.chr(0x202A) + String.chr(0x202B),  # the two EMBEDDINGS
	]
	for a: String in attacks:
		var clean: String = PlayerProfile.sanitize_name(a)
		for i: int in clean.length():
			var c: int = clean.unicode_at(i)
			var is_bidi: bool = c == 0x200E or c == 0x200F or (c >= 0x202A and c <= 0x202E) \
				or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF
			_expect(not is_bidi,
				"U+%04X survived sanitising %s — a name can then rewrite the row beside it"
				% [c, JSON.stringify(a)])
		_expect(clean.contains("Rae"),
			"...and the legitimate part of the name survives (got %s from %s)"
			% [JSON.stringify(clean), JSON.stringify(a)])
	_completes("a_bidi_override_cannot_reach_a_label")


## ⚠ THE CAP IS IN CHARACTERS AND IS APPLIED LAST. `String.length()` in Godot 4 counts
## CODE POINTS, so an accented letter costs one and the card's width budget is honoured.
## Capping first would let a 200-space prefix eat the whole allowance and leave nothing.
func _test_a_long_name_is_capped_in_characters() -> void:
	var cap: int = PlayerProfile.MAX_NAME_CHARS
	var long_name: String = "A".repeat(cap * 30)
	_expect(PlayerProfile.sanitize_name(long_name).length() == cap,
		"a %d-character name is capped to %d" % [long_name.length(), cap])
	var padded: String = " ".repeat(200) + "Rae"
	_expect(PlayerProfile.sanitize_name(padded) == "Rae",
		"a long whitespace prefix does not eat the allowance (got %s)"
		% JSON.stringify(PlayerProfile.sanitize_name(padded)))
	# Émoji and accents cost ONE each, not their UTF-8 byte count.
	_expect(PlayerProfile.sanitize_name("é".repeat(cap * 2)).length() == cap,
		"the cap counts code points, not bytes")
	# And the stored form is what the field must show back — a `LineEdit` that keeps
	# displaying the rejected text is a field that lies about what your friend will see.
	_expect(PlayerProfile.set_display_name(long_name).length() == cap,
		"`set_display_name` returns what was STORED, so the field can put it back")
	_completes("a_long_name_is_capped_in_characters")


## Two unnamed players in one session must not both be called "Climber" — the entire job
## of the right-hand card is to say who the OTHER person is.
func _test_an_unnamed_peer_reads_as_its_number() -> void:
	_expect(PlayerProfile.clean_incoming("", 2) == "Player 2",
		"an empty wire name falls back to the peer's own number")
	_expect(PlayerProfile.clean_incoming(String.chr(0x202E) + "\n\t", 3) == "Player 3",
		"...and so does a name that is entirely stripped away")
	_expect(PlayerProfile.clean_incoming("", 2) != PlayerProfile.clean_incoming("", 3),
		"two unnamed peers are told apart rather than both reading as the default")
	_expect(PlayerProfile.clean_incoming("Rae", 2) == "Rae",
		"and a real name is left alone")
	_completes("an_unnamed_peer_reads_as_its_number")


## The id exists so a FUTURE friend list has something to key on. A peer id is assigned
## by the host and is meaningless once the session ends; this is not.
func _test_the_id_is_stable_across_a_restart() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	PlayerProfile.forget_cache()
	var first: String = PlayerProfile.player_id()
	_expect(first.length() == PlayerProfile.ID_CHARS,
		"an id is minted on first ask (%d chars, want %d)"
		% [first.length(), PlayerProfile.ID_CHARS])
	PlayerProfile.forget_cache()          # ← the restart
	_expect(PlayerProfile.player_id() == first,
		"and it is the SAME id tomorrow (%s vs %s)" % [first, PlayerProfile.player_id()])
	# ⚠ NOT A HARDWARE ID. `OS.get_unique_id()` would be exactly as stable and would put
	# a device fingerprint on disk — and, the moment a friend list exists, on a network.
	# Stability comes from the FILE, not from the source of the bytes.
	_expect(first != OS.get_unique_id(),
		"the id is minted, not taken from the device's hardware identifier")
	# A truncated or hand-edited id is treated as absent rather than becoming permanent.
	_expect(PlayerProfile.parse_profile_save({"id": "abc"})["id"] == "",
		"a malformed id is refused")
	_expect(PlayerProfile.parse_profile_save({"id": first})["id"] == first,
		"...and a well-formed one is kept")
	_completes("the_id_is_stable_across_a_restart")


## ⚠ THE RECORD IS PURE AND MUST STAY THAT WAY, and the field ORDER is the thing being
## pinned. `GameState.build_climber_save` states the rule this copies: new fields go on
## the END with a default, never in the middle, or every existing positional caller —
## and every suite that pins one — breaks silently.
func _test_the_record_is_pure_and_round_trips() -> void:
	var rec: Dictionary = PlayerProfile.build_profile_save("Rae")
	_expect(int(rec["version"]) == PlayerProfile.SAVE_VERSION, "the record is versioned")
	_expect(String(rec["name"]) == "Rae", "the name round-trips")
	# Sanitised on the way OUT as well as in — a future caller that forgets is the
	# second route in, and this is the single point both pass through.
	_expect(String(PlayerProfile.build_profile_save("Ra\ne")["name"]) == "Ra e",
		"a record built from dirty input is clean")
	# ⚠ THE M9 JSON TRAP. `JSON.parse_string` hands back every number as TYPE_FLOAT, so a
	# saved `1` arrives as `1.0`. In M9 that confusion made a valid save look like an old
	# one, ran a migration on it and DESTROYED the data — and it survived two code
	# reviews because it fails in the direction that still looks correct.
	_expect(typeof(PlayerProfile.parse_profile_save({"version": 1.0})["version"]) == TYPE_INT,
		"a float version off JSON is coerced to int (the M9 trap)")
	_expect(int(PlayerProfile.parse_profile_save({"version": 1.0})["version"]) == 1,
		"...to the right value")
	# Not-a-dictionary is a normal answer, not an error path.
	_expect(String(PlayerProfile.parse_profile_save("nonsense")["name"]) == "",
		"a non-dictionary parses to the defaults rather than throwing")
	_completes("the_record_is_pure_and_round_trips")


# ═══════════════════════════════════════════════════════════ 2. the wire
## ⚠ HOSTILE STRINGS THROUGH THE REAL RPC HANDLER ON THE REAL SINGLETON. `_sync_name_table`
## is the RELAY path — the table a HOST sends every client — and it is the one an
## attacker controls wholesale: `_announce_name` only lets a peer name ITSELF, whereas a
## malicious host hands you a whole dictionary. Both are driven below.
##
## The strings are built with `String.chr` rather than written out, because Godot's own
## parser refuses a source file containing an unescaped bidi override. A UDP packet gets
## no such parser, which is the entire point.
func _test_net_sanitises_on_receipt() -> void:
	var net: Node = root.get_node_or_null(^"/root/Net")
	_expect(net != null, "the Net autoload is up (it is, under --script — see the header)")
	if net == null:
		return
	var table: Dictionary = net.get("peer_name") as Dictionary
	_expect(table != null, "Net carries a name table alongside peer_class")
	if table == null:
		return
	# ⚠ SNAPSHOT AND RESTORE. This is a live autoload, not a fixture.
	var saved: Dictionary = table.duplicate(true)

	var rtl: String = "Rae" + String.chr(0x202E) + "reklawmrots"
	net.call("_sync_name_table", {
		2: rtl,                              # a bidi override off the wire
		3: 12345,                            # not a string at all
		4: "B".repeat(400),                  # a name longer than any label
		5: "Zed\nSecond line",               # a newline, which re-measures the card
		6: "",                               # nothing at all
	})

	var got2: String = String(net.call("name_of", 2))
	for i: int in got2.length():
		var c: int = got2.unicode_at(i)
		var is_bidi: bool = c == 0x200E or c == 0x200F or (c >= 0x202A and c <= 0x202E) \
			or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF
		_expect(not is_bidi,
			("U+%04X reached `name_of` off the wire — a peer's name can then rewrite the "
			+ "'— Stormcaller' this game wrote next to it") % c)
	_expect(got2.contains("Rae"), "...while the legitimate part survives (got %s)" % got2)

	# ⚠ A NON-STRING IS REFUSED, NOT COERCED. `str()` on a Dictionary produces a page of
	# braces, which is a Label the height of the screen.
	_expect(String(net.call("name_of", 3)) == "Player 3",
		"a non-string value is dropped and the seat reads as its number (got %s)"
		% net.call("name_of", 3))
	_expect(String(net.call("name_of", 4)).length() <= PlayerProfile.MAX_NAME_CHARS,
		"a 400-character name is capped to %d (got %d)"
		% [PlayerProfile.MAX_NAME_CHARS, String(net.call("name_of", 4)).length()])
	_expect(not String(net.call("name_of", 5)).contains("\n"),
		"a newline cannot reach a Label and turn a one-line row into two")
	_expect(String(net.call("name_of", 6)) == "Player 6",
		"an empty name falls back to the peer's number rather than a blank card")
	# A peer nobody has heard from is a number, not "".
	_expect(String(net.call("name_of", 9)) == "Player 9",
		"and an unheard-of peer reads as its number while it is still connecting")

	# ⚠ THE OTHER RECEIPT. `_announce_name` keys on `get_remote_sender_id()` — with no
	# session that is 0, which is exactly the degenerate id the fallback has to survive.
	net.call("_announce_name", "Ari" + String.chr(0x202E))
	var announced: String = String(net.call("name_of", 0))
	_expect(not announced.contains(String.chr(0x202E)),
		"`_announce_name` cleans on RECEIPT too — sanitising at the SENDER is worth "
		+ "nothing, because the sender is the untrusted party")

	net.set("peer_name", saved)

	# The two structural claims a drive cannot make: that the id comes off the SOCKET
	# rather than out of the packet (else any peer could overwrite the host's row), and
	# that there is exactly one reader.
	var src: String = _read(NET_SCRIPT)
	var at: int = src.find("func _announce_name")
	var body: String = src.substr(at, 400) if at >= 0 else ""
	_expect(at >= 0, "a peer announces its display name as well as its class and floor")
	_expect(body.contains("get_remote_sender_id"),
		("...keyed on the sender id off the socket, never on a value in the packet — "
		+ "otherwise any peer could name itself the host"))
	_expect(src.contains("func name_of"),
		"and there is one reader, so a Label never touches the raw dictionary")
	_completes("net_sanitises_on_receipt_not_only_on_send")


## ⚠ THE SCOPE LOCK IS LOAD-BEARING AND THIS IS WHERE IT IS PINNED. Two players is the
## settled mobile spec — the 25-entity budget, the one-screen arena and the friendly-fire
## social loop are all balanced around exactly two thumbs in one room — and a realm
## screen is precisely the kind of feature that invites somebody to raise it.
## `Net._announce_friendly_fire` names the player who shot you by asking for "the OTHER
## hero", which is only exact while this is 2.
func _test_net_still_seats_exactly_two() -> void:
	var src: String = _read(NET_SCRIPT)
	if src == "":
		return
	_expect(src.contains("const MAX_PLAYERS: int = 2"),
		"Net.MAX_PLAYERS is still 2 — the mobile scope-lock, not a placeholder")
	_completes("net_still_seats_exactly_two")


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


# ═══════════════════════════════════════════════════════════ 3. the screen
func _make_realm() -> Control:
	var script: GDScript = load(REALM_SCRIPT) as GDScript
	if script == null:
		return null
	var c: Control = script.new() as Control
	root.add_child(c)
	c.size = Vector2(BASE_W, BASE_H)
	return c


## ⚠ THE MEASUREMENT IS THE MINIMUM SIZE OF THE COLUMN PLUS ITS MARGINS, not the
## resolved rect. The screen is anchored full-rect, so its resolved rect always "fits"
## by construction — it fits by being clipped. What decides whether the bottom row is
## reachable is how much height the content NEEDS.
func _test_the_realm_screen_fits() -> void:
	var realm: Control = _make_realm()
	_expect(realm != null, "the realm screen instantiates")
	if realm == null:
		return
	await process_frame
	await process_frame
	var col: Control = realm.get("_col") as Control
	_expect(col != null, "the realm screen exposes its column for measurement")
	if col == null:
		realm.queue_free()
		return
	# The MarginContainer's 10 px top + 10 px bottom, which the column's own minimum
	# does not include.
	var needed: float = col.get_combined_minimum_size().y + 20.0
	_measured_h = needed
	_expect(needed <= BASE_H,
		("the whole realm screen fits 360 px of height (needs %.0f) — height is the "
		+ "scarce axis: `aspect=expand` grows the WIDTH on a taller phone, never the height")
		% needed)
	_expect(col.get_combined_minimum_size().x + 32.0 <= BASE_W,
		"and it fits 640 px of width (needs %.0f), which is a floor rather than a ceiling"
		% (col.get_combined_minimum_size().x + 32.0))
	# ⚠ NO SINGLE ELEMENT MAY EAT THE PAGE. The same rule `slice_test_settings` holds the
	# title screen to; without it "the column fits" is satisfied by one enormous row.
	for c: Node in col.get_children():
		var cc: Control = c as Control
		if cc != null and cc.visible:
			_expect(cc.get_combined_minimum_size().y <= BASE_H * 0.35,
				"no realm row eats more than 35%% of the screen (%s is %.0f px)"
				% [cc.get_class(), cc.get_combined_minimum_size().y])
	realm.queue_free()
	await process_frame
	_completes("the_realm_screen_fits_the_base_viewport")


## Every tappable row — the buttons AND the name field, which is the one control on this
## screen a player has to hit precisely.
func _test_every_realm_row_clears_the_thumb_floor() -> void:
	var realm: Control = _make_realm()
	if realm == null:
		return
	await process_frame
	var seen: int = 0
	for b: Button in _all(realm, "Button"):
		seen += 1
		_expect(b.custom_minimum_size.y >= MIN_TAP_PX - 0.5,
			"the realm button `%s` clears the %.0f px thumb floor (got %.0f)"
			% [b.text, MIN_TAP_PX, b.custom_minimum_size.y])
		# A stray focus ring on a phone reads as a rendering bug — the rule every other
		# screen in this game holds to.
		_expect(b.focus_mode == Control.FOCUS_NONE,
			"the realm button `%s` takes no focus ring" % b.text)
	_expect(seen >= 4,
		("the screen offers Host, Join, Local Play and a way back (found %d buttons) — "
		+ "Start Run is hidden until you are hosting") % seen)
	for e: LineEdit in _all(realm, "LineEdit"):
		_expect(e.custom_minimum_size.y >= MIN_TAP_PX - 0.5,
			"the name field clears the %.0f px thumb floor (got %.0f)"
			% [MIN_TAP_PX, e.custom_minimum_size.y])
		# The engine's own cap as well as the sanitiser's: a `LineEdit` WIDENS its
		# container while it holds text, so this is a layout guard before it is a data one.
		_expect(e.max_length > 0 and e.max_length <= PlayerProfile.MAX_NAME_CHARS,
			"the name field caps its own length at %d (got %d)"
			% [PlayerProfile.MAX_NAME_CHARS, e.max_length])
	# The three verbs are present and say what they are.
	var joined: String = ""
	for b: Button in _all(realm, "Button"):
		joined += b.text + " | "
	for wanted: String in ["Host", "Join", "Local Play", "Start Run", "Back"]:
		_expect(joined.contains(wanted),
			"the realm screen offers `%s` (has: %s)" % [wanted, joined])
	realm.queue_free()
	await process_frame
	_completes("every_realm_row_clears_the_thumb_floor")


## ⚠ AN EMPTY SEAT MUST READ AS AN INVITATION. A blank right-hand card, or one saying
## "Player 2 — —", is indistinguishable from a screen that failed to load — and this is
## the state the screen is in for the whole of the time somebody is trying to join.
func _test_an_empty_seat_reads_as_an_invitation() -> void:
	var realm: Control = _make_realm()
	if realm == null:
		return
	await process_frame
	var texts: Array[String] = []
	for l: Label in _all(realm, "Label"):
		texts.append(l.text)
		_expect(not l.text.begins_with("Player "),
			("no seat reads as a bare peer NUMBER (`%s`) — the number is assigned by the "
			+ "host and is not a person") % l.text)
	var joined: String = " | ".join(texts)
	_expect(joined.to_lower().contains("waiting for a friend"),
		"the empty seat invites somebody in (labels: %s)" % joined)
	# And your own seat says YOUR name, not a placeholder.
	PlayerProfile.set_display_name("Rae")
	realm.call("_refresh")
	await process_frame
	var joined2: String = ""
	for l: Label in _all(realm, "Label"):
		joined2 += l.text + " | "
	_expect(joined2.contains("Rae"),
		"your own seat shows your name (labels: %s)" % joined2)
	realm.queue_free()
	await process_frame
	_completes("an_empty_seat_reads_as_an_invitation")


## The route. Pressing the title's existing MULTIPLAYER button must open this screen —
## which is the whole ask, and is the half a unit test of the screen alone cannot see.
func _test_multiplayer_opens_the_realm_screen() -> void:
	var packed: PackedScene = load(LOBBY_SCENE) as PackedScene
	_expect(packed != null, "the lobby scene loads")
	if packed == null:
		return
	var lobby: Control = packed.instantiate() as Control
	root.add_child(lobby)
	await process_frame
	await process_frame
	var mp: Button = null
	for b: Button in _all(lobby, "Button"):
		if b.text.begins_with("MULTIPLAYER"):
			mp = b
	_expect(mp != null, "the title screen still has a MULTIPLAYER button")
	if mp == null:
		lobby.queue_free()
		return
	mp.pressed.emit()
	await process_frame
	await process_frame
	var realm: Variant = lobby.get("_realm")
	_expect(realm != null and is_instance_valid(realm as Object),
		"pressing MULTIPLAYER opens the realm screen")
	# And it closes cleanly, or hosting-then-backing-out leaks an overlay per press.
	if realm != null and (realm as Object).has_signal(&"closed"):
		(realm as Object).emit_signal(&"closed")
		await process_frame
		_expect(lobby.get("_realm") == null, "and Back closes it")
	lobby.queue_free()
	await process_frame
	_completes("multiplayer_opens_the_realm_screen")


## ⚠ THE THING THE MAKER ASKED FOR TWICE. The title was cut from ten buttons to three
## and then asked to be smaller and clear of the artwork. This change routes the
## MULTIPLAYER press somewhere new; it must not have added a row or changed a size.
func _test_the_title_screen_gained_no_button() -> void:
	var packed: PackedScene = load(LOBBY_SCENE) as PackedScene
	if packed == null:
		return
	var lobby: Control = packed.instantiate() as Control
	root.add_child(lobby)
	await process_frame
	await process_frame
	var visible_texts: Array[String] = []
	for b: Button in _all(lobby, "Button"):
		if not b.is_visible_in_tree():
			continue    # the collapsed co-op fallback and the join screen
		visible_texts.append(b.text)
		if b.text.begins_with("SINGLE PLAYER") or b.text.begins_with("MULTIPLAYER"):
			_expect(b.custom_minimum_size.y >= MIN_PRIMARY_PX - 0.5,
				("the PRIMARY title button `%s` still clears %.0f px (got %.0f) — the "
				+ "front door's four buttons once measured 5.5 to 7.6 mm")
				% [b.text, MIN_PRIMARY_PX, b.custom_minimum_size.y])
	for t: String in visible_texts:
		_expect(TITLE_BUTTONS.has(t),
			("the title screen shows only its four agreed rows; `%s` is new. The realm "
			+ "screen is one press IN — nothing is added to the front door.") % t)
	_expect(visible_texts.size() == TITLE_BUTTONS.size(),
		"and it still shows exactly %d (found %d: %s)"
		% [TITLE_BUTTONS.size(), visible_texts.size(), visible_texts])
	lobby.queue_free()
	await process_frame
	_completes("the_title_screen_gained_no_button")


## ⚠ LOCAL PLAY IS NOT A LOOPBACK HOST, AND THIS IS THE ASSERTION THAT KEEPS IT HONEST.
## `Net.host()` opens a real ENet server on a real port and starts a UDP beacon; that is
## ONLINE play that happens to also answer on 127.0.0.1. Same-screen co-op is separate
## and already shipped — `Arena` builds a `LocalCoop` on every offline run and a second
## person joins by pressing A on a pad. What was missing was `SessionKind.LOCAL`, which
## `GameState` DECLARED and nothing ever wrote, so `World._session_is_party()` was false
## for a couch game and the hub's Party Stone could not stand up for one.
## ⚠ NOT DRIVEN END-TO-END, AND THE REASON IS THE HARNESS RATHER THAN THE FEATURE.
## `--script` brings up the REAL `GameState`, holding the maker's own climber save, and
## `_local_play` ends in `visit_hub()` — a genuine scene change that pulls the whole
## Antechamber in and swaps the tree out from under this suite. An earlier draft did
## exactly that. A `FakeGameState` cannot help either: the real autoload already occupies
## `/root/GameState`, so a second node of that name is auto-renamed `@GameState@2` and
## the lookup silently finds the real one — which is precisely the shape of vacuous pass
## this file's header is about.
##
## So the MAGIC NUMBER is checked against the live enum by reflection (which is the one
## thing that could actually be wrong about the write), and the "no network" half is
## checked against the source. Said plainly, because this is a weaker claim than a drive.
func _test_local_play_is_not_a_network_path() -> void:
	var gs: Node = root.get_node_or_null(^"/root/GameState")
	_expect(gs != null, "the GameState autoload is up")
	if gs == null:
		return
	# ⚠ THE ENUM, READ FROM THE LIVE SCRIPT. `Lobby` writes the literal `1` (a bare
	# `GameState.SessionKind.LOCAL` inside a UI script would be an autoload reference,
	# which the rest of the file deliberately avoids), and a literal is only correct
	# while the enum's ORDER is. Reordering `{ SOLO, LOCAL, ONLINE }` would silently
	# turn Local Play into an online session.
	var consts: Dictionary = gs.get_script().get_script_constant_map()
	_expect(consts.has("SessionKind"), "GameState declares a SessionKind enum")
	if consts.has("SessionKind"):
		var kinds: Dictionary = consts["SessionKind"]
		_expect(int(kinds.get("LOCAL", -1)) == 1,
			("SessionKind.LOCAL is still 1 (got %d) — `Lobby._local_play` writes the "
			+ "literal, so a reorder would make Local Play an ONLINE session")
			% int(kinds.get("LOCAL", -1)))
		_expect(int(kinds.get("SOLO", -1)) == 0, "...and SOLO is still 0")

	var src: String = _read("res://scripts/ui/Lobby.gd")
	var at: int = src.find("func _local_play")
	_expect(at >= 0, "the lobby has a _local_play")
	if at < 0:
		return
	var body: String = src.substr(at, 900)
	_expect(body.contains("\"session_kind\", 1"),
		("Local Play sets SessionKind.LOCAL — the value GameState DECLARED and nothing "
		+ "ever wrote, which is why `World._session_is_party()` was false for a couch "
		+ "game and the hub's Party Stone could never stand up for one"))
	_expect(body.contains("visit_hub"),
		"...and walks into the same room SINGLE PLAYER does")
	# ⚠ THE LINE THAT KEEPS IT HONEST. `Net.host()` opens a real ENet server on a real
	# port and starts a UDP beacon; that is ONLINE play that happens to also answer on
	# 127.0.0.1. Same-screen co-op is separate and already shipped — `Arena` builds a
	# `LocalCoop` on every offline run — so routing this through the socket would be
	# relabelling the wrong thing.
	_expect(not body.contains("_net."),
		"`_local_play` never touches Net")
	_expect(not body.contains(".host("), "...and never hosts")
	# And the feature it is a door to is really in this build, or the button is a lie.
	_expect(ResourceLoader.exists("res://scripts/combat/LocalCoop.gd"),
		"same-screen co-op is in this build for the button to lead to")
	var arena: String = _read("res://scripts/combat/Arena.gd")
	_expect(arena.contains("LocalCoop.new()"),
		"...and the arena still builds one on the offline branch")
	_completes("local_play_is_not_a_network_path")
