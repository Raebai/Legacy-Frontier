extends Node2D

const VERTICAL_OFFSET: float = 18.0  # pixels above character origin
const MAX_WIDTH: float = 220.0
const MIN_WIDTH: float = 32.0  # only used by show_thinking()
const BINARY_SEARCH_ITERATIONS: int = 6
const BINARY_SEARCH_PRECISION: float = 4.0

# Three frames with a bold dot sliding left-to-right against dim dots — reads
# as "thinking" with horizontal motion rather than the additive grow-shrink
# pattern of earlier versions.
const THINKING_FRAMES: PackedStringArray = [
	"[b]●[/b] [color=#888]●[/color] [color=#888]●[/color]",
	"[color=#888]●[/color] [b]●[/b] [color=#888]●[/color]",
	"[color=#888]●[/color] [color=#888]●[/color] [b]●[/b]",
]

@onready var panel: PanelContainer = $Panel
@onready var label: RichTextLabel = $Panel/Margin/Label
@onready var fade_timer: Timer = $FadeTimer
@onready var thinking_timer: Timer = $ThinkingTimer

# x_offset shifts the bubble horizontally relative to the character.
# Used to anchor whispering player's bubble away from the NPC they're talking to.
var _x_offset: float = 0.0
var _thinking: bool = false
var _thinking_frame: int = 0


func _ready() -> void:
	visible = false
	fade_timer.timeout.connect(_on_fade_timeout)
	thinking_timer.timeout.connect(_on_thinking_tick)


func _process(_delta: float) -> void:
	if not visible:
		return
	# Force panel to its minimum content-based size every frame; this
	# shrinks-to-fit regardless of any stale offsets/layout state.
	panel.size = panel.get_combined_minimum_size()
	var desired_y: float = -panel.size.y - VERTICAL_OFFSET
	# Clamp: keep bubble top inside the visible viewport.
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var viewport_top_world: float = camera.global_position.y - viewport_size.y * 0.5
		var panel_top_world: float = global_position.y + desired_y
		if panel_top_world < viewport_top_world + 4.0:
			desired_y = (viewport_top_world + 4.0) - global_position.y
	panel.position = Vector2(-panel.size.x * 0.5 + _x_offset, desired_y)


func say(text: String, fade_seconds: float = 6.0, x_offset: float = 0.0) -> void:
	_stop_thinking()
	label.text = text
	_x_offset = x_offset
	await _resize_to_content()
	visible = true
	fade_timer.stop()
	if fade_seconds > 0.0:
		fade_timer.wait_time = fade_seconds
		fade_timer.start()


func show_thinking() -> void:
	_thinking = true
	_thinking_frame = 0
	label.text = THINKING_FRAMES[0]
	_x_offset = 0.0
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size = Vector2(MIN_WIDTH, 0)
	visible = true
	fade_timer.stop()
	thinking_timer.start()


func clear_bubble() -> void:
	_stop_thinking()
	visible = false
	fade_timer.stop()


func _on_fade_timeout() -> void:
	_stop_thinking()
	visible = false


func _on_thinking_tick() -> void:
	if not _thinking:
		return
	_thinking_frame = (_thinking_frame + 1) % THINKING_FRAMES.size()
	label.text = THINKING_FRAMES[_thinking_frame]


func _stop_thinking() -> void:
	if _thinking:
		_thinking = false
		thinking_timer.stop()


# Resize the label so the bubble fits text exactly.
# Single-line text: bubble width = unwrapped natural text width.
# Multi-line text: binary search for the smallest width that keeps the same
# line count as wrapping at MAX_WIDTH — guarantees no slack on the longest line.
func _resize_to_content() -> void:
	# Pass 1: measure unwrapped natural width.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size = Vector2.ZERO
	await get_tree().process_frame
	var natural_width: float = float(label.get_content_width())
	if natural_width <= MAX_WIDTH:
		# Fits on one line — hug the text exactly.
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size = Vector2(natural_width, 0)
		return
	# Pass 2: wrap at MAX_WIDTH, get baseline line count.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	await get_tree().process_frame
	var target_lines: int = label.get_line_count()
	# Binary search: smallest width where line count doesn't exceed target.
	var low: float = 50.0
	var high: float = MAX_WIDTH
	var best: float = MAX_WIDTH
	for i in BINARY_SEARCH_ITERATIONS:
		if high - low < BINARY_SEARCH_PRECISION:
			break
		var mid: float = (low + high) * 0.5
		label.custom_minimum_size = Vector2(mid, 0)
		await get_tree().process_frame
		if label.get_line_count() <= target_lines:
			best = mid
			high = mid
		else:
			low = mid
	label.custom_minimum_size = Vector2(best, 0)
