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

## Snapshot of the hero's slot dictionaries, refreshed once per frame in
## _process and consumed by _draw. Empty = draw nothing (no hero this scene).
var _slots: Array = []


func _ready() -> void:
	# Full-rect anchors so our size tracks the viewport; all layout is
	# recomputed in _draw from the live viewport size (no hardcoded res).
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Pure HUD readout — never eat clicks meant for the game underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	# Poll-don't-push: cooldown timers tick every frame anyway, so a per-frame
	# read of the hero contract is simpler than plumbing signals for 6 slots.
	var hero: Node = get_tree().get_first_node_in_group("hero")
	if hero == null or not hero.has_method("ability_hud_state"):
		_slots = []
	else:
		_slots = hero.ability_hud_state()
	queue_redraw()


func _draw() -> void:
	if _slots.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var view: Vector2 = get_viewport_rect().size
	var count: int = _slots.size()
	var total_w: float = float(count) * SLOT_SIZE + float(count - 1) * SLOT_GAP
	var origin_x: float = (view.x - total_w) * 0.5
	var origin_y: float = view.y - BOTTOM_MARGIN - SLOT_SIZE
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


## Return `color` with its alpha scaled by `factor` — the one-line dimming
## primitive behind the disabled-slot read.
func _with_alpha(color: Color, factor: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * factor)
