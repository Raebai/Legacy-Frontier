class_name LoadoutBar
extends Control
## The slot bar along the bottom — what you are holding, at a glance.
##
## Renders a HandSlots model as a short row of squares: fists, your weapon, and
## up to four spells. Small, centred, bottom-anchored, and tappable, so the same
## control works with a mouse click, a number key, or a thumb.
##
## NO ART DEPENDENCY. Icons are drawn procedurally from the spell's KIND and
## element colour, so the bar is complete the moment a spell exists and never
## waits on an artist — and because the glyph comes from the kind, two spells that
## behave alike look alike, which is a useful signal rather than a limitation.
##
## DIRECT SELECTION, not scroll-only. With a cap of four spells the whole bar is
## reachable in one tap, and cycling would be O(n) under pressure — the reason
## League gives fixed keys rather than a wheel. Scrolling still works as a
## convenience, it just isn't the only way in.

signal slot_selected(index: int)

const SLOT: float = 34.0          # square edge, in the 640x360 base space
const GAP: float = 6.0
const BOTTOM_MARGIN: float = 10.0
const CORNER: float = 5.0
const BG: Color = Color(0.09, 0.10, 0.14, 0.82)
const BORDER: Color = Color(0.42, 0.45, 0.55, 0.9)
const BORDER_SELECTED: Color = Color(1.0, 0.94, 0.72, 1.0)
const COOLDOWN_VEIL: Color = Color(0.03, 0.04, 0.07, 0.72)
const FISTS_TINT: Color = Color(0.85, 0.86, 0.92)
const WEAPON_TINT: Color = Color(0.78, 0.82, 0.95)
## The selected slot lifts slightly. Movement reads faster than a colour change
## when your eyes are on the fight rather than the bar.
const SELECTED_LIFT: float = 3.0
## READY-FLASH — the "you can act NOW" beat, thrown once as a slot comes back.
## Matches `AbilityBar`'s so the two bars read as one system.
const READY_FLASH_COLOR: Color = Color(0.6, 0.95, 1.0)
const READY_FLASH_TIME: float = 0.38
const READY_FLASH_GROW: float = 7.0
## Key hint drawn on the spell slots. The Nth spell in the carousel is `spell_N`, so
## the bar can name the button that reaches it instead of leaving the player to guess.
const KEY_FONT_SIZE: int = 9
const KEY_TEXT_COLOR: Color = Color(0.95, 0.96, 1.0, 0.9)

## ── TIER 3 CHARGE PIPS ───────────────────────────────────────────────────────
## A picked-up spell has a COUNT, and the spec's "picking one up is a decision"
## only holds if you can see that count BEFORE you spend it. Without this, a Tier 3
## with one use left is indistinguishable from one with two — you commit your last
## charge on a trash mob and discover the cost afterwards, which turns a decision
## into a surprise.
##
## Drawn as PIPS, not a number, because the counts are tiny (1–2) and a row of dots
## is read at a glance without focusing — the same reason ammo counters in shooters
## go to pips at low magazine sizes. Above 4 it degrades to `xN` rather than a row
## of dots nobody can count under pressure.
##
## GOLD on purpose: `SpellPickup.TIER3_GOLD` is the colour the thing was wearing on
## the floor, so the pips say "the spell you found" and not "a new cooldown".
const PIP_COLOR: Color = Color(1.0, 0.86, 0.42, 0.95)
const PIP_RADIUS: float = 2.1
const PIP_GAP: float = 5.4
const PIP_INSET: Vector2 = Vector2(4.0, 4.5)
const PIP_MAX_DOTS: int = 4
const PIP_FONT_SIZE: int = 9

var slots: HandSlots = null
## The hero whose GRANTS this bar reports. Optional: the spike playground hands this
## bar a `HandSlots` with no hero behind it at all, and a bar with no hero simply
## draws no pips rather than guessing.
##
## Resolved by MATCHING THE HAND, never by taking the first hero in the group — in
## co-op there are two heroes and the wrong one's charges would be a confident lie.
var hero: Node = null
## Per-slot flash timers + the ready-edge latch behind them.
##
## Latched HERE, unlike `AbilityBar` — which takes its pulse from the hero — because
## this bar renders a `HandSlots` model handed to it directly (the spike playground's),
## with no hero contract behind it and no second reader of that same model to disagree
## with. One owner either way; it is just a different owner.
var _flash: Array[float] = []
var _was_ready: Array[bool] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Anchors ALONE leave size at (0,0) until a layout pass, and this control
	# positions everything from `size` — so it would draw its squares off-screen
	# on the first frames, or never if nothing triggers a resize.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vp: Viewport = get_viewport()
	if vp != null:
		size = vp.get_visible_rect().size
		vp.size_changed.connect(func() -> void: size = vp.get_visible_rect().size)


func _process(delta: float) -> void:
	_tick_flashes(delta)
	queue_redraw()


## Age the flashes and catch the not-ready -> ready edge on every slot.
func _tick_flashes(delta: float) -> void:
	var n: int = 0 if slots == null else slots.slots.size()
	if _flash.size() != n:
		_flash.resize(n)
		_was_ready.resize(n)
		for i: int in n:
			_flash[i] = 0.0
			# Seeded from the LIVE state: seeding "ready" would make every slot that
			# happened to be recovering when the bar appeared flash once for nothing.
			_was_ready[i] = slots.is_ready(i)
	for i: int in n:
		_flash[i] = maxf(_flash[i] - delta, 0.0)
		var now: bool = slots.is_ready(i)
		if now and not _was_ready[i]:
			_flash[i] = READY_FLASH_TIME
		_was_ready[i] = now


## Top-left corner of slot `i`, in this control's space.
func _slot_pos(i: int, count: int) -> Vector2:
	var total: float = float(count) * SLOT + float(maxi(count - 1, 0)) * GAP
	var x: float = (size.x - total) * 0.5 + float(i) * (SLOT + GAP)
	var y: float = size.y - SLOT - BOTTOM_MARGIN
	if slots != null and i == slots.selected:
		y -= SELECTED_LIFT
	return Vector2(x, y)


func _gui_input(event: InputEvent) -> void:
	if slots == null or slots.slots.is_empty():
		return
	var at: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton and event.pressed:
		at = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		at = (event as InputEventScreenTouch).position
	else:
		return
	var count: int = slots.slots.size()
	for i in count:
		# Generous vertical padding on the hit box: a thumb is far bigger than a
		# 34 px square, and a tap that misses the bar during a fight is worse
		# than one that lands on the wrong slot.
		if Rect2(_slot_pos(i, count) - Vector2(0.0, 8.0), Vector2(SLOT, SLOT + 16.0)).has_point(at):
			slots.select(i)
			slot_selected.emit(i)
			accept_event()
			return


func _draw() -> void:
	if slots == null or slots.slots.is_empty():
		return
	var count: int = slots.slots.size()
	var font: Font = ThemeDB.fallback_font
	var spell_n: int = 0
	for i in count:
		var entry: Dictionary = slots.slots[i]
		var pos: Vector2 = _slot_pos(i, count)
		var box := Rect2(pos, Vector2(SLOT, SLOT))
		var is_sel: bool = i == slots.selected
		draw_rect(box, BG, true)
		_draw_glyph(entry, box)
		# Cooldown veil sweeps DOWNWARD as it recovers, so a nearly-ready slot is
		# nearly clear. Reading "how much is left" from a shrinking veil is faster
		# than reading a number mid-fight.
		#
		# ⚠ `cooldown_total` IS THE DENOMINATOR, AND NOTHING USED TO WRITE IT. The old
		# `.get("cooldown_total", cd)` fallback quietly made total == remaining, so the
		# fraction was 1.0 on every frame: the veil sat at FULL height for the whole
		# cooldown and then vanished. The bar was never broken — it was being handed a
		# number nobody had ever set. `HandSlots.start_cooldown` writes it now, so the
		# fallback is dead code; it is kept, warns, and draws a full veil, because a
		# slot on cooldown with no recorded duration is a real bug and reading "not yet"
		# is the safe wrong answer.
		var cd: float = float(entry.get("cooldown", 0.0))
		if cd > 0.0:
			var total: float = float(entry.get("cooldown_total", 0.0))
			if total <= 0.0:
				push_warning("LoadoutBar: slot %d is on cooldown with no cooldown_total" % i)
				total = cd
			var frac: float = clampf(cd / maxf(total, 0.001), 0.0, 1.0)
			draw_rect(Rect2(pos, Vector2(SLOT, SLOT * frac)), COOLDOWN_VEIL, true)
		draw_rect(box, BORDER_SELECTED if is_sel else BORDER, false, 2.0 if is_sel else 1.0)
		if is_sel:
			# A soft outer glow so the selected slot survives a busy background.
			draw_rect(box.grow(2.0), Color(BORDER_SELECTED.r, BORDER_SELECTED.g,
				BORDER_SELECTED.b, 0.35), false, 1.0)
		# The key that reaches this slot. Spells are numbered in carousel order, which
		# IS the kit-slot order Hero binds `spell_1..3` to.
		if int(entry.get("kind", HandSlots.Kind.FISTS)) == HandSlots.Kind.SPELL:
			spell_n += 1
			draw_string(font, pos + Vector2(3.0, float(KEY_FONT_SIZE) + 1.0), str(spell_n),
				HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT_SIZE, KEY_TEXT_COLOR)
			# `spell_n - 1` IS the grant ledger's `nth`: both count SPELL slots only,
			# skipping fists and any weapon (see HandSlots.spell_slot_index).
			_draw_charges(box, SpellGrant.charges_in_slot(_owner_hero(), spell_n - 1), font)
		# ...and the flare when it came back. Outside every other branch so a slot that
		# is re-cast within the flash window still gets to finish flashing.
		var flash: float = 0.0 if i >= _flash.size() else _flash[i] / READY_FLASH_TIME
		if flash > 0.0:
			draw_rect(box.grow(READY_FLASH_GROW * (1.0 - flash)),
				Color(READY_FLASH_COLOR.r, READY_FLASH_COLOR.g, READY_FLASH_COLOR.b, flash),
				false, 2.0)


## The hero behind `slots`, or null. Cached, and re-derived the moment the cached
## one dies — heroes are respawned on death and on every floor change, and a stale
## handle here would draw the pips of a corpse.
##
## Reaches `_hand` by name, the same private `SpellGrant._current_spell` already
## depends on; `tools/slice_test_drops.gd` asserts that name still exists on a real
## Hero and fails loudly the day it is renamed.
func _owner_hero() -> Node:
	if hero != null and is_instance_valid(hero) and not hero.is_queued_for_deletion():
		return hero
	hero = null
	if slots == null or not is_inside_tree():
		return null
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if is_instance_valid(h) and h.get(&"_hand") == slots:
			hero = h
			break
	return hero


## `charges` < 0 means "not a granted drop" and draws nothing at all — the pips are
## a fact about a PICKUP, and putting a count on every class spell would make the
## one thing that actually runs out invisible again.
func _draw_charges(box: Rect2, charges: int, font: Font) -> void:
	if charges < 0:
		return
	if charges > PIP_MAX_DOTS:
		draw_string(font, box.position + Vector2(box.size.x - 16.0, float(PIP_FONT_SIZE) + 2.0),
			"x%d" % charges, HORIZONTAL_ALIGNMENT_LEFT, -1, PIP_FONT_SIZE, PIP_COLOR)
		return
	# Right-aligned along the top edge so the pips never sit on the key hint (top
	# LEFT) and never on the cooldown veil's leading edge (which sweeps up from the
	# bottom) — the three readouts share a 34 px square and must not overlap.
	var y: float = box.position.y + PIP_INSET.y
	for i: int in charges:
		var x: float = box.end.x - PIP_INSET.x - float(i) * PIP_GAP
		draw_circle(Vector2(x, y), PIP_RADIUS, PIP_COLOR, true, -1.0, true)


## Procedural icon per slot. Shape comes from what the thing DOES (its kind) and
## colour from its element, so the bar is self-describing without any assets.
func _draw_glyph(entry: Dictionary, box: Rect2) -> void:
	var c: Vector2 = box.get_center()
	var r: float = SLOT * 0.28
	match int(entry.get("kind", HandSlots.Kind.FISTS)):
		HandSlots.Kind.FISTS:
			draw_circle(c, r * 0.8, FISTS_TINT, true, -1.0, true)
			return
		HandSlots.Kind.WEAPON:
			# A blade: a long tapered wedge with a crossguard.
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -r * 1.25), c + Vector2(r * 0.30, r * 0.25),
				c + Vector2(-r * 0.30, r * 0.25)]), WEAPON_TINT)
			draw_line(c + Vector2(-r * 0.62, r * 0.3), c + Vector2(r * 0.62, r * 0.3),
				WEAPON_TINT, 2.0, true)
			return
	var spell: Variant = entry.get("spell")
	var tint: Color = Color(0.75, 0.65, 1.0)
	var kind: int = -1
	if spell != null:
		kind = int(spell.get("kind"))
		var e: int = int(spell.get("element"))
		tint = Elements.color(e) if e >= 0 else tint
	match kind:
		SpellDef.Kind.BEAM, SpellDef.Kind.DIVINE_RAY:
			draw_line(c + Vector2(-r, r * 0.7), c + Vector2(r, -r * 0.7), tint, 3.0, true)
		SpellDef.Kind.WALL, SpellDef.Kind.ICE_WALL, SpellDef.Kind.PILLAR:
			draw_rect(Rect2(c - Vector2(r * 0.55, r), Vector2(r * 1.1, r * 2.0)), tint, true)
		SpellDef.Kind.ZONE:
			draw_arc(c, r, 0.0, TAU, 20, tint, 2.4, true)
		SpellDef.Kind.METEOR, SpellDef.Kind.CONVERGENCE:
			draw_circle(c + Vector2(0.0, r * 0.35), r * 0.55, tint, true, -1.0, true)
			draw_line(c + Vector2(0.0, -r), c + Vector2(0.0, -r * 0.1), tint, 2.0, true)
		SpellDef.Kind.CRAWLER:
			# A ground-hugging wave, sat low in the box to read as "along the floor".
			var pts := PackedVector2Array()
			for i in 9:
				var t: float = float(i) / 8.0
				pts.append(c + Vector2(lerpf(-r, r, t), r * 0.55 + sin(t * TAU) * r * 0.3))
			draw_polyline(pts, tint, 2.2, true)
		SpellDef.Kind.THROWN_ANCHOR:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -r), c + Vector2(r * 0.6, 0.0),
				c + Vector2(0.0, r), c + Vector2(-r * 0.6, 0.0)]), tint)
		SpellDef.Kind.CHAIN, SpellDef.Kind.MISSILES:
			for k in 3:
				draw_circle(c + Vector2(lerpf(-r * 0.7, r * 0.7, float(k) / 2.0), 0.0),
					r * 0.30, tint, true, -1.0, true)
		_:
			draw_arc(c, r * 0.85, 0.0, TAU, 16, tint, 2.2, true)
