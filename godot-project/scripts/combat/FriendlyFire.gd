class_name FriendlyFire
extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════════
## THE GAME NOTICING THAT YOU HIT YOUR FRIEND.
## ═══════════════════════════════════════════════════════════════════════════════
##
## Friendly fire is the stated social engine of THE TOWER and it shipped with ZERO
## acknowledgement: no bark category covers it, damage numbers are the same colour
## whoever dealt them, and there was no player-facing switch — only a debug toggle
## inside the director. So the funniest thing that can happen in this game (you
## delete your teammate with the Void) rendered exactly like a stray enemy hit.
##
## **Comedy needs attribution.** A hit nobody is blamed for is not a joke, it is a
## bug report. This file is the attribution.
##
## ── WHAT IT IS ─────────────────────────────────────────────────────────────────
## Two things, deliberately in one file because they are one decision:
##   1. THE READ — `report()`: the beat that fires when hero hits hero.
##   2. THE DIAL — `enabled()` / `set_enabled()`: the ONE switch, so the pause menu
##      and the director cannot disagree about whether it is on.
##
## ── WHERE IT IS WIRED, AND WHERE IT IS NOT (read before extending) ─────────────
## `Hero.take_damage(amount)` takes NO attacker, so nothing downstream of a hit can
## say who threw it. There is exactly one place in this codebase where hero-on-hero
## damage is identifiable without that argument:
##
##     `Net.deal_damage(target, ...)` with a HERO target.
##
## `Spell.tscn` is instanced only by `Hero` (`Hero.gd:241`), and `Spell._damage_hero`
## is the only caller of `Net.deal_damage` — so a hero on the receiving end of that
## router is, by construction, a hero's bolt hitting a hero. With `Net.MAX_PLAYERS`
## capped at 2 the attacker is then the *other* live hero, exactly, with no guess.
##
## That covers the BOLT — the verb the right thumb holds down, and the most-thrown
## thing in the game. It does NOT cover the AoE spectacles, which resolve through
## `SpellTargets.hurt()` -> `target.take_damage(amount)` and never touch the router.
## Closing that gap is one line inside `SpellTargets.hurt` (a file this workstream
## does not own):
##
##     FriendlyFire.note(target, SpellTargets.owner_of(ctx), amount)
##
## Nothing here guesses at attribution. A read that sometimes blames your friend for
## an enemy's hit is worse than silence, because it teaches the player to distrust
## the one signal the whole social design rests on.
##
## ── WHY THE TEXT LIVES HERE AND NOT IN `Bark.LINES` ───────────────────────────
## It belongs in `Bark.LINES` under a `friendly_fire` key and should move there —
## `Bark.gd` is owned by another workstream. The lines below obey Bark's own rules
## (five words or fewer, present tense, no proper nouns, chalk-and-ink voice) so the
## move is a copy-paste when that file is available.

## Team-damage colour. Warm gold rather than the hurt-red every other hit uses, so
## the difference is legible in one frame at the 0.63 framing zoom where a hero is
## ~19 px tall. Matches the LEAVE-THE-TOWER portal's gold: in this game, gold means
## "this was your own doing".
const TEAM_TINT: Color = Color(1.0, 0.78, 0.30)

## How long the toast holds. Longer than a bark (1.9 s) because it is the ONLY
## thing on screen that names what happened, and shorter than a floor banner.
const TOAST_HOLD: float = 1.35
const TOAST_FADE: float = 0.45
## Above the ability bar (60) and the Hype shouts (55), below the pause menu (90):
## a friendly-fire hit must not be hidden behind the HUD, and must not cover a menu.
const TOAST_LAYER: int = 72
## Only ever one on screen. A beam sweeping a teammate lands a hit per tick, and a
## stack of toasts is a wall of text at the exact moment the player wants to see the
## fight. The newest replaces the oldest in place.
const TOAST_GROUP: StringName = &"friendly_fire_toast"

## Minimum gap between two READS for the same victim, in seconds. The damage still
## lands every tick — this rate-limits the CEREMONY only, on the same reasoning as
## `Bark.COOLDOWN`. A drain tether on a teammate should read as one mistake, not
## forty.
const READ_COOLDOWN: float = 1.1

## What the attacker's own figure says. Bark's voice: dry, short, unimpressed, and
## never an explanation.
const ATTACKER_LINES: Array[String] = [
	"...hand slipped.",
	"wrong shape.",
	"my line, sorry.",
	"drew that badly.",
]
## And the victim's, which is the half that makes it funny rather than confusing.
const VICTIM_LINES: Array[String] = [
	"same page, idiot.",
	"that was YOU.",
	"aim. please.",
	"i'm on your side.",
]

const BUBBLE_SCENE: String = "res://scenes/SpeechBubble.tscn"
## Reuses `Bark`'s bubble node by NAME rather than adding a second one — two
## bubbles on one body render two lines on top of each other.
const BUBBLE_NAME: StringName = &"BarkBubble"
const BUBBLE_HOLD: float = 1.6


# ═══════════════════════════════════════════════════════════════════ THE DIAL
## Is friendly fire live?
##
## ⚠ THERE IS EXACTLY ONE SWITCH AND IT IS `SpellCaster.friendly_fire`. That static
## decides which group `SpellCaster._stamp` writes onto all 21 dispatch arms, which
## is what makes every spectacle in the game faction-blind. Mirroring it into a
## second bool here would let the pause menu and the director drift apart, and the
## first symptom of that would be a player turning it "off" and still deleting their
## friend.
static func enabled() -> bool:
	return SpellCaster.friendly_fire


## Turn it on or off. This is the PLAYER-FACING dial (pause -> Settings), and the
## director's own toggle writes the same static, so the two always agree.
##
## ⚠ THE SWITCH IS NOT COMPLETE ON ITS OWN, WHICH IS WHY `blocks_bolt()` EXISTS.
## Flipping the static re-points every SPECTACLE at a faction group and genuinely
## stops AoE hitting a teammate. It does NOT stop the basic bolt: `Spell._damage_hero`
## permits a hero hit through its own clause (`session and hostile_group == &"enemy"`),
## which never consults this static. So "off" used to mean "off, except for the one
## attack every class throws constantly" — a dial that lies. `Net.deal_damage`
## asks `blocks_bolt()` and drops the hit, which closes it.
static func set_enabled(on: bool) -> void:
	SpellCaster.friendly_fire = on


## Should this hero-on-hero BOLT hit be discarded? True only when the dial is off.
## Kept as its own named question rather than `not enabled()` at the call site, so
## the reason it is being asked is readable from `Net.deal_damage`.
static func blocks_bolt() -> bool:
	return not SpellCaster.friendly_fire


## The three-word answer for a settings row / a signpost.
static func status_text() -> String:
	return "ON — you can hit your friend" if enabled() else "off"


# ══════════════════════════════════════════════════════════════════ THE READ
## Fire the whole beat: the toast, the gold burst on the victim, a line over each
## figure's head, the camera kick and the tally.
##
## Returns true if a read actually landed. False means: not two distinct live
## heroes, no tree, or still inside `READ_COOLDOWN` — all normal, none an error.
##
## `attacker` may be null when the source is known to be a teammate but not WHICH
## teammate; the toast still fires (the victim is entitled to know), the attacker's
## bubble simply does not.
static func report(victim: Node, attacker: Node, amount: int) -> bool:
	if not is_hero(victim):
		return false
	if attacker != null and (attacker == victim or not is_hero(attacker)):
		return false
	var tree: SceneTree = victim.get_tree()
	if tree == null or tree.root == null:
		return false
	if not _off_cooldown(victim):
		return false
	var hurt: int = maxi(amount, 0)
	_tally(tree, hurt)
	_toast(tree, hurt)
	if victim is Node2D:
		var at: Vector2 = (victim as Node2D).global_position
		CombatVfx.spawn_burst(tree.current_scene if tree.current_scene != null else victim,
			at + Vector2(0.0, -14.0), TEAM_TINT,
			Color(TEAM_TINT.r, TEAM_TINT.g, TEAM_TINT.b, 0.0),
			18, 0.5, 70.0, 210.0, 0.9, 2.4, 30.0, 70.0)
		_bubble(victim as Node2D, VICTIM_LINES)
	if attacker is Node2D:
		_bubble(attacker as Node2D, ATTACKER_LINES)
	# A shake rather than a hit-stop: the hit ALREADY paid for a hit-stop inside
	# `Hero.take_damage`, and stacking a second one on the same frame reads as a
	# stutter rather than as emphasis.
	Juice.shake_camera(7.0)
	_sfx(tree)
	return true


## Is this node a live hero body?
static func is_hero(n: Node) -> bool:
	return n != null and is_instance_valid(n) and not n.is_queued_for_deletion() \
		and n.is_in_group(&"hero")


## The other live hero in the party, or null.
##
## ⚠ EXACT RATHER THAN HEURISTIC, AND ONLY BECAUSE THE PARTY IS CAPPED AT TWO.
## `Net.MAX_PLAYERS == 2` is a hard design cap ("the 25-entity budget, the one-screen
## arena and the friendly-fire social loop are all balanced around exactly two
## thumbs"), so "not the victim" identifies the attacker with no guessing. If that
## cap ever rises this MUST return null for a party of three or more rather than
## picking one — blaming the wrong teammate is worse than blaming nobody.
static func other_hero(tree: SceneTree, victim: Node) -> Node:
	if tree == null:
		return null
	var live: Array[Node] = []
	for h: Node in tree.get_nodes_in_group(&"hero"):
		if is_hero(h):
			live.append(h)
	if live.size() != 2:
		return null
	for h: Node in live:
		if h != victim:
			return h
	return null


# ══════════════════════════════════════════════════════════════════ internals
## Per-victim rate limit, stored on the node itself — the same shape (and the same
## reasoning) as `Bark._off_cooldown`: a static dictionary keyed by instance id
## would leak one entry per body that ever spawned.
static func _off_cooldown(who: Node) -> bool:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var last: float = float(who.get_meta(&"ff_read_last", -999.0))
	if now - last < READ_COOLDOWN:
		return false
	who.set_meta(&"ff_read_last", now)
	return true


## Bank it on the run record so the summary card can say what the two of you did to
## each other. Guarded: no GameState (headless, the F6 sandbox) is a normal answer.
static func _tally(tree: SceneTree, amount: int) -> void:
	var gs: Node = tree.root.get_node_or_null(^"GameState")
	if gs != null and gs.has_method(&"notify_friendly_fire"):
		gs.call(&"notify_friendly_fire", amount)


## THE THING THAT MAKES IT UNMISTAKABLE. One line, screen-space, gold, gone in a
## second and a half.
static func _toast(tree: SceneTree, amount: int) -> void:
	# `current_scene` is the right home in game (the toast dies with the arena), but it
	# is NULL in a `--script` capture tool and during a scene change — and a read that
	# silently does nothing in the one context built to LOOK at it is a read nobody can
	# review. Fall back to the tree root.
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	if host == null:
		return
	for old: Node in tree.get_nodes_in_group(TOAST_GROUP):
		if is_instance_valid(old):
			old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = TOAST_LAYER
	layer.add_to_group(TOAST_GROUP)
	host.add_child(layer)
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Below the floor banner (y 22) so the two never overlap on a cleared floor.
	lbl.offset_top = 46.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = "FRIENDLY FIRE   −%d" % amount
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", TEAM_TINT)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 0.95))
	lbl.add_theme_constant_override("outline_size", 5)
	layer.add_child(lbl)
	# Runs on the PROCESS clock and ignores time_scale, so a read that lands inside a
	# hit-stop still clears itself instead of hanging on screen.
	var tw: Tween = lbl.create_tween()
	tw.tween_interval(TOAST_HOLD)
	tw.tween_property(lbl, "modulate:a", 0.0, TOAST_FADE)
	tw.tween_callback(layer.queue_free)


## One line over a figure's head, reusing Bark's bubble node.
static func _bubble(who: Node2D, lines: Array[String]) -> void:
	if lines.is_empty():
		return
	var bubble: Node = who.get_node_or_null(NodePath(String(BUBBLE_NAME)))
	if bubble == null:
		var packed: Resource = load(BUBBLE_SCENE)
		if packed == null or not (packed is PackedScene):
			return
		bubble = (packed as PackedScene).instantiate()
		bubble.name = String(BUBBLE_NAME)
		who.add_child(bubble)
		# Bare, for the same reason and by the same rule as `Bark._bubble_for`: a
		# bubble built at runtime on a fighter is a fight bubble, and no fight bubble
		# wears the old box. See that function for why the line is drawn at who
		# BUILT the bubble rather than at the mode.
		if bubble.has_method(&"set_bare"):
			bubble.call(&"set_bare", 9)
	if not bubble.has_method(&"say"):
		return
	# NOT awaited, for the same reason `Bark.say` does not: `SpeechBubble.say` yields
	# a few frames while it shrink-to-fits, and a damage router must never become a
	# coroutine.
	bubble.call(&"say", lines[randi() % lines.size()], BUBBLE_HOLD, 0.0)


static func _sfx(tree: SceneTree) -> void:
	var s: Node = tree.root.get_node_or_null(^"Sfx")
	if s != null and s.has_method(&"play"):
		# A bright, wrong, unmistakably NOT-a-kill sound. Deliberately the parry ding
		# pitched down: the roster has no dedicated team-hit cue, and inventing one is
		# an audio pass, not a code change.
		s.call(&"play", "ding", -2.0, 0.02, 0.62)
