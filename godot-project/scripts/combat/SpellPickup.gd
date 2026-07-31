class_name SpellPickup
extends Area2D
## A SPELL LYING ON THE FLOOR. Walk over it and it goes into your hand, taking a
## seat from what you were carrying.
##
## ══ IT HAS TO BE SEEN, FROM ACROSS A 640x360 SCREEN, MID-FIGHT ═════════════════
## The spec asks for pickups that are "visible and contested. Both players can race
## for them", and a race needs a finish line both players can see from where they
## are standing. That is a harder requirement than it sounds on a phone screen full
## of spell effects, so this draws FOUR things rather than one, each solving a
## different failure of the last:
##   1. A BEACON — a tall column of light. The only element that survives being off
##      the bottom of a busy frame, and the one that says "over there" before you
##      can read anything else.
##   2. A DISC + HALO in the spell's own element colour, pulsing. What says "this is
##      a pickup" rather than a spell effect somebody left running.
##   3. THE NAME, drawn in text above it. Nothing else can answer "is that worth
##      crossing the room for". Text is expensive to read mid-fight, which is
##      exactly why it is the third layer and not the first.
##   4. A TIER CROWN — three rotating shards for a Tier 3 and one ring for a Tier 2.
##      Shelf at a glance, from further away than the name can be read.
##
## ══ CO-OP, HONESTLY ════════════════════════════════════════════════════════════
## Both peers spawn this from the same seeded roll (`SpellDrops`) so it is the same
## spell in the same place on both screens with no message passing. COLLECTION is
## resolved locally: whoever touches it first on THIS peer takes it. Hero positions
## are replicated, so the two peers agree in almost every case — but a genuine
## photo-finish can be scored differently on each screen, and there is no way to
## close that from inside this file. `collect_by(hero)` is public precisely so the
## networking layer can drive it from one authoritative decision when it is ready.
## Flagged in the handoff rather than papered over.

## Which spell this is. An ID and not a SpellDef, because a Resource sitting on a
## scene is shared mutable state between every hero who ever touches it — the
## SpellDef is minted fresh at the moment of collection.
@export var spell_id: String = ""

## Beacon height in px. Tall enough to be seen over the arena's terrain from the
## far side of the room. UNTESTED VISUAL GUESS.
const BEACON_HEIGHT: float = 190.0
const DISC_RADIUS: float = 13.0
const HALO_RADIUS: float = 26.0
const LABEL_LIFT: float = 46.0
const BOB: float = 5.0
## Tier 3 pickups are physically bigger and gold-crowned. The shelf has to read
## before the name does.
const TIER3_SCALE: float = 1.45
const TIER3_GOLD: Color = Color(1.5, 1.15, 0.45)

var _phase: float = 0.0
var _consumed: bool = false
var _spell: SpellDef = null
var _color: Color = Color(0.8, 0.7, 1.0)
var _tier3: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_resolve()


## Resolve the id into a def + palette. Called from `_ready` and again if `spell_id`
## is written after the node is in the tree (which `FloorBuilder` does).
func _resolve() -> void:
	_spell = SpellDrops.spell_for_id(spell_id)
	if _spell == null:
		return
	_tier3 = _spell.kind == SpellDef.Kind.CATACLYSM
	_color = _spell.resolve_color(Color(0.8, 0.7, 1.0))
	queue_redraw()


## Set the spell after instantiation. Separate from the export so `FloorBuilder`
## has one call that also refreshes the palette — writing `spell_id` alone on a node
## already in the tree would leave it drawing the wrong colour forever.
func set_spell(id: String) -> void:
	spell_id = id
	if is_inside_tree():
		_resolve()


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _consumed or _spell == null:
		return
	if not body.is_in_group("hero"):
		return
	collect_by(body)


## PUBLIC so the networking layer can drive collection from one authoritative
## decision rather than from two independent overlap tests. Idempotent: a second
## call after the pickup is spent does nothing.
func collect_by(hero: Node) -> bool:
	if _consumed or _spell == null or hero == null or not is_instance_valid(hero):
		return false
	# Minted fresh per collection — see `spell_id`'s note. Two heroes taking two
	# copies of the same drop must not share one Resource.
	var mine: SpellDef = SpellDrops.spell_for_id(spell_id)
	if mine == null or SpellGrant.apply(hero, mine) < 0:
		return false
	_consumed = true
	var at: Vector2 = global_position
	CombatVfx.spawn_burst(get_parent(), at, Color(_color.r * 1.6, _color.g * 1.6, _color.b * 1.6, 1.0),
		Color(_color.r, _color.g, _color.b, 0.0), 22, 0.5, 60.0, 210.0, 1.2, 3.4, 0.0, 0.0, true)
	SpellDrops.sfx("ding" if not _tier3 else "charge_ult", -3.0, 0.05)
	Juice.on_hit({"shake": 6.0 if not _tier3 else 14.0, "zoom": 0.06 if not _tier3 else 0.14,
		"sfx": "none", "hitstop": 0.0 if not _tier3 else 0.06})
	queue_free()
	return true


func _draw() -> void:
	if _spell == null:
		# A pickup whose id resolved to nothing still draws SOMETHING. A silently
		# invisible pickup is indistinguishable from a floor with no pickup, which
		# is the one failure that would never get reported.
		draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.2, 0.6, 0.8), false, 2.0, true)
		return
	var s: float = TIER3_SCALE if _tier3 else 1.0
	var bob: Vector2 = Vector2(0.0, sin(_phase * 2.2) * BOB)
	var pulse: float = 0.5 + 0.5 * sin(_phase * 3.4)
	_draw_beacon(s, pulse)
	_draw_disc(bob, s, pulse)
	_draw_crown(bob, s)
	_draw_name(bob, s)


## 1. THE BEACON. Drawn from the ground UP so it reads even when the disc itself is
## behind a crate — the thing that says "there is something here" from the far side
## of the room.
func _draw_beacon(s: float, pulse: float) -> void:
	var col: Color = TIER3_GOLD if _tier3 else _color
	var h: float = BEACON_HEIGHT * s
	# Three stacked bands rather than one gradient: `draw_line` has no gradient, and
	# three widths reads as a soft column instead of a hard bar.
	draw_line(Vector2.ZERO, Vector2(0.0, -h),
		Color(col.r, col.g, col.b, 0.05 + 0.05 * pulse), 26.0 * s, true)
	draw_line(Vector2.ZERO, Vector2(0.0, -h * 0.8),
		Color(col.r, col.g, col.b, 0.10 + 0.08 * pulse), 12.0 * s, true)
	draw_line(Vector2.ZERO, Vector2(0.0, -h * 0.55),
		Color(col.r, col.g, col.b, 0.22 + 0.15 * pulse), 4.0 * s, true)
	# A ground ring so the beacon has a footprint and does not look like it is
	# hanging in the air.
	draw_arc(Vector2.ZERO, HALO_RADIUS * s * (0.9 + 0.12 * pulse), 0.0, TAU, 32,
		Color(col.r, col.g, col.b, 0.4), 1.8, true)


## 2. THE DISC. The spell itself, bobbing.
func _draw_disc(bob: Vector2, s: float, pulse: float) -> void:
	var at: Vector2 = bob + Vector2(0.0, -HALO_RADIUS * s)
	draw_circle(at, HALO_RADIUS * s * (0.8 + 0.15 * pulse),
		Color(_color.r, _color.g, _color.b, 0.16), true, -1.0, true)
	draw_circle(at, DISC_RADIUS * s, Color(_color.r * 1.4, _color.g * 1.4, _color.b * 1.4, 0.9),
		true, -1.0, true)
	draw_arc(at, DISC_RADIUS * s + 3.0, 0.0, TAU, 28,
		Color(1.6, 1.6, 1.8, 0.55 + 0.3 * pulse), 1.6, true)


## 3. THE CROWN. Shelf at a glance: one thin ring for a Tier 2, three orbiting gold
## shards for a Tier 3. Rotation is what makes the Tier 3 impossible to mistake for
## a Tier 2 in peripheral vision.
func _draw_crown(bob: Vector2, s: float) -> void:
	var at: Vector2 = bob + Vector2(0.0, -HALO_RADIUS * s)
	if not _tier3:
		draw_arc(at, DISC_RADIUS * s + 9.0, 0.0, TAU, 30,
			Color(_color.r, _color.g, _color.b, 0.5), 1.2, true)
		return
	for i: int in 3:
		var ang: float = _phase * 1.6 + TAU * float(i) / 3.0
		var p: Vector2 = at + Vector2.RIGHT.rotated(ang) * (DISC_RADIUS * s + 13.0)
		draw_line(p, p + Vector2.RIGHT.rotated(ang + PI * 0.5) * 7.0,
			Color(TIER3_GOLD.r, TIER3_GOLD.g, TIER3_GOLD.b, 0.95), 2.4, true)
	draw_arc(at, DISC_RADIUS * s + 13.0, 0.0, TAU, 36,
		Color(TIER3_GOLD.r, TIER3_GOLD.g, TIER3_GOLD.b, 0.4), 1.2, true)


## 4. THE NAME. `ThemeDB.fallback_font` rather than a theme resource: this node is
## instanced by `FloorBuilder` into a bare arena with no theme in scope, and a null
## font here would abort `_draw` and take the beacon down with it.
func _draw_name(bob: Vector2, s: float) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var label: String = _spell.display_name
	var size: int = 11 if not _tier3 else 13
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var at: Vector2 = bob + Vector2(-w * 0.5, -HALO_RADIUS * s - LABEL_LIFT)
	# Drawn twice, dark then light. A single pass vanishes over the arena's own
	# floor tint at half the palettes in the tower.
	draw_string(font, at + Vector2(1.0, 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		size, Color(0.0, 0.0, 0.0, 0.75))
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size,
		TIER3_GOLD if _tier3 else Color(1.0, 1.0, 1.0, 0.95))
