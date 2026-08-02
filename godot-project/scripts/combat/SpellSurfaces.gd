class_name SpellSurfaces
extends RefCounted
## SPELLS DAMAGE THE WORLD, not just the people standing in it.
##
## The maker's note: *"ordinary and the other cool spells should damage whatever
## it's hitting, the surfaces etc, all of that stuff"* — and the repo already agreed
## with them; there is a commit named "docs: record the spell-vs-environment
## requirement as top priority". This file is the mechanism, and it exists for the
## same reason `SpellTargets` does: the behaviour was already implemented, correctly,
## seventeen separate times.
##
## ============================== THE FOURTH SIBLING ==========================
## Slots underneath the three that already split this problem up:
##   * `SpellGeometry` — pure shape maths, sees no world and no targets.
##   * `SpellWorld`    — touches the physics world. Walls, floors, solidity.
##   * `SpellTargets`  — combines both against a list of BODIES. "Who takes the hit?"
##   * `SpellSurfaces` (this file) — the same question asked of the SCENERY.
##
## It is deliberately a thin skin over `SpellTargets` rather than a parallel
## implementation. The selection maths for "what is inside this circle" must not
## fork depending on whether the thing inside it breathes.
##
## ⚠ TRAP 1 — A SECOND PASS, NEVER A SECOND GROUP. This is the single most important
## line in the file, and it is written from a bug that already happened. The obvious
## "fix" is to put crates into the faction-blind `"mortal"` group so the existing
## fighter scan finds them for free. That was tried. Because a crate would then be in
## BOTH `"destructible"` and `"mortal"`, and most spectacles scan both, every crate
## took EVERY HIT TWICE — at double damage, invisibly, with no error anywhere.
## `DestructibleProp` still carries the comment explaining why it stays out of
## `mortal`. So: scenery is found by its own separate pass over `"destructible"`,
## always, and nothing here ever adds a group to anything.
##
## ⚠ TRAP 2 — NEVER READ A SPECTACLE'S TRANSFORM, same as the sibling files. Spell
## spectacles park at the arena origin and draw in world coordinates, so their
## `global_position` is `(0, 0)` and is NOT where the effect is. Every function here
## takes explicit world-space values; `ctx` is a handle used to reach the tree and to
## resolve the caster, never a position.
##
## ⚠ TRAP 3 — `damage_at` IS NOT UNIVERSAL. `DestructibleTerrain`, `BreakablePlatform`
## and `DestructibleFloor` implement it and use the direction to throw their debris
## the right way; `DestructibleProp` (the crate) implements only `take_damage`. So
## every call here is duck-typed with a fallback, exactly as the existing hand-rolled
## passes are. Do not "simplify" this to a bare `damage_at` — crates would silently
## stop breaking.
##
## ⚠ CO-OP AUTHORITY IS NOT THIS FILE'S BUSINESS AND MUST NOT BECOME IT.
## `DestructibleProp.take_damage` already routes through `Net`: a client applies a
## predicted hit floored at 1 hp and the host broadcasts the verdict. That guard sits
## behind the same entry point everything else calls, so calling it from here inherits
## it for free. Adding an authority check up here would double-guard the crate and
## leave the other three destructibles — which have no guard at all — still unguarded.


## Damage every destructible inside `radius` of `center`.
##
## `require_los` defaults TRUE for the same reason it does on `SpellTargets`: the safe
## behaviour must be the one you get by not thinking about it. A blast should not
## shatter a crate through the floor of the room below any more than it should kill
## the person standing next to it.
##
## Returns how many were hit, so a caller can drive a "something broke" beat without
## re-querying. Ignore it freely.
static func in_radius(ctx: Node, center: Vector2, radius: float, damage: int,
		require_los: bool = true) -> int:
	if ctx == null or not ctx.is_inside_tree() or damage <= 0:
		return 0
	var hit: int = 0
	for prop: Node in SpellTargets.in_radius(
			center, radius, ctx.get_tree().get_nodes_in_group(&"destructible"),
			[], ctx, require_los):
		if _hurt(prop, damage, center):
			hit += 1
	return hit


## Damage every destructible within `width` of the segment `from` -> `from + dir*len`.
## The line-shaped counterpart: beams, lances, sweeps, chain corridors.
static func on_line(ctx: Node, from: Vector2, dir: Vector2, length: float,
		width: float, damage: int, require_los: bool = true) -> int:
	if ctx == null or not ctx.is_inside_tree() or damage <= 0:
		return 0
	var hit: int = 0
	for prop: Node in SpellTargets.on_line(
			from, dir, length, width,
			ctx.get_tree().get_nodes_in_group(&"destructible"), [], ctx, require_los):
		if _hurt(prop, damage, from):
			hit += 1
	return hit


## Damage every destructible inside an arbitrary caller-supplied predicate.
##
## THE ESCAPE HATCH, and it earns its place: several spectacles do not have a circle
## or a line to offer. `ZoneSpell` has a per-effect footprint, `ShadowRoot` has a
## vertical catch band, `IceWall` has its own `shatter_contains`. Forcing those into a
## bounding circle would either over-reach or under-reach, and both are worse than
## letting the caller keep the shape it already computes for fighters.
##
## `contains` is called with each candidate's world position and must answer whether
## it is inside. LOS is the caller's business here — the shapes that need this are
## exactly the ones that already ran their own `SpellWorld.filter_reachable`.
static func in_shape(ctx: Node, origin: Vector2, damage: int,
		contains: Callable) -> int:
	if ctx == null or not ctx.is_inside_tree() or damage <= 0 or not contains.is_valid():
		return 0
	var hit: int = 0
	for prop: Node in ctx.get_tree().get_nodes_in_group(&"destructible"):
		if prop is not Node2D or not is_instance_valid(prop):
			continue
		if not bool(contains.call((prop as Node2D).global_position)):
			continue
		if _hurt(prop, damage, origin):
			hit += 1
	return hit


## Damage ONE destructible, directionally, away from `origin`.
##
## Public because two spectacles (chain hops, per-collision bolts) already have the
## node in hand from their own traversal and re-querying would be wrong as well as
## wasteful — a chain that re-scans would re-hit its earlier links.
static func hurt(prop: Node, damage: int, origin: Vector2) -> bool:
	return _hurt(prop, damage, origin)


## Prefer the directional break, fall back to the plain one. See TRAP 3.
static func _hurt(prop: Node, damage: int, origin: Vector2) -> bool:
	if prop == null or not is_instance_valid(prop):
		return false
	if prop is Node2D and prop.has_method("damage_at"):
		var at: Vector2 = (prop as Node2D).global_position
		var away: Vector2 = (at - origin).normalized()
		prop.call("damage_at", damage, at, away if away != Vector2.ZERO else Vector2.UP)
		return true
	if prop.has_method("take_damage"):
		prop.call("take_damage", damage)
		return true
	return false
