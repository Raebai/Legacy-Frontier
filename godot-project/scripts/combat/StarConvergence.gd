class_name StarConvergence
extends Node2D

## Who this convergence's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## THE SIEGE — the ult that arrives from OFF-SCREEN, from every direction at once.
##
## IDENTITY (maker, mid-playtest: "most ults look the same — just are recolours or
## retypes of the same meteor type of thing"). The failure this is designed
## against is that every big spell resolved as "bright things converge on a marked
## circle, then a flash and a shockwave". So the axes here are deliberately the
## ones NOTHING else in the kit uses:
##   * DIRECTION  — INWARD, from beyond the edge of the frame. Judgment falls, the
##                  Colossus erupts, the bombardment sweeps across, the nova pushes
##                  out. This one CLOSES IN. It is the only spell whose motion
##                  begins in the player's peripheral vision.
##   * TIMING     — the longest, slowest, most dreadful build in the game (1.30 s
##                  of tell) collapsing into ONE overwhelming instant. A long ramp
##                  into a single frame, where the bombardment is a rhythm of many
##                  small beats and the nova is an instant with no ramp at all.
##   * EYE        — starts at eight points spread around the screen EDGE and drags
##                  the eye inward to one point. Every other ult tells you where to
##                  look immediately; this one takes your attention away from the
##                  centre and then yanks it back.
##   * SCREEN     — the camera PULLS WIDE during the wind-up (so you can actually
##                  see the ring closing) and PUNCHES IN on the hit. That
##                  reveal-then-slam pairing is this spell's alone; nothing else
##                  touches the zoom during its telegraph.
##   * RESIDUE    — a radial STARBURST of scorch spokes running outward along the
##                  lance paths. No other spell leaves a directional scar; round
##                  craters and blobs of scorch belong to the things that fall.
##
## ⚠ THERE IS DELIBERATELY NO MAGIC CIRCLE HERE ANY MORE. It used to open a sky
## sigil, and that is the single biggest reason the ults read as one another: FIVE
## of the seven opened with the same hexagram, at the same size, in the same place
## — and the sigil is the biggest, brightest object on screen during exactly the
## beat the player has the most time to study it. The telegraph is now the RING OF
## LANCES itself, which is unique to this spell and also tells the truth about
## which direction the danger is coming from.
##
## Radius damage on the nova footprint (`targets_in_radius`, pure/testable);
## `converge()` drives the timeline. Procedural, no assets.

# ── timing ───────────────────────────────────────────────────────────────────
## THE DODGE BUDGET: CHARGE_TIME + CONVERGE_TIME = 1.30 s from the first visible
## mark to the hit. The longest telegraph in the game ON PURPOSE — this is also
## the biggest single hit, and the house rule is that more spectacle must buy MORE
## counterplay, not less. Both halves are readable: the charge shows the true
## footprint and the eight ignition points, the converge shows the lances actually
## travelling. UNTESTED GUESS — if it drags, shorten CONVERGE_TIME first (the
## lances moving is the exciting half; the static charge is the fair half).
const CHARGE_TIME: float = 0.70     # ignition: the ring lights, the ground marks
const CONVERGE_TIME: float = 0.60   # the lances visibly rush inward
const DODGE_WINDOW: float = CHARGE_TIME + CONVERGE_TIME
const IMPACT_HOLD: float = 0.12
const FADE_TIME: float = 0.55       # long quiet aftermath (contrast to the snap)

# ── geometry ─────────────────────────────────────────────────────────────────
## How far out the lances ignite. Beyond the combat camera's framing on purpose:
## they must enter FROM off-screen, which is what makes the arrival read as a
## siege rather than as a firework. UNTESTED GUESS.
const RING_RADIUS: float = 520.0
const LANCE_COUNT: int = 8
## Fraction of its run that a lance draws as a bright streak. A SHORT streak reads
## as an object travelling fast; a long one reads as a static spoke being drawn.
const LANCE_STREAK: float = 0.30
const DEFAULT_RADIUS: float = 160.0
const DEFAULT_DAMAGE: int = 130
const KNOCKBACK: float = 380.0

# ── residue ──────────────────────────────────────────────────────────────────
## The starburst scar: scorch dropped along each lance path so the ground
## afterwards records the SHAPE of what hit it. Reach is a fraction of `_radius`,
## never of RING_RADIUS — a scar stretching out to the ignition ring would imply
## the spell damaged an area 3x wider than it did. UNTESTED GUESSES.
const SCAR_SPOKES: int = 8
const SCAR_STEPS: int = 3
const SCAR_REACH: float = 1.0       # x _radius — the scar ends ON the footprint
const SCAR_LIFETIME: float = 9.0

var _ground: Vector2 = Vector2.ZERO
var _color: Color = Color(1.0, 0.86, 0.4, 1.0)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var _effect: String = "holy"
var _elapsed: float = -1.0
var _detonated: bool = false
## Elemental ailment (Elements.Element) applied to enemies the nova hits. -1=none.
var element_id: int = -1

## WHO CAST THIS. `SpellCaster._stamp` has always written this name onto every
## spectacle it builds, but this file never declared it — and `set()` on an
## undeclared property is a silent no-op, so the write went nowhere. That cost
## nothing while a hero's spells scanned `"enemy"` (the caster was never in that
## group) and became a SELF-KILL the moment friendly fire pointed them at the
## shared `"mortal"` group. Declaring it is what arms `SpellTargets.hostiles()` /
## `SpellTargets.owner_of()`, which is where the exclusion is now enforced.
var caster_node: Node = null


## Public entry: converge on `target`, dealing `damage` over `radius`.
func converge(
	target: Vector2, color: Color = Color(1.0, 0.86, 0.4),
	radius: float = DEFAULT_RADIUS, damage: int = DEFAULT_DAMAGE,
	effect: String = "holy",
) -> void:
	_ground = target
	_color = color
	_radius = radius
	_damage = damage
	_effect = effect
	_elapsed = 0.0
	# THE REVEAL. Pull the camera wide for the whole wind-up so the closing ring is
	# actually on screen — a convergence you cannot see converging is just a flash.
	# This is the only spell that touches the zoom during its TELEGRAPH instead of
	# at its impact, and that is precisely the point of difference.
	Juice.zoom_pull_camera(0.30, DODGE_WINDOW * 0.75, 0.18, 0.45)
	Sfx.play("charge_up", -4.0, 0.05)  # a rising note, not the radiant chord
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if not _detonated and _elapsed >= DODGE_WINDOW:
		_detonate()
	if _elapsed >= DODGE_WINDOW + IMPACT_HOLD + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## The lances slam together: radius damage once at the point + the biggest juice
## in the kit (this is the finisher).
func _detonate() -> void:
	_detonated = true
	var at: Vector2 = _ground
	# Silhouette-aware + line-of-sight selection. The LOS half matters here beyond
	# the usual "no damage through walls": a bare circle also reaches `_radius`
	# straight DOWN through the floor, into whatever is standing in the room
	# underneath. `filter_reachable` (inside `SpellTargets`) is what stops that.
	for enemy: Node in SpellTargets.in_radius(
			at, _radius, get_tree().get_nodes_in_group(target_group),
			[caster_node], self):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - at).normalized()
			enemy.apply_knockback((away if away != Vector2.ZERO else Vector2.UP) * KNOCKBACK)
	for prop: Node in SpellTargets.in_radius(
			at, _radius, get_tree().get_nodes_in_group("destructible"), [], self):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)
	_impact_burst(at)
	_burn_starburst(at)
	# The finisher CRATERS the ground + throws rubble.
	GroundCrater.spawn(get_parent(), at, _radius * 0.7, true)
	DebrisChunk.spawn_burst(get_parent(), at, Color(0.3, 0.26, 0.22), 18, Vector2.UP, 320.0)
	# THE SLAM half of the reveal-then-slam pairing. The wide pull from converge()
	# is still easing back, so the punch lands against a wide frame and reads as
	# the world snapping shut.
	Juice.hit_stop(0.12)
	Juice.shake_camera(24.0)
	Juice.zoom_punch_camera(0.16, 0.30)
	PostProcess.shock(1.1, Juice.world_to_uv(at))  # ripple centred ON the hit
	Sfx.play("ult_siege", 2.0, 0.06)
	# ⚠ `Juice.impact_frame` — THE WHITE BLOW-OUT — IS STILL DELIBERATELY NOT CALLED
	# HERE, and the reason is the single most important note on this spell.
	#
	# It used to fire at strength 1.4. Rendered and looked at, the result was that
	# for ~0.2 s — the exact window in which a player identifies WHICH ult just
	# went off — the entire screen became the same white rectangle full of the same
	# radial speed lines that every other big spell also ended with. The most
	# identity-bearing moment of each ult was the moment they were most identical,
	# which is a large part of the "they're all recolours" verdict. Turning it down
	# to 0.55 was tried first and was still washing the frame pale grey.
	#
	# The last line of that note used to read "it is just no longer this spell's
	# ending, because it was everybody's ending" — and the sentence immediately
	# above it named the actual fix without noticing: *the eight-spoke wheel is
	# readable against a DARK screen and unreadable against a white one.* So this
	# spell now gets the frame it always wanted, which is the BLACK one.
	# `ImpactFrame.Style.SILHOUETTE` drops the screen out instead of blowing it
	# up, and the eight burning lance paths and the footprint ring — the things
	# that make this ult identifiably THIS ult — are exactly what is left lit.
	#
	# `lines: false` because this spell draws its own eight spokes; the style's
	# generic wedges would sit on top of them and turn a specific shape back into
	# a generic one, which is the original bug wearing a different colour.
	Juice.frame({
		"style": ImpactFrame.Style.SILHOUETTE, "strength": 1.25, "at": at,
		"lines": false, "zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
	})


## The starburst scar: scorch dropped in a line along each lance's final approach,
## so the ground afterwards remembers that this was a RADIAL event. Each sample is
## snapped to the floor beneath it (never floating in the sky, never buried inside
## rock), and a spoke STOPS at the first sample with no floor under it — so one
## that runs off the lip of a platform simply ends there.
func _burn_starburst(at: Vector2) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var tint := Color(0.09, 0.06, 0.03, 0.55)
	for i: int in SCAR_SPOKES:
		var dirv: Vector2 = Vector2.from_angle(TAU * float(i) / float(SCAR_SPOKES))
		for s: int in SCAR_STEPS:
			var f: float = (float(s) + 1.0) / float(SCAR_STEPS)
			var probe: Vector2 = at + dirv * _radius * SCAR_REACH * f
			var g: Dictionary = SpellWorld.floor_below(probe, 90.0, [], self)
			if not bool(g["hit"]):
				break  # ran off the edge of the world — the spoke stops here
			ScorchDecal.spawn(
				host, g["position"], _radius * 0.16 * (1.2 - f), "scorch",
				tint, SCAR_LIFETIME
			)


## Big radiant nova spray at the point (holy character; scaled up for the finisher).
func _impact_burst(at: Vector2) -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(1.0, 0.99, 0.9, 0.98), fade,
		64, 0.7, 120.0, 380.0, 1.5, 4.0, 1.0, 2.5, true
	)


## Pure geometry (testable): nodes within `radius` of `center`.
##
## Kept as a static so `slice4_test_spells` can pin the boundary without a physics
## world, but the body now delegates to the shared selector, so the game has ONE
## definition of "inside the blast" instead of the seven copy-pasted ones this
## used to be part of. `require_los = false` because this overload asks the pure
## SHAPE question; the live path in `_detonate()` asks the cover question too. For
## a target with no drawn silhouette (a crate, a bolt, a test stub) `SpellTargets`
## falls back to exactly the `global_position` distance test that used to be
## written out here, so the pinned boundary is byte-identical.
static func targets_in_radius(center: Vector2, radius: float, nodes: Array) -> Array:
	return SpellTargets.in_radius(center, radius, nodes, [], null, false)


func _draw() -> void:
	if _elapsed < 0.0:
		return
	var c: Color = _color
	if _elapsed < CHARGE_TIME:
		_draw_charge(c)
		return
	if _elapsed < DODGE_WINDOW:
		_draw_converge(c)
		return
	_draw_impact(c)


## Charge tell: the true footprint on the ground, plus eight ignition points far
## out on the ring with their approach corridors already sketched inward.
##
## ⚠ THE FOOTPRINT RING NOW SETTLES AT EXACTLY `_radius`. It used to grow to
## `_radius * 0.9` and stop, so for the spell's entire wind-up the telegraph
## UNDER-STATED the damage radius by 10% — a player who read the ring correctly
## and stood just outside it was hit anyway. The ring is a promise; it has to be
## the same number the damage query uses.
func _draw_charge(c: Color) -> void:
	var tp: float = _elapsed / CHARGE_TIME
	# Footprint: grows to the true radius, then holds there and brightens.
	var fr: float = _radius * clampf(0.45 + 0.55 * (tp * 1.35), 0.0, 1.0)
	draw_arc(_ground, fr, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.30 + 0.35 * tp), 2.5, true)
	# Ignition points brighten and swell where the lances will come from, each
	# dragging a faint guide line inward so the eight approach corridors are
	# legible BEFORE anything starts moving.
	for i: int in LANCE_COUNT:
		var ang: float = TAU * float(i) / float(LANCE_COUNT)
		var pos: Vector2 = _ground + Vector2.from_angle(ang) * RING_RADIUS
		var inward: Vector2 = (_ground - pos).normalized()
		draw_line(pos, pos + inward * RING_RADIUS * 0.30 * tp,
			Color(c.r, c.g, c.b, 0.10 + 0.18 * tp), 1.5, true)
		# A hard pulse in the last third: the "it is about to go" beat.
		var pulse: float = 1.0 + 1.8 * maxf(tp - 0.66, 0.0) * absf(sin(_elapsed * 26.0))
		draw_circle(pos, (2.5 + 4.0 * tp) * pulse,
			Color(1.0, 1.0, 0.95, 0.35 + 0.5 * tp), true, -1.0, true)


## Convergence: eight lances streak inward from beyond the frame, accelerating.
## The bright streak body is SHORT (LANCE_STREAK) so each reads as an object
## travelling rather than as a spoke being drawn outward.
func _draw_converge(c: Color) -> void:
	var f: float = clampf((_elapsed - CHARGE_TIME) / CONVERGE_TIME, 0.0, 1.0)
	var eased: float = f * f * f  # hard acceleration — slow, slow, then gone
	for i: int in LANCE_COUNT:
		var ang: float = TAU * float(i) / float(LANCE_COUNT)
		var start: Vector2 = _ground + Vector2.from_angle(ang) * RING_RADIUS
		var head: Vector2 = start.lerp(_ground, eased)
		var tail: Vector2 = start.lerp(_ground, maxf(eased - LANCE_STREAK, 0.0))
		draw_line(tail, head, Color(c.r, c.g, c.b, 0.40), 9.0, true)           # soft body
		draw_line(tail, head, Color(1.7, 1.6, 1.35, 0.85), 3.5, true)          # HDR core
		draw_circle(head, 6.0, Color(1.75, 1.75, 1.6, 0.9), true, -1.0, true)  # head
	# The footprint stays visible the whole way in: the dodge information must not
	# vanish the moment the scary part starts.
	draw_arc(_ground, _radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.55), 2.5, true)
	# The point charges as they close.
	draw_circle(_ground, _radius * 0.14 * eased, Color(c.r, c.g, c.b, 0.5 * eased), true, -1.0, true)


## Impact: one hard instant, then a quiet fade.
##
## ⚠ THE EXPANDING RINGS ARE NOW BOUNDED TO THE FOOTPRINT. They used to sweep out
## to ~2.6x `_radius`, so the visible shockwave washed straight over bodies that
## took nothing — the mirror image of the "damage got out of the radius" bug, and
## just as hard to read. Everything drawn here now stops at or just inside the
## circle the damage query actually used, and the hard ring at exactly `_radius`
## is the honest statement of the footprint.
func _draw_impact(c: Color) -> void:
	var local: float = _elapsed - DODGE_WINDOW
	var intensity: float
	if local < IMPACT_HOLD:
		intensity = 1.0 if local > 0.04 else local / 0.04
	else:
		intensity = clampf(1.0 - (local - IMPACT_HOLD) / FADE_TIME, 0.0, 1.0)
	if intensity <= 0.01:
		return
	var t: float = clampf(local / (IMPACT_HOLD + FADE_TIME), 0.0, 1.0)
	# A true flash: punches once at the moment of impact, then gone fast.
	var flash: float = clampf(1.0 - local / 0.13, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(_ground, _radius * (0.9 + 0.25 * flash), Color(1.15, 1.12, 1.0, 0.16 * flash), true, -1.0, true)
	draw_circle(_ground, _radius * (0.45 + 0.35 * intensity), Color(1.7, 1.65, 1.5, 0.5 * intensity), true, -1.0, true)
	draw_circle(_ground, _radius * 0.26 * intensity, Color(1.9, 1.9, 1.7, 0.8 * intensity), true, -1.0, true)
	# The footprint line — hardest at the instant of the hit, so the player can see
	# exactly what the spell claimed.
	draw_arc(_ground, _radius, 0.0, TAU, 64, Color(1.7, 1.65, 1.5, 0.85 * intensity), 3.0, true)
	# Two rings settling INSIDE the footprint rather than sweeping past it.
	for k: int in 2:
		var rr: float = _radius * lerpf(0.35 + 0.2 * float(k), 0.98, t)
		draw_arc(_ground, rr, 0.0, TAU, 56, Color(c.r, c.g, c.b, (0.6 - 0.2 * float(k)) * intensity), lerpf(6.0, 1.0, t), true)
	# The eight lance paths glow on the ground for a beat: the SHAPE of what hit
	# you, held long enough to survive the flash. This is the read that makes the
	# spell identifiable in a clip with the colour drained out.
	for i: int in LANCE_COUNT:
		var dirv: Vector2 = Vector2.from_angle(TAU * float(i) / float(LANCE_COUNT))
		draw_line(
			_ground + dirv * _radius * 0.15, _ground + dirv * _radius,
			Color(1.6, 1.5, 1.25, 0.5 * intensity), lerpf(7.0, 1.0, t), true
		)
