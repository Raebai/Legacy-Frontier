# Persistent-Climb Spine (Floors Step 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the roguelite run-loop into a persistent Tower-of-God climb — highest/current floor, falls, and rank persist to disk; entering the tower resumes from the saved floor; dying drops you 2 floors but keeps everything (you stay in the tower); a deliberate return portal on cleared floors takes you back to the hub where the NPCs clock your climb.

**Architecture:** Extends the already-shipped data-driven floor system (steps 1–4). `GameState` (autoload) gains a small JSON persistence layer at `user://climber.json` following the existing atomic tmp-rename idiom from `NPC.save_memory`. The run-loop's three transition points (advance / fall / return) each mutate the persisted climber state and save. `Hero._die` in a run now calls `GameState.fall()` (drop-2, stay) instead of `end_run(true)` (die → hub). `Arena` gains a `fell` handler that clears enemies, rebuilds the dropped floor in place, and revives the hero — reusing the existing floor-rebuild mechanism — plus a second "RETURN TO TOWN" portal on non-final cleared floors.

**Tech Stack:** Godot 4.6 / GDScript. Headless test runner via the repo `SceneTree`-on-first-`_process` idiom (see `tools/slice2_test_runloop.gd`). Godot headless binary: `godot-engine/Godot_v4.6.2-stable_win64_console.exe`.

## Global Constraints

- Branch: `v2.0-tower` (build directly on it — Godot/Gopeak bind to this working dir).
- All new persistence code is **static + pure where possible** so it tests headlessly with no scene, no Ollama, no `change_scene` — matching the existing `GameState` static/pure discipline.
- **JSON int/float trap (the M9 lesson):** `JSON.parse_string` returns every number as `TYPE_FLOAT`. Every int field read back from disk MUST be coerced through `int(...)`; every bool through `bool(...)`. This is non-negotiable — it silently corrupted saves in M9.
- Persistence uses the **atomic tmp-then-rename** write (write `<file>.tmp`, then `DirAccess.rename` to the final name) so a crash mid-write can't corrupt an existing save. Copy the pattern from `NPC.save_memory` (`godot-project/scripts/NPC.gd:148-184`).
- **Backward compatible:** a missing `user://climber.json` must yield the exact pre-step-5 behaviour (start at floor 1). `build_outcome`'s new `falls` parameter must default so the existing 7-arg call sites and tests keep passing.
- The **F6 sandbox** (`Arena.tscn` with no active run) must be untouched — every new code path is gated behind `_run_mode` / `is_run_active()`.
- Godot's global-class cache trap: after adding/changing any `class_name` or before any run that consumes new script shapes, run a headless `--import` once (see the run commands in each task).

---

### Task 1: Climber persistence data layer (pure/static) + fall math

Pure, headless-testable functions on `GameState`: the disk save-shape builder, the parser (with the JSON float-trap coercion), the fall-floor math, and the `falls`-aware extensions to the existing outcome/fact builders. No IO, no scene — just data transforms with a dedicated test.

**Files:**
- Modify: `godot-project/scripts/GameState.gd` (add static funcs; extend `build_outcome` / `build_run_fact` / `run_hint_text`)
- Test: `godot-project/tools/slice_test_climb.gd` (new)

**Interfaces:**
- Produces (consumed by Tasks 2 & 3):
  - `static func fall_floor(current: int) -> int` — `maxi(current - 2, 1)`
  - `static func build_climber_save(current_floor: int, highest_floor: int, falls: int, tower_conquered: bool, rank_power: int) -> Dictionary`
  - `static func parse_climber_save(raw: Dictionary) -> Dictionary` — returns `{current_floor:int, highest_floor:int, falls:int, tower_conquered:bool, rank_power:int}`, all ints coerced
  - `static func build_outcome(..., rank_title: String, falls: int = 0) -> Dictionary` — now carries `"falls"`
  - `const CLIMBER_SAVE_VERSION: int = 1`

- [ ] **Step 1: Write the failing test**

Create `godot-project/tools/slice_test_climb.gd`:

```gdscript
# Run: godot --headless --path godot-project --script tools/slice_test_climb.gd
# Persistent-climb spine (floors step 5). GameState's climber save/parse + fall
# math are static + pure, so they test with no scene, no Ollama, no change_scene.
# One isolated disk round-trip uses a throwaway user:// path so the maker's real
# climber.json is never touched. Runs on the first _process frame per repo idiom.
extends SceneTree

const GS_PATH: String = "res://scripts/GameState.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var GS: GDScript = load(GS_PATH) as GDScript
	var failed: int = 0
	failed += _test_fall_floor(GS)
	failed += _test_climber_save_shape(GS)
	failed += _test_parse_json_float_trap(GS)
	failed += _test_outcome_carries_falls(GS)
	failed += _test_fact_mentions_falls(GS)
	failed += _test_climber_disk_roundtrip(GS)
	if failed > 0:
		printerr("Climb spine tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Climb spine tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_fall_floor(GS: GDScript) -> int:
	var failed: int = 0
	failed += _expect(int(GS.fall_floor(5)) == 3, "fall from 5 -> 3")
	failed += _expect(int(GS.fall_floor(3)) == 1, "fall from 3 -> 1")
	failed += _expect(int(GS.fall_floor(2)) == 1, "fall from 2 clamps to 1")
	failed += _expect(int(GS.fall_floor(1)) == 1, "fall from 1 stays 1")
	return failed


func _test_climber_save_shape(GS: GDScript) -> int:
	var failed: int = 0
	var s: Dictionary = GS.build_climber_save(4, 6, 2, true, 40)
	failed += _expect(int(s["version"]) == int(GS.CLIMBER_SAVE_VERSION), "version stamped")
	failed += _expect(int(s["current_floor"]) == 4, "current floor carried")
	failed += _expect(int(s["highest_floor"]) == 6, "highest floor carried")
	failed += _expect(int(s["falls"]) == 2, "falls carried")
	failed += _expect(bool(s["tower_conquered"]) == true, "conquered carried")
	failed += _expect(int(s["rank_power"]) == 40, "rank power carried")
	# highest is clamped to be >= current even if a caller passes a stale value.
	var s2: Dictionary = GS.build_climber_save(5, 3, 0, false, 0)
	failed += _expect(int(s2["highest_floor"]) == 5, "highest clamps up to current")
	# floors/falls/power never go below their floors.
	var s3: Dictionary = GS.build_climber_save(0, 0, -3, false, -9)
	failed += _expect(int(s3["current_floor"]) == 1, "current floor floored at 1")
	failed += _expect(int(s3["falls"]) == 0, "falls floored at 0")
	failed += _expect(int(s3["rank_power"]) == 0, "rank power floored at 0")
	return failed


func _test_parse_json_float_trap(GS: GDScript) -> int:
	# The real trap: JSON.parse_string returns numbers as TYPE_FLOAT. parse_climber_save
	# MUST coerce every int field or reloads corrupt (M9 lesson). Round-trip through
	# actual JSON text to reproduce the float typing authentically.
	var failed: int = 0
	var payload: Dictionary = GS.build_climber_save(4, 6, 2, true, 40)
	var text: String = JSON.stringify(payload)
	var back: Variant = JSON.parse_string(text)
	failed += _expect(typeof(back) == TYPE_DICTIONARY, "JSON parses back to a dict")
	var state: Dictionary = GS.parse_climber_save(back)
	failed += _expect(typeof(state["current_floor"]) == TYPE_INT, "current floor coerced to int")
	failed += _expect(typeof(state["highest_floor"]) == TYPE_INT, "highest floor coerced to int")
	failed += _expect(typeof(state["falls"]) == TYPE_INT, "falls coerced to int")
	failed += _expect(typeof(state["rank_power"]) == TYPE_INT, "rank power coerced to int")
	failed += _expect(int(state["current_floor"]) == 4, "current value survives")
	failed += _expect(int(state["highest_floor"]) == 6, "highest value survives")
	failed += _expect(bool(state["tower_conquered"]) == true, "conquered value survives")
	# A malformed/empty dict yields safe defaults (fresh climber).
	var empty: Dictionary = GS.parse_climber_save({})
	failed += _expect(int(empty["current_floor"]) == 1, "empty parse -> floor 1")
	failed += _expect(int(empty["falls"]) == 0, "empty parse -> 0 falls")
	return failed


func _test_outcome_carries_falls(GS: GDScript) -> int:
	var failed: int = 0
	# 8-arg call carries falls.
	var o: Dictionary = GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber", 4)
	failed += _expect(int(o["falls"]) == 4, "outcome carries falls when passed")
	# 7-arg legacy call still works (default 0) — proves backward compat.
	var o2: Dictionary = GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber")
	failed += _expect(int(o2["falls"]) == 0, "outcome falls defaults to 0")
	return failed


func _test_fact_mentions_falls(GS: GDScript) -> int:
	var failed: int = 0
	var many: String = GS.build_run_fact(GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber", 3))
	failed += _expect(many.contains("3 falls"), "death fact names the fall count")
	# With 0 falls the fact is unchanged (still contains the base death text).
	var zero: String = GS.build_run_fact(GS.build_outcome(3, 7, false, true, ["Fire"], 1, "Climber", 0))
	failed += _expect(zero.contains("floor 3") and not zero.contains("falls so far"), "0 falls omits the clause")
	return failed


func _test_climber_disk_roundtrip(GS: GDScript) -> int:
	# Isolated disk round-trip through a THROWAWAY path so the real climber.json is
	# untouched. Proves the atomic tmp-rename write + the load path together.
	var failed: int = 0
	var test_path: String = "user://climber_test.json"
	var gs: Node = GS.new()
	gs._floor = 4
	gs._highest_floor = 6
	gs._falls = 2
	gs.tower_conquered = true
	gs._saved_rank_power = 40
	gs._save_climber(test_path)
	var gs2: Node = GS.new()
	gs2._load_climber(test_path)
	failed += _expect(gs2._floor == 4, "current floor round-trips")
	failed += _expect(gs2._highest_floor == 6, "highest floor round-trips")
	failed += _expect(gs2._falls == 2, "falls round-trips")
	failed += _expect(gs2.tower_conquered == true, "conquered round-trips")
	failed += _expect(gs2._saved_rank_power == 40, "rank power round-trips")
	failed += _expect(typeof(gs2._floor) == TYPE_INT, "loaded floor is int not float")
	var d: DirAccess = DirAccess.open("user://")
	if d != null:
		d.remove("climber_test.json")
	gs.free()
	gs2.free()
	return failed
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_climb.gd`
Expected: FAIL — `fall_floor` / `build_climber_save` / `parse_climber_save` / `CLIMBER_SAVE_VERSION` don't exist yet (and `build_outcome` has no `falls`). Errors like "Invalid call. Nonexistent function 'fall_floor'".

- [ ] **Step 3: Add the pure/static functions + extend the builders**

In `godot-project/scripts/GameState.gd`, add the version const near the other consts (after line 31's `KEY_FACTS_CAP`):

```gdscript
## Climber save schema version (bump + migrate if the shape changes).
const CLIMBER_SAVE_VERSION: int = 1
```

Add these static functions in the PURE/STATIC section (after `synthesize_floor_def` / near the floor-math block, e.g. after line 293's `default_layout`):

```gdscript
## Failing a floor drops you 2 floors but never below 1. Pure so it tests headlessly.
static func fall_floor(current: int) -> int:
	return maxi(current - 2, 1)


## The on-disk climber record. All fields clamped to their floors; highest is
## never below current. Static + pure -> headless-testable.
static func build_climber_save(current_floor: int, highest_floor: int, falls: int, tower_conquered: bool, rank_power: int) -> Dictionary:
	var current: int = maxi(current_floor, 1)
	return {
		"version": CLIMBER_SAVE_VERSION,
		"current_floor": current,
		"highest_floor": maxi(highest_floor, current),
		"falls": maxi(falls, 0),
		"tower_conquered": tower_conquered,
		"rank_power": maxi(rank_power, 0),
	}


## Parse a raw (JSON-loaded) climber dict into typed fields. JSON.parse_string
## returns numbers as TYPE_FLOAT, so EVERY int is coerced through int() — the M9
## trap. A malformed/empty dict yields fresh-climber defaults (floor 1).
static func parse_climber_save(raw: Dictionary) -> Dictionary:
	var current: int = maxi(int(raw.get("current_floor", 1)), 1)
	var highest: int = maxi(int(raw.get("highest_floor", current)), current)
	var falls: int = maxi(int(raw.get("falls", 0)), 0)
	var conquered: bool = bool(raw.get("tower_conquered", false))
	var rank_power: int = maxi(int(raw.get("rank_power", 0)), 0)
	return {
		"current_floor": current,
		"highest_floor": highest,
		"falls": falls,
		"tower_conquered": conquered,
		"rank_power": rank_power,
	}
```

Modify `build_outcome` (line 179) to accept + carry `falls`:

```gdscript
static func build_outcome(
	floor_reached: int, kills: int, boss_killed: bool, died: bool,
	elements: Array, rank_tier: int, rank_title: String, falls: int = 0
) -> Dictionary:
	var elems: Array = []
	for e in elements:
		elems.append(str(e))
	return {
		"floor_reached": floor_reached,
		"enemies_killed": kills,
		"boss_killed": boss_killed,
		"cleared": (not died),
		"died": died,
		"rank_tier": rank_tier,
		"rank_title": rank_title,
		"elements_used": elems,
		"falls": maxi(falls, 0),
	}
```

Modify `build_run_fact` (line 199) to append a falls clause on the non-boss paths:

```gdscript
static func build_run_fact(run: Dictionary) -> String:
	var floor_reached: int = int(run.get("floor_reached", 1))
	var kills: int = int(run.get("enemies_killed", 0))
	var falls: int = int(run.get("falls", 0))
	var elems: Array = run.get("elements_used", [])
	var elem_clause: String = ""
	if elems.size() > 0:
		elem_clause = ", wielding %s" % String(elems[0]).to_lower()
	var fall_clause: String = ""
	if falls > 0:
		fall_clause = " (%d falls so far)" % falls
	if bool(run.get("died", false)):
		return "%sfell on floor %d after %d kills%s, came back rattled%s" % [
			RUN_FACT_PREFIX, floor_reached, kills, elem_clause, fall_clause
		]
	if bool(run.get("boss_killed", false)):
		return "%sconquered all %d floors and felled the guardian%s" % [
			RUN_FACT_PREFIX, floor_reached, elem_clause
		]
	return "%swalked out of floor %d alive after %d kills%s%s" % [
		RUN_FACT_PREFIX, floor_reached, kills, elem_clause, fall_clause
	]
```

Modify `run_hint_text` (line 220) death branch to reference repeat falls:

```gdscript
static func run_hint_text(run: Dictionary) -> String:
	var floor_reached: int = int(run.get("floor_reached", 1))
	if bool(run.get("died", false)):
		var falls: int = int(run.get("falls", 0))
		var fall_note: String = ""
		if falls > 1:
			fall_note = " That is %d falls now." % falls
		return ("The player has JUST returned from the tower — they died on floor %d.%s "
			+ "Open by acknowledging that specifically, in your own voice — needle them "
			+ "or console them, but reference the fall.") % [floor_reached, fall_note]
	if bool(run.get("boss_killed", false)):
		return ("The player has JUST returned from the tower — they cleared every floor "
			+ "and put down the guardian. Open by reacting to THAT feat specifically, in "
			+ "your own voice.")
	return ("The player has JUST returned from the tower — they made it to floor %d and "
		+ "walked out alive. Open by reacting to that specifically, in your own voice.") % floor_reached
```

> Note: `_save_climber` / `_load_climber` / the runtime vars (`_highest_floor`, `_falls`, `tower_conquered`, `_saved_rank_power`) used by the disk round-trip test are added in **Task 2**. This test's disk-round-trip case will still fail until Task 2 lands — that is expected and is the bridge into Task 2. All the OTHER cases (fall math, save shape, float trap, outcome, fact) pass at the end of Task 1.

- [ ] **Step 4: Run the pure tests to verify they pass (disk case still pending Task 2)**

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_climb.gd`
Expected: the run FAILS only on `_test_climber_disk_roundtrip` (missing `_save_climber`/`_load_climber`/vars). Confirm every OTHER `_test_*` prints no `FAIL:` line. If any of fall/shape/trap/outcome/fact fail, fix before moving on.

- [ ] **Step 5: Commit**

```bash
git add godot-project/scripts/GameState.gd godot-project/tools/slice_test_climb.gd
git commit -m "climb: pure climber save/parse + fall math + falls-aware run facts"
```

---

### Task 2: Climber IO + load-on-ready (persistence wiring)

Add the runtime persistent vars, the atomic disk writer/reader (path-overridable for isolated testing), the rank-power helpers, and load-on-`_ready`. This completes the disk round-trip test from Task 1.

**Files:**
- Modify: `godot-project/scripts/GameState.gd`
- Test: `godot-project/tools/slice_test_climb.gd` (already written in Task 1 — no new test code; this task makes its disk case pass)

**Interfaces:**
- Consumes (from Task 1): `build_climber_save`, `parse_climber_save`, `CLIMBER_SAVE_VERSION`
- Produces (consumed by Task 3):
  - vars `_highest_floor: int`, `_falls: int`, `tower_conquered: bool`, `_saved_rank_power: int`
  - `func _save_climber(path: String = CLIMBER_PATH) -> void`
  - `func _load_climber(path: String = CLIMBER_PATH) -> void`
  - `func _restore_rank_power() -> void`
  - `func _live_rank_power() -> int`
  - `const CLIMBER_PATH: String`

- [ ] **Step 1: The failing case already exists**

`_test_climber_disk_roundtrip` (Task 1) is the failing test for this task. Confirm it still fails:

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_climb.gd`
Expected: FAIL on the disk round-trip (nonexistent `_save_climber` / `_load_climber` / vars).

- [ ] **Step 2: Add the persistence vars**

In `godot-project/scripts/GameState.gd`, add the path const near `CLIMBER_SAVE_VERSION`:

```gdscript
## Where the persistent climber lives (highest/current floor, falls, conquered, rank).
const CLIMBER_PATH: String = "user://climber.json"
```

Add the runtime vars alongside the existing live-run accumulators (after line 49's `var active_tower` / near `var mode`):

```gdscript
# --- persistent climber state (loaded at _ready, saved at every floor transition) ---
var _highest_floor: int = 1          # highest floor ever reached (monotonic)
var _falls: int = 0                  # cumulative falls (deaths); the town clocks these
var tower_conquered: bool = false    # cleared the guardian at least once this save
var _saved_rank_power: int = 0       # Rank.power snapshot, applied to /root/Rank on enter_run
```

- [ ] **Step 3: Add `_ready` (load on boot) + the IO + rank helpers**

Add `_ready` near the top of the non-static section (before `enter_run`, after line 65's `const TOWER_PATH`):

```gdscript
func _ready() -> void:
	_load_climber()
```

Add the IO + rank helpers in the non-static section (a good home is just after `_change_scene`, ~line 144):

```gdscript
# --------------------------------------------------- climber persistence (IO)
## Atomic save: write <path>.tmp then rename over the real file, so a crash
## mid-write can't corrupt an existing climber. Mirrors NPC.save_memory.
func _save_climber(path: String = CLIMBER_PATH) -> void:
	var payload: Dictionary = build_climber_save(
		_floor, _highest_floor, _falls, tower_conquered, _live_rank_power()
	)
	var tmp_path: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("GameState._save_climber: cannot open %s for writing" % tmp_path)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("GameState._save_climber: cannot open user://")
		return
	var err: int = dir.rename(tmp_path.get_file(), path.get_file())
	if err != OK:
		push_error("GameState._save_climber: rename %s -> %s failed (err=%d)" % [tmp_path.get_file(), path.get_file(), err])


## Load the climber from disk into the runtime vars. Missing file -> defaults
## (fresh climber at floor 1) so the pre-step-5 behaviour is preserved exactly.
func _load_climber(path: String = CLIMBER_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameState._load_climber: malformed save, ignoring")
		return
	var state: Dictionary = parse_climber_save(parsed)
	_floor = int(state["current_floor"])
	_highest_floor = int(state["highest_floor"])
	_falls = int(state["falls"])
	tower_conquered = bool(state["tower_conquered"])
	_saved_rank_power = int(state["rank_power"])


## The live rank power to persist. Reads /root/Rank when present (combat), else
## falls back to the last-saved snapshot (headless / hub) so a save never zeroes it.
func _live_rank_power() -> int:
	var r: Node = get_node_or_null("/root/Rank")
	if r != null:
		return int(r.power)
	return _saved_rank_power


## Push the saved rank power back into /root/Rank (called on entering the tower,
## where the Rank HUD + aura live). No-op headless / if Rank is absent.
func _restore_rank_power() -> void:
	var r: Node = get_node_or_null("/root/Rank")
	if r != null and r.has_method("set_power"):
		r.set_power(_saved_rank_power)
```

- [ ] **Step 4: Run the full climb test — all cases pass**

First a headless import (the class-cache discipline), then the test:

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --import`
Then: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_climb.gd`
Expected: `Climb spine tests: all PASS` (exit 0). The disk round-trip now passes; the throwaway `climber_test.json` is removed by the test.

- [ ] **Step 5: Commit**

```bash
git add godot-project/scripts/GameState.gd
git commit -m "climb: atomic climber persistence to user://climber.json + load-on-ready"
```

---

### Task 3: Rewire the run-loop — resume, fall, return, conquer, rank

Change the three transition points so the loop is a persistent climb: `enter_run` resumes from the saved floor and restores rank; `advance_floor` banks progress + saves + resets on conquer; a new `fall()` drops 2 floors and emits `fell`; a new `return_to_hub()` banks the cleared floor and bounces to the hub. `end_run` now records `falls`.

**Files:**
- Modify: `godot-project/scripts/GameState.gd`
- Test: `godot-project/tools/slice_test_climb.gd` (add loop-transition cases on a bare instance)

**Interfaces:**
- Consumes (from Tasks 1–2): `fall_floor`, `_save_climber`, `_restore_rank_power`, `_highest_floor`, `_falls`, `tower_conquered`
- Produces (consumed by Tasks 4 & 5):
  - `signal fell(new_floor: int)`
  - `func fall() -> void`
  - `func return_to_hub() -> void`
  - (modified) `func enter_run()`, `func advance_floor()`, `func end_run(died: bool)`

- [ ] **Step 1: Write the failing loop-transition tests**

Append these two test functions to `godot-project/tools/slice_test_climb.gd`, and add their calls into `_process` (after `failed += _test_climber_disk_roundtrip(GS)`):

```gdscript
	failed += _test_fall_transition(GS)
	failed += _test_advance_and_bank(GS)
```

```gdscript
## fall() on a live run drops 2 floors, ticks the fall counter, and emits `fell`
## with the dropped floor. Driven on a bare instance (no scene) — _change_scene
## is guarded on get_tree()==null so it no-ops off-tree.
func _test_fall_transition(GS: GDScript) -> int:
	var failed: int = 0
	var gs: Node = GS.new()
	gs.active_tower = GS.build_default_tower()
	gs._run_active = true
	gs._floor = 5
	gs._falls = 1
	var seen: Array = []
	gs.fell.connect(func(nf: int) -> void: seen.append(nf))
	gs.fall()
	failed += _expect(gs._floor == 3, "fall drops 2 floors (5 -> 3)")
	failed += _expect(gs._falls == 2, "fall increments the fall counter")
	failed += _expect(seen.size() == 1 and int(seen[0]) == 3, "fell emitted with the dropped floor")
	# A fall in the SANDBOX (no active run) is a no-op.
	var gs2: Node = GS.new()
	gs2._run_active = false
	gs2._floor = 4
	gs2.fall()
	failed += _expect(gs2._floor == 4, "sandbox fall is a no-op")
	gs.free()
	gs2.free()
	return failed


## advance_floor on a non-final floor banks the next floor + lifts highest.
func _test_advance_and_bank(GS: GDScript) -> int:
	var failed: int = 0
	var gs: Node = GS.new()
	gs.active_tower = GS.build_default_tower()   # 5 floors
	gs._run_active = true
	gs._floor = 2
	gs._highest_floor = 2
	var advanced: Array = []
	gs.floor_advanced.connect(func(nf: int) -> void: advanced.append(nf))
	gs.advance_floor()
	failed += _expect(gs._floor == 3, "advance climbs to the next floor")
	failed += _expect(gs._highest_floor == 3, "highest floor tracks the climb")
	failed += _expect(advanced.size() == 1 and int(advanced[0]) == 3, "floor_advanced emitted")
	# Advancing past the last floor conquers (no floor_advanced; conquered flag set).
	var gs2: Node = GS.new()
	gs2.active_tower = GS.build_default_tower()
	gs2._run_active = true
	gs2._floor = 5
	gs2._highest_floor = 5
	var advanced2: Array = []
	gs2.floor_advanced.connect(func(nf: int) -> void: advanced2.append(nf))
	gs2.advance_floor()
	failed += _expect(gs2.tower_conquered == true, "clearing the last floor conquers the tower")
	failed += _expect(advanced2.is_empty(), "conquer does not emit floor_advanced")
	gs.free()
	gs2.free()
	return failed
```

> These tests DO call `_save_climber()` internally (via `fall`/`advance_floor`), which writes the real `user://climber.json`. That is acceptable in a dev/test environment — but to keep the maker's real save pristine, the tests run on bare instances that were never loaded from disk, and the written values are valid climber states. If you want zero touch of the real file, that is handled in Step 3's note. (The primary correctness gates are the pure functions; these transition tests assert the in-memory math.)

- [ ] **Step 2: Run to verify the new cases fail**

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_climb.gd`
Expected: FAIL — `fell` signal and `fall()` don't exist; `advance_floor` doesn't set `_highest_floor` / `tower_conquered`.

- [ ] **Step 3: Add the `fell` signal, rewire the transitions**

In `godot-project/scripts/GameState.gd`, add the signal with the others (after line 18's `returned_to_hub`):

```gdscript
signal fell(new_floor: int)                  # died on a floor -> dropped, staying in the tower
```

Replace `enter_run` (line 68) — resume from the saved floor, restore rank, drop the hard reset to 1:

```gdscript
func enter_run() -> void:
	if active_tower == null:
		active_tower = _load_or_build_tower()
	# Persistent climb: a conquered tower re-climbs fresh; otherwise resume from
	# the saved floor. NEVER a blanket reset to 1.
	if tower_conquered:
		_floor = 1
		tower_conquered = false
	_floor = clampi(_floor, 1, total_floors())
	_highest_floor = maxi(_highest_floor, _floor)
	_restore_rank_power()
	_kills = 0
	_boss_killed = false
	_elements_used = {}
	_run_active = true
	mode = Mode.RUN
	run_started.emit()
	_change_scene(ARENA_SCENE)
```

Replace `advance_floor` (line 100) — bank + save + conquer:

```gdscript
func advance_floor() -> void:
	if not _run_active:
		return
	if _floor >= total_floors():
		_boss_killed = true               # cleared the guardian floor
		tower_conquered = true
		_highest_floor = maxi(_highest_floor, total_floors())
		_save_climber()
		end_run(false)
		return
	_floor += 1
	_highest_floor = maxi(_highest_floor, _floor)
	_save_climber()
	floor_advanced.emit(_floor)
```

Add `fall()` and `return_to_hub()` just after `advance_floor`:

```gdscript
## Failing a floor: drop 2 floors, stay in the tower, keep everything. Ticks the
## falls counter and emits `fell` — the Arena rebuilds the dropped floor in place
## and revives the hero. No scene change, no hub trip.
func fall() -> void:
	if not _run_active:
		return                            # sandbox death: Hero handles the local reset
	_falls += 1
	_floor = fall_floor(_floor)
	_save_climber()
	fell.emit(_floor)


## Deliberate hub return from a cleared floor. Banks the cleared floor (resume
## continues the climb, no refight), then bounces to the hub with a "walked out
## alive" outcome the NPCs ingest.
func return_to_hub() -> void:
	if not _run_active:
		return
	if _floor < total_floors():
		_floor += 1
		_highest_floor = maxi(_highest_floor, _floor)
	_save_climber()
	end_run(false)
```

Modify `end_run` (line 113) to record `falls` in the outcome (change only the `build_outcome` call):

```gdscript
	last_run = build_outcome(
		_floor, _kills, _boss_killed, died,
		_elements_used.keys(), _rank_tier(), _rank_title(), _falls
	)
```

> Note on conquer + resume: after a conquer the disk holds `tower_conquered=true` and `current_floor=total`. On the next `enter_run`, `tower_conquered` flips it to a fresh floor-1 climb (highest_floor + rank persist as bragging rights). This is intentional per the design ("entering the tower resumes … or re-climbs after conquering").

- [ ] **Step 4: Run the tests — all pass**

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --import`
Then: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_climb.gd`
Expected: `Climb spine tests: all PASS`.

Also run the existing runloop suite to confirm no regression (the `build_outcome`/fact changes are backward compatible):

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice2_test_runloop.gd`
Expected: `Slice2 runloop tests: all PASS`.

- [ ] **Step 5: Commit**

```bash
git add godot-project/scripts/GameState.gd godot-project/tools/slice_test_climb.gd
git commit -m "climb: resume on enter, fall (drop-2-stay), return-to-hub, conquer + rank restore"
```

---

### Task 4: Hero death → fall (drop-2-stay instead of die→hub)

The one-line behaviour flip that makes death a fall.

**Files:**
- Modify: `godot-project/scripts/combat/Hero.gd:1802-1809`

**Interfaces:**
- Consumes (from Task 3): `GameState.fall()`

- [ ] **Step 1: Change `_die` to call `fall()`**

In `godot-project/scripts/combat/Hero.gd`, replace `_die` (lines 1802-1811):

```gdscript
func _die() -> void:
	# In a run: a death is a FALL — drop 2 floors but stay in the tower (GameState
	# ticks the fall counter + saves; the Arena rebuilds the dropped floor in place
	# and revives us). In the standalone sandbox: just reset to full so the feel
	# loop never stops.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.fall()
		return
	hp = max_hp
	health_changed.emit(hp, max_hp)
```

- [ ] **Step 2: Headless import + boot-clean check**

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --import`
Expected: clean import, no parse errors on `Hero.gd`.

> This change has no headless unit test (death → fall is an integration behaviour exercised in Task 6's playtest). The gate here is: parse-clean + the `gs.fall()` symbol resolves (it exists from Task 3).

- [ ] **Step 3: Commit**

```bash
git add godot-project/scripts/combat/Hero.gd
git commit -m "climb: hero death is now a FALL (drop-2-stay) in a run"
```

---

### Task 5: Arena — fell handler (revive + rebuild) + return-to-town portal

Wire the `fell` signal to rebuild the dropped floor in place and revive the hero, and spawn a second "RETURN TO TOWN" portal on non-final cleared floors.

**Files:**
- Modify: `godot-project/scripts/combat/Arena.gd`

**Interfaces:**
- Consumes (from Task 3): `GameState.fell` signal, `GameState.return_to_hub()`, `GameState.current_floor()`, `GameState.total_floors()`
- Consumes existing: `ExitPortal` (`portal_label`, `ring_color`, `trigger_group` — set BEFORE `add_child`, since `_ready` reads them)

- [ ] **Step 1: Add the return-portal field + colour const**

In `godot-project/scripts/combat/Arena.gd`, add near the other portal state (after line 22's `var _portal`):

```gdscript
var _return_portal: ExitPortal = null
const RETURN_PORTAL_COLOR: Color = Color(1.0, 0.85, 0.4)   # warm gold vs the cyan climb-exit
```

- [ ] **Step 2: Connect the `fell` signal**

In `_ready`, inside the `if _run_mode:` block, after the `floor_advanced` connect (line 52-53), add:

```gdscript
		if not _gs.fell.is_connected(_on_fell):
			_gs.fell.connect(_on_fell)
```

- [ ] **Step 3: Add the `fell` handler + hero revive + enemy clear**

Add these functions after `_on_floor_advanced` (line 118-119):

```gdscript
## A fall landed us on an earlier floor: clear the current fight, rebuild the
## dropped floor, and revive the hero. Reuses the same floor-rebuild path as a
## normal climb — the only difference is we may have live enemies to clear.
func _on_fell(new_floor: int) -> void:
	_clear_portal()
	_clear_enemies()
	_setup_floor(new_floor)   # sets _current_floor_def to the dropped floor, respawns the fight
	_revive_hero()            # after _setup_floor so hero_start reflects the new floor


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()


## Full-heal + reposition the hero to the (new) floor's start. MVP revive: HP +
## position. The active-ragdoll rig self-recovers from the death flinch.
func _revive_hero() -> void:
	var heroes: Array[Node] = get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		return
	var hero: Node2D = heroes[0] as Node2D
	if hero == null:
		return
	var full: int = int(hero.get("max_hp"))
	hero.set("hp", full)
	if hero.has_signal("health_changed"):
		hero.emit_signal("health_changed", full, full)
	var start: Vector2 = Vector2(600, 340)
	if _current_floor_def != null and _current_floor_def.layout != null:
		start = _current_floor_def.layout.hero_start
	hero.global_position = start
```

- [ ] **Step 4: Spawn the return portal on non-final cleared floors**

Replace `_on_floor_cleared` (lines 99-108):

```gdscript
func _on_floor_cleared() -> void:
	if not _run_mode:
		return
	var layout: LayoutDef = _current_floor_def.layout
	var exit_pt: Vector2 = DEFAULT_EXIT_POINT
	if layout != null:
		exit_pt = layout.exit_point
	_portal = EXIT_PORTAL_SCRIPT.new() as ExitPortal
	add_child(_portal)
	_portal.global_position = exit_pt
	_portal.taken.connect(_on_portal_taken)
	# A deliberate hub-return portal appears alongside the climb-exit on every
	# non-final floor. Clearing the BOSS floor is the conquer (the climb-exit's
	# advance path handles it), so no return portal there.
	if _gs.current_floor() < _gs.total_floors():
		var return_pt: Vector2 = Vector2(exit_pt.x, 520.0)
		if layout != null:
			return_pt = Vector2(layout.hero_start.x, layout.room_size.y - 120.0)
		_return_portal = EXIT_PORTAL_SCRIPT.new() as ExitPortal
		_return_portal.portal_label = "RETURN TO TOWN"
		_return_portal.ring_color = RETURN_PORTAL_COLOR
		_return_portal.trigger_group = "hero"
		add_child(_return_portal)
		_return_portal.global_position = return_pt
		_return_portal.taken.connect(_on_return_taken)


func _on_return_taken() -> void:
	_clear_portal()
	_gs.return_to_hub()
```

- [ ] **Step 5: Clear both portals in `_clear_portal`**

Replace `_clear_portal` (lines 122-127):

```gdscript
func _clear_portal() -> void:
	if is_instance_valid(_portal):
		if _portal.taken.is_connected(_on_portal_taken):
			_portal.taken.disconnect(_on_portal_taken)
		_portal.queue_free()
	_portal = null
	if is_instance_valid(_return_portal):
		if _return_portal.taken.is_connected(_on_return_taken):
			_return_portal.taken.disconnect(_on_return_taken)
		_return_portal.queue_free()
	_return_portal = null
```

- [ ] **Step 6: Headless import + boot-clean**

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --import`
Expected: clean import, no parse errors on `Arena.gd`.

- [ ] **Step 7: Commit**

```bash
git add godot-project/scripts/combat/Arena.gd
git commit -m "climb: Arena fell-handler (revive + rebuild in place) + return-to-town portal"
```

---

### Task 6: Full sweep + boot-clean + maker playtest checklist

Verify nothing regressed, the game boots clean, and hand the maker a deterministic feel/playtest checklist (the parts headless can't judge).

**Files:**
- Create: `godot-project/../docs/v2.0-climb-checklist.md`

- [ ] **Step 1: Run the full headless test sweep**

Run each and confirm the PASS line:

```bash
GODOT=godot-engine/Godot_v4.6.2-stable_win64_console.exe
$GODOT --headless --path godot-project --import
$GODOT --headless --path godot-project --script tools/slice_test_climb.gd
$GODOT --headless --path godot-project --script tools/slice2_test_runloop.gd
$GODOT --headless --path godot-project --script tools/slice2_test_enemy_archetypes.gd
$GODOT --headless --path godot-project --script tools/slice_test_floor.gd
```
Expected: every suite prints `... all PASS` and exits 0. (Run the rest of the `tools/slice*_test_*.gd` sweep too if quick — the climb change only touches GameState/Hero/Arena, so the combat suites should be untouched.)

- [ ] **Step 2: Boot the full loop clean (headless, no window)**

Run: `godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project scenes/Main.tscn --quit-after 120`
Expected: boots to the hub, no script errors in the output. (Hub NPCs will warn about Ollama if it's not running — that is not a climb-spine failure.)

- [ ] **Step 3: Write the maker playtest checklist**

Create `docs/v2.0-climb-checklist.md`:

```markdown
# v2.0 Persistent-Climb Spine — Maker Playtest Checklist

Prereqs: Ollama running with `llama3.2:3b` (for hub NPC dialogue). Boot with **F5** (`Main.tscn`).
The climber save lives at `%APPDATA%\Godot\app_userdata\Legacy Frontier\climber.json`.
To reset the climb: delete that file.

## A. Resume
- [ ] Enter the tower (hub portal). First-ever entry starts on **Floor 1 / 5**.
- [ ] Clear floor 1, take the cyan **EXIT** portal → banner reads **Floor 2 / 5**.
- [ ] Quit (X) mid-climb, relaunch, re-enter the tower → you **resume on the floor you'd reached**, not floor 1.

## B. Fall (die = drop 2, stay in the tower)
- [ ] On floor 3+, let the hero die. You should **NOT** return to the hub.
- [ ] The floor rebuilds at **current − 2** (floor 3 → floor 1; floor 5 → floor 3), hero **full HP**, repositioned to the start.
- [ ] Falls accumulate: die again → the drop-2 repeats. (`climber.json` `falls` ticks up.)
- [ ] Feel check: does the in-place respawn read clearly? Any lingering death-ragdoll weirdness on revive? (MVP revive = HP + reposition; flag if the rig looks stuck.)

## C. Return to town
- [ ] Clear any non-boss floor → **two** portals appear: cyan **EXIT** (climb) + gold **RETURN TO TOWN**.
- [ ] Take RETURN → back in the hub. Re-enter → you resume on the **next** floor (banked, no refight).
- [ ] The boss floor (5) shows **only** the EXIT portal (clearing it conquers).

## D. Town clocks the climb
- [ ] After a fall, return to town and talk to Raebai/Mirelle → the greeting **references the fall** (and the fall count after repeat falls).
- [ ] After a clean return, the NPCs reference the floor you reached.
- [ ] After conquering (clear floor 5), the NPCs react to felling the guardian.

## E. Persistence of rank
- [ ] Grind kills to raise the rank title, quit, relaunch, re-enter → the **rank title/tier persists** (no reset to Nameless).

## F. Conquer + re-climb
- [ ] Clear floor 5 → return to hub with a victory beat.
- [ ] Re-enter → a **fresh floor-1 climb** (rank + highest-floor bragging rights persist).

## Known MVP scope (not failures)
- Revive resets HP + position only (cooldowns/ailments/ragdoll not force-cleared).
- No fall-through animation (instant rebuild); can be added later behind the `fell` seam.
- No REST-floor economy, no PvP, no bespoke boss room yet (reserved seams).
```

- [ ] **Step 4: Commit**

```bash
git add docs/v2.0-climb-checklist.md
git commit -m "docs: v2.0 persistent-climb playtest checklist + full headless sweep green"
```

- [ ] **Step 5: Update the live ledger**

Append a session entry to `.superpowers/sdd/progress.md` (top STATUS block) noting: floors **step 5 (persistent-climb spine) SHIPPED** — climber state to disk (`user://climber.json`), resume-on-enter, death = drop-2-stay-in-tower, return-to-town portal, rank persists, town clocks falls. Headless-verified; **UNPLAYTESTED for feel** (awaiting maker F5 per `docs/v2.0-climb-checklist.md`).

```bash
git add .superpowers/sdd/progress.md
git commit -m "ledger: floors step 5 persistent-climb spine shipped (headless-verified, unplaytested)"
```

---

## Self-Review

**Spec coverage** (against `docs/superpowers/specs/2026-07-10-the-climb-and-floors-design.md` §1 + build-order step 5):
- Persistent Climber, rank/highest-floor never reset → Task 2 (`_highest_floor`, rank_power persisted) + Task 3 (`_restore_rank_power`). ✓
- Failing a floor = drop 2, stay, keep everything, `falls` ticks → Task 3 `fall()` + Task 5 revive-in-place + Task 4 death→fall. ✓
- Town clocks you (floor + falls) via existing memory plumbing → Task 1 falls in outcome/fact/hint, reusing `ingest_run_fact`/`apply_run_to_hub_npcs` (unchanged). ✓
- Return to hub deliberately (portal on cleared floor) OR on conquering; entering resumes → Task 5 return portal + Task 3 `return_to_hub`/`enter_run` resume + conquer. ✓
- Invariant preserved (§5): `enter_run → Arena._ready → build → clear → ExitPortal → advance_floor → floor_advanced → build`, plus `Hero._die`, plus F6 sandbox — all reused; new `fell` path mirrors the `floor_advanced` rebuild. ✓
- Out of scope (§4) untouched: no procedural gen, no room pool, no REST economy, no PvP. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases". Every code step shows full code. ✓

**Type consistency:** `fall_floor`, `build_climber_save`, `parse_climber_save`, `_save_climber(path=…)`, `_load_climber(path=…)`, `_live_rank_power`, `_restore_rank_power`, `fell(new_floor)`, `fall()`, `return_to_hub()`, `_on_fell`, `_revive_hero`, `_clear_enemies`, `_return_portal`, `RETURN_PORTAL_COLOR` — names used identically across the task that defines them and the tasks that consume them. `build_outcome`'s `falls` is the 8th positional param with a default, matching every call site (7-arg legacy + 8-arg in `end_run`). ✓
```
