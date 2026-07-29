# WHY TWO BEAMS DO NOT EXPLODE — the stage-by-stage evidence for the maker's
# live play report ("when the two beams clash they should EXPLODE"; they do not).
#
#   godot --headless --path godot-project --script tools/beam_clash_probe.gd
#
# This is a PROBE, not a test: it asserts nothing and fails nothing, it prints
# what SpellReactor actually sees so the fix is aimed at a measured cause rather
# than a plausible one.
#
# ⚠ IT CANNOT INSTANTIATE A REAL BeamSpell. BeamSpell.gd names the `Sfx` autoload
# (Sfx.gd has no class_name), and autoloads are NOT registered under `--script`,
# so merely touching the class is a compile error that fails the whole dependency
# chain. So the timing arm below REPLICATES BeamSpell's constants as literals —
# they are asserted against the real file by _check_timing_constants(), which
# reads the source, so this probe cannot drift away from the thing it models.
extends SceneTree

## BeamSpell's timeline, mirrored. Verified against the source at run time.
const CHARGE_TIME: float = 0.34
const FIRE_TIME: float = 0.26
const FADE_TIME: float = 0.22
const BEAM_SRC: String = "res://scripts/combat/BeamSpell.gd"

var _ran: bool = false


func _process(_d: float) -> bool:
	if _ran:
		return true
	_ran = true
	print("=== BEAM CLASH PROBE ===")
	_check_timing_constants()
	_stage_0_weights()
	_stage_3_element_matrix()
	_stage_1_timing()
	_stage_5_reactor_trace()
	print("=== PROBE END ===")
	quit(0)
	return true


## The literals above are a model of another file. Prove the model.
func _check_timing_constants() -> void:
	var f: FileAccess = FileAccess.open(BEAM_SRC, FileAccess.READ)
	if f == null:
		print("[!] could not read BeamSpell.gd to verify the mirrored constants")
		return
	var src: String = f.get_as_text()
	var ok: bool = src.contains("CHARGE_TIME: float = %s" % str(CHARGE_TIME)) \
		and src.contains("FIRE_TIME: float = %s" % str(FIRE_TIME)) \
		and src.contains("FADE_TIME: float = %s" % str(FADE_TIME))
	print("[model] mirrored BeamSpell timings match source: %s" % ("yes" if ok else "NO — PROBE IS STALE"))


# ── STAGE 0: what do beams actually WEIGH when they meet? ───────────────────
# The suspicion was that the beam family's HEAVY/ULT spread makes two beams
# unequal, dropping them out of `mutual_annihilation` (require_weight "equal")
# and into `overpower`, where the heavy one simply eats the light one.
func _stage_0_weights() -> void:
	print("\n-- STAGE 0: weight --")
	var beam_src: FileAccess = FileAccess.open(BEAM_SRC, FileAccess.READ)
	var implements: bool = beam_src != null \
		and beam_src.get_as_text().contains("func reaction_weight")
	print("  BeamSpell implements reaction_weight(): %s" % ("YES" if implements else "NO"))
	print("  -> every live beam therefore weighs SpellTier.DEFAULT_WEIGHT (%s)"
		% SpellTier.display_name(SpellTier.DEFAULT_WEIGHT))
	print("  -> the loadout shelves below NEVER REACH THE REACTOR:")
	for s: SpellDef in SpellLibrary.build_all():
		if s.kind != SpellDef.Kind.BEAM:
			continue
		print("       %-16s loadout tier=%-5s  clash weight=%s"
			% [s.id, SpellTier.display_name(SpellTier.of(s)),
				SpellTier.display_name(SpellTier.DEFAULT_WEIGHT)])


# ── STAGE 3: which outcome does each real beam PAIR resolve to? ─────────────
func _stage_3_element_matrix() -> void:
	print("\n-- STAGE 3: element predicate, every real beam pair, DIFFERENT casters --")
	var beams: Array = []
	for s: SpellDef in SpellLibrary.build_all():
		if s.kind == SpellDef.Kind.BEAM:
			beams.append(s)
	var tally: Dictionary = {}
	for i: int in range(beams.size()):
		for j: int in range(i, beams.size()):
			var a: SpellDef = beams[i]
			var b: SpellDef = beams[j]
			var r: Dictionary = ReactionTable.match_rule(
				ReactionTable.Form.BEAM, a.element, ReactionTable.Form.BEAM, b.element,
				"different", SpellTier.DEFAULT_WEIGHT, SpellTier.DEFAULT_WEIGHT)
			var out: String = String(r.get("outcome", "(none)"))
			var consumes: String = "both" if (bool(r.get("consumes_a", false)) \
				and bool(r.get("consumes_b", false))) else "not both"
			tally[out] = int(tally.get(out, 0)) + 1
			print("  %-16s x %-16s -> %-22s pri=%-4s spends=%s"
				% [a.id, b.id, out, str(r.get("priority", "-")), consumes])
	print("  TALLY: %s" % str(tally))


# ── STAGE 1: do the two beams' LIVE windows ever overlap? ──────────────────
# reaction_active() is false during the charge telegraph, so the whole window in
# which two beams can meet is FIRE_TIME + FADE_TIME after each one's charge.
func _stage_1_timing() -> void:
	print("\n-- STAGE 1: reaction_active() overlap window --")
	var live: float = FIRE_TIME + FADE_TIME
	print("  a beam is inert for %.2fs (charge), then LIVE for %.2fs" % [CHARGE_TIME, live])
	print("  -> two beams overlap only if their casts land within %.2fs of each other" % live)
	for offset: float in [0.0, 0.2, 0.45, 0.5, 0.8]:
		print("     cast offset %.2fs -> %s" % [offset,
			"OVERLAP (can react)" if offset < live else "NO OVERLAP (can never react)"])


# ── STAGE 5: drive the real reactor with two crossing beam-shaped effects ──
func _stage_5_reactor_trace() -> void:
	print("\n-- STAGE 5: live reactor, two crossing beams, two casters --")
	var reactor: Node = (load("res://scripts/combat/SpellReactor.gd") as GDScript).new()
	reactor.set("spawn_effects", false)   # detection only: no spectacle, no autoloads
	root.add_child(reactor)
	reactor.set_process(false)            # we drive resolve_now() by hand
	var E := Elements.Element
	# Same element (two Arcanists, the most likely duel), then neutral, then opposed.
	for probe: Array in [
		["SAME element (arcane vs arcane)", E.ARCANE, E.ARCANE],
		["NEUTRAL pair (arcane vs ice)", E.ARCANE, E.ICE],
		["OPPOSED pair (fire vs ice)", E.FIRE, E.ICE],
	]:
		var a: Node2D = _stub(reactor, Vector2(-500, 0), Vector2(500, 0), int(probe[1]), "P1")
		var b: Node2D = _stub(reactor, Vector2(0, -500), Vector2(0, 500), int(probe[2]), "P2")
		var n: int = int(reactor.call(&"resolve_now"))
		print("  %-32s fired=%d  a_consumed=%s b_consumed=%s"
			% [String(probe[0]), n, str(a.get("consumed")), str(b.get("consumed"))])
		reactor.call(&"unregister", a)
		reactor.call(&"unregister", b)
		a.queue_free()
		b.queue_free()
	# And the case that must stay silent: both beams still charging.
	var c: Node2D = _stub(reactor, Vector2(-500, 0), Vector2(500, 0), E.ARCANE, "P1")
	var d: Node2D = _stub(reactor, Vector2(0, -500), Vector2(0, 500), E.ICE, "P2")
	c.set("active", false)
	d.set("active", false)
	print("  %-32s fired=%d (must be 0 — charge telegraph)"
		% ["BOTH STILL CHARGING", int(reactor.call(&"resolve_now"))])
	reactor.queue_free()


## A beam-shaped reactant, PARKED AT THE ORIGIN exactly like the real thing.
func _stub(reactor: Node, from: Vector2, to: Vector2, element: int, caster: String) -> Node2D:
	var s: Node2D = (load("res://tools/beam_clash_probe_stub.gd") as GDScript).new()
	var o := Node.new()
	o.name = caster
	root.add_child(o)
	s.set("owner_node", o)
	s.set("shape", SpellGeometry.capsule(from, to, 46.0))
	s.set("element", element)
	root.add_child(s)
	reactor.call(&"register", s, ReactionTable.Form.BEAM, element)
	return s
