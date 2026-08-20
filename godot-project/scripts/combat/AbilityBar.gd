class_name AbilityBar
extends Control
## MMO-style ability/cooldown hotbar HUD, drawn entirely in code (no scene).
## Lives under a CanvasLayer so it renders in screen space — the world camera
## zoom never touches it. Each frame it polls the hero's `ability_hud_state()`
## contract and redraws: slot panels, key labels, cooldown wipes + timers, a
## ready-glow, and a dimmed read for class-disabled abilities. If no hero is
## in the tree (hub/menu scenes reuse this HUD), it simply draws nothing.
##
## The bar reads in TWO CLUSTERS separated by a gap: the body verbs on the left, and
## the equipped SPELL SOCKETS on the right, ramped weakest-to-heaviest so the ult is
## always the far-right button. Neither the split nor the ramp is authored anywhere —
## both are derived per frame from the hero's own data (`SpellTier.of`), so a retuned
## spell or a mid-floor pickup rearranges the bar without a HUD edit.
##
## ⚠ SIX SQUARES, BY RULING. Watching a live playtest the maker cut it: **"4 spells,
## deflect and basic attack — that's all there should be to all of them."** So the left
## cluster is now exactly the DEFENSIVE verb and the BASIC ATTACK, and the right is the
## four spell sockets. The rows that used to pad the left — the class's movement verb
## (Spc), its AoE (Q), Blink (R) and Nova (T) — are no longer published at all; see the
## ⚠ block on `Hero.ability_hud_state`, which also explains why the KEYS still work.
## Nothing here counts them: the split is found by counting back `SpellTier.SLOT_COUNT`
## from the end, so this file needed no arithmetic change to obey the ruling.

## -- Layout -------------------------------------------------------------
## ⚠ 46px is a THUMB TARGET (D-011 mobile-first), not a look. Nothing below is
## allowed to shrink a slot to make the bar fit — the bar splits into groups and
## re-orders, but every slot stays the same reachable size.
const SLOT_SIZE: float = 46.0
const SLOT_GAP: float = 6.0
## THE BREAK BETWEEN WHAT YOU DO WITH YOUR BODY AND WHAT YOU THROW.
##
## The bar was one undifferentiated run of nine squares, so finding Parry mid-fight
## meant reading names — and reading is exactly what a player has no spare attention
## for while something is winding up at them. Two clusters with a physical gap can be
## found by POSITION instead: the body verbs live at the left end, the spell sockets at
## the right, and the hand learns "left edge = the thing that saves you".
##
## Three slot-gaps wide: enough that the eye reads two objects rather than one row,
## small enough that the whole bar still centres inside the 640px base viewport. Since
## the six-thing ruling that is 6 slots + 5 gaps + this = 324px of 640 — the gap got
## cheaper, not more expensive, so nothing here needed retuning.
const GROUP_GAP: float = 18.0
## Rank inside the LEFT cluster, lowest first. The DEFENSIVE verb, then the rest.
##
## ⚠ KEYED ON THE KEY LABEL, not on the ability NAME and not on the slot INDEX. The
## defensive slot's name is class-dependent — `Hero._defense_hud_slot` answers "Guard"
## for a held-guard class and "Parry" for a press-window one — so a name match would
## silently drop half the roster's defence out of the cluster. An absolute index is the
## thing this file already refuses to trust (see _stamp_charges). The fixed rows' key
## labels are literals in `Hero.ability_hud_state`, so they are the most stable fact
## published about a verb slot.
##
## ⚠ "R" AND "Spc" USED TO RANK HERE and were dropped with the six-thing ruling, not
## lost: Blink and the movement verb are no longer published as bar rows at all, so a
## rank for them would be a rule about slots that cannot arrive. Left as a table rather
## than collapsed to an `if`, because putting a verb back is one row.
const VERB_RANK: Dictionary = {"RMB": 0}
## Everything the table does not name keeps its published order, after the defence —
## today that is the basic attack alone. Any value above the ranked ones will do.
const VERB_RANK_OTHER: int = 9
## Breathing room below the bar so it doesn't kiss the screen edge.
const BOTTOM_MARGIN: float = 14.0

## ══ THE BAR IS A THUMB TARGET ONLY WHERE THERE IS A THUMB ══════════════════════
## Maker: *"the spell boxes are too big when I make it full screen, they also increase
## in size, they should be smaller or on the side"*.
##
## ⚠ `SLOT_SIZE` 46 IS LOCKED AND STAYS LOCKED — but read WHY it is locked: it is a
## THUMB TARGET (D-011, mobile-first). On a desktop nobody is touching the screen; the
## slots are read, not pressed, and 46 px of a 360 px design height is 13% of the
## picture spent on six squares a keyboard player never aims at.
##
## And it does grow in fullscreen, exactly as reported. The project stretches
## canvas_items/expand from a 640x360 base, so a 1920x1080 screen scales everything 3x:
## the bar goes from ~98 real px to ~138. Fullscreen shows the same picture BIGGER
## rather than showing more of it, and the HUD is the part of that you notice.
##
## So the bar keeps its full thumb size wherever a touch pad can appear, and shrinks
## where one cannot. `_touch_pad_live()` already draws NOTHING on touch devices, so this
## scale only ever applies to the desktop case — the locked constant is untouched and
## the mobile contract is unchanged.
const DESKTOP_SCALE: float = 0.62
## ...and it moves OUT OF THE MIDDLE. The maker offered "smaller or on the side" and the
## side is worth taking on its own merits: centre-bottom is where two fighters land, and
## it is the same real estate the camera has to reserve. Hugging the left edge frees the
## centre of the frame for the thing the frame is about.
const SIDE_MARGIN: float = 16.0
## Inset for the key label from the slot's top-left corner.
const KEY_PADDING: Vector2 = Vector2(4.0, 3.0)
## Lift for the ability name off the slot's bottom edge.
const NAME_BOTTOM_PADDING: float = 3.0

## -- Type ---------------------------------------------------------------
const KEY_FONT_SIZE: int = 10
const NAME_FONT_SIZE: int = 8
const TIMER_FONT_SIZE: int = 15

## -- Colors -------------------------------------------------------------
## Dark panel + light text so slots read on both dark arenas and bright hubs.
const PANEL_COLOR: Color = Color(0.08, 0.08, 0.12, 0.88)
const BORDER_COLOR: Color = Color(0.36, 0.36, 0.44, 0.9)
const BORDER_WIDTH: float = 1.0
## Accent: the "usable NOW" glow — cool cyan so it pops against the warm
## combat VFX without fighting the element colours.
const READY_GLOW_COLOR: Color = Color(0.55, 0.9, 1.0, 0.9)
const READY_GLOW_WIDTH: float = 2.0
const KEY_TEXT_COLOR: Color = Color(0.95, 0.96, 1.0)
const NAME_TEXT_COLOR: Color = Color(0.62, 0.62, 0.7)
const TIMER_TEXT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)
## Cooldown wipe: dark + semi-transparent so the slot art stays legible
## underneath while clearly reading "not yet".
const COOLDOWN_OVERLAY_COLOR: Color = Color(0.0, 0.0, 0.0, 0.6)
## Whole-slot alpha multiplier when an ability is class-disabled (e.g. the
## mage's Parry slot) — present but visibly "not yours".
const DISABLED_ALPHA: float = 0.32
## The "this is the one the cast key throws" frame, drawn OUTSIDE the slot so the
## cooldown wipe cannot cover it. Warm, to read as a selection rather than as another
## readiness state — READY_GLOW_COLOR already owns the cool end.
const SELECTED_COLOR: Color = Color(1.0, 0.94, 0.72, 0.95)
const SELECTED_GROW: float = 2.5
const SELECTED_WIDTH: float = 1.5
## THE READY-FLASH: "you can act NOW", said once, at the moment it becomes true.
##
## The resting `READY_GLOW` answers "is this usable" for a player who LOOKS at the bar.
## It cannot answer "it just came back" for a player who is looking at the fight, which
## is every player — a static border has no event in it. So a slot that transitions to
## ready throws a frame that expands OUTWARD and fades: motion, which peripheral vision
## is built to catch, in the cool accent the bar already uses for readiness.
##
## The EDGE is detected by the hero (`Hero._tick_ready_pulse`) and arrives here as a
## 1 -> 0 `pulse` in the slot dictionary. Deliberately not latched here: this bar is
## rebuilt from a poll every frame and is not even in the tree in some scenes, so a
## HUD-side latch would miss edges that happened while it was away, and a second HUD
## reading the same hero would keep its own private, differently-wrong copy.
const READY_FLASH_COLOR: Color = Color(0.6, 0.95, 1.0)
const READY_FLASH_GROW: float = 9.0
const READY_FLASH_WIDTH: float = 2.5
## ── THE SPELL SOCKET ─────────────────────────────────────────────────────────
## A spell slot was drawing identically to Dash: a dark square with a word in it.
## So the kit — the part of the bar the player actually chose, and the only part
## that changes between classes — was the least distinguishable thing on screen.
##
## A socket says three things a label cannot. The RING is the spell's own colour
## (`SpellDef.resolve_color`, the same resolution the cast uses), so the border
## matches what comes out of your hand — you find your fire slot by looking for
## orange, not by reading. The CORNER BRACKETS carry the tier colour, so the shelf
## (QUICK / HEAVY / ULT) is legible without a fourth line of text in a 46px box.
## The faint WASH keeps the identity readable when the cooldown veil is over it.
##
## ⚠ ALL OF IT IS DRAWN INSIDE THE SLOT RECT. The slot's outer edge is already a
## language — resting border, ready glow, selected frame, ready flash — and every
## one of those means something the socket does not. The socket takes the inner lip
## and touches none of them, so nothing that was readable before got quieter.
## The ring colour again at low alpha, filling the socket. Deliberately weak: it is
## a tint on the panel, not a second background competing with the cooldown veil.
const SOCKET_WASH_ALPHA: float = 0.13
## An EMPTY socket is drawn, in neutral steel, rather than left as a bare panel —
## "you have a slot here and nothing in it" is a thing worth being able to see, and
## it is the same reason Hero draws the "--" row instead of shrinking the bar.
const EMPTY_SOCKET_COLOR: Color = Color(0.45, 0.45, 0.55, 0.85)

## ── THE ULT'S OWN FRAME ──────────────────────────────────────────────────────
## Maker: "the 4 / ultra should have that special border."
##
## The far-right socket already differs by TIER COLOUR on its corner brackets, which
## is a real signal and a quiet one — three shelves of bracket in three hues, read at
## 46 px, while something is winding up at you. The ult is not one of three shelves;
## it is the button you are saving. So it gets a frame nothing else on the bar has: a
## full double ring, drawn OUTSIDE the slot so the cooldown veil cannot swallow it,
## in the tier's own gold.
##
## ⚠ KEYED ON THE TIER, NOT ON BEING LAST. The row is sorted by `SpellTier.of` at draw
## time, so "last" is a consequence and the tier is the cause — a retuned spell that
## stopped being an ult would otherwise keep the crown for sitting in the right place.
## (`ULT_FRAME_GROW` / `_WIDTH` / `_GAP` lived here and are gone with the rectangle
## they sized. The crown is a counter-rotating gold RING now — see `_draw_socket`.
## Deleted rather than left declared: an unused constant invites the next edit to
## find a use for it.)

## ── TIER 3 CHARGE PIPS ───────────────────────────────────────────────────────
## A picked-up spell has a COUNT, and "picking one up is a decision" only holds if
## the count is visible BEFORE you spend it. Pips rather than a number because the
## counts are 1–2 and a row of dots is read without focusing; gold because that is
## what the pickup was wearing on the floor (`SpellPickup.TIER3_GOLD`), so they say
## "the spell you found" rather than "another timer".
const PIP_COLOR: Color = Color(1.0, 0.86, 0.42, 0.95)
const PIP_RADIUS: float = 2.6
const PIP_GAP: float = 7.0
const PIP_INSET: Vector2 = Vector2(5.0, 6.0)
const PIP_MAX_DOTS: int = 4
const PIP_FONT_SIZE: int = 10

## Snapshot of the hero's slot dictionaries, refreshed once per frame in
## _process and consumed by _draw. Empty = draw nothing (no hero this scene).
var _slots: Array = []
## Current class name, drawn above the hotbar so the player always knows their class.
var _class_name: String = ""


func _ready() -> void:
	# Full-rect anchors so our size tracks the viewport; all layout is
	# recomputed in _draw from the live viewport size (no hardcoded res).
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Pure HUD readout — never eat clicks meant for the game underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## THE HOTBAR STANDS DOWN WHEN THE TOUCH PAD IS LIVE.
##
## Not a preference — the two collide. The pad's spell arc and DASH sit in the
## bottom-right corner, and at 640x360 base their rectangles physically overlap this
## bar's (measured in a capture, not reasoned about).
##
## ⚠ THE SECOND HALF OF THIS ARGUMENT DIED WITH THE SIX-THING RULING and it is worth
## saying so rather than leaving a stale claim standing. The bar used to draw Q / R / T
## — verbs a thumb cannot reach at all under the pad's scheme — so the overlap was also
## buying the phone player a readout for buttons they do not have. It no longer draws
## them. What remains is purely the geometric collision: at 6 slots the bar still spans
## x 158..482 of 640 and the first spell pad sits at x 385..445, so they are still on
## top of each other and one of them has to yield.
##
## The pad carries its own veils and ready-flashes on every button it DOES show, from
## the same `Hero` publishers this bar reads, so nothing is lost on that platform.
##
## Gated on a live pad rather than on `DisplayServer.is_touchscreen_available()`,
## because a touchscreen laptop played with a keyboard must keep its hotbar — and
## `TouchControls` only joins the group when it has actually shown itself.
## 1.0 where a thumb has to hit it, smaller where it is only read. See DESKTOP_SCALE.
static func slot_scale() -> float:
	return 1.0 if DisplayServer.is_touchscreen_available() else DESKTOP_SCALE


## ⚠ HOW MUCH OF THE BOTTOM OF THE SCREEN THIS COVERS — published, because the CAMERA
## needs it and had no way to ask. `CombatCamera` used to carry a hardcoded 69 px copy
## of this arithmetic, which is a second definition that goes stale the moment the bar
## is resized. It just was. One owner, one number.
static func occupied_height() -> float:
	var k: float = slot_scale()
	return (BOTTOM_MARGIN + SLOT_SIZE) * k + 9.0 * k     # + the class label above it


func _touch_pad_live() -> bool:
	return get_tree().get_first_node_in_group(TouchControls.PAD_GROUP) != null


func _process(_delta: float) -> void:
	if _touch_pad_live():
		_slots = []
		_class_name = ""
		queue_redraw()
		return
	# Poll-don't-push: cooldown timers tick every frame anyway, so a per-frame
	# read of the hero contract is simpler than plumbing signals for 6 slots.
	var hero: Node = get_tree().get_first_node_in_group("hero")
	if hero == null or not hero.has_method("ability_hud_state"):
		_slots = []
		_class_name = ""
	else:
		_slots = hero.ability_hud_state()
		_class_name = String(hero.call("class_display_name")) if hero.has_method("class_display_name") else ""
		_repair_signature_label(hero)
		_stamp_charges(hero)
		_stamp_spell_identity(hero)
	queue_redraw()


## Fold each signature slot's remaining charges into the slot dictionary, so
## `_draw_slot` stays a pure function of one dictionary and never has to reach back
## for a hero it was not handed.
##
## The signature slots are the LAST `SpellTier.SLOT_COUNT` entries of
## `ability_hud_state()` (a fixed prefix of ability rows, then the signatures — see
## Hero.ability_hud_state). Keyed off the END of the array rather than off absolute
## indices so adding or REMOVING an ability row above cannot silently start stamping
## charges onto the wrong square — which is exactly what earned its keep when the
## six-thing ruling cut four rows out of that prefix and this needed no edit.
func _stamp_charges(hero: Node) -> void:
	var first: int = _spell_slot_start()
	if first < 0:
		return
	for i: int in SpellTier.SLOT_COUNT:
		if not _slots[first + i] is Dictionary:
			continue
		(_slots[first + i] as Dictionary)["charges"] = SpellGrant.charges_in_slot(hero, i)


## Where the spell sockets begin in `_slots`, or -1 if the contract is too short to
## hold them. Three readers now depend on this one rule — the charge stamp, the
## identity stamp, and the draw-order split — so it is written once. Getting it
## wrong by one would badge Dash as a spell and sort the bar by a tier it invented.
func _spell_slot_start() -> int:
	var first: int = _slots.size() - SpellTier.SLOT_COUNT
	return first if first >= 0 else -1


## Fold each spell slot's COLOUR and TIER into its dictionary, from the SpellDef the
## hero already holds. Same reason as `_stamp_charges`: `_draw_slot` stays a pure
## function of one dictionary and never reaches back for a hero it was not handed.
##
## The tier is DERIVED (`SpellTier.of`), never read off the name — that is the whole
## point of SpellTier, and it is what makes the strength ordering honest: retune a
## spell to be slower and pricier and it moves rightward along the bar on its own.
## A null (empty) slot resolves to QUICK and therefore sorts to the light end, which
## is where a hole in your kit belongs.
##
## The colour goes through `SpellDef.resolve_color` rather than straight to
## `Elements.color`, because that is the function the SPELL uses to decide what it
## looks like: it honours an explicit override (`_ray()` turns use_element_color off,
## so Judgment stays gold) and only falls back to the element when the spell has not
## said. The fallback is the same guess the cast sigil makes (SpellCaster.resolve_
## element), so the socket and the magic circle can never disagree about a spell.
func _stamp_spell_identity(hero: Node) -> void:
	var first: int = _spell_slot_start()
	if first < 0 or not hero.has_method("signature_at"):
		return
	for i: int in SpellTier.SLOT_COUNT:
		if not _slots[first + i] is Dictionary:
			continue
		var slot: Dictionary = _slots[first + i]
		var sig: SpellDef = hero.call("signature_at", i) as SpellDef
		slot["tier"] = SpellTier.of(sig)
		var accent: Color = EMPTY_SOCKET_COLOR
		if sig != null:
			accent = sig.resolve_color(Elements.color(SpellCaster.resolve_element(sig)))
		slot["accent"] = accent
		slot["glyph"] = glyph_for(sig)


# ══ THE SOCKET GLYPH — the THIRD axis, after colour and tier ═══════════════════
## A class whose spells share an element showed four sockets of the same colour,
## and tier only separates three weights across four slots. The figure inside is
## what tells them apart, and it is the SAME thirteen drawings the cast circle
## uses (`MagicCircle.draw_motif`), so it costs the player nothing to learn.
##
## ⚠ THE OBVIOUS IMPLEMENTATION IS THE WRONG ONE, AND IT WAS BUILT TO FIND OUT.
## Keying the glyph on `SpellDef.Kind` was rendered across all nine classes and
## EIGHT OF NINE had a duplicated figure — the Shadowblade drew three identical
## BLADE circles. That is not a bug in the table: `MagicCircle.Motif` is keyed by
## CONSEQUENCE on purpose ("two different wall spells SHOULD open the same
## figure"), which is exactly right for a cast circle and exactly wrong for a
## hotbar, whose entire job is telling four spells apart. So the primary key is
## the SPECTACLE.
##
## Measured over all 36 reachable hands (a class has C(4,3)=4 hands, because the
## player leaves one non-ult role behind at class-select — the DEFAULT hand alone
## would have reported a much rosier number):
##
##     live table only                24 of 36 hands carry a duplicate
##     + the 11 SpellSigil additions  19 of 36
##     + these 8 overrides             0 of 36
##
## ⚠ WHY THE OVERRIDES LIVE HERE AND NOT IN `SpellSigil.MOTIF_BY_SCRIPT`. Three of
## the eight would make the WORLD cast circle less accurate — a rock pillar really
## does erupt, a shadow root really does snare, a convergence really does descend.
## The two tables answer different questions, so they are allowed to differ: the
## world says WHAT WILL HAPPEN, the hotbar says WHICH SPELL THIS IS. What is NOT
## duplicated is the drawing — that is one static, and it cannot drift.
const GLYPH_OVERRIDE: Dictionary = {
	"RiftDagger.gd": MagicCircle.Motif.LANCE,        # world: BLADE. it is THROWN
	"ChainBolt.gd": MagicCircle.Motif.SNARE,         # world: LANCE. a chain holds
	"DrainTether.gd": MagicCircle.Motif.VOID,        # world: SNARE. it unmakes
	"BlinkStrike.gd": MagicCircle.Motif.SPIRAL,      # world: BLADE. the rules bend
	"HorizonArc.gd": MagicCircle.Motif.PULSE,        # world: LANCE. it sweeps out
	# The three that would DEGRADE the world reading, so they stay hotbar-local.
	"RockPillar.gd": MagicCircle.Motif.BARRIER,      # world stays ERUPTION
	"ShadowRoot.gd": MagicCircle.Motif.WARD,         # world stays SNARE
	"StarConvergence.gd": MagicCircle.Motif.ORBIT,   # world stays DESCENT
	# Two ULTs that collide with their OWN class's basic spell. Both of these are
	# spectacles that declare their world figure themselves (`sigil_motif`), and
	# both declarations are right for the world — a thousand cuts IS a blade, a
	# fault line DOES come up out of the ground. But on a Shadowblade's bar the
	# blade figure is already taken by `blade_flurry`, and on a Juggernaut's the
	# eruption is already taken by `boulder_hurl`. So the bar states the OTHER true
	# thing about each: what makes them different from their neighbour.
	"ThousandCuts.gd": MagicCircle.Motif.PULSE,      # world BLADE. it opens you from every angle
	"FaultLine.gd": MagicCircle.Motif.LANCE,         # world ERUPTION. it TRAVELS
}

## FALLBACK ONLY, and it must cover every `Kind`. `SpellCaster.spectacle_path`
## returns `EnergyNova.tscn` for NOVA — a `.tscn`, which the script-keyed table
## cannot hold — so without this row a nova resolves to `NONE`, and a `NONE` draws
## NOTHING, which looks exactly like the flat socket this whole pass replaced.
const MOTIF_BY_KIND: Dictionary = {
	SpellDef.Kind.BEAM: MagicCircle.Motif.LANCE,
	SpellDef.Kind.DIVINE_RAY: MagicCircle.Motif.DESCENT,
	SpellDef.Kind.NOVA: MagicCircle.Motif.PULSE,
	SpellDef.Kind.METEOR: MagicCircle.Motif.DESCENT,
	SpellDef.Kind.CONVERGENCE: MagicCircle.Motif.DESCENT,
	SpellDef.Kind.RUSH: MagicCircle.Motif.LANCE,
	SpellDef.Kind.BOULDER: MagicCircle.Motif.ERUPTION,
	SpellDef.Kind.PILLAR: MagicCircle.Motif.ERUPTION,
	SpellDef.Kind.WALL: MagicCircle.Motif.BARRIER,
	SpellDef.Kind.ICE_WALL: MagicCircle.Motif.BARRIER,
	SpellDef.Kind.CHAIN: MagicCircle.Motif.LANCE,
	SpellDef.Kind.ZONE: MagicCircle.Motif.WARD,
	SpellDef.Kind.MISSILES: MagicCircle.Motif.ORBIT,
	SpellDef.Kind.BLINK_STRIKE: MagicCircle.Motif.BLADE,
	SpellDef.Kind.TETHER: MagicCircle.Motif.SNARE,
	SpellDef.Kind.FLURRY: MagicCircle.Motif.BLADE,
	SpellDef.Kind.CRAWLER: MagicCircle.Motif.SNARE,
	SpellDef.Kind.THROWN_ANCHOR: MagicCircle.Motif.BLADE,
	SpellDef.Kind.WARD: MagicCircle.Motif.WARD,
	SpellDef.Kind.ARC: MagicCircle.Motif.LANCE,
	SpellDef.Kind.HEX: MagicCircle.Motif.SPIRAL,
	SpellDef.Kind.CATACLYSM: MagicCircle.Motif.VOID,
}

## Which figure this spell wears on the bar. Static and pure, so the guard suite
## can ask it about every class's every hand without building a HUD.
static func glyph_for(sig: SpellDef) -> int:
	if sig == null:
		return MagicCircle.Motif.NONE
	var file: String = SpellCaster.spectacle_path(sig).get_file()
	if not file.is_empty():
		var over: int = int(GLYPH_OVERRIDE.get(file, MagicCircle.Motif.NONE))
		if over != MagicCircle.Motif.NONE:
			return over
		var shared: int = int(SpellSigil.MOTIF_BY_SCRIPT.get(file, MagicCircle.Motif.NONE))
		if shared != MagicCircle.Motif.NONE:
			return shared
	return int(MOTIF_BY_KIND.get(sig.kind, MagicCircle.Motif.NONE))


## THE BIG BEAM'S NAME. `Hero._signature_hud_slot()` shortens the equipped
## signature with `display_name.split(" ")[0]` — take the first word — which was
## fine for "Infernal Lance" and "Umbral Lance" and broke the moment the IP pass
## renamed `zoltraak` to **"The Ordinary Spell"**. First word of that is "The",
## so the maker's signature beam has been labelled `The` on the hotbar ever since.
##
## Fixed HERE rather than in Hero.gd because Hero is held by another agent — and
## the fix has to live at the point the label is CHOSEN, not merely rendered:
## once Hero has already thrown away everything after the first space, "The" is
## unrecoverable. So the bar goes back to the source (`current_signature()`, a
## public method it already polls this same hero for) and re-derives the short
## name properly. When Hero.gd learns the same rule this becomes a no-op that
## computes the identical string — it is not a race, both sides agree.
##
## Only the SELECTED spell slot is touched, and only when it is not showing the Rift
## Dagger's transient "RECALL" state, so a reordering of the hotbar cannot make this
## repair the wrong slot.
##
## ⚠ TARGETED BY `selected`, NOT BY THE KEY LABEL "G". The bar now draws one slot per
## kit spell rather than one cycled one, and the key label is a fact about the BINDINGS
## (the cast key on the selected slot, the cycle key on the others) — so keying the
## repair off "G" would silently start repairing whichever slot happened to hold the
## cast binding after a control-scheme change. `current_signature()` describes the
## selected slot and nothing else, so `selected` is the only honest match.
func _repair_signature_label(hero: Node) -> void:
	if _slots.is_empty() or not hero.has_method("current_signature"):
		return
	var sig: SpellDef = hero.call("current_signature") as SpellDef
	if sig == null or sig.display_name == "":
		return
	for i: int in range(_slots.size()):
		if not _slots[i] is Dictionary:
			continue
		var slot: Dictionary = _slots[i]
		if not bool(slot.get("selected", false)) or String(slot.get("name", "")) == "RECALL":
			continue
		slot["name"] = short_spell_name(sig.display_name)
		return


## A hotbar-sized label for a spell, from its full display name.
##
## The rule is "the most IDENTIFYING word", not "the first word" — the two only
## agree when a name happens to open with its own noun. Leading articles carry no
## identity at all, so they are dropped, and what is left is the first remaining
## word ("The Ordinary Spell" -> "Ordinary", "Infernal Lance" -> "Infernal",
## "Frostpiercer" -> "Frostpiercer"). A name that is NOTHING but articles falls
## back to the whole string rather than to the empty one — a wrong label is
## recoverable, a blank slot is not.
##
## Static and pure so a test can pin it without a scene tree.
static func short_spell_name(display_name: String) -> String:
	const ARTICLES: Array[String] = ["the", "a", "an", "of"]
	for word: String in display_name.split(" ", false):
		if not ARTICLES.has(word.to_lower()):
			return word
	return display_name


## THE ORDER ON SCREEN IS NOT THE ORDER IN `_slots`, and the difference is
## deliberate: the hero publishes its rows in the order it happens to compute them
## (the basic attack, then defence, then the kit), which is an implementation detail
## of Hero.gd, not a reading order for a player under pressure — the defensive verb
## is pulled to the left edge here so the hand can find it without reading.
##
## ⚠ REORDERING IS DRAW-ONLY — `_slots` is never permuted. Both stamps above index
## it POSITIONALLY against the hero (slot i's charges, slot i's SpellDef), so a
## permuted `_slots` would start putting one spell's charges on another's socket.
## The rows below hold references to the same dictionaries, so every stamp still
## lands; only where they are painted changes.
##
## Malformed entries are dropped here rather than skipped mid-loop, so a bad row
## leaves no hole for the eye to read as a missing ability.
func _verb_row() -> Array:
	var first: int = _spell_slot_start()
	var end_i: int = first if first >= 0 else _slots.size()
	var items: Array = []
	var ranks: Array = []
	for i: int in range(end_i):
		if not _slots[i] is Dictionary:
			continue
		var slot: Dictionary = _slots[i]
		items.append(slot)
		ranks.append(int(VERB_RANK.get(String(slot.get("key", "")), VERB_RANK_OTHER)))
	return _stable_by_rank(items, ranks)


## The spell sockets, WEAKEST FIRST — so the bar is a strength ramp and the ult
## always sits at the far right end, under the same finger every time whatever the
## class. Sorted by the derived tier, so it stays true when a spell is retuned or a
## Tier 3 pickup drops into a slot mid-floor; ties keep the slot order the keys 1/2/3
## already imply, so two QUICK spells never swap places under the player's thumb.
func _spell_row() -> Array:
	var first: int = _spell_slot_start()
	if first < 0:
		return []
	var items: Array = []
	var ranks: Array = []
	for i: int in range(first, _slots.size()):
		if not _slots[i] is Dictionary:
			continue
		var slot: Dictionary = _slots[i]
		items.append(slot)
		ranks.append(int(slot.get("tier", SpellTier.Tier.QUICK)))
	return _stable_by_rank(items, ranks)


## `items` ordered by `ranks`, ties keeping their original order.
##
## `Array.sort_custom` is NOT stable, so the tie is broken on the original index
## rather than left to the sort — an unstable tie here would let two equal-tier
## spells trade places between frames, which on a hotbar is the worst possible
## failure: the button moves out from under a press already in flight.
static func _stable_by_rank(items: Array, ranks: Array) -> Array:
	var order: Array = []
	for i: int in range(items.size()):
		order.append(i)
	var by_rank: Callable = func(a: int, b: int) -> bool:
		if int(ranks[a]) == int(ranks[b]):
			return a < b
		return int(ranks[a]) < int(ranks[b])
	order.sort_custom(by_rank)
	var out: Array = []
	for i: int in order:
		out.append(items[i])
	return out


func _draw() -> void:
	if _slots.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var view: Vector2 = get_viewport_rect().size
	var verbs: Array = _verb_row()
	var spells: Array = _spell_row()
	var count: int = verbs.size() + spells.size()
	if count == 0:
		return
	# No gap unless there is something on both sides of it — a lone group must stay
	# centred, not sit off to one side of a break with nothing behind it.
	var k: float = slot_scale()
	var slot_px: float = SLOT_SIZE * k
	var split: float = (GROUP_GAP * k) if not verbs.is_empty() and not spells.is_empty() else 0.0
	var total_w: float = float(count) * slot_px + float(count - 1) * (SLOT_GAP * k) + split
	# Centred where it is a thumb target, tucked into the left corner where it is not —
	# see DESKTOP_SCALE / SIDE_MARGIN.
	var origin_x: float = (view.x - total_w) * 0.5 if is_equal_approx(k, 1.0) 		else SIDE_MARGIN
	var origin_y: float = view.y - (BOTTOM_MARGIN * k) - slot_px
	# Class name centered just above the hotbar (always know your class).
	if _class_name != "":
		draw_string(
			font, Vector2(origin_x, origin_y - 9.0), _class_name.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, total_w, int(round(13.0 * k)),
			Color(0.95, 0.96, 1.0, 0.95)
		)
	var x: float = origin_x
	for slot: Dictionary in verbs:
		_draw_slot(Rect2(Vector2(x, origin_y), Vector2(slot_px, slot_px)), slot, font)
		x += slot_px + SLOT_GAP * k
	x += split
	for slot: Dictionary in spells:
		_draw_slot(Rect2(Vector2(x, origin_y), Vector2(slot_px, slot_px)), slot, font)
		x += slot_px + SLOT_GAP * k


## Draw one hotbar slot: panel + border + key/name labels, then either the
## cooldown wipe + seconds readout or the ready glow. `enabled == false`
## dims the whole slot and suppresses the glow.
func _draw_slot(rect: Rect2, slot: Dictionary, font: Font) -> void:
	# Defensive reads: the contract is trusted but a missing key shouldn't
	# take the HUD down (same .get()-with-fallback idiom as the save layer).
	var ability_name: String = String(slot.get("name", ""))
	var key_label: String = String(slot.get("key", ""))
	var remaining: float = float(slot.get("remaining", 0.0))
	var total: float = float(slot.get("total", 0.0))
	var enabled: bool = bool(slot.get("enabled", true))
	var alpha: float = 1.0 if enabled else DISABLED_ALPHA

	# Panel + resting border.
	draw_rect(rect, _with_alpha(PANEL_COLOR, alpha))
	# The socket rides between the panel and the border: it is the slot's CONTENTS,
	# so it must sit under every mark that describes the slot's STATE. `accent` is
	# stamped only onto spell slots, so a verb slot is drawn exactly as it always was.
	var is_spell: bool = slot.has("accent")
	var cd_frac: float = clampf(remaining / total, 0.0, 1.0) if (remaining > 0.0 and total > 0.0) else 0.0
	if is_spell:
		var accent: Color = slot.get("accent", EMPTY_SOCKET_COLOR)
		_draw_socket(rect, accent, int(slot.get("tier", SpellTier.Tier.QUICK)), alpha,
			cd_frac, clampf(float(slot.get("pulse", 0.0)), 0.0, 1.0),
			int(slot.get("glyph", MagicCircle.Motif.NONE)))
	draw_rect(rect, _with_alpha(BORDER_COLOR, alpha), false, BORDER_WIDTH)
	# The spell slots are all live and all show their own cooldown, so the bar
	# also has to say WHICH one the cast key throws right now. A lifted outer frame
	# rather than a colour change: movement reads faster than hue when your eyes are on
	# the fight (the same reasoning as LoadoutBar's SELECTED_LIFT), and it survives the
	# cooldown wipe drawn on top of the slot below.
	if bool(slot.get("selected", false)):
		draw_rect(rect.grow(SELECTED_GROW), _with_alpha(SELECTED_COLOR, alpha),
			false, SELECTED_WIDTH)
	# (The ULT's double RECTANGLE lived here. It is the gold counter-rotating outer
	# RING inside `_draw_socket` now — the same "this one is special" job drawn in the
	# grammar the rest of the socket speaks, and gold-OUTSIDE/element-inside rather
	# than gold-on-orange, which was at its least visible on a fire ult.)

	# Key label: top-left, small + bright — the "which finger" read.
	draw_string(
		font,
		rect.position + Vector2(KEY_PADDING.x, KEY_PADDING.y + float(KEY_FONT_SIZE)),
		key_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT_SIZE,
		_with_alpha(KEY_TEXT_COLOR, alpha)
	)
	# Ability name: bottom, tiny + dim — identification, not the focal point.
	#
	# ⚠ SPELL SLOTS NO LONGER CARRY IT. At true phone pixels these were barely legible
	# grey-on-black AND the socket ring crossed them, so 8 px of every slot was spent
	# on something unreadable under pressure. The verb slots keep theirs (they name a
	# class verb you cannot infer from a shape); the spell sockets are told apart by
	# colour, ring weight and the ult's crown. A text REDUCTION, per the standing rule.
	if not is_spell:
		draw_string(
			font,
			Vector2(rect.position.x, rect.end.y - NAME_BOTTOM_PADDING),
			ability_name,
			HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), NAME_FONT_SIZE,
			_with_alpha(NAME_TEXT_COLOR, alpha)
		)

	var on_cooldown: bool = remaining > 0.0 and total > 0.0
	# ⚠ A SPELL SOCKET SHOWS ITS COOLDOWN AS ITS RING CLOSING (see `_draw_socket`), so
	# it gets neither the black wipe nor the numeral on top of it. Only the VERB slots
	# keep them: they are squares with no ring to close, and theirs are the cooldowns
	# you actually weave against. Four running "%.1f" timers were the loudest thing on
	# the whole HUD and they broke the standing no-more-text rule.
	if on_cooldown and not is_spell:
		# Bottom-up wipe: overlay height shrinks with remaining/total, so the
		# slot visibly "fills back up" as it cools — legible at a glance.
		var wipe_h: float = rect.size.y * cd_frac
		var wipe: Rect2 = Rect2(
			Vector2(rect.position.x, rect.end.y - wipe_h),
			Vector2(rect.size.x, wipe_h)
		)
		draw_rect(wipe, _with_alpha(COOLDOWN_OVERLAY_COLOR, alpha))
		# Seconds left, 1 decimal, centered — precise timing for ability weaving.
		var secs: String = "%.1f" % remaining
		draw_string(
			font,
			Vector2(rect.position.x, rect.get_center().y + float(TIMER_FONT_SIZE) * 0.35),
			secs,
			HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), TIMER_FONT_SIZE,
			_with_alpha(TIMER_TEXT_COLOR, alpha)
		)
	elif not on_cooldown and enabled:
		# Ready: a brighter accent border so the eye reads "usable" without
		# the slot shouting. Disabled slots never glow.
		draw_rect(rect, READY_GLOW_COLOR, false, READY_GLOW_WIDTH)
	# The flash rides OVER the cooldown branch rather than inside the `elif`: a slot
	# that recovers and is re-cast within READY_PULSE_TIME is back on cooldown when
	# this runs, and swallowing its flash would silence exactly the fastest, most
	# satisfying rotation the player can pull off.
	var pulse: float = clampf(float(slot.get("pulse", 0.0)), 0.0, 1.0)
	if pulse > 0.0 and enabled:
		draw_rect(rect.grow(READY_FLASH_GROW * (1.0 - pulse)),
			Color(READY_FLASH_COLOR.r, READY_FLASH_COLOR.g, READY_FLASH_COLOR.b, pulse),
			false, READY_FLASH_WIDTH)
	# LAST, over everything: the count has to survive the cooldown wipe. "Two left"
	# is exactly the fact you need while the slot is recovering and you are deciding
	# whether to spend the next one here or save it for the guardian.
	_draw_charges(rect, int(slot.get("charges", -1)), font, alpha)


## The socket frame: element wash, element ring, tier corner brackets.
##
## Brackets rather than a full second border in the tier colour, because two closed
## rectangles one pixel apart read as a rendering mistake at 46px — four corner marks
## read as a mount holding something. They are also where the eye already lands when
## it checks whether a box is full, and they are the only part of the frame that the
## bottom-up cooldown veil cannot fully swallow: the top pair always stays lit.
## ══ THE SOCKET IS A MAGIC CIRCLE ═══════════════════════════════════════════════
## Maker: "visually the spell slots are kinda boring — they could be made more game
## like and fun to see."
##
## They were right, and a capture is what settles it: above the bar the game draws a
## beam with a white core, a rotating rune circle, a cast portal, bloom and chromatic
## aberration; below it sat SEVEN FLAT BLACK RECTANGLES with 1 px outlines. The bar
## was the only element on screen with no curve, no motion and no depth — it read like
## a debug overlay pasted onto the game.
##
## Four faults, in the order they hurt:
##   1. Seven identical squares. Silhouette carried zero information.
##   2. ~55% of every slot was dead black in the middle. That void IS the boring.
##   3. The accent ring and the tier's corner brackets sat 0-2 px apart, so at real
##      size they read as one candy-striped border rather than a mount holding
##      something.
##   4. Nothing moved. In a game whose signature is rotating summoning circles.
##
## So the socket becomes a small dashed circle that turns — the bar quoting the thing
## the maker likes most in the game (`MagicCircle` / `SpellSigil`). The left cluster
## keeps its squares (body verbs), the right cluster becomes rings (spells), so the
## two-cluster split the maker drew is now carried by SHAPE and not only by the gap.
##
## ⚠ ONE `draw_multiline` FOR THE WHOLE RING, AND THAT CHOICE IS WHAT MAKES IT
## AFFORDABLE. Measured on this machine: 16 dashes as one `draw_multiline` costs
## ~24 us; the same 16 dashes as 16 `draw_arc` calls costs ~298 us — 12x. A naive
## per-dash socket would have been ruinous at seven slots a frame.
##
## Tier is carried by WEIGHT (fewer, fatter dashes = heavier), not by count. A mock
## rendered the other way round first and it read inverted: many fine dashes look
## busy, not strong.
const TIER_DASHES: Array[int] = [12, 8, 5]        # QUICK, HEAVY, ULT
const TIER_DUTY: Array[float] = [0.30, 0.45, 0.55]
const TIER_RING_WIDTH: Array[float] = [1.6, 2.2, 2.8]
## Socket radius, and how far the ULT's second ring sits outside it. 1.18 rather than
## anything larger because past that it pokes outside the 46 px slot box.
const SOCKET_RADIUS: float = 16.0
const ULT_OUTER_R: float = 1.18
const SOCKET_SPIN: float = 0.35                   # rad/s at rest
## How hard a cast kicks the ring outward. The same `pulse` the ready-flash rides.
const SOCKET_PUNCH: float = 0.35
## The glyph sits just OUTSIDE the ring's radius as a fraction, because
## `MagicCircle.draw_motif` keeps every stroke inside its own MOTIF_OUTER (0.62) —
## so 1.16 puts the figure at ~0.72 of the socket, filling the middle that the
## dashed ring leaves empty without touching the ULT's gold ring at 1.18.
const GLYPH_RADIUS: float = SOCKET_RADIUS * 1.16
const GLYPH_WIDTH: float = 1.8


func _draw_socket(rect: Rect2, accent: Color, tier: int, alpha: float,
		frac: float = 0.0, pulse: float = 0.0, glyph: int = MagicCircle.Motif.NONE) -> void:
	var c: Vector2 = rect.get_center()
	var low: bool = TuningConfig.quality_is_low()
	# LOW freezes the spin rather than dropping the ring: the ring is the READ, the
	# motion is the texture. Same ruling MagicCircle already makes for its motif.
	var phase: float = 0.0 if low else float(Time.get_ticks_msec()) * 0.001
	var t: int = clampi(tier, 0, TIER_DASHES.size() - 1)
	# A faint wash so the middle is not a hole, but well under the ring.
	draw_circle(c, SOCKET_RADIUS,
		_with_alpha(Color(accent.r, accent.g, accent.b, SOCKET_WASH_ALPHA), alpha), true, -1.0, not low)
	# THE CAST PUNCH: on the frame the spell fires, the ring kicks out and spins up.
	var r: float = SOCKET_RADIUS * (1.0 + SOCKET_PUNCH * pulse)
	var spin: float = phase * SOCKET_SPIN + pulse * 6.0
	# ⚠ THE COOLDOWN IS THE RING CLOSING, and it replaces BOTH the black bottom-up
	# wipe and the "%.1f" numeral that sat on top of it. Four running timers were the
	# loudest thing on the HUD and they broke the standing no-more-text rule; a circle
	# that visibly COMPLETES as the spell returns says the same thing without a word.
	_ring(c, r, TIER_DASHES[t], TIER_DUTY[t], spin, TAU * (1.0 - clampf(frac, 0.0, 1.0)),
		_with_alpha(accent, alpha), TIER_RING_WIDTH[t], not low)
	if tier == SpellTier.Tier.ULT:
		# The ULT is visibly HUNGRIER: a second ring outside, turning the other way, in
		# the tier's gold. Gold OUTSIDE and the element inside also stops the hue clash
		# the old double rectangle had on a fire ult, where gold sat on orange.
		_ring(c, r * ULT_OUTER_R, 3, 0.5, -phase * 0.5, TAU,
			_with_alpha(SpellTier.color(SpellTier.Tier.ULT), 0.75 * alpha), 2.0, not low)
	# ⚠ DRAWN UNROTATED, WHICH IS THE WHOLE REASON IT IS A SEPARATE TRANSFORM FROM
	# THE RING. LANCE means "that way" and a spinning arrow points everywhere; the
	# world sigil makes exactly the same ruling for exactly the same reason (see the
	# rules block on `MagicCircle.draw_motif`). The ring keeps turning around it.
	#
	# `count_work` is FALSE: `_work_*` are MagicCircle's own statics and the profile
	# reads them to reason about sigil cost. Four HUD sockets redrawing every frame
	# would be counted as sigil work and silently inflate it.
	if glyph != MagicCircle.Motif.NONE:
		var gcol := Color(accent.r * 1.25, accent.g * 1.25, accent.b * 1.25, 0.95 * alpha)
		draw_set_transform(c, 0.0, Vector2.ONE)
		MagicCircle.draw_motif(self, glyph, GLYPH_RADIUS, gcol, GLYPH_WIDTH,
			phase, low, 0.95 * alpha, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One dashed ring as a single `draw_multiline`. `sweep` < TAU draws a partial ring
## from 12 o'clock, which is how the cooldown reads.
func _ring(c: Vector2, r: float, n: int, duty: float, rot: float, sweep: float,
		col: Color, w: float, aa: bool) -> void:
	if sweep <= 0.0 or n <= 0 or r <= 0.0:
		return
	var pts := PackedVector2Array()
	var step: float = TAU / float(n)
	var a: float = 0.0
	while a < sweep:
		var a0: float = -PI * 0.5 + rot + a
		pts.append(c + Vector2.from_angle(a0) * r)
		pts.append(c + Vector2.from_angle(a0 + minf(step * duty, sweep - a)) * r)
		a += step
	if pts.size() >= 2:
		draw_multiline(pts, col, w, aa)


## `charges` < 0 means "not a granted drop" and draws nothing — the pips are a fact
## about a PICKUP, and a count on every class spell would bury the one that runs out.
func _draw_charges(rect: Rect2, charges: int, font: Font, alpha: float) -> void:
	if charges < 0:
		return
	var col: Color = _with_alpha(PIP_COLOR, alpha)
	if charges > PIP_MAX_DOTS:
		draw_string(font, rect.position + Vector2(rect.size.x - 18.0, float(PIP_FONT_SIZE) + 3.0),
			"x%d" % charges, HORIZONTAL_ALIGNMENT_LEFT, -1, PIP_FONT_SIZE, col)
		return
	# Top-RIGHT: the key label owns the top-left and the ability name the bottom edge.
	var y: float = rect.position.y + PIP_INSET.y
	for i: int in charges:
		draw_circle(Vector2(rect.end.x - PIP_INSET.x - float(i) * PIP_GAP, y),
			PIP_RADIUS, col, true, -1.0, true)


## Return `color` with its alpha scaled by `factor` — the one-line dimming
## primitive behind the disabled-slot read.
func _with_alpha(color: Color, factor: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * factor)
