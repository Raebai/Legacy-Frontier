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

## ⚠ THE BURN WAS BOTH TOO MUCH DAMAGE AND TOO MANY EVENTS. Maker, watching duels:
## *"fire dot damage please reduce"* and *"reduce the sound sfx when taking dot
## damage"* — and those are one finding, because every tick routes through
## `_deal_self` -> `take_damage`, i.e. the real hurt path, so each one carried a hurt
## grunt, a flash, a hit-stop and a camera shake.
##
## 3 damage every 0.35 s for 2.6 s was SEVEN ticks and 21 damage — comparable to a
## whole class primary, delivered as seven separate jolts, for a status nobody
## consciously applied. Now 2 every 0.55 s: **five ticks and 10 damage**, so the
## damage halves and the noise more than halves with it. A DoT should be a pressure
## you notice, not a second attack that also makes the screen rattle.
##
## The tick SPACING is the half that fixes the sound. `Sfx`'s repeat governor only
## thins hits inside 190 ms, and a burn was landing just outside that window — close
## enough to smear, far enough to dodge the thinner.
const BURN_DURATION: float = 2.6
const BURN_TICK: float = 0.55
const BURN_TICK_DMG: int = 2
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


## ⚠ A CORPSE KEPT BURNING, AND NOTHING ANYWHERE CHECKED. Maker: *"all dot damage
## should go away on death"*.
##
## This `_process` ticked burn, dealt `_deal_self` damage, fired `_shatter()` when a
## freeze expired and `_pop_unstable()` when unstable ran out — all of it with no
## notion of whether the body it is attached to is still alive. So a dead fighter went
## on taking damage numbers, glow pulses and, through `SpellTargets.hurt`, KNOCKBACK.
##
## That last one is very likely the second half of the maker's *"in death they become
## all elongated"*: knockback on a corpse drives the rig's spring sim while it is in
## full ragdoll, which is exactly the state its limbs are loosest in.
##
## Duck-typed, because the two body types answer differently and neither should have
## to grow an interface for this: `Hero` publishes `is_downed()`, `Enemy` carries `hp`
## and simply stops existing. Anything that answers neither is assumed alive, which
## keeps every headless stub and test dummy behaving exactly as before.
func _owner_is_dead() -> bool:
	var o: Node = get_parent()
	if o == null or not is_instance_valid(o):
		return true
	# ⚠ BOTH, NOT EITHER-OR — AND THE FIRST VERSION OF THIS SHIPPED BROKEN BECAUSE IT
	# ASKED ONLY THE FIRST QUESTION. Maker, after that build: *"you also didnt remove
	# the dot damage on death"*.
	#
	# `is_downed()` is the GHOST state, and a bot-match fighter never enters it.
	# `BotMatch` explains why at its `stay_dead` line: `Hero._die` outside a run heals
	# straight back to full so the F6 feel toy never stops, so that mode keeps its
	# loser dead by other means and the body is not "downed" at all. Returning
	# `is_downed()` and stopping therefore answered "alive" for exactly the corpses
	# the maker was watching burn.
	if o.has_method("is_downed") and bool(o.call("is_downed")):
		return true
	var hp: Variant = o.get("hp")
	return hp != null and int(hp) <= 0


## Drop every ailment. Called the moment the owner dies so nothing is left to tick,
## and safe to call repeatedly.
func clear_all() -> void:
	_burn = 0.0
	_burn_tick = 0.0
	_chill = 0.0
	_freeze = 0.0
	_shock = 0.0
	_weaken = 0.0
	_unstable = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	# ⚠ BEFORE ANY TIMER MOVES. Clearing rather than merely returning matters: the
	# ailment TINT and `status_bits()` are read by the rig and the HUD, so a corpse
	# that kept its flags would still be drawn on fire while taking no damage.
	# ⚠ AND `_freeze` IS ZEROED THROUGH `clear_all` RATHER THAN ALLOWED TO EXPIRE, so
	# the `was_frozen` edge below cannot fire `_shatter()` on a body that is already
	# dead — a corpse exploding into ice shards seconds after it fell is the same
	# class of bug as the burn ticks, just louder.
	if _owner_is_dead():
		if is_active():
			clear_all()
		return
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


## Damage the owning enemy (burn tick / unstable pop). Guarded so a mid-tick
## death or a detached component never crashes.
## ⚠ TRUE ONLY WHILE A PERIODIC TICK IS LANDING. Maker: *"dot damage shouldnt have
## any screen shake in general"*.
##
## Every tick routes through the real hurt path — `take_damage` — which is correct
## (it is real damage, it can kill, it must flash and count) and is also why each one
## carried a full on-connect camera shake. A burn is five ticks, so a status nobody
## consciously applied rattled the screen five times. The header above already
## records the maker asking for the same thing about the SOUND, and the fix then was
## to space the ticks out; this removes the shake outright.
##
## A static flag rather than a `take_damage` parameter, deliberately: that method is
## a duck-typed contract with TWO live signatures already (Hero takes 1 arg, Enemy
## takes 2), calling the wrong arity THROWS and aborts the caller, and every test
## stub in the suite implements it. A third variant is a trap. This is safe as a
## flag precisely because the tick is SYNCHRONOUS — set, call, clear, with nothing
## awaited in between.
##
## ⚠ IT COVERS THE PERIODIC TICK ONLY. The shock chain and the Unstable pop are
## DISCRETE events — one bang each, consciously set up — and they keep their punch.
static var dealing_dot: bool = false


func _deal_self(amount: int) -> void:
	var owner_e: Node = get_parent()
	if owner_e != null and is_instance_valid(owner_e) and owner_e.has_method("take_damage"):
		# Pass the ailment hue so the DoT tick spawns a coloured damage number + a
		# glow-pulse in the ailment colour (the "glow w/ tick" read).
		# Adapter: Hero takes take_damage(int), Enemy takes (int, Color). The 2-arg
		# form on a hero THROWS and aborts the enclosing function, losing the hit and
		# everything after it. Latent until factions let these point at a hero.
		dealing_dot = true
		SpellTargets.hurt(owner_e, amount, Color(_last_color.r, _last_color.g, _last_color.b, 1.0))
		dealing_dot = false


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
		SpellTargets.hurt(best, SHOCK_CHAIN_DMG, Color(1.0, 0.95, 0.4, 1.0))
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


## ⚠ BURN / CHILL / FREEZE / SHOCK ARE NO LONGER DRAWN HERE. They are drawn by
## `CharacterRig._draw_status`, which has the solved pose and can put a stroke on an
## actual limb. See the long note there for why: this node sits at the BODY origin,
## which `_align_feet_to_body` puts 6.5 px below the middle of the figure, so a 14 px
## disc drawn here is a ring centred at mid-thigh that the figure stands inside — the
## maker's "that large circle thing", and not a size-tuning problem.
##
## WEAKEN and UNSTABLE are still drawn here, deliberately and temporarily: they have
## the same fault and the maker named neither, so they are left visibly inconsistent
## rather than redesigned on a guess. They are the next two to move.
## ⚠ THIS NODE NO LONGER DRAWS ANYTHING AT ALL. Every ailment overlay — burn, chill,
## freeze, shock, and now weaken and unstable — is drawn by `CharacterRig._draw_status`,
## which has the solved pose and can put a stroke on an actual limb.
##
## The last two moved for the same reason as the first four: this node sits at the BODY
## origin, which `_align_feet_to_body` puts 6.5 px BELOW the middle of the figure, so a
## ~14 px disc drawn here is a ring centred at mid-thigh that the figure stands inside.
## Leaving two of six visibly inconsistent was a deliberate pause, not a design.


# ---------------------------------------------------- what the rig needs to know
const B_BURN: int = 1
const B_CHILL: int = 2
const B_FREEZE: int = 4
const B_SHOCK: int = 8
const B_WEAKEN: int = 16
const B_UNSTABLE: int = 32


## Which ailments are live, as `CharacterRig.ST_*` bits. FREEZE outranks CHILL: they
## are two rungs of one fuse, and drawing both would say "cold" twice.
func status_bits() -> int:
	var b: int = 0
	if _burn > 0.0:
		b |= B_BURN
	if _freeze > 0.0:
		b |= B_FREEZE
	elif _chill > 0.0:
		b |= B_CHILL
	if _shock > 0.0:
		b |= B_SHOCK
	if _weaken > 0.0:
		b |= B_WEAKEN
	if _unstable > 0.0:
		b |= B_UNSTABLE
	return b


## The colour of whatever caused the current ailment, so a reused mechanic
## (EARTH->freeze, HOLY->burn, WIND->shock) still reads as its own element.
func tint() -> Color:
	return _last_color


## (`_draw_burn`, `_draw_chill`, `_draw_freeze` and `_draw_shock` lived here. They are
## DELETED rather than left unreferenced: an overlay nothing calls is dead code behind
## a live switch, and this project already ruled on that when it deleted the sparring
## station rather than leave it unbuilt. The drawings themselves moved to
## `CharacterRig._draw_status`, which knows where the limbs are.)


