extends BossModRider
## PATIENT — "does nothing until attacked."
##
## The boss is drawn but not yet WOKEN: it stands where the hand put it, does not
## approach, does not attack, and cannot hurt you by touch. It stays that way until
## something takes a point of health off it, and then the whole fight starts at
## once with the attack it has been banking the entire time.
##
## ── WHY THIS IS THE GENTLE ONE (min_floor 1) ─────────────────────────────────
## Every other modifier takes something away. This one GIVES: a free opening, a
## room you get to position in, a boss you get to look at before it looks back.
## That is why it is the only modifier a shallow floor can roll, and why it is
## worth having at all — a set of six escalations with no downward step in it reads
## as a difficulty slider rather than as variety.
##
## It is not free forever. `Boss._physics_process` ticks `_attack_cd` down every
## frame it is in a fight phase, whether or not it is allowed to act, so a boss you
## left dormant for eight seconds wakes with a deeply negative cooldown and attacks
## on the frame you hit it. The longer you stare, the harder the first exchange.
##
## ── HOW IT HOLDS THE BOSS STILL ──────────────────────────────────────────────
## `_busy` — the boss's own "I am mid-attack, do not move or choose" flag. Setting
## it every frame is exactly what an attack does, so there is no new state machine
## and no branch inside Boss.gd: approach goes to zero and `_choose_attack` is never
## reached. Touch damage is zeroed separately, because "does nothing" must include
## "does nothing when you walk into it".

## How far the body colour is washed toward the page while dormant. Not invisible —
## an invisible boss is a bug report, not a mechanic. It reads as UNINKED.
const DORMANT_WASH: float = 0.45
const DORMANT_PAGE: Color = Color(0.72, 0.70, 0.66)

var _dormant: bool = true
var _watch_hp: int = 0
var _saved_touch: int = 0
var _saved_tint: Color = Color.WHITE


func _setup() -> void:
	_watch_hp = int(boss.get("hp"))
	_saved_touch = int(boss.get("touch_damage"))
	boss.set("touch_damage", 0)
	var r: Node = rig()
	if r != null:
		_saved_tint = r.get("limb_color") as Color
	_wash()
	# The boss re-dresses its rig on every phase change, and the intro hands over to
	# P1 two and a half seconds after it spawns — so without this the wash would be
	# painted over while the thing is still asleep.
	if boss.has_signal("phase_changed") and not boss.is_connected("phase_changed", _on_phase):
		boss.connect("phase_changed", _on_phase)
	set_boss_busy(true)


func _on_phase(_p: int) -> void:
	if _dormant:
		_wash()


func _wash() -> void:
	var r: Node = rig()
	if r == null:
		return
	r.call("set_tint", _saved_tint.lerp(DORMANT_PAGE, DORMANT_WASH))
	r.call("set_aura", DORMANT_PAGE, 0.06)
	r.call("set_aura_tier", 0)


func _tick(_delta: float) -> void:
	if not _dormant:
		return
	# Re-asserted every frame rather than set once: an attack timer left over from
	# the boss's own `_unbusy_after` would otherwise clear the flag out from under
	# us and the "statue" would take a swing.
	set_boss_busy(true)
	if int(boss.get("hp")) < _watch_hp:
		_wake()


func _wake() -> void:
	_dormant = false
	boss.set("touch_damage", _saved_touch)
	set_boss_busy(false)
	var r: Node = rig()
	if r != null:
		r.call("set_tint", _saved_tint)
		r.call("flash_color", Color(1.6, 1.55, 1.4), 0.22)
	# THE WAKE IS AN EVENT. A boss that quietly starts moving reads as a bug; a boss
	# that detonates into motion reads as a mechanic. One mark, not two — the
	# arbiter would refuse a second full-screen frame anyway.
	Juice.epic_moment({
		"strength": 1.15, "shake": 13.0, "sfx": "charge_up",
		"frame": true, "at": boss_pos(), "style": ImpactFrame.Style.SILHOUETTE,
	})
	# NOT `_enter_phase(current)` — re-entering a phase re-fires its whole opening
	# beat, which on P2 means the boss summons a fresh set of adds for waking up.
	# Restoring the saved tint is the entire undo the wash needs.
