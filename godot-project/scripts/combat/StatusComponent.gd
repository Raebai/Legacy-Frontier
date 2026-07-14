class_name StatusComponent
extends Node2D
## Elemental AILMENTS on an enemy — the thing the maker asked to make real
## ("freeze, burn, all that"). A child of the Enemy: it ticks the effect logic
## (burn damage-over-time, chill/freeze decay, weaken timer, unstable pop),
## draws the on-body overlay (flame licks / ice crust / spark arcs / smoke /
## shimmer), and exposes slow_factor() + damage_mult() for the Enemy to read
## each frame. Pure Node2D + timers — headless-safe (the DoT calls the owner's
## take_damage, which every enemy + test stub implements).
##
## Elements (Elements.Element): FIRE=Burn, ICE=Chill->Freeze, LIGHTNING=Shock
## (stun + one chain), SHADOW=Weaken (damage amp), ARCANE=Unstable (delayed pop).

const BURN_DURATION: float = 2.6
const BURN_TICK: float = 0.35
const BURN_TICK_DMG: int = 3
const CHILL_DURATION: float = 2.2
const CHILL_SLOW: float = 0.5      # half move speed while chilled
const FREEZE_DURATION: float = 0.6   # shorter — full-root freeze was oppressive ("ice is not fair")
const FREEZE_SLOW: float = 0.32    # slowed hard, not fully rooted, so it's escapable
const SHOCK_STUN: float = 0.35
const SHOCK_SLOW: float = 0.05
const SHOCK_CHAIN_RANGE: float = 150.0
const SHOCK_CHAIN_DMG: int = 8
const WEAKEN_DURATION: float = 3.2
const WEAKEN_MULT: float = 1.3     # takes +30% damage while weakened
const UNSTABLE_DURATION: float = 1.2
const UNSTABLE_POP_DMG: int = 12
const UNSTABLE_POP_RADIUS: float = 46.0

# Element indices mirror Elements.Element.
const FIRE: int = 0
const ICE: int = 1
const LIGHTNING: int = 2
const SHADOW: int = 3
const ARCANE: int = 4
# The three appended elements reuse proven ailment mechanics with their own tint
# (the overlay lerps toward _last_color): EARTH = Stagger (direct root, like a
# freeze), HOLY = Radiance (a burn DoT), WIND = Gale (a brief stun, like shock).
const EARTH: int = 5
const HOLY: int = 6
const WIND: int = 7
const STAGGER_DURATION: float = 0.7  # earth root — shorter than a full ice freeze

var _burn: float = 0.0
var _burn_tick: float = 0.0
var _chill: float = 0.0
var _freeze: float = 0.0
var _shock: float = 0.0
var _weaken: float = 0.0
var _unstable: float = 0.0
var _phase: float = 0.0
## The tint of whatever was applied last — colours the shimmer/aura accents.
var _last_color: Color = Color(0.9, 0.4, 0.85)


## Apply / refresh an ailment. `can_chain` gates the lightning hop so a chained
## shock can't re-chain forever. Reads Elements colours for the overlay tint.
func apply(element: int, can_chain: bool = true) -> void:
	_last_color = Elements.color(element)
	match element:
		FIRE:
			_burn = BURN_DURATION
		ICE:
			# Chill first; a second ice hit on an already-chilled target FREEZES it.
			if _chill > 0.0 or _freeze > 0.0:
				_freeze = FREEZE_DURATION
			else:
				_chill = CHILL_DURATION
		LIGHTNING:
			_shock = SHOCK_STUN
			if can_chain:
				_chain_shock()
		SHADOW:
			_weaken = WEAKEN_DURATION
		ARCANE:
			_unstable = UNSTABLE_DURATION
		EARTH:
			_freeze = STAGGER_DURATION   # Stagger: a direct short root (brown crust via tint)
		HOLY:
			_burn = BURN_DURATION        # Radiance: a radiant burn (gold flames via tint)
		WIND:
			_shock = SHOCK_STUN          # Gale: a brief stun (teal arcs via tint; no chain)
	queue_redraw()


## Movement multiplier the Enemy applies to its chase speed: the strongest active
## impediment wins (frozen < shocked < chilled < none).
func slow_factor() -> float:
	var f: float = 1.0
	if _chill > 0.0:
		f = minf(f, CHILL_SLOW)
	if _shock > 0.0:
		f = minf(f, SHOCK_SLOW)
	if _freeze > 0.0:
		f = minf(f, FREEZE_SLOW)
	return f


## Incoming-damage multiplier (weaken amplifies).
func damage_mult() -> float:
	return WEAKEN_MULT if _weaken > 0.0 else 1.0


## True while any ailment is active (lets the Enemy free the component when clean).
func is_active() -> bool:
	return _burn > 0.0 or _chill > 0.0 or _freeze > 0.0 or _shock > 0.0 \
			or _weaken > 0.0 or _unstable > 0.0


## True while a movement-locking ailment (freeze or shock-stun) holds — the Enemy
## uses this to suppress starting a NEW attack windup, so a frozen/shocked enemy
## is genuinely locked down (chill only slows).
func is_hard_cc() -> bool:
	return _freeze > 0.0 or _shock > 0.0


func _process(delta: float) -> void:
	_phase += delta
	if _burn > 0.0:
		_burn -= delta
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = BURN_TICK
			_deal_self(BURN_TICK_DMG)
	_chill = maxf(_chill - delta, 0.0)
	var was_frozen: bool = _freeze > 0.0
	_freeze = maxf(_freeze - delta, 0.0)
	if was_frozen and _freeze <= 0.0:
		_shatter()  # the ice breaks
	_shock = maxf(_shock - delta, 0.0)
	_weaken = maxf(_weaken - delta, 0.0)
	if _unstable > 0.0:
		_unstable -= delta
		if _unstable <= 0.0:
			_pop_unstable()
	queue_redraw()


## Damage the owning enemy (burn tick / unstable pop). Guarded so a mid-tick
## death or a detached component never crashes.
func _deal_self(amount: int) -> void:
	var owner_e: Node = get_parent()
	if owner_e != null and is_instance_valid(owner_e) and owner_e.has_method("take_damage"):
		# Pass the ailment hue so the DoT tick spawns a coloured damage number + a
		# glow-pulse in the ailment colour (the "glow w/ tick" read).
		owner_e.call("take_damage", amount, Color(_last_color.r, _last_color.g, _last_color.b, 1.0))


## Lightning hop: nearest OTHER enemy in range takes chain damage + a shock (no
## further chain), with a spark burst so the arc reads.
func _chain_shock() -> void:
	var owner_e: Node = get_parent()
	if owner_e == null or not is_instance_valid(owner_e) or not owner_e is Node2D:
		return
	var here: Vector2 = (owner_e as Node2D).global_position
	var best: Node2D = null
	var best_d: float = SHOCK_CHAIN_RANGE
	for other: Node in get_tree().get_nodes_in_group("enemy"):
		if other == owner_e or not other is Node2D or not is_instance_valid(other):
			continue
		var d: float = here.distance_to((other as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = other as Node2D
	if best == null:
		return
	if best.has_method("take_damage"):
		best.call("take_damage", SHOCK_CHAIN_DMG, Color(1.0, 0.95, 0.4, 1.0))
	if best.has_method("apply_status"):
		best.call("apply_status", LIGHTNING, false)
	CombatVfx.spawn_burst(
		get_parent().get_parent(), best.global_position,
		Color(1.0, 0.95, 0.4, 0.95), Color(1.0, 0.8, 0.2, 0.0), 10, 0.25, 60.0, 150.0
	)


## Arcane instability detonates on expiry: a small AoE pop hitting nearby enemies.
func _pop_unstable() -> void:
	var owner_e: Node = get_parent()
	if owner_e == null or not is_instance_valid(owner_e) or not owner_e is Node2D:
		return
	var here: Vector2 = (owner_e as Node2D).global_position
	CombatVfx.spawn_burst(
		owner_e.get_parent(), here,
		Color(0.95, 0.4, 0.85, 0.95), Color(0.6, 0.2, 0.7, 0.0), 20, 0.4, 80.0, 200.0
	)
	_deal_self(UNSTABLE_POP_DMG)


## The ice breaks: a quick crystal-shard burst when a freeze ends (satisfying
## "shatter" read). Sfx via a guarded lookup so headless contexts stay safe.
func _shatter() -> void:
	var owner_e: Node = get_parent()
	if owner_e == null or not is_instance_valid(owner_e) or not owner_e is Node2D:
		return
	CombatVfx.spawn_burst(
		owner_e.get_parent(), (owner_e as Node2D).global_position,
		Color(0.85, 0.97, 1.0, 0.95), Color(0.5, 0.75, 1.0, 0.0), 14, 0.35, 80.0, 200.0, 0.6, 1.8
	)
	var sfx: Node = owner_e.get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.call("play", "spell_impact", -4.0, 0.15)


# ------------------------------------------------------------------- overlay draw
## Blend an ailment's base colour toward the causing element's tint so a reused
## mechanic (EARTH→freeze, HOLY→burn, WIND→shock) still READS as its own element.
## For the native element _last_color ~= the base, so the look is unchanged.
func _ail_tint(base: Color) -> Color:
	var t: Color = base.lerp(Color(_last_color.r, _last_color.g, _last_color.b, base.a), 0.45)
	t.a = base.a
	return t


func _draw() -> void:
	var r: float = 14.0
	if _freeze > 0.0:
		_draw_freeze(r)
	elif _chill > 0.0:
		_draw_chill(r)
	if _burn > 0.0:
		_draw_burn(r)
	if _shock > 0.0:
		_draw_shock(r)
	if _weaken > 0.0:
		_draw_weaken(r)
	if _unstable > 0.0:
		_draw_unstable(r)


func _draw_burn(_r: float) -> void:
	# Realistic organic flames licking off the body (maker: "the fire effect is so
	# corny; make it more like fire" + subtle on the enemy). Two small offset flames
	# via the shared CharacterRig.draw_flame so the burn coat matches the hero's fire.
	# HOLY-radiance reuses this burn mechanic; its gold tint is carried by the
	# glow-on-tick pulse (Enemy.take_damage), so keeping the flame fire-hued is fine.
	CharacterRig.draw_flame(self, Vector2(-4.0, 2.0), 7.0, 0.85, _phase)
	CharacterRig.draw_flame(self, Vector2(5.0, 3.0), 5.5, 0.7, _phase * 1.13 + 1.7)


func _draw_chill(r: float) -> void:
	# Cyan frost sheen + a few crystal spikes.
	draw_circle(Vector2.ZERO, r * 1.05, Color(0.6, 0.9, 1.0, 0.14))
	for i: int in 6:
		var ang: float = TAU * float(i) / 6.0 + 0.2 * sin(_phase * 2.0)
		var base: Vector2 = Vector2.from_angle(ang) * r * 0.7
		var tip: Vector2 = Vector2.from_angle(ang) * r * 1.2
		draw_line(base, tip, Color(0.7, 0.92, 1.0, 0.7), 2.0)


func _draw_freeze(r: float) -> void:
	# A solid ice block: faceted cyan polygon over the body, bright rim.
	var pts := PackedVector2Array([
		Vector2(-r, -r * 1.2), Vector2(r * 0.9, -r * 1.1), Vector2(r * 1.1, r * 0.8),
		Vector2(-r * 0.8, r * 1.2), Vector2(-r * 1.15, -r * 0.2),
	])
	draw_colored_polygon(pts, _ail_tint(Color(0.55, 0.85, 1.0, 0.4)))
	draw_polyline(pts + PackedVector2Array([pts[0]]), _ail_tint(Color(0.85, 0.97, 1.0, 0.9)), 2.0)
	# Internal facet lines.
	draw_line(Vector2(-r, -r * 1.2), Vector2(r * 0.3, r), Color(1, 1, 1, 0.35), 1.0)
	draw_line(Vector2(r * 0.9, -r * 1.1), Vector2(-r * 0.4, r * 0.6), Color(1, 1, 1, 0.3), 1.0)


func _draw_shock(r: float) -> void:
	# Jagged yellow arcs crackling around the body (redrawn each frame = flicker).
	for i: int in 3:
		var a0: float = _phase * 20.0 + float(i) * 2.0
		var pts := PackedVector2Array()
		for k: int in 5:
			var ang: float = a0 + float(k) * 0.5
			var rad: float = r * (0.8 + 0.5 * float((k + i) % 2))
			pts.append(Vector2.from_angle(ang) * rad)
		draw_polyline(pts, _ail_tint(Color(1.0, 0.95, 0.4, 0.85)), 1.5)


func _draw_weaken(r: float) -> void:
	# Dark smoky aura pulsing — the "vulnerable" read.
	var pulse: float = 0.5 + 0.2 * sin(_phase * 4.0)
	draw_circle(Vector2.ZERO, r * 1.3 * pulse, Color(0.35, 0.1, 0.45, 0.16))
	for i: int in 4:
		var ang: float = -_phase * 1.5 + TAU * float(i) / 4.0
		draw_circle(Vector2.from_angle(ang) * r * 1.1, 3.0, Color(0.5, 0.2, 0.6, 0.3))


func _draw_unstable(r: float) -> void:
	# Magenta shimmer ring building toward the pop.
	var t: float = 1.0 - clampf(_unstable / UNSTABLE_DURATION, 0.0, 1.0)
	draw_arc(Vector2.ZERO, r * (1.0 + 0.4 * t), 0.0, TAU, 24, Color(0.95, 0.4, 0.85, 0.4 + 0.4 * t), 2.0)
	draw_circle(Vector2.ZERO, r * 0.2 * (0.5 + t), Color(1.0, 0.7, 0.95, 0.3 + 0.4 * t))
