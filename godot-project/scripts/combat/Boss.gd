class_name Boss
extends "res://scripts/combat/Enemy.gd"
## THE ASHSPIRE GUARDIAN — a giant procedural stone-and-ember colossus, the
## tower's floor-5 final boss. Three HP-gated phases, a top-screen boss bar, an
## intro beat, and telegraphed spectacle attacks (the existing spell kit
## retargeted at group "hero"). Extends Enemy so it reuses hp / take_damage /
## knockback / _die + the "enemy" group — Encounter's alive==0 clear gate ends
## the floor when the Guardian dies, with zero change to the gate.

signal phase_changed(phase: int)
signal defeated

enum BPhase { INTRO, P1, P2, P3, DEAD }

const RIG_HEIGHT: float = 95.0
const STONE_TINT: Color = Color(0.34, 0.33, 0.38)
const KNOCKBACK_RESIST: float = 0.14   # a colossus barely budges
const PHASE2_AT: float = 0.66
const PHASE3_AT: float = 0.33
const INTRO_TIME: float = 2.6
const ADD_CAP: int = 3
const PHASE_CD: Dictionary = {BPhase.P1: 2.4, BPhase.P2: 1.7, BPhase.P3: 1.1}

# ══ THE CEREMONY SCALES WITH THE FIGHT ═══════════════════════════════════════
## Every floor now ends on a guardian, and until this landed every one of them got
## the SAME arrival: a 2.6 s title card it cannot attack through, a camera pull, a
## full-width health bar and a name in 36 pt. The fun audit measured what that
## ceremony was actually introducing on floor 1 — a **6 to 13 second fight**. Two
## and a half seconds of posturing in front of six seconds of fighting is not an
## entrance, it is an apology.
##
## The fix is NOT to delete the entrance. A floor-1 guardian should still land as an
## event — it is the only thing on the floor that is not trash, and a mini-guardian
## that simply walks on is a reskinned brute. What it must not be is a twelve-second
## opera. So the ceremony has two settings, and which one you get is read off
## `body_scale`, which `Encounter` already sets pre-`_ready` from the floor type and
## already ships in the co-op spawn dictionary — so both phones agree with no new
## field, no new packet, and no caller changing.
##
##   FULL  (body_scale >= FULL_CEREMONY_SCALE): the floor-5 guardian and anything
##         else authored at near-full size. Byte-identical to what shipped.
##   BRIEF (below): a fast name flash, a short pull, a compact bar. The beats are
##         the same beats — you still get a name, a roar and a bar — at about a
##         third of the running time.
##
## The three PHASES are untouched in both. They were invisible on floors 1-4
## because the fight was over before the first gate; that is fixed on the HP side
## (`Encounter.boss_hp_fraction_for_type`), which is the honest place to fix it.
const FULL_CEREMONY_SCALE: float = 0.9
## A mini-guardian's intro. Long enough to read a name and see it wake; short
## enough that you are fighting before you have put the phone down.
const BRIEF_INTRO_TIME: float = 1.0

## BEAM TELEGRAPH (1.6). The beam used to be the one attack with no tell — a
## 1400 px/s bolt out of a still silhouette, which breaks the floor's own
## "every attack is dodgeable because you saw it coming" grammar. Now it lays a
## LANE along the snapshot aim first, exactly like the charger's dash lane, and
## fires when the lane expires. The aim is frozen at telegraph time, so walking
## out of the lane is the dodge.
const BEAM_WINDUP: float = 0.55
const BEAM_LANE_LENGTH: float = 900.0
const BEAM_LANE_WIDTH: float = 40.0
const BEAM_ACCENT: Color = Color(0.7, 0.4, 1.0, 1.0)

## Guardian size as a fraction of the full Ashen colossus. Encounter sets this
## pre-_ready from the floor's boss scale: 1.0 on a BOSS floor, smaller for the
## mini-guardian that now caps every other floor. Scales the rig + the crown, not
## the collision box (which stays a clean rectangle either way).
@export var body_scale: float = 1.0

var _bphase: int = BPhase.INTRO
var _attack_cd: float = 0.0
var _intro_timer: float = INTRO_TIME
var _busy: bool = false
var _adorn: BossAdornment = null
var _bar_layer: CanvasLayer = null
var _bar: BossBar = null
var _summoned: Array = []
## The one-shot "put my feet on the floor" flag — see `_stand_on_ground`.
var _ground_snap_pending: bool = true


## WHO THIS BOSS IS. Declared on the base rather than on `TowerBoss` so that
## `BossBar` and the intro card can ask ANY boss what it is called and what colour it
## writes itself in — including this one. Before this, the bar carried a
## `const NAME_TEXT = "THE ASHSPIRE GUARDIAN"` and the roster rewrote the label after
## construction; see `BossBar.setup` for why that was a trap rather than a default.
func boss_title() -> String:
	return "THE ASHSPIRE GUARDIAN"


func boss_accent() -> Color:
	return Color(1.0, 0.55, 0.2)


## THE EPITHET — the second line of the billing.
##
## A guardian is not "boss 3 of 4", it is a HAND: the thing that drew this floor,
## standing on it. The spec's own escalation rule is that skill, not statistics, is
## the ladder — "drawings that seem to be fighting the hand rather than you" is the
## ceiling — and an epithet is how a title tells you which rung you are on before
## the fight teaches you. `TowerBoss` renders it under the name card in the accent
## colour at a third of the size, which is a CAPTION, not a codex: one line, on
## screen for the length of the intro, never again.
func boss_epithet() -> String:
	return "charcoal colossus of the first page"


## Which artist's bark row this guardian speaks from. `Bark.say_variant` tries
## `<event>_<suffix>` and falls back to the generic row, so an unauthored suffix is
## silent-safe and a boss added tomorrow speaks the moment it exists.
func bark_suffix() -> String:
	return "guardian"


## ── THE REST OF THE IDENTITY, LIFTED OFF `TowerBoss` ─────────────────────────
## These five used to exist ONLY on `TowerBoss`, which meant the Ashen Guardian —
## the fallback boss, and the most frequently fought body in the tower — could not be
## asked what it looks like or how fast it swings. That was invisible until
## `slice_test_bossmods` was driven off `BossRoster.ids()` instead of a hand-listed
## three: the Guardian had quietly been left out of the one test that asks whether
## the roster's bosses are actually different fights.
##
## Same argument as `boss_title` above, one rung further: the questions the roster
## asks must be answerable by EVERY boss, or the answers only cover the ones that
## happened to be listed. The values below are the Guardian's own, moved rather than
## invented — `_ready` now reads them instead of the literals it used to carry, so
## there is exactly one statement of each.
func boss_artist() -> String:
	return "charcoal on stone"


func boss_rig_height() -> float:
	return RIG_HEIGHT


func boss_tint() -> Color:
	return STONE_TINT


func boss_preset() -> String:
	return "brawler"


## A guardian-king crown on the colossus. `TowerBoss` overrides this to nothing —
## the other artists wear their own mark instead.
func boss_equipment() -> Dictionary:
	return {"head": "crown"}


## Seconds between attacks in phase `p`. The Guardian's cadence IS `PHASE_CD`; a boss
## whose identity is rhythm overrides this. Declared here so the cadence question can
## be put to any boss on the roster.
## ⚠ DEPTH SQUEEZES EVERY ARTIST'S RHYTHM, IT DOES NOT REPLACE IT. Set from the
## floor by `Encounter` (1.0 on floor 1 and on every legacy spawn). Multiplying each
## boss's own `PHASE_CD` keeps the Illuminator a long fight and the Scribble a short
## violent one while making both of them press harder the deeper you are — where a
## flat depth cadence would have collapsed all six to the same fight played fast.
@export var cadence_mult: float = 1.0


func phase_cooldown(p: int) -> float:
	return float(PHASE_CD.get(p, 2.0))


## The gap actually used after an attack: this artist's authored rhythm, squeezed by
## depth.
##
## ⚠ APPLIED HERE AND NOT INSIDE `phase_cooldown`, WHICH WAS THE FIRST ATTEMPT AND
## WOULD HAVE BEEN DEAD CODE FOR FIVE OF SIX BOSSES. Every subclass — Cartographer,
## Eraser, Etcher, Illuminator, Scribble, and `TowerBoss` itself — OVERRIDES
## `phase_cooldown` with its own table and never calls `super`, so a multiply in the
## base would have reached the Guardian alone and silently missed the deep-floor
## roster the maker was actually complaining about. Every override still declares its
## own identity; the squeeze is applied once, at the one place the number is spent.
func next_attack_cd(p: int) -> float:
	return phase_cooldown(p) * clampf(cadence_mult, 0.3, 1.0)


func _ready() -> void:
	super._ready()   # hp, _hero, joins "enemy" + "mortal", tiny CharacterBars
	body_scale = clampf(body_scale, 0.3, 1.0)
	# ⚠ ORDER IS LOAD-BEARING: box, then rig, then feet, then hurtbox, then ground.
	# Every step below reads the result of the one above it — see _fit_box_to_scale.
	_fit_box_to_scale()
	if is_instance_valid(rig):
		rig.set("height", boss_rig_height() * body_scale)
		rig.set_tint(boss_tint())
		rig.class_preset(boss_preset())
		for slot: String in boss_equipment():
			rig.set_equipment(slot, String(boss_equipment()[slot]))
		rig.set_aura(Color(1.0, 0.45, 0.15), 0.45)   # subtle ember halo — the stone body must read
		rig.set_aura_tier(2)
		_realign_feet()
	refresh_hurtbox()   # the silhouette hitbox was cut for the pre-scale rig height
	_adorn = BossAdornment.new()
	add_child(_adorn)
	_adorn.configure(boss_rig_height() * body_scale)
	_adorn.set_intensity(0.35)
	_build_bar()
	_install_voice()
	_play_intro()


# ═══════════════════════════════════════════════════════════ THE GOD REGISTER
## A guardian must not sound like the trash it is standing over, and it must not
## sound like an elite either. Two things separate it, and neither costs an asset:
##
##   THE BAND. `Gibberish.voice()` spreads a seed over all six pitch bands, so an
##       unlucky roll gives the god of the floor the voice of a mosquito. A boss
##       pins the bottom slice (`BAND_BOSS`, 0.72–0.95) and takes its identity from
##       inside it — so the four artists still sound like four different people,
##       all of whom are LOW.
##   THE SEED. Off `boss_title()`, which is a virtual per CLASS. That is the one
##       identity that is guaranteed identical on every peer without a byte being
##       sent, and it means the Cartographer sounds like the Cartographer on every
##       floor of every climb, forever, with nothing stored.
##
## Set as metadata on the body rather than passed at each call site, so everything
## that already knows how to make a body talk — `Bark.say`, `VoiceDirector`'s death
## cry — picks it up without being told a boss is special.
const VOICE_DB: float = 3.0

func _install_voice() -> void:
	set_meta(Bark.SEED_META, Gibberish.seed_for(boss_title()))
	set_meta(Bark.BAND_META, Gibberish.BAND_BOSS)
	set_meta(Bark.DB_META, VOICE_DB)


# ═════════════════════════════════════════════════ THE FLOOR REDRAWS ITSELF
## SPEC, verbatim: *"the floor visibly redraws itself at boss phase transitions.
## Scripted, not simulated. More dramatic than emergent rubble, syncs trivially."*
##
## This is that. Breaking a phase does not just re-tint the guardian — the HAND
## takes the page back and draws over it while the guardian is still standing on
## it, in that guardian's own hand. It is the one moment in the game where the
## fiction (you are a drawing, someone is drawing this) becomes a mechanic you can
## see, and it is the difference between a boss with three HP gates and a god.
##
## ── WHY IT IS BUILT HERE AND NOT IN THE ARENA ────────────────────────────────
## The obvious home is the arena — it owns the floor. But a spectacle the GUARDIAN
## summons around itself is both better fiction (the hand answers the guardian, not
## the room) and better engineering: it needs no new owner, no new autoload, and it
## rides `_apply_phase`, which ALREADY runs on both peers (the host through
## `_enter_phase`, the client through `net_apply_phase` off `Net.broadcast_boss_phase`).
## That is the "syncs trivially" the spec promised — the redraw crosses the wire
## for free because the transition already does, and not one byte is added.
##
## ── WHY IT IS SCRIPTED AND CHEAP ─────────────────────────────────────────────
## No shader, no second full-screen pass, no simulation. It is ONE `_draw` on ONE
## Node2D: a wipe rect and a bounded list of strokes, generated once at birth from a
## deterministic RNG and then only revealed over time. The stroke budget halves at
## `graphics_quality = LOW` and the whole thing is shorter there, because a redraw
## that costs 40 ms is not epic, it is a stutter — the CPU budget is the top
## technical risk in this project and this beat is not allowed to be the thing that
## breaks it.
##
## ── EACH ARTIST REDRAWS IN ITS OWN HAND ──────────────────────────────────────
## `redraw_style()` is the seam. The Guardian hatches in charcoal; the Scribble
## scrawls over the page; the Cartographer rules new lines across it; the
## Illuminator gilds it. Same code, four hands.
func redraw_style() -> StringName:
	return &"hatch"


## Summon the redraw. Called from `_apply_phase` on EVERY peer — see above.
##
## ⚠ PARENTED TO THE GUARDIAN, NOT TO THE ARENA, WHICH IS A DELIBERATE DEVIATION
## from the house rule that spectacles hang off the arena. Two reasons, one of them
## paid for in a failing suite:
##   * fiction — the hand answers the GUARDIAN, and a page it summons around itself
##     should die with it rather than outlive the fight;
##   * hygiene — the arena's child list is walked by several suites (and by the
##     pooled-VFX recycler), and adding a short-lived self-freeing node to it made
##     `slice_test_bossnet` abort on a stale child. A spectacle that only exists for
##     one second has no business in a list other systems iterate.
## It is camera-anchored every frame, so being a child of a moving boss costs it
## nothing.
func _redraw_the_page(p: int) -> void:
	var host: Node = self
	if not is_inside_tree():
		return
	var page := PageRedraw.new()
	page.style = redraw_style()
	page.accent = boss_accent()
	page.phase = p
	# Deterministic per (artist, phase): both peers generate the same strokes from
	# the same seed, so the two screens are redrawn identically without syncing a
	# single stroke. Same reason the elite roll travels as ids rather than as bodies.
	page.gen_seed = Gibberish.seed_combine([Gibberish.seed_for(boss_title()), p])
	page.origin = global_position
	host.add_child(page)


## THE PAGE ITSELF. A short-lived Node2D that wipes the visible floor and draws it
## back in the guardian's hand.
##
## An INNER class on purpose: it has exactly one caller, it is presentation with no
## state anybody else can want, and a separate file in `scripts/combat/` would be a
## new owner for a thing that only ever belongs to a boss.
class PageRedraw extends Node2D:
	## Stroke ceiling at full quality, and the halved one that ships to a phone.
	const STROKES_HIGH: int = 26
	const STROKES_LOW: int = 10
	const LIFE_HIGH: float = 1.05
	const LIFE_LOW: float = 0.6
	## The wipe: a band of blank page travelling across the room ahead of the new
	## lines. Narrow and translucent — a WIPE, not a white blow-out, which is the
	## mark this codebase already decided erases the very thing a beat exists to show.
	const WIPE_FRAC: float = 0.26
	const WIPE_ALPHA: float = 0.26
	## Squeeze every stroke's reveal time toward the front of the life. Rendered
	## frames of the first cut showed the problem plainly: at a third of the way in,
	## four of the Cartographer's eight rules were on screen and it read as "some
	## lines appeared" rather than as a page being redrawn. Compressing the schedule
	## (rather than lengthening the beat, which costs frames on a phone) puts most of
	## the new page down while the wipe is still travelling, which is the whole read.
	const REVEAL_COMPRESS: float = 0.62
	## How long one stroke takes to grow to full length once it starts.
	const STROKE_GROW: float = 0.14
	## Over the arena, under the HUD and under the boss bar's CanvasLayer.
	const Z: int = 40

	var style: StringName = &"hatch"
	var accent: Color = Color.WHITE
	var phase: int = 2
	var gen_seed: int = 0
	var origin: Vector2 = Vector2.ZERO

	var _t: float = 0.0
	var _life: float = LIFE_HIGH
	var _half: Vector2 = Vector2(320.0, 180.0)
	## [{a, b, w, at, col}] — a is the start, b the end, `at` the fraction of the
	## life at which this stroke starts being drawn. Generated ONCE.
	var _strokes: Array = []
	## Filled blocks (the Illuminator's gold leaf). [{r: Rect2, at: float}]
	var _blocks: Array = []

	func _ready() -> void:
		z_index = Z
		z_as_relative = false
		# Keep drawing through the hit-stop the phase break itself causes — the
		# redraw IS the beat the hit-stop is punctuating.
		process_mode = Node.PROCESS_MODE_ALWAYS
		global_position = origin
		var low: bool = TuningConfig.quality_is_low()
		_life = LIFE_LOW if low else LIFE_HIGH
		_measure()
		_generate(STROKES_LOW if low else STROKES_HIGH)

	## Cover what the player can actually see. Falls back to the boss's own
	## neighbourhood when there is no camera (a headless harness, a capture tool
	## mid-setup) rather than drawing nothing, so the beat is testable.
	func _measure() -> void:
		var vp: Viewport = get_viewport()
		if vp == null:
			return
		var cam: Camera2D = vp.get_camera_2d()
		var size: Vector2 = vp.get_visible_rect().size
		if cam != null:
			global_position = cam.global_position
			size = size / maxf(cam.zoom.x, 0.05)
		_half = size * 0.5

	func _process(delta: float) -> void:
		_t += delta
		# Track the camera: a floor being redrawn must stay under the player even if
		# they are running while it happens.
		var vp: Viewport = get_viewport()
		if vp != null:
			var cam: Camera2D = vp.get_camera_2d()
			if cam != null:
				global_position = cam.global_position
		if _t >= _life:
			queue_free()
			return
		queue_redraw()

	# ------------------------------------------------------------- generation
	## Every stroke decided up front, from a seeded RNG. Nothing here is random at
	## draw time, which is what makes two peers redraw the same page and what keeps
	## `_draw` down to a bounded list of `draw_line` calls.
	func _generate(budget: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = gen_seed
		var w: float = _half.x * 2.0
		var h: float = _half.y * 2.0
		var ink: Color = accent
		match style:
			&"scrawl":
				# THE SCRIBBLE. A child going over the same place four times.
				#
				# ⚠ TUNED OFF A RENDERED FRAME, NOT OFF REASONING. The first cut was
				# `budget` short three-segment runs scattered over the page, and the
				# capture showed exactly what that is: confetti. A scrawl is FEWER,
				# LONGER, OVERLAPPING runs that cross the room — so this makes half as
				# many, four segments each, up to nine tenths of the screen wide, and
				# thick enough to read as crayon. Same stroke count, completely
				# different picture.
				var runs: int = maxi(budget / 2, 3)
				for i in runs:
					var cx: float = rng.randf_range(-_half.x * 0.8, _half.x * 0.8)
					var cy: float = rng.randf_range(-_half.y * 0.8, _half.y * 0.8)
					var ang: float = rng.randf_range(-PI, PI)
					var len: float = rng.randf_range(w * 0.35, w * 0.9)
					var p0 := Vector2(cx, cy)
					for seg in 4:
						var jitter: float = rng.randf_range(-0.75, 0.75)
						var p1: Vector2 = p0 + Vector2.RIGHT.rotated(ang + jitter) * (len / 4.0)
						_strokes.append({"a": p0, "b": p1,
							"w": rng.randf_range(3.5, 6.5),
							"at": float(i) / float(runs) * 0.7,
							"col": ink})
						p0 = p1
			&"rule":
				# THE CARTOGRAPHER. Ruled straight, at even spacing, with tick marks —
				# the floor being re-surveyed underneath you.
				var rows: int = maxi(budget / 3, 2)
				for i in rows:
					var y: float = -_half.y + h * (float(i) + 0.5) / float(rows)
					_strokes.append({"a": Vector2(-_half.x, y), "b": Vector2(_half.x, y),
						"w": 1.6, "at": float(i) / float(rows) * 0.6, "col": ink})
					# ticks along it
					var ticks: int = 6
					for k in ticks:
						var x: float = -_half.x + w * (float(k) + 0.5) / float(ticks)
						_strokes.append({"a": Vector2(x, y - 7.0), "b": Vector2(x, y + 7.0),
							"w": 1.2, "at": float(i) / float(rows) * 0.6 + 0.06, "col": ink})
				# ...and one struck arc, the compass signature, approximated as a fan
				# of chords so `_draw` stays a list of lines.
				var r: float = minf(_half.x, _half.y) * 0.72
				var steps: int = 18
				for k2 in steps:
					var a0: float = PI * (float(k2) / float(steps))
					var a1: float = PI * (float(k2 + 1) / float(steps))
					_strokes.append({
						"a": Vector2(cos(a0), sin(a0)) * r,
						"b": Vector2(cos(a1), sin(a1)) * r,
						"w": 2.0, "at": 0.45 + 0.3 * float(k2) / float(steps), "col": ink})
			&"gild":
				# THE ILLUMINATOR. Long rules, blocks of leaf, and hairlines radiating
				# out of the guardian — a page being illuminated while you stand on it.
				var lines: int = maxi(budget / 2, 3)
				for i2 in lines:
					var y2: float = -_half.y + h * (float(i2) + 0.5) / float(lines)
					_strokes.append({"a": Vector2(-_half.x, y2), "b": Vector2(_half.x, y2),
						"w": 2.2, "at": float(i2) / float(lines) * 0.5, "col": ink})
				for k3 in mini(budget, 14):
					var ang2: float = TAU * float(k3) / float(mini(budget, 14))
					var rr: float = minf(_half.x, _half.y)
					_strokes.append({
						"a": Vector2.RIGHT.rotated(ang2) * (rr * 0.20),
						"b": Vector2.RIGHT.rotated(ang2) * (rr * 0.95),
						"w": 1.2, "at": 0.35 + 0.35 * float(k3) / 14.0, "col": ink})
				# The leaf itself. Skipped entirely at LOW — filled rects are the one
				# thing here with real fill cost, and the rules alone still read.
				if budget >= STROKES_HIGH:
					for b in 4:
						var bw: float = rng.randf_range(w * 0.06, w * 0.13)
						_blocks.append({"r": Rect2(
							rng.randf_range(-_half.x, _half.x - bw),
							rng.randf_range(-_half.y, _half.y - bw),
							bw, bw), "at": 0.5 + 0.1 * float(b)})
			&"erase":
				# THE ERASER. It does not redraw the page — it takes strokes OFF it. So
				# this hand is the inverse of every other one: short horizontal scrubs in
				# the pale of BLANK PAPER rather than in ink, laid in overlapping passes
				# the way a rubber is actually worked, each leaving the room emptier
				# instead of fuller. One crumb in the accent at the end of every scrub.
				var scrubs: int = maxi(budget / 2, 4)
				var blank: Color = Color(1.0, 0.98, 0.95, 0.85)
				for i4 in scrubs:
					var sx: float = rng.randf_range(-_half.x * 0.85, _half.x * 0.85)
					var sy: float = rng.randf_range(-_half.y * 0.85, _half.y * 0.85)
					var span: float = rng.randf_range(w * 0.10, w * 0.22)
					var at4: float = float(i4) / float(scrubs) * 0.7
					# Three passes over the same place, each shorter. A rubber does not
					# do it in one stroke and neither does this.
					for pass_i in 3:
						var shrink: float = 1.0 - 0.18 * float(pass_i)
						var off: float = float(pass_i - 1) * 5.0
						_strokes.append({
							"a": Vector2(sx - span * 0.5 * shrink, sy + off),
							"b": Vector2(sx + span * 0.5 * shrink, sy + off),
							"w": rng.randf_range(5.0, 8.5),
							"at": at4 + 0.04 * float(pass_i), "col": blank})
					_strokes.append({
						"a": Vector2(sx + span * 0.5, sy + 2.0),
						"b": Vector2(sx + span * 0.5 + 6.0, sy + 4.0),
						"w": 2.4, "at": at4 + 0.12, "col": ink})
			&"etch":
				# THE ETCHER. Not drawn — BITTEN, in two events that have to read as two.
				# First the needle: fine parallel work in tight bands, the hatching an
				# etcher actually cuts. Then the acid, arriving later and eating further
				# than the needle went — long ragged diagonals crossing the bands.
				var bands: int = maxi(budget / 6, 2)
				for b2 in bands:
					var by: float = -_half.y + h * (float(b2) + 0.5) / float(bands)
					var bx: float = rng.randf_range(-_half.x * 0.6, _half.x * 0.2)
					var bw2: float = rng.randf_range(w * 0.18, w * 0.34)
					for n2 in 7:
						var lx: float = bx + bw2 * (float(n2) / 6.0)
						_strokes.append({
							"a": Vector2(lx, by - 16.0), "b": Vector2(lx + 6.0, by + 16.0),
							"w": 1.1,
							"at": float(b2) / float(bands) * 0.45 + 0.05 * (float(n2) / 7.0),
							"col": ink})
				var bites: int = maxi(budget / 5, 3)
				for c in bites:
					var pb := Vector2(rng.randf_range(-_half.x, _half.x * 0.5),
						rng.randf_range(-_half.y, _half.y * 0.5))
					var ang3: float = rng.randf_range(0.35, 0.95)
					for seg2 in 3:
						var pb2: Vector2 = pb + Vector2.RIGHT.rotated(
							ang3 + rng.randf_range(-0.3, 0.3)) * rng.randf_range(w * 0.10, w * 0.20)
						_strokes.append({"a": pb, "b": pb2,
							"w": rng.randf_range(2.6, 4.4),
							"at": 0.5 + 0.35 * float(c) / float(bites), "col": ink})
						pb = pb2
			_:
				# CHARCOAL. The first hand: dense diagonal hatching, pressed hard.
				for i3 in budget:
					var t: float = float(i3) / float(maxi(budget - 1, 1))
					var x0: float = lerpf(-_half.x * 1.4, _half.x, t)
					_strokes.append({
						"a": Vector2(x0, -_half.y),
						"b": Vector2(x0 + _half.x * 0.55, _half.y),
						"w": rng.randf_range(1.8, 3.4), "at": t * 0.65, "col": ink})

	# ------------------------------------------------------------------- draw
	func _draw() -> void:
		var k: float = clampf(_t / maxf(_life, 0.001), 0.0, 1.0)
		# Everything fades out over the last fifth, so the page is clean again and the
		# fight is never left reading through a lattice of leftover ink.
		var fade: float = 1.0 if k < 0.8 else (1.0 - (k - 0.8) / 0.2)

		# 1 · THE WIPE. A band of blank page travelling left to right, ahead of the
		#     new lines. It is what makes this read as "erased and redrawn" rather
		#     than "some lines appeared".
		var band: float = _half.x * 2.0 * WIPE_FRAC
		var lead: float = lerpf(-_half.x - band, _half.x + band, minf(k / 0.55, 1.0))
		if k < 0.70:
			draw_rect(Rect2(lead - band, -_half.y, band, _half.y * 2.0),
				Color(1.0, 0.98, 0.94, WIPE_ALPHA * fade), true)
			# The edge the hand is working at, and the softer one it has left behind.
			# Two lines rather than one because a single edge reads as a wall; a pair
			# reads as a band that is TRAVELLING.
			draw_line(Vector2(lead, -_half.y), Vector2(lead, _half.y),
				Color(accent.r, accent.g, accent.b, 0.9 * fade), 3.0)
			draw_line(Vector2(lead - band, -_half.y), Vector2(lead - band, _half.y),
				Color(accent.r, accent.g, accent.b, 0.35 * fade), 1.5)

		# 2 · THE NEW LINES, revealed behind the wipe. Each stroke grows from its own
		#     start time, so the page is drawn rather than switched on.
		for s: Dictionary in _strokes:
			var at: float = float(s["at"]) * REVEAL_COMPRESS
			if k < at:
				continue
			var grow: float = clampf((k - at) / STROKE_GROW, 0.0, 1.0)
			var a: Vector2 = s["a"]
			var b: Vector2 = a.lerp(s["b"], grow)
			var col: Color = s["col"]
			draw_line(a, b, Color(col.r, col.g, col.b, fade), float(s["w"]))

		# 3 · Gold leaf, if this hand uses any.
		for bl: Dictionary in _blocks:
			if k < float(bl["at"]) * REVEAL_COMPRESS:
				continue
			draw_rect(bl["r"] as Rect2,
				Color(accent.r, accent.g, accent.b, 0.35 * fade), true)


# ------------------------------------------------------------------ boss brain
func _physics_process(delta: float) -> void:
	# Co-op: the guardian is host-authoritative — a client puppet only animates from
	# the synced transform/hp (no phases, no attacks, no move_and_slide) on its side.
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		_remote_enemy_visual(delta)
		return
	# ONCE, on the first physics frame: put the feet on the floor before gravity or
	# the intro get a say. See _stand_on_ground for why it is not in `_ready`.
	if _ground_snap_pending:
		_ground_snap_pending = false
		_stand_on_ground()
	_touch_cooldown = max(_touch_cooldown - delta, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_apply_gravity(delta)
	var approach: float = 0.0
	if not _busy and _bphase != BPhase.INTRO and is_instance_valid(_hero):
		approach = signf(_hero.global_position.x - global_position.x) * move_speed
	velocity.x = _knockback.x + approach
	# ══ THE BOSS CAN LEAVE THE GROUND NOW ═══════════════════════════════════════
	# Maker: *"make the stage 1 boss be able to jump"*. It could not — and the reason
	# is that the whole airborne kit was INHERITED AND NEVER CALLED. `Enemy` already
	# owns `_try_chase_jump` (the hop over a wall it is walking into, and the hop up to
	# a hero standing above it), the ballistic LEAP solver, and the POUNCE; all of it
	# is already replicated, already animated and already interruptible. Grep the boss
	# scripts for `velocity.y` and the only hit in any of them is the ground-snap zero.
	# So this is one call at the insertion point `Enemy._try_chase_jump` documents for
	# itself — between gravity and `move_and_slide`.
	#
	# ⚠ GATED THE SAME WAY THE WALK IS. A boss mid-cast is rooted on purpose (`_busy`),
	# the intro is a held pose, and the Etcher's breakable wind-up parks its own
	# movement — a boss that hopped out of a rooted cast would break the one beat in
	# the game the player is invited to interrupt.
	if not _busy and _bphase != BPhase.INTRO and _bphase != BPhase.DEAD:
		_try_chase_jump()
	move_and_slide()
	if is_instance_valid(rig):
		if is_instance_valid(_hero):
			rig.set_facing(Vector2(_hero.global_position.x - global_position.x, 0.0))
		rig.set_body_velocity(velocity)
		# ⚠ AND THE RIG IS TOLD, which closes a gap `CharacterRig` names in its own
		# comments ("`Enemy` and `Boss` never call `set_grounded`"). It mattered less
		# while a boss could never be airborne; now that it can, a body in the air
		# drawn in its planted stance is the "legs are wrong" bug all over again.
		rig.set_grounded(is_on_floor())
		if not is_on_floor():
			rig.play(CharacterRig.State.AIR)
		else:
			rig.play(CharacterRig.State.RUN if absf(velocity.x) > 8.0 else CharacterRig.State.IDLE)
	match _bphase:
		BPhase.INTRO:
			_intro_timer -= delta
			if _intro_timer <= 0.0:
				_enter_phase(BPhase.P1)
		BPhase.DEAD:
			return
		_:
			_attack_cd -= delta
			if not _busy and _attack_cd <= 0.0:
				_choose_attack()
	_boss_touch()


# ══ THE GUARDIAN AND THE FLOOR MUST AGREE ABOUT WHERE THE FLOOR IS ═══════════
## Maker, playtesting: *"the boss needs to be able to move, it gets stuck in the
## floor."*
##
## Same family as the bug `CharacterRig._align_feet_to_body` just fixed — a body and
## the thing that draws it disagreeing about the ground — but there were THREE
## disagreements stacked on one guardian, and only the third is cosmetic. All three
## are measured by `tools/probe_boss_feet.gd`; the numbers below are its output on
## the shipped 1160x560 room, whose floor collider's top face is y 552.
##
##   1 · BORN INSIDE THE FLOOR. `Encounter.STAND_OFFSET` (40) is how far above the
##       ground plane a spawned body's ORIGIN goes. It is sized for a trash mob,
##       whose box reaches 10 px below its origin. `Boss.tscn`'s box is 44x92 at
##       (0, 6), so it reaches **52 px** down — 12 px more than the entire stand-off.
##           spawn_y 512   box_bottom 564   ground 552   -> BURIED 12.00 px
##       Depenetration does recover it in the clean test room, but "the guardian is
##       born 12 px inside the floor and relies on the solver to spit it out" is not
##       a thing to leave standing next to a report of being stuck in it.
##
##   2 · A BOX TWICE THE SIZE OF THE DRAWING. `body_scale` shrank the RIG and left
##       the collider at full size, so the mini-guardian that caps floors 1-4 and
##       6-9 is a 42.75 px figure inside a 92 px box. Its origin — which is what its
##       spells, its adds and `_boss_touch` all measure from — sat above its own
##       head, and the box it walked around in bore no relation to what you could
##       see. That is the half that reads as "stuck": the visible body does not
##       stand where the invisible one does.
##
##   3 · FEET ALIGNED TO THE WRONG HEIGHT. `CharacterRig._align_feet_to_body` runs
##       in the RIG's `_ready`, which fires before this one, so it aligned against
##       `height` 95 — the scene default — and then this function changed the height
##       underneath it. Measured on the mini-guardian: drawn feet 525.87 against a
##       floor at 552, i.e. **26 px in the air**.
##
## Fixed in that order, because each step reads the previous one's result.
##
## ⚠ AT `body_scale == 1.0` EVERY ONE OF THESE IS A NO-OP by construction — the box
## is unscaled, the rig height already matches what the alignment was computed for,
## and the ground snap moves the body by the same 12 px the solver moved it anyway.
## The floor-5 colossus (and `tools/slice_test_boss.gd`, which fights it) is
## unchanged.


## Shrink the collision box with the body. A guardian drawn at 45% must be 45% of a
## guardian to walk into, to shove and to stand on the floor with.
##
## ⚠ THE SHAPE IS DUPLICATED BEFORE IT IS TOUCHED. A `SubResource` in a .tscn is
## SHARED between every instance of that scene, so resizing it in place would resize
## every other guardian in the session — including ones already standing on a floor.
## `Arena._set_wall` documents the same trap for the room's walls.
func _fit_box_to_scale() -> void:
	if is_equal_approx(body_scale, 1.0):
		return
	for c: Node in get_children():
		var cs := c as CollisionShape2D
		if cs == null or not (cs.shape is RectangleShape2D):
			continue
		var r: RectangleShape2D = (cs.shape as RectangleShape2D).duplicate() as RectangleShape2D
		r.size *= body_scale
		cs.shape = r
		cs.position *= body_scale
	# Whatever `CharacterRig._align_feet_to_body` decided in the rig's own `_ready`
	# was computed against the box that existed a moment ago. It is about to be
	# recomputed against this one — see `_realign_feet`.


## Re-run the rig's own feet-to-box alignment now that BOTH the box and the rig's
## height have moved.
##
## ⚠ IT CALLS THE RIG'S OWN FUNCTION RATHER THAN REPEATING ITS ONE LINE, and that is
## deliberate rather than lazy. The rule ("the drawn feet sit on the lowest bottom
## edge of the parent's collision rectangles") is written once, in CharacterRig, with
## the long explanation of the leg-folding bug that produced it. A copy of
## `position.y = box_bottom - height * 0.5` here would be a second source that a
## future edit to the rig cannot reach — which is precisely the drift `Enemy`'s
## RIG_HIP_Y_FACTOR block already refuses to allow. Guarded by `has_method` so a
## stub rig in a harness is silently skipped.
func _realign_feet() -> void:
	if rig.has_method(&"_align_feet_to_body"):
		rig.call(&"_align_feet_to_body")


## Put the guardian's FEET on the floor it was spawned over, instead of trusting the
## trash-mob stand-off and the depenetration solver.
##
## Done here rather than in `Encounter._boss_spawn_position` on purpose: only the
## body knows how far its own box reaches (the four roster scenes each carry their
## own), and asking the world where the floor is costs one ray and cannot go stale
## the way a mirrored constant in Encounter would. Deterministic on both co-op peers
## — identical body, identical room, identical ray.
##
## Silently does nothing when the ray finds no floor (a headless harness with no
## walls, a boss spawned over a pit): gravity then behaves exactly as it did before.
##
## ⚠ RUN FROM THE FIRST PHYSICS FRAME, NOT FROM `_ready`, AND THAT IS MEASURED. In
## `_ready` the ray found nothing whenever the room's static bodies had been added in
## the same idle frame — the physics space has not taken them yet — and the guardian
## silently fell the 16 px instead of being placed on the floor. One physics frame
## later the space is live, the ray hits, and the placement is exact. (Arena builds
## the room well before the boss spawns, so this only bit the harness; a correction
## that works by luck of ordering is not a correction.)
func _stand_on_ground() -> void:
	if not is_inside_tree():
		return
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return
	var reach: float = RIG_HEIGHT * 2.0 + GROUND_SNAP_REACH
	var q := PhysicsRayQueryParameters2D.create(
		global_position - Vector2(0.0, GROUND_SNAP_LIFT),
		global_position + Vector2(0.0, reach),
		collision_mask)
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	global_position.y = float((hit["position"] as Vector2).y) - _box_bottom_offset()
	velocity.y = 0.0


## How far the lowest collision rectangle reaches below the body's origin — i.e.
## where physics will rest this body. Mirrors the rule `CharacterRig` uses to find
## the same edge, so the feet and the snap can never land on different answers.
func _box_bottom_offset() -> float:
	var best: float = 0.0
	for c: Node in get_children():
		var cs := c as CollisionShape2D
		if cs == null or not (cs.shape is RectangleShape2D):
			continue
		best = maxf(best, cs.position.y + (cs.shape as RectangleShape2D).size.y * 0.5)
	return best


## Start the ground ray this far ABOVE the origin. The whole point is that the body
## may already be buried, and a ray starting inside the floor collider finds nothing.
const GROUND_SNAP_LIFT: float = 8.0
## ...and end it this far below the deepest a guardian's box can reach, so the ray is
## long enough to find a floor from any legal spawn height without being so long that
## it reaches through into the next room's geometry.
const GROUND_SNAP_REACH: float = 120.0


func _boss_touch() -> void:
	if not is_instance_valid(_hero) or _touch_cooldown > 0.0:
		return
	if global_position.distance_to(_hero.global_position) < RIG_HEIGHT * body_scale * 0.55:
		if _hero.has_method("take_damage"):
			_hero.take_damage(touch_damage)
			_touch_cooldown = 0.8


# ------------------------------------------------------------------ overrides
func take_damage(amount: int, tint: Color = Color(1.0, 1.0, 1.0, 0.0)) -> void:
	if _bphase == BPhase.DEAD:
		return
	# Co-op: a hit on a client-side puppet boss forwards to the host BEFORE any phase
	# logic — only the host advances phases / spawns adds (the guardian is host-owned).
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_take_damage", amount, tint)
		return
	super.take_damage(amount, tint)   # hp / flash / numbers / may call _die
	if _bphase == BPhase.DEAD:
		return
	var frac: float = float(hp) / float(maxi(max_hp, 1))
	if _bphase == BPhase.P1 and frac <= PHASE2_AT:
		_enter_phase(BPhase.P2)
	elif _bphase == BPhase.P2 and frac <= PHASE3_AT:
		_enter_phase(BPhase.P3)


func apply_knockback(impulse: Vector2, do_flop: bool = true) -> void:
	# Puppet -> forward the RAW impulse to the host; the host applies RESIST once.
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_apply_knockback", impulse)
		return
	super.apply_knockback(impulse * KNOCKBACK_RESIST, do_flop)


func _die() -> void:
	if _bphase == BPhase.DEAD:
		return
	_bphase = BPhase.DEAD
	# THE CLIMAX RUNG. A boss dying is the one moment in a run that earns the most
	# expensive mark in the vocabulary: `CUT_IN` slams black bars in from top and
	# bottom and holds on a band the boss is still DRAWN inside, so you watch it
	# fall instead of watching a white rectangle. If this fires more than once a
	# fight something has gone wrong — that rarity is what makes it land.
	#
	# The old pair of calls here (an epic_moment with frame:true AND a second
	# impact_frame at 1.3, back to back) was two white blow-outs on top of each
	# other; the arbiter would now refuse the second one anyway, but asking for it
	# was the bug. One beat, one mark.
	Juice.epic_moment({"strength": 1.4, "shake": 20.0, "sfx": "cannon"})
	Juice.tier_frame(SpellTier.Tier.ULT, global_position, -1, {"climax": true})
	var sc := StarConvergence.new()
	sc.target_group = "none"   # visual-only finisher (no group "none" -> hits nobody)
	# Owned too, even though it damages nobody: the reaction layer does not care
	# about target groups, and a death spectacle crossing a live hero beam should
	# read as the boss's, not as an ownerless orphan.
	sc.set("caster_node", self)
	get_parent().add_child(sc)
	sc.converge(global_position, Color(1.0, 0.6, 0.2), 180.0, 0, "holy")
	if _bar != null:
		var tw := create_tween()
		tw.tween_property(_bar, "modulate:a", 0.0, 0.8)
	emit_signal("defeated")
	super._die()


## THE GUARDIAN'S XP, and the reason `Enemy._notify_run_kill` is virtual at all.
##
## A guardian dying used to file as one more trash kill: it would have drawn one
## body's worth from the floor's kill purse, i.e. the climax of the floor would have
## paid roughly what a chaser pays. It is now the floor's single biggest XP event,
## paid OUTSIDE the purse, because it is not one of the floor's bodies.
##
## This also closes a gap that predates XP entirely: `GameState.notify_boss_killed`
## existed and was called by nobody, so `_boss_killed` was only ever set when
## clearing the LAST floor. A guardian felled on floors 1-9 went unrecorded in the
## run outcome. It is recorded now.
func _notify_run_kill() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.notify_guardian_killed(global_position)


# -------------------------------------------------------------------- phases
func current_phase() -> int:
	match _bphase:
		BPhase.P1: return 1
		BPhase.P2: return 2
		BPhase.P3: return 3
		BPhase.DEAD: return 4
		_: return 0


## PHASE ESCALATION, and in co-op it has to CROSS. `take_damage` forwards a puppet
## hit to the host before any phase logic runs, which is correct — but it means a
## client's guardian never re-tinted, never grew its aura, never played the enrage
## beat. Half the party watched a boss that visibly never changed. The broadcast
## goes out first so the two screens escalate together.
func _enter_phase(p: int) -> void:
	if _net != null and _net.is_host():
		_net.broadcast_boss_phase(self, p)
	_apply_phase(p, true)
	emit_signal("phase_changed", current_phase())


## Client side of the same escalation, driven by the host's broadcast. Same LOOK,
## none of the fight logic — see the `authoritative` flag below for exactly what a
## client must not do.
func net_apply_phase(p: int) -> void:
	_apply_phase(p, false)
	emit_signal("phase_changed", current_phase())


## ⚠ ONE FUNCTION, NOT TWO, and that is the point. The obvious shape here is a
## client-side copy of the escalation — and a copy is precisely how the two drift:
## the next person to retint P3 edits one of them, the boss looks different on the
## two phones, and nothing errors. So the host path and the client path are the same
## code, and `authoritative` names the only difference.
##
## What a client must NOT do: spawn the enrage adds (enemies are host-owned, and a
## client minting its own would put bodies on one screen that exist on neither peer's
## authority), or drive the attack clock (only the host chooses attacks at all).
func _apply_phase(p: int, authoritative: bool) -> void:
	_bphase = p
	if authoritative:
		_attack_cd = next_attack_cd(p) * 0.6
	# THE BOSS FIGHT'S ONE REWARD EVENT. Hype's channels — kill streaks and
	# multi-kills — both need a crowd, so a 1v1 guardian pays out NOTHING for its
	# whole length (the audit measured ~23 seconds of it on floor 5). Breaking a
	# phase is the beat a boss fight reliably produces, so it is the beat that pays.
	# Granted on BOTH the host and the client path deliberately: rank is a local
	# cosmetic and each peer's own player earned their own break.
	if p == BPhase.P2 or p == BPhase.P3:
		_grant_phase_break_power()
		# THE HAND TAKES THE PAGE BACK. Deliberately OUTSIDE the `authoritative`
		# guard: this is presentation, both peers reach this function (the host via
		# `_enter_phase`, the client via `net_apply_phase`), and a phase break that
		# redrew the floor on one phone and not the other would read as the host
		# lying — the exact failure the shared `_apply_phase` exists to prevent.
		_redraw_the_page(p)
	match p:
		BPhase.P1:
			if _adorn != null: _adorn.set_intensity(0.35)
			if is_instance_valid(rig):
				rig.set_aura(Color(1.0, 0.45, 0.15), 0.45)
				rig.set_aura_tier(2)
		BPhase.P2:
			if _adorn != null: _adorn.set_intensity(0.7)
			if is_instance_valid(rig):
				rig.set_tint(Color(0.44, 0.32, 0.30))
				rig.set_aura(Color(1.0, 0.38, 0.12), 0.6)
				rig.set_aura_tier(3)
				rig.flash_color(Color(1.4, 1.3, 1.2), 0.18)
			Juice.epic_moment({"strength": 1.1, "shake": 12.0, "sfx": "charge_up"})
			if authoritative:
				_atk_summon()   # open the enrage with adds
		BPhase.P3:
			if _adorn != null: _adorn.set_intensity(1.0)
			if is_instance_valid(rig):
				rig.set_tint(Color(0.52, 0.28, 0.24))
				rig.set_aura(Color(1.0, 0.28, 0.08), 0.78)
				rig.set_aura_tier(4)
			# The enrage is a REVEAL, not a detonation: the boss changes and you
			# need to see what it changed into. So the black cut, which drops the
			# room out and leaves the new silhouette lit, rather than the white
			# blow-out, which erases the very thing the beat exists to show.
			Juice.epic_moment({"strength": 1.2, "shake": 14.0, "sfx": "cannon",
				"frame": true, "at": global_position,
				"style": ImpactFrame.Style.SILHOUETTE})


## ⚠ A TREE LOOKUP, NOT THE BARE `Rank` IDENTIFIER. `Rank` is an autoload and
## `Rank.gd` declares no `class_name`, so the identifier only resolves once the
## autoload is registered — and a `--script` harness registers none. Naming it here
## would make this WHOLE FILE fail to compile under every headless boss suite, and a
## `class_name` script that failed to compile still resolves to a GDScript object
## with none of its members on it. (`Juice` above is safe for the opposite reason:
## it has a `class_name`.) `SpellDrops.sfx` documents the same trap at length.
##
## The AMOUNT comes off the Rank script rather than being copied, so the boss's
## reward and the curve it feeds can never drift apart. `preload` of a plain script
## resource does not register or need the autoload.
const RANK_SCRIPT: GDScript = preload("res://scripts/combat/Rank.gd")


func _grant_phase_break_power() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	var r: Node = tree.root.get_node_or_null(^"Rank")
	if r != null and r.has_method(&"add_power"):
		r.call(&"add_power", int(RANK_SCRIPT.get(&"PHASE_BREAK_POWER")))


## Broadcast one spectacle to every client as a DAMAGE-FREE twin. Host-gated inside
## `Net.broadcast_boss_fx`, so this is a no-op in single player and on a client.
func _bfx(kind: String, data: Dictionary) -> void:
	if _net != null and _net.is_host():
		data["src"] = String(get_path())
		_net.broadcast_boss_fx(kind, data)


# ------------------------------------------------------------ attack selection
func _phase_attack_ids(phase: int) -> Array:
	match phase:
		1: return ["slam", "pillars"]
		2: return ["beam", "rays", "summon"]
		3: return ["meteor", "convergence", "nova", "slam"]
	return []


func _choose_attack() -> void:
	var ids: Array = _phase_attack_ids(current_phase())
	if ids.is_empty():
		_attack_cd = 1.0
		return
	_run_attack(String(ids[randi() % ids.size()]))
	_attack_cd = next_attack_cd(_bphase)


func _run_attack(id: String) -> void:
	_busy = true
	if is_instance_valid(rig):
		var g: int = CharacterRig.GestureKind.STOMP if id in ["slam", "pillars"] else CharacterRig.GestureKind.RAISE
		rig.cast_gesture(g, 0.9)
	match id:
		"slam": _atk_slam()
		"pillars": _atk_pillars()
		"beam": _atk_beam()
		"rays": _atk_rays()
		"summon": _atk_summon()
		"meteor": _atk_meteor()
		"convergence": _atk_convergence()
		"nova": _atk_nova()
	_unbusy_after(_attack_duration(id))


func _attack_duration(id: String) -> float:
	match id:
		"slam": return 1.0
		"pillars": return 1.1
		"beam": return BEAM_WINDUP + 0.9   # the tell is part of the attack
		"rays": return 1.0
		"summon": return 1.0
		"meteor": return 1.1
		"convergence": return 1.4
		"nova": return 0.6
	return 0.8


func _unbusy_after(t: float) -> void:
	get_tree().create_timer(t).timeout.connect(func() -> void: _busy = false)


# ---------------------------------------------------------------- the attacks
func _atk_slam() -> void:
	if not is_instance_valid(_hero):
		return
	var center: Vector2 = _hero.global_position
	var b: Node = load("res://scenes/combat/BlastSpell.tscn").instantiate()
	get_parent().add_child(b)
	# CASTER IDENTITY — see _atk_beam for why this is load-bearing rather than
	# bookkeeping. `set()` is a silent no-op on a spectacle that has not declared
	# `caster_node` yet, so this is safe now and becomes live the day it does.
	b.set("caster_node", self)
	b.configure({"target_group": "hero", "damage": 28, "radius": 100, "knockback": 360, "windup": 0.7, "element_id": Elements.Element.EARTH})
	b.detonate_at(center)   # runs its own ZONE telegraph windup (the dodge tell)
	# Co-op: the slam's own windup IS the dodge tell, so the twin carries it too —
	# a client that only got the crater would be told about the attack after it hit.
	_bfx("slam", {"pos": center, "r": 100.0, "windup": 0.7, "el": Elements.Element.EARTH})
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		GroundCrater.spawn(get_parent(), center, 64.0, true)
		_bfx("crater", {"pos": center, "r": 64.0})
		Juice.on_hit({"shake": 15.0, "sfx": "blast", "hitstop": 0.09}))


func _atk_pillars() -> void:
	if not is_instance_valid(_hero):
		return
	var base: Vector2 = _hero.global_position
	var offs: Array = [-180.0, 0.0, 180.0]
	for i: int in 3:
		var pt: Vector2 = base + Vector2(float(offs[i]), 0.0)
		get_tree().create_timer(0.12 * float(i)).timeout.connect(func() -> void:
			if not is_instance_valid(self):
				return
			var p := RockPillar.new()
			p.target_group = "hero"
			p.set("caster_node", self)   # caster identity — see _atk_beam
			get_parent().add_child(p)
			p.erupt(pt, Color(0.8, 0.55, 0.28), 66.0, 30)
			_bfx("pillar", {"pos": pt, "col": Color(0.8, 0.55, 0.28), "r": 66.0}))


## THE TELL. Snapshot the aim, lay a charge LANE from the guardian along it, and
## only fire when the lane expires. Same grammar as every other boss attack (and
## as the charger's dash): the shape you can see is the shape that will hurt, and
## it is on screen long enough to step out of. `no_resolve` keeps this off
## Enemy._on_telegraph_fired, whose archetype switch would run a brute strike.
func _atk_beam() -> void:
	if not is_instance_valid(_hero):
		return
	var dir: Vector2 = (_hero.global_position - global_position).normalized()
	dir = Vector2(dir.x, dir.y * 0.35).normalized()   # flatten toward horizontal
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var tele: Telegraph = _emit_telegraph({
		"style": Telegraph.Style.MUZZLE, "pos": global_position,
		"accent": BEAM_ACCENT, "windup": BEAM_WINDUP,
		"line": true, "length": BEAM_LANE_LENGTH, "width": BEAM_LANE_WIDTH,
		"angle": dir.angle(), "aim": dir, "reach": BEAM_LANE_LENGTH,
		"no_resolve": true,
	})
	_spawn_caster_signal(16.0, BEAM_WINDUP)
	if tele == null:
		_fire_beam(dir)
		return
	tele.fired.connect(func() -> void:
		_free_caster_signal()
		if is_instance_valid(self) and _bphase != BPhase.DEAD:
			_fire_beam(dir))


func _fire_beam(dir: Vector2) -> void:
	var origin: Vector2 = rig.get_weapon_tip() if is_instance_valid(rig) else global_position
	var beam := BeamSpell.new()
	beam.target_group = "hero"
	beam.element_id = Elements.Element.ARCANE
	# CASTER IDENTITY — load-bearing, not bookkeeping. The reaction layer's
	# ownership predicate reads this, and a null caster reports as "unowned",
	# which satisfies neither `require_owner: "same"` nor `"different"`. So an
	# ownerless beam matches NO clash row at all: without this line the boss's
	# beam could never annihilate against the hero's, and the cross-caster
	# Hollow Purple row was unreachable in single-player. The same omission is
	# what made Hollow Purple look broken for two sessions.
	beam.caster_node = self
	get_parent().add_child(beam)
	beam.fire(origin, dir, Color(0.7, 0.4, 1.0), 1400.0, 34.0, 34, "arcane")
	_bfx("beam", {"pos": origin, "dir": dir, "col": Color(0.7, 0.4, 1.0),
		"len": 1400.0, "w": 34.0, "fx": "arcane", "el": Elements.Element.ARCANE})


func _atk_rays() -> void:
	if not is_instance_valid(_hero):
		return
	var base: Vector2 = _hero.global_position
	var offs: Array = [-140.0, 0.0, 140.0]
	for i: int in 3:
		var pt: Vector2 = base + Vector2(float(offs[i]), 0.0)
		get_tree().create_timer(0.25 * float(i)).timeout.connect(func() -> void:
			if not is_instance_valid(self):
				return
			var d := DivineRay.new()
			d.target_group = "hero"
			d.set("caster_node", self)   # caster identity — see _atk_beam
			get_parent().add_child(d)
			d.strike(pt, Color(1.0, 0.5, 0.2), 70.0, 40, "fire")
			_bfx("ray", {"pos": pt, "col": Color(1.0, 0.5, 0.2), "r": 70.0, "fx": "fire",
				"el": Elements.Element.FIRE}))


## Adds are capped TWICE: by the guardian's own ADD_CAP (this fight should not
## become an add fight) and by the floor's live-entity budget, which the boss
## does not own and must ask about. Before 1.4 this bypassed the encounter cap
## entirely, so a summoning boss could push the floor past its ceiling.
func _atk_summon() -> void:
	_prune_summoned()
	var n: int = mini(2, ADD_CAP - _summoned.size())
	n = mini(n, _spawn_headroom())
	if n <= 0:
		return
	var chaser: Dictionary = ARCHETYPE_DEFAULTS[Archetype.CHASER]
	for i: int in n:
		var pos: Vector2 = global_position + Vector2(randf_range(-90.0, 90.0), -20.0)
		var e: Node = _spawn_runtime_enemy({
			"boss": false, "arch": 0, "hp": 22,
			"spd": float(chaser["speed"]), "touch": int(chaser["touch"]),
			"tint": Color(1.0, 0.6, 0.35, 1), "tele": false,
			"x": pos.x, "y": pos.y,
		})
		if e != null:
			_summoned.append(e)


func _prune_summoned() -> void:
	var kept: Array = []
	for e in _summoned:
		if is_instance_valid(e):
			kept.append(e)
	_summoned = kept


func _atk_meteor() -> void:
	if not is_instance_valid(_hero):
		return
	var m := MeteorSigil.new()
	m.target_group = "hero"
	m.set("caster_node", self)   # caster identity — see _atk_beam
	get_parent().add_child(m)
	m.rain(_hero.global_position, Color(1.0, 0.55, 0.2), 170.0, 22, 12, "fire")
	_bfx("meteor", {"pos": _hero.global_position, "col": Color(1.0, 0.55, 0.2),
		"r": 170.0, "n": 12, "fx": "fire", "el": Elements.Element.FIRE})
	Juice.zoom_pull_camera(0.16, 0.5)


func _atk_convergence() -> void:
	if not is_instance_valid(_hero):
		return
	var s := StarConvergence.new()
	s.target_group = "hero"
	s.set("caster_node", self)   # caster identity — see _atk_beam
	get_parent().add_child(s)
	s.converge(_hero.global_position, Color(1.0, 0.4, 0.15), 170.0, 110, "fire")
	_bfx("convergence", {"pos": _hero.global_position, "col": Color(1.0, 0.4, 0.15),
		"r": 170.0, "fx": "fire", "el": Elements.Element.FIRE})


func _atk_nova() -> void:
	var n: Node = load("res://scenes/combat/EnergyNova.tscn").instantiate()
	n.target_group = "hero"
	n.set("caster_node", self)   # caster identity — see _atk_beam
	get_parent().add_child(n)
	n.activate_at(global_position)
	_bfx("nova", {"pos": global_position})


# ------------------------------------------------------------------ boss HUD
## Is this the floor's HEADLINE act, or a mini-guardian? Read off `body_scale`, which
## is set pre-`_ready` and travels in the co-op spawn dict — see the CEREMONY block.
func full_ceremony() -> bool:
	return body_scale >= FULL_CEREMONY_SCALE


## How long the boss stands there being announced (and cannot attack).
func intro_time() -> float:
	return INTRO_TIME if full_ceremony() else BRIEF_INTRO_TIME


## Name-card typography + timing, as one bag so the base intro and every subclass's
## override read the same numbers instead of each hard-coding 36 / 0.5 / 1.4 / 0.5.
## `hold` is the interval the card sits at full alpha; fade in/out bracket it, and
## the three together must fit inside `intro_time()`.
func card_style() -> Dictionary:
	if full_ceremony():
		return {"size": 36, "outline": 7, "top": 120.0, "sig_size": 12, "sig_top": 160.0,
			"fade": 0.5, "hold": 1.4, "roar": 0.6, "pull": 0.2, "pull_hold": 0.4,
			"pull_release": 0.6}
	# A flash, not a card: smaller, higher up, and gone in under a second.
	return {"size": 20, "outline": 5, "top": 96.0, "sig_size": 10, "sig_top": 122.0,
		"fade": 0.22, "hold": 0.3, "roar": 0.25, "pull": 0.1, "pull_hold": 0.18,
		"pull_release": 0.35}


func _build_bar() -> void:
	_bar_layer = CanvasLayer.new()
	_bar_layer.layer = 55
	add_child(_bar_layer)
	_bar = BossBar.new()
	_bar_layer.add_child(_bar)
	# Virtual dispatch: a subclass's title/accent are in place from the first frame,
	# so the bar never briefly shows the wrong boss's name. A mini-guardian gets the
	# COMPACT bar — it still needs its HP read at a glance, it just does not need
	# two thirds of the screen width to say so.
	_bar.setup(self, boss_title(), boss_accent(), not full_ceremony())


func _play_intro() -> void:
	_bphase = BPhase.INTRO
	_intro_timer = intro_time()
	var s: Dictionary = card_style()
	Juice.zoom_pull_camera(float(s["pull"]), _intro_timer,
		float(s["pull_hold"]), float(s["pull_release"]))
	var card := Label.new()
	card.set_anchors_preset(Control.PRESET_TOP_WIDE)
	card.offset_top = float(s["top"])
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.text = boss_title()
	card.add_theme_font_size_override("font_size", int(s["size"]))
	card.add_theme_color_override("font_color", boss_accent())
	card.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.03, 0.95))
	card.add_theme_constant_override("outline_size", int(s["outline"]))
	card.modulate.a = 0.0
	_bar_layer.add_child(card)
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, float(s["fade"]))
	tw.tween_interval(float(s["hold"]))
	tw.tween_property(card, "modulate:a", 0.0, float(s["fade"]))
	tw.tween_callback(card.queue_free)
	get_tree().create_timer(float(s["roar"])).timeout.connect(_roar_intro)


func _roar_intro() -> void:
	if not is_instance_valid(self):
		return
	# No body flash (it fights the stone read + lingers under the intro hitstop) —
	# the aura pop + shake + roar sfx carry the wake. The molten core does the glow.
	if _adorn != null:
		_adorn.set_intensity(0.55)
	Juice.epic_moment({"strength": 1.0, "shake": 10.0, "sfx": "charge_up"})
