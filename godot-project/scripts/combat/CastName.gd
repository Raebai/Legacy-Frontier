class_name CastName
extends Node2D
## THE SPELL SAYS ITS OWN NAME — but only when it has earned the right to.
##
## Maker: *"some spells dont show the words when they are being cast please fix that
## but like show the non ult spells as like casting words coming from the character
## like their speech lets test that see how it look and then the big spells and ults
## can be across the screen actually tou tell me if this is a good idea or if there is
## a better way of doing it"*.
##
## ⚠ I WAS ASKED FOR AN OPINION AND THIS IS IT, so it is written down rather than
## silently implemented differently. The ESCALATION is exactly what was asked for.
## The medium for the bottom rung is not.
##
## WHY NOT SPEECH BUBBLES for the small tier, which is what was proposed:
##   * `Bark` enforces ONE bubble per body (`Bark.BUBBLE_NAME`, and `BotMatch` shares
##     the node deliberately). A cast label and a duel taunt would fight over the same
##     node, and whichever spoke first would own the styling for the body's whole life
##     — that exact reuse hole already existed and was just fixed.
##   * Two casters overlapping puts a wall of text at head height, which is where the
##     floating health bars already live.
##   * A bubble reads as the CHARACTER talking. A spell name is not something the
##     fighter says; it is a label on the thing they are throwing.
##   * And it was worth noticing that the previous note in this same playtest was
##     *"none of the text should have those old speech bubbles"* — adding a new
##     speech-shaped channel a few minutes later would be pulling in two directions.
##
## WHAT THIS DOES INSTEAD — three rungs, taken from `SpellTier.of`, which DERIVES the
## shelf from cast time / cooldown / cost. Deriving matters: a spell cannot lie about
## how important its own announcement is, and nobody has to maintain a list.
##
##   QUICK  — nothing at all. The shape and the colour are the read. A name on every
##            bolt is noise, and noise is what makes the ult's name mean nothing.
##   HEAVY  — a small name rising off the caster in the element's colour, ~0.6 s.
##            Part of the spell, not the character.
##   ULT    — big, centred, across the screen, held. This is the one the maker asked
##            for and it is the one that stays rare enough to land.
##
## Primitive-drawn and self-freeing, like `SwingArc` and `BlinkSpark`. The ULT rung
## uses a `CanvasLayer` so it is screen-space rather than world-space — a world-space
## banner would be parallaxed by the camera and clipped by the stage edges.

const HEAVY_LIFE: float = 0.62
const ULT_LIFE: float = 1.15
## How far a HEAVY name drifts up over its life, px. Small: it is a label, not a
## damage number, and a long climb turns it into litter.
const HEAVY_RISE: float = 26.0
## Above the head, clear of the floating bars.
const HEAVY_LIFT: float = 40.0
const HEAVY_FONT: int = 11
const ULT_FONT: int = 34


static func _default_font() -> Font:
	var lbl := Label.new()
	var f: Font = lbl.get_theme_default_font()
	lbl.free()
	return f


## Announce `spell` cast by `who`. Returns the node it made, or null when the shelf
## says this one stays quiet.
##
## `parent` is the arena for a HEAVY (world space) and is ignored for an ULT, which
## builds its own `CanvasLayer` on the tree root. Silently does nothing without a
## live tree, so a headless suite that casts a spell does not have to know this
## exists.
static func announce(parent: Node, who: Node2D, spell: SpellDef, tint: Color) -> Node:
	if spell == null or parent == null or not is_instance_valid(parent):
		return null
	if not parent.is_inside_tree():
		return null
	var text: String = spell.display_name.strip_edges()
	if text == "":
		return null
	match SpellTier.of(spell):
		SpellTier.Tier.QUICK:
			return null                       # deliberately silent — see the header
		SpellTier.Tier.ULT:
			return _ult_banner(parent, text, tint)
		_:
			return _heavy_label(parent, who, text, tint)


static func _heavy_label(parent: Node, who: Node2D, text: String, tint: Color) -> Node:
	if who == null or not is_instance_valid(who):
		return null
	var n := CastName.new()
	n._text = text
	n._tint = tint
	n._life = HEAVY_LIFE
	n.z_index = 3
	n.z_as_relative = false
	parent.add_child(n)
	n.global_position = who.global_position - Vector2(0.0, HEAVY_LIFT)
	return n


## SCREEN-SPACE, on its own layer. A world-space banner would drift with the camera
## and be clipped by the stage; "across the screen" has to mean the screen.
static func _ult_banner(parent: Node, text: String, tint: Color) -> Node:
	var tree: SceneTree = parent.get_tree()
	if tree == null:
		return null
	var layer := CanvasLayer.new()
	layer.layer = 90          # under the pause overlay, over the arena
	var n := CastName.new()
	n._text = text
	n._tint = tint
	n._life = ULT_LIFE
	n._ult = true
	n._owns_layer = layer
	layer.add_child(n)
	tree.root.add_child(layer)
	# Centred on the viewport, a little above the middle so it does not sit on the
	# fighters it is announcing.
	var vp: Vector2 = Vector2(tree.root.get_visible_rect().size)
	n.position = Vector2(vp.x * 0.5, vp.y * 0.34)
	return n


var _text: String = ""
var _tint: Color = Color.WHITE
var _life: float = HEAVY_LIFE
var _ult: bool = false
var _owns_layer: CanvasLayer = null
var _t: float = 0.0
var _font: Font = null


func _ready() -> void:
	_font = _default_font()
	# ⚠ RUNS THROUGH A PAUSE. An ult banner that appears on the frame `BotMatch`
	# freezes the tree would otherwise hang on screen forever.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		if _owns_layer != null and is_instance_valid(_owns_layer):
			_owns_layer.queue_free()
		else:
			queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _font == null or _text == "":
		return
	var u: float = clampf(_t / _life, 0.0, 1.0)
	if _ult:
		_draw_ult(u)
	else:
		_draw_heavy(u)


## A small name that rises and fades. Outlined rather than boxed — the outline is
## what makes text legible over a busy stage, and it is what the speech bubble was
## relying on anyway.
func _draw_heavy(u: float) -> void:
	var fade: float = 1.0 - u * u        # holds, then goes quickly
	var rise: float = -HEAVY_RISE * u
	var size: Vector2 = _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, HEAVY_FONT)
	var at: Vector2 = Vector2(-size.x * 0.5, rise)
	for o: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_string(_font, at + o, _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			HEAVY_FONT, Color(0.02, 0.02, 0.04, 0.85 * fade))
	draw_string(_font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, HEAVY_FONT,
		Color(_tint.r, _tint.g, _tint.b, fade))


## The big one. Snaps in wide, settles, holds, fades — with a rule under it, because
## a bare word floating on a fight reads as a debug print.
func _draw_ult(u: float) -> void:
	var fade: float = 1.0 if u < 0.62 else clampf((1.0 - u) / 0.38, 0.0, 1.0)
	# A short overshoot on the way in is what makes it land rather than appear.
	var pop: float = 1.0 + 0.22 * maxf(1.0 - u / 0.14, 0.0)
	var size: Vector2 = _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, ULT_FONT)
	var half: float = size.x * 0.5 * pop
	var at: Vector2 = Vector2(-half, 0.0)
	for o: Vector2 in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		draw_string(_font, at + o, _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			ULT_FONT, Color(0.01, 0.01, 0.03, 0.9 * fade))
	draw_string(_font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ULT_FONT,
		Color(_tint.r, _tint.g, _tint.b, fade))
	# The rule, drawn from the centre outward so it opens WITH the word.
	var rule: float = half * 1.16 * clampf(u / 0.18, 0.0, 1.0)
	draw_line(Vector2(-rule, 10.0), Vector2(rule, 10.0),
		Color(_tint.r, _tint.g, _tint.b, 0.75 * fade), 2.0, true)
