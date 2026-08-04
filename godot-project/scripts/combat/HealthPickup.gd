extends Area2D
## A HEALTH PACK LYING ON THE FLOOR. Walk over it and you get a slab of HP back.
##
## ══ WHY THIS EXISTS ════════════════════════════════════════════════════════════
## Maker: "the character needs more HP it needs to be clearere as the game is hard
## right now and there should be like health packs and stuff". Three separate asks,
## and this file owns the third. The tower had NO in-fight healing that was not a
## class kit (Cleric nova, Warlock lifesteal) — every other class arrived at the
## guardian carrying whatever was left of the pool it started the floor with, and a
## floor's difficulty was therefore "how well did you play the FIRST wave".
##
## A pack on the floor turns that into a decision with a shape: the HP is over
## there, the fight is over here, and crossing the room to get it costs you the
## seconds you spend not fighting. That is the same trade `WeaponPickup` makes with
## its carry clock, and it is deliberately the same trade — the tower's floor
## objects should all read as "a thing worth walking to".
##
## ══ THE HEAL IS A FRACTION, NOT A NUMBER ═══════════════════════════════════════
## `Hero.CLASS_CONFIG` spans 109 HP (Stormcaller) to 203 (Juggernaut), so a flat
## "+40" is a third of one class's bar and a fifth of another's. A fraction of
## `max_hp` means one pack is the same amount of RELIEF for everyone, which is what
## the pack is actually for. The floor under it (`HEAL_MIN`) exists so a body that
## somehow has a tiny pool still gets something worth crossing the room for.
##
## ══ CO-OP: ONE FINISH LINE (copied deliberately, not reinvented) ═══════════════
## ⚠ `WeaponPickup` shipped with a photo-finish bug — both peers ran their own
## overlap test, so a dead heat handed the sword to a DIFFERENT hero on each screen
## and the local `_consumed` latch made that disagreement permanent for the floor.
## `SpellPickup` had already solved it. This file follows the FIXED shape exactly:
##
##   * the peer that OWNS the colliding hero REPORTS the overlap (a puppet's overlap
##     is a stale echo of a position this peer never integrated — reporting it would
##     let lag decide the race);
##   * `_reported` latches so a body that keeps overlapping cannot spam the host;
##   * the host DECIDES once (`Net._host_award_pickup` keys on position and drops
##     every later request for the same key);
##   * the award comes back through `collect_by` on EVERY peer, which is why the
##     heal, the burst and the sound land on both screens rather than only on the
##     screen of whoever happened to see the overlap first.
##
## Singleplayer takes none of it: `Net.is_active()` is false and `_on_body_entered`
## calls `collect_by` directly, exactly like the other two families.
##
## ⚠ THE "SHOULD I EVEN TAKE THIS" TEST RUNS BEFORE THE REPORT, NOT AT THE AWARD.
## A full-health hero must not consume a pack (walking over your own lifeline at
## 100% and wasting it is the single most annoying thing a pickup can do), but that
## refusal cannot live in `collect_by`: the host latches the award the moment it is
## asked, so a peer that refuses AFTER the decision leaves a pack that is spent on
## the host's ledger and still standing on the floor — visible, and impossible to
## take. So the health test gates the REQUEST, and the award is unconditional.

## Fraction of `max_hp` restored. ~a third of a bar: enough to be worth crossing a
## room mid-wave, not enough to undo a bad floor.
## UNTESTED FEEL GUESS — nobody has played this. This is the first number to turn.
const HEAL_FRACTION: float = 0.34
## Floor on the heal, for any body with an unusually small pool.
const HEAL_MIN: int = 25

## Do not report an overlap unless at least this much of the bar is missing. Without
## it, brushing past a pack while nearly full burns it for a couple of points.
const MIN_MISSING_FRACTION: float = 0.12

## ⚠ THE GHOST GROUP AS A LITERAL, not `GhostForm.GHOST_GROUP`. Same reason
## `GhostForm` itself spells `mortal` out: naming that class here drags its compile
## graph into a node that a headless suite loads by path. `GhostForm.GHOST_GROUP` is
## the source of truth; `tools/slice_test_health_pickup.gd` asserts the two agree.
const GHOST_GROUP: StringName = &"ghost"

## The wire identity for the co-op pickup race — see `_on_body_entered` and
## `Net._client_pickup`, which scans this group by position key.
const PICKUP_GROUP: StringName = &"health_pickup"

## --- the look. Green cross, because NOTHING ELSE in this game draws a plus. ---
const BEACON_HEIGHT: float = 120.0
const DISC_RADIUS: float = 11.0
const HALO_RADIUS: float = 22.0
const BOB: float = 4.0
const HEAL_COLOR: Color = Color(0.36, 0.95, 0.52)

var _consumed: bool = false
## Latched once this peer has asked the host for the award, so a body that keeps
## overlapping (or re-enters while the request is in flight) cannot spam it.
var _reported: bool = false
var _phase: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group(PICKUP_GROUP)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _consumed or _reported:
		return
	if not _wants_healing(body):
		return
	var net: Node = get_node_or_null(^"/root/Net")
	if net == null or not net.has_method(&"is_active") or not bool(net.call(&"is_active")):
		collect_by(body)   # singleplayer: unchanged, no round trip
		return
	var owner_peer: int = body.get_multiplayer_authority()
	if owner_peer != int(net.call(&"my_id")):
		return   # a puppet's overlap is a stale echo — its own peer will report it
	_reported = true
	net.call(&"request_pickup", self, owner_peer)


## Is this body a live hero with room in its bar? The whole gate, in one place,
## because it has to be asked BEFORE the host is told (see the header).
##
## ⚠ A GHOST IS REFUSED HERE AND AGAIN AT THE AWARD. A downed hero's
## `collision_layer` is zeroed by `GhostForm.enter`, so in practice it can never
## trip this Area2D at all — but "cannot currently reach it" and "must never be
## healed by it" are different promises, and only the second one survives somebody
## later giving ghosts a collision layer back.
func _wants_healing(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not body.is_in_group(&"hero"):
		return false
	if _is_downed(body):
		return false
	var mx: int = HpWatch.max_hp_of(body)
	var cur: int = HpWatch.hp_of(body)
	if mx <= 0 or cur < 0:
		return false
	return float(mx - cur) >= float(mx) * MIN_MISSING_FRACTION


## Downed / ghosted, by either of the two answers a hero publishes. Both are read
## defensively: `get()` on an absent property returns a null Variant and casting
## that ABORTS the enclosing function — the bug that silently killed the spell
## handoff — so nothing here casts a value it has not type-checked.
func _is_downed(body: Node) -> bool:
	if body.is_in_group(GHOST_GROUP):
		return true
	if body.has_method(&"is_downed"):
		return bool(body.call(&"is_downed"))
	var v: Variant = body.get(&"downed")
	return v is bool and bool(v)


## PUBLIC so the networking layer can drive collection from ONE authoritative
## decision rather than from two independent overlap tests. Idempotent: a second
## call after the pack is spent does nothing and returns false, which is what
## `Net._client_pickup` counts.
##
## ⚠ THE ONLY REFUSAL LEFT HERE IS THE GHOST. Everything else was decided before
## the host was asked. A hero who went down in the gap between the report and the
## award arriving is the one lossy case: the host has already latched the key, so
## the pack is spent on its ledger and stays standing on the floor until the room
## rebuilds. Narrow enough to name rather than machine around — the same call
## `Net._client_pickup` makes about a winner who disconnected mid-award.
func collect_by(body: Node) -> bool:
	if _consumed:
		return false
	if body == null or not is_instance_valid(body):
		return false
	if _is_downed(body):
		return false   # ⚠ a pack must NEVER resurrect a ghost. Revive is a teammate's job.
	var mx: int = HpWatch.max_hp_of(body)
	if mx <= 0:
		return false
	_consumed = true
	# ⚠ THROUGH THE SHARED HELPER, never a bare `hp` write. `HpWatch.gain` prefers the
	# body's own `heal()` (which clamps to max_hp, emits `health_changed` so the bar
	# moves, and flashes the rig green) and falls back to a clamped write for anything
	# that has no heal. A direct `hp +=` here would skip the emit and the HUD would
	# keep showing the old value until the next damage tick.
	HpWatch.gain(body, maxi(HEAL_MIN, int(round(float(mx) * HEAL_FRACTION))))
	# CO-OP: this runs on every peer, so both screens see the burst and the green rig
	# flash. The puppet's own `hp` is replicated from its owner (`Hero` publishes `:hp`),
	# so the local heal is a one-frame prediction that the authority immediately
	# confirms — the same shape as `WeaponPickup` calling `equip_weapon` everywhere.
	CombatVfx.spawn_burst(get_parent(), global_position,
		Color(0.7, 1.4, 0.85, 1.0), Color(0.3, 0.9, 0.5, 0.0),
		20, 0.45, 50.0, 190.0, 1.1, 3.0, 0.0, 0.0, true)
	Sfx.play("ding", -4.0, 0.05, 0.85)
	queue_free()
	return true


# ══════════════════════════════════════════════════════════════════════ the look
## Three layers, for the same reason `SpellPickup` draws four: at 640x360 with the
## camera pulled back to frame the whole room, a small green dot on a green-ish
## floor is not findable mid-fight.
##   1. A BEACON — a soft column, the only element that survives being behind a
##      crate or off the busy part of the frame.
##   2. A HALO + PLATE — says "pickup", not "a spell effect somebody left running".
##   3. THE CROSS — the read. Nothing else in this game draws a plus, so the shape
##      alone answers "what is it" without a word of text.
## No name label, unlike `SpellPickup`: there is only ever one kind of pack, so the
## shape IS the label. (The maker's standing rule: fewer text pieces, clearer shapes.)
func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_phase * 3.0)
	var bob: Vector2 = Vector2(0.0, sin(_phase * 2.0) * BOB)
	_draw_beacon(pulse)
	_draw_plate(bob, pulse)
	_draw_cross(bob)


func _draw_beacon(pulse: float) -> void:
	var c: Color = HEAL_COLOR
	draw_line(Vector2.ZERO, Vector2(0.0, -BEACON_HEIGHT),
		Color(c.r, c.g, c.b, 0.05 + 0.04 * pulse), 22.0, true)
	draw_line(Vector2.ZERO, Vector2(0.0, -BEACON_HEIGHT * 0.62),
		Color(c.r, c.g, c.b, 0.14 + 0.10 * pulse), 8.0, true)
	# A ground ring, so the column has a footprint and does not read as hanging.
	draw_arc(Vector2.ZERO, HALO_RADIUS * (0.9 + 0.12 * pulse), 0.0, TAU, 28,
		Color(c.r, c.g, c.b, 0.42), 1.8, true)


func _draw_plate(bob: Vector2, pulse: float) -> void:
	var at: Vector2 = bob + Vector2(0.0, -HALO_RADIUS)
	draw_circle(at, HALO_RADIUS * (0.78 + 0.14 * pulse),
		Color(HEAL_COLOR.r, HEAL_COLOR.g, HEAL_COLOR.b, 0.16), true, -1.0, true)
	# A dark plate under the cross: the cross is drawn bright, and bright-on-bright
	# is exactly how a pickup disappears against a lit floor.
	draw_circle(at, DISC_RADIUS + 2.0, Color(0.05, 0.12, 0.08, 0.85), true, -1.0, true)
	draw_arc(at, DISC_RADIUS + 2.0, 0.0, TAU, 26,
		Color(0.8, 1.5, 1.0, 0.5 + 0.35 * pulse), 1.6, true)


func _draw_cross(bob: Vector2) -> void:
	var at: Vector2 = bob + Vector2(0.0, -HALO_RADIUS)
	var arm: float = DISC_RADIUS * 0.62
	var col := Color(0.85, 1.6, 1.05, 1.0)
	draw_line(at - Vector2(arm, 0.0), at + Vector2(arm, 0.0), col, 4.0, true)
	draw_line(at - Vector2(0.0, arm), at + Vector2(0.0, arm), col, 4.0, true)
