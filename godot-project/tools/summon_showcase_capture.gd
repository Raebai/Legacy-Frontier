# LOOK AT EVERY SPELL SUMMONING. Fires the eighteen spectacles that gained a
# summoning circle in the magic-circle pass into the real VersusArena and grabs each
# one AT ITS SUMMON BEAT, so the answer to "does every spell now arrive out of a
# circle that reads as that element and that spell" is a picture rather than a claim.
#
#   summon_showcase_a.png  3x3 — placed / ground spells: the two walls, the pillar,
#                          the nova, the field, the root, plus three projected ones.
#   summon_showcase_b.png  3x3 — the mobility, melee and shadow set.
#
# ⚠ THESE SPECTACLES ARE BUILT WITHOUT A HERO CASTING THEM, which is the casterless
# path — no wind-up sigil is on offer, so every circle here is the FRESH one
# `MagicCircle.adopt_or_open` falls back to. That is deliberate and is half the test:
# adoption must be optional, so the fallback has to look right on its own. The
# hand-off (circle descends from the caster's hand into the muzzle) is what
# tools/cast_windup_capture.gd shows, with a real Hero.
#
# The element and tier ARE stamped here, by hand, exactly the way
# `SpellCaster._stamp` does it — without them every sigil would draw generic runes at
# the middle shelf and the sheet would prove nothing.
#
# GUI binary (must render — captures are black under --headless):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/summon_showcase_capture.gd
# PNGs land in %APPDATA%/Godot/app_userdata/Legacy Frontier/.
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
const CELL: Vector2i = Vector2i(440, 300)
const COLS: int = 3

var _arena: Node2D = null
var _hero: Node2D = null
var _sheet: Image = null
var _cell: int = 0
var _labels: CanvasLayer = null


func _initialize() -> void:
	_arena = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_arena)
	_labels = CanvasLayer.new()
	_labels.layer = 120
	root.add_child(_labels)
	_run()


func _run() -> void:
	for _i: int in 45:
		await process_frame
	_hero = _find_hero()
	if _hero == null:
		printerr("summon_showcase: no hero in the arena — nothing to cast from")
		quit(1)
		return
	_zoom(1.15)

	_sheet = _blank()
	_cell = 0
	await _shot("Rock Wall", 14, func(o: Vector2) -> Node2D:
		return _spawn("RockWall", Elements.Element.EARTH, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.raise_wall(o, Vector2.RIGHT, Elements.color(Elements.Element.EARTH), "earth"))
	)
	await _shot("Ice Wall", 14, func(o: Vector2) -> Node2D:
		return _spawn("IceWall", Elements.Element.ICE, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.raise_wall(o, Vector2.RIGHT, Elements.color(Elements.Element.ICE), "frost"))
	)
	await _shot("Rock Pillar", 12, func(o: Vector2) -> Node2D:
		return _spawn("RockPillar", Elements.Element.EARTH, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.erupt(o + Vector2(120.0, 0.0), Elements.color(Elements.Element.EARTH), 46.0, 40, "earth"))
	)
	await _shot("Energy Nova", 8, func(o: Vector2) -> Node2D:
		var n: Node2D = (load("res://scenes/combat/EnergyNova.tscn") as PackedScene).instantiate()
		_arena.add_child(n)
		n.set("element_id", Elements.Element.ARCANE)
		n.set("spell_tier", SpellTier.Tier.ULT)
		n.call("activate_at", o)
		return n
	)
	await _shot("Blizzard Field", 16, func(o: Vector2) -> Node2D:
		return _spawn("ZoneSpell", Elements.Element.ICE, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.open(o + Vector2(140.0, 0.0), Elements.color(Elements.Element.ICE), 110.0, 6, "frost", 4.5))
	)
	await _shot("Shadow Root", 12, func(o: Vector2) -> Node2D:
		return _spawn("ShadowRoot", Elements.Element.SHADOW, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.erupt(o, Vector2(260.0, 0.0), Elements.color(Elements.Element.SHADOW), 80.0, 30, "shadow"))
	)
	await _shot("Rune Orbs", 10, func(o: Vector2) -> Node2D:
		return _spawn("RuneOrbs", Elements.Element.ARCANE, SpellTier.Tier.QUICK,
			func(n: Node2D) -> void: n.launch(o, Vector2.RIGHT, Elements.color(Elements.Element.ARCANE), 5, 24, "arcane"))
	)
	await _shot("Chain Bolt", 6, func(o: Vector2) -> Node2D:
		return _spawn("ChainBolt", Elements.Element.LIGHTNING, SpellTier.Tier.QUICK,
			func(n: Node2D) -> void: n.chain(o, Vector2.RIGHT, Elements.color(Elements.Element.LIGHTNING), 4, 260.0, 44, "lightning"))
	)
	await _shot("Boulder Hurl", 10, func(o: Vector2) -> Node2D:
		return _spawn("BoulderHurl", Elements.Element.EARTH, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.hurl(o, Vector2.RIGHT, Elements.color(Elements.Element.EARTH), 60.0, 40, "earth"))
	)
	_save("user://summon_showcase_a.png")

	_sheet = _blank()
	_cell = 0
	await _shot("Lightning Rush", 8, func(o: Vector2) -> Node2D:
		return _spawn("LightningRush", Elements.Element.LIGHTNING, SpellTier.Tier.ULT,
			func(n: Node2D) -> void: n.rush(o, Vector2.RIGHT, Elements.color(Elements.Element.LIGHTNING), 560.0, 26.0, 62, "lightning"))
	)
	await _shot("Blade Flurry", 8, func(o: Vector2) -> Node2D:
		return _spawn("BladeFlurry", Elements.Element.SHADOW, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.flurry(o, Vector2.RIGHT, Elements.color(Elements.Element.SHADOW), 18, 5, "shadow"))
	)
	await _shot("Horizon Arc", 10, func(o: Vector2) -> Node2D:
		return _spawn("HorizonArc", Elements.Element.ARCANE, SpellTier.Tier.ULT,
			func(n: Node2D) -> void: n.sweep(o, Vector2.RIGHT, Elements.color(Elements.Element.ARCANE), 520.0, 22.0, 60.0, 120.0, 110, "arcane"))
	)
	await _shot("Shadow Crawler", 10, func(o: Vector2) -> Node2D:
		return _spawn("ShadowCrawler", Elements.Element.SHADOW, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.crawl(o, Vector2.RIGHT, Elements.color(Elements.Element.SHADOW), 420.0, 40.0, 34, "shadow"))
	)
	await _shot("Rift Dagger", 8, func(o: Vector2) -> Node2D:
		return _spawn("RiftDagger", Elements.Element.SHADOW, SpellTier.Tier.QUICK,
			func(n: Node2D) -> void: n.throw_dagger(_hero, o, Vector2.RIGHT, Elements.color(Elements.Element.SHADOW), 500.0, 60.0, 30, 4.0, 6.0, "shadow"))
	)
	await _shot("Aegis Ward", 14, func(o: Vector2) -> Node2D:
		return _spawn("AegisWard", Elements.Element.HOLY, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.raise_ward(o, Vector2.RIGHT, Elements.color(Elements.Element.HOLY), "holy"))
	)
	await _shot("Ice Spike Line", 10, func(o: Vector2) -> Node2D:
		return _spawn("IceSpikeLine", Elements.Element.ICE, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.erupt(o, Elements.color(Elements.Element.ICE), 210.0, 38, "frost"))
	)
	await _shot("Drain Tether", 10, func(o: Vector2) -> Node2D:
		return _spawn("DrainTether", Elements.Element.SHADOW, SpellTier.Tier.HEAVY,
			func(n: Node2D) -> void: n.tether(o, Vector2.RIGHT, Elements.color(Elements.Element.SHADOW), 10, "shadow", _hero))
	)
	await _shot("Blink Strike", 8, func(o: Vector2) -> Node2D:
		return _spawn("BlinkStrike", Elements.Element.SHADOW, SpellTier.Tier.ULT,
			func(n: Node2D) -> void: n.strike(o, o + Vector2(220.0, 0.0), Elements.color(Elements.Element.SHADOW), 50, "shadow", null))
	)
	_save("user://summon_showcase_b.png")
	quit(0)


# ------------------------------------------------------------------------ plumbing
## Build a spectacle, STAMP it the way SpellCaster._stamp does, and run its entry
## function. The stamp is the whole reason the sigil knows what to draw.
func _spawn(script_name: String, element: int, tier: int, fire: Callable) -> Node2D:
	var n: Node2D = (load("res://scripts/combat/%s.gd" % script_name) as GDScript).new()
	_arena.add_child(n)
	n.set("element_id", element)
	n.set("spell_tier", tier)
	n.set("target_group", "enemy")
	n.set("_target_group", "enemy")
	fire.call(n)
	return n


## Cast, wait `frames` (the summon beat for that spell), shoot, then let it clear.
func _shot(label: String, frames: int, build: Callable) -> void:
	var spell: Node2D = build.call(_hero.global_position) as Node2D
	_label(label)
	await _wait(frames)
	_grab()
	# Long enough for the previous spell's IMPACT FRAME to expire before the next
	# shot. At 26 frames the full-screen marks (up to 0.30 s for a CUT_IN) were still
	# on screen when the following cell was grabbed, and half the sheet came back as
	# a white or black plate with no sigil visible at all.
	await _wait(48)
	if spell != null and is_instance_valid(spell):
		spell.queue_free()
	await _wait(6)


func _blank() -> Image:
	var img := Image.create(CELL.x * COLS, CELL.y * COLS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.03, 0.03, 0.05, 1.0))
	return img


func _label(text: String) -> void:
	for ch: Node in _labels.get_children():
		ch.queue_free()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 24)
	l.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.9))
	l.position = Vector2(18, 12)
	_labels.add_child(l)


func _wait(frames: int) -> void:
	for _i: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab() -> void:
	var img: Image = root.get_texture().get_image()
	if img == null or _sheet == null:
		return
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL),
		Vector2i((_cell % COLS) * CELL.x, (_cell / COLS) * CELL.y))
	_cell += 1


func _save(path: String) -> void:
	var err: int = _sheet.save_png(path)
	if err == OK:
		print("summon showcase: saved ", ProjectSettings.globalize_path(path))
	else:
		printerr("summon showcase: save failed err=", err, " path=", path)


func _zoom(z: float) -> void:
	for child: Node in _hero.get_children():
		if child is Camera2D:
			(child as Camera2D).zoom = Vector2(z, z)
			return


func _find_hero() -> Node2D:
	var heroes: Array = get_nodes_in_group("hero")
	return heroes[0] as Node2D if not heroes.is_empty() else null
