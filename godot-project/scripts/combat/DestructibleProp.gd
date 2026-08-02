extends StaticBody2D
## Shatterable crate prop: blocks movement like a wall until spells, blasts or
## melee break it — then it bursts into chunky debris, leaves a crack decal on
## the floor and frees. Group "destructible" + take_damage is the damage
## routing contract (mirrors the "enemy" pattern in Enemy.gd).
##
## Collision: layer 5 = bit 1 (blocks hero/enemy movement like the walls)
## + bit 4 (the Spell projectile's Area2D mask only scans layer 4, so the
## crate must sit there too or bolts would fly straight through it).

const CRATE_SIZE: float = 20.0  # px, matches the CollisionShape2D box
const CRATE_COLOR: Color = Color(0.55, 0.38, 0.2, 1.0)  # warm plank brown
const CRATE_EDGE_COLOR: Color = Color(0.35, 0.23, 0.11, 1.0)
const CRATE_PLANK_COLOR: Color = Color(0.45, 0.3, 0.15, 1.0)
# Non-lethal hit feedback: brief lighten + a tiny visual jolt.
const HIT_FLASH_TIME: float = 0.09
const HIT_NUDGE: float = 2.5  # px
# Shatter spectacle tuning — chunky: fewer/larger/faster than a spell hit.
const DEBRIS_AMOUNT: int = 14
const DEBRIS_LIFETIME: float = 0.55
const DEBRIS_VELOCITY_MIN: float = 140.0
const DEBRIS_VELOCITY_MAX: float = 320.0
const DEBRIS_SCALE_MIN: float = 3.0
const DEBRIS_SCALE_MAX: float = 6.0
const DEBRIS_DAMPING_MIN: float = 60.0
const DEBRIS_DAMPING_MAX: float = 140.0
# Flying plank chunks (real Node2Ds, beyond the particle burst).
const DEBRIS_CHUNK_COUNT: int = 5
const DEBRIS_CHUNK_SPEED: float = 220.0  # px/s initial drift
const DEBRIS_CHUNK_FADE: float = 0.5  # s to fade + free
const SHATTER_SHAKE: float = 3.0
const CRACK_DECAL_RADIUS: float = 16.0
const CRACK_DECAL_TINT: Color = Color(0.16, 0.1, 0.05, 0.8)  # dark wood-char

@export var max_hp: int = 30
var hp: int = 30
var _flash_timer: float = 0.0
var _nudge: Vector2 = Vector2.ZERO


func _ready() -> void:
	# ⚠ THIS DREW AT z 0 — the fighters' own layer — because it set no z_index, so a
	# crate standing where a fighter stands painted over him. Same defect the maker
	# reported on the versus stage; the crates are the tower's instance of it. One
	# table now, in StageLayers, with a test that fails if a stage drawer is missing
	# from it.
	StageLayers.apply(self, StageLayers.COVER)
	add_to_group("destructible")
	# NOT in `mortal`, deliberately — see slice_test_mortal_group.
	# `mortal` exists to make FACTIONS blind to each other. Cover was never
	# factioned: every spectacle scans its stamped target_group for fighters AND
	# the "destructible" literal for crates, as two separate passes
	# (BlastSpell.gd:232 + :251, BeamSpell.gd:365 + :372, and ~20 more). A crate
	# in both groups is found by both passes and takes every hit TWICE.
	hp = max_hp
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		if _flash_timer <= 0.0:
			_nudge = Vector2.ZERO
		queue_redraw()


## ⚠ IN CO-OP THE HOST IS THE ONLY PEER THAT MAY BREAK A CRATE. In single player
## `Net.is_active()` is false and every line below is the code that always ran —
## byte-identical, no branch taken.
##
## WHY. Cover destroyed by an ENEMY existed on one phone only. A hero's spell is
## rebuilt on the other peer as a twin, and although that twin's fighter scan is
## pointed at a dead group, every spectacle scans the "destructible" literal as a
## second, un-stamped pass — so hero-sourced prop damage already converged. Enemy
## attack twins are explicitly `visual_only`, so the client watched the blast and
## the crate stayed standing. You then take cover behind a crate your teammate
## cannot see, which is a fairness bug, not a cosmetic one.
##
## The fix is one writer rather than teeth on the enemy twins (which would
## double-apply the moment an enemy hit a hero — the exact thing the twins exist to
## avoid). The host sees EVERY damage source: enemies natively, heroes through the
## twin it builds of the client's cast. So it decides, and broadcasts ABSOLUTE hp.
##
## THE CLIENT STILL FLINCHES. It applies the hit locally for instant feedback —
## absolute hp is what makes that safe, because the host's number overwrites rather
## than compounds — but it is FLOORED AT 1. A crate must never shatter twice, and a
## client that guessed wrong about a kill has no way to put the cover back.
func take_damage(amount: int) -> void:
	if hp <= 0:
		return  # already shattering this frame
	var net: Node = get_node_or_null(^"/root/Net")
	var coop: bool = net != null and net.has_method(&"is_active") and bool(net.call(&"is_active"))
	if coop and not bool(net.call(&"is_host")):
		hp = maxi(hp - amount, 1)   # predicted, never fatal — the host owns the kill
		_hit_feedback()
		return
	hp = max(hp - amount, 0)
	if hp == 0:
		# Broadcast BEFORE shattering: `_shatter` frees the node, and `broadcast_prop_state`
		# needs it in the tree to read the position that identifies it on the wire.
		if coop:
			net.call(&"broadcast_prop_state", self, 0, true)
		_shatter()
		return
	_hit_feedback()
	if coop:
		net.call(&"broadcast_prop_state", self, hp, false)


## The host's verdict, applied verbatim. Absolute hp, so a client that predicted a
## few hits of its own is corrected rather than compounded.
func net_apply_prop_state(hp_now: int, shattered: bool) -> void:
	if hp <= 0:
		return
	hp = maxi(hp_now, 0)
	if shattered or hp <= 0:
		hp = 0
		_shatter()
		return
	_hit_feedback()


## The non-lethal hit read: brief lighten + a tiny jolt. Split out so the local,
## predicted and host-applied paths cannot drift into three different flinches.
func _hit_feedback() -> void:
	_flash_timer = HIT_FLASH_TIME
	_nudge = Vector2.from_angle(randf() * TAU) * HIT_NUDGE
	queue_redraw()


## The payoff: chunky debris burst + flying plank chunks + a persistent crack
## decal on the floor, then gone. Leaves the group immediately so same-frame
## radius queries (blast) don't re-hit a dead crate.
func _shatter() -> void:
	remove_from_group("destructible")
	remove_from_group(&"mortal")   # same-frame radius queries must not re-hit a dead crate
	_spawn_debris_burst()
	_spawn_debris_chunks()
	ScorchDecal.spawn(
		get_parent(), global_position, CRACK_DECAL_RADIUS, "crack", CRACK_DECAL_TINT
	)
	Juice.shake_camera(SHATTER_SHAKE)
	Sfx.play("enemy_death")
	queue_free()


## Wood-tinted particle pop via the shared burst builder.
func _spawn_debris_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		CRATE_COLOR.lightened(0.2), Color(CRATE_COLOR.r, CRATE_COLOR.g, CRATE_COLOR.b, 0.0),
		DEBRIS_AMOUNT, DEBRIS_LIFETIME,
		DEBRIS_VELOCITY_MIN, DEBRIS_VELOCITY_MAX,
		DEBRIS_SCALE_MIN, DEBRIS_SCALE_MAX,
		DEBRIS_DAMPING_MIN, DEBRIS_DAMPING_MAX
	)


## A few plank squares that fly outward, decelerate and fade — the "bits of
## crate everywhere" read the particles alone don't quite sell.
func _spawn_debris_chunks() -> void:
	var parent: Node = get_parent()
	if parent == null or not parent.is_inside_tree():
		return
	for i: int in DEBRIS_CHUNK_COUNT:
		var chunk: ColorRect = ColorRect.new()
		var side: float = randf_range(3.0, 6.0)
		chunk.size = Vector2(side, side)
		chunk.color = CRATE_PLANK_COLOR.lightened(randf_range(0.0, 0.25))
		parent.add_child(chunk)
		chunk.global_position = global_position - chunk.size * 0.5
		chunk.rotation = randf() * TAU
		var dir: Vector2 = Vector2.from_angle(randf() * TAU)
		var target: Vector2 = chunk.global_position + dir * DEBRIS_CHUNK_SPEED * DEBRIS_CHUNK_FADE
		var tween: Tween = chunk.create_tween()
		tween.set_parallel(true)
		tween.tween_property(chunk, "global_position", target, DEBRIS_CHUNK_FADE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(chunk, "modulate:a", 0.0, DEBRIS_CHUNK_FADE)
		tween.chain().tween_callback(chunk.queue_free)


func _draw() -> void:
	var half: float = CRATE_SIZE * 0.5
	var rect: Rect2 = Rect2(Vector2(-half, -half) + _nudge, Vector2(CRATE_SIZE, CRATE_SIZE))
	var body_color: Color = CRATE_COLOR
	if _flash_timer > 0.0:
		body_color = CRATE_COLOR.lightened(0.45)
	draw_rect(rect, body_color)
	draw_rect(rect, CRATE_EDGE_COLOR, false, 2.0)
	# Two horizontal plank seams so it reads "crate", not "brown square".
	for i: int in [1, 2]:
		var y: float = rect.position.y + CRATE_SIZE * float(i) / 3.0
		draw_line(
			Vector2(rect.position.x + 2.0, y), Vector2(rect.end.x - 2.0, y),
			CRATE_PLANK_COLOR, 1.5
		)
