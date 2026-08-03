extends Node2D
## SPELL PLAYGROUND — play the ragdoll stick fighter AND cast/cycle every spell at
## destructible cover + practice dummies. The stickman spike (movement, jump, wall-jump,
## punch, ragdoll) + the real spell tree (SpellCaster) + destructibles, in one throwaway
## sandbox. Touches no game logic. Delete scripts/spike/ + scenes/spike/ to remove.
##
## Combat verbs use the GAME's input map so the sandbox is a true preview, not a
## third control scheme: LMB cast · F melee · RMB deflect · SPACE dash.
## move A/D (or arrows) · jump W/Up · duck/crawl S · aim MOUSE ·
## Q/E or SCROLL cycle spell · HOLD RMB = guard ring · B incoming test-bolt ·
## H hit · K kill · R reset · TAB physics-tune
##
## ROCK WALL IS A TWO-BEAT SPELL ON ONE BUTTON: LMB raises the wall, LMB again
## punches it across the arena. See the SHOVE_* constants for the exact rule.

const FIG := preload("res://scripts/spike/SpikeFigure.gd")
const ENEMY_SCENE := "res://scenes/combat/Enemy.tscn"
const DESTRUCTIBLE := "res://scripts/combat/DestructibleTerrain.gd"

const FLOOR_Y := 340.0
const HALF_W := 560.0
const CEIL_Y := -320.0
const FIG_COLOR := Color(0.93, 0.51, 0.51)
const COVER_X := [-210.0, 90.0, 360.0]

## ---- THE ROCK WALL TWO-BEAT -------------------------------------------------
## The maker's ask: "the first left click summons it, the second left click should
## be the punch that sends it". One button, two beats. The shove itself was always
## built — it was just unreachable, because while a spell is held LMB means CAST,
## so the second press raised a second wall and the punch path was never taken.
## These three numbers ARE the arbitration rule; a press only becomes a punch when
## all of them hold (plus: the wall must be one YOU raised, and still standing).
##
## How close the fighter must be to a standing rock wall for a punch to shove it.
## Generous vs the 96 px dummy punch: the wall is a big object and hunting for a
## pixel-perfect contact point would make the shove feel unreliable.
const SHOVE_REACH := 150.0
## How long after a wall erupts the second beat stays armed.
##
## THE ESCAPE HATCH, and the reason the claim is timed at all: a wall lives 4.5 s,
## and a wall you raised as COVER and then stood behind must not spend those
## seconds eating your casts. The window expires well inside the wall's life, so
## a combo you meant to throw is always available and a wall you meant to keep
## quietly hands the button back — and waiting it out (or simply aiming somewhere
## else) is how you get a SECOND wall. Nothing is ever locked away: F (melee)
## shoves any standing wall in reach at any time, window or no window.
## UNTESTED GUESS: 2.5 s is reasoning, not feel. Tune it here.
const SHOVE_CLAIM_WINDOW := 2.5
## How much "toward the wall" a swing has to be before it counts as aimed at it.
## Shared by both halves of the shove so the tell can never light up for a press
## that then misses — one gate, asked twice.
const SHOVE_FACING_DOT := 0.1
const DUMMY_X := [-70.0, 220.0]
## Windup multiplier per tier — a jab is near-instant, an ult is a commitment.
const _TIER_WINDUP := {0: 0.35, 1: 1.0, 2: 1.9}
## Upward impulse as the heavier spells gather. Quick spells never levitate.
const _LEVITATE := {0: 0.0, 1: 900.0, 2: 1600.0}

var _fig: SpikeFigure
var _cam: Camera2D
var _hud: Label
var _spells: Array = []
var _sidx := 0
var _covers: Array = []
var _dummies: Array = []
var _shake := 0.0
var _shake_dir := Vector2.ZERO
var _cast_cd := 0.0
## What is in the hand right now, and the bar that shows it.
var _slots: HandSlots = null
var _bar: LoadoutBar = null
## The wall currently holding the use button, or null. Kept as a reference (not
## just a bool) so the tell is switched off on exactly the wall that had it, even
## if the claim jumps straight from one wall to another in a single frame.
var _primed_wall: Node2D = null

var _knobs := {
	"stiffness": 3000.0, "damping": 90.0, "max_torque": 14000.0, "air_factor": 0.2,
	"grav_scale": 2.0, "jump_speed": 880.0, "move_speed": 420.0, "upright_k": 55000.0, "punch_lunge": 3400.0,
}
var _knob_order := ["stiffness", "damping", "max_torque", "air_factor", "grav_scale", "jump_speed", "move_speed", "upright_k", "punch_lunge"]
var _sel := 0
var _show_tune := false


func _ready() -> void:
	Engine.physics_ticks_per_second = 120
	RenderingServer.set_default_clear_color(Color(0.13, 0.14, 0.18))
	Atmosphere.add_glow(self)                 # 2D bloom so spell cores radiate
	_spells = SpellLibrary.build_all()
	_center_window()
	_build_world()
	_build_targets()
	_spawn_figure()
	_build_camera()
	_build_hud()
	_build_bar()
	_update_hud()


func _center_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var w := get_window()
	w.mode = Window.MODE_WINDOWED
	w.size = Vector2i(1280, 720)


func _build_world() -> void:
	var th := 44.0
	var mid_y := (FLOOR_Y + CEIL_Y) * 0.5
	var wall_h := (FLOOR_Y - CEIL_Y) + th * 2.0
	_static_rect(Vector2(0, FLOOR_Y + th * 0.5), Vector2(HALF_W * 2 + th * 2, th))   # floor
	_static_rect(Vector2(0, CEIL_Y - th * 0.5), Vector2(HALF_W * 2 + th * 2, th))    # ceiling
	_static_rect(Vector2(-HALF_W - th * 0.5, mid_y), Vector2(th, wall_h))            # left wall
	_static_rect(Vector2(HALF_W + th * 0.5, mid_y), Vector2(th, wall_h))             # right wall
	_static_rect(Vector2(-320, 150), Vector2(150, 22))                              # ledges to wall-jump
	_static_rect(Vector2(-90, -40), Vector2(150, 22))


func _static_rect(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = SpikeFigure.WORLD_LAYER   # layer 1 — stickman + dummies both stand on it
	body.collision_mask = 0
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	poly.color = Color(0.32, 0.35, 0.42)
	poly.position = pos
	poly.z_index = -5
	add_child(poly)


func _build_targets() -> void:
	for cx: float in COVER_X:
		var block: Node2D = (load(DESTRUCTIBLE) as GDScript).new()
		block.position = Vector2(cx, FLOOR_Y - 32.0)
		add_child(block)
		_covers.append(block)
	var es: PackedScene = load(ENEMY_SCENE)
	for dx: float in DUMMY_X:
		var d: Node = es.instantiate()
		# They WALK AND FIGHT BACK now, rather than standing there as targets — you
		# cannot judge a defensive kit against something that never attacks. Left
		# on the default difficulty so it is a spar, not a gauntlet, and given real
		# (if generous) HP so they can actually be killed instead of being
		# invincible posts.
		d.set("passive", false)
		d.set("max_hp", 450)
		d.set("tint", Color(0.56, 0.56, 0.6))
		d.set("scale", Vector2(1.9, 1.9))            # match the stick fighter's size (dummies default ~half)
		d.set("position", Vector2(dx, FLOOR_Y - 100.0))
		add_child(d)
		d.add_to_group("dummy")
		_dummies.append(d)


func _spawn_figure() -> void:
	_fig = FIG.new()
	_fig.spawn_pos = Vector2(0, 120)
	_fig.body_color = FIG_COLOR
	_fig.configure(_knobs)
	add_child(_fig)
	_fig.punched.connect(_on_punch)
	_fig.parried.connect(_on_parried)


## The stickman's punch lands on nearby dummies: damage + a satisfying knockback shove.
## A punch that lands on a standing ROCK WALL instead SHOVES it — the wall becomes a
## grinding projectile that plows the arena until it hits something solid.
func _on_punch(dir: Vector2) -> void:
	_shake = maxf(_shake, 0.5)
	_shake_dir = dir
	var t: Node2D = _fig.get("_torso")
	if t == null:
		return
	var origin: Vector2 = t.global_position
	# Wall first: if one is in reach, the punch commits to shoving it rather than
	# also cutting through to whatever stands behind it. `false` = the ANY-wall
	# test: a thrown fist shoves whatever it can reach, including walls whose
	# two-beat window has lapsed and walls nobody owns. That is the escape hatch
	# the timed claim in _update_shove_claim() leans on.
	var wall: Node2D = _shoveable_for(origin, dir, false)
	if wall != null:
		var to_wall: Vector2 = wall.call("footprint_center") - origin
		if wall.call("shove", Vector2(signf(to_wall.x) if to_wall.x != 0.0 else 1.0, 0.0)):
			_shake = maxf(_shake, 0.9)
			return
	var connected := false
	for d in _dummies:
		if not is_instance_valid(d):
			continue
		var to: Vector2 = (d as Node2D).global_position - origin
		if to.length() < 96.0 and to.normalized().dot(dir) > 0.25:   # in front, in range
			connected = true
			if d.has_method("take_damage"):
				d.call("take_damage", 22)
			if d.has_method("apply_knockback"):
				d.call("apply_knockback", dir * 620.0)
	if connected:
		Sfx.play("melee_hit", 0.0, 0.1)              # the CONNECT crack (swing already played on the rig)


## THE one reach + facing test behind BOTH halves of the shove, so the tell can
## never promise a punch that then misses.
##
## `dir` is a unit aim/punch direction and `origin` is the TORSO — the same origin
## _on_punch reports against. (punch() derives its direction from the shoulder,
## ~10 px off; far inside the dot gate, and using two different origins here is
## exactly how a tell and its action drift apart.)
##
## `claimable` adds the two gates that let a wall STEAL the use button: it must
## be a wall YOU raised, and still inside the combo window. A plain F punch passes
## false and shoves any standing wall it can reach.
func _shoveable_for(origin: Vector2, dir: Vector2, claimable: bool) -> Node2D:
	var wall: Node2D = RockWall.find_shoveable_near(
		get_tree(), origin, SHOVE_REACH, _fig if claimable else null)
	if wall == null:
		return null
	if claimable and float(wall.call("time_since_raise")) > SHOVE_CLAIM_WINDOW:
		return null
	# footprint_center(), not global_position: the wall node sits at the arena
	# origin and draws in world coords, so its transform is (0,0) and a facing
	# test against it would answer for the middle of the arena, not the wall.
	# Gate on facing so punching AWAY from a wall never drags it back onto you.
	var to_wall: Vector2 = wall.call("footprint_center") - origin
	if to_wall.normalized().dot(dir) <= SHOVE_FACING_DOT:
		return null
	return wall


## THE ARBITRATION. Resolved every frame: does the use button belong to a wall
## standing in front of you, or to the spell in your hand? Published through
## HandSlots so primary_action() stays the single answer to "what does left click
## do", and read back by the input handler exactly as if fists were equipped.
##
## Note this is a no-op when fists are already held — they punch anyway — so the
## claim only ever CHANGES anything for the beat it exists for: the press right
## after you raised your own wall.
func _update_shove_claim() -> void:
	var wall: Node2D = null
	var t: Node2D = _fig.get("_torso") as Node2D
	# Guarding already costs you your offence (see the cast branch in _input), so
	# it must not light the tell either — a promise the press would not keep.
	if t != null and not _fig.is_guarding():
		var aim: Vector2 = (_fig.ctrl_aim - t.global_position).normalized()
		wall = _shoveable_for(t.global_position, aim, true)
	_set_primed_wall(wall)
	if _slots != null:
		_slots.claim_primary("punch" if wall != null else "")


## Move the "next press punches me" highlight, and refresh the HUD line only when
## it actually changes — the state flips rarely, so the tell stays event-driven
## rather than rebuilding the label every frame.
func _set_primed_wall(wall: Node2D) -> void:
	if wall == _primed_wall:
		return
	if is_instance_valid(_primed_wall) and _primed_wall.has_method("set_primed"):
		_primed_wall.call("set_primed", false)
	_primed_wall = wall
	if wall != null:
		wall.call("set_primed", true)
	_update_hud()


## A successful deflect: localized impact frame AT the parry point (ding + shell fire
## on the rig itself) — the curated "big deflect" beat from the feel study.
func _on_parried(world_pos: Vector2) -> void:
	Juice.impact_frame(0.45, world_pos)


## The League-style strip along the bottom: fists, then the spells you can reach.
## The playground carries all 26 so every spell stays reviewable; the real game
## caps this at four chosen out of combat.
func _build_bar() -> void:
	_slots = HandSlots.new()
	# The REAL loadout shape: four spell slots plus a dedicated ult slot (fists
	# stay at 0). The playground still reaches all 26 spells — Q/E swaps which
	# spell sits in the SELECTED slot, drawn from the spells that slot accepts —
	# so everything stays testable while the bar shows the shipping layout.
	_slots.rebuild([], _default_loadout())
	_slots.select(1)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_bar = LoadoutBar.new()
	_bar.slots = _slots
	layer.add_child(_bar)
	_bar.slot_selected.connect(_on_slot_selected)


## Four QUICK/HEAVY spells then one ULT — the shipping loadout, filled with the
## first spell of each shelf so the bar is never empty on boot.
func _default_loadout() -> Array:
	var quick: Array = SpellTier.filter(_spells, SpellTier.Tier.QUICK)
	var heavy: Array = SpellTier.filter(_spells, SpellTier.Tier.HEAVY)
	var ults: Array = SpellTier.filter(_spells, SpellTier.Tier.ULT)
	var pool: Array = quick + heavy
	var out: Array = []
	for i in 4:
		if i < pool.size():
			out.append(pool[i])
	if not ults.is_empty():
		out.append(ults[0])
	return out


## A spell's own colour: its element tint where it has one, else its authored
## override — the same choice SpellCaster makes when it tints the spectacle.
func _spell_colour(spell: SpellDef) -> Color:
	if spell.use_element_color and spell.element >= 0:
		return Elements.color(spell.element)
	return spell.color


## Spells this slot is allowed to hold. Slot 5 (index 4 among spells) is the ult
## slot; the other four take anything that is not an ult.
func _pool_for_slot(slot: int) -> Array:
	if SpellTier.slot_accepts_ult(slot - 1):
		return SpellTier.filter(_spells, SpellTier.Tier.ULT)
	return SpellTier.filter(_spells, SpellTier.Tier.QUICK) 		+ SpellTier.filter(_spells, SpellTier.Tier.HEAVY)


## Q/E swap the spell IN the selected slot rather than moving the selection, so
## the bar keeps its shape while every spell stays reachable for review.
func _swap_in_slot(dir: int) -> void:
	if _slots == null or _slots.selected <= 0:
		return
	var pool: Array = _pool_for_slot(_slots.selected)
	if pool.is_empty():
		return
	var entry: Dictionary = _slots.slots[_slots.selected]
	var cur: int = pool.find(entry.get("spell"))
	var nxt: Variant = pool[wrapi(cur + signi(dir), 0, pool.size())]
	entry["spell"] = nxt
	entry["id"] = String(nxt.get(&"id"))
	entry["name"] = String(nxt.get(&"display_name"))
	_sidx = maxi(_spells.find(nxt), 0)
	_update_hud()


## Tapping a square picks it; slot 0 is fists, so spell indices are offset by one.
func _on_slot_selected(index: int) -> void:
	if index > 0:
		_sidx = wrapi(index - 1, 0, _spells.size())
	_update_hud()


func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = _fig.spawn_pos
	cam.zoom = Vector2(0.55, 0.55)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	add_child(cam)
	cam.make_current()
	_cam = cam


func _physics_process(_delta: float) -> void:
	if _fig == null:
		return
	_cast_cd = maxf(0.0, _cast_cd - _delta)
	# Movement through named actions too, so a virtual joystick can drive the
	# playground later without touching this file (the project's mobile-first rule
	# is that code names actions and never keys).
	_fig.ctrl_move_x = Input.get_axis("move_left", "move_right")
	# Jump is W/Up only — SPACE belongs to dash, matching the game's input map.
	_fig.ctrl_jump = Input.is_action_pressed("jump")
	_fig.ctrl_duck = Input.is_action_pressed("move_down")
	_fig.ctrl_aim = get_global_mouse_position()
	# Aim-hold is the CAST button held down, so it follows the rebind rather than
	# staying pinned to whatever the left mouse button happens to do.
	_fig.ctrl_aim_hold = Input.is_action_pressed("cast")
	# AFTER the aim is written, never before: the claim is decided against where
	# you are pointing THIS frame, so a flick away from the wall hands the button
	# back on the same frame the tell goes out.
	_update_shove_claim()


func _process(delta: float) -> void:
	if _cam != null and _fig != null:
		var t: Node = _fig.get("_torso")
		if t != null:
			_cam.position = (t as Node2D).global_position
		if _shake > 0.0:
			_shake = maxf(0.0, _shake - delta * 2.2)
			var amp := _shake * _shake * 5.0
			_cam.offset = _shake_dir * amp * 1.6 + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) * 0.35
		else:
			_cam.offset = Vector2.ZERO


func _cast() -> void:
	if _fig == null or _spells.is_empty() or _cast_cd > 0.0:
		return
	_cast_cd = 0.35
	var t: Node2D = _fig.get("_torso")
	var origin: Vector2 = t.global_position if t != null else _fig.global_position
	var target: Vector2 = get_global_mouse_position()
	var spell: SpellDef = _spells[_sidx]
	# Rule 4: the rig throws each KIND of spell with its own body language — a wall
	# gets slammed out of the ground, a bombardment gets a ritual circle, a chidori
	# gets coiled into the chest. The pose fires FIRST so the windup reads as the
	# cause of the spectacle rather than a shrug alongside it.
	var pose: int = CastStyle.for_spell_def(spell)
	var aim: Vector2 = (target - origin).normalized()
	_fig.cast(aim, pose)
	# THE CASTING PROCESS. The spell no longer leaves the same frame you press:
	# the body winds up, a sigil opens along the aim, and only then does it fire.
	# How long you are committed scales with the spell's TIER, so a quick jab is
	# nearly instant while an ult is a visible, punishable commitment — that
	# window IS the counterplay, and it is why casting is worth watching.
	var tier: int = SpellTier.of(spell)
	var windup: float = CastStyle.duration(pose) * _TIER_WINDUP[tier]
	_cast_cd = maxf(0.35, windup + 0.12)
	var circle := MagicCircle.new()
	add_child(circle)
	circle.position = origin + aim * 46.0
	# The sigil is the SPELL'S colour, not its tier's. Badging the circle by tier
	# meant a gold ring opened and then something violet came out of it, which
	# reads as two unrelated effects. The circle is the spell arriving, so it has
	# to be the same colour as the thing it delivers; SIZE alone carries the tier.
	circle.appear(_spell_colour(spell), 34.0 + 26.0 * float(tier), maxf(windup * 0.7, 0.08))
	# Side-on, along the aim: a circle in this game stands perpendicular to the
	# way its magic travels, so you can read where a cast is pointed off the sigil.
	circle.set_orientation(true, aim, 0.22)
	# Heavier spells lift you slightly off the floor as they gather — the body
	# telling you this one costs something. Never for a quick spell, or the whole
	# kit would feel floaty.
	if tier != SpellTier.Tier.QUICK:
		var t2: Node = _fig.get("_torso")
		if t2 is RigidBody2D:
			(t2 as RigidBody2D).apply_central_impulse(Vector2(0.0, -_LEVITATE[tier]))
	if windup > 0.0:
		await get_tree().create_timer(windup).timeout
	if not is_instance_valid(_fig) or not is_instance_valid(circle):
		# Interrupted windup: the cast never happens, so nothing will ever adopt
		# this sigil. Bloom it out rather than leaking it — and withdraw in case
		# an earlier offer from this caster is still pending.
		if is_instance_valid(circle):
			circle.vanish(0.14)
		MagicCircle.withdraw(_fig)
		return
	# HAND OFF rather than dismiss. Vanishing here and letting SpellCaster build a
	# fresh muzzle sigil is exactly the bug the maker reported — "I summon a circle,
	# it goes away, and then another circle spawns which the spell comes out of".
	# The two even shared a radius (34+26*tier ≈ width*3.3 ≈ 86 px) and sat only
	# 46 px apart, so it read as one circle glitching rather than as two, which is
	# why it survived earlier review. `offer` parks this circle for the spectacle
	# about to be built; adopt_or_open() claims it by caster and travels it to the
	# muzzle, so ONE sigil spans the whole cast.
	#
	# Ordering is load-bearing: offer() must run BEFORE SpellCaster.cast() in the
	# same frame, and the local reference is dropped immediately afterwards so
	# nothing here keeps driving a circle that now belongs to the spell.
	MagicCircle.offer(circle, _fig)
	circle = null
	# Re-read the aim at RELEASE: you kept control through the windup, so the
	# spell should go where you are pointing NOW, not where you were when you
	# pressed.
	var release_target: Vector2 = get_global_mouse_position()
	var t3: Node2D = _fig.get("_torso")
	var release_origin: Vector2 = t3.global_position if t3 != null else origin
	# The trailing `_fig` is the caster, and it is what makes the wall two-beat work:
	# a wall knows who raised it, so the NEXT press can be a PUNCH that shoves it
	# rather than a second wall — and cannot be a punch aimed at somebody else's.
	#
	# This used to be bracketed by a snapshot/adopt pair that diffed the "shoveable"
	# group before and after the cast, because SpellCaster did not forward the caster
	# to raise_wall(). It now stamps caster identity onto EVERY spectacle it builds,
	# so the diff was doing nothing but re-deriving an answer already recorded — and
	# a workaround left in place after its cause is fixed is just a second mechanism
	# to keep in sync. Deleted.
	SpellCaster.cast(spell, self, release_origin, release_target,
		Color(0.78, 0.84, 1.0), "", _fig)
	_shake = maxf(_shake, 0.35)
	_shake_dir = (release_target - release_origin).normalized()


## Dash toward held movement keys (true 8-way incl. straight up/down); with no
## direction held, dash toward the mouse aim.
func _dash() -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir == Vector2.ZERO:
		var t: Node2D = _fig.get("_torso")
		if t != null:
			dir = (get_global_mouse_position() - t.global_position).normalized()
	_fig.dash(dir)


## Lob a slow hostile test-bolt in from ahead of the figure, aimed at it — the
## deflect target: parry (C) as it arrives to reflect it back out with the ding.
func _spawn_test_bolt() -> void:
	var t: Node2D = _fig.get("_torso")
	if t == null:
		return
	var facing: float = _fig.get("_facing")
	var proj := EnemyProjectile.new()
	add_child(proj)
	proj.global_position = t.global_position + Vector2(facing * 330.0, -26.0)
	proj.launch((t.global_position - proj.global_position).normalized())


## Q/E and the scroll wheel move the SAME selection the bar shows, so the two
## never disagree about what is in your hand.
func _cycle_synced(d: int) -> void:
	_cycle(d)
	if _slots != null:
		_slots.select(_sidx + 1)


func _cycle(step: int) -> void:
	_sidx = (_sidx + step + _spells.size()) % _spells.size()
	_update_hud()


func _reset_arena() -> void:
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	if _fig == null:
		return
	# The four combat verbs go through the ACTION MAP, not raw keys, so the
	# playground answers the same bindings the shipped game does instead of being
	# a third control scheme to remember: LMB cast · F melee · RMB deflect ·
	# SPACE dash. The sandbox-only keys below stay on raw keycodes deliberately —
	# they are debug affordances (spawn a bolt, kill, reset) and do not belong in
	# the game's input map.
	if event.is_action_pressed("cast"):
		# Holding the guard costs your offence — the trade that stops a sustained
		# hold being free. Same rule on every platform.
		if _fig.is_guarding():
			return
		# primary_action() is the ONLY question asked here, and it already folds in
		# the rock-wall two-beat claim (_update_shove_claim): with your own wall
		# standing in front of you it answers "punch" even though a spell is held,
		# so the second press sends the wall instead of raising another one.
		if _slots != null and _slots.primary_action() == "punch":
			_fig.punch()
		else:
			_cast()
		return
	if event.is_action_pressed("melee"):
		_fig.punch()
		return
	if event.is_action_pressed("parry"):
		_fig.guard_press()
		return
	if event.is_action_released("parry"):
		_fig.guard_release()
		return
	if event.is_action_pressed("dash"):
		_dash()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				_swap_in_slot(1)
			KEY_Q:
				_swap_in_slot(-1)
			KEY_B:
				_spawn_test_bolt()
			KEY_H:
				var d := Vector2(_fig._facing if _fig._facing != 0 else 1.0, -0.35)
				_fig.hit(d.normalized(), 460.0)
			KEY_K:
				_fig.kill()
			KEY_R:
				_reset_arena()
			KEY_TAB:
				_show_tune = not _show_tune
				_update_hud()
			KEY_BRACKETLEFT:
				_adjust(0.926)
			KEY_BRACKETRIGHT:
				_adjust(1.08)
			_:
				var idx: int = event.keycode - KEY_1
				if idx >= 0 and idx < _knob_order.size():
					_sel = idx
					_update_hud()


func _adjust(factor: float) -> void:
	if not _show_tune:
		return
	var key: String = _knob_order[_sel]
	_knobs[key] = _knobs[key] * factor
	if _fig != null:
		_fig.configure(_knobs)
	_update_hud()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(20, 14)
	_hud.size = Vector2(1236, 320)
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hud)


func _update_hud() -> void:
	if _hud == null or _spells.is_empty():
		return
	var s: SpellDef = _spells[_sidx]
	var txt := "SPELL PLAYGROUND   [%d / %d]   %s\n%s · %s · dmg %d · cd %.1fs%s\n\nLMB  CAST toward mouse    F  punch    RMB  HOLD to guard    SPACE  dash    Q E / SCROLL  cycle    B  test-bolt    R  reset\nmove A/D · jump W/Up · duck/crawl S · aim mouse · H hit · K kill · TAB tune" % [
		_sidx + 1, _spells.size(), s.display_name,
		_kind_name(s.kind), _elem_name(s.element), int(s.damage), float(s.cooldown), _extra(s),
	]
	# The second half of the tell. The pulsing crown on the wall says "me"; this
	# says what the button will DO, because a player mid-fight should never have
	# to infer that from a highlight they have not been taught yet.
	# is_instance_valid, not != null: a freed wall leaves the reference reading as
	# non-null until _update_shove_claim clears it next frame, and the HUD is also
	# rebuilt by the slot keys in between — which would flash the line on a wall
	# that has already crumbled.
	if is_instance_valid(_primed_wall):
		txt += "\n>> WALL PRIMED — LMB PUNCHES IT (aim away to cast instead)"
	if _show_tune:
		txt += "\n\n-- physics tune (number keys select · [ ] adjust) --"
		for i in _knob_order.size():
			var key: String = _knob_order[i]
			var mark := ">" if i == _sel else " "
			txt += "\n%s %d %-11s %.1f" % [mark, i + 1, key, _knobs[key]]
	_hud.text = txt


func _extra(s: SpellDef) -> String:
	var parts: Array = []
	if s.count > 0:
		parts.append("x%d" % s.count)
	if s.radius > 0.0:
		parts.append("r%d" % int(s.radius))
	if s.reach > 0.0:
		parts.append("reach %d" % int(s.reach))
	return ("  ·  " + " · ".join(parts)) if not parts.is_empty() else ""


func _kind_name(k: int) -> String:
	match k:
		SpellDef.Kind.BEAM: return "BEAM"
		SpellDef.Kind.DIVINE_RAY: return "RAY"
		SpellDef.Kind.METEOR: return "METEOR"
		SpellDef.Kind.CONVERGENCE: return "CONVERGENCE"
		SpellDef.Kind.RUSH: return "RUSH"
		SpellDef.Kind.NOVA: return "NOVA"
		SpellDef.Kind.BOULDER: return "BOULDER"
		SpellDef.Kind.PILLAR: return "PILLAR"
		SpellDef.Kind.WALL: return "WALL"
		SpellDef.Kind.ICE_WALL: return "ICE WALL"
		SpellDef.Kind.CHAIN: return "CHAIN"
		SpellDef.Kind.ZONE: return "ZONE"
		SpellDef.Kind.MISSILES: return "MISSILES"
		SpellDef.Kind.TETHER: return "TETHER"
		SpellDef.Kind.FLURRY: return "FLURRY"
		SpellDef.Kind.BLINK_STRIKE: return "BLINK"
		SpellDef.Kind.CRAWLER: return "CRAWLER"
		SpellDef.Kind.THROWN_ANCHOR: return "ANCHOR"
	return "SPELL"


func _elem_name(e: int) -> String:
	match e:
		0: return "FIRE"
		1: return "ICE"
		2: return "LIGHTNING"
		3: return "SHADOW"
		4: return "ARCANE"
		5: return "EARTH"
		6: return "HOLY"
		7: return "WIND"
	return "—"
