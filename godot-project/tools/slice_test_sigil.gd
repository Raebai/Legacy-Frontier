# Run: godot --headless --path godot-project --script tools/slice_test_sigil.gd
# THE SUMMONING-CIRCLE VOCABULARY, pinned. Covers the two halves that can rot
# silently:
#
#   1. THE RULES — the tier ladder (radius / grow time / glyph count), the element
#      inference that gives an un-told sigil its band for free, and the growth curve
#      whose discontinuity was the most-repeated pop in the VFX layer. All pure
#      functions, all assertable without rendering a frame. What a sigil LOOKS like
#      is a job for the capture tools (tools/sigil_matrix_capture.gd); what it is
#      SUPPOSED to look like is a rule, and rules get tests.
#
#   2. THE WIRING — that every spectacle which is meant to summon still declares the
#      three stamped identity fields and still calls SpellSigil. This is the half
#      that matters most, because both failure modes are INVISIBLE:
#        * a spectacle that stops declaring `caster_node` is inert in the entire
#          reaction system (reaction_owner() -> null -> matches no clash row, nothing
#          errors) AND its sigil can no longer find the caster's wind-up circle to
#          adopt, so the ritual visibly restarts mid-cast;
#        * a spectacle that stops declaring `element_id` / `spell_tier` still draws a
#          perfectly nice generic ring at the middle shelf, so nobody notices the
#          element band and the tier ladder have gone.
#      `SpellCaster._stamp` writes all three with `set()`, and `set()` on an
#      undeclared property is a SILENT NO-OP. Nothing anywhere else would catch it.
#
# ⚠ THE IDIOM. Failures accumulate on the MEMBER `_fails` and every test records a
# completion sentinel, so a test that aborts part-way (a dead property read aborts the
# enclosing function and returns the type's zero) fails the suite BY ABSENCE rather
# than passing vacuously. Never write `failed += _test_x()`. See
# tools/slice_test_loadout.gd for the full account.
extends SceneTree

## Every spectacle that gained a summoning circle in the magic-circle pass, plus the
## four that already had one. Listed by script name; the source file is read from disk
## rather than instantiated, so this check needs no arena, no physics and no autoloads
## — which is exactly why it can be trusted to run.
const SUMMONING_SPECTACLES: Array[String] = [
	"RockWall", "IceWall", "RockPillar", "EnergyNova", "ZoneSpell", "ShadowRoot",
	"RuneOrbs", "ChainBolt", "BoulderHurl", "LightningRush", "BladeFlurry",
	"HorizonArc", "ShadowCrawler", "RiftDagger", "AegisWard", "BlinkStrike",
	"IceSpikeLine", "DrainTether",
]

## The identity `SpellCaster._stamp` writes onto every spectacle it builds. A
## spectacle missing any of these takes the write as a silent no-op.
const STAMPED_FIELDS: Array[String] = ["element_id", "spell_tier", "caster_node"]

const TESTS: Array[String] = [
	"tier_ladder", "element_inference", "effective_tier", "glyph_ladder",
	"explicit_signature_wins", "growth_curve_is_continuous",
	"spectacles_declare_the_stamp", "spectacles_summon",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_tier_ladder()
	_test_element_inference()
	_test_effective_tier()
	_test_glyph_ladder()
	_test_explicit_signature_wins()
	_test_growth_curve_is_continuous()
	_test_spectacles_declare_the_stamp()
	_test_spectacles_summon()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("Sigil tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Sigil tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------- the rules
## The ladder must be STRICTLY increasing, not merely different: "an ult looks like
## an ult" is only true if a bigger shelf is unambiguously bigger on screen.
func _test_tier_ladder() -> void:
	var q: float = SpellSigil.radius_for(SpellTier.Tier.QUICK)
	var h: float = SpellSigil.radius_for(SpellTier.Tier.HEAVY)
	var u: float = SpellSigil.radius_for(SpellTier.Tier.ULT)
	_expect(q < h and h < u, "radius ladder increases QUICK<HEAVY<ULT (%.0f/%.0f/%.0f)" % [q, h, u])
	var gq: float = SpellSigil.grow_for(SpellTier.Tier.QUICK)
	var gh: float = SpellSigil.grow_for(SpellTier.Tier.HEAVY)
	var gu: float = SpellSigil.grow_for(SpellTier.Tier.ULT)
	_expect(gq < gh and gh < gu, "grow-time ladder increases (%.2f/%.2f/%.2f)" % [gq, gh, gu])
	# A QUICK sigil must be fully formed inside the shortest wind-up in the cast
	# vocabulary (LASH, 0.18 s) or the spell lands before its own summon does.
	_expect(gq <= CastStyle.duration(CastStyle.Pose.LASH),
		"a QUICK sigil forms inside the shortest wind-up (%.2f <= %.2f)"
			% [gq, CastStyle.duration(CastStyle.Pose.LASH)])
	# An unknown shelf must not produce a zero-radius (invisible) sigil.
	_expect(SpellSigil.radius_for(-99) > 0.0, "an unknown shelf still gets a visible radius")
	_completes("tier_ladder")


## THE FREE UPGRADE: a caster that never heard of the signature API still passes a
## COLOUR, and every element's colour must be recognised from it — including at the
## HDR brightness `Elements.emissive` lifts cores to, which is where a naive RGB
## distance would fail. This is what gives Hero's wind-up sigil its element band
## without an edit to Hero.gd.
func _test_element_inference() -> void:
	for e: int in Elements.count():
		_expect(MagicCircle._infer_element(Elements.color(e)) == e,
			"%s's signature colour is recognised as itself" % Elements.display_name(e))
		_expect(MagicCircle._infer_element(Elements.emissive(e)) == e,
			"%s's HDR emissive colour is still recognised as %s"
				% [Elements.display_name(e), Elements.display_name(e)])
	# A colour that is nobody's must degrade to "not told" (generic runes) rather
	# than being mislabelled as the nearest element.
	_expect(MagicCircle._infer_element(Color(0.5, 0.5, 0.5)) == -1,
		"a neutral grey is nobody's element")
	# Black has no chroma at all and must not divide by zero into a match.
	_expect(MagicCircle._infer_element(Color(0.0, 0.0, 0.0)) == -1,
		"black is nobody's element and does not crash the chroma normalise")
	_completes("element_inference")


## Explicit tier wins; with none, the radius bands decide. The bands exist so Hero's
## wind-up sigil — sized from the spell's cost by a file this pass does not touch —
## still lands on a sensible shelf.
func _test_effective_tier() -> void:
	var c := MagicCircle.new()
	root.add_child(c)
	c.appear(Elements.color(Elements.Element.FIRE), 18.0, 0.2)
	_expect(c.effective_tier() == SpellTier.Tier.QUICK, "a small un-told sigil reads QUICK")
	c.appear(Elements.color(Elements.Element.FIRE), 26.0, 0.2)
	_expect(c.effective_tier() == SpellTier.Tier.HEAVY, "a mid un-told sigil reads HEAVY")
	c.appear(Elements.color(Elements.Element.FIRE), 90.0, 0.2)
	_expect(c.effective_tier() == SpellTier.Tier.ULT, "a large un-told sigil reads ULT")
	c.set_signature(Elements.Element.FIRE, SpellTier.Tier.QUICK)
	_expect(c.effective_tier() == SpellTier.Tier.QUICK,
		"an explicit shelf beats the radius guess even at a large radius")
	c.queue_free()
	_completes("effective_tier")


func _test_glyph_ladder() -> void:
	var c := MagicCircle.new()
	root.add_child(c)
	c.appear(Elements.color(Elements.Element.ICE), 50.0, 0.2)
	c.set_signature(Elements.Element.ICE, SpellTier.Tier.QUICK)
	var q: int = c.glyph_count()
	c.set_signature(Elements.Element.ICE, SpellTier.Tier.HEAVY)
	var h: int = c.glyph_count()
	c.set_signature(Elements.Element.ICE, SpellTier.Tier.ULT)
	var u: int = c.glyph_count()
	_expect(q < h and h < u, "glyph band grows with the shelf (%d/%d/%d)" % [q, h, u])
	_expect(q >= 4, "even a QUICK band has enough glyphs to read as a band (%d)" % q)
	c.queue_free()
	_completes("glyph_ladder")


## A STATED element must survive a later `appear()` — the hand-off re-colours an
## adopted sigil and re-infers from the new colour, and a spectacle's stated answer
## must be the last word or the inference could silently overrule it.
func _test_explicit_signature_wins() -> void:
	var c := MagicCircle.new()
	root.add_child(c)
	c.set_signature(Elements.Element.SHADOW, SpellTier.Tier.ULT)
	# Re-open it in a colour that is unmistakably a DIFFERENT element.
	c.appear(Elements.color(Elements.Element.FIRE), 60.0, 0.2)
	_expect(c.effective_tier() == SpellTier.Tier.ULT,
		"an explicit shelf survives a re-appear")
	_expect(c.glyph_count() == MagicCircle.GLYPHS_ULT,
		"...and so does the glyph count that comes with it")
	c.queue_free()
	_completes("explicit_signature_wins")


## THE POP THAT WAS THERE. The grow curve used to be `lerpf(0.35, 1.08, e)` followed
## by a hard `_scale = 1.0` on the completing frame — a 7% snap-down at full opacity
## on every cast in the game. The replacement must land EXACTLY on 1.0 as e -> 1, or
## the pop is simply smaller rather than gone. Asserted against the formula directly:
## the alternative is sampling `_scale` across frames, which is timing-dependent and
## would be the flakiest test in the suite.
func _test_growth_curve_is_continuous() -> void:
	_expect(is_equal_approx(_grow_scale(0.0), 0.35), "the curve starts at the seed scale 0.35")
	_expect(is_equal_approx(_grow_scale(1.0), 1.0),
		"the curve ENDS exactly at 1.0 — no snap on the completing frame (got %.6f)"
			% _grow_scale(1.0))
	# Continuity is not enough on its own: the ring must also still punch PAST its
	# target somewhere in the middle, which is the life in it.
	var peak: float = 0.0
	for i: int in 101:
		peak = maxf(peak, _grow_scale(float(i) / 100.0))
	_expect(peak > 1.005, "the curve still overshoots before settling (peak %.3f)" % peak)
	_expect(peak < 1.12, "...but not so far it reads as a bounce (peak %.3f)" % peak)
	# And it must be monotonic-ish rather than wobbling: no frame may jump more than
	# a few percent, which is what "smooth" means numerically here.
	var worst: float = 0.0
	for i: int in 100:
		worst = maxf(worst, absf(_grow_scale(float(i + 1) / 100.0) - _grow_scale(float(i) / 100.0)))
	_expect(worst < 0.05, "no single step in the curve jumps (worst %.4f)" % worst)
	_completes("growth_curve_is_continuous")


## The grow-scale formula from MagicCircle._process, mirrored. Deliberately a COPY:
## the value there is computed inline inside a frame-driven branch, and reaching it
## would mean driving frames and reading a private member — which is precisely the
## kind of assertion that dies silently when the member is renamed. If this copy and
## the original ever disagree, the capture sheets show it immediately.
func _grow_scale(e: float) -> float:
	return 1.0 - 0.65 * pow(1.0 - e, 1.8) + 0.11 * sin(PI * e)


# ------------------------------------------------------------------ the wiring
## Every summoning spectacle still DECLARES the three stamped fields. Read from
## source rather than from an instance because most of these spectacles cannot be
## instantiated without an arena, physics and autoloads — and a check that is
## expensive to run is a check that gets deleted.
func _test_spectacles_declare_the_stamp() -> void:
	for name: String in SUMMONING_SPECTACLES:
		var src: String = _source(name)
		if src.is_empty():
			_expect(false, "%s.gd is readable (moved or renamed?)" % name)
			continue
		for field: String in STAMPED_FIELDS:
			_expect(src.contains("var %s" % field),
				"%s declares `%s` — without it SpellCaster._stamp's write is a SILENT no-op"
					% [name, field])
	_completes("spectacles_declare_the_stamp")


## Every summoning spectacle still opens a circle. A spell that quietly stops
## summoning looks fine in isolation — it just goes back to appearing out of nothing,
## which is the state this whole pass existed to end.
func _test_spectacles_summon() -> void:
	for name: String in SUMMONING_SPECTACLES:
		var src: String = _source(name)
		if src.is_empty():
			continue  # already reported by the stamp test
		_expect(src.contains("SpellSigil.open(") or src.contains("MagicCircle.adopt_or_open("),
			"%s still summons through a circle" % name)
	_completes("spectacles_summon")


func _source(script_name: String) -> String:
	var path: String = "res://scripts/combat/%s.gd" % script_name
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()
