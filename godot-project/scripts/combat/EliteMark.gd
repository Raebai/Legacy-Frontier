extends Node2D
## THE ELITE READ — the three things that say "this one is not like the others"
## BEFORE it reaches you.
##
## A behavioural affix that does not announce itself is indistinguishable from a bug.
## `BossModifierHud` settled that argument for bosses ("why did it teleport?" has to
## have an answer the player can read off the screen); a boss gets a name card and a
## screen-wide row of words to do it with. A trash mob in a wave of eleven gets none
## of that, so the read has to live on the body.
##
##   1. THE AURA. `CharacterRig.set_aura` is documented "enemies stay bare sticks" —
##      strength 0, on every enemy in the game, always. Turning it on therefore makes
##      an elite the ONLY glowing thing in the room, and tier 3 adds the spinning
##      ground ring under its feet. At 640x360 that is legible at the far wall, which
##      is the actual requirement: you must know before it hits you.
##   2. THE WORD. One short capital, in the affix's own colour, over its head. Same
##      mnemonic-not-sentence rule the boss HUD landed on — at phone size a sentence
##      is a grey smear. Drawn with the fallback font (zero asset dependency,
##      draw-time only, headless-safe) and outlined, because the arena wash can be
##      any colour the floor rolled.
##   3. THE SILHOUETTE. 12% taller. NOT an HP buff wearing a hat — the hurtbox is cut
##      from the rig height (`Enemy._sync_hurtbox` re-cuts it the frame it changes),
##      so a bigger elite is also a bigger TARGET. Harder to fight, easier to hit.
##
## Every one of these runs on every peer. A client that cannot see which body is the
## elite is playing a different game to the host, and in co-op that reads as the
## host lying.

## Set by EliteModifier.attach before the node enters the tree.
var affix_ids: Array = []

const HEIGHT_MULT: float = 1.12
const AURA_STRENGTH: float = 0.95
## Tier 3 is the first rung with the ground ring (CharacterRig.GROUND_RING_MIN_TIER),
## which is what carries the read when the body itself is behind a crate.
const AURA_TIER: int = 3
const FONT_SIZE: int = 9
## Clearance over the head. CharacterBars sits at -24 on a 31px figure, so the word
## goes above the bar rather than through it.
const LABEL_LIFT: float = 16.0
## Over the rig (which sets its own z) and over the bars.
const Z: int = 60

var _set_up: bool = false
var _text: String = ""
var _color: Color = Color.WHITE
var _lift: float = 48.0


func _ready() -> void:
	z_index = Z
	z_as_relative = false
	var parts: Array[String] = []
	for a in affix_ids:
		parts.append(EliteModifier.name_for(String(a)))
	_text = " ".join(parts)
	if not affix_ids.is_empty():
		_color = EliteModifier.tint_for(String(affix_ids[0]))


## Deferred exactly like a rider's: at `_ready` the parent enemy has not run its own
## `_ready` yet, so there is no rig to dress and no height to read.
func _process(_delta: float) -> void:
	if _set_up:
		return
	_set_up = true
	set_process(false)
	var body: Node = get_parent()
	if body == null or not is_instance_valid(body):
		return
	var rig: Node = body.get_node_or_null(^"Rig")
	if rig == null or not is_instance_valid(rig):
		queue_redraw()
		return
	var h: float = float(rig.get("height"))
	rig.set("height", h * HEIGHT_MULT)
	rig.call("set_aura", _color, AURA_STRENGTH)
	rig.call("set_aura_tier", AURA_TIER)
	# A single bright pop as it lands, so the arrival itself reads as an event.
	rig.call("flash_color", Color(_color.r * 1.8 + 0.3, _color.g * 1.8 + 0.3, _color.b * 1.8 + 0.3), 0.28)
	_lift = h * HEIGHT_MULT + LABEL_LIFT
	queue_redraw()


func _draw() -> void:
	if _text == "":
		return
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var w: float = font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var at := Vector2(-w * 0.5, -_lift)
	# Dark keyline first: the arena wash is a different colour on every floor, and a
	# thin coloured word on an unlucky background is not a read.
	draw_string_outline(font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4,
		Color(0.04, 0.04, 0.07, 0.95))
	draw_string(font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, _color)
