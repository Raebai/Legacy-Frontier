extends BossModRider
## UNFINISHED — the sixth modifier. "The artist keeps rubbing it out."
##
## THE DESIGN ARGUMENT (the spec names five and asks for a sixth in the same
## spirit; this is the reasoning, kept here rather than in a changelog):
##
## The five named modifiers each rewrite something the boss DOES — its pace
## (Enraged), its body count (Split), the ground (Void-touched), its repertoire
## (Mirrored), its aggression (Patient). Not one of them touches WHERE IT IS. On a
## phone, spacing is the game: every boss in the roster is built around a range it
## wants to hold, and every answer the player has is a distance. Taking that axis
## away is the biggest behavioural change left that is not a number.
##
## It is also the modifier the lore hands you for free. The tower is DRAWN. Each
## floor is a sheet of paper under an unseen hand. So: the hand keeps changing its
## mind. The boss is ERASED mid-fight and REDRAWN somewhere else in the room.
##
## ── THE PLAY AGAINST IT ──────────────────────────────────────────────────────
## The spec's rule for anything big is "unmistakable wind-up, punishable cast,
## there is a play against it". So the REDRAW MARK — a ground sigil in the same
## charge-and-snap vocabulary the player already reads off every spell in the game
## — lands on the page BEFORE the body does, and the body arrives where the mark
## is. Step off the mark. The boss also arrives with its attack cooldown spent, so
## a player who ignores the mark eats the first swing for free; a player who reads
## it gets a free swing instead, because the boss is rooted for the tell.
##
## Deliberately NOT random-teleport: the destination is always chosen relative to
## the hero, so the redraw is a repositioning of the FIGHT rather than a dice roll
## about whether the boss is nearby.

## Seconds between redraws, per phase.
const INTERVAL: Array[float] = [7.5, 5.8, 4.2]
## How long the mark is on the page before the body arrives. Long enough to walk
## out of at hero speed, short enough that the boss is not a free target.
const TELL: float = 0.75
## Horizontal offsets from the hero the boss may be redrawn at. Both sides, so the
## redraw can cut off a retreat instead of always landing in front.
const OFFSETS: Array[float] = [-215.0, -150.0, 150.0, 215.0]
const MARK_RADIUS: float = 62.0

var _timer: float = 4.0
var _redrawing: bool = false


func _tick(delta: float) -> void:
	if _redrawing:
		return
	var ph: int = boss_phase()
	if ph < 1 or ph > 3:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL[clampi(ph - 1, 0, INTERVAL.size() - 1)]
	# Never interrupt the boss's own cast. A redraw that ate a telegraphed attack
	# would break the promise that the shape you can see is the shape that hurts.
	if boss_busy():
		_timer = 0.9
		return
	_begin_redraw()


func _begin_redraw() -> void:
	var h: Node2D = nearest_hero()
	var host: Node = arena()
	if h == null or host == null or not host.is_inside_tree():
		return
	var dest := Vector2(
		h.global_position.x + OFFSETS[randi() % OFFSETS.size()],
		boss_pos().y
	)
	_redrawing = true
	set_boss_busy(true)          # rooted for the tell: this is the punish window

	var tint: Color = BossModifier.tint_for(BossModifier.UNFINISHED)
	# THE MARK, in the game's own summoning vocabulary — a face-on sigil laid FLAT
	# on the floor, which is how every placed spell in this game says "the ground is
	# about to do something here". Its glyph band fills as the tell runs, so the
	# countdown is literally countable off the rim.
	var mark := MagicCircle.new()
	host.add_child(mark)
	mark.global_position = dest
	mark.appear(tint, MARK_RADIUS, 0.16)
	mark.set_signature(Elements.Element.ARCANE, SpellTier.Tier.HEAVY)
	mark.set_ground(0.34)
	mark.hold(TELL, 0.2)

	# The erasure itself: the body scribbles out where it stands.
	CombatVfx.spawn_burst(host, boss_pos() + Vector2(0.0, -20.0),
		Color(tint.r, tint.g, tint.b, 0.9), Color(tint.r, tint.g, tint.b, 0.0),
		20, 0.45, 60.0, 190.0, 0.8, 2.2, 0.0, 0.0, true)
	var r: Node = rig()
	if r != null:
		r.call("flash_color", Color(1.5, 1.5, 1.5), 0.14)
	Juice.shake_camera(3.0)

	# CO-OP. The boss's new POSITION replicates on its own (the enemy synchronizer
	# streams `position`), so what a client is missing is not the move — it is the
	# WARNING. Without the mark the body simply blinks across the room, and the one
	# play this modifier offers ("step off the mark") does not exist on that screen.
	bfx("circle", {"pos": dest, "col": tint, "r": MARK_RADIUS, "grow": 0.16,
		"el": Elements.Element.ARCANE, "tier": SpellTier.Tier.HEAVY,
		"hold": TELL, "ground": true})
	bfx("burst", {"pos": boss_pos() + Vector2(0.0, -20.0),
		"col": Color(tint.r, tint.g, tint.b, 0.9), "n": 20, "life": 0.45,
		"v0": 60.0, "v1": 190.0, "s0": 0.8, "s1": 2.2})

	get_tree().create_timer(TELL).timeout.connect(func() -> void: _land(dest))


func _land(dest: Vector2) -> void:
	_redrawing = false
	if not is_instance_valid(self) or boss == null or not is_instance_valid(boss):
		return
	if boss_phase() == PHASE_DEAD:
		return
	(boss as Node2D).global_position = dest
	set_boss_busy(false)
	# Redrawn WITH ITS COOLDOWN SPENT — the redraw is an approach, not a rest.
	boss.set("_attack_cd", 0.05)
	var host: Node = arena()
	if host != null and host.is_inside_tree():
		var tint: Color = BossModifier.tint_for(BossModifier.UNFINISHED)
		CombatVfx.spawn_burst(host, dest + Vector2(0.0, -20.0),
			Color(1.3, 1.3, 1.25, 0.95), Color(tint.r, tint.g, tint.b, 0.0),
			24, 0.4, 80.0, 240.0, 0.7, 2.0, 0.0, 0.0, true)
		bfx("burst", {"pos": dest + Vector2(0.0, -20.0),
			"col": Color(1.3, 1.3, 1.25, 0.95),
			"col2": Color(tint.r, tint.g, tint.b, 0.0), "n": 24, "life": 0.4,
			"v0": 80.0, "v1": 240.0, "s0": 0.7, "s1": 2.0})
	Juice.shake_camera(5.0)
	bfx("beat", {"pos": dest, "str": 0.9, "shake": 5.0, "sfx": "charge_up"})
