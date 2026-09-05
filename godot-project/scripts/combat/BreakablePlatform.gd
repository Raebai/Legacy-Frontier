class_name BreakablePlatform
extends StaticBody2D
## A platform you can stand/jump on AND destroy — then it REGENERATES naturally
## after a while (the maker's ask). A lean single-hp break/reform state machine
## (NOT DestructibleTerrain's cell-grid, which frees permanently on shatter):
## spells / melee / hard knockback-slams chew its hp; at zero it shatters into
## debris, drops its collider + visual for `regen_time`, warns with a fading
## outline in the last second, then reforms with a poof. An amber rim marks it as
## the breakable one (permanent ledges have a green rim). Group "destructible" +
## take_damage/damage_at is the damage-routing contract (like DestructibleTerrain).

@export var platform_size: Vector2 = Vector2(160, 22)
@export var max_hp: int = 50
@export var regen_time: float = 6.0
@export var base_color: Color = Color(0.20, 0.22, 0.29)

const REFORM_WARNING_TIME: float = 1.0

## ══ IT CARVES INTO BITS NOW, AND THE WHOLE-SLAB SHATTER IS WHAT IT ENDS IN ══
## Maker: *"please make the floating platforms destroyable into bits just like the floor
## was beforehand as well"*. The header above still describes a "lean single-hp
## break/reform state machine" and that half is intact — hp still decides WHEN the ledge
## goes, the co-op wire is untouched, the regen is untouched. What changed is that every
## hit now also takes a bite out of a `DestructibleStage` chunk grid hung on this body
## (`DestructibleStage.attach_ledge`), so the ledge visibly loses chunks on the way down
## instead of standing pristine at 3 hp and then vanishing.
##
## ⚠ ROUTED BY `BODY_META`, NEVER BY `DestructibleStage.GROUP_NAME`. `stage_in` returns
## THE FIRST MEMBER of that group, so twenty ledges in it would send every `carve_area`
## in the game to whichever one sorted first. See `DestructibleStage.advertise_in_group`.
## Ledges are reached two ways instead, both per-body: this `damage_at` (the
## `"destructible"` group contract, which is how every bolt already found this node) and
## `carve_from_body`, which reads the meta off the collider that was actually hit.

## ══ HOW SMALL BEFORE IT SHOULD JUST GO ═════════════════════════════════════
## A plank chewed down to a two-chunk splinter you can still technically balance on is
## worse than a clean break: it reads as broken, it is not, and it silently keeps a
## route open that the fight has visibly closed. Two rules, and the SECOND is the one
## that matters.
##
## `COLLAPSE_SOLID_FRACTION` — bulk. Under a third of its rock left, the ledge goes.
##
## `MIN_STANDABLE_RUN` — shape, and the real test. What survives has to be a landing,
## not a sliver: `widest_standable_run` measures the widest UNBROKEN span still holding
## rock, because a plank carved into three 8 px slivers has a perfectly healthy
## fraction and nothing whatever to land on. 24 px is the fighter's own footprint plus a
## margin — the body collider under the 31 px rig is 18 px wide
## ([[feedback_rig_feet_vs_collider]]), so anything narrower than this cannot hold one.
const COLLAPSE_SOLID_FRACTION: float = 0.34
const MIN_STANDABLE_RUN: float = 24.0

## ══ AND WHY A CARVED LEDGE HEALS ═══════════════════════════════════════════
## The same argument that made "shatters and re-forms" load-bearing: `FloorGen` reasons
## about REACHABLE SURFACES when it lays a floor out, so a ledge that stays permanently
## holed can strand a spawn point or a pickup above a gap nothing can cross — and unlike
## a shattered ledge, a HOLED one leaves no amber outline to say it is coming back, so
## the stranding would be silent. Permanent loss would need a reachability argument this
## does not have.
##
## So carving arms the same clock the break does. Every fresh bite refreshes it; when it
## runs out the grid is rebuilt whole with a quiet poof — no shake, no sound, because
## this is a plank knitting a hole shut and not a platform materialising.
const REPAIR_POOF_COUNT: int = 8
## Ledge-sized rubble per bite. This is a plank losing a chunk, not the ult that took
## it: `DestructibleStage`'s own spectacle throws `ArenaTerrain.ROCK_UPPER` chips and
## stamps a `radius * 0.9` crack, which is right for a hole in the world's floor and
## absurd on a 24 px plank — so the grid's `spectacle` is off and this is what fires.
const CARVE_DEBRIS: int = 3
const CARVE_DEBRIS_LOW: int = 1
## ⚠ AMBER IS RULE 2 OF THE STAGE LEGEND (see StageLayers): a lit cap says "you can
## land here", and amber says "and it breaks". Both come from StageLayers so this
## ledge and a permanent one are the same shape in different paint — which is the
## only way the difference between them is learnable at 31 px.
const BREAK_EDGE_COLOR: Color = StageLayers.BREAK_AMBER
const HIT_FLASH_TIME: float = 0.09
const HIT_NUDGE: float = 2.0
const REFORM_POOF_START: Color = Color(0.75, 0.85, 1.0, 0.9)
const REFORM_POOF_END: Color = Color(0.75, 0.85, 1.0, 0.0)

var hp: int = 50
var _broken: bool = false
var _regen_timer: float = 0.0
var _flash_timer: float = 0.0
var _nudge: Vector2 = Vector2.ZERO
## The chunk grid. It installs its merged shapes onto THIS body (borrowed-body mode),
## so there is no separate `_collider` any more — the collision a fighter stands on IS
## the surviving rock.
var _grid: DestructibleStage = null
## Counts down while the ledge is standing but holed. Distinct from `_regen_timer`,
## which only runs while it is gone: one repairs a surface, the other restores a whole
## platform, and they must not share a clock or a bite in the last second before a
## reform would cancel the reform.
var _repair_timer: float = 0.0
## Cached once — never per-draw, per-carve or per-frame (mobile-first, 640x360 base).
var _low: bool = false


func _ready() -> void:
	# ⚠ THE BUG THE MAKER PLAYED INTO. This drawer set no z_index at all, so it sat
	# at 0 — the fighters' own layer — and drew among them. See StageLayers.
	StageLayers.apply(self, StageLayers.PLATFORM)
	add_to_group("destructible")
	add_to_group("breakable_platform")
	hp = max_hp
	collision_layer = 5  # bit1 (blocks + supports movement) + bit3 (spell-Area2D bucket)
	_low = TuningConfig.quality_is_low()
	# ⚠ THE SINGLE `RectangleShape2D` IS GONE. It was one box the width of the ledge, so
	# the ledge was solid until the frame it was not. The grid hands back the same
	# geometry to begin with (one merged rect over a full slab) and then LOSES PIECES OF
	# IT, which is the whole ask. Built in `_ready` and not deferred: `platform_size` is
	# set before `add_child` by `FloorBuilder` (its comment says why), and the grid is in
	# LOCAL space, so unlike a world-space grid it does not have to wait for
	# `global_position` to be assigned after the add.
	_grid = DestructibleStage.attach_ledge(self, platform_size, base_color)
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		if _flash_timer <= 0.0:
			_nudge = Vector2.ZERO
		queue_redraw()
	if _broken:
		_regen_timer -= delta
		if _regen_timer <= REFORM_WARNING_TIME:
			queue_redraw()  # fade the "it's coming back" outline in
		if _regen_timer <= 0.0:
			_reform()
		return
	# STANDING BUT HOLED. See `REPAIR_POOF_COUNT`'s block: a carved ledge has to come
	# back or `FloorGen`'s reachability reasoning quietly stops being true.
	if _repair_timer > 0.0:
		_repair_timer -= delta
		if _repair_timer <= 0.0:
			_repair()


## Group contract entry (blind damage): chew from the centre.
func take_damage(amount: int) -> void:
	damage_at(amount, global_position, Vector2.UP)


## ⚠ HOST-AUTHORITATIVE, AND THIS ONE IS COLLISION GEOMETRY, NOT PAINT.
##
## `DestructibleProp` (the crate) was made host-authoritative because a crate that
## broke on one phone only is a fairness bug. This platform had the identical hole
## and a worse consequence: `_break` disables the collider, so a desynced platform
## is SOLID GROUND ON ONE SCREEN AND OPEN AIR ON THE OTHER. Position is synced from
## the owner, so both screens draw the hero at the same coordinates while one of
## them is standing on nothing.
##
## It is live, not theoretical: `FloorGen` rolls `"breakable"` per ledge and
## `FloorBuilder.build_platforms` instantiates them into every generated floor.
##
## Same shape as the crate: enemy attack twins are `visual_only`, so enemy-sourced
## damage lands on the host alone. The host is the one peer that sees every damage
## source, so it decides and broadcasts ABSOLUTE hp. The client still flinches for
## feedback but is FLOORED AT 1 — it must never break a platform out from under its
## own player, because it has no way to put the ground back.
##
## Reuses the crate's wire verbatim (`broadcast_prop_state` -> `destructible` group
## -> `net_apply_prop_state`), so this needs no change in Net.gd.
##
## REGEN IS DELIBERATELY LEFT LOCAL. Both peers run the same `regen_time` from
## their own break, so they reform one network latency apart rather than in
## lockstep. That is tens of milliseconds on the LAN this ships for, it is
## self-correcting, and paying a packet to tighten it would buy nothing a player
## could perceive.
##
## ⚠ THE CARVE RUNS ON EVERY PEER; ONLY THE COLLAPSE IS THE HOST'S. That is not a
## loosening of the rule above, it is the same rule applied to two different things.
## The break is a VERDICT — it must be taken once and broadcast, or one screen has
## ground the other does not. A carve is DERIVED: both peers see the same hit at the
## same point with the same damage and remove the same cells, so the two grids converge
## on their own. It is the identical argument `Spell._try_damage` writes down for why
## even a cosmetic twin still carves the ground.
func damage_at(amount: int, world_pos: Vector2, dir: Vector2,
		footprint: float = 0.0, source: Object = null) -> void:
	if _broken:
		return
	_carve(amount, world_pos, dir, footprint, source)
	var net: Node = get_node_or_null(^"/root/Net")
	var coop: bool = net != null and net.has_method(&"is_active") and bool(net.call(&"is_active"))
	if coop and not bool(net.call(&"is_host")):
		hp = maxi(hp - amount, 1)   # predicted, never fatal — the host owns the break
		_hit_feedback(world_pos)
		return
	hp = max(hp - amount, 0)
	if hp == 0 or _is_splintered():
		# Broadcast BEFORE breaking: the receiver finds this node by its position in
		# the `destructible` group, and `_break` removes it from that group.
		if coop:
			net.call(&"broadcast_prop_state", self, 0, true)
		_break(dir)
		return
	_hit_feedback(world_pos)
	if coop:
		net.call(&"broadcast_prop_state", self, hp, false)


## The host's verdict, applied verbatim. Absolute hp, so a client that predicted a
## few hits of its own is corrected rather than compounded.
func net_apply_prop_state(hp_now: int, shattered: bool) -> void:
	if _broken:
		return
	hp = maxi(hp_now, 0)
	if shattered or hp <= 0:
		hp = 0
		_break(Vector2.UP)
		return
	_hit_feedback(global_position)


## Take a bite out of the grid at the point the hit landed, and arm the repair clock.
##
## Everything about HOW BIG the bite is belongs to `DestructibleStage` and is deliberately
## not second-guessed here: the ledge does not get its own opinion of what counts as a
## heavy hit, for the same reason `Spell` does not get one about the ground.
func _carve(amount: int, world_pos: Vector2, dir: Vector2,
		footprint: float, source: Object) -> void:
	if _grid == null or not is_instance_valid(_grid):
		return
	if _grid.damage_at(amount, world_pos, dir, footprint, source) <= 0:
		return
	# Refreshed, not accumulated: a ledge under sustained fire stays holed for as long as
	# it is being hit and knits up `regen_time` after the last bite.
	_repair_timer = regen_time
	DebrisChunk.spawn_burst(get_parent(), world_pos, base_color.lightened(0.2),
		CARVE_DEBRIS_LOW if _low else CARVE_DEBRIS, dir, 150.0)


## Is what is left a landing, or a splinter? See `MIN_STANDABLE_RUN`.
func _is_splintered() -> bool:
	if _grid == null or not is_instance_valid(_grid):
		return false
	return _grid.solid_fraction() < COLLAPSE_SOLID_FRACTION \
		or _grid.widest_standable_run() < MIN_STANDABLE_RUN


## Knit the holes shut. The ledge never left, so this is quiet on purpose — no shake and
## no sound, both of which belong to a platform coming BACK (`_reform`).
func _repair() -> void:
	_repair_timer = 0.0
	_rebuild_grid()
	CombatVfx.spawn_burst(
		get_parent(), global_position, REFORM_POOF_START, REFORM_POOF_END,
		1 if _low else REPAIR_POOF_COUNT, 0.3, 40.0, 90.0, 1.0, 2.5
	)
	queue_redraw()


## Lay a fresh, whole grid over this body — dropping the shapes the old one installed.
## Used by both restore paths; see `DestructibleStage._free_shape_nodes` for why the old
## shapes have to be detached rather than merely queued.
func _rebuild_grid() -> void:
	if _grid == null or not is_instance_valid(_grid):
		_grid = DestructibleStage.attach_ledge(self, platform_size, base_color)
		return
	_grid.build_from_rects([Rect2(-platform_size * 0.5, platform_size)] as Array[Rect2])
	_grid.rebuild_collision(self, self)
	_grid.queue_redraw()


func _hit_feedback(world_pos: Vector2) -> void:
	_flash_timer = HIT_FLASH_TIME
	_nudge = Vector2.from_angle(randf() * TAU) * HIT_NUDGE
	CombatVfx.spawn_burst(
		get_parent(), world_pos, base_color.lightened(0.3),
		Color(base_color.r, base_color.g, base_color.b, 0.0), 5, 0.35, 70.0, 160.0, 1.5, 3.0
	)
	queue_redraw()


func _break(dir: Vector2) -> void:
	_broken = true
	remove_from_group("destructible")  # same-frame AoE queries don't re-hit a dead platform
	_repair_timer = 0.0   # the whole thing is going; there is nothing left to knit shut
	# ⚠ THE LAYER, NOT THE SHAPES. There is no single `_collider` to disable any more —
	# collision is however many merged rectangles the grid currently has, and it changes
	# on every carve. Zeroing the layer takes the body out of BOTH buckets (bit1 movement,
	# bit3 the spell-Area2D one) in one assignment that cannot go stale, and `_reform`
	# puts it back. The shapes themselves are untouched, so the grid can keep its state.
	collision_layer = 0
	visible = false
	DebrisChunk.spawn_burst(get_parent(), global_position, base_color, 10, dir, 260.0)
	# ⚠ SNAPPED. A breakable platform is BY DEFINITION a thing floating in the air, so
	# stamping a floor crack at its own position drew a mark on nothing — the other
	# half of the maker's *"a crack in the air"*. Now it marks the ground the debris
	# lands on, or marks nothing at all when the platform hangs over a drop.
	ScorchDecal.spawn(get_parent(), global_position, platform_size.x * 0.4, "crack",
		Color(0.2, 0.15, 0.1, 0.6), 0.0, true)
	Juice.shake_camera(4.0)
	Sfx.play("enemy_death")
	_regen_timer = regen_time


func _reform() -> void:
	_broken = false
	hp = max_hp
	# A ledge that came back holed would be a ledge that never really came back — and
	# every one of `FloorGen`'s reachable-surface guarantees is written against a WHOLE
	# platform. So the grid is laid fresh, not restored.
	_rebuild_grid()
	collision_layer = 5   # see `_break` — bit1 movement + bit3 spell-Area2D
	visible = true
	add_to_group("destructible")
	CombatVfx.spawn_burst(
		get_parent(), global_position, REFORM_POOF_START, REFORM_POOF_END,
		18, 0.4, 60.0, 150.0, 1.5, 3.5
	)
	Juice.shake_camera(2.0)
	Sfx.play("blink", -4.0, 0.1)  # magical materialise cue (closest existing sfx)
	queue_redraw()


func _draw() -> void:
	if _broken:
		# Fading dashed "it's coming back" outline in the last warning second.
		if _regen_timer <= REFORM_WARNING_TIME:
			var a: float = clampf(1.0 - _regen_timer / REFORM_WARNING_TIME, 0.0, 1.0)
			var half: Vector2 = platform_size * 0.5
			draw_rect(Rect2(-half, platform_size), Color(BREAK_EDGE_COLOR.r, BREAK_EDGE_COLOR.g, BREAK_EDGE_COLOR.b, 0.4 * a), false, 2.0)
		return
	var half2: Vector2 = platform_size * 0.5
	var o: Vector2 = -half2 + _nudge
	var w: float = platform_size.x
	var h: float = platform_size.y
	var cap: float = StageLayers.cap_height(h)
	var body_col: Color = base_color.lightened(0.45) if _flash_timer > 0.0 else base_color
	# Body + a dark underside so the silhouette detaches from the floor wash.
	draw_rect(Rect2(o, platform_size), body_col)
	draw_rect(Rect2(o + Vector2(0.0, h - cap * 0.6), Vector2(w, cap * 0.6)),
		StageLayers.UNDERSIDE)
	# RULE 1 + RULE 2: the lit cap says "land here", in amber because it breaks.
	draw_rect(Rect2(o, Vector2(w, cap)), StageLayers.BREAK_AMBER_DIM)
	draw_rect(Rect2(o, Vector2(w, maxf(cap * 0.45, 1.5))), BREAK_EDGE_COLOR)
	# Fracture hairlines across the body — "fragile" said quietly, under the cap, so
	# it never competes with the cap for the eye.
	var seams: int = maxi(2, int(w / 40.0))
	for s in range(1, seams):
		var sx: float = o.x + w * float(s) / float(seams)
		draw_line(Vector2(sx, o.y + cap), Vector2(sx + 3.0, o.y + h - 1.0),
			StageLayers.BREAK_AMBER_DIM, 1.0, true)
	draw_rect(Rect2(o, platform_size), StageLayers.EDGE_DARK, false, 1.0)
