class_name SimArena
extends Node2D
## The stage both bot tools fight on — the simulation (`tools/bot_sim.gd`) and the
## clip capture (`tools/bot_clip_capture.gd`) build the SAME arena, so a bug the
## sim finds can be replayed on camera without the geometry changing underneath.
##
## Built entirely in code, no .tscn — the `Arena.gd` / `FloorBuilder` /
## `VersusArena.gd` programmatic-stage idiom this codebase already uses.
##
## ⚠ DELIBERATELY UNWALLED AT THE SIDES. `VersusArena` rings the platform with
## PIT hazards; this one does not, and that is the point: the sim's
## "a body left the world" check needs escapes to be POSSIBLE in order to detect
## them. A stage that physically cannot be left would silently pass that check
## forever. The floor is wide enough that normal play never reaches an edge, so
## anything that does get out got there by being launched or by tunnelling —
## which is exactly the class of bug worth a row.
##
## ⚠ EVERY GAME SCRIPT IS load()ed AT RUNTIME, never preloaded. Their scripts
## touch autoload globals (Sfx / Rank / Juice) at parse time, and those only
## register once the main loop is live; a preload here would compile them too
## early and fail the whole dependency chain. This is the same trap documented in
## `VersusArena._spawn_fighters` and `tools/slice1_test_weapon.gd`.

const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"
const ENEMY_SCENE: String = "res://scenes/combat/Enemy.tscn"
const DESTRUCTIBLE_SCRIPT: String = "res://scripts/combat/DestructibleTerrain.gd"

## Stage geometry. Wide and flat on purpose: the harness is measuring COMBAT, and
## a fancy landscape would turn "the bot never reached its opponent" into a level
## design question instead of a bot question.
const FLOOR_Y: float = 700.0
const FLOOR_X0: float = -900.0
const FLOOR_X1: float = 900.0
const FLOOR_DEPTH: float = 400.0
## Two blocks of real, chewable cover so spell-vs-terrain gets exercised every run
## (spells passing through terrain has been the biggest bug class this month).
const COVER_X: Array[float] = [-260.0, 260.0]

## Slack added to the floor span before a body counts as having escaped. Generous
## enough that a big legitimate knockback is not a false positive.
const BOUNDS_SLACK_X: float = 500.0
const BOUNDS_SLACK_UP: float = 1200.0
const BOUNDS_SLACK_DOWN: float = 300.0


## The rect a fighter is allowed to be inside. Anything outside is a row.
static func bounds() -> Rect2:
	return Rect2(
		Vector2(FLOOR_X0 - BOUNDS_SLACK_X, -BOUNDS_SLACK_UP),
		Vector2((FLOOR_X1 - FLOOR_X0) + BOUNDS_SLACK_X * 2.0,
			(FLOOR_Y + BOUNDS_SLACK_DOWN) + BOUNDS_SLACK_UP)
	)


func _ready() -> void:
	_build_floor()
	_build_cover()


## One solid slab. The TOP edge sits exactly on FLOOR_Y and the box grows down, so
## nothing clips under it and `below_floor` means what it says.
func _build_floor() -> void:
	var body := StaticBody2D.new()
	var width: float = FLOOR_X1 - FLOOR_X0
	body.position = Vector2((FLOOR_X0 + FLOOR_X1) * 0.5, FLOOR_Y + FLOOR_DEPTH * 0.5)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, FLOOR_DEPTH)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	# A visual only the capture tool cares about; free in the headless sim.
	var slab := ColorRect.new()
	slab.color = Color(0.17, 0.19, 0.24, 1.0)
	slab.position = Vector2(FLOOR_X0, FLOOR_Y)
	slab.size = Vector2(width, FLOOR_DEPTH)
	slab.z_index = -5
	slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slab)


func _build_cover() -> void:
	var script: GDScript = load(DESTRUCTIBLE_SCRIPT) as GDScript
	if script == null:
		return    # cover is a nice-to-have; a missing script must not sink the run
	for x: float in COVER_X:
		var block: Node2D = script.new()
		add_child(block)
		block.position = Vector2(x, FLOOR_Y - 32.0)


## Spawn a hero of `class_id` standing on the floor at `x`.
##
## The Camera2D that ships inside `Hero.tscn` is DISABLED here, mirroring what
## `Hero._setup_net_role` does for a co-op puppet. Two heroes each carrying a live
## camera would fight over the viewport, and in the clip capture the framing must
## belong to the harness, not to whichever fighter spawned last.
func spawn_hero(class_id: int, x: float, keep_camera: bool = false) -> CharacterBody2D:
	var scene: PackedScene = load(HERO_SCENE) as PackedScene
	var hero: CharacterBody2D = scene.instantiate()
	hero.position = Vector2(x, FLOOR_Y - 40.0)
	add_child(hero)
	if not keep_camera:
		for child: Node in hero.get_children():
			if child is Camera2D:
				(child as Camera2D).enabled = false
	if hero.has_method("configure_class"):
		hero.configure_class(class_id)
	return hero


## Spawn one of the tower's own AI enemies. Used by the `vs_enemy` mode, which is
## the harness's fallback while hero-vs-hero damage routing is still group-hard-
## wired — an Enemy damages a hero and takes damage from one TODAY, so it is the
## only pairing that produces real signal until the faction seam lands.
func spawn_enemy(archetype: int, x: float, hp: int = 90) -> CharacterBody2D:
	var scene: PackedScene = load(ENEMY_SCENE) as PackedScene
	var bot: CharacterBody2D = scene.instantiate()
	bot.archetype = archetype   # BEFORE add_child: Enemy._ready reads it
	bot.max_hp = hp             # BEFORE add_child: _ready seeds hp = max_hp
	bot.position = Vector2(x, FLOOR_Y - 40.0)
	add_child(bot)
	return bot
