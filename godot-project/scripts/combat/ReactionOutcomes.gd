class_name ReactionOutcomes
extends RefCounted
## What an authored reaction actually DOES. One static function per outcome key;
## SpellReactor decides that two effects met, this decides what that means.
##
## Outcomes land one at a time. An outcome named in ReactionTable but not yet
## implemented here is a deliberate no-op: the reactor still memoizes the pair
## (so it cannot spam), nothing is consumed, and the game behaves exactly as it
## did before the row was written. That is what makes the ~28-row matrix
## shippable in slices instead of as one landing.

## For a CROSS-CASTER crossing the meeting must sit in the BODY of both beams,
## not at a muzzle graze — a beam clipping the very tip of another is a near-miss,
## and reading it as an annihilation feels arbitrary. A SELF-combo is exempt:
## both beams leave the same muzzle, so they always meet at t~0 by construction.
const CROSS_MIN_T: float = 0.08
const CROSS_MAX_T: float = 0.97
## No two stubs faking a collapse.
const MIN_BEAM_LENGTH: float = 300.0
## How far in front of the caster the fusion circle opens, along their aim.
const SELF_COMBO_OFFSET: float = 200.0

const HOLLOW_PURPLE_PATH: String = "res://scripts/combat/HollowPurple.gd"

# --- CONTEST outcomes (the weight axis) --------------------------------------
# Every number here is REASONING, not feel — none of it has been played. They are
# together in one block so a single playtest pass can retune the whole family.
## Deliberately under Hollow Purple's spectacle: a clash is a thing that happens
## several times a fight, and it must not read as the once-a-fight fusion.
const CONTEST_BURST_COUNT: int = 34
const CONTEST_BURST_LIFE: float = 0.42
const CONTEST_BURST_SPEED_MIN: float = 140.0
const CONTEST_BURST_SPEED_MAX: float = 420.0
## Roughly BeamSpell's own discharge hitstop (0.09) minus a touch — a clash should
## register as an event without stopping the fight the way a beam landing does.
const CONTEST_HITSTOP: float = 0.07
const CONTEST_SHAKE: float = 13.0
const CONTEST_SFX_DB: float = -1.0
## A ONE-SIDED result (overpower, breach, a wall eating a spell) is a smaller
## moment than a mutual annihilation: something was deleted, but nothing was
## traded. Everything above is scaled by this when only one side is spent.
const CONTEST_ONE_SIDED_SCALE: float = 0.55

# --- THE ANNIHILATION (two beams meeting) ------------------------------------
# WHY THIS LEFT `_contest`. The maker's play report was "when the two beams clash
# they should EXPLODE" — and they WERE clashing. `tools/beam_clash_probe.gd`
# proved the detection was already correct: nine of the fifteen real beam pairs
# resolve to `mutual_annihilation`, and the reactor fires it and spends BOTH
# beams. What was missing was the BEAT. Sharing `_contest` meant two
# screen-crossing lances deleting each other got the same 34-particle puff as a
# wall being nudged, and — the loudest single miss — the generic "blast" stem
# rather than `rx_annihilate`, which has sat unused in the roster the whole time
# (`Sfx.REACTION_SOUND` has mapped `mutual_annihilation` -> `rx_annihilate`
# since the sound pass; nothing ever asked for it).
#
# Every other weight outcome stays on `_contest`. This one is split out because
# it is the only member of that family where BOTH sides are deleted at once, and
# that is a different size of event, not a louder version of the same one.
#
# ⚠ NOTHING HERE MAY EXCEED THE ROW'S RADIUS. The maker's rule is "the spells
# shouldn't be able to get out the radius", so the burst, the shock and the
# damage all derive from the one number the row authored, and
# tools/slice6_test_weight.gd asserts a body just outside takes zero.
const ANNIHILATE_BURST_COUNT: int = 96
const ANNIHILATE_BURST_LIFE: float = 0.62
## Particle speeds as FRACTIONS of the authored radius, so the spray reaches the
## edge of what was damaged and stops there — the visual half of the reach
## contract, the same trick `_banish` uses.
const ANNIHILATE_SPEED_MIN_FRAC: float = 0.9
const ANNIHILATE_SPEED_MAX_FRAC: float = 2.3
## Above BeamSpell's own discharge hitstop (0.09): the shot landing is a beat,
## two shots erasing each other is THE beat.
const ANNIHILATE_HITSTOP: float = 0.13
const ANNIHILATE_SHAKE: float = 26.0
const ANNIHILATE_ZOOM: float = 0.14
const ANNIHILATE_ZOOM_TIME: float = 0.3
## The screen ripple, harder than the beam's own discharge (0.6) because two of
## them just cancelled in one place.
const ANNIHILATE_SHOCK: float = 0.9
const ANNIHILATE_SFX_DB: float = 2.0
## A second, tighter, whiter core burst inside the coloured one — the flashpoint
## where the two beams actually touched. Fraction of the row's radius.
const ANNIHILATE_CORE_FRAC: float = 0.34
const ANNIHILATE_CORE_COUNT: int = 34

# --- SHARED PAYOFF NUMBERS ---------------------------------------------------
# Everything below this line landed in one pass and NONE of it has been played.
# Grouped here, like the contest block above, so one playtest can retune the whole
# family instead of hunting nine functions.
## Groups a reaction's damage may reach. Deliberately NOT "hero": every one of the
## ~15 spectacles in this game resolves damage against "enemy" (plus props), so a
## reaction layer that quietly friendly-fired would be a rules change smuggled in
## under a VFX feature. If reactions should hurt heroes one day, that is a design
## decision made HERE, in one line, rather than discovered in a co-op session.
## "hero" INCLUDED. Friendly fire is a locked design pillar of this game, and a
## reaction that is pure spectacle in a duel is a lie: the maker watched two beams
## annihilate between two players and nothing happened to either of them. If a
## clash is loud enough to stop the screen it has to be able to hurt whoever is
## standing in it. Co-op partners are hittable by every other spell already, so
## this makes reactions consistent with the rest of the game rather than an
## exception to it.
const HURT_GROUPS: Array[String] = ["enemy", "destructible", "hero"]
## Area used when an authored row deals damage but names no radius. Only
## `beam_resonance`, `supercharge` and `banish` are in that shape today, and none
## of them opens a new blast — the first two make a thing that already exists
## stronger, and the third is bounded by the FIELD it is unmaking — so the
## fallback is deliberately modest. UNTESTED GUESS.
const IMPLIED_RADIUS: float = 120.0
## A shattered barrier throws its own material outward. UNTESTED GUESS: a touch
## under IceWall's own SHATTER_KNOCKBACK (300), because the wall's authored death
## already supplies most of the shove and this rides on top of it.
const SHATTER_KNOCKBACK: float = 260.0
## Shrapnel is the same event with a DIRECTION, so it hits harder along the line
## the projectile was travelling. UNTESTED GUESS.
const SHRAPNEL_KNOCKBACK: float = 340.0
## Half-angle of the shrapnel cone, as a dot product. 0.25 is ~76 degrees each
## side — wide enough that "I broke the wall toward them" is forgiving, narrow
## enough that standing BEHIND the projectile is safe, which is the whole point of
## authoring a cone instead of a circle. UNTESTED GUESS.
const SHRAPNEL_MIN_DOT: float = 0.25
## The void's inversion: knockback becomes a PULL. Negative because `_radial`
## reads the sign as direction — away from the point, or toward it. UNTESTED GUESS.
const VOID_PULL: float = -300.0
## Resonance does not shove. Two beams swelling into each other is a bloom, not a
## blast, and a knockback here would make the constructive reaction feel like the
## destructive one — the exact confusion `beam_resonance` exists to prevent.
const RESONANCE_KNOCKBACK: float = 0.0
## Screen kick for the reactions that are events rather than set-pieces. All under
## the contest block's numbers on purpose: these fire more often. UNTESTED GUESSES.
const MINOR_HITSTOP: float = 0.05
const MINOR_SHAKE: float = 9.0
const STEAM_SHAKE: float = 6.0

## --- BANISH (holy vs shadow) -------------------------------------------------
## The erasure's whole visual argument is that it is SLOW and INWARD where every
## other reaction here is fast and outward. These numbers are the argument, and
## like the block above none of them has been played.
## Motes are spawned at a fraction of the field's radius and heavily damped, so
## they drift and settle inside the footprint instead of spraying past it — light
## filling a space rather than a blast leaving one. Deliberately NOT `_flash`,
## which derives particle speed as radius*0.9..radius*2.4 (a spray that reaches
## the edge and stops); reusing it would have made the one reaction that must not
## look like an explosion look like every explosion.
const BANISH_MOTES: int = 46
const BANISH_LIFE: float = 0.85
const BANISH_SPEED_MIN_FRAC: float = 0.12
const BANISH_SPEED_MAX_FRAC: float = 0.5
const BANISH_DAMPING: float = 2.4
## Gold-white going to nothing. Over 1.0 so the core clears the arena bloom
## threshold and the erasure reads as LIGHT rather than as a pale particle.
const BANISH_CORE: Color = Color(1.9, 1.8, 1.35, 0.95)
const BANISH_EDGE: Color = Color(1.0, 0.93, 0.6, 0.0)
## Under MINOR_SHAKE: something was REMOVED, not detonated. A kick here would be
## the screen disagreeing with the picture.
const BANISH_SHAKE: float = 5.0
## Only used if a field publishes no usable shape at all — normally the field's
## own drawn radius is the damaged radius. UNTESTED GUESS.
const BANISH_FALLBACK_RADIUS: float = 150.0

const STEAM_CLOUD_PATH: String = "res://scripts/combat/SteamCloud.gd"

const EPS_SQ: float = 0.000001


## Dispatch. `ctx` carries {reactor, rule, a, b, element_a, element_b, weight_a,
## weight_b, shape_a, shape_b, owner_rel, point, spawn_effects}. Returns true when
## the event was handled and should be memoized; false leaves the pair free to try
## again next tick.
##
## ⚠ AN OUTCOME KEY WITH NO ARM HERE IS WORSE THAN NO ROW AT ALL. The reactor
## memoizes the pair the moment `apply` returns true, so an unimplemented key
## marks two spells as "having reacted" and then lets them pass through each
## other. Six keys sat in exactly that state — steam_cloud, supercharge,
## field_merge, beam_resonance, shatter_ice_barrier, shrapnel_cone, void_charged,
## ground_out and carve all matched, memoized and did nothing. If you add a row to
## ReactionTable, add its arm here in the same commit.
static func apply(outcome: String, ctx: Dictionary) -> bool:
	match outcome:
		"hollow_purple":
			return _hollow_purple(ctx)
		# The whole weight family shares ONE implementation, because the rows
		# already differ in the only way that matters: which sides they spend.
		# "both" is a mutual annihilation, "the lighter one" is an overpower,
		# "the barrier" is a breach, "the spell" is a wall holding. Writing four
		# near-identical functions would be four places to forget the swapped-side
		# mapping in.
		#
		# `ground_out` (earth eats a lightning beam) and `shatter_ward` (shadow
		# pops a holy ward) join them because they say the same sentence with
		# different words: one side is spent, the other walks away. Their identity
		# lives in the ROW — which side, which elements, which priority — which is
		# what this whole file is arguing for.
		# ...with ONE member split off. `mutual_annihilation` is the only outcome in
		# that family that deletes BOTH sides at once, and its participants are
		# always two screen-crossing lances. That is a different SIZE of event, not
		# a louder version of the same one. See the ANNIHILATE_* block.
		"mutual_annihilation":
			return _annihilate(ctx)
		# ⚠ `bolt_fizzle` IS ROUTED HERE AND DELIBERATELY *NOT* TO `_annihilate`. That
		# function's own header justifies its ult-sized beat by RARITY — two beams
		# meeting is a headline event. Two bolts meeting is the highest-traffic
		# collision in the game, several times a duel, so giving it the loudest
		# spectacle in the file would spend the beam clash's currency on small change.
		# `_contest` spends both sides and stages a scaled two-element burst, which is
		# the right size for a pop.
		"overpower", "breach", "barrier_blocks", \
		"ground_out", "shatter_ward", "bolt_fizzle":
			return _contest(ctx)
		"beam_resonance":
			return _resonance(ctx)
		"shatter_ice_barrier":
			return _shatter_barrier(ctx)
		"shrapnel_cone":
			return _shrapnel(ctx)
		"steam_cloud":
			return _steam_cloud(ctx)
		"supercharge":
			return _supercharge(ctx)
		"void_charged":
			return _void_charged(ctx)
		"carve":
			return _carve(ctx)
		"field_merge":
			return _field_merge(ctx)
		"ward_absorb":
			return _ward_absorb(ctx)
		"banish":
			return _banish(ctx)
		# The three new arms. ⚠ ADDED IN THE SAME COMMIT AS THEIR ROWS, which the
		# header above insists on: an outcome key with no arm here is worse than no
		# row at all, because `apply` returns true, the reactor memoizes the pair, and
		# the two spells then pass through each other doing nothing.
		"vaporise":
			return _vaporise(ctx)
		"prism_burst":
			return _prism_burst(ctx)
		"molten_slag":
			return _molten_slag(ctx)
	return true


# ------------------------------------------------------------ WEIGHT CONTESTS

## Two effects met and the table decided the outcome by how much they weigh. All
## this does is SPEND what the row says is spent and put a burst where they met —
## the design lives in ReactionTable, which is the point.
##
## Note it consumes nothing the row did not name: `overpower` leaves the heavy
## side completely untouched, still drawn, still damaging, still travelling. That
## is the difference the maker asked for between "both explode" and "the big one
## wins".
static func _contest(ctx: Dictionary) -> bool:
	var rule: Dictionary = ctx.get("rule", {})
	var node_a: Node = ctx.get("a") as Node
	var node_b: Node = ctx.get("b") as Node
	# ⚠ Through consumes_caller, never the raw flags: the row may have matched
	# with its sides reversed, in which case its consumes_a means our `b`.
	var spend_a: bool = ReactionTable.consumes_caller(rule, 0)
	var spend_b: bool = ReactionTable.consumes_caller(rule, 1)
	var spent: int = (1 if spend_a else 0) + (1 if spend_b else 0)
	if spent == 0:
		# A contest row that spends nothing is a no-op by design (an authored
		# "these two just push past each other"). Still memoized so it cannot
		# re-fire every tick for as long as the pair overlaps.
		return true
	# Spectacle BEFORE consumption: reaction_consume() queue_free()s a spectacle,
	# and the burst is parented to that spectacle's parent.
	if bool(ctx.get("spawn_effects", true)):
		_contest_spectacle(ctx, spent)
	if spend_a:
		_break(node_a)
	if spend_b:
		_break(node_b)
	return true


## MUTUAL_ANNIHILATION — two beams meet, both are erased, and the place they met
## detonates. The maker's sentence, made true: "if any two of these line spells
## hit each other they should EXPLODE and go away."
##
## THE PICTURE IS A SHAPE, so the impact frame is the BLACK SILHOUETTE cut and
## never the white blow-out. This is the same reasoning BeamSpell._discharge
## already writes down for its own frame, and it applies twice as hard here:
## whatever is left on screen at the moment two lances cancel is the last frame
## of two drawn lines, and white erases lines. Black silhouettes them. `lines:
## false` for the same reason — nothing should compete with the beams.
##
## WHY IT IS SAFE TO BE THIS LOUD. Unlike `_contest`, which fires for wall nudges
## several times a fight, this needs two casters to land screen-crossing beams
## across each other inside a 0.48 s window (BeamSpell's live phase). It is rare
## by construction, which is exactly what earns it an ult-sized beat.
##
## Damage, burst and shock all derive from the ROW's radius — one number, so the
## drawn extent and the damaged extent cannot drift apart.
static func _annihilate(ctx: Dictionary) -> bool:
	var p: Vector2 = ctx.get("point", Vector2.ZERO)
	var r: float = _rule_radius(ctx, 150.0)
	var element_a: int = int(ctx.get("element_a", -1))
	var element_b: int = int(ctx.get("element_b", -1))
	# No ailment. Two beams cancelling is not either element LANDING on anyone —
	# passing one would arbitrarily pick a winner between the two schools that just
	# erased each other, and would burn or chill bystanders with a spell that never
	# reached them. `_radial`'s element argument is -1 for exactly this case.
	_radial(ctx, p, r, _rule_damage(ctx), -1, SHATTER_KNOCKBACK)
	if not bool(ctx.get("spawn_effects", true)):
		# Detection-only (headless suites): spend the beams, stage nothing.
		_spend(ctx)
		return true
	var host: Node = _stage_parent(ctx)
	if host != null:
		var mix: Color = _element_color(element_a).lerp(_element_color(element_b), 0.5)
		# The two schools blowing apart, bounded by the row's radius.
		CombatVfx.spawn_burst(
			host, p,
			Color(mix.r, mix.g, mix.b, 0.98), Color(mix.r, mix.g, mix.b, 0.0),
			ANNIHILATE_BURST_COUNT, ANNIHILATE_BURST_LIFE,
			r * ANNIHILATE_SPEED_MIN_FRAC, r * ANNIHILATE_SPEED_MAX_FRAC,
			1.2, 4.2, 0.0, 0.0, true)
		# ...and a tight white-hot core at the flashpoint. Over 1.0 so it clears the
		# arena bloom threshold: the point where the two beams touched should be the
		# brightest thing on screen for one frame.
		CombatVfx.spawn_burst(
			host, p, Color(2.0, 1.95, 1.9, 1.0), Color(1.4, 1.3, 1.6, 0.0),
			ANNIHILATE_CORE_COUNT, ANNIHILATE_BURST_LIFE * 0.55,
			r * ANNIHILATE_CORE_FRAC * 0.6, r * ANNIHILATE_CORE_FRAC * 2.0,
			1.0, 3.0, 0.0, 0.0, true)
	Juice.hit_stop(ANNIHILATE_HITSTOP)
	Juice.shake_camera(ANNIHILATE_SHAKE)
	Juice.zoom_punch_camera(ANNIHILATE_ZOOM, ANNIHILATE_ZOOM_TIME)
	PostProcess.shock(ANNIHILATE_SHOCK)
	# The black anime cut. Element -1 keeps the horizon neutral — see above: this
	# frame belongs to neither school.
	Juice.frame({
		"style": ImpactFrame.Style.SILHOUETTE, "strength": 1.0, "at": p,
		"element": -1, "lines": false,
		# Every screen verb is already spent above; passing them again here would
		# double-shake and double-stop.
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
	})
	# `rx_annihilate` — the roster's own ULT-weighted crack, resolved through
	# Sfx.reaction_sound() rather than named here. It has been mapped from this
	# outcome since the sound pass and never played, because `_contest` reached for
	# the generic "blast" stem instead.
	_reaction_sfx("mutual_annihilation", ANNIHILATE_SFX_DB, 0.0)
	_spend(ctx)
	return true


static func _contest_spectacle(ctx: Dictionary, spent: int) -> void:
	var host: Node = _stage_parent(ctx)
	if host == null:
		# Nowhere to hang particles. The consumption still happens — a clash that
		# silently fails to spend its beams is far worse than a silent clash.
		return
	var p: Vector2 = ctx.get("point", Vector2.ZERO)
	var scale: float = 1.0 if spent >= 2 else CONTEST_ONE_SIDED_SCALE
	# The two elements meeting, blended — a fire/lightning clash should not look
	# like a fire/lightning clash's neighbour. No new palette to maintain.
	var mix: Color = _element_color(int(ctx.get("element_a", -1))).lerp(
		_element_color(int(ctx.get("element_b", -1))), 0.5)
	CombatVfx.spawn_burst(
		host, p,
		Color(mix.r, mix.g, mix.b, 0.95), Color(mix.r, mix.g, mix.b, 0.0),
		int(float(CONTEST_BURST_COUNT) * scale), CONTEST_BURST_LIFE,
		CONTEST_BURST_SPEED_MIN * scale, CONTEST_BURST_SPEED_MAX * scale,
		1.2, 3.4, 0.0, 0.0, true
	)
	Juice.hit_stop(CONTEST_HITSTOP * scale)
	Juice.shake_camera(CONTEST_SHAKE * scale)
	_sfx("blast", CONTEST_SFX_DB, 0.05)


# ------------------------------------------------------- WHICH SIDE IS WHICH
# ⚠ THE SAME TRAP consumes_caller() EXISTS FOR, AND IT BITES HARDER HERE. A row
# written "fire beam vs ice barrier" ALSO matches when the barrier was seen first,
# and then the row's form_a is the caller's `b`. `_contest` only had to get the
# CONSUMPTION the right way round; every outcome below has to find a specific
# participant — the barrier to shatter, the field to boil, the ward to degrade —
# so each one asks the rule which caller side its authored form_a/form_b landed
# on. Assuming the author's ordering survived the match is how a fire beam ends up
# shattering itself.

## The caller's side index (0 = ctx.a, 1 = ctx.b) currently sitting on the RULE's
## side `rule_side` (0 = the row's form_a, 1 = its form_b).
static func _caller_side(ctx: Dictionary, rule_side: int) -> int:
	var rule: Dictionary = ctx.get("rule", {})
	return (1 - rule_side) if bool(rule.get("swapped", false)) else rule_side


static func _node_at(ctx: Dictionary, side: int) -> Node:
	return ctx.get("b" if side == 1 else "a") as Node


static func _shape_at(ctx: Dictionary, side: int) -> Dictionary:
	var s: Variant = ctx.get("shape_b" if side == 1 else "shape_a", {})
	return s as Dictionary if s is Dictionary else {}


static func _element_at(ctx: Dictionary, side: int) -> int:
	return int(ctx.get("element_b" if side == 1 else "element_a", -1))


## WHERE an effect actually is, from the shape it published — never from its
## transform, which for ten of the spectacles is the arena origin and a lie.
## Falls back to the meeting point, which is always meaningful.
static func _shape_center(s: Dictionary, fallback: Vector2) -> Vector2:
	if s.is_empty():
		return fallback
	if SpellGeometry.is_circle(s):
		return s["center"] as Vector2
	return ((s["from"] as Vector2) + (s["to"] as Vector2)) * 0.5


## How big an area an effect occupies, from its own shape. Used when a row deals
## damage "inside the field" rather than inside an authored blast — the field's
## drawn radius IS the damaged radius then, which is the cheapest possible way to
## honour "the spells shouldn't be able to get out the radius".
static func _shape_reach(s: Dictionary, fallback: float) -> float:
	if s.is_empty():
		return fallback
	if SpellGeometry.is_circle(s):
		return float(s["radius"])
	return (s["from"] as Vector2).distance_to(s["to"] as Vector2) * 0.5


## Which way an effect was TRAVELLING when it met the other one. A capsule knows
## (from -> to); a circle does not, so it is inferred from where it met the thing
## it ran into — which for a projectile hitting a wall is exactly its heading.
static func _travel_dir(s: Dictionary, toward: Vector2) -> Vector2:
	if not s.is_empty() and not SpellGeometry.is_circle(s):
		var d: Vector2 = (s["to"] as Vector2) - (s["from"] as Vector2)
		if d.length_squared() > EPS_SQ:
			return d.normalized()
	var c: Vector2 = _shape_center(s, toward)
	var away: Vector2 = toward - c
	return away.normalized() if away.length_squared() > EPS_SQ else Vector2.RIGHT


# --------------------------------------------------------------- THE PAYOFF

## Damage / status / shove everything a reaction reaches. THE one function every
## outcome below resolves through, which is what stops nine reactions becoming
## nine slightly-different target loops — the exact duplication SpellTargets was
## written to end.
##
## `center` and `radius` are the DRAWN extent of the reaction, always. The maker's
## rule is "the spells shouldn't be able to get out the radius", so every caller
## passes the geometry it is about to draw a burst at, and line-of-sight culling
## comes free (SpellTargets.in_radius defaults require_los = true, so a reaction
## cannot kill through solid rock).
##
## `knockback` is signed: positive shoves away from `center`, NEGATIVE PULLS
## TOWARD IT. The sign is the whole of `void_charged`'s inversion, expressed as a
## number rather than a branch.
##
## Deliberately NOT gated on `spawn_effects`: that seam suppresses SPECTACLE so a
## headless suite need not stage a 1.6 s set-piece, and suppressing damage with it
## would leave the tests unable to prove the thing that actually matters. `_contest`
## draws the same line — it consumes unconditionally and only gates its burst.
##
## Returns how many bodies were affected, so a test can assert reach and, more
## importantly, assert the NEGATIVE case: that something just outside is untouched.
static func _radial(ctx: Dictionary, center: Vector2, radius: float, damage: int,
		element: int, knockback: float = 0.0,
		cone_dir: Vector2 = Vector2.ZERO, cone_min_dot: float = -2.0) -> int:
	if radius <= 0.0:
		return 0
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var host: Node = _stage_parent(ctx)
	var affected: int = 0
	for group: String in HURT_GROUPS:
		for n: Node in SpellTargets.in_radius(center, radius,
				tree.get_nodes_in_group(group), [], host):
			var n2: Node2D = n as Node2D
			if n2 == null:
				continue
			var span: Vector2 = n2.global_position - center
			# The cone gate, when there is one. A target standing exactly ON the
			# centre has no direction and is always included — it is inside the
			# burst by any reading, and excluding it would make point-blank the
			# safest place to stand.
			if cone_min_dot > -1.5 and cone_dir.length_squared() > EPS_SQ \
					and span.length_squared() > EPS_SQ \
					and cone_dir.dot(span.normalized()) < cone_min_dot:
				continue
			if damage > 0 and n.has_method(&"take_damage"):
				n.call(&"take_damage", damage)
			if element >= 0 and n.has_method(&"apply_status"):
				n.call(&"apply_status", element)
			if not is_zero_approx(knockback) and n.has_method(&"apply_knockback"):
				var away: Vector2 = span.normalized() if span.length_squared() > EPS_SQ \
					else Vector2.UP
				n.call(&"apply_knockback", away * knockback)
			affected += 1
	return affected


## Spend exactly what the winning row said to spend, read through
## consumes_caller() so a swapped match cannot eat the wrong effect.
static func _spend(ctx: Dictionary) -> int:
	var rule: Dictionary = ctx.get("rule", {})
	var n: int = 0
	if ReactionTable.consumes_caller(rule, 0):
		_break(_node_at(ctx, 0))
		n += 1
	if ReactionTable.consumes_caller(rule, 1):
		_break(_node_at(ctx, 1))
		n += 1
	return n


## The row's authored blast, with a sane fallback. Rows that name a radius mean
## it; rows that deal damage without one are asking for the implied area.
static func _rule_radius(ctx: Dictionary, fallback: float = IMPLIED_RADIUS) -> float:
	var r: float = float((ctx.get("rule", {}) as Dictionary).get("radius", 0.0))
	return r if r > 0.0 else fallback


static func _rule_damage(ctx: Dictionary) -> int:
	return int((ctx.get("rule", {}) as Dictionary).get("damage", 0))


## One burst, tinted by the two elements meeting, honouring `spawn_effects`.
## Sized off the reaction's own radius so the picture and the damage agree.
static func _flash(ctx: Dictionary, at: Vector2, radius: float, count: int,
		life: float, dir: Vector2 = Vector2.ZERO, spread: float = 180.0,
		additive: bool = true) -> void:
	if not bool(ctx.get("spawn_effects", true)):
		return
	var host: Node = _stage_parent(ctx)
	if host == null:
		return
	var mix: Color = _element_color(int(ctx.get("element_a", -1))).lerp(
		_element_color(int(ctx.get("element_b", -1))), 0.5)
	# Particle speed is derived from the radius so the spray reaches the edge of
	# what was damaged and no further — the visual half of the reach contract.
	CombatVfx.spawn_burst(
		host, at,
		Color(mix.r, mix.g, mix.b, 0.95), Color(mix.r, mix.g, mix.b, 0.0),
		count, life, radius * 0.9, radius * 2.4, 1.0, 3.2, 0.0, 0.0,
		additive, dir, spread)


# ------------------------------------------------------ the authored outcomes

## BEAM_RESONANCE — two beams of the SAME element crossing REINFORCE rather than
## annihilate. Nothing is spent (both beams keep firing), so the payoff has to BE
## the crossing: a same-element bloom and one damage pulse around it.
##
## The constructive case matters more than it looks. Without it every meeting in
## the game is destruction, players learn "never cross the streams", and the whole
## reaction layer collapses into one lesson.
static func _resonance(ctx: Dictionary) -> bool:
	var p: Vector2 = ctx.get("point", Vector2.ZERO)
	var r: float = _rule_radius(ctx)
	# Both sides are the same element by the row's own require_same predicate, so
	# either one names the ailment.
	_radial(ctx, p, r, _rule_damage(ctx), int(ctx.get("element_a", -1)),
		RESONANCE_KNOCKBACK)
	_flash(ctx, p, r, 40, 0.5)
	if bool(ctx.get("spawn_effects", true)):
		Juice.hit_stop(MINOR_HITSTOP)
		Juice.shake_camera(MINOR_SHAKE)
		_reaction_sfx("beam_resonance", -2.0, 0.02)
	return true


## SHATTER_ICE_BARRIER — fire or holy light (or any physical impact) meets an ice
## wall and the wall goes. Staged at the BARRIER, not at the meeting point: the
## thing that exploded is the wall, and a burst hanging out at the beam's edge
## would read as the beam having done something to the air.
static func _shatter_barrier(ctx: Dictionary) -> bool:
	var b: int = _caller_side(ctx, 1)         # the row's form_b is the BARRIER
	var at: Vector2 = _shape_center(_shape_at(ctx, b), ctx.get("point", Vector2.ZERO))
	var r: float = _rule_radius(ctx)
	# The ailment carried is the ATTACKER's — fire shatters an ice wall and leaves
	# burning, not chilled, bodies around it.
	_radial(ctx, at, r, _rule_damage(ctx), _element_at(ctx, _caller_side(ctx, 0)),
		SHATTER_KNOCKBACK)
	_flash(ctx, at, r, 44, 0.5)
	if bool(ctx.get("spawn_effects", true)):
		Juice.hit_stop(MINOR_HITSTOP)
		Juice.shake_camera(MINOR_SHAKE)
		_reaction_sfx("shatter_ice_barrier", 0.0, 0.02)
	# ⚠ UNTESTED TUNING NOTE: IceWall.shatter() carries its own 18-damage burst, so
	# a wall popped by this row deals the row's damage AND the wall's. That stacking
	# is deliberate — the row's number is what the REACTION is worth and the wall's
	# is what it was always worth — but it is the first thing to look at if popping
	# a wall onto a crowd feels like a nuke.
	_spend(ctx)
	return true


## SHRAPNEL_CONE — the same event with a DIRECTION. A thrown thing punches through
## an ice wall and the wall comes apart ALONG its flight, so breaking the wall
## toward someone is a play and standing behind the thrower is safe.
static func _shrapnel(ctx: Dictionary) -> bool:
	var a: int = _caller_side(ctx, 0)         # the row's form_a is the PROJECTILE
	var b: int = _caller_side(ctx, 1)
	var at: Vector2 = _shape_center(_shape_at(ctx, b), ctx.get("point", Vector2.ZERO))
	var dir: Vector2 = _travel_dir(_shape_at(ctx, a), at)
	var r: float = _rule_radius(ctx)
	_radial(ctx, at, r, _rule_damage(ctx), _element_at(ctx, b),
		SHRAPNEL_KNOCKBACK, dir, SHRAPNEL_MIN_DOT)
	# A cone of spray, thrown the way the shards went — the picture and the hit
	# test read the same direction.
	_flash(ctx, at, r, 40, 0.45, dir, 62.0)
	if bool(ctx.get("spawn_effects", true)):
		var host: Node = _stage_parent(ctx)
		if host != null:
			DebrisChunk.spawn_burst(host, at, Color(0.78, 0.92, 1.0), 14, dir, 320.0)
		Juice.hit_stop(MINOR_HITSTOP)
		Juice.shake_camera(MINOR_SHAKE)
		_reaction_sfx("shrapnel_cone", 1.0, 0.0)
	_spend(ctx)
	return true


## STEAM_CLOUD — the ONE reaction in the table whose payoff is VISION rather than
## damage. Fire boils a frost field off and what is left is a bank of steam
## standing where the field was, hiding whatever walks into it.
##
## Note it deals no damage at all, and the row authors none: turning the vision
## reaction into a damage reaction would delete the only non-damage answer the
## matrix has.
## ══ A BOLT FLIES INTO A BEAM ═══════════════════════════════════════════════
## The quietest of the five new reactions, and deliberately so: it fires often (every
## caster throws bolts, four hold beams) and anything loud at that rate becomes
## wallpaper. A hard white pop AT THE BOLT, no screen verbs at all beyond the minor
## shake — the beam is unbroken and must go on looking unbroken.
##
## No damage: the bolt is gone, which is the whole outcome. A splash here would make
## standing behind your own bolt dangerous.
static func _vaporise(ctx: Dictionary) -> bool:
	var b: int = _caller_side(ctx, 1)          # form_b is the PROJECTILE
	var at: Vector2 = _shape_center(_shape_at(ctx, b), ctx.get("point", Vector2.ZERO))
	if bool(ctx.get("spawn_effects", true)):
		_flash(ctx, at, _rule_radius(ctx, 60.0) * 0.55, 18, 0.22)
		Juice.shake_camera(MINOR_SHAKE * 0.5)
		_reaction_sfx("vaporise", -3.0, 0.0)
	_spend(ctx)
	return true


## ══ ...AND OPPOSED, IT SPLITS ══════════════════════════════════════════════
## The spectacle half of the same meeting. Two colours thrown apart from one point:
## the beam's element sprays FORWARD along the beam, the bolt's sprays BACK down the
## line it came in on, so the picture says which came from where. That directional
## split is the entire read, and it is what a radial burst — which is what every other
## clash in this file does — cannot say.
static func _prism_burst(ctx: Dictionary) -> bool:
	var a: int = _caller_side(ctx, 0)
	var b: int = _caller_side(ctx, 1)
	var at: Vector2 = _shape_center(_shape_at(ctx, b), ctx.get("point", Vector2.ZERO))
	var r: float = _rule_radius(ctx, 170.0)
	# The beam's element carries the damage: the bolt is the thing that died.
	var hit: int = _radial(ctx, at, r, _rule_damage(ctx), _element_at(ctx, a),
		SHATTER_KNOCKBACK * 0.6)
	if bool(ctx.get("spawn_effects", true)):
		# `_travel_dir` takes the SHAPE and a point to fall back toward, not a side
		# index — a capsule reports its own from->to, and a circle has to be told
		# which way "away" is.
		var beam_dir: Vector2 = _travel_dir(_shape_at(ctx, a), at)
		var bolt_dir: Vector2 = _travel_dir(_shape_at(ctx, b), at)
		_flash(ctx, at, r * 0.7, 34, 0.42, beam_dir, 46.0)
		_flash(ctx, at, r * 0.7, 34, 0.42, -bolt_dir, 46.0)
		# COLOR_FIELD, not BLOWOUT: the payoff IS two colours, and a white wash is the
		# one frame style that erases exactly that.
		Juice.frame({"style": ImpactFrame.Style.COLOR_FIELD, "strength": 0.9,
			"at": at, "element": _element_at(ctx, a)})
		Juice.hit_stop(MINOR_HITSTOP * 1.6)
		Juice.shake_camera(MINOR_SHAKE * 1.4)
		_reaction_sfx("prism_burst", 0.0, 0.02)
	_spend(ctx)
	return hit >= 0


## ══ FIRE MELTS STONE ═══════════════════════════════════════════════════════
## The barrier goes, and it goes DOWNWARD — a wall that is cut in half falls, a wall
## that is melted slumps. The burst is therefore weighted along gravity rather than
## radially, which is a one-argument difference that does most of the work of saying
## "melted" rather than "shattered".
##
## The damage is the attacker's FIRE, applied where the wall was, so anyone sheltering
## behind their own rock wall pays for having chosen it against a lance.
static func _molten_slag(ctx: Dictionary) -> bool:
	var a: int = _caller_side(ctx, 0)
	var b: int = _caller_side(ctx, 1)          # form_b is the BARRIER
	var wall: Dictionary = _shape_at(ctx, b)
	var at: Vector2 = _shape_center(wall, ctx.get("point", Vector2.ZERO))
	var r: float = maxf(_rule_radius(ctx, 140.0), _shape_reach(wall, 0.0))
	var hit: int = _radial(ctx, at, r, _rule_damage(ctx), _element_at(ctx, a), 0.0)
	if bool(ctx.get("spawn_effects", true)):
		# Slumping, not bursting: down the screen, slow, and heavily damped so the
		# motes settle instead of flying.
		var host: Node = _stage_parent(ctx)
		if host != null:
			CombatVfx.spawn_burst(host, at,
				Color(2.2, 1.15, 0.35, 1.0), Color(0.55, 0.18, 0.06, 0.0),
				40, 0.75, 30.0, 130.0, 1.2, 3.4, 2.2, 3.6, true,
				Vector2.DOWN, 62.0)
		Juice.hit_stop(MINOR_HITSTOP)
		Juice.shake_camera(MINOR_SHAKE)
		_reaction_sfx("molten_slag", -2.0, 0.02)
	_spend(ctx)
	return hit >= 0


static func _steam_cloud(ctx: Dictionary) -> bool:
	var b: int = _caller_side(ctx, 1)         # the row's form_b is the FIELD
	var fshape: Dictionary = _shape_at(ctx, b)
	var at: Vector2 = _shape_center(fshape, ctx.get("point", Vector2.ZERO))
	# The row's radius wins, but a field that drew itself bigger than the row
	# expected should still boil off entirely rather than leaving a visible collar
	# of untouched frost outside the steam.
	var r: float = maxf(_rule_radius(ctx, 160.0), _shape_reach(fshape, 0.0))
	if bool(ctx.get("spawn_effects", true)):
		var host: Node = _stage_parent(ctx)
		if host != null:
			# Loaded by PATH, never by class_name — the same rule _hollow_purple
			# follows. A class_name reference pulls the spectacle into the compile
			# graph of every headless suite that touches this file, and a spectacle
			# that names an autoload then fails the WHOLE chain.
			var cloud: Node2D = (load(STEAM_CLOUD_PATH) as GDScript).new()
			host.add_child(cloud)
			cloud.call(&"boil", at, r)
		Juice.shake_camera(STEAM_SHAKE)
		_reaction_sfx("steam_cloud", -4.0, 0.03)
	_spend(ctx)
	return true


## SUPERCHARGE — lightning through a frost field conducts harder. Nothing is
## spent: the beam carries on and the field keeps standing, it is just a very bad
## place to be for one moment.
##
## The damaged area is the FIELD'S OWN SHAPE, not an authored blast. That is the
## cheapest possible way to satisfy "the spells shouldn't be able to get out the
## radius" — the thing being drawn IS the thing being damaged, by construction.
static func _supercharge(ctx: Dictionary) -> bool:
	var b: int = _caller_side(ctx, 1)         # the row's form_b is the FIELD
	var fshape: Dictionary = _shape_at(ctx, b)
	var at: Vector2 = _shape_center(fshape, ctx.get("point", Vector2.ZERO))
	var r: float = _shape_reach(fshape, _rule_radius(ctx))
	# The ailment is the BEAM's (shock), not the field's: the field is the
	# conductor, the lightning is what reaches you.
	_radial(ctx, at, r, _rule_damage(ctx), _element_at(ctx, _caller_side(ctx, 0)))
	_flash(ctx, at, r, 46, 0.34)
	if bool(ctx.get("spawn_effects", true)):
		Juice.hit_stop(MINOR_HITSTOP)
		Juice.shake_camera(MINOR_SHAKE)
		_reaction_sfx("supercharge", 1.0, 0.0)
	return true


## VOID_CHARGED — anything detonating inside a void field is void-charged and the
## knockback INVERTS into a pull. The inversion is the entire identity of the row,
## and here it is one negative number rather than a branch.
static func _void_charged(ctx: Dictionary) -> bool:
	var b: int = _caller_side(ctx, 1)         # the row's form_b is the FIELD
	var p: Vector2 = ctx.get("point", Vector2.ZERO)
	var r: float = _rule_radius(ctx, 175.0)
	_radial(ctx, p, r, _rule_damage(ctx), _element_at(ctx, b), VOID_PULL)
	# Particles thrown INWARD would need a spawner this helper does not have, so
	# the implosion is sold by a tight, short, dark burst instead of a wide spray.
	_flash(ctx, p, r * 0.45, 34, 0.42)
	if bool(ctx.get("spawn_effects", true)):
		Juice.hit_stop(MINOR_HITSTOP)
		Juice.shake_camera(MINOR_SHAKE)
		PostProcess.shock(0.45)   # the screen ripple sells a collapse better than shake
		_reaction_sfx("void_charged", -2.0, 0.0)
	return true


## CARVE — the authored exception where a barrier is POROUS. An evenly-matched
## beam bores through stone without breaking it, so nothing is consumed; the wall
## simply takes the damage the row names.
##
## RockWall has no `take_damage` today, which makes the damage half of this a
## no-op and the reaction a purely visual "you are getting through". That is
## correct and deliberate: the ROW's promise is that the beam is not stopped, and
## that promise is kept by spending nothing. The duck-typed call is here so a
## barrier that learns to take damage inherits the rest for free.
static func _carve(ctx: Dictionary) -> bool:
	var b: int = _caller_side(ctx, 1)         # the row's form_b is the BARRIER
	var barrier: Node = _node_at(ctx, b)
	var p: Vector2 = ctx.get("point", Vector2.ZERO)
	var dmg: int = _rule_damage(ctx)
	if dmg > 0 and barrier != null and is_instance_valid(barrier) \
			and barrier.has_method(&"take_damage"):
		barrier.call(&"take_damage", dmg)
	if bool(ctx.get("spawn_effects", true)):
		var host: Node = _stage_parent(ctx)
		if host != null:
			# Dust and grit, NOT additive: this is rock being eaten, not light.
			CombatVfx.spawn_burst(host, p, Color(0.85, 0.62, 0.35, 0.9),
				Color(0.4, 0.28, 0.15, 0.0), 20, 0.5, 50.0, 190.0, 1.6, 4.2)
			DebrisChunk.spawn_burst(host, p, Color(0.5, 0.38, 0.22), 6, Vector2.ZERO, 180.0)
		Juice.shake_camera(MINOR_SHAKE * 0.5)
		_reaction_sfx("carve", -6.0, 0.0)
	return true


## FIELD_MERGE — two fields of the same element become ONE bigger field instead of
## two rings stacked on the same floor. The row spends side b; side a is the
## survivor and is asked to grow.
##
## `reaction_grow(radius)` is a NEW duck-typed contract, added here rather than
## demanded of every field: a field that does not implement it simply absorbs the
## other one without swelling, which is still better than two rings overlapping.
## ZoneSpell adopting it is a two-line follow-up, not a prerequisite.
static func _field_merge(ctx: Dictionary) -> bool:
	var a: int = _caller_side(ctx, 0)         # the SURVIVOR
	var keeper: Node = _node_at(ctx, a)
	var at: Vector2 = _shape_center(_shape_at(ctx, a), ctx.get("point", Vector2.ZERO))
	var r: float = _rule_radius(ctx, 190.0)
	if keeper != null and is_instance_valid(keeper) and keeper.has_method(&"reaction_grow"):
		keeper.call(&"reaction_grow", r)
	# Sized to the MERGED radius so the flare reads as the field swelling to its
	# new edge, which is the only cue the player gets that anything happened.
	_flash(ctx, at, r, 30, 0.6, Vector2.ZERO, 180.0, false)
	if bool(ctx.get("spawn_effects", true)):
		Juice.shake_camera(MINOR_SHAKE * 0.4)
		_reaction_sfx("field_merge", -4.0, 0.0)
	_spend(ctx)
	return true


## WARD_ABSORB — a protective spell doing the one thing the three barrier rungs
## cannot say: EATING the spell without being spent by it. The row consumes the
## attacker and leaves the ward standing; this tells the ward it just paid, so it
## can burn a charge and get visibly weaker.
##
## `reaction_absorb(at)` is duck-typed like everything else, and a ward that does
## not implement it degrades into an indestructible screen — which is exactly why
## the AegisWard test asserts the charge actually goes down.
static func _ward_absorb(ctx: Dictionary) -> bool:
	var b: int = _caller_side(ctx, 1)         # the row's form_b is the WARD
	var ward: Node = _node_at(ctx, b)
	var p: Vector2 = ctx.get("point", Vector2.ZERO)
	if ward != null and is_instance_valid(ward) and ward.has_method(&"reaction_absorb"):
		ward.call(&"reaction_absorb", p)
	_flash(ctx, p, _rule_radius(ctx, 90.0), 26, 0.36)
	if bool(ctx.get("spawn_effects", true)):
		Juice.hit_stop(MINOR_HITSTOP * 0.6)
		Juice.shake_camera(MINOR_SHAKE * 0.6)
		# The shared parry ding: a ward holding and a blade parrying are the same
		# verb from the player's side, so they should sound like it.
		_reaction_sfx("ward_absorb", -1.0, 0.0)
	_spend(ctx)
	return true


## BANISH — the maker's holy-vs-shadow, and the ONLY reaction in this file that is
## an erasure rather than an explosion. Light meets a field of dark and the dark
## simply stops being there: the field is spent, bodies standing in it are burned
## by the radiance, and NOTHING IS THROWN.
##
## Three deliberate absences, each one a thing every neighbouring outcome does:
##   * NO KNOCKBACK. `_radial`'s shove argument is left at zero — the one outcome
##     here with no push at all. It sits in the same bucket as `void_charged`,
##     whose entire identity is an inverted shove, so a banish that also moved
##     bodies would read as its neighbour with a different tint.
##   * NO DEBRIS, no shards, no scorch. There is no material to leave behind. That
##     is the difference between unmaking a shadow and breaking an ice wall, and it
##     is the cue that tells the player which of the two they just did.
##   * NO PostProcess.shock. Again `void_charged`'s signature, one row down.
##
## THE DAMAGED AREA IS THE FIELD'S OWN SHAPE, not an authored blast — the same
## trick `_supercharge` uses, and the cheapest possible way to honour "the spells
## shouldn't be able to get out the radius": the thing being drawn IS the thing
## being damaged, by construction. A row that named a radius would immediately be
## a second description of the field's size, free to drift from it.
static func _banish(ctx: Dictionary) -> bool:
	var b: int = _caller_side(ctx, 1)         # the row's form_b is the FIELD
	var fshape: Dictionary = _shape_at(ctx, b)
	var at: Vector2 = _shape_center(fshape, ctx.get("point", Vector2.ZERO))
	var r: float = _shape_reach(fshape, _rule_radius(ctx, BANISH_FALLBACK_RADIUS))
	# The ailment carried is the LIGHT'S, never the dark's — you are burned by the
	# radiance that cleared the field, not weakened by the shadow that just left.
	# Same rule `_shatter_barrier` follows: the attacker names the ailment.
	_radial(ctx, at, r, _rule_damage(ctx), _element_at(ctx, _caller_side(ctx, 0)), 0.0)
	if bool(ctx.get("spawn_effects", true)):
		var host: Node = _stage_parent(ctx)
		if host != null:
			# Slow, damped, short-travel motes seeded across the footprint: light
			# SETTLING into the volume the dark occupied. Speeds are fractions of
			# the field's own radius so the bloom is bounded by the same number the
			# damage is — the visual half of the reach contract, kept by hand here
			# because `_flash` is tuned to spray outward (see the BANISH_* block).
			CombatVfx.spawn_burst(
				host, at, BANISH_CORE, BANISH_EDGE,
				BANISH_MOTES, BANISH_LIFE,
				r * BANISH_SPEED_MIN_FRAC, r * BANISH_SPEED_MAX_FRAC,
				0.9, 2.6, BANISH_DAMPING, BANISH_DAMPING, true)
		Juice.hit_stop(MINOR_HITSTOP)
		Juice.shake_camera(BANISH_SHAKE)
		# WANTED: a dedicated `reaction_banish` key — a rising choral swell with no
		# transient, the opposite shape to every impact in the bank. Using the
		# existing `holy` stem until the sound pass lands one; an unknown key warns
		# and bails in Sfx.play, and a warning on a clean boot is a real cost.
		_reaction_sfx("banish", 0.0, 0.02)
	_spend(ctx)
	return true


## Autoloads are NOT registered under `--script`, so naming `Sfx` directly here is
## a COMPILE error in every headless suite that reaches this file — and because
## GDScript fails the whole dependency chain, one such reference took down the
## Hollow Purple suite entirely rather than just muting a sound. Reaching the
## autoload through the tree keeps the clash audible in game and silent (not
## fatal) in tests. Same idiom as SpellDeflect._sfx.
## An outcome's OWN sound, resolved from the audio roster rather than hardcoded at
## the call site. Every reaction used to reach for a near-miss from the tiny legacy
## roster — three different outcomes all played "ice" — so shattering a wall, boiling
## a field and bursting shrapnel were audibly the same event. `Sfx.REACTION_SOUND`
## maps all 18 authored outcomes, deliberately NOT as a 1:1 name map (shatter_ward
## resolves to a glass-bell break, `none` resolves to silence).
##
## An unmapped outcome resolves to "" and we play nothing, which is the correct
## failure: Sfx.play() warns-and-bails on an unknown key, and a warning on every
## reaction would be worse than a missing sound.
static func _reaction_sfx(outcome: String, volume_db: float, delay: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sfx: Node = tree.root.get_node_or_null(^"/root/Sfx")
	if sfx == null or not sfx.has_method(&"reaction_sound"):
		return
	var key: String = String(sfx.call(&"reaction_sound", outcome))
	if key == "":
		return
	sfx.call("play", key, volume_db, delay)


static func _sfx(sound: String, volume_db: float, delay: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sfx: Node = tree.root.get_node_or_null(^"/root/Sfx")
	if sfx != null and sfx.has_method(&"play"):
		sfx.call("play", sound, volume_db, delay)


## An element's tint, tolerating the elementless case. SpellReactor refuses to
## register an effect with element < 0, so this only guards against a future
## caller building a ctx by hand.
static func _element_color(element: int) -> Color:
	return Elements.color(element) if element >= 0 else Color(1.0, 1.0, 1.0)


## Somewhere in the tree to hang a reaction's spectacle: either participant's
## parent, then the current scene. Same fallback chain _hollow_purple walks, and
## for the same reason — a spectacle whose parent is momentarily unusable is not
## a reason to abandon a reaction that has already been decided.
static func _stage_parent(ctx: Dictionary) -> Node:
	for side: String in ["a", "b"]:
		var n: Node = ctx.get(side) as Node
		if n != null and is_instance_valid(n):
			var p: Node = n.get_parent()
			if p != null and p.is_inside_tree():
				return p
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var cur: Node = tree.current_scene
	return cur if cur != null and cur.is_inside_tree() else null


# ------------------------------------------------------------ HOLLOW PURPLE

## Two beams of OPPOSING elements fuse. Both are absorbed into a magic circle,
## and the result erupts out of it in a line.
##
## WHERE the circle opens, and which way it fires, depends on whose beams these
## are — and that is the only place ownership is consulted, because the table
## already decided the rule applies:
##   SAME owner (the headline self-combo) — the circle opens a fixed distance in
##     FRONT of the caster along their aim, and fires along that aim. There is no
##     meaningful bisector when both beams leave the same muzzle.
##   DIFFERENT owners (the rarer crossing) — the circle opens at the geometric
##     crossing and fires along the two beams' angle bisector.
static func _hollow_purple(ctx: Dictionary) -> bool:
	var reactor: Node = ctx["reactor"]
	# Global one-shot: one annihilation owns the screen at a time.
	if reactor.call(&"hollow_purple_live"):
		return false
	var sa: Dictionary = ctx["shape_a"]
	var sb: Dictionary = ctx["shape_b"]
	if SpellGeometry.is_circle(sa) or SpellGeometry.is_circle(sb):
		return false
	var a0: Vector2 = sa["from"]
	var a1: Vector2 = sa["to"]
	var b0: Vector2 = sb["from"]
	var b1: Vector2 = sb["to"]
	var la: float = a0.distance_to(a1)
	var lb: float = b0.distance_to(b1)
	if la < MIN_BEAM_LENGTH or lb < MIN_BEAM_LENGTH:
		return false
	var self_combo: bool = String(ctx.get("owner_rel", "")) == "same"
	var p: Vector2 = ctx["point"]
	var axis: Vector2 = Vector2.RIGHT
	if self_combo:
		# `b` is the LATER registration, so its direction is the caster's most
		# recent aim — the one they were holding when they completed the combo.
		axis = (b1 - b0).normalized()
		p = b0 + axis * SELF_COMBO_OFFSET
	else:
		axis = SpellGeometry.bisector(sa, sb)
		var ta: float = (p - a0).dot((a1 - a0) / la) / la
		var tb: float = (p - b0).dot((b1 - b0) / lb) / lb
		if ta < CROSS_MIN_T or ta > CROSS_MAX_T or tb < CROSS_MIN_T or tb > CROSS_MAX_T:
			return false

	var node_a: Node = ctx["a"]
	var node_b: Node = ctx["b"]
	_freeze(node_a)
	_freeze(node_b)
	if not bool(ctx.get("spawn_effects", true)):
		# Detection-only mode (headless suites): the pair is spent, no spectacle.
		_consume(node_a)
		_consume(node_b)
		return true

	# Somewhere to hang the collapse. Falling back to the current scene matters:
	# returning false here USED to leave both beams frozen but neither consumed
	# nor released, so the fusion visibly seized and then simply let go — which is
	# exactly how this failed. A beam whose parent is momentarily unusable is not
	# a reason to abandon a reaction that has already committed.
	var parent: Node = node_a.get_parent()
	if parent == null or not parent.is_inside_tree():
		parent = node_b.get_parent()
	if parent == null or not parent.is_inside_tree():
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		parent = tree.current_scene if tree != null else null
	if parent == null or not parent.is_inside_tree():
		# Genuinely nowhere to stage it — hand the beams BACK rather than leaving
		# them stuck mid-seize.
		_unfreeze(node_a)
		_unfreeze(node_b)
		return false
	var rule: Dictionary = ctx["rule"]
	var hp: Node2D = (load(HOLLOW_PURPLE_PATH) as GDScript).new()
	parent.add_child(hp)
	reactor.call(&"claim_hollow_purple", hp)
	hp.call(&"begin", p, axis,
		_beam_data(node_a, sa, int(ctx["element_a"])),
		_beam_data(node_b, sb, int(ctx["element_b"])),
		rule)
	return true


## Everything the collapse needs to keep drawing a beam after the beam itself is
## gone. `_damage` / `target_group` are BeamSpell's; Object.get returns null for
## a participant that has neither, so the fallbacks keep this duck-typed.
static func _beam_data(node: Node, shape: Dictionary, element: int) -> Dictionary:
	var dmg: Variant = node.get(&"_damage")
	var grp: Variant = node.get(&"target_group")
	return {
		"from": shape["from"] as Vector2,
		"to": shape["to"] as Vector2,
		"width": float(shape["width"]),
		"element": element,
		"damage": int(dmg) if dmg != null else 40,
		"group": String(grp) if grp != null else "enemy",
		"node": node,
	}


static func _freeze(n: Node) -> void:
	if n != null and is_instance_valid(n) and n.has_method(&"reaction_freeze"):
		n.call(&"reaction_freeze")


static func _consume(n: Node) -> void:
	if n != null and is_instance_valid(n) and n.has_method(&"reaction_consume"):
		n.call(&"reaction_consume")


## Spend an effect, with ONE fallback: a barrier that predates the reaction
## contract but already knows how to die on demand.
##
## IceWall has published a public `shatter()` since before the reaction layer
## existed, and documents it as "the Phase 3 interaction hook (fire beam / boulder
## / impact destroys it early)". Honouring it means `shatter_ice_barrier` gets the
## wall's own authored death — shards, chill, ring flash — instead of a silent
## queue_free, and it costs one has_method call. `reaction_consume` always wins
## when both exist, because that is the contract and a spectacle that implements
## it has said how it wants to be spent.
static func _break(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.has_method(&"reaction_consume"):
		n.call(&"reaction_consume")
		return
	if n.has_method(&"shatter"):
		n.call(&"shatter")


## Hand a seized effect back. Only used when a committed reaction cannot be
## staged after all — without it the participant stays frozen forever and the
## fusion reads as "grabbed them, then thought better of it".
static func _unfreeze(n: Node) -> void:
	if n != null and is_instance_valid(n) and n.has_method(&"reaction_release"):
		n.call(&"reaction_release")
