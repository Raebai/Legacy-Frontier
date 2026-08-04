class_name Juice
extends RefCounted
## Static game-feel helpers. Time-scale-safe so hit-stop restores itself.

# The active SceneTree is reachable via Engine's main loop.
static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Generation counter for OVERLAPPING freezes. Two hit-stops in flight used to
## fight: the shorter one's restore fired first and snapped time_scale back to 1
## while the longer one was still meant to be holding, so a big beat layered over
## a small one silently lost its freeze. Only the LATEST freeze restores; earlier
## ones see a stale generation and return without touching time_scale.
static var _hit_stop_gen: int = 0


## ⚠ THE FREEZE IS SPENT ONLY WHERE IT IS EARNED — IN THE HUB IT READS AS LAG.
##
## Maker's report, verbatim: "it lags when I shoot at something like the dummy or an
## NPC in the hub, that's weird please fix that". It is not lag, and it is not a frame
## hitch. MEASURED by firing a real `Spell` at a real `town_dummy` in a headless boot
## of `Main.tscn`: `Engine.time_scale` goes 1.000 -> 0.050 on the connect frame, holds
## for three frames, then restores. The entire world runs at ONE TWENTIETH speed for
## ~50 ms, on every single bolt. That is the stutter, and it is this function.
##
## Two things make the hub worse than the arena, and neither is a fault in the freeze
## itself — which is why the answer is scope, not a smaller number:
##
##   * A HUB HIT SPENDS THE FREEZE TWICE. `Hero.take_damage` spends HURT_HIT_STOP
##     (0.05) and then `Spell._damage_hero` spends another 0.045 through `on_hit`.
##     The generation counter above means only the last one restores, so it is one
##     freeze — but in the arena that double-spend is buried under an enemy that
##     flinches away, staggers and eventually dies. Here it lands on a 9999-hp dummy
##     that does not move, does not die, and is standing in exactly the same place for
##     the next twenty bolts. Identical code, no payoff, so it reads as a fault.
##
##   * A MISS FREEZES TOO, and this one is probably the bigger half. Every wall,
##     building and floor slab in the town is a `StaticBody2D`, and `Spell._try_damage`'s
##     `StaticBody2D` arm spends `hit_stop(0.03)`. So bolts that hit NOTHING AT ALL
##     still stutter the room — which is exactly what "it lags when I shoot" describes
##     and what no amount of tuning the hit numbers would have fixed.
##
## Nothing below this line changes what a hit-stop COSTS. The arena's numbers, the
## weighting between a jab and an ult, the ult's `epic_moment` beat and the impact
## frame's freeze are all byte-identical — the only new question is whether the room
## you are standing in gets one. Everything else a hub hit fires is untouched: the
## screenshake, the camera kick, the white flash, the ragdoll flinch, the damage
## numbers, the spark burst and the SFX all still land, so a bolt into a dummy still
## reads as a hit rather than as a bolt passing through fog.
##
## ⚠ THIS IS A DELIBERATE DIVERGENCE, and the cost is worth stating plainly: the dummy
## yard exists so the kit can be FELT, and the kit now feels a hair lighter there than
## it does in the tower. If that trade ever reads wrong, do NOT delete the guard —
## raise this scale. 0.0 = no freeze in the hub (today); 1.0 = arena-identical (i.e.
## the bug); ~0.25 is "a hint of weight, no world freeze" if a middle ground is wanted.
const LOBBY_HIT_STOP_SCALE: float = 0.0

## Non-combat rooms, by scene path. Second half of the `in_lobby` test — see there.
const LOBBY_SCENES: PackedStringArray = ["res://scenes/Main.tscn"]


## Is the tree currently showing a room nobody is fighting in?
##
## Two INDEPENDENT signals, because each one rots in a different way and either one
## catching it is enough:
##   * the town's own marker group. Survives a scene rename or a re-parent, and is
##     what actually defines "this is the hub" — `town_dummy` is added by
##     `World._spawn_dummy_yard` and by nothing else in the project (VersusArena's
##     practice bodies deliberately use a different group, `free_dummy`).
##   * the scene path. Survives the dummy yard being emptied, reshaped or spawned
##     late, which the group check alone would fail open on.
##
## ⚠ DELIBERATELY A DENY-LIST, not an allow-list of combat scenes, and the asymmetry
## is the whole point. A new lobby-ish room that somebody forgets to add here merely
## gets today's bug back — which is visible to the first person who casts in it. A new
## ARENA forgotten in an allow-list would SILENTLY lose its hit-stop, and quietly
## losing the arena's hard-won feel to a bookkeeping miss is the one outcome this
## change is not allowed to risk.
static func in_lobby() -> bool:
	var tree: SceneTree = _tree()
	if tree == null:
		return false
	if tree.get_first_node_in_group(&"town_dummy") != null:
		return true
	var scene: Node = tree.current_scene
	return scene != null and LOBBY_SCENES.has(scene.scene_file_path)


static func hit_stop(duration: float = 0.06) -> void:
	var tree: SceneTree = _tree()
	if tree == null or not _hit_stop_enabled():
		return
	# The freeze is a COMBAT verb. See LOBBY_HIT_STOP_SCALE for the measurement.
	# Scaled rather than skipped so the middle ground is one constant away, and
	# checked HERE rather than at the ~40 call sites because this is the only place
	# in the project that writes `Engine.time_scale` — so one guard covers the bolt
	# hit, the miss into a wall, the melee swing, the parry and the ult alike.
	if in_lobby():
		duration *= LOBBY_HIT_STOP_SCALE
	if duration <= 0.0:
		return
	_hit_stop_gen += 1
	var gen: int = _hit_stop_gen
	Engine.time_scale = 0.05
	# ignore_time_scale = true so the restore timer runs in real time.
	var timer: SceneTreeTimer = tree.create_timer(duration, true, false, true)
	await timer.timeout
	if gen == _hit_stop_gen:
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
		# `style` / `element` let a caller pick its mark from the vocabulary
		# instead of always getting the white wash (the default stays BLOWOUT so
		# existing epic_moment callers are unchanged).
		# Camera + freeze are suppressed here (zoom/shake/shock/hitstop 0): this
		# function ALREADY fired all four, and letting the frame fire its own set
		# on top double-punches the camera and lets the frame's freeze overwrite
		# the epic beat's own, tuned one.
		frame({
			"style": int(opts.get("style", ImpactFrame.Style.BLOWOUT)),
			"strength": 0.7 * s,
			"at": opts.get("at", Vector2.INF),
			"element": int(opts.get("element", -1)),
			"lines": bool(opts.get("lines", true)),
			"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
		})
	hit_stop(0.07 * s)  # fired LAST (it awaits) so the reveal/shake land first


## THE PUNCTUATION BEAT — one entry point for every impact frame in the game.
##
## Fires a screen mark (see `ImpactFrame.Style` for the vocabulary and when to
## reach for each) together with the camera/time cluster that sells it. Whether
## it plays at all is decided by `ImpactFrame.decide`, the global arbiter — see
## that file for why a referee is not optional here.
##
## ⚠ WHEN THE ARBITER SAYS NO, *NOTHING* FIRES — not the mark, and not the shake
## / zoom / ripple / freeze either. That is deliberate and it is what makes a
## barrage safe. The freeze in particular is the dangerous half: `hit_stop` drops
## `Engine.time_scale` to 0.05, and twelve boulders landing inside 0.34 s each
## requesting their own 0.2 s freeze is how you lock the game in stuttering slow
## motion for seconds (MeteorSigil._land_earth carries the scar). Callers all
## fire their OWN on-hit juice already, so a suppressed frame costs the hit
## nothing — it just does not get punctuated.
##
## opts (all optional):
##   style: int       an ImpactFrame.Style; default BLOWOUT
##   strength: float  0.25 .. 1.6
##   duration: float  real seconds; default per style
##   at: Vector2      WORLD hit position — pass it whenever one exists
##   element: int     an Elements.Element; supplies the tint for COLOR_FIELD etc.
##   tint: Color      explicit tint, overriding `element`
##   lines: bool      draw the style's radial lines/wedges (default true)
##   shake/zoom/shock/hitstop: floats overriding the strength-derived cluster
## Returns true when the frame actually played.
static func frame(opts: Dictionary = {}) -> bool:
	var tree: SceneTree = _tree()
	if tree == null:
		return false
	var strength: float = float(opts.get("strength", 1.0))
	var decision: Dictionary = ImpactFrame.decide({
		"style": int(opts.get("style", ImpactFrame.Style.BLOWOUT)),
		"strength": strength,
		"duration": opts.get("duration", ImpactFrame.default_duration(
			int(opts.get("style", ImpactFrame.Style.BLOWOUT)))),
	})
	if not bool(decision["granted"]):
		return false
	# The mark's own strength may have been clamped by the accessibility
	# downgrade; the surrounding cluster follows it down so the whole beat
	# softens together instead of a quiet flash under a violent camera.
	var s: float = float(decision["strength"])
	var at: Vector2 = opts.get("at", Vector2.INF)
	var element: int = int(opts.get("element", -1))
	var tint: Color = opts.get("tint",
		Elements.color(element) if element >= 0 else Color(1.0, 1.0, 1.0))
	ImpactFrame.spawn(decision, at, tint, bool(opts.get("lines", true)))
	var zoom: float = float(opts.get("zoom", 0.14 * s))
	if zoom > 0.0:
		zoom_punch_camera(zoom, 0.22)
	var shake: float = float(opts.get("shake", 11.0 * s))
	if shake > 0.0:
		shake_camera(shake)
	var shock: float = float(opts.get("shock", 1.15 * s))
	if shock > 0.0:
		# Centre the ripple on the hit when we know where it is, for the same
		# reason the mark itself is: a beat that belongs to a place in the world
		# and rings from screen centre reads as a UI glitch.
		if at.is_finite():
			PostProcess.shock(shock, world_to_uv(at))
		else:
			PostProcess.shock(shock)
	var hs: float = float(opts.get("hitstop", 0.15 * s))
	if hs > 0.0:
		hit_stop(hs)   # fired LAST (it awaits) so the rest lands first
	return true


## THE TIER LADDER — what a spectacle should call. A jab, a heavy spell, an ult
## and a climax get four different marks, keyed off the SAME `SpellTier` shelf the
## clash layer and the audio roster already read, so "an ult feels like an ult"
## means one thing across the game. See ImpactFrame's TIER_* constants.
##
## `element` (an Elements.Element, or -1) is what makes two ults of different
## elements end on genuinely different screens rather than on the same white
## wash — the specific failure that got impact frames deleted from three spells
## here. Pass the spell's `element_id`.
##
## `opts` is forwarded to `frame`, so a spectacle can override any single part of
## its rung (a style, a duration) without leaving the ladder.
static func tier_frame(tier: int, at: Vector2 = Vector2.INF, element: int = -1,
		opts: Dictionary = {}) -> bool:
	var cfg: Dictionary = {"at": at, "element": element}
	cfg.merge(ImpactFrame.ladder(tier, element, bool(opts.get("climax", false))))
	cfg.merge(opts, true)
	cfg.erase("climax")
	return frame(cfg)


## Legacy entry point, unchanged in signature and (when the arbiter grants it) in
## behaviour: a white blow-out with the original camera/time cluster. Kept so the
## ~10 existing call sites outside this system keep working; new call sites should
## prefer `tier_frame` so they land on the ladder.
static func impact_frame(strength: float = 1.0, world_pos: Vector2 = Vector2.INF) -> void:
	frame({
		"style": ImpactFrame.Style.BLOWOUT, "strength": strength, "at": world_pos,
		"zoom": 0.14 * strength, "shake": 11.0 * strength,
		"shock": 1.15 * strength, "hitstop": 0.15 * strength,
	})


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


## Flatten a knockback toward the HORIZONTAL, preserving its magnitude.
##
## Radial knockback is computed as "away from the blast centre", and a blast that
## lands at someone's FEET therefore points almost straight up — so a meteor or a
## ground detonation launched people vertically instead of throwing them aside.
## That reads as a bug even though every individual spell was doing something
## reasonable.
##
## MUST be applied by the SOURCE that computes a radial "away" vector, not
## blanket-applied when a body receives a shove: several attacks launch straight
## up ON PURPOSE (the uppercut, the wall plow's up-and-out), and flattening those
## silently removes a designed behaviour — slice3_test_enemy_sideon exists to
## catch exactly that, and did. A small upward share is kept and enforced so a
## flattened hit still leaves the floor and the ragdoll can tumble.
static func lateral_knockback(v: Vector2, max_vertical_share: float = 0.55) -> Vector2:
	var mag: float = v.length()
	if mag <= 0.001:
		return v
	var n: Vector2 = v / mag
	# Nothing horizontal at all (a dead-on vertical hit): pick a side rather than
	# firing them at the ceiling.
	if absf(n.x) < 0.001:
		n.x = 1.0 if randf() < 0.5 else -1.0
	var lift: float = clampf(n.y, -max_vertical_share, max_vertical_share)
	# Always at least a little lift, so a flattened hit still leaves the ground.
	if lift > -0.18:
		lift = -0.18
	return Vector2(signf(n.x) * sqrt(maxf(1.0 - lift * lift, 0.0)), lift) * mag


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
