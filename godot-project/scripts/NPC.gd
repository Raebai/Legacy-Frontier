extends StaticBody2D
## A TOWNSPERSON. A stick figure that ambles the town, stops when you come close,
## and says ONE LINE when you press interact. That is the whole of it.
##
## ── WHAT THIS FILE USED TO BE ──────────────────────────────────────────────
## 300-odd lines of it were the v0.5 AI-NPC stack: a four-layer memory model
## (`short_term` / `long_term_summary` / `relationships` / gossip inbox) saved to
## `user://npc_memory/<id>.json`, a v1→v2 migration, a patience scalar, and an
## `HTTPRequest` child that POSTed the whole transcript to a local Ollama server
## at `127.0.0.1:11434` to have a 3B model consolidate it. It is deleted, not
## commented out — the design doc cuts persistent world / NPC memory / LLM
## anything permanently, and on the target platform that address is the phone's
## own loopback, so the feature could never have run there at all. Git history
## has every line of it.
##
## ── HOW A TOWNSPERSON SPEAKS NOW ───────────────────────────────────────────
## `NPCData.lines` + the shared `SpeechBubble`, with `Bark.voice_only()` for the
## mouth — the same synthesised gibberish every other body in the game uses, so a
## townsperson sounds like a person and specifically like THEMSELVES: the voice is
## seeded from `npc_id` via `Bark.SEED_META`, which is stable across launches and
## across peers, unlike the node name `Gibberish` would otherwise read.
##
## No branching, no state, no queue, nothing to await. Pressing interact twice
## gets you a second line, never a second half of the first one.

@onready var hint_label: Label = $HintLabel
@onready var proximity_area: Area2D = $ProximityArea
@onready var speech_bubble: Node2D = $SpeechBubble

@export var data: NPCData

## How long a townsperson's line stays up. Longer than a combat bark (`Bark.HOLD`
## is 1.9 s) because nobody is dodging anything in the town.
const LINE_HOLD: float = 3.4

## Ambling speed, and how far either side of their post they wander.
const PATROL_SPEED: float = 32.0

var _player_in_range: bool = false
var _rig: CharacterRig = null
var _patrol_center: float = 0.0
var _patrol_range: float = 0.0
var _patrol_dir: float = 1.0
## Index of the last line said, so the same one never lands twice running.
var _last_line: int = -1


func _ready() -> void:
	hint_label.visible = false
	proximity_area.body_entered.connect(_on_body_entered)
	proximity_area.body_exited.connect(_on_body_exited)
	var block: Node = get_node_or_null("Visual")
	if block != null:
		(block as CanvasItem).visible = false
	_rig = CharacterRig.new()
	add_child(_rig)
	# Feet at the node origin (the rig draws its feet height*0.5 below its own
	# origin) so the body stands ON the ground rather than sunk into it.
	_rig.position.y = -_rig.height * 0.5
	_rig.play(CharacterRig.State.IDLE)
	if data != null:
		_rig.set_tint(data.display_color)
		hint_label.text = "[E] %s" % data.npc_name
		# A voice that is theirs and stays theirs. See the note on Bark.SEED_META:
		# a node name is assigned by whichever parent adopts the body, so anything
		# that must sound the same twice seeds from replicated data instead.
		set_meta(Bark.SEED_META, hash(data.npc_id))


## The town calls this to make the body amble around `center_x`, +/- `patrol_range`.
func set_hub_patrol(center_x: float, patrol_range: float) -> void:
	_patrol_center = center_x
	_patrol_range = patrol_range
	global_position.x = center_x


## Amble, but STOP and stand still whenever the player is close enough to talk
## (maker: "show NPCs walking around but stop when you go up to them"). A
## StaticBody2D on flat ground, so x is animated directly — no gravity needed.
func _physics_process(delta: float) -> void:
	if _patrol_range <= 0.0 or _rig == null:
		return  # not a patrolling townsperson (headless tests, for one)
	if _player_in_range:
		_rig.play(CharacterRig.State.IDLE)
		return
	var nx: float = global_position.x + _patrol_dir * PATROL_SPEED * delta
	if nx > _patrol_center + _patrol_range:
		_patrol_dir = -1.0
		nx = _patrol_center + _patrol_range
	elif nx < _patrol_center - _patrol_range:
		_patrol_dir = 1.0
		nx = _patrol_center - _patrol_range
	global_position.x = nx
	_rig.play(CharacterRig.State.RUN)
	_rig.set_facing(Vector2(_patrol_dir, 0.0))


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("talk") or not _player_in_range:
		return
	if _overlay_open():
		return
	speak()
	get_viewport().set_input_as_handled()


## ⚠ THE TOWN CLOCKING YOUR CLIMB, AND IT IS THE WHOLE POINT OF THE TOWN.
##
## The v0.5 AI-NPC stack existed so the town could say "that is 4 falls now". That
## stack is deleted and stays deleted — but the FEELING it was for is the project's
## moat, and it does not actually need a language model. It needs four numbers.
##
## So an authored line may carry a token, and the town fills it in:
##   {floor} the floor you will resume on   {best} the highest you have ever reached
##   {falls} how many times you have fallen {level} your level
##   {points} unspent skill points
##
## A line with no token is untouched, which is every line the town shipped with.
## An unknown token is left as-is rather than blanked — a visible `{oops}` in a
## speech bubble is a bug report; a silently empty sentence is not.
func _fill(line: String) -> String:
	if not line.contains("{"):
		return line
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs == null:
		return line
	var level: int = int(gs.call("level"))
	var owned: Array = gs.get("unlocked_nodes") as Array
	var out: String = line
	out = out.replace("{floor}", str(int(gs.call("current_floor"))))
	out = out.replace("{best}", str(int(gs.get("_highest_floor"))))
	out = out.replace("{falls}", str(int(gs.get("_falls"))))
	out = out.replace("{level}", str(level))
	out = out.replace("{points}", str(SpellTree.points_available(level, owned)))
	return out


## Say one line. Public so a capture tool can pose the town without faking input.
## Returns false when there is nothing to say — SYNCHRONOUS, like `Bark.say`, and
## for the same reason: one `await` in here turns every call site into a coroutine.
func speak() -> bool:
	if data == null or data.lines.is_empty():
		return false
	var i: int = randi() % data.lines.size()
	if data.lines.size() > 1 and i == _last_line:
		i = (i + 1) % data.lines.size()
	_last_line = i
	# NOT awaited — SpeechBubble.say yields a few frames while it shrink-to-fits.
	speech_bubble.say(_fill(data.lines[i]), LINE_HOLD)
	Bark.voice_only(self, Gibberish.Mood.TALK)
	return true


## True while any town panel is up, so interact does not fire THROUGH an open
## screen. Every station in the town asks the same question; it is three lookups
## rather than a shared helper because a new script outside the station set is a
## bigger change than the duplication it would save.
func _overlay_open() -> bool:
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel != null and sel.has_method("is_open") and sel.is_open():
		return true
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("is_open") and lo.is_open():
		return true
	for o: Node in get_tree().get_nodes_in_group("town_overlay"):
		if o is CanvasItem and (o as CanvasItem).visible:
			return true
	return false


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		hint_label.visible = true
		if _rig != null:
			# Turn to face whoever walked up.
			_rig.set_facing(Vector2(signf(body.global_position.x - global_position.x), 0.0))


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		hint_label.visible = false


## Kept because the town's own scripts put lines over heads through it.
func say(text: String, fade_seconds: float = LINE_HOLD) -> void:
	speech_bubble.say(text, fade_seconds)
