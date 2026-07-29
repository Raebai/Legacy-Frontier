# Run: godot --headless --path godot-project --script tools/slice7_test_cast_style.gd
#
# THE CASTING PROCESS. A spell is not a spawn: the body throws it in that spell's
# own body language (CastStyle), the sigil opens overhead, the caster lifts
# slightly off the floor, and only THEN does the spectacle exist. The length of
# that windup is the opponent's dodge window, so these are balance numbers wearing
# animation clothes — which is exactly why they are worth pinning down.
#
# Covers, in order:
#   * the windup is per-KIND (CastStyle) scaled by TIER (SpellTier), not one number
#   * the windup actually DELAYS the spawn instead of playing alongside it
#   * high-tier casts open a sigil ABOVE the caster and lift them; jabs do neither
#   * every way a cast can end puts the hero back on the ground
#   * the sigil is HANDED OVER to the spectacle, never dismissed and respawned
#     (maker: "no spells where I summon a circle, it goes away, and then another
#     circle spawns which the spell comes out of")
#
# Driven from _physics_process, not _init or _process: Hero._process_summon calls
# move_and_slide(), which belongs in the physics step.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"windup_is_per_kind_and_tier",
	"windup_delays_the_spawn",
	"high_tier_opens_a_sigil_above_and_lifts",
	"quick_spell_stays_grounded_and_bare",
	"interrupt_puts_the_hero_down",
	"sigil_is_handed_over_not_dismissed",
	"unclaimed_sigil_is_cleaned_up",
]

var _fails: int = 0
var _completed: Dictionary = {}

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const HERO_SCRIPT_PATH: String = "res://scripts/combat/Hero.gd"
const MAGE: int = 0  # Hero.HeroClass.MAGE
## A fixed step to hand _process_summon, so the windup advances deterministically
## instead of depending on how fast the headless loop happens to run.
const STEP: float = 1.0 / 60.0
const EPSILON: float = 0.001

var _ran: bool = false


func _physics_process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_windup_is_per_kind_and_tier()
	_test_windup_delays_the_spawn()
	_test_high_tier_opens_a_sigil_above_and_lifts()
	_test_quick_spell_stays_grounded_and_bare()
	_test_interrupt_puts_the_hero_down()
	_test_sigil_is_handed_over_not_dismissed()
	_test_unclaimed_sigil_is_cleaned_up()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice7 cast-style tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice7 cast-style tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _consts() -> Dictionary:
	return (load(HERO_SCRIPT_PATH) as GDScript).get_script_constant_map()


func _make_hero(pos: Vector2) -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.configure_class(MAGE)
	hero.global_position = pos
	return hero


## Build a SpellDef whose numbers land it on a chosen shelf. SpellTier DERIVES the
## tier from cost/cooldown/cast_time rather than reading a tag, so a test spell has
## to be described the same way a real one is.
func _spell(kind: int, mp: int, cooldown: float) -> SpellDef:
	var s := SpellDef.new()
	s.kind = kind
	s.mp_cost = mp
	s.cooldown = cooldown
	s.cast_time = 0.0  # 0 = the summon windup path; > 0 would route to the channel
	return s


## Advance a running windup by `seconds` of physics steps, stopping early if the
## cast ends (fires or is interrupted) so a test never runs past what it is asking.
func _advance_summon(hero: CharacterBody2D, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0 and bool(hero.get("_summoning")):
		hero._process_summon(STEP)
		left -= STEP


## The ladder moved: it used to be `Hero.CAST_TIER_WINDUP`, and it now lives on
## `SignatureRite` because the windup is not private bookkeeping — it IS the
## opponent's dodge budget, and the rite has to report that for casters other than
## the hero. The computation is still spelled out here rather than delegated to
## `SignatureRite.windup_for()`, so this stays a test of the RULE (per-kind body
## language x per-tier commitment) instead of a function checked against itself.
func _expected_windup(spell: SpellDef) -> float:
	var pose: int = CastStyle.for_spell(spell.kind)
	return CastStyle.duration(pose) * SignatureRite.TIER_WINDUP[SpellTier.of(spell)]


## The headline of Task 2: the windup is the SPELL'S, not one hardcoded gesture.
## A wall (SLAM, 0.34 s of commitment) must not take the same time as a chain
## (LASH, 0.18 s — the flick is the whole gesture).
func _test_windup_is_per_kind_and_tier() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(1000, 1000))
	var wall: SpellDef = _spell(SpellDef.Kind.WALL, 40, 5.0)
	hero._begin_summon(wall, false, 0)
	var wall_windup: float = float(hero.get("_summon_total"))
	_expect(
		int(hero.get("_summon_pose")) == CastStyle.Pose.SLAM,
		"a wall is SLAMMED out of the ground (CastStyle drives the pose)")
	_expect(
		absf(wall_windup - _expected_windup(wall)) < EPSILON,
		"wall windup = CastStyle.duration(SLAM) * tier multiplier (got %f)" % wall_windup)
	hero._cancel_summon()

	var chain: SpellDef = _spell(SpellDef.Kind.CHAIN, 44, 3.0)
	hero._begin_summon(chain, false, 0)
	var chain_windup: float = float(hero.get("_summon_total"))
	_expect(
		int(hero.get("_summon_pose")) == CastStyle.Pose.LASH,
		"a chain FLICKS off one hand (CastStyle drives the pose)")
	_expect(
		absf(chain_windup - _expected_windup(chain)) < EPSILON,
		"chain windup = CastStyle.duration(LASH) * tier multiplier (got %f)" % chain_windup)
	hero._cancel_summon()

	_expect(
		wall_windup > chain_windup,
		"the heavier body language commits for longer — one gesture no longer fits all")
	_completes("windup_is_per_kind_and_tier")


## The windup has to GATE the spawn. If the spectacle appeared alongside the pose
## the dodge window would be fiction, which is the whole reason CastStyle's
## durations are described as balance numbers.
func _test_windup_delays_the_spawn() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(2000, 2000))
	var before: int = root.get_child_count()
	var wall: SpellDef = _spell(SpellDef.Kind.WALL, 40, 5.0)
	hero._begin_summon(wall, false, 0)
	_expect(bool(hero.get("_summoning")), "the windup is running")
	# One sigil is allowed to appear (it IS the windup); a spectacle is not.
	var during: int = root.get_child_count()
	_expect(during - before <= 1, "nothing but the sigil exists during the windup")
	_advance_summon(hero, float(hero.get("_summon_total")) * 0.5)
	_expect(
		bool(hero.get("_summoning")),
		"halfway through the windup the cast is still committed, not fired")
	hero._cancel_summon()
	_completes("windup_delays_the_spawn")


## Task 3, the maker's ask: "a magic circle + slight levitation when casting the
## more powerful spells", and "the circle should sit ABOVE".
func _test_high_tier_opens_a_sigil_above_and_lifts() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(3000, 3000))
	var wall: SpellDef = _spell(SpellDef.Kind.WALL, 40, 5.0)  # cooldown 5.0 -> HEAVY
	_expect(SpellTier.of(wall) != SpellTier.Tier.QUICK, "the test spell is above a jab")
	hero._begin_summon(wall, false, 0)
	var sigil: Node2D = hero.get("_cast_sigil")
	_expect(sigil != null, "a powerful cast opens a sigil")
	if sigil != null:
		# Clear of the HEAD, not merely above the origin (which sits at the figure's
		# middle). The rise carries a share of the sigil's own radius for exactly
		# this reason — a bigger ring that did not rise further would sink onto the
		# caster and "above" would quietly stop being true.
		_expect(
			sigil.global_position.y + float(sigil.get("radius")) < hero.global_position.y,
			"the whole sigil clears the caster, not just its centre")
	_expect(
		float(hero.get("_summon_lift_target")) > 0.0,
		"a powerful cast lifts the caster off the floor")
	# ...and the lift is a FLOURISH, not a jump: well under the hero's own height.
	_expect(
		float(hero.get("_summon_lift_target")) < 20.0,
		"the levitation stays slight")
	var base_y: float = float(hero.get("_summon_base_y"))
	_advance_summon(hero, float(hero.get("_summon_total")) * 0.6)
	if bool(hero.get("_summoning")):
		_expect(hero.global_position.y < base_y, "the caster actually leaves the ground")
	hero._cancel_summon()
	_completes("high_tier_opens_a_sigil_above_and_lifts")


## The other half of "more powerful spells": a jab opens no summoning ring and
## never hops. Nothing in the shipped library is QUICK yet, so this pins the gate
## down before a cheap signature lands and quietly inherits the ceremony.
func _test_quick_spell_stays_grounded_and_bare() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(4000, 4000))
	var jab: SpellDef = _spell(SpellDef.Kind.CHAIN, 20, 1.5)
	_expect(SpellTier.of(jab) == SpellTier.Tier.QUICK, "the test spell is a jab")
	hero._begin_summon(jab, false, 0)
	_expect(hero.get("_cast_sigil") == null, "a jab opens no sigil")
	_expect(
		is_equal_approx(float(hero.get("_summon_lift_target")), 0.0),
		"a jab never leaves the floor")
	hero._cancel_summon()
	_completes("quick_spell_stays_grounded_and_bare")


## The windup branch returns before gravity is integrated, so anything that ends a
## cast mid-lift MUST put the hero back down by hand or they hang in mid-air. Three
## endings are checked because they are three different call paths: a hit landing,
## a co-op down, and a revive.
func _test_interrupt_puts_the_hero_down() -> void:
	var wall: SpellDef = _spell(SpellDef.Kind.WALL, 40, 5.0)

	# 1. A hit shatters the windup.
	var hero: CharacterBody2D = _make_hero(Vector2(5000, 5000))
	var ground_y: float = hero.global_position.y
	hero._begin_summon(wall, false, 0)
	_advance_summon(hero, float(hero.get("_summon_total")) * 0.6)
	hero._cancel_summon()
	_expect(not bool(hero.get("_summoning")), "the interrupted cast is over")
	_expect(
		absf(hero.global_position.y - ground_y) < EPSILON,
		"an interrupted cast drops the hero back to the ground they left")
	_expect(hero.get("_cast_sigil") == null, "an interrupted cast takes its sigil with it")

	# 2. Dying / being downed mid-windup (co-op path).
	var hero2: CharacterBody2D = _make_hero(Vector2(6000, 6000))
	var ground2: float = hero2.global_position.y
	hero2._begin_summon(wall, false, 0)
	_advance_summon(hero2, float(hero2.get("_summon_total")) * 0.6)
	hero2._enter_downed()
	_expect(
		absf(hero2.global_position.y - ground2) < EPSILON,
		"going down mid-windup does not leave a corpse floating")

	# 3. Revive while a windup is somehow still live.
	var hero3: CharacterBody2D = _make_hero(Vector2(7000, 7000))
	var ground3: float = hero3.global_position.y
	hero3._begin_summon(wall, false, 0)
	_advance_summon(hero3, float(hero3.get("_summon_total")) * 0.6)
	hero3.revive()
	_expect(
		absf(hero3.global_position.y - ground3) < EPSILON,
		"a revive mid-windup restores normal footing")
	_completes("interrupt_puts_the_hero_down")


## The duplicate-circle bug the maker reported is a sigil being DISMISSED at the end
## of the windup while the spectacle opens a fresh one. So a fired cast must OFFER
## its live sigil (MagicCircle's protocol) rather than vanish it, and a spectacle
## adopting on the same frame must get that very node back.
func _test_sigil_is_handed_over_not_dismissed() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(8000, 8000))
	hero._begin_summon(_spell(SpellDef.Kind.WALL, 40, 5.0), false, 0)
	var sigil: MagicCircle = hero.get("_cast_sigil")
	_expect(sigil != null, "the windup opened a sigil to hand over")
	hero._end_summon(true)  # the handoff path _finish_summon takes
	_expect(
		is_instance_valid(sigil) and not bool(sigil.get("_vanishing")),
		"a fired cast leaves its sigil ALIVE rather than blooming it out")
	_expect(
		hero.get("_cast_sigil") == null,
		"the caster lets go the instant it offers — the protocol owns it now")
	# Stand in for the spectacle: adopt through the real seam, hosted by a node in
	# the tree (adoption reparents, so an out-of-tree host is refused by design).
	var host := Node2D.new()
	root.add_child(host)
	var adopted: MagicCircle = MagicCircle.adopt_or_open(
		host, hero, Vector2(8100, 8000), Color.WHITE, 30.0)
	_expect(adopted == sigil, "the spectacle continues the very same sigil")
	_expect(
		MagicCircle.adopt_or_open(host, hero, Vector2.ZERO, Color.WHITE, 30.0) != sigil,
		"an offer can only be adopted once")
	_completes("sigil_is_handed_over_not_dismissed")


## ...and an interrupted cast must not wait out a TTL to clear its ring. Every
## teardown path that is NOT a successful fire withdraws instead of offering.
func _test_unclaimed_sigil_is_cleaned_up() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(9000, 9000))
	hero._begin_summon(_spell(SpellDef.Kind.WALL, 40, 5.0), false, 0)
	var sigil: MagicCircle = hero.get("_cast_sigil")
	_expect(sigil != null, "the windup opened a sigil")
	hero._cancel_summon()
	_expect(hero.get("_cast_sigil") == null, "the caster dropped it")
	_expect(
		bool(sigil.get("_vanishing")),
		"an interrupted cast blooms its sigil out instead of leaving it hanging")
	_expect(
		MagicCircle.adopt_or_open(root, hero, Vector2.ZERO, Color.WHITE, 30.0) != sigil,
		"a withdrawn sigil is not left on offer for the next spell to inherit")
	_completes("unclaimed_sigil_is_cleaned_up")
