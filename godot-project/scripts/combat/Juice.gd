class_name Juice
extends RefCounted
## Static game-feel helpers. Time-scale-safe so hit-stop restores itself.

# The active SceneTree is reachable via Engine's main loop.
static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func hit_stop(duration: float = 0.06) -> void:
	var tree: SceneTree = _tree()
	if tree == null or not _hit_stop_enabled():
		return
	Engine.time_scale = 0.05
	# ignore_time_scale = true so the restore timer runs in real time.
	var timer: SceneTreeTimer = tree.create_timer(duration, true, false, true)
	await timer.timeout
	Engine.time_scale = 1.0


## Accessibility toggle (Tuning.cfg.hit_stop_enabled) — off = no time-freeze.
static func _hit_stop_enabled() -> bool:
	var tree: SceneTree = _tree()
	if tree == null:
		return true
	var t: Node = tree.root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		return true
	var v: Variant = t.cfg.get(&"hit_stop_enabled")
	return v == null or bool(v)


## Unified "fire ALL the juice for one hit" dispatcher — the Stick-Fight
## simultaneity trick (study §4): one call fires the whole camera/time/sound
## cluster in sync (previously duplicated as hit_stop+shake+zoom+sfx at ~15 hit
## sites). The victim's body reaction (white flash + knockback + ragdoll flop)
## fires from the entity's own take_damage/apply_knockback so it's direction-
## aware and covers every damage source — together they are the "all six at
## once" hit. Every ctx key is optional (absent = skipped):
##   dir: Vector2      hit direction (drives the directional camera kick)
##   shake: float      screenshake amount
##   kick: float       directional camera-punch px along dir
##   zoom: float       zoom-punch amount
##   sfx: String       Sfx key to play (+ sfx_db, sfx_pitch)
##   hitstop: float    freeze duration — fired LAST (it awaits) so the rest lands first
static func on_hit(ctx: Dictionary) -> void:
	var dir: Vector2 = ctx.get("dir", Vector2.ZERO)
	var shake: float = ctx.get("shake", 0.0)
	if shake > 0.0:
		shake_camera(shake)
	var kick: float = ctx.get("kick", 0.0)
	if kick > 0.0 and dir != Vector2.ZERO:
		kick_camera(dir.normalized(), kick)
	var zoom: float = ctx.get("zoom", 0.0)
	if zoom > 0.0:
		zoom_punch_camera(zoom)
	var sfx: String = ctx.get("sfx", "")
	if sfx != "":
		var tree: SceneTree = _tree()
		if tree != null:
			var sfx_node: Node = tree.root.get_node_or_null(^"/root/Sfx")
			if sfx_node != null and sfx_node.has_method(&"play"):
				sfx_node.call("play", sfx, ctx.get("sfx_db", 0.0), ctx.get("sfx_pitch", 0.06))
	var hs: float = ctx.get("hitstop", 0.0)
	if hs > 0.0:
		hit_stop(hs)


## THE EPIC MOMENT — one synchronized "big beat" for an ult release / finisher:
## the crescendo->payoff cluster fired IN SYNC (the maker's north-star juice system).
## Pairs with the caster-side anticipation (charge SFX + growing spell circle +
## gather motes) so the whole arc reads anticipation -> crescendo -> payoff ->
## aftermath. Composed from the existing camera/time primitives so it layers with
## a spell's own zoom_pull without fighting. Every key optional:
##   strength: float   overall scale (0.6 small .. 1.4 screen-filling ult)
##   frame: bool       also fire the full-screen impact-frame speed-lines (biggest)
##   shake: float      override the screenshake amount (else scales from strength)
##   sfx: String       an accent Sfx key to punch on the release
static func epic_moment(opts: Dictionary = {}) -> void:
	var s: float = opts.get("strength", 1.0)
	# Reveal: pull the frame WIDE to show the whole spectacle, hold, ease home.
	zoom_pull_camera(0.18 * s, 0.5, 0.12, 0.55)
	# ...with a quick lunge-IN punch layered on the reveal — the "slam" of release.
	zoom_punch_camera(0.07 * s, 0.18)
	shake_camera(float(opts.get("shake", 9.0 * s)))
	PostProcess.shock(s)  # the screen-space ripple that sells the "insane" beat
	var sfx: String = opts.get("sfx", "")
	if sfx != "":
		var tree: SceneTree = _tree()
		if tree != null:
			var sfx_node: Node = tree.root.get_node_or_null(^"/root/Sfx")
			if sfx_node != null and sfx_node.has_method(&"play"):
				sfx_node.call("play", sfx, 0.0, 0.05)
	if bool(opts.get("frame", false)):
		# "at" is the world point the beat belongs to; omitted = viewport centre.
		impact_frame(0.7 * s, opts.get("at", Vector2.INF))
	hit_stop(0.07 * s)  # fired LAST (it awaits) so the reveal/shake land first


## The anime IMPACT FRAME — spawn a full-screen speed-line + flash burst, a harder
## freeze, a big zoom-punch + shake spike. Reserve for CURATED cool moments (a big
## deflect, a heavy punch, a finisher) — not every hit. Respects the hit-stop toggle.
## Pass the WORLD hit position when one exists so the flash + converging lines
## happen AT the impact (screen-projected) — omitted = viewport centre (legacy).
static func impact_frame(strength: float = 1.0, world_pos: Vector2 = Vector2.INF) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	var f: Node = (load("res://scripts/combat/ImpactFrame.gd") as GDScript).new()
	tree.root.add_child(f)
	f.call("flash", strength, world_pos)
	zoom_punch_camera(0.14 * strength, 0.22)
	shake_camera(11.0 * strength)
	PostProcess.shock(1.15 * strength)  # a hard screen ripple on the curated impact frame
	hit_stop(0.15 * strength)


## Project a WORLD point to a screen UV (0..1). PostProcess.shock takes a
## screen-space centre, so a beat that belongs to a place in the world (a beam
## crossing, a localized impact) has to be projected or the ripple silently
## centres on the middle of the screen. Falls back to the centre when there is
## no viewport/camera (headless).
static func world_to_uv(world_pos: Vector2) -> Vector2:
	var tree: SceneTree = _tree()
	if tree == null:
		return Vector2(0.5, 0.5)
	var vp: Viewport = tree.root.get_viewport()
	if vp == null:
		return Vector2(0.5, 0.5)
	var size: Vector2 = vp.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var screen: Vector2 = vp.get_canvas_transform() * world_pos
	return Vector2(clampf(screen.x / size.x, 0.0, 1.0), clampf(screen.y / size.y, 0.0, 1.0))


static func shake_camera(amount: float = 6.0) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("combat_camera"):
		if cam.has_method("add_shake"):
			cam.add_shake(amount)


## Directional camera punch along `dir` (px), eases back — pairs with
## shake_camera for hits that have a clear direction (melee follow-through).
static func kick_camera(dir: Vector2, amount: float) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("combat_camera"):
		if cam.has_method("kick"):
			cam.kick(dir, amount)


## Quick zoom-in kick that eases back — the "camera lunges at the blast" beat.
static func zoom_punch_camera(amount: float = 0.1, duration: float = 0.18) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("combat_camera"):
		if cam.has_method("zoom_punch"):
			cam.zoom_punch(amount, duration)


## Temporary zoom-OUT that eases wide, holds, eases back — the "camera pulls back
## to show the big spell" beat (meteor / divine ray / ultimate spectacles).
static func zoom_pull_camera(amount: float = 0.16, hold: float = 0.5, ease_in: float = 0.12, ease_out: float = 0.55) -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("combat_camera"):
		if cam.has_method("zoom_pull"):
			cam.zoom_pull(amount, hold, ease_in, ease_out)
