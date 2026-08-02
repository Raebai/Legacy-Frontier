class_name DeathSmudge
extends Node2D
## THE DEATH BEAT — a body goes loose, folds into a heap, and is RUBBED OUT.
##
## The maker's ask, verbatim: *"where is the ragdoll when they die — maybe there
## should be some cool death animation, small but cute"*. Before this file, a dead
## enemy left a STATIC, BOLT-UPRIGHT silhouette skating sideways off the screen
## (`RigGhost` with a launch velocity), and a bot-match KO left the loser standing
## at attention under the win card. Nothing on any death path ever went slack.
##
## ══ WHY THIS IS NOT A SECOND RAGDOLL ═══════════════════════════════════════════
## The standing rig directive is blunt: *"grounded = settled/planted, airborne +
## hits = loose/reactive ragdoll reusing the flop/limp system; true physics-body
## ragdoll only as a last resort"*. This file does NOT compete with that, and the
## split is deliberate:
##
##   * A body that IS STILL THERE when it dies — a downed hero, the loser of a bot
##     match — goes down on the REAL rig, via `CharacterRig.collapse()`, which is
##     nothing but the existing `set_limp(1)` + `apply_impulse()` + `play(HURT)`
##     already used for every hit in the game. No new animation, no keyframes.
##   * A body that CEASES TO EXIST on the same frame it dies — every `Enemy`, which
##     `queue_free()`s inside `_die()` — cannot ragdoll, because there is nothing
##     left to ragdoll. That is what this node is for, and the correct read for it
##     is not physics. It is the FICTION.
##
## ══ THE FICTION: SOMEONE IS DRAWING THIS ═══════════════════════════════════════
## The title screen's subtitle is "someone is drawing this"; enemies are scribbled
## into existence; the run-end card for a death is literally titled RUBBED OUT. So
## the death of a drawing is not a corpse. It is the unseen hand FOLDING the figure
## down and then SCRUBBING IT OFF THE PAGE — eraser strokes sweeping across, the
## lines lifting where they pass, graphite crumbs flicking off, a grey smudge left
## on the paper for a beat. Same visual language as `GhostForm` (chalk, graphite,
## eraser), which is what a hero death already turns into.
##
## SMALL BUT CUTE, and both words are budgets. The whole thing is `DURATION` long —
## a fifth of a second of fold, a third of a second of erase — because a wave kills
## five things at once and a three-second cinematic per body would be the exact dead
## air the brief exists to prevent.
##
## ══ CLOCKED IN REAL TIME, ON PURPOSE ═══════════════════════════════════════════
## ⚠ THIS IS LOAD-BEARING FOR THE BOT MATCH and is the reason `_age` is not `+=
## delta`. The two clocks this node has to survive:
##   * `Engine.time_scale = 0.05` — `Juice.hit_stop` fires on the KILLING blow, so a
##     delta-driven death animation would play at 1/20 speed exactly when it matters.
##   * `get_tree().paused = true` — `BotMatch._freeze()` pauses the whole tree on the
##     decisive frame and holds it for `FREEZE_BEAT`. A PAUSABLE node would be frozen
##     before it drew a single frame of its own death.
## So: `PROCESS_MODE_ALWAYS` (set in `_ready`) plus `Time.get_ticks_msec()`. Between
## them the beat plays at the same real-world speed whether the tree is running, in
## hit-stop, or frozen under a result card. `BotMatch` uses `_real_seconds()` for its
## own beats for precisely this reason; this is the same trick.
##
## ══ COST ═══════════════════════════════════════════════════════════════════════
## One `Node2D`, no physics, no collision, self-freeing. Its `_draw` is one
## `CharacterRig.draw_figure` (the same call the live body already makes each frame)
## plus a handful of lines and circles. Concurrency is capped by `MAX_ALIVE`; at
## `graphics_quality = LOW` the strokes and crumbs thin (see `_low`), but the FOLD
## and the FADE — the two things that carry the read — never thin. Readability is
## never the thing that degrades.

## This file, by path. See `spawn` for why nothing here is reached by `class_name` —
## not even from inside this file.
const SELF_SCRIPT: String = "res://scripts/combat/DeathSmudge.gd"
## Everything alive is in this group, so the cap is one group query and so a test can
## count them without walking the tree.
const GROUP: StringName = &"death_smudge"
## Hard ceiling on concurrent smudges. A wave can kill five bodies in a frame and a
## boss add-phase more; past this the extra deaths keep their particle burst and
## simply skip the smudge, which is the correct thing to drop first.
const MAX_ALIVE: int = 14
const MAX_ALIVE_LOW: int = 6

## Total real seconds, fold + erase. Tuned as a fifth + a third: long enough to READ
## as a body folding, short enough that five at once is punctuation and not a scene.
const DURATION: float = 0.52
## Fraction of DURATION spent folding into the heap. The erase overlaps the tail of
## the fold on purpose — the hand starts rubbing before the body has finished
## settling, which is what makes it read as one gesture instead of two.
const FOLD_FRACTION: float = 0.42
const ERASE_START: float = 0.34

## How far past the heap pose the fold overshoots before settling, as a fraction of
## the remaining distance. A dead body does not ease politely into place; it drops,
## overshoots slightly, and settles. Zero here reads as a lift being lowered.
const FOLD_OVERSHOOT: float = 0.13

## --- the heap, in fractions of figure height, in the rig's own local space ---
## `+y` is down and the feet sit near `+height * 0.5`, so "the ground" is the lowest
## foot in the snapshot and every joint below is placed relative to it. Hand-placed
## so the silhouette reads as a body lying on its side, head toward the fall
## direction, limbs splayed — not as a puddle.
const HEAP_HIP_LIFT: float = 0.055
const HEAP_SHOULDER_X: float = 0.17
const HEAP_SHOULDER_LIFT: float = 0.065
const HEAP_HEAD_X: float = 0.31
const HEAP_HEAD_LIFT: float = 0.075
const HEAP_HAND_LEAD_X: float = 0.44
const HEAP_HAND_OFF_X: float = 0.05
const HEAP_FOOT_LEAD_X: float = -0.21
const HEAP_FOOT_OFF_X: float = -0.34
const HEAP_FOOT_OFF_LIFT: float = 0.04

## --- the eraser ---
## Strokes sweep across the heap left-to-right, each in its own slice of the erase
## window so the figure comes apart in pieces rather than dissolving evenly.
const STROKES: int = 3
const STROKES_LOW: int = 1
const STROKE_WIDTH_FACTOR: float = 0.30   # of figure height
const STROKE_SPAN_FACTOR: float = 1.35    # horizontal travel, of figure height
## Soft circles per stroke — see `_draw_strokes` for why this is not one thick line.
const STROKE_BLOBS: int = 4
const STROKE_COLOR: Color = Color(0.86, 0.88, 0.93, 0.16)
## Graphite crumbs flicked off by the rubbing — the same language as GhostForm's
## motes, so a death and a ghost read as the same hand doing the same thing.
const CRUMBS: int = 6
const CRUMBS_LOW: int = 0
const CRUMB_COLOR: Color = Color(0.30, 0.32, 0.40, 0.9)
const CRUMB_RISE: float = 18.0
const CRUMB_SPREAD: float = 26.0
## The grey mark left on the paper once the figure is gone. Fades out over the last
## sliver of the beat; it is what stops the death ending on a hard pop.
const SMUDGE_COLOR: Color = Color(0.55, 0.58, 0.66, 0.24)
const SMUDGE_RADIUS_FACTOR: float = 0.42

## px/s^2 an optional launch velocity bleeds off — the enemy "body flies" read,
## carried over from the `RigGhost` corpse this replaced so that reaction is not lost.
const LAUNCH_DECAY: float = 520.0

# --- configured by `spawn()` before the node enters the tree ---
var pose: Dictionary = {}
var equipment_slots: Dictionary = {}
var fig_height: float = 22.0
var base_color: Color = Color(0.8, 0.8, 0.85, 1.0)
## Which way the body topples. +1 = head falls toward +x local, -1 = toward -x.
var fall_dir: float = 1.0
var launch_velocity: Vector2 = Vector2.ZERO
## Per-instance beat length, so a hero's death can breathe a fraction longer than a
## trash mob's without either one needing its own script.
var duration: float = DURATION

var _start_ms: int = 0
var _age: float = 0.0
var _heap: Dictionary = {}
var _low: bool = false
var _rng_seed: int = 0


## THE ONE WAY TO MAKE ONE. Snapshots a live rig and returns the node (or null if it
## was capped, or the rig was not usable) so a caller can tell whether one exists.
##
## ⚠ `rig` is typed `Object`, not `CharacterRig`, for the same reason the capture
## tools take their scenes by path: this file is reached from `Enemy`, `Hero` and
## `BotMatch`, and a hard type here would drag the rig's whole compile graph — and
## the autoloads inside it — into every one of them.
static func spawn(
	parent: Node,
	rig: Object,
	body_color: Color,
	toward: Vector2 = Vector2.ZERO,
	launch: Vector2 = Vector2.ZERO,
	beat: float = DURATION,
) -> Node2D:
	if parent == null or rig == null or not (rig is Node2D):
		return null
	var rig2d: Node2D = rig as Node2D
	if not rig2d.is_inside_tree() or not parent.is_inside_tree():
		return null
	var tree: SceneTree = parent.get_tree()
	if tree == null:
		return null
	var cap: int = MAX_ALIVE_LOW if TuningConfig.quality_is_low() else MAX_ALIVE
	if tree.get_nodes_in_group(GROUP).size() >= cap:
		return null
	if not rig2d.has_method("snapshot_pose"):
		return null
	var snap: Variant = rig2d.call("snapshot_pose")
	if not (snap is Dictionary) or (snap as Dictionary).is_empty():
		return null

	# ⚠ THE SCRIPT IS RE-`load()`ED RATHER THAN NAMED, INCLUDING HERE, INSIDE ITSELF.
	# A brand-new `class_name` is not in `.godot/global_script_class_cache.cfg` until
	# somebody re-imports the project, and until then NAMING it is a compile error —
	# which, from `Enemy` or `Hero`, takes the whole dependency chain down with it. A
	# file cannot even name ITSELF: `DeathSmudge.new()` on this very line failed with
	# "Identifier not found: DeathSmudge" until it became the load below. MEASURED, on
	# the first run of `tools/death_capture.gd`. `ResourceLoader` caches it, so this
	# costs a dictionary lookup and never a disk read.
	var self_script: GDScript = load(SELF_SCRIPT) as GDScript
	if self_script == null:
		return null
	var s: Node2D = self_script.new() as Node2D
	s.pose = snap as Dictionary
	var eq: Variant = rig2d.get(&"equipment")
	s.equipment_slots = (eq as Dictionary).duplicate() if eq is Dictionary else {}
	var h: Variant = rig2d.get(&"height")
	s.fig_height = float(h) if h != null else 22.0
	s.base_color = body_color
	s.duration = maxf(beat, 0.1)
	s.launch_velocity = launch
	# Which way it topples. Prefer the killing blow's direction; fall back to the way
	# the figure is already facing, mirrored into the rig's (possibly flipped) local
	# frame so "head falls forward" means the same thing on both facings.
	var flip: float = 1.0 if rig2d.scale.x >= 0.0 else -1.0
	if toward.x != 0.0:
		s.fall_dir = signf(toward.x) * flip
	else:
		s.fall_dir = 1.0
	parent.add_child(s)
	s.global_transform = rig2d.global_transform
	# z_index 0, NOT -1: the arena floor is an opaque z=0 canvas item, so anything
	# behind it is simply invisible. Same reason `CharacterRig.spawn_ghost` says so.
	s.z_index = 0
	return s


func _ready() -> void:
	add_to_group(GROUP)
	# See the header: the bot-match KO happens on a PAUSED tree, so a PAUSABLE death
	# animation would never draw a frame of itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_low = TuningConfig.quality_is_low()
	_start_ms = Time.get_ticks_msec()
	_rng_seed = int(global_position.x) * 73856093 + int(global_position.y) * 19349663
	_heap = _build_heap()
	set_process(true)


## Real seconds since spawn — NOT `+= delta`. See the header: `Engine.time_scale`
## drops to 0.05 on the killing blow and the tree is paused during a KO freeze, and
## the death has to play at real speed through both.
func _process(_delta: float) -> void:
	_age = float(Time.get_ticks_msec() - _start_ms) / 1000.0
	if _age >= duration:
		queue_free()
		return
	if launch_velocity != Vector2.ZERO:
		# Integrated against the SAME real clock as everything else here, so a frozen
		# tree cannot leave a corpse hanging in mid-flight.
		var step: float = minf(_delta, 1.0 / 30.0)
		global_position += launch_velocity * step
		launch_velocity = launch_velocity.move_toward(Vector2.ZERO, LAUNCH_DECAY * step)
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_age / duration, 0.0, 1.0)
	var fold: float = _fold_amount(t)
	var erase: float = _erase_amount(t)
	if erase < 1.0:
		var col: Color = Color(base_color.r, base_color.g, base_color.b,
			base_color.a * (1.0 - erase))
		CharacterRig.draw_figure(self, _blend_pose(fold), col, equipment_slots, fig_height)
	# The eraser itself, then what it leaves behind. Both are pure garnish and both
	# thin at LOW — the fold above and the fade are what carry the read.
	if erase > 0.0:
		_draw_strokes(t)
		_draw_smudge(erase)
		if not _low:
			_draw_crumbs(t)


# ═══════════════════════════════════════════════════════════════════ THE FOLD

## 0 -> 1 fold progress with a small overshoot near the end. A body drops, goes
## slightly past, and settles; easing politely into place reads as machinery.
func _fold_amount(t: float) -> float:
	var f: float = clampf(t / maxf(FOLD_FRACTION, 0.01), 0.0, 1.0)
	# Fast out of the gate (the legs give way), then settle.
	var eased: float = 1.0 - pow(1.0 - f, 3.0)
	# Overshoot rides a half-sine so it is zero at both ends and peaks mid-settle.
	return eased + FOLD_OVERSHOOT * sin(f * PI) * (1.0 - f)


## Where the body ends up: lying on its side, head toward `fall_dir`, limbs splayed.
## Built once in `_ready` from the snapshot's own ground line, so a body killed
## mid-air folds relative to where its feet WERE rather than to a hard-coded floor.
func _build_heap() -> Dictionary:
	var h: float = fig_height
	var gy: float = maxf(_p("foot_lead").y, _p("foot_off").y)
	var d: float = fall_dir
	var heap: Dictionary = {}
	heap["hip"] = Vector2(0.0, gy - h * HEAP_HIP_LIFT)
	heap["shoulder"] = Vector2(d * h * HEAP_SHOULDER_X, gy - h * HEAP_SHOULDER_LIFT)
	heap["head_center"] = Vector2(d * h * HEAP_HEAD_X, gy - h * HEAP_HEAD_LIFT)
	# The neck rides between the shoulder and the head so the spine stays a spine.
	heap["neck"] = (heap["shoulder"] as Vector2).lerp(heap["head_center"] as Vector2, 0.55)
	heap["hand_lead"] = Vector2(d * h * HEAP_HAND_LEAD_X, gy)
	heap["hand_off"] = Vector2(d * h * HEAP_HAND_OFF_X, gy)
	heap["foot_lead"] = Vector2(d * h * HEAP_FOOT_LEAD_X, gy)
	heap["foot_off"] = Vector2(d * h * HEAP_FOOT_OFF_X, gy - h * HEAP_FOOT_OFF_LIFT)
	return heap


## The drawn pose: the snapshot lerped toward the heap. Scalars (`w`, `r`, the hand
## and foot radii) are carried through untouched so a geared body keeps its gear.
func _blend_pose(fold: float) -> Dictionary:
	var out: Dictionary = pose.duplicate()
	for key: String in _heap:
		out[key] = _p(key).lerp(_heap[key] as Vector2, clampf(fold, 0.0, 1.2))
	return out


func _p(key: String) -> Vector2:
	var v: Variant = pose.get(key)
	return v as Vector2 if v is Vector2 else Vector2.ZERO


# ══════════════════════════════════════════════════════════════ THE RUB-OUT

## 0 -> 1 across the erase window. Squared so the lines hold for a moment and then
## go quickly, which is how a pencil mark actually lifts.
func _erase_amount(t: float) -> float:
	if t <= ERASE_START:
		return 0.0
	var e: float = (t - ERASE_START) / maxf(1.0 - ERASE_START, 0.01)
	return clampf(e * e, 0.0, 1.0)


## Eraser strokes sweeping across the heap, each in its own slice of the window so
## the figure comes apart in pieces rather than dissolving evenly.
##
## ⚠ BLOBS, NOT `draw_line`. The first version drew each stroke as one thick
## antialiased line, and at `STROKE_WIDTH_FACTOR` of a figure height that is a HARD
## GREY RECTANGLE with square-ish ends parked on top of the body — it read as a UI
## panel, not as a rubber. LOOKED AT, in `user://death_beat.png`, which is the only
## reason it was caught. Overlapping circles of jittered radius give the soft, uneven
## edge a rubbed pencil mark actually has, for the same handful of draw calls.
func _draw_strokes(t: float) -> void:
	var count: int = STROKES_LOW if _low else STROKES
	var h: float = fig_height
	var gy: float = maxf(_p("foot_lead").y, _p("foot_off").y)
	var span: float = h * STROKE_SPAN_FACTOR
	var radius: float = h * STROKE_WIDTH_FACTOR * 0.5
	for i: int in count:
		# Stagger the strokes across the erase window, overlapping by half so the
		# rubbing is continuous rather than three separate wipes.
		var slot: float = float(i) / float(maxi(count, 1))
		var local_t: float = (t - ERASE_START - slot * (1.0 - ERASE_START) * 0.5) \
			/ maxf((1.0 - ERASE_START) * 0.62, 0.01)
		if local_t <= 0.0 or local_t >= 1.0:
			continue
		# Alpha peaks mid-stroke: the rubber presses, then lifts.
		var a: float = sin(local_t * PI)
		var y: float = gy - h * (0.03 + 0.07 * float(i))
		var x0: float = fall_dir * (-span * 0.5 + span * local_t)
		var col: Color = Color(STROKE_COLOR.r, STROKE_COLOR.g, STROKE_COLOR.b,
			STROKE_COLOR.a * a)
		for b: int in STROKE_BLOBS:
			var f: float = float(b) / float(maxi(STROKE_BLOBS - 1, 1))
			var n: float = _noise(i * 11 + b)
			draw_circle(
				Vector2(x0 + fall_dir * h * 0.20 * f, y + (n - 0.5) * radius * 0.7),
				radius * (0.65 + 0.45 * n), col)


## Graphite crumbs flicked off by the rubbing, lifting and fading — the same motion
## `GhostForm` gives its motes, so a death and the ghost it becomes read as one idea.
func _draw_crumbs(t: float) -> void:
	var h: float = fig_height
	var gy: float = maxf(_p("foot_lead").y, _p("foot_off").y)
	var e: float = _erase_amount(t)
	for i: int in CRUMBS:
		var n: float = _noise(i)
		var life: float = clampf(e * (0.6 + 0.4 * n), 0.0, 1.0)
		if life <= 0.0:
			continue
		var x: float = fall_dir * (n - 0.5) * CRUMB_SPREAD
		var y: float = gy - h * 0.05 - CRUMB_RISE * life
		var a: float = (1.0 - life) * 0.9
		draw_circle(Vector2(x, y), maxf(0.8, h * 0.035),
			Color(CRUMB_COLOR.r, CRUMB_COLOR.g, CRUMB_COLOR.b, CRUMB_COLOR.a * a))


## What is left on the paper. Blooms as the figure goes and fades with it, so the
## death ends on a mark rather than on a pop.
func _draw_smudge(erase: float) -> void:
	var h: float = fig_height
	var gy: float = maxf(_p("foot_lead").y, _p("foot_off").y)
	# Rises to full at the moment the figure is gone, then fades.
	var a: float = sin(clampf(erase, 0.0, 1.0) * PI)
	if a <= 0.01:
		return
	draw_set_transform(Vector2(0.0, gy - h * 0.06), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, h * SMUDGE_RADIUS_FACTOR,
		Color(SMUDGE_COLOR.r, SMUDGE_COLOR.g, SMUDGE_COLOR.b, SMUDGE_COLOR.a * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Cheap deterministic 0..1 per index. Deterministic on purpose: a capture tool that
## renders the same death twice must get the same picture, or an A/B is worthless.
func _noise(i: int) -> float:
	var x: int = (_rng_seed + i * 2654435761) & 0x7fffffff
	x = (x ^ (x >> 13)) * 1274126177
	return float((x ^ (x >> 16)) & 0xffff) / 65535.0
