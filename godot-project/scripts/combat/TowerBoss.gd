class_name TowerBoss
extends Boss
## Shared scaffolding for the bosses added alongside the Ashspire Guardian.
##
## ── WHY THIS EXISTS RATHER THAN THREE PARALLEL BOSS SCRIPTS ──────────────────
## `Boss.gd` already owns everything a boss fight needs and none of it is worth
## rebuilding: the INTRO beat, the top-screen bar, the three HP-gated phases and
## their signal, the busy/cooldown attack loop, the `_emit_telegraph` grammar, the
## knockback resistance, the co-op puppet guard, and the death climax. Writing a
## second one of those would give the tower two subtly different boss engines, and
## the second one would be the one with the bugs.
##
## So the three new artists are SUBCLASSES, and this file is the thin layer that
## makes subclassing pleasant: it sheds the Ashspire's bespoke dressing (a molten
## stone core is wrong on ink and gold leaf), re-points the name card and the health
## bar at the subclass's own identity, and replaces the hard-coded attack switch
## with `_perform(id)`.
##
## ── WHAT IT DELIBERATELY DOES *NOT* OVERRIDE ─────────────────────────────────
## `take_damage`, `apply_knockback` and `_die`. All three carry the co-op
## authority/RPC paths, and a subclass that reimplemented them would silently drop
## whatever network handling `Boss.gd` grows next. Every override below is
## presentation or attack selection — nothing that touches the wire.
##
## `_enter_phase` calls `super` first FOR THE SAME REASON: whatever the base does on
## a phase change (today: state, cooldown, signal, dressing; tomorrow: possibly a
## broadcast) still happens, and this only repaints on top of it.

## The artist's mark worn in place of the Guardian's molten adornment.
var _mark: BossSigilMark = null

## Per-boss identity. Subclasses override these; the defaults are the Guardian's so
## a subclass that overrides nothing is still a legal, working boss.
##
## `boss_title()` and `boss_accent()` are NOT restated here — they now live on
## `Boss` itself, because the bar and the intro card need to be able to ask any
## boss (the Guardian included) rather than only a `TowerBoss`.
func boss_artist() -> String: return "charcoal on stone"
func boss_tint() -> Color: return STONE_TINT
func boss_rig_height() -> float: return RIG_HEIGHT
func boss_preset() -> String: return "brawler"
func boss_equipment() -> Dictionary: return {}


## Per-phase dressing: {"tint": Color, "aura": Color, "strength": float,
## "tier": int, "mark": float}. `p` is 1/2/3.
func phase_palette(p: int) -> Dictionary:
	var a: Color = boss_accent()
	var k: float = float(clampi(p, 1, 3) - 1) / 2.0     # 0 .. 1 across the fight
	return {
		"tint": boss_tint().lerp(a, 0.28 * k),
		"aura": a,
		"strength": lerpf(0.42, 0.8, k),
		"tier": 2 + clampi(p - 1, 0, 2),
		"mark": lerpf(0.3, 1.0, k),
	}


## Seconds between attacks in phase `p`. Defaults to the base's PHASE_CD; a boss
## whose identity is RHYTHM (all three of them, in different directions) overrides
## it. This is the knob that separates "constant pressure" from "big committed
## casts with a punish window" without touching a single damage number.
func phase_cooldown(p: int) -> float:
	return float(PHASE_CD.get(p, 2.0))


## The rig gesture an attack id plays. RAISE for casts, STOMP for ground work.
func gesture_for(_id: String) -> int:
	return CharacterRig.GestureKind.RAISE


## Run the attack named `id`. This is the whole per-boss moveset seam.
func _perform(_id: String) -> void:
	pass


# ------------------------------------------------------------------- lifecycle
func _ready() -> void:
	super._ready()              # hp, rig, bar, intro (our _play_intro), Ashspire dressing
	_shed_ashspire_dressing()
	_apply_identity()
	_dress_phase(1)


## The Guardian's molten core is hard-coded orange in every channel, which is right
## for stone and ember and wrong for graphite, ink and gold. Free it and wear a
## recolourable artist's mark instead. `_adorn` is nulled rather than left dangling
## because `Boss._enter_phase` null-checks it on every phase change.
func _shed_ashspire_dressing() -> void:
	if _adorn != null and is_instance_valid(_adorn):
		_adorn.queue_free()
	_adorn = null
	if _mark == null:
		_mark = BossSigilMark.new()
		add_child(_mark)
	_mark.configure(boss_rig_height() * body_scale, boss_accent())


func _apply_identity() -> void:
	if is_instance_valid(rig):
		rig.set("height", boss_rig_height() * body_scale)
		rig.class_preset(boss_preset())
		for slot: String in boss_equipment():
			rig.set_equipment(slot, String(boss_equipment()[slot]))
		rig.set_tint(boss_tint())
	# THE BAR IS NO LONGER RENAMED FROM OUT HERE. `Boss._build_bar` calls
	# `BossBar.setup(self, boss_title(), boss_accent())` and those are virtual, so
	# the bar is built with this boss's identity in the first place. The old
	# rewrite-the-label-afterwards workaround (and its dependence on a private
	# `_name_label`) is gone; see the note on `BossBar.setup`.


# ---------------------------------------------------------------------- phases
func _enter_phase(p: int) -> void:
	super._enter_phase(p)       # state + cooldown + signal (+ anything the base adds later)
	_dress_phase(p)


func _dress_phase(p: int) -> void:
	if p < 1 or p > 3:
		return
	var pal: Dictionary = phase_palette(p)
	if is_instance_valid(rig):
		rig.set_tint(pal["tint"] as Color)
		rig.set_aura(pal["aura"] as Color, float(pal["strength"]))
		rig.set_aura_tier(int(pal["tier"]))
	if _mark != null and is_instance_valid(_mark):
		_mark.set_colour(boss_accent())
		_mark.set_intensity(float(pal["mark"]))


## The Guardian opens its second phase by summoning ember adds. That is ITS
## identity, not the roster's, so the default here is nothing — a boss that summons
## says so by overriding this (the Illuminator does).
func _atk_summon() -> void:
	pass


# ------------------------------------------------------------- attack dispatch
func _choose_attack() -> void:
	var ids: Array = _phase_attack_ids(current_phase())
	if ids.is_empty():
		_attack_cd = 1.0
		return
	_run_attack(String(ids[randi() % ids.size()]))
	_attack_cd = phase_cooldown(_bphase)


func _run_attack(id: String) -> void:
	_busy = true
	if is_instance_valid(rig):
		rig.cast_gesture(gesture_for(id), 0.9)
	_perform(id)
	_unbusy_after(_attack_duration(id))


# ----------------------------------------------------------------- presentation
## The contact hitbox scales with the ACTUAL rig, not the Guardian's 95 px. Without
## this a 58 px scribble would damage you from 52 px away — a hitbox half again the
## size of its own body, which is the classic "that didn't touch me" complaint.
func _boss_touch() -> void:
	if not is_instance_valid(_hero) or _touch_cooldown > 0.0:
		return
	if global_position.distance_to(_hero.global_position) < boss_rig_height() * body_scale * 0.55:
		if _hero.has_method("take_damage"):
			_hero.take_damage(touch_damage)
			_touch_cooldown = 0.8


## Same beats as the base intro — zoom pull, name card in, hold, out, wake roar —
## with this boss's own name and colour. Reimplemented rather than post-edited
## because the card is a local built inside the base's version and there is nothing
## to reach for afterwards.
## Every number that used to be a literal in here now comes from `Boss.card_style()`,
## so a mini-guardian's flash and a headline act's card stay one decision rather than
## two copies that drift — see the CEREMONY block in Boss.gd.
func _play_intro() -> void:
	_bphase = BPhase.INTRO
	_intro_timer = intro_time()
	var s: Dictionary = card_style()
	Juice.zoom_pull_camera(float(s["pull"]), _intro_timer,
		float(s["pull_hold"]), float(s["pull_release"]))
	var accent: Color = boss_accent()
	var card := Label.new()
	card.set_anchors_preset(Control.PRESET_TOP_WIDE)
	card.offset_top = float(s["top"])
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.text = boss_title()
	card.add_theme_font_size_override("font_size", int(s["size"]))
	card.add_theme_color_override("font_color", accent)
	card.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.03, 0.95))
	card.add_theme_constant_override("outline_size", int(s["outline"]))
	card.modulate.a = 0.0
	_bar_layer.add_child(card)
	# THE SIGNATURE LINE. One line of the artist, under the name, in the same colour
	# at a third of the size. It is the only place the lore is ever stated out loud,
	# it costs a Label, and it is the difference between "boss 3 of 4" and "somebody
	# drew this". Never a cutscene, never a codex — a caption.
	var sig := Label.new()
	sig.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sig.offset_top = float(s["sig_top"])
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# THE BILLING LINE. `boss_epithet()` is what a god is announced as; it falls back
	# to `boss_artist()` (the material note) so a boss that has not been given one
	# still reads exactly as it did before this landed. On a FULL ceremony it is
	# framed, because that beat is the one the tower is allowed to spend on; a
	# mini-guardian's brief flash stays bare, per the ceremony split.
	var billing: String = boss_epithet()
	if billing == "":
		billing = boss_artist()
	elif full_ceremony():
		billing = "— %s —" % billing
	sig.text = billing
	sig.add_theme_font_size_override("font_size", int(s["sig_size"]))
	sig.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.75))
	sig.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.03, 0.9))
	sig.add_theme_constant_override("outline_size", 5)
	sig.modulate.a = 0.0
	_bar_layer.add_child(sig)
	var fade: float = float(s["fade"])
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, fade)
	tw.parallel().tween_property(sig, "modulate:a", 1.0, fade)
	tw.tween_interval(float(s["hold"]))
	tw.tween_property(card, "modulate:a", 0.0, fade)
	tw.parallel().tween_property(sig, "modulate:a", 0.0, fade)
	tw.tween_callback(card.queue_free)
	tw.tween_callback(sig.queue_free)
	get_tree().create_timer(float(s["roar"])).timeout.connect(_roar_intro)


func _roar_intro() -> void:
	if not is_instance_valid(self):
		return
	if _mark != null and is_instance_valid(_mark):
		_mark.set_intensity(0.6)
	Juice.epic_moment({"strength": 1.0, "shake": 10.0, "sfx": "charge_up"})


# ------------------------------------------------------------ shared attack kit
## Lay a LANE tell from this boss along `dir` and call `on_fire` when it expires.
## The charger's grammar, which is the one lane vocabulary the player has already
## learned by the time they meet any boss: the shape you can see is the shape that
## will hurt, the aim is frozen when it appears, and walking out of it is the dodge.
##
## `no_resolve` is mandatory here — every boss is an Enemy subclass carrying
## archetype BRUTE, so without it `Enemy._on_telegraph_fired` would answer the tell
## with a brute ground strike instead of the attack we asked for.
func lane_tell(dir: Vector2, length: float, width: float, windup: float, on_fire: Callable) -> void:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var tele: Telegraph = _emit_telegraph({
		"style": Telegraph.Style.LANE, "pos": global_position,
		"accent": boss_accent(), "windup": windup,
		"line": true, "length": length, "width": width,
		"angle": d.angle(), "aim": d, "reach": length,
		"no_resolve": true,
	})
	_spawn_caster_signal(15.0, windup)
	if tele == null:
		on_fire.call()
		return
	tele.fired.connect(func() -> void:
		_free_caster_signal()
		if is_instance_valid(self) and _bphase != BPhase.DEAD:
			on_fire.call())


## A ground ZONE tell at `at` — the "something is about to happen HERE" mark. Same
## contract as lane_tell.
func zone_tell(at: Vector2, radius: float, windup: float, on_fire: Callable) -> void:
	var tele: Telegraph = _emit_telegraph({
		"style": Telegraph.Style.ZONE, "pos": at,
		"accent": boss_accent(), "radius": radius, "windup": windup,
		"no_resolve": true,
	})
	if tele == null:
		on_fire.call()
		return
	tele.fired.connect(func() -> void:
		if is_instance_valid(self) and _bphase != BPhase.DEAD:
			on_fire.call())


## Open a summoning circle at `at` in this boss's colour and let it bloom out on its
## own timer. The same MagicCircle every spell in the game summons out of, so a boss
## cast is read with the skills the player already has: the glyph band says which
## element, the tier ring says how big, and the band FILLS as the wind-up runs, so
## the countdown is countable off the rim rather than merely watched.
func summon_circle(at: Vector2, element: int, tier: int, radius: float, hold: float,
		ground: bool = false) -> MagicCircle:
	var host: Node = get_parent()
	if host == null or not host.is_inside_tree():
		return null
	var grow: float = minf(0.26, maxf(hold * 0.4, 0.08))
	var c := MagicCircle.new()
	host.add_child(c)
	c.global_position = at
	c.appear(boss_accent(), radius, grow)
	c.set_signature(element, tier)
	if ground:
		c.set_ground(0.34)
	c.hold(hold, 0.22)
	# CO-OP. The sigil is a FAIRNESS signal on this roster, not decoration — it is
	# how the compass states its radius and how the Final Page states its size — so
	# the twin goes out from the one place every boss opens a circle. `_bfx` is
	# host-gated inside, so this is a no-op in single player.
	_bfx("circle", {"pos": at, "col": boss_accent(), "r": radius, "grow": grow,
		"el": element, "tier": tier, "hold": hold, "ground": ground})
	return c


## Spawn a hostile spectacle of `script_path` into the arena, stamped so it hurts
## heroes and is OWNED by this boss.
##
## ⚠ THE OWNERSHIP STAMP IS LOAD-BEARING. The reaction layer asks a spectacle
## `reaction_owner()`; null reports "unowned", which satisfies neither
## `require_owner: "same"` nor `"different"`, so an un-owned effect matches NO clash
## row and is silently inert in the whole reaction system. Nothing errors. Routing
## every boss spectacle through one helper is the same argument `SpellCaster._stamp`
## makes: forgetting stops being expressible.
func spawn_spectacle(script_path: String, element: int, tier: int = SpellTier.Tier.HEAVY) -> Node:
	var host: Node = get_parent()
	if host == null or not host.is_inside_tree():
		return null
	var gs: GDScript = load(script_path) as GDScript
	if gs == null:
		return null
	var n: Node = gs.new()
	n.set("target_group", "hero")
	n.set("_target_group", "hero")
	n.set("caster_node", self)
	n.set("element_id", element)
	n.set("spell_tier", tier)
	host.add_child(n)
	return n
