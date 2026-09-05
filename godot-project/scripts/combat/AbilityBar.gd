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
## Clear air between the key label's baseline and the top of the ability name. The
## constant this replaces (`NAME_BOTTOM_PADDING`) had been dead since the name stopped
## hugging the bottom edge — it was the offset of a draw call that no longer existed.
const NAME_KEY_GAP: float = 2.0

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
## THE CLASS'S OWN COLOUR, and the only hue the sockets wear now. Maker: *"the loader is
## enough, in their class colours — minimalistic and clear on what they do"*.
##
## What this replaces is the per-spell ELEMENT accent, which was a deliberate feature: you
## found your fire slot by looking for orange. It cost more than it bought. Four sockets in
## four different hues, each with a tier-weighted ring and a motif, is four things to tell
## apart on a bar you are not looking at; one class colour makes the whole kit read as YOURS
## at a glance and leaves the MOTIF as the thing that distinguishes the spells — which is the
## axis that actually says what a spell does, and the one the socket already draws.
var _class_color: Color = READY_GLOW_COLOR

## SAME-SCREEN CO-OP. Null means "whoever is first in the hero group", which is the
## single-player answer and the shipped behaviour. Set it and this bar belongs to one
## specific climber for as long as that climber is alive.
##
## ⚠ THE SETTER EXISTS BECAUSE A FREED OBJECT COMPARES EQUAL TO null IN GODOT. The
## first version of this tested `bound_hero != null` to decide whether it was bound —
## which is true while the climber lives and quietly goes FALSE the moment they are
## freed, dropping the bar back onto the group lookup and drawing the SURVIVOR's
## cooldowns in the dead player's corner. It looked like it was working, which is the
## one thing a HUD must never do. Caught by
## `slice_test_local_coop.a_bound_bar_whose_climber_died_draws_nothing`; the boolean
## remembers the intent even after the reference rots.
var bound_hero: Node = null:
	set(v):
		bound_hero = v
		_bound = v != null
var _bound: bool = false
## Which corner this bar lives in, and how far up the stack. Player one keeps the left
## corner it has always had.
var dock_right: bool = false
var dock_row: int = 0


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
	# ⚠ AN EXPLICIT HERO WINS; THE GROUP LOOKUP IS STILL THE DEFAULT. This bar was a
	# singleton by construction - it found "the" hero with `get_first_node_in_group`,
	# which is exactly right while there is one, and silently draws player one's
	# cooldowns to BOTH players the moment there are two. `bound_hero` lets same-screen
	# co-op hand each player their own bar; leaving it null is byte-identical to what
	# shipped, which is why solo needed no change and got none.
	#
	# ⚠ A BOUND HERO THAT DIED DRAWS NOTHING, rather than falling back to the group.
	# The fallback would quietly repoint player two's bar at player one and still look
	# like it was working - the worst failure available to a HUD.
	var hero: Node = null
	if _bound:
		hero = bound_hero if is_instance_valid(bound_hero) else null
	else:
		hero = get_tree().get_first_node_in_group("hero")
	if hero == null or not hero.has_method("ability_hud_state"):
		_slots = []
		_class_name = ""
	else:
		_slots = hero.ability_hud_state()
		_class_name = String(hero.call("class_display_name")) if hero.has_method("class_display_name") else ""
		_class_color = _color_for_class(_class_name)
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
## ⚠ PUBLISHED ORDER — 1, 2, 3, 4 — AND THE STRENGTH RAMP IS GONE.
##
## This used to sort by `SpellTier.of` so the bar read weakest-to-heaviest and the ult was
## always the far-right button whatever the class. That is a real property and it was
## argued for at length. It is also wrong, and the maker said so plainly: *"the spells
## should always be in the order of 1 2 3 4"*.
##
## The ramp optimised for a player READING the bar. The keys optimise for a player PRESSING
## it — and the number printed on the square is a promise about which finger throws it. When
## the ramp and the keys disagree, the bar is sorted by something the player cannot see while
## the labels say something else, so slot 2 can sit third and every glance costs a re-read.
## A hotbar's first duty is that the thing under "3" is the thing labelled 3.
func _spell_row() -> Array:
	var first: int = _spell_slot_start()
	if first < 0:
		return []
	var items: Array = []
	for i: int in range(first, _slots.size()):
		if _slots[i] is Dictionary:
			items.append(_slots[i])
	return items


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


## ONE SIZE FOR EVERY LABEL ON THE BAR. Maker: *"the font should always match, it doesn't
## look professional"* — and they were describing something this file did to itself.
##
## `fit_text` shrinks a label until it fits its box, which fixed the clipping it was written
## for and introduced a worse-looking problem: it fits each label INDEPENDENTLY, so "Parry"
## drew at 8 pt beside "Bolt Step" at 6 pt beside "Radiant" at 7 pt. Three type sizes in one
## row of six squares reads as three different UIs, and it is exactly the kind of fault that
## has no single wrong line to point at.
##
## So the fit is computed over the WHOLE ROW and the smallest winner is used everywhere: one
## size, chosen by the longest word on the bar, changing only when the class does.
func _uniform_size(font: Font, rows: Array, key: String, room: float, preferred: int) -> int:
	var size: int = preferred
	for slot: Variant in rows:
		if not slot is Dictionary:
			continue
		var text: String = String((slot as Dictionary).get(key, ""))
		if text.is_empty():
			continue
		size = mini(size, int(fit_text(font, text, room, preferred)[0]))
	return size


## The class's own hue, by name. Falls back to the ready accent when the class is unknown,
## which is the hub/menu case where the bar draws nothing anyway.
func _color_for_class(display: String) -> Color:
	for i: int in ClassInfo.count():
		if ClassInfo.name_for(i) == display:
			return ClassInfo.color_for(i)
	return READY_GLOW_COLOR


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
	# Player two's bar hugs the OTHER corner. Two bars in one corner is one bar you
	# cannot read, and opposite corners also match where the two of you are sitting.
	if dock_right:
		origin_x = view.x - total_w - SIDE_MARGIN
	var origin_y: float = view.y - (BOTTOM_MARGIN * k) - slot_px
	# Players three and four stack UPWARD off their own side rather than landing on
	# top of whoever already has that corner.
	if dock_row > 0:
		origin_y -= float(dock_row) * (slot_px + 8.0 * k)
	# Class name centered just above the hotbar (always know your class).
	if _class_name != "":
		draw_string(
			font, Vector2(origin_x, origin_y - 9.0), _class_name.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, total_w, int(round(13.0 * k)),
			Color(0.95, 0.96, 1.0, 0.95)
		)
	# Sized once, over every row, so the bar speaks in one voice. See `_uniform_size`.
	var name_pt: int = _uniform_size(font, verbs, "name", slot_px, NAME_FONT_SIZE)
	var key_pt: int = _uniform_size(font, verbs + spells, "key",
		slot_px - KEY_PADDING.x, KEY_FONT_SIZE)
	var x: float = origin_x
	for slot: Dictionary in verbs:
		_draw_slot(Rect2(Vector2(x, origin_y), Vector2(slot_px, slot_px)), slot, font,
			name_pt, key_pt)
		x += slot_px + SLOT_GAP * k
	x += split
	for slot: Dictionary in spells:
		_draw_slot(Rect2(Vector2(x, origin_y), Vector2(slot_px, slot_px)), slot, font,
			name_pt, key_pt)
		x += slot_px + SLOT_GAP * k


## Draw one hotbar slot: panel + border + key/name labels, then either the
## cooldown wipe + seconds readout or the ready glow. `enabled == false`
## dims the whole slot and suppresses the glow.
func _draw_slot(rect: Rect2, slot: Dictionary, font: Font,
		name_pt: int = NAME_FONT_SIZE, key_pt: int = KEY_FONT_SIZE) -> void:
	# Defensive reads: the contract is trusted but a missing key shouldn't
	# take the HUD down (same .get()-with-fallback idiom as the save layer).
	var ability_name: String = String(slot.get("name", ""))
	var key_label: String = String(slot.get("key", ""))
	var remaining: float = float(slot.get("remaining", 0.0))
	var total: float = float(slot.get("total", 0.0))
	var enabled: bool = bool(slot.get("enabled", true))
	var alpha: float = 1.0 if enabled else DISABLED_ALPHA
	# `accent` is stamped onto spell slots and only onto spell slots (see
	# `_stamp_spell_identity`), so this one read answers both "does this slot have an
	# element" and "is this slot a disc or a square". One fact, two consequences.
	var is_spell: bool = slot.has("accent")
	var cd_frac: float = clampf(remaining / total, 0.0, 1.0) if (remaining > 0.0 and total > 0.0) else 0.0
	var pulse: float = clampf(float(slot.get("pulse", 0.0)), 0.0, 1.0)
	var c: Vector2 = rect.get_center()
	var disc_r: float = rect.size.x * SOCKET_DISC_FRAC

	# THE SHAPE SPLIT IS FINALLY REAL, AND THAT IS THE WHOLE FIX.
	#
	# The header of this file has claimed for a while that "the left cluster keeps its
	# squares (body verbs), the right cluster becomes rings (spells), so the split the
	# maker drew is carried by SHAPE and not only by the gap". It was not true. What
	# shipped was a square panel, a square border, a square ready-glow, a square
	# selection frame and a square ready-flash, with a circle drawn INSIDE all of that
	# and (measured, see the SOCKET_*_FRAC block) a circle 3.5 px WIDER than the square
	# containing it. The dominant silhouette stayed square, the circle burst out of it
	# into the neighbouring slot, and the maker read the result exactly as it was:
	# "the spell slots like a box over a circle is so random".
	#
	# So the square goes. On a spell slot every mark that describes the SLOT is now
	# drawn as a circle -- panel, border, ready glow, selection, ready flash -- and the
	# socket has the whole cell to live in. The verb slots are untouched squares. Two
	# shapes, two meanings, and neither one drawn on top of the other.
	#
	# THE KEY LABEL STAYS IN THE CELL'S TOP-LEFT CORNER ON BOTH SHAPES, which does put
	# it outside the disc, and that is the one place shape purity deliberately loses.
	# All six key labels sitting on one baseline is what lets a player find "which
	# finger" by position without reading; moving the spell keys onto the disc would
	# buy a tidier circle and cost the only alignment on the bar the eye actually uses.
	# It gets an outline instead, since it no longer has a dark panel behind it.
	if is_spell:
		draw_circle(c, disc_r, _with_alpha(PANEL_COLOR, alpha), true, -1.0, true)
		# THE CLASS COLOUR, not the spell's element — see `_class_color`. An EMPTY socket
		# keeps its neutral steel, because "there is nothing here" is not a class fact.
		var socket_col: Color = _class_color if slot.get("accent", null) != null else EMPTY_SOCKET_COLOR
		_draw_socket(rect, socket_col,
			int(slot.get("tier", SpellTier.Tier.QUICK)), alpha, cd_frac, pulse,
			int(slot.get("glyph", MagicCircle.Motif.NONE)))
		draw_arc(c, disc_r, 0.0, TAU, DISC_SEGMENTS,
			_with_alpha(BORDER_COLOR, alpha), BORDER_WIDTH, true)
	else:
		draw_rect(rect, _with_alpha(PANEL_COLOR, alpha))
		draw_rect(rect, _with_alpha(BORDER_COLOR, alpha), false, BORDER_WIDTH)

	# ⚠ THE SPELL DISCS NO LONGER DRAW THIS RING, and the maker is the one who spotted
	# that it had stopped meaning anything. *"why does 1 have an order circle around it
	# and not the others if anything the ult should have that circle"*.
	#
	# It marked `_signature_index` — "the slot the cast key throws right now" — from
	# when there was ONE cast key and you cycled which spell it threw. Every slot has
	# had its own action and its own key for a while (`Hero.SPELL_ACTIONS`, and that
	# file's own comment says there is no longer "the one you can cast" and "the ones
	# you have to cycle to"). What was left was a gold ring parked on slot 1, because
	# `_signature_index` starts at 0 and slot 1 is the damage line you throw all fight,
	# so it almost never moved. A permanent decoration on one arbitrary slot.
	#
	# The ULT's crown ring in `_draw_socket` is the circle that means something, it is
	# already tier-derived, and it is already on `SpellTier.ULT_SLOT` for all nine
	# classes. Removing this one leaves exactly one ring on the bar and it is on the ult.
	#
	# The VERB squares keep it: nothing sets `selected` on them today, so this is a
	# no-op there rather than a second ruling.
	if bool(slot.get("selected", false)) and not is_spell:
		draw_rect(rect.grow(SELECTED_GROW), _with_alpha(SELECTED_COLOR, alpha),
			false, SELECTED_WIDTH)

	# Key label: top-left, small + bright -- the "which finger" read. Fitted, so a
	# three-character key ("RMB", "Spc") cannot be clipped by a future scale change
	# the way the ability names silently were.
	var key_room: float = rect.size.x - KEY_PADDING.x
	var key_fit: Array = fit_text(font, key_label, key_room, key_pt)
	var key_size: int = int(key_fit[0])
	var key_pos: Vector2 = rect.position + Vector2(KEY_PADDING.x, KEY_PADDING.y + float(key_size))
	if is_spell:
		# No dark panel under this corner any more, so the glyph and the arena show
		# through behind it. Two pixels of outline buy the contrast back.
		draw_string_outline(font, key_pos, String(key_fit[1]), HORIZONTAL_ALIGNMENT_LEFT,
			-1, key_size, 2, _with_alpha(Color(0.03, 0.03, 0.05, 0.9), alpha))
	draw_string(font, key_pos, String(key_fit[1]), HORIZONTAL_ALIGNMENT_LEFT, -1,
		key_size, _with_alpha(KEY_TEXT_COLOR, alpha))

	# Ability name: bottom, tiny + dim -- identification, not the focal point.
	#
	# SPELL SLOTS NO LONGER CARRY IT. At true phone pixels these were barely legible
	# grey-on-black AND the socket ring crossed them, so 8 px of every slot was spent
	# on something unreadable under pressure. The verb slots keep theirs (they name a
	# class verb you cannot infer from a shape); the spell sockets are told apart by
	# colour, ring weight, motif and the ult's crown. A text REDUCTION, per the
	# standing rule.
	if not is_spell:
		# ⚠ CENTRED IN THE SQUARE, not hugging its bottom edge. Maker: *"the air dash and
		# stuff should be centred in its little square"*. It sat on the baseline because the
		# slot used to carry a cooldown numeral in the middle; the numeral is fitted and
		# small now, so the middle is where the word belongs — and a word pinned to the floor
		# of a box reads as a caption under the box rather than as its label.
		# See `fit_verb_name`: sized and seated in the room BELOW the key, not centred in
		# the whole box on top of it. `key_size` and not `key_pt` — the key may have been
		# shrunk to fit its own width, and reserving room for a size that was not drawn
		# would rob the name on exactly the classes with the longest key labels.
		var name_fit: Array = fit_verb_name(font, ability_name, rect.size, key_size, name_pt)
		draw_string(
			font,
			Vector2(rect.position.x, rect.position.y + float(name_fit[2])),
			String(name_fit[1]),
			HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), int(name_fit[0]),
			_with_alpha(NAME_TEXT_COLOR, alpha)
		)

	var on_cooldown: bool = remaining > 0.0 and total > 0.0
	# A SPELL SOCKET SHOWS ITS COOLDOWN AS ITS RING CLOSING (see `_draw_socket`), so it
	# gets neither the black wipe nor the numeral on top of it. Only the VERB slots
	# keep them: they are squares with no ring to close, and theirs are the cooldowns
	# you actually weave against. Four running "%.1f" timers were the loudest thing on
	# the whole HUD and they broke the standing no-more-text rule.
	if on_cooldown and not is_spell:
		# Bottom-up wipe: overlay height shrinks with remaining/total, so the
		# slot visibly "fills back up" as it cools -- legible at a glance.
		var wipe_h: float = rect.size.y * cd_frac
		var wipe: Rect2 = Rect2(
			Vector2(rect.position.x, rect.end.y - wipe_h),
			Vector2(rect.size.x, wipe_h)
		)
		draw_rect(wipe, _with_alpha(COOLDOWN_OVERLAY_COLOR, alpha))
		# Seconds left, 1 decimal, centered -- precise timing for ability weaving.
		# Fitted: "10.5" is 30 px of a 28.5 px slot, so every cooldown of ten seconds
		# or more was losing its last digit, which on a timer is worse than useless.
		var secs_fit: Array = fit_text(font, "%.1f" % remaining, rect.size.x,
			mini(TIMER_FONT_SIZE, maxi(name_pt + 4, FIT_FLOOR_SIZE)))
		draw_string(
			font,
			Vector2(rect.position.x, rect.get_center().y + float(int(secs_fit[0])) * 0.35),
			String(secs_fit[1]),
			HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), int(secs_fit[0]),
			_with_alpha(TIMER_TEXT_COLOR, alpha)
		)
	elif not on_cooldown and enabled and not is_spell:
		# Ready: a brighter accent border so the eye reads "usable" without the slot
		# shouting. Disabled slots never glow.
		#
		# ⚠ SPELL SLOTS NO LONGER GET ONE. Maker: *"for all of them remove that little blue
		# circle around them — the loader is enough"*. And it is: a spell socket already
		# shows readiness as its RING BEING WHOLE, because the cooldown is drawn as that ring
		# closing. So the cyan disc was a second, redundant answer to a question the socket
		# had already answered — in a hue that belongs to no class, on the one part of the
		# bar the player chose. The verb squares keep theirs; they have no ring to complete.
		draw_rect(rect, READY_GLOW_COLOR, false, READY_GLOW_WIDTH)
	# The flash rides OVER the cooldown branch rather than inside the `elif`: a slot
	# that recovers and is re-cast within READY_PULSE_TIME is back on cooldown when
	# this runs, and swallowing its flash would silence exactly the fastest, most
	# satisfying rotation the player can pull off.
	if pulse > 0.0 and enabled:
		var flash: Color = Color(READY_FLASH_COLOR.r, READY_FLASH_COLOR.g,
			READY_FLASH_COLOR.b, pulse)
		var grow: float = READY_FLASH_GROW * (1.0 - pulse)
		if is_spell:
			draw_arc(c, disc_r + grow, 0.0, TAU, DISC_SEGMENTS, flash,
				READY_FLASH_WIDTH, true)
		else:
			draw_rect(rect.grow(grow), flash, false, READY_FLASH_WIDTH)
	# LAST, over everything: the count has to survive the cooldown wipe. "Two left"
	# is exactly the fact you need while the slot is recovering and you are deciding
	# whether to spend the next one here or save it for the guardian.
	_draw_charges(rect, int(slot.get("charges", -1)), font, alpha, is_spell)


## THE LARGEST SIZE THAT FITS, AND THE STRING TO DRAW AT IT. Returns `[size, text]`.
##
## `draw_string`'s `width` argument does not shrink and does not wrap -- it CLIPS,
## mid-glyph, with no ellipsis and no error. So a label that outgrows its box fails
## silently and looks, from the code, exactly like one that fits. This is the
## measurement that closes that gap, and it runs at draw time against the real font
## rather than against a table of hand-checked strings, so a movement verb somebody
## names next month is covered without anyone remembering to re-check it.
##
## Static and pure, so the guard suite can ask it about every label the bar can hold
## without building a HUD.
static func fit_text(font: Font, text: String, max_w: float, preferred: int) -> Array:
	if text.is_empty() or max_w <= 0.0:
		return [preferred, text]
	var size: int = preferred
	while size > FIT_FLOOR_SIZE:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			return [size, text]
		size -= 1
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return [size, text]
	# At the floor and still too wide. Truncate rather than clip: an ellipsis says
	# "there is more of this word" where a clipped glyph says nothing at all. No label
	# the bar can currently hold reaches this branch -- the widest, "Bolt Step", fits
	# at the floor with room to spare -- so it exists for the day one does, to degrade
	# legibly instead of silently.
	var cut: String = text
	while cut.length() > 1:
		cut = cut.substr(0, cut.length() - 1)
		if font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			return [size, cut + "…"]
	return [size, cut]


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
## ══ EVERY SOCKET RADIUS IS A FRACTION OF THE SLOT, AND THAT IS THE BUG FIX ═════
## Maker: *"the spell slots like a box over a circle is so random"*. Measured, that
## sentence is a literal description of the geometry, not a complaint about taste:
##
##     slot          28.52 px   (SLOT_SIZE 46 x DESKTOP_SCALE 0.62)
##     socket ring   32.00 px   OVERFLOWS +3.48
##     ult crown     37.76 px   OVERFLOWS +9.24
##     ring at punch 43.20 px   OVERFLOWS +14.68
##     slot pitch    32.24 px   -- so adjacent sockets TOUCH, and an ult's crown
##                                 crosses 5.5 px into its neighbour's square.
##
## The socket was authored against the 46 px thumb slot, where 32 px sits inside 46
## with a 7 px margin and everything is fine. `DESKTOP_SCALE` arrived later, scaled
## the RECT, and left these constants absolute. Nobody re-measured, because on a
## touch build (k = 1.0) it still looked exactly as designed.
##
## So they are fractions now, and the slot is the only length in the file. Correct at
## both scales BY CONSTRUCTION rather than by anyone remembering to check the other
## one — which is the property the absolute version lacked, and the reason it broke.
## `tools/probe_hotbar_fit.gd` prints the arithmetic; `slice_test_hotbar_fit` pins it.
##
## The numbers are chosen so the OUTERMOST mark still clears half the slot pitch:
##     ring at punch  0.40 x 1.28 = 0.512 of the slot   (+ half the 2.8 px ring width)
##     ult crown      0.40 x 1.18 = 0.472 of the slot
##     half pitch     (46 + 6) / 2 / 46 = 0.565 of the slot
## i.e. nothing a socket draws at rest or on a cast can reach its neighbour.
## The disc that BACKS the socket is the full half-slot: the socket fills its cell.
const SOCKET_DISC_FRAC: float = 0.50
const SOCKET_RING_FRAC: float = 0.40
const ULT_OUTER_R: float = 1.18
const SOCKET_SPIN: float = 0.35                   # rad/s at rest
## How hard a cast kicks the ring outward. The same `pulse` the ready-flash rides.
##
## ⚠ APPLIED TO THE ELEMENT RING ONLY, NOT TO THE ULT'S CROWN. Inflating both made
## the whole socket breathe, which at 0.35 pushed the crown past the neighbour and
## also read as the slot wobbling rather than as the spell firing. A stable outer
## crown with a kicking inner ring says the same thing and stays inside its cell.
const SOCKET_PUNCH: float = 0.28
## How many segments a socket circle is drawn with. 28 is where the rim stops reading
## as a polygon at the 46 px touch size; below that the ult's crown visibly facets.
const DISC_SEGMENTS: int = 28
## The glyph sits just OUTSIDE the ring's radius as a fraction, because
## `MagicCircle.draw_motif` keeps every stroke inside its own MOTIF_OUTER (0.62) —
## so 1.16 puts the figure at ~0.72 of the socket, filling the middle that the
## dashed ring leaves empty without touching the ULT's gold ring at 1.18.
const GLYPH_R_OVER_RING: float = 1.16
const GLYPH_WIDTH: float = 1.8

## ── TEXT THAT CANNOT SPILL OUT OF ITS BOX ────────────────────────────────────
## Maker, in the same breath as the circle: *"the wording doesnt fit within some
## boxes"*. Measured across all nine classes at the desktop scale, three verb labels
## are clipped mid-word by `draw_string`'s width argument, and a cooldown numeral
## joins them the moment it reaches double digits:
##
##     "Bolt Step"  (Stormcaller)  35.00 px into 28.52   CLIPPED +6.48
##     "Air Dash"   (Shadowblade)  33.00 px into 28.52   CLIPPED +4.48
##     "Radiant"    (Cleric)       30.00 px into 28.52   CLIPPED +1.48
##     "10.5"       (any 10s+ cd)  30.00 px into 28.52   CLIPPED +1.48
##
## ⚠ THE CAUSE IS THE SAME ONE AS THE CIRCLE, AND FIXING IT THE OBVIOUS WAY WOULD
## HAVE MADE IT WORSE. The slot shrank by `DESKTOP_SCALE` and the font sizes did not,
## so the reflex is to multiply every font by `k` too. That drops the name to 5 px and
## the key to 6 px on a 640x360 canvas and trades three clipped words for six
## illegible ones. Shrinking is only correct WHERE IT IS NEEDED and only AS FAR as it
## is needed, which is a measurement, not a constant.
##
## So the labels are fitted: the largest size at or below the preferred one whose
## MEASURED width fits the box, floored so it can never become unreadable, and
## ellipsised on the (currently unreachable) case where even the floor overflows.
## Generality is the point — this holds for the next movement verb somebody names,
## which is exactly the kind of thing a hand-shortened string table forgets.
const FIT_FLOOR_SIZE: int = 6


func _draw_socket(rect: Rect2, accent: Color, tier: int, alpha: float,
		frac: float = 0.0, pulse: float = 0.0, glyph: int = MagicCircle.Motif.NONE) -> void:
	var c: Vector2 = rect.get_center()
	var low: bool = TuningConfig.quality_is_low()
	# LOW freezes the spin rather than dropping the ring: the ring is the READ, the
	# motion is the texture. Same ruling MagicCircle already makes for its motif.
	var phase: float = 0.0 if low else float(Time.get_ticks_msec()) * 0.001
	var t: int = clampi(tier, 0, TIER_DASHES.size() - 1)
	# EVERY LENGTH IN THIS FUNCTION COMES OFF THE RECT. See the SOCKET_*_FRAC block:
	# the previous version measured in absolute pixels authored against the 46 px thumb
	# slot, so on desktop (0.62x) the ring was wider than the square it sat in.
	var disc_r: float = rect.size.x * SOCKET_DISC_FRAC
	var ring_r: float = rect.size.x * SOCKET_RING_FRAC
	# ...and so does the LINE WEIGHT. A 2.8 px ring on a 46 px slot and the same 2.8 px
	# on a 28.5 px slot are not the same drawing: the second is half again as heavy
	# relative to what it encircles, which is why the desktop bar read as clotted even
	# where it did fit. One ratio, applied to every stroke the socket makes.
	var w: float = rect.size.x / SLOT_SIZE
	# A faint wash across the whole disc interior so the socket reads as a filled
	# object rather than as a ring floating on the arena. Well under the ring: this is
	# a tint on the panel, not a second background competing with the cooldown veil.
	draw_circle(c, disc_r - BORDER_WIDTH,
		_with_alpha(Color(accent.r, accent.g, accent.b, SOCKET_WASH_ALPHA), alpha),
		true, -1.0, not low)
	# THE CAST PUNCH: on the frame the spell fires, the ring kicks out and spins up.
	var r: float = ring_r * (1.0 + SOCKET_PUNCH * pulse)
	var spin: float = phase * SOCKET_SPIN + pulse * 6.0
	# THE COOLDOWN IS THE RING CLOSING, and it replaces BOTH the black bottom-up wipe
	# and the "%.1f" numeral that sat on top of it. Four running timers were the
	# loudest thing on the HUD and they broke the standing no-more-text rule; a circle
	# that visibly COMPLETES as the spell returns says the same thing without a word.
	_ring(c, r, TIER_DASHES[t], TIER_DUTY[t], spin, TAU * (1.0 - clampf(frac, 0.0, 1.0)),
		_with_alpha(accent, alpha), TIER_RING_WIDTH[t] * w, not low)
	if tier == SpellTier.Tier.ULT:
		# The ULT is visibly HUNGRIER: a second ring outside, turning the other way, in
		# the tier's gold. Gold OUTSIDE and the element inside also stops the hue clash
		# the old double rectangle had on a fire ult, where gold sat on orange.
		#
		# DRAWN AT THE RESTING RADIUS, NOT THE PUNCHED ONE. Riding the punch made the
		# crown the outermost thing on the bar at exactly the moment it was largest,
		# which is how it ended up 5.5 px inside its neighbour's slot. A crown that
		# holds still while the element ring kicks under it also reads better: the
		# stable frame is what makes the kick legible as movement.
		#
		# ⚠ AND IT CLOSES AS THE ULT COMES BACK. Maker: *"the yellow circle also needs to
		# move around as the ults recharge"*. It drew a FULL ring at every moment of the
		# cooldown, so the one mark the eye goes to on the bar said the same thing whether
		# the ult was a second away or twenty. The element ring under it has read its
		# cooldown as a closing sweep since it replaced the numeral; the crown simply
		# never got the same treatment, and it is the ring people actually watch.
		# Same expression, same 12-o'clock start, so the two close together and arrive
		# together — and a ready ult is the only state where the crown is a whole circle.
		_ring(c, ring_r * ULT_OUTER_R, 3, 0.5, -phase * 0.5,
			TAU * (1.0 - clampf(frac, 0.0, 1.0)),
			_with_alpha(SpellTier.color(SpellTier.Tier.ULT), 0.75 * alpha), 2.0 * w, not low)
	# DRAWN UNROTATED, WHICH IS THE WHOLE REASON IT IS A SEPARATE TRANSFORM FROM THE
	# RING. LANCE means "that way" and a spinning arrow points everywhere; the world
	# sigil makes exactly the same ruling for exactly the same reason (see the rules
	# block on `MagicCircle.draw_motif`). The ring keeps turning around it.
	#
	# `count_work` is FALSE: `_work_*` are MagicCircle's own statics and the profile
	# reads them to reason about sigil cost. Four HUD sockets redrawing every frame
	# would be counted as sigil work and silently inflate it.
	if glyph != MagicCircle.Motif.NONE:
		var gcol := Color(accent.r * 1.25, accent.g * 1.25, accent.b * 1.25, 0.95 * alpha)
		draw_set_transform(c, 0.0, Vector2.ONE)
		MagicCircle.draw_motif(self, glyph, ring_r * GLYPH_R_OVER_RING, gcol,
			GLYPH_WIDTH * w, phase, low, 0.95 * alpha, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## ══ WHERE THE TWO STRINGS IN A VERB SQUARE SIT ═════════════════════════
## Maker, twice: *"the rmb and spc buttons and what they do in the corner the text is
## blocking each other its not very aestetic"*, then *"the Guard and LUNGE BUTTONS IN
## THE BOTTOM LEFT CORNER OF THE SCREEN ARE OVERWRITTEN BY THE RMB AND SPC TEXT"*.
##
## Both strings are drawn inside ONE square, and the square is 28.5 px on desktop —
## `SLOT_SIZE` 46 times `DESKTOP_SCALE` 0.62, not the 46 px thumb target the constant
## is written for. The name used to sit on the square's bottom edge, as far from the
## top-left key as the box allows. It was moved to the square's CENTRE to answer a
## different maker note (*"the air dash and stuff should be centred in its little
## square"*), and at 28.5 px the centre is only a few pixels below the key's own
## baseline, so the two glyph bands landed on top of each other. On a 46 px touch
## slot the same maths has ~13 px more room and does not collide — which is why it
## survived a review and failed on the maker's screen.
##
## The name is still centred; it is centred in THE ROOM THAT IS LEFT rather than in
## the whole box. That keeps the answer to both notes: it is not pinned to the floor
## like a caption, and it is not sitting under the key.
##
## Static and pure so a test can assert the clearance without standing a HUD up — no
## probe in the tree measured the gap between two drawn strings, only whether each
## string fitted its own box's WIDTH, which is why nothing caught this.
static func key_baseline_y(key_pt: int) -> float:
	return KEY_PADDING.y + float(key_pt)


## The ability name, fitted to the room LEFT OVER under the key label — in BOTH axes.
## Returns `[size, text, baseline_y]`, with the baseline measured from the square's
## own top edge.
##
## ⚠ THE KEY'S DESCENT IS PART OF THE KEY. The first attempt at this reserved
## `key_baseline + gap` and still overlapped by 0.4 px on all nine classes, because a
## baseline is not the bottom of a glyph — 'p' and 'y' hang about 3 px below it at
## 10 pt. Caught by the test below, which measures the drawn bands rather than the
## point sizes; the point sizes had looked fine.
##
## ⚠ AND HEIGHT IS FITTED, NOT ASSUMED. `fit_text` has only ever asked whether a
## string fits its box's WIDTH, which is why every existing check was green about a
## bar the maker could not read. A 28.5 px desktop square cannot hold a 10 pt key and
## an 8 pt name stacked, so the name gives up a point rather than the two of them
## sharing a row of pixels.
static func fit_verb_name(font: Font, text: String, rect_size: Vector2,
		key_pt: int, base_pt: int = NAME_FONT_SIZE) -> Array:
	var top: float = key_baseline_y(key_pt) + font.get_descent(key_pt) + NAME_KEY_GAP
	var room: float = maxf(rect_size.y - top, 1.0)
	var fit: Array = fit_text(font, text, rect_size.x, base_pt)
	var pt: int = int(fit[0])
	while pt > FIT_FLOOR_SIZE and font.get_ascent(pt) + font.get_descent(pt) > room:
		pt -= 1
		fit = fit_text(font, text, rect_size.x, pt)
		pt = int(fit[0])
	var band: float = font.get_ascent(pt) + font.get_descent(pt)
	# Centred on the GLYPH BAND inside the leftover room, so a word with no descenders
	# does not sit visibly high in its own gap.
	return [pt, fit[1], top + maxf(room - band, 0.0) * 0.5 + font.get_ascent(pt)]


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
func _draw_charges(rect: Rect2, charges: int, font: Font, alpha: float,
		is_spell: bool = false) -> void:
	if charges < 0:
		return
	var col: Color = _with_alpha(PIP_COLOR, alpha)
	var w: float = rect.size.x / SLOT_SIZE
	if charges > PIP_MAX_DOTS:
		var over_fit: Array = fit_text(font, "x%d" % charges, rect.size.x * 0.5, PIP_FONT_SIZE)
		draw_string(font, rect.position + Vector2(rect.size.x * 0.55, float(int(over_fit[0])) + 3.0 * w),
			String(over_fit[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(over_fit[0]), col)
		return
	# A SQUARE PUTS THEM IN THE TOP-RIGHT CORNER; A DISC HAS NO CORNER. On the verb
	# squares the key label owns the top-left and the ability name the bottom edge, so
	# the top-right is the free one. On a spell disc that same point is OUTSIDE the
	# circle, and pips floating off the edge of the socket read as a rendering fault
	# rather than as a count. So the disc takes them as a centred row along the bottom
	# of its interior, which is empty (the motif sits in the middle, the ring at the
	# rim) and which is where a "how many are left" row belongs anyway.
	var gap: float = PIP_GAP * w
	var radius: float = PIP_RADIUS * w
	if is_spell:
		var c: Vector2 = rect.get_center()
		var row_y: float = c.y + rect.size.x * SOCKET_RING_FRAC * 0.72
		var row_w: float = float(charges - 1) * gap
		for i: int in charges:
			draw_circle(Vector2(c.x - row_w * 0.5 + float(i) * gap, row_y),
				radius, col, true, -1.0, true)
		return
	var y: float = rect.position.y + PIP_INSET.y * w
	for i: int in charges:
		draw_circle(Vector2(rect.end.x - PIP_INSET.x * w - float(i) * gap, y),
			radius, col, true, -1.0, true)


## Return `color` with its alpha scaled by `factor` — the one-line dimming
## primitive behind the disabled-slot read.
func _with_alpha(color: Color, factor: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * factor)
