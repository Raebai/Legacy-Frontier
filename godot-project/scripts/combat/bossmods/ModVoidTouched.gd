extends BossModRider
## VOID-TOUCHED — "leaves damaging zones."
##
## The page is rotting under it. Every few seconds the floor where the boss is
## standing gives way into a lingering void field; every phase change tears one
## open under the PLAYER as well.
##
## ── WHAT IT ACTUALLY CHANGES ABOUT THE FIGHT ─────────────────────────────────
## Ground. Nothing else. Damage numbers stay where they were, the boss's own kit is
## untouched, its speed is untouched. What it takes away is the right to stand
## still and to keep fighting in the corner you like — the arena visibly shrinks as
## the fight goes on, so a duel that was about reading telegraphs becomes a duel
## about reading telegraphs while being evicted.
##
## That is also why it is honest against a slow boss and brutal against a fast one:
## the Cartographer paints itself into a box you can simply walk around, while the
## Scribble drags its rot straight through the room after you. Same modifier, two
## different problems, which is the whole point of composing modifiers with a fixed
## roster rather than generating bosses.
##
## ── THE CAP IS THE FAIRNESS ──────────────────────────────────────────────────
## MAX_ZONES exists because "the arena fills up" is a mechanic and "the arena is
## full" is a soft-lock. The oldest field is retired when a new one opens, so there
## is always a route.

## Seconds between fields, per phase (P1 / P2 / P3). Escalates the RATE, never the
## damage — the tick stays where it is for the whole fight.
const INTERVAL: Array[float] = [4.0, 3.1, 2.3]
const MAX_ZONES: int = 4
const RADIUS: float = 62.0
const TICK_DAMAGE: int = 5
const LIFETIME: float = 8.5
## A field opened on a phase change lands under the HERO instead of the boss, and
## is the one moment this modifier is allowed to be aggressive rather than ambient.
const PHASE_FIELD_RADIUS: float = 78.0

const ZONE_SCRIPT: String = "res://scripts/combat/ZoneSpell.gd"

var _timer: float = 2.2
var _zones: Array = []


func _setup() -> void:
	if boss.has_signal("phase_changed") and not boss.is_connected("phase_changed", _on_phase):
		boss.connect("phase_changed", _on_phase)


func _on_phase(_p: int) -> void:
	# Visual-safe: a client that mirrors the phase must not open its own field, or
	# the host's and the client's would both exist and the damage would double.
	if not is_authority():
		return
	var h: Node2D = nearest_hero()
	if h != null:
		_open_field(h.global_position, PHASE_FIELD_RADIUS)


func _tick(delta: float) -> void:
	var ph: int = boss_phase()
	if ph < 1 or ph > 3:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL[clampi(ph - 1, 0, INTERVAL.size() - 1)]
	_open_field(boss_pos(), RADIUS)


func _open_field(at: Vector2, radius: float) -> void:
	var host: Node = arena()
	if host == null or not host.is_inside_tree():
		return
	_prune()
	while _zones.size() >= MAX_ZONES:
		var oldest: Node = _zones.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var gs: GDScript = load(ZONE_SCRIPT) as GDScript
	if gs == null:
		return
	var z: Node = gs.new()
	# Stamped BEFORE open(): a field decides who it may touch as it opens, and an
	# un-owned one is inert in the whole reaction system (see BossModRider).
	stamp_hostile(z, Elements.Element.SHADOW, SpellTier.Tier.HEAVY)
	host.add_child(z)
	z.call("open", at, BossModifier.tint_for(BossModifier.VOID_TOUCHED),
		radius, TICK_DAMAGE, "shadow", LIFETIME)
	_zones.append(z)


func _prune() -> void:
	var kept: Array = []
	for z in _zones:
		if is_instance_valid(z):
			kept.append(z)
	_zones = kept
