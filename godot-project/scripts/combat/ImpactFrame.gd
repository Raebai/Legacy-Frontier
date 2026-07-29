class_name ImpactFrame
extends CanvasLayer
## THE PUNCTUATION BEAT. For a few frames the world stops and the screen becomes a
## flat graphic mark — a white blow-out, a black silhouette cut, a field of the
## spell's own colour, a negative, or a letterboxed cut-in. Then it's gone and the
## fight continues. It is the cheapest way in the whole game to make a hit feel
## enormous, and it works for exactly one reason: it is RARE.
##
## This file is two things stapled together on purpose, because they only make
## sense as a pair:
##
##   1. A VOCABULARY of frame styles (see `Style`), each with a "use this when".
##      One style used everywhere is what killed the previous generation of impact
##      frames in this codebase: StarConvergence, EnergyNova and HollowPurple all
##      deliberately DELETED their impact frame, and the recorded reason (read
##      StarConvergence._slam) was that every ult ended in the same white
##      speed-line wash, so the most identity-bearing moment of each spell was the
##      moment they were most identical. The fix is not "stop using frames", it is
##      "stop using the SAME frame" — and specifically, a spell whose payoff is a
##      readable SHAPE (an eight-spoke wheel, a lance) wants a BLACK frame, which
##      silhouettes it, not a white one, which erases it.
##
##   2. An ARBITER (see `decide`) that makes it structurally impossible for a
##      barrage to strobe. A meteor avalanche lands 12 boulders in 0.34 s; a chain
##      reaction can request twenty frames in half a second. Without a global
##      referee "more impact frames" becomes an unreadable, exhausting, and
##      paradoxically LESS impactful screen. The arbiter is the thing that lets
##      the answer to "MORE IMPACT FRAMES" be yes.
##
## The arbiter also carries a hard photosensitive-seizure ceiling. Rapid
## full-screen black/white alternation is a genuine medical risk and a thing
## storefront accessibility reviews check for; see MAX_FULLSCREEN_FLASHES_PER_SECOND.
##
## Everything here runs on the REAL clock (`Time.get_ticks_msec`), never on
## `delta`. `Juice.hit_stop` drops `Engine.time_scale` to 0.05, and `delta` is
## scaled by it even under PROCESS_MODE_ALWAYS — so a 0.22 s frame driven by
## `delta` actually stayed on screen for over a second whenever it fired
## alongside a freeze, which is both why frames felt washy and why a duration
## budget expressed in `delta` could not have meant anything.

# ---------------------------------------------------------------- vocabulary
## The five full-screen marks plus the one localized fallback. Each entry says
## what it looks like and WHEN TO REACH FOR IT — the "when" is the load-bearing
## half, because picking the wrong one is how they all start looking the same.
enum Style {
	## WHITE BLOW-OUT + inward speed lines, blooming from the hit. The classic
	## "the world went white" concussion. USE FOR: physical impact — a heavy
	## punch, a boulder landing, a pillar erupting. AVOID FOR: anything whose
	## payoff is a drawn shape, because white erases the shape.
	BLOWOUT,
	## BLACK SILHOUETTE CUT: the screen drops to near-black and the only things
	## lit are a hairline horizon through the hit and a few hard radial wedges.
	## The classic anime cut, and usually more striking than white. USE FOR: the
	## release of an ult whose payoff is a READABLE SHAPE (a lance, a spoke
	## wheel, a beam) — black makes the shape legible instead of burying it.
	SILHOUETTE,
	## COLOUR FIELD: the screen becomes a flat field of the SPELL'S OWN element
	## colour, world ghosting through, with an emissive core at the hit. USE FOR:
	## elemental ult payoffs. This is the direct answer to "the ults are all
	## recolours" — a fire ult and an ice ult end on genuinely different screens.
	COLOR_FIELD,
	## NEGATIVE: the actual rendered frame, inverted, for a couple of frames. The
	## world stays perfectly readable (it is the same picture) while reading as
	## deeply wrong. USE FOR: shadow / void / reality-bending beats and reaction
	## payoffs — the "something impossible just happened" punctuation.
	INVERT,
	## CUT-IN: black letterbox bars slam in from top and bottom, leaving a band in
	## which THE FIGHTERS STAY DRAWN, with a bright slash across the hit. The
	## world freezes but you can still see who did what to whom. USE FOR: the
	## genuine climax — a boss death, a finisher. The most expensive mark in the
	## vocabulary; if it fires more than once a fight it stops being a climax.
	CUT_IN,
	## LOCALIZED RING: no full-screen field at all — a compact bright ring and a
	## few short ticks around the hit. Small area, low contrast, harmless to
	## repeat. USE FOR: the long tail of small deserving moments (an ordinary
	## enemy death, a parry) where a full-screen mark would be too much. ALSO the
	## automatic downgrade every full-screen style takes when reduce-flashing is
	## on, which is why it must always look like a deliberate effect and never
	## like a disabled one.
	LOCAL,
}


## How long each mark stays on screen, in REAL seconds. Short is the point: the
## beat has to be over before the player registers it as an interruption.
## UNTESTED GUESSES, all of them — these are the numbers to nudge if the frames
## read as either a blink or a stall.
const DURATION_BLOWOUT: float = 0.16
const DURATION_SILHOUETTE: float = 0.13
const DURATION_COLOR_FIELD: float = 0.15
const DURATION_INVERT: float = 0.07   # a negative reads instantly and outstays its welcome fastest
const DURATION_CUT_IN: float = 0.30   # the climax mark is allowed to be felt
const DURATION_LOCAL: float = 0.10


# ------------------------------------------------------------- the tier ladder
## A jab, a heavy spell, an ult and a genuine climax must NOT get the same mark —
## that hierarchy IS the feature. The shelf a spell sits on is already decided,
## once, by `SpellTier` (from its cast time / cooldown / cost), and the spell
## clash layer and the audio roster both already read it. This is deliberately
## the same rule and not a fourth scale, so that "an ult feels like an ult" means
## one thing across the whole game.
##
##   QUICK  -> LOCAL          a small ring; safe to see often
##   HEAVY  -> BLOWOUT        a real white pop
##   ULT    -> COLOR_FIELD    the element takes the screen (SILHOUETTE if the
##                            caller supplies no element, since a colour field
##                            with no colour is just a grey wash)
##   ULT + climax -> CUT_IN   the finisher
##
## `climax` is a flag rather than a fourth tier on purpose: a boss death and a
## finishing blow are not a heavier SHELF, they are an ult-weight beat that
## happens to be the last one.
const TIER_STRENGTH_QUICK: float = 0.55
const TIER_STRENGTH_HEAVY: float = 0.80
const TIER_STRENGTH_ULT: float = 1.15
const TIER_STRENGTH_CLIMAX: float = 1.40


## The ladder as a PURE lookup: (shelf, element, climax) -> {style, strength}.
## Split out from `Juice.tier_frame` so the mapping can be asserted headlessly
## without a scene tree, a camera or a rendered frame — the rung a spell lands on
## is a rule, and rules should be pinned by tests even when the thing they
## produce can only be judged by eye.
static func ladder(tier: int, element: int = -1, climax: bool = false) -> Dictionary:
	match tier:
		SpellTier.Tier.ULT:
			if climax:
				return {"style": Style.CUT_IN, "strength": TIER_STRENGTH_CLIMAX}
			# No element = no colour, and a colour field with no colour is a grey
			# wash. Fall back to the black cut, which needs no colour at all.
			return {
				"style": Style.COLOR_FIELD if element >= 0 else Style.SILHOUETTE,
				"strength": TIER_STRENGTH_ULT,
			}
		SpellTier.Tier.HEAVY:
			return {"style": Style.BLOWOUT, "strength": TIER_STRENGTH_HEAVY}
	return {"style": Style.LOCAL, "strength": TIER_STRENGTH_QUICK}


# ----------------------------------------------------------- ARBITER: the feel
## Minimum real-time gap between two full-screen marks. This is a FEEL knob: it
## is what keeps a frame reading as a punctuation beat rather than as a texture.
## Turn it DOWN if the fight feels under-punctuated; the safety ceiling below
## still holds regardless of what this is set to.
## UNTESTED GUESS.
const MIN_INTERVAL: float = 0.26
## The same gap for LOCAL rings, which are small and low-contrast and so may
## repeat far more freely.
const MIN_LOCAL_INTERVAL: float = 0.09
## How many localized rings may start inside any rolling second. Not a safety
## limit (a small low-contrast ring is not a flash) — purely "stop it looking
## like confetti in a crowd fight".
const MAX_LOCAL_PER_SECOND: int = 6
## A new request must beat the in-flight one by this much to supersede it, so a
## cluster of identical requests cannot churn the screen by replacing each other.
const SUPERSEDE_EPSILON: float = 0.12


# -------------------------------------------------- ARBITER: the SAFETY limits
## ⚠ SAFETY LIMIT — NOT A FEEL KNOB. DO NOT RAISE THIS TO MAKE THE GAME PUNCHIER.
##
## Rapid large-area high-contrast flashing is a photosensitive-seizure risk. The
## widely used guidance (WCAG 2.3.1 / the Harding-style broadcast rule both land
## in the same place) is: no more than THREE full-screen flashes in any one
## second, and general caution about large-area high-contrast alternation. We sit
## deliberately UNDER that at two, because our marks are large-area AND
## maximum-contrast (a full white field alternating with a full black one is the
## worst case the guidance describes), and because a rule that is only exactly at
## the limit has no margin for a frame that overruns.
##
## This is checked on a true SLIDING one-second window, not a reset bucket, so
## two frames either side of a bucket boundary cannot smuggle four into a second.
## If the game ever needs to be louder, make the individual marks bigger or the
## FEEL interval shorter — never this.
const MAX_FULLSCREEN_FLASHES_PER_SECOND: int = 2

## ⚠ SAFETY LIMIT — NOT A FEEL KNOB. The other half of the same rule: even two
## flashes a second is unacceptable if each covers most of that second, because
## then the screen is not being punctuated, it IS the flash. At most this
## fraction of any rolling second may be covered by full-screen marks.
## UNTESTED as a number; the RULE is not up for tuning.
const MAX_FRAME_SECONDS_PER_SECOND: float = 0.45

## The ceiling a LOCAL ring is clamped to when it is standing in for a
## downgraded full-screen mark, so "reduce flashing" genuinely reduces contrast
## rather than merely shrinking the same blaze.
const LOCAL_MAX_STRENGTH: float = 0.7


# -------------------------------------------------------------- arbiter state
## Modelled as plain integers rather than "is the node still alive", so the whole
## decision is a pure function of (request, now) and can be tested headlessly
## with an injected clock and no scene tree at all.
static var _active_until_ms: int = -1
static var _active_strength: float = 0.0
static var _active_is_local: bool = false
static var _active_node: ImpactFrame = null
static var _last_fullscreen_ms: int = -100000
static var _last_local_ms: int = -100000
## Sliding one-second history. Each entry is (start_ms, duration_ms) for a
## FULL-SCREEN mark; LOCAL rings are counted separately in `_local_history`
## because they are not flashes and must not eat the safety budget.
static var _history: Array[Vector2i] = []
static var _local_history: Array[int] = []


# ------------------------------------------------------------ instance render
var _t: float = 0.0
var _start_us: int = 0
var _style: int = Style.BLOWOUT
var _strength: float = 1.0
var _duration: float = DURATION_BLOWOUT
var _tint: Color = Color(1.0, 1.0, 1.0)
var _lines: bool = true
var _rect: Control = null
var _screen_plate: ColorRect = null
## World-space hit position the mark is built around. Vector2.INF = no position
## supplied -> viewport centre (the legacy behaviour, and still correct for a
## beat that belongs to the whole screen rather than to a place).
##
## ⚠ This used to not exist, and the flash always blew out screen CENTRE no
## matter where the blast was — the maker reported it as reading like a UI
## glitch. Every style below converges on `_convergence_point`; do not regress
## back to a centred draw.
var _world_pos: Vector2 = Vector2.INF


func _init() -> void:
	layer = 90  # above the world + HUD, below nothing important
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_start_us = Time.get_ticks_usec()
	_rect = Control.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_rect.draw.connect(_draw_frame)
	_build_screen_plate()


func _exit_tree() -> void:
	# Only clear the arbiter's model if WE are still the frame it is modelling —
	# a superseded frame is freed AFTER its replacement has already registered,
	# so an unguarded clear here would wipe the newcomer's slot and let the very
	# next request through unchecked.
	if _active_node == self:
		_active_node = null


## Configure a spawned frame. Kept as a method (rather than constructor args) so
## `Juice` can build it through a loaded GDScript with no static typing.
func configure(cfg: Dictionary) -> void:
	_style = int(cfg.get("style", Style.BLOWOUT))
	_strength = clampf(float(cfg.get("strength", 1.0)), 0.25, 1.6)
	_duration = maxf(float(cfg.get("duration", default_duration(_style))), 0.02)
	_tint = cfg.get("tint", Color(1.0, 1.0, 1.0))
	_lines = bool(cfg.get("lines", true))
	_world_pos = cfg.get("at", Vector2.INF)
	if is_inside_tree():
		_build_screen_plate()


func _process(_delta: float) -> void:
	# REAL time, deliberately: see the file header. `_delta` is ignored.
	var t: float = float(Time.get_ticks_usec() - _start_us) / 1_000_000.0
	if t >= _duration:
		queue_free()
		return
	apply_beat(t)


## Put the mark at an exact point in its own beat. Split out of `_process` so the
## capture tool (tools/impact_frame_capture.gd) can sample a frame at a chosen
## fraction of its life with `set_process(false)` — otherwise the shortest mark in
## the vocabulary (INVERT, 0.07 s) expires between two screenshot awaits and the
## capture silently renders nothing, which is indistinguishable from a mark that
## is broken.
func apply_beat(t: float) -> void:
	_t = t
	if _screen_plate != null and _screen_plate.material != null:
		# Both plate styles must be FULLY on from the very first frame — a mark
		# that fades in reads as a colour grade, not as a cut. They differ in how
		# they leave: the negative snaps off (it is 0.07 s long and any lingering
		# turns it into a wash), the black cut HOLDS and then lifts (that hold is
		# the whole "the world stopped" beat).
		var u: float = clampf(_t / _duration, 0.0, 1.0)
		var k: float = 1.0 - pow(u, 2.4) if _style == Style.SILHOUETTE else (1.0 - u) * 1.6
		(_screen_plate.material as ShaderMaterial).set_shader_parameter(
			&"amount", clampf(k, 0.0, 1.0) * clampf(_strength, 0.0, 1.0))
	if _rect != null:
		_rect.queue_redraw()


static func default_duration(style: int) -> float:
	match style:
		Style.SILHOUETTE:
			return DURATION_SILHOUETTE
		Style.COLOR_FIELD:
			return DURATION_COLOR_FIELD
		Style.INVERT:
			return DURATION_INVERT
		Style.CUT_IN:
			return DURATION_CUT_IN
		Style.LOCAL:
			return DURATION_LOCAL
	return DURATION_BLOWOUT


# ================================================================== THE ARBITER
## Decide whether a requested frame may play, and with what settings.
##
## PURE with respect to the scene tree — it reads only static state and the
## injected `now_ms` — so the whole referee is headlessly testable without
## rendering anything. It DOES mutate the sliding-window history, but only on a
## grant, so a dropped request leaves no trace.
##
## `req` keys (all optional):
##   style: int      a Style; default BLOWOUT
##   strength: float 0.25 .. 1.6
##   duration: float real seconds; default per style
##   reduce: bool    force the reduce-flashing path (tests); else read from Tuning
##
## Returns {granted, style, strength, duration, supersede, reason}. `reason` names
## which rule dropped it, so a "why did my frame not fire" is a one-line answer.
static func decide(req: Dictionary, now_ms: int = -1) -> Dictionary:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var style: int = int(req.get("style", Style.BLOWOUT))
	var strength: float = clampf(float(req.get("strength", 1.0)), 0.25, 1.6)
	var duration: float = maxf(float(req.get("duration", default_duration(style))), 0.02)
	# ACCESSIBILITY DOWNGRADE, applied before any budgeting so the cheaper mark
	# is also budgeted as the cheaper mark. Note this DOWNGRADES rather than
	# denies: the beat still happens, it just stops being a full-screen flash.
	# The hit-stop, shake and camera punch that surround it are untouched.
	var reduce: bool = bool(req["reduce"]) if req.has("reduce") else reduce_flashing()
	if reduce and style != Style.LOCAL:
		style = Style.LOCAL
		strength = minf(strength, LOCAL_MAX_STRENGTH)
		duration = minf(duration, DURATION_LOCAL)
	var out: Dictionary = {
		"granted": false, "style": style, "strength": strength,
		"duration": duration, "supersede": false, "reason": "",
	}
	_prune(now_ms)
	var is_local: bool = style == Style.LOCAL

	# --- rule 1: one mark at a time, and the STRONGER one wins outright.
	# A stronger request supersedes (kills + replaces) rather than queueing
	# behind — queueing is what turns a chain reaction into a strobe, because
	# every deferred frame eventually plays. Anything not strictly stronger is
	# DROPPED, never deferred.
	if now_ms < _active_until_ms:
		if strength <= _active_strength + SUPERSEDE_EPSILON:
			out["reason"] = "weaker_than_active"
			return out
		out["supersede"] = true
		# A superseded frame is killed on the spot, so it never spends the rest of
		# its booked time. Charging the budget for time that was never shown made
		# the second beat of a legitimate one-two (a heavy landing, then the ult
		# that follows it) refusable for a frame nobody saw. Truncate the booking
		# to what actually played.
		_truncate_active(now_ms)
	else:
		# --- rule 2: minimum interval (feel).
		var last: int = _last_local_ms if is_local else _last_fullscreen_ms
		var gap: float = MIN_LOCAL_INTERVAL if is_local else MIN_INTERVAL
		if now_ms - last < int(gap * 1000.0):
			out["reason"] = "min_interval"
			return out

	# --- rule 3: the ceilings. Checked LAST and applied to supersedes too: a
	# supersede swaps a white field for a black one, which is exactly the
	# high-contrast alternation the safety rule is about, so it must not be a
	# way around the budget.
	if is_local:
		if _local_history.size() >= MAX_LOCAL_PER_SECOND:
			out["reason"] = "local_rate"
			return out
	else:
		if _history.size() >= MAX_FULLSCREEN_FLASHES_PER_SECOND:
			out["reason"] = "flash_rate_ceiling"
			return out
		var budget_ms: int = int(MAX_FRAME_SECONDS_PER_SECOND * 1000.0)
		if _spent_ms() + int(duration * 1000.0) > budget_ms:
			out["reason"] = "frame_time_budget"
			return out

	# --- granted: record it.
	out["granted"] = true
	if is_local:
		_local_history.append(now_ms)
		_last_local_ms = now_ms
	else:
		_history.append(Vector2i(now_ms, int(duration * 1000.0)))
		_last_fullscreen_ms = now_ms
	_active_until_ms = now_ms + int(duration * 1000.0)
	_active_strength = strength
	_active_is_local = is_local
	return out


## Shorten the in-flight frame's booked duration to the time it actually got,
## because it is about to be replaced. Only full-screen bookings carry a duration
## (LOCAL rings are counted, not timed), so a superseded local needs nothing.
static func _truncate_active(now_ms: int) -> void:
	if _active_is_local or _history.is_empty():
		return
	var last: Vector2i = _history[_history.size() - 1]
	var shown: int = maxi(now_ms - last.x, 0)
	if shown < last.y:
		_history[_history.size() - 1] = Vector2i(last.x, shown)


## Drop history entries older than the sliding window. A true sliding window
## (not a bucket that resets on the second) is the whole point: with a resetting
## bucket, two frames just before a reset plus two just after are four flashes
## inside one real second while every individual check passed.
static func _prune(now_ms: int) -> void:
	while _history.size() > 0 and now_ms - _history[0].x >= 1000:
		_history.remove_at(0)
	while _local_history.size() > 0 and now_ms - _local_history[0] >= 1000:
		_local_history.remove_at(0)


## Total full-screen frame time started inside the sliding window, in ms.
static func _spent_ms() -> int:
	var total: int = 0
	for e: Vector2i in _history:
		total += e.y
	return total


## Test hook + arena teardown: forget everything. Not called in normal play.
static func reset_arbiter() -> void:
	_active_until_ms = -1
	_active_strength = 0.0
	_active_is_local = false
	_active_node = null
	_last_fullscreen_ms = -100000
	_last_local_ms = -100000
	_history.clear()
	_local_history.clear()


## Accessibility option: full-screen flashes downgrade to the localized ring.
## Read through the tree rather than by naming the `Tuning` autoload, because
## naming an autoload inside a STATIC function is a compile error that takes the
## whole dependency chain down with a misleading message (see SpellDeflect._sfx).
static func reduce_flashing() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var t: Node = tree.root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		return false
	var v: Variant = t.cfg.get(&"reduce_flashing")
	return v != null and bool(v)


## Spawn a decided frame, killing whatever it superseded. Returns the node, or
## null when the arbiter said no. `Juice` is the only caller.
static func spawn(decision: Dictionary, at: Vector2, tint: Color, lines: bool) -> ImpactFrame:
	if not bool(decision.get("granted", false)):
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	if bool(decision.get("supersede", false)) and _active_node != null \
			and is_instance_valid(_active_node):
		var old: ImpactFrame = _active_node
		_active_node = null   # so the old node's _exit_tree guard is a no-op
		old.queue_free()
	var f := ImpactFrame.new()
	f.configure({
		"style": decision["style"], "strength": decision["strength"],
		"duration": decision["duration"], "at": at, "tint": tint, "lines": lines,
	})
	tree.root.add_child(f)
	_active_node = f
	return f


# ==================================================================== rendering
## The NEGATIVE. No CanvasItemMaterial blend mode computes 1-dst (SUB gives
## dst-src, which just goes black), so this needs the rendered frame back.
const SHADER_INVERT: String = """shader_type canvas_item;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
void fragment() {
	vec3 s = texture(screen_tex, SCREEN_UV).rgb;
	COLOR = vec4(mix(s, vec3(1.0) - s, amount), 1.0);
}
"""

## The BLACK CUT, and the reason it is a shader rather than a black rectangle.
##
## ⚠ RENDERED AND LOOKED AT: painting an opaque black rect over the screen is
## the obvious implementation and it is WRONG. It buries the spell exactly as
## badly as the white blow-out did, only darker — the eight-spoke wheel this
## style exists to preserve came out as three barely-visible navy scratches. The
## whole premise ("black silhouettes the shape, white erases it") is only true if
## the black is a CUT-OUT rather than a coat of paint.
##
## So: threshold the rendered frame by luminance. Everything below the cut goes
## to pure black — floor, platforms, background, all of it — and everything above
## survives at full brightness. The things above the cut are precisely the things
## worth looking at: the HDR spell cores, the bolts, and the fighters' own body
## colours. That is a real silhouette frame, and it is why this style can be used
## on a beam or a spoke wheel where the white one could not.
##
## `cut` is the one number to move if too much or too little survives.
const SHADER_SILHOUETTE: String = """shader_type canvas_item;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float cut : hint_range(0.0, 1.5) = 0.55;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
void fragment() {
	vec3 s = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(s, vec3(0.30, 0.60, 0.10));
	float keep = smoothstep(cut - 0.20, cut + 0.08, l);
	COLOR = vec4(mix(s, s * keep, amount), 1.0);
}
"""

## Luminance below which the world is cut to black by SHADER_SILHOUETTE. Tuned by
## eye against the staged capture: the arena floor (~0.23) and blocks (~0.28) go,
## the fighters (~0.7+) and every spell core stay.
## UNTESTED GUESS in game — raise it for a harsher cut, lower it to keep more of
## the room.
const SILHOUETTE_CUT: float = 0.55


## Build the full-screen shader plate for the two styles that TRANSFORM the
## rendered frame rather than paint on top of it. Every other style draws with
## plain `draw_*` calls and needs no plate.
func _build_screen_plate() -> void:
	if _screen_plate != null:
		return
	var code: String = ""
	match _style:
		Style.INVERT:
			code = SHADER_INVERT
		Style.SILHOUETTE:
			code = SHADER_SILHOUETTE
		_:
			return
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter(&"cut", SILHOUETTE_CUT)
	_screen_plate = ColorRect.new()
	_screen_plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_plate.material = mat
	# Below `_rect` so the bright accents drawn there sit on top of the plate.
	add_child(_screen_plate)
	move_child(_screen_plate, 0)


func _draw_frame() -> void:
	var u: float = clampf(_t / _duration, 0.0, 1.0)
	var vp: Vector2 = _rect.size
	var c: Vector2 = _convergence_point(vp)
	match _style:
		Style.SILHOUETTE:
			_draw_silhouette(u, vp, c)
		Style.COLOR_FIELD:
			_draw_color_field(u, vp, c)
		Style.INVERT:
			_draw_invert_accents(u, vp, c)
		Style.CUT_IN:
			_draw_cut_in(u, vp, c)
		Style.LOCAL:
			_draw_local(u, vp, c)
		_:
			_draw_blowout(u, vp, c)


## WHITE BLOW-OUT. Preserved verbatim from the original frame, because it is the
## one style that has been looked at and signed off, and because it is still the
## right answer for a physical impact.
func _draw_blowout(u: float, vp: Vector2, c: Vector2) -> void:
	var fade: float = 1.0 - u
	var diag: float = vp.length()
	if u < 0.35:
		var flash_a: float = (1.0 - u / 0.35) * _strength
		# A weak whole-screen lift keeps the "the world went white" concussion...
		_rect.draw_rect(Rect2(Vector2.ZERO, vp), Color(1.4, 1.4, 1.5, 0.10 * flash_a))
		# ...while the blowout itself sits ON the blast and expands with it.
		var rings: int = 7
		var peak: float = diag * 0.23 * (0.75 + 0.85 * u)
		for i in rings:
			var t: float = float(i) / float(rings - 1)   # 0 = outermost ring
			_rect.draw_circle(c, peak * (1.0 - t * 0.86),
				Color(1.4, 1.4, 1.5, 0.13 * flash_a), true, -1.0, true)
	if not _lines:
		return
	# Radial speed lines rushing inward from the edges toward the center.
	var n: int = 44
	var col: Color = Color(0.04, 0.04, 0.07, 0.8 * fade * _strength)
	var inner: float = diag * (0.16 + 0.18 * u)
	for i in n:
		var a: float = TAU * float(i) / float(n) + sin(float(i) * 12.3) * 0.06
		var d: Vector2 = Vector2.from_angle(a)
		var w: float = (2.0 + 6.0 * absf(sin(float(i) * 7.7))) * _strength
		_rect.draw_line(c + d * inner, c + d * diag * 0.8, col, w)


## BLACK SILHOUETTE CUT. The screen drops out and what remains is a graphic mark:
## a hairline horizon running through the hit, and a handful of hard wedges. This
## is HollowPurple's own language — its most striking beat is a black core with a
## white horizon, not more brightness — generalized so any spell can borrow it.
##
## The horizon EXPANDS out of the hit rather than being drawn full width from
## frame one, so the eye is pulled to where the thing actually happened.
func _draw_silhouette(u: float, vp: Vector2, c: Vector2) -> void:
	var diag: float = vp.length()
	# ⚠ NO BLACK RECT HERE. The blackout is the luminance CUT-OUT done by
	# SHADER_SILHOUETTE on the plate below this one — see that constant for the
	# rendered evidence that painting black instead buries the very shape this
	# style exists to reveal. All that is drawn here is the graphic mark on top.
	#
	# The hairline horizon, blown out past white so it survives the bloom pass.
	var reach: float = vp.x * (0.25 + 1.1 * u)
	var thick: float = maxf(1.0, 3.5 * (1.0 - u) * _strength)
	var line_col: Color = Color(_tint.r * 1.8 + 0.6, _tint.g * 1.8 + 0.6, _tint.b * 1.8 + 0.6,
		clampf(1.0 - u * 0.7, 0.0, 1.0))
	_rect.draw_line(Vector2(c.x - reach, c.y), Vector2(c.x + reach, c.y), line_col, thick)
	# Hard wedges: few, wide, and irregular, so this cannot be mistaken for the
	# 44 even speed lines of the blow-out.
	if not _lines:
		return
	var n: int = 6
	for i in n:
		var a: float = TAU * float(i) / float(n) + 0.35 + sin(float(i) * 3.1) * 0.5
		var d: Vector2 = Vector2.from_angle(a)
		var w: float = (5.0 + 9.0 * absf(sin(float(i) * 5.3))) * _strength * (1.0 - u)
		_rect.draw_line(c + d * diag * 0.10, c + d * diag * (0.3 + 0.5 * u), line_col, w)


## COLOUR FIELD. The screen becomes the element. The world is still faintly
## there (this is a wash, not a blackout), the edges darken so the field reads as
## a frame rather than as a bug, and an emissive core sits on the hit.
##
## This is the style that makes two ults of different elements END DIFFERENTLY,
## which was the specific complaint that got impact frames removed from three
## spells in this codebase.
func _draw_color_field(u: float, vp: Vector2, c: Vector2) -> void:
	var diag: float = vp.length()
	var k: float = 1.0 - pow(u, 1.7)
	var field := Color(_tint.r, _tint.g, _tint.b, 0.62 * k * _strength)
	_rect.draw_rect(Rect2(Vector2.ZERO, vp), field)
	# Darkened corners: four fat edge bands, cheaper than a real vignette and
	# graphic enough at this duration that nobody will read it as a gradient.
	var band: float = vp.y * 0.16
	var dark := Color(0.0, 0.0, 0.02, 0.5 * k)
	_rect.draw_rect(Rect2(Vector2.ZERO, Vector2(vp.x, band)), dark)
	_rect.draw_rect(Rect2(Vector2(0.0, vp.y - band), Vector2(vp.x, band)), dark)
	# The hot core, expanding out of the hit.
	var rings: int = 6
	var peak: float = diag * 0.20 * (0.6 + 1.1 * u)
	for i in rings:
		var t: float = float(i) / float(rings - 1)
		_rect.draw_circle(c, peak * (1.0 - t * 0.85),
			Color(_tint.r * 1.6 + 0.35, _tint.g * 1.6 + 0.35, _tint.b * 1.6 + 0.35,
				0.16 * k * _strength), true, -1.0, true)


## NEGATIVE. The inversion itself is done by the shader on `_screen_plate`; all
## this adds is a thin bright rim at the hit so the eye still knows where to
## look. Deliberately minimal — the whole point of this style is that the picture
## is unchanged apart from being wrong.
func _draw_invert_accents(u: float, _vp: Vector2, c: Vector2) -> void:
	var k: float = 1.0 - u
	var r: float = 40.0 + 260.0 * u
	_rect.draw_arc(c, r, 0.0, TAU, 48,
		Color(1.6, 1.6, 1.7, 0.5 * k * _strength), 3.0 * _strength, true)


## CUT-IN. Black bars slam in from top and bottom and stop, leaving a band the
## fight is still visible inside — the "hold on the silhouette while the world
## freezes" beat. A bright slash rakes across the band through the hit.
##
## The bars EASE IN over the first fifth of the duration and then hold, rather
## than being static: the slam is most of the drama, and a bar that is simply
## there on frame one reads as a letterbox, not as a hit.
func _draw_cut_in(u: float, vp: Vector2, c: Vector2) -> void:
	var slam: float = clampf(u / 0.18, 0.0, 1.0)
	slam = 1.0 - pow(1.0 - slam, 3.0)   # ease-out: fast in, settles hard
	# Band height shrinks toward BAND_FRACTION of the screen as the bars close.
	var band_frac: float = 0.34
	var half_band: float = vp.y * lerpf(0.5, band_frac * 0.5, slam)
	# Not quite opaque, deliberately: at 0.97 the fighters outside the band vanished
	# completely and the frame read as a screen wipe. A hair of transparency keeps
	# them as ghosts, so the cut still says "look HERE" without deleting the fight.
	var bar_col := Color(0.0, 0.0, 0.02, 0.90)
	var top_h: float = maxf(c.y - half_band, 0.0)
	var bot_y: float = minf(c.y + half_band, vp.y)
	_rect.draw_rect(Rect2(Vector2.ZERO, Vector2(vp.x, top_h)), bar_col)
	_rect.draw_rect(Rect2(Vector2(0.0, bot_y), Vector2(vp.x, vp.y - bot_y)), bar_col)
	# Hot rims on the bar edges — the bars read as cut metal, not as black paper.
	var rim := Color(_tint.r * 1.7 + 0.5, _tint.g * 1.7 + 0.5, _tint.b * 1.7 + 0.5, 0.9 * (1.0 - u))
	_rect.draw_line(Vector2(0.0, top_h), Vector2(vp.x, top_h), rim, 2.5)
	_rect.draw_line(Vector2(0.0, bot_y), Vector2(vp.x, bot_y), rim, 2.5)
	# The slash: a diagonal streak through the hit, drawn only after the bars land.
	if u > 0.16:
		var s: float = clampf((u - 0.16) / 0.30, 0.0, 1.0)
		var d := Vector2(0.94, -0.34).normalized()
		var len_px: float = vp.x * (0.35 + 0.9 * s)
		_rect.draw_line(c - d * len_px, c + d * len_px,
			Color(1.9, 1.9, 2.0, 0.85 * (1.0 - s)), maxf(1.5, 7.0 * (1.0 - s)) * _strength)


## LOCALIZED RING. Small, low-contrast, harmless to repeat — and the shape every
## full-screen style becomes when reduce-flashing is on. Drawn as a bright
## expanding ring plus a handful of short outward ticks, so it still reads as a
## deliberate punctuation and not as "the effect failed to play".
func _draw_local(u: float, _vp: Vector2, c: Vector2) -> void:
	var k: float = 1.0 - u
	var r: float = 26.0 + 150.0 * u * _strength
	var col := Color(_tint.r * 1.5 + 0.4, _tint.g * 1.5 + 0.4, _tint.b * 1.5 + 0.4, 0.75 * k)
	_rect.draw_arc(c, r, 0.0, TAU, 40, col, maxf(1.5, 6.0 * k * _strength), true)
	_rect.draw_circle(c, r * 0.35, Color(col.r, col.g, col.b, 0.28 * k), true, -1.0, true)
	if not _lines:
		return
	for i in 8:
		var a: float = TAU * float(i) / 8.0 + 0.2
		var d: Vector2 = Vector2.from_angle(a)
		_rect.draw_line(c + d * r * 1.05, c + d * (r * 1.05 + 26.0 * k * _strength),
			col, 3.0 * _strength)


## Screen-space point every style is built around: the world hit position
## projected through the active camera's canvas transform, clamped a margin
## inside the screen so near-edge / off-screen hits still read. No world
## position -> viewport centre (backward-compatible default).
func _convergence_point(vp: Vector2) -> Vector2:
	if not _world_pos.is_finite():
		return vp * 0.5
	var screen: Vector2 = _rect.get_viewport().get_canvas_transform() * _world_pos
	var margin: Vector2 = vp * 0.12
	return screen.clamp(margin, vp - margin)
