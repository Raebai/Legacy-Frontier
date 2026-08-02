# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_friendly_fire.gd
#
# FRIENDLY FIRE — the spec's social engine, and the audit that had to come with it.
#
# The feature itself is one substitution: `SpellCaster._stamp` writes the shared
# `mortal` group instead of the caster's faction, and ~23 spectacles that each scan
# exactly one group start finding everybody. What that substitution ALSO does is
# delete a guarantee nobody had ever had to think about — "a spell cannot hit its own
# caster" used to be true by construction, because a hero's spells scanned `"enemy"`
# and a hero is not in `"enemy"`. It is not true any more: most effects originate at
# the caster's own feet, and the caster is now standing in the group being scanned.
#
# WHAT THIS SUITE PINS
#   1. POLICY — the stamp widens to `mortal` with friendly fire on and restores the
#      faction verbatim with it off (so the off switch is real, not decorative).
#   2. MEMBERSHIP — a hero joins `mortal` WITHOUT losing `hero`. Dropping `hero` to
#      "tidy up" would silently break ~40 scans (camera framing, party-wipe, enemy
#      target selection); this is the group-drift trap that has bitten twice.
#   3. THE SEAM — `owner_of()` across all four spellings the codebase uses, and
#      `hostiles()` removing exactly one node and no others.
#   4. THE SWEEP — every spell in the library, cast by a real Hero, must leave its own
#      caster on full HP. This is the audit made mechanical.
#   5. IT ACTUALLY HITS YOUR FRIEND — the point of the whole feature.
#   6. MELEE SANITY — the arc lands on a team-mate you aimed at; the auto-target
#      never reaches for one you did not.
#
# ⚠ THE SWEEP IS CANARY-GUARDED, AND THAT IS THE WHOLE REASON IT MEANS ANYTHING.
# "The caster took no damage" is trivially true for a spell that damaged NOTHING —
# a spectacle that silently failed to fire, or a frame budget too short for its
# windup, would pass this test while proving nothing at all. So every cast also puts
# a plain `mortal` body at the CASTER'S EXACT POSITION. If the canary is hit and the
# caster is not, the effect's damage volume genuinely covered the caster and the
# exclusion did the work. Spells whose canary is never hit are counted and reported
# as UNPROVEN rather than counted as passes, and the suite fails if the proven count
# collapses — so this cannot quietly rot into a no-op.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read ABORTS the enclosing function in GDScript and hands the caller
# the return type's zero. Failures therefore accumulate on the MEMBER `_fails`, and
# every test records a completion sentinel as its last line, so a test that aborts
# part-way fails the suite BY ABSENCE rather than passing silently.

const TESTS: Array[String] = [
	"stamp_policy",
	"hero_joins_mortal_without_losing_hero",
	"owner_of_reads_every_spelling",
	"hostiles_removes_exactly_the_caster",
	"pool_excludes_the_caster_via_ctx",
	"no_spectacle_scans_its_group_bare",
	"a_spell_hits_the_other_hero",
	"no_spell_in_the_library_hits_its_own_caster",
	"melee_hits_a_teammate_you_aimed_at",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
const COMBAT_DIR: String = "res://scripts/combat"

## How long each spell in the sweep is given to do its worst, in accumulated
## `_process` delta. Short on purpose: the DANGEROUS window for self-damage is the
## opening frames, when the effect is still sitting on the muzzle it left. A longer
## budget would only add wall-clock for the placed bombardments, whose landing point
## is out at the aim anyway.
const SWEEP_SECONDS: float = 0.5
const SWEEP_FRAME_CAP: int = 4000

## Below this many spells CANARY-CONFIRMED as covering the caster's own position, the
## sweep has stopped proving anything and the suite says so. Measured, not guessed:
## the instant self-originating family (nova / beam / rush / chain / missiles / flurry
## / crawler / walls / tether / arc / ward / blink) all cover their own muzzle inside
## the budget. Set well under the observed count so a single retune does not turn this
## into a flake, but high enough that a wholesale regression cannot slip past.
const MIN_PROVEN_SPELLS: int = 6


## A bare damageable body in the `mortal` group. No rig, no silhouette, no
## `hit_margin` — which is exactly the `DEFAULT_HIT_MARGIN = 0.0` fallback path
## `SpellTargets` documents, so it is hit on the same terms every crate is.
class Mortal extends Node2D:
	var taken: int = 0

	func _ready() -> void:
		add_to_group("mortal")

	func take_damage(amount: int) -> void:
		taken += amount

	func apply_knockback(_v: Vector2) -> void:
		pass

	func apply_status(_e: int, _c: bool = true) -> void:
		pass


## Four stubs, one per name this codebase uses for "who cast this". `owner_of` has to
## answer for all of them or the exclusion is only as good as whichever spelling the
## spectacle happened to pick.
class OwnerStubA extends Node2D:
	var caster_node: Node = null
class OwnerStubB extends Node2D:
	var _caster: Node = null
class OwnerStubC extends Node2D:
	var _owner: Node = null
class OwnerStubD extends Node2D:
	var caster: Node = null


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_stamp_policy()
	_test_hero_joins_mortal()
	_test_owner_of()
	_test_hostiles()
	_test_pool_ctx()
	_test_no_bare_group_scans()
	_test_spell_hits_the_other_hero()
	_test_sweep_no_self_damage()
	_test_melee_teammate_rules()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Friendly-fire tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Friendly-fire tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort survives the abort instead of being discarded with its result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------- 1. policy
func _test_stamp_policy() -> void:
	var was: bool = SpellCaster.friendly_fire
	_expect(was, "friendly fire ships ON — it is the spec's social engine, not an option")
	_expect(String(SpellCaster.damage_group(&"enemy")) == "mortal",
		"friendly fire on -> an enemy-hostile attack scans `mortal`")
	_expect(String(SpellCaster.damage_group(&"hero")) == "mortal",
		"...and so does a hero-hostile one — one group, everybody in it")
	# Idempotent, so converting at more than one layer is safe. Hero passes an already
	# converted group into `SpellCaster.cast`, which stamps it again.
	_expect(String(SpellCaster.damage_group(SpellCaster.MORTAL_GROUP)) == "mortal",
		"damage_group is idempotent (Hero converts, then the stamp converts again)")
	SpellCaster.friendly_fire = false
	_expect(String(SpellCaster.damage_group(&"enemy")) == "enemy",
		"friendly fire off -> the faction is honoured verbatim (the switch is real)")
	_expect(String(SpellCaster.damage_group(&"team_b")) == "team_b",
		"...for a bot faction group too")
	SpellCaster.friendly_fire = was
	_completes("stamp_policy")


# --------------------------------------------------------------- 2. membership
func _test_hero_joins_mortal() -> void:
	var hero: CharacterBody2D = _make_hero(Vector2(-40000.0, 0.0))
	_expect(hero.is_in_group("mortal"), "a hero joins `mortal` so spells can find them")
	# ADDED, NOT SWAPPED. `hero` is identity and is scanned by the camera's framing,
	# Encounter's party-wipe check, Enemy target selection and Arena's spawn logic.
	_expect(hero.is_in_group("hero"),
		"...and KEEPS `hero` — dropping it would silently break ~40 unrelated scans")
	_expect(String(hero.call("attack_group")) == "mortal",
		"a hero's attacks scan `mortal` while friendly fire is on")
	# Faction is untouched: bots steer by it and `Spell._damage_hero` reasons about it.
	_expect(String(hero.get("hostile_group")) == "enemy",
		"...while `hostile_group` still reports the FACTION, unwidened")
	hero.queue_free()
	_completes("hero_joins_mortal_without_losing_hero")


# ---------------------------------------------------------------- 3+4+5. the seam
func _test_owner_of() -> void:
	var who := Node2D.new()
	root.add_child(who)
	for stub: Node2D in [OwnerStubA.new(), OwnerStubB.new(), OwnerStubC.new(), OwnerStubD.new()]:
		root.add_child(stub)
		for field: String in ["caster_node", "_caster", "_owner", "caster"]:
			if stub.get(field) != null or _declares(stub, field):
				stub.set(field, who)
		_expect(SpellTargets.owner_of(stub) == who,
			"owner_of reads the caster off a %s" % stub.get_class())
		stub.queue_free()
	_expect(SpellTargets.owner_of(null) == null, "owner_of(null) is null, not a crash")
	var plain := Node2D.new()
	root.add_child(plain)
	_expect(SpellTargets.owner_of(plain) == null,
		"a node with no caster field answers null (so every caller is a no-op)")
	plain.queue_free()
	who.queue_free()
	_completes("owner_of_reads_every_spelling")


func _test_hostiles() -> void:
	var spell := OwnerStubA.new()
	root.add_child(spell)
	var caster := Mortal.new()
	var other := Mortal.new()
	var third := Mortal.new()
	for m: Mortal in [caster, other, third]:
		root.add_child(m)
	spell.caster_node = caster
	var found: Array = SpellTargets.hostiles(spell, &"mortal")
	_expect(not found.has(caster), "hostiles() drops the spectacle's own caster")
	_expect(found.has(other) and found.has(third),
		"...and drops NOBODY else — the filter is subtractive by exactly one")
	# No caster: the raw group, unchanged. Adopting hostiles() must never be able to
	# REMOVE a target the old bare scan would have found.
	spell.caster_node = null
	var raw: Array = SpellTargets.hostiles(spell, &"mortal")
	_expect(raw.has(caster) and raw.has(other) and raw.has(third),
		"with no caster, hostiles() is the raw group scan verbatim")
	for n: Node in [spell, caster, other, third]:
		n.queue_free()
	_completes("hostiles_removes_exactly_the_caster")


## The backstop for the three spectacles (EnergyNova, MeteorSigil, StarConvergence)
## that call the selectors with a LITERAL empty skip list. `ctx` was already being
## passed for the line-of-sight rays, so deriving the caster from it fixes them
## without touching a single call site.
func _test_pool_ctx() -> void:
	var spell := OwnerStubA.new()
	root.add_child(spell)
	var caster := Mortal.new()
	var victim := Mortal.new()
	root.add_child(caster)
	root.add_child(victim)
	caster.global_position = Vector2(-50000.0, 0.0)
	victim.global_position = Vector2(-50000.0, 0.0)  # same point: both inside any radius
	spell.caster_node = caster
	var hit: Array = SpellTargets.in_radius(caster.global_position, 120.0,
		get_nodes_in_group("mortal"), [], spell, false)
	_expect(not hit.has(caster),
		"an EMPTY skip list still excludes the caster, derived from ctx")
	_expect(hit.has(victim), "...and the body standing on the same spot is still hit")
	for n: Node in [spell, caster, victim]:
		n.queue_free()
	_completes("pool_excludes_the_caster_via_ctx")


# ------------------------------------------------- 6. the structural regression net
## THE AUDIT, FROZEN. Eighteen of twenty-three spectacles scanned their faction group
## bare — `get_tree().get_nodes_in_group(target_group)` with no caster anywhere near
## the call — because until friendly fire landed they never needed to. A behavioural
## test can only catch the ones whose damage volume happens to cover the caster inside
## a frame budget; this catches the SHAPE, in every spectacle, forever, including ones
## that do not exist yet.
##
## Scans the SOURCE for the same reason the banned-IP-names sweep does: the mistake is
## expressible in a file that no test currently instantiates.
func _test_no_bare_group_scans() -> void:
	const BARE: Array[String] = [
		"get_nodes_in_group(target_group)",
		"get_nodes_in_group(_target_group)",
	]
	## Allowed to keep the bare form because the caster is excluded on the very next
	## line, by a `skip` array the call site builds explicitly. Named individually so
	## adding a file here is a deliberate act with a reason attached.
	const EXEMPT: Dictionary = {
		# skip = [caster_node] / [_caster] / [_owner], passed straight to the selector.
		"BladeFlurry.gd": true, "BlastSpell.gd": true, "BlinkStrike.gd": true,
		"BoulderHurl.gd": true, "RiftDagger.gd": true, "RockPillar.gd": true,
		# `[caster_node]` in the skip argument on the same statement.
		"MeteorSigil.gd": true, "StarConvergence.gd": true, "EnergyNova.gd": true,
		# The two seam files THEMSELVES. They are where the rule is defined and
		# documented, so the pattern appears in their prose and in `hostiles()`'s own
		# implementation — which is the one place it is supposed to appear.
		"SpellCaster.gd": true, "SpellTargets.gd": true,
		# ── THE DROP ECONOMY (Tier 2 / Tier 3). These five scan bare ON PURPOSE, and
		# each one is a spec requirement rather than a forgotten skip list. They are
		# named individually, with the reason, exactly as this table asks.
		#   GravityFlip   — "inverts gravity 5s, CASTER INCLUDED". A flip with a hole
		#                   in it where the caster stands is not the spell.
		#   Chronostasis  — "your teammate is frozen too", and so is the caster: it
		#                   stops time in a PLACE, not for a side.
		#   Equinox       — levels "you, your friend, and the thing you are fighting".
		#                   Excluding the caster would make it a heal with extra steps.
		#   VoidCollapse  — the PULL is bare (a singularity that politely refuses to
		#                   tug its own summoner hands the spell a free safe spot at
		#                   its worst moment). Its DAMAGE query does route through
		#                   `SpellTargets.hostiles`.
		#   Petrify       — the bare scan is in `_launch`, which is looking for
		#                   somebody to throw the statue AWAY from. It is a direction
		#                   query, not a damage query; the damage goes through
		#                   `hostiles` on both the sweep and the shatter.
		"GravityFlip.gd": true, "Chronostasis.gd": true, "Equinox.gd": true,
		"VoidCollapse.gd": true, "Petrify.gd": true,
	}
	var dir: DirAccess = DirAccess.open(COMBAT_DIR)
	_expect(dir != null, "the combat script directory is readable for the source sweep")
	if dir == null:
		return  # bail: the _expect above failed, and the missing sentinel says so twice
	var checked: int = 0
	for fname: String in dir.get_files():
		if not fname.ends_with(".gd") or EXEMPT.has(fname):
			continue
		var f: FileAccess = FileAccess.open("%s/%s" % [COMBAT_DIR, fname], FileAccess.READ)
		if f == null:
			continue
		var src: String = ""
		# CODE ONLY. Comment lines are stripped before the search, because every file
		# that documents this rule quotes the forbidden form in prose — and a sweep
		# that cannot tell an instruction from a violation is a sweep people delete.
		for line: String in f.get_as_text().split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			src += line + "\n"
		f.close()
		for bad: String in BARE:
			if src.contains(bad):
				_expect(false,
					("%s scans its faction group BARE (`%s`). Under friendly fire that "
					+ "group contains the caster — route it through "
					+ "SpellTargets.hostiles(self, group), or add the file to EXEMPT "
					+ "with the skip-list line that justifies it.") % [fname, bad])
		checked += 1
	_expect(checked > 40, "the source sweep actually read the combat scripts (got %d)" % checked)
	_completes("no_spectacle_scans_its_group_bare")


# ------------------------------------------------------ 7. it hits your friend
## THE FEATURE, in one assertion. EnergyNova is the spell chosen because it is the
## single worst case in the whole audit: instant, self-CENTRED, and it was calling
## the selector with an empty skip list — so before this work a hero pressing T next
## to a team-mate would have killed both of them.
func _test_spell_hits_the_other_hero() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var here: Vector2 = Vector2(-60000.0, 0.0)
	var caster: CharacterBody2D = _make_hero(here)
	var mate: CharacterBody2D = _make_hero(here + Vector2(50.0, 0.0))
	var caster_hp: int = int(caster.get("hp"))
	var mate_hp: int = int(mate.get("hp"))

	var nova: SpellDef = _spell_by_id("void_zone")  # any def; the NOVA arm ignores most of it
	nova = SpellDef.new()
	nova.kind = SpellDef.Kind.NOVA
	nova.damage = 30
	nova.effect = "arcane"
	nova.element = Elements.Element.ARCANE
	var ok: bool = SpellCaster.cast(nova, arena, here, here + Vector2(50.0, 0.0),
		Color.WHITE, "arcane", caster, caster.call("attack_group"))
	_expect(ok, "the NOVA arm dispatched")
	# Long enough to clear EnergyNova.WINDUP_TIME (0.30) — the nova GATHERS now
	# before it goes off, so a 0.25 s advance would sample it mid-telegraph and read
	# as "friendly fire is broken". See the telegraph block in EnergyNova.gd.
	_advance(0.45)

	_expect(int(mate.get("hp")) < mate_hp,
		"FRIENDLY FIRE: a hero's nova damages the OTHER hero (this is the whole feature)")
	_expect(int(caster.get("hp")) == caster_hp,
		"...and never the caster, who is standing at its exact centre")
	for n: Node in [arena, caster, mate]:
		n.queue_free()
	_completes("a_spell_hits_the_other_hero")


# ----------------------------------------------------- 8. the whole-library sweep
## Every spell in the library, thrown by a real Hero, at a real target, with a canary
## sitting on the caster's own position. See the header for why the canary is what
## makes this mean anything.
## Spells that MAY move their own caster's health, because doing so is what the
## spell is. Named individually — the rule "no spell hits its own caster" stays in
## force for every one of the other twenty-eight, and an accident is still a
## failure; this is the short list of deliberate exceptions the drop economy added.
##   blood_pact   — "a damage buff that DRAINS YOUR OWN HP" is the whole spell. It
##                  is also the only reason the buff is allowed to be as big as it
##                  is, and you can die to it.
##   equinox      — drags every living thing to the room's mean, the caster with
##                  them. It is a leveller; a leveller with an exception is a heal.
##   chronostasis — freezes a place, not a side. The caster inside their own ring
##                  is frozen, so anything already banked against them pays out.
const SELF_AFFECTING: Dictionary = {
	"blood_pact": true, "equinox": true, "chronostasis": true,
}


func _test_sweep_no_self_damage() -> void:
	var proven: Array[String] = []
	var unproven: Array[String] = []
	var slot: int = 0
	for spell: SpellDef in SpellLibrary.build_all():
		if SELF_AFFECTING.has(spell.id):
			continue
		slot += 1
		var here: Vector2 = Vector2(-100000.0 - float(slot) * 4000.0, 0.0)
		var arena := Node2D.new()
		root.add_child(arena)
		var caster: CharacterBody2D = _make_hero(here)
		var canary := Mortal.new()
		var victim := Mortal.new()
		arena.add_child(canary)
		arena.add_child(victim)
		canary.global_position = here            # ON the caster: proves the volume covers them
		victim.global_position = here + Vector2(70.0, 0.0)
		var hp_before: int = int(caster.get("hp"))
		SpellCaster.cast(spell, arena, here, here + Vector2(70.0, 0.0),
			Color.WHITE, spell.effect, caster, caster.call("attack_group"))
		_advance(SWEEP_SECONDS)
		_expect(int(caster.get("hp")) == hp_before,
			"`%s` never damages its own caster (hp %d -> %d)"
				% [spell.id, hp_before, int(caster.get("hp"))])
		if canary.taken > 0:
			proven.append(spell.id)
		else:
			unproven.append(spell.id)
		for n: Node in [arena, caster]:
			n.queue_free()
		_advance(0.0)  # let the frees land before the next spell shares the tree
	_expect(proven.size() >= MIN_PROVEN_SPELLS,
		("the sweep is not vacuous: %d spells were CANARY-CONFIRMED to cover their own "
		+ "caster's position and excluded them anyway (need >= %d). Proven: %s")
			% [proven.size(), MIN_PROVEN_SPELLS, ", ".join(proven)])
	# Reported, never failed. A spell whose damage lands out at the aim point (the
	# placed bombardments) legitimately never reaches the caster inside the budget, and
	# turning that into a failure would only teach the next person to pad the budget.
	print("[friendly-fire sweep] self-exclusion PROVEN for %d spells; %d unproven "
		% [proven.size(), unproven.size()], unproven)
	_completes("no_spell_in_the_library_hits_its_own_caster")


# ------------------------------------------------------------- 9. melee sanity
## The asymmetry that keeps friendly fire from feeling like betrayal:
##   arc  (you pointed at them)  -> lands on a team-mate
##   auto-target (you did not)   -> never reaches for one
func _test_melee_teammate_rules() -> void:
	var here: Vector2 = Vector2(-30000.0, 0.0)
	var a: CharacterBody2D = _make_hero(here)
	var mate: CharacterBody2D = _make_hero(here + Vector2(24.0, 0.0))
	a.set_faction(&"ff_team", &"ff_foe")
	mate.set_faction(&"ff_team", &"ff_foe")
	a.set("facing", Vector2.RIGHT)
	a.set("_aim_dir", Vector2.RIGHT)
	_expect(a.call("_nearest_enemy_in_melee_range") == null,
		"the melee auto-target refuses to lock onto a team-mate (it scans the FACTION)")
	var before: int = int(mate.get("hp"))
	a.call("_on_melee_hit_frame")
	_expect(int(mate.get("hp")) < before,
		"...but a swing you AIMED at them lands — that is the feature working")

	# Behind you, outside the arc: only an auto-target could reach them, and none does.
	var back_home: Vector2 = Vector2(-31000.0, 0.0)
	var b: CharacterBody2D = _make_hero(back_home)
	var mate_back: CharacterBody2D = _make_hero(back_home + Vector2(-24.0, 0.0))
	b.set_faction(&"ff_team2", &"ff_foe2")
	mate_back.set_faction(&"ff_team2", &"ff_foe2")
	b.set("facing", Vector2.RIGHT)
	b.set("_aim_dir", Vector2.RIGHT)
	var back_before: int = int(mate_back.get("hp"))
	b.call("_on_melee_hit_frame")
	_expect(int(mate_back.get("hp")) == back_before,
		"a team-mate BEHIND you is never dragged into the swing")
	for n: Node in [a, mate, b, mate_back]:
		n.queue_free()
	_completes("melee_hits_a_teammate_you_aimed_at")


# ------------------------------------------------------------------- helpers
## A hero parked at `at` with physics OFF. The freeze matters: gravity is 2600 px/s²,
## so half a second of falling would carry the caster 325 px away from the canary
## sitting on their spawn point and quietly turn the sweep into a test of nothing.
func _make_hero(at: Vector2) -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.global_position = at
	hero.set_physics_process(false)
	return hero


func _spell_by_id(id: String) -> SpellDef:
	for s: SpellDef in SpellLibrary.build_all():
		if s.id == id:
			return s
	return null


## Does `obj` actually declare `field`? `get()` on an undeclared property answers null,
## which is indistinguishable from a declared-but-unset one — so the stub loop asks
## the property list instead of guessing.
func _declares(obj: Object, field: String) -> bool:
	for p: Dictionary in obj.get_property_list():
		if String(p["name"]) == field:
			return true
	return false


## Run the tree forward by `seconds` of accumulated frame time (frame-capped, because
## a headless main loop is unthrottled and a stalled delta must not hang the suite).
func _advance(seconds: float) -> void:
	var t: float = 0.0
	var frames: int = 0
	while t < seconds and frames < SWEEP_FRAME_CAP:
		var dt: float = 1.0 / 60.0
		if not _step(dt):
			break
		t += dt
		frames += 1


## One simulated frame. `SceneTree.process` does not exist to be driven by hand from a
## `--script` harness, so the spectacles are stepped directly: every one of them is a
## plain `Node2D` whose damage fires out of `_process` / `_physics_process`, and
## driving those with a FIXED delta is what makes this suite deterministic rather than
## dependent on how fast the machine happens to spin the main loop.
func _step(dt: float) -> bool:
	_step_node(root, dt)
	return true


func _step_node(n: Node, dt: float) -> void:
	if not is_instance_valid(n) or n.is_queued_for_deletion():
		return
	if n.has_method("_process") and n.is_processing():
		n.call("_process", dt)
	if n.has_method("_physics_process") and n.is_physics_processing():
		n.call("_physics_process", dt)
	for c: Node in n.get_children():
		_step_node(c, dt)
