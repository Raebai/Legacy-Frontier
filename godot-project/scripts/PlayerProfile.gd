extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════════
## WHO YOU ARE — one name, one id, one file, and the first identity this game
## has ever had.
## ═══════════════════════════════════════════════════════════════════════════════
##
## ⚠ BEFORE THIS THERE WAS NO PLAYER IDENTITY AT ALL, and that is not an overstatement.
## `Net` tracked `peer_class` and `peer_floor` and nothing else: no display name, no id,
## nowhere to put one. So a co-op screen could only ever have said "Player 2 —
## Stormcaller", and a friend list would have had nothing to key a friend ON. The maker
## asked for a realm screen "where you can add other people to your realm"; the honest
## first half of that is a person to add.
##
## ⚠ NO `class_name`, DELIBERATELY, AND FOR THE REASON `Settings.gd` GIVES AT LENGTH.
## Registering a global class rewrites Godot's `global_script_class_cache.cfg`, and this
## checkout is edited by several agents at once — a concurrent import corrupts that cache
## and takes the whole dependency chain down with a misleading "missing method" error
## somewhere else entirely. Consumers do:
##
##     const PlayerProfile := preload("res://scripts/PlayerProfile.gd")
##
## which resolves at compile time, needs no import, and — because `preload` returns the
## one GDScript resource — shares the static state below across every consumer. That is
## the same shape `Settings` and `HudStyle` already ship in, so this is the house idiom
## rather than an exception to it.
##
## ⚠ AND EVERYTHING HERE IS STATIC, WHICH FORBIDS NAMING AN AUTOLOAD. Saying `GameState`
## as a bare identifier inside a `static func` is a COMPILE error in GDScript and it
## surfaces as an unrelated missing method (see `Settings`'s header, and
## `TuningConfig.quality_is_low`). Nothing in this file reaches an autoload; it does not
## need to.
##
## ⚠ THE STATIC-NAMESPACE TRAP. A `const X := preload("....gd")` IS the script resource,
## so every method here shares a namespace with `Script`, `Resource` and `Object`. That
## is why there is no `load()`, no `save()` and no `reload()` on this class — `Settings`
## lost an hour to `reload()` silently resolving to `Script.reload()` and recompiling
## itself, which reset every static and pointed the suite at the maker's real file while
## reporting all PASS.

## ══════════════════════════════════════════════════════════════════ the file
## Its OWN file rather than a section of `user://settings.cfg`, and that is a
## durability decision rather than tidiness. `Settings` is a `ConfigFile` written on a
## 400 ms debounce from a slider drag; the profile is written once, rarely, and is the
## key a future friend list hangs off — so it gets the same treatment `climber.json`
## gets: JSON, versioned, and written tmp-then-rename so a crash mid-write cannot
## corrupt an identity that already exists.
const PATH: String = "user://profile.json"
const SAVE_VERSION: int = 1

## What an unnamed climber is called. Never "" and never "Player 1": the empty-name
## fallback has to READ as a person, because it is what the realm screen puts on the
## left-hand card on a first run before anybody has typed anything.
const DEFAULT_NAME: String = "Climber"

## ⚠ 16 CHARACTERS, AND THE NUMBER IS A LAYOUT MEASUREMENT RATHER THAN A PREFERENCE.
## `RealmScreen` gives each of the two identity cards half of the 640-px base viewport
## less its margins — about 296 px — and draws the name at font 15, where a wide glyph
## runs ~9 px. 16 characters is ~144 px, i.e. it fits with room to spare even before
## `clip_text` is asked to do anything. It is also short enough that the beacon packet
## (`Net._process` broadcasts the name once a second) stays inside one UDP datagram
## with no thought required.
const MAX_NAME_CHARS: int = 16

## ⚠ THE PATH IS A VARIABLE SO A SUITE CAN POINT IT SOMEWHERE ELSE, and `Settings` paid
## for this lesson in full: the only honest way to prove a name SURVIVES A RESTART is to
## write it, throw the in-memory copy away, read the file back and check what comes out —
## and a suite that did that against `user://profile.json` would rename the maker every
## time it ran. Ships at `PATH`; only `tools/slice_test_realm.gd` ever moves it.
static var _path: String = PATH

static var _loaded: bool = false
static var _name: String = ""
static var _id: String = ""


# ══════════════════════════════════════════════════════════════════ the reads
## The name to put in front of a human. NEVER empty — a blank card reads as a broken
## screen, not as "unnamed" — so a missing file, a corrupt file, a file whose name is
## nothing but control characters, and a file that has simply never been written all
## come back as `DEFAULT_NAME`.
static func display_name() -> String:
	_ensure_loaded()
	return _name if _name != "" else DEFAULT_NAME


## Has the player actually chosen a name, as opposed to being handed the default?
##
## ⚠ THE DISTINCTION EXISTS FOR EXACTLY ONE CALLER AND IT IS NOT COSMETIC. `Net.host()`
## puts a name on the LAN beacon, and the beacon's job is to tell two phones in one room
## APART. `display_name()` can never say "unset" — it is contractually never empty — so a
## host that asked it would advertise "Climber" on a first run, and two unnamed hosts
## would be two identical buttons in the join list. `Net` therefore falls back to the
## machine name (`_default_host_name`) until this is true.
static func is_named() -> bool:
	_ensure_loaded()
	return _name != ""


## The stable local id. Minted once on the first run that asks for it and written
## immediately, so it is the same string tomorrow.
##
## ⚠ WHAT IT IS FOR, SAID OUT LOUD BECAUSE NOTHING CONSUMES IT YET. `MAX_PLAYERS` is 2
## and a two-person session can key everything on the ENet peer id, which is what
## `Net.peer_class` / `peer_floor` / `peer_name` all do. A peer id is assigned by the
## host and is meaningless five seconds after the session ends, so it cannot be what a
## friend list remembers. This can. It is deliberately minted now rather than when the
## friend list is built, because an id added later is an id that half the installed base
## does not have.
static func player_id() -> String:
	_ensure_loaded()
	if _id == "":
		_id = _mint_id()
		write_now()
	return _id


# ═════════════════════════════════════════════════════════════════ the writes
## Set the name and put it on disk. Returns what was actually STORED, which may not be
## what was passed — the caller (a `LineEdit`) should show the stored form back so the
## player can see that their 40-character paste became 16.
static func set_display_name(raw: String) -> String:
	_ensure_loaded()
	_name = sanitize_name(raw)
	write_now()
	return display_name()


## Write the profile. Atomic: JSON into `<path>.tmp`, then a rename over the real file,
## which on Windows is `MoveFileEx(MOVEFILE_REPLACE_EXISTING)`. Straight from
## `GameState._save_climber`, and for its stated reason — a crash mid-write cannot
## corrupt a profile that already exists.
static func write_now() -> void:
	var payload: Dictionary = build_profile_save(_name, _id)
	var tmp_path: String = _path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("PlayerProfile.write_now: cannot open %s for writing" % tmp_path)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	var dir: DirAccess = DirAccess.open(_path.get_base_dir() + "/")
	if dir == null:
		push_error("PlayerProfile.write_now: cannot open %s" % _path.get_base_dir())
		return
	var err: int = dir.rename(tmp_path.get_file(), _path.get_file())
	if err != OK:
		push_error("PlayerProfile.write_now: rename %s -> %s failed (err=%d)"
			% [tmp_path.get_file(), _path.get_file(), err])


# ══════════════════════════════════════════════════════ the record (pure, testable)
## The on-disk profile record. Static + pure, so a suite can prove the shape without a
## disk, a tree or an autoload — the same split `GameState.build_climber_save` uses.
##
## ⚠ NEW FIELDS GO ON THE END WITH A DEFAULT, NEVER IN THE MIDDLE. That is the rule
## `build_climber_save` states about its own three levelling fields, and it is what keeps
## every existing positional caller — and every suite that pins one — untouched when this
## record grows a friend list.
static func build_profile_save(display: String, id: String = "") -> Dictionary:
	return {
		"version": SAVE_VERSION,
		# Sanitised ON THE WAY OUT as well as on the way in. A hand-edited file is one
		# route in; a future caller that forgets to sanitise is the other, and this is
		# the single point both pass through.
		"name": sanitize_name(display),
		"id": _sanitize_id(id),
	}


## A raw (JSON-loaded) profile dict, parsed into `{name, id}` with both fields cleaned.
##
## ⚠ THE M9 JSON TRAP IS WHY `version` IS COERCED THROUGH `int()`. `JSON.parse_string`
## hands back every number as `TYPE_FLOAT`, so a saved `1` arrives as `1.0` and a bare
## `raw.get("version") == 1` is FALSE against it. In M9 that exact confusion made a
## valid v2 save look like a v1, ran the migration on it and DESTROYED the NPC memory —
## and it survived two code reviews because it fails in the direction that still looks
## correct. There is only one version today, so nothing branches on it yet; the coercion
## is here so that the day something does, it is already right.
##
## A malformed record is not an error path. It yields the defaults, because the correct
## response to "your profile file is nonsense" is a climber called `Climber`, not a
## refusal to start the game.
static func parse_profile_save(raw: Variant) -> Dictionary:
	var out: Dictionary = {"version": SAVE_VERSION, "name": "", "id": ""}
	if not (raw is Dictionary):
		return out
	var d: Dictionary = raw
	var v: Variant = d.get("version", SAVE_VERSION)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		out["version"] = int(v)
	var n: Variant = d.get("name", "")
	if typeof(n) == TYPE_STRING:
		out["name"] = sanitize_name(String(n))
	var i: Variant = d.get("id", "")
	if typeof(i) == TYPE_STRING:
		out["id"] = _sanitize_id(String(i))
	return out


# ══════════════════════════════════════════════════════════ SANITISING A NAME
## ⚠ THIS IS THE SECURITY BOUNDARY, AND IT HAS TWO SIDES. One is the player's own
## `LineEdit`, which is merely careless. The other is `Net._announce_name` — a string
## that arrived over a socket from another machine and is on its way to a `Label`. Both
## go through here, and the wire side is the reason the rules below are not just a
## length cap:
##
##   * **C0 CONTROLS (< 0x20) AND DEL (0x7F).** A newline in a name turns a one-line row
##     into a two-line one and silently re-measures the card that has to fit 360 px of
##     height. `\t` and `\r` do the same to a `Label`'s metrics.
##   * **C1 CONTROLS (0x80..0x9F).** Same class, and they survive a naive `is_valid_*`
##     style filter because they are "printable" as far as a length check cares.
##   * **BIDI OVERRIDES (U+200E/F, U+202A..U+202E, U+2066..U+2069) AND U+FEFF.** These
##     are the interesting ones. `U+202E RIGHT-TO-LEFT OVERRIDE` reverses the rendering
##     of everything after it, so a name can make the text NEXT TO IT read backwards —
##     which is how the "Rae — Stormcaller" row gets to say something the sender chose
##     rather than something this game wrote. It is invisible, so it cannot be
##     eyeballed, and the character count does not notice it either.
##
## ⚠ TAB / NEWLINE / CR BECOME A SPACE RATHER THAN BEING DELETED. Deleting them turns
## "Ari\tB" into "AriB", which quietly invents a name nobody typed; a space preserves the
## word break the sender meant. Every other control is genuinely meaningless and goes.
##
## Runs of spaces are then collapsed and the edges stripped, so leading whitespace cannot
## be used to sort yourself to the top of a future list, and so a name that is nothing
## BUT whitespace comes back as `""` — which every reader turns into a real fallback.
##
## ⚠ THE CAP IS APPLIED LAST AND IN CHARACTERS. `String.length()` in Godot 4 is a COUNT
## OF CODE POINTS, not bytes, so an emoji or an accented letter costs one here and the
## card's width budget is honoured. Capping first would let a 200-space prefix eat the
## whole allowance and leave an empty name.
static func sanitize_name(raw: String) -> String:
	var out: String = ""
	for i: int in raw.length():
		var c: int = raw.unicode_at(i)
		if c == 0x09 or c == 0x0A or c == 0x0D:
			out += " "
			continue
		if c < 0x20 or c == 0x7F or (c >= 0x80 and c <= 0x9F):
			continue
		if c == 0x200E or c == 0x200F or (c >= 0x202A and c <= 0x202E):
			continue
		if (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF:
			continue
		out += String.chr(c)
	# Collapse runs of spaces. A bounded loop rather than a regex: `RegEx` has to be
	# compiled and this runs on a UDP packet handler once a second.
	while out.contains("  "):
		out = out.replace("  ", " ")
	out = out.strip_edges()
	if out.length() > MAX_NAME_CHARS:
		out = out.substr(0, MAX_NAME_CHARS).strip_edges()
	return out


## What a name off the WIRE is allowed to become. Same cleaning, but an empty result
## falls back to the peer's own number rather than to `DEFAULT_NAME` — two unnamed
## players in one session must not both be called "Climber", because the entire job of
## the right-hand card is to say who the other person is.
static func clean_incoming(raw: String, peer_id: int) -> String:
	var clean: String = sanitize_name(raw)
	return clean if clean != "" else ("Player %d" % maxi(peer_id, 1))


# ═════════════════════════════════════════════════════════════════════ the id
## 24 lowercase hex characters. Long enough that two installs colliding is not worth
## thinking about, short enough to read aloud in a bug report.
const ID_CHARS: int = 24


## ⚠ MINTED FROM TIME + RNG, AND EXPLICITLY NOT FROM `OS.get_unique_id()`. That call
## returns a real hardware identifier, and writing a device fingerprint to disk — and
## then, the moment a friend list exists, over a network — is a privacy decision this
## feature has no need to make. A random id is exactly as stable, because stability
## comes from the FILE, not from the source of the bytes.
static func _mint_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# The clock is mixed in so two installs minted in the same second by an RNG that
	# somehow failed to seed still differ.
	var s: String = "%08x" % (int(Time.get_unix_time_from_system()) & 0xFFFFFFFF)
	while s.length() < ID_CHARS:
		s += "%08x" % rng.randi()
	return s.substr(0, ID_CHARS)


## An id is machine-written, so this is a shape check rather than a cleaning: anything
## that is not lowercase hex of the right length is treated as absent and a fresh one is
## minted. A hand-edited or truncated id must not become a permanent identity.
static func _sanitize_id(raw: String) -> String:
	if raw.length() != ID_CHARS:
		return ""
	for i: int in raw.length():
		var c: int = raw.unicode_at(i)
		var is_digit: bool = c >= 0x30 and c <= 0x39
		var is_hex_lower: bool = c >= 0x61 and c <= 0x66
		if not (is_digit or is_hex_lower):
			return ""
	return raw


# ═══════════════════════════════════════════════════════════════════ the cache
## Read the file at most once per process. A missing file is not an error — it is a
## first run — so it leaves the defaults in place and does NOT write anything: minting
## an id is what creates the file, and it happens on the first `player_id()`.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(_path):
		return
	var f: FileAccess = FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	# ⚠ NO `push_error` ON A BAD PARSE, UNLIKE `GameState._load_climber`. A corrupt
	# climber save loses a climb and is worth shouting about; a corrupt profile loses a
	# nickname, and the recovery — `Climber`, and a fresh id on the next write — is
	# complete and silent. Erroring here would put a red line in the console on every
	# boot for a file the player cannot see and did not break.
	var state: Dictionary = parse_profile_save(parsed)
	_name = String(state["name"])
	_id = String(state["id"])


## Where the profile lives right now.
static func profile_path() -> String:
	return _path


## ⚠ TESTS ONLY — see the note on `_path`. Drops the in-memory copy, so the next read
## comes off the new file.
static func use_path(p: String) -> void:
	_path = p
	forget_cache()


## Forget everything held in memory and re-read on next access. This is what "the player
## closed the game and opened it again" looks like from inside one process, and it is the
## only way a suite can PROVE persistence rather than assert it — writing a value and
## reading the same value back proves only that the in-memory copy answers.
##
## ⚠ NOT CALLED `reload()`. See the header: that name resolves to `Script.reload()` on a
## preloaded script and recompiles this file, resetting every static above.
static func forget_cache() -> void:
	_loaded = false
	_name = ""
	_id = ""
