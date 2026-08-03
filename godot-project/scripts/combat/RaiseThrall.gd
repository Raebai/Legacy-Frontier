extends Node2D
## ══ RAISE THRALL ══════════════════════════════════════════════════════════════
## The Warlock reaches into the floor and pulls a body out of it. It fights for him
## and then it comes apart — and the coming apart is the spell, not a limitation of
## it. (`Thrall.gd` is the body; this file is the ceremony that produces it, and the
## only place the cap, the grave rule and the co-op rule are decided.)
##
## ── THE GRAVE IS THE POINT ────────────────────────────────────────────────────
## "Summon the dead" has to mean the DEAD, or it is a turret with a skull on it. So
## a raise checks the ground it is aimed at for a body that recently fell there, and
## a raise ON a grave is strictly the better one: it comes up faster, with more hp,
## it stands for longer, and a rich grave yields TWO. A raise on bare floor still
## works — the spell must never fizzle — it is just a thinner, shorter-lived thing
## dragged out of nothing.
##
## ⚠ THE GRAVES ARE CLAIMED AT CAST TIME, NOT AT RESOLVE TIME, and that ordering is
## load-bearing rather than tidy. The only corpse marker this codebase has is
## `DeathSmudge`, whose whole life is `DURATION = 0.52 s` (it is a rub-out beat, not
## a body). With a `RAISE_WINDUP` of 0.7 s, a resolve-time scan would find the smudge
## GONE every single time and the corpse rule would silently never fire — the exact
## shape of bug this repo keeps writing warnings about. Claiming at cast time also
## reads better: you mark the body, the ink fades, and the ceremony carries on over
## the spot you already took.
##
## `note_grave()` widens that 0.52 s window to `GRAVE_MEMORY_MS` for anything that
## chooses to report a death. Nothing calls it yet — it is a one-line hook for
## `Enemy._die()` (a file this agent does not own); until something does, the smudge
## group alone is the corpse channel and the spell is fully functional on it.
##
## ── THE CAP IS NOT OPTIONAL ───────────────────────────────────────────────────
## Two independent ceilings, mirroring the enemy SUMMONER (`Enemy.gd:149-152`) so
## both sides of the board obey one rule:
##   1. `THRALL_MAX_ALIVE` per OWNER — a private cap, so two Warlocks in co-op each
##      get their own hand rather than sharing one.
##   2. The floor's `MAX_LIVE_ENTITIES` budget, asked of the `Encounter` through the
##      Arena exactly as `Enemy._spawn_headroom` asks it. A spawner that keeps a
##      private cap and never asks the floor is how the 25-entity budget was bypassed
##      once already.
## Unlike the summoner, hitting cap (1) does not FIZZLE the cast: it RECYCLES. See
## `RECYCLE_OLDEST_AT_CAP`.
##
## ── THE SPECTACLE CONTRACT ────────────────────────────────────────────────────
## Dispatched through `SpellCaster`'s `Kind.HEX` fork (registry `HEX_SCRIPTS`), fixed
## entry `hex(caster, origin, target, spell, color, fx)`. All five stamped properties
## are DECLARED below — `set()` on an undeclared property is a silent no-op, and a
## missing `caster_node` would be doubly fatal here because the caster is also the
## OWNER: unowned thralls answer to nobody, count against no cap and cannot be
## swapped with. Element is a real SHADOW, never -1.
##
## Parked at the arena origin like every spectacle in this codebase: `global_position`
## is (0,0) and is NOT where the effect is. Everything below is drawn and resolved in
## explicit world coordinates.

# ───────────────────────────────────────────── the five stamped identity fields
var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.SHADOW
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

const THRALL_SCENE: String = "res://scenes/combat/Thrall.tscn"
const THRALL_SCRIPT: String = "res://scripts/combat/Thrall.gd"

# ═════════════════════════════════════════════════════════ THE CAP
## Concurrent thralls PER OWNER. One below the enemy summoner's `SUMMON_MAX_ALIVE`
## (4) on purpose: a thrall is meaningfully stronger than a summoner's chaff, and
## three bodies is already the point at which a one-screen floor stops reading.
const THRALL_MAX_ALIVE: int = 3
## Bodies per cast off BARE GROUND, and off a GRAVE. The grave case is the whole
## incentive to aim at something you killed rather than at your feet.
const RAISE_COUNT_BARE: int = 1
const RAISE_COUNT_GRAVE: int = 2
## ⚠ AT CAP, THE OLDEST IS CONSUMED RATHER THAN THE CAST BEING REFUSED.
##
## `Enemy._spawn_minions` clamps to zero and simply summons nothing, which is right
## for an AI (nobody is holding the button and feeling cheated). For a PLAYER spell,
## spending 58 MP and a 6.4 s cooldown to watch nothing happen is the worst outcome
## in the game — so a fourth raise pulls the oldest body back down and stands a fresh
## one up in its place. The population ceiling is identical either way; only the
## feedback changes, and it changes from "broken" to "the dead are recycled", which
## is on-theme. The floor's ENTITY budget is still absolute — see `_headroom`.
const RECYCLE_OLDEST_AT_CAP: bool = true

# ═════════════════════════════════════════════════════════ THE GRAVE
## How far from the aim point a fallen body still counts as the grave you meant.
## Generous, because the aim is a thumb on a phone and the corpse is a fading smudge.
const GRAVE_RADIUS: float = 118.0
## How long a REPORTED death (see `note_grave`) stays raisable. Six seconds is about
## two exchanges — long enough that "kill it, then raise it" is a plan, short enough
## that the floor is not a permanent graveyard.
const GRAVE_MEMORY_MS: int = 6000
## Ring-buffer ceiling on the grave log, so a long floor cannot grow it without bound.
const MAX_GRAVES: int = 24

## What a body raised from each source is worth. The grave line is better in all
## three dimensions at once, deliberately: one clearly-better case is a decision, and
## three marginal ones are a spreadsheet.
const BARE_HP: int = 22
const BARE_LIFE: float = 9.0
const GRAVE_HP: int = 34
const GRAVE_LIFE: float = 15.0

# ═════════════════════════════════════════════════════════ THE CEREMONY
## Cast -> body. Long enough to be a ritual and to be interrupted by killing the
## Warlock; short enough that it is not a channel. Under `Enemy`'s shortest attack
## windup (0.6) would make it read as a tell, so it sits just above.
const RAISE_WINDUP: float = 0.7
## Afterglow once the bodies are up — the grave marks burn out rather than blink off.
const AFTERGLOW: float = 0.4
## Hands clawing out of each mark as the fill completes. Halved on the cheap picture.
const HANDS: int = 7
const HANDS_LOW: int = 3
## Grave sigil radius in world px, and how far it is squashed to lie on the floor.
## Sized against the capture frames rather than guessed: at 34 the marks read as
## coins beside the caster's own summoning circle, and the ceremony is supposed to
## be the loudest thing in the shot.
const SIGIL_R: float = 46.0
const SIGIL_SQUASH: float = 0.36
## Horizontal gap between two bodies coming up from the same cast. A touch wider than
## the mark so the rings read as two graves rather than one smeared one.
const SPREAD: float = 58.0
## How far ABOVE the mark a body is placed. The mark sits ON the floor surface, and a
## `CharacterBody2D` whose origin is on that surface is half inside the collider — it
## either pops out on the first physics frame or sinks. Half a body up, and gravity
## does the rest in three frames.
const RISE_OFFSET: float = 14.0
## Redraw rate. The mark is re-derived from `progress` every time, so a low rate
## reads as a hand working rather than as a low frame rate (SpawnTell's trick).
const REDRAW_HZ_HIGH: float = 30.0
const REDRAW_HZ_LOW: float = 15.0

# ═════════════════════════════════════════════════════════ CO-OP
## ⚠ CAN A CLIENT WARLOCK RAISE? NOT IN THIS PASS, AND THE FAILURE IS SAFE.
##
## Thralls replicate exactly the way summoner minions and boss adds already do:
## through `Arena.spawn_extra_enemy`, which routes to the Arena's `MultiplayerSpawner`
## when a session is live. That makes them HOST-AUTHORITATIVE (authority = peer 1,
## set by `Arena._spawn_enemy_net`), gives them the inherited code-built
## `MultiplayerSynchronizer` streaming position/velocity/hp, and leaves damage on the
## existing victim-authority router (`Enemy.take_damage` / `Hero.take_damage` both
## self-forward).
##
## `MultiplayerSpawner.spawn()` may only be called by the spawner's authority, i.e.
## the host. There is no generic "ask the host to spawn X" RPC in `Net.gd` and adding
## one is an edit to a file this agent does not own. So a CLIENT Warlock plays the
## full ceremony and no body arrives. That is a missing feature, not a desync — the
## alternative (spawning a body locally on the client) would have the client's minion
## killing enemies the host believes are untouched, which is the one thing the brief
## forbids. Flip this to true only together with the `Net` request-RPC named in the
## handoff.
const COOP_CLIENT_MAY_RAISE: bool = false

# ─────────────────────────────────────────────────────────────────── grave log
## Reported deaths: `{"p": Vector2, "t": int_ms}`. A STATIC, like `SpellDrops.climb_seed`
## and `FloorGen.climb_seed`, so a headless suite and a capture tool can drive it the
## same way the game does.
##
## ⚠ NO AUTOLOAD MAY BE NAMED IN A STATIC FUNCTION IN THIS REPO — doing so breaks the
## whole compile chain under `--script`. `Time` is an engine singleton, not an
## autoload, so it is safe here; nothing else in this block touches the tree.
static var _graves: Array[Dictionary] = []


## Report a body falling at `at` so a raise within `GRAVE_MEMORY_MS` can use it.
## Idempotent-ish and allocation-cheap; safe to call from anywhere, including from
## inside a death handler.
static func note_grave(at: Vector2) -> void:
	_graves.append({"p": at, "t": Time.get_ticks_msec()})
	while _graves.size() > MAX_GRAVES:
		_graves.pop_front()


## Every reported grave still inside the memory window, freshest LAST. Prunes in
## place, so the log self-maintains without a ticker.
static func recent_graves() -> Array[Vector2]:
	var now: int = Time.get_ticks_msec()
	var kept: Array[Dictionary] = []
	var out: Array[Vector2] = []
	for g: Dictionary in _graves:
		if now - int(g["t"]) <= GRAVE_MEMORY_MS:
			kept.append(g)
			out.append(g["p"] as Vector2)
	_graves = kept
	return out


## Test hook — a suite that seeds graves must be able to unseed them, because a
## static survives between suites in the same process.
static func clear_graves() -> void:
	_graves.clear()


# ─────────────────────────────────────────────────────────────────── instance
var _color: Color = Color(0.62, 0.45, 0.88)
var _origin: Vector2 = Vector2.ZERO
var _marks: Array[Vector2] = []      # world points a body is coming out of
var _on_grave: bool = false
var _t: float = 0.0
var _raised: bool = false
var _life: float = RAISE_WINDUP + AFTERGLOW
var _low: bool = false
var _next_draw: float = 0.0
var _seed: int = 0
var _raised_bodies: Array = []
## ENTERED / COMPLETED — the `_draw` half of this repo's completion-sentinel idiom.
## A runtime error inside `_draw` aborts the function and the engine emits `draw`
## anyway, so "it drew" proves nothing; `entered > completed` is what a headless
## suite can actually see.
var _draw_entered: int = 0
var _draw_done: int = 0


func hex(caster: Node, origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_color = color
	_origin = origin
	_seed = randi()
	_low = TuningConfig.quality_is_low()
	global_position = Vector2.ZERO   # world-space draw, like every spectacle here
	_claim_graves(target)
	if spell != null and spell.length > 0.1:
		# `length` doubles as the ceremony duration, the same double-duty ZONE gives
		# it for a field lifetime. Absent -> the constant.
		_life = maxf(spell.length, 0.2) + AFTERGLOW
	else:
		_life = RAISE_WINDUP + AFTERGLOW
	SpellSigil.open(self, origin, color, 1.15, false, Vector2.UP, true, 0.16, 0.5)
	SpellDrops.sfx("shadow_cast", -2.0, 0.1, 0.78)
	Juice.zoom_pull_camera(0.12, RAISE_WINDUP, 0.14, 0.5)
	Juice.shake_camera(3.5)
	queue_redraw()


## Which ground the bodies come out of, decided ONCE, now. See the cast-time note in
## the header for why this cannot wait for the windup to finish.
func _claim_graves(target: Vector2) -> void:
	_marks.clear()
	var found: Array[Vector2] = []
	# 1. Reported deaths (the wide window, if anything is feeding `note_grave`).
	for p: Vector2 in recent_graves():
		if p.distance_to(target) <= GRAVE_RADIUS:
			found.append(p)
	# 2. The rub-out beat still on screen — the only corpse marker this codebase
	#    ships, and a 0.52 s one. Cheap to scan and it costs nothing when empty.
	var tree: SceneTree = get_tree()
	if tree != null:
		for s: Node in tree.get_nodes_in_group(&"death_smudge"):
			if not (s is Node2D) or not is_instance_valid(s):
				continue
			var sp: Vector2 = (s as Node2D).global_position
			if sp.distance_to(target) <= GRAVE_RADIUS:
				found.append(sp)
	_on_grave = not found.is_empty()
	var want: int = RAISE_COUNT_GRAVE if _on_grave else RAISE_COUNT_BARE
	for i: int in want:
		if i < found.size():
			_marks.append(_on_floor(found[i]))
		else:
			# Fill from bare floor, fanned along X so two bodies never come up inside
			# one another.
			#
			# ⚠ ALONG X, NOT AROUND A CIRCLE. This was a radial fan
			# (`Vector2.from_angle(a) * r`) for exactly one capture pass, and the
			# frames showed the problem immediately: a mark rolled to +90° is a
			# summoning circle floating in mid-air with a body climbing out of
			# nothing. Bodies come out of the FLOOR. Only x may vary.
			var slot: float = float(i) - float(want - 1) * 0.5
			var jitter: float = (_hash01(_seed + i * 7) - 0.5) * SPREAD * 0.5
			_marks.append(_on_floor(target + Vector2(slot * SPREAD + jitter, 0.0)))


## `p` dropped onto the floor beneath it. `floor_point` returns `p` UNCHANGED when
## there is no floor (a pit, or a headless harness with no physics world), which is
## the right degradation both times: over a pit the mark stays where it was aimed and
## the body simply falls, and headlessly there is no floor to disagree with.
func _on_floor(p: Vector2) -> Vector2:
	return SpellWorld.floor_point(p, SpellWorld.FLOOR_PROBE, [], self)


func _physics_process(delta: float) -> void:
	_t += delta
	if not _raised and _t >= RAISE_WINDUP:
		_raised = true
		_raise()
	if _t >= _life:
		queue_free()
		return
	_next_draw -= delta
	if _next_draw <= 0.0:
		_next_draw = 1.0 / (REDRAW_HZ_LOW if _low else REDRAW_HZ_HIGH)
		queue_redraw()


# ─────────────────────────────────────────────────────────────────── the raise
## The tell paid off. Everything that can refuse a body refuses it HERE — not at cast
## time — because 0.7 s is long enough for the floor to fill up, for the owner to die,
## or for the arena to be torn down under us.
func _raise() -> void:
	var arena: Node = get_parent()
	if arena == null or not is_instance_valid(arena) or caster_node == null \
			or not is_instance_valid(caster_node):
		return
	var script: GDScript = load(THRALL_SCRIPT) as GDScript
	if script == null:
		return
	# Reached through `call()` rather than as `script.live_for(...)`: the static lives
	# on a script this file only holds as a `GDScript` resource, and a dynamic call
	# cannot be broken by the analyzer's view of that type.
	var live: Array = script.call(&"live_for", get_tree(), caster_node) as Array
	var want: int = _marks.size()
	# CAP 1 — the owner's own hand. Recycle from the front (group order is insertion
	# order, so `live[0]` is the oldest standing body) until there is room.
	var over: int = (live.size() + want) - THRALL_MAX_ALIVE
	if over > 0:
		if not RECYCLE_OLDEST_AT_CAP:
			want = maxi(want - over, 0)
		else:
			for i: int in mini(over, live.size()):
				var old: Node = live[i]
				if is_instance_valid(old) and old.has_method(&"dismiss"):
					old.call(&"dismiss")
	# CAP 2 — the floor's absolute entity budget. Asked, never assumed.
	want = mini(want, _headroom(arena))
	if want <= 0:
		return
	var hp: int = GRAVE_HP if _on_grave else BARE_HP
	var life: float = GRAVE_LIFE if _on_grave else BARE_LIFE
	for i: int in want:
		var body: Node = _spawn_thrall(arena, _marks[i] + Vector2(0.0, -RISE_OFFSET),
			life, hp)
		if body != null:
			_raised_bodies.append(body)
			CombatVfx.spawn_burst(arena, _marks[i],
				Color(_color.r, _color.g, _color.b, 0.9),
				Color(_color.r * 0.25, _color.g * 0.2, _color.b * 0.4, 0.0),
				20, 0.45, 40.0, 190.0, 1.1, 3.0)
	if not _raised_bodies.is_empty():
		SpellDrops.sfx("shadow_root", 0.0, 0.1, 0.7)
		Juice.shake_camera(6.0)
		Juice.hit_stop(0.05)


## THE FLOOR'S LIVE-ENTITY BUDGET, asked of the Encounter through the Arena. A verbatim
## mirror of `Enemy._spawn_headroom` — same question, same guard, same "outside a floor
## there is no budget" answer (the F6 sandbox, VersusArena, every headless harness), so
## those paths behave exactly as they did before thralls existed.
##
## ⚠ THIS IS ONLY HALF OF THE ACCOUNTING. `Encounter.live_entity_count()` sums
## `enemy` + `hero` + pending spawn tells; a thrall is in NEITHER group, so a standing
## thrall does not currently consume budget the way a summoner's minion does. Asking
## for headroom before each raise bounds the overshoot at `THRALL_MAX_ALIVE` per
## Warlock, which is safe but not exact. The exact fix is one line in `Encounter` —
## see the handoff — and this call site does not change when it lands.
func _headroom(arena: Node) -> int:
	if arena == null or not arena.has_method("encounter"):
		return 0x7FFFFFFF
	var enc: Node = arena.call("encounter")
	if enc == null or not enc.has_method("spawn_headroom"):
		return 0x7FFFFFFF
	return int(enc.call("spawn_headroom"))


## One body. Single player adds it straight into the arena; a co-op host routes it
## through the replicated spawner; a co-op client gets nothing (see
## `COOP_CLIENT_MAY_RAISE`).
func _spawn_thrall(arena: Node, at: Vector2, life: float, hp: int) -> Node:
	var net: Node = get_node_or_null(^"/root/Net")
	var coop: bool = net != null and net.has_method(&"is_active") and bool(net.call(&"is_active"))
	if coop:
		if not bool(net.call(&"is_host")) and not COOP_CLIENT_MAY_RAISE:
			return null
		return _spawn_replicated(arena, at, life, hp)
	var scene: PackedScene = load(THRALL_SCENE) as PackedScene
	if scene == null:
		return null
	var t: Node = scene.instantiate()
	# Set BEFORE add_child, the house pattern for riders: `Thrall._ready` reads all
	# three, and a value that arrives a frame late is a body that spent a frame with
	# no owner, no clock and the wrong tint.
	t.set(&"owner_hero", caster_node)
	t.set(&"thrall_life", life)
	t.set(&"max_hp", hp)
	arena.add_child(t)
	(t as Node2D).global_position = at
	return t


## Co-op host path: the SAME choke point summoner minions and boss adds go through, so
## the 25-entity cap and the MultiplayerSpawner are both honoured for free.
##
## ⚠ IT VERIFIES WHAT IT GOT BACK, and that check is the difference between a safe
## degradation and a catastrophe. `Arena.spawn_extra_enemy` builds through
## `Encounter.build_enemy_from_data`, which has no thrall branch until the handoff edit
## is applied — without it, this dictionary builds a perfectly ordinary HOSTILE enemy
## and hands the Warlock a new foe as the reward for his ult. So the full enemy key set
## is included (an un-patched build must not CRASH on a missing key), the result is
## duck-checked for a Thrall-only method, and anything else is freed on the spot.
func _spawn_replicated(arena: Node, at: Vector2, life: float, hp: int) -> Node:
	if arena == null or not arena.has_method(&"spawn_extra_enemy"):
		return null
	var owner_path: String = ""
	if caster_node != null and is_instance_valid(caster_node) and caster_node.is_inside_tree():
		owner_path = String(caster_node.get_path())
	var n: Node = arena.call(&"spawn_extra_enemy", {
		"thrall": true, "life": life, "owner": owner_path,
		# ...and the whole enemy shape, purely so an un-patched builder degrades
		# instead of erroring. Nothing below is used once the thrall branch exists.
		"boss": false, "arch": 0, "hp": hp, "spd": 118.0, "touch": 9,
		"tint": Color(0.52, 0.38, 0.72, 1.0), "tele": true,
		"x": at.x, "y": at.y,
	})
	if n == null:
		return null
	if not n.has_method(&"life_remaining"):
		push_warning("RaiseThrall: Encounter.build_enemy_from_data has no `thrall` branch — "
			+ "the replicated spawn produced a hostile Enemy and was discarded. "
			+ "Apply the handoff edit, or co-op raises stay disabled.")
		n.queue_free()
		return null
	return n


# ───────────────────────────────────────────────────────────────────── readout
## How many bodies this cast actually stood up. Public so a suite can assert the
## raise really happened rather than that a cap was merely respected — "no thralls
## were raised" trivially satisfies "the cap never broke" and is not a passing test.
func raised_count() -> int:
	var n: int = 0
	for b in _raised_bodies:
		if is_instance_valid(b):
			n += 1
	return n


## Did this cast land on a corpse? Read by the suite to pin the grave rule.
func on_grave() -> bool:
	return _on_grave


## World points bodies are coming out of. A copy, so a caller cannot rewrite the plan.
func marks() -> Array[Vector2]:
	return _marks.duplicate()


## `_draw` calls started / finished. Equal means no draw has ever aborted part-way.
func draw_counts() -> Vector2i:
	return Vector2i(_draw_entered, _draw_done)


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


# ───────────────────────────────────────────────────────────────────── picture
## THE SUMMONING MARK, drawn in world space (this node sits at the origin).
##
## Each grave gets a squashed ring lying flat on the floor that FILLS as the ceremony
## runs, a tether of will from the caster's hand to it, and — as the fill closes —
## hands breaking the surface. The mark is what makes the spell readable to the OTHER
## player too: they can see where a body is about to be standing.
##
## LOW gives up the tether, the inner star and half the hands, and halves the redraw
## rate. It never gives up the ring or the fill, because a ceremony you cannot see the
## end of is a spell with no tell.
func _draw() -> void:
	_draw_entered += 1
	var p: float = clampf(_t / maxf(RAISE_WINDUP, 0.01), 0.0, 1.0)
	var fade: float = 1.0
	if _t > RAISE_WINDUP:
		fade = clampf(1.0 - (_t - RAISE_WINDUP) / maxf(_life - RAISE_WINDUP, 0.01), 0.0, 1.0)
	var ink := Color(_color.r, _color.g, _color.b, (0.35 + 0.5 * p) * fade)
	var dark := Color(_color.r * 0.18, _color.g * 0.12, _color.b * 0.28, 0.75 * fade)
	for i: int in _marks.size():
		var c: Vector2 = _marks[i]
		# THE VOID UNDER THE MARK. Drawn first and near-black so the shadow school
		# EATS light here rather than glowing — the same rule ShadowRoot and
		# ShadowCrawler are written to.
		_ellipse(c, SIGIL_R * p, SIGIL_R * SIGIL_SQUASH * p, dark, 0.0)
		_ellipse(c, SIGIL_R, SIGIL_R * SIGIL_SQUASH, ink, 1.8)
		# The FILL: an arc closing clockwise. This is the clock on the ceremony.
		_arc_fill(c, SIGIL_R * 0.74, SIGIL_R * 0.74 * SIGIL_SQUASH, p, ink, 2.6)
		if not _low:
			_star(c, SIGIL_R * 0.42, 5, _t * 0.9 + float(i), ink)
			# THE TETHER OF WILL — caster to grave. This is the line that says WHOSE
			# the body about to stand there is, which matters most in co-op.
			draw_line(_origin, c, Color(ink.r, ink.g, ink.b, ink.a * 0.5), 1.4, true)
		# HANDS. They only break the surface in the last third, so the ring reads as
		# a warning first and a birth second.
		var claw: float = clampf((p - 0.62) / 0.38, 0.0, 1.0)
		if claw > 0.0:
			_hands(c, claw, i, ink, fade)
	_draw_done += 1   # LAST LINE. See _draw_entered.


func _hands(c: Vector2, claw: float, idx: int, ink: Color, fade: float) -> void:
	var n: int = HANDS_LOW if _low else HANDS
	for h: int in n:
		var fx: float = _hash01(_seed + idx * 131 + h * 17)
		var fy: float = _hash01(_seed + idx * 977 + h * 53)
		var x: float = c.x + (fx - 0.5) * SIGIL_R * 1.7
		var base := Vector2(x, c.y + (fy - 0.4) * SIGIL_R * SIGIL_SQUASH)
		var rise: float = (7.0 + 13.0 * fy) * claw
		var wrist: Vector2 = base - Vector2(0.0, rise)
		draw_line(base, wrist, Color(ink.r, ink.g, ink.b, 0.9 * fade), 2.0, true)
		# Three fingers, splayed — enough to read as a hand at 640x360, cheap enough
		# to draw twenty-one of.
		for f: int in 3:
			var a: float = -PI * 0.5 + (float(f) - 1.0) * 0.55 + (fx - 0.5) * 0.4
			draw_line(wrist, wrist + Vector2.from_angle(a) * (rise * 0.45 + 2.0),
				Color(ink.r, ink.g, ink.b, 0.75 * fade), 1.4, true)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	if rx <= 0.5 or ry <= 0.5:
		return
	var steps: int = 12 if _low else 22
	var pts := PackedVector2Array()
	for s: int in steps + 1:
		var a: float = TAU * float(s) / float(steps)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if width <= 0.0:
		draw_colored_polygon(pts, col)
	else:
		draw_polyline(pts, col, width, true)


func _arc_fill(c: Vector2, rx: float, ry: float, fill: float, col: Color,
		width: float) -> void:
	if fill <= 0.01 or rx <= 0.5:
		return
	var steps: int = maxi(int((8 if _low else 16) * fill), 2)
	var pts := PackedVector2Array()
	for s: int in steps + 1:
		var a: float = -PI * 0.5 + TAU * fill * (float(s) / float(steps))
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, width, true)


func _star(c: Vector2, r: float, points: int, spin: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for s: int in points + 1:
		var a: float = spin + TAU * (float(s) * 2.0) / float(points)
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * SIGIL_SQUASH))
	draw_polyline(pts, Color(col.r, col.g, col.b, col.a * 0.7), 1.2, true)


# ──────────────────────────────────────────────────────────── start-of-floor
## "A Warlock should begin a floor with one thrall already up."
##
## PUBLIC AND STATIC so the one line that calls it can live in `Arena` (a file this
## agent does not own) without that file needing to know anything about graves, caps
## or replication. It raises ONE bare-ground body beside every hero that actually
## carries the spell, and no-ops in every other case — no arena, no heroes, a client
## peer, a hero of the wrong class, no room on the floor.
##
## ⚠ NOT A STATIC FUNCTION FOR THE AUTOLOAD REASON. It names none: `SpellLibrary` and
## `SpellTier` are `class_name` globals, and the Net check goes through the tree by
## path rather than through the `Net` identifier. Naming an autoload inside a static
## breaks the compile chain under `--script` in this repo.
##
## Returns how many bodies it stood up, so the caller (or a suite) can see it work.
static func raise_opening_thralls(arena: Node, spell_id: String = "raise_thrall") -> int:
	if arena == null or not is_instance_valid(arena) or not arena.is_inside_tree():
		return 0
	var tree: SceneTree = arena.get_tree()
	if tree == null:
		return 0
	# Reached BY PATH rather than by `new()`: this script declares no `class_name`
	# (deliberately — a brand-new one is absent from
	# `.godot/global_script_class_cache.cfg` until somebody re-imports, and until then
	# every file that NAMES it fails to compile), so a static here has no identifier
	# for its own type. `SpellCaster` reaches every spectacle the same way.
	var self_script: GDScript = load("res://scripts/combat/RaiseThrall.gd") as GDScript
	if self_script == null:
		return 0
	var raised: int = 0
	for h: Node in tree.get_nodes_in_group("hero"):
		if not (h is Node2D) or not is_instance_valid(h):
			continue
		if not _carries(h, spell_id):
			continue
		var spell: SpellDef = _find_spell(spell_id)
		if spell == null:
			continue
		var at: Vector2 = (h as Node2D).global_position
		var rt: Node2D = self_script.new()
		arena.add_child(rt)
		# Aimed at the hero's own feet, slightly off so the fan maths never sees a
		# zero vector. There is no corpse on a fresh floor, so this is the BARE case
		# by construction — the free body is the thin one, and finding a grave is
		# still the thing that makes the spell good.
		rt.call(&"hex", h, at, at + Vector2(18.0, 0.0), spell,
			spell.resolve_color(Color(0.62, 0.45, 0.88)), spell.effect)
		raised += 1
	return raised


## Does this hero's equipped kit hold `spell_id`? Read from the hero's class through
## `SpellLibrary`, which is the same source `Hero` builds its own loadout from — so
## this answer cannot drift from what the player is actually holding.
##
## `_hero_class` is reached DYNAMICALLY because `Hero.gd` declares no `class_name`.
## A rename there makes this return false (no opening thrall) rather than crash,
## which is the conservative direction.
static func _carries(hero: Node, spell_id: String) -> bool:
	var cls_v: Variant = hero.get(&"_hero_class")
	if cls_v == null:
		return false
	for s: SpellDef in SpellLibrary.build_for_class(int(cls_v)):
		if s != null and s.id == spell_id:
			return true
	return false


static func _find_spell(spell_id: String) -> SpellDef:
	for s: SpellDef in SpellLibrary.build_all():
		if s != null and s.id == spell_id:
			return s
	return null
