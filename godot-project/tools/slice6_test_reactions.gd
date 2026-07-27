# SpellGeometry + ReactionTable — the Phase 3 foundation, before anything is
# wired to it. Both are pure, so the whole layer is provable with no scene.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_reactions.gd
extends SceneTree

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_overlap()
	failed += _test_meeting_point()
	failed += _test_forms()
	failed += _test_opposed()
	failed += _test_matching()
	failed += _test_inheritance()
	if failed > 0:
		printerr("Reaction tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Reaction tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_overlap() -> int:
	var ok: int = 0
	var c1 := SpellGeometry.circle(Vector2.ZERO, 50.0)
	var c2 := SpellGeometry.circle(Vector2(80.0, 0.0), 40.0)
	var c3 := SpellGeometry.circle(Vector2(500.0, 0.0), 40.0)
	ok += _expect(SpellGeometry.overlaps(c1, c2), "touching circles overlap")
	ok += _expect(not SpellGeometry.overlaps(c1, c3), "distant circles do not overlap")
	# Two beams crossing at right angles through the origin.
	var b1 := SpellGeometry.capsule(Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 20.0)
	var b2 := SpellGeometry.capsule(Vector2(0.0, -200.0), Vector2(0.0, 200.0), 20.0)
	ok += _expect(SpellGeometry.overlaps(b1, b2), "crossed beams overlap")
	# Parallel beams far apart must NOT overlap — the parallel branch is the one
	# most likely to divide by zero or silently return true.
	var b3 := SpellGeometry.capsule(Vector2(-200.0, 300.0), Vector2(200.0, 300.0), 20.0)
	ok += _expect(not SpellGeometry.overlaps(b1, b3), "parallel separated beams do not overlap")
	var b4 := SpellGeometry.capsule(Vector2(-200.0, 15.0), Vector2(200.0, 15.0), 20.0)
	ok += _expect(SpellGeometry.overlaps(b1, b4), "parallel close beams do overlap")
	# Beams that would cross if extended, but whose segments fall short.
	var short1 := SpellGeometry.capsule(Vector2(-200.0, 0.0), Vector2(-150.0, 0.0), 10.0)
	ok += _expect(not SpellGeometry.overlaps(short1, b2),
		"a beam that stops short of the crossing does not react")
	# Circle vs capsule both ways round.
	ok += _expect(SpellGeometry.overlaps(c1, b1), "circle overlaps a beam through it")
	ok += _expect(SpellGeometry.overlaps(b1, c1), "overlap is symmetric")
	return ok


func _test_meeting_point() -> int:
	var ok: int = 0
	# The crossing of these two beams is the origin — NOT either caster and not
	# the midpoint between them. Hollow Purple detonates here.
	var b1 := SpellGeometry.capsule(Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 20.0)
	var b2 := SpellGeometry.capsule(Vector2(0.0, -200.0), Vector2(0.0, 200.0), 20.0)
	var p: Vector2 = SpellGeometry.meeting_point(b1, b2)
	ok += _expect(p.length() < 1.0, "crossed beams meet at the crossing (got %s)" % p)
	# Off-centre crossing.
	var b3 := SpellGeometry.capsule(Vector2(120.0, -200.0), Vector2(120.0, 200.0), 20.0)
	var p2: Vector2 = SpellGeometry.meeting_point(b1, b3)
	ok += _expect(absf(p2.x - 120.0) < 1.0, "off-centre crossing is found (got %s)" % p2)
	# Bisector of a right-angle crossing points diagonally between the two.
	var bis: Vector2 = SpellGeometry.bisector(b1, b2)
	ok += _expect(absf(absf(bis.x) - absf(bis.y)) < 0.05,
		"bisector splits a right angle evenly (got %s)" % bis)
	# Directly opposed beams have no bisector sum; must not return a zero vector.
	var head := SpellGeometry.capsule(Vector2(-200.0, 0.0), Vector2(0.0, 0.0), 20.0)
	var into := SpellGeometry.capsule(Vector2(200.0, 0.0), Vector2(0.0, 0.0), 20.0)
	ok += _expect(SpellGeometry.bisector(head, into).length() > 0.5,
		"directly opposed beams still yield a firing axis")
	return ok


func _test_forms() -> int:
	var ok: int = 0
	ok += _expect(ReactionTable.form_for_kind(SpellDef.Kind.BEAM) == ReactionTable.Form.BEAM,
		"a beam is a BEAM")
	ok += _expect(ReactionTable.form_for_kind(SpellDef.Kind.ICE_WALL) == ReactionTable.Form.BARRIER,
		"an ice wall is a BARRIER")
	ok += _expect(ReactionTable.form_for_kind(SpellDef.Kind.ZONE) == ReactionTable.Form.FIELD,
		"a zone is a FIELD")
	ok += _expect(ReactionTable.form_for_kind(SpellDef.Kind.CRAWLER) == ReactionTable.Form.PROJECTILE,
		"the floor crawler is a PROJECTILE")
	ok += _expect(ReactionTable.form_for_kind(SpellDef.Kind.METEOR) == ReactionTable.Form.IMPACT,
		"a bombardment falls through to IMPACT")
	# Bucket key must be order-independent or every rule needs writing twice.
	ok += _expect(ReactionTable.bucket_key(ReactionTable.Form.BEAM, ReactionTable.Form.BARRIER)
		== ReactionTable.bucket_key(ReactionTable.Form.BARRIER, ReactionTable.Form.BEAM),
		"bucket key is order-independent")
	return ok


func _test_opposed() -> int:
	var E := Elements.Element
	var ok: int = 0
	ok += _expect(ReactionTable.opposed(E.FIRE, E.ICE), "fire opposes ice")
	ok += _expect(ReactionTable.opposed(E.ICE, E.FIRE), "opposition is symmetric")
	ok += _expect(ReactionTable.opposed(E.SHADOW, E.HOLY), "shadow opposes holy")
	ok += _expect(not ReactionTable.opposed(E.FIRE, E.FIRE), "an element does not oppose itself")
	ok += _expect(not ReactionTable.opposed(E.FIRE, E.LIGHTNING), "unrelated elements are not opposed")
	return ok


func _test_matching() -> int:
	var E := Elements.Element
	var F := ReactionTable.Form
	var ok: int = 0
	# HOLLOW PURPLE, from one row, for every opposing pair.
	var hp: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.ICE)
	ok += _expect(String(hp.get("outcome", "")) == "hollow_purple", "opposed beams annihilate")
	var hp2: Dictionary = ReactionTable.match_rule(F.BEAM, E.SHADOW, F.BEAM, E.HOLY)
	ok += _expect(String(hp2.get("outcome", "")) == "hollow_purple",
		"the SAME row covers shadow vs holy")
	ok += _expect(bool(hp.get("consumes_a", false)) and bool(hp.get("consumes_b", false)),
		"an annihilation spends both beams")
	# Same element reinforces instead.
	var res: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.FIRE)
	ok += _expect(String(res.get("outcome", "")) == "beam_resonance", "matched beams resonate")
	# Unrelated elements: no rule, they simply coexist.
	var none: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING)
	ok += _expect(none.is_empty(), "unrelated beams do not react")
	# Order independence: fire beam vs ice wall, written one way, matched both.
	var s1: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BARRIER, E.ICE)
	var s2: Dictionary = ReactionTable.match_rule(F.BARRIER, E.ICE, F.BEAM, E.FIRE)
	ok += _expect(String(s1.get("outcome", "")) == "shatter_ice_barrier",
		"a fire beam shatters an ice barrier")
	ok += _expect(String(s2.get("outcome", "")) == "shatter_ice_barrier",
		"...and matches with the sides swapped")
	# The explicit null row must read as "nothing happens", not as a rule.
	var walls: Dictionary = ReactionTable.match_rule(F.BARRIER, E.EARTH, F.BARRIER, E.EARTH)
	ok += _expect(walls.is_empty(), "two barriers touching is deliberately silent")
	return ok


## The whole point of keying on form rather than Kind: a spell that did not exist
## when the table was written still inherits the reactions of its shape.
func _test_inheritance() -> int:
	var E := Elements.Element
	var F := ReactionTable.Form
	var ok: int = 0
	# THROWN_ANCHOR was added after these rules were authored, and it is a
	# projectile, so it shatters an ice wall with no new row.
	var f: int = ReactionTable.form_for_kind(SpellDef.Kind.THROWN_ANCHOR)
	var r: Dictionary = ReactionTable.match_rule(f, E.FIRE, F.BARRIER, E.ICE)
	ok += _expect(String(r.get("outcome", "")) == "shrapnel_cone",
		"a brand-new projectile kind inherits the barrier reaction")
	# A holy beam shatters ice through the multi-element list, not a copied row.
	var h: Dictionary = ReactionTable.match_rule(F.BEAM, E.HOLY, F.BARRIER, E.ICE)
	ok += _expect(String(h.get("outcome", "")) == "shatter_ice_barrier",
		"holy shatters ice via the element list")
	return ok
