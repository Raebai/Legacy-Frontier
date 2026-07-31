class_name SpellHandoff
extends Node2D
## PLAYER-TO-PLAYER SPELL HANDOFF — stand next to your teammate and give them what
## you found.
##
## The spec is explicit that this is worth building, and it is right about why:
## it is the one mechanic in the drop economy that produces BOTH clips. Handing your
## last Void charge to the player who can actually reach the boss is the generous
## play. Taking a Meteor Storm off the floor two steps ahead of your friend and then
## refusing to pass it is the betrayal. Same button.
##
## ══ WHY THE INPUT LIVES HERE AND NOT ON THE HERO ═══════════════════════════════
## Handing something over needs a button, and adding an action to `project.godot`
## or a branch to `Hero._physics_process` are both outside this agent's files. So
## this node polls the input itself. That is not the shape it would take if `Hero`
## were editable — but it is genuinely self-contained, it needs no new action (the
## hub's `talk` binding is unused in the arena), and the actual transfer is a public
## call any other input path can drive.
##
## ⚠ MOBILE. `talk` has no touch button. `TouchControls` is owned elsewhere, so on a
## phone this mechanic is currently UNREACHABLE. The fix is one pad calling
## `try_local_handoff()`; it is in the handoff notes and it is a real gap, not a
## deferral dressed up as one.
##
## ══ THE PROMPT IS THE FEATURE ══════════════════════════════════════════════════
## Half of what makes a handoff a social moment is your teammate SEEING that you
## could give it to them and deciding whether to ask. So the prompt is drawn above
## the receiver, not above the giver, and it names the spell.

## The action pressed to hand over. `talk` is the v0.0 hub's NPC key (E) and is
## bound to nothing inside the arena, so borrowing it adds no keybinding and
## collides with nothing.
const HANDOFF_ACTION: StringName = &"talk"
## How close two heroes must be. Deliberately SHORT — a handoff should be a moment
## where you both stopped fighting and stood together, not something that happens
## by accident while running past. UNTESTED FEEL GUESS.
const RANGE: float = 74.0
## Seconds the "handed over" flash lasts.
const FLASH_TIME: float = 0.9

var _giver: Node2D = null
var _taker: Node2D = null
var _flash: float = 0.0
var _flash_at: Vector2 = Vector2.ZERO
var _flash_name: String = ""
var _phase: float = 0.0


func _process(delta: float) -> void:
	_phase += delta
	_flash = maxf(_flash - delta, 0.0)
	_resolve_pair()
	if _giver != null and _taker != null and Input.is_action_just_pressed(HANDOFF_ACTION):
		try_local_handoff()
	queue_redraw()


## Hand the local player's held drop to the nearest other hero. PUBLIC so a touch
## button, a bot, or the networking layer can drive the same transfer.
func try_local_handoff() -> bool:
	if _giver == null or _taker == null:
		return false
	var have: Dictionary = SpellGrant.held(_giver)
	if have.is_empty():
		return false
	var label: String = (have["spell"] as SpellDef).display_name
	if not SpellGrant.hand_over(_giver, _taker):
		return false
	_flash = FLASH_TIME
	_flash_at = _taker.global_position
	_flash_name = label
	SpellDrops.sfx("ding", -4.0, 0.05, 1.2)
	CombatVfx.spawn_burst(get_parent(), _taker.global_position,
		Color(1.4, 1.4, 1.8, 1.0), Color(0.7, 0.7, 1.0, 0.0), 16, 0.5, 50.0, 160.0,
		1.0, 2.8, 0.0, 0.0, true)
	Juice.on_hit({"shake": 4.0, "sfx": "none", "hitstop": 0.0})
	return true


## Who could give, and who to. The GIVER is the local player — the hero that is not
## bot-driven and, in co-op, the one this peer has authority over. The TAKER is the
## nearest other hero inside `RANGE`.
##
## Both are re-derived every frame rather than cached: heroes are respawned on death
## and on a floor change, and a cached reference to a freed hero is exactly the kind
## of stale handle that turns a social mechanic into a crash.
func _resolve_pair() -> void:
	_giver = null
	_taker = null
	var heroes: Array = get_tree().get_nodes_in_group("hero")
	for h: Node in heroes:
		if not is_instance_valid(h) or h.is_queued_for_deletion() or not (h is Node2D):
			continue
		if _is_local_player(h):
			_giver = h as Node2D
			break
	if _giver == null:
		return
	var best: float = RANGE
	for h: Node in heroes:
		if h == _giver or not is_instance_valid(h) or not (h is Node2D):
			continue
		var d: float = _giver.global_position.distance_to((h as Node2D).global_position)
		if d < best:
			best = d
			_taker = h as Node2D
	# Nothing to give = no prompt. Checked here rather than in `_draw` so the
	# "who is my partner" answer and the "is there a prompt" answer cannot disagree.
	if SpellGrant.held(_giver).is_empty():
		_taker = null


## Is this hero the one at the keyboard? Duck-typed against the two facts the rest
## of the codebase uses for the same question: a bot-driven hero publishes a bot
## controller, and in co-op a hero is driven by its multiplayer authority. A hero
## that answers neither (single player) is the local player by elimination.
func _is_local_player(h: Node) -> bool:
	if bool(h.get(&"bot_driven")) or h.get(&"_bot") != null:
		return false
	var net: Node = get_node_or_null(^"/root/Net")
	if net != null and net.has_method(&"is_active") and bool(net.call(&"is_active")):
		return h.is_multiplayer_authority()
	return true


func _draw() -> void:
	if _flash > 0.0:
		_draw_flash()
	if _giver == null or _taker == null:
		return
	var have: Dictionary = SpellGrant.held(_giver)
	if have.is_empty():
		return
	_draw_prompt(_taker.global_position, (have["spell"] as SpellDef).display_name)


## Drawn above the RECEIVER. The giver already knows what they are holding; the
## person who needs to see the offer is the one who might be about to get it.
func _draw_prompt(at: Vector2, spell_name: String) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(_phase * 4.0)
	var text: String = "[E] give %s" % spell_name
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
	var p: Vector2 = at + Vector2(-w * 0.5, -62.0)
	draw_string(font, p + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
		Color(0.0, 0.0, 0.0, 0.8))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
		Color(1.0, 0.95, 0.7, 0.7 + 0.3 * pulse))
	# A line between the two, so it is obvious WHO would receive it in a crowd.
	if _giver != null:
		draw_line(_giver.global_position + Vector2(0.0, -20.0), at + Vector2(0.0, -20.0),
			Color(1.0, 0.95, 0.7, 0.18 + 0.14 * pulse), 1.6, true)


func _draw_flash() -> void:
	var font: Font = ThemeDB.fallback_font
	var t: float = _flash / FLASH_TIME
	if font != null and _flash_name != "":
		var text: String = "%s !" % _flash_name
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x
		draw_string(font, _flash_at + Vector2(-w * 0.5, -78.0 - 22.0 * (1.0 - t)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 0.95, 0.7, t))
	draw_arc(_flash_at, 26.0 + 34.0 * (1.0 - t), 0.0, TAU, 30,
		Color(1.3, 1.3, 1.7, t * 0.8), 2.4, true)
