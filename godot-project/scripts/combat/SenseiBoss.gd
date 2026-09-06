class_name SenseiBoss
extends TowerBoss
## THE SENSEI — the promise kept on floor 20.
##
## ── WHY THIS FILE EXISTS ─────────────────────────────────────────────────────
## `4d357ed` built the dojo: a teacher who shows you the controls, then puts you on the
## floor and leaves saying *"I'll see you in the tower..."*. It added a `SENSEI` row to
## `BossRoster` so the tower keeps that promise at floor 20 — and pointed that row at
## `res://scenes/combat/Boss.tscn`, the ASHEN GUARDIAN's scene. Its own commit message
## said so: *"a bespoke scene with his iai kit is the follow-up this entry is honest
## about not being."* This is that follow-up.
##
## ⚠ AND UNTIL IT LANDED, FOUR SUITES WERE RED AND THEY WERE RIGHT. Sharing a scene
## meant sharing an identity: `boss_title()` answered "THE ASHSPIRE GUARDIAN", the bar
## carried that name, the bark row was the Guardian's, the rig was the Guardian's
## height and every attack id belonged to the Guardian already. A player who climbed
## twenty floors on the strength of a spoken promise met the boss they had already
## fought several times, wearing a name from a table nothing read. That is worse than
## not making the promise.
##
## ── THE ARTIST ───────────────────────────────────────────────────────────────
## `BossRoster` bills him as **"ink, one stroke, no correction"**, and that is the
## whole design brief. The other six draw with something that can be worked over — a
## scribble goes back and forth, gold leaf is laid in layers, an etcher bites the plate
## again. A brush loaded once and drawn once cannot be corrected. So he is the roster's
## only COMMITTED artist, and his fight is about the moment of commitment.
##
## ── HOW HE FIGHTS DIFFERENTLY ────────────────────────────────────────────────
## The roster's standing question is what each fight ASKS, not what it does:
##
##   Scribble      — wants to be AT you.       Answer: dodge on the beat.
##   Cartographer  — wants you at a DISTANCE.  Answer: stand in the right cell.
##   Illuminator   — wants you COMMITTED.      Answer: survive, then punish.
##   Eraser        — wants the ROOM.           Answer: give up ground and close in.
##   Etcher        — wants an UNBROKEN plate.  Answer: break the cast.
##   **Sensei      — wants you ON THE LINE.    Answer: get OFF it, and the only way
##     off is ACROSS.**
##
## Every cut he makes is a LANE that passes THROUGH him and out both sides, so it has
## no range to escape and no back to run to — moving away along his facing keeps you on
## it for as long as you can run. The only exit is perpendicular, which means moving
## THROUGH his reach while a blade is about to come out of it. That is the lesson the
## dojo actually taught (*"the tower does not end. neither does anyone who climbs it
## well."*) restated as a mechanic: the safe move is the one that looks suicidal.
##
## ⚠ SO HIS TELLS ARE THE LONGEST ON THE ROSTER AND HIS COOLDOWNS THE SHORTEST, and
## that pairing IS the fight rather than two separate dials. A long tell is what makes
## crossing possible at all; a short cooldown is what stops crossing once from being
## the answer forever. Read either number alone and it looks mistuned.
##
## ── ⚠ THE NAMED WEAKNESS, KEPT IN THE FILE ───────────────────────────────────
## He is a LANE boss and so is the Cartographer's `straightedge`. The separation is
## real — hers are ruled at fixed angles across a static page and reset between
## figures, his all pivot through one moving body and never repeat an angle — but it
## is a separation of KIND, and kind is the thing playtest most often disagrees with.
## If a session reports that the two feel the same, THIS is the one to re-cut: the
## Cartographer carries the compass annulus, which nothing else in the game teaches.

## Pale jade — the colour he wears while he is still your teacher, lifted verbatim from
## `FreePlay._spawn_sensei` and `data/npcs/sensei.tres` so the body on floor 20 is
## recognisably the person from the dojo.
const JADE: Color = Color(0.62, 0.86, 0.78)
## ...and the red he turns before he says the line. `FreePlay.SENSEI_TURNED`. This is
## his ACCENT: every telegraph, every stroke of his redraw and the rim of his name card
## are in the colour he turned, against a body still wearing the colour he taught in.
## The fight is that contradiction and the palette states it before he moves.
const TURNED: Color = Color(0.86, 0.24, 0.30)

## ⚠ TALLER THAN THE GUARDIAN, SHORTER THAN THE SERAPH, THINNER THAN EITHER.
## `slice_test_bossmods` requires a rig height no other artist has — a roster whose
## bodies are the same size is a roster of recolours — and the first draft picked 92,
## which the Cartographer already had. Taken: 60 Scribble, 78 Eraser, 86 Etcher,
## 92 Cartographer, 95 Guardian, 102 Illuminator.
##
## 99 is a reading, not a free slot. He is a swordsman, so the silhouette is long — but
## the REACH is the blade, not the body, and making him the tallest thing in the tower
## would say his threat is mass. The Illuminator keeps that; this one only has to look
## like it can reach further than it should.
##
## ⚠ IT IS WRITTEN IN TWO PLACES AND BOTH ARE LOAD-BEARING: here, which is what the
## roster and the suites ask, and `SenseiBoss.tscn`'s `Rig.height`, which is what
## actually gets drawn. Every other boss in this roster carries the same pair.
const RIG_H: float = 99.0

# ── the cuts ────────────────────────────────────────────────────────────────
## IAI. The single stroke, drawn from the sheath along his facing. It passes THROUGH
## him — see the header — so `LANE_LEN` is the reach on EACH side and the tell is
## centred on his body rather than fanned out in front of it.
##
## ⚠ THE TELL IS 0.85 s, WHICH IS THE LONGEST ON THE ROSTER (the Eraser's `unmake`, its
## own P3 signature, is 0.7). It has to be: the counter is to cross the lane, the lane
## passes through the boss, and a player has to be able to cover roughly his own body
## width before it lands. Shorten this and the fight stops having an answer.
const IAI_TELL: float = 0.85
const IAI_LEN: float = 460.0
const IAI_WIDTH: float = 34.0
const IAI_DAMAGE: int = 30

## STEP. He closes to a fixed distance and cuts from there. Its job is to delete
## "stand far away" as a plan: the lane is the same lane, and the range you bought is
## spent in one move. Shorter tell than `iai` because the reposition IS half the tell.
const STEP_TELL: float = 0.55
const STEP_RANGE: float = 96.0
const STEP_LEN: float = 300.0
const STEP_WIDTH: float = 30.0
const STEP_DAMAGE: int = 22

## CROSSGUARD (P2+). Two lanes at ninety degrees, fired together. Turns "get off the
## line" into "get into the right QUADRANT" — the same question one rung harder, which
## is how this roster is supposed to escalate (by what the fight asks, not by HP).
const CROSS_TELL: float = 0.80
const CROSS_LEN: float = 380.0
const CROSS_WIDTH: float = 28.0
const CROSS_DAMAGE: int = 24

## SHEATHE (P2+). He puts the blade away. Nothing comes out of it — this is a pure
## RECOVERY beat and the only window in the fight where he is not asking a question.
##
## ⚠ A BOSS ATTACK THAT DOES NO DAMAGE IS DELIBERATE AND IT IS THE POINT OF HIM. A
## quick-draw only reads as a quick-draw if you have seen the blade go away; and a
## fight built on committed strokes needs a beat where the player may commit too, or
## "punish the recovery" is advice with nowhere to land. It is in the table so the
## cadence includes it, and so it can be asserted rather than hoped for.
const SHEATHE_HOLD: float = 0.9
const SHEATHE_RADIUS: float = 120.0

## KESA (P3). The signature. Five lanes fanned around him with ONE deliberate gap, so
## the whole floor is cut except one wedge and the player is being TOLD where to stand.
##
## ⚠ THE GAP IS A CONSTANT AND ITS WIDTH NEVER ROLLS. An attack whose entire content is
## "be here" has to mean the same thing every time it is cast or it is not a lesson, it
## is a dice roll — the same rule the Eraser's `unmake` states about its corridor. What
## rolls is only WHERE the gap points, which is what stops it being memorised as a
## corner of the room.
const KESA_TELL: float = 0.95
const KESA_LANES: int = 5
const KESA_LEN: float = 420.0
const KESA_WIDTH: float = 26.0
const KESA_DAMAGE: int = 26
const KESA_STAGGER: float = 0.07


func boss_title() -> String: return "THE SENSEI"
func boss_artist() -> String: return "ink, one stroke, no correction"
## THE BILLING. Not "master swordsman" — the roster's epithets say which rung of the
## artistic ladder a body stands on, and his rung is the one where the drawing stops
## being corrected at all. It also has to carry the promise for a player who has
## forgotten the dojo twenty floors ago: they should read this and remember a room.
func boss_epithet() -> String: return "the one who said he would be here"
func bark_suffix() -> String: return "sensei"
## He does not redraw the page. He CUTS it, once, and the cut is the drawing.
func redraw_style() -> StringName: return &"cut"
func boss_accent() -> Color: return TURNED
func boss_tint() -> Color: return JADE
func boss_rig_height() -> float: return RIG_H
## ⚠ `swordsaint`, NOT `brawler`. The preset is what puts a blade in the rig's hand,
## and a quick-draw boss holding nothing is a fight about a weapon nobody can see.
func boss_preset() -> String: return "swordsaint"


## ⚠ THE FASTEST CADENCE ON THE ROSTER, AND IT IS HALF OF ONE DECISION. See the ⚠ in
## the header: his tells are the longest anyone gets, so without a tight cadence the
## fight is a series of long pauses and the player crosses the lane once and waits. The
## two numbers are one knob. `BossRoster` also gives him `speed_scale` 1.55 — he closes
## the gap you just made, which is the third face of the same idea.
func phase_cooldown(p: int) -> float:
	match p:
		1: return 1.9
		2: return 1.4
		3: return 1.0
	return 1.6


func _phase_attack_ids(phase: int) -> Array:
	match phase:
		1: return ["iai", "step"]
		2: return ["iai", "step", "crossguard", "sheathe"]
		3: return ["kesa", "crossguard", "iai", "sheathe"]
	return []


## RAISE for the draws — every one of them starts with the arm going up and the blade
## coming out. `sheathe` is the one that goes the other way, and GATHER is the closest
## thing the rig has to putting something away.
func gesture_for(id: String) -> int:
	return CharacterRig.GestureKind.GATHER if id == "sheathe" \
		else CharacterRig.GestureKind.RAISE


func _attack_duration(id: String) -> float:
	match id:
		"iai": return IAI_TELL + 0.45
		"step": return STEP_TELL + 0.45
		"crossguard": return CROSS_TELL + 0.5
		"sheathe": return SHEATHE_HOLD + 0.25
		"kesa": return KESA_TELL + KESA_STAGGER * float(KESA_LANES) + 0.5
	return 1.0


func _perform(id: String) -> void:
	match id:
		"iai": _atk_iai()
		"step": _atk_step()
		"crossguard": _atk_crossguard()
		"sheathe": _atk_sheathe()
		"kesa": _atk_kesa()


# ---------------------------------------------------------------- the moveset
## IAI. One stroke along the bearing to the hero, through the body and out both sides.
func _atk_iai() -> void:
	_cut(_bearing(), IAI_LEN, IAI_WIDTH, IAI_TELL, IAI_DAMAGE)


## STEP. Close first, then cut. The reposition is instant and DELIBERATELY visible —
## it happens before the tell, so the player sees where the line will be from and has
## the whole wind-up to answer it. A blink that landed mid-tell would move the lane
## after it was drawn, which is the one thing a telegraph may never do.
func _atk_step() -> void:
	if is_instance_valid(_hero):
		var to: Vector2 = _hero.global_position - global_position
		if to.length() > STEP_RANGE:
			# Straight along the ground: a swordsman closing distance walks, and a
			# vertical component here would put him inside the floor or above it.
			var step_dir: Vector2 = Vector2(signf(to.x), 0.0)
			if step_dir == Vector2.ZERO:
				step_dir = Vector2.RIGHT
			global_position += step_dir * (to.length() - STEP_RANGE)
			Juice.shake_camera(3.0)
	_cut(_bearing(), STEP_LEN, STEP_WIDTH, STEP_TELL, STEP_DAMAGE)


## CROSSGUARD (P2+). Two lanes at ninety degrees, telegraphed together and landing
## together, so the safe ground is a quadrant rather than a side.
func _atk_crossguard() -> void:
	var d: Vector2 = _bearing()
	_cut(d, CROSS_LEN, CROSS_WIDTH, CROSS_TELL, CROSS_DAMAGE)
	_cut(d.orthogonal(), CROSS_LEN, CROSS_WIDTH, CROSS_TELL, CROSS_DAMAGE)


## SHEATHE (P2+). The blade goes away and nothing comes out. See the ⚠ on
## `SHEATHE_HOLD`: this is the fight's only offered window, and it does no damage on
## purpose. The circle is drawn so the beat is READ as a beat — a boss that simply
## stopped for a second would look like a bug or a stutter.
func _atk_sheathe() -> void:
	summon_circle(global_position, Elements.Element.WIND, SpellTier.Tier.QUICK,
		SHEATHE_RADIUS, SHEATHE_HOLD, true)


## KESA (P3). Five lanes around him, one wedge left open.
##
## The gap's bearing is rolled per cast and the lanes are laid at even angles skipping
## it, so the answer is always "find the gap" and never "stand where it was last time".
func _atk_kesa() -> void:
	var gap: float = randf() * TAU
	summon_circle(global_position, Elements.Element.WIND, SpellTier.Tier.ULT,
		KESA_LEN * 0.4, KESA_TELL, true)
	for i: int in KESA_LANES:
		# Even angles around the circle, offset so none of them lands ON the gap. With
		# `KESA_LANES` odd, stepping by TAU/(lanes+1) from the gap leaves exactly one
		# unfilled wedge and spaces the rest evenly, which is what makes the safe
		# ground findable at a glance instead of measurable.
		var a: float = gap + TAU * float(i + 1) / float(KESA_LANES + 1)
		var dir := Vector2.RIGHT.rotated(a)
		var delay: float = KESA_STAGGER * float(i)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_instance_valid(self) or _bphase == BPhase.DEAD:
				return
			_cut(dir, KESA_LEN, KESA_WIDTH, KESA_TELL, KESA_DAMAGE))
	Juice.zoom_pull_camera(0.14, 0.55)


# ------------------------------------------------------------------- internals
## Where the blade is pointing. FLATTENED toward the horizontal, because a lane that
## can point steeply up or down is a lane a grounded player cannot cross — the counter
## in this whole fight is lateral movement, and a near-vertical cut takes it away.
func _bearing() -> Vector2:
	if not is_instance_valid(_hero):
		return Vector2(signf(scale.x) if scale.x != 0.0 else 1.0, 0.0)
	var to: Vector2 = _hero.global_position - global_position
	to = Vector2(to.x, to.y * 0.28)
	return to.normalized() if to != Vector2.ZERO else Vector2.RIGHT


## ONE CUT: the telegraph, then the blade along it.
##
## ⚠ EVERY LANE IN THIS FIGHT GOES THROUGH THIS FUNCTION, and the reason is the rule
## the whole boss rests on — a cut passes THROUGH his body and out both sides. That is
## one line of arithmetic (`lane_tell` fans forward from `global_position`, so the tell
## is emitted from a point half a length BEHIND him) and it would be forgotten by
## exactly one attack added later, which is the attack that would make the fight
## unfair without anybody being able to say why.
func _cut(dir: Vector2, length: float, width: float, windup: float, damage: int) -> void:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var behind: Vector2 = global_position - d * length
	# ⚠ BOTH HALVES ARE TELEGRAPHED AND THAT IS NOT OPTIONAL. `lane_tell` fans FORWARD
	# from the body, so on its own it would mark the half of the line in front of him
	# while the blade below cuts `2 * length` centred on him — a telegraph that
	# under-reports its own attack, which is the one thing a tell may never do. The back
	# half is marked with a bare `_emit_telegraph` rather than a second `lane_tell`,
	# because `lane_tell` also calls `_spawn_caster_signal` and only ONE of the two
	# would ever reach the matching `_free_caster_signal` in its callback — two signals
	# spawned, one freed, on every cut of the fight.
	_emit_telegraph({
		"style": Telegraph.Style.LANE, "pos": global_position,
		"accent": boss_accent(), "windup": windup,
		"line": true, "length": length, "width": width,
		"angle": (-d).angle(), "aim": -d, "reach": length,
		"no_resolve": true,
	})
	lane_tell(d, length, width, windup, func() -> void:
		# ⚠ A BEAM, NOT `HorizonArc`. The arc is the Swordsaint's TRAVELLING crescent —
		# it has a real position over time and is answered by out-running or jumping its
		# height band. That is a different question from the one this fight asks, and a
		# spell that arrives later than its tell would make a line you crossed correctly
		# hit you anyway. `BeamSpell` resolves instantly along the line, which is what
		# was drawn on the floor.
		var beam: Node = spawn_spectacle("res://scripts/combat/BeamSpell.gd",
			Elements.Element.WIND, SpellTier.Tier.HEAVY)
		if beam == null:
			return
		beam.call("fire", behind, d, TURNED, length * 2.0, width, damage, "wind")
		# Replicated: a client that could not see the cut would be reading an unfair
		# fight, and this one is ALL cut.
		_bfx("beam", {"pos": behind, "dir": d, "col": TURNED, "len": length * 2.0,
			"w": width, "fx": "wind", "el": Elements.Element.WIND})
		Juice.on_hit({"shake": 6.0, "sfx": "melee_swing", "hitstop": 0.04}))
