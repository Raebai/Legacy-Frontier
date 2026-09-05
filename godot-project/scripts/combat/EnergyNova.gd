class_name EnergyNova
extends Node2D

## Who this nova's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## THE SHOVE — the punctuation mark of the ult set.
##
## IDENTITY (maker, mid-playtest: "most ults look the same — just are recolours
## or retypes of the same meteor type of thing"). Every other big spell in the kit
## is a SKY event that takes a second to arrive somewhere you marked. This one is
## the opposite on every axis that matters, and those contrasts ARE the design:
##   * DIRECTION  — outward from the caster's own feet, along the FLOOR. Not down
##                  from above, not inward from the edges.
##   * TIMING     — a single instant. No build at all. The whole event is over in
##                  ~0.26 s, where Heaven's Verdict spends 1.3 s just winding up.
##   * SCALE      — deliberately the SMALLEST footprint of the set (135 px vs
##                  160-300). It is a "get off me", not a room-wipe.
##   * SILHOUETTE — a flat ground-hugging ELLIPSE that scrapes outward, plus a
##                  hard vertical clap. Not a disc, not a column, not a sigil.
##   * SCREEN     — the only ult that does NOT touch the camera zoom. No pull, no
##                  punch, no impact frame. A short hard shake and a ripple, then
##                  nothing. Every big spell reaching for the same three juice
##                  calls is a large part of why they stopped feeling different.
##   * RESIDUE    — nearly none. A scrape that clears. Craters and scorch belong
##                  to the spells that fall out of the sky.
##
## ⚠ IT NOW HAS A TELEGRAPH. THE MAKER OVERRULED THE "NO WIND-UP" ARGUMENT, and the
## previous version of this paragraph — which defended the instant fire at length —
## is preserved below because the reasoning is still the counter-argument anyone
## reopening this should have to answer.
##
## The playtest note, verbatim: *"nova damages ourselves and has no way of blocking
## it as it has no charge up so we need to fix that as well."* Two defects in one
## sentence, and only the first is a bug in the ordinary sense (see the self-
## exclusion block on `_resolve_caster` below). The second is the design one: the
## spec's rule for big spells is that they are *"loud, committal, answerable... there
## is a play against it"*, and an instant self-centred 135 px burst is unanswerable
## by construction. Not hard to answer — IMPOSSIBLE to. Nobody in the room, including
## the caster, can act on information that arrives in the same frame as the damage.
##
## So the nova now GATHERS for `WINDUP_TIME` and then goes off, and the summoning
## sigil is the telegraph: it opens at EXACTLY the damage radius (see
## `_sigil_radius_scale`) and its glyph band fills over exactly the wind-up (see
## `MagicCircle.set_charge_time`), so the ring on the floor is a literal, honest
## statement of "this is the circle, and this is how long you have". That is the same
## grammar the Cartographer's sigil already uses, which is the one boss attack the
## spec singles out as fair.
##
## WHAT THAT COSTS, stated plainly rather than hidden: this is no longer a panic
## button that can be pressed *during* an incoming hit, and it can be walked out of —
## including by the caster, who is no longer anchored to their own blast. The
## deliberate compensations are that the wind-up is the SHORTEST in the kit by a
## factor of four (0.30 s against Heaven's Verdict's 1.3 s), and that the ring is
## still the smallest footprint of the set. It remains the fastest answer available;
## it is no longer a free one.
##
## THE ARGUMENT IT REPLACES, kept intact: "The house rule is 'every ability must be
## dodgeable, with a real telegraph and a window to move'. This one has neither,
## because it is the reactive panic button: a wind-up makes it useless for the job it
## exists to do... Its counterplay is SPACING — it has the smallest footprint in the
## kit by a wide margin." If a playtest says the shove has stopped doing its job,
## that is the paragraph to restore, and `WINDUP_TIME = 0.0` is the switch that
## restores it — every other beat below already handles a zero wind-up.

const NOVA_RADIUS: float = 135.0
## THE DRAWN RING NOW ENDS EXACTLY ON THE DAMAGE RADIUS. Pinned at 1.0, and the
## pin IS the bug fix.
##
## THE LIE THIS REPLACES: the ring used to be drawn to `NOVA_RADIUS * 0.62 * 1.3`
## — about 109 px — while `_apply_nova_damage()` queried the raw 135 px. So the
## nova damaged 1.24x WIDER than anything it ever drew, and a body standing in the
## visibly empty gap outside the ring still took 30 and got launched. That is the
## maker's "the spells shouldn't be able to get out the radius", in miniature.
##
## The old 0.62 came from a real complaint (the pre-shrink ring reached 175 px and
## read as half the screen at the combat camera's 1.6x zoom), which is exactly why
## the fix pulls the DRAWING out to the damage radius instead of inflating the
## damage out to the drawing: 135 is still comfortably tighter than the 175 that
## was complained about, and it is now honest.
##
## ⚠ Lower this again and you re-introduce the lie. The honest way to make the
## nova smaller on screen is to lower NOVA_RADIUS, which moves both together.
const VISUAL_RADIUS_FACTOR: float = 1.0
const NOVA_DAMAGE: int = 30
## ⚠ RETIRED — the shove is now derived from the spell's own damage and shelf via
## `SpellTier.push_for_spectacle`. Kept only as the record of what it used to be:
## every one of these sat BELOW `SlamPhysics.MIN_SLAM_SPEED` (250), so no spell in
## the game could throw a body hard enough to crack what it hit. Do not tune this
## number — nothing reads it. The band is in `SpellTier`.
const RETIRED_NOVA_KNOCKBACK: float = 275.0
const SHOCKWAVE_TIME: float = 0.26   # the whole event; shortest in the ult set
const CLEANUP_DELAY: float = 0.7
## Ground-plane squash for the shockwave ellipse. The arena is SIDE-VIEW, so a
## true circle reads as a bubble hanging in the air; squashing it makes the same
## ring read as a wave travelling across the FLOOR. Truer to the fiction, and the
## single cheapest change that stops this looking like every other radial burst in
## the game. UNTESTED GUESS.
const GROUND_SQUASH: float = 0.42
## Fraction of the event spent on the inward compression flash. A READ, not a
## dodge window (see the no-telegraph note above). UNTESTED GUESS.
const COMPRESS_FRAC: float = 0.22
## Faint floor scrape under the caster: the shove visibly stresses the arena.
## Snapped down onto the actual floor (never the sky) + fades so it clears up.
const CRACK_RADIUS_FACTOR: float = 0.35
const CRACK_TINT: Color = Color(0.3, 0.4, 0.5, 0.45)
const CRACK_LIFETIME: float = 5.0  # seconds before the scrape fades away
const DEBRIS_COUNT: int = 8
const DEBRIS_COLOR: Color = Color(0.45, 0.55, 0.62)  # cool shattered stone

## THE GATHER — the wind-up the maker asked for. See the telegraph block at the top.
##
## 0.30 s is chosen as the SHORTEST duration that is still a real window rather than
## a courtesy: at the hero's run speed it is a little over a body-width of travel, so
## someone standing at the rim of the 135 px ring can clear it and someone standing
## on the caster's toes cannot. That asymmetry is the point — the shove still wins
## the fight it exists to win (someone is already on top of you) and now loses the
## one it should never have won (someone was leaving anyway).
##
## Set to 0.0 to restore the old instant behaviour exactly: `activate_at` detonates
## in the same call, which is the path every headless test and capture tool that
## predates the wind-up still needs.
const WINDUP_TIME: float = 0.30
## Radius the safe-line ring is drawn at during the gather, as a fraction of the
## damage radius. PINNED AT 1.0 for the same reason `VISUAL_RADIUS_FACTOR` is: a
## telegraph that draws a smaller circle than it damages is not a telegraph, it is a
## trap with a decoration on it.
const TELEGRAPH_RADIUS_FACTOR: float = 1.0

var _shockwave_elapsed: float = -1.0  # < 0 means not yet fired.
## Gather progress, in seconds. < 0 means "not gathering" — either not started, or
## already detonated.
var _windup_elapsed: float = -1.0
## Where this nova will go off. Captured at `activate_at`; the blast does NOT follow
## the caster during the gather, so walking out of your own circle is a real option.
var _center: Vector2 = Vector2.ZERO
var _sigil: MagicCircle = null
## Element index (Elements.Element) applied as an ailment to enemies in radius.
var element_id: int = -1

## WHO CAST THIS. `SpellCaster._stamp` has always written this name onto every
## spectacle it builds, but this file never declared it — and `set()` on an
## undeclared property is a silent no-op, so the write went nowhere. That cost
## nothing while a hero's spells scanned `"enemy"` (the caster was never in that
## group) and became a SELF-KILL the moment friendly fire pointed them at the
## shared `"mortal"` group. Declaring it is what arms `SpellTargets.hostiles()` /
## `SpellTargets.owner_of()`, which is where the exclusion is now enforced.
var caster_node: Node = null
## The shelf this nova sits on. `SpellCaster._stamp` writes it onto every spectacle
## it builds, but `set()` on an undeclared property is a silent no-op — so until this
## line existed the write went nowhere and the summoning sigil could not tell a jab
## from a finisher.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT


## The colour the SUMMONING SIGIL draws in. The nova's own rings are a hardcoded
## pale blue and stay that way — that shockwave is the spell's identity and it is
## not an elemental recolour — but the sigil is the CASTER'S mark rather than the
## blast's, so it takes the element when there is one and falls back to the nova's
## own blue when the nova was cast by something that never declared an element.
func _sigil_color() -> Color:
	return Elements.color(element_id) if element_id >= 0 else Color(0.6, 0.9, 1.0)


## How much to scale the tier's default sigil radius by so the drawn ring lands
## exactly on `NOVA_RADIUS`. The nova's telegraph has to state a DISTANCE, not a
## weight class, so it is the one sigil in the game sized by its own geometry rather
## than by its shelf.
func _sigil_radius_scale() -> float:
	var base: float = SpellSigil.radius_for(SpellTier.weight_or_default(spell_tier))
	if base <= 0.01:
		return 1.0
	return NOVA_RADIUS * TELEGRAPH_RADIUS_FACTOR / base


## ══════════════════ WHY THE NOVA WAS KILLING ITS OWN CASTER ══════════════════
##
## The maker's note is *"nova damages ourselves"*, and the previous fix for it was
## real but landed one layer too high. Reconstructed:
##
##   1. `SpellTargets` enforces self-exclusion twice — `hostiles()` subtracts the
##      caster from the group, and `_pool()` implicitly skips `owner_of(ctx)`. Both
##      read `caster_node` off the spectacle. This file declares `caster_node` and
##      passes `[caster_node]` as the skip list, so on paper it is covered twice.
##   2. BOTH LAYERS ARE NO-OPS WHEN `caster_node` IS NULL. That is correct and
##      deliberate — an unowned effect (a capture tool, a reaction-spawned burst)
##      must not have a caster invented for it.
##   3. `SpellCaster._stamp` writes `caster_node` on every spectacle IT builds. But
##      the hero's nova does not go through `SpellCaster`. `Hero._spawn_nova` builds
##      it by hand and stamps only the FACTION (`Hero._stamp_faction` writes
##      `target_group` / `_target_group`, and nothing else).
##   4. So `caster_node` stayed null, the skip list was `[null]`, `owner_of` answered
##      null, and both exclusion layers politely did nothing.
##   5. Which cost nothing at all while the target group was `"enemy"` — the caster
##      is not in `"enemy"`. The moment friendly fire pointed it at the shared
##      `"mortal"` group, the caster was standing in the middle of a group the spell
##      was allowed to hurt, AT range zero, and ate its own 30 damage every cast.
##
## THE REAL FIX IS ONE LINE IN `Hero._spawn_nova` (`nova.set("caster_node", self)`,
## exactly as `Hero._blast` already does) and it is REPORTED rather than made here,
## because `Hero.gd` belongs to another pass. The same omission covers the other
## hand-built class spectacles in that file.
##
## THIS IS THE BACKSTOP, and it is written to be safe rather than clever. A nova is
## SELF-CENTRED: at the instant of casting, the caster is standing on the centre,
## within a couple of pixels. Nothing else in the game reliably is. So when nobody
## told us who cast this, the body sitting on the blast origin at cast time is
## adopted as the caster.
##
## ⚠ WHY IT RUNS AT CAST TIME AND NOT AT DETONATION. With a wind-up in place, by the
## time the blast goes off the caster may have walked off the centre (that is the
## whole point of the wind-up) and an ENEMY may have walked onto it. Resolving late
## would therefore adopt the wrong body and grant an enemy immunity — the exact
## inverse of the bug. Resolving at cast time is unambiguous.
##
## ⚠ AND WHY THE RADIUS IS TINY. At 6 px this can only ever mistake a body that is
## essentially co-located with the caster for the caster. In the worst case — two
## team-mates perfectly stacked — one team-mate is spared one nova. Compare that with
## the failure it replaces, which is the caster killing themselves on every cast.
## Wrong in the cheap direction, on purpose.
const SELF_INFER_RADIUS: float = 6.0

func _resolve_caster() -> void:
	if caster_node != null and is_instance_valid(caster_node):
		return
	if not is_inside_tree():
		return
	var best: Node = null
	var best_d: float = SELF_INFER_RADIUS
	for n: Node in get_tree().get_nodes_in_group(target_group):
		if n is not Node2D:
			continue
		var d: float = (n as Node2D).global_position.distance_to(_center)
		if d <= best_d:
			best_d = d
			best = n
	caster_node = best


## Public entry: place the nova and START THE GATHER. It detonates `WINDUP_TIME`
## later — or immediately, if the wind-up is zero.
##
## ⚠ THE CASTER IS RESOLVED HERE, AT CAST TIME, and that timing is load-bearing —
## see `_resolve_caster`. Do not move it into `_detonate`.
func activate_at(pos: Vector2) -> void:
	global_position = pos
	_center = pos
	_resolve_caster()
	# A GROUND sigil, because a nova is a placed spell — it happens where the caster
	# is standing, not somewhere they are pointing. Laid flat so it reads as the
	# floor answering, which is the same visual grammar the walls and wards use and
	# the opposite of the edge-on gates the projected spells fire through.
	#
	# ⚠ Unlike almost every other spectacle in this codebase, this node is NOT parked
	# at the arena origin — `global_position` really is the nova's centre — so world
	# space and this node's own position happen to coincide here. Do not copy this
	# line into a spectacle that draws in world coordinates.
	#
	# THE RADIUS IS THE MESSAGE. Scaled so the drawn ring lands on the damage radius
	# rather than on the tier's default size, because during the gather this circle
	# is the only information anyone in the room has about how far to walk.
	_sigil = SpellSigil.open(
		self, pos, _sigil_color(), _sigil_radius_scale(),
		false, Vector2.RIGHT, true, 0.14, 0.0
	)
	if _sigil != null:
		# ...and the FILL is the clock. `set_charge_time` must come after `open`,
		# which resets it (see that function's warning).
		_sigil.set_charge_time(maxf(WINDUP_TIME, 0.01))
	if WINDUP_TIME <= 0.0:
		_detonate()
		return
	_windup_elapsed = 0.0
	Sfx.play("cast", 0.7, -0.25)   # the gather is audible too, not only visible
	queue_redraw()


## Fire NOW, cancelling any remaining gather. Idempotent — a second call is a no-op,
## so a spectacle that is force-fired and then reaches the end of its own wind-up
## cannot detonate twice.
##
## Public because the headless suites and capture tools need the old instant
## behaviour without having to simulate 0.3 s of frames, and because a future
## interrupt/counterspell wants exactly this shape.
func detonate_now() -> void:
	if _windup_elapsed < 0.0 and _shockwave_elapsed >= 0.0:
		return
	_detonate()


func _detonate() -> void:
	_windup_elapsed = -1.0
	if _sigil != null and is_instance_valid(_sigil):
		# The release flare on the sigil IS the moment of firing — the ritual ends
		# and the spell starts on the same frame, which is the whole grammar the
		# charge/snap pair exists for.
		_sigil.snap(1.0)
		SpellSigil.close(_sigil, 0.18)
		_sigil = null
	_apply_nova_damage()
	_spawn_nova_burst()
	# Scrape the FLOOR beneath the caster only — NEVER the sky (the maker's ask).
	# Airborne over a pit -> no scrape, no debris; just the energy ring rings out.
	# `SpellWorld.floor_below` is the house helper for this (it replaces a private
	# `_floor_below` that eight spectacles each had their own copy of).
	var hit: Dictionary = SpellWorld.floor_below(global_position, NOVA_RADIUS, [], self)
	if bool(hit["hit"]):
		var floor_pos: Vector2 = hit["position"]
		ScorchDecal.spawn(
			get_parent(), floor_pos,
			NOVA_RADIUS * CRACK_RADIUS_FACTOR, "crack", CRACK_TINT, CRACK_LIFETIME
		)
		# ⚠ THIS BLOCK USED TO EXPLAIN, AT LENGTH, WHY THE NOVA COULD NOT CARVE. The
		# argument was sound and its premise is gone. It ran: `NOVA_DAMAGE` is 30,
		# `CARVE_MIN_DAMAGE` was 40, so the call would only ever tick `refused_hits`
		# while looking like the floor was being eaten — a comment pretending to be an
		# implementation. The maker's correction retired that shelf (*"for all things
		# where it was hit"*), so the nova now carves like everything else, and the
		# other half of the old note — that a hint could only ever WIDEN a crater the
		# damage had already earned — is retired with it: the footprint SETS the size.
		#
		# `NOVA_RADIUS` (135) is the footprint, and a 30-damage shove sits near the
		# bottom of the damage band, so the ring opens a ~32 px crater: plainly wider
		# than a beam's 13 and plainly narrower than a meteor's 41. That is the shape of
		# the spell — a wide, shallow shove — rendered in missing rock.
		#
		# `Vector2.UP` is the hit direction, not the normal: `_spawn_carve_spectacle`
		# throws its debris back along `-dir`, so UP sends the stone down and out, which
		# is where a ground-hugging shockwave puts it.
		DestructibleStage.carve_from_body(hit.get("collider"), NOVA_DAMAGE,
			floor_pos, Vector2.UP, NOVA_RADIUS, self)
		#
		# Dust kicked SIDEWAYS along the floor rather than up: the read is a shove,
		# not an explosion.
		DebrisChunk.spawn_burst(
			get_parent(), floor_pos, DEBRIS_COLOR, DEBRIS_COUNT, Vector2.LEFT, 200.0
		)
		DebrisChunk.spawn_burst(
			get_parent(), floor_pos, DEBRIS_COLOR, DEBRIS_COUNT, Vector2.RIGHT, 200.0
		)
	_shockwave_elapsed = 0.0
	queue_redraw()
	# THE SCREEN GRAMMAR THAT IS DELIBERATELY *NOT* SHARED WITH THE SKY ULTS: no
	# zoom_punch, no zoom_pull, and — still — no white blow-out. Those three were
	# fired by every big spell in the kit, so they stopped reading as "this one is
	# big" and started reading as "a spell happened". A short freeze, a hard shake
	# and a ripple is this spell's vocabulary.
	Juice.hit_stop(0.08)
	Juice.shake_camera(14.0)
	PostProcess.shock(0.6)  # the shove rings the screen outward
	# ...and ONE mark, chosen precisely because no other spell in the kit uses it.
	# The nova is a SHOVE: everything is pushed away from you at once and nothing
	# is destroyed. `INVERT` is the only style in the vocabulary that keeps the
	# picture completely intact — same silhouettes, same positions, same
	# readability — while making it read as deeply wrong for two frames. That is
	# the shove, exactly: the world did not explode, it flinched. It is also the
	# shortest mark there is (0.07 s), so it cannot become the wash this spell
	# spent a rewrite escaping.
	Juice.frame({
		"style": ImpactFrame.Style.INVERT, "strength": 1.0, "at": global_position,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
	})
	Sfx.play("nova", 1.0, 0.08)
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)


## Radius-query damage + OUTWARD knockback. Split out so headless tests can
## exercise the geometry without driving the VFX/juice side effects.
##
## Selection goes through `SpellTargets` rather than a hand-rolled distance loop:
## it measures to the target's DRAWN silhouette (an `Enemy`'s head sits ~10 px
## above its node origin — 19 px on the 1.9x sparring dummies — so an origin-only
## test let bursts pass straight through heads), and it drops anything behind
## cover, which is what stops the burst reaching through the floor into the room
## below. Targets with no silhouette (crates, bolts, test stubs) fall back to the
## exact `global_position` point test this used before, so the 135 px boundary
## pinned by `slice1_test_nova` is unchanged.
func _apply_nova_damage() -> void:
	var here: Vector2 = global_position
	for enemy: Node in SpellTargets.in_radius(
			here, NOVA_RADIUS, get_tree().get_nodes_in_group(target_group),
			[caster_node], self):
		if enemy.has_method("take_damage"):
			enemy.take_damage(NOVA_DAMAGE)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - here).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			enemy.apply_knockback(away * SpellTier.push_for_spectacle(
				float(NOVA_DAMAGE), SpellTier.PUSH_TIER[SpellTier.Tier.HEAVY]))
	# Crates around the caster shatter too (no knockback — they're static).
	for prop: Node in SpellTargets.in_radius(
			here, NOVA_RADIUS, get_tree().get_nodes_in_group("destructible"), [], self):
		# Blow parts off outward from the nova centre (falls back to take_damage).
		if prop.has_method("damage_at"):
			var out: Vector2 = ((prop as Node2D).global_position - here).normalized()
			prop.damage_at(NOVA_DAMAGE, (prop as Node2D).global_position, out if out != Vector2.ZERO else Vector2.UP)
		elif prop.has_method("take_damage"):
			prop.take_damage(NOVA_DAMAGE)
	# Enemy bolts caught in the nova are cleared from the air (spell-vs-spell).
	# Deliberately NOT line-of-sight filtered: a bolt inside the burst is already
	# inside it, and a projectile is not a body that cover can sensibly hide.
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		if proj is Node2D and here.distance_to((proj as Node2D).global_position) <= NOVA_RADIUS \
				and proj.has_method("consume"):
			proj.call("consume")


func _process(delta: float) -> void:
	if _windup_elapsed >= 0.0:
		_windup_elapsed += delta
		queue_redraw()
		if _windup_elapsed >= WINDUP_TIME:
			_detonate()
		return
	if _shockwave_elapsed < 0.0:
		return
	_shockwave_elapsed += delta
	queue_redraw()


func _draw() -> void:
	if _windup_elapsed >= 0.0:
		_draw_windup()
		return
	if _shockwave_elapsed < 0.0:
		return
	var t: float = clampf(_shockwave_elapsed / SHOCKWAVE_TIME, 0.0, 1.0)
	if t >= 1.0:
		return
	# BEAT 1 — the compression: a hard bright ring snapping INWARD to the caster.
	# It is the read ("this came out of THAT body"). Drawn first so it never
	# fights the outward wave for the same pixels.
	if t < COMPRESS_FRAC:
		var ct: float = t / COMPRESS_FRAC
		var cr: float = lerpf(NOVA_RADIUS * 0.85, 6.0, ct * ct)
		_draw_ground_ring(cr, Color(1.5, 1.8, 2.0, 0.75 * (1.0 - ct)), lerpf(2.0, 6.0, ct))
	# BEAT 2 — the shove: one flat ellipse scraping outward along the floor. It
	# ends EXACTLY on the damage radius (see VISUAL_RADIUS_FACTOR), so what you can
	# see is what can hit you.
	var r: float = lerpf(10.0, NOVA_RADIUS * VISUAL_RADIUS_FACTOR, _ease_out(t))
	var alpha: float = 1.0 - t
	_draw_ground_ring(r, Color(0.6, 0.9, 1.0, 0.95 * alpha), lerpf(11.0, 1.5, t))
	_draw_ground_ring(r * 0.78, Color(0.85, 0.95, 1.0, 0.5 * alpha), lerpf(6.0, 1.0, t))
	# BEAT 3 — the clap: two short hard strokes at the caster. A percussive accent
	# that stops the burst reading as a soft bubble, and the ONLY bright thing
	# here: there is deliberately no big white flash disc, because "a white disc at
	# the impact point" is the motif every other ult in the kit already owns.
	if t < 0.35:
		var f: float = 1.0 - t / 0.35
		var h: float = NOVA_RADIUS * 0.5 * f
		draw_line(Vector2(0.0, -h), Vector2(0.0, h), Color(1.5, 1.8, 2.1, 0.8 * f), 3.0 * f + 1.0, true)
		draw_line(
			Vector2(-h * 0.55, 0.0), Vector2(h * 0.55, 0.0),
			Color(1.4, 1.7, 2.0, 0.55 * f), 2.0 * f + 1.0, true
		)


## THE GATHER, drawn. Three things, and every one of them is information rather
## than decoration:
##
##   THE SAFE LINE — a full ellipse at exactly the damage radius, held for the whole
##   wind-up, brightening as it fills. This is the answer to "no way of blocking it":
##   the boundary is on the floor, from the first frame, at its true size. It is
##   drawn as a dashed ring rather than a solid one specifically so it reads as a
##   WARNING and cannot be mistaken for the solid shockwave that follows it.
##
##   THE FILL — a bright arc sweeping around that same ellipse like a clock hand.
##   Distance is the ring; TIME is the sweep. Two separate questions, two separate
##   marks, so neither has to be inferred from the other.
##
##   THE INHALE — a small ring collapsing inward at the centre. It says which body
##   this is coming out of, which is the read the old instant version tried to buy
##   with a one-frame compression flash that arrived too late to be read.
func _draw_windup() -> void:
	var t: float = clampf(_windup_elapsed / maxf(WINDUP_TIME, 0.0001), 0.0, 1.0)
	var R: float = NOVA_RADIUS * TELEGRAPH_RADIUS_FACTOR
	# The safe line. Alpha climbs so the last frames before the blast are the loudest.
	var warn := Color(0.65, 0.9, 1.0, 0.30 + 0.45 * t)
	_draw_ground_ring(R, warn, 1.5 + 1.5 * t)
	# The clock hand, on the same ellipse.
	var pts := PackedVector2Array()
	var steps: int = maxi(int(ceil(28.0 * t)), 2)
	for i: int in steps + 1:
		var a: float = -PI * 0.5 + TAU * t * float(i) / float(steps)
		pts.append(Vector2(cos(a) * R, sin(a) * R * GROUND_SQUASH))
	draw_polyline(pts, Color(1.2, 1.6, 1.9, 0.85), 2.5, true)
	# The inhale.
	var ir: float = lerpf(R * 0.55, 4.0, ease(t, 0.6))
	_draw_ground_ring(ir, Color(1.0, 1.4, 1.7, 0.25 + 0.5 * t), 1.5)


## One floor-plane ellipse centred on the caster. Godot has no ellipse-arc
## primitive, so it is a polyline of points on the squashed circle — cheap, and it
## keeps the ring in the ground plane, where a side-view arena needs it.
func _draw_ground_ring(radius: float, col: Color, width: float) -> void:
	if radius <= 1.0:
		return
	var pts := PackedVector2Array()
	var steps: int = 48
	for i: int in steps + 1:
		var a: float = TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius * GROUND_SQUASH))
	draw_polyline(pts, col, width, true)


## Decelerating expansion — the wave leaves fast and settles, which reads as a
## shove rather than as a steadily-growing bubble.
func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 2.4)


## The shared burst builder, tuned to throw particles SIDEWAYS along the floor
## rather than spherically: the spray is part of the "flat shove" silhouette.
func _spawn_nova_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(0.75, 0.95, 1.0, 1.0), Color(0.25, 0.55, 1.0, 0.0),
		90, 0.45, 240.0, 540.0, 1.5, 4.5, 60.0, 130.0, true
	)
