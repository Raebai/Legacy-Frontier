extends CanvasLayer

@onready var name_banner: Label = $Box/VBox/NameBanner
@onready var history_pane: RichTextLabel = $Box/VBox/HistoryPane
@onready var input_field: LineEdit = $Box/VBox/InputField

var _is_open: bool = false


func _ready() -> void:
	visible = false
	input_field.keep_editing_on_text_submit = true
	input_field.text_submitted.connect(_on_text_submitted)


func is_open() -> bool:
	return _is_open


func open(data: NPCData) -> void:
	if _is_open:
		return
	name_banner.text = data.npc_name
	history_pane.clear()
	input_field.clear()
	visible = true
	_is_open = true
	input_field.grab_focus()


func close() -> void:
	if not _is_open:
		return
	visible = false
	_is_open = false
	input_field.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_text_submitted(message: String) -> void:
	var trimmed: String = message.strip_edges()
	if trimmed == "":
		return
	history_pane.append_text("[b]You:[/b] " + trimmed + "\n")
	history_pane.append_text("[color=#cc7733][b]NPC:[/b][/color] I heard you say: " + trimmed + "\n\n")
	input_field.clear()
