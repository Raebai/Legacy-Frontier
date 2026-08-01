class_name FloorGen
extends RefCounted
## THE HAND NEVER DRAWS THE SAME ROOM TWICE.
##
## Five authored floors, each expressed differently every climb. This file takes a
## TowerDef whose floors carry their IDENTITY (type, depth, boss curve, difficulty
## band, wave shape) and re-draws their EXPRESSION (room proportion, ledges, cover,
## spawn geometry, pickups, wave rhythm, palette) from a seed.
##
## The lore does the design work: each floor is a fresh sheet of paper and an unseen
## hand draws the room live. A floor being different every time is DIEGETIC, so this
## does not have to hide its seams — a room that reads as "freshly drawn" is the
## point.
##
## ── WHAT NEVER MOVES ─────────────────────────────────────────────────────────
##   * `floor_type`, `depth`, `boss_hp_multiplier`, `brute_chance` — the floor's
##     identity and its place on the difficulty curve.
##   * `hp_multiplier` — 1.0, and this file NEVER WRITES IT. The spec is explicit:
##     "higher floors add modifiers, not HP". A generator that quietly multiplied
##     enemy HP would be the exact back door that rule exists to close, and
##     `tools/slice_test_floorgen.gd` fails the build if any generated floor or wave
##     carries an HP multiplier.
##   * The floor's TOTAL enemy budget, its wave COUNT, and the non-decreasing shape
##     of its wave budgets/caps. Two rolls of floor 3 are the same amount of fight.
##   * Which artist stands at the end (BossRoster does that roll, from the depth).
##
## ── WHAT IS REDRAWN ──────────────────────────────────────────────────────────
##   room proportion · the LEDGE SKYLINE (five archetypes, permanent + breakable) ·
##   cover count and placement · hero start + exit point · spawn rect and spacing ·
##   weapon pickups · per-wave budget distribution, concurrent cap, opening burst,
##   spawn interval · the archetype MIX (swapped WITHIN a threat class, so the band
##   holds) · the wash tint.
##
## ── CO-OP DETERMINISM IS THE HARD CONSTRAINT ─────────────────────────────────
## Both phones must draw the identical floor. Everything below is PURE: one
## RandomNumberGenerator seeded from (tower id, depth, climb seed), no `randi()`, no
## `randf()`, and NEVER `Array.shuffle()` — which draws from the engine's GLOBAL
## stream and would silently make this impure (the same trap BossRoster documents).
##
## `apply()` resolves the climb seed under a policy that CANNOT desync a party:
##   1. `FloorGen.climb_seed != 0`  -> use it. This is the hook for shipping the
##      host's seed to the party (see THE UPGRADE at the bottom of this block).
##   2. a live co-op session      -> seed 0, i.e. PINNED. Both peers derive the same
##      floor from (tower, depth) alone, with no networking at all. Less per-climb
##      variety than solo, and honest about it: a desynced party is a mystery bug,
##      a pinned floor is a known limitation.
##   3. otherwise (single player) -> a fresh roll, so every climb is a new tower.
##
## THE UPGRADE, when someone wants co-op to re-roll per climb too: the host already
## broadcasts `Net._enter_coop_run(floor)`. Widen it to `(floor, seed)` and have both
## sides set `FloorGen.climb_seed = seed` before the Arena builds. Nothing in this
## file changes — case 1 above already handles it.

## THE CLIMB SEED. 0 = "not told" (see the policy above). Set this from whatever
## owns the run spine; it is deliberately a plain static so a headless test, a
## capture tool and a future host broadcast can all drive it the same way.
static var climb_seed: int = 0
## The seed the last `apply()` actually used. Read by tooling so a roll can be
## replayed or reported; never read by gameplay.
static var last_seed: int = 0

## ONE SCREEN. The fit-all camera can pull back to CombatCamera.FRAME_VIEWPORT
## (640x360) / FRAME_ZOOM_MIN (0.5) minus FRAME_PAD (300, 220) => 980x500 of world.
## Hardcoded rather than loaded so this file drags no combat script into a headless
## harness's compile graph; `slice_test_floorgen` re-derives it from CombatCamera and
## fails if the two ever disagree.
const MAX_ROOM: Vector2 = Vector2(980.0, 500.0)
## ...and a floor is still an arena. A one-screen room that used half the screen
## would just be a smaller box, not a different room.
const MIN_ROOM: Vector2 = Vector2(820.0, 420.0)

## Arena.WALL_THICKNESS. The bottom wall is centred on y = room_h, so its top face —
## the ground everything stands on — is half a thickness above that.
const WALL_THICKNESS: float = 16.0

## ── THE MOVEMENT BUDGET, which is what makes a ledge a ledge ─────────────────
## Hero.JUMP_VELOCITY 580 against Hero.GRAVITY 1500 apexes at 580^2/(2*1500) = 112px,
## and MAX_AIR_JUMPS is 0 — wall-jumping is the only air move. So a step the hero can
## take COMFORTABLY (not frame-perfectly) is well under that.
##
## The enemy side has a DEAD ZONE that decides the band: Enemy's chase hop reaches
## ~90px and `LEAP_MIN_HEIGHT` is 105, so a rise between those two is a step NO enemy
## can follow you up — it would mill about below the ledge and the floor would read
## as broken. Every step is therefore cut to fit UNDER the hop, and height is gained
## by STACKING tiers: two 80px steps put the top ledge ~160px over the ground, which
## lands squarely inside the leap window (105-340) — so an enemy on the floor springs
## straight at a hero on the balcony. That is the leap system, finally with something
## to leap onto.
const STEP_MIN: float = 72.0
const STEP_MAX: float = 86.0
## Horizontal reach on a rising jump (~0.71s of airtime at SPEED 210 is ~149px), cut
## for safety. Flat/downward gaps are more generous — you cross those falling.
const GAP_UP_MAX: float = 110.0
const GAP_FLAT_MAX: float = 170.0
## THE GROUND CORRIDOR. No platform's underside may come within this of the ground,
## so the floor is always a clear wall-to-wall runway and no roll can box a player in.
## The hero's collider is 18x18, so this is two and a half bodies of headroom.
## It also sets a FLOOR under STEP_MIN: a first-tier ledge has to clear the corridor
## by its own thickness, i.e. rise >= GROUND_CORRIDOR + PLATFORM_H = 70.
const GROUND_CORRIDOR: float = 46.0
## Headroom above the topmost ledge, so its surface is somewhere you can stand.
const CEILING_CLEARANCE: float = 78.0
## Minimum CLEAR AIR between two ledges whose spans overlap.
##
## ⚠ THIS HAS TO STAY BELOW `STEP_MAX - PLATFORM_H`, or it fights the step budget and
## a stacked ledge becomes unrepresentable. The first cut asked for 66px of air
## between ledges whose centres are at most STEP_MAX (86) apart — leaving 62px once
## the 24px thickness is taken out — so every second storey this file tried to draw
## was rejected by its own rule, silently, and the "pillars"/"split"/"gallery" shapes
## all came out one tier tall.
const TIER_CLEARANCE: float = 40.0
## Keep the drawing off the player's face: nothing is placed this close to the spawn.
const HERO_CLEAR_X: float = 96.0

const PLATFORM_H: float = 24.0
const CRATE_HALF: float = 10.0          # DestructibleProp.CRATE_SIZE * 0.5
## How close to a wall a ledge's edge may sit. Wall thickness plus a little, so a
## ledge reads as attached to the wall rather than embedded in it.
const WALL_MARGIN: float = WALL_THICKNESS + 8.0
## Clear air required between two ledges on the same tier. Small: two perches 40px
## apart are a pair of perches, and the reachability walk decides whether the gap
## between them is crossable.
const SIDE_CLEARANCE: float = 12.0

## THE FIVE SHAPES A FLOOR CAN BE DRAWN AS. Named so a roll is legible in
## `special_tags` ("gen:gallery") and in a bug report.
const SHAPE_OPEN: String = "open"       # bare runway; the fight is the room
const SHAPE_STAIRS: String = "stairs"   # a rising staircase off one wall
const SHAPE_GALLERY: String = "gallery" # two wall balconies + a middle island
const SHAPE_PILLARS: String = "pillars" # scattered perches at one tier
const SHAPE_SPLIT: String = "split"     # a broken causeway across the middle

const SHAPES: Array[String] = [SHAPE_OPEN, SHAPE_STAIRS, SHAPE_GALLERY, SHAPE_PILLARS, SHAPE_SPLIT]

## Tags this file stamps onto a floor so a roll is visible + replayable. Stripped
## before re-stamping so applying twice cannot grow the array. BossRoster.parse_tags
## ignores anything it does not recognise, so these ride alongside "boss:" / "mod:"
## pins without disturbing them.
const TAG_SHAPE: String = "gen:"
const TAG_SEED: String = "genseed:"

## ── THE ARCHETYPE MIX: SWAP WITHIN A THREAT CLASS, NEVER ACROSS ──────────────
## This is the whole "differently interesting, not randomly harder" rule made
## mechanical. A wave authored as "chaser + brute + charger" may come back as
## "assassin + charger + brute" — the same three PRESSURES, drawn by a different
## hand — but it can never come back with a summoner it was not built to carry.
## (ids are Enemy.Archetype: 0 CHASER 1 BRUTE 2 CASTER 3 CHARGER
##                           4 SUMMONER 5 ASSASSIN 6 BOMBER 7 MAGE)
const CLASS_PRESSURE: Array[int] = [0, 5]    # chaser, assassin — bodies in your face
const CLASS_HEAVY: Array[int] = [1, 3]       # brute, charger — telegraphed commitment
const CLASS_RANGED: Array[int] = [2, 7]      # caster, mage — you cannot only look forward
const CLASS_ODD: Array[int] = [4, 6]         # summoner, bomber — threat multipliers

## Odds an authored archetype entry is redrawn as its classmate.
const SWAP_CHANCE: float = 0.45
## Odds a wave gains one extra entry, drawn from a class ALREADY in that wave.
const WIDEN_CHANCE: float = 0.30
## Odds a wave gets an explicit opening burst instead of the cap-derived default.
const VANGUARD_CHANCE: float = 0.35
## Odds a wave gets an explicit spawn interval.
const INTERVAL_CHANCE: float = 0.50


# ============================================================== the entry point
## Redraw every floor of `t` and hand back a NEW tower. The original is never
## mutated: `_load_or_build_tower` may hand us a CACHED `.tres` (ResourceLoader
## returns the same instance to every caller), and writing through that would
## corrupt the authored tower for the rest of the process and compound each climb.
##
## THE ONE-LINE WIRING lives in GameState._load_or_build_tower:
##     return FloorGen.apply(build_default_tower())
static func apply(t: TowerDef, seed_value: int = -1) -> TowerDef:
	if t == null:
		return t
	var s: int = seed_value if seed_value >= 0 else resolve_seed()
	last_seed = s
	return vary_tower(t, s)


## The climb seed, under the co-op policy documented at the top of this file.
static func resolve_seed() -> int:
	if climb_seed != 0:
		return climb_seed
	if _coop_active():
		return 0            # PINNED: both peers derive the same floor from depth alone
	return _fresh_seed()


## PURE. Same (tower, seed) -> the same tower, field for field, on every machine.
static func vary_tower(t: TowerDef, seed_value: int) -> TowerDef:
	if t == null:
		return t
	var out := TowerDef.new()
	out.id = t.id
	out.display_name = t.display_name
	out.theme = t.theme
	var floors: Array[FloorDef] = []
	for i: int in t.floors.size():
		var f: FloorDef = t.floors[i]
		if f == null:
			continue
		var depth: int = f.depth if f.depth > 0 else i + 1
		floors.append(vary_floor(f, depth, t.id, seed_value))
	out.floors = floors
	return out


## Redraw ONE floor. Returns a fresh FloorDef — the input is read, never written.
static func vary_floor(f: FloorDef, depth: int, tower_id: String, seed_value: int) -> FloorDef:
	var out: FloorDef = _clone_floor(f)
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed(tower_id, depth, seed_value)
	var shape: String = _roll_shape(rng, int(out.floor_type))
	out.layout = generate_layout(rng, shape, int(out.floor_type), depth)
	out.theme = _jitter_theme(rng, f.theme)
	out.waves = vary_waves(rng, f.waves)
	# Keep the flat legacy fields consistent with the redrawn waves, exactly as
	# GameState._make_floor does — anything still reading `enemy_budget` (including
	# Encounter's synthesized-wave fallback) must see the same floor.
	var total: int = 0
	var cap: int = 1
	for w: WaveDef in out.waves:
		total += maxi(w.enemy_budget, 0)
		cap = maxi(cap, w.concurrent_cap)
	if not out.waves.is_empty():
		out.enemy_budget = total
		out.concurrent_cap = cap
	out.special_tags = _stamp_tags(f.special_tags, shape, int(rng.seed))
	return out


## The per-floor seed. Mixed so two adjacent floors of the same climb land in
## unrelated parts of the stream rather than drawing near-identical rooms.
static func floor_seed(tower_id: String, depth: int, seed_value: int) -> int:
	return _mix(_mix(_str_hash(tower_id), maxi(depth, 1)), seed_value)


# ================================================================== the layout
## THE ROOM, drawn. Everything downstream (spawn rect, hero start, exit, cover,
## pickups) is derived from the geometry this produces, so the invariants below hold
## by CONSTRUCTION rather than by hoping the numbers happen to line up.
static func generate_layout(rng: RandomNumberGenerator, shape: String,
		floor_type: int, depth: int) -> LayoutDef:
	var l := LayoutDef.new()
	# --- proportion. A wide low hall and a tall narrow shaft are different fights.
	var wide: float = rng.randf()          # 0 = tall + narrow, 1 = wide + low
	var w: float = _snap(lerpf(MIN_ROOM.x, MAX_ROOM.x, wide), 10.0)
	var h: float = _snap(lerpf(MAX_ROOM.y, MIN_ROOM.y, wide * rng.randf_range(0.55, 1.0)), 10.0)
	w = clampf(w, MIN_ROOM.x, MAX_ROOM.x)
	h = clampf(h, MIN_ROOM.y, MAX_ROOM.y)
	l.room_size = Vector2(w, h)

	var ground_y: float = h - WALL_THICKNESS * 0.5

	# --- the hero stands on one side, so the room opens out in front of them.
	var left_start: bool = rng.randi_range(0, 1) == 0
	var hx: float = _snap(w * (rng.randf_range(0.14, 0.30) if left_start else rng.randf_range(0.70, 0.86)), 5.0)
	l.hero_start = Vector2(hx, ground_y - 40.0)

	# --- the skyline.
	var plats: Array[Dictionary] = _build_platforms(rng, shape, w, ground_y, floor_type, depth)
	l.platforms = plats

	# --- the standing surfaces, and which of them you can actually get to.
	var surfaces: Array[Dictionary] = _surfaces(plats, w, ground_y)
	var reach: Array[Dictionary] = reachable_surfaces(surfaces)

	# --- the exit. On a ledge when a verified step-chain leads to one (the floor is
	# then a small climb), otherwise on the ground on the far side. NEVER anywhere
	# the reachability walk below did not already reach.
	l.exit_point = _pick_exit(rng, reach, w, ground_y, hx, left_start)

	# --- spawn geometry, derived from the actual room rather than assumed.
	l.spawn_rect_min = Vector2(70.0, 70.0)
	l.spawn_rect_max = Vector2(w - 70.0, h - 70.0)
	l.min_spawn_dist_from_hero = _snap(rng.randf_range(150.0, 200.0), 5.0)

	# --- cover, resting on surfaces you can reach.
	l.crate_positions = _place_crates(rng, reach, floor_type, l.hero_start, l.exit_point)
	l.weapon_pickups = _place_pickups(rng, reach, floor_type, l.hero_start)
	return l


## Which shape the hand draws. A BOSS floor is always the open runway: the colossus
## needs the room, and its authored identity has always been a clean arena.
static func _roll_shape(rng: RandomNumberGenerator, floor_type: int) -> String:
	if floor_type == FloorDef.FloorType.BOSS:
		return SHAPE_OPEN
	return SHAPES[rng.randi_range(0, SHAPES.size() - 1)]


## The ledges. Every candidate is filtered through `_legal_platform` before it is
## kept, so a shape that would have produced an illegal ledge simply produces fewer —
## the room degrades to something emptier, never to something broken.
static func _build_platforms(rng: RandomNumberGenerator, shape: String, w: float,
		ground_y: float, floor_type: int, depth: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# The topmost surface a ledge may occupy. Everything else hangs off this.
	var top_limit: float = CEILING_CLEARANCE + PLATFORM_H * 0.5
	# ⚠ TIERS ARE CENTRES; STEPS ARE MEASURED BETWEEN SURFACES. A ledge's standing
	# surface is half its thickness ABOVE its centre, so the first tier has to be
	# lifted by that half-thickness or the step up from the ground is silently 12px
	# taller than asked for — which is how the first cut put most first-tier ledges
	# at a 90-98px rise, past what the hero's 112px jump comfortably clears, and had
	# the reachability pruner quietly delete four fifths of the tower's architecture.
	# Tier 2 and 3 are centre-to-centre offsets between equal-thickness ledges, so
	# there the offset IS the step.
	var t1: float = ground_y - rng.randf_range(STEP_MIN, STEP_MAX) + PLATFORM_H * 0.5
	var t2: float = t1 - rng.randf_range(STEP_MIN, STEP_MAX)
	var t3: float = t2 - rng.randf_range(STEP_MIN, STEP_MAX)

	# How much of the drawing is UNSTABLE. Deeper floors are drawn faster and looser,
	# so more of the architecture is the kind that shatters and re-forms. Floor 1
	# never breaks: the first room a player meets should stay where they left it.
	var break_chance: float = 0.0 if depth <= 1 else clampf(0.12 * float(depth - 1), 0.0, 0.5)
	if floor_type == FloorDef.FloorType.BOSS:
		break_chance = 0.0

	# ⚠ EVERY TIER ABOVE THE FIRST IS STACKED OVER SOMETHING, not floated next to it.
	# The first cut of this placed upper ledges by fraction-of-room-width and stranded
	# them on 80% of rolls: a second-tier ledge is ~150px over the floor, so the ONLY
	# way up is a step from a lower ledge, and two ledges 245px apart on x are 115px
	# of gap — five pixels past what a rising jump covers. The stack helper below
	# guarantees the x-overlap that makes the step legal. The prune pass at the end is
	# the safety net for anything that still slips through.
	match shape:
		SHAPE_OPEN:
			# One low island, sometimes. The boss floor usually gets nothing at all.
			if floor_type != FloorDef.FloorType.BOSS or rng.randf() < 0.5:
				_try_add(out, rng, w * rng.randf_range(0.38, 0.62), t1,
					rng.randf_range(150.0, 210.0), break_chance, ground_y, top_limit, w)
		SHAPE_STAIRS:
			# A staircase: each tread steps up AND along, and the run is short enough
			# that consecutive treads nearly touch.
			var dir: float = 1.0 if rng.randi_range(0, 1) == 0 else -1.0
			var base_x: float = w * (0.24 if dir > 0.0 else 0.76)
			var run: float = rng.randf_range(150.0, 190.0)
			for i: int in 3:
				var px: float = base_x + dir * run * float(i)
				var py: float = [t1, t2, t3][i]
				_try_add(out, rng, px, py, rng.randf_range(150.0, 190.0),
					break_chance, ground_y, top_limit, w)
		SHAPE_GALLERY:
			# Two wall balconies and a middle stage, all on ONE tier — the balconies
			# reach the stage across a flat gap (crossed while falling, so the budget
			# is the generous one), and the ground reaches all three straight up.
			# ⚠ THE INSET IS `WALL_MARGIN`, NOT A ROUND NUMBER. The first cut parked a
			# balcony's left edge at x=20, four pixels inside the wall margin, so BOTH
			# balconies were rejected on every single roll and a "gallery" came back
			# as one lonely slab.
			var bw: float = rng.randf_range(190.0, 250.0)
			_try_add(out, rng, WALL_MARGIN + bw * 0.5, t1, bw, break_chance, ground_y, top_limit, w)
			_try_add(out, rng, w - WALL_MARGIN - bw * 0.5, t1, bw, break_chance, ground_y, top_limit, w)
			var stage: int = _try_add(out, rng, w * 0.5, t1, rng.randf_range(170.0, 220.0),
				break_chance, ground_y, top_limit, w)
			# ...and sometimes a crow's nest directly over the stage.
			if stage >= 0 and rng.randf() < 0.55:
				_try_stack(out, rng, stage, rng.randf_range(STEP_MIN, STEP_MAX),
					rng.randf_range(110.0, 150.0), break_chance, ground_y, top_limit, w)
		SHAPE_PILLARS:
			# Perches, all within one step of the floor, staggered in height so the
			# skyline is ragged rather than a shelf. One of them may carry a second
			# storey, stacked directly on top of itself.
			#
			# ⚠ THE PERCHES ARE LAID OUT INSIDE THE USABLE SPAN, not across the whole
			# room. Placing them at `w * (i + 0.5) / n` put the outer two half-off the
			# wall on a narrow room and left the middle pair close enough to trip the
			# separation rule — a four-perch shape reliably produced one perch.
			var n: int = rng.randi_range(3, 4)
			var pill_w: float = rng.randf_range(110.0, 150.0)
			var usable: float = w - 2.0 * (WALL_MARGIN + pill_w * 0.5)
			# ...and if the room cannot separate that many perches, it draws fewer.
			while n > 2 and usable / float(n - 1) < pill_w + 40.0:
				n -= 1
			var raised: int = rng.randi_range(0, n - 1)
			for i: int in n:
				var px2: float = WALL_MARGIN + pill_w * 0.5 + usable * float(i) / float(maxi(n - 1, 1))
				px2 += rng.randf_range(-14.0, 14.0)
				# Same surface-vs-centre correction as t1 above.
				var py2: float = ground_y - rng.randf_range(STEP_MIN, STEP_MAX) + PLATFORM_H * 0.5
				var idx: int = _try_add(out, rng, px2, py2, pill_w,
					break_chance, ground_y, top_limit, w)
				if idx >= 0 and i == raised:
					_try_stack(out, rng, idx, rng.randf_range(STEP_MIN, STEP_MAX),
						rng.randf_range(100.0, 140.0), break_chance, ground_y, top_limit, w)
		SHAPE_SPLIT:
			# A broken causeway: two spans with a hole punched through the middle.
			var span: float = rng.randf_range(200.0, 260.0)
			var gap: float = rng.randf_range(70.0, GAP_FLAT_MAX - 20.0)
			var left: int = _try_add(out, rng, w * 0.5 - gap * 0.5 - span * 0.5, t1, span,
				break_chance, ground_y, top_limit, w)
			_try_add(out, rng, w * 0.5 + gap * 0.5 + span * 0.5, t1, span,
				break_chance, ground_y, top_limit, w)
			if left >= 0 and rng.randf() < 0.6:
				_try_stack(out, rng, left, rng.randf_range(STEP_MIN, STEP_MAX),
					rng.randf_range(130.0, 180.0), break_chance, ground_y, top_limit, w)
	return _prune_stranded(out, w, ground_y)


## Keep a candidate ledge only if it is legal against every geometry invariant.
## Returns its index in `out`, or -1 when it was rejected — callers stack on top of
## what actually landed rather than on what they hoped would.
static func _try_add(out: Array[Dictionary], rng: RandomNumberGenerator, cx: float,
		cy: float, pw: float, break_chance: float, ground_y: float,
		top_limit: float, room_w: float) -> int:
	var p: Dictionary = {
		"x": _snap(cx, 5.0), "y": _snap(cy, 5.0),
		"w": _snap(pw, 10.0), "h": PLATFORM_H,
		"breakable": rng.randf() < break_chance,
	}
	if not _legal_platform(p, out, ground_y, top_limit, room_w):
		return -1
	out.append(p)
	return out.size() - 1


## A second storey directly over ledge `base_idx`, offset sideways by less than half
## its width so the two spans always overlap — which is what makes the step up legal
## no matter how the widths rolled.
static func _try_stack(out: Array[Dictionary], rng: RandomNumberGenerator, base_idx: int,
		rise: float, pw: float, break_chance: float, ground_y: float,
		top_limit: float, room_w: float) -> int:
	if base_idx < 0 or base_idx >= out.size():
		return -1
	var base: Dictionary = out[base_idx]
	var shift: float = float(base["w"]) * rng.randf_range(-0.3, 0.3)
	return _try_add(out, rng, float(base["x"]) + shift, float(base["y"]) - rise,
		pw, break_chance, ground_y, top_limit, room_w)


## THE SAFETY NET. Drop any ledge the reachability walk cannot get to, repeatedly,
## until the skyline is a fixed point. A stranded ledge is not merely decoration —
## `Enemy`'s leap targets the HERO, so a hero standing somewhere no enemy can step to
## would beach the whole floor. The shapes above are built so this almost never
## fires; it exists so that "almost" is not load-bearing.
static func _prune_stranded(plats: Array[Dictionary], room_w: float,
		ground_y: float) -> Array[Dictionary]:
	var current: Array[Dictionary] = plats
	while true:
		var surfaces: Array[Dictionary] = _surfaces(current, room_w, ground_y)
		var reach: Array[int] = reachable_indices(surfaces)
		if reach.size() == surfaces.size():
			return current
		var keep: Array[Dictionary] = []
		for idx: int in reach:
			if idx > 0:            # index 0 is the ground, which is not a ledge
				keep.append(current[idx - 1])
		if keep.size() == current.size():
			return current      # nothing was actually dropped — do not spin
		current = keep
	return current              # unreachable; GDScript wants every path to return


## THE GEOMETRY INVARIANTS, in one place so the test can name them:
##   1. inside the walls, with a margin;
##   2. never wider than 55% of the room (no ledge cuts the room in two);
##   3. its underside stays clear of the GROUND CORRIDOR, so the floor is always a
##      wall-to-wall runway and no roll can seal a player in;
##   4. it sits below the ceiling clearance, so its surface is standable;
##   5. it does not overlap another ledge, and any ledge whose span overlaps it is
##      at least TIER_CLEARANCE away vertically (headroom between tiers).
static func _legal_platform(p: Dictionary, others: Array[Dictionary], ground_y: float,
		top_limit: float, room_w: float) -> bool:
	var px: float = float(p["x"])
	var py: float = float(p["y"])
	var pw: float = float(p["w"])
	var ph: float = float(p["h"])
	if pw > room_w * 0.55:
		return false
	if px - pw * 0.5 < WALL_MARGIN or px + pw * 0.5 > room_w - WALL_MARGIN:
		return false
	if py + ph * 0.5 > ground_y - GROUND_CORRIDOR:
		return false
	if py - ph * 0.5 < top_limit:
		return false
	for o: Dictionary in others:
		var ox: float = float(o["x"])
		var oy: float = float(o["y"])
		var ow: float = float(o["w"])
		var oh: float = float(o["h"])
		var x_overlap: bool = absf(px - ox) < (pw + ow) * 0.5 + SIDE_CLEARANCE
		if not x_overlap:
			continue
		if absf(py - oy) < TIER_CLEARANCE + (ph + oh) * 0.5:
			return false
	return true


## Every surface a body can stand on: the ground plus each ledge top.
## `{"y": surface_y, "x0": left, "x1": right, "ground": bool}`.
static func _surfaces(plats: Array[Dictionary], room_w: float, ground_y: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{
		"y": ground_y,
		"x0": WALL_THICKNESS,
		"x1": room_w - WALL_THICKNESS,
		"ground": true,
	}]
	for p: Dictionary in plats:
		out.append({
			"y": float(p["y"]) - float(p["h"]) * 0.5,
			"x0": float(p["x"]) - float(p["w"]) * 0.5,
			"x1": float(p["x"]) + float(p["w"]) * 0.5,
			"ground": false,
		})
	return out


## THE REACHABILITY WALK. A breadth-first flood from the ground over "can a hero get
## from this surface to that one in one jump", using the movement budget at the top
## of the file. Everything the room places — the exit, the pickups, the cover — is
## drawn ONLY from what comes back, which is how "no unwinnable roll" is guaranteed
## by construction instead of by inspection. Pure; the test walks it over hundreds
## of seeds and also re-derives it independently.
## ⚠ INDICES, NOT THE DICTIONARIES THEMSELVES. The first cut returned the surface
## dicts and the pruner matched them back by identity — which silently dropped almost
## every ledge and left the tower a bare box again, with the invariant suite still
## green because "every ledge is reachable" is trivially true of a floor with no
## ledges. Index 0 is always the ground, so ledge `k` is index `k + 1`.
static func reachable_indices(surfaces: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	if surfaces.is_empty():
		return out
	var seen: Dictionary = {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		out.append(i)
		for j: int in surfaces.size():
			if seen.has(j):
				continue
			if can_step(surfaces[i], surfaces[j]):
				seen[j] = true
				queue.append(j)
	return out


## The same walk, as surfaces. What the layout builder places things on.
static func reachable_surfaces(surfaces: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in reachable_indices(surfaces):
		out.append(surfaces[i])
	return out


## One jump, from surface `a` to surface `b`.
static func can_step(a: Dictionary, b: Dictionary) -> bool:
	var rise: float = float(a["y"]) - float(b["y"])     # positive => b is higher
	if rise > STEP_MAX:
		return false
	var gap: float = 0.0
	if float(b["x0"]) > float(a["x1"]):
		gap = float(b["x0"]) - float(a["x1"])
	elif float(a["x0"]) > float(b["x1"]):
		gap = float(a["x0"]) - float(b["x1"])
	return gap <= (GAP_UP_MAX if rise > 0.0 else GAP_FLAT_MAX)


## The exit, always somewhere the walk above already reached. Prefers a ledge — a
## floor that ends in a small climb reads better than one that ends in a walk — but
## only ever an ELIGIBLE ledge, and falls back to the ground otherwise.
static func _pick_exit(rng: RandomNumberGenerator, reach: Array[Dictionary], room_w: float,
		ground_y: float, hero_x: float, hero_left: bool) -> Vector2:
	var ledges: Array[Dictionary] = []
	for s: Dictionary in reach:
		if not bool(s["ground"]) and float(s["x1"]) - float(s["x0"]) >= 100.0:
			ledges.append(s)
	if not ledges.is_empty() and rng.randf() < 0.45:
		var pick: Dictionary = ledges[rng.randi_range(0, ledges.size() - 1)]
		var ex: float = _snap(lerpf(float(pick["x0"]) + 34.0, float(pick["x1"]) - 34.0, rng.randf()), 5.0)
		var cand := Vector2(ex, float(pick["y"]) - 38.0)
		# ...unless it landed in the player's lap. A floor whose exit is inside the
		# spawn is a floor you can finish by standing still.
		if cand.distance_to(Vector2(hero_x, ground_y - 40.0)) >= 200.0:
			return cand
	# Ground exit, on the far side from the hero so the room is crossed.
	var gx: float = room_w * (rng.randf_range(0.66, 0.86) if hero_left else rng.randf_range(0.14, 0.34))
	gx = clampf(gx, 60.0, room_w - 60.0)
	if absf(gx - hero_x) < 200.0:
		# Whichever wall is further away. MIN_ROOM.x is 820, so one of them is always
		# comfortably past the 200px separation.
		gx = 60.0 if hero_x > room_w * 0.5 else room_w - 60.0
	return Vector2(_snap(gx, 5.0), ground_y - 38.0)


## Cover, in clusters, RESTING ON SURFACES rather than floating. Floating cover is a
## stepping stone by accident, which would put geometry the reachability walk never
## considered into the middle of the room; a crate that sits on a ledge or on the
## floor is unambiguously cover.
static func _place_crates(rng: RandomNumberGenerator, reach: Array[Dictionary], floor_type: int,
		hero_start: Vector2, exit_point: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var want: int = _crate_budget(rng, floor_type)
	if want <= 0 or reach.is_empty():
		return out
	var guard: int = 0
	while out.size() < want and guard < want * 12:
		guard += 1
		var s: Dictionary = reach[rng.randi_range(0, reach.size() - 1)]
		var x0: float = float(s["x0"]) + 26.0
		var x1: float = float(s["x1"]) - 26.0
		if x1 <= x0:
			continue
		var cx: float = _snap(rng.randf_range(x0, x1), 5.0)
		var cy: float = float(s["y"]) - CRATE_HALF
		# Clusters of 1-3 read as a barricade someone stacked, not as confetti.
		var run: int = rng.randi_range(1, 3)
		for k: int in run:
			if out.size() >= want:
				break
			var px: float = cx + float(k) * 22.0
			if px > x1:
				break
			if absf(px - hero_start.x) < HERO_CLEAR_X and absf(cy - hero_start.y) < 120.0:
				continue
			if absf(px - exit_point.x) < 60.0 and absf(cy - exit_point.y) < 80.0:
				continue
			out.append(Vector2(px, cy))
	return out


## How much cover a floor type wants. ELITE stays open — the authored floor's note
## was "a more open room so the tankier fight has space" — and BOSS stays clean.
static func _crate_budget(rng: RandomNumberGenerator, floor_type: int) -> int:
	match floor_type:
		FloorDef.FloorType.BOSS:
			return 0
		FloorDef.FloorType.ELITE:
			return rng.randi_range(2, 5)
		FloorDef.FloorType.REST:
			return rng.randi_range(0, 3)
		_:
			return rng.randi_range(4, 8)


## The weapon pickup(s). Placed on a reachable surface and away from the spawn, so
## picking one up is a decision rather than something that happens to you.
static func _place_pickups(rng: RandomNumberGenerator, reach: Array[Dictionary],
		floor_type: int, hero_start: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if floor_type == FloorDef.FloorType.BOSS or reach.is_empty():
		return out
	var want: int = rng.randi_range(1, 2)
	var guard: int = 0
	while out.size() < want and guard < 24:
		guard += 1
		var s: Dictionary = reach[rng.randi_range(0, reach.size() - 1)]
		var x0: float = float(s["x0"]) + 40.0
		var x1: float = float(s["x1"]) - 40.0
		if x1 <= x0:
			continue
		var px: float = _snap(rng.randf_range(x0, x1), 5.0)
		if absf(px - hero_start.x) < HERO_CLEAR_X:
			continue
		out.append(Vector2(px, float(s["y"]) - 26.0))
	return out


# =================================================================== the waves
## Redraw the floor's fight WITHOUT changing how much fight it is. The total budget
## and the wave count survive exactly; what moves is the distribution across the
## waves, the pressure cap, the opening burst, the trickle rate and the MIX.
static func vary_waves(rng: RandomNumberGenerator, waves: Array[WaveDef]) -> Array[WaveDef]:
	var out: Array[WaveDef] = []
	if waves.is_empty():
		return out
	var n: int = waves.size()
	var budgets: Array[int] = []
	var caps: Array[int] = []
	for w: WaveDef in waves:
		budgets.append(maxi(w.enemy_budget, 1))
		caps.append(maxi(w.concurrent_cap, 2))
	budgets = _reshape(rng, budgets, 1)
	caps = _reshape(rng, caps, 2)
	for i: int in n:
		var src: WaveDef = waves[i]
		var w2 := WaveDef.new()
		w2.enemy_budget = budgets[i]
		w2.concurrent_cap = clampi(caps[i], 2, 8)
		w2.brute_chance = src.brute_chance
		# NEVER TOUCHED. -1 = inherit the floor's 1.0. See the header block.
		w2.hp_multiplier = -1.0
		w2.archetypes = _vary_roster(rng, src.archetypes)
		w2.vanguard = -1
		if rng.randf() < VANGUARD_CHANCE:
			w2.vanguard = clampi(w2.concurrent_cap, 2, w2.enemy_budget)
		w2.spawn_interval = -1.0
		if rng.randf() < INTERVAL_CHANCE:
			w2.spawn_interval = snappedf(rng.randf_range(0.26, 0.44), 0.01)
		# Left derived on purpose: the handoff threshold is the one wave knob that
		# can put dead air back into a floor, and dead air is the exact thing the
		# pacing pass removed. Rhythm varies through the burst and the trickle.
		w2.handoff_alive = src.handoff_alive
		out.append(w2)
	return out


## Jitter a non-decreasing series and hand back a non-decreasing series with the
## SAME SUM. Sorting after the jitter is what guarantees both: a floor authored as
## "12 bodies escalating" stays 12 bodies escalating, drawn differently.
static func _reshape(rng: RandomNumberGenerator, series: Array[int], floor_v: int) -> Array[int]:
	var out: Array[int] = series.duplicate()
	var n: int = out.size()
	if n < 2:
		return out
	for i: int in n - 1:
		var d: int = rng.randi_range(-1, 1)
		if out[i] - d >= floor_v and out[i + 1] + d >= floor_v:
			out[i] -= d
			out[i + 1] += d
	out.sort()
	return out


## The MIX. Each authored entry is either kept or redrawn as its classmate, and a
## wave may gain one extra body-type from a class it ALREADY carries. An empty
## roster (the floor's weighted roll over all eight) is left empty.
static func _vary_roster(rng: RandomNumberGenerator, roster: Array[int]) -> Array[int]:
	var out: Array[int] = []
	if roster.is_empty():
		return out
	for a: int in roster:
		var cls: Array[int] = threat_class(a)
		if cls.size() > 1 and rng.randf() < SWAP_CHANCE:
			out.append(cls[rng.randi_range(0, cls.size() - 1)])
		else:
			out.append(a)
	if rng.randf() < WIDEN_CHANCE:
		var pick: int = out[rng.randi_range(0, out.size() - 1)]
		var cls2: Array[int] = threat_class(pick)
		out.append(cls2[rng.randi_range(0, cls2.size() - 1)])
	return out


## Which threat class an archetype belongs to. The generator may only ever swap
## within the returned array — that rule is what keeps a re-rolled floor inside its
## authored difficulty band.
static func threat_class(archetype: int) -> Array[int]:
	if CLASS_PRESSURE.has(archetype):
		return CLASS_PRESSURE
	if CLASS_HEAVY.has(archetype):
		return CLASS_HEAVY
	if CLASS_RANGED.has(archetype):
		return CLASS_RANGED
	if CLASS_ODD.has(archetype):
		return CLASS_ODD
	return [archetype] as Array[int]


# ================================================================== internals
static func _clone_floor(f: FloorDef) -> FloorDef:
	var out := FloorDef.new()
	out.floor_type = f.floor_type
	out.enemy_budget = f.enemy_budget
	out.concurrent_cap = f.concurrent_cap
	out.brute_chance = f.brute_chance
	out.hp_multiplier = f.hp_multiplier      # copied, never computed
	out.wave_break = f.wave_break
	out.boss_scale = f.boss_scale
	out.boss_hp_multiplier = f.boss_hp_multiplier
	out.depth = f.depth
	out.theme = f.theme
	out.layout = f.layout
	out.waves = f.waves
	out.special_tags = f.special_tags
	return out


## A fresh wash tint inside the floor's band. The hand reaches for the same colour
## and gets a slightly different one; the layer still reads as surface / underground
## / sky, but no two climbs are the same shade of it.
static func _jitter_theme(rng: RandomNumberGenerator, src: EnvTheme) -> EnvTheme:
	var out := EnvTheme.new()
	out.name = src.name if src != null else "surface"
	var base: Color = src.wash_tint if src != null else Color(0.20, 0.28, 0.22)
	out.wash_tint = Color(
		clampf(base.r + rng.randf_range(-0.03, 0.03), 0.0, 1.0),
		clampf(base.g + rng.randf_range(-0.03, 0.03), 0.0, 1.0),
		clampf(base.b + rng.randf_range(-0.03, 0.03), 0.0, 1.0),
		base.a
	)
	return out


## Re-stamp the roll onto `special_tags`, preserving every authored pin and never
## growing the array when applied twice.
static func _stamp_tags(tags: Array[String], shape: String, used_seed: int) -> Array[String]:
	var out: Array[String] = []
	for t: String in tags:
		if t.begins_with(TAG_SHAPE) or t.begins_with(TAG_SEED):
			continue
		out.append(t)
	out.append(TAG_SHAPE + shape)
	out.append(TAG_SEED + str(used_seed))
	return out


## Is a co-op session live? Reached through the main loop's root rather than by
## naming the `Net` autoload: a bare autoload IDENTIFIER inside a STATIC function is
## a compile-time error that takes the whole dependency chain down with it, and
## reports as an unrelated missing method somewhere else entirely.
static func _coop_active() -> bool:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var r: Node = (loop as SceneTree).root
	if r == null:
		return false
	var net: Node = r.get_node_or_null(^"Net")
	if net == null or not net.has_method(&"is_active"):
		return false
	return bool(net.call(&"is_active"))


## A new climb seed. Never 0 — 0 is the "not told" sentinel.
static func _fresh_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return maxi(rng.randi() & 0x7FFFFFFF, 1)


## Deterministic string hash. NOT `String.hash()`: this has to produce the same
## number on every machine forever, and an engine-internal hash is not a contract.
static func _str_hash(s: String) -> int:
	var h: int = 2166136261
	for i: int in s.length():
		h = (h ^ s.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h


## The shared avalanche, public. `SpellDrops` salts its drop rolls with the climb
## seed and must mix it the SAME way this file does — one hash for the whole climb,
## so the room and the loot cannot end up derived from two different notions of
## "different enough".
static func mix_seed(a: int, b: int) -> int:
	return _mix(a, b)


## Cheap 32-bit avalanche, lifted verbatim from BossRoster._mix so the two seeded
## rolls in the tower behave identically. Masked at every step because GDScript ints
## are 64-bit and an unmasked multiply drifts away from the intended mixing.
static func _mix(a: int, b: int) -> int:
	var h: int = (a ^ (b * 0x9E3779B1)) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	h = (h * 0x7FEB352D) & 0xFFFFFFFF
	h = (h ^ (h >> 15)) & 0xFFFFFFFF
	h = (h * 0x846CA68B) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFFFFFF


static func _snap(v: float, step: float) -> float:
	return snappedf(v, step)
