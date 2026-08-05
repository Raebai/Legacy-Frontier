class_name DivineRay
extends Node2D

## Who this ray's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## THE VERDICT — the ult that is one instantaneous vertical LINE, and then a burn
## that will not go away.
##
## IDENTITY (maker, mid-playtest: "most ults look the same — just are recolours or
## retypes of the same meteor type of thing"). The axes that separate this from
## the rest of the kit are TIMING and STILLNESS, not palette:
##   * DIRECTION  — strictly vertical, sky to ground, full screen height. The
##                  Siege closes in horizontally, the bombardment sweeps across on
##                  a diagonal, the nova pushes out along the floor. This is the
##                  only ult that is a single clean vertical.
##   * TIMING     — a long MOTIONLESS tell, then a SNAP, then a long slow burn
##                  down. Nothing else in the kit holds still while it threatens,
##                  and nothing else lingers afterwards: the aftermath here is
##                  3.5x longer than the hit that caused it, so a Verdict is
##                  still visibly cooling on screen a second later.
##   * EYE        — travels DOWN a line. Every other ult asks the eye to watch a
##                  patch of ground.
##   * SCREEN     — a downward camera kick (`kick_camera`), which no other spell
##                  uses, instead of the shared zoom-punch.
##   * RESIDUE    — none. Pure light leaves nothing but the afterimage. Craters
##                  and scorch belong to the things made of rock and fire.
##
## ⚠ THE SKY MAGIC CIRCLE IS GONE, DELIBERATELY. It used to open a sigil overhead,
## and that sigil was the single biggest cause of the "they all look the same"
## verdict: five of the seven ults opened with the same hexagram at the same size
## in the same place, and it is the brightest object on screen during the beat the
## player has longest to study. The tell here is now a HAIRLINE THREAD hanging
## dead still in the exact column the pillar will occupy — unique in the kit, and
## strictly more informative than a circle floating above the action.
##
## Damage matches what is DRAWN: the bright column (a vertical capsule) plus the
## ground footprint disc. `targets_in_radius` stays as the pure/testable primitive;
## `strike()` drives the timeline. Instantiate .new(), add to the arena, call
## strike().
##
## The trailing `effect` param picks the elemental CHARACTER
## ("holy" | "frost" | "fire" | "arcane" | ...) — same pillar silhouette,
## distinct palette + impact.
##
## EXCEPTION — "earth" (Colossus Pillar): not a light column at all. It runs a
## separate stone-eruption timeline: fissures crack outward + the ground heaves
## (long telegraph), then a titanic slate spire ERUPTS from below with dust,
## debris and a heavy landing thump, holds as area denial, then crumbles. That
## mode was already the most distinct thing in the ult set — an opaque physical
## OBJECT with real mass where everything else is glowing light — so its look is
## deliberately left alone here; only its damage shape was corrected.

## THE DODGE BUDGET for the light column: 0.55 s of motionless thread before the
## pillar lands. Longer than the old 0.42 because the tell is now quiet and still
## rather than a growing ring — a subtle tell has to last longer to be fair.
## UNTESTED GUESS.
const CHARGE_TIME: float = 0.55
## The hit itself: a SNAP, cut from 0.18 to make the contrast with the long fade
## sharp. The pillar should feel like it was already over before you registered it.
const PILLAR_HOLD: float = 0.06
## The long burn-down. 0.30 -> 0.85: this is the "retinal afterimage" that gives
## the Verdict a silhouette in memory rather than just at the moment of impact.
const FADE_TIME: float = 0.85
const SKY_HEIGHT: float = 560.0   # how far above the ground the column starts
const DEFAULT_RADIUS: float = 70.0
const DEFAULT_DAMAGE: int = 95
## ⚠ RETIRED — the shove is now derived from the spell's own damage and shelf via
## `SpellTier.push_for_spectacle`. Kept only as the record of what it used to be:
## every one of these sat BELOW `SlamPhysics.MIN_SLAM_SPEED` (250), so no spell in
## the game could throw a body hard enough to crack what it hit. Do not tune this
## number — nothing reads it. The band is in `SpellTier`.
const RETIRED_KNOCKBACK: float = 210.0
## Half-width of the DAMAGING column, as a fraction of `_radius`.
##
## THE MISMATCH THIS FIXES: damage was a plain circle of `_radius` around the
## ground point, so (a) it reached `_radius` straight DOWN through the floor, and
## (b) a body standing high up inside the drawn column — on a platform, mid-jump —
## was outside the circle and took nothing at all, despite a pillar of light being
## drawn straight through it. The column is drawn with a bright band about
## `_radius * 0.9` across, so half of that is 0.45; 0.5 is that band plus a hair,
## and it is measured to the target's silhouette rather than to a point. UNTESTED.
const COLUMN_HALF_FACTOR: float = 0.5

# ── COLOSSUS PILLAR / stone mode ("earth" effect) ────────────────────────────
# The "earth" character is not a tinted light column — it is GEOLOGY: fissures
# spread, the ground heaves, then a titanic slate spire erupts UP out of the
# dirt. Deliberately the OPPOSITE of RockPillar's fast uppercut fang: slow tell
# (rule 2 — real reaction window), vast multi-slab mass, long area-denying hold.
const STONE_CHARGE: float = 0.85   # the dodge window — over 2x Judgment's tell
const STONE_RISE: float = 0.18
const STONE_HOLD: float = 0.60     # lingers (area denial) vs Judgment's 0.18 flash
const STONE_CRUMBLE: float = 0.45
const STONE_HEIGHT: float = 300.0  # 2x the RockPillar uppercut spike
const STONE_SLABS: int = 7
const STONE_CRACKS: int = 9
# Cold slate palette so the colossus cannot be mistaken for RockPillar's warm
# brown fang or for any light column. RIM is HDR (>1.0) so fresh fracture
# faces bloom like hot mineral seams.
const STONE_BODY: Color = Color(0.40, 0.36, 0.30)
const STONE_FACE: Color = Color(0.52, 0.46, 0.37)   # lit left facet — strata read as rock
const STONE_LIT: Color = Color(0.68, 0.60, 0.47)
const STONE_RIM: Color = Color(1.22, 1.06, 0.84)    # HDR mineral seam (subtle bloom, not wire)
const STONE_SEAM: Color = Color(0.15, 0.13, 0.10)
const STONE_DUST: Color = Color(0.62, 0.52, 0.38)
## Colossus damage shape, corrected to match its DRAWING (see the audit note on
## `_erupt_stone`). The spire is drawn `_radius * 0.95` wide at the base and
## STONE_HEIGHT tall; the broken-slab rubble hump around its foot spans
## `+/- _radius * 0.85`. The old damage query was a single `_radius` circle at the
## base, which was simultaneously too WIDE (it hit past the rubble, and `_radius`
## straight down through the floor) and far too SHORT (a body level with the
## middle of a 300 px spire took nothing while rock was drawn through it).
const STONE_BASE_FACTOR: float = 0.85    # x _radius — matches the drawn rubble hump
const STONE_COLUMN_FACTOR: float = 0.5   # x _radius — matches the drawn slab width

var _ground: Vector2 = Vector2.ZERO
var _color: Color = Color(1.0, 0.92, 0.55, 1.0)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var _effect: String = "holy"
var _elapsed: float = -1.0
var _struck: bool = false
## Elemental ailment (Elements.Element) applied to enemies the pillar hits. -1=none.
var element_id: int = -1

# Stone-mode state (Colossus Pillar). Crack fan + slab jitter are seeded once in
# strike() so per-frame redraws don't shimmer.
var _stone: bool = false
var _rumble_accum: float = 0.0
var _crack_angles: PackedFloat32Array = PackedFloat32Array()
var _crack_lens: PackedFloat32Array = PackedFloat32Array()
var _slab_jitter: PackedFloat32Array = PackedFloat32Array()

## WHO CAST THIS. `SpellCaster._stamp` has always written this name onto every
## spectacle it builds, but this file never declared it — and `set()` on an
## undeclared property is a silent no-op, so the write went nowhere. That cost
## nothing while a hero's spells scanned `"enemy"` (the caster was never in that
## group) and became a SELF-KILL the moment friendly fire pointed them at the
## shared `"mortal"` group. Declaring it is what arms `SpellTargets.hostiles()` /
## `SpellTargets.owner_of()`, which is where the exclusion is now enforced.
var caster_node: Node = null


## Public entry: smite the single point `target` with a pillar dealing `damage`
## over `radius`. Colour tints the spectacle; `effect` picks its character.
func strike(
	target: Vector2, color: Color = Color(1.0, 0.92, 0.55),
	radius: float = DEFAULT_RADIUS, damage: int = DEFAULT_DAMAGE,
	effect: String = "holy",
) -> void:
	_ground = target
	_color = color
	_radius = radius
	_damage = damage
	_effect = effect
	# FORCED-HOLY FIX (magic-overhaul phase 2): SpellLibrary._ray() hardcodes
	# effect="holy" on every DIVINE_RAY def and _colossus_pillar() never
	# overrides it, so the "titanic stone spire" arrived here as a brown-tinted
	# holy light column. The spell's EARTH identity DOES survive in element_id
	# (SpellCaster sets it before calling strike()), so reinterpret holy+EARTH
	# as stone. Judgment (holy, LIGHTNING ailment) and the Boss's fire rays are
	# untouched; if SpellLibrary later passes "earth" directly this is a no-op.
	if _effect == "holy" and element_id == Elements.Element.EARTH:
		_effect = "earth"
	_stone = _effect == "earth"
	_elapsed = 0.0
	if _stone:
		# Geology, not sky magic: no heaven sigil, no radiant chord. Seed the
		# deterministic crack fan + slab jitter once (redraws must not shimmer).
		for i: int in STONE_CRACKS:
			_crack_angles.append(TAU * (float(i) + randf_range(-0.3, 0.3)) / float(STONE_CRACKS))
			_crack_lens.append(randf_range(0.7, 1.25))
		for i: int in STONE_SLABS + 2:
			_slab_jitter.append(randf_range(-0.3, 0.3))
		Sfx.play("earth", -4.0, 0.08)  # the ground starts to groan
		Juice.shake_camera(3.0)
		queue_redraw()
		return
	# NO SKY SIGIL (see the header note). The tell is drawn by this file, in
	# _draw_thread(): a hairline of light hanging dead still in the exact column
	# the pillar will fill. Stillness is the whole point — every other telegraph in
	# the game grows, spins or pulses, so a threat that simply HANGS there is
	# instantly identifiable as this one.
	Sfx.play("holy", -8.0, 0.05)  # a quiet, sustained note under the stillness
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	var done: bool = _stone_step(delta) if _stone else _light_step()
	if done:
		queue_free()
		return
	queue_redraw()


## Light-column timeline (Judgment + every non-earth effect). Returns true when
## the spectacle is finished and the node should free.
func _light_step() -> bool:
	if not _struck and _elapsed >= CHARGE_TIME:
		_smite()
	return _elapsed >= CHARGE_TIME + PILLAR_HOLD + FADE_TIME


## Stone-eruption timeline (Colossus Pillar): rumbling telegraph, one heavy
## eruption, an area-denying hold shedding rubble, then crumble. Returns true
## when finished.
func _stone_step(delta: float) -> bool:
	if _elapsed < STONE_CHARGE:
		# Escalating rumble: shakes + dirt puffs come faster and harder as the
		# eruption nears, so the tell reads with peripheral vision too.
		_rumble_accum += delta
		var late: bool = _elapsed > STONE_CHARGE * 0.55
		if _rumble_accum >= (0.08 if late else 0.14):
			_rumble_accum = 0.0
			Juice.shake_camera(3.5 if late else 1.8)
			CombatVfx.spawn_burst(
				get_parent(), _ground + Vector2(randf_range(-0.6, 0.6) * _radius, 0.0),
				Color(0.7, 0.58, 0.4, 0.55), Color(0.4, 0.32, 0.2, 0.0),
				5 if late else 3, 0.4, 30.0, 100.0, 1.2, 3.0
			)
		return false
	if not _struck:
		_erupt_stone()
	var total: float = STONE_CHARGE + STONE_RISE + STONE_HOLD + STONE_CRUMBLE
	if _elapsed >= STONE_CHARGE + STONE_RISE + STONE_HOLD and _elapsed < total:
		# Crumble: shed rubble in staggered pops as the spire collapses.
		if fmod(_elapsed, 0.11) < delta:
			DebrisChunk.spawn_burst(
				get_parent(), _ground - Vector2(0.0, STONE_HEIGHT * 0.45),
				Color(0.42, 0.37, 0.30), 5, Vector2.ZERO, 200.0
			)
	if _elapsed >= total:
		# The eruption leaves a permanent-feeling scar, not a scorch.
		ScorchDecal.spawn(
			get_parent(), _ground, _radius * 0.6, "crack",
			Color(0.5, 0.45, 0.38, 0.55), 8.0
		)
		return true
	return false


## The colossus lands: same damage/status/knockback contract as _smite(), but
## the spectacle is geological — grit ring, hanging dust, debris, a gouged
## crater and a deep pitched-down thump (a mountain landing, not artillery).
func _erupt_stone() -> void:
	_struck = true
	var at: Vector2 = _ground
	# AUDIT FIX — the damage now has the SHAPE OF THE SPIRE. See STONE_BASE_FACTOR
	# / STONE_COLUMN_FACTOR: a tall narrow capsule for the slab stack plus the
	# rubble hump at its foot, instead of one `_radius` ball at the base that was
	# both wider than the drawn rock at ground level and blind to everything above
	# knee height on a 300 px tower.
	# hostiles(): the column is placed by aim and CAN be placed on your own feet.
	for enemy: Node in _column_targets(
			STONE_HEIGHT, _radius * STONE_COLUMN_FACTOR, _radius * STONE_BASE_FACTOR,
			SpellTargets.hostiles(self, target_group)):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - at).normalized()
			enemy.apply_knockback((away if away != Vector2.ZERO else Vector2.UP)
				* SpellTier.push_for_spectacle(float(_damage),
					SpellTier.PUSH_TIER[SpellTier.Tier.ULT]))
	for prop: Node in _column_targets(
			STONE_HEIGHT, _radius * STONE_COLUMN_FACTOR, _radius * STONE_BASE_FACTOR,
			get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)
	# Fast grit blasting outward at the base + slow dust that HANGS in the air.
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.85, 0.72, 0.5, 0.95), Color(0.4, 0.33, 0.22, 0.0),
		40, 0.6, 120.0, 340.0, 1.8, 5.0
	)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.62, 0.52, 0.38, 0.6), Color(0.5, 0.42, 0.3, 0.0),
		26, 0.9, 40.0, 130.0, 3.0, 7.0
	)
	DebrisChunk.spawn_burst(get_parent(), at, Color(0.42, 0.37, 0.30), 14, Vector2.UP, 320.0)
	GroundCrater.spawn(get_parent(), at, _radius * 0.7, true)
	Juice.hit_stop(0.11)
	Juice.shake_camera(18.0)
	Juice.zoom_punch_camera(0.10, 0.26)
	PostProcess.shock(0.6)  # the whole screen feels the mass land
	# A falling MASS is the one thing the white blow-out was always right for —
	# it is a concussion, not a shape — so this rung takes it straight off the
	# ladder at ULT weight. Camera + freeze suppressed (fired above, tuned).
	Juice.tier_frame(SpellTier.Tier.ULT, at, element_id,
		{"style": ImpactFrame.Style.BLOWOUT,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	Sfx.play("cannon", 1.0, 0.05, 0.72)  # pitched DOWN — heavy landing thump
	Sfx.play("earth", -1.0, 0.06)


## The pillar lands: radius damage once at the marked point, impact spray + mark,
## and a heavy screen kick (Judgment is a big single-target hit).
func _smite() -> void:
	_struck = true
	var at: Vector2 = _ground
	# AUDIT FIX — damage now has the SHAPE OF THE PILLAR: the drawn column as a
	# vertical capsule from the sky down, plus the ground footprint disc. The old
	# `_radius` circle at the ground point missed anyone standing high inside the
	# beam (on a platform, mid-jump) while reaching `_radius` down through the
	# floor into the level below. See COLUMN_HALF_FACTOR.
	for enemy: Node in _column_targets(
			SKY_HEIGHT, _radius * COLUMN_HALF_FACTOR, _radius,
			SpellTargets.hostiles(self, target_group)):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - at).normalized()
			enemy.apply_knockback((away if away != Vector2.ZERO else Vector2.UP)
				* SpellTier.push_for_spectacle(float(_damage),
					SpellTier.PUSH_TIER[SpellTier.Tier.ULT]))
	for prop: Node in _column_targets(
			SKY_HEIGHT, _radius * COLUMN_HALF_FACTOR, _radius,
			get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)
	_impact_burst(at)
	_impact_mark(at)
	Juice.hit_stop(0.09)
	Juice.shake_camera(14.0)
	# A DOWNWARD camera kick rather than the zoom-punch every other big spell
	# fires: the screen is shoved along the same axis the pillar travelled, which
	# is a distinct physical read and costs nothing.
	Juice.kick_camera(Vector2.DOWN, 16.0)
	PostProcess.shock(0.55, Juice.world_to_uv(at))  # ripple centred on the strike
	# The COLUMN of light gets the colour field, not the blow-out: the whole read
	# of this spell is "the sky opened in <element>", and a field of that element
	# is that sentence as a single frame. A white flash would say "something
	# exploded", which is the wrong spell.
	Juice.tier_frame(SpellTier.Tier.ULT, at, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	Sfx.play("cannon", 0.0, 0.06)  # the pillar slams down


## Everyone inside a vertical effect standing on `_ground`: a capsule `height` tall
## and `half_width` wide, UNIONed with a `base_radius` disc at its foot.
##
## That union is the honest description of both vertical spells in this file — a
## tall narrow body with a wider splash where it meets the floor — and replacing
## the single ground circle with it is what stops the drawn extent and the damaged
## extent disagreeing in BOTH directions at once.
##
## Order is deterministic (capsule hits first, then disc-only hits) because the
## input group order is, which keeps it headless-testable. LOS is on for both
## halves: the column is traced from the sky so a target under a ledge is
## correctly shielded, and the disc is traced from the impact point so the splash
## cannot leak through a wall or the floor.
func _column_targets(height: float, half_width: float, base_radius: float,
		nodes: Array) -> Array:
	var top := Vector2(_ground.x, _ground.y - height)
	var out: Array = SpellTargets.on_line(top, Vector2.DOWN, height, half_width, nodes, [], self)
	for n: Node in SpellTargets.in_radius(_ground, base_radius, nodes, [], self):
		if not out.has(n):
			out.append(n)
	return out


## Impact spray at the footprint, charactered per effect.
func _impact_burst(at: Vector2) -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	match _effect:
		"frost":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.9, 0.98, 1.0, 0.96), fade,
				34, 0.5, 150.0, 360.0, 0.7, 1.8, 3.0, 6.0, true
			)
		"fire":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.85, 0.4, 0.95), Color(0.85, 0.15, 0.05, 0.0),
				38, 0.55, 90.0, 300.0, 1.5, 4.5, 0.0, 0.0, true
			)
			DebrisChunk.spawn_burst(get_parent(), at, Color(0.55, 0.25, 0.1), 3, Vector2.UP, 190.0)
		"arcane":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1, 1, 1, 0.96), fade,
				40, 0.5, 100.0, 320.0, 1.4, 4.0, 0.0, 0.0, true
			)
		"lightning":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 1.0, 0.7, 0.96), fade,
				38, 0.34, 200.0, 480.0, 0.4, 1.3, 4.0, 8.0, true
			)
		"shadow":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.7, 0.45, 1.0, 0.96), Color(0.14, 0.05, 0.3, 0.0),
				40, 0.6, 80.0, 240.0, 1.2, 3.2, 1.0, 2.5, true
			)
		"earth":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.85, 0.62, 0.35, 0.9), Color(0.4, 0.28, 0.15, 0.0),
				28, 0.5, 60.0, 220.0, 1.6, 4.5
			)
			DebrisChunk.spawn_burst(get_parent(), at, Color(0.5, 0.38, 0.22), 5, Vector2.UP, 220.0)
		"wind":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.72, 1.0, 0.92, 0.9), fade,
				36, 0.4, 190.0, 460.0, 0.6, 1.8, 2.0, 5.0, true
			)
		_:
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.99, 0.9, 0.98), fade,
				44, 0.6, 70.0, 260.0, 1.0, 3.0, 1.0, 2.5, true
			)


## Lingering ground mark under the pillar: frost cracks the ground with ice, fire
## scorches it.
##
## ⚠ HOLY / ARCANE DELIBERATELY LEAVE NOTHING, AND THE CRATER IS GONE. This used
## to gouge the ground on every effect, so the floor after a Verdict looked
## identical to the floor after a meteor storm or a convergence — the residue is a
## read the player gets for free, seconds after the spell, and spending it on the
## same crater every time threw that read away. Craters belong to the ults made of
## ROCK (the Colossus, the boulder barrage). This one's aftermath is the column
## burning down in place above an untouched floor.
func _impact_mark(at: Vector2) -> void:
	match _effect:
		"frost":
			ScorchDecal.spawn(
				get_parent(), at, _radius * 0.5, "crack",
				Color(0.62, 0.88, 1.0, 0.5), 6.0
			)
		"fire":
			ScorchDecal.spawn(
				get_parent(), at, _radius * 0.5, "scorch",
				Color(0.06, 0.03, 0.02, 0.6), 8.0
			)
			GroundCrater.spawn(get_parent(), at, _radius * 0.5, true)


## Pure geometry (testable): nodes within `radius` of `center`.
##
## Kept as a static so `slice4_test_spells` can pin the footprint boundary without
## a physics world, but the body now delegates to the shared selector so the game
## has ONE definition of "inside the blast" instead of the seven copy-pasted ones
## this used to be part of. `require_los = false` because this overload asks the
## pure SHAPE question; the live paths ask the cover question too. A target with no
## drawn silhouette (crate, bolt, test stub) falls back to exactly the
## `global_position` distance test that used to be written out here, so the pinned
## boundary is byte-identical.
static func targets_in_radius(center: Vector2, radius: float, nodes: Array) -> Array:
	return SpellTargets.in_radius(center, radius, nodes, [], null, false)


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _stone:
		_draw_stone()
		return
	var c: Color = _color
	var sky_y: float = _ground.y - SKY_HEIGHT
	if _elapsed < CHARGE_TIME:
		_draw_thread(c, sky_y, _elapsed / CHARGE_TIME)
		return
	var local: float = _elapsed - CHARGE_TIME
	var intensity: float
	if local < PILLAR_HOLD:
		intensity = 1.0 if local > 0.04 else local / 0.04
	else:
		intensity = clampf(1.0 - (local - PILLAR_HOLD) / FADE_TIME, 0.0, 1.0)
	if intensity <= 0.01:
		return
	_draw_pillar(_ground.x, sky_y, c, _effect_core_color(), intensity)


## THE TELL — a hairline of light hanging DEAD STILL down the exact column the
## pillar will fill, plus a tight ring marking the footprint on the floor.
##
## Why a thread instead of the old growing danger ring: the ring said "something
## will happen here" in the same visual language as every other spell in the game,
## and said nothing about the column. The thread states the full silhouette of the
## incoming attack a half-second early — you can see the whole vertical corridor
## you must not be standing in — while being almost motionless, which makes it
## read as menace rather than as activity. It BRIGHTENS and THINS rather than
## growing, so the escalation is legible without anything moving.
func _draw_thread(c: Color, sky_y: float, tp: float) -> void:
	var sky := Vector2(_ground.x, sky_y)
	var ground := Vector2(_ground.x, _ground.y)
	# The thread: a soft halo and a hard hairline, both narrowing as it charges.
	draw_line(sky, ground, Color(c.r, c.g, c.b, 0.05 + 0.13 * tp), lerpf(7.0, 2.5, tp), true)
	draw_line(sky, ground, Color(1.4, 1.35, 1.1, 0.35 + 0.55 * tp), lerpf(2.0, 0.9, tp), true)
	# The footprint, drawn at the TRUE radius from the first frame — it does not
	# grow, because the danger area never grows either.
	draw_arc(_ground, _radius, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.25 + 0.45 * tp), 2.0, true)
	# One bead of light slides down the thread in the last third: the only motion
	# in the whole tell, and it is the "now" cue.
	if tp > 0.66:
		var f: float = (tp - 0.66) / 0.34
		draw_circle(sky.lerp(ground, f * f), 3.0 + 3.0 * f,
			Color(1.6, 1.55, 1.3, 0.9), true, -1.0, true)


## Draw the column of light at ground x `px`, from `sky_y` down to the ground.
func _draw_pillar(px: float, sky_y: float, c: Color, core: Color, intensity: float) -> void:
	var flick: float = _effect_flicker()
	var w: float = _radius * 0.9 * intensity * flick
	var sky: Vector2 = Vector2(px, sky_y)
	var ground: Vector2 = Vector2(px, _ground.y)
	if _effect == "holy":
		_draw_column(sky, ground, w * 2.6, Color(c.r, c.g, c.b, 0.1 * intensity))
	_draw_column(sky, ground, w * 1.7, Color(c.r, c.g, c.b, 0.25 * intensity))
	_draw_column(sky, ground, w * 1.0, Color(c.r, c.g, c.b, 0.65 * intensity))
	# Bright core as a thick AA line (clean round-profile edges) instead of a
	# flat aliased quad; the soft outer bands stay polygons (no below-ground cap
	# bulge, MSAA is fine for their low alpha).
	draw_line(sky, ground, Color(core.r, core.g, core.b, 0.95 * intensity), w * 0.4, true)
	_draw_effect_detail(sky, ground, w, intensity)
	# Ground impact: a bright disc at the foot of the column, held INSIDE the
	# footprint.
	draw_circle(ground, minf(w * 1.5, _radius), Color(core.r, core.g, core.b, 0.5 * intensity), true, -1.0, true)
	# ⚠ NO EXPANDING SHOCKWAVE RING HERE ANY MORE. An expanding ring at the impact
	# point was the single most-shared motif in the ult set — the Siege, the nova,
	# the bombardment and this all ended with one, which is a large part of why the
	# maker read them as retypes of each other. This spell's aftermath is the
	# COLUMN itself burning down in place, which is a silhouette nothing else has.
	# The footprint is instead stated as a static ring at the true radius.
	draw_arc(ground, _radius, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.55 * intensity), 2.0, true)


func _effect_flicker() -> float:
	match _effect:
		"frost":
			return 1.0
		"fire":
			return 0.8 + 0.2 * sin(_elapsed * 85.0)
		"arcane":
			return 0.9 + 0.1 * sin(_elapsed * 60.0)
		"lightning":
			return 0.6 + 0.4 * sin(_elapsed * 95.0)
		"shadow":
			return 0.82 + 0.18 * sin(_elapsed * 18.0)
		"earth":
			return 1.0
		"wind":
			return 0.88 + 0.12 * sin(_elapsed * 70.0)
		_:
			return 0.94 + 0.06 * sin(_elapsed * 28.0)


func _effect_core_color() -> Color:
	match _effect:
		"frost":
			return Color(1.4, 1.5, 1.7)  # HDR cores bloom
		"fire":
			return Color(1.8, 1.55, 1.0)
		"arcane":
			return Color(1.6, 1.6, 1.7)
		"lightning":
			return Color(1.9, 1.7, 0.9)
		"shadow":
			return Color(1.5, 1.0, 1.9)
		"earth":
			return Color(1.7, 1.35, 0.85)
		"wind":
			return Color(1.35, 1.85, 1.7)
		_:
			return Color(1.85, 1.75, 1.45)


## Per-effect garnish drawn along the column so each element is unmistakable.
func _draw_effect_detail(sky: Vector2, ground: Vector2, w: float, intensity: float) -> void:
	match _effect:
		"frost":
			for i: int in 6:
				var t: float = (float(i) + 0.7) / 6.5
				var p: Vector2 = sky.lerp(ground, t)
				var side: float = 1.0 if i % 2 == 0 else -1.0
				var reach: float = w * (1.2 + 0.5 * absf(sin(float(i) * 12.9898)))
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(0.0, -w * 0.35), p + Vector2(0.0, w * 0.35),
					p + Vector2(side * reach, 0.0),
				]), Color(0.85, 0.97, 1.0, 0.7 * intensity))
		"fire":
			for i: int in 8:
				var t: float = fposmod(float(i) / 8.0 - _elapsed * 1.1 + sin(float(i) * 7.31) * 0.05, 1.0)
				var p: Vector2 = sky.lerp(ground, t) \
					+ Vector2(sin(_elapsed * 14.0 + float(i) * 2.1) * w * 1.1, 0.0)
				draw_circle(p, w * 0.16 + 1.5,
					Color(1.0, 0.55 + 0.3 * absf(sin(float(i) * 3.7)), 0.15, 0.8 * intensity), true, -1.0, true)
		"holy":
			for i: int in 7:
				var t: float = (float(i) + 0.5) / 7.0
				var p: Vector2 = sky.lerp(ground, t) \
					+ Vector2(sin(_elapsed * 6.0 + float(i) * 1.7) * w * 1.3, 0.0)
				var ma: float = (0.35 + 0.25 * sin(_elapsed * 9.0 + float(i))) * intensity
				draw_circle(p, w * 0.4, Color(1.0, 0.97, 0.8, ma * 0.5), true, -1.0, true)
				draw_circle(p, w * 0.16, Color(1.0, 1.0, 0.95, ma), true, -1.0, true)


## A vertical band of thickness `thick` from `sky` down to `ground`.
func _draw_column(sky: Vector2, ground: Vector2, thick: float, col: Color) -> void:
	var half: Vector2 = Vector2(thick * 0.5, 0.0)
	draw_colored_polygon(
		PackedVector2Array([sky - half, sky + half, ground + half, ground - half]), col
	)


# ── Colossus Pillar (stone mode) rendering ───────────────────────────────────


func _draw_stone() -> void:
	if _elapsed < STONE_CHARGE:
		_draw_stone_telegraph(_elapsed / STONE_CHARGE)
		return
	var local: float = _elapsed - STONE_CHARGE
	var rise_t: float = clampf(local / STONE_RISE, 0.0, 1.0)
	var alpha: float = 1.0
	if local >= STONE_RISE + STONE_HOLD:
		alpha = clampf(1.0 - (local - STONE_RISE - STONE_HOLD) / STONE_CRUMBLE, 0.0, 1.0)
	if alpha <= 0.01:
		return
	# Ease-out rise: the mass decelerates as it locks into place.
	var h: float = STONE_HEIGHT * (1.0 - pow(1.0 - rise_t, 3.0))
	if h <= 2.0:
		return
	# Dust skirt widens slightly as the spire crumbles (settling cloud).
	var skirt: float = _radius * (0.9 + 0.3 * (1.0 - alpha))
	draw_circle(_ground, skirt, Color(STONE_DUST.r, STONE_DUST.g, STONE_DUST.b, 0.26 * alpha), true, -1.0, true)
	# Flanking shards erupt a beat late and lean OUTWARD — the multi-slab
	# cluster silhouette RockPillar's single fang never has.
	var side_t: float = clampf((local - 0.05) / STONE_RISE, 0.0, 1.0)
	var sh: float = STONE_HEIGHT * (1.0 - pow(1.0 - side_t, 3.0))
	if sh > 2.0:
		_draw_stone_shard(Vector2(_ground.x - _radius * 0.58, _ground.y), sh * 0.5, _radius * 0.34, -0.38, alpha, 7)
		_draw_stone_shard(Vector2(_ground.x + _radius * 0.62, _ground.y), sh * 0.62, _radius * 0.40, 0.32, alpha, 8)
	_draw_stone_spire(h, alpha)
	_draw_stone_rubble(alpha)


## Telegraph (the dodge window): a danger ring in the game's tell grammar, a
## fan of jagged fissures crawling outward, a heaving mound, and — in the last
## 40% — molten HDR light leaking up through the cracks (pressure building).
func _draw_stone_telegraph(tp: float) -> void:
	var c: Color = _color
	draw_arc(
		_ground, _radius * (0.35 + 0.65 * tp), 0.0, TAU, 40,
		Color(c.r, c.g, c.b, 0.5 * tp), 3.0, true
	)
	for i: int in STONE_CRACKS:
		var dirv: Vector2 = Vector2.from_angle(_crack_angles[i])
		var reach: float = _radius * _crack_lens[i] * tp
		if reach < 4.0:
			continue
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var p0: Vector2 = _ground + dirv * _radius * 0.08
		var mid: Vector2 = _ground + dirv * reach * 0.55 \
			+ Vector2(-dirv.y, dirv.x) * reach * 0.16 * side
		var p1: Vector2 = _ground + dirv * reach
		draw_line(p0, mid, Color(STONE_SEAM.r, STONE_SEAM.g, STONE_SEAM.b, 0.8 * tp), 2.6, true)
		draw_line(mid, p1, Color(STONE_SEAM.r, STONE_SEAM.g, STONE_SEAM.b, 0.65 * tp), 1.8, true)
		if tp > 0.6:
			var glow: float = (tp - 0.6) * 2.5
			draw_line(p0, mid, Color(1.55, 1.1, 0.45, 0.55 * glow), 1.1, true)
	# The ground swells upward — mass is coming.
	var bulge: float = 12.0 * tp * tp
	if bulge > 1.0:
		draw_colored_polygon(PackedVector2Array([
			_ground + Vector2(-_radius * 0.5, 0.0),
			_ground + Vector2(-_radius * 0.22, -bulge),
			_ground + Vector2(_radius * 0.05, -bulge * 1.15),
			_ground + Vector2(_radius * 0.3, -bulge * 0.7),
			_ground + Vector2(_radius * 0.5, 0.0),
		]), Color(0.42, 0.36, 0.28, 0.55 * tp))


## The central titan: stacked jagged slabs tapering to a crown. Each slab gets
## a lit top edge, an HDR rim on the sun side and a dark seam below — the same
## fracture grammar as RockPillar but at twice the scale and in cold slate.
func _draw_stone_spire(height: float, alpha: float) -> void:
	var base_w: float = _radius * 0.95
	var slab_h: float = height / float(STONE_SLABS)
	for i: int in STONE_SLABS:
		var f0: float = float(i) / float(STONE_SLABS)
		var f1: float = float(i + 1) / float(STONE_SLABS)
		var w0: float = base_w * (1.0 - 0.62 * f0)
		var w1: float = base_w * (1.0 - 0.62 * f1)
		var jx: float = _slab_jitter[i] * base_w * 0.3
		var y0: float = _ground.y - height * f0
		var y1: float = _ground.y - height * f1
		var cx: float = _ground.x + jx
		var verts := PackedVector2Array([
			Vector2(cx - w0 * 0.5, y0), Vector2(cx - w1 * 0.5 - 2.0, y1),
			Vector2(cx + w1 * 0.5 + 1.0, y1), Vector2(cx + w0 * 0.55, y0),
		])
		draw_colored_polygon(verts, Color(STONE_BODY.r, STONE_BODY.g, STONE_BODY.b, alpha))
		# Lit LEFT facet: without a second tone the slabs collapse into one dark
		# silhouette and the spire reads as edges, not rock faces.
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - w0 * 0.5, y0), Vector2(cx - w1 * 0.5 - 2.0, y1),
			Vector2(cx - w1 * 0.5 + w1 * 0.32, y1), Vector2(cx - w0 * 0.5 + w0 * 0.38, y0),
		]), Color(STONE_FACE.r, STONE_FACE.g, STONE_FACE.b, alpha))
		draw_line(
			Vector2(cx - w1 * 0.5 - 2.0, y1), Vector2(cx + w1 * 0.5 + 1.0, y1),
			Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, alpha), 3.2, true
		)
		draw_line(
			Vector2(cx - w1 * 0.5 - 2.0, y1), Vector2(cx - w0 * 0.5, y0),
			Color(STONE_RIM.r, STONE_RIM.g, STONE_RIM.b, 0.55 * alpha), 1.2, true
		)
		draw_line(
			Vector2(cx - w0 * 0.5, y0), Vector2(cx + w0 * 0.55, y0),
			Color(STONE_SEAM.r, STONE_SEAM.g, STONE_SEAM.b, alpha), 2.4, true
		)
	# Jagged crown: the top slab breaks into a two-point silhouette.
	var top_y: float = _ground.y - height
	var top_w: float = base_w * (1.0 - 0.62) * 0.5
	var cxt: float = _ground.x + _slab_jitter[STONE_SLABS - 1] * base_w * 0.3
	draw_colored_polygon(PackedVector2Array([
		Vector2(cxt - top_w, top_y),
		Vector2(cxt - top_w * 0.45, top_y - slab_h * 1.1),
		Vector2(cxt + top_w * 0.1, top_y - slab_h * 0.35),
		Vector2(cxt + top_w * 0.6, top_y - slab_h * 0.8),
		Vector2(cxt + top_w, top_y),
	]), Color(STONE_BODY.r, STONE_BODY.g, STONE_BODY.b, alpha))
	draw_line(
		Vector2(cxt - top_w, top_y), Vector2(cxt - top_w * 0.45, top_y - slab_h * 1.1),
		Color(STONE_RIM.r, STONE_RIM.g, STONE_RIM.b, 0.65 * alpha), 1.3, true
	)


## One flanking shard: a tilted triangular slab with a lit face and HDR edge.
func _draw_stone_shard(
	base: Vector2, height: float, width: float, tilt: float, alpha: float, ji: int
) -> void:
	var dirv := Vector2(sin(tilt), -cos(tilt))
	var perp := Vector2(-dirv.y, dirv.x)
	var tip: Vector2 = base + dirv * height + perp * _slab_jitter[ji] * width * 0.4
	var kink: Vector2 = base + dirv * height * 0.55 - perp * width * 0.62
	var verts := PackedVector2Array([
		base - perp * width * 0.5, kink, tip, base + perp * width * 0.55,
	])
	draw_colored_polygon(verts, Color(STONE_BODY.r, STONE_BODY.g, STONE_BODY.b, alpha))
	# Lit facet toward the kink side so the shard reads as an angled rock face.
	draw_colored_polygon(PackedVector2Array([
		base - perp * width * 0.5, kink, base.lerp(tip, 0.55),
	]), Color(STONE_FACE.r, STONE_FACE.g, STONE_FACE.b, alpha))
	draw_line(kink, tip, Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, alpha), 2.2, true)
	draw_line(tip, base + perp * width * 0.55, Color(STONE_RIM.r, STONE_RIM.g, STONE_RIM.b, 0.5 * alpha), 1.2, true)


## Broken slabs heaped where the spire punched through — sells "ERUPTED out of
## the ground" instead of "placed on top of it".
func _draw_stone_rubble(alpha: float) -> void:
	var r: float = _radius
	var hump := PackedVector2Array([
		_ground + Vector2(-r * 0.85, 0.0),
		_ground + Vector2(-r * 0.6, -10.0),
		_ground + Vector2(-r * 0.3, -16.0),
		_ground + Vector2(r * 0.15, -13.0),
		_ground + Vector2(r * 0.55, -17.0),
		_ground + Vector2(r * 0.85, 0.0),
	])
	draw_colored_polygon(hump, Color(0.36, 0.32, 0.26, 0.9 * alpha))
	draw_line(
		_ground + Vector2(-r * 0.6, -10.0), _ground + Vector2(-r * 0.3, -16.0),
		Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, 0.7 * alpha), 2.0, true
	)
	draw_line(
		_ground + Vector2(r * 0.15, -13.0), _ground + Vector2(r * 0.55, -17.0),
		Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, 0.6 * alpha), 2.0, true
	)
