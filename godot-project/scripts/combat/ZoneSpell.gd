class_name ZoneSpell
extends Node2D
## A persistent GROUND FIELD (SpellDef.Kind.ZONE) — Cryomancer's BLIZZARD (frost),
## Cleric's CONSECRATED GROUND (holy — heals allies standing in it) and the legacy
## shadow pool (Warlock's shadow ZONE now routes to ShadowRoot in the dispatcher).
## Aim-placed, lives for its lifetime, then fades. Draws in world coordinates.
##
## ── WHAT BLIZZARD IS FOR (the maker's "it's just a random zone of frost, I don't
## think it would be used much") ──────────────────────────────────────────────
## The kit already owns damage lines (beams), barriers (walls), bombardments
## (meteors) and mobility (blink/rush). The one currency nothing else in a
## four-slot loadout buys is TIME. So blizzard is no longer a puddle that chips
## 8 damage every 0.4 s — it is a FREEZE TRAP with a visible per-victim fuse:
##
##   1. RIME  — anything standing in the squall accretes rime, drawn ON that body
##              as ice climbing its legs plus a ring meter counting down over its
##              head. Step out and the meter DRAINS (RIME_DECAY). That is the
##              dodge, it is legible, and it is available every single frame.
##   2. ENCASE — at a full meter the victim is sealed in a casing: the existing
##              StatusComponent chill->freeze channel, refreshed for ENCASE_HOLD.
##              Nothing else the Cryomancer owns can take a body off the board.
##   3. SHATTER — the casing bursts for ENCASE_SHATTER_DAMAGE on that ONE body.
##              The beat the field was missing: a payoff you EARNED by holding
##              someone in it, not a tick that happened to you.
##
## Rime replaces the old per-tick apply_status(ICE) spam, which quietly chained
## chill->freeze->chill->freeze every 0.4 s: a permanent stunlock with no build,
## no tell and no counterplay — the exact thing "ice is not fair"
## (StatusComponent.FREEZE_DURATION) was shortened to avoid. One chill on entry,
## one earned encase, one shatter.
##
## It is also the kit's COMBO SUBSTRATE: the field now implements the
## SpellReactor participant contract as ReactionTable.Form.FIELD, which is the
## side of the authored `steam_cloud` (fire into frost) and `supercharge`
## (lightning into frost) rows that had no implementor. Those outcomes are
## no-ops in ReactionOutcomes today, so registering changes nothing yet — it
## means the field is present the day the outcome rows are written.
##
## ── THE RADIUS CONTRACT ──────────────────────────────────────────────────────
## "the spells shouldn't be able to get out the radius". `footprint_contains()`
## is the ONE source of truth for what is inside this field, and `_draw()` builds
## its geometry from the same radius and the same GROUND_SQUASH / cell height. A
## body outside the drawn extent takes exactly zero. See tools/slice7_test_frost_field.gd.
##
## Look: frost draws a full storm CELL above the footprint — wind-driven snow
## STREAKING sideways through the volume (the wind blows away from the caster),
## pulsing gust sheets, a ragged churning storm-front instead of a clean ring,
## and ice visibly ACCRETING on the ground for the squall's life.

const TICK: float = 0.4
const FADE: float = 0.6
const HEAL_PER_TICK: int = 6

## ── footprint geometry: shared by the draw AND the damage query ──────────────
## How long the footprint takes to ease open. Damage uses the SAME eased radius,
## so the field can never bite at a size that is not yet on screen — which is why
## there is no longer an immediate _tick() in open() (it would have hit at full
## radius against a footprint of zero).
const GROW_TIME: float = 0.18
## Vertical squash of the ground ellipse. A field lies on the FLOOR; drawing it
## face-on would be a face-on disc. Damage now uses this too.
const GROUND_SQUASH: float = 0.42

## Blizzard squall tuning — streak count/speed chosen so the motion reads at a
## glance without melting the draw pass (all polylines, one canvas item).
const SQUALL_FLAKES: int = 58
const SQUALL_WIND: float = 390.0    # horizontal drive px/s — violent, not drifting
const SQUALL_FALL: float = 90.0     # downward bias so streaks slant like sleet
const SQUALL_HEIGHT: float = 118.0  # storm cell height above the footprint
const SQUALL_HEIGHT_PER_RADIUS: float = 0.25  # wider squalls are taller squalls
const ICICLE_COUNT: int = 9

## ── rime / encase / shatter — UNTESTED FEEL GUESSES, all of them ─────────────
## Seconds of exposure to fill the meter. Long enough that a moving fight never
## trips it by accident, short enough that pinning someone in the squall for a
## beat and a half is a real play. GUESS.
const RIME_TO_ENCASE: float = 1.4
## Meter drain per second once you leave. Slower than it fills (1.0/s), so
## re-entering still costs the victim ground — but a clean exit always saves you.
## GUESS.
const RIME_DECAY: float = 0.8
## How long the casing holds before it bursts. Sits just above the 0.6 s
## StatusComponent freeze so the refresh below has something to refresh. GUESS.
const ENCASE_HOLD: float = 0.8
## Freeze re-apply cadence inside the hold — must be < FREEZE_DURATION or the
## casing visibly lets go halfway through. GUESS.
const ENCASE_REFRESH: float = 0.25
## The payoff hit. Deliberately SINGLE-TARGET: the casing is on one body, so
## there is no second AoE radius that could reach outside anything drawn. GUESS.
const ENCASE_SHATTER_DAMAGE: int = 34
## Fuse-meter placement above the victim's DRAWN head, and its size. Lifted clear
## of the floating HP bar; big enough to read through a whiteout. GUESSES.
const RIME_RING_LIFT: float = 22.0
## Hard floor above the node ORIGIN, so the ring clears the floating HP bar
## (CharacterBars is placed at -24) even for a target with no measurable rig.
const RIME_RING_MIN_LIFT: float = 48.0
const RIME_RING_RADIUS: float = 12.0

## Height above the field's floor point that cover is traced from — roughly a
## body's chest, so the ray runs level with the victim instead of grazing the
## floor the field was just snapped to. UNTESTED GUESS.
const LOS_EYE: float = 26.0
## How far down to look for the ground under the aim point.
const FLOOR_PROBE: float = 240.0

## WHO THIS SPELL MAY HURT. Stamped by SpellCaster._stamp() at cast time, so it
## follows the CASTER's faction rather than being fixed at "enemy" forever.
##
## Every spectacle used to scan the literal group "enemy", which is why a
## hero-shaped bot's spells passed harmlessly through another hero: the aim was
## right, the spectacle spawned and drew, and then it queried a group its target
## was not in. Nothing errored — the spell simply never hit anything, which reads
## as a physics bug rather than a targeting one.
##
## Defaults to "enemy", so every existing caster, capture tool and test is
## byte-identical and single player does not change by one branch.
var target_group: String = "enemy"
var element_id: int = Elements.Element.SHADOW
## Who cast this, for ReactionTable's `require_owner` predicate. SpellCaster does
## not pass a caster to the ZONE arm today, so this stays null and the field is
## "unowned" — correct, and it starts working the moment that arm sets it.
var caster_node: Node = null

var _at: Vector2 = Vector2.ZERO
var _color: Color = Color(0.6, 0.3, 0.9)
var _radius: float = 120.0
var _tick_dmg: int = 10
var _effect: String = "shadow"
var _life: float = 4.5
var _elapsed: float = 0.0
var _tick_t: float = 0.0
var _consumed: bool = false                             # spent by a reaction
var _seed: PackedFloat32Array = PackedFloat32Array()
var _wind: float = 1.0                                  # squall direction sign
var _fseed: PackedFloat32Array = PackedFloat32Array()   # per-flake px/py/speed/len
var _iseed: PackedFloat32Array = PackedFloat32Array()   # per-icicle x-frac/height
## instance_id -> {node, t, enc, ref}. `t` is rime seconds accrued, `enc` is the
## remaining casing hold (-1 = not encased). Keyed on ID, never on the node, so a
## victim that dies mid-freeze cannot keep this dictionary alive.
var _rime: Dictionary = {}


func open(
	at: Vector2, color: Color, radius: float, tick_damage: int,
	effect: String = "shadow", lifetime: float = 4.5
) -> void:
	_at = at
	_color = color
	_radius = radius
	_tick_dmg = tick_damage
	_effect = effect
	_life = lifetime
	global_position = Vector2.ZERO
	# Plant the field on the actual ground under the aim point (SpellWorld, not a
	# private raycast — see docs/spell-world-contract.md; over a pit floor_point
	# hands `at` straight back, which for a squall is fine: it blows over the hole).
	_at = SpellWorld.floor_point(at, FLOOR_PROBE, [], self)
	for i: int in 10:
		_seed.append(randf() * TAU)
	if _effect == "frost":
		_wind = _wind_sign()
		for i: int in SQUALL_FLAKES * 4:
			_fseed.append(randf())
		for i: int in ICICLE_COUNT * 2:
			_iseed.append(randf())
		# Entrance gust: a horizontal blast of driven snow so the squall ARRIVES
		# instead of fading in — the "violent weather" first impression.
		CombatVfx.spawn_burst(get_parent(), _at + Vector2(-_wind * _radius * 0.5, -46.0),
			Color(0.98, 1.05, 1.2, 0.9), Color(0.7, 0.85, 1.0, 0.0),
			18, 0.55, 260.0, 460.0, 0.5, 1.4, 0.0, 0.0, true, Vector2(_wind, -0.08), 22.0)
	Juice.shake_camera(4.0)
	Sfx.play("cast", -3.0, 0.12)
	# First bite lands exactly when the footprint finishes easing open, so the
	# damage query and the drawing agree on frame one. (The old code ticked
	# immediately, at FULL radius, before a single pixel had been drawn.)
	_tick_t = GROW_TIME
	# The FIELD side of the reaction matrix. reaction_active() keeps it inert
	# while the footprint is still opening and once it starts fading out.
	_reactor_call(&"register", [self, ReactionTable.Form.FIELD, element_id])
	queue_redraw()


func _exit_tree() -> void:
	_reactor_call(&"unregister", [self])


## Reach the reactor autoload, or do nothing. Guarded on is_inside_tree() because
## an absolute get_node path throws outside the active tree — which is exactly
## where a helper suite builds effects — and because the autoload itself can be
## absent (headless tools, a bare --script main loop).
func _reactor_call(method: StringName, args: Array) -> void:
	if not is_inside_tree():
		return
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null and reactor.has_method(method):
		reactor.callv(method, args)


# ------------------------------------------------------------ the radius contract

## Height of the drawn storm CELL above the footprint. The snow streaks, gust
## sheets and haze lobes are all built from this, and so is the damage query —
## one number, two consumers, no way for them to drift apart.
static func frost_cell_height(radius: float) -> float:
	return SQUALL_HEIGHT + radius * SQUALL_HEIGHT_PER_RADIUS


## THE ONE CONTAINMENT TEST. Everything this field does to a body — chip damage,
## rime accretion, the holy heal — asks this and nothing else, and `_draw()`
## builds its geometry from the same numbers.
##
## FROST is a COLUMN: half-width `radius`, running from the top of the drawn
## storm cell down to the bottom of the drawn ground ellipse. That is exactly the
## volume the snow is drawn in, which is why a body on a ledge inside the squall
## is fair game and a body a pixel past the edge is not.
##
## Every other zone is the flat ground ELLIPSE it draws: `radius` across,
## `radius * GROUND_SQUASH` tall. The old code damaged in a full CIRCLE of
## `radius` while drawing that ellipse, so anything up to 2.4x the visible
## vertical extent was hit while standing plainly outside the field.
static func footprint_contains(effect: String, at: Vector2, radius: float, p: Vector2) -> bool:
	if radius <= 0.0:
		return false
	var d: Vector2 = p - at
	if effect == "frost":
		if absf(d.x) > radius:
			return false
		return d.y <= radius * GROUND_SQUASH and d.y >= -frost_cell_height(radius)
	var ry: float = radius * GROUND_SQUASH
	return (d.x * d.x) / (radius * radius) + (d.y * d.y) / (ry * ry) <= 1.0


## The footprint's radius RIGHT NOW, eased open. Shared by the draw and the
## damage query — the second half of the contract above.
func _footprint_radius() -> float:
	return _radius * smoothstep(0.0, GROW_TIME, _elapsed)


## Where cover is traced FROM — the storm's core, at roughly chest height.
func _field_eye() -> Vector2:
	return _at + Vector2(0.0, -LOS_EYE)


## Is this BODY in the field? Tests the drawn SILHOUETTE, not just the origin.
## An Enemy's head centre sits ~10 px above its node origin (19 px on the 1.9x
## sparring dummies), so a column edge can fall between the two and a body
## plainly standing in the snow reads as outside — SpellTargets TRAP 2, the
## maker's "spells pass through heads". Origin OR drawn head counts.
##
## Deliberately NOT widened by SpellTargets.hit_margin, unlike the radius
## selectors there. The maker's rule here is about THIS field's radius, and a
## forgiveness ring would push damage past the rim the player can see. Testing
## the silhouette fixes the real miss without moving the drawn edge.
func _catches(target: Node2D, r: float) -> bool:
	if footprint_contains(_effect, _at, r, target.global_position):
		return true
	return footprint_contains(_effect, _at, r, SpellTargets.aim_point(target))


## Everything in `group` that is BOTH inside the drawn footprint and not behind a
## wall. The two halves of the contract in one place: shape (footprint_contains,
## via _catches) and cover (SpellWorld.filter_reachable), exactly as
## docs/spell-world-contract.md's IMPACT step prescribes. Without the second half
## a squall cast against a wall freezes whoever is standing on the far side of it.
func _bodies_in_field(group: String, r: float) -> Array:
	if r <= 0.0:
		return []
	var shortlist: Array = []
	for n: Node in get_tree().get_nodes_in_group(group):
		if not n is Node2D or not is_instance_valid(n):
			continue
		if _catches(n as Node2D, r):
			shortlist.append(n)
	if shortlist.is_empty():
		return shortlist
	return SpellWorld.filter_reachable(_field_eye(), shortlist, [], self)


## The squall blows AWAY from whoever cast it — a directional storm, not an
## isotropic puddle.
##
## Reads `caster_node` rather than hunting the nearest member of a group. The old
## version scanned group "player", which in a combat arena matches NOTHING (the
## tower hero is in "hero"; "player" is the v0.0 overworld scene). It therefore
## always fell through to the rightward fallback — a branch whose comment says it
## exists for "headless tests and deterministic captures", so in real play every
## squall blew right and the bug read as an intentional default. That is the worst
## shape of failure: silent, plausible, and self-justifying in its own comment.
##
## The caster is also strictly better than "nearest player" even when the group is
## right: a stray bystander could win the nearest test and reverse the wind of a
## storm they did not cast. SpellCaster now stamps `caster_node` on every arm.
func _wind_sign() -> float:
	if caster_node != null and is_instance_valid(caster_node) and caster_node is Node2D:
		return 1.0 if _at.x >= (caster_node as Node2D).global_position.x else -1.0
	# No caster (headless suites, detached sandboxes, reaction-spawned fields):
	# rightward, so captures stay deterministic.
	return 1.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _effect == "frost":
		_update_rime(delta)
	if _elapsed < _life and not _consumed:
		_tick_t -= delta
		if _tick_t <= 0.0:
			_tick_t = TICK
			_tick()
	# The field outliving its own fade is deliberate: a casing sealed in the last
	# half-second must still get to burst, or the payoff silently evaporates.
	if _elapsed >= _life + FADE and not _has_encased():
		queue_free()
		return
	queue_redraw()


## Chip damage + ailments for every body inside; holy zones also heal players.
## Frost deliberately does NOT re-apply its ailment here — rime owns that channel
## (see the header): a per-tick apply_status(ICE) is a chill->freeze stunlock.
func _tick() -> void:
	var r: float = _footprint_radius()
	if r <= 0.0:
		return
	var tint: Color = Color(_color.r, _color.g, _color.b, 1.0)
	for e: Node in _bodies_in_field(target_group, r):
		if e.has_method("take_damage"):
			# Enemy.take_damage already routes to the host in co-op; no gating here.
			SpellTargets.hurt(e, _tick_dmg, tint)
		if _effect != "frost" and e.has_method("apply_status"):
			e.apply_status(element_id)
	if _effect == "holy":
		# GROUP "hero", NOT "player". This healed nobody, ever. The tower hero joins
		# group "hero"; "player" belongs to the v0.0 overworld scene, which nothing in
		# a combat arena is ever in. So the consecration field's entire defining
		# mechanic was dead code — silently, with no error, because a group query that
		# matches nothing is indistinguishable from one that matched and found no one
		# in range. DrainTether's life-drain had the identical bug and was equally
		# dead. Group-name drift between the v0.0 and v2.0 layers is the hazard here:
		# both names are live somewhere in the repo, so neither reads as wrong.
		for pl: Node in _bodies_in_field("hero", r):
			if pl.has_method("heal"):
				pl.call("heal", HEAL_PER_TICK)
	if _effect == "frost":
		# Wind-driven sleet gust from the upwind edge — the tick reads as WEATHER
		# pushing through, not motes floating up out of a stain.
		CombatVfx.spawn_burst(get_parent(), _at + Vector2(-_wind * r * 0.7, -30.0 - randf() * 60.0),
			Color(0.95, 1.0, 1.12, 0.8), Color(0.7, 0.85, 1.0, 0.0),
			10, 0.45, 240.0, 380.0, 0.5, 1.2, 0.0, 0.0, true, Vector2(_wind, 0.14), 16.0)
	else:
		# A soft upward pulse of motes at the tick so the field reads as "active".
		CombatVfx.spawn_burst(get_parent(), _at + Vector2(0.0, 4.0),
			Color(_color.r, _color.g, _color.b, 0.7), Color(_color.r, _color.g, _color.b, 0.0),
			8, 0.5, 30.0, 70.0, 0.6, 1.6, 0.0, 0.0, true)


# ------------------------------------------------------------ rime -> encase -> shatter

## Per-FRAME (not per-tick) so the meter and the drain are smooth and the casing
## hold has real resolution. The enemy group is a handful of bodies; this is the
## same scan `_tick` already does, four times as often.
func _update_rime(delta: float) -> void:
	var r: float = _footprint_radius()
	var live: bool = not _consumed and _elapsed < _life
	# Resolve "who is in the squall" ONCE per frame — filter_reachable casts a ray
	# per candidate, so asking it inside the per-body loop below would cast the
	# same rays twice.
	var caught: Dictionary = {}
	if live:
		for n: Node in _bodies_in_field(target_group, r):
			caught[n.get_instance_id()] = true
	var seen: Dictionary = {}
	for e: Node in get_tree().get_nodes_in_group(target_group):
		if not e is Node2D or not is_instance_valid(e):
			continue
		var n: Node2D = e as Node2D
		var id: int = n.get_instance_id()
		seen[id] = true
		# has()/[] rather than get(id, {...}) — the default of get() is built
		# eagerly, so the convenient form would allocate a throwaway dictionary per
		# tracked body per frame.
		var rec: Dictionary = _rime[id] if _rime.has(id) \
			else {"node": n, "t": 0.0, "enc": -1.0, "ref": 0.0}
		if float(rec["enc"]) >= 0.0:
			_hold_encase(rec, n, delta)
		elif caught.has(id):
			# Entry chill, applied ONCE. A second ICE application on an already
			# chilled body is what freezes it, so refreshing here would be the very
			# stunlock this rework removed — the encase is the only freeze.
			if float(rec["t"]) <= 0.0 and n.has_method("apply_status"):
				n.apply_status(element_id)
			rec["t"] = float(rec["t"]) + delta
			if float(rec["t"]) >= RIME_TO_ENCASE:
				_encase(rec, n)
		else:
			rec["t"] = maxf(float(rec["t"]) - RIME_DECAY * delta, 0.0)
		if float(rec["t"]) <= 0.0 and float(rec["enc"]) < 0.0:
			_rime.erase(id)
		else:
			_rime[id] = rec
	# Anything that died or left the group stops being tracked. keys() is a copy,
	# so erasing inside this loop is safe.
	for id: int in _rime.keys():
		if not seen.has(id):
			_rime.erase(id)


func _has_encased() -> bool:
	for id: int in _rime:
		if float((_rime[id] as Dictionary)["enc"]) >= 0.0:
			return true
	return false


## The meter filled: seal them. Two ICE applications because StatusComponent's
## first application only chills — the second, on an already-chilled body, is the
## freeze. Applying twice guarantees the casing even if the entry chill lapsed.
func _encase(rec: Dictionary, n: Node2D) -> void:
	rec["enc"] = ENCASE_HOLD
	rec["ref"] = ENCASE_REFRESH
	rec["t"] = RIME_TO_ENCASE
	if n.has_method("apply_status"):
		n.apply_status(element_id)
		n.apply_status(element_id)
	var p: Vector2 = n.global_position
	CombatVfx.spawn_burst(get_parent(), p, Color(1.05, 1.35, 1.7, 0.95),
		Color(0.5, 0.75, 1.0, 0.0), 20, 0.45, 60.0, 200.0, 0.6, 1.8, 0.0, 0.0, true)
	# `ice_encase` — the casing sealing shut, NOT the generic `ice` stem. Blizzard's
	# three beats (rime / encase / shatter) are the whole spell, and until now only
	# the CAST made a sound: the fuse filled, the body sealed and the casing burst in
	# silence. Three distinct recordings are what make the beats readable by ear.
	Juice.on_hit({"dir": Vector2.UP, "shake": 5.0, "sfx": "ice_encase",
		"sfx_pitch": -0.1, "hitstop": 0.035})


## Hold the casing shut, then burst it. The refresh cadence has to beat
## StatusComponent.FREEZE_DURATION or the victim visibly thaws mid-casing.
func _hold_encase(rec: Dictionary, n: Node2D, delta: float) -> void:
	rec["enc"] = float(rec["enc"]) - delta
	rec["ref"] = float(rec["ref"]) - delta
	if float(rec["enc"]) > 0.0 and float(rec["ref"]) <= 0.0:
		rec["ref"] = ENCASE_REFRESH
		if n.has_method("apply_status"):
			n.apply_status(element_id)
	if float(rec["enc"]) <= 0.0:
		_shatter_casing(n)
		rec["enc"] = -1.0
		rec["t"] = 0.0  # the fuse resets — a second encase has to be earned again


## THE PAYOFF. Single body, no AoE: the casing is on THEM, so there is no second
## radius here that could reach past anything drawn.
func _shatter_casing(n: Node2D) -> void:
	if n == null or not is_instance_valid(n):
		return
	var p: Vector2 = n.global_position
	if n.has_method("take_damage"):
		SpellTargets.hurt(n, ENCASE_SHATTER_DAMAGE, Color(0.72, 0.92, 1.0, 1.0))
	DebrisChunk.spawn_burst(get_parent(), p, Color(0.78, 0.92, 1.0), 14, Vector2.UP, 300.0)
	CombatVfx.spawn_burst(get_parent(), p, Color(1.2, 1.5, 1.85, 0.95),
		Color(0.5, 0.75, 1.0, 0.0), 26, 0.5, 90.0, 300.0, 0.7, 2.2, 0.0, 0.0, true)
	# `ice_shatter` — the casing BURSTING, a different recording from the sealing
	# above. Same reasoning as the impact frame below: this is the field's one
	# sudden beat, so it is the one that earns a distinct sound.
	Juice.on_hit({"dir": Vector2.UP, "shake": 9.0, "zoom": 0.05, "sfx": "ice_shatter",
		"sfx_pitch": 0.14, "hitstop": 0.05})
	# THE ENCASED TARGET SHATTERING is this field's payoff moment — the one beat
	# in a slow zone spell that is sudden — so it is the one that gets punctuated,
	# in the field's own element. Deliberately NOT on the per-tick chill damage,
	# which fires on a cadence for the whole life of the storm: a mark on a
	# cadence is a strobe with extra steps. Camera + freeze suppressed.
	Juice.tier_frame(SpellTier.Tier.HEAVY, p, element_id,
		{"style": ImpactFrame.Style.COLOR_FIELD,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


# ------------------------------------------------------------ reaction participant

## World-space, built from this field's own points — NEVER global_position, which
## is (0,0) because every spectacle parks at the arena origin (see SpellGeometry).
## A circle centred in the storm cell: the reactor only needs to know two effects
## are in the same place, and it is deliberately not the damage query, which is
## the tighter `footprint_contains` above.
func reaction_shape() -> Dictionary:
	var r: float = _footprint_radius()
	if _effect == "frost":
		return SpellGeometry.circle(_at - Vector2(0.0, frost_cell_height(r) * 0.35), r)
	return SpellGeometry.circle(_at, r)


## LOAD-BEARING: inert while the footprint is still easing open (nothing to react
## with yet) and once the field starts fading out (a spent field must not eat a
## beam on its way out).
func reaction_active() -> bool:
	return not _consumed and _elapsed < _life and _footprint_radius() > 1.0


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.FIELD


func reaction_owner() -> Node:
	return caster_node


## Spent by a reaction (fire boils this into steam). Stop damaging immediately
## and run the normal fade so the field visibly boils off rather than popping.
func reaction_consume() -> void:
	if _consumed:
		return
	_consumed = true
	_life = minf(_life, _elapsed)
	CombatVfx.spawn_burst(get_parent(), _at + Vector2(0.0, -20.0),
		Color(0.9, 0.95, 1.0, 0.7), Color(0.8, 0.85, 0.9, 0.0),
		18, 0.7, 40.0, 120.0, 1.4, 3.2, 0.0, 0.0, false, Vector2.UP, 30.0)


# ------------------------------------------------------------ drawing

func _draw() -> void:
	var alpha: float = 1.0
	if _elapsed >= _life:
		alpha = clampf(1.0 - (_elapsed - _life) / FADE, 0.0, 1.0)
	var r: float = _footprint_radius()
	if _effect == "frost":
		if r > 1.0 and alpha > 0.0:
			_draw_squall(r, alpha)  # blizzard owns its whole look — no generic puddle
		# Rime rides its OWN alpha: a casing sealed in the last half-second has to
		# stay visible while the field behind it fades out.
		_draw_rime()
		return
	if r <= 1.0:
		return
	# Flat ground ellipse (squashed y) — a field on the floor, not a face-on disc.
	# GROUND_SQUASH is the same constant footprint_contains() damages through.
	draw_set_transform(_at, 0.0, Vector2(1.0, GROUND_SQUASH))
	# Soft fill + rotating ring.
	draw_circle(Vector2.ZERO, r, Color(_color.r, _color.g, _color.b, 0.14 * alpha), true, -1.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(_color.r, _color.g, _color.b, 0.6 * alpha), 2.2, true)
	draw_arc(Vector2.ZERO, r * 0.7, _elapsed * 1.2, _elapsed * 1.2 + 4.5, 24,
		Color(_color.r, _color.g, _color.b, 0.4 * alpha), 1.6, true)
	# Effect-flavoured fill drawn in the same flat frame.
	match _effect:
		"holy":
			_draw_radiance(r, alpha)
		_:
			_draw_tendrils(r, alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## BLIZZARD: a violent, directional storm cell. Layer order matters — ground ice
## first (behind), then haze, gust sheets, and the snow streaks on top so the
## motion is the loudest read. Every alpha rides `alpha` so the fade-out kills
## the whole cell together.
func _draw_squall(r: float, alpha: float) -> void:
	var acc: float = smoothstep(0.0, _life * 0.65, _elapsed)  # ice accretion build
	var h: float = frost_cell_height(r)  # the same height the damage query uses
	# ---- ground plane (squashed frame): cold shadow, accreting slab, ragged rim.
	draw_set_transform(_at, 0.0, Vector2(1.0, GROUND_SQUASH))
	draw_circle(Vector2.ZERO, r, Color(0.10, 0.16, 0.30, 0.16 * alpha), true, -1.0, true)
	draw_circle(Vector2.ZERO, r * (0.5 + 0.4 * acc),
		Color(0.62, 0.82, 0.98, (0.07 + 0.13 * acc) * alpha), true, -1.0, true)
	# Ragged storm-front: jittered rim dashes rotating with the wind — a churning
	# edge, deliberately NOT the clean ring every other zone had. `jag` never
	# exceeds 1.0 of r, so the loudest edge cue stays inside the damaged extent.
	for i: int in 26:
		var a0: float = TAU * float(i) / 26.0 + _elapsed * 0.9 * _wind
		var jag: float = 0.86 + 0.14 * sin(_seed[i % 10] * 7.0 + _elapsed * 5.0 + float(i))
		var flick: float = 0.35 + 0.30 * absf(sin(float(i) * 1.7 + _elapsed * 3.0))
		var span: float = 0.10 + 0.12 * _seed[(i + 3) % 10] / TAU
		draw_arc(Vector2.ZERO, r * jag, a0, a0 + span, 4,
			Color(0.80, 0.93, 1.05, flick * alpha), 2.0, true)
	# Inner vortex arcs — fast counter-rotating swirls say "cyclone", cheaply.
	draw_arc(Vector2.ZERO, r * 0.62, _elapsed * 2.6 * _wind, _elapsed * 2.6 * _wind + 2.2, 18,
		Color(0.85, 0.95, 1.1, 0.22 * alpha), 1.8, true)
	draw_arc(Vector2.ZERO, r * 0.40, -_elapsed * 3.4 * _wind, -_elapsed * 3.4 * _wind + 1.7, 14,
		Color(0.9, 1.0, 1.15, 0.18 * alpha), 1.4, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# ---- icicles accreting upward off the slab (world frame, grow with `acc`).
	for i: int in ICICLE_COUNT:
		var xfrac: float = _iseed[i * 2]
		var hmul: float = _iseed[i * 2 + 1]
		var ih: float = acc * (6.0 + 13.0 * hmul)
		if ih < 2.0:
			continue
		var base: Vector2 = _at + Vector2((xfrac * 2.0 - 1.0) * r * 0.7, 2.0)
		var tip: Vector2 = base + Vector2(0.0, -ih)
		draw_line(base + Vector2(-2.2, 0.0), tip, Color(0.75, 0.90, 1.0, 0.75 * alpha), 1.4, true)
		draw_line(base + Vector2(2.2, 0.0), tip, Color(0.85, 0.95, 1.05, 0.6 * alpha), 1.2, true)
		# HDR glint on the tip so the accretion sparkles under bloom.
		var glint: float = 0.5 + 0.4 * sin(_elapsed * 9.0 + xfrac * 20.0)
		draw_circle(tip, 1.1, Color(1.3, 1.55, 1.8, glint * acc * alpha), true, -1.0, true)
	# ---- whiteout haze: translucent lobes drifting inside the cell. Two nested
	# discs per lobe = a cheap soft gradient, so no hard "UFO disc" edge shows.
	for i: int in 3:
		var ph: float = _elapsed * (0.6 + 0.2 * float(i)) + _seed[i]
		draw_set_transform(_at + Vector2(sin(ph) * r * 0.3, -h * (0.30 + 0.20 * float(i))),
			0.0, Vector2(1.25, 0.5))
		var la: float = (0.030 + 0.012 * float(i)) * alpha
		draw_circle(Vector2.ZERO, r * (0.5 + 0.12 * float(i)),
			Color(0.86, 0.93, 1.0, la), true, -1.0, true)
		draw_circle(Vector2.ZERO, r * (0.32 + 0.08 * float(i)),
			Color(0.9, 0.96, 1.05, la * 1.4), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# ---- gust sheets: broad curved bands of driven snow, pulsing like gusts.
	for g: int in 3:
		var env: float = 0.35 + 0.65 * maxf(0.0, sin(_elapsed * (1.6 + 0.4 * float(g)) + _seed[g] * 3.0))
		var pts := PackedVector2Array()
		for k: int in 13:
			var u: float = float(k) / 12.0
			var gy: float = -h * (0.30 + 0.18 * float(g)) \
				+ sin(u * 4.5 - _wind * _elapsed * (5.0 + float(g)) + _seed[g]) * h * 0.10
			pts.append(_at + Vector2((u * 2.0 - 1.0) * r, gy))
		draw_polyline(pts, Color(1.0, 1.05, 1.15, 0.10 * env * alpha), 10.0, true)
		draw_polyline(pts, Color(0.92, 0.97, 1.05, 0.16 * env * alpha), 5.0, true)
	# ---- the snow itself: fast, slanted, wind-driven streaks wrapping the cell.
	for i: int in SQUALL_FLAKES:
		var px: float = _fseed[i * 4]
		var py: float = _fseed[i * 4 + 1]
		var sm: float = 0.7 + 0.7 * _fseed[i * 4 + 2]
		var lm: float = 0.6 + 0.8 * _fseed[i * 4 + 3]
		var vel := Vector2(_wind * SQUALL_WIND * sm, SQUALL_FALL * (0.5 + 0.5 * sm))
		var x: float = fposmod(px * r * 2.0 + _elapsed * vel.x, r * 2.0) - r
		var y: float = -h + fposmod(py * h + _elapsed * vel.y, h)
		# Fade at the cell edges so streaks never pop in/out of existence.
		var edge: float = (1.0 - pow(absf(x) / r, 2.4)) \
			* (1.0 - pow(absf(y + h * 0.5) / (h * 0.5), 3.0))
		if edge <= 0.03:
			continue
		var head: Vector2 = _at + Vector2(x, y)
		var dir: Vector2 = vel.normalized()
		# Tapered streak: bright short head + long faint tail = MOTION, not dots.
		# Length is scaled by `edge`, which is zero at the rim and already below the
		# 0.03 cull by |x| ~ 0.99r — so a tail leaving the column is bounded to a
		# couple of pixels of near-invisible line and the drawn snow stays inside
		# the half-width that `footprint_contains` damages through.
		var streak: float = (12.0 + 16.0 * lm) * edge
		draw_line(head, head - dir * streak * 0.4,
			Color(1.0, 1.08, 1.2, edge * alpha), 2.2, true)
		draw_line(head - dir * streak * 0.35, head - dir * streak,
			Color(0.8, 0.9, 1.0, 0.5 * edge * alpha), 1.3, true)
		if i % 5 == 0:  # sparse HDR sleet glints so the storm sparkles under bloom
			draw_circle(head, 1.2, Color(1.35, 1.55, 1.8, 0.7 * edge * alpha), true, -1.0, true)


## The fuse, drawn ON the victim. This is the whole legibility argument for the
## rework: the player can see how close a body is to being sealed, and the body's
## owner can see they need to leave.
func _draw_rime() -> void:
	for id: int in _rime:
		var rec: Dictionary = _rime[id]
		var n: Variant = rec["node"]
		if n == null or not is_instance_valid(n):
			continue
		var p: Vector2 = (n as Node2D).global_position
		var enc: float = float(rec["enc"])
		if enc >= 0.0:
			_draw_casing(p, 1.0 - clampf(enc / ENCASE_HOLD, 0.0, 1.0))
		else:
			# The meter hangs off the DRAWN head so it scales itself on the 1.9x
			# sparring dummies — but with a hard floor measured from the ORIGIN,
			# because the floating HP bar sits at -24 there and a first pass with
			# only the head anchor still landed the ring on top of it (a target
			# whose rig is missing falls back to the origin, and short rigs put the
			# head barely above it). Whichever anchor is higher wins.
			var head: Vector2 = SpellTargets.aim_point(n)
			var ring := Vector2(p.x,
				minf(head.y - RIME_RING_LIFT, p.y - RIME_RING_MIN_LIFT))
			_draw_accretion(p, ring, clampf(float(rec["t"]) / RIME_TO_ENCASE, 0.0, 1.0))


## Rime climbing a body: a frost pool at the feet, crystal spurs growing up the
## legs, and a ring meter over the head that closes as the fuse burns.
func _draw_accretion(p: Vector2, ring: Vector2, f: float) -> void:
	if f <= 0.02:
		return
	var foot: Vector2 = p + Vector2(0.0, 15.0)
	draw_set_transform(foot, 0.0, Vector2(1.0, GROUND_SQUASH))
	draw_circle(Vector2.ZERO, 8.0 + 12.0 * f, Color(0.72, 0.90, 1.0, 0.22 * f), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i: int in 5:
		var sx: float = (float(i) / 4.0 - 0.5) * 22.0
		var sh: float = (5.0 + 11.0 * fmod(_seed[i] * 0.37, 1.0)) * f
		var base: Vector2 = foot + Vector2(sx, -2.0)
		draw_line(base, base + Vector2(sx * 0.06, -sh), Color(0.78, 0.93, 1.05, 0.75 * f), 1.6, true)
	# The meter. HDR so it blooms and reads across a whiteout, and drawn over a dark
	# backing disc because a thin cyan arc alone disappears into driven snow.
	draw_circle(ring, RIME_RING_RADIUS + 2.0, Color(0.04, 0.07, 0.14, 0.55), true, -1.0, true)
	draw_arc(ring, RIME_RING_RADIUS, 0.0, TAU, 28, Color(0.5, 0.7, 0.9, 0.35), 1.6, true)
	draw_arc(ring, RIME_RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * f, 28,
		Color(1.15, 1.5, 1.85, 0.95), 3.0, true)


## The casing: a faceted shell over the body with cracks that widen toward the
## burst, so the shatter is telegraphed on the body itself rather than arriving.
func _draw_casing(p: Vector2, k: float) -> void:
	var r: float = 21.0 + 3.0 * k
	var pts := PackedVector2Array([
		p + Vector2(-r, -r * 1.15), p + Vector2(r * 0.92, -r * 1.05),
		p + Vector2(r * 1.08, r * 0.85), p + Vector2(-r * 0.82, r * 1.18),
		p + Vector2(-r * 1.12, -r * 0.18),
	])
	draw_colored_polygon(pts, Color(0.52, 0.82, 1.0, 0.30))
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(1.0, 1.5, 1.9, 0.85), 2.0, true)
	# Cracks race out from the core as the hold burns down.
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + _seed[i % 10]
		var d: Vector2 = Vector2.from_angle(a)
		draw_line(p + d * r * 0.15, p + d * r * (0.2 + 0.8 * k),
			Color(1.3, 1.7, 2.0, 0.35 + 0.5 * k), 1.0 + 1.2 * k, true)
	if k > 0.82:  # the tell that the burst is one beat away
		var flash: float = (k - 0.82) / 0.18
		draw_circle(p, r * (0.4 + 0.5 * flash), Color(1.4, 1.7, 2.0, 0.35 * flash), true, -1.0, true)


## Void zone: writhing dark tendrils reaching in from the rim (legacy shadow
## fill — kept for any ZONE def that still routes shadow here).
func _draw_tendrils(r: float, alpha: float) -> void:
	for i: int in _seed.size():
		var a0: float = _seed[i] + _elapsed * 0.6
		var pts := PackedVector2Array()
		for k: int in 5:
			var t: float = float(k) / 4.0
			var wob: float = sin(_elapsed * 4.0 + _seed[i] + t * 6.0) * 8.0 * (1.0 - t)
			var ang: float = a0 + wob * 0.02
			pts.append(Vector2.from_angle(ang) * r * (1.0 - t * 0.75) + Vector2.from_angle(ang).orthogonal() * wob)
		draw_polyline(pts, Color(0.35, 0.12, 0.5, 0.55 * alpha), 2.4, true)


## Consecrated ground: radiant spokes + a bright bloom (heals allies).
func _draw_radiance(r: float, alpha: float) -> void:
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0 + _elapsed * 0.3
		draw_line(Vector2.from_angle(a) * r * 0.2, Vector2.from_angle(a) * r * 0.9,
			Color(1.3, 1.15, 0.6, 0.4 * alpha), 1.6, true)
	draw_circle(Vector2.ZERO, r * 0.3, Color(1.4, 1.2, 0.7, 0.35 * alpha), true, -1.0, true)
