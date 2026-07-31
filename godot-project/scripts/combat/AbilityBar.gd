class_name AbilityBar
extends Control
## MMO-style ability/cooldown hotbar HUD, drawn entirely in code (no scene).
## Lives under a CanvasLayer so it renders in screen space — the world camera
## zoom never touches it. Each frame it polls the hero's `ability_hud_state()`
## contract and redraws: slot panels, key labels, cooldown wipes + timers, a
## ready-glow, and a dimmed read for class-disabled abilities. If no hero is
## in the tree (hub/menu scenes reuse this HUD), it simply draws nothing.

## -- Layout -------------------------------------------------------------
## Slot geometry: sized for a thumb-friendly read at 46px (D-011 mobile-first)
## with a gap wide enough that the wipe on one slot never bleeds into the next.
const SLOT_SIZE: float = 46.0
const SLOT_GAP: float = 6.0
## Breathing room below the bar so it doesn't kiss the screen edge.
const BOTTOM_MARGIN: float = 14.0
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
## Not a preference — the two collide. This bar is nine slots centred across the bottom
## of the screen; the pad's spell arc and DASH sit in the bottom-right corner, and at
## 640x360 base their rectangles physically overlap (measured in a capture, not
## reasoned about). Worse, most of what the bar draws — Q, R, T, LMB — names verbs a
## thumb cannot reach at all under the three-button scheme, so the overlap was buying
## the phone player a cooldown readout for buttons they do not have.
##
## The pad carries its own veils and ready-flashes on every button it DOES show, from
## the same `Hero` publishers this bar reads, so nothing is lost on that platform.
##
## Gated on a live pad rather than on `DisplayServer.is_touchscreen_available()`,
## because a touchscreen laptop played with a keyboard must keep its hotbar — and
## `TouchControls` only joins the group when it has actually shown itself.
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
	queue_redraw()


## Fold each signature slot's remaining charges into the slot dictionary, so
## `_draw_slot` stays a pure function of one dictionary and never has to reach back
## for a hero it was not handed.
##
## The signature slots are the LAST `SpellTier.SLOT_COUNT` entries of
## `ability_hud_state()` (it is a fixed prefix of six ability rows plus the
## signatures — see Hero.ability_hud_state). Keyed off the END of the array rather
## than off absolute indices so adding an ability row above cannot silently start
## stamping charges onto Dash.
func _stamp_charges(hero: Node) -> void:
	var first: int = _slots.size() - SpellTier.SLOT_COUNT
	if first < 0:
		return
	for i: int in SpellTier.SLOT_COUNT:
		if not _slots[first + i] is Dictionary:
			continue
		(_slots[first + i] as Dictionary)["charges"] = SpellGrant.charges_in_slot(hero, i)


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
## ⚠ TARGETED BY `selected`, NOT BY THE KEY LABEL "G". The bar now draws three spell
## slots rather than one cycled one, and the key label is a fact about the BINDINGS
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


func _draw() -> void:
	if _slots.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var view: Vector2 = get_viewport_rect().size
	var count: int = _slots.size()
	var total_w: float = float(count) * SLOT_SIZE + float(count - 1) * SLOT_GAP
	var origin_x: float = (view.x - total_w) * 0.5
	var origin_y: float = view.y - BOTTOM_MARGIN - SLOT_SIZE
	# Class name centered just above the hotbar (always know your class).
	if _class_name != "":
		draw_string(
			font, Vector2(origin_x, origin_y - 9.0), _class_name.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, total_w, 13, Color(0.95, 0.96, 1.0, 0.95)
		)
	for i: int in range(count):
		if not _slots[i] is Dictionary:
			continue  # malformed entry — skip rather than crash the HUD
		var rect: Rect2 = Rect2(
			Vector2(origin_x + float(i) * (SLOT_SIZE + SLOT_GAP), origin_y),
			Vector2(SLOT_SIZE, SLOT_SIZE)
		)
		_draw_slot(rect, _slots[i], font)


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
	draw_rect(rect, _with_alpha(BORDER_COLOR, alpha), false, BORDER_WIDTH)
	# The three spell slots are all live and all show their own cooldown, so the bar
	# also has to say WHICH one the cast key throws right now. A lifted outer frame
	# rather than a colour change: movement reads faster than hue when your eyes are on
	# the fight (the same reasoning as LoadoutBar's SELECTED_LIFT), and it survives the
	# cooldown wipe drawn on top of the slot below.
	if bool(slot.get("selected", false)):
		draw_rect(rect.grow(SELECTED_GROW), _with_alpha(SELECTED_COLOR, alpha),
			false, SELECTED_WIDTH)

	# Key label: top-left, small + bright — the "which finger" read.
	draw_string(
		font,
		rect.position + Vector2(KEY_PADDING.x, KEY_PADDING.y + float(KEY_FONT_SIZE)),
		key_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT_SIZE,
		_with_alpha(KEY_TEXT_COLOR, alpha)
	)
	# Ability name: bottom, tiny + dim — identification, not the focal point.
	draw_string(
		font,
		Vector2(rect.position.x, rect.end.y - NAME_BOTTOM_PADDING),
		ability_name,
		HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), NAME_FONT_SIZE,
		_with_alpha(NAME_TEXT_COLOR, alpha)
	)

	var on_cooldown: bool = remaining > 0.0 and total > 0.0
	if on_cooldown:
		# Bottom-up wipe: overlay height shrinks with remaining/total, so the
		# slot visibly "fills back up" as it cools — legible at a glance.
		var frac: float = clampf(remaining / total, 0.0, 1.0)
		var wipe_h: float = rect.size.y * frac
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
	elif enabled:
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
