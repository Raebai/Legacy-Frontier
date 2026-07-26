class_name Boss
extends "res://scripts/combat/Enemy.gd"
## THE ASHSPIRE GUARDIAN — a giant procedural stone-and-ember colossus, the
## tower's floor-5 final boss. Three HP-gated phases, a top-screen boss bar, an
## intro beat, and telegraphed spectacle attacks (the existing spell kit
## retargeted at group "hero"). Extends Enemy so it reuses hp / take_damage /
## knockback / _die + the "enemy" group — Encounter's alive==0 clear gate ends
## the floor when the Guardian dies, with zero change to the gate.

signal phase_changed(phase: int)
signal defeated

enum BPhase { INTRO, P1, P2, P3, DEAD }

const RIG_HEIGHT: float = 95.0
const STONE_TINT: Color = Color(0.34, 0.33, 0.38)
const KNOCKBACK_RESIST: float = 0.14   # a colossus barely budges
const PHASE2_AT: float = 0.66
const PHASE3_AT: float = 0.33
const INTRO_TIME: float = 2.6
const ADD_CAP: int = 3
const PHASE_CD: Dictionary = {BPhase.P1: 2.4, BPhase.P2: 1.7, BPhase.P3: 1.1}

var _bphase: int = BPhase.INTRO
var _attack_cd: float = 0.0
var _intro_timer: float = INTRO_TIME
var _busy: bool = false
var _adorn: BossAdornment = null
var _bar_layer: CanvasLayer = null
var _bar: BossBar = null
var _summoned: Array = []


func _ready() -> void:
	super._ready()   # hp, _hero, joins "enemy", tiny CharacterBars
	if is_instance_valid(rig):
		rig.set("height", RIG_HEIGHT)
		rig.set_tint(STONE_TINT)
		rig.class_preset("brawler")
		rig.set_equipment("head", "crown")            # a guardian-king crown on the colossus
		rig.set_aura(Color(1.0, 0.45, 0.15), 0.45)   # subtle ember halo — the stone body must read
		rig.set_aura_tier(2)
	_adorn = BossAdornment.new()
	add_child(_adorn)
	_adorn.configure(RIG_HEIGHT)
	_adorn.set_intensity(0.35)
	_build_bar()
	_play_intro()


# ------------------------------------------------------------------ boss brain
func _physics_process(delta: float) -> void:
	# Co-op: the guardian is host-authoritative — a client puppet only animates from
	# the synced transform/hp (no phases, no attacks, no move_and_slide) on its side.
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		_remote_enemy_visual(delta)
		return
	_touch_cooldown = max(_touch_cooldown - delta, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_apply_gravity(delta)
	var approach: float = 0.0
	if not _busy and _bphase != BPhase.INTRO and is_instance_valid(_hero):
		approach = signf(_hero.global_position.x - global_position.x) * move_speed
	velocity.x = _knockback.x + approach
	move_and_slide()
	if is_instance_valid(rig):
		if is_instance_valid(_hero):
			rig.set_facing(Vector2(_hero.global_position.x - global_position.x, 0.0))
		rig.set_body_velocity(velocity)
		rig.play(CharacterRig.State.RUN if absf(velocity.x) > 8.0 else CharacterRig.State.IDLE)
	match _bphase:
		BPhase.INTRO:
			_intro_timer -= delta
			if _intro_timer <= 0.0:
				_enter_phase(BPhase.P1)
		BPhase.DEAD:
			return
		_:
			_attack_cd -= delta
			if not _busy and _attack_cd <= 0.0:
				_choose_attack()
	_boss_touch()


func _boss_touch() -> void:
	if not is_instance_valid(_hero) or _touch_cooldown > 0.0:
		return
	if global_position.distance_to(_hero.global_position) < RIG_HEIGHT * 0.55:
		if _hero.has_method("take_damage"):
			_hero.take_damage(touch_damage)
			_touch_cooldown = 0.8


# ------------------------------------------------------------------ overrides
func take_damage(amount: int, tint: Color = Color(1.0, 1.0, 1.0, 0.0)) -> void:
	if _bphase == BPhase.DEAD:
		return
	# Co-op: a hit on a client-side puppet boss forwards to the host BEFORE any phase
	# logic — only the host advances phases / spawns adds (the guardian is host-owned).
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_take_damage", amount, tint)
		return
	super.take_damage(amount, tint)   # hp / flash / numbers / may call _die
	if _bphase == BPhase.DEAD:
		return
	var frac: float = float(hp) / float(maxi(max_hp, 1))
	if _bphase == BPhase.P1 and frac <= PHASE2_AT:
		_enter_phase(BPhase.P2)
	elif _bphase == BPhase.P2 and frac <= PHASE3_AT:
		_enter_phase(BPhase.P3)


func apply_knockback(impulse: Vector2, do_flop: bool = true) -> void:
	# Puppet -> forward the RAW impulse to the host; the host applies RESIST once.
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_apply_knockback", impulse)
		return
	super.apply_knockback(impulse * KNOCKBACK_RESIST, do_flop)


func _die() -> void:
	if _bphase == BPhase.DEAD:
		return
	_bphase = BPhase.DEAD
	Juice.epic_moment({"strength": 1.4, "frame": true, "shake": 20.0, "sfx": "cannon"})
	Juice.impact_frame(1.3, global_position)  # localized on the falling boss
	var sc := StarConvergence.new()
	sc.target_group = "none"   # visual-only finisher (no group "none" -> hits nobody)
	get_parent().add_child(sc)
	sc.converge(global_position, Color(1.0, 0.6, 0.2), 180.0, 0, "holy")
	if _bar != null:
		var tw := create_tween()
		tw.tween_property(_bar, "modulate:a", 0.0, 0.8)
	emit_signal("defeated")
	super._die()


# -------------------------------------------------------------------- phases
func current_phase() -> int:
	match _bphase:
		BPhase.P1: return 1
		BPhase.P2: return 2
		BPhase.P3: return 3
		BPhase.DEAD: return 4
		_: return 0


func _enter_phase(p: int) -> void:
	_bphase = p
	_attack_cd = float(PHASE_CD.get(p, 2.0)) * 0.6
	match p:
		BPhase.P1:
			if _adorn != null: _adorn.set_intensity(0.35)
			if is_instance_valid(rig):
				rig.set_aura(Color(1.0, 0.45, 0.15), 0.45)
				rig.set_aura_tier(2)
		BPhase.P2:
			if _adorn != null: _adorn.set_intensity(0.7)
			if is_instance_valid(rig):
				rig.set_tint(Color(0.44, 0.32, 0.30))
				rig.set_aura(Color(1.0, 0.38, 0.12), 0.6)
				rig.set_aura_tier(3)
				rig.flash_color(Color(1.4, 1.3, 1.2), 0.18)
			Juice.epic_moment({"strength": 1.1, "shake": 12.0, "sfx": "charge_up"})
			_atk_summon()   # open the enrage with adds
		BPhase.P3:
			if _adorn != null: _adorn.set_intensity(1.0)
			if is_instance_valid(rig):
				rig.set_tint(Color(0.52, 0.28, 0.24))
				rig.set_aura(Color(1.0, 0.28, 0.08), 0.78)
				rig.set_aura_tier(4)
			Juice.impact_frame(1.2, global_position)  # enrage beat AT the boss
			Juice.epic_moment({"strength": 1.2, "shake": 14.0, "sfx": "cannon"})
	emit_signal("phase_changed", current_phase())


# ------------------------------------------------------------ attack selection
func _phase_attack_ids(phase: int) -> Array:
	match phase:
		1: return ["slam", "pillars"]
		2: return ["beam", "rays", "summon"]
		3: return ["meteor", "convergence", "nova", "slam"]
	return []


func _choose_attack() -> void:
	var ids: Array = _phase_attack_ids(current_phase())
	if ids.is_empty():
		_attack_cd = 1.0
		return
	_run_attack(String(ids[randi() % ids.size()]))
	_attack_cd = float(PHASE_CD.get(_bphase, 2.0))


func _run_attack(id: String) -> void:
	_busy = true
	if is_instance_valid(rig):
		var g: int = CharacterRig.GestureKind.STOMP if id in ["slam", "pillars"] else CharacterRig.GestureKind.RAISE
		rig.cast_gesture(g, 0.9)
	match id:
		"slam": _atk_slam()
		"pillars": _atk_pillars()
		"beam": _atk_beam()
		"rays": _atk_rays()
		"summon": _atk_summon()
		"meteor": _atk_meteor()
		"convergence": _atk_convergence()
		"nova": _atk_nova()
	_unbusy_after(_attack_duration(id))


func _attack_duration(id: String) -> float:
	match id:
		"slam": return 1.0
		"pillars": return 1.1
		"beam": return 0.9
		"rays": return 1.0
		"summon": return 1.0
		"meteor": return 1.1
		"convergence": return 1.4
		"nova": return 0.6
	return 0.8


func _unbusy_after(t: float) -> void:
	get_tree().create_timer(t).timeout.connect(func() -> void: _busy = false)


# ---------------------------------------------------------------- the attacks
func _atk_slam() -> void:
	if not is_instance_valid(_hero):
		return
	var center: Vector2 = _hero.global_position
	var b: Node = load("res://scenes/combat/BlastSpell.tscn").instantiate()
	get_parent().add_child(b)
	b.configure({"target_group": "hero", "damage": 28, "radius": 100, "knockback": 360, "windup": 0.7, "element_id": Elements.Element.EARTH})
	b.detonate_at(center)   # runs its own ZONE telegraph windup (the dodge tell)
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		GroundCrater.spawn(get_parent(), center, 64.0, true)
		Juice.on_hit({"shake": 15.0, "sfx": "blast", "hitstop": 0.09}))


func _atk_pillars() -> void:
	if not is_instance_valid(_hero):
		return
	var base: Vector2 = _hero.global_position
	var offs: Array = [-180.0, 0.0, 180.0]
	for i: int in 3:
		var pt: Vector2 = base + Vector2(float(offs[i]), 0.0)
		get_tree().create_timer(0.12 * float(i)).timeout.connect(func() -> void:
			if not is_instance_valid(self):
				return
			var p := RockPillar.new()
			p.target_group = "hero"
			get_parent().add_child(p)
			p.erupt(pt, Color(0.8, 0.55, 0.28), 66.0, 30))


func _atk_beam() -> void:
	if not is_instance_valid(_hero):
		return
	var dir: Vector2 = (_hero.global_position - global_position).normalized()
	dir = Vector2(dir.x, dir.y * 0.35).normalized()   # flatten toward horizontal
	var origin: Vector2 = rig.get_weapon_tip() if is_instance_valid(rig) else global_position
	var beam := BeamSpell.new()
	beam.target_group = "hero"
	beam.element_id = Elements.Element.ARCANE
	get_parent().add_child(beam)
	beam.fire(origin, dir, Color(0.7, 0.4, 1.0), 1400.0, 34.0, 34, "arcane")


func _atk_rays() -> void:
	if not is_instance_valid(_hero):
		return
	var base: Vector2 = _hero.global_position
	var offs: Array = [-140.0, 0.0, 140.0]
	for i: int in 3:
		var pt: Vector2 = base + Vector2(float(offs[i]), 0.0)
		get_tree().create_timer(0.25 * float(i)).timeout.connect(func() -> void:
			if not is_instance_valid(self):
				return
			var d := DivineRay.new()
			d.target_group = "hero"
			get_parent().add_child(d)
			d.strike(pt, Color(1.0, 0.5, 0.2), 70.0, 40, "fire"))


func _atk_summon() -> void:
	_prune_summoned()
	var n: int = mini(2, ADD_CAP - _summoned.size())
	if n <= 0:
		return
	var chaser: Dictionary = ARCHETYPE_DEFAULTS[Archetype.CHASER]
	for i: int in n:
		var pos: Vector2 = global_position + Vector2(randf_range(-90.0, 90.0), -20.0)
		var e: Node = _spawn_runtime_enemy({
			"boss": false, "arch": 0, "hp": 22,
			"spd": float(chaser["speed"]), "touch": int(chaser["touch"]),
			"tint": Color(1.0, 0.6, 0.35, 1), "tele": false,
			"x": pos.x, "y": pos.y,
		})
		if e != null:
			_summoned.append(e)


func _prune_summoned() -> void:
	var kept: Array = []
	for e in _summoned:
		if is_instance_valid(e):
			kept.append(e)
	_summoned = kept


func _atk_meteor() -> void:
	if not is_instance_valid(_hero):
		return
	var m := MeteorSigil.new()
	m.target_group = "hero"
	get_parent().add_child(m)
	m.rain(_hero.global_position, Color(1.0, 0.55, 0.2), 170.0, 22, 12, "fire")
	Juice.zoom_pull_camera(0.16, 0.5)


func _atk_convergence() -> void:
	if not is_instance_valid(_hero):
		return
	var s := StarConvergence.new()
	s.target_group = "hero"
	get_parent().add_child(s)
	s.converge(_hero.global_position, Color(1.0, 0.4, 0.15), 170.0, 110, "fire")


func _atk_nova() -> void:
	var n: Node = load("res://scenes/combat/EnergyNova.tscn").instantiate()
	n.target_group = "hero"
	get_parent().add_child(n)
	n.activate_at(global_position)


# ------------------------------------------------------------------ boss HUD
func _build_bar() -> void:
	_bar_layer = CanvasLayer.new()
	_bar_layer.layer = 55
	add_child(_bar_layer)
	_bar = BossBar.new()
	_bar_layer.add_child(_bar)
	_bar.setup(self)


func _play_intro() -> void:
	_bphase = BPhase.INTRO
	_intro_timer = INTRO_TIME
	Juice.zoom_pull_camera(0.2, INTRO_TIME, 0.4, 0.6)
	var card := Label.new()
	card.set_anchors_preset(Control.PRESET_TOP_WIDE)
	card.offset_top = 120.0
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.text = "THE ASHSPIRE GUARDIAN"
	card.add_theme_font_size_override("font_size", 36)
	card.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	card.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.03, 0.95))
	card.add_theme_constant_override("outline_size", 7)
	card.modulate.a = 0.0
	_bar_layer.add_child(card)
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.5)
	tw.tween_interval(1.4)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)
	get_tree().create_timer(0.6).timeout.connect(_roar_intro)


func _roar_intro() -> void:
	if not is_instance_valid(self):
		return
	# No body flash (it fights the stone read + lingers under the intro hitstop) —
	# the aura pop + shake + roar sfx carry the wake. The molten core does the glow.
	if _adorn != null:
		_adorn.set_intensity(0.55)
	Juice.epic_moment({"strength": 1.0, "shake": 10.0, "sfx": "charge_up"})
