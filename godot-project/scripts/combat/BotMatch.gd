class_name BotMatch
extends Node2D
## BOT vs BOT, WATCHABLE — and now a MATCH rather than an exhibition.
##
## The maker's note, verbatim, after watching it: *"yo the whole watch bots thing is
## awesome — like it needs them to start equal and the camera needs to follow it
## cinematically please so the audience can see it all all the time. make sure its
## good like video quality and the sound effects need to be improved please. and of
## course they need health bars, and to move around so that they can die and the
## watch can end. but give them health etc based on their characters, who they are,
## damage types"*.
##
## ---------------------------------------------------------------------------
## ⚠ WHY THE FIGHT NEVER ENDED. Three independent reasons, all of them measured by
## reading the code they live in, and all three had to be fixed for a bout to resolve:
##
##   1. THE RING-OUT MODEL WAS ON. `VersusArena.showcase_ringout` defaults to TRUE
##      and this scene never set it, so `Hero.take_damage` piled onto `damage_pct`
##      and NEVER DRAINED HP. Nothing that watches HP could ever see a knockdown.
##   2. HP DEATH SELF-HEALS. Turning the ring-out model off is not enough. Outside a
##      run and outside a net session, `Hero._die()` runs `hp = max_hp` IN THE SAME
##      CALL as the fatal hit. So HP never rests at zero for even one frame, and
##      `VersusArena._poll_showcase_end` / `ClipDirector._check_knockdown` — which
##      both poll `hp <= 0` once a frame — can never fire. The fighters on this stage
##      were, literally, immortal. The signal `health_changed` DOES report `hp == 0`,
##      because `take_damage` emits it before calling `_die`; that is the only honest
##      hook, and it is what this file listens to.
##   3. THERE WAS NO TERMINAL STATE ANYWHERE. `_poll_showcase_end` deliberately
##      RESETS the bout (it is a sparring loop, by design, so the clip camera keeps
##      rolling), and a stock-out routes to `_restock`, which refills both sides and
##      carries on. Even a working knockdown would only have started the next round.
##      Nothing in the scene could ever say "this one is over".
##
## So the match spine lives HERE: this node holds the win condition, the round clock
## and the result beat, and `VersusArena` stays exactly the exhibition stage it is.
##
## ---------------------------------------------------------------------------
## EQUAL FOOTING, CHARACTERFUL STATS — the two halves of the maker's ask, which pull
## against each other, resolved as:
##
##   FOOTING is mirrored and identical. Both fighters spawn the same distance from
##   the centre of the fight floor, on the same flat ground, facing each other, at
##   the same bot tier, on the same clock, with the same cooldowns. Neither side is
##   handed an opening advantage of any kind, and because this stage is NOT
##   left-right symmetric (the terraces and the bluff are all on the right), the
##   sides SWAP on every rematch so nothing the map gives away accrues to one class.
##
##   STATS are not identical, because a Juggernaut with an Arcanist's health is not a
##   Juggernaut. `CLASS_VITALITY` scales the shared HP pool by who the fighter IS.
##   It is a multiplier on ONE shared number, so the knob stays a match-length knob:
##   change `fighter_hp` and every matchup scales together.
##
## ⚠ AND THAT IS THE WHOLE OF IT. Nothing here touches damage, cooldowns, reaction
## time, error rate or what a bot can see. Both fighters get the same stock
## `BotController` + `BotBrain` + `BotProfile` the game ships. If a matchup is
## lopsided that is a BALANCE FINDING to report — `tools/botmatch_sim.gd` measures it
## — and never something to paper over with a handicap. A clip of a rigged fight is
## worthless for finding bugs and dishonest as marketing.
##
## ⚠ CLASS_VITALITY IS LOCAL TO THIS MODE. It is applied to the two bodies this scene
## stands up, after the arena has built them. It does not touch the tower, the duel,
## free play or the class definitions — per-class vitality does not exist as a real
## stat anywhere in this project yet, and inventing one inside a spectator mode would
## be the wrong place to put it.

const ARENA_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const ARENA_SCRIPT: String = "res://scripts/combat/VersusArena.gd"
const BOT_MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
## LEAVING GOES TO THE TITLE, NOT THE HUB.
##
## This used to be `res://scenes/Main.tscn` — the parked v0.0 town, which the
## design doc cuts permanently. The run spine was moved off it,
## but every SANDBOX exit still pointed there, so backing out of a bot match
## dropped you into a different game's village with nothing to do in it. The maker
## found it immediately and asked why it was there.
##
## The Lobby is the boot scene, works on a phone, and is where every other exit in
## the game now lands. The hub stays on disk and stays reachable as an opt-in
## detour from the run-summary card; it is simply not somewhere you arrive by
## accident.
const HUB_SCENE: String = "res://scenes/ui/Lobby.tscn"

const CLASS_LABELS: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]
const TIER_LABELS: Array[String] = ["Easy", "Normal", "Hard", "Impossible"]

## ══════════════════════════════════════════════════════════ YELLOW vs BLUE
## THE TWO CORNERS, AND THE ONLY PLACE THEY ARE WRITTEN DOWN.
##
## The maker's ask was literally "an intro screen like yellow vs blue", and the reason
## that could not be honoured before is that BOTH fighters were painted from
## `GameState.colourway` — ONE global value, shared, so a bot match was two identically
## coloured stickmen and the audience had to track which was which by position alone.
## `Hero.COLOURWAYS` has no yellow at all, so there was nothing to pick either.
##
## So the SIDE decides the colour here, not the class and not the save file: left is
## yellow, right is blue, always, in every bout. The intro card, the name plates and
## the bodies all read from this one array, which is what makes it impossible for the
## card to promise a yellow fighter and the stage to draw a blue one.
##
## ⚠ THIS DOES NOT REPLACE THE PER-CLASS TINT ANYWHERE ELSE. `ClassInfo.color_for` is
## still the class's colour on the select screen, in the tower and in the hub. It is
## only in a MATCH — where the question is "which corner", not "which class" — that
## the side wins.
const SIDE_COLORS: Array[Color] = [
	Color(1.00, 0.82, 0.22),   # LEFT  — chalk yellow
	Color(0.30, 0.64, 1.00),   # RIGHT — ink blue
]
## Anything that is neither corner (a missing fighter, a draw).
const FALLBACK_TINT: Color = Color(0.85, 0.88, 0.95)


## The corner colour. Static so the intro card, the plates and the suite all ask the
## SAME function rather than three copies of an index-into-an-array.
static func side_color(side: int) -> Color:
	# ══ THE CLASS WINS WHEN THE CLASSES CAN BE TOLD APART ═══════════════════
	# Maker: *"can we like make the stick fighters colours relvant to their class
	# cleric yellow warlock purple etc."*.
	#
	# `ClassInfo.color_for` has always held exactly that — Cleric pale gold, Warlock
	# violet, Cryomancer ice blue — and this file overrode it with a corner palette
	# because of the problem stated above: `GameState.colourway` painted BOTH fighters
	# one shared colour, so the audience had nothing to track. Corner colours fixed
	# that by throwing the class away, which is a different loss.
	#
	# ⚠ AND THE FALLBACK IS NOT ABOUT MIRROR MATCHES ONLY. The Shadowblade and the
	# Warlock are the SAME violet in `ClassInfo` — `Color(0.6, 0.35, 0.9)` twice — so
	# "same class" would not have caught the worst case. `_resolve_side_tints`
	# measures the actual colour distance and hands the bout back to yellow-vs-blue
	# whenever the two classes are not separable, which covers mirror matches for free.
	#
	# ⚠ AND IT IS STILL ONE FUNCTION. The intro card, the corner plates, the result
	# card and the bodies all read this, which is what makes it impossible for the
	# card to promise one colour and the stage to draw another. Resolving the class
	# tint HERE rather than at each of those call sites is what keeps that true.
	if side >= 0 and side < side_tint.size():
		return side_tint[side]
	if side < 0 or side >= SIDE_COLORS.size():
		return FALLBACK_TINT
	return SIDE_COLORS[side]


## Below this RGB distance two class colours are the same colour to an audience, and
## the bout falls back to the corner palette. The Shadowblade/Warlock pair sits at
## exactly 0.0, so this is not a hypothetical.
const MIN_CLASS_SEPARATION: float = 0.30

## Resolved per bout by `_resolve_side_tints`. EMPTY means "use the corner palette".
##
## A static for the same reason every other knob in this file is one: the intro card
## and the suite reach `side_color` without an instance. Cleared in `_exit_tree`,
## because a static outlives the scene and a stale pair would repaint the next bout.
static var side_tint: Array[Color] = []


## Pick the two body colours for this bout: the classes' own, unless they are too
## close to tell apart. See `side_color`.
func _resolve_side_tints() -> void:
	side_tint = []
	var a: Color = ClassInfo.color_for(_fighter_class[0])
	var b: Color = ClassInfo.color_for(_fighter_class[1])
	var d: float = Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
	if d < MIN_CLASS_SEPARATION:
		return   # indistinguishable — yellow vs blue, and the corner is the read
	side_tint = [a, b]

## WHO THEY ARE, as a multiplier on the shared HP pool. Ordered like CLASS_LABELS.
##
## Derived from each class's own fantasy line in `ClassInfo.CLASSES` and its kit in
## `Hero.CLASS_CONFIG` — a tank that trades melee range for a block is supposed to
## outlast a zoner that never wants to be touched, and a pure-melee class that has to
## cross the whole stage to do anything is supposed to survive the crossing.
##
## ⚠ THE BRAWLER NUMBER IS DELIBERATE AND IT IS NOT A HANDICAP. The bot sim measures
## the Brawler winning 14% at Normal — the pure-melee class is the one most hurt by
## the reflex layer working, because everything it does requires being in range. The
## fix for that is its KIT, not its health bar, and that is another agent's file. The
## 1.15 here is what its own class card already promises ("knockout" bruiser) and it
## is applied before any fight is run, not tuned until it wins.
##
## ⚠ RE-TUNED 2026-08-05 AGAINST A REAL 72-BOUT SWEEP — every one of the 36 pairings,
## both side orders, 72/72 resolved by KO, zero draws. Measured win rates BEFORE:
##
##     CLERIC 75%  JUGGERNAUT 69%  STORMCALLER 69%  WARLOCK 63%  SHADOWBLADE 56%
##     ARCANIST 44%  BRAWLER 31%  CRYOMANCER 25%  SWORDSAINT 19%
##
## — a 56-point spread, which means two thirds of matchups are decided by the pairing
## rather than by the fight. For a mode whose whole product is a watchable duel that is
## the defect, not a curiosity.
##
## Two things the sweep settled that had been argued from stale numbers:
##   · THE `bolt_heal` HYPOTHESIS WAS RIGHT AND IS ALREADY ACTIONED. Cleric 4->2 and
##     Warlock 3->2 are in the tree, and the pair fell 91->75 and 84->63. Lifesteal is
##     no longer the top offender, so do NOT cut the heal again — the heal is the class.
##   · CRYOMANCER AT 25% IS A NEW FINDING NOBODY HAD FLAGGED, and it is the maker's
##     "the ice class needs a buff" independently confirmed by measurement.
##
## ⚠ AND THIS IS A HANDICAP, WHICH THIS FILE ELSEWHERE SAYS TO REPORT RATHER THAN PAPER
## OVER. Stated plainly: it makes every matchup watchable without touching the tower,
## and it is NOT the same as fixing the kits. The real Swordsaint fix is its `cast_cd`
## 0.45 (slowest in the roster) and `blast_cd` 3.0 (longest), both outliers in their own
## columns; the real Brawler fix is its kit. Those are separate work.
## ⚠ RE-MEASURED 2026-08-05 ON A REAL ROUND-ROBIN, and the previous numbers came
## from EIGHT HAND-PICKED PAIRINGS. 72 bouts, every unordered pair twice with the
## sides swapped, drops OFF (a random Tier 3 swings a duel harder than any class
## difference this is measuring). 72/72 resolved, 0 draws:
##
##     STORMCALLER 75%   ARCANIST  50%   SHADOWBLADE 44%
##     WARLOCK     75%   BRAWLER   50%   CLERIC      38%
##     JUGGERNAUT  50%   CRYOMANCER 50%  SWORDSAINT  19%
##
## The last pass WORKED on four of them — Cryomancer 25 -> 50, Brawler 31 -> 50,
## Juggernaut 69 -> 50 — and OVERSHOT Cleric, 75 -> 38. Stormcaller and Warlock both
## got worse.
##
## ⚠ ONLY THE OUTLIERS MOVE, AND THAT IS A STATISTICS RULE RATHER THAN CAUTION. Each
## class played 16 bouts, so the standard error on a 50% rate is about 12 points:
## 44% and 50% are the same number. Moving the middle of this table would be tuning
## noise into the game and then measuring the noise again next time.
##
## ⚠ AND SWORDSAINT IS STILL THE THING THIS CANNOT FIX. It carries the largest
## vitality in the table, it was given a longer dash, and it has not moved off 19%.
## A class that needs +45% health to reach parity does not have a health problem. The
## finding to report is that its KIT loses, and this file's own header says to report
## that rather than paper over it — so the number below buys watchability, and it is
## not a fix.
const CLASS_VITALITY: Array[float] = [
	0.98,  # ARCANIST     50% — UNCHANGED, dead centre.
	0.85,  # SHADOWBLADE  44% — UNCHANGED. Inside the noise band; 44 and 50 are the
		   #               same number at n=16 and moving it would be tuning a coin.
	1.30,  # BRAWLER      50% — UNCHANGED. Was 31%; the 1.30 did its job. Its KIT is
		   #               still the real fix — everything it does needs to be in range.
	1.20,  # JUGGERNAUT   50% — UNCHANGED. Was 69%; the 1.20 did its job.
	0.98,  # CLERIC       38% — OVERSHOT, from 75%. 0.90 cut a class that sustains AND
		   #               carried an above-average bar, and cut it past the middle.
		   #               Back toward 1: take the bar, keep the heal.
	1.10,  # CRYOMANCER   50% — UNCHANGED. Was 25% and second worst; the maker's "the
		   #               ice class needs a buff", measured and landed.
	0.68,  # STORMCALLER  75% — CUT, and it went UP from 69 under the last pass. The
		   #               most mobile body in the game is not paying for the mobility
		   #               anywhere else, so it pays here.
	0.78,  # WARLOCK      75% — CUT, from 63%. Attrition wins a 22-second bout on its
		   #               own; the shorter the fight, the less that should be true.
	1.45,  # SWORDSAINT   19% — RAISED, and read the ⚠ above before trusting it. It was
		   #               already carrying the largest number in this table at 1.25 and
		   #               had a longer dash, and it did not move a single bout. This
		   #               buys watchability. It is not a fix.
]

## STATICS, and they survive the scene reload every matchup change performs. A
## member would reset to its default on the first change and the maker would never
## be able to leave the opening pairing — the same reason `VersusArena`'s duel knobs
## are statics.
static var class_a: int = 6      # STORMCALLER
static var class_b: int = 5      # CRYOMANCER
static var difficulty: int = 3   # the tier that plays the whole kit (combo 0.90)
## Scaled per fighter by CLASS_VITALITY.
##
## ⚠ 190 -> 320, MATCHING `VersusArena.SHOWCASE_HP`. The old value's reasoning ("a clip
## needs the fight to END") was right about clips and wrong about this mode: a CAPTURE
## already overrides it (`make_clip.py --hp 500`), so 190 only ever governed the fight a
## HUMAN opens — and at 190 that fight is a demolition. MEASURED across 72 bouts:
## p10 3.1 s / median 5.3 s / p90 10.9 s, with 44% ending under five seconds and 31%
## won with the winner still above 80% health. There is no read, no comeback and often
## no second exchange.
## ⚠ 320 -> 440. Maker, watching: *"give the bots more health or make their attacks
## do lightly less damage these are quick fights"* — so both, and this is the half that
## touches nothing outside the duel. `_apply_matchup` writes `max_hp`/`hp` AFTER
## `configure_class`, so this number overrides `CLASS_CONFIG.hp` and
## `TuningConfig.hero_vitality_mult` in this mode only; the tower is untouched.
## The damage half is the Shadowblade's `blade_damage` 9 -> 6 in `Hero.CLASS_CONFIG`.
##
## ⚠ RAISE `round_seconds` WITH IT OR LONGER BOUTS GET CALLED ON THE HEALTH BAR
## instead of finishing — the two are one dial in two places, and a decision on
## points is exactly the anticlimax this change is meant to remove.
static var fighter_hp: int = 440
## Which side each class starts on. Flipped on every rematch so the stage's own
## left/right asymmetry cannot accrue to one class over a series. See the footing
## note at the top of this file.
static var swap_sides: bool = false
## Roll straight into the next bout after the result card. TRUE for the maker
## watching (it becomes a highlight reel); a capture tool turns it OFF so the clip
## ends where the match does.
static var auto_rematch: bool = true

## ⚠ HOW LONG THE "VS" CARD HOLDS BEFORE ANYBODY MOVES — and why it is a STATIC and
## not a const. `tools/botmatch_sim.gd` runs this exact scene over many pairings and
## `tools/directed_clip_capture.gd` films it; a ceremony charged to every one of them
## is throughput a sim never asked for. A tool sets this to 0 and the card is skipped
## whole. Set to <= 0 to disable.
##
## It is ALSO skipped automatically when there is no real display (see `_ceremony()`),
## so the headless suites and the sim pay nothing without having to know this knob
## exists at all.
## ⚠ 1.8 -> 3.2. Maker: *"before the fight starts I need some time to show x vs z on
## the screen as the stick figures stand there like a couple seconds"*. The card was
## already there and already held both fighters with the tree paused — it was simply
## too short to read two class names, register the two bodies, and land the word
## FIGHT. At 1.8 s, minus a 0.28 s fade each end and the 0.45 s FIGHT beat, the
## readable hold was under a second. This gives it the couple of seconds asked for.
##
## It is the FIRST thing in every clip, so it is also the thumbnail.
static var intro_seconds: float = 3.2
## Do the fighters talk? Same reasoning: on by default for a watch, off for anything
## measuring throughput, and forced off with no display.
static var taunts: bool = true

## ------------------------------------------------------------------ THE INTRO CARD
## Ink-sketchbook palette, lifted verbatim from `Lobby` / `RunSummary` so the pre-fight
## card, the title screen and the run summary read as the same hand.
const CARD_CHALK: Color = Color(0.93, 0.92, 0.86)
## (`CARD_GRAPHITE` lived here and is gone with the tier caption it was the colour of.
## Kept out rather than left declared: an unused half of a palette invites the next
## edit to find a use for it, and the card is deliberately down to two lines now.)
## The dim over the stage. Heavier than the result card's 0.42 — the fighters are
## standing still behind it and the card is the only thing worth reading.
const CARD_DIM: Color = Color(0.055, 0.052, 0.075, 0.62)
## Typography, in the shape `Boss.card_style()` established for a big moment: one
## oversized head, one small caption, a fat outline so it survives a busy backdrop.
const CARD_VS_SIZE: int = 44
const CARD_NAME_SIZE: int = 17
const CARD_FIGHT_SIZE: int = 40
## The colour swatch above each fighter's name — the card's promise about which body
## is which, in the one form that needs no reading.
const SWATCH_SIZE: Vector2 = Vector2(62.0, 9.0)
## Fade in / fade out, bracketing the hold. Both are inside `intro_seconds`.
const INTRO_FADE: float = 0.28
## "FIGHT" holds this long AFTER the tree unpauses — the fight is already live under
## it, which is the whole point: the word lands ON the first step, not before it.
const INTRO_FIGHT_BEAT: float = 0.45

## ---------------------------------------------------------------------- TAUNTS
## Per-speaker rate limit, in REAL seconds, and it deliberately shares
## `Bark`'s own `bark_last` meta key: a fighter that has just barked must not
## immediately taunt over its own bubble, and one bubble per body is a hard rule
## (`Bark.BUBBLE_NAME`). Same 3.0 s window `Bark.COOLDOWN` uses.
const TAUNT_COOLDOWN: float = 3.0
const TAUNT_META: StringName = &"bark_last"
## The bubble node's name. THE SAME ONE `Bark` uses, so the two systems can never
## stack two bubbles on one head — whoever gets there first builds it, everybody
## after that reuses it.
const TAUNT_BUBBLE_NAME: StringName = &"BarkBubble"
const TAUNT_BUBBLE_SCENE: String = "res://scenes/SpeechBubble.tscn"
## What counts as a BIG hit worth gloating about, as a fraction of the victim's own
## max HP. Below this a taunt on every exchange is a tickertape.
const BIG_HIT_FRACTION: float = 0.12
## Below this fraction, the fighter says so. Once per bout per fighter.
const LOW_HEALTH_FRACTION: float = 0.28

## ------------------------------------------------------------------ MATCH RULES
## Where the two fighters stand, as a distance either side of the CENTRE OF THE FIGHT
## FLOOR. `VersusArena`'s own showcase spawns are 520 / 1080, whose midpoint is 800 —
## 80 px right of the flat ground's actual centre, so one fighter started nearer the
## stairs than the other did the mound. Mirrored about the real centre instead.
const FLOOR_CENTRE_X: float = 720.0     # (40 + 1400) / 2, the main walkable ground
const SPAWN_SPREAD: float = 280.0       # same 560 px gap the showcase always used
## ⚠ 716 -> 760: THEY WERE SPAWNING 64 PX IN THE AIR. Maker: *"their spawn shouldnt
## not be in the ait like they should spawn on the ground"*. `VersusArena.GROUND_TOP`
## is 780 and a hero's origin is the CENTRE of its collider, so a body rests at about
## `780 - 17`. At 716 both fighters dropped four body-heights before the bell — the
## first thing in every clip was two men falling.
##
## Deliberately a few px ABOVE the rest position rather than exactly on it. Landing is
## free and invisible; starting BELOW is not, because depenetration ejects a box whose
## midline is under the floor's — that is precisely the floor-2 blocker this project
## already spent a session on.
const SPAWN_Y: float = 760.0
## Off the rock entirely — a fall nothing recovers from. The terrain spans x 40..1965
## (VersusArena.TERRACES), so anything outside this is in the air over a blast zone.
const RIM_LEFT: float = 24.0
const RIM_RIGHT: float = 1980.0
## Nobody watches a stalemate. If neither fighter has gone down by here the match is
## decided on the health bars, which is a real result and not a cop-out: the fighter
## who took less punishment over 50 seconds won the fight the audience watched.
##
## A STATIC rather than a const so `tools/botmatch_sim.gd` can run a shorter round
## without editing the number the maker watches. GAME seconds, so hit-stop stretches
## the wall clock but never the fight.
## ⚠ 50 -> 75, AND IT MOVES WITH `fighter_hp`. At 440 health and a calmer cast
## cadence a real bout can now run past fifty seconds, and a fight that ends on the
## clock is scored on the health bar rather than won — see `_decide`'s DECISION arm.
static var round_seconds: float = 75.0

## ══ THE BOTS CARRY A TIER 3 DROP IN A SHOWCASE DUEL ═════════════════════════
## Maker: *"the bots should have the cool spells when 1 vs 1"*. They did not, and
## the reason was structural rather than an oversight: `build_tier3()` — the void,
## chronostasis, equinox, roulette — are BOSS DROPS, found on a floor mid-run. A
## duel has no floor, so a bot duel could only ever show nine class kits, and the
## four loudest things in the game were unreachable in the one mode whose entire
## job is to produce footage.
##
## Granted through `SpellGrant.apply`, which is the real pickup path: it displaces a
## slot, remembers what it displaced, and carries the drop's own CHARGES — so a
## Chronostasis is a one-shot showpiece, not a spam button.
##
## ⚠ SHOWCASE ONLY. This is `BotMatch`, the bot-vs-bot scene. The played versus
## sandbox and the tower reach `VersusArena` without passing through here, so
## neither is touched.
## ⚠ ROLL THE MATCHUP. A content engine that always shoots STORMCALLER vs CRYOMANCER
## produces one clip nine times, and both of this scene's entry points defaulted to
## that pair: the Lobby button and `make_clip.py`. Set before `_ready` (the statics
## are read there) or pass `--random=1` to the capture tool.
##
## The two are always DIFFERENT classes — a mirror match is the one duel that cannot
## show a matchup — and the roll happens once, in `_ready`, so both fighters and every
## label downstream agree about who is fighting.
static var random_matchup: bool = false

static var drops: bool = true
## Which drop each side carries. -1 rolls. Set them to shoot a specific spell.
static var drop_a: int = -1
static var drop_b: int = -1

## ══ EACH CLASS'S SIGNATURE DROP ═════════════════════════════════════════════
## Maker: "give all the classes their tier 3 drop spells". A RANDOM roll meant a
## Swordsaint might open Equinox in one clip and Roulette in the next, so the clip
## showed the DROP and not the class — which is the opposite of what a per-class
## showcase is for.
##
## ⚠ THIS IS A MAPPING, NOT THE FEATURE ASKED FOR, AND THE DIFFERENCE IS REAL.
## There are SIX drops (`drop_ids()`: arc_of_fools, meteor_storm, the_void,
## chronostasis, equinox, roulette) and NINE classes, so three of these rows are
## shared. Giving every class one of its OWN means authoring three-plus new
## ult-weight spells, each with a bespoke spectacle — the existing four are
## rule-benders with their own drawing, not element recolours, and
## [[project_v2_class_identity_mandate]] rules out making the difference a tint.
## That build has not been done and this is not it.
##
## FOUR OF THESE ARE THE SPELL-TREE SPEC'S OWN LINKS
## (`docs/superpowers/specs/2026-08-04-spell-trees-and-progression-design.md` §4):
## Cleric→equinox, Warlock→the_void, Warlock→arc_of_fools, Arcanist→chronostasis.
## ⚠ I MOVED CHRONOSTASIS TO THE CRYOMANCER and the reason is checkable rather than
## taste: the spell's own `element` is ICE and its whole mechanic is freezing. The
## spec reaches it from the Arcanist as an "arcane control" TREE LINK, which is a
## different claim from whose signature it is.
## ⚠ NINE CLASSES, NINE DISTINCT DROPS — no row appears twice any more.
##
## This table used to pin six drops across nine classes, so three PAIRS shared, and
## two of the six (`arc_of_fools`, `meteor_storm`) were Tier 2 spells standing in for
## a Tier 3 that did not exist. That is the recolour problem in its purest form: two
## classes reaching the same boss reward and being handed the same spell.
##
## The five new ones each bend a different RULE of the game rather than carrying a
## bigger number — see the block on `SpellLibrary.build_tier3()`. `arc_of_fools` and
## `meteor_storm` stay in the Tier 2 pool; they are simply no longer anybody's
## signature reward.
const CLASS_DROP: Array[String] = [
	"roulette",      # 0 ARCANIST    — a dispatcher re-roll is the most arcane thing here
	"severance",     # 1 SHADOWBLADE — mark, wait, execute. Damage read off the victim
	"teardown",      # 2 BRAWLER     — no magic: the room IS the weapon
	"siegeworks",    # 3 JUGGERNAUT  — the ground obeys, and it takes the room away
	"equinox",       # 4 CLERIC      — the spec's link
	"chronostasis",  # 5 CRYOMANCER  — ICE element, and the mechanic IS freezing
	"the_circuit",   # 6 STORMCALLER — it stops choosing a direction. No radius at all
	"the_void",      # 7 WARLOCK     — the spec's link. Now unshared
	"zanshin",       # 8 SWORDSAINT  — one cut, worth more for everyone who walked in
]
## How close two health fractions have to be before a timeout is called a DRAW
## rather than a decision.
const DRAW_MARGIN: float = 0.04
## Real seconds the frozen KO frame holds before the result card MAY slam in. This
## is a MINIMUM, not the answer — see `_screen_is_quiet`.
const FREEZE_BEAT: float = 0.55
## ...and the ceiling on that wait. A spectacle that never finishes (or a future
## effect with a lifetime nobody re-checked here) must not be able to eat the card
## entirely, so the quiet gate gives up at this point and shows it regardless.
const RESULT_MAX_WAIT: float = 2.5
## How long the card holds before the next bout, when `auto_rematch` is on. Measured
## from when the card APPEARS, which is what this constant always claimed to mean —
## it was previously measured from the KO, so anything that delayed the card silently
## shortened it.
const RESULT_HOLD: float = 4.2

enum Outcome { NONE, KO, RINGOUT, DECISION, DRAW }

## The pre-fight card's own little state machine. VS holds both fighters on the card
## with the tree PAUSED; FIGHT unpauses and lets the word land over live combat; DONE
## is every frame after, and is also where a headless run starts.
enum Intro { VS, FIGHT, DONE }

var _arena: Node2D = null
var _readout: Label = null
var _labels: Dictionary = {}

## ---- the two fighters, in side order (0 = left, 1 = right) -----------------
var _fighters: Array[Node2D] = []
## Which `build_tier3()` index each side was handed, so the two differ.
var _granted_index: Array[int] = [-1, -1]
var _fighter_class: Array[int] = [-1, -1]
var _fighter_max: Array[int] = [1, 1]
var _fighter_hp_now: Array[int] = [1, 1]
## Latched at the decisive beat, so the plates show the KO state and not the value
## `Hero._die` heals it back to a microsecond later.
var _final_hp: Array[int] = [-1, -1]

## ---- match state ----------------------------------------------------------
var _clock: float = 0.0
var _outcome: int = Outcome.NONE
var _winner: int = -1                 # side index, or -1 for a draw
var _decided_at: float = -1.0         # REAL seconds (unscaled) when it was decided
var _card_shown_at: float = 0.0       # REAL seconds the card actually appeared (0 = not yet)
var _taunt_until: float = 0.0         # REAL seconds the newest taunt bubble clears
var _frozen: bool = false
var _result_card: Control = null
var _plates: Array[Dictionary] = []
var _clock_label: Label = null
var _music_band: int = -1

## ---- the pre-fight card -----------------------------------------------------
var _intro_card: Control = null
var _intro_row: Control = null
var _intro_fight: Label = null
var _intro_phase: int = Intro.DONE
## REAL (unscaled) seconds the card opened. Same clock `_freeze` uses, and for the
## same reason — the tree is paused under it, so nothing scaled can be trusted.
var _intro_at: float = 0.0

## ---- taunt book-keeping -----------------------------------------------------
var _first_blood: bool = false
var _said_low: Array[bool] = [false, false]


## The one-line hook, for a Lobby button or a dev menu:
##     BotMatch.enter(get_tree())
static func enter(tree: SceneTree) -> void:
	tree.paused = false
	tree.change_scene_to_file(BOT_MATCH_SCENE)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if random_matchup:
		_roll_matchup()
	# Statics BEFORE the scene instantiates — `VersusArena._ready` reads them all.
	# Reached BY PATH, never by `class_name`, for the autoload-at-parse-time reason
	# every capture tool in this project documents.
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script != null:
		arena_script.set("free_play", false)
		arena_script.set("showcase_a", _left_class())
		arena_script.set("showcase_b", _right_class())
		arena_script.set("showcase_difficulty", clampi(difficulty, 0, 3))
		arena_script.set("showcase_directed", true)
		arena_script.set("showcase_hp_override", fighter_hp)
		# ⚠ REASON 1 THAT FIGHTS NEVER ENDED. This static defaults to TRUE and this
		# scene never set it, so hits piled onto `damage_pct` and HP never moved. A
		# watch that cannot end is not a watch. HP death is the model that resolves.
		arena_script.set("showcase_ringout", false)
		# ⚠ TELL THE STAGE WHERE THE FIGHTERS WILL ACTUALLY STAND. `_adopt_fighters`
		# re-seats them at 720 +/- 280 AFTER the arena has finished building, so the
		# stage's own `SHOWCASE_SPAWN_A/B` are not where anybody ends up — and the left
		# one, 440, lands two pixels inside the cover block authored at 470. See
		# `VersusArena.SPAWN_FOOTPRINT_HALF`; the block moves, the footing does not.
		# ⚠ TYPED, NOT A BARE LITERAL. `VersusArena.spawn_keepout_x` is `Array[float]`,
		# and an untyped `Array` into a typed slot is the exact fault that left the duel
		# stage with no terrain for a week ("Invalid assignment of property or key").
		# Going through `Object.set()` rather than `=` does not make it safe — it only
		# moves where it surfaces, which here is `_spawn_keepout()`'s typed return, so
		# `_build_cover` would abort at its first line and cover would silently stop
		# existing with the cause two files away.
		#
		# The sibling call in `_exit_tree` already casts (`[] as Array[float]`), which is
		# the tell that somebody met this once and fixed one of the two sites.
		var keepout: Array[float] = [
			FLOOR_CENTRE_X - SPAWN_SPREAD, FLOOR_CENTRE_X + SPAWN_SPREAD]
		arena_script.set("spawn_keepout_x", keepout)
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(_arena)
	_adopt_fighters()
	_hide_duplicate_chrome()
	_build_overlay()
	_extend_pause_menu()
	_open_bout()
	_open_intro()


## ⚠ CLEAR THE SHOWCASE STATICS ON THE WAY OUT. They outlive this node, this scene
## and the scene change that leaves it — so walking from a bot match into the versus
## duel would hand the duel two bots and no player, with the cause two scenes back.
## `showcase_ringout` is restored to its shipped TRUE for the same reason in reverse:
## the played sandbox is a Smash stage and is supposed to be.
func _exit_tree() -> void:
	# ...and NEVER leave the tree paused. `_freeze` pauses on the decisive beat; a
	# scene change out of a frozen result card would otherwise hand the Lobby a
	# paused tree, which reads as the game having hung.
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	# The brain's drop overlay is keyed by instance id on a STATIC, so it outlives
	# this scene exactly the way the showcase statics below do. Unforgotten ids would
	# accumulate for the life of the process.
	for f: Node2D in _fighters:
		BotBrain.forget_drops(f)
	_set_rank_hud(true)   # the autoload outlives this scene; see _hide_duplicate_chrome
	# A static outlives the scene: a stale pair would repaint the next bout's fighters
	# in the last one's classes. Same reason the showcase statics below are cleared.
	side_tint = []
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script == null:
		return
	arena_script.set("showcase_a", -1)
	arena_script.set("showcase_b", -1)
	arena_script.set("showcase_directed", false)
	arena_script.set("showcase_hp_override", 0)
	arena_script.set("showcase_ringout", true)
	# Back to "ask the stage" — a later free-play or duel seats bodies somewhere else
	# entirely and must not inherit this match's footing.
	arena_script.set("spawn_keepout_x", [] as Array[float])


# ==========================================================================
# THE FIGHTERS — footing, stats, and the only honest death signal on this stage
# ==========================================================================

## Pick two DIFFERENT classes. Writes the statics rather than a local, because
## `_left_class` / `_right_class` / the VS card / the corner plates / the result card
## all read them, and a roll held anywhere else would have the card naming one pair
## and the arena building another.
func _roll_matchup() -> void:
	var n: int = CLASS_LABELS.size()
	if n < 2:
		return
	class_a = randi() % n
	class_b = randi() % n
	if class_b == class_a:
		class_b = (class_b + 1 + (randi() % (n - 1))) % n
	print("[botmatch] rolled %s vs %s"
		% [CLASS_LABELS[class_a], CLASS_LABELS[class_b]])


func _left_class() -> int:
	var a: int = clampi(class_a, 0, CLASS_LABELS.size() - 1)
	var b: int = clampi(class_b, 0, CLASS_LABELS.size() - 1)
	return b if swap_sides else a


func _right_class() -> int:
	var a: int = clampi(class_a, 0, CLASS_LABELS.size() - 1)
	var b: int = clampi(class_b, 0, CLASS_LABELS.size() - 1)
	return a if swap_sides else b


## Take the two bodies the arena built, put them on mirrored footing, give them the
## health their class earns, and subscribe to the one signal that can see a death.
##
## The arena spawns fighter A first, so tree order IS side order.
func _adopt_fighters() -> void:
	_fighters.clear()
	for n: Node in get_tree().get_nodes_in_group(&"hero"):
		if n is Node2D and is_instance_valid(n):
			_fighters.append(n as Node2D)
	if _fighters.size() != 2:
		return
	_fighter_class[0] = _left_class()
	_fighter_class[1] = _right_class()
	# Before anything paints: the card, the plates and the bodies all read
	# `side_color`, so the tints have to be settled before any of them ask.
	_resolve_side_tints()
	for side: int in 2:
		var f: Node2D = _fighters[side]
		var hp: int = _vital_hp(_fighter_class[side])
		f.set("max_hp", hp)
		f.set("hp", hp)
		_fighter_max[side] = hp
		_fighter_hp_now[side] = hp
		# ⚠ A SPECTATED BOUT HAS A LOSER AND MUST KEEP ONE. Maker: *"when they die in
		# spectating they shouldnt stand up they died"*. `Hero._die` outside a run
		# heals to full so the F6 feel toy never stops, which left this mode toppling
		# the rig of a live, full-health body — and anything that re-drove the rig
		# stood it back up. Set HERE rather than inferred in `Hero`, so free play, the
		# sandbox and the human duel keep the heal they were designed around.
		f.set("stay_dead", true)
		# MIRRORED FOOTING. Same distance from the centre of the fight floor, same
		# flat ground, facing each other.
		var x: float = FLOOR_CENTRE_X + (SPAWN_SPREAD if side == 1 else -SPAWN_SPREAD)
		f.global_position = Vector2(x, SPAWN_Y)
		f.set("facing", Vector2.RIGHT if side == 0 else Vector2.LEFT)
		_reseat_registry(f)
		# ⚠ THE ONLY DEATH SIGNAL THAT WORKS HERE. See reason 2 at the top of the
		# file: `Hero.take_damage` emits `health_changed(0, max)` and only THEN calls
		# `_die`, which heals straight back to full. Polling `hp` misses it every
		# time; the signal does not.
		if f.has_signal("health_changed"):
			f.connect("health_changed", _on_health_changed.bind(side))
		# ⚠ THE FLOATING BAR IS HIDDEN ON BOTH FIGHTERS FOR THE WHOLE MATCH. This mode
		# already has screen-space plates reading `STORMCALLER 418` in each corner, so
		# the over-the-head bar is the same number said twice — and on a 65 px stick
		# figure the bar plus its MP strip is PHYSICALLY LARGER THAN THE TORSO. On the
		# result frame it sits squarely on top of the winner, which is the one shot this
		# mode exists to produce.
		#
		# `_put_the_loser_down` used to hide only the loser's, which is why this went
		# unnoticed: the corpse was tidy and the winner wore a health bar for a hat.
		_hide_floating_bars(f)
		_grant_showcase_drop(f, side)
	_paint_corners()


## Hand this fighter its showpiece. See the `drops` block above for why a duel has
## to be TOLD to do this — there is no floor here to find one on.
##
## The two sides are given DIFFERENT drops wherever possible, because the point is a
## clip: two bots opening the same Chronostasis is one spell shown twice.
func _grant_showcase_drop(f: Node2D, side: int) -> void:
	if not drops:
		return
	var pool: Array = SpellLibrary.build_tier3()
	if pool.is_empty():
		return
	var want: int = drop_a if side == 0 else drop_b
	var spell: SpellDef = null
	if want >= 0:
		spell = pool[clampi(want, 0, pool.size() - 1)]
	else:
		# THE CLASS'S OWN, not a roll. See CLASS_DROP.
		var cls: int = _fighter_class[side]
		var id: String = CLASS_DROP[cls] if cls >= 0 and cls < CLASS_DROP.size() else ""
		spell = SpellLibrary.drop_by_id(id)
		if spell == null:
			spell = pool[randi() % pool.size()]
	var nth: int = SpellGrant.apply(f, spell)
	if nth < 0:
		push_warning("[botmatch] side %d could not take '%s'" % [side, spell.id])
		return
	# ⚠ AND THE BRAIN IS TOLD, which is the half that makes it actually get CAST.
	# `BotBrain._kit_facts` scores a slot from the CLASS KIT, so without this the bot
	# goes on scoring the spell the drop replaced — its range, its form, its timing —
	# and casts a 235 px ring at whatever distance the displaced spell wanted. The
	# comment on `slot_affordable` in that file already worries about exactly this.
	BotBrain.note_drop(f, nth, spell)
	print("[botmatch] side %d carries %s in slot %d (%d charge(s))"
		% [side, spell.id, nth, spell.charges])


## Every `CharacterBars` under a fighter, off. Found by TYPE rather than by node name:
## `Hero` builds its bars in code (`Hero.gd`), so there is no authored name to rely on
## — the same trap that made `probe_town_feet` silently skip every NPC.
func _hide_floating_bars(f: Node) -> void:
	if f == null:
		return
	for c: Node in f.get_children():
		if c is CharacterBars:
			(c as CharacterBars).visible = false


## YELLOW ON THE LEFT, BLUE ON THE RIGHT — see the note on `SIDE_COLORS`.
##
## ⚠ IT HAS TO HAPPEN HERE, IN `_adopt_fighters`, and not anywhere earlier. `Hero._ready`
## applies `GameState.colourway` to its own rig as the last thing it does, so a tint set
## before the arena is built is simply overwritten by the save file. This runs AFTER
## `add_child(_arena)` has returned, i.e. after both heroes are fully ready, which is
## the first moment the colour can stick.
##
## `CharacterRig.flash_color()` / `flash()` temporarily replace `limb_color` on every
## hit and restore it afterwards — that is the hit feedback doing its job, and it
## restores to whatever `set_tint` last wrote, so it restores to the corner colour.
func _paint_corners() -> void:
	for side: int in _fighters.size():
		var f: Node2D = _fighters[side]
		if not is_instance_valid(f):
			continue
		var rig: Variant = f.get("rig")
		if rig != null and (rig is Object) and (rig as Object).has_method("set_tint"):
			(rig as Object).call("set_tint", side_color(side))


## HP for a class: the shared pool, scaled by who they are. Never below 40, so a
## short-clip HP setting cannot make a squishy class die to one stray bolt.
func _vital_hp(class_id: int) -> int:
	var mult: float = 1.0
	if class_id >= 0 and class_id < CLASS_VITALITY.size():
		mult = CLASS_VITALITY[class_id]
	return maxi(int(round(float(fighter_hp) * mult)), 40)


## Tell the arena's ring-out registry where this fighter now lives, so a respawn
## puts it back on the mirrored footing rather than on the arena's own spawn point.
##
## `_registry` is a plain member on `VersusArena`; this reads and rewrites one field
## of one row and touches nothing else. A private read is the smaller evil than a
## fighter respawning 80 px off its opponent's mirror.
func _reseat_registry(f: Node2D) -> void:
	if _arena == null:
		return
	var reg: Variant = _arena.get("_registry")
	if not (reg is Dictionary):
		return
	var row: Variant = (reg as Dictionary).get(f.get_instance_id())
	if row is Dictionary:
		(row as Dictionary)["spawn"] = f.global_position


## The death hook. `hp == 0` here is the fatal frame, before `Hero._die` heals it.
##
## It is also the only place in this scene that can see a HIT — no damage signal exists
## and polling HP once a frame cannot tell a 4-point chip from a 40-point ult — so the
## fight's dialogue beats are derived from the DROP between two reports of this signal.
func _on_health_changed(hp: int, _max_hp: int, side: int) -> void:
	if side < 0 or side > 1:
		return
	var before: int = _fighter_hp_now[side]
	_fighter_hp_now[side] = hp
	if hp <= 0 and _outcome == Outcome.NONE:
		_decide(Outcome.KO, 1 - side)
		return
	_taunt_on_damage(side, before - hp)


## The three mid-fight beats, all read off one health drop:
##
##   FIRST BLOOD — the first real hit of the bout. The one who LANDED it speaks.
##   BIG HIT     — anything past `BIG_HIT_FRACTION` of the victim's bar. Also the
##                 attacker, because a taunt is what a big hit is FOR.
##   LOW HEALTH  — the victim, once, when the bar crosses the line. It is the only
##                 line in the book that is not swagger.
##
## ⚠ THE "ATTACKER" HERE IS `1 - side`, AND THAT IS AN ASSUMPTION, NOT A FACT. This
## stage has friendly fire, terrain and ring-out pits, so a fighter can absolutely lose
## HP to its own meteor with the other one across the map. There is no attacker
## attribution on `health_changed` to do better with. The failure mode is one wrongly
## attributed gloat in a fight nobody is scoring on dialogue, which is a much smaller
## cost than plumbing a damage-source signal through the hero for a spectator mode.
func _taunt_on_damage(side: int, drop: int) -> void:
	if drop <= 0:
		return
	var attacker: int = 1 - side
	var frac: float = float(drop) / maxf(float(_fighter_max[side]), 1.0)
	if not _first_blood:
		_first_blood = true
		_taunt(attacker, &"first_blood")
	elif frac >= BIG_HIT_FRACTION:
		_taunt(attacker, &"big_hit")
	if not _said_low[side] and _hp_frac(side) <= LOW_HEALTH_FRACTION:
		_said_low[side] = true
		_taunt(side, &"low_health")


# ==========================================================================
# TAUNTS — the fighters having an opinion about the fight
#
# ⚠ `Bark.say()` CANNOT DO THIS, and it was checked before this was written. Bark can
# only speak events that exist in its own fixed `LINES` table; there is no way to pass
# it authored text. So this does what Bark itself does one layer down — parents a
# `SpeechBubble` to the speaker and calls `say()` — and takes its WORDS from
# `TauntBook`, which is a pure static table precisely so a suite can sweep it without
# standing up a scene.
#
# ⚠ AND IT SHARES BARK'S BUBBLE AND BARK'S COOLDOWN META ON PURPOSE. One bubble per
# body is a hard rule (two would render two lines on top of each other), and one rate
# limit per body is why a fight is punctuated rather than narrated. If `VoiceDirector`
# is ever bound to this stage, the two systems already interleave correctly.
# ==========================================================================

func _taunts_enabled() -> bool:
	return taunts and _ceremony()


## Put a taunt over a fighter's head and speak it in that fighter's voice.
##
## `always` skips the rate limit, for the one beat that must land no matter what the
## speaker said ten seconds ago: the line that ends the recording.
func _taunt(side: int, beat: StringName, always: bool = false) -> void:
	if not _taunts_enabled():
		return
	if side < 0 or side >= _fighters.size():
		return
	var who: Node2D = _fighters[side]
	if not is_instance_valid(who) or not who.is_inside_tree():
		return
	# WHO IS OPPOSITE. Maker: "make the bots text chats interact with each other based
	# on who they are fighting." Side 0 is `class_a` and side 1 is `class_b`, which is
	# the same mapping `_apply_matchup` uses — read from the statics rather than from
	# the body, because a fighter does not carry its own class id in a form this file
	# can trust after a mid-match switch.
	var vs: int = class_b if side == 0 else class_a
	var text: String = TauntBook.line_for(beat, -1, vs)
	if text.is_empty():
		return
	# ⚠ THE LINE WEARS THE SPEAKER'S OWN COLOUR. Maker: *"make the text in the colour
	# of the stickman"*. With two bubbles on screen and both of them white, the only
	# way to tell who just spoke was to trace the tail back to a body — which in a clip
	# is a beat the viewer does not have. The corner colour is already the identity
	# everything else in this mode reads (`side_color`, the plates, the rig tint), so
	# the bubble joins it rather than inventing a third scheme.
	#
	# LIGHTENED FOR THE PANEL IT SITS ON. The bubble backing is near-black, and the
	# blue corner at its authored value is a legibility problem against it while the
	# yellow is not — so both go through the same lift rather than hand-picking one.
	# `to_html(false)` drops alpha, which BBCode's `[color=#rrggbb]` does not take.
	var ink: Color = side_color(side).lightened(0.25)
	text = "[color=#%s]%s[/color]" % [ink.to_html(false), text]
	if not always and not _off_taunt_cooldown(who):
		return
	var bubble: Node = _bubble_for(who)
	if bubble == null:
		return
	# NOT awaited. `SpeechBubble.say` yields a few frames while it shrink-to-fits, and
	# a taunt must never be something a match tick has to wait for. Same contract
	# `Bark.say` documents.
	bubble.call(&"say", text, TauntBook.HOLD, 0.0)
	# The only handle anything has on a bubble's lifetime — `SpeechBubble` exposes
	# neither a count nor a remaining-time query, and the result card needs to know
	# when the finisher line has cleared. See `_screen_is_quiet`.
	_taunt_until = maxf(_taunt_until, _real_seconds() + TauntBook.HOLD)
	# The mouth. Routed through `Bark.voice_only` rather than a raw `Sfx.speak` so the
	# taunt uses the SAME derived voice the rest of the game gives this body, honouring
	# any seed / band / billing meta it carries.
	var mood: int = TauntBook.mood_for(beat)
	Bark.voice_only(who, mood, Gibberish.syllables_for_text(text, mood))


## Find or build this fighter's bubble. One per body, reused for its whole life —
## `Bark._bubble_for` does exactly this, and shares the node name so the two never
## build a second one over the first.
##
## ⚠ THE BUBBLE IS `PROCESS_MODE_ALWAYS`, and that is load-bearing for the KO line.
## `SpeechBubble._process` is what positions the panel over the speaker's head, and the
## finishing taunt is fired on the frame the match is decided — one frame before
## `_freeze()` pauses the whole tree. A PAUSABLE bubble would be frozen before it ever
## placed itself and the last line of the clip would render at the fighter's feet.
func _bubble_for(who: Node2D) -> Node:
	var existing: Node = who.get_node_or_null(NodePath(String(TAUNT_BUBBLE_NAME)))
	if existing != null:
		existing.process_mode = Node.PROCESS_MODE_ALWAYS
		return existing
	var scene: PackedScene = load(TAUNT_BUBBLE_SCENE) as PackedScene
	if scene == null:
		return null
	var bubble: Node = scene.instantiate()
	bubble.name = String(TAUNT_BUBBLE_NAME)
	bubble.process_mode = Node.PROCESS_MODE_ALWAYS
	who.add_child(bubble)
	# No box, smaller type — the duel's own register. See `SpeechBubble.set_bare` for
	# why this is applied here rather than in the shared scene: the hub townsfolk use
	# the same bubble and the panel earns its place there.
	# ⚠ AFTER `add_child`, not before: the overrides go through `@onready` node
	# references that do not exist until the bubble is in the tree.
	if bubble.has_method("set_bare"):
		bubble.call("set_bare", 9)
	return bubble


## Per-speaker rate limit, on the node itself rather than in a static dictionary — a
## static map keyed by instance id would leak an entry for every body that ever
## spawned. Same key and same window as `Bark`; see the block header.
func _off_taunt_cooldown(who: Node) -> bool:
	var now: float = _real_seconds()
	var last: float = float(who.get_meta(TAUNT_META, -999.0))
	if now - last < TAUNT_COOLDOWN:
		return false
	who.set_meta(TAUNT_META, now)
	return true


# ==========================================================================
# THE MATCH
# ==========================================================================

func _open_bout() -> void:
	_clock = 0.0
	_outcome = Outcome.NONE
	_winner = -1
	_decided_at = -1.0
	_card_shown_at = 0.0
	_taunt_until = 0.0
	_frozen = false
	_final_hp[0] = -1
	_final_hp[1] = -1
	_first_blood = false
	_said_low[0] = false
	_said_low[1] = false
	_play("ding", 0.0)


func _process(delta: float) -> void:
	_tick_readout()
	# THE CARD OWNS THE OPENING. Nothing below runs until it clears: the clock must not
	# start, the rim check must not fire on a fighter standing still, and the music must
	# not climb through a still frame. `_paint_hud` still runs so the plates are already
	# full and correct behind the dim.
	if _intro_phase != Intro.DONE:
		_tick_intro()
		_paint_hud()
		return
	if _outcome != Outcome.NONE:
		_tick_result(delta)
		_paint_hud()
		return
	_clock += delta
	_sample_fighters()
	_check_rimout()
	_check_timeout()
	_drive_music()
	_paint_hud()


## Poll HP for the BARS only. It is not a death check — see reason 2 at the top.
func _sample_fighters() -> void:
	for side: int in _fighters.size():
		var f: Node2D = _fighters[side]
		if is_instance_valid(f):
			_fighter_hp_now[side] = int(f.get("hp"))


## A fighter off the rock is falling into a blast zone and is not coming back.
##
## Detected by POSITION rather than by the arena's pit signal, because the pit
## routes to `_on_fighter_fell`, which burns a stock and respawns — i.e. by the time
## the arena has an opinion the fighter is already back on its feet at full health,
## and the most watchable event this game has has been erased.
func _check_rimout() -> void:
	for side: int in _fighters.size():
		var f: Node2D = _fighters[side]
		if not is_instance_valid(f):
			continue
		var x: float = f.global_position.x
		if x < RIM_LEFT or x > RIM_RIGHT:
			_decide(Outcome.RINGOUT, 1 - side)
			return


## Nobody watches a stalemate. On the clock, the healthier fighter takes it.
func _check_timeout() -> void:
	if _clock < round_seconds:
		return
	var a: float = _hp_frac(0)
	var b: float = _hp_frac(1)
	if absf(a - b) <= DRAW_MARGIN:
		_decide(Outcome.DRAW, -1)
	else:
		_decide(Outcome.DECISION, 0 if a > b else 1)


func _hp_frac(side: int) -> float:
	if side < 0 or side >= _fighter_hp_now.size():
		return 0.0
	return clampf(float(_fighter_hp_now[side]) / maxf(float(_fighter_max[side]), 1.0), 0.0, 1.0)


## THE RESULT BEAT. Freeze on the killing frame, hold it, slam the card in.
##
## The freeze is a real tree pause, and it is what STOPS THE ARENA FROM ERASING THE
## ENDING: `VersusArena._process` early-outs while paused, so its sparring-loop reset
## (which would teleport both fighters back to their spawns at full health, on the
## very frame the fight was won) never runs. `_match_over` is latched on the arena as
## well, so the reset stays dead even if something unpauses.
##
## The `ClipDirector` keeps ticking through the pause — it inherits PROCESS_MODE
## ALWAYS from the arena — so the camera settles onto the KO instead of stopping dead
## with it. That settle IS the shot.
func _decide(outcome: int, winner: int) -> void:
	if _outcome != Outcome.NONE:
		return
	_outcome = outcome
	_winner = winner
	_decided_at = _real_seconds()
	_final_hp[0] = _fighter_hp_now[0]
	_final_hp[1] = _fighter_hp_now[1]
	if outcome == Outcome.KO and winner >= 0:
		_final_hp[1 - winner] = 0
	elif outcome == Outcome.RINGOUT and winner >= 0:
		_final_hp[1 - winner] = 0
	# Tell the camera operator where to look. It cannot see this itself — see the
	# note on `ClipDirector.note_knockdown`.
	var d: Object = _director()
	if d != null:
		var loser: int = -1 if winner < 0 else 1 - winner
		var at: Vector2 = Vector2.INF
		if loser >= 0 and loser < _fighters.size() and is_instance_valid(_fighters[loser]):
			at = _fighters[loser].global_position
		if outcome == Outcome.RINGOUT and d.has_method("note_ringout"):
			d.call("note_ringout", at)
		elif d.has_method("note_knockdown"):
			d.call("note_knockdown", at, _outcome_word())
	# THE LAST WORDS IN THE CLIP. Fired BEFORE the freeze, on a still-live frame, so the
	# bubble is parented and placed rather than caught mid-layout by the pause. `always`
	# because a winner who gloated ten seconds ago must still get the closing line.
	if winner >= 0:
		_taunt(winner, &"finisher", true)
	_put_the_loser_down(winner)
	_freeze()
	_sting()


## THE LOSER GOES DOWN, and it has to happen HERE — before `_freeze()` — because the
## line after this pauses the tree and nothing pausable moves again.
##
## ⚠ THE BUG THIS FIXES. Watch a bot match end before this existed and the beaten
## fighter is STANDING BOLT UPRIGHT, unanimated, under the word "KO", at FULL health.
## Three separate things conspired:
##   1. `Hero.take_damage` emits `health_changed(0, max)` and only THEN calls `_die()`.
##   2. `_die()` outside a run (which a bot match is) heals straight back to `max_hp`
##      and returns — the feel-sandbox behaviour, correct there, invisible here.
##   3. `_decide` fires off that signal and pauses the tree, so even if something HAD
##      gone limp it would have frozen mid-stand.
## The result card therefore drew over a fighter who was, visually, fine.
##
## The fix is not a new animation. Per the standing rig directive it is the EXISTING
## flop/limp machinery held at full ragdoll (`CharacterRig.collapse`), plus the one
## thing the pause makes necessary: the loser's rig is switched to
## `PROCESS_MODE_ALWAYS` so its `_physics_process` keeps stepping the spring sim while
## the rest of the stage is frozen. That is what lets the body actually MELT to the
## floor across the `FREEZE_BEAT` instead of freezing at frame one of its own fall.
## `Juice.hit_stop` restores `Engine.time_scale` on an `ignore_time_scale` timer, so
## the melt runs at real speed within about a tenth of a second of the kill.
##
## Only the LOSER is switched. The winner stays pausable and stays frozen mid-pose,
## which is the shot: one fighter still standing, one on the floor.
func _put_the_loser_down(winner: int) -> void:
	if winner < 0:
		return                      # a DRAW has no loser to drop
	var loser: int = 1 - winner
	if loser < 0 or loser >= _fighters.size():
		return
	var f: Node2D = _fighters[loser]
	if not is_instance_valid(f):
		return
	var rig: Variant = f.get("rig")
	if rig == null or not (rig is Node) or not (rig as Object).has_method("collapse"):
		return
	# Topple AWAY from the winner, so the body falls the way the fight pushed it.
	var from_dir: Vector2 = Vector2.RIGHT if loser == 0 else Vector2.LEFT
	if winner < _fighters.size() and is_instance_valid(_fighters[winner]):
		var d: Vector2 = f.global_position - _fighters[winner].global_position
		if d.x != 0.0:
			from_dir = Vector2(-signf(d.x), -0.5)
	(rig as Node).process_mode = Node.PROCESS_MODE_ALWAYS
	# ⚠ ASSERT GROUNDEDNESS, or the body sprawls in mid-air. `CharacterRig` only drops
	# its ride height toward `RIDE_PRONE` — the thing that actually puts a limp body ON
	# THE FLOOR — while `_grounded` is true, and `_grounded` is fed once a frame by
	# `Hero._physics_process`, which the pause on the next line stops forever. A fatal
	# blow almost always pops the victim off the floor, so at the decisive frame that
	# flag is usually FALSE and would stay false for the whole result card: a fighter
	# going limp while hovering. Measured on a real KO before this line existed — the
	# rig's ride offset never moved off 0.
	if (rig as Object).has_method("set_grounded"):
		(rig as Object).call("set_grounded", true)
	# ══ THE DEATH ITSELF, WHICH THIS MODE NEVER SHOWED ══════════════════════════
	# Maker, watching duels: *"when one of them die it should show them dying"*.
	# Traced: a duel fighter is a `Hero`, and `Hero._die()` gates its whole death
	# spectacle on `GameState.is_run_active()` or a live net session. A bot match is
	# NEITHER, so `_die` heals the body back to full and returns — `_enter_downed`,
	# with the corpse fold and the sound, is never reached. The tower's own kill
	# (`Enemy._die`) is unreachable for the opposite reason: a fighter is not an
	# `Enemy`. So the loudest moment in the mode was a rig going limp, in silence,
	# with a 0.05 s hit-stop against the tower's 0.11, and then 1.7 seconds of a
	# completely static frame before the result card.
	#
	# Both halves below are the EXACT pair the tower and the in-run hero death
	# already use — no new node type, no new animation, nothing added to
	# `CharacterRig`. Order matters and mirrors `Hero._enter_downed`: the smudge
	# snapshots the pose AS IT STOOD, so it must be taken BEFORE `collapse`.
	#
	# ⚠ BOTH SURVIVE THE PAUSE ON THE NEXT LINE. `DeathSmudge` sets
	# `PROCESS_MODE_ALWAYS` in its own `_ready` and runs on `Time.get_ticks_msec()`
	# precisely so it plays through hit-stop; `CombatVfx` parents to the arena, which
	# is already `PROCESS_MODE_ALWAYS`. Neither needed plumbing here — that is the
	# whole argument for reusing them rather than writing a duel-only death.
	# ⚠ NO `DeathSmudge` HERE, AND THAT WAS A REAL BUG I SHIPPED. Maker: *"when they
	# die they bug out and glitch"*. A smudge is a SNAPSHOT of the rig that folds into
	# a heap and is rubbed out — `Enemy._die` uses it INSTEAD of a ragdoll, because it
	# `queue_free`s the body on the same frame, and `Hero._enter_downed` uses it while
	# the real body leaves for `GhostForm`. A bot-match loser does NEITHER: it stays on
	# stage and ragdolls. Adding a smudge on top drew a SECOND stickman over the first,
	# folding one way while the body toppled another. Two figures, one death.
	#
	# The ragdoll IS the dying here, so what this beat needs is weight around it, not a
	# second corpse.
	CombatVfx.spawn_burst(
		f.get_parent(), f.global_position,
		side_color(loser).lightened(0.3), Color(side_color(loser), 0.0),
		42, 0.5, 110.0, 240.0, 1.5, 4.0, 40.0, 90.0)
	(rig as Object).call("collapse", from_dir)
	# ⚠ DEFERRED, OR IT IS SILENTLY THROWN AWAY. A kill is the heaviest impact in the
	# game and the tower prices it at 0.11 s against the 0.05 s of an ordinary hurt.
	# But this runs INSIDE `Hero.take_damage`, which fires its own `Juice.hit_stop(0.05)`
	# a few lines later — and `hit_stop` bumps a generation counter that cancels the
	# previous restore, so the LAST caller wins. Called straight, the heavier freeze was
	# overwritten by the lighter one on the same frame and the kill felt like a graze.
	# Deferring puts it after `take_damage` has finished having its say.
	Juice.hit_stop.call_deferred(0.11)
	# ⚠ AND HIDE THE LOSER'S FLOATING HP BAR, which would otherwise sit over the body
	# reading FULL GREEN. `Hero._die()` outside a run heals straight back to `max_hp`
	# (the F6 feel-sandbox behaviour, correct there), and `CharacterBars` POLLS `hp`
	# every frame — so the corpse wears a full health bar for the whole result card
	# while the HUD name plate two feet above it correctly reads 0, because that plate
	# reads `_final_hp` and never touches the fighter. Photographed, in
	# `user://death_ko_04_zoom.png`, before this existed. Hiding the bar rather than
	# forcing `hp = 0` keeps this scene from reaching into `Hero`'s death rules.
	for c: Node in f.get_children():
		if c is CharacterBars:
			(c as CanvasItem).visible = false


func _freeze() -> void:
	if _frozen:
		return
	_frozen = true
	if _arena != null:
		_arena.set("_match_over", true)
	_hold_corner_colours()
	get_tree().paused = true


## YELLOW STAYS YELLOW AND BLUE STAYS BLUE, right through the result card.
##
## ⚠ THE BUG, AND IT IS THE REASON THIS IS CALLED EVERY FRAME AND NOT ONCE.
## `CharacterRig._flash_timer` is decremented inside `advance()`, which runs off the
## PHYSICS clock — so on a paused tree a hit-flash NEVER expires, and `_draw` prefers
## `_flash_color` over `limb_color`. The killing blow sets `Hero.HURT_FLASH_COLOR`
## (1, 0.2, 0.2), the tree freezes, and the KO frame — the frame that gets RECORDED —
## renders a fighter in flat RED with its corner colour nowhere on screen. Any trade
## in the last fraction of a second paints the winner too, which is how BOTH fighters
## came out red in a 1920x1080 capture while the HUD name plates — which read
## `side_color()` directly and never touch a rig — stayed correctly yellow and blue.
## The tint was never lost. `_paint_corners` works. The flash simply outlived it.
##
## EVERY FRAME because of the ORDER inside `Hero.take_damage`: it emits
## `health_changed` FIRST (which lands here, decides the bout and pauses the tree) and
## sets the red flash AFTERWARDS. A one-shot clear inside `_freeze` therefore fires
## before the red exists and misses it entirely — measured, on a real KO. The call is
## idempotent and returns immediately when nothing is flashing, so the per-frame cost
## on a frozen stage is two method lookups.
func _hold_corner_colours() -> void:
	for f: Node2D in _fighters:
		if not is_instance_valid(f):
			continue
		var rig: Variant = f.get("rig")
		if rig != null and (rig is Object) and (rig as Object).has_method("clear_flash"):
			(rig as Object).call("clear_flash")


## Real (unscaled) seconds. The result beat must not stretch when hit-stop drops
## `Engine.time_scale` to 0.05 on the very hit that ended the fight — which is
## exactly when it would, since that hit is a kill.
func _real_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _tick_result(_delta: float) -> void:
	_hold_corner_colours()
	var age: float = _real_seconds() - _decided_at
	if _result_card != null and not _result_card.visible \
			and age >= FREEZE_BEAT \
			and (_screen_is_quiet() or age >= RESULT_MAX_WAIT):
		_show_result_card()
		_card_shown_at = _real_seconds()
	if auto_rematch and _card_shown_at > 0.0 \
			and _real_seconds() - _card_shown_at >= RESULT_HOLD:
		_reload()


## ⚠ THE CARD USED TO LAND ON TOP OF THE KILL.
##
## `FREEZE_BEAT` was 0.55 s and the card came in on that alone, but the finisher
## taunt bubble holds for `TauntBook.HOLD` (1.9 s, plus a few frames of shrink-to-fit
## layout) and the killing blow's damage number runs 0.72 s — 0.864 s on a big hit,
## and it is spawned onto an ALREADY-PAUSED tree, so it starts its life after the
## freeze rather than during it. The result card therefore slammed down over a live
## taunt and a floating number roughly every time.
##
## Waiting on a fixed larger constant would fix today and rot tomorrow, so this asks
## the screen instead. `RESULT_MAX_WAIT` is the backstop.
##
## ⚠ `ClipDirector.is_hot()` IS NOT USABLE HERE and looks like it should be: heat is
## structurally zero on a paused tree (no damage, no live spells, no telegraphs), so
## it would read "quiet" instantly and this gate would do nothing. Ask the things
## that actually have lifetimes.
##
## The taunt is the one that needed a new seam — `SpeechBubble` exposes no lifetime
## query and no count, so `_taunt` latches its own expiry.
func _screen_is_quiet() -> bool:
	if _real_seconds() < _taunt_until:
		return false
	if DamageNumber.alive_count() > 0:
		return false
	if ElementFx.alive_count() > 0:
		return false
	return true


func _outcome_word() -> String:
	match _outcome:
		Outcome.KO: return "KO"
		Outcome.RINGOUT: return "RING-OUT"
		Outcome.DECISION: return "DECISION"
		Outcome.DRAW: return "DRAW"
	return ""


## The machine-readable result, for a capture tool's manifest and for the sim.
func result() -> Dictionary:
	return {
		"outcome": _outcome_word(),
		"over": _outcome != Outcome.NONE,
		"winner_side": _winner,
		"winner": "" if _winner < 0 else _label(_fighter_class[_winner]),
		"loser": "" if _winner < 0 else _label(_fighter_class[1 - _winner]),
		"left": _label(_fighter_class[0]), "right": _label(_fighter_class[1]),
		"left_hp": _final_hp[0] if _final_hp[0] >= 0 else _fighter_hp_now[0],
		"right_hp": _final_hp[1] if _final_hp[1] >= 0 else _fighter_hp_now[1],
		"left_max": _fighter_max[0], "right_max": _fighter_max[1],
		"seconds": snappedf(_clock, 0.01),
		"tier": _tier(),
	}


func match_over() -> bool:
	return _outcome != Outcome.NONE


## IS THE PRE-FIGHT CARD STILL UP.
##
## Public because a capture tool cannot film a card it cannot see, and `ClipDirector`
## heat is STRUCTURALLY zero behind it: no damage (the tree is paused), no live spells,
## no armed telegraphs, and the mirrored spawns sit `SPAWN_SPREAD * 2` = 560 px apart
## against the director's own `CLOSE_RANGE * 2.5` = 400 px proximity cutoff — so even
## the one term that could fire clamps to 0. MEASURED: `heat 0.000` on every rendered
## frame of the card, and `is_hot()` first going true FOUR FRAMES AFTER it had gone.
## A hot-gated capture therefore always starts after the intro, every time.
func intro_active() -> bool:
	return _intro_phase != Intro.DONE


# ==========================================================================
# SOUND
#
# ⚠ WHAT THIS FILE CAN AND CANNOT DO ABOUT THE MAKER'S "the sound effects need to be
# improved". The 248-key roster, its per-key trims, its weight classes and its
# ducking rules all live in `Sfx.gd`, which this agent does not own. What a match
# CAN do from here is the structural half that was simply absent: the fight had no
# audio punctuation at all — no bell, no stinger on the decisive hit, and a music bed
# that sat at one level whether the fighters were circling or trading ults.
# ==========================================================================

## The bell, the stinger, and the card. Weighted so the KO reads as the loudest
## thing in the clip.
func _sting() -> void:
	match _outcome:
		Outcome.KO:
			_play("enemy_death_big", 2.0)
			_play("sub_boom", 0.0, 0.05)
		Outcome.RINGOUT:
			_play("body_fall", 2.0)
			_play("sub_boom", -2.0, 0.06)
		_:
			_play("ding", 1.0)


## Music intensity follows the director's heat, in BANDS rather than continuously.
## `Music.set_intensity` re-arms a tween on every distinct value, so driving it from
## a per-frame float would rebuild a tween sixty times a second and the bed would
## never actually get anywhere.
func _drive_music() -> void:
	var d: Object = _director()
	if d == null:
		return
	var band: int = clampi(int(float(d.call("heat")) * 4.0), 0, 3)
	if band == _music_band:
		return
	_music_band = band
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("set_intensity"):
		music.call("set_intensity", float(band) / 3.0)


## Guarded, because this scene is instantiated by headless harnesses that have no
## `Sfx` autoload and a hard reference would abort the calling function.
func _play(key: String, db: float = 0.0, delay: float = 0.0) -> void:
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		# (key, volume_db, pitch_variation, pitch_base, delay) — the last two are
		# easy to transpose, and transposing them re-pitches the sample instead of
		# spacing the beat.
		sfx.call("play", key, db, 0.06, 1.0, delay)


# ==========================================================================
# THE HUD — health bars that read at 640x360 without covering the fight
#
# ⚠ `CharacterBars` IS NOT THE COMPONENT FOR THIS, and it was checked before this was
# written. It is a 30 px floating bar parented to the fighter (Hero.gd:977 and
# Enemy.gd:919 both add one), so at the clip camera's zoom it renders about 15 screen
# pixels wide, under the fighter's own spell glow, and it moves with the body — the
# audience cannot track a number that is walking around the frame. It stays exactly
# as it is and keeps doing its job in the tower. What a MATCH needs is a fighting
# game's plates: fixed, screen-space, top corners, out of the fight's way. (Note in
# passing: `CharacterBars.configure(show_mp)` defaults false and no caller in the
# project has ever passed true, so the MP half of that component is dead code.)
# ==========================================================================

const PLATE_W: float = 232.0
const PLATE_H: float = 10.0
const PLATE_MARGIN: float = 14.0
const PLATE_TOP: float = 12.0
const PLATE_BG: Color = Color(0.05, 0.06, 0.10, 0.80)
const PLATE_EDGE: Color = Color(0.0, 0.0, 0.0, 0.65)
const HP_FULL: Color = Color(0.36, 0.88, 0.42)
const HP_MID: Color = Color(0.96, 0.83, 0.24)
const HP_LOW: Color = Color(0.94, 0.26, 0.22)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	for side: int in 2:
		_plates.append(_build_plate(layer, side))
	_clock_label = _make_label(layer, 13, Color(0.92, 0.95, 1.0, 0.92))
	_clock_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_clock_label.offset_top = PLATE_TOP - 2.0
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_result_card(layer)
	_build_intro_card(layer)
	# The director's own opinion, over the fight it is filming. This is the thing that
	# turns "watch two bots" into "tune the clip engine": if the heat number sits at
	# 0.05 through an exchange, the camera opens late and the thresholds are wrong.
	_readout = _make_label(layer, 11, Color(0.86, 0.92, 1.0, 0.75))
	_readout.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_readout.offset_left = 12.0
	_readout.offset_top = -22.0
	# ...and it is an INSTRUMENT, so it comes off the screen in cinematic mode. It is
	# gated rather than deleted because it is the only number that says whether the
	# director opened the shot too late. See `scripts/combat/Cinematic.gd`.
	Cinematic.mark(_readout)


## One fighter's plate: a name, a class-tinted flash, and a bar that DRAINS TOWARD
## THE CENTRE of the screen, so the two bars read as one contest rather than as two
## unrelated meters.
func _build_plate(layer: CanvasLayer, side: int) -> Dictionary:
	var draw := _PlateDraw.new()
	draw.side = side
	draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(draw)
	# The name sits ON TOP of the bar's layer, added after it, so the outline is not
	# buried under the plate's own background.
	var name_label: Label = _make_label(layer, 12, Color(0.95, 0.97, 1.0))
	name_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	return {"name": name_label, "draw": draw}


## ⚠ THREE HUDS WERE STACKED ON THE SAME 40 PIXELS, and the first captured frame is
## how it was found: the arena's own "STORMCALLER vs CRYOMANCER" card, the `Rank`
## autoload's "Nameless · Tier 0" title, and this file's plates and clock, all drawn
## over each other in the top strip. Unreadable, and it is the first thing an audience
## sees.
##
## The plates say everything the arena's card said and more, so the card goes; the
## rank title belongs to a RUN and this is a spectator mode, so it goes too. Both are
## hidden at RUNTIME rather than edited out of their own files — the arena is still an
## exhibition stage when something else drives it, and `Rank`'s HUD is an autoload
## that outlives this scene, which is why `_exit_tree` puts it back.
func _hide_duplicate_chrome() -> void:
	if _arena != null:
		for layer: Node in _arena.get_children():
			if not (layer is CanvasLayer):
				continue
			# DIRECT children only. The pause overlay's own labels are nested inside
			# a panel, and blanking those would empty the menu.
			for ctl: Node in layer.get_children():
				if ctl is Label:
					(ctl as Label).visible = false
	_set_rank_hud(false)


func _set_rank_hud(shown: bool) -> void:
	var rank: Node = get_node_or_null("/root/Rank")
	if rank == null:
		return
	var label: Variant = rank.get("_hud_label")
	# ⚠ VALIDITY BEFORE `is` — this Label lives in the arena scene but is held by the
	# `Rank` AUTOLOAD, which outlives every scene change. Textbook stale reference.
	if is_instance_valid(label) and label is Label:
		(label as Label).visible = shown


func _make_label(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.07, 0.95))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_result_card(layer: CanvasLayer) -> void:
	_result_card = Control.new()
	_result_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_card.visible = false
	layer.add_child(_result_card)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_card.add_child(dim)
	var head := _make_label(_result_card, 30, Color(1.0, 0.97, 0.86))
	head.name = "Head"
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 132.0
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# ⚠ NO SUBTITLE UNDER THE WINNER. It used to read "<outcome> · <seconds> · <hp>—<hp>"
	# — the maker, watching: *"what all this random subtext under where it says x wins,
	# please remove that"*. It was telemetry wearing a result card's clothes: the outcome
	# word is already implied by the headline, and the clock and both HP totals are on
	# screen the entire fight in the plates above. Every number in it was either a
	# duplicate or a debug readout, on the one frame that is the thumbnail.
	#
	# `_outcome_word()` stays — the result dictionary and `ClipDirector` both read it.


func _show_result_card() -> void:
	if _result_card == null:
		return
	var head: Label = _result_card.get_node_or_null("Head") as Label
	if head != null:
		head.text = "DRAW" if _winner < 0 else "%s WINS" % _label(_fighter_class[_winner])
		# THE WINNER'S CORNER, not the winner's class — the same yellow-or-blue the card
		# opened on and the body has been wearing all fight. See `SIDE_COLORS`.
		head.add_theme_color_override("font_color",
			Color(0.92, 0.94, 1.0) if _winner < 0 else side_color(_winner))
	_result_card.visible = true
	_play("holy_swell", -1.0)


# ==========================================================================
# THE PRE-FIGHT CARD — "YELLOW vs BLUE", and then FIGHT
#
# Combat used to be live on frame one: the scene opened and two bots were already
# swinging, with no statement of who they were. For a mode whose entire product is a
# RECORDING, the first two seconds were doing nothing.
#
# ⚠ HOW COMBAT IS ACTUALLY GATED, because this is the part that is easy to get wrong.
# The fighters are `PROCESS_MODE_PAUSABLE` and `VersusArena._process` early-returns on
# `get_tree().paused`, while THIS node is `PROCESS_MODE_ALWAYS` (see `_ready`). So the
# card simply pauses the tree and counts down on its own `_process`, exactly the way
# `_freeze()` already holds the KO beat.
#
# ⚠ AND IT COUNTS ON THE UNSCALED REAL CLOCK (`_real_seconds`), never on `delta`. A
# paused tree still delivers delta to an ALWAYS node, but `Engine.time_scale` is a
# live knob in this project (hit-stop drives it to 0.05), so a delta-summed card would
# stretch the moment somebody else touched the scale.
#
# ⚠ AND THE FADE IS DRIVEN BY HAND, not by a `Tween`. A default tween does not advance
# on a paused tree, so the card would simply sit at alpha 0 for its whole life and the
# fight would start behind an invisible dim. One line of `modulate.a` in `_process` is
# both simpler and immune to it.
# ==========================================================================

## Is there anybody to show a ceremony TO? False under `--headless`, where the dummy
## renderer draws nothing, reports success, and would happily charge every suite and
## every sim bout ~2 s of staring at a card that does not exist.
static func _ceremony() -> bool:
	return DisplayServer.get_name() != "headless"


func _intro_enabled() -> bool:
	return intro_seconds > 0.0 and _ceremony()


func _build_intro_card(layer: CanvasLayer) -> void:
	_intro_card = Control.new()
	_intro_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_card.visible = false
	layer.add_child(_intro_card)

	var dim := ColorRect.new()
	dim.color = CARD_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_card.add_child(dim)

	# CENTRED IN THE VIEWPORT rather than at a hardcoded offset, so the card sits right
	# at any window size — this scene is filmed at 1920x1080 and watched at whatever the
	# window happens to be.
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_card.add_child(centre)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	centre.add_child(row)
	_intro_row = row

	row.add_child(_intro_corner(0))
	var vs: Label = _make_label(row, CARD_VS_SIZE, CARD_CHALK)
	vs.text = "VS"
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_intro_corner(1))

	# The second beat, in the same card. Hidden until the tree unpauses.
	_intro_fight = _make_label(_intro_card, CARD_FIGHT_SIZE, CARD_CHALK)
	_intro_fight.text = "FIGHT"
	_intro_fight.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_intro_fight.offset_top = 128.0
	_intro_fight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_fight.visible = false


## One corner of the card: the side's colour, then the class it is being worn by. The
## SWATCH is the load-bearing half — it is the only part of the card that says the same
## thing as the body on the stage without anybody having to read a word.
func _intro_corner(side: int) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 7)

	var swatch := ColorRect.new()
	swatch.color = side_color(side)
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(swatch)

	var who: Label = _make_label(col, CARD_NAME_SIZE, side_color(side))
	who.text = _label(_fighter_class[side] if side < _fighter_class.size() else -1)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ⚠ THE TIER USED TO BE PRINTED HERE TOO — under BOTH fighters, so the VS card
	# every clip opens on said "Impossible" twice. Cut with the clock's copy: the
	# card exists to say WHO is fighting, and a difficulty setting stated twice is
	# exactly the "random UI pieces we don't need" the standing rule is about.
	return col


## Open the card and stop the fight. A no-op (straight to DONE) when the ceremony is
## off or there is no display — which is exactly what the sim and the suites get.
func _open_intro() -> void:
	if not _intro_enabled() or _intro_card == null:
		_intro_phase = Intro.DONE
		return
	_intro_phase = Intro.VS
	_intro_at = _real_seconds()
	_intro_card.modulate.a = 0.0
	_intro_card.visible = true
	get_tree().paused = true
	_play("ding", 1.0)


func _tick_intro() -> void:
	if _intro_card == null:
		_intro_phase = Intro.DONE
		return
	var age: float = _real_seconds() - _intro_at
	if _intro_phase == Intro.VS:
		# Fade in, hold, fade out — all three inside `intro_seconds`, so the knob means
		# exactly what it says and a short card degrades gracefully into a flash.
		var fade: float = minf(INTRO_FADE, intro_seconds * 0.4)
		var a: float = 1.0
		if age < fade:
			a = age / maxf(fade, 0.001)
		elif age > intro_seconds - fade:
			a = maxf(intro_seconds - age, 0.0) / maxf(fade, 0.001)
		_intro_card.modulate.a = clampf(a, 0.0, 1.0)
		if age >= intro_seconds:
			_start_fight()
		return
	# FIGHT. The tree is already live under this — the word lands ON the first step.
	var held: float = age - intro_seconds
	_intro_card.modulate.a = clampf(1.0 - held / maxf(INTRO_FIGHT_BEAT, 0.001), 0.0, 1.0)
	if held >= INTRO_FIGHT_BEAT:
		_intro_phase = Intro.DONE
		_intro_card.visible = false


## The bell. Unpause FIRST, then swap the card to its second beat, so there is no frame
## where "FIGHT" is on screen over a still stage.
func _start_fight() -> void:
	_intro_phase = Intro.FIGHT
	get_tree().paused = false
	if _intro_row != null:
		_intro_row.visible = false
	if _intro_fight != null:
		_intro_fight.visible = true
	_intro_card.modulate.a = 1.0
	_play("sub_boom", -1.0)
	# ONE of them opens the mouth, never both — two openers is a script reading rather
	# than a fight. Which one is rolled, so a series does not always start the same way.
	_taunt(randi() % 2, &"fight_start")


## Push the current numbers into the plates. Poll-don't-push (the AbilityBar idiom).
func _paint_hud() -> void:
	if _plates.size() != 2:
		return
	# ⚠ THE VIEWPORT CAN BE GONE WHILE `_process` IS STILL RUNNING, and this crashed a
	# live session after ONE fight with "Cannot call method 'get_visible_rect' on a null
	# value". `_process` keeps firing for a frame after the node leaves the tree — the
	# teardown between bouts is exactly that window — and `get_viewport()` answers null
	# there. Painting a HUD for a viewport that no longer exists is never meaningful, so
	# bail rather than invent a width: a fallback would draw the plates in the wrong
	# place for a frame instead of not drawing them.
	if get_viewport() == null:
		return
	for side: int in 2:
		var plate: Dictionary = _plates[side]
		var name_label: Label = plate["name"]
		var draw: _PlateDraw = plate["draw"]
		var cls: int = _fighter_class[side] if side < _fighter_class.size() else -1
		var shown: int = _final_hp[side] if _final_hp[side] >= 0 else _fighter_hp_now[side]
		var frac: float = clampf(float(shown) / maxf(float(_fighter_max[side]), 1.0), 0.0, 1.0)
		name_label.text = "%s   %d" % [_label(cls), maxi(shown, 0)]
		# ⚠ THE PLATE IS THE CORNER'S COLOUR, NOT THE CLASS'S. It used to read
		# `ClassInfo.color_for(cls)`, which meant the plate and the body it belonged to
		# could disagree — and now that the bodies are forced to yellow/blue, they
		# always would. One source (`SIDE_COLORS`) for the card, the plate and the rig.
		name_label.add_theme_color_override("font_color", side_color(side))
		var vw: float = float(get_viewport().get_visible_rect().size.x)
		name_label.size = Vector2(PLATE_W, 16.0)
		name_label.horizontal_alignment = \
			HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		name_label.position = Vector2(
			PLATE_MARGIN if side == 0 else vw - PLATE_MARGIN - PLATE_W,
			PLATE_TOP + PLATE_H + 3.0)
		draw.frac = frac
		draw.tint = _hp_tint(frac)
		draw.queue_redraw()
	if _clock_label != null:
		var left: float = maxf(round_seconds - _clock, 0.0)
		# ⚠ THE DIFFICULTY WORD IS NOT PRINTED HERE ANY MORE. Maker: "remove that
		# impossible wording at the top of the screen." This read `Impossible  1:30`,
		# so the loudest word on the screen named a SETTING rather than anything
		# happening in the fight — and on a shared clip it reads as a boast about the
		# bots rather than as information. The tier still lives where a tier belongs:
		# the pause menu's `Difficulty:` button, which is where it is changed.
		_clock_label.text = "%d:%02d" % [int(left) / 60, int(left) % 60]


func _hp_tint(frac: float) -> Color:
	if frac > 0.5:
		return HP_MID.lerp(HP_FULL, (frac - 0.5) * 2.0)
	return HP_LOW.lerp(HP_MID, frac * 2.0)


## The bar itself, drawn rather than laid out, because it drains toward the centre
## and a `ProgressBar` fills from a fixed edge. A `Control` subclass so the draw
## happens in screen space at the base viewport's scale.
class _PlateDraw extends Control:
	var side: int = 0
	var frac: float = 1.0
	var tint: Color = Color(0.36, 0.88, 0.42)

	func _draw() -> void:
		var vw: float = size.x
		var x0: float = BotMatch.PLATE_MARGIN if side == 0 \
			else vw - BotMatch.PLATE_MARGIN - BotMatch.PLATE_W
		var box := Rect2(Vector2(x0, BotMatch.PLATE_TOP),
			Vector2(BotMatch.PLATE_W, BotMatch.PLATE_H))
		draw_rect(box.grow(1.0), BotMatch.PLATE_EDGE)
		draw_rect(box, BotMatch.PLATE_BG)
		var w: float = BotMatch.PLATE_W * clampf(frac, 0.0, 1.0)
		# Left plate drains right-to-left; right plate drains left-to-right. Both
		# empty toward the middle of the screen, so the gap between them IS the score.
		var fx: float = x0 if side == 0 else x0 + BotMatch.PLATE_W - w
		draw_rect(Rect2(Vector2(fx, BotMatch.PLATE_TOP), Vector2(w, BotMatch.PLATE_H)), tint)


func _tick_readout() -> void:
	if _readout == null or not _readout.visible:
		return   # hidden by cinematic mode — no reason to format a string nobody sees
	var d: Object = _director()
	if d == null:
		_readout.text = "%s vs %s" % [_label(_fighter_class[0]), _label(_fighter_class[1])]
		return
	_readout.text = "heat %.2f %s%s" % [
		float(d.call("heat")),
		"[ROLLING]" if bool(d.call("is_hot")) else "",
		"  %s" % _outcome_word() if _outcome != Outcome.NONE else "",
	]


func _director() -> Object:
	if _arena != null and _arena.has_method("clip_director"):
		return _arena.call("clip_director") as Object
	return null


func _label(id: int) -> String:
	return CLASS_LABELS[id] if id >= 0 and id < CLASS_LABELS.size() else "?"


func _tier() -> String:
	return TIER_LABELS[clampi(difficulty, 0, 3)]


# ==========================================================================
# THE MATCHUP KNOBS
#
# Every one of them RELOADS THE SCENE, and unlike free play that is the right call
# here: a matchup change means two different bodies with two different kits and two
# fresh brains. There is nothing to preserve across it — no learned record, no
# session, no position worth keeping — so a reload is the honest, simplest way to
# get a clean bout, and it is why all four knobs are statics.
# ==========================================================================

func _extend_pause_menu() -> void:
	if _arena == null or not _arena.has_method("pause_menu"):
		return
	var menu: Object = _arena.call("pause_menu")
	if menu == null:
		return
	menu.call("add_action", "Rematch", Callable(self, "_rematch"))
	menu.call("add_setting_section", "Bot Match")
	_labels["a"] = menu.call("add_setting_button", "Fighter A: %s" % _label(class_a),
		Callable(self, "_cycle_a"))
	_labels["b"] = menu.call("add_setting_button", "Fighter B: %s" % _label(class_b),
		Callable(self, "_cycle_b"))
	_labels["tier"] = menu.call("add_setting_button", "Difficulty: %s" % _tier(),
		Callable(self, "_cycle_tier"))
	_labels["hp"] = menu.call("add_setting_button", "Fighter HP: %d" % fighter_hp,
		Callable(self, "_cycle_hp"))
	_labels["loop"] = menu.call("add_setting_button",
		"Auto-rematch: %s" % ("on" if auto_rematch else "off"),
		Callable(self, "_cycle_loop"))


func _cycle_a() -> void:
	class_a = (class_a + 1) % CLASS_LABELS.size()
	if class_a == class_b:
		# A mirror match is a legal and interesting thing to watch, but it is a
		# DELIBERATE choice — walking into one by accident while cycling is not, and
		# it is the pairing most likely to produce the stalemate the brain's
		# stagnation model exists to break.
		class_a = (class_a + 1) % CLASS_LABELS.size()
	_reload()


func _cycle_b() -> void:
	class_b = (class_b + 1) % CLASS_LABELS.size()
	if class_b == class_a:
		class_b = (class_b + 1) % CLASS_LABELS.size()
	_reload()


func _cycle_tier() -> void:
	difficulty = (difficulty + 1) % TIER_LABELS.size()
	_reload()


## 120 / 190 / 260 / 340. Shorter bouts make better clips; longer ones show more of
## a kit. It is the pool BOTH fighters' vitality scales from, so it is a length knob
## and never an advantage.
func _cycle_hp() -> void:
	const STEPS: Array[int] = [120, 190, 260, 340]
	var i: int = STEPS.find(fighter_hp)
	fighter_hp = STEPS[(i + 1) % STEPS.size()] if i >= 0 else STEPS[1]
	_reload()


func _cycle_loop() -> void:
	auto_rematch = not auto_rematch
	_reload()


func _rematch() -> void:
	_reload()


## SIDES SWAP ON EVERY RELOAD. This stage is not left-right symmetric — every terrace
## and the whole bluff are on the right — so a series in which one class always
## started on the left would be measuring the map as much as the matchup.
func _reload() -> void:
	swap_sides = not swap_sides
	get_tree().paused = false
	get_tree().reload_current_scene()
