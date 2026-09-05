extends BossModRider
## SPLIT — "dies into two copies."
##
## ── THE POOL IS CARVED, NOT ADDED. READ THIS BEFORE TUNING ANYTHING BELOW. ────
## The obvious implementation is "kill the boss, then spawn two more bosses", and
## it is wrong, because it is an HP buff wearing a costume. The spec is explicit
## and it is the rule this whole feature exists to obey: "higher floors add
## MODIFIERS, NOT HP. HP scaling makes fights longer, not harder, and long is the
## enemy of chaos on a phone." A previous pass already pinned trash HP at 1.0 on
## every floor for the same reason. Re-introducing the curve through a modifier
## would be the exact back door that warning is about.
##
## So the split is a REDISTRIBUTION of the health the boss already had:
##
##   parent   52%  of the rolled pool
##   copy A   24%
##   copy B   24%
##   ------------
##   total   100%
##
## The fight is the same LENGTH as an unmodified one. What changes is its SHAPE:
## one large committed duel becomes a duel and then a two-front scramble against
## smaller, faster bodies that can flank. That is a behavioural rewrite, which is
## what a modifier is supposed to be.
##
## ── WHY THE COPIES ARE QUIET ─────────────────────────────────────────────────
## They spawn with `quiet` set, which suppresses their boss bar and their intro
## card (see BossQuiet.gd). Two identical name cards and two identical full-width
## health bars stacked on each other is not drama, it is a rendering bug. Instead
## the top bar disappears with the parent and the copies carry the ordinary
## over-the-head enemy bars every other body in the room has — which is exactly the
## read we want: the boss stopped being A Boss and became two problems.
##
## The copies inherit every OTHER modifier the parent had, minus Split (so they
## cannot split again — that is the recursion guard, and it is a data filter rather
## than a depth counter) and minus Patient (a copy that stands there doing nothing
## after the drama of a split reads as a spawn failure).

## Fraction of the original pool the parent keeps, and each copy gets. Must sum to
## 1.0 across parent + both copies — see the block above.
const PARENT_FRACTION: float = 0.52
const COPY_FRACTION: float = 0.24
## Copies are physically smaller and quicker. The scale change is what sells that
## one body became two; the speed change is what stops them being a slower version
## of the same fight.
const COPY_BODY_SCALE: float = 0.66
const COPY_SPEED_MULT: float = 1.3
## How far apart the two halves are drawn, in px on x.
const SPREAD: float = 78.0

## Modifiers a copy never inherits.
const NOT_INHERITED: Array[String] = [BossModifier.SPLIT, BossModifier.PATIENT]

var _original_max_hp: int = 0
var _split_done: bool = false


func _setup() -> void:
	_original_max_hp = maxi(int(boss.get("max_hp")), 1)
	if not is_authority():
		# A client's puppet never runs the carve: its hp/max_hp are replicated from
		# the host, and halving them locally would desync the boss bar.
		return
	var carved: int = maxi(int(round(float(_original_max_hp) * PARENT_FRACTION)), 1)
	boss.set("max_hp", carved)
	boss.set("hp", mini(int(boss.get("hp")), carved))
	if boss.has_signal("defeated") and not boss.is_connected("defeated", _on_defeated):
		boss.connect("defeated", _on_defeated)


func _on_defeated() -> void:
	if _split_done or not is_authority():
		return
	_split_done = true
	var host: Node = arena()
	if host == null or not host.is_inside_tree():
		return
	var at: Vector2 = boss_pos()
	var phase: int = clampi(boss_phase(), 1, 3)
	# THE MOMENT. `Boss._die` already spends the climax mark (a cut-in) on the
	# parent's death, so this deliberately does NOT ask for a second full-screen
	# frame — the arbiter would refuse it anyway, and asking was the bug the last
	# time somebody stacked two. Shake and a sound carry the beat.
	Juice.epic_moment({"strength": 1.2, "shake": 16.0, "sfx": "charge_up"})
	# CO-OP. The two COPIES already replicate — `Arena.spawn_extra_enemy` puts them
	# through the MultiplayerSpawner, so both peers build them from this same
	# dictionary and neither needs telling. What was host-only is the BEAT that
	# explains them: without it a client watches a boss die and two new bodies appear
	# in silence.
	bfx("beat", {"pos": at, "str": 1.2, "shake": 16.0, "sfx": "charge_up"})
	# ⚠ ONE COPY PER FRAME. Maker: *"when i killed the boss on floor 4 i lagged a
	# ton"* — and floor 3 upward is exactly where SPLIT becomes eligible.
	#
	# Each copy is a FULL boss: a scene instantiation, a `CharacterRig` built in code,
	# a health bar, and a fresh rider per inherited modifier, each doing its own
	# `_setup`. Two of those on the same frame as the parent's own death spectacle —
	# the climax mark, the burst, the sound — is the single heaviest frame the game can
	# produce, and it lands at the exact moment the player is watching a kill.
	#
	# Deferring the second one costs nothing anybody can perceive (the two halves are
	# 78 px apart and appear a sixtieth of a second apart) and halves the spike. The
	# mechanic is untouched: still two copies, still the same carve, still the same
	# inheritance.
	_spawn_copy(at + Vector2(-SPREAD, -6.0), phase)
	_spawn_copy.call_deferred(at + Vector2(SPREAD, -6.0), phase)


func _spawn_copy(at: Vector2, phase: int) -> void:
	var data: Dictionary = _copy_data(modifier_ctx, _original_max_hp, at, phase)
	var host: Node = arena()
	# ⚠ THE HOST CAN BE GONE BY NOW, AND THIS USED TO DEREFERENCE IT BLIND.
	# The second copy is `call_deferred`, so this body runs a frame AFTER the parent
	# boss died -- which is exactly the frame a floor teardown or a run-end is also
	# using. `arena()` answers null once the boss is freed, and `host.has_method(...)`
	# on a null instance is a hard error. `_on_defeated` checks this; this did not.
	if host == null or not is_instance_valid(host):
		return
	var node: Node = null
	if host.has_method("spawn_extra_enemy"):
		# The replicated path: in co-op this goes through the MultiplayerSpawner, so
		# both peers build the copy from this identical dictionary.
		# LAUNDERED: `Arena.spawn_extra_enemy` is not our file, and a foreign return
		# value bound into a typed slot faults on a freed instance. See live_node.
		node = live_node(host.call("spawn_extra_enemy", data))
	else:
		node = _fallback_build(host, data)
	if node == null:
		return   # the floor's live-entity budget said no; one half is better than none


## PURE. The spawn dictionary for one copy, given the parent's original data.
## Static + free of tree access so a headless test can assert the carve arithmetic
## and the modifier inheritance without spawning anything.
static func copy_spawn_data(parent: Dictionary, original_max_hp: int, at: Vector2, phase: int) -> Dictionary:
	var d: Dictionary = parent.duplicate(true)
	d["boss"] = true
	d["hp"] = maxi(int(round(float(maxi(original_max_hp, 1)) * COPY_FRACTION)), 1)
	d["bscale"] = clampf(float(parent.get("bscale", 1.0)) * COPY_BODY_SCALE, 0.3, 1.0)
	d["spd"] = float(parent.get("spd", 66.0)) * COPY_SPEED_MULT
	d["x"] = at.x
	d["y"] = at.y
	var inherited: Array[String] = []
	for m in parent.get("mods", []):
		var mid: String = String(m)
		if not NOT_INHERITED.has(mid):
			inherited.append(mid)
	d["mods"] = inherited
	d["quiet"] = true          # no second boss bar, no second name card
	d["qphase"] = phase        # ...and no 2.6 s intro pause either
	return d


func _copy_data(parent: Dictionary, original_max_hp: int, at: Vector2, phase: int) -> Dictionary:
	var base: Dictionary = parent
	if base.is_empty():
		# No ctx (a hand-built boss, or a harness that skipped Encounter). Rebuild
		# enough of a spawn dict from the live boss that the copies are still right.
		base = {
			"boss": true,
			"bid": BossRoster.GUARDIAN,
			"hp": original_max_hp,
			"spd": float(boss.get("move_speed")),
			"touch": int(boss.get("touch_damage")),
			"bscale": float(boss.get("body_scale")),
			"mods": [],
		}
	return copy_spawn_data(base, original_max_hp, at, phase)


## Only reached outside an Arena (headless harnesses). Mirrors what
## Encounter.build_enemy_from_data does for a boss, including the modifier attach,
## so a test sees the same copy the game does.
func _fallback_build(host: Node, data: Dictionary) -> Node:
	var path: String = BossRoster.scene_path(String(data.get("bid", BossRoster.GUARDIAN)))
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	var e: Node = scene.instantiate()
	e.set("max_hp", int(data["hp"]))
	e.set("move_speed", float(data["spd"]))
	e.set("touch_damage", int(data["touch"]))
	e.set("body_scale", float(data.get("bscale", 1.0)))
	BossModifier.attach(e, data.get("mods", []), data)
	var quiet_gs: GDScript = load("res://scripts/combat/bossmods/BossQuiet.gd") as GDScript
	if quiet_gs != null:
		var q: Node = quiet_gs.new()
		q.set("target_phase", int(data.get("qphase", 1)))
		e.add_child(q)
	host.add_child(e)
	(e as Node2D).global_position = Vector2(float(data["x"]), float(data["y"]))
	return e
