extends CanvasLayer
## Hub Armory LOADOUT panel (autoload "Loadout"). Pick your gear per slot
## (weapon / head / body); every piece carries a GearAbilities ability that shapes
## the run hero (its element, melee profile, HP/speed, ward). Writes GameState.loadout
## and live-previews the choice on the hub stick figure. Built in code + scene-safe
## (mirrors ClassSelect / PauseMenu). "Default" (empty) keeps the class's own gear for
## that slot.
##
## ⚠ THIS PANEL WAS COMPLETE AND UNREACHABLE. Its only opener was the hub's
## `ArmoryStation`, which sits behind a literal `if false:` in the parked hub
## (`World.gd`) — so 19 authored pieces with live effect bags, already consumed by
## `Hero._aggregate_gear`, had never been seen by a player. It is now opened from the
## **Outfitter** on the Lobby (`scripts/ui/Outfitter.gd`), which is the boot screen and
## works on a phone. The hub opener is left exactly as it was.
##
## IS THIS PERMANENT PROGRESSION? No, and the distinction is the one the spec cares
## about. Nothing here accumulates: a piece is CHOSEN per run, `Hero` recomputes every
## effect from a per-class base snapshot (`_base_max_hp` and friends) on every change,
## and a class switch clears `_gear_override` outright. Equip the helmet twice and you
## are not 40% tougher — `tools/slice_test_loadout.gd` pins that idempotency. It is a
## loadout, not a ladder.
##
## The honest caveat is a BALANCE one rather than a progression one, and it is left
## alone deliberately: the head and body pieces are pure upside against the class
## default (+HP, +speed, ward, flat mitigation) with no matching cost, so each of
## those two slots has a strictly-best answer. The weapon slot does not have that
## problem — it trades (greatsword +30% damage for +30% cooldown; dagger sheds damage
## for speed). Giving head/body the same shape is a one-line data edit in
## `GearAbilities.gd`, but it is a balance change that wants a playtest behind it, and
## this file's own header warns against destabilising the balanced classes on a guess.

const SLOTS: Array = ["weapon", "head", "body"]
const SLOT_LABELS: Dictionary = {"weapon": "WEAPON", "head": "HEAD", "body": "BODY"}
const OPTIONS: Dictionary = {
	"weapon": ["", "staff", "staff_ice", "staff_storm", "staff_holy", "sword", "dagger", "hammer", "greatsword", "scythe", "orb"],
	"head": ["", "hat", "hood", "helmet"],
	"body": ["", "robe", "cape", "armor"],
}
const HIGHLIGHT: Color = Color(0.55, 0.9, 1.0)

## Laid out for the 640x360 base viewport in LANDSCAPE — the same budget the Lobby
## and the Outfitter are pinned to. Every piece button clears BUTTON_H.
const PANEL_W: float = 420.0
const BUTTON_H: float = 30.0
## FIXED height of the scrolling slot list. See the note at the ScrollContainer.
const LIST_H: float = 150.0

var _slot_buttons: Dictionary = {}       # slot -> Array[Button]
var _ability_label: RichTextLabel = null
var _scroll: ScrollContainer = null
## The panel column. Held so a suite can assert the whole armory still fits 360 px.
var _col: VBoxContainer = null


func _ready() -> void:
	layer = 90
	visible = false
	var dim := ColorRect.new()
	# Nearly opaque. This now opens over the Outfitter rather than over an empty hub
	# floor, and at 0.62 a whole second menu read straight through the piece names.
	dim.color = Color(0.03, 0.03, 0.06, 0.93)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_child(vbox)
	_col = vbox

	var title := Label.new()
	title.text = "⚒  ARMORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	vbox.add_child(title)

	# ⚠ THE BOUND, and the reason this panel now fits a phone at all. Measured at
	# 560x377 before this scroll existed — 17 px TALLER than the entire 640x360 base
	# viewport, so the bottom row of the body slot and the ability read-out were off
	# the screen on the one platform this game is for. Nobody had noticed because the
	# panel was unreachable: its only opener sat behind a literal `if false:` in the
	# parked hub.
	#
	# A ScrollContainer reports zero minimum size on its scrolling axis, so this
	# constant decides how tall the panel is — not the number of pieces in the
	# registry. Add five more weapons and it measures exactly the same.
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(PANEL_W, LIST_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	_scroll.add_child(rows)
	for slot: String in SLOTS:
		rows.add_child(_build_slot_row(slot))

	# Ability read-out for the current selection.
	_ability_label = RichTextLabel.new()
	_ability_label.bbcode_enabled = true
	_ability_label.fit_content = true
	_ability_label.custom_minimum_size = Vector2(PANEL_W - 16.0, 40)
	_ability_label.add_theme_font_size_override("normal_font_size", 11)
	vbox.add_child(_ability_label)

	# An explicit way out. Tap-away works (the dim eats the press), but a phone
	# player has no Esc key and no reason to guess that the darkness is a button.
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(PANEL_W - 16.0, BUTTON_H)
	done.add_theme_font_size_override("font_size", 14)
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	vbox.add_child(done)


func _build_slot_row(slot: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = String(SLOT_LABELS[slot])
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	row.add_child(lbl)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	row.add_child(flow)
	var buttons: Array = []
	for kind: String in OPTIONS[slot]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, BUTTON_H)
		b.add_theme_font_size_override("font_size", 12)
		b.focus_mode = Control.FOCUS_NONE   # a stray focus ring on a phone reads as a bug
		b.text = _option_label(kind)
		b.pressed.connect(_on_option.bind(slot, kind))
		flow.add_child(b)
		buttons.append(b)
	_slot_buttons[slot] = buttons
	return row


## Short button caption: "Default" for the empty slot, else the piece's ability name.
func _option_label(kind: String) -> String:
	if kind == "":
		return "Default"
	var a: Dictionary = GearAbilities.of(kind)
	return String(a.get("name", kind))


func is_open() -> bool:
	return visible


func open() -> void:
	_refresh()
	_preview()
	visible = true


func close() -> void:
	visible = false


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_option(slot: String, kind: String) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var lo: Variant = gs.get("loadout")
		if lo is Dictionary:
			(lo as Dictionary)[slot] = kind   # Dictionaries are references — mutate in place
	_preview()
	_refresh()


## Dress the hub stick in the class default + the chosen overrides so the player
## sees their loadout. No-op outside the hub (scene-safe).
func _preview() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("preview_loadout"):
		return
	player.call("preview_loadout", _preset(), _loadout())


## The hero preset for the currently-selected class (for the default-gear preview).
## Hero.gd has no class_name, so its CLASS_CONFIG is read via a runtime (cached) load
## rather than a parse-time reference (which would fail this autoload's compile).
const HERO_PATH: String = "res://scripts/combat/Hero.gd"

func _preset() -> String:
	var gs: Node = get_node_or_null("/root/GameState")
	var cls: int = int(gs.get("selected_class")) if gs != null else 0
	var cfg_all: Dictionary = (load(HERO_PATH) as GDScript).get_script_constant_map().get("CLASS_CONFIG", {})
	var cfg: Dictionary = cfg_all.get(cls, {})
	return String(cfg.get("preset", ""))


func _loadout() -> Dictionary:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var lo: Variant = gs.get("loadout")
		if lo is Dictionary:
			return lo
	return {"weapon": "", "head": "", "body": ""}


## Highlight the selected button per slot + list the active abilities.
func _refresh() -> void:
	var lo: Dictionary = _loadout()
	for slot: String in SLOTS:
		var sel: String = String(lo.get(slot, ""))
		var opts: Array = OPTIONS[slot]
		var buttons: Array = _slot_buttons.get(slot, [])
		for i: int in buttons.size():
			(buttons[i] as Button).modulate = HIGHLIGHT if String(opts[i]) == sel else Color.WHITE
	if _ability_label != null:
		_ability_label.text = _ability_text(lo)


## BBCode read-out of the equipped pieces' abilities (skips empty slots).
func _ability_text(lo: Dictionary) -> String:
	var lines: Array = []
	for slot: String in SLOTS:
		var kind: String = String(lo.get(slot, ""))
		if kind == "":
			continue
		var a: Dictionary = GearAbilities.of(kind)
		if a.is_empty():
			continue
		lines.append("[color=#8fd0ff]%s[/color]  %s" % [a.get("name", kind), a.get("desc", "")])
	if lines.is_empty():
		return "[color=#9aa4b5]Class default gear. Pick pieces to customise your kit.[/color]"
	return "\n".join(lines)
