class_name EnergyNova
extends Node2D

## Who this nova's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## THE SHOVE — the punctuation mark of the ult set.
##
## IDENTITY (maker, mid-playtest: "most ults look the same — just are recolours
## or retypes of the same meteor type of thing"). Every other big spell in the kit
## is a SKY event that takes a second to arrive somewhere you marked. This one is
## the opposite on every axis that matters, and those contrasts ARE the design:
##   * DIRECTION  — outward from the caster's own feet, along the FLOOR. Not down
##                  from above, not inward from the edges.
##   * TIMING     — a single instant. No build at all. The whole event is over in
##                  ~0.26 s, where Heaven's Verdict spends 1.3 s just winding up.
##   * SCALE      — deliberately the SMALLEST footprint of the set (135 px vs
##                  160-300). It is a "get off me", not a room-wipe.
##   * SILHOUETTE — a flat ground-hugging ELLIPSE that scrapes outward, plus a
##                  hard vertical clap. Not a disc, not a column, not a sigil.
##   * SCREEN     — the only ult that does NOT touch the camera zoom. No pull, no
##                  punch, no impact frame. A short hard shake and a ripple, then
##                  nothing. Every big spell reaching for the same three juice
##                  calls is a large part of why they stopped feeling different.
##   * RESIDUE    — nearly none. A scrape that clears. Craters and scorch belong
##                  to the spells that fall out of the sky.
##
## ⚠ NO TELEGRAPH, AND THAT IS DELIBERATE — FLAGGED, NOT FORGOTTEN. The house rule
## is "every ability must be dodgeable, with a real telegraph and a window to
## move". This one has neither, because it is the reactive panic button: a wind-up
## makes it useless for the job it exists to do, and deferring its damage by even
## one frame breaks both its i-frame-adjacent contract and `slice1_test_nova`'s
## Hero-cooldown case. Its counterplay is SPACING — it has the smallest footprint
## in the kit by a wide margin. The compression flash in beat 1 below is a READ (so
## a nearby player sees which body it came out of), NOT a dodge window: it is drawn
## in the same frame the damage already landed. Giving this a real window is a
## design decision about what the button is for, not a tuning tweak.

const NOVA_RADIUS: float = 135.0
## THE DRAWN RING NOW ENDS EXACTLY ON THE DAMAGE RADIUS. Pinned at 1.0, and the
## pin IS the bug fix.
##
## THE LIE THIS REPLACES: the ring used to be drawn to `NOVA_RADIUS * 0.62 * 1.3`
## — about 109 px — while `_apply_nova_damage()` queried the raw 135 px. So the
## nova damaged 1.24x WIDER than anything it ever drew, and a body standing in the
## visibly empty gap outside the ring still took 30 and got launched. That is the
## maker's "the spells shouldn't be able to get out the radius", in miniature.
##
## The old 0.62 came from a real complaint (the pre-shrink ring reached 175 px and
## read as half the screen at the combat camera's 1.6x zoom), which is exactly why
## the fix pulls the DRAWING out to the damage radius instead of inflating the
## damage out to the drawing: 135 is still comfortably tighter than the 175 that
## was complained about, and it is now honest.
##
## ⚠ Lower this again and you re-introduce the lie. The honest way to make the
## nova smaller on screen is to lower NOVA_RADIUS, which moves both together.
const VISUAL_RADIUS_FACTOR: float = 1.0
const NOVA_DAMAGE: int = 30
const NOVA_KNOCKBACK: float = 275.0   # was 420.0 — maker: spell knockback was way too much
const SHOCKWAVE_TIME: float = 0.26   # the whole event; shortest in the ult set
const CLEANUP_DELAY: float = 0.7
## Ground-plane squash for the shockwave ellipse. The arena is SIDE-VIEW, so a
## true circle reads as a bubble hanging in the air; squashing it makes the same
## ring read as a wave travelling across the FLOOR. Truer to the fiction, and the
## single cheapest change that stops this looking like every other radial burst in
## the game. UNTESTED GUESS.
const GROUND_SQUASH: float = 0.42
## Fraction of the event spent on the inward compression flash. A READ, not a
## dodge window (see the no-telegraph note above). UNTESTED GUESS.
const COMPRESS_FRAC: float = 0.22
## Faint floor scrape under the caster: the shove visibly stresses the arena.
## Snapped down onto the actual floor (never the sky) + fades so it clears up.
const CRACK_RADIUS_FACTOR: float = 0.35
const CRACK_TINT: Color = Color(0.3, 0.4, 0.5, 0.45)
const CRACK_LIFETIME: float = 5.0  # seconds before the scrape fades away
const DEBRIS_COUNT: int = 8
const DEBRIS_COLOR: Color = Color(0.45, 0.55, 0.62)  # cool shattered stone

var _shockwave_elapsed: float = -1.0  # < 0 means not yet fired.
## Element index (Elements.Element) applied as an ailment to enemies in radius.
var element_id: int = -1

## WHO CAST THIS. `SpellCaster._stamp` has always written this name onto every
## spectacle it builds, but this file never declared it — and `set()` on an
## undeclared property is a silent no-op, so the write went nowhere. That cost
## nothing while a hero's spells scanned `"enemy"` (the caster was never in that
## group) and became a SELF-KILL the moment friendly fire pointed them at the
## shared `"mortal"` group. Declaring it is what arms `SpellTargets.hostiles()` /
## `SpellTargets.owner_of()`, which is where the exclusion is now enforced.
var caster_node: Node = null


## Public entry: place the nova on the caster and fire IMMEDIATELY.
func activate_at(pos: Vector2) -> void:
	global_position = pos
	_apply_nova_damage()
	_spawn_nova_burst()
	# Scrape the FLOOR beneath the caster only — NEVER the sky (the maker's ask).
	# Airborne over a pit -> no scrape, no debris; just the energy ring rings out.
	# `SpellWorld.floor_below` is the house helper for this (it replaces a private
	# `_floor_below` that eight spectacles each had their own copy of).
	var hit: Dictionary = SpellWorld.floor_below(global_position, NOVA_RADIUS, [], self)
	if bool(hit["hit"]):
		var floor_pos: Vector2 = hit["position"]
		ScorchDecal.spawn(
			get_parent(), floor_pos,
			NOVA_RADIUS * CRACK_RADIUS_FACTOR, "crack", CRACK_TINT, CRACK_LIFETIME
		)
		# Dust kicked SIDEWAYS along the floor rather than up: the read is a shove,
		# not an explosion.
		DebrisChunk.spawn_burst(
			get_parent(), floor_pos, DEBRIS_COLOR, DEBRIS_COUNT, Vector2.LEFT, 200.0
		)
		DebrisChunk.spawn_burst(
			get_parent(), floor_pos, DEBRIS_COLOR, DEBRIS_COUNT, Vector2.RIGHT, 200.0
		)
	_shockwave_elapsed = 0.0
	queue_redraw()
	# THE SCREEN GRAMMAR THAT IS DELIBERATELY *NOT* SHARED WITH THE SKY ULTS: no
	# zoom_punch, no zoom_pull, and — still — no white blow-out. Those three were
	# fired by every big spell in the kit, so they stopped reading as "this one is
	# big" and started reading as "a spell happened". A short freeze, a hard shake
	# and a ripple is this spell's vocabulary.
	Juice.hit_stop(0.08)
	Juice.shake_camera(14.0)
	PostProcess.shock(0.6)  # the shove rings the screen outward
	# ...and ONE mark, chosen precisely because no other spell in the kit uses it.
	# The nova is a SHOVE: everything is pushed away from you at once and nothing
	# is destroyed. `INVERT` is the only style in the vocabulary that keeps the
	# picture completely intact — same silhouettes, same positions, same
	# readability — while making it read as deeply wrong for two frames. That is
	# the shove, exactly: the world did not explode, it flinched. It is also the
	# shortest mark there is (0.07 s), so it cannot become the wash this spell
	# spent a rewrite escaping.
	Juice.frame({
		"style": ImpactFrame.Style.INVERT, "strength": 1.0, "at": global_position,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
	})
	Sfx.play("nova", 1.0, 0.08)
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)


## Radius-query damage + OUTWARD knockback. Split out so headless tests can
## exercise the geometry without driving the VFX/juice side effects.
##
## Selection goes through `SpellTargets` rather than a hand-rolled distance loop:
## it measures to the target's DRAWN silhouette (an `Enemy`'s head sits ~10 px
## above its node origin — 19 px on the 1.9x sparring dummies — so an origin-only
## test let bursts pass straight through heads), and it drops anything behind
## cover, which is what stops the burst reaching through the floor into the room
## below. Targets with no silhouette (crates, bolts, test stubs) fall back to the
## exact `global_position` point test this used before, so the 135 px boundary
## pinned by `slice1_test_nova` is unchanged.
func _apply_nova_damage() -> void:
	var here: Vector2 = global_position
	for enemy: Node in SpellTargets.in_radius(
			here, NOVA_RADIUS, get_tree().get_nodes_in_group(target_group),
			[caster_node], self):
		if enemy.has_method("take_damage"):
			enemy.take_damage(NOVA_DAMAGE)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - here).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			enemy.apply_knockback(away * NOVA_KNOCKBACK)
	# Crates around the caster shatter too (no knockback — they're static).
	for prop: Node in SpellTargets.in_radius(
			here, NOVA_RADIUS, get_tree().get_nodes_in_group("destructible"), [], self):
		# Blow parts off outward from the nova centre (falls back to take_damage).
		if prop.has_method("damage_at"):
			var out: Vector2 = ((prop as Node2D).global_position - here).normalized()
			prop.damage_at(NOVA_DAMAGE, (prop as Node2D).global_position, out if out != Vector2.ZERO else Vector2.UP)
		elif prop.has_method("take_damage"):
			prop.take_damage(NOVA_DAMAGE)
	# Enemy bolts caught in the nova are cleared from the air (spell-vs-spell).
	# Deliberately NOT line-of-sight filtered: a bolt inside the burst is already
	# inside it, and a projectile is not a body that cover can sensibly hide.
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		if proj is Node2D and here.distance_to((proj as Node2D).global_position) <= NOVA_RADIUS \
				and proj.has_method("consume"):
			proj.call("consume")


func _process(delta: float) -> void:
	if _shockwave_elapsed < 0.0:
		return
	_shockwave_elapsed += delta
	queue_redraw()


func _draw() -> void:
	if _shockwave_elapsed < 0.0:
		return
	var t: float = clampf(_shockwave_elapsed / SHOCKWAVE_TIME, 0.0, 1.0)
	if t >= 1.0:
		return
	# BEAT 1 — the compression: a hard bright ring snapping INWARD to the caster.
	# It is the read ("this came out of THAT body"). Drawn first so it never
	# fights the outward wave for the same pixels.
	if t < COMPRESS_FRAC:
		var ct: float = t / COMPRESS_FRAC
		var cr: float = lerpf(NOVA_RADIUS * 0.85, 6.0, ct * ct)
		_draw_ground_ring(cr, Color(1.5, 1.8, 2.0, 0.75 * (1.0 - ct)), lerpf(2.0, 6.0, ct))
	# BEAT 2 — the shove: one flat ellipse scraping outward along the floor. It
	# ends EXACTLY on the damage radius (see VISUAL_RADIUS_FACTOR), so what you can
	# see is what can hit you.
	var r: float = lerpf(10.0, NOVA_RADIUS * VISUAL_RADIUS_FACTOR, _ease_out(t))
	var alpha: float = 1.0 - t
	_draw_ground_ring(r, Color(0.6, 0.9, 1.0, 0.95 * alpha), lerpf(11.0, 1.5, t))
	_draw_ground_ring(r * 0.78, Color(0.85, 0.95, 1.0, 0.5 * alpha), lerpf(6.0, 1.0, t))
	# BEAT 3 — the clap: two short hard strokes at the caster. A percussive accent
	# that stops the burst reading as a soft bubble, and the ONLY bright thing
	# here: there is deliberately no big white flash disc, because "a white disc at
	# the impact point" is the motif every other ult in the kit already owns.
	if t < 0.35:
		var f: float = 1.0 - t / 0.35
		var h: float = NOVA_RADIUS * 0.5 * f
		draw_line(Vector2(0.0, -h), Vector2(0.0, h), Color(1.5, 1.8, 2.1, 0.8 * f), 3.0 * f + 1.0, true)
		draw_line(
			Vector2(-h * 0.55, 0.0), Vector2(h * 0.55, 0.0),
			Color(1.4, 1.7, 2.0, 0.55 * f), 2.0 * f + 1.0, true
		)


## One floor-plane ellipse centred on the caster. Godot has no ellipse-arc
## primitive, so it is a polyline of points on the squashed circle — cheap, and it
## keeps the ring in the ground plane, where a side-view arena needs it.
func _draw_ground_ring(radius: float, col: Color, width: float) -> void:
	if radius <= 1.0:
		return
	var pts := PackedVector2Array()
	var steps: int = 48
	for i: int in steps + 1:
		var a: float = TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius * GROUND_SQUASH))
	draw_polyline(pts, col, width, true)


## Decelerating expansion — the wave leaves fast and settles, which reads as a
## shove rather than as a steadily-growing bubble.
func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 2.4)


## The shared burst builder, tuned to throw particles SIDEWAYS along the floor
## rather than spherically: the spray is part of the "flat shove" silhouette.
func _spawn_nova_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(0.75, 0.95, 1.0, 1.0), Color(0.25, 0.55, 1.0, 0.0),
		90, 0.45, 240.0, 540.0, 1.5, 4.5, 60.0, 130.0, true
	)
