class_name EraserBoss
extends TowerBoss
## THE ERASER — the hand that takes the page back.
##
## ── THE ARTIST ───────────────────────────────────────────────────────────────
## Not an artist. The other four draw; this one is what happens when the tower
## decides a floor was a mistake. A blunt grey mass with a worn edge, leaving pink
## crumbs, and every mark it makes is the ABSENCE of a mark. It appears on floors
## 1-6 and stops, because by the deep half of the tower the pages are worth keeping.
##
## ── HOW IT FIGHTS DIFFERENTLY ────────────────────────────────────────────────
## THE PLAYER MUST COME TO IT AND STAY. Every other fight in the roster is about
## making space:
##
##   Scribble      — wants to be AT you.       Answer: dodge on the beat.
##   Cartographer  — wants you at a DISTANCE.  Answer: stand in the right cell.
##   Illuminator   — wants you COMMITTED.      Answer: survive, then punish.
##   Eraser        — wants the ROOM.           Answer: give up ground and close in.
##
## It eats the floor permanently — erased patches last PATCH_LIFE seconds and they
## ACCUMULATE, because nothing here cleans up after itself — and the one place it
## never erases is the pocket under its own feet. Run and the room runs out. The
## only ground that is reliably safe is the ground it is standing on, which means
## the correct play against the boss that denies space is to walk INTO its reach
## and stay there. Kiting loses. That is the whole fight.
##
## ── WHY THE PATCHES ARE FIELDS AND NOT STRIKES ───────────────────────────────
## A strike is an event you dodge and then forget. A field is a DECISION that is
## still on the floor two attacks later, and the fight only asks its question if
## the answers stack up where you can see them. The tick damage is deliberately
## small (PATCH_TICK against a mob roster whose biggest single hit is 22): standing
## in one is not what kills you, running out of anywhere to stand is.
##
## ── ⚠ THE NAMED WEAKNESS, KEPT IN THE FILE ───────────────────────────────────
## This is a SPATIAL boss and so is the Cartographer. The separation is real but it
## is of KIND, not of degree: the Cartographer's page RESETS between figures (read
## the shape, step to the cell, the floor is clean again), and this one's never does
## (commit to a shrinking pocket). If a playtest reports that the two feel the same,
## THIS is the one to cut — the Cartographer is load-bearing for the compass
## annulus, which nothing else in the game teaches.

const RIG_H: float = 78.0
## Worn rubber grey, and the pink crumb it leaves behind.
const RUBBER: Color = Color(0.58, 0.55, 0.57)
const CRUMB: Color = Color(0.95, 0.72, 0.74)

## AN ERASED PATCH. Long-lived on purpose — see the class doc: it is the floor
## being taken away, not a hit to dodge, so it has to still be there when the next
## attack lands. Nine seconds is roughly four attack cadences at P1.
const PATCH_LIFE: float = 9.0
const PATCH_RADIUS: float = 76.0
const PATCH_TICK: int = 5
const PATCH_TELL: float = 0.5

## THE POCKET. The Eraser never erases within this distance of itself, and that is
## the only promise the fight makes. Stated as a constant because the whole read is
## "the safe ground is where the boss is" and a jittered pocket would make that a
## guess instead of a rule.
const POCKET: float = 110.0

## PRESS. The close nova — the NEAR edge of the pocket, so "stay near" is a band to
## hold rather than a corner to hide in. Without this the answer to the whole boss
## would be "stand on its toes and never move again".
const PRESS_TELL: float = 0.62
const PRESS_RADIUS: float = 96.0

## SWATHE (P2+). Four patches marching AWAY from the boss — it herds you inward,
## which is the fight stating its thesis in a direction rather than in words.
const SWATHE_COUNT: int = 4
const SWATHE_STEP: float = 118.0
const SWATHE_STAGGER: float = 0.13

## SMEAR (P2+). A drag across the floor: the answer to a player who has found one
## clean tile and decided to live on it.
const SMEAR_LEN: float = 380.0
const SMEAR_WIDTH: float = 46.0
const SMEAR_TELL: float = 0.5
const SMEAR_RADIUS: float = 80.0
const SMEAR_DAMAGE: int = 24

## UNMAKE (P3). The thesis, stated: six patches laid at fixed offsets with a clean
## corridor at +-POCKET. Fixed, not rolled — the player is being TOLD where to
## stand, and the attack is only fair if the answer is the same every time.
const UNMAKE_OFFSETS: Array[float] = [-370.0, -260.0, -150.0, 150.0, 260.0, 370.0]
const UNMAKE_STAGGER: float = 0.1
const UNMAKE_TELL: float = 0.7


func boss_title() -> String: return "THE ERASER"
func boss_artist() -> String: return "worn rubber, and pink crumbs on the floor"
## THE BILLING. It is not an artist and it does not pretend to be one — it is the
## decision to un-draw, given a body. The epithet says which of the two it is.
func boss_epithet() -> String: return "THAT WHICH TAKES THE PAGE BACK"
func bark_suffix() -> String: return "eraser"
## It does not redraw the page. It rubs it out and leaves the room emptier.
func redraw_style() -> StringName: return &"erase"
func boss_accent() -> Color: return CRUMB
func boss_tint() -> Color: return RUBBER
func boss_rig_height() -> float: return RIG_H
func boss_preset() -> String: return "juggernaut"


## Slow to open and never frantic. This boss escalates by leaving MORE of the room
## gone, not by acting faster — a floor that is disappearing does not need urgency
## on top, and a player who cannot find a gap between casts cannot walk into the
## pocket, which is the one move the fight is asking for.
func phase_cooldown(p: int) -> float:
	match p:
		1: return 2.2
		2: return 1.7
		3: return 1.3
	return 2.0


func _phase_attack_ids(phase: int) -> Array:
	match phase:
		1: return ["smudge", "press"]
		2: return ["smudge", "press", "swathe", "smear"]
		3: return ["unmake", "swathe", "smear", "press"]
	return []


func gesture_for(id: String) -> int:
	return CharacterRig.GestureKind.STOMP if id in ["press", "smear"] else CharacterRig.GestureKind.GATHER


func _attack_duration(id: String) -> float:
	match id:
		"smudge": return PATCH_TELL + 0.5
		"press": return PRESS_TELL + 0.5
		"swathe": return PATCH_TELL + SWATHE_STAGGER * float(SWATHE_COUNT) + 0.4
		"smear": return SMEAR_TELL + 0.6
		"unmake": return UNMAKE_TELL + UNMAKE_STAGGER * float(UNMAKE_OFFSETS.size()) + 0.5
	return 1.0


func _perform(id: String) -> void:
	match id:
		"smudge": _atk_smudge()
		"press": _atk_press()
		"swathe": _atk_swathe()
		"smear": _atk_smear()
		"unmake": _atk_unmake()


# ---------------------------------------------------------------- the moveset
## SMUDGE. One patch, on the ground you are standing on. The clock of the whole
## fight: it is not trying to hit you, it is trying to make where you are stop
## being anywhere.
func _atk_smudge() -> void:
	if not is_instance_valid(_hero):
		return
	_erase_at(_hero.global_position, PATCH_RADIUS, PATCH_TELL)


## PRESS. A close nova centred on the boss, reaching just past the pocket's near
## edge. It is the reason the pocket is a BAND: stand on its feet and this catches
## you, stand outside the pocket and the patches do.
func _atk_press() -> void:
	summon_circle(global_position, Elements.Element.EARTH, SpellTier.Tier.HEAVY,
		PRESS_RADIUS, PRESS_TELL, true)
	get_tree().create_timer(PRESS_TELL).timeout.connect(func() -> void:
		if not is_instance_valid(self) or _bphase == BPhase.DEAD:
			return
		# ⚠ EnergyNova is a `.tscn`, so it cannot go through `spawn_spectacle` — all
		# five ownership properties are set by hand. A spectacle with no `caster_node`
		# reports "unowned" to the reaction layer and is silently inert there, with no
		# error anywhere. Same shape as `ScribbleBoss._atk_tantrum`.
		var n: Node = load("res://scenes/combat/EnergyNova.tscn").instantiate()
		n.set("target_group", "hero")
		n.set("_target_group", "hero")
		n.set("caster_node", self)
		n.set("element_id", Elements.Element.EARTH)
		n.set("spell_tier", SpellTier.Tier.HEAVY)
		get_parent().add_child(n)
		n.call("activate_at", global_position)
		_bfx("nova", {"pos": global_position})
		Juice.on_hit({"shake": 8.0, "sfx": "blast", "hitstop": 0.05}))


## SWATHE (P2+). Four patches marching outward from the boss along the hero's
## bearing. It does not aim AT you — it takes the ground BEHIND you, one step at a
## time, so backing away costs more each time you do it.
func _atk_swathe() -> void:
	if not is_instance_valid(_hero):
		return
	var away: float = signf(_hero.global_position.x - global_position.x)
	if away == 0.0:
		away = 1.0
	for i: int in SWATHE_COUNT:
		var at := Vector2(global_position.x + away * (POCKET + SWATHE_STEP * float(i + 1)),
			_hero.global_position.y)
		var delay: float = SWATHE_STAGGER * float(i)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_instance_valid(self) or _bphase == BPhase.DEAD:
				return
			_erase_at(at, PATCH_RADIUS * 0.9, PATCH_TELL))


## SMEAR (P2+). A drag torn across the floor away from the body — the same reaching
## ground grab the Scribble scratches with, recoloured, and here it is the answer to
## somebody who has found one clean tile and stopped moving. It DAMAGES, which the
## patches barely do: this is the attack, the patches are the fight.
func _atk_smear() -> void:
	if not is_instance_valid(_hero):
		return
	var aim: Vector2 = _hero.global_position - global_position
	aim = Vector2(aim.x, aim.y * 0.3)
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	var dir: Vector2 = aim.normalized()
	lane_tell(dir, SMEAR_LEN, SMEAR_WIDTH, SMEAR_TELL, func() -> void:
		var n: Node = spawn_spectacle("res://scripts/combat/ShadowRoot.gd",
			Elements.Element.SHADOW, SpellTier.Tier.HEAVY)
		if n == null:
			return
		var col: Color = RUBBER.lerp(CRUMB, 0.5)
		n.call("erupt", global_position, dir, col, SMEAR_RADIUS, SMEAR_DAMAGE, "shadow")
		_bfx("root", {"pos": global_position, "aim": dir, "col": col, "r": SMEAR_RADIUS,
			"fx": "shadow", "el": Elements.Element.SHADOW})
		Juice.shake_camera(5.0))


## UNMAKE (P3). Six patches at fixed offsets either side, leaving one clean corridor
## at +-POCKET. The fight has been implying this for two phases; here it says it.
##
## The offsets are CONSTANTS and the corridor is always the same width, because an
## attack whose entire content is "stand here" has to mean the same thing every
## time it is cast or it is not a lesson, it is a dice roll.
func _atk_unmake() -> void:
	summon_circle(global_position, Elements.Element.SHADOW, SpellTier.Tier.ULT,
		POCKET, UNMAKE_TELL, true)
	for i: int in UNMAKE_OFFSETS.size():
		var at := Vector2(global_position.x + UNMAKE_OFFSETS[i], global_position.y)
		var delay: float = UNMAKE_STAGGER * float(i)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_instance_valid(self) or _bphase == BPhase.DEAD:
				return
			_erase_at(at, PATCH_RADIUS, UNMAKE_TELL))
	Juice.zoom_pull_camera(0.15, 0.6)


# ------------------------------------------------------------------- internals
## OPEN AN ERASED PATCH, telegraphed first. The one rule the whole fight rests on
## lives here rather than at each call site: a patch is never opened inside the
## pocket. Putting it in the helper means "the ground under it is safe" cannot be
## forgotten by an attack added later — the same argument `spawn_spectacle` makes
## about the ownership stamp.
func _erase_at(at: Vector2, radius: float, windup: float) -> void:
	var pushed: Vector2 = at
	var dx: float = at.x - global_position.x
	if absf(dx) < POCKET:
		var away: float = signf(dx)
		if away == 0.0:
			away = 1.0 if (randi() % 2) == 0 else -1.0
		pushed.x = global_position.x + away * POCKET
	zone_tell(pushed, radius, windup, func() -> void:
		var z: Node = spawn_spectacle("res://scripts/combat/ZoneSpell.gd",
			Elements.Element.SHADOW, SpellTier.Tier.HEAVY)
		if z == null:
			return
		z.call("open", pushed, RUBBER, radius, PATCH_TICK, "shadow", PATCH_LIFE)
		# The patches ARE the fight. A client that could not see which ground was
		# gone would be playing a different game in the same room — it would read
		# the pocket as arbitrary and the boss as unfair.
		_bfx("zone", {"pos": pushed, "col": RUBBER, "r": radius, "fx": "shadow",
			"el": Elements.Element.SHADOW, "life": PATCH_LIFE}))
