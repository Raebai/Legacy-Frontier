# Headless suite for the CAST -> SPELL magic-circle HAND-OFF seam.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_circle_handoff.gd
#
# WHAT THIS CAN AND CANNOT PROVE. The bug it guards is visual — "one cast, two
# circles in sequence" — and no assertion can tell you whether the sigil LOOKED
# continuous. What these tests do pin down is everything underneath that: that
# exactly ONE circle exists per cast, that it is the SAME INSTANCE the caster
# opened, that it lands in world space rather than at the arena origin, that it
# travels rather than teleports, and — the part most likely to rot — that every
# no-caster and interruption path still cleans up instead of orphaning a sigil.
# The visual verdict comes from tools/handoff_capture.gd.
#
# TWO LOCAL CONVENTIONS, both there to keep a headless run honest:
#  * BeamSpell is load()ed at RUNTIME, never preload()ed. A preload compiles
#    before the autoloads exist, and BeamSpell references the Sfx singleton — so
#    a preload fails to compile and every beam case silently turns into a no-op.
#  * The glide is stepped by hand (set_process(false) + _process_handoff(dt))
#    rather than by awaiting engine frames. Headless deltas are unthrottled and
#    wildly uneven, so a frame-counting travel assertion passes or fails on
#    machine speed, which is worse than no test at all.
extends SceneTree

const CIRCLE := preload("res://scripts/combat/MagicCircle.gd")
const BEAM_PATH: String = "res://scripts/combat/BeamSpell.gd"
const DT: float = 1.0 / 60.0

var _fails: int = 0
var _stage: Node2D = null
var _beam_script: GDScript = null
var _started: bool = false


## Started from the FIRST FRAME, not from _initialize(). Nodes added to `root`
## during _initialize() are not yet is_inside_tree(), and adopt_or_open refuses
## to reparent into a host that is out of the tree — so every adoption would
## silently degrade to a fresh circle and the whole suite would test nothing.
## (Same _process(delta) -> bool entry the other slice suites use.)
func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_beam_script = load(BEAM_PATH) as GDScript
	_run()
	return false


func _run() -> void:
	_t_fresh_when_no_offer()
	_t_adopts_same_instance()
	_t_travels_to_world_pos()
	_t_origin_parked_host_trap()
	_t_anonymous_single_offer()
	_t_anonymous_declines_when_ambiguous()
	_t_mismatched_caster_declines()
	await _t_ttl_reaps_unclaimed_offer()
	_t_withdraw_cleans_up()
	_t_offer_refuses_dying_circle()
	_t_face_to_edge_folds_without_flip()
	_t_edge_to_face_opens_then_flips()
	_t_same_mode_interpolates_rotation()
	_t_freed_circle_never_adopted()
	_t_beam_adopts()
	_t_beam_opens_its_own()
	_t_beam_reaction_consume_dismisses_adopted()
	_t_beam_dies_without_orphaning()
	_teardown()
	if _fails == 0:
		print("slice6_test_circle_handoff: all PASS")
	else:
		printerr("slice6_test_circle_handoff: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- the cases

## No windup to adopt (enemy / boss / reaction-spawned spectacles) — the seam
## must be invisible: a circle is constructed and appear()ed exactly as before.
func _t_fresh_when_no_offer() -> void:
	_setup()
	var host: Node2D = _host()
	var c: MagicCircle = CIRCLE.adopt_or_open(host, _caster(), Vector2(300, 120),
		Color.RED, 90.0, 0.3, true, Vector2.RIGHT, 0.14)
	_ok(c != null, "no-offer: a circle is still returned")
	_ok(c.get_parent() == host, "no-offer: parented to the host")
	_ok(c.global_position.is_equal_approx(Vector2(300, 120)), "no-offer: at the world pos")
	_ok(c._edge_on, "no-offer: honours the requested orientation")
	_ok(_live() == 1, "no-offer: exactly one circle")


## THE BUG, inverted: the sigil the spectacle uses must be the very instance the
## caster opened — not a second one built alongside it.
func _t_adopts_same_instance() -> void:
	_setup()
	var host: Node2D = _host()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -90))
	CIRCLE.offer(windup, caster)
	var c: MagicCircle = CIRCLE.adopt_or_open(host, caster, Vector2(140, 0),
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14)
	_ok(c == windup, "adopt: same instance handed over")
	_ok(c.get_parent() == host, "adopt: reparented under the spectacle")
	_ok(not c._vanishing, "adopt: never replays a vanish")
	_ok(is_equal_approx(c._alpha, 1.0), "adopt: at full presence, not re-growing from 0")
	_ok(_live() == 1, "adopt: exactly ONE circle alive for the cast")


## The travel is a feature (it connects the ritual to the shot), so it must not
## be a teleport — and it must ARRIVE.
func _t_travels_to_world_pos() -> void:
	_setup()
	var host: Node2D = _host()
	var caster: Node2D = _caster()
	var from: Vector2 = Vector2(0, -90)
	var to: Vector2 = Vector2(160, 10)
	var windup: MagicCircle = _open_windup(caster, from)
	windup.scale = Vector2(1.25, 1.25)   # the caster grows the node as it charges
	CIRCLE.offer(windup, caster)
	var c: MagicCircle = CIRCLE.adopt_or_open(host, caster, to,
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14, 0.2)
	_ok(c.global_position.is_equal_approx(from), "travel: starts where the windup left it")
	_step(c, 3)
	var mid: Vector2 = c.global_position
	_ok(not mid.is_equal_approx(to), "travel: not teleported to the muzzle")
	_ok(mid.distance_to(from) > 0.5, "travel: actually moving off the windup spot")
	_step(c, 30)
	_ok(c.global_position.distance_to(to) < 1.0, "travel: arrives at the muzzle")
	_ok(c.scale.is_equal_approx(Vector2.ONE), "travel: caster's node scale eased back to 1")
	_ok(is_equal_approx(c.radius, 80.0), "travel: morphed to the spell's radius")
	_ok(not c._ho_active, "travel: the glide finishes and lets go")


## THE COORDINATE TRAP. Spectacles park at the arena origin and draw in world
## coordinates, so a host at (0,0) is exactly the case where a naive reparent
## strands the sigil at the top-left of the arena.
func _t_origin_parked_host_trap() -> void:
	_setup()
	var host: Node2D = _host()
	host.global_position = Vector2.ZERO          # parked, like every spectacle
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(-420, -300))
	CIRCLE.offer(windup, caster)
	var c: MagicCircle = CIRCLE.adopt_or_open(host, caster, Vector2(512, 288),
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14, 0.12)
	_ok(c.global_position.is_equal_approx(Vector2(-420, -300)),
		"trap: reparent kept the global transform (no jump to the arena origin)")
	_step(c, 20)
	_ok(c.global_position.distance_to(Vector2(512, 288)) < 1.0,
		"trap: lands on the WORLD muzzle, not the host's local origin")


## Channelled casts reach SpellCaster with no caster reference, so the beam's
## caster_node is null. One pending offer is unambiguous — adopt it.
func _t_anonymous_single_offer() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -80))
	CIRCLE.offer(windup, caster)
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), null, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14)
	_ok(c == windup, "anon: a single pending offer is adopted")
	_ok(_live() == 1, "anon: still one circle")


## Two heroes releasing on the same frame: guessing would STEAL the other
## player's sigil, so an anonymous take declines and both offers survive.
func _t_anonymous_declines_when_ambiguous() -> void:
	_setup()
	var a: Node2D = _caster()
	var b: Node2D = _caster()
	var wa: MagicCircle = _open_windup(a, Vector2(0, -80))
	var wb: MagicCircle = _open_windup(b, Vector2(200, -80))
	CIRCLE.offer(wa, a)
	CIRCLE.offer(wb, b)
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), null, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14)
	_ok(c != wa and c != wb, "anon-ambiguous: declined, fresh circle built")
	_ok(CIRCLE.adopt_or_open(_host(), a, Vector2.ZERO, Color.BLUE, 80.0) == wa,
		"anon-ambiguous: caster A's offer survived intact")
	_ok(CIRCLE.adopt_or_open(_host(), b, Vector2.ZERO, Color.BLUE, 80.0) == wb,
		"anon-ambiguous: caster B's offer survived intact")


func _t_mismatched_caster_declines() -> void:
	_setup()
	var rightful: Node2D = _caster()
	var other: Node2D = _caster()
	var windup: MagicCircle = _open_windup(rightful, Vector2(0, -80))
	CIRCLE.offer(windup, rightful)
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), other, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14)
	_ok(c != windup, "mismatch: another caster cannot claim the offer")
	_ok(CIRCLE.adopt_or_open(_host(), rightful, Vector2.ZERO, Color.BLUE, 80.0) == windup,
		"mismatch: the rightful owner can still claim it")


## INTERRUPTION SAFETY NET. Most spells open no sigil of their own, so their
## offers are MEANT to go unclaimed — and a cast shattered mid-windup leaves one
## too. Neither may strand a sigil in the world. Real frames here on purpose:
## the TTL is wall-clock, so this is the one case a hand-stepped delta cannot
## exercise.
func _t_ttl_reaps_unclaimed_offer() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -80))
	CIRCLE.offer(windup, caster)
	var deadline: int = Time.get_ticks_msec() + CIRCLE.OFFER_TTL_MS + 250
	while Time.get_ticks_msec() < deadline:
		await process_frame
	_ok(not is_instance_valid(windup) or windup._vanishing,
		"ttl: an unclaimed offer blooms itself out")
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), caster, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14)
	_ok(not is_instance_valid(windup) or c != windup,
		"ttl: the reaped offer is no longer claimable")


## The explicit interruption path — a hit shatters the windup, the caster dies,
## a co-op down. Must dismiss immediately and be safe to call unconditionally.
func _t_withdraw_cleans_up() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -80))
	CIRCLE.offer(windup, caster)
	CIRCLE.withdraw(caster)
	_ok(windup._vanishing, "withdraw: the sigil is blooming out")
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), caster, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14)
	_ok(c != windup, "withdraw: nothing left to adopt, fresh circle built")
	CIRCLE.withdraw(caster)                       # must not explode
	CIRCLE.withdraw(null)                         # nor on a dead caster
	_ok(true, "withdraw: safe to call twice, and with null")


func _t_offer_refuses_dying_circle() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -80))
	windup.vanish(0.2)
	CIRCLE.offer(windup, caster)
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), caster, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14)
	_ok(c != windup, "dying: a vanishing sigil is never handed over")


## Sky spells open a FACE-ON disc; a beam wants an EDGE-ON gate. A hard switch
## between the two draw routines would read as a SECOND glitch, so the disc must
## become a full-round edge-on gate immediately and FOLD closed over the travel.
func _t_face_to_edge_folds_without_flip() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -80))
	windup.set_orientation(false)                      # face-on sky sigil
	CIRCLE.offer(windup, caster)
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), caster, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, true, Vector2.UP, 0.14, 0.15)
	_ok(c._edge_on, "fold: switches to the edge-on draw at once")
	_ok(is_equal_approx(c._edge_thick, 1.0), "fold: starts fully ROUND (same silhouette)")
	_ok(is_equal_approx(c.rotation, Vector2.UP.angle()),
		"fold: rotation snapped while round — invisible, never the long way round")
	_step(c, 3)
	_ok(c._edge_thick < 1.0 and c._edge_thick > 0.14, "fold: closing gradually, not snapping")
	_step(c, 20)
	_ok(absf(c._edge_thick - 0.14) < 0.01, "fold: closed to the beam's gate thickness")


## The mirror case a sky spectacle will hit once it adopts: an aimed edge-on
## windup handed to a face-on portal must OPEN to round first and only flip the
## draw at the end, where the two are indistinguishable.
func _t_edge_to_face_opens_then_flips() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -80))
	windup.set_orientation(true, Vector2.RIGHT, 0.2)
	CIRCLE.offer(windup, caster)
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), caster, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, false, Vector2.RIGHT, 0.15, 0.15)
	_ok(c._edge_on, "open: still edge-on while it widens")
	_step(c, 5)
	_ok(c._edge_on and c._edge_thick > 0.2, "open: widening toward round before any flip")
	_step(c, 20)
	_ok(not c._edge_on, "open: flips to the face-on disc only at the end")
	_ok(is_zero_approx(c.rotation), "open: face-on discs carry no rotation")


## Aimed windup -> aimed beam is the common case: same mode, slightly different
## angle. That must INTERPOLATE, never snap.
func _t_same_mode_interpolates_rotation() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -80))
	windup.set_orientation(true, Vector2.RIGHT, 0.22)
	CIRCLE.offer(windup, caster)
	var aim: Vector2 = Vector2.DOWN                     # a quarter turn away
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), caster, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, true, aim, 0.14, 0.25)
	_step(c, 3)
	var mid: float = c.rotation
	_ok(absf(angle_difference(mid, Vector2.RIGHT.angle())) > 0.001,
		"rotate: has begun turning off the windup angle")
	_ok(absf(angle_difference(mid, aim.angle())) > 0.001,
		"rotate: has NOT snapped straight to the beam angle")
	_step(c, 30)
	_ok(absf(angle_difference(c.rotation, aim.angle())) < 0.01,
		"rotate: settles on the beam's axis")


## A caster who dies on the release frame frees its sigil. The registry must not
## hand a corpse to the spectacle — nor let one count toward "exactly one".
func _t_freed_circle_never_adopted() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -80))
	CIRCLE.offer(windup, caster)
	windup.free()
	var c: MagicCircle = CIRCLE.adopt_or_open(_host(), caster, Vector2(60, 0),
		Color.BLUE, 80.0, 0.3, true, Vector2.RIGHT, 0.14)
	_ok(c != null and is_instance_valid(c), "freed: a fresh circle is built instead")
	var caster2: Node2D = _caster()
	var w2: MagicCircle = _open_windup(caster2, Vector2(0, -80))
	CIRCLE.offer(w2, caster2)
	_ok(CIRCLE.adopt_or_open(_host(), null, Vector2.ZERO, Color.BLUE, 80.0) == w2,
		"freed: swept from the registry, so a lone real offer stays unambiguous")


# ---------------------------------------------------------- BeamSpell wiring

func _t_beam_adopts() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -100))
	CIRCLE.offer(windup, caster)
	var beam: Node2D = _fire_beam(caster, Vector2(40, 0), Vector2.RIGHT)
	_ok(beam.get("_circle") == windup, "beam: adopts the caster's windup sigil")
	_ok(windup.get_parent() == beam, "beam: the sigil now rides the beam node")
	_ok(windup._edge_on, "beam: adopted sigil is the edge-on gate the bolt bursts through")
	_ok(_live() == 1, "beam: ONE sigil for the cast, not two")


## Enemies, bosses and the reaction system spawn beams with no windup at all.
func _t_beam_opens_its_own() -> void:
	_setup()
	var beam: Node2D = _fire_beam(null, Vector2(40, 0), Vector2.RIGHT)
	var c: Variant = beam.get("_circle")
	_ok(c != null and is_instance_valid(c), "no-caster beam: opens its own sigil")
	_ok((c as Node).get_parent() == beam, "no-caster beam: parented to the beam")
	_ok((c as Node2D).global_position.is_equal_approx(Vector2(40, 0)),
		"no-caster beam: sigil at the world muzzle, not the arena origin")
	_ok(_live() == 1, "no-caster beam: exactly one sigil")


## A beam eaten by a spell reaction must still dismiss its sigil — adopted or not.
func _t_beam_reaction_consume_dismisses_adopted() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -100))
	CIRCLE.offer(windup, caster)
	var beam: Node2D = _fire_beam(caster, Vector2(40, 0), Vector2.RIGHT)
	beam.call("reaction_consume")
	_ok(windup._vanishing, "consume: the adopted sigil is dismissed, never orphaned")


## The whole point of the seam is that nothing is left floating. A beam freed
## mid-flight takes its adopted sigil with it, because the sigil is its child.
func _t_beam_dies_without_orphaning() -> void:
	_setup()
	var caster: Node2D = _caster()
	var windup: MagicCircle = _open_windup(caster, Vector2(0, -100))
	CIRCLE.offer(windup, caster)
	var beam: Node2D = _fire_beam(caster, Vector2(40, 0), Vector2.RIGHT)
	beam.free()
	_ok(not is_instance_valid(windup), "die: the adopted sigil goes with the beam")
	_ok(_live() == 0, "die: nothing left floating in the arena")


# ------------------------------------------------------------------ helpers

## A clean arena per case. Freed IMMEDIATELY (not queue_free) between tests, so
## the "exactly one circle" counts can never be polluted by the previous case's
## deferred teardown — which is a real hazard here, since the whole suite is
## about counting circles.
func _setup() -> void:
	_teardown()
	_stage = Node2D.new()
	root.add_child(_stage)


func _teardown() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.free()
	_stage = null


## A spectacle stand-in, parked at the arena origin — where every real spell
## spectacle sits, because they all draw in world coordinates.
func _host() -> Node2D:
	var n: Node2D = Node2D.new()
	_stage.add_child(n)
	return n


func _caster() -> Node2D:
	var n: Node2D = Node2D.new()
	_stage.add_child(n)
	return n


## What a caster's windup does today: a sigil parented to the ARENA (a sibling of
## the spectacle, never a child of the caster) at a world position over its head.
func _open_windup(caster: Node2D, offset: Vector2) -> MagicCircle:
	var c: MagicCircle = CIRCLE.new()
	_stage.add_child(c)
	c.global_position = caster.global_position + offset
	c.appear(Color.VIOLET, 60.0, 0.2)
	c._alpha = 1.0        # the windup has finished; release is the hand-off moment
	c._growing = false
	return c


func _fire_beam(caster: Node, origin: Vector2, dir: Vector2) -> Node2D:
	var beam: Node2D = _beam_script.new()
	_stage.add_child(beam)
	beam.set("caster_node", caster)
	beam.fire(origin, dir, Color.MAGENTA, 400.0, 26.0, 10, "arcane")
	return beam


## Drive the glide by hand. Engine frames are useless for this headless: with no
## vsync the deltas are unthrottled and uneven, so a frame-counted travel test
## would pass or fail on machine speed.
func _step(c: MagicCircle, frames: int) -> void:
	c.set_process(false)
	for _i: int in frames:
		if c._ho_active:
			c._process_handoff(DT)


## Live, non-vanishing circles on the stage — the count the bug is about.
func _live(n: Node = null) -> int:
	var node: Node = n if n != null else _stage
	var total: int = 0
	if node is MagicCircle and not (node as MagicCircle)._vanishing:
		total += 1
	for c: Node in node.get_children():
		total += _live(c)
	return total


func _ok(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		printerr("  FAIL: ", label)
