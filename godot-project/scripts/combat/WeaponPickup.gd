extends Area2D
## Ground weapon pickup — the hero walks over it to equip. Swaps the rig's
## weapon slot and the melee tuning via Hero.equip_weapon ("gear = visual
## + ability"). Placeholder _draw icon until real drop sprites exist.
##
## ══ WHAT THE WEAPON IS FOR ════════════════════════════════════════════════════
## Melee is the FLOOR under your damage — the thing that means a caster whose three
## buttons are on cooldown is a fighter and not a spectator. It must never be the
## CEILING. Bare fists are a fine floor (14 damage on a 0.34 s swing, ~41 dps) and
## they are free and permanent, which is exactly right for a floor.
##
## The sword was ALSO free and permanent, at 26 damage — ~76 dps, more than most
## classes' entire three-spell kit did to a single target. The fun audit's
## prediction followed: on floors 1-4 the optimal play for a caster is "grab the
## sword, hold melee, use spells as garnish", in a game whose pitch is absurd magic.
##
## Two things were wrong, and this file owns one of them. (The other — kits that
## lost to bare fists — is a damage pass in `SpellLibrary`, pinned by
## `tools/slice_test_melee_economy.gd`.)
##
## ⚠ THE COST CAME OUT AND NOTHING REPLACED IT. `mp_cost` used to gate a cast, so
## throwing spells spent something and swinging did not; that was melee's whole
## opportunity cost. The mana gate was removed (`Hero.gd` — "Mana no longer gates a
## cast") and `mp_cost` survives only as a sigil-sizing input and a `SpellTier`
## derivation input. Melee kept its zero cost and lost the thing it was traded
## against.
##
## So the cost comes back as TIME. A weapon you pick up off the floor is a WAR
## PRIZE, not a build: it is loud, it is a real power spike, and it is going to
## break. That makes picking it up a decision about WHEN — grab it now, or clear
## this wave and carry it into the guardian? — instead of a decision about whether
## to keep casting at all. Fists never expire, so the FLOOR is untouched; only the
## ceiling is on a clock.

## How long a picked-up weapon lasts, in seconds of play. Roughly a third of a floor
## at the measured pace, so one sword covers a wave and a bit, or a whole guardian.
## UNTESTED FEEL GUESS — nobody has played this. **Set it to a negative number for
## the old permanent behaviour**; that is the one-line revert if the clock feels bad.
const CARRY_TIME: float = 22.0

@export var weapon_kind: String = "sword"
## Per-instance override of CARRY_TIME (0 = use the constant, < 0 = never expires).
@export var carry_time: float = 0.0

var _consumed: bool = false
var _phase: float = 0.0
## Who took it, what they were carrying before, and how long they have left. The
## node stays alive after the pickup precisely to own this clock.
var _holder: Node = null
var _restore_kind: String = "fists"
var _left: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _holder != null:
		_tick_carry(delta)
		return
	# Gentle glow pulse so the pickup reads as interactable on the floor.
	_phase += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _consumed:
		return
	if not body.is_in_group("hero") or not body.has_method("equip_weapon"):
		return
	_consumed = true
	# What they had BEFORE. Two classes are configured WITH a weapon as class
	# identity (`Hero.configure_class` -> equip_weapon), so a blanket revert to
	# fists would quietly disarm a class that is supposed to be armed. A ground
	# weapon expiring puts you back where you were, not back to zero.
	var had: Variant = body.get("_weapon")
	_restore_kind = String(had) if typeof(had) == TYPE_STRING and String(had) != "" else "fists"
	body.equip_weapon(weapon_kind)
	Sfx.play("cast", -6.0, 0.1)
	var span: float = carry_time if carry_time != 0.0 else CARRY_TIME
	if span < 0.0:
		queue_free()      # permanent: there is no clock to own
		return
	_holder = body
	_left = span
	# Stop being a pickup: no collision, no icon, just the clock.
	monitoring = false
	visible = false


## The carry clock. Runs on this node rather than on a SceneTree timer so it pauses
## with the game, dies with the arena, and can watch for the holder swapping the
## weapon out from under it.
func _tick_carry(delta: float) -> void:
	if not is_instance_valid(_holder):
		queue_free()
		return
	# Somebody else's weapon is on them now (a second pickup, a live class switch).
	# This clock is no longer about anything — let go rather than yanking their new
	# one out of their hands when it runs out.
	if String(_holder.get("_weapon")) != weapon_kind:
		queue_free()
		return
	_left -= delta
	if _left <= 0.0:
		_break_weapon()


func _break_weapon() -> void:
	if is_instance_valid(_holder) and _holder.has_method("equip_weapon"):
		_holder.equip_weapon(_restore_kind)
		# The break has to be SEEN — a weapon that silently stops existing reads as
		# your damage mysteriously halving. The rig already swapped its overlay off
		# on the equip above; this is the flash that draws the eye to it.
		var rig: Variant = _holder.get("rig")
		if rig != null and is_instance_valid(rig) and rig.has_method("flash_color"):
			rig.flash_color(Color(1.3, 1.2, 1.0), 0.14)
	Sfx.play("crate_break", -4.0, 0.12, 1.25)
	queue_free()


## Seconds of carry left; 0 when nobody is carrying it. Public for tests and for a
## future HUD readout — a carried weapon with a clock on it deserves a pip.
func carry_remaining() -> float:
	return maxf(_left, 0.0) if _holder != null else 0.0


func _draw() -> void:
	var glow_alpha: float = 0.14 + 0.08 * sin(_phase * 3.0)
	draw_circle(Vector2.ZERO, 12.0, Color(1.0, 0.9, 0.4, glow_alpha))
	match weapon_kind:
		"sword":
			var blade_col := Color(0.85, 0.9, 1.0, 1.0)
			var hilt_col := Color(0.8, 0.6, 0.3, 1.0)
			draw_line(Vector2(-4, 6), Vector2(7, -7), blade_col, 2.5)  # blade
			draw_line(Vector2(-6, 1), Vector2(-1, 6), hilt_col, 2.0)  # crossguard
			draw_line(Vector2(-4, 6), Vector2(-7, 9), hilt_col, 2.5)  # grip
		_:
			draw_circle(Vector2.ZERO, 4.0, Color(0.9, 0.9, 0.9, 1.0))
