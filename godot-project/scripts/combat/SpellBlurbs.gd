extends RefCounted
## ONE SENTENCE PER SPELL, SAYING WHAT IT DOES.
##
## Maker: *"each spell should have a description of what it does, short and sweet but
## in an epic way and clear what it does"*. The second half is the hard half. "Flame
## Burst" sounds impressive and tells a player nothing; a blurb has to name the SHAPE
## (beam / ring / wall / field), the RANGE and the CONSEQUENCE, in a line a thumb-sized
## label can hold at 640x360.
##
## == WHY THIS IS ITS OWN FILE AND NOT A `description` ON `SpellDef` ============
## `SpellDef.description` already exists and is `@export_multiline`, so that is where a
## description "belongs" -- and the first version of this file deferred to it for
## exactly that reason. THEN IT WAS MEASURED: all 54 spells already have one, and 46 of
## the 54 are LONGER THAN 96 CHARACTERS. They are long-form paragraphs, three or four
## lines each at the sizes these screens draw at:
##
##   iai_slash -> "Draw and cut in one motion. The corridor is drawn before the blade
##                 leaves the sheath, and it is barely longer than you are. Bait it and
##                 the duelist has no damage for five seconds."
##
## That is good writing and it is the wrong LENGTH for a 30 px row on a 640x360 screen.
## `SpellDef.description` is the long form; this file is the SHORT form, and the two are
## different jobs rather than two copies of one. `for_spell()` therefore prefers THIS
## table and falls back to the def only for a spell the table has never heard of -- a
## `.tres`-authored drop, say -- so an unknown spell says something rather than nothing.
##
## Keeping it out of `SpellLibrary.gd` is also what makes the COVERAGE CHECK below
## possible: a per-spell field can only be audited by building all 54 defs, while a
## table can be diffed against the library's own id list in one call. (And that file is
## a 2510-line script owned by another agent mid-edit.)
##
## == EVERY ENTRY POINT HERE IS `static`, AND THAT IS LOAD-BEARING ==============
## This script has NO `class_name` (the same call the codebase makes for `HudStyle` and
## `Hero`), so consumers reach it with
##     const SpellBlurbs := preload("res://scripts/combat/SpellBlurbs.gd")
## and `preload` yields the SCRIPT OBJECT, not an instance. A plain `func` on a script
## object is not callable -- and it does not fail at parse time, it fails at RUNTIME, in
## the frame the player opened the screen. Four agents have hit a variant of that trap
## in this project. So: `const` table, `static func` accessors, no instance state, and
## `tools/slice_test_class_identity.gd` calls every accessor statically so that the trap
## is caught by a suite rather than by a player.
##
## == HOUSE RULES FOR AN ENTRY ==================================================
##   * ONE sentence, or two very short ones. `MAX_LEN` is enforced by the suite, not by
##     good intentions, because the consuming labels are 300 px wide at font size 9 and
##     a fifth line silently pushes a 360 px panel off a phone.
##   * SAY THE SHAPE. "A bolt that leaps body to body" is a blurb; "unleash the storm"
##     is a tagline. Every line below names a geometry, a target rule, or a cost.
##   * NO NUMBERS. Damage and cooldown move with balance passes and a hard-typed "62
##     damage" is the `ClassInfo.kit` rot in miniature -- a promise nothing checks. The
##     hotbar already shows the real numbers.
##   * NO BORROWED NAMES. `tools/slice8_test_spell_kits.gd` sweeps the library's source
##     for IP strings; this file is player-facing text and is held to the same bar.

## Longest blurb we will render. Measured, not guessed: the widest consumer is
## `ClassSelect`'s detail column at `DETAIL_W` 300 px with a font size 9 label, which
## fits roughly 66 characters per line, and the row reserves two lines. 132 is the
## ceiling; 96 is the ceiling we hold ourselves to so the second line is never full.
const MAX_LEN: int = 96

## id -> blurb. Keyed by `SpellDef.id` and NOT by display name, because display names
## have been renamed three times in this project (The Ordinary Spell -> First Lance,
## Crescent Step -> Crescent Rush, Shadow Step -> Shadowburst) while the ids stayed put.
## A rename therefore cannot orphan a blurb.
const BLURBS: Dictionary = {
	# -- the 36 ids a class can actually carry (`SpellLibrary.CLASS_KITS`) -------
	"aegis_ward": "A standing gate of light. It eats the next three spells fired through it.",
	"blade_flurry": "A fan of crescent slashes torn out in front of you, at arm's length.",
	"blink_strike": "Vanish, reappear at your aim, and burst the ground you land on.",
	"blizzard": "A lasting field of frost. Everything inside slows, then freezes.",
	"blood_pact": "Everything you cast hits far harder, and you bleed for every second of it.",
	"boulder_hurl": "Rip a slab out of the floor and throw it straight down your aim.",
	"chain_lightning": "A bolt that leaps body to body, hunting the next one in range.",
	"creeping_shade": "A shadow races the floor, passes under walls, and spikes what it reaches.",
	"crescent_step": "Dash forward and cut the whole lane you crossed on the way through.",
	"drain_tether": "Lash a hook down your aim. It drags life back to you while it holds.",
	"fault_line": "A rupture tears along the floor, splitting cover. A pit stops it dead.",
	"frozen_comet": "A crest of ice erupts from the ground and races outward, freezing as it goes.",
	"grave_tide": "The floor opens both ways and hands hold what they catch. Be airborne.",
	"gravity_flip": "Gravity inverts for the entire room, you included. Everything falls up.",
	"heavens_verdict": "One verdict falls on the ground you marked. The heaviest hit in the tower.",
	"heavens_wrath": "A storm cell drifts across the field, dropping five marked strikes.",
	"horizon_cut": "A travelling crescent of edge that keeps going through whatever it cuts.",
	"iai_slash": "One committed draw-cut, a body and a half long. Whiff it and you wait.",
	"ice_wall": "A wall of ice planted where you aim. It blocks shots and chills on touch.",
	"judgment": "A single pillar of holy light drops on the ground you mark.",
	"meteor_fist": "Leap, and come down fist-first. The blast ring is drawn before you jump.",
	"meteor_sigil": "A sigil opens overhead and rains burning rock across the marked circle.",
	"mirror_image": "A copy of you appears and repeats every spell you cast, one beat behind.",
	"ordinary_spell": "A straight arcane lance punched down your aim. The line you throw all fight.",
	"petrify": "Turn a body to stone where it stands, then pick the statue up and throw it.",
	"radiant_volley": "A rack of parallel holy lances. Stand in the middle and take every one.",
	"raise_thrall": "Call a servant out of the ground. Two better ones, if something died here.",
	"rift_dagger": "Throw a dagger that sticks where it lands. Press again to tear across to it.",
	"rock_pillar": "Telegraphed ground erupts into stone, launching whoever was standing on it.",
	"rock_wall": "A slab of stone rises to block the lane. Cast again to shove it forward.",
	"rune_orbs": "A staggered fan of rune-orbs, flung exactly where you aimed and nowhere else.",
	"shatter": "A frost charge hurled at the ground. It rimes what it lands on; TRIPLE on a frozen body.",
	"shockwave_stomp": "Boot the floor. A ridge runs along the ground to either side of you.",
	"thousand_cuts": "Mark one body, vanish, and open it from every angle at once.",
	"thunderclap": "A jagged bolt rips straight down your aim from a charged fist.",
	"void_zone": "Shadows race out from your feet and root whatever the closing mark catches.",

	# -- floor pickups and boss drops (`build_tier2` / `build_tier3`) -----------
	"arc_of_fools": "Six greedy links of lightning. It leaps to any body, friends included.",
	"chronostasis": "Freeze a circle for three seconds. All damage dealt to it lands at once.",
	"equinox": "Every living thing in the room is dragged to the same share of its own health.",
	"meteor_storm": "A long, loud channel, then sixteen rocks across a very wide circle.",
	"roulette": "One of the other three cataclysms at random, and sometimes centred on you.",
	"severance": "Mark a ring, wait, then execute. Each victim is priced off its own wounds.",
	"siegeworks": "Two stone faces rise and walk inward, shrinking the arena around everyone.",
	"teardown": "Rip every piece of cover out of the ring and throw all of it at once.",
	"the_circuit": "No radius at all. It arcs through every hostile on the stage, in turn.",
	"the_void": "A singularity collapses and deletes what is inside it. Allies included.",

	# -- authored, tuned, and in nobody's kit today. Kept because the drop pool and
	# the review harness still build them, and a spell a player can be HANDED with no
	# description is the same failure as one on a class card. ------------------
	"avalanche": "Boulders fall across the marked circle and stagger whatever they land on.",
	"colossus_pillar": "A titanic stone spire slams up through the spot you marked.",
	"frostpiercer": "The thinnest, longest frost beam. A precision poke, not a finisher.",
	"infernal_lance": "The fattest fire beam in the tower. It wins any head-on clash.",
	"tempest": "A lightning beam built to be fired through your own ice field.",
	"umbral_lance": "A channelled shadow beam, long enough to win the clash it starts.",
	"void_barrage": "Shadow meteors rain on the marked circle and pop where they land.",
	"zanshin": "A stance that counts everyone who enters, then one cut worth all of them.",
}


## The blurb for a spell id, or `""` when there is none.
##
## Returns EMPTY rather than a placeholder on purpose. A caller that renders "no
## description available" ships that string to a player and nobody ever notices; a
## caller that renders nothing leaves a visible hole, and `missing_ids()` plus the
## suite turn that hole into a red test before it reaches a screen.
static func for_id(id: String) -> String:
	return String(BLURBS.get(id, ""))


static func has_blurb(id: String) -> bool:
	return BLURBS.has(id)


## The blurb for a built `SpellDef`.
##
## ⚠ THE TABLE WINS, AND THAT ORDER WAS A BUG BEFORE IT WAS A DECISION. This
## deferred to `spell.description` first, on the assumption the field was empty. It is
## not: 54 of 54 are populated and 46 are over `MAX_LEN`, so every consumer that
## reserved two lines silently got three or four. The def is the long form and this is
## the short form; the short form is what a 30 px row and a one-line header can hold.
##
## The def is still the FALLBACK, so a spell this table has never heard of -- a
## `.tres`-authored drop added after this file -- says something rather than nothing.
## `missing_ids()` plus the suite exist so that fallback stays a safety net rather than
## a way for a spell to quietly ship with a four-line label.
static func for_spell(spell: SpellDef) -> String:
	if spell == null:
		return ""
	var short: String = for_id(spell.id)
	if short != "":
		return short
	return spell.description.strip_edges()


## Every id this table covers, sorted. Used by the suite and by nothing else.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in BLURBS.keys():
		out.append(String(k))
	out.sort()
	return out


## WHICH OF `wanted` HAS NO BLURB -- the check that makes this table auditable.
##
## A description table that silently covers 40 of 54 is exactly the failure the
## `ClassInfo` header is about: the screen looks finished and a seventh of the roster
## reads as blank. The suite feeds this the library's own id list, so adding a spell to
## `SpellLibrary` and forgetting this file is a RED TEST rather than an empty label.
static func missing_ids(wanted: Array) -> Array[String]:
	var out: Array[String] = []
	for w: Variant in wanted:
		var id: String = String(w)
		if id != "" and not BLURBS.has(id):
			out.append(id)
	out.sort()
	return out


## Entries longer than `MAX_LEN`. Same reasoning as `missing_ids`, from the other end:
## an over-long blurb does not error, it wraps to a fifth line and pushes the panel it
## sits in off the bottom of a 360 px phone -- where only a capture would ever show it.
static func overlong_ids() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in BLURBS.keys():
		if String(BLURBS[k]).length() > MAX_LEN:
			out.append(String(k))
	out.sort()
	return out
