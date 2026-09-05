class_name FloorBuilder
extends RefCounted
## Populates a floor's room from data: given a LayoutDef, instances the crates,
## weapon pickups, the floor's SPELL DROP and the machinery around it. Pure
## "data -> children" — no enemy logic, no sequencing. The one arena shell is
## parameterized by this.
##
## THE DROP ECONOMY ENTERS HERE, and this is the only place it touches the floor
## lifecycle. `Arena._rebuild_room` frees every child of the Room and calls
## `build_props` once per floor, which makes this function the exact seam for all
## four of the spec's per-floor rules:
##   * the Tier 2 pickup is placed (or not — see `SpellDrops`, it is a roll);
##   * `BossDropWatcher` is parked, ready to drop a Tier 3 when the guardian falls;
##   * `SpellHandoff` is parked, so players can pass what they find;
##   * every hero's grants are RESTORED, which is the spec's "resets each floor"
##     made literal — you carry your floor number up the tower, not your loot.
##
## ⚠ THE SIGNATURE IS UNCHANGED ON PURPOSE. `Arena.gd` calls `build_props(room,
## layout)` and is owned by another agent, so the floor number is DERIVED here
## (from `GameState`, via the container's tree) rather than added as a parameter.
## The optional third argument exists only for tests and capture tools, which have
## no GameState to ask.

## ⚠ NO `WEAPON_PICKUP_SCENE` PRELOAD ANY MORE. The spawn was removed when a
## hardcoded `"sword"` turned out to be handed to whoever walked over it (see
## `build_props`), but the preload stayed — so every headless suite that so much as
## touched FloorBuilder was still dragging `WeaponPickup.tscn` into its compile
## graph, which is the precise cost the three `## Loaded by PATH` notes below exist
## to avoid. Weapons are chosen at the hub Armory now and nowhere else.
const DESTRUCTIBLE_SCENE: PackedScene = preload("res://scenes/combat/DestructibleProp.tscn")
## Loaded by PATH, not preloaded. `SpellPickup.gd` reaches `Sfx` / `Juice` /
## `CombatVfx`, and a `preload` here would drag all three into the compile graph of
## every headless suite that touches FloorBuilder — where autoloads do not exist.
const SPELL_PICKUP_PATH: String = "res://scenes/combat/SpellPickup.tscn"
## THE SKYLINE, for the same reason as the spell pickup above: loaded by PATH.
## `BreakablePlatform` names `Sfx` / `Juice` / `CombatVfx` / `DebrisChunk` /
## `ScorchDecal`, and a `preload` here would drag all of them into the compile graph
## of every headless suite that so much as touches FloorBuilder — where autoloads do
## not exist.
const RUIN_PLATFORM_PATH: String = "res://scripts/combat/RuinPlatform.gd"
const BREAKABLE_PLATFORM_PATH: String = "res://scripts/combat/BreakablePlatform.gd"
## ⚠ BY PATH, for the same reason as the spell pickup: `HealthPickup.gd` names `Sfx`
## and `CombatVfx`, and a `preload` here would drag both into the compile graph of
## every headless suite that touches FloorBuilder — where autoloads do not exist.
const HEALTH_PICKUP_PATH: String = "res://scenes/combat/HealthPickup.tscn"

## WHERE THE PACKS GO WHEN NOBODY HAS SAID. Fractions of the room, settled onto
## whatever surface is beneath them (same treatment as the floor's spell drop, and
## for the same reason — an anchor in mid-air is a pickup you can see and never
## collect). Two of them, on opposite sides, so healing is never on the same side of
## the room as the fight for both players at once.
##
## ⚠ THIS IS A FALLBACK, NOT A DEFAULT LAYOUT. Every authoring table that produces a
## `LayoutDef` — `GameState.default_layout` / `_elite_layout` / `_boss_layout` and
## `FloorGen.generate_layout` — is owned elsewhere, so none of them can name
## `health_pickups` yet. Shipping the packs behind an empty-array fallback means the
## tower actually HAS healing on the next F5 instead of after a second agent's pass,
## and the moment any floor authors a position this branch stops running for it.
## Delete the `else` branch in `build_health_packs` and the tower goes back to
## authored-only.
const DEFAULT_HEALTH_PACKS: Array[Vector2] = [Vector2(0.18, 0.34), Vector2(0.82, 0.34)]


## Build the floor's props into `container` (typically a fresh Room node that the
## arena frees + rebuilds per floor).
static func build_props(container: Node2D, layout: LayoutDef, floor_index: int = -1) -> void:
	if layout == null:
		return
	build_platforms(container, layout)
	# ⚠ NO SWORDS ON THE FLOOR. Maker: *"there is no need for magic types to wield a
	# sword, the random sword drops and stuff remove"*. Every one of these was a
	# hardcoded `"sword"` handed to whoever walked over it — so an Arcanist, a Cleric
	# or a Cryomancer picked up a blade that its own class card says it does not carry,
	# and `equip_weapon` duly retuned its melee around a weapon the fantasy denies.
	#
	# THE LAYOUT DATA IS LEFT ALONE ON PURPOSE. `layout.weapon_pickups` still carries
	# its positions and `FloorGen` still authors them; only the spawn is gone. Those
	# points are good "something interesting is here" spots and a later drop worth
	# picking up (a spell, a charge, a relic) should reuse them rather than have them
	# re-derived by whoever wants one next.
	pass
	for pos: Vector2 in layout.crate_positions:
		var crate: StaticBody2D = DESTRUCTIBLE_SCENE.instantiate()
		container.add_child(crate)
		crate.global_position = pos
	build_health_packs(container, layout)
	build_drop_economy(container, layout, floor_index)


## THE PACKS. Authored positions win outright; an empty array falls back to
## `DEFAULT_HEALTH_PACKS` (see the note on that constant — an empty array today means
## "unauthored", not "none wanted").
##
## ⚠ THE POSITIONS ARE SETTLED, exactly like the floor's spell drop. A pack authored
## at a raw point can hang in mid-air over a room whose ledges changed, and a health
## pack you can see and cannot reach is worse than no pack at all when the complaint
## being answered is "the game is hard right now".
##
## ⚠ BOTH PEERS BUILD THIS INDEPENDENTLY AND MUST AGREE. That is why the fallback is
## a CONSTANT of room fractions and not a roll: `Net` identifies a pickup across the
## wire by its rounded position (`Net.pos_key`), so two peers deriving the same point
## from the same `LayoutDef` is the entire cross-peer handshake. Nothing random may
## enter this function.
static func build_health_packs(container: Node2D, layout: LayoutDef) -> void:
	if container == null or layout == null:
		return
	var scene: PackedScene = load(HEALTH_PICKUP_PATH) as PackedScene
	if scene == null:
		return
	var points: Array[Vector2] = []
	if not layout.health_pickups.is_empty():
		for pos: Vector2 in layout.health_pickups:
			points.append(settle_onto_surface(layout, pos))
	elif not layout.health_packs_authored:
		# EMPTY AND SILENT — "no opinion", so the floor gets the sensible pair rather
		# than shipping with no healing on it at all. This is the pre-existing branch
		# and every floor authored before `health_packs_authored` existed takes it.
		for frac: Vector2 in DEFAULT_HEALTH_PACKS:
			points.append(_anchor(layout, frac))
	# EMPTY AND AUTHORED — "this floor has none", and it is obeyed literally. The deep
	# ascent (floor 36+) is what asked for it; see `LayoutDef.health_packs_authored`.
	# Falling through with an empty `points` is the whole implementation: the loop
	# below builds nothing, which is exactly what was asked for.
	for pos: Vector2 in points:
		var pack: Area2D = scene.instantiate()
		container.add_child(pack)
		pack.global_position = pos


## THE LEDGES. Turns `LayoutDef.platforms` into real bodies — permanent
## `RuinPlatform`s and amber-rimmed `BreakablePlatform`s (which shatter and re-form).
## Both are `StaticBody2D`s that already carry the "destructible" damage contract and
## have existed since VersusArena; until now nothing in the tower ever built one, so
## the arena was a bare box and `Enemy`'s leap system had nothing to leap onto.
##
## `platform_size` is set BEFORE `add_child` because both scripts build their
## collider in `_ready`, which runs on entering the tree — setting it afterwards
## would leave every ledge at its default size with a mismatched collider.
static func build_platforms(container: Node2D, layout: LayoutDef) -> void:
	if layout == null:
		return
	for p: Dictionary in layout.platforms:
		var breakable: bool = bool(p.get("breakable", false))
		var gs: GDScript = load(BREAKABLE_PLATFORM_PATH if breakable else RUIN_PLATFORM_PATH) as GDScript
		if gs == null:
			continue
		var node: StaticBody2D = gs.new() as StaticBody2D
		if node == null:
			continue
		node.set(&"platform_size", Vector2(
			float(p.get("w", 190.0)), float(p.get("h", 24.0))))
		if breakable:
			if p.has("hp"):
				node.set(&"max_hp", int(p["hp"]))
			if p.has("regen"):
				node.set(&"regen_time", float(p["regen"]))
		container.add_child(node)
		node.global_position = Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
		# ⚠ NO LONGER OVERRIDDEN. This used to force every tower ledge to z -1,
		# because the arena's `Floor` ColorRect covered the room at -2 and a ledge at
		# its own -4 was drawn behind it. That made the tower a second, contradictory
		# z scheme. `Arena._apply_room_size` now parks the wash at
		# `StageLayers.BACKDROP`, so a ledge's own `StageLayers.PLATFORM` is correct
		# here and on the versus stage alike. The assert-by-test lives in
		# `tools/slice_test_stage_layers.gd`.


## The per-floor drop machinery. Split out from `build_props` so a test or a
## capture tool can stage it alone, and so the prop loop above stays the one-screen
## function it has always been.
static func build_drop_economy(container: Node2D, layout: LayoutDef,
		floor_index: int = -1) -> void:
	if container == null or not container.is_inside_tree():
		return
	var floor_no: int = _resolve_floor(container, floor_index)
	_restore_grants(container)
	_place_floor_drop(container, layout, floor_no)
	var watcher: Node2D = BossDropWatcher.new()
	watcher.name = "BossDropWatcher"
	watcher.floor_index = floor_no
	container.add_child(watcher)
	# Centred so its own `global_position` is a sane fallback drop point for a
	# guardian that somehow died without a body to ask.
	watcher.global_position = _anchor(layout, SpellDrops.BOSS_ANCHOR)
	var handoff: Node2D = SpellHandoff.new()
	handoff.name = "SpellHandoff"
	container.add_child(handoff)


## PROGRESSION RESETS EACH FLOOR. Every hero gets its class kit back at the top of
## the floor, so the Tier 1 -> Tier 2 -> Tier 3 arc happens INSIDE a floor and
## never stacks across them. Without this the spec's escalation becomes a
## stockpile, and by floor five everyone is holding two Tier 3s.
static func _restore_grants(container: Node2D) -> void:
	for h: Node in container.get_tree().get_nodes_in_group("hero"):
		SpellGrant.restore_all(h)


static func _place_floor_drop(container: Node2D, layout: LayoutDef, floor_no: int) -> void:
	var id: String = SpellDrops.roll_floor_drop(floor_no)
	if id == "":
		return   # most floors have nothing. That is what makes the rest matter.
	var pickup: Area2D = (load(SPELL_PICKUP_PATH) as PackedScene).instantiate()
	container.add_child(pickup)
	pickup.global_position = _anchor(layout, SpellDrops.DROP_ANCHOR)
	pickup.call(&"set_spell", id)


## A fraction of the room resolved to a world point, then SETTLED onto the surface
## under it.
##
## ⚠ THE SETTLE IS NOT COSMETIC. `SpellDrops.DROP_ANCHOR` is (0.72, 0.42), which in a
## 960x440 room is 247px above the floor — a Tier 2 spell hanging in mid-air, well
## past a 112px jump, i.e. a drop the player can see and never collect. That was
## survivable while every floor was the same bare box and could be eyeballed once;
## with generated floors it becomes a roll-dependent lottery. So the anchor now falls
## onto whatever is beneath it — a ledge if one is there, the ground otherwise — and
## because `FloorGen` guarantees every ledge is reachable from the ground, a settled
## drop is always collectable.
static func _anchor(layout: LayoutDef, frac: Vector2) -> Vector2:
	var size: Vector2 = layout.room_size if layout != null else Vector2(960.0, 480.0)
	return settle_onto_surface(layout, Vector2(size.x * frac.x, size.y * frac.y))


## Drop `pt` straight down onto the nearest standing surface below it (a ledge top,
## else the floor) and float it `clearance` above that surface. Pure — headless-tested.
static func settle_onto_surface(layout: LayoutDef, pt: Vector2,
		clearance: float = 26.0) -> Vector2:
	var size: Vector2 = layout.room_size if layout != null else Vector2(960.0, 480.0)
	# Arena.WALL_THICKNESS is 16 and the bottom wall is centred on y = room_h, so the
	# standable floor is half a thickness above it.
	var best: float = size.y - 8.0
	if layout != null:
		for p: Dictionary in layout.platforms:
			var px: float = float(p.get("x", 0.0))
			var pw: float = float(p.get("w", 0.0))
			if pt.x < px - pw * 0.5 or pt.x > px + pw * 0.5:
				continue
			var surface: float = float(p.get("y", 0.0)) - float(p.get("h", 24.0)) * 0.5
			# The HIGHEST surface that is still BELOW the anchor.
			if surface >= pt.y and surface < best:
				best = surface
	return Vector2(pt.x, best - clearance)


## The floor number for the seeded roll: the explicit override, else GameState, else
## 1. A sandbox arena with no GameState still rolls a floor-1 table rather than
## silently never dropping anything, which would be indistinguishable from the
## feature being broken.
static func _resolve_floor(container: Node2D, floor_index: int) -> int:
	if floor_index >= 0:
		return floor_index
	var gs: Node = container.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method(&"current_floor"):
		return int(gs.call(&"current_floor"))
	return 1
