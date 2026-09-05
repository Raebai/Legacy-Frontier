# Run: godot --headless --path godot-project --script tools/slice_test_spell_signature.gd
#
# Pins the two things the maker reported in the same breath:
#   1. THE CIRCLE MUST SAY WHICH SPELL IT IS. The sigil already carried element and
#      tier; the SPELL axis (`MagicCircle.Motif`, mapped in `SpellSigil`) is new, and
#      the failure mode it exists to prevent is silent — a mistyped key in the table
#      simply draws nothing, which looks fine.
#   2. A NOVA MUST NOT KILL ITS OWN CASTER, on the HERO path specifically. The
#      existing friendly-fire suite covers the `SpellCaster.cast` path, where
#      `caster_node` is stamped. The hero's T-key nova does NOT go through
#      SpellCaster — it is hand-built in `Hero._spawn_nova` — and that is exactly the
#      path that was self-damaging. Nothing was testing it.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# Failures accumulate on the MEMBER `_fails`, never on a return value: a dead member
# read ABORTS the enclosing function and hands back the zero value, so `failed +=
# _test_x()` reads as "no failures" while silently skipping every later assertion.
# Every test's last line records that it reached the end; a name missing from
# `_completed` fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"motif_table_keys_are_real_scripts",
	"motif_resolves_for_every_listed_spectacle",
	"motif_defaults_to_none_and_clamps",
	"sigil_motif_and_the_table_agree",
	"nova_windup_defers_its_damage",
	"hero_nova_never_damages_its_own_caster",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const NOVA_SCENE_PATH: String = "res://scenes/combat/EnergyNova.tscn"
const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"


## Records damage taken; joins whichever groups the caller asks for.
class StubBody:
	extends CharacterBody2D
	var damage_taken: int = 0

	func take_damage(amount: int) -> void:
		damage_taken += amount

	func apply_knockback(_vec: Vector2) -> void:
		pass


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_motif_table_keys_are_real_scripts()
	_test_motif_resolves_for_every_listed_spectacle()
	_test_sigil_motif_and_the_table_agree()
	_test_motif_defaults_to_none_and_clamps()
	_test_nova_windup_defers_its_damage()
	_test_hero_nova_never_damages_its_own_caster()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Spell-signature tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Spell-signature tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ the motif
## THE TYPO GUARD. `MOTIF_BY_SCRIPT` is keyed on script FILENAMES, which means a
## rename or a typo produces no error at all — the lookup misses, the motif comes
## back NONE, and the sigil draws exactly as it did before the table existed. This is
## the only thing that can notice.
func _test_motif_table_keys_are_real_scripts() -> void:
	var missing: Array[String] = []
	for key: String in SpellSigil.MOTIF_BY_SCRIPT.keys():
		if not FileAccess.file_exists("res://scripts/combat/%s" % key):
			missing.append(key)
	_expect(missing.is_empty(),
		"every MOTIF_BY_SCRIPT key names a real script in scripts/combat/ (missing: %s)"
		% str(missing))
	_expect(SpellSigil.MOTIF_BY_SCRIPT.size() >= 30,
		"the motif table still covers the roster (got %d entries)"
		% SpellSigil.MOTIF_BY_SCRIPT.size())
	_completes("motif_table_keys_are_real_scripts")


## The resolution path end to end: a node carrying a listed script must answer with
## that script's motif. Guards against `_motif_of` losing the script lookup — which
## would also fail silently.
func _test_motif_resolves_for_every_listed_spectacle() -> void:
	var wrong: Array[String] = []
	for key: String in SpellSigil.MOTIF_BY_SCRIPT.keys():
		var path: String = "res://scripts/combat/%s" % key
		var script: GDScript = load(path) as GDScript
		if script == null:
			wrong.append("%s (would not load)" % key)
			continue
		# `script.new()` rather than `set_script()` on a Node2D: spectacles do not all
		# share a base (`Spell` is a CharacterBody2D), and `set_script` with a
		# mismatched base silently leaves the node script-less — which resolves to
		# NONE and reads as a table bug that is really a harness bug.
		var probe: Object = script.new()
		if probe is not Node:
			wrong.append("%s (not a Node)" % key)
			continue
		var got: int = SpellSigil._motif_of(probe as Node)
		if got != int(SpellSigil.MOTIF_BY_SCRIPT[key]):
			wrong.append("%s (got %d, want %d)" % [key, got, int(SpellSigil.MOTIF_BY_SCRIPT[key])])
		(probe as Node).free()
	_expect(wrong.is_empty(), "_motif_of resolves every listed spectacle (wrong: %s)" % str(wrong))
	_completes("motif_resolves_for_every_listed_spectacle")


## An UNLISTED spectacle must degrade to NONE rather than guessing, and the circle
## must reject an out-of-range value instead of drawing garbage.
func _test_motif_defaults_to_none_and_clamps() -> void:
	var bare := Node2D.new()
	_expect(SpellSigil._motif_of(bare) == MagicCircle.Motif.NONE,
		"a node with no script and no table entry resolves to Motif.NONE")
	bare.free()

	var circle := MagicCircle.new()
	_expect(circle.motif() == MagicCircle.Motif.NONE, "a fresh MagicCircle has no motif")
	circle.set_motif(MagicCircle.Motif.DESCENT)
	_expect(circle.motif() == MagicCircle.Motif.DESCENT, "set_motif stores a valid motif")
	circle.set_motif(9999)
	_expect(circle.motif() == MagicCircle.Motif.NONE, "an out-of-range motif falls back to NONE")
	circle.set_motif(-4)
	_expect(circle.motif() == MagicCircle.Motif.NONE, "a negative motif falls back to NONE")
	circle.free()
	_completes("motif_defaults_to_none_and_clamps")


# ------------------------------------------------------------------- the nova
## THE TELEGRAPH, as a behavioural assertion rather than a drawing one: `activate_at`
## must NOT damage in the same call any more. This is the "no way of blocking it"
## half of the maker's note — if this test goes green again by returning to instant
## damage, the wind-up has been removed and the spell is unanswerable again.
func _test_nova_windup_defers_its_damage() -> void:
	var center: Vector2 = Vector2(21000.0, 3000.0)
	var victim: StubBody = _make_body(center + Vector2(60.0, 0.0), ["enemy", SpellCaster.MORTAL_GROUP])
	var nova: Node2D = _make_nova()

	nova.call("activate_at", center)
	_expect(nova.WINDUP_TIME > 0.0,
		"EnergyNova still HAS a wind-up (it is the whole telegraph — see the file header)")
	_expect(victim.damage_taken == 0,
		"a nova does not damage in the same frame it is cast — it gathers first (got %d)"
		% victim.damage_taken)
	nova.call("detonate_now")
	_expect(victim.damage_taken == nova.NOVA_DAMAGE,
		"...and lands its full damage when the gather completes (got %d)" % victim.damage_taken)
	nova.call("detonate_now")
	_expect(victim.damage_taken == nova.NOVA_DAMAGE,
		"detonate_now is idempotent — a second call cannot double-hit")
	_completes("nova_windup_defers_its_damage")


## THE MAKER'S BUG, pinned on the exact path that had it.
##
## `Hero._spawn_nova` hand-builds the spectacle and stamps only the FACTION, never
## `caster_node` — so both of `SpellTargets`' self-exclusion layers were no-ops, and
## the moment friendly fire pointed the scan at the shared `mortal` group the caster
## was a valid target standing at range zero from their own blast.
##
## This asserts the OUTCOME (the hero is unhurt) rather than the mechanism, so it
## stays true whether the fix lands in `Hero` (the one-line stamp, which is the right
## place) or in `EnergyNova`'s backstop. It must never go red again either way.
func _test_hero_nova_never_damages_its_own_caster() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.global_position = Vector2(24000.0, 3000.0)
	var hp_before: int = int(hero.get("hp"))
	var bystander: StubBody = _make_body(
		hero.global_position + Vector2(70.0, 0.0),
		["enemy", SpellCaster.MORTAL_GROUP])

	# ⚠ THE ANTI-VACUOUS GUARD. If friendly fire were off, the nova would scan
	# `"enemy"`, the hero would not be in it, and this test would pass for a reason
	# that has nothing to do with the fix. Assert the hero really is standing inside
	# the group their own nova is about to sweep — otherwise this proves nothing.
	var scanned: StringName = hero.call("attack_group")
	_expect(hero.is_in_group(scanned),
		"the caster IS in the group their own nova scans (%s) — otherwise this test is vacuous"
		% scanned)

	# ⚠ `_spawn_nova`, NOT `_nova`. The free T ability is gone (the maker asked three
	# times); the SPECTACLE is not, because the Rogue's Q whirlwind still spawns it, and
	# this invariant is about the spectacle. `_spawn_nova` is precisely the function the
	# comment above names as the one that stamps only the faction — so the test is now
	# pointed straight at the code it was always describing rather than at a wrapper.
	hero.call("_spawn_nova")
	for n: Node in root.get_children():
		if n.has_method("detonate_now"):
			n.call("detonate_now")

	_expect(int(hero.get("hp")) == hp_before,
		"a hero's own nova NEVER damages the hero who cast it (hp %d -> %d)"
		% [hp_before, int(hero.get("hp"))])
	_expect(bystander.damage_taken > 0,
		"...while still hitting everything else in the ring (the exclusion is one node, not a disable)")
	_completes("hero_nova_never_damages_its_own_caster")


# ------------------------------------------------------------------- fixtures
func _make_nova() -> Node2D:
	# Runtime load, never preload: EnergyNova references autoloads (Sfx), which are
	# only registered with GDScript after the main loop is up.
	var nova: Node2D = (load(NOVA_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(nova)
	return nova


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	return hero


func _make_body(pos: Vector2, groups: Array) -> StubBody:
	var b: StubBody = StubBody.new()
	root.add_child(b)
	b.global_position = pos
	for g: String in groups:
		b.add_to_group(g)
	return b


## ⚠ THE SPLIT-BRAIN GUARD. A spectacle may state its own figure by declaring
## `var sigil_motif`, and `_motif_of` honours that over the table — which is right,
## because the declaration lives next to the thing it describes.
##
## But `AbilityBar.glyph_for` is STATIC. It answers from a `SpellDef` with nothing
## instantiated, so it can only read the TABLE. If the two disagree, the same spell
## draws one figure when you cast it and a different one on the bar you cast it
## from — and nothing errors, because both halves are individually fine.
##
## That is not hypothetical: the first cut of the class-signature rows contradicted
## two declarations (ThousandCuts, FaultLine) and the sibling test above is what
## caught it. This makes it structural instead of lucky.
##
## The hotbar is still ALLOWED to differ, via `AbilityBar.GLYPH_OVERRIDE` — that is
## a deliberate, listed, commented decision per spell. What is banned is the two
## silently drifting apart.
func _test_sigil_motif_and_the_table_agree() -> void:
	var dir: DirAccess = DirAccess.open("res://scripts/combat")
	_expect(dir != null, "the spectacle directory is readable")
	if dir == null:
		return
	var checked: int = 0
	var wrong: Array[String] = []
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var script: GDScript = load("res://scripts/combat/%s" % file) as GDScript
		if script == null:
			continue
		var probe: Object = script.new()
		if probe is not Node:
			if probe is RefCounted:
				continue
			continue
		var stated: Variant = (probe as Node).get(&"sigil_motif")
		(probe as Node).free()
		if stated == null or int(stated) == MagicCircle.Motif.NONE:
			continue
		checked += 1
		var row: Variant = SpellSigil.MOTIF_BY_SCRIPT.get(file)
		if row == null:
			wrong.append("%s declares %d but has NO table row (the bar would draw nothing)"
				% [file, int(stated)])
		elif int(row) != int(stated):
			wrong.append("%s declares %d, table says %d" % [file, int(stated), int(row)])
	_expect(checked >= 5,
		"spectacles that state their own figure were found (%d — zero would pass vacuously)" % checked)
	_expect(wrong.is_empty(), "every declared sigil_motif matches its table row (wrong: %s)" % str(wrong))
	_completes("sigil_motif_and_the_table_agree")
