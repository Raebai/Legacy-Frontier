extends BossModRider
## MIRRORED — "copies the last spell cast."
##
## The boss watches what you throw at it and throws it back. Not a themed
## approximation: the actual SpellDef, through the actual `SpellCaster.cast`
## dispatch, so the thing that comes back at you is the same spectacle with the
## same geometry, the same element and the same weight in a clash.
##
## ── HOW IT KNOWS WHAT YOU CAST, WITHOUT A HOOK IN HERO.GD ────────────────────
## It watches the ARENA. Every spell spectacle in this game is parented to the
## arena and stamped by `SpellCaster._stamp` with three things: `caster_node`,
## `element_id` and `spell_tier`. So a spectacle whose `caster_node` is in group
## "hero" is, by construction, a spell the player just cast — and its own script is
## which spell it was. No signal, no edit to Hero.gd, and it works for every class
## in the game including ones that do not exist yet.
##
## `match_spell` then walks back up: script -> SpellDef.Kind -> the SpellLibrary
## entry of that kind that best matches the element and tier observed. It is pure
## and static, so the mapping is a headless test rather than a thing to eyeball.
##
## ── THE TELL IS THE PLAYER'S OWN VOCABULARY, ON PURPOSE ──────────────────────
## The wind-up opens a MagicCircle over the boss carrying the MIRRORED spell's
## element band and tier ring — the same sigil the player sees over their own head
## when they cast it. So the read is not "the boss is doing something", it is "the
## boss is about to do MY THING", and the player already knows exactly how long
## that takes and how it is dodged, because they have cast it.
##
## The sigil is handed to the spectacle with `MagicCircle.offer` rather than
## dismissed, so the ritual travels from the boss's hand into the muzzle in one
## continuous motion, exactly as it does for the player. Interruption withdraws it.
##
## ── FRIENDLY FIRE IS LEFT ALONE, AND THAT IS THE PLAY AGAINST IT ─────────────
## `SpellCaster.cast` routes damage through `damage_group`, which under the game's
## permanent friendly-fire rule is "everything with a body". The mirrored spell is
## therefore a real spell under the real rules — which means a boss that mirrors
## your zone can be baited into standing in it. That is deliberate. The spec's
## requirement for anything this loud is "there is a play against it", and for the
## nastiest modifier in the set the play needed to be more interesting than
## "dodge".

## Seconds between mirrors. Long: the whole point is that it answers your ULT, and
## an answer that arrives every two seconds is just a second attack pattern.
const COOLDOWN: float = 6.0
## Wind-up before the copy fires.
const TELL: float = 0.8
## How often the arena is swept for new hero spells.
const SCAN_INTERVAL: float = 0.18
## Sigil radius for the wind-up, per tier — the tier ladder, matched to SpellSigil's
## shelves so the boss's ring is the same size as the one the player just saw.
const TELL_RADIUS: Array[float] = [38.0, 54.0, 76.0]

## SCRIPT PATH -> SpellDef.Kind. Mirrors `SpellCaster`'s dispatch table in the
## opposite direction. It is written out rather than derived because SpellCaster's
## constants are a mix of scripts and scenes (NOVA is a .tscn) and because a
## silently-wrong reverse map would make this modifier fire the wrong spell rather
## than fail — the worse of the two failure modes.
const KIND_FOR_SCRIPT: Dictionary = {
	"res://scripts/combat/BeamSpell.gd": SpellDef.Kind.BEAM,
	"res://scripts/combat/DivineRay.gd": SpellDef.Kind.DIVINE_RAY,
	"res://scripts/combat/EnergyNova.gd": SpellDef.Kind.NOVA,
	"res://scripts/combat/MeteorSigil.gd": SpellDef.Kind.METEOR,
	"res://scripts/combat/StarConvergence.gd": SpellDef.Kind.CONVERGENCE,
	"res://scripts/combat/BoulderHurl.gd": SpellDef.Kind.BOULDER,
	"res://scripts/combat/RockPillar.gd": SpellDef.Kind.PILLAR,
	"res://scripts/combat/RockWall.gd": SpellDef.Kind.WALL,
	"res://scripts/combat/IceWall.gd": SpellDef.Kind.ICE_WALL,
	"res://scripts/combat/ChainBolt.gd": SpellDef.Kind.CHAIN,
	"res://scripts/combat/ZoneSpell.gd": SpellDef.Kind.ZONE,
	"res://scripts/combat/RuneOrbs.gd": SpellDef.Kind.MISSILES,
	"res://scripts/combat/DrainTether.gd": SpellDef.Kind.TETHER,
	"res://scripts/combat/BladeFlurry.gd": SpellDef.Kind.FLURRY,
	"res://scripts/combat/ShadowCrawler.gd": SpellDef.Kind.CRAWLER,
	"res://scripts/combat/RiftDagger.gd": SpellDef.Kind.THROWN_ANCHOR,
	"res://scripts/combat/AegisWard.gd": SpellDef.Kind.WARD,
	"res://scripts/combat/HorizonArc.gd": SpellDef.Kind.ARC,
}

## Kinds that MOVE THEIR CASTER. `SpellCaster` hands displacement to a duck-typed
## `blink_to` contract that only the Hero implements, so mirroring one of these
## would spawn a spectacle that quietly does nothing to the boss. Declining to
## record them means the boss keeps whatever it last saw that it CAN throw, which
## is a far better failure than a mirror that visibly fizzles.
const SKIP_KINDS: Array[int] = [SpellDef.Kind.RUSH, SpellDef.Kind.BLINK_STRIKE]

var _cool: float = 3.0
var _scan: float = 0.0
var _seen: Dictionary = {}
var _spell: SpellDef = null
var _spell_element: int = -1
var _spell_tier: int = SpellTier.Tier.HEAVY
var _casting: bool = false
var _circle: MagicCircle = null


func _tick(delta: float) -> void:
	var ph: int = boss_phase()
	if ph < 1 or ph > 3:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_INTERVAL
		_observe()
	if _casting:
		return
	_cool -= delta
	if _cool > 0.0 or _spell == null or boss_busy():
		return
	_begin_mirror()


# ------------------------------------------------------------------- watching
func _observe() -> void:
	var host: Node = arena()
	if host == null:
		return
	if _seen.size() > 256:
		_seen.clear()          # cheap bound; a re-seen corpse is harmless
	for n: Node in host.get_children():
		var id: int = n.get_instance_id()
		if _seen.has(id):
			continue
		_seen[id] = true
		var caster: Variant = n.get("caster_node")
		# ⚠ VALIDITY BEFORE `is` — a live spell node holding a dead caster.
		if not is_instance_valid(caster) or not (caster is Node):
			continue
		if not (caster as Node).is_in_group("hero"):
			continue
		var scr: Script = n.get_script() as Script
		if scr == null:
			continue
		var elem: int = int(n.get("element_id")) if n.get("element_id") != null else -1
		var tier_v: Variant = n.get("spell_tier")
		var tier: int = int(tier_v) if tier_v != null else -1
		var found: SpellDef = match_spell(scr.resource_path, elem, tier)
		if found == null:
			continue
		_spell = found
		_spell_element = elem if elem >= 0 else found.element
		_spell_tier = SpellTier.of(found)


## PURE. Which SpellDef the boss should throw back, given the script of the
## spectacle it just watched, plus the element and tier stamped on it.
## Returns null when the spell is not mirrorable (unknown script, or a kind that
## displaces its caster).
static func match_spell(script_path: String, element: int, tier: int) -> SpellDef:
	if not KIND_FOR_SCRIPT.has(script_path):
		return null
	var kind: int = int(KIND_FOR_SCRIPT[script_path])
	if SKIP_KINDS.has(kind):
		return null
	var best: SpellDef = null
	var best_score: int = -1
	for s in SpellLibrary.build_all():
		var sd: SpellDef = s as SpellDef
		if sd == null or sd.kind != kind:
			continue
		# Element is worth more than tier: a frost beam answered with a frost beam
		# of the wrong weight still READS as your spell; a fire one does not.
		var score: int = 1
		if element >= 0 and sd.element == element:
			score += 4
		if tier >= 0 and SpellTier.of(sd) == tier:
			score += 2
		if score > best_score:
			best_score = score
			best = sd
	return best


# -------------------------------------------------------------------- casting
func _begin_mirror() -> void:
	var h: Node2D = nearest_hero()
	var host: Node = arena()
	if h == null or host == null or not host.is_inside_tree() or _spell == null:
		return
	_casting = true
	_cool = COOLDOWN
	set_boss_busy(true)

	var elem: int = _spell_element if _spell_element >= 0 else Elements.Element.ARCANE
	var col: Color = Elements.color(elem)
	var r: Node = rig()
	var muzzle: Vector2 = boss_pos() + Vector2(0.0, -46.0)
	if r != null:
		r.call("cast_gesture", CharacterRig.GestureKind.RAISE, 0.95)
	# The on-body charge glow every telegraphed enemy attack in this game already
	# uses — so the "something is coming from THAT body" read is the familiar one.
	if boss.has_method("_spawn_caster_signal"):
		boss.call("_spawn_caster_signal", 18.0, TELL)

	var tell_r: float = TELL_RADIUS[clampi(_spell_tier, 0, 2)]
	_circle = MagicCircle.new()
	host.add_child(_circle)
	_circle.global_position = muzzle
	_circle.appear(col, tell_r, 0.22)
	_circle.set_signature(elem, _spell_tier)
	# CO-OP: THE TELL IS THE POINT. The sigil says "the boss is about to do YOUR
	# thing", which is the read that lets a player who has cast that spell already
	# know how long it takes and how it is dodged. Host-only, so it is broadcast.
	bfx("circle", {"pos": muzzle, "col": col, "r": tell_r, "grow": 0.22,
		"el": elem, "tier": _spell_tier, "hold": TELL})

	get_tree().create_timer(TELL).timeout.connect(_fire)


func _fire() -> void:
	_casting = false
	if boss == null or not is_instance_valid(boss) or boss_phase() == PHASE_DEAD:
		# Interrupted: bloom the un-taken sigil out rather than stranding it.
		MagicCircle.withdraw(boss)
		_circle = null
		return
	set_boss_busy(false)
	var host: Node = arena()
	var h: Node2D = nearest_hero()
	if host == null or not host.is_inside_tree() or h == null or _spell == null:
		MagicCircle.withdraw(boss)
		_circle = null
		return
	var elem: int = _spell_element if _spell_element >= 0 else Elements.Element.ARCANE
	var col: Color = Elements.color(elem)
	var origin: Vector2 = boss_pos() + Vector2(0.0, -40.0)
	var r: Node = rig()
	if r != null and r.has_method("get_weapon_tip"):
		origin = r.call("get_weapon_tip")
	# ORDER IS LOAD-BEARING (MagicCircle's rule 1): the offer must be made BEFORE
	# the spell is spawned and in the SAME FRAME, because the spectacle adopts
	# inside its own constructor path. And rule 2: let go of the reference straight
	# after, or we would drag the sigil back onto the boss while it is travelling.
	# ⚠ VALIDITY BEFORE THE CALL, BECAUSE THE CALLEE CANNOT DO IT FOR US.
	# `MagicCircle.offer` opens with `if circle == null or not is_instance_valid(circle)`
	# and that guard is unreachable from here: its parameter is TYPED
	# (`circle: MagicCircle`), and binding a freed instance to a typed parameter faults
	# before the body runs at all. Measured -- "The Object-derived class of argument 1
	# (previously freed) is not a subclass of the expected argument class."
	# `_circle` is held across the TELL (a SceneTreeTimer) and is parented to the ARENA,
	# not to the boss -- so a floor teardown during the tell frees the sigil while this
	# rider and its boss survive the frame. That is the window.
	if is_instance_valid(_circle):
		MagicCircle.offer(_circle, boss)
	_circle = null
	SpellCaster.cast(_spell, host, origin, h.global_position, col, _spell.effect, boss, &"hero")
	# CO-OP: THE ANSWER. The nastiest modifier in the set throwing your own ult back
	# at you is unplayable if it is invisible on your screen. The twin is rebuilt on
	# the client through the SAME `SpellCaster.cast` dispatcher — identical geometry,
	# element and clash weight — pointed at the group nobody is in. `sid` travels
	# rather than the SpellDef because a Resource is not RPC payload, and every peer
	# can look the id back up in `SpellLibrary`.
	bfx("spell", {"sid": _spell.id, "pos": origin, "pt": h.global_position,
		"col": col, "fx": _spell.effect, "el": elem})
	Juice.shake_camera(4.0)
