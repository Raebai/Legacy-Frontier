# THE TELL AUDIT — does the drawn warning match the thing that actually hurts?
#
#   godot --headless --path godot-project --script tools/probe_tell_audit.gd
#
# ══ WHY THIS EXISTS ═════════════════════════════════════════════════════════
# "Everything must be dodgeable" is the locked rule, and a telegraph is how the
# game keeps it. A telegraph that does not match its hitbox is therefore not a
# cosmetic bug — it is the rule being broken while a picture says it is not. This
# repo has already been bitten by exactly that at least twice and written both up:
# `EnergyNova` damaged 1.24x wider than it drew, and `SpellBoltVisual`'s header
# now carries a hard "the wake grows BACKWARDS ONLY" constraint for the same
# reason. Nothing had ever swept the whole roster.
#
# ══ WHAT IT IS AND IS NOT ═══════════════════════════════════════════════════
# ⚠ THE NUMBERS ARE READ FROM THE CODE, THE PAIRINGS ARE THE AUDIT'S JUDGEMENT.
# Every figure below comes out of a live `const` (via `get_script_constant_map`)
# or a live `SpellDef`, so a re-tune moves this table on the next run and cannot
# silently invalidate it. What is hand-written is which tell belongs to which
# hitbox, because that lives in control flow across three files and cannot be
# derived. A row's `note` says where its damage geometry was read.
#
# ⚠ AND `ARCHETYPE_SPELLS` IS DELIBERATELY WALKED RATHER THAN TABULATED. Five of
# the worst rows come from one shared code path (`Enemy._start_spell_windup`), so
# hard-coding them would let a sixth archetype spell be added tomorrow into the
# same fault with nothing to say so.
#
# Test-idiom note: a HARNESS, not an assertion suite — it reports, it does not gate.
extends SceneTree

## ⚠ `load()` INSIDE `_process`, NOT `preload`. `Enemy.gd` and `Hero.gd` reference
## the `Sfx` and `Rank` autoloads, and a `preload` on a `--script` run resolves
## while the autoload singletons are still being brought up — so the compile fails
## with "Identifier not found: Sfx", the whole dependency chain is reported broken,
## and the probe prints its table anyway from a half-loaded script. Loading from a
## live frame is after the tree is up and is silent.
const ENEMY_PATH: String = "res://scripts/combat/Enemy.gd"
const HERO_PATH: String = "res://scripts/combat/Hero.gd"

## Verdicts, worst last so the summary can count them.
const OK: String = "MATCH"
const OVER: String = "OVER-DRAWN"     # the tell claims more ground than hurts
const UNDER: String = "UNDER-DRAWN"   # ⚠ danger outside the drawing: unfair
const SHAPE: String = "WRONG SHAPE"   # circle drawn, corridor damages (or vice versa)
const ORIGIN: String = "WRONG ORIGIN" # drawn somewhere the damage does not start
const NONE: String = "NO TELL"        # damage with nothing drawn at all

var _rows: Array[Dictionary] = []
var _ran: bool = false


func _process(_d: float) -> bool:
	if _ran:
		return true
	_ran = true
	var enemy_script: GDScript = load(ENEMY_PATH) as GDScript
	var hero_script: GDScript = load(HERO_PATH) as GDScript
	if enemy_script == null or hero_script == null:
		printerr("probe_tell_audit: could not load Enemy/Hero — the table would be empty")
		quit(1)
		return true
	var e: Dictionary = enemy_script.get_script_constant_map()
	var h: Dictionary = hero_script.get_script_constant_map()
	# Vacuity guard: a constant map that came back short means a rename landed and
	# every figure below would silently be a default rather than the game's number.
	if not e.has("ATTACK_RADIUS") or not h.has("MELEE_RANGE"):
		printerr("probe_tell_audit: the constants moved — this table is stale, not clean")
		quit(1)
		return true
	_audit_enemy_base(e)
	_audit_enemy_spells(e)
	_audit_hero(h)
	_report()
	quit(0)
	return true


func _add(row: Dictionary) -> void:
	_rows.append(row)


# ---------------------------------------------------------------- the roster
## The seven archetype base attacks. Damage geometry read from `Enemy.gd`:
## `_resolve_strike` (brute), `_spawn_enemy_bolt` (caster), `_process_charging`
## (charger + assassin), `_spawn_minions` (summoner), `_detonate` (bomber),
## `_cast_mage_aoe` (mage).
func _audit_enemy_base(e: Dictionary) -> void:
	_add({
		"name": "BRUTE heavy strike", "style": "ZONE", "colour": "archetype red",
		"windup": float(e["ATTACK_WINDUP"]), "dmg": int(e["ATTACK_DAMAGE"]),
		"drawn": "circle r=%.0f at the snapshot spot" % float(e["ATTACK_RADIUS"]),
		"hurts": "circle r=%.0f at the same spot" % float(e["ATTACK_RADIUS"]),
		"verdict": OK, "err": "0 px",
		"note": "Enemy._resolve_strike: distance_to(center) <= ATTACK_RADIUS. 1:1.",
	})
	# The bolt is a travelling body with no fixed reach; the tell draws a `reach`
	# tracer of 130 px (hard-coded at the call site) and reports an 18 px circle.
	_add({
		"name": "CASTER bolt", "style": "MUZZLE", "colour": "archetype violet",
		"windup": float(e["CASTER_WINDUP"]), "dmg": 0,
		"drawn": "circle r=%.0f on the caster + a %.0f px aim tracer"
			% [float(e["CASTER_TELE_RADIUS"]), 130.0],
		"hurts": "a bolt travelling the whole room down the same aim",
		"verdict": SHAPE, "err": "tracer stops at 130 px; the bolt does not",
		"note": "Enemy._spawn_enemy_bolt. The PICTURE is right (a corridor) but "
			+ "danger_shape() reports the 18 px circle, so a dodging brain sidesteps "
			+ "the staff instead of the shot.",
	})
	var charge_travel: float = float(e["CHARGE_SPEED"]) * float(e["CHARGE_TIME"])
	_add({
		"name": "CHARGER lane", "style": "LANE", "colour": "archetype orange",
		"windup": float(e["CHARGE_WINDUP"]), "dmg": int(e["CHARGE_DAMAGE"]),
		"drawn": "lane %.0f x %.0f px" % [float(e["CHARGE_LEN"]), float(e["CHARGE_WIDTH"])],
		"hurts": "a %.0f px run (%.0f px/s x %.2f s), catch radius %.0f -> effective width %.0f"
			% [charge_travel, float(e["CHARGE_SPEED"]), float(e["CHARGE_TIME"]),
				float(e["CHARGE_HIT_RADIUS"]), float(e["CHARGE_HIT_RADIUS"]) * 2.0],
		"verdict": UNDER,
		"err": "length OVER by %.0f px; WIDTH UNDER by %.0f px (%.0f per side)"
			% [float(e["CHARGE_LEN"]) - charge_travel - float(e["CHARGE_HIT_RADIUS"]),
				float(e["CHARGE_HIT_RADIUS"]) * 2.0 - float(e["CHARGE_WIDTH"]),
				(float(e["CHARGE_HIT_RADIUS"]) * 2.0 - float(e["CHARGE_WIDTH"])) * 0.5],
		"note": "Enemy._process_charging: distance_to(hero) <= CHARGE_HIT_RADIUS along "
			+ "the run. Standing just outside the drawn lane is still inside the catch.",
	})
	_add({
		"name": "SUMMONER call", "style": "GATHER", "colour": "archetype green",
		"windup": float(e["SUMMON_WINDUP"]), "dmg": 0,
		"drawn": "circle r=%.0f on the summoner" % float(e["SUMMON_TELE_RADIUS"]),
		"hurts": "nothing — it spawns %d chasers" % int(e["SUMMON_COUNT"]),
		"verdict": OK, "err": "n/a",
		"note": "Enemy._spawn_minions. A warning, not a danger zone; STYLE_CONSEQUENCE "
			+ "calls GATHER 'ground', which is the one place the vocabulary overstates.",
	})
	var lunge_travel: float = float(e["ASSASSIN_LUNGE_SPEED"]) * float(e["ASSASSIN_LUNGE_TIME"])
	_add({
		"name": "ASSASSIN lunge", "style": "DART", "colour": "archetype silver",
		"windup": float(e["ASSASSIN_WINDUP"]), "dmg": int(e["ASSASSIN_DAMAGE"]),
		"drawn": "circle r=%.0f at the snapshot spot" % float(e["ASSASSIN_TELE_RADIUS"]),
		"hurts": "a %.0f px lunge with catch radius %.0f — a CORRIDOR, not a point"
			% [lunge_travel, float(e["ASSASSIN_HIT_RADIUS"])],
		"verdict": SHAPE,
		"err": "%.0f px of travel corridor is undrawn" % lunge_travel,
		"note": "Enemy._process_charging (assassin branch). The mark says 'not here'; "
			+ "the truth is 'not anywhere on the line between me and here'.",
	})
	_add({
		"name": "BOMBER detonation", "style": "BOMB", "colour": "archetype orange",
		"windup": float(e["BOMB_WINDUP"]), "dmg": int(e["BOMB_DAMAGE"]),
		"drawn": "circle r=%.0f on the bomber" % float(e["BOMB_RADIUS"]),
		"hurts": "circle r=%.0f at the marked spot" % float(e["BOMB_RADIUS"]),
		"verdict": OK, "err": "0 px",
		"note": "Enemy._detonate: distance_to(_strike_center) <= BOMB_RADIUS. 1:1, and "
			+ "the biggest, slowest tell in the roster carries the biggest hit. Correct.",
	})
	_add({
		"name": "MAGE ground AoE", "style": "ZONE", "colour": "archetype violet",
		"windup": float(e["MAGE_WINDUP"]), "dmg": int(e["MAGE_AOE_DAMAGE"]),
		"drawn": "circle r=%.0f at the snapshot spot" % float(e["MAGE_AOE_RADIUS"]),
		"hurts": "BlastSpell radius %.0f at the same spot" % float(e["MAGE_AOE_RADIUS"]),
		"verdict": OK, "err": "0 px",
		"note": "Enemy._cast_mage_aoe passes MAGE_AOE_RADIUS to both. 1:1.",
	})


## THE FIVE ARCHETYPE SPELLS, walked from the live table rather than listed — one
## shared code path (`Enemy._start_spell_windup`) telegraphs all of them, and it
## plants EVERY tell at `_strike_center`, which is where the HERO is standing.
## Four of the five spells do not originate there at all.
func _audit_enemy_spells(e: Dictionary) -> void:
	var names: Dictionary = {0: "CHASER", 1: "BRUTE", 2: "CASTER", 3: "CHARGER",
		4: "SUMMONER", 5: "ASSASSIN", 6: "BOMBER", 7: "MAGE"}
	var table: Dictionary = e["ARCHETYPE_SPELLS"]
	var styles: Dictionary = {0: "ZONE", 1: "MUZZLE", 2: "LANE", 3: "DART",
		4: "GATHER", 5: "BOMB", 6: "FIST", 7: "CRESCENT"}
	for arch: int in table:
		var row: Dictionary = table[arch]
		var id: String = String(row["id"])
		var spell: SpellDef = SpellLibrary.by_id(id)
		# The default in `_start_spell_windup` when a row states no radius. Read as a
		# literal because it IS a literal at that call site — Enemy.gd:1946.
		var drawn_r: float = float(row.get("radius", 90.0))
		var verdict: String = OK
		var err: String = ""
		var hurts: String = "(spell not found)"
		if spell != null:
			hurts = "%s: radius %.0f, reach %.0f" % [spell.id, spell.radius, spell.reach]
			# Reach > 0 means the working TRAVELS from the caster's feet — a corridor
			# or a pair of them — and a circle planted on the hero cannot describe it.
			if spell.reach > 0.0:
				verdict = ORIGIN
				err = "drawn on the HERO; the working starts at the CASTER and runs %.0f px" \
					% spell.reach
			elif absf(spell.radius - drawn_r) > 2.0:
				verdict = UNDER if spell.radius > drawn_r else OVER
				err = "drawn r=%.0f vs damage r=%.0f (%+.0f px)" % [drawn_r, spell.radius, spell.radius - drawn_r]
			else:
				err = "0 px"
		_add({
			"name": "%s spell (%s)" % [String(names.get(arch, "?")), id],
			"style": String(styles.get(int(row["style"]), "?")),
			"colour": "archetype accent (NOT the spell's element)",
			"windup": float(row["windup"]), "dmg": int(row["dmg"]),
			"drawn": "circle r=%.0f at the HERO's snapshot spot" % drawn_r,
			"hurts": hurts, "verdict": verdict, "err": err,
			"note": "Enemy._start_spell_windup — one telegraph for all five spells, "
				+ "always at _strike_center, always the row's own radius.",
		})


## The hero's own tells. Damage geometry read from `Hero.gd`:
## `_on_melee_hit_frame`, `_resolve_uppercut`, `_resolve_frost_cone`, `_fire_punch`,
## `_ground_slam`, `_spawn_nova`.
func _audit_hero(h: Dictionary) -> void:
	var reach: float = float(h["MELEE_RANGE"])
	var tell_w: float = maxf(reach * float(h["SWING_TELL_WIDTH"]), float(h["SWING_TELL_MIN_WIDTH"]))
	# The tell's own angular half-width, measured at full reach: a lane of width w
	# over a length L subtends atan((w/2)/L) from the swinger.
	var tell_deg: float = rad_to_deg(atan((tell_w * 0.5) / reach))
	var arc_deg: float = rad_to_deg(acos(clampf(float(h["MELEE_ARC_DOT"]), -1.0, 1.0)))
	var swing_windup: float = float(CharacterRig.ONE_SHOT_DURATIONS.get(CharacterRig.State.PUNCH, 0.22)) \
		* CharacterRig.HIT_FRAME_FRACTION
	_add({
		"name": "HERO melee swing", "style": "FIST / CRESCENT", "colour": "class element",
		"windup": swing_windup, "dmg": int(h["MELEE_DAMAGE"]),
		"drawn": "lane %.0f x %.1f px from the lead hand (half-angle %.1f deg)"
			% [reach, tell_w, tell_deg],
		"hurts": "cone r=%.0f, half-angle %.1f deg from the BODY, PLUS the nearest body "
			% [reach, arc_deg] + "within %.0f px at ANY angle (auto-target)" % reach,
		"verdict": UNDER,
		"err": "arc under-drawn by %.1f deg per side; auto-target makes the real "
			% (arc_deg - tell_deg) + "footprint a full 360 deg disc for the closest body",
		"note": "Hero._on_melee_hit_frame: `_nearest_enemy_in_melee_range()` always "
			+ "connects regardless of the cone. This is the largest drawn-vs-damage "
			+ "gap in the game and it is on the most-used attack in the game.",
	})
	var up_reach: float = float(h["UPPERCUT_REACH"])
	var up_deg: float = rad_to_deg(acos(clampf(float(h["UPPERCUT_DOT"]), -1.0, 1.0)))
	var up_drawn_r: float = up_reach * 0.6
	_add({
		"name": "BRAWLER uppercut", "style": "DART", "colour": "class element",
		"windup": float(h["ABILITY_TELL_LEAD"]), "dmg": 18 + int(h["MELEE_DAMAGE"]),
		"drawn": "circle r=%.0f centred 24 px ahead" % up_drawn_r,
		"hurts": "cone r=%.0f, half-angle %.1f deg from the body" % [up_reach, up_deg],
		"verdict": UNDER,
		"err": "the wedge reaches %.0f deg off the aim; the circle covers roughly the "
			% up_deg + "forward %.0f px only, so up to %.0f px of rear/lateral danger is undrawn"
			% [up_drawn_r + 24.0, up_reach],
		"note": "Hero._resolve_uppercut: SpellTargets.in_cone(..., UPPERCUT_DOT = %.2f), "
			% float(h["UPPERCUT_DOT"]) + "i.e. everything but a 157 deg rear wedge.",
	})
	# ⚠ HARD-CODED, AND FLAGGED AS SUCH. `CONE_RANGE` / `CONE_COS` are function-local
	# consts inside `Hero._primary_frost_cone` (Hero.gd:4849-4850) so there is nothing
	# to read. If that function is retuned this row goes stale and the note is the
	# only thing that will say so.
	var cone_range: float = 118.0
	var cone_cos: float = 0.5
	var cone_deg: float = rad_to_deg(acos(cone_cos))
	_add({
		"name": "CRYOMANCER frost cone", "style": "MUZZLE", "colour": "class element",
		"windup": float(h["ABILITY_TELL_LEAD"]), "dmg": 19,
		"drawn": "circle r=%.0f centred %.0f px ahead (+ a %.0f px tracer)"
			% [cone_range * 0.5, cone_range * 0.5, cone_range],
		"hurts": "cone r=%.0f, half-angle %.0f deg" % [cone_range, cone_deg],
		"verdict": UNDER,
		"err": "at mid-range the real cone is %.0f px wide per side against the circle's %.0f"
			% [cone_range * 0.5 * tan(deg_to_rad(cone_deg)), cone_range * 0.5],
		"note": "Hero._resolve_frost_cone. Hard-coded here — CONE_RANGE/CONE_COS are "
			+ "function-local consts (Hero.gd:4849).",
	})
	for spec: Array in [
		["BRAWLER fire punch", 66.0, 30 + int(h["MELEE_DAMAGE"]), "44 px ahead"],
		["JUGGERNAUT ground slam", 98.0, 34, "on the hero"],
	]:
		_add({
			"name": String(spec[0]), "style": "ZONE (BlastSpell's own)",
			"colour": "⚠ Telegraph.RING_COLOR — the element is NOT carried",
			"windup": float(h["ABILITY_TELL_LEAD"]), "dmg": int(spec[2]),
			"drawn": "ring r=%.0f, %s" % [float(spec[1]), String(spec[3])],
			"hurts": "radius r=%.0f, same centre" % float(spec[1]),
			"verdict": OK, "err": "0 px",
			"note": "BlastSpell.detonate_at passes `radius` to both the ring and the "
				+ "sweep. Geometry 1:1 — but `telegraph.accent` is never set, so every "
				+ "blast in the game tells in danger-red whatever element it is.",
		})
	_add({
		"name": "MAGE energy nova", "style": "(sigil, not a Telegraph)", "colour": "class element",
		"windup": 0.0, "dmg": 0,
		"drawn": "the cast sigil, opened at exactly the damage radius",
		"hurts": "EnergyNova.NOVA_RADIUS, 1:1 with the drawing",
		"verdict": OK, "err": "0 px",
		"note": "EnergyNova pins VISUAL_RADIUS_FACTOR and TELEGRAPH_RADIUS_FACTOR at "
			+ "1.0 with a written-out block on why. The reference case for this audit.",
	})


# --------------------------------------------------------------------- report
func _report() -> void:
	print("")
	print("╔═ THE TELL AUDIT ═ does the drawn warning match the hitbox? ═══════════════")
	var counts: Dictionary = {}
	for r: Dictionary in _rows:
		var v: String = String(r["verdict"])
		counts[v] = int(counts.get(v, 0)) + 1
		print("")
		print("── %-28s  %-18s  windup %.3fs  dmg %d"
			% [String(r["name"]), String(r["style"]), float(r["windup"]), int(r["dmg"])])
		print("   colour : %s" % String(r["colour"]))
		print("   drawn  : %s" % String(r["drawn"]))
		print("   hurts  : %s" % String(r["hurts"]))
		print("   VERDICT: %-12s %s" % [String(r["verdict"]), String(r["err"])])
		print("   why    : %s" % String(r["note"]))
	print("")
	print("╠═ SUMMARY ════════════════════════════════════════════════════════════════")
	for v: String in [OK, OVER, UNDER, SHAPE, ORIGIN, NONE]:
		if counts.has(v):
			print("║  %-12s %d of %d" % [v, int(counts[v]), _rows.size()])
	print("║")
	print("║  A tell that does not match its hitbox is the 'everything is dodgeable'")
	print("║  rule being broken while a picture says it is not. UNDER-DRAWN is the")
	print("║  unfair direction (damage outside the warning); WRONG ORIGIN / WRONG")
	print("║  SHAPE mean the player is told to dodge the wrong kind of thing.")
	print("╚══════════════════════════════════════════════════════════════════════════")
	# The windup ladder, sorted, so rule 3 (warning proportional to danger) is one
	# glance rather than an argument.
	print("")
	print("── WINDUP vs DAMAGE ladder (rule 3: the warning must scale with the hit) ──")
	print("   ⚠ COMPARE WITHIN A SIDE, NOT ACROSS ONE. An enemy tell protects the")
	print("   player; a hero tell protects whatever the hero is swinging at — a bot, a")
	print("   sparring dummy, or a co-op partner under friendly fire. The enemy rows")
	print("   sit in a tight 5-29 dmg per second of warning band, which is a ladder.")
	print("   The hero rows sit at 180-440, which is not one: ABILITY_TELL_LEAD is a")
	print("   single 0.10 s constant for four abilities of very different weight, and")
	print("   the melee swing's 0.077 s is derived from an ANIMATION rather than from")
	print("   the damage. Both are known and documented in Hero.gd; neither is tuned.")
	var sorted: Array[Dictionary] = _rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["dmg"]) > int(b["dmg"]))
	for r: Dictionary in sorted:
		if int(r["dmg"]) <= 0:
			continue
		var w: float = float(r["windup"])
		print("   dmg %3d   windup %.3fs   %6.1f dmg per second of warning   %s"
			% [int(r["dmg"]), w, float(r["dmg"]) / maxf(w, 0.001), String(r["name"])])
