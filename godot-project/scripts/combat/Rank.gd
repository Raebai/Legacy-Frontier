extends Node
## Rank progression autoload: grinding kills accrues `power`, which maps to a
## tier (0..5) + title. A tier-up emits `rank_changed` — the hero's aura
## escalation plus the tiny HUD title ARE the feedback. No menus.

signal rank_changed(new_tier: int, new_title: String)

## Threshold power per tier (index = tier). Reaching TIER_POWER[i] IS tier i.
const TIER_POWER: Array[int] = [0, 6, 16, 32, 54, 84]
const TIER_TITLE: Array[String] = [
	"Nameless", "Climber", "Ranked", "Adept", "Ranker", "Ascendant",
]
## Power granted per enemy kill (Enemy._die feeds this via /root/Rank).
const KILL_POWER: int = 3

var power: int = 0

var _hud_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	_refresh_hud()
	rank_changed.connect(_on_rank_changed)


## Highest tier whose threshold `power` meets, clamped to 0..5.
func tier() -> int:
	var t: int = 0
	for i: int in range(TIER_POWER.size()):
		if power >= TIER_POWER[i]:
			t = i
	return clampi(t, 0, TIER_TITLE.size() - 1)


func title() -> String:
	return TIER_TITLE[tier()]


## Grant power (kills now; bosses/quests later). Emits rank_changed only when
## the tier actually flips.
func add_power(n: int) -> void:
	set_power(power + n)


## Set power directly (demo/testing). Same tier-change emit as add_power.
func set_power(n: int) -> void:
	var before: int = tier()
	power = n
	var after: int = tier()
	if after != before:
		rank_changed.emit(after, title())


func _on_rank_changed(_new_tier: int, _new_title: String) -> void:
	_refresh_hud()


## Minimal HUD: one small outlined title label, top-center. Not a menu — the
## rank title + the aura escalation are the entire progression UI.
func _build_hud() -> void:
	var hud: CanvasLayer = CanvasLayer.new()
	hud.layer = 50
	add_child(hud)
	_hud_label = Label.new()
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_label.offset_top = 6.0
	_hud_label.add_theme_font_size_override("font_size", 11)
	_hud_label.add_theme_color_override("font_color", Color(0.93, 0.91, 0.98, 0.92))
	_hud_label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.11, 0.9))
	_hud_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_hud_label)


func _refresh_hud() -> void:
	if _hud_label == null:
		return
	_hud_label.text = "%s · Tier %d" % [title(), tier()]
