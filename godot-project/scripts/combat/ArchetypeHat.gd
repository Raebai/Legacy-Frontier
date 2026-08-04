extends Node2D
## ══ TELL THE MOBS APART BY THEIR HEADS ═══════════════════════════════════════
## Maker, playtesting: the mobs want visual differentiation *"by the hats they are
## wearing or something like that"*.
##
## The roster already differs by TINT (Enemy.ARCHETYPE_DEFAULTS) and by held WEAPON
## (Enemy.ARCHETYPE_GEAR), and neither survives the moment that matters. Tint dies
## the instant a body is flashing white from a hit, backlit by a nova, or standing
## in front of a floor washed in its own theme colour; a held prop is a few pixels
## wide and is swinging. A HAT is a change to the SILHOUETTE — the outline of the
## thing, at the top of it, where the eye already goes — so it reads at 640x360, in
## a crowd, mid-hitstop, in monochrome.
##
## ── WHY THIS IS NOT `rig.set_equipment("head", ...)` ─────────────────────────
## CharacterRig HAS a head-gear system ("hat"/"hood"/"helmet"/"crown") and it is
## switched OFF: `draw_clothing` defaults false on the maker's twice-repeated
## instruction — *"the characters are not stickmen, I just want to see STICKMEN"*.
## Flipping that flag to get four hats would also put robes, armour and sandals back
## on every figure in the game, which is the opposite of what they asked for twice.
##
## So this is a separate, additive thing: no robe, no armour, no boots — a hat, on an
## enemy, and nothing else. It also gets EIGHT distinct silhouettes rather than the
## registry's four, which is what an eight-archetype roster actually needs.
##
## ── HOW IT COSTS NOTHING ─────────────────────────────────────────────────────
## It is a child of the RIG, not of the enemy. That means the flip from
## `set_facing`, the floating-capsule ride and the body pitch all arrive for free
## through the parent transform — there is no `_process`, no per-frame sync, and no
## second copy of the rig's posture maths to drift out of step (the failure mode
## `Enemy._sync_body_offset` exists to patch for the hurtbox, avoided here by
## parenting instead of by chasing). Drawing is a handful of polygon calls behind
## `queue_redraw`-on-change only.
##
## ⚠ THE HEAD GEOMETRY IS DERIVED FROM THE RIG, NOT RE-TYPED. `HEAD_R_FACTOR` below
## mirrors `Enemy.RIG_HEAD_R_FACTOR`, which itself mirrors the rig's own head maths.
## If the drawn head ever moves or changes size, the hat must move with it or it
## floats off the skull — the same class of bug as a hitbox left where the art used
## to be. There is exactly one number here and this comment is why.

## Mirrors Enemy.RIG_HEAD_R_FACTOR (which mirrors CharacterRig's head radius).
const HEAD_R_FACTOR: float = 0.105
## Keyline weight as a fraction of the head radius — matches the weight the rig
## gives its own head outline closely enough to read as one drawing.
const LINE_W: float = 0.42
## The dark keyline every piece of this game's line art carries.
const KEYLINE: Color = Color(0.06, 0.05, 0.07, 0.95)

## Enemy.Archetype id. -1 = draw nothing.
var archetype: int = -1
## The hat's own colour. Set from the body's tint, lifted toward white so the hat
## reads as a SEPARATE object sitting on the head rather than as more head.
var hat_color: Color = Color(0.9, 0.9, 0.95)


func configure(kind: int, body_tint: Color) -> void:
	archetype = kind
	# Lift toward white but keep the hue: the archetype's colour is still the first
	# thing you read, the hat just has to separate from the skull under it.
	hat_color = body_tint.lerp(Color(1, 1, 1), 0.45)
	queue_redraw()


## The drawn head's centre and radius, in the RIG's local space — which is this
## node's space, because it is parented to the rig.
func _head() -> Dictionary:
	var parent := get_parent()
	if parent == null or not (parent is Node2D):
		return {}
	var h: float = float(parent.get(&"height")) if parent.get(&"height") != null else 31.0
	var r: float = h * HEAD_R_FACTOR
	return {"c": Vector2(0.0, -h * 0.5 + r), "r": r}


func _draw() -> void:
	if archetype < 0:
		return
	var head: Dictionary = _head()
	if head.is_empty():
		return
	var c: Vector2 = head["c"]
	var r: float = float(head["r"])
	# Every shape is authored in units of the head radius, so a 1.9x sparring dummy
	# and a 0.45x mini-guardian both get a hat that fits without a second scale knob.
	match archetype:
		1: _helm_horned(c, r)      # BRUTE — the heavy. Widest silhouette in the roster.
		2: _hat_pointed(c, r, 2.1, 1.5)   # CASTER — the classic wizard cone.
		3: _helm_crested(c, r)     # CHARGER — a fin, like a thing that runs at you.
		4: _antlers(c, r)          # SUMMONER — forked, "calls things in".
		5: _hood(c, r)             # ASSASSIN — swept-back cowl, low and quiet.
		6: _fuse(c, r)             # BOMBER — a lit fuse. It IS the bomb.
		7: _hat_pointed(c, r, 2.6, 2.2)   # MAGE — taller cone, much wider brim.
		_: pass                    # CHASER — bare. The baseline you compare to.


# ─────────────────────────────────────────────────────────────────── the shapes
## Filled polygon + keyline, in one place so all eight read as the same hand.
func _piece(pts: PackedVector2Array, r: float, close: bool = true) -> void:
	draw_colored_polygon(pts, hat_color)
	var outline: PackedVector2Array = pts.duplicate()
	if close and outline.size() > 1:
		outline.append(outline[0])
	draw_polyline(outline, KEYLINE, r * LINE_W)


## A dome over the top of the skull with a horn out of each side.
func _helm_horned(c: Vector2, r: float) -> void:
	_piece(PackedVector2Array([
		c + Vector2(-r * 1.15, 0.0), c + Vector2(-r * 1.0, -r * 0.9),
		c + Vector2(0.0, -r * 1.25), c + Vector2(r * 1.0, -r * 0.9),
		c + Vector2(r * 1.15, 0.0),
	]), r)
	for side: float in [-1.0, 1.0]:
		_piece(PackedVector2Array([
			c + Vector2(side * r * 0.95, -r * 0.35),
			c + Vector2(side * r * 2.1, -r * 1.15),
			c + Vector2(side * r * 1.05, -r * 0.1),
		]), r)


## A cone with a brim. `tall` and `wide` are in head radii — the caster gets a neat
## one, the mage an absurd one, and that difference is the read between them.
func _hat_pointed(c: Vector2, r: float, tall: float, wide: float) -> void:
	_piece(PackedVector2Array([
		c + Vector2(-r * wide, -r * 0.7), c + Vector2(r * wide, -r * 0.7),
		c + Vector2(r * wide * 0.55, -r * 0.95), c + Vector2(-r * wide * 0.55, -r * 0.95),
	]), r)   # the brim
	_piece(PackedVector2Array([
		c + Vector2(-r * 0.95, -r * 0.85),
		# The tip leans back, so a pointed hat still has a FRONT and the figure's
		# facing stays readable when it is standing still.
		c + Vector2(-r * 0.55, -r * tall),
		c + Vector2(r * 0.95, -r * 0.85),
	]), r)


## A low band with a tall fin along the midline.
func _helm_crested(c: Vector2, r: float) -> void:
	_piece(PackedVector2Array([
		c + Vector2(-r * 1.1, -r * 0.15), c + Vector2(-r * 1.1, -r * 0.75),
		c + Vector2(r * 1.1, -r * 0.75), c + Vector2(r * 1.1, -r * 0.15),
	]), r)
	_piece(PackedVector2Array([
		c + Vector2(-r * 0.8, -r * 0.75), c + Vector2(-r * 0.2, -r * 1.9),
		c + Vector2(r * 0.7, -r * 1.75), c + Vector2(r * 0.75, -r * 0.75),
	]), r)


## Two forked prongs. Open shapes, so they read as antlers rather than as a hat.
func _antlers(c: Vector2, r: float) -> void:
	for side: float in [-1.0, 1.0]:
		var base: Vector2 = c + Vector2(side * r * 0.55, -r * 0.75)
		var mid: Vector2 = c + Vector2(side * r * 1.25, -r * 1.7)
		draw_polyline(PackedVector2Array([base, mid, c + Vector2(side * r * 1.15, -r * 2.5)]),
			KEYLINE, r * LINE_W * 2.4)
		draw_polyline(PackedVector2Array([base, mid, c + Vector2(side * r * 1.15, -r * 2.5)]),
			hat_color, r * LINE_W * 1.3)
		draw_line(mid, c + Vector2(side * r * 2.2, -r * 2.0), KEYLINE, r * LINE_W * 2.0)
		draw_line(mid, c + Vector2(side * r * 2.2, -r * 2.0), hat_color, r * LINE_W)


## A cowl: covers the top and back of the skull and sweeps into a point behind.
func _hood(c: Vector2, r: float) -> void:
	_piece(PackedVector2Array([
		c + Vector2(r * 0.9, r * 0.15), c + Vector2(r * 0.75, -r * 1.0),
		c + Vector2(0.0, -r * 1.45), c + Vector2(-r * 1.2, -r * 1.1),
		c + Vector2(-r * 2.0, -r * 0.15), c + Vector2(-r * 1.0, r * 0.3),
	]), r)


## A stub of fuse with a spark on the end. No hat at all — which is itself the read:
## the bomber is the one carrying the thing that is about to go off.
func _fuse(c: Vector2, r: float) -> void:
	var top: Vector2 = c + Vector2(0.0, -r * 1.05)
	draw_line(top, top + Vector2(r * 0.5, -r * 1.1), KEYLINE, r * LINE_W * 2.2)
	draw_line(top, top + Vector2(r * 0.5, -r * 1.1), hat_color, r * LINE_W * 1.1)
	var spark: Vector2 = top + Vector2(r * 0.5, -r * 1.1)
	draw_circle(spark, r * 0.55, KEYLINE)
	draw_circle(spark, r * 0.36, Color(1.0, 0.82, 0.3))
