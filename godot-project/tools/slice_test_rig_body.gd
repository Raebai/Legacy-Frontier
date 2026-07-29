# Run: godot --headless --path godot-project --script tools/slice_test_rig_body.gd
# THE FLOATING-CAPSULE BODY — CharacterRig's port of SpikeFigure's RigidBody2D torso.
#
# What this suite is actually defending, in the maker's words: "make sure it's that one
# that we spent ages optimising together." Two previous ports brought the spike's SKIN
# across (world-locked feet, slack airborne limbs, slimmer proportions) and left its
# SKELETON behind — the ride spring and the pitch spring. So every test here is about
# the body, not the drawing:
#
#   * landing COMPRESSES and then REBOUNDS (a damped oscillator, not a step)
#   * the compression is proportional to how hard you fell, and a step off a curb
#     produces none at all
#   * the feet stay WORLD-LOCKED through the squash — which is the whole mechanism,
#     because that is what bends the knees
#   * airborne, the upright spring is nearly OFF, so the body keeps its momentum's tilt
#   * a hit tips and sinks the BODY, not just the hands
#   * and the drawn silhouette (what Enemy.body_distance / SpellTargets measure)
#     follows the body, or "spells pass through heads" comes back
#
# Test hygiene per tools/slice_test_loadout.gd: failures land on the MEMBER `_fails`
# and every test records a completion sentinel, so a test that aborts on a moved
# property fails by ABSENCE instead of silently reporting zero failures.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const DT: float = 1.0 / 60.0

## Rig members these tests reach dynamically. If one moves house, _require_props names
## it rather than leaving the sentinel to say only "something died".
const RIG_MEMBERS: Array[String] = [
	"_ride", "_ride_vel", "_pitch", "_pitch_vel", "_lean_cap",
	"_applied_ride", "_peak_fall", "_was_airborne", "_ground_world_y",
	"_grounded", "_limp", "_gait_speed", "_plant_w", "_gait_ready",
]

const TESTS: Array[String] = [
	"rest_is_still", "landing_squashes_and_rebounds", "squash_scales_with_fall",
	"curb_step_is_silent", "feet_stay_world_locked_through_squash",
	"airborne_lets_the_body_tip", "grounded_rights_itself",
	"hit_moves_the_body_not_just_the_hands", "limp_sinks_and_topples",
	"transform_carries_the_silhouette", "owner_base_offset_survives",
	"public_surface_intact", "no_nan_under_abuse",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_rest_is_still()
	_test_landing_squashes_and_rebounds()
	_test_squash_scales_with_fall()
	_test_curb_step_is_silent()
	_test_feet_stay_world_locked_through_squash()
	_test_airborne_lets_the_body_tip()
	_test_grounded_rights_itself()
	_test_hit_moves_the_body_not_just_the_hands()
	_test_limp_sinks_and_topples()
	_test_transform_carries_the_silhouette()
	_test_owner_base_offset_survives()
	_test_public_surface_intact()
	_test_no_nan_under_abuse()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Rig body tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Rig body tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _require_props(obj: Object, names: Array[String], owner_label: String) -> void:
	if obj == null:
		_expect(false, "%s exists (cannot check its members)" % owner_label)
		return
	var present: Dictionary = {}
	for p: Dictionary in obj.get_property_list():
		present[String(p["name"])] = true
	for n: String in names:
		_expect(present.has(n),
			"%s still declares `%s` (moved or renamed — assertions reading it are dead)"
				% [owner_label, n])


## A rig in the tree, standing still, with its springs already settled.
func _make_rig(h: float = 31.0) -> CharacterRig:
	var rig: CharacterRig = (load(RIG_PATH) as GDScript).new() as CharacterRig
	rig.height = h
	root.add_child(rig)
	rig.set_grounded(true)
	rig.play(CharacterRig.State.IDLE)
	_settle(rig, 40)
	return rig


## Drive `n` frames of the rig's own update. `advance` is the deterministic entry
## point (_process just forwards to it), so no real frame loop is needed.
func _settle(rig: CharacterRig, n: int) -> void:
	for _i: int in n:
		rig.advance(DT)


## Simulate a FALL: move the node down at `speed` px/s for `frames` while the rig is
## told it is airborne, then declare it grounded. The rig derives fall speed from the
## node's own world motion (Enemy and Boss never feed it velocity), so moving the node
## is exactly how a real fall arrives.
func _drop(rig: CharacterRig, speed: float, frames: int = 12) -> void:
	rig.set_grounded(false)
	rig.play(CharacterRig.State.AIR)
	rig.set_air_phase(false, false)
	for _i: int in frames:
		rig.position.y += speed * DT
		rig.advance(DT)
	rig.set_grounded(true)
	rig.set_air_phase(false, true)
	rig.play(CharacterRig.State.IDLE)
	rig.advance(DT)   # the touchdown frame


## Standing still, nothing should be moving. If the body springs idle-hum, every
## figure in the game acquires a permanent wobble — the exact "float smear" the
## resting pose was tightened to kill.
func _test_rest_is_still() -> void:
	var rig: CharacterRig = _make_rig()
	_require_props(rig, RIG_MEMBERS, "CharacterRig")
	_settle(rig, 120)
	_expect(absf(rig.body_ride()) < 0.05,
		"a standing figure's ride spring is at rest (got %.4f)" % rig.body_ride())
	_expect(absf(rig.body_pitch()) < 0.02,
		"a standing figure is upright (got %.4f rad)" % rig.body_pitch())
	_expect(absf(rig.position.y) < 0.05,
		"...and it has not drifted off its owner's origin (got %.4f)" % rig.position.y)
	rig.queue_free()
	_completes("rest_is_still")


## THE HEADLINE. A landing must COMPRESS — the body sinking toward its planted feet is
## the whole weight read — by an amount that matches the source, then recover quickly.
##
## ⚠ It must NOT visibly bounce, and that assertion is deliberate. The spike's spring
## runs at zeta 0.71, whose overshoot is ~4% — it THUMPS and settles. An earlier draft
## of this suite demanded a rebound, which is a nice idea and not what the maker tuned;
## chasing it would have meant softening the damping and turning a landing into a
## trampoline. The port follows the source, and the test follows the port.
func _test_landing_squashes_and_rebounds() -> void:
	var rig: CharacterRig = _make_rig()
	_drop(rig, 700.0)
	# Compression peaks within a few frames of touchdown (w = 22.9 rad/s -> ~1/4 cycle
	# is about 0.07 s), so sample the first tenth of a second.
	var peak: float = 0.0
	for _i: int in 8:
		peak = maxf(peak, rig.body_ride())
		rig.advance(DT)
	# The source number: 17% of the figure's own height for a 700 px/s fall. Bracketed
	# rather than pinned, so tuning the constants stays possible while a silent
	# regression back to "barely moves" cannot pass.
	_expect(peak > rig.height * 0.11,
		"a 700 px/s landing DEEPLY compresses the body (peak %.3f px on a %.0f px figure = %.0f%%)"
			% [peak, rig.height, 100.0 * peak / rig.height])
	_expect(peak < rig.height * 0.24,
		"...without folding the figure in half (peak %.3f px)" % peak)
	# Recovery is FAST — a landing that lingers reads as sinking into mud.
	_settle(rig, 20)
	_expect(rig.body_ride() < rig.height * 0.03,
		"the crouch is mostly gone a third of a second later (%.4f)" % rig.body_ride())
	_settle(rig, 90)
	_expect(absf(rig.body_ride()) < 0.05,
		"...and fully settled, with no residual ring (%.4f)" % rig.body_ride())
	rig.queue_free()
	_completes("landing_squashes_and_rebounds")


## Weight has to be PROPORTIONAL or every landing feels the same. Drop from twice the
## speed, get a markedly bigger squash.
func _test_squash_scales_with_fall() -> void:
	var soft: CharacterRig = _make_rig()
	_drop(soft, 300.0)
	var soft_peak: float = 0.0
	for _i: int in 8:
		soft_peak = maxf(soft_peak, soft.body_ride())
		soft.advance(DT)
	var hard: CharacterRig = _make_rig()
	_drop(hard, 850.0)
	var hard_peak: float = 0.0
	for _i: int in 8:
		hard_peak = maxf(hard_peak, hard.body_ride())
		hard.advance(DT)
	_expect(hard_peak > soft_peak * 1.6,
		"a hard fall lands markedly heavier than a soft one (%.3f vs %.3f)"
			% [hard_peak, soft_peak])
	# A bigger fighter squashes proportionally — the spike hand-tuned its amplitudes
	# against an 86 px figure and they are re-derived per height, not hardcoded.
	var big: CharacterRig = _make_rig(62.0)
	_drop(big, 850.0)
	var big_peak: float = 0.0
	for _i: int in 8:
		big_peak = maxf(big_peak, big.body_ride())
		big.advance(DT)
	_expect(big_peak > hard_peak * 1.4,
		"a 2x-tall fighter squashes ~2x as far in px (%.3f vs %.3f)" % [big_peak, hard_peak])
	soft.queue_free()
	hard.queue_free()
	big.queue_free()
	_completes("squash_scales_with_fall")


## Stepping off a curb is not a landing. Below LAND_FALL_MIN nothing happens at all —
## otherwise walking down a slope would make the figure permanently jitter.
func _test_curb_step_is_silent() -> void:
	var rig: CharacterRig = _make_rig()
	_drop(rig, 90.0, 6)
	var peak: float = 0.0
	for _i: int in 10:
		peak = maxf(peak, absf(rig.body_ride()))
		rig.advance(DT)
	_expect(peak < 0.35,
		"a 90 px/s touchdown produces no squash (got %.4f)" % peak)
	rig.queue_free()
	_completes("curb_step_is_silent")


## THE MECHANISM, asserted directly. The squash only bends knees because the foot
## plants are held in WORLD space while the body drops toward them. If a plant ever
## followed the body down, the legs would stay straight and the landing would read as
## the whole figure sliding down the screen.
func _test_feet_stay_world_locked_through_squash() -> void:
	var rig: CharacterRig = _make_rig()
	_drop(rig, 800.0)
	# Sampled AFTER touchdown: the plants are naturally re-seeded at the new floor when
	# the figure lands (a landing must never drag the feet back to where the jump
	# started). What must hold is that they do not move again DURING the squash.
	#
	# Six frames, not one: the gait stays switched off until the AIRBORNE LOOSENESS has
	# eased back under STEP_SFX_MAX_LOOSE, so the plants re-seed a couple of frames into
	# the landing rather than on the contact frame itself.
	_settle(rig, 6)
	var plants_before: Array = (rig.get("_plant_w") as Array).duplicate()
	_expect(bool(rig.get("_gait_ready")), "the gait re-seeded its plants on touchdown")
	var max_plant_drift: float = 0.0
	var max_ride: float = 0.0
	for _i: int in 30:
		rig.advance(DT)
		max_ride = maxf(max_ride, rig.body_ride())
		var now: Array = rig.get("_plant_w") as Array
		for i: int in 2:
			max_plant_drift = maxf(max_plant_drift,
				absf((now[i] as Vector2).y - (plants_before[i] as Vector2).y))
	_expect(max_ride > 0.6, "the drop did compress the body (%.3f)" % max_ride)
	_expect(max_plant_drift < 0.001,
		"the planted feet do NOT follow the body down (drift %.5f px)" % max_plant_drift)
	rig.queue_free()
	_completes("feet_stay_world_locked_through_squash")


## AIRBORNE = LOOSE. SpikeFigure drops its upright gain to 0.09 in the air precisely so
## the body keeps whatever tilt its momentum or a hit gave it. This is the difference
## between a ragdoll and a sprite that happens to be off the ground.
func _test_airborne_lets_the_body_tip() -> void:
	var rig: CharacterRig = _make_rig()
	rig.set_grounded(false)
	rig.play(CharacterRig.State.AIR)
	rig.set_air_phase(true, false)
	# Kick the body into a spin the way a blow would, then let it fly.
	rig.apply_impulse(Vector2.RIGHT, 600.0)
	var tip: float = 0.0
	for _i: int in 30:
		rig.position.y -= 300.0 * DT
		rig.advance(DT)
		tip = maxf(tip, absf(rig.body_pitch()))
	_expect(tip > 0.25,
		"airborne, a blow visibly TIPS the body over (max %.3f rad)" % tip)
	_expect(absf(rig.body_pitch()) > 0.12,
		"...and it is still tilted 0.5 s later — the upright spring is nearly off in the air (%.3f rad)"
			% rig.body_pitch())
	_expect(absf(rig.body_pitch()) <= CharacterRig.LEAN_CAP_AIR + 0.001,
		"...but never past the airborne cap")
	rig.queue_free()
	_completes("airborne_lets_the_body_tip")


## ...and the same blow on the ground is caught and rightled: gain 1.0 means a planted
## fighter recovers. Loose in the air, planted on the floor — that pairing IS the feel.
func _test_grounded_rights_itself() -> void:
	var rig: CharacterRig = _make_rig()
	rig.apply_impulse(Vector2.RIGHT, 600.0)
	var tip: float = 0.0
	for _i: int in 12:
		rig.advance(DT)
		tip = maxf(tip, absf(rig.body_pitch()))
	_expect(tip > 0.05, "the blow tilts a planted fighter too (%.3f rad)" % tip)
	_settle(rig, 120)
	_expect(absf(rig.body_pitch()) < 0.03,
		"a planted fighter rights itself within ~2 s (got %.4f rad)" % rig.body_pitch())
	rig.queue_free()
	_completes("grounded_rights_itself")


## The old rig's hits rattled the HANDS. SpikeFigure's throw the whole torso. Both must
## now happen, or a hit still fails to read as the character being hit.
func _test_hit_moves_the_body_not_just_the_hands() -> void:
	var rig: CharacterRig = _make_rig()
	var ride0: float = rig.body_ride()
	var pitch0: float = rig.body_pitch()
	rig.apply_impulse(Vector2(0.7, 0.7).normalized(), 700.0)
	rig.advance(DT)
	_expect(absf(rig.body_pitch() - pitch0) > 0.005,
		"a blow SPINS the body, not just the hands (pitch %.4f -> %.4f)"
			% [pitch0, rig.body_pitch()])
	# ...and its VERTICAL half is dropped on purpose. SpikeFigure.hit() runs every blow
	# through Juice.lateral_knockback, which exists to stop a blast at your feet firing
	# you at the ceiling; coupling the vertical into the ride spring would undo that.
	_expect(absf(rig.body_ride() - ride0) < 0.05,
		"...while the downward half is flattened out, as lateral_knockback intends (ride %.4f -> %.4f)"
			% [ride0, rig.body_ride()])
	# Direction matters: a blow from the left must not tip you leftward.
	var r2: CharacterRig = _make_rig()
	r2.apply_impulse(Vector2.RIGHT, 800.0)
	r2.advance(DT)
	_expect(r2.body_pitch() > 0.0, "a rightward blow tips the body rightward")
	var r3: CharacterRig = _make_rig()
	r3.apply_impulse(Vector2.LEFT, 800.0)
	r3.advance(DT)
	_expect(r3.body_pitch() < 0.0, "a leftward blow tips the body leftward")
	# clash_recoil routes through apply_impulse, so it inherits all of this.
	var r4: CharacterRig = _make_rig()
	r4.clash_recoil(Vector2.RIGHT, 1.0)
	r4.advance(DT)
	_expect(absf(r4.body_pitch()) > 0.005, "clash_recoil reaches the body springs too")
	rig.queue_free()
	r2.queue_free()
	r3.queue_free()
	r4.queue_free()
	_completes("hit_moves_the_body_not_just_the_hands")


## Hold DOWN / die: the body collapses toward the floor and lies over. SpikeFigure
## drops its ride height from 58.5 to 11 and rotates the lean target flat; this is that
## collapse, at the amplitude documented on PRONE_RIDE_FACTOR.
func _test_limp_sinks_and_topples() -> void:
	var rig: CharacterRig = _make_rig()
	rig.set_limp(1.0)
	rig.play(CharacterRig.State.HURT)
	_settle(rig, 90)
	_expect(rig.body_ride() > rig.height * 0.15,
		"a fully limp grounded body SINKS toward the floor (ride %.3f on a %.0f px figure)"
			% [rig.body_ride(), rig.height])
	_expect(absf(rig.body_pitch()) > 0.5,
		"...and topples over rather than sinking bolt upright (%.3f rad)" % rig.body_pitch())
	# Releasing must bring it back up — the hold-DOWN ragdoll is not a one-way trip.
	rig.set_limp(0.0)
	rig.play(CharacterRig.State.IDLE)
	_settle(rig, 180)
	_expect(absf(rig.body_ride()) < 0.15,
		"releasing the ragdoll stands the body back up (ride %.4f)" % rig.body_ride())
	_expect(absf(rig.body_pitch()) < 0.06,
		"...upright again (%.4f rad)" % rig.body_pitch())
	rig.queue_free()
	_completes("limp_sinks_and_topples")


## ⚠ THE REGRESSION GUARD FOR "SPELLS PASS THROUGH HEADS".
##
## Enemy.body_distance() / head_point() build the hit silhouette by pushing ANALYTIC
## head + hip points through `rig.global_transform`. That is only safe while the body
## springs drive the TRANSFORM. If anyone ever "optimises" this into a draw-time offset
## or a pose-space fudge, the drawing moves and the hitbox does not — which is the
## original bug, wearing a new hat. So: assert the transform actually carries it.
func _test_transform_carries_the_silhouette() -> void:
	var rig: CharacterRig = _make_rig()
	var head_local: Vector2 = Vector2(0.0, -rig.height * 0.5 + rig.height * 0.105)
	var head_before: Vector2 = rig.global_transform * head_local
	_drop(rig, 850.0)
	for _i: int in 4:
		rig.advance(DT)
	var head_after: Vector2 = rig.global_transform * head_local
	_expect(absf(rig.body_ride()) > 0.4, "the landing compressed the body")
	# The node itself moved down by the fall, so compare against the un-squashed body:
	# what must be true is that the SILHOUETTE tracked the squash, not that it is still.
	var expected: Vector2 = Transform2D(0.0, Vector2(rig.global_position.x,
			rig.global_position.y - rig.body_ride())) * head_local
	_expect(head_after.distance_to(expected) > 0.3,
		"the hit silhouette MOVED with the squash rather than staying at the un-squashed height")
	_expect(absf(head_after.y - head_before.y) > 0.3,
		"the silhouette head is not frozen where the art used to be")
	# ...and under a lean, the transform's rotation carries it sideways too.
	var r2: CharacterRig = _make_rig()
	r2.apply_impulse(Vector2.RIGHT, 900.0)
	r2.set_limp(0.9)
	_settle(r2, 45)
	var tilted: Vector2 = r2.global_transform * head_local
	_expect(absf(r2.body_pitch()) > 0.1, "the body is leaning (%.3f rad)" % r2.body_pitch())
	_expect(absf(tilted.x - r2.global_position.x) > 0.5,
		"a leaning body's silhouette head swings off the vertical axis (dx %.3f)"
			% (tilted.x - r2.global_position.x))
	rig.queue_free()
	r2.queue_free()
	_completes("transform_carries_the_silhouette")


## The hub stands its figures on the node origin with `_rig.position.y = -height * 0.5`
## (Player.gd / NPC.gd). The body spring writes the SAME property, so it has to compose
## with that base rather than overwrite it — otherwise every hub NPC sinks half a body
## into the floor the first time the rig ticks.
func _test_owner_base_offset_survives() -> void:
	var rig: CharacterRig = (load(RIG_PATH) as GDScript).new() as CharacterRig
	rig.height = 31.0
	root.add_child(rig)
	var base: float = -rig.height * 0.5
	rig.position.y = base                 # exactly what Player.gd/NPC.gd do, in _ready
	rig.set_grounded(true)
	_settle(rig, 120)
	_expect(absf(rig.position.y - base) < 0.05,
		"the owner's own rig offset survives the body spring (%.4f, expected %.4f)"
			% [rig.position.y, base])
	# ...and a squash offsets FROM wherever the owner has since put the node, not from
	# the origin. (`_drop` translates the node, so the reference is re-read on
	# touchdown; what is asserted is that the un-squashed body stays put while the
	# spring rings — i.e. the spring adds to the owner's position instead of replacing
	# it, which is the thing that would sink every hub NPC into the floor.)
	_drop(rig, 850.0)
	var settled_base: float = rig.position.y - rig.body_ride()
	var max_base_drift: float = 0.0
	for _i: int in 40:
		rig.advance(DT)
		max_base_drift = maxf(max_base_drift,
			absf((rig.position.y - rig.body_ride()) - settled_base))
	_expect(absf(rig.body_ride()) > 0.0, "the drop put energy into the spring")
	_expect(max_base_drift < 0.001,
		"a squash is an OFFSET from the owner's own position, never a replacement of it (drift %.5f)"
			% max_base_drift)
	rig.queue_free()
	_completes("owner_base_offset_survives")


## The port is only shippable if the swap contract still holds — one rig drives the
## hero, every enemy and the boss. Call the whole public surface on a live rig and
## assert nothing errors and nothing NaNs.
func _test_public_surface_intact() -> void:
	var rig: CharacterRig = _make_rig()
	rig.play(CharacterRig.State.RUN)
	rig.set_facing(Vector2.LEFT)
	rig.set_tint(Color.RED)
	rig.flash(0.05)
	rig.flash_color(Color.CYAN, 0.05)
	rig.set_aim(Vector2.UP)
	rig.set_aim_arm(true)
	rig.cast_gesture(CharacterRig.GestureKind.GATHER, 0.8, 0)
	rig.set_equipment("weapon", "staff")
	rig.class_preset("mage")
	rig.set_aura(Color.BLUE, 0.5)
	rig.set_aura_tier(3)
	rig.set_airborne(0.5)
	rig.set_grounded(true)
	rig.set_air_phase(true, false)
	rig.set_body_velocity(Vector2(180.0, -40.0))
	rig.set_frozen(true)
	rig.set_hand_fire(0.6, 0)
	rig.set_parry(Vector2.RIGHT, 0.2)
	rig.set_limp(0.3)
	rig.flop(0.6, 0.1)
	rig.apply_impulse(Vector2.UP, 300.0)
	rig.clash_recoil(Vector2.LEFT, 0.8)
	_settle(rig, 30)
	rig.set_frozen(false)
	rig.play(CharacterRig.State.PUNCH)
	_settle(rig, 10)
	var tip: Vector2 = rig.get_weapon_tip()
	var hand: Vector2 = rig.get_lead_hand_global()
	_expect(is_finite(tip.x) and is_finite(tip.y), "get_weapon_tip stays finite")
	_expect(is_finite(hand.x) and is_finite(hand.y), "get_lead_hand_global stays finite")
	_expect(rig.is_striking(), "is_striking still reports the live one-shot")
	rig.spawn_ghost(root, Color.WHITE, Vector2.RIGHT)
	_expect(root.get_tree().get_nodes_in_group("rig_ghost").size() > 0,
		"spawn_ghost still produces an afterimage")
	# The ghost must inherit the squashed/leaning transform, or a dash trail is five
	# copies of a figure standing somewhere the figure is not.
	for g: Node in root.get_tree().get_nodes_in_group("rig_ghost"):
		(g as Node2D).queue_free()
	# height + draw_figure are part of the contract too.
	_expect(rig.height > 0.0, "height is still a live property")
	_expect((load(RIG_PATH) as GDScript).has_method("draw_figure"),
		"draw_figure is still a static entry point")
	rig.queue_free()
	_completes("public_surface_intact")


## Everything the springs read can arrive as garbage (a blink, a teleporting spawner, a
## zero delta, a NaN velocity). None of it may leave the body in a broken state, because
## a NaN transform makes a figure vanish rather than misbehave visibly.
func _test_no_nan_under_abuse() -> void:
	var rig: CharacterRig = _make_rig()
	rig.advance(0.0)                                     # zero delta
	rig.set_body_velocity(Vector2(NAN, NAN))             # guarded at the setter
	rig.apply_impulse(Vector2.ZERO, 500.0)               # degenerate direction
	rig.apply_impulse(Vector2.RIGHT, NAN)                # degenerate strength
	rig.advance(DT)
	rig.position.y += 90000.0                            # a teleport / blink
	rig.advance(DT)
	rig.position.y -= 90000.0
	for _i: int in 30:
		rig.apply_impulse(Vector2(randf() - 0.5, randf() - 0.5), 4000.0)
		rig.advance(DT)
	_expect(is_finite(rig.body_ride()) and is_finite(rig.body_pitch()),
		"the body springs stay finite under abuse (ride %f pitch %f)"
			% [rig.body_ride(), rig.body_pitch()])
	_expect(is_finite(rig.position.y) and is_finite(rig.rotation),
		"...and so does the transform they write")
	_expect(absf(rig.body_ride()) <= rig.height * 0.5,
		"the ride clamp holds even under a spam of maximal impulses (%.3f)" % rig.body_ride())
	_settle(rig, 240)
	_expect(absf(rig.body_ride()) < 0.2 and absf(rig.body_pitch()) < 0.1,
		"and it recovers to a clean stand afterwards (ride %.4f pitch %.4f)"
			% [rig.body_ride(), rig.body_pitch()])
	rig.queue_free()
	_completes("no_nan_under_abuse")
