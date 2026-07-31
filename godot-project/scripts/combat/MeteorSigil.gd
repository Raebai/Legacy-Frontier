class_name MeteorSigil
extends Node2D

## Who this meteor storm's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## Signature spectacle #3 — the SKY BOMBARDMENT. A huge magic circle opens high
## over the marked area and a barrage falls, staggered so it reads as a shower.
##
## Phase-2 redesign: the four elements are NO LONGER recolors of one falling
## head. Each has its own falling-object identity + impact behaviour:
##   FIRE   — true meteors: tumbling molten rock with glowing cracks and a
##            ragged burning tail; impact explodes outward and leaves a
##            persistent scorch + a flickering ember pool.
##   FROST  — NO LONGER A BOMBARDMENT. See the fork at the top of rain(): the
##            ice family now erupts from the FLOOR as a spreading crest of
##            spikes (IceSpikeLine.gd) instead of raining spears on a circle.
##            The old falling-spear draw / _land_frost / IceSpikeCluster below
##            are now UNREACHABLE from rain(). Kept for one iteration so the
##            redesign is a small, reversible diff while it is still unplayed;
##            if the crest survives its first playtest, delete them.
##   EARTH  — heavy dumb BOULDERS: slower, no tail, a looming ground shadow;
##            impact is a dust plume + debris chunks kicked sideways + the
##            hardest camera thump of the four.
##   SHADOW — not objects at all: TEARS rip open in the air, a column of void
##            drops from each, and the impact IMPLODES — pulls targets inward
##            instead of knocking them away.
##
## Dodgeability (overhaul rule 2): besides the 0.5 s sigil charge, EVERY impact
## point gets its own element-flavoured ground telegraph (scorch ring / frost
## bloom / looming dust shadow / dilating void slit) that starts BEFORE the
## object can hit, so each strike has a genuine per-point reaction window.
##
## Per-meteor radius damage (targets_in_radius, pure/testable); rain() drives
## the timeline. Instantiate .new(), add to the arena, call rain(). The
## trailing `effect` param picks the element ("fire"|"frost"|"earth"|"shadow"
## bespoke; anything else falls back to the classic head+trail template).

## The frost family's spectacle now lives in its own file (see the FROST fork in
## rain()). load()ed by PATH, never by class_name: this script is load()ed at
## runtime by headless tools precisely so nothing early-compiles the autoload
## chain, and a class_name reference would drag IceSpikeLine in at compile time.
const SPIKE_LINE_PATH: String = "res://scripts/combat/IceSpikeLine.gd"

const CHARGE_TIME: float = 0.5     # sky sigil + ground telegraph before ANY launch
const FALL_TIME: float = 0.52      # fire + generic per-meteor descent
const BARRAGE_TIME: float = 1.15   # window the meteors spawn across
const FADE_TIME: float = 0.35
## Per-element descent times — the fall IS the personality: frost spears are
## quick (compensated by an earlier telegraph), earth boulders are ponderous
## mass, shadow spends most of its window visibly tearing open before the drop.
const FALL_TIME_FROST: float = 0.40
const FALL_TIME_EARTH: float = 0.82
const FALL_TIME_SHADOW: float = 0.55
## Frost's ground bloom starts this long BEFORE its spike launches, so the
## fast spear still gives a fair (0.30 + 0.40 = 0.70 s) reaction window.
const MARK_LEAD_FROST: float = 0.30
## Shadow tears open THIS far above the ground — low, menacing, readable.
const RIFT_HEIGHT: float = 115.0
## Fraction of shadow's fall spent opening the tear (the rest is the void drop).
const RIFT_OPEN_FRAC: float = 0.64
## Meteors streak in from just above the combat view (not far off-screen) so you
## SEE the shower coming down — readability + the "here it comes" tell.
const SKY_HEIGHT: float = 360.0

# ── THE SKY GATE: the summoning circle the bombardment pours OUT of ──────────
# THE MAKER, LIVE, MID-PLAYTEST: "I can't see the circle for the sky attack."
#
# He was right, and the cause is not a bug — it is an amputation. The previous
# pass DELETED the shared sky sigil (its tombstone is still the `⚠ NO MAGIC
# CIRCLE` note in `rain()`) on the grounds that it was the single biggest reason
# five ults read as one another. That diagnosis was correct. The amputation was
# not: what it left behind is a bombardment with no visible SOURCE. Rocks appear
# somewhere near the top of the frame and fall, which is the least magical way it
# is possible to stage a summon, and the capture of the charge beat showed
# literally nothing overhead but seven stray ignition ticks floating in a void.
#
# The gate comes back — but it is not the old shared object:
#   * IT IS CLAMPED INTO FRAME (`_clamp_into_view`). The old sigil hung at
#     SKY_HEIGHT (360 px) over a floor-level footprint, and the base viewport is
#     640x360, so on a camera sitting anywhere near the floor the circle was
#     simply ABOVE THE TOP OF THE SCREEN. A circle you cannot see is not a circle.
#   * THE METEORS ARE BORN ON IT (`_gate_mouth`). The shower comes out of the
#     ritual instead of out of the bezel, and each rock gets a birth bloom at the
#     mouth (`_draw_birth_bloom`) so you SEE it emerge.
#   * ITS COMPOSITION IS PER-FAMILY — one wide gate for fire's sweeping front,
#     three small holes for earth's avalanche — so the opening beat still says
#     which spell this is at a glance, which is what the deletion was protecting.
#
# ⚠ THE GATE IS SCENERY. It deals no damage, and it does not touch `_spread`, so
# the drawn danger footprint and the rolled impact points are the same numbers
# they were before this block existed (pinned by tools/slice_test_meteor_gate.gd).
# Nor does it move any timing: CHARGE_TIME, the per-meteor delays and `_fall_time`
# are untouched, so every dodge budget is exactly what it was.
#
## Gate centre height above the footprint, BEFORE the in-frame clamp. Lower than
## SKY_HEIGHT on purpose — the gate is the thing you must actually look at, so it
## wants to sit inside the frame by construction and rely on the clamp only as a
## backstop. UNTESTED GUESS.
const GATE_HEIGHT: float = 236.0
## Gate radius as a fraction of the footprint half-width, with hard bounds so a
## tiny-radius spell still gets a legible circle and a huge one does not fill the
## sky.
##
## ⚠ THE MAX IS THE IMPORTANT ONE AND IT WAS MEASURED, NOT GUESSED. The first
## render of this gate used 178 and the result was a circle whose diameter was
## most of the arena view: it hung down over the player, the impact footprint and
## the falling rocks all at once, so the fix for "I can't see the circle" briefly
## became "I can't see anything else". A gate has to be big enough to read as a
## ritual and small enough that the fight still happens underneath it.
const GATE_RADIUS_FACTOR: float = 0.52
const GATE_RADIUS_MIN: float = 46.0
const GATE_RADIUS_MAX: float = 104.0
## Clearance kept between the gate's rim and the edge of the visible frame.
## UNTESTED GUESS.
const GATE_MARGIN: float = 12.0
## The clamp may never drag the gate closer than this to the ground it feeds —
## otherwise a very short camera view would slide the summoning circle down onto
## the player's head. When the view is too short to satisfy both, THIS wins and
## the gate is allowed to ride partly off the top: a circle overlapping the
## fight would be worse than a circle half in frame. UNTESTED GUESS.
const GATE_MIN_LIFT: float = 178.0
## EARTH opens several small holes instead of one wide gate — the avalanche drops
## out of a cracked ceiling, not a portal. Composition, not colour, is what keeps
## it from reading as a recoloured fire storm. UNTESTED GUESS.
const GATE_COUNT_EARTH: int = 3
const GATE_RADIUS_FACTOR_EARTH: float = 1.7
## Spacing between multiple gates, measured IN GATE RADII rather than in px or in
## fractions of the footprint. Earth's footprint is deliberately narrow
## (SPREAD_EARTH 0.55), so a footprint-relative spacing put its three holes on top
## of each other and they read as one lumpy circle. > 2.0 guarantees clear air
## between the rims. UNTESTED GUESS.
const GATE_SEPARATION: float = 2.35
## Fraction of the gate's own radius that meteors are born within, so ten rocks
## do not all leave from one pixel at the centre. UNTESTED GUESS.
const GATE_MOUTH_SPREAD: float = 0.74
## How long a meteor's birth bloom burns at the gate mouth after it launches.
## Short — it is a "something came through" pop, not a second telegraph.
## UNTESTED GUESS.
const GATE_BIRTH_FLASH: float = 0.17
## How long the gate takes to bloom shut once the last rock is through.
## UNTESTED GUESS.
const GATE_CLOSE_TIME: float = 0.32
## Radius of the halo the birth bloom flares to, in px. UNTESTED GUESS.
const BIRTH_BLOOM_RADIUS: float = 27.0
const DEFAULT_RADIUS: float = 135.0
const DEFAULT_DAMAGE: int = 22     # per meteor — many meteors overlap
const DEFAULT_COUNT: int = 10
const METEOR_IMPACT_RADIUS: float = 48.0
const KNOCKBACK: float = 240.0
const SLANT: Vector2 = Vector2(110.0, 0.0)  # fire meteors streak in from the upper-right
## (SIGIL_VISUAL_RADIUS_FACTOR removed with the sky sigil — see `rain()`.)
## The arena is SIDE-VIEW: the AoE `radius` is a ground FOOTPRINT, so impact
## points scatter across a y-squashed ellipse hugging the floor plane. A full
## disc put ~half the strikes (and their telegraphs) in empty sky, which
## destroyed the "this is where it lands" read and wasted damage on air.
const GROUND_SCATTER: Vector2 = Vector2(1.0, 0.35)

# ── PER-FAMILY SHAPE: why fire, earth and shadow are no longer recolours ─────
# The maker's verdict, mid-playtest: "most ults look the same — just are
# recolours or retypes of the same meteor type of thing." It was correct, and the
# proof was brutal: rendered side by side, the fire / earth / shadow arms of this
# file produced the SAME image with the hue rotated — an identical hexagram sigil
# at an identical size in an identical place, over an identical tight cluster of
# staggered impacts. Colour was doing 100% of the differentiation.
#
# Two structural causes, both fixed here:
#   1. THE SHARED SKY SIGIL. It was the biggest, brightest object on screen, it
#      was the same for every family, and it appeared during the beat the player
#      has longest to look at it. It is GONE (see `rain()`); each family now
#      opens with its own tell in its own visual language.
#   2. IDENTICAL SPREAD AND RHYTHM. Every family scattered over the same ellipse
#      across the same 1.15 s. The constants below give each one a different
#      FOOTPRINT SHAPE and a different TIMING ENVELOPE, which is what the eye
#      actually reads at a glance:
#
#   FIRE   — THE BOMBARDMENT. A wide front sweeping ACROSS the screen on the
#            entry diagonal, right to left, over the longest window. Rhythm.
#   EARTH  — THE AVALANCHE. A tight cluster of dead weight arriving almost
#            TOGETHER in one concentrated multi-thump. Mass.
#   SHADOW — THE UNMAKING. No sky and no falling object at all: tears open low,
#            the screen DIMS instead of brightening, everything is pulled inward.
#            Negative space (the lesson from HollowPurple).
#
# All three UNTESTED GUESSES — they are shape and feel, which only F5 can judge.
## Horizontal spread multipliers on the `radius` footprint, per family.
const SPREAD_FIRE: float = 1.7      # a broad front, not a puddle
const SPREAD_EARTH: float = 0.55    # concentrated mass
const SPREAD_SHADOW: float = 1.0
## Window the strikes are spread across, per family. Fire is a long rhythm; earth
## is nearly simultaneous; shadow sits between, with most of its time spent
## opening rather than falling.
const BARRAGE_TIME_EARTH: float = 0.34
const BARRAGE_TIME_SHADOW: float = 0.75
## Fire sweeps along its entry diagonal instead of popping at random: impacts are
## ordered by x so the eye TRACKS a wave crossing the ground. Ordering an existing
## barrage costs nothing and is the single biggest readability win in this file.
const SWEEP_JITTER: float = 0.10    # fraction of the window left random, so the
                                    # sweep still feels like weather, not a comb
## SHADOW's dimming veil — the anti-explosion. Alpha it reaches at full collapse.
##
## ⚠ THE TENSION IN THIS NUMBER, since it will want tuning on the first playtest:
## the veil sits on a CanvasLayer ABOVE the world, so it dims the void spectacle
## by exactly as much as it dims everything else. Too high and the spell hides
## its own payoff; too low and "the lights went out" stops reading. 0.42 was
## picked by rendering it: at 0.55 the implosion rings were being swallowed. Raise
## it only alongside a brightness lift on the violet elements. UNTESTED GUESS.
const VOID_VEIL_ALPHA: float = 0.42
const VOID_VEIL_TINT: Color = Color(0.02, 0.0, 0.04, 0.0)
## Ground-plane squash for every per-impact marker (matches the 0.4–0.5 used
## by the charge telegraphs / decals) — markers are floor shading, never HUD.
const MARKER_SQUASH: Vector2 = Vector2(1.0, 0.45)

var _center: Vector2 = Vector2.ZERO
var _color: Color = Color(1.0, 0.55, 0.2, 1.0)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var _effect: String = "fire"
var _elapsed: float = -1.0
var _meteors: Array = []  # each: {delay, from, to, landed, seed, spin, verts}
## The scatter half-extents actually used, in world px. Kept as state (rather than
## recomputed) because the CHARGE TELEGRAPH has to be drawn at exactly the same
## extent the strikes are rolled within — a per-family spread multiplier that fed
## the scatter but not the tell would be a fresh "the spell got out of its drawn
## radius" bug, which is the thing this pass exists to stop.
var _spread: Vector2 = Vector2.ZERO
## SHADOW only: the full-screen dimmer (see VOID_VEIL_ALPHA).
var _veil: ColorRect = null
## Elemental ailment (Elements.Element) applied to enemies a meteor hits. -1=none.
var element_id: int = -1
## One impact frame per BARRAGE, not per impact. See `_punctuate_once` — this
## single bool is the difference between one beat and a dozen-frame strobe.
var _punctuated: bool = false
## WHO CAST THIS. Written by `SpellCaster._stamp` — and until now it was written
## into thin air: `Object.set()` on a property a script does not declare is a
## silent no-op, so this spectacle has always been handed its caster and always
## dropped it on the floor. Declaring it is what lets the sky gate ADOPT the
## caster's live windup sigil (MagicCircle.offer/adopt_or_open) instead of opening
## a second one — i.e. what makes the cast one continuous ritual that visibly
## rises from the hand into the sky, rather than two circles in a row.
var caster_node: Node = null
## The summoning gate(s) the bombardment falls out of. Empty for SHADOW, which
## has no sky beat by design (see `_open_gates`).
var _gates: Array[MagicCircle] = []
## Gate centres in WORLD space, post-clamp. Kept separate from `_gates` because
## `_spawn_point` and `_draw` need the geometry every frame and must not care
## whether a circle node is still alive.
var _gate_points: PackedVector2Array = PackedVector2Array()
## The radius every gate opened at — one number, so the mouth the rocks are born
## in can never drift away from the circle that is drawn.
var _gate_radius: float = 0.0
var _gates_dismissed: bool = false


## Public entry: open a sigil over `target` and rain `count` meteors within
## `radius`. Colour tints the shower; `effect` picks its character
## ("fire"/"frost"/"earth"/"shadow" bespoke, others generic).
func rain(
	target: Vector2, color: Color, radius: float = DEFAULT_RADIUS,
	damage: int = DEFAULT_DAMAGE, count: int = DEFAULT_COUNT,
	effect: String = "fire",
) -> void:
	# FROST FORK (maker, mid-playtest: the ice bombardment "reads as more an AoE
	# spell ... let's change it so it's not just a random zone of frost"). Ice no
	# longer falls from the sky — it comes UP out of the floor at the aimed point
	# and spreads outward, so it is dodged by JUMPING rather than by standing
	# somewhere else. Handled here rather than as a new SpellDef.Kind because the
	# Kind->spectacle dispatch table (SpellCaster.gd) is owned elsewhere, and the
	# METEOR arm already hands us exactly what the crest needs: the ground point
	# the player AIMED at, clamped to reach. Fire / earth / shadow fall through
	# untouched and stay bombardments.
	if effect == "frost":
		_hand_off_to_spike_line(target, color, radius, damage)
		return
	_center = target
	_color = color
	_radius = radius
	_damage = damage
	_effect = effect
	_elapsed = 0.0
	_spread = GROUND_SCATTER * radius
	_spread.x *= _spread_factor()
	# THE GATE OPENS FIRST, and the order is load-bearing: `_spawn_point` births
	# every rock on a gate mouth, so the gates have to exist before the roll loop.
	# (The old code needed no ordering because rocks spawned at a blind offset off
	# the top of the frame — which is exactly the bug.)
	_open_gates()
	for i: int in count:
		var ang: float = randf() * TAU
		var unit: float = sqrt(randf())  # sqrt -> uniform over the disc
		# The scatter uses _spread, and so does the telegraph — one number, so the
		# drawn danger area and the rolled impact area can never drift apart.
		var to: Vector2 = _center + Vector2.from_angle(ang) * unit * _spread
		var m: Dictionary = {
			"delay": 0.0, "from": _spawn_point(to), "to": to, "landed": false,
			"seed": randf() * TAU, "spin": randf_range(-2.2, 2.2),
			"verts": PackedVector2Array(),
		}
		# Rock silhouettes are baked ONCE per meteor so the tumbling shape stays
		# stable frame to frame (re-rolling per _draw would shimmer).
		match _effect:
			"fire":
				m["verts"] = _bake_rock(9.5, 0.45)
			"earth":
				m["verts"] = _bake_rock(17.0, 0.4)
				m["spin"] = randf_range(-3.4, 3.4)  # boulders tumble harder
		_meteors.append(m)
	_schedule_barrage()
	if _effect == "shadow":
		_build_veil()
		# NO rising chord. The Unmaking's tell is the light going out; a build-up
		# sting would make it read as another firework winding up.
		Sfx.play("charge_up", -12.0, 0.05, 0.55)  # pitched far down, almost subsonic
	else:
		Sfx.play("charge_up", -2.0, 0.05)  # epic build before the barrage
	queue_redraw()


## Horizontal spread multiplier — the footprint SHAPE that separates the families
## at a glance (a wide front vs a concentrated pile). See the PER-FAMILY block.
func _spread_factor() -> float:
	match _effect:
		"fire":
			return SPREAD_FIRE
		"earth":
			return SPREAD_EARTH
		"shadow":
			return SPREAD_SHADOW
		_:
			return 1.0


## Window the strikes are spread across. The TIMING ENVELOPE is half of each
## family's identity: two spells with the same envelope feel the same even when
## they look different, which is exactly how these three ended up interchangeable.
func _barrage_time() -> float:
	match _effect:
		"earth":
			return BARRAGE_TIME_EARTH
		"shadow":
			return BARRAGE_TIME_SHADOW
		_:
			return BARRAGE_TIME


## Assign each strike its delay.
##
## FIRE SWEEPS: impacts are ordered along the entry diagonal (right to left, since
## SLANT brings the meteors in from the upper right) so the barrage reads as one
## wave crossing the ground rather than as popcorn. Only SWEEP_JITTER of the
## window is left random, which keeps it weather rather than a metronome.
##
## EARTH and SHADOW keep an unordered scatter: a tight simultaneous slam has no
## direction to sweep along, and giving it one would just make it a faster fire.
func _schedule_barrage() -> void:
	var window: float = _barrage_time()
	var n: int = _meteors.size()
	if n == 0:
		return
	if _effect == "fire":
		# Descending x — the wave starts where the meteors come FROM.
		_meteors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["to"] as Vector2).x > (b["to"] as Vector2).x
		)
	for i: int in n:
		var base: float = (float(i) / float(n)) * window
		_meteors[i]["delay"] = base + randf_range(0.0, window * SWEEP_JITTER)


## SHADOW's dimmer. A CanvasLayer above the world but below the post-process
## grade, mirroring HollowPurple's veil — the one spell in the game whose payoff
## is the screen getting DARKER. Everything else in the kit competes to be the
## brightest thing on screen, so going the other way is instantly identifiable.
func _build_veil() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 7  # above the world, below the post-process grade (8) and HUD
	add_child(layer)
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.color = VOID_VEIL_TINT
	layer.add_child(_veil)


## Swap ourselves out for the ice crest. The line is parented to the ARENA
## (get_parent()), never to this node, because we free ourselves immediately —
## it has to outlive the sigil that never opened. `_elapsed` is left at -1.0 so
## _process/_draw stay inert for the frame or two before the free lands.
##
## Every real caller add_child()s this node before calling rain(), so get_parent()
## is the arena; a caller that hasn't is a no-op cast rather than a crash.
func _hand_off_to_spike_line(
	target: Vector2, color: Color, half_length: float, damage: int
) -> void:
	var host: Node = get_parent()
	if host == null or not host.is_inside_tree():
		return
	var line: Node2D = (load(SPIKE_LINE_PATH) as GDScript).new()
	host.add_child(line)
	# Both are set on US before rain() is called (SpellCaster sets element_id,
	# Boss sets target_group), so they carry straight across.
	line.set("element_id", element_id)
	line.set("target_group", target_group)
	line.call("erupt", target, color, half_length, damage, "frost")
	queue_free()


## Open the summoning gate(s) this bombardment falls out of. See the SKY GATE
## block at the top for why this exists at all.
##
## SHADOW IS DELIBERATELY EXCLUDED and that is not an oversight: The Unmaking is
## the one family in this file that is NOT a bombardment. Nothing falls, so there
## is nothing for a gate to be the source of, and its identity (see the PER-FAMILY
## SHAPE block) is precisely that the sky stays empty while the lights go out.
## Hanging a bright circle over it would delete the one ult that reads by absence.
func _open_gates() -> void:
	if _effect == "shadow":
		return
	var n: int = GATE_COUNT_EARTH if _effect == "earth" else 1
	var factor: float = GATE_RADIUS_FACTOR_EARTH if _effect == "earth" else GATE_RADIUS_FACTOR
	# Divided by the gate count so three holes span roughly the same ceiling one
	# wide gate would, rather than three overlapping full-size circles.
	_gate_radius = clampf(_spread.x * factor / float(n), GATE_RADIUS_MIN, GATE_RADIUS_MAX)
	var view: Rect2 = _visible_world_rect()
	var col: Color = _gate_color()
	for i: int in n:
		# Single gate sits over the middle of the footprint; multiple gates step
		# outward from it in GATE RADII (see that constant) so the avalanche
		# visibly drops from several separate cracks at once.
		var fx: float = 0.0 if n == 1 else (float(i) - float(n - 1) * 0.5)
		var want := Vector2(
			_center.x + fx * _gate_radius * GATE_SEPARATION, _center.y - GATE_HEIGHT)
		var at: Vector2 = _clamp_into_view(want, _gate_radius, view)
		_gate_points.append(at)
		var circle: MagicCircle
		if i == 0:
			# THE HAND-OFF (see MagicCircle's seam doc): if the caster has a live
			# windup sigil on offer, this ADOPTS it — the circle the player watched
			# gather in the hand travels up and becomes the gate, spin and phase
			# unbroken. With nothing on offer (enemy casts, boss casts, capture
			# tools) it opens a fresh one and nothing else changes.
			circle = MagicCircle.adopt_or_open(
				self, caster_node, at, col, _gate_radius, CHARGE_TIME * 0.85)
		else:
			circle = MagicCircle.new()
			add_child(circle)
			circle.global_position = at
			circle.appear(col, _gate_radius, CHARGE_TIME * 0.85)
		# BEHIND this node's own drawing. A child CanvasItem draws AFTER its
		# parent by default, which put the sigil ON TOP of the rocks — the first
		# render had meteors disappearing INSIDE the circle they were supposedly
		# coming out of, which is the opposite of the read this whole change is
		# for. z_as_relative is on by default, so -1 is "just behind my parent".
		circle.z_index = -1
		_gates.append(circle)


## The gate's own colour. Fire's gate is a hot portal; earth's is a rune-lit
## crack in dusty stone, NOT a flare — the family's tell is still "no light of its
## own", it just now has a visible mouth. Everything else inherits the spell tint.
func _gate_color() -> Color:
	match _effect:
		"fire":
			return Color(1.15, 0.5, 0.16)
		"earth":
			return Color(0.86, 0.62, 0.32)
	return _color


## The world rectangle the camera can actually see, or a zero Rect2 when there is
## no viewport (headless helper callers) — in which case the clamp is skipped and
## the gate keeps its unclamped placement.
##
## ⚠ Read at CAST time, which is BEFORE SpellCaster's `zoom_pull_camera` has
## widened the view. That is the safe direction to be wrong in: clamping against
## the TIGHTER pre-pull rect can only ever put the gate further inside the frame
## the player ends up looking at.
func _visible_world_rect() -> Rect2:
	var vp: Viewport = get_viewport()
	if vp == null:
		return Rect2()
	var inv: Transform2D = vp.get_canvas_transform().affine_inverse()
	return Rect2(inv * Vector2.ZERO, inv.basis_xform(vp.get_visible_rect().size))


## Drag a gate centre far enough inside `view` that its whole disc is on screen.
## This is the function that answers the maker's complaint literally.
func _clamp_into_view(want: Vector2, r: float, view: Rect2) -> Vector2:
	if view.size.x <= 0.0 or view.size.y <= 0.0:
		return want
	var pad: float = r + GATE_MARGIN
	var out: Vector2 = want
	# Down into frame from the top...
	out.y = maxf(out.y, view.position.y + pad)
	# ...but never down onto the fight (GATE_MIN_LIFT's note explains which of the
	# two constraints wins when the view is too short to honour both).
	out.y = minf(out.y, _center.y - GATE_MIN_LIFT)
	out.x = clampf(out.x, view.position.x + pad, view.end.x - pad)
	return out


## Where this element's falling object enters from. Fire / earth / generic are now
## BORN ON A GATE (that is the whole point of the sky gate). Frost keeps its
## vertical drop for the hand-driven callers that still reach the old spear draw,
## and shadow tears open LOW — nothing falls from the sky for it at all.
func _spawn_point(to: Vector2) -> Vector2:
	match _effect:
		"frost":
			return to + Vector2(randf_range(-10.0, 10.0), -SKY_HEIGHT)
		"shadow":
			return to + Vector2(0.0, -RIFT_HEIGHT)
	return _gate_mouth(to)


## A random point in the mouth of one of the gates.
##
## ⚠ THE GATE IS PICKED AT RANDOM, NOT BY PROXIMITY, and the render is why. The
## obvious rule — "fall out of the hole above your mark" — silently collapses when
## the gate spacing is wider than the footprint, which is exactly EARTH's case
## (SPREAD_EARTH narrows the footprint to ~74 px while GATE_SEPARATION puts the
## holes ~108 px apart). Every boulder then picked the centre hole and the two
## outer ones sat there decoratively doing nothing. A random hole spreads the
## avalanche across all three and the converging diagonals read better anyway.
##
## Falls back to the old blind off-screen offset if no gate opened, so a
## hand-driven caller that skipped `_open_gates` still gets a falling object.
func _gate_mouth(to: Vector2) -> Vector2:
	if _gate_points.is_empty():
		return to + SLANT + Vector2(0.0, -SKY_HEIGHT)
	var best: Vector2 = _gate_points[randi() % _gate_points.size()]
	var ang: float = randf() * TAU
	var reach: float = sqrt(randf()) * _gate_radius * GATE_MOUTH_SPREAD
	return best + Vector2.from_angle(ang) * reach


## Bloom the gates shut once the last rock is through. Called from `_process`.
func _dismiss_gates() -> void:
	if _gates_dismissed:
		return
	_gates_dismissed = true
	for g: MagicCircle in _gates:
		if is_instance_valid(g):
			g.vanish(GATE_CLOSE_TIME)


## Per-element descent duration (see the constants' WHY note).
func _fall_time() -> float:
	match _effect:
		"frost":
			return FALL_TIME_FROST
		"earth":
			return FALL_TIME_EARTH
		"shadow":
			return FALL_TIME_SHADOW
		_:
			return FALL_TIME


## How long before launch this element's per-impact ground telegraph appears.
func _mark_lead() -> float:
	return MARK_LEAD_FROST if _effect == "frost" else 0.0


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	for m: Dictionary in _meteors:
		if not m["landed"] and _elapsed >= CHARGE_TIME + float(m["delay"]) + _fall_time():
			_land(m)
	_update_veil()
	# The gate closes when the last rock is through it, NOT when this node dies —
	# so the circle blooms shut while the shower is still landing, which is the
	# order the ritual reads in. (The bloom finishes well inside the node's own
	# remaining lifetime: `_fall_time` alone is >= 0.4 s against GATE_CLOSE_TIME.)
	if _elapsed >= CHARGE_TIME + _barrage_time():
		_dismiss_gates()
	if _elapsed >= CHARGE_TIME + _barrage_time() + _fall_time() + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## SHADOW only: the screen darkens through the charge, sits at its darkest across
## the collapse, and lifts over the fade. The darkness IS the spectacle — it is
## what makes The Unmaking legible as a different KIND of event from a spell that
## drops burning rocks, even with the colour drained out of both.
func _update_veil() -> void:
	if _veil == null:
		return
	var lift_at: float = CHARGE_TIME + _barrage_time() + _fall_time()
	var a: float
	if _elapsed < CHARGE_TIME:
		a = VOID_VEIL_ALPHA * (_elapsed / CHARGE_TIME)
	elif _elapsed < lift_at:
		a = VOID_VEIL_ALPHA
	else:
		a = VOID_VEIL_ALPHA * clampf(1.0 - (_elapsed - lift_at) / maxf(FADE_TIME, 0.001), 0.0, 1.0)
	_veil.color = Color(VOID_VEIL_TINT.r, VOID_VEIL_TINT.g, VOID_VEIL_TINT.b, a)


## One strike lands: radius damage + status (shared contract), then the
## element's own impact spectacle. Residue nodes are parented to the arena
## (get_parent()), never self — they must outlive this spectacle node.
func _land(m: Dictionary) -> void:
	m["landed"] = true
	# THE FLOOR FIX (docs/spell-world-contract.md names this file as the canonical
	# offender). The impact point was a raw scatter roll, and a scatter roll lands
	# in mid-air or below the world about as often as it lands on the ground — so
	# strikes were detonating inside and underneath the floor. Resolve the y
	# against the floor BENEATH the roll instead, and over a genuine pit skip the
	# strike entirely rather than dropping it into the void.
	#
	# SHADOW is exempt: its tears open in the AIR at RIFT_HEIGHT by design, and
	# snapping them to the floor would delete the one family that is not a
	# bombardment at all.
	if _effect != "shadow":
		var ground: Dictionary = SpellWorld.floor_below(m["to"] as Vector2, SKY_HEIGHT * 1.5, [], self)
		if not bool(ground["hit"]):
			return
		# Write it back so the in-flight draw ends exactly where the impact is.
		m["to"] = ground["position"]
	var at: Vector2 = m["to"]
	_apply_damage(at)
	match _effect:
		"fire":
			_land_fire(at)
		"frost":
			_land_frost(at)
		"earth":
			_land_earth(at)
		"shadow":
			_land_shadow(at)
		_:
			_land_generic(at)
	_punctuate_once(at)


## ONE punctuation beat for the WHOLE barrage, fired on the first strike that
## actually lands, and never again from this sigil.
##
## ⚠ THIS FUNCTION EXISTS BECAUSE OF THE SCAR RECORDED IN `_land_earth`. A
## barrage puts up to a dozen impacts inside ~0.34 s. A per-impact frame is the
## obvious thing to write and it is wrong twice over: the marks would strobe, and
## the freeze each one carries would drop `Engine.time_scale` to 0.05 while the
## REMAINING boulders are still scheduled in GAME time — every freeze pushing the
## next landing further out in real time and re-triggering another freeze, which
## locks the game in stuttering slow motion for seconds.
##
## The global arbiter would refuse the extra marks anyway (that is its job, and
## Juice.frame fires nothing at all when it refuses, freeze included), but
## relying on the referee to clean up after a call site that asks for twelve
## frames is not the same as a call site that asks for one. Both guards, on
## purpose: this flag is the intent, the arbiter is the safety net.
##
## The FIRST impact is deliberately the one that gets it rather than the last:
## the barrage's drama is the arrival, and a mark on the final trailing rock
## lands after the player has already read the event.
func _punctuate_once(at: Vector2) -> void:
	if _punctuated:
		return
	_punctuated = true
	# Camera + freeze suppressed. The per-impact shakes and ripples stack into the
	# sustained pounding that IS this spell's grammar; a frame-owned freeze on top
	# is the trap above.
	Juice.tier_frame(SpellTier.Tier.ULT, at, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


## Shared damage/status contract for every element; only the knockback
## CHARACTER differs — fire blasts away, frost pins (soft push), earth slams
## hardest, shadow PULLS INWARD (the implosion made mechanical).
func _apply_damage(at: Vector2) -> void:
	# Silhouette-aware + line-of-sight selection (see `targets_in_radius` below for
	# why the static stayed). Cover blocks the blast: a meteor landing on the far
	# side of a wall no longer reaches through it, and a strike no longer damages
	# METEOR_IMPACT_RADIUS straight down through the floor.
	for enemy: Node in SpellTargets.in_radius(
			at, METEOR_IMPACT_RADIUS, get_tree().get_nodes_in_group(target_group),
			[caster_node], self):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var out: Vector2 = ((enemy as Node2D).global_position - at).normalized()
			if out == Vector2.ZERO:
				out = Vector2.UP
			match _effect:
				"shadow":
					enemy.apply_knockback(-out * 210.0)  # sucked toward the void
				"frost":
					enemy.apply_knockback(out * 150.0)   # speared, not blasted
				"earth":
					enemy.apply_knockback(out * 300.0)   # the heaviest thump
				_:
					enemy.apply_knockback(out * KNOCKBACK)
	for prop: Node in SpellTargets.in_radius(
			at, METEOR_IMPACT_RADIUS, get_tree().get_nodes_in_group("destructible"), [], self):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)


## FIRE impact: outward explosion — flame plume + ember burst + persistent
## scorch + a lingering EMBER POOL that keeps flickering after the blast.
func _land_fire(at: Vector2) -> void:
	if element_id >= 0:
		ElementFx.spawn(get_parent(), at, element_id, METEOR_IMPACT_RADIUS * 0.62)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(1.5, 0.7, 0.2, 0.95), Color(0.8, 0.2, 0.05, 0.0),
		18, 0.5, 60.0, 220.0, 1.0, 2.6, 0.5, 1.6, true
	)
	ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.7, "scorch",
		Color(0.08, 0.03, 0.02, 0.6), 8.0)
	EmberPool.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.6)
	GroundCrater.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.55, true)
	# FIRE's screen grammar: HEAT. Every strike pulses the heat-haze in the grade,
	# so a long bombardment visibly cooks the whole picture — a cumulative, rising
	# effect no other spell in the kit produces. Shake stays small on purpose: this
	# family's weight comes from RHYTHM (many light beats) where earth's comes from
	# MASS (one heavy one), and giving both a big thump is how they became the
	# same spell with different colours.
	PostProcess.pulse_heat(0.5)
	Juice.shake_camera(4.5)
	Sfx.play("spell_impact", 0.0, 0.08)


## FROST impact: the spike SPEARS IN and stays — a standing crystal cluster
## that shatters a beat later (via IceSpikeCluster). No crater: ice doesn't
## gouge, it pierces; a frost-crack decal marks the plant point instead.
func _land_frost(at: Vector2) -> void:
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.9, 0.98, 1.0, 0.9), Color(0.7, 0.9, 1.0, 0.0),
		10, 0.3, 60.0, 170.0, 0.5, 1.3, 2.0, 4.0, true
	)
	ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.6, "crack",
		Color(0.62, 0.88, 1.0, 0.45), 5.0)
	IceSpikeCluster.spawn(get_parent(), at)
	Juice.shake_camera(3.5)
	Sfx.play("spell_impact", -2.0, 0.08, 1.35)  # higher pitch — glassy, not boomy


## EARTH impact: a real ground-thump — huge slow dust plume (alpha-blended so
## it reads as dirt, not light), debris chunks kicked SIDEWAYS, the biggest
## crater and the hardest shake of the four.
func _land_earth(at: Vector2) -> void:
	# One bright frame first: even dead weight needs a flash for the thump to
	# read on a dark arena (Stick-Fight rule — the hit moment is the brightest).
	CombatVfx.spawn_burst(
		get_parent(), at, Color(1.35, 1.15, 0.85, 0.9), Color(0.9, 0.7, 0.45, 0.0),
		8, 0.18, 90.0, 200.0, 0.8, 1.5, 2.0, 4.0, true
	)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.82, 0.68, 0.5, 0.95), Color(0.5, 0.4, 0.28, 0.0),
		30, 0.9, 40.0, 150.0, 3.0, 7.0, 2.0, 4.0
	)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.95, 0.8, 0.58, 0.95), Color(0.55, 0.44, 0.3, 0.0),
		14, 0.4, 130.0, 280.0, 1.0, 2.0, 1.0, 2.0
	)
	DebrisChunk.spawn_burst(get_parent(), at, Color(0.5, 0.38, 0.22), 3, Vector2.LEFT, 250.0)
	DebrisChunk.spawn_burst(get_parent(), at, Color(0.46, 0.35, 0.2), 3, Vector2.RIGHT, 250.0)
	ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.7, "crack",
		Color(0.6, 0.45, 0.28, 0.5), 6.0)
	GroundCrater.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.8, true)
	# EARTH's screen grammar: MASS. Because BARRAGE_TIME_EARTH lands the whole
	# cluster in ~0.34 s, these stack into one sustained pounding rather than a
	# rhythm — which is exactly the read the avalanche wants and the opposite of
	# fire's long simmer. No heat pulse, no zoom: just weight arriving.
	#
	# ⚠ AND DELIBERATELY NO `hit_stop`. It is the obvious way to sell weight and it
	# is a trap HERE: `hit_stop` drops `Engine.time_scale` to 0.05, the remaining
	# boulders are scheduled in GAME time, so each freeze pushes the next landing
	# further out in REAL time and re-triggers another freeze. A dozen strikes in a
	# 0.34 s cluster would lock the game in stuttering slow motion for seconds.
	# Weight here comes from shakes and ripples STACKING, which compose safely.
	Juice.shake_camera(11.0)
	PostProcess.shock(0.35, Juice.world_to_uv(at))
	Sfx.play("spell_impact", 2.0, 0.05, 0.7)  # pitched DOWN — dead weight, not energy


## SHADOW impact: an IMPLOSION — everything converges (VoidImplosion draws the
## collapse), targets get pulled inward in _apply_damage, and only a faint
## violet stain remains. No crater, no outward burst: the anti-explosion.
func _land_shadow(at: Vector2) -> void:
	if element_id >= 0:
		ElementFx.spawn(get_parent(), at, element_id, METEOR_IMPACT_RADIUS * 0.5)
	VoidImplosion.spawn(get_parent(), at, METEOR_IMPACT_RADIUS)
	ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.55, "scorch",
		Color(0.08, 0.03, 0.14, 0.5), 5.0)
	# SHADOW's screen grammar: STILLNESS. Almost no shake, no ripple, no heat, no
	# hit-stop. The game is loud constantly, so an ult that takes the light away
	# and then barely moves the camera is the loudest contrast available and costs
	# nothing (the lesson HollowPurple's silent HELD beat proved). The veil is
	# doing the work; adding a thump here would drag it back toward being a
	# purple explosion.
	Juice.shake_camera(1.5)
	Sfx.play("spell_impact", -3.0, 0.06, 0.62)  # pitched down, quiet — a swallow


## Fallback impact for non-bespoke effects (arcane/holy/lightning/wind/etc):
## the classic energy burst + crater, charactered by the old per-effect arms.
func _land_generic(at: Vector2) -> void:
	if element_id >= 0:
		ElementFx.spawn(get_parent(), at, element_id, METEOR_IMPACT_RADIUS * 0.62)
	_impact_burst(at)
	GroundCrater.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.55, true)
	Juice.shake_camera(5.0)
	Sfx.play("spell_impact", 0.0, 0.1)


## Generic impact spray, charactered per (non-bespoke) effect.
func _impact_burst(at: Vector2) -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	match _effect:
		"arcane":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1, 1, 1, 0.95), fade,
				22, 0.4, 80.0, 240.0, 1.5, 3.5, 0.0, 0.0, true
			)
		"holy":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.99, 0.9, 0.95), fade,
				24, 0.45, 50.0, 190.0, 1.0, 2.5, 1.0, 2.0, true
			)
		"lightning":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 1.0, 0.7, 0.95), fade,
				24, 0.3, 180.0, 420.0, 0.4, 1.2, 4.0, 8.0, true
			)
		"wind":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.72, 1.0, 0.92, 0.9), fade,
				22, 0.35, 170.0, 420.0, 0.6, 1.7, 2.0, 5.0, true
			)
		_:
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.95, 0.7, 0.95), fade,
				22, 0.4, 80.0, 240.0, 1.5, 3.5, 0.0, 0.0, true
			)
			DebrisChunk.spawn_burst(get_parent(), at, Color(0.35, 0.3, 0.3), 3, Vector2.UP, 180.0)
			ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.7, "scorch",
				Color(0.06, 0.03, 0.02, 0.55), 8.0)


## Pure geometry (testable): nodes within `radius` of `center`.
##
## Kept as a static so `slice4_test_spells` can pin the per-meteor boundary
## without a physics world, but the body now delegates to the shared selector so
## the game has ONE definition of "inside the blast" rather than the seven
## copy-pasted ones this used to be part of. `require_los = false` because this
## overload asks the pure SHAPE question; `_apply_damage` asks the cover question
## too. A target with no drawn silhouette (crate, bolt, test stub) falls back to
## exactly the `global_position` distance test that used to be written out here,
## so the pinned boundary is byte-identical.
static func targets_in_radius(center: Vector2, radius: float, nodes: Array) -> Array:
	return SpellTargets.in_radius(center, radius, nodes, [], null, false)


## Bake one irregular rock silhouette (7 verts) — fire meteor / earth boulder.
static func _bake_rock(size_px: float, irregularity: float) -> PackedVector2Array:
	var verts: PackedVector2Array = PackedVector2Array()
	var n: int = 7
	for i: int in n:
		var ang: float = TAU * float(i) / float(n) + randf_range(-irregularity, irregularity)
		var reach: float = size_px * randf_range(0.62, 1.0)
		verts.append(Vector2.from_angle(ang) * reach)
	return verts


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _elapsed < CHARGE_TIME:
		_draw_charge_telegraph(_elapsed / CHARGE_TIME)
	for m: Dictionary in _meteors:
		if m["landed"]:
			continue
		var launch_t: float = CHARGE_TIME + float(m["delay"])
		var land_t: float = launch_t + _fall_time()
		var mark_t: float = launch_t - _mark_lead()
		# Per-impact ground telegraph FIRST (under the falling object): the
		# element-flavoured "get out of THIS spot" marker (overhaul rule 2).
		if _elapsed >= mark_t:
			_draw_impact_marker(m, clampf((_elapsed - mark_t) / maxf(land_t - mark_t, 0.001), 0.0, 1.0))
		if _elapsed < launch_t:
			continue
		# THE EMERGENCE. A rock that merely exists at the gate's centre on frame
		# one has not come THROUGH anything — the eye needs the mouth to flare as
		# it passes. Drawn before the object so the object rides out of the flare.
		var since: float = _elapsed - launch_t
		if since < GATE_BIRTH_FLASH and not _gate_points.is_empty():
			_draw_birth_bloom(m["from"] as Vector2, 1.0 - since / GATE_BIRTH_FLASH)
		var f: float = clampf((_elapsed - launch_t) / _fall_time(), 0.0, 1.0)
		match _effect:
			"fire":
				_draw_fire_meteor(m, f)
			"frost":
				_draw_ice_spike(m, f)
			"earth":
				_draw_earth_boulder(m, f)
			"shadow":
				_draw_shadow_rift(m, f)
			_:
				_draw_generic_meteor(m, f)


## The flare a rock leaves behind as it comes THROUGH the gate mouth. `k` ramps
## 1 -> 0 across GATE_BIRTH_FLASH. HDR core so it blooms in the grade.
func _draw_birth_bloom(at: Vector2, k: float) -> void:
	var c: Color = _effect_core_color()
	draw_circle(at, BIRTH_BLOOM_RADIUS * k, Color(c.r, c.g, c.b, 0.26 * k), true, -1.0, true)
	draw_circle(at, BIRTH_BLOOM_RADIUS * 0.42 * k, Color(c.r, c.g, c.b, 0.8 * k), true, -1.0, true)
	# An expanding rim: the ripple in the gate's surface the object punched through.
	draw_arc(at, BIRTH_BLOOM_RADIUS * (1.35 - k), 0.0, TAU, 26,
		Color(c.r, c.g, c.b, 0.45 * k), 2.0, true)


## THE OPENING TELL — one per family, in three different visual languages.
##
## This function used to be the clearest evidence for the maker's verdict: every
## family drew the same one-or-two concentric rings, recoloured. Under a big
## shared sigil, that meant the first half-second of a fire storm, an earth storm
## and a void storm were the same picture. Each family now gets a tell built from
## a different PRIMITIVE — a burning horizon, an absence of light, a set of
## vertical tears — so the spell is identifiable before anything has landed, and
## identifiable with the colour drained out.
##
## Everything is drawn at `_spread`, the exact half-extents the strikes are rolled
## within, so the danger area promised by the tell is the danger area used.
func _draw_charge_telegraph(tp: float) -> void:
	var ex: float = _spread.x * (0.55 + 0.45 * tp)
	var ey: float = maxf(_spread.y, 1.0)
	var squash: float = ey / maxf(_spread.x, 1.0)
	match _effect:
		"fire":
			# THE BURNING HORIZON. A wide, low band of heat lying across the whole
			# strike front — the shape says "a broad front is coming", which is
			# what fire's spread actually is. Plus ignition streaks high above,
			# angled along the entry diagonal, so the DIRECTION is legible early.
			var flick: float = 0.06 * sin(_elapsed * 24.0)
			draw_set_transform(_center, 0.0, Vector2(1.0, squash))
			draw_circle(Vector2.ZERO, ex, Color(0.9, 0.28, 0.06, (0.10 + 0.12 * tp)), true, -1.0, true)
			draw_arc(Vector2.ZERO, ex, 0.0, TAU, 56, Color(1.2, 0.5, 0.14, (0.35 + flick) * tp), 2.5, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# Ignition dripping out of the GATE's rim while it charges, so the
			# source of the shower is legible before the first rock is through.
			# These used to hang at a blind -SKY_HEIGHT offset with nothing around
			# them: the capture of the charge beat showed seven stray red ticks
			# floating in an empty void, attached to no object at all.
			if not _gate_points.is_empty():
				var mouth: Vector2 = _gate_points[0]
				for k: int in 9:
					var th: float = float(k) * 2.39 + _elapsed * 1.6
					var rim: Vector2 = Vector2(cos(th), 0.5 * sin(th)) * _gate_radius * 0.86
					var drip: float = 26.0 * tp * (0.5 + 0.5 * absf(sin(_elapsed * 6.0 + float(k))))
					draw_line(mouth + rim, mouth + rim + Vector2(0.0, drip),
						Color(1.3, 0.6, 0.2, 0.3 * tp), 2.0, true)
		"frost":
			# UNREACHABLE from rain() since the frost fork (see the top of rain()).
			# Kept only so a hand-driven caller passing "frost" still draws something.
			draw_arc(_center, ex, 0.0, TAU, 44, Color(0.72, 0.92, 1.0, 0.42 * tp), 2.0, true)
		"earth":
			# THE SHADOW OF THE MASS. Earth's tell emits NO light at all — it is a
			# darkening on the floor plus a low haze of disturbed dust, tightly
			# concentrated. An absence where every other tell is a glow, and the
			# only tell in the kit you read by things getting darker underfoot.
			draw_set_transform(_center, 0.0, Vector2(1.0, squash))
			draw_circle(Vector2.ZERO, ex * 1.05, Color(0.05, 0.04, 0.03, 0.10 + 0.30 * tp), true, -1.0, true)
			draw_circle(Vector2.ZERO, ex * 0.55 * tp, Color(0.03, 0.02, 0.02, 0.35 * tp), true, -1.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# Dust lifting off the ground as the pressure wave arrives ahead of the
			# rock — motion without light.
			for k: int in 9:
				var px: float = _center.x + lerpf(-ex, ex, float(k) / 8.0)
				var lift: float = 14.0 * tp * (0.5 + 0.5 * absf(sin(_elapsed * 5.0 + float(k))))
				draw_line(
					Vector2(px, _center.y), Vector2(px, _center.y - lift),
					Color(0.5, 0.42, 0.3, 0.20 * tp), 1.6, true
				)
		"shadow":
			# THE TEARS. No ground ring, no glow, no falling anything: thin vertical
			# slits prising open in mid-air at RIFT_HEIGHT while the veil takes the
			# light out of the room. The eye is pulled UP and into the gaps, which
			# is the opposite instruction from every other ult in the kit.
			for k: int in 6:
				var fx: float = lerpf(-0.85, 0.85, float(k) / 5.0)
				var p: Vector2 = _center + Vector2(fx * ex, -RIFT_HEIGHT * (0.7 + 0.3 * absf(fx)))
				var h: float = 34.0 * tp * (0.6 + 0.6 * absf(sin(float(k) * 2.7)))
				var w: float = 1.0 + 3.0 * tp * tp
				draw_line(p + Vector2(0.0, -h), p + Vector2(0.0, h),
					Color(0.02, 0.0, 0.04, 0.85 * tp), w + 3.0, true)
				draw_line(p + Vector2(0.0, -h), p + Vector2(0.0, h),
					Color(0.8, 0.35, 1.2, 0.55 * tp), w, true)
		_:
			draw_arc(_center, ex, 0.0, TAU, 44,
				Color(_color.r, _color.g, _color.b, 0.45 * tp), 2.5, true)


## Per-impact-point ground marker. `u` ramps 0 -> 1 across the reaction window.
## Density pass (post-review): with count~11, the old 2–3 stroked arcs PER
## POINT stacked into a screen-filling spirograph that read as a HUD overlay
## and buried the impacts themselves. Every element now gets AT MOST one thin
## stroke; the countdown read comes from FILLED ground-shading that grows and
## darkens toward impact. Same timing window (overhaul rule 2 intact) — only
## the visual volume knob moved. Everything is drawn y-squashed (MARKER_SQUASH)
## so markers are unmistakably floor paint, never floating UI.
func _draw_impact_marker(m: Dictionary, u: float) -> void:
	var at: Vector2 = m["to"]
	var close_r: float = lerpf(METEOR_IMPACT_RADIUS * 1.6, METEOR_IMPACT_RADIUS, u)
	match _effect:
		"fire":
			# Ember heat pooling in the strike spot + ONE closing scorch ring.
			var flick: float = 0.06 * sin(_elapsed * 26.0 + float(m["seed"]) * 7.0)
			draw_set_transform(at, 0.0, MARKER_SQUASH)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.3 + 0.55 * u),
				Color(1.1, 0.4, 0.1, 0.1 + 0.16 * u + flick), true, -1.0, true)
			# Ring kept FAINT: at count~11 even one ring per point stacks up, so
			# the growing ember pool carries the read and the ring only whispers.
			draw_arc(Vector2.ZERO, close_r, 0.0, TAU, 30,
				Color(1.3, 0.6, 0.18, 0.08 + 0.24 * u), 1.3, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"frost":
			# Frost bloom: a rime pool creeps over the ground while a six-armed
			# ice crystal grows in it — the arms ARE the countdown; the single
			# thin ring just marks the true footprint late.
			draw_set_transform(at, 0.0, MARKER_SQUASH)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.25 + 0.6 * u),
				Color(0.65, 0.85, 1.0, 0.08 + 0.12 * u), true, -1.0, true)
			for k: int in 6:
				var dirv: Vector2 = Vector2.from_angle(float(m["seed"]) + TAU * float(k) / 6.0)
				var arm: Vector2 = dirv * METEOR_IMPACT_RADIUS * 0.85 * u
				draw_line(Vector2.ZERO, arm, Color(0.85, 0.97, 1.0, 0.5 * u), 1.5, true)
				var elbow: Vector2 = dirv * METEOR_IMPACT_RADIUS * 0.5 * u
				var side: Vector2 = dirv.orthogonal() * METEOR_IMPACT_RADIUS * 0.18 * u
				draw_line(elbow, elbow + side + dirv * 5.0, Color(0.85, 0.97, 1.0, 0.35 * u), 1.2, true)
				draw_line(elbow, elbow - side + dirv * 5.0, Color(0.85, 0.97, 1.0, 0.35 * u), 1.2, true)
			draw_arc(Vector2.ZERO, METEOR_IMPACT_RADIUS, 0.0, TAU, 30,
				Color(0.8, 0.95, 1.1, 0.35 * u * u), 1.2, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"earth":
			# NO strokes at all: the boulder's shadow is displaced dust — a soft
			# pale smudge at the footprint plus a darkening core that grows as
			# the rock nears. Shading the ground (not outlining it) is what
			# keeps the impact spectacle in front of its own telegraph.
			draw_set_transform(at, 0.0, MARKER_SQUASH)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.45 + 0.55 * u),
				Color(0.58, 0.48, 0.34, 0.11 + 0.17 * u), true, -1.0, true)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * 0.62 * u,
				Color(0.07, 0.05, 0.04, 0.55 * u), true, -1.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"shadow":
			# Void slit: a dark ground tear dilating open with ONE violet rim,
			# plus a few ticks CONVERGING inward — this spot is about to swallow.
			draw_set_transform(at, 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * 0.8 * u,
				Color(0.05, 0.02, 0.1, 0.22 + 0.3 * u), true, -1.0, true)
			draw_arc(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.5 + 0.5 * u), 0.0, TAU, 26,
				Color(0.7, 0.3, 1.1, 0.22 + 0.33 * u), 1.6, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for k: int in 5:
				var dirv2: Vector2 = Vector2.from_angle(float(m["seed"]) + TAU * float(k) / 5.0)
				var reach: float = lerpf(METEOR_IMPACT_RADIUS * 1.5, METEOR_IMPACT_RADIUS * 0.4, u)
				var p0: Vector2 = at + Vector2(dirv2.x, dirv2.y * 0.4) * reach
				var p1: Vector2 = at + Vector2(dirv2.x, dirv2.y * 0.4) * (reach - 9.0)
				draw_line(p0, p1, Color(0.6, 0.28, 0.95, 0.25 + 0.35 * u), 1.4, true)
		_:
			# Generic: a soft tinted pool + ONE closing ring.
			draw_set_transform(at, 0.0, MARKER_SQUASH)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.3 + 0.55 * u),
				Color(_color.r, _color.g, _color.b, 0.07 + 0.13 * u), true, -1.0, true)
			draw_arc(Vector2.ZERO, close_r, 0.0, TAU, 30,
				Color(_color.r, _color.g, _color.b, 0.18 + 0.36 * u), 1.4, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## FIRE in flight: a tumbling molten rock — dark silhouette, HDR glowing
## cracks, a white-hot leading edge — dragging a ragged three-tongue burning
## tail that sheds embers. THE meteor.
func _draw_fire_meteor(m: Dictionary, f: float) -> void:
	var from: Vector2 = m["from"]
	var to: Vector2 = m["to"]
	var pos: Vector2 = from.lerp(to, f)
	var dir: Vector2 = (to - from).normalized()
	var perp: Vector2 = dir.orthogonal()
	var s: float = float(m["seed"])
	# Ragged burning tail: three wavering tongues, widest+dimmest at the back.
	for k: int in 3:
		var tongue_len: float = (58.0 + 16.0 * float(k)) * (0.55 + 0.45 * f)
		var sway: float = sin(_elapsed * (11.0 + 3.0 * float(k)) + s + float(k) * 2.1) * (3.0 + 2.5 * float(k))
		var tail: Vector2 = pos - dir * tongue_len + perp * sway
		var tones: Array = [
			Color(1.0, 0.42, 0.1, 0.28), Color(1.2, 0.6, 0.15, 0.4), Color(1.5, 0.85, 0.3, 0.55),
		]
		draw_line(tail, pos, tones[k], 12.0 - 3.5 * float(k), true)
	# Embers shed along the wake.
	for e: int in 5:
		var back: float = 14.0 + 13.0 * float(e)
		var wob: Vector2 = perp * sin(_elapsed * 17.0 + s + float(e) * 1.7) * (2.0 + float(e))
		draw_circle(pos - dir * back + wob, 2.4 - 0.3 * float(e),
			Color(1.6, 0.7, 0.2, 0.7 - 0.11 * float(e)), true, -1.0, true)
	# Heat halo, then the tumbling rock body with glowing cracks.
	draw_circle(pos, 16.0, Color(1.0, 0.4, 0.12, 0.28), true, -1.0, true)
	var verts: PackedVector2Array = m["verts"]
	draw_set_transform(pos, s + _elapsed * float(m["spin"]), Vector2.ONE)
	draw_colored_polygon(verts, Color(0.26, 0.15, 0.11, 1.0))
	draw_line(verts[0] * 0.7, verts[3] * 0.75, Color(1.7, 0.75, 0.2, 0.9), 1.6, true)
	draw_line(verts[1] * 0.65, verts[4] * 0.7, Color(1.5, 0.55, 0.15, 0.8), 1.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# White-hot leading edge — air friction, HDR so it blooms.
	draw_circle(pos + dir * 7.0, 4.0, Color(1.9, 1.3, 0.6, 0.9), true, -1.0, true)


## FROST in flight: a sheer crystal spear falling point-down — translucent
## faceted body, HDR rim + refractive core line, cold air-streaks instead of
## any burning tail. Reads "javelin", not "rock".
func _draw_ice_spike(m: Dictionary, f: float) -> void:
	var pos: Vector2 = (m["from"] as Vector2).lerp(m["to"], f)
	var s: float = float(m["seed"])
	var spear_len: float = 50.0
	var w: float = 7.5
	draw_set_transform(pos, sin(s) * 0.1, Vector2.ONE)
	var body := PackedVector2Array([
		Vector2(0.0, spear_len * 0.58),           # tip — leading, points DOWN
		Vector2(w, spear_len * 0.1),
		Vector2(w * 0.5, -spear_len * 0.42),
		Vector2(0.0, -spear_len * 0.5),
		Vector2(-w * 0.5, -spear_len * 0.42),
		Vector2(-w, spear_len * 0.1),
	])
	draw_colored_polygon(body, Color(0.6, 0.83, 1.0, 0.5))   # translucent crystal
	var rim: PackedVector2Array = body.duplicate()
	rim.append(body[0])
	draw_polyline(rim, Color(1.2, 1.55, 1.75, 1.0), 1.5, true)  # HDR facet rim
	draw_line(Vector2(0.0, -spear_len * 0.42), Vector2(0.0, spear_len * 0.5),
		Color(1.6, 1.7, 1.85, 0.9), 2.2, true)                  # refractive core
	draw_circle(Vector2(0.0, spear_len * 0.5), 3.0, Color(1.7, 1.8, 1.9, 0.85), true, -1.0, true)  # tip glint
	# Cold air-streaks trailing above — pure speed, no fire.
	draw_line(Vector2(0.0, -spear_len * 0.6), Vector2(0.0, -spear_len * 1.15),
		Color(0.75, 0.92, 1.0, 0.3), 2.5, true)
	draw_line(Vector2(w * 0.6, -spear_len * 0.5), Vector2(w * 0.6, -spear_len * 0.95),
		Color(0.75, 0.92, 1.0, 0.18), 1.5, true)
	draw_line(Vector2(-w * 0.6, -spear_len * 0.5), Vector2(-w * 0.6, -spear_len * 0.95),
		Color(0.75, 0.92, 1.0, 0.18), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## EARTH in flight: a big dumb boulder — flat opaque rock tones, hard tumble,
## NO tail (a whisper of falling dust only). Mass, not energy.
func _draw_earth_boulder(m: Dictionary, f: float) -> void:
	var pos: Vector2 = (m["from"] as Vector2).lerp(m["to"], f)
	var verts: PackedVector2Array = m["verts"]
	# A dusty speed-smear behind (NOT a burning tail — displaced air + grit),
	# so the dark mass separates from the dark sky while it falls.
	var up: Vector2 = ((m["from"] as Vector2) - (m["to"] as Vector2)).normalized()
	draw_line(pos + up * 16.0, pos + up * 52.0, Color(0.62, 0.52, 0.38, 0.22), 9.0, true)
	draw_line(pos + up * 16.0, pos + up * 38.0, Color(0.72, 0.6, 0.44, 0.18), 4.0, true)
	draw_set_transform(pos, float(m["seed"]) + _elapsed * float(m["spin"]), Vector2.ONE)
	# Lit rock: warm mid-tone body + sun-side highlight facet + dark under-edge.
	# The old 0.45/0.35/0.23 fill vanished against the dark arena sky.
	draw_colored_polygon(verts, Color(0.56, 0.45, 0.31, 1.0))
	var highlight := PackedVector2Array([
		verts[0] * 0.9, verts[1] * 0.9, verts[2] * 0.55, Vector2.ZERO,
	])
	draw_colored_polygon(highlight, Color(0.74, 0.62, 0.44, 1.0))
	var outline: PackedVector2Array = verts.duplicate()
	outline.append(verts[0])
	draw_polyline(outline, Color(0.24, 0.18, 0.12, 1.0), 1.8, true)
	# Facet lines so the rock reads 3D while it tumbles.
	draw_line(verts[1] * 0.85, verts[4] * 0.8, Color(0.3, 0.23, 0.15, 0.8), 1.2, true)
	draw_line(verts[2] * 0.8, verts[5] * 0.85, Color(0.78, 0.66, 0.48, 0.7), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d: int in 3:
		var dust: Vector2 = pos + up * (20.0 + 13.0 * float(d)) + Vector2(
			sin(_elapsed * 9.0 + float(d) * 2.2 + float(m["seed"])) * 5.0, 0.0)
		draw_circle(dust, 2.6, Color(0.68, 0.57, 0.42, 0.2), true, -1.0, true)


## SHADOW in flight: nothing falls from the sky. A lens-shaped TEAR rips open
## low above the mark (violet HDR rim around a void interior, reality-cracks
## converging into it), then a column of void slams down to the ground.
func _draw_shadow_rift(m: Dictionary, f: float) -> void:
	var to: Vector2 = m["to"]
	var rift: Vector2 = m["from"]  # = to + (0, -RIFT_HEIGHT), see _spawn_point
	var s: float = float(m["seed"])
	var open_f: float = clampf(f / RIFT_OPEN_FRAC, 0.0, 1.0)
	var half_w: float = 42.0 * open_f
	if half_w > 0.5:
		# A soft darkness halo BEHIND the tear — the air dims around a wound
		# in reality, which sells "hole", not "purple ellipse".
		draw_circle(rift, half_w * 1.5, Color(0.03, 0.01, 0.07, 0.35 * open_f), true, -1.0, true)
		draw_set_transform(rift, sin(s) * 0.15, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, half_w, Color(0.02, 0.0, 0.05, 0.95), true, -1.0, true)
		draw_arc(Vector2.ZERO, half_w, 0.0, TAU, 32, Color(1.1, 0.5, 1.6, 0.95), 2.6, true)
		draw_arc(Vector2.ZERO, half_w * 0.8, 0.0, TAU, 28, Color(0.6, 0.25, 1.0, 0.5), 1.4, true)
		# The rim SEETHES: a bright HDR glint racing around the edge.
		var glint: Vector2 = Vector2.from_angle(_elapsed * 9.0 + s) * half_w
		draw_circle(glint, 2.6, Color(1.5, 1.0, 1.8, 0.9), true, -1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Motes + reality-cracks being SUCKED into the tear while it opens.
	if f < RIFT_OPEN_FRAC + 0.1:
		for k: int in 8:
			var dirv: Vector2 = Vector2.from_angle(s + TAU * float(k) / 8.0)
			var pull: float = fposmod(_elapsed * 1.8 + float(k) * 0.37, 1.0)
			var reach: float = lerpf(64.0, 8.0, pull)
			var mote: Vector2 = rift + Vector2(dirv.x, dirv.y * 0.55) * reach
			draw_line(mote, mote + Vector2(dirv.x, dirv.y * 0.55) * -10.0,
				Color(0.75, 0.38, 1.1, (0.2 + 0.5 * open_f) * (1.0 - pull * 0.4)), 1.6, true)
			draw_circle(mote, 1.8, Color(0.9, 0.55, 1.3, (0.3 + 0.5 * open_f) * pull), true, -1.0, true)
	# The drop: a void column slams from the tear to the ground.
	if f > RIFT_OPEN_FRAC:
		var t2: float = (f - RIFT_OPEN_FRAC) / (1.0 - RIFT_OPEN_FRAC)
		var tip: Vector2 = rift.lerp(to, t2)
		draw_line(rift, tip, Color(0.07, 0.02, 0.13, 0.9), 15.0, true)
		draw_line(rift, tip, Color(0.5, 0.2, 0.8, 0.7), 7.0, true)
		draw_line(rift, tip, Color(1.2, 0.7, 1.7, 0.9), 2.5, true)  # HDR seam


## Fallback in-flight draw (non-bespoke effects): the classic head + trail.
func _draw_generic_meteor(m: Dictionary, f: float) -> void:
	var from: Vector2 = m["from"]
	var to: Vector2 = m["to"]
	var pos: Vector2 = from.lerp(to, f)
	var trail: Vector2 = from.lerp(to, maxf(f - 0.38, 0.0))
	var c: Color = _color
	var inner: Color = _trail_inner_color()
	var core: Color = _effect_core_color()
	draw_line(trail, pos, Color(c.r, c.g, c.b, 0.5), 10.0, true)
	draw_line(trail, pos, Color(inner.r, inner.g, inner.b, 0.7), 4.0, true)
	draw_circle(pos, 13.0, Color(c.r, c.g, c.b, 0.4), true, -1.0, true)
	draw_circle(pos, 8.0, Color(c.r, c.g, c.b, 0.95), true, -1.0, true)
	draw_circle(pos, 4.5, core, true, -1.0, true)


## Bright inner-trail tint (generic template only).
func _trail_inner_color() -> Color:
	match _effect:
		"arcane":
			return Color(1.0, 0.85, 1.0)
		"holy":
			return Color(1.0, 0.99, 0.85)
		"lightning":
			return Color(1.0, 1.0, 0.75)
		"wind":
			return Color(0.8, 1.0, 0.95)
		_:
			return Color(1.0, 0.9, 0.6)


## Hot-core tint (generic template only). HDR cores bloom.
func _effect_core_color() -> Color:
	match _effect:
		"arcane":
			return Color(1.7, 1.5, 1.7, 1.0)
		"holy":
			return Color(1.75, 1.75, 1.5, 1.0)
		"lightning":
			return Color(1.9, 1.7, 0.9, 1.0)
		"wind":
			return Color(1.35, 1.85, 1.7, 1.0)
		_:
			return Color(1.8, 1.6, 1.2, 1.0)


## ---------------------------------------------------------------------------
## Residue nodes. Inner classes so this redesign stays inside ONE file (other
## spell files are being edited in parallel). All are parented to the ARENA at
## spawn so they outlive the sigil node, and use NO autoloads (pure draw +
## the headless-safe CombatVfx/DebrisChunk statics), matching ScorchDecal.


## FIRE residue: a pool of embers that keeps flickering after the blast — the
## "the ground is still burning" beat that a one-shot burst can't sell.
class EmberPool extends Node2D:
	const LIFE: float = 2.8

	var radius: float = 30.0
	var _age: float = 0.0
	var _embers: Array = []  # each: {pos, size, phase}

	static func spawn(parent: Node, world_pos: Vector2, pool_radius: float) -> void:
		if parent == null or not parent.is_inside_tree():
			return
		var pool := EmberPool.new()
		pool.radius = pool_radius
		pool.z_index = -1  # embers sit ON the floor, under the fighters
		parent.add_child(pool)
		pool.global_position = world_pos

	func _ready() -> void:
		for i: int in 9:
			_embers.append({
				# Squash y so the pool hugs the ground plane like the crater/decals.
				"pos": Vector2.from_angle(randf() * TAU) * (sqrt(randf()) * radius) * Vector2(1.0, 0.5),
				"size": randf_range(1.6, 3.4),
				"phase": randf() * TAU,
			})

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade: float = 1.0 - smoothstep(0.55, 1.0, _age / LIFE)
		if fade <= 0.01:
			return
		# Low heat-glow over the scorch, then the individual winking embers.
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.35, 0.08, 0.07 * fade), true, -1.0, true)
		for e: Dictionary in _embers:
			var flick: float = 0.5 + 0.5 * sin(_age * 9.0 + float(e["phase"]))
			var a: float = (0.35 + 0.6 * flick) * fade
			var p: Vector2 = e["pos"]
			draw_circle(p, float(e["size"]) * (0.8 + 0.3 * flick),
				Color(1.6, 0.55, 0.12, a * 0.8), true, -1.0, true)
			draw_circle(p, float(e["size"]) * 0.45, Color(1.9, 1.1, 0.4, a), true, -1.0, true)  # HDR heart


## FROST residue: the speared-in crystal cluster — stands as jagged ice for a
## beat (the spike's whole identity: it PLANTS, it doesn't splash), then
## shatters into flying fragments + a frost burst.
class IceSpikeCluster extends Node2D:
	const STAND_TIME: float = 0.6
	const SHATTER_TIME: float = 0.24
	const EMERGE_TIME: float = 0.09  # spear-in pop: scale up fast, don't blink in

	var _age: float = 0.0
	var _shattered: bool = false
	var _spears: Array = []  # each: {off, len, hw, tilt}
	var _frags: Array = []   # each: {dir, speed, size, spin}

	static func spawn(parent: Node, world_pos: Vector2) -> void:
		if parent == null or not parent.is_inside_tree():
			return
		var cluster := IceSpikeCluster.new()
		parent.add_child(cluster)
		cluster.global_position = world_pos

	func _ready() -> void:
		for i: int in 3:
			_spears.append({
				"off": Vector2(float(i - 1) * randf_range(7.0, 11.0), randf_range(-2.0, 2.0)),
				"len": randf_range(34.0, 52.0) * (1.0 if i == 1 else 0.72),  # center spear tallest
				"hw": randf_range(4.0, 6.5),
				"tilt": float(i - 1) * randf_range(0.14, 0.24),
			})
		for i: int in 10:
			_frags.append({
				"dir": Vector2.from_angle(randf_range(-PI, 0.0)),  # upward half only
				"speed": randf_range(60.0, 170.0),
				"size": randf_range(2.0, 4.2),
				"spin": randf_range(-9.0, 9.0),
			})

	func _process(delta: float) -> void:
		_age += delta
		if _age >= STAND_TIME and not _shattered:
			_shattered = true
			# The shatter beat: a frost burst + a couple of physical ice chips.
			CombatVfx.spawn_burst(
				get_parent(), global_position, Color(0.9, 0.98, 1.0, 0.95),
				Color(0.7, 0.9, 1.0, 0.0), 22, 0.4, 120.0, 300.0, 0.6, 1.6, 2.5, 5.0, true
			)
			DebrisChunk.spawn_burst(get_parent(), global_position,
				Color(0.72, 0.86, 0.95), 3, Vector2.UP, 200.0)
		if _age >= STAND_TIME + SHATTER_TIME:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		if not _shattered:
			_draw_standing()
		else:
			_draw_fragments()

	func _draw_standing() -> void:
		var pop: float = clampf(_age / EMERGE_TIME, 0.0, 1.0)  # spear-in growth
		var glint: float = 0.75 + 0.25 * sin(_age * 13.0)
		for sp: Dictionary in _spears:
			var off: Vector2 = sp["off"]
			var spear_len: float = float(sp["len"]) * pop
			var hw: float = sp["hw"]
			draw_set_transform(off, float(sp["tilt"]), Vector2.ONE)
			var body := PackedVector2Array([
				Vector2(0.0, -spear_len),        # crystal tip points UP now
				Vector2(hw, -spear_len * 0.25),
				Vector2(hw * 0.7, 2.0),
				Vector2(-hw * 0.7, 2.0),
				Vector2(-hw, -spear_len * 0.25),
			])
			draw_colored_polygon(body, Color(0.55, 0.8, 1.0, 0.42))
			var rim: PackedVector2Array = body.duplicate()
			rim.append(body[0])
			draw_polyline(rim, Color(1.15, 1.5, 1.7, 0.85 * glint), 1.3, true)
			draw_line(Vector2(0.0, 0.0), Vector2(0.0, -spear_len * 0.92),
				Color(1.4, 1.6, 1.8, 0.5 * glint), 1.4, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_fragments() -> void:
		var t: float = (_age - STAND_TIME) / SHATTER_TIME
		var a: float = 1.0 - t
		for fr: Dictionary in _frags:
			var p: Vector2 = (fr["dir"] as Vector2) * float(fr["speed"]) * t * SHATTER_TIME * 4.0
			p.y += 220.0 * t * t * SHATTER_TIME  # gravity pulls the chips back down
			var fs: float = fr["size"]
			var rot: float = float(fr["spin"]) * t
			var tri := PackedVector2Array([
				p + Vector2(0.0, -fs).rotated(rot),
				p + Vector2(fs * 0.8, fs * 0.6).rotated(rot),
				p + Vector2(-fs * 0.8, fs * 0.6).rotated(rot),
			])
			draw_colored_polygon(tri, Color(0.8, 0.93, 1.0, 0.7 * a))


## SHADOW impact: the IMPLOSION — rings and streaks CONVERGE onto the point
## (the exact inverse of every other element's outward burst), then the
## collapse snaps to a single HDR violet star and blinks out.
class VoidImplosion extends Node2D:
	const LIFE: float = 0.5
	const COLLAPSE_FRAC: float = 0.66  # converge for 2/3, flash out for 1/3

	var radius: float = 48.0
	var _age: float = 0.0
	var _seeds: PackedFloat32Array = PackedFloat32Array()

	static func spawn(parent: Node, world_pos: Vector2, impact_radius: float) -> void:
		if parent == null or not parent.is_inside_tree():
			return
		var imp := VoidImplosion.new()
		imp.radius = impact_radius
		imp.z_index = 40
		parent.add_child(imp)
		imp.global_position = world_pos

	func _ready() -> void:
		for i: int in 10:
			_seeds.append(randf() * TAU)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _age / LIFE
		if t < COLLAPSE_FRAC:
			var tt: float = t / COLLAPSE_FRAC
			var ease_in: float = tt * tt  # accelerating collapse — gravity, not a fade
			var rr: float = lerpf(radius * 1.5, radius * 0.12, ease_in)
			draw_circle(Vector2.ZERO, radius * 0.5 * (1.0 - 0.6 * tt),
				Color(0.05, 0.01, 0.1, 0.75), true, -1.0, true)
			draw_arc(Vector2.ZERO, rr, 0.0, TAU, 30,
				Color(0.8, 0.35, 1.3, 0.5 + 0.4 * tt), 2.5, true)
			draw_arc(Vector2.ZERO, rr * 1.35, 0.0, TAU, 30,
				Color(0.6, 0.25, 1.0, 0.3 + 0.2 * tt), 1.5, true)
			for i: int in 10:
				var dirv: Vector2 = Vector2.from_angle(_seeds[i])
				var p_out: Vector2 = dirv * lerpf(radius * 1.7, radius * 0.15, ease_in)
				draw_line(p_out, p_out - dirv * 14.0 * (1.0 - tt * 0.5),
					Color(0.9, 0.5, 1.4, 0.6), 1.6, true)
		else:
			var t2: float = (t - COLLAPSE_FRAC) / (1.0 - COLLAPSE_FRAC)
			# The snap: one HDR violet star + a thin escaping ring — the only
			# outward element, and it's light, not matter.
			draw_circle(Vector2.ZERO, lerpf(3.0, radius * 0.45, t2),
				Color(1.4, 0.9, 1.8, (1.0 - t2) * 0.9), true, -1.0, true)
			draw_arc(Vector2.ZERO, radius * (0.3 + 0.9 * t2), 0.0, TAU, 30,
				Color(0.9, 0.5, 1.4, (1.0 - t2) * 0.5), 1.5, true)
