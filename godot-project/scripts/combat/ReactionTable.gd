class_name ReactionTable
extends RefCounted
## What happens when two live spell effects meet — authored as DATA.
##
## Keyed on physical FORM x an element predicate, deliberately NOT on
## SpellDef.Kind. Kind has 18 append-only values, so keying on it would give a
## mostly-empty 18x18x8x8 space in which a newly-added spell inherits NOTHING —
## exactly the outcome the curated-reaction design exists to avoid. Six forms
## give 21 ordered buckets, and a spell added next month with effect="fire"
## shatters ice walls with no code edit at all.
##
## Element predicates are wildcards by default: an empty element list matches any
## element, which is how the generic fallback rows are written. `require_opposed`
## covers all four opposing pairs with a single row rather than four near-copies.

## The physical shape a spell presents to the world, derived from its Kind.
## Lossy on purpose — reactions care whether a thing is a lance, a barrier or a
## lingering field, not which of five lances it is.
enum Form { BEAM, BARRIER, FIELD, PROJECTILE, IMPACT, AURA }

## Elements that annihilate rather than merely mix. One row keyed on
## `require_opposed` then covers fire/ice, lightning/earth, shadow/holy and
## arcane/wind without four near-identical entries.
const OPPOSED: Dictionary = {
	Elements.Element.FIRE: Elements.Element.ICE,
	Elements.Element.ICE: Elements.Element.FIRE,
	Elements.Element.LIGHTNING: Elements.Element.EARTH,
	Elements.Element.EARTH: Elements.Element.LIGHTNING,
	Elements.Element.SHADOW: Elements.Element.HOLY,
	Elements.Element.HOLY: Elements.Element.SHADOW,
	Elements.Element.ARCANE: Elements.Element.WIND,
	Elements.Element.WIND: Elements.Element.ARCANE,
}


static func opposed(a: int, b: int) -> bool:
	return OPPOSED.get(a, -1) == b


## Kind -> Form. Anything unrecognised is an IMPACT, which is the least
## surprising default: a new spell reacts like a hit rather than silently
## matching nothing at all.
static func form_for_kind(kind: int) -> int:
	match kind:
		SpellDef.Kind.BEAM, SpellDef.Kind.DIVINE_RAY:
			return Form.BEAM
		SpellDef.Kind.WALL, SpellDef.Kind.ICE_WALL, SpellDef.Kind.PILLAR:
			return Form.BARRIER
		SpellDef.Kind.ZONE:
			return Form.FIELD
		SpellDef.Kind.BOULDER, SpellDef.Kind.MISSILES, SpellDef.Kind.THROWN_ANCHOR, \
		SpellDef.Kind.CRAWLER:
			return Form.PROJECTILE
		SpellDef.Kind.TETHER:
			return Form.AURA
	return Form.IMPACT


## Canonical bucket for an unordered form pair, so (BEAM, BARRIER) and
## (BARRIER, BEAM) land in the same place and each rule is written once.
static func bucket_key(form_a: int, form_b: int) -> int:
	return (mini(form_a, form_b) << 4) | maxi(form_a, form_b)


## One authored rule. Plain dictionaries rather than a Resource so the table is
## readable in one screen and diffable in review; it can be promoted to .tres
## files later without changing the lookup.
##   outcome        : dispatch key the reactor turns into an effect
##   elements_a/b   : allowed elements, [] = any. Matched against whichever side
##                    sits on form_a, and BOTH orderings are tried.
##   require_opposed: only fires when the two elements annihilate
##   require_same   : only fires when the two elements match
##   priority       : higher wins when several rules match a pair
##   consumes_a/b   : the effect is spent by the reaction
static func _rule(outcome: String, form_a: int, form_b: int, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = {
		"outcome": outcome,
		"form_a": form_a,
		"form_b": form_b,
		"elements_a": opts.get("elements_a", []),
		"elements_b": opts.get("elements_b", []),
		"require_opposed": opts.get("require_opposed", false),
		"require_same": opts.get("require_same", false),
		"priority": opts.get("priority", 0),
		"consumes_a": opts.get("consumes_a", false),
		"consumes_b": opts.get("consumes_b", false),
		"radius": opts.get("radius", 0.0),
		"damage": opts.get("damage", 0),
		"suppress": opts.get("suppress", false),
	}
	return r


## The authored matrix. Headliners first — these are the ones that must land.
static func rules() -> Array:
	var E := Elements.Element
	return [
		# HOLLOW PURPLE. Two opposing beams crossed collapse into an annihilation.
		# One row, all four opposing pairs, because the predicate does the work.
		_rule("hollow_purple", Form.BEAM, Form.BEAM, {
			"require_opposed": true, "priority": 100,
			"consumes_a": true, "consumes_b": true, "radius": 190.0, "damage": 150,
		}),
		# Two beams of the SAME element reinforce instead of annihilating — the
		# constructive case matters, or players learn that every meeting is
		# destruction and stop experimenting.
		_rule("beam_resonance", Form.BEAM, Form.BEAM, {
			"require_same": true, "priority": 60, "damage": 40,
		}),
		# Fire (or holy) light against an ice barrier shatters it.
		_rule("shatter_ice_barrier", Form.BEAM, Form.BARRIER, {
			"elements_a": [E.FIRE, E.HOLY], "elements_b": [E.ICE],
			"priority": 90, "consumes_b": true, "radius": 120.0, "damage": 30,
		}),
		# ...and the same rule for a physical hit, so a boulder works like a beam.
		_rule("shatter_ice_barrier", Form.IMPACT, Form.BARRIER, {
			"elements_b": [E.ICE], "priority": 85, "consumes_b": true,
			"radius": 120.0, "damage": 30,
		}),
		_rule("shrapnel_cone", Form.PROJECTILE, Form.BARRIER, {
			"elements_b": [E.ICE], "priority": 88, "consumes_b": true,
			"radius": 140.0, "damage": 45,
		}),
		# Fire into a frost field boils it into steam — the one reaction whose
		# payoff is VISION rather than damage.
		_rule("steam_cloud", Form.BEAM, Form.FIELD, {
			"elements_a": [E.FIRE], "elements_b": [E.ICE],
			"priority": 80, "consumes_b": true, "radius": 160.0,
		}),
		_rule("steam_cloud", Form.IMPACT, Form.FIELD, {
			"elements_a": [E.FIRE], "elements_b": [E.ICE],
			"priority": 78, "consumes_b": true, "radius": 160.0,
		}),
		# Lightning through a frost field conducts harder.
		_rule("supercharge", Form.BEAM, Form.FIELD, {
			"elements_a": [E.LIGHTNING], "elements_b": [E.ICE],
			"priority": 75, "damage": 55,
		}),
		# Anything detonating inside a void field is void-charged: the knockback
		# inverts into a pull.
		_rule("void_charged", Form.IMPACT, Form.FIELD, {
			"elements_b": [E.SHADOW], "priority": 70, "radius": 175.0, "damage": 40,
		}),
		# Earth grounds out lightning — a barrier that genuinely counters a school.
		_rule("ground_out", Form.BEAM, Form.BARRIER, {
			"elements_a": [E.LIGHTNING], "elements_b": [E.EARTH],
			"priority": 82, "consumes_a": true,
		}),
		# A beam boring into a stone barrier carves through it rather than stopping.
		_rule("carve", Form.BEAM, Form.BARRIER, {
			"elements_b": [E.EARTH], "priority": 40, "damage": 25,
		}),
		# Same-element fields merge and strengthen rather than stacking two rings.
		_rule("field_merge", Form.FIELD, Form.FIELD, {
			"require_same": true, "priority": 50, "consumes_b": true, "radius": 190.0,
		}),
		# Explicit NULL row: two barriers touching is architecture, not an event.
		# Written down so the silence is a decision rather than a gap.
		_rule("none", Form.BARRIER, Form.BARRIER, {"priority": 10, "suppress": true}),
	]


## Best matching rule for a pair of live effects, or {} when they simply coexist.
## `a` and `b` are {form, element} descriptors. Both orderings are tried, so a
## rule written fire-beam-vs-ice-wall also fires when the wall is seen first.
static func match_rule(form_a: int, element_a: int, form_b: int, element_b: int) -> Dictionary:
	var key: int = bucket_key(form_a, form_b)
	var best: Dictionary = {}
	for r: Dictionary in rules():
		if bucket_key(int(r["form_a"]), int(r["form_b"])) != key:
			continue
		if not _sides_match(r, form_a, element_a, form_b, element_b) \
				and not _sides_match(r, form_b, element_b, form_a, element_a):
			continue
		if best.is_empty() or int(r["priority"]) > int(best["priority"]):
			best = r
	if not best.is_empty() and bool(best.get("suppress", false)):
		return {}
	return best


static func _sides_match(r: Dictionary, form_a: int, element_a: int,
		form_b: int, element_b: int) -> bool:
	if int(r["form_a"]) != form_a or int(r["form_b"]) != form_b:
		return false
	if bool(r["require_opposed"]) and not opposed(element_a, element_b):
		return false
	if bool(r["require_same"]) and element_a != element_b:
		return false
	var ea: Array = r["elements_a"]
	var eb: Array = r["elements_b"]
	if not ea.is_empty() and not ea.has(element_a):
		return false
	if not eb.is_empty() and not eb.has(element_b):
		return false
	return true
