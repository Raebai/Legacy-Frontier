extends BossModRider
## ENRAGED — "faster phases."
##
## Two things, and the spec's wording covers both: the boss REACHES its phases
## earlier, and it ACTS faster once it is in them.
##
##   gates   66% / 33%  ->  80% / 50%
##   cadence attack cooldowns tick at 1.5x
##
## ── WHY THIS IS NOT "MORE HP" IN DISGUISE ────────────────────────────────────
## It is strictly less total fight. The boss's health pool is untouched, and every
## phase gate moves EARLIER, so an enraged boss spends less of its life in its
## opening phase and more of it in the one where it is genuinely dangerous. The
## fight gets shorter and worse, which is the direction the spec keeps pointing:
## "HP scaling makes fights longer, not harder, and long is the enemy of chaos on
## a phone."
##
## ── THE ONE SUBTLETY ─────────────────────────────────────────────────────────
## `Boss.take_damage` runs its own 66/33 checks after every hit, but they are
## written as "if I am in P1 and I have fallen past 66%". By the time those run we
## have already pushed the boss into P2 at 80%, so the condition is false and there
## is no double transition. The gates do not need disabling — they need beating,
## and this beats them.

## Extra cooldown drain per second, on top of the boss's own 1.0. 0.5 -> 1.5x.
## Deliberately not larger: past about 1.6x the Illuminator's long committed casts
## start overlapping their own recovery windows, and the punish window IS the fight.
const EXTRA_COOLDOWN_RATE: float = 0.5
const GATE_P2: float = 0.80
const GATE_P3: float = 0.50

## How much hotter the aura runs. Enraged has to be visible from the first frame or
## the player never learns what the word on the HUD means.
const AURA_BOOST: float = 0.28


func _setup() -> void:
	_redress()
	if boss.has_signal("phase_changed") and not boss.is_connected("phase_changed", _on_phase):
		boss.connect("phase_changed", _on_phase)


func _on_phase(_p: int) -> void:
	_redress()


func _redress() -> void:
	var r: Node = rig()
	if r == null:
		return
	var t: Color = BossModifier.tint_for(BossModifier.ENRAGED)
	r.call("set_aura", t, 0.55 + AURA_BOOST)
	r.call("set_aura_tier", 4)


func _tick(delta: float) -> void:
	var ph: int = boss_phase()
	if ph < 1 or ph > 3:
		return
	# Mirrors `Boss._physics_process`, which drains the cooldown in every fight
	# phase whether or not the boss is busy — a busy boss simply banks the drain and
	# swings the instant it is free.
	boss.set("_attack_cd", float(boss.get("_attack_cd")) - delta * EXTRA_COOLDOWN_RATE)
	var f: float = hp_fraction()
	if ph == 1 and f <= GATE_P2:
		boss.call("_enter_phase", 2)
	elif ph == 2 and f <= GATE_P3:
		boss.call("_enter_phase", 3)
