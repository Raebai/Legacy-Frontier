class_name ShockwaveStomp
extends Node2D
## SHOCKWAVE STOMP — the Brawler's damage line. One boot into the floor, and a ridge
## of broken ground runs away from it in BOTH directions, following the terrain.
##
## ═══════════════════════════════════════════════════════════════════════════════
## WHY IT EXISTS: THE CLASS WAS THROWING A SPELL
## ═══════════════════════════════════════════════════════════════════════════════
## The Brawler is defined in `Hero.CLASS_CONFIG` as "PURE MELEE, no magic" — and its
## damage slot held `thunderclap`, a LIGHTNING lance it charges into its fist and rips
## down the aim. That is a spell, and it is also the Stormcaller's payoff, so the
## class was simultaneously off-fantasy and a recolour of another kit. This replaces
## it with the only thing a man with no magic can do to a room: hit the floor hard
## enough that the floor does the work.
##
## ── THE THREE RULES THIS SPELL OBEYS, WHICH ARE WHAT MAKE IT PHYSICAL ─────────
##   NO PROJECTILE. Nothing is spawned that travels through the air. The damage is a
##     query around a point that walks along the GROUND.
##   NO BEAM. There is no corridor from the caster to anywhere. The reach is measured
##     along the floor, and it stops at the lip of a pit because the floor does.
##   NO SKY. Nothing falls, nothing is summoned overhead, nothing arrives from
##     off-screen. Everything that happens, happens at foot height.
## If any future edit breaks one of those three, this stops being the Brawler's spell
## and becomes another caster's. They are the identity, not the numbers.
##
## ── FOLLOWING THE TERRAIN ─────────────────────────────────────────────────────
## The ridge path is `SpellWorld.ground_path`, one floor probe per sample, so the wave
## climbs a step and dips into a trough instead of sliding through solid rock at one
## flat y. That helper also owns THE PIT RULE — sampling stops at the first x with no
## floor under it — so a ridge that reaches a ledge simply ends at the lip. A ground
## effect drawn across thin air is the same class of bug as a meteor under the floor.
##
## ⚠ THE FLAT FALLBACK IS NOT A SHORTCUT. With no physics world at all (a `--script`
## suite, a bare capture rig) every probe misses and `ground_path` returns nothing,
## which would make this spell silently do NOTHING in exactly the contexts built to
## verify it. So a path with fewer than two points degrades to a straight line at the
## caster's own foot height — which is what flat ground would have produced anyway.
## See `_build_path`.
##
## ═══════════════════════════════════════════════════════════════════════════════
## THE TELL AND THE COUNTERPLAY (the locked "everything must be dodgeable" rule)
## ═══════════════════════════════════════════════════════════════════════════════
## TELL — two things, in order. First `WINDUP` seconds of a shared `Telegraph` LANE
##   down each side, drawn at the full reach the ridge will cover, so the extent is
##   stated before the boot lands (and `BotDodge` can perceive it — the shared
##   Telegraph joins the `telegraph` group). Then the ridge itself TRAVELS at a
##   finite `RIDGE_SPEED`, so at the far end of the reach you get most of a second of
##   visible approach on top of the windup.
##
## COUNTERPLAY — **JUMP.** This is a grounded effect and the bite is a circle of
##   `RIDGE_BITE` around a point ON THE FLOOR, so a body whose silhouette is more than
##   that far above the ground is not in it. That is not a special case bolted on: it
##   falls straight out of measuring from the floor, which is why the answer is
##   legible without being taught. The Brawler has a double jump; so does everyone
##   who is about to be hit by this.
##   Secondarily: outrange it (the reach is finite and drawn), or stand across a pit.
##
## UNPLAYTESTED. Every number below is a reasoned first guess with its rationale.

# ------------------------------------------------------------------- the beats
## THE FIRST DODGE BUDGET: the boot going up. Longer than a jab's tell and shorter
## than `BlastSpell.WINDUP` (0.55) — this is a damage line thrown all fight, not a
## centrepiece, and the ridge's own travel is the second half of the warning.
const WINDUP: float = 0.22
## How fast the ridge runs along the floor, px/s. THE SECOND DODGE BUDGET: at the
## shipping reach of 300 px, a body at the far end gets ~0.48 s of visible approach.
## Fast enough to feel like force, slow enough to jump. If it feels unavoidable at
## close range, that is correct — this is a melee class's melee answer.
const RIDGE_SPEED: float = 620.0
## How long the broken ground stays on screen after both ridges have run out.
const AFTER_GLOW: float = 0.32

## How far from the floor point a body may be and still be caught.
##
## ⚠ THIS NUMBER IS THE "JUMP OVER IT" RULE, stated once. `SpellTargets.hits`
## measures to the target's DRAWN SILHOUETTE, so a standing body (whose feet are on
## the floor point) is at distance ~0 and a body 60 px in the air is at ~60. Raising
## this past a body height would quietly delete the counterplay.
const RIDGE_BITE: float = 38.0

## How many floor probes each side's path is sampled at. `SpellWorld.ground_path`
## costs one raycast per sample; 12 over 300 px is a probe every 25 px, which is finer
## than the terrain features this game builds.
const RIDGE_SAMPLES: int = 12
## How deep below the caster's feet the ground is looked for. Generous enough to find
## the floor when the stomp is registered slightly above it, shallow enough that a
## stomp over a pit reports no floor rather than finding the next storey down.
const FLOOR_PROBE: float = 130.0
## How far ABOVE the probe point every floor ray is started from.
##
## ⚠ NOT COSMETIC — WITHOUT IT THE TERRAIN TRACKING IS DEAD IN THE COMMON CASE, and it
## fails silently by falling through to the flat fallback. A body standing on the floor
## has its feet EXACTLY on the collider's top surface, and a downward ray that starts
## exactly on a surface does not reliably register a hit. So every probe missed, every
## path came back empty, and the ridge ran flat straight over a step in the ground —
## which is precisely what `tools/melee_signature_capture.gd` photographed before this
## constant existed. Starting the ray a little above the foot makes the first thing it
## can possibly hit the floor the caster is standing on. `FLOOR_PROBE` is extended by
## the same amount so the reach downward is unchanged.
const PROBE_LIFT: float = 24.0

## Straight UP with a small push away — a shockwave POPS you off the floor, it does
## not sweep you sideways. The vertical share is the read: a body that goes up was
## hit by the ground.
const KNOCK_UP: float = 380.0
const KNOCK_OUT: float = 150.0

# ---------------------------------------------------------------- the picture
## Raised floor plates drawn at the ridge front. Three is enough to read as a crest
## and few enough to stay legible at the 0.63 framing zoom.
const PLATES: int = 3
## Sized against a rendered frame rather than reasoned: at 26 x 16 the crest was a
## speck beside the caster's own ground sigil and the eye went to the sigil instead
## of to the thing about to hit you.
const PLATE_WIDTH: float = 32.0
const PLATE_LIFT: float = 22.0
## HDR amber-white, > 1.0 so the fracture line blooms through the post grade.
const CORE: Color = Color(1.55, 1.25, 0.80)
const DUST: Color = Color(0.62, 0.52, 0.40)
const TELL_ACCENT: Color = Color(0.95, 0.16, 0.13, 0.9)

# ------------------------------------------------- the stamp (all five, declared)
## ⚠ ALL FIVE, because `set()` on an undeclared property is a SILENT no-op — and a
## spectacle with no `caster_node` is quietly inert in the whole reaction system, and
## one with no element is DROPPED by `SpellReactor.register` outright.
var target_group: String = "enemy"
var _target_group: String = "enemy"
## EARTH: the floor is the weapon. It also opposes LIGHTNING in `ReactionTable.OPPOSED`,
## which is a pleasing consequence of taking the lightning spell off this class.
var element_id: int = Elements.Element.EARTH
var spell_tier: int = SpellTier.Tier.HEAVY
var caster_node: Node = null
## "A ring leaves this centre" — which is exactly what two opposed ridges are.
## Overrides `SpellSigil.MOTIF_BY_SCRIPT`, a table this workstream does not own.
var sigil_motif: int = MagicCircle.Motif.PULSE

var _foot: Vector2 = Vector2.ZERO     ## the stomp point, snapped to the floor
var _reach: float = 300.0
var _color: Color = Color(0.78, 0.55, 0.28, 1.0)
var _damage: int = 54
var _elapsed: float = -1.0            ## < 0 means hex() has not run yet
var _stomped: bool = false
## One path per side, sampled along the terrain at cast time. Empty means that side
## had nowhere to run (a pit right at the caster's feet).
var _paths: Array[PackedVector2Array] = []
## Instance ids already caught. The front's bite circle overlaps itself frame to
## frame, so without this a body would take one hit per frame it stood in the ridge.
var _hit: Dictionary = {}
var _tells: Array[Telegraph] = []


## Cast entry — the fixed shape every `SpellCaster.HEX_SCRIPTS` entry shares.
## `target` is discarded: a stomp goes both ways, so the aim decides nothing here.
## (That is itself part of the identity — it is the one attack in the kit you cannot
## point.)
func hex(caster: Node, origin: Vector2, _target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	global_position = Vector2.ZERO   # world-space draw, like every spectacle here
	_color = color
	_damage = maxi(spell.damage, 1)
	_reach = maxf(spell.reach, 60.0)
	_foot = _floor_at(origin)
	_paths = [_build_path(1.0), _build_path(-1.0)]
	# Laid FLAT on the ground under the boot — a placed, grounded working. Held for
	# the windup plus the first slice of travel so the gate closes behind the wave.
	SpellSigil.open(self, _foot, _color, 1.0, false, Vector2.RIGHT, true, 0.16,
		WINDUP + 0.25)
	_arm_telegraphs()
	SpellDrops.sfx("charge_up", -8.0, 0.05, 0.7)
	_elapsed = 0.0
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.IMPACT, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


## How long the ridges take to run their full length, and the node's whole life.
## DERIVED from the reach and the speed — one number cannot drift from the other.
func _travel_time() -> float:
	return _reach / maxf(RIDGE_SPEED, 1.0)


func _life() -> float:
	return WINDUP + _travel_time() + AFTER_GLOW


## The floor under `p`, or `p` itself when there is none (a pit, or no physics world
## at all). `SpellWorld.floor_below` returns the caller's own point unchanged on a
## miss, which is exactly the fallback wanted here: with no floor to snap to, the
## caster's own feet are the best available answer.
func _floor_at(p: Vector2) -> Vector2:
	var g: Dictionary = SpellWorld.floor_below(p + Vector2(0.0, -PROBE_LIFT),
		FLOOR_PROBE + PROBE_LIFT, SpellWorld.rids([caster_node]), self)
	# On a MISS `floor_below` returns the point it was GIVEN, which is the lifted one —
	# so the miss path has to undo the lift or the whole spell floats 24 px in the air.
	return (g["position"] as Vector2) if bool(g["hit"]) else p


## One side's path along the terrain.
##
## THE FLAT FALLBACK (see the class docs): `ground_path` returns nothing when the very
## first probe misses, which is what happens with no physics world. A spell that
## silently does nothing in the headless suite and the capture rig is a spell nobody
## can verify, so fewer than two points degrades to a straight line at foot height —
## the answer flat ground would have given anyway. Over a real PIT this is still
## correct behaviour: the probe at the caster's own feet SUCCEEDS (he is standing on
## something), so `ground_path` returns the points up to the lip and the fallback
## never fires.
func _build_path(sign_x: float) -> PackedVector2Array:
	var to: Vector2 = _foot + Vector2(sign_x * _reach, 0.0)
	# Lifted for the same reason `_floor_at` lifts — see PROBE_LIFT. `ground_path`
	# probes DOWN from the y of the line it walks, so that line has to start above the
	# surface or every sample misses.
	var lift := Vector2(0.0, -PROBE_LIFT)
	var path: PackedVector2Array = SpellWorld.ground_path(_foot + lift, to + lift,
		RIDGE_SAMPLES, FLOOR_PROBE + PROBE_LIFT, SpellWorld.rids([caster_node]), self)
	if path.size() >= 2:
		return path
	var flat := PackedVector2Array()
	for i: int in RIDGE_SAMPLES:
		flat.append(_foot.lerp(to, float(i) / float(RIDGE_SAMPLES - 1)))
	return flat


## One LANE per side, at the full reach, so the extent is a promise made before the
## boot lands. ONE CLOCK: their `_process` is off and `advance()` drives them.
func _arm_telegraphs() -> void:
	for sign_x: float in [1.0, -1.0]:
		var t := Telegraph.new()
		add_child(t)
		# ⚠ STAMPED, so `BotController.perceive_threats` can tell whose tell this is.
		# An unstamped hero telegraph is indistinguishable from an enemy one, which
		# makes a bot-driven caster dodge its own spell for the whole wind-up.
		t.source = caster_node as Node2D
		t.global_position = _foot
		t.accent = TELL_ACCENT
		t.style = Telegraph.Style.LANE
		t.aim_dir = Vector2(sign_x, 0.0)
		t.reach = _reach
		t.set_process(false)
		t.start_line(_reach, RIDGE_BITE * 2.0, 0.0 if sign_x > 0.0 else PI, WINDUP)
		_tells.append(t)


func _process(delta: float) -> void:
	advance(delta)


## Deterministic time-step, so a headless suite can drive windup -> travel -> settle
## without waiting on real frames.
func advance(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	for t: Telegraph in _tells:
		if t != null and is_instance_valid(t):
			t.advance(delta)
	if not _stomped and _elapsed >= WINDUP:
		_stomped = true
		_stomp()
	if _stomped and _elapsed < WINDUP + _travel_time() + 0.05:
		_bite()
	if _elapsed >= _life():
		queue_free()
		return
	queue_redraw()


# ------------------------------------------------------------------ the impact
## The boot landing. All the residue is placed here rather than trailed along the
## ridge: the fracture starts at the foot, and a crater at every sample point would
## be a stripe of holes rather than a crack.
func _stomp() -> void:
	GroundCrater.spawn(get_parent(), _foot, 34.0, true)
	ScorchDecal.spawn(get_parent(), _foot, 30.0, "crack", Color(0.20, 0.17, 0.14, 0.55), 6.0)
	DebrisChunk.spawn_burst(get_parent(), _foot, Color(0.42, 0.36, 0.30), 14,
		Vector2.UP, 260.0)
	CombatVfx.spawn_burst(get_parent(), _foot, Color(DUST.r, DUST.g, DUST.b, 0.9),
		Color(DUST.r, DUST.g, DUST.b, 0.0), 26, 0.5, 70.0, 220.0, 1.2, 3.4)
	Juice.hit_stop(0.07)
	Juice.shake_camera(10.0)
	# The camera is KICKED DOWNWARD rather than punched in: the force went into the
	# floor, and the frame should agree with it.
	Juice.kick_camera(Vector2.DOWN, 6.0)
	SpellDrops.sfx("earth_impact", 0.0, 0.06, 0.85)
	SpellDrops.sfx("rubble", -5.0, 0.1, 1.0)


## Everything the two ridge fronts are currently passing over. Called every frame of
## the travel; `_hit` makes each body's first contact its only one.
func _bite() -> void:
	var tint := Color(_color.r, _color.g, _color.b, 1.0)
	for path: PackedVector2Array in _paths:
		var front: Vector2 = _front_of(path)
		if front == Vector2.INF:
			continue
		for e: Node in SpellTargets.in_radius(front, RIDGE_BITE, _hostiles(),
				[caster_node], self):
			var id: int = (e as Object).get_instance_id()
			if _hit.has(id):
				continue
			_hit[id] = true
			# Deflectable: the ground does not travel, so there is nothing to send
			# back and a well-timed guard EATS the wave.
			var dealt: int = SpellDeflect.resolve(e, _damage, Vector2.UP, front,
				_deflect_window())
			if dealt <= 0:
				continue
			SpellTargets.hurt(e, dealt, tint)
			if e.has_method("apply_status"):
				e.call("apply_status", element_id)   # EARTH
			if e.has_method("apply_knockback"):
				var away: float = signf((e as Node2D).global_position.x - _foot.x)
				if away == 0.0:
					away = 1.0
				e.call("apply_knockback",
					Vector2(away * KNOCK_OUT, -KNOCK_UP))
			Juice.shake_camera(3.0)
			SpellDrops.sfx("earth_impact", -8.0, 0.1, 1.25)
		for prop: Node in SpellTargets.in_radius(front, RIDGE_BITE,
				get_tree().get_nodes_in_group("destructible"), [caster_node], self):
			var pid: int = (prop as Object).get_instance_id()
			if _hit.has(pid):
				continue
			_hit[pid] = true
			if prop.has_method("damage_at"):
				prop.call("damage_at", _damage, front, Vector2.UP)
			elif prop.has_method("take_damage"):
				prop.call("take_damage", _damage)


## How far each ridge has run, in px. Clamped to the reach so a ridge stops rather
## than running off the end of its own path.
func _front_distance() -> float:
	return clampf((_elapsed - WINDUP) * RIDGE_SPEED, 0.0, _reach)


## The world point at the head of `path`.
##
## The samples are evenly spaced in X (that is how `ground_path` walks), so the index
## is the travelled fraction of the reach. Over sloping terrain the true arc length is
## slightly longer than the horizontal run, which means the wave is a few per cent slow
## up a hill. That is a deliberate approximation: exact arc-length parameterisation
## would need a cumulative-length table per cast, and nobody can see a 3 % speed
## difference on a ramp.
##
## Returns `Vector2.INF` for a path with nothing in it — a side that had no floor to
## run along at all, which the caller skips.
func _front_of(path: PackedVector2Array) -> Vector2:
	if path.size() < 2:
		return Vector2.INF
	var f: float = clampf(_front_distance() / maxf(_reach, 1.0), 0.0, 1.0)
	# The path may be SHORTER than the reach (it stopped at a pit lip), so the front
	# is clamped to the path's own end — the wave dies at the edge instead of
	# extrapolating into the void.
	var pos: float = f * float(path.size() - 1)
	var i: int = clampi(int(floor(pos)), 0, path.size() - 2)
	return path[i].lerp(path[i + 1], pos - float(i))


func _hostiles() -> Array:
	return SpellTargets.hostiles(self, StringName(target_group))


func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT \
		else SpellDeflect.WINDOW_NORMAL


# --------------------------------------------- reaction contract (SpellReactor)
## World space, centred on the FOOT — never `global_position`, which is (0, 0).
##
## ⚠ AN HONEST APPROXIMATION, written down rather than hidden: the danger is really
## two narrow bands at the ridge fronts, and this reports the whole disc out to the
## current front distance. `SpellGeometry` has circles and capsules, not annuli, and a
## reaction footprint that is slightly generous is the safe direction — it can only
## cause a clash that should arguably have happened, never miss one that should.
func reaction_shape() -> Dictionary:
	return SpellGeometry.circle(_foot, maxf(_front_distance(), RIDGE_BITE))


## LOAD-BEARING: false for the whole windup (two drawn lanes are a promise, not a
## hit) and false once the ridges have run out.
func reaction_active() -> bool:
	return _stomped and _elapsed < WINDUP + _travel_time()


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.IMPACT


func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


func reaction_consume() -> void:
	queue_free()


# ------------------------------------------------------------------ the picture
## The cheap picture (the phone, and the maker's desktop LOW preview). THE RULE:
## thin the garnish, never the read. The fracture line and the raised plates survive
## at LOW because they ARE the "where is it now" signal; the hatching behind the
## front and the dust motes are what go.
func _low() -> bool:
	return TuningConfig.quality_is_low()


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if not _stomped:
		_draw_windup()
		return
	for path: PackedVector2Array in _paths:
		_draw_ridge(path)


## The boot going up: the fracture already forming under the foot, and the two lanes'
## full extent marked with a tick at each end so the reach is a stated number and not
## a guess. Drawn on top of the Telegraph's own lanes.
func _draw_windup() -> void:
	var t: float = clampf(_elapsed / WINDUP, 0.0, 1.0)
	draw_circle(_foot, 4.0 + 9.0 * t, Color(CORE.r, CORE.g, CORE.b, 0.35 + 0.45 * t),
		true, -1.0, true)
	for sign_x: float in [1.0, -1.0]:
		var end: Vector2 = _foot + Vector2(sign_x * _reach, 0.0)
		draw_line(end + Vector2(0.0, -14.0), end + Vector2(0.0, 6.0),
			Color(_color.r, _color.g, _color.b, 0.25 + 0.35 * t), 2.0, true)


## One ridge: a fracture line drawn along the terrain up to the front, and a crest of
## raised plates AT the front. The plates are the thing the eye tracks — they are the
## only part that moves, and they sit exactly where the bite circle is.
func _draw_ridge(path: PackedVector2Array) -> void:
	if path.size() < 2:
		return
	var front: Vector2 = _front_of(path)
	if front == Vector2.INF:
		return
	var age: float = clampf((_elapsed - WINDUP - _travel_time()) / AFTER_GLOW, 0.0, 1.0)
	var fade: float = 1.0 - age
	if fade <= 0.0:
		return
	# The fracture, following the floor sample by sample. This is the part that proves
	# the effect tracks the terrain rather than sliding along one flat y.
	var travelled: float = _front_distance()
	var pts := PackedVector2Array()
	for p: Vector2 in path:
		if absf(p.x - _foot.x) > travelled + 1.0:
			break
		pts.append(p + Vector2(0.0, -2.0))
	if pts.size() >= 2:
		draw_polyline(pts, Color(_color.r * 0.7, _color.g * 0.6, _color.b * 0.5,
			0.55 * fade), 3.0, true)
		if not _low():
			# Hatching either side of the crack — the ground is BROKEN, not painted.
			for i: int in range(0, pts.size(), 2):
				var p: Vector2 = pts[i]
				draw_line(p + Vector2(-5.0, 0.0), p + Vector2(3.0, -7.0),
					Color(_color.r, _color.g, _color.b, 0.28 * fade), 1.2, true)
	if _elapsed >= WINDUP + _travel_time():
		return   # the wave is spent; only the crack is left
	var emissive: Color = Elements.emissive(element_id)
	var dir_x: float = signf(front.x - _foot.x)
	if dir_x == 0.0:
		dir_x = 1.0
	for i: int in PLATES:
		# Plates lean FORWARD and shorten with distance behind the front, so the crest
		# reads as ground being shoved up and over rather than as three identical
		# triangles.
		var back: float = float(i) * PLATE_WIDTH * 0.55
		var base: Vector2 = front - Vector2(dir_x * back, 0.0)
		var h: float = PLATE_LIFT * (1.0 - 0.26 * float(i))
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-dir_x * PLATE_WIDTH * 0.5, 2.0),
			base + Vector2(dir_x * PLATE_WIDTH * 0.35, -h),
			base + Vector2(dir_x * PLATE_WIDTH * 0.55, 2.0),
		]), Color(_color.r, _color.g, _color.b, (0.85 - 0.2 * float(i))))
	# The hot seam at the very front — thin and over 1.0, so the bloom catches the
	# LEADING EDGE and the player's eye goes to the thing that is about to touch them.
	draw_line(front + Vector2(0.0, 3.0), front + Vector2(0.0, -PLATE_LIFT - 4.0),
		Color(emissive.r, emissive.g, emissive.b, 0.9), 2.2, true)
	if _low():
		return
	# The bite circle, faintly. It is the hitbox, and drawing it is the promise that
	# nothing lands outside the picture.
	# Dim: it is the honest extent of the bite, not a feature. At 0.18 it rendered as
	# two big bubbles riding the floor and read louder than the crest inside it.
	draw_arc(front, RIDGE_BITE, 0.0, TAU, 20,
		Color(_color.r, _color.g, _color.b, 0.10), 1.0, true)
