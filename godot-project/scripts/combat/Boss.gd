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

## BEAM TELEGRAPH (1.6). The beam used to be the one attack with no tell — a
## 1400 px/s bolt out of a still silhouette, which breaks the floor's own
## "every attack is dodgeable because you saw it coming" grammar. Now it lays a
## LANE along the snapshot aim first, exactly like the charger's dash lane, and
## fires when the lane expires. The aim is frozen at telegraph time, so walking
## out of the lane is the dodge.
const BEAM_WINDUP: float = 0.55
const BEAM_LANE_LENGTH: float = 900.0
const BEAM_LANE_WIDTH: float = 40.0
const BEAM_ACCENT: Color = Color(0.7, 0.4, 1.0, 1.0)

## Guardian size as a fraction of the full Ashspire colossus. Encounter sets this
## pre-_ready from the floor's boss scale: 1.0 on a BOSS floor, smaller for the
## mini-guardian that now caps every other floor. Scales the rig + the crown, not
## the collision box (which stays a clean rectangle either way).
@export var body_scale: float = 1.0

var _bphase: int = BPhase.INTRO
var _attack_cd: float = 0.0
var _intro_timer: float = INTRO_TIME
var _busy: bool = false
var _adorn: BossAdornment = null
var _bar_layer: CanvasLayer = null
var _bar: BossBar = null
var _summoned: Array = []


## WHO THIS BOSS IS. Declared on the base rather than on `TowerBoss` so that
## `BossBar` and the intro card can ask ANY boss what it is called and what colour it
## writes itself in — including this one. Before this, the bar carried a
## `const NAME_TEXT = "THE ASHSPIRE GUARDIAN"` and the roster rewrote the label after
## construction; see `BossBar.setup` for why that was a trap rather than a default.
func boss_title() -> String:
	return "THE ASHSPIRE GUARDIAN"


func boss_accent() -> Color:
	return Color(1.0, 0.55, 0.2)


func _ready() -> void:
	super._ready()   # hp, _hero, joins "enemy" + "mortal", tiny CharacterBars
	body_scale = clampf(body_scale, 0.3, 1.0)
	if is_instance_valid(rig):
		rig.set("height", RIG_HEIGHT * body_scale)
		rig.set_tint(STONE_TINT)
		rig.class_preset("brawler")
		rig.set_equipment("head", "crown")            # a guardian-king crown on the colossus
		rig.set_aura(Color(1.0, 0.45, 0.15), 0.45)   # subtle ember halo — the stone body must read
		rig.set_aura_tier(2)
	_adorn = BossAdornment.new()
	add_child(_adorn)
	_adorn.configure(RIG_HEIGHT * body_scale)
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
	if global_position.distance_to(_hero.global_position) < RIG_HEIGHT * body_scale * 0.55:
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
	# THE CLIMAX RUNG. A boss dying is the one moment in a run that earns the most
	# expensive mark in the vocabulary: `CUT_IN` slams black bars in from top and
	# bottom and holds on a band the boss is still DRAWN inside, so you watch it
	# fall instead of watching a white rectangle. If this fires more than once a
	# fight something has gone wrong — that rarity is what makes it land.
	#
	# The old pair of calls here (an epic_moment with frame:true AND a second
	# impact_frame at 1.3, back to back) was two white blow-outs on top of each
	# other; the arbiter would now refuse the second one anyway, but asking for it
	# was the bug. One beat, one mark.
	Juice.epic_moment({"strength": 1.4, "shake": 20.0, "sfx": "cannon"})
	Juice.tier_frame(SpellTier.Tier.ULT, global_position, -1, {"climax": true})
	var sc := StarConvergence.new()
	sc.target_group = "none"   # visual-only finisher (no group "none" -> hits nobody)
	# Owned too, even though it damages nobody: the reaction layer does not care
	# about target groups, and a death spectacle crossing a live hero beam should
	# read as the boss's, not as an ownerless orphan.
	sc.set("caster_node", self)
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


## PHASE ESCALATION, and in co-op it has to CROSS. `take_damage` forwards a puppet
## hit to the host before any phase logic runs, which is correct — but it means a
## client's guardian never re-tinted, never grew its aura, never played the enrage
## beat. Half the party watched a boss that visibly never changed. The broadcast
## goes out first so the two screens escalate together.
func _enter_phase(p: int) -> void:
	if _net != null and _net.is_host():
		_net.broadcast_boss_phase(self, p)
	_apply_phase(p, true)
	emit_signal("phase_changed", current_phase())


## Client side of the same escalation, driven by the host's broadcast. Same LOOK,
## none of the fight logic — see the `authoritative` flag below for exactly what a
## client must not do.
func net_apply_phase(p: int) -> void:
	_apply_phase(p, false)
	emit_signal("phase_changed", current_phase())


## ⚠ ONE FUNCTION, NOT TWO, and that is the point. The obvious shape here is a
## client-side copy of the escalation — and a copy is precisely how the two drift:
## the next person to retint P3 edits one of them, the boss looks different on the
## two phones, and nothing errors. So the host path and the client path are the same
## code, and `authoritative` names the only difference.
##
## What a client must NOT do: spawn the enrage adds (enemies are host-owned, and a
## client minting its own would put bodies on one screen that exist on neither peer's
## authority), or drive the attack clock (only the host chooses attacks at all).
func _apply_phase(p: int, authoritative: bool) -> void:
	_bphase = p
	if authoritative:
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
			if authoritative:
				_atk_summon()   # open the enrage with adds
		BPhase.P3:
			if _adorn != null: _adorn.set_intensity(1.0)
			if is_instance_valid(rig):
				rig.set_tint(Color(0.52, 0.28, 0.24))
				rig.set_aura(Color(1.0, 0.28, 0.08), 0.78)
				rig.set_aura_tier(4)
			# The enrage is a REVEAL, not a detonation: the boss changes and you
			# need to see what it changed into. So the black cut, which drops the
			# room out and leaves the new silhouette lit, rather than the white
			# blow-out, which erases the very thing the beat exists to show.
			Juice.epic_moment({"strength": 1.2, "shake": 14.0, "sfx": "cannon",
				"frame": true, "at": global_position,
				"style": ImpactFrame.Style.SILHOUETTE})


## Broadcast one spectacle to every client as a DAMAGE-FREE twin. Host-gated inside
## `Net.broadcast_boss_fx`, so this is a no-op in single player and on a client.
func _bfx(kind: String, data: Dictionary) -> void:
	if _net != null and _net.is_host():
		data["src"] = String(get_path())
		_net.broadcast_boss_fx(kind, data)


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
		"beam": return BEAM_WINDUP + 0.9   # the tell is part of the attack
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
	# CASTER IDENTITY — see _atk_beam for why this is load-bearing rather than
	# bookkeeping. `set()` is a silent no-op on a spectacle that has not declared
	# `caster_node` yet, so this is safe now and becomes live the day it does.
	b.set("caster_node", self)
	b.configure({"target_group": "hero", "damage": 28, "radius": 100, "knockback": 360, "windup": 0.7, "element_id": Elements.Element.EARTH})
	b.detonate_at(center)   # runs its own ZONE telegraph windup (the dodge tell)
	# Co-op: the slam's own windup IS the dodge tell, so the twin carries it too —
	# a client that only got the crater would be told about the attack after it hit.
	_bfx("slam", {"pos": center, "r": 100.0, "windup": 0.7, "el": Elements.Element.EARTH})
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		GroundCrater.spawn(get_parent(), center, 64.0, true)
		_bfx("crater", {"pos": center, "r": 64.0})
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
			p.set("caster_node", self)   # caster identity — see _atk_beam
			get_parent().add_child(p)
			p.erupt(pt, Color(0.8, 0.55, 0.28), 66.0, 30)
			_bfx("pillar", {"pos": pt, "col": Color(0.8, 0.55, 0.28), "r": 66.0}))


## THE TELL. Snapshot the aim, lay a charge LANE from the guardian along it, and
## only fire when the lane expires. Same grammar as every other boss attack (and
## as the charger's dash): the shape you can see is the shape that will hurt, and
## it is on screen long enough to step out of. `no_resolve` keeps this off
## Enemy._on_telegraph_fired, whose archetype switch would run a brute strike.
func _atk_beam() -> void:
	if not is_instance_valid(_hero):
		return
	var dir: Vector2 = (_hero.global_position - global_position).normalized()
	dir = Vector2(dir.x, dir.y * 0.35).normalized()   # flatten toward horizontal
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var tele: Telegraph = _emit_telegraph({
		"style": Telegraph.Style.MUZZLE, "pos": global_position,
		"accent": BEAM_ACCENT, "windup": BEAM_WINDUP,
		"line": true, "length": BEAM_LANE_LENGTH, "width": BEAM_LANE_WIDTH,
		"angle": dir.angle(), "aim": dir, "reach": BEAM_LANE_LENGTH,
		"no_resolve": true,
	})
	_spawn_caster_signal(16.0, BEAM_WINDUP)
	if tele == null:
		_fire_beam(dir)
		return
	tele.fired.connect(func() -> void:
		_free_caster_signal()
		if is_instance_valid(self) and _bphase != BPhase.DEAD:
			_fire_beam(dir))


func _fire_beam(dir: Vector2) -> void:
	var origin: Vector2 = rig.get_weapon_tip() if is_instance_valid(rig) else global_position
	var beam := BeamSpell.new()
	beam.target_group = "hero"
	beam.element_id = Elements.Element.ARCANE
	# CASTER IDENTITY — load-bearing, not bookkeeping. The reaction layer's
	# ownership predicate reads this, and a null caster reports as "unowned",
	# which satisfies neither `require_owner: "same"` nor `"different"`. So an
	# ownerless beam matches NO clash row at all: without this line the boss's
	# beam could never annihilate against the hero's, and the cross-caster
	# Hollow Purple row was unreachable in single-player. The same omission is
	# what made Hollow Purple look broken for two sessions.
	beam.caster_node = self
	get_parent().add_child(beam)
	beam.fire(origin, dir, Color(0.7, 0.4, 1.0), 1400.0, 34.0, 34, "arcane")
	_bfx("beam", {"pos": origin, "dir": dir, "col": Color(0.7, 0.4, 1.0),
		"len": 1400.0, "w": 34.0, "fx": "arcane", "el": Elements.Element.ARCANE})


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
			d.set("caster_node", self)   # caster identity — see _atk_beam
			get_parent().add_child(d)
			d.strike(pt, Color(1.0, 0.5, 0.2), 70.0, 40, "fire")
			_bfx("ray", {"pos": pt, "col": Color(1.0, 0.5, 0.2), "r": 70.0, "fx": "fire",
				"el": Elements.Element.FIRE}))


## Adds are capped TWICE: by the guardian's own ADD_CAP (this fight should not
## become an add fight) and by the floor's live-entity budget, which the boss
## does not own and must ask about. Before 1.4 this bypassed the encounter cap
## entirely, so a summoning boss could push the floor past its ceiling.
func _atk_summon() -> void:
	_prune_summoned()
	var n: int = mini(2, ADD_CAP - _summoned.size())
	n = mini(n, _spawn_headroom())
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
	m.set("caster_node", self)   # caster identity — see _atk_beam
	get_parent().add_child(m)
	m.rain(_hero.global_position, Color(1.0, 0.55, 0.2), 170.0, 22, 12, "fire")
	_bfx("meteor", {"pos": _hero.global_position, "col": Color(1.0, 0.55, 0.2),
		"r": 170.0, "n": 12, "fx": "fire", "el": Elements.Element.FIRE})
	Juice.zoom_pull_camera(0.16, 0.5)


func _atk_convergence() -> void:
	if not is_instance_valid(_hero):
		return
	var s := StarConvergence.new()
	s.target_group = "hero"
	s.set("caster_node", self)   # caster identity — see _atk_beam
	get_parent().add_child(s)
	s.converge(_hero.global_position, Color(1.0, 0.4, 0.15), 170.0, 110, "fire")
	_bfx("convergence", {"pos": _hero.global_position, "col": Color(1.0, 0.4, 0.15),
		"r": 170.0, "fx": "fire", "el": Elements.Element.FIRE})


func _atk_nova() -> void:
	var n: Node = load("res://scenes/combat/EnergyNova.tscn").instantiate()
	n.target_group = "hero"
	n.set("caster_node", self)   # caster identity — see _atk_beam
	get_parent().add_child(n)
	n.activate_at(global_position)
	_bfx("nova", {"pos": global_position})


# ------------------------------------------------------------------ boss HUD
func _build_bar() -> void:
	_bar_layer = CanvasLayer.new()
	_bar_layer.layer = 55
	add_child(_bar_layer)
	_bar = BossBar.new()
	_bar_layer.add_child(_bar)
	# Virtual dispatch: a subclass's title/accent are in place from the first frame,
	# so the bar never briefly shows the wrong boss's name.
	_bar.setup(self, boss_title(), boss_accent())


func _play_intro() -> void:
	_bphase = BPhase.INTRO
	_intro_timer = INTRO_TIME
	Juice.zoom_pull_camera(0.2, INTRO_TIME, 0.4, 0.6)
	var card := Label.new()
	card.set_anchors_preset(Control.PRESET_TOP_WIDE)
	card.offset_top = 120.0
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.text = boss_title()
	card.add_theme_font_size_override("font_size", 36)
	card.add_theme_color_override("font_color", boss_accent())
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
