# Run: godot --headless --path godot-project --script tools/slice_test_mobile_config.gd
#
# Phase 6. Pins the mobile-readiness work that is otherwise INVISIBLE — settings
# in a file the Godot editor rewrites whenever it feels like it, an export
# exclude list nobody looks at, and two pools whose whole job is to be
# unnoticeable when they work.
#
# Why a settings suite exists at all: `project.godot` is not hand-maintained. The
# editor rewrites it on save and has already, in this project's history, silently
# normalised entries away (Session 3: it dropped a `window/stretch/aspect` line on
# import). A per-platform override that vanishes does not error — the phone build
# just quietly renders with the desktop's 8x MSAA and nobody finds out until a
# device is in hand. So these are asserted against the FILE TEXT, not against
# `ProjectSettings.get_setting()`: the engine registers built-in defaults for
# `rendering_method.mobile` and friends, so the setting lookup answers correctly
# even when our line has been deleted. Reading the file is the only check that
# actually fails when the thing we care about is gone.
#
# TEST IDIOM — see the long note in tools/slice_test_loadout.gd. Failures
# accumulate on the MEMBER `_fails`; every test's last line records a COMPLETION
# SENTINEL. A test that aborts half-way (a dead property read aborts the
# enclosing function and returns zero, which the old `failed += _test_x()` idiom
# read as "no failures") therefore fails the suite BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"rendering_settings", "export_preset", "quality_dial",
	"impact_frame_low_quality", "damage_number_pool", "combat_vfx_pool",
	"atmosphere_no_preprocess",
]

## Exact lines that must survive in project.godot. Written as substrings of the
## file so a reordering by the editor does not fail them, but a deletion does.
const REQUIRED_PROJECT_LINES: Array[String] = [
	'renderer/rendering_method="forward_plus"',
	'renderer/rendering_method.mobile="mobile"',
	"anti_aliasing/quality/msaa_2d=3",
	"anti_aliasing/quality/msaa_2d.mobile=1",
	"viewport/hdr_2d=true",
	'window/handheld/orientation="landscape"',
	'window/stretch/aspect="expand"',
	'run/main_scene="res://scenes/ui/Lobby.tscn"',
	"common/physics_ticks_per_second=60",
]

## Everything that must be kept OUT of the shipping pack. The MCP entries are the
## load-bearing ones: they are a WebSocket dev bridge that opens a listening
## socket at boot.
const REQUIRED_EXCLUDES: Array[String] = [
	"res://tools/*",
	"res://addons/godot_mcp_runtime/*",
	"res://addons/godot_mcp_editor/*",
	"res://addons/auto_reload/*",
	"res://scripts/spike/*",
	"res://scenes/spike/*",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_rendering_settings()
	_test_export_preset()
	_test_quality_dial()
	_test_impact_frame_low_quality()
	_test_damage_number_pool()
	_test_combat_vfx_pool()
	_test_atmosphere_no_preprocess()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Mobile config tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Mobile config tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------- settings
func _test_rendering_settings() -> void:
	var text: String = FileAccess.get_file_as_string("res://project.godot")
	_expect(not text.is_empty(), "project.godot is readable")
	for line: String in REQUIRED_PROJECT_LINES:
		_expect(text.contains(line),
			"project.godot still carries `%s` (the editor rewrites this file — a "
			% line + "per-platform override that vanishes fails silently on device)")
	# 8x MSAA is the maker's deliberate desktop choice: this game draws its
	# fighters as procedural lines and arcs, not sprites, so MSAA is doing real
	# work here in a way it would not for pixel art. The mobile override exists
	# to spare a tile GPU that cost, NOT to walk the desktop decision back.
	_expect(not text.contains("anti_aliasing/quality/msaa_2d=0"),
		"desktop MSAA was NOT quietly turned off along with the mobile override")
	_completes("rendering_settings")


func _test_export_preset() -> void:
	_expect(FileAccess.file_exists("res://export_presets.cfg"),
		"export_presets.cfg exists (it was git-ignored until Phase 6)")
	var text: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	_expect(text.contains('platform="Android"'), "an Android preset is defined")
	for ex: String in REQUIRED_EXCLUDES:
		_expect(text.contains(ex), "the export excludes `%s`" % ex)
	# `all_resources`, not `resources`. Dependency scanning cannot see a path held
	# in a String constant, and this codebase loads that way constantly —
	# SimArena's HERO_SCENE, PostProcess's SHADER_PATH, Atmosphere's
	# GLOW_ENV_PATH, Vfx's EXPLOSION. A scanned export would ship a game that
	# looks fine in the editor and is missing half its content on the phone.
	_expect(text.contains('export_filter="all_resources"'),
		"export_filter is all_resources (runtime load()-by-string is everywhere here)")
	# effects/ LOOKS like dev leftovers and is not: Vfx.gd loads
	# res://effects/2d_explosion/source/explosion.tscn at runtime.
	_expect(not text.contains("res://effects"),
		"effects/ is NOT excluded — Vfx.gd load()s explosion.tscn from it at runtime")
	# Secret guard. Godot writes signing credentials to the separate, still-ignored
	# export_credentials.cfg, but this file is tracked now and a stray keystore
	# path or password here is a leaked credential in a repo that is going public.
	var lower: String = text.to_lower()
	_expect(not lower.contains("password"), "no password field leaked into the tracked preset")
	_expect(not lower.contains(".keystore") and not lower.contains(".jks"),
		"no keystore path leaked into the tracked preset")
	_completes("export_preset")


# -------------------------------------------------------------- quality dial
func _test_quality_dial() -> void:
	# Under `--script` there is no Tuning autoload, so the dial reads AUTO, and
	# AUTO on a desktop is HIGH. Every other suite in tools/ therefore keeps
	# seeing exactly the picture it saw before Phase 6.
	_expect(not TuningConfig.quality_is_low(),
		"headless desktop resolves to HIGH (so no other suite changed behaviour)")
	_expect(TuningConfig.screen_shaders_allowed(),
		"screen-reading shaders are allowed on the desktop path")
	_expect(ImpactFrame.downgrade_for_quality(ImpactFrame.Style.INVERT)
		== ImpactFrame.Style.COLOR_FIELD, "INVERT downgrades to COLOR_FIELD")
	_expect(ImpactFrame.downgrade_for_quality(ImpactFrame.Style.SILHOUETTE)
		== ImpactFrame.Style.COLOR_FIELD, "SILHOUETTE downgrades to COLOR_FIELD")
	# The three styles that are already pure draw_* calls must pass through
	# untouched — the downgrade is about screen READS, not about being quieter.
	for keep: int in [ImpactFrame.Style.BLOWOUT, ImpactFrame.Style.COLOR_FIELD,
			ImpactFrame.Style.CUT_IN, ImpactFrame.Style.LOCAL]:
		_expect(ImpactFrame.downgrade_for_quality(keep) == keep,
			"style %d needs no screen read and is left alone" % keep)
	_completes("quality_dial")


func _test_impact_frame_low_quality() -> void:
	ImpactFrame.reset_arbiter()
	var d: Dictionary = ImpactFrame.decide(
		{"style": ImpactFrame.Style.INVERT, "low_quality": true}, 10_000)
	_expect(bool(d["granted"]), "a downgraded frame still plays")
	_expect(int(d["style"]) == ImpactFrame.Style.COLOR_FIELD,
		"INVERT becomes COLOR_FIELD on LOW")
	# The duration must stay INVERT's, not inherit COLOR_FIELD's. INVERT is 0.07s
	# because a negative outstays its welcome fastest; 0.15s would be a different,
	# worse effect wearing the same name.
	_expect(is_equal_approx(float(d["duration"]), ImpactFrame.DURATION_INVERT),
		"the downgrade keeps the ORIGINAL duration (%.3f, got %.3f)"
			% [ImpactFrame.DURATION_INVERT, float(d["duration"])])

	ImpactFrame.reset_arbiter()
	d = ImpactFrame.decide({"style": ImpactFrame.Style.SILHOUETTE, "low_quality": true}, 20_000)
	_expect(int(d["style"]) == ImpactFrame.Style.COLOR_FIELD,
		"SILHOUETTE becomes COLOR_FIELD on LOW")

	ImpactFrame.reset_arbiter()
	d = ImpactFrame.decide({"style": ImpactFrame.Style.SILHOUETTE, "low_quality": false}, 30_000)
	_expect(int(d["style"]) == ImpactFrame.Style.SILHOUETTE,
		"HIGH keeps the black cut (the mobile gate is not a global nerf)")

	# ACCESSIBILITY OUTRANKS QUALITY. reduce-flashing must still reach LOCAL even
	# when the quality downgrade has already moved the style — a photosensitivity
	# setting that a performance setting could override would be a real bug.
	ImpactFrame.reset_arbiter()
	d = ImpactFrame.decide({
		"style": ImpactFrame.Style.SILHOUETTE, "low_quality": true, "reduce": true}, 40_000)
	_expect(int(d["style"]) == ImpactFrame.Style.LOCAL,
		"reduce-flashing still wins over the mobile downgrade")
	ImpactFrame.reset_arbiter()
	_completes("impact_frame_low_quality")


# -------------------------------------------------------------------- pools
func _numbers(host: Node) -> Array:
	var out: Array = []
	for c: Node in host.get_children():
		if c is DamageNumber:
			out.append(c)
	return out


func _test_damage_number_pool() -> void:
	DamageNumber.reset_pool()
	var host := Node2D.new()
	root.add_child(host)
	DamageNumber.spawn(host, Vector2(10, 10), 5)
	_expect(DamageNumber.alive_count() == 1, "one spawn -> one alive")
	_expect(DamageNumber.pooled_count() == 0, "nothing is banked while it animates")
	var nums: Array = _numbers(host)
	_expect(nums.size() == 1, "exactly one node was created")
	if nums.size() != 1:
		host.free()
		DamageNumber.reset_pool()
		return  # deliberately NOT completed: the missing sentinel fails the suite
	var first: DamageNumber = nums[0]
	first._release()
	_expect(DamageNumber.alive_count() == 0, "expiry frees the slot")
	_expect(DamageNumber.pooled_count() == 1, "expiry BANKS the instance")
	DamageNumber.spawn(host, Vector2(20, 20), 7)
	_expect(_numbers(host).size() == 1,
		"the second spawn REUSED the node — this is the whole point, and the old "
		+ "code allocated a fresh one here")
	_expect(DamageNumber.alive_count() == 1, "a reused node counts as alive")
	_expect(DamageNumber.pooled_count() == 0, "the bank is empty again")
	# The cap. It used to be an O(n) group walk on every hit and every DoT tick.
	for i: int in DamageNumber.MAX_ALIVE + 10:
		DamageNumber.spawn(host, Vector2(float(i), 0.0), 3)
	_expect(DamageNumber.alive_count() == DamageNumber.MAX_ALIVE,
		"the cap holds at MAX_ALIVE (%d, got %d)"
			% [DamageNumber.MAX_ALIVE, DamageNumber.alive_count()])
	# THE RATCHET GUARD, and the reason _exit_tree exists. A floor torn down
	# mid-fight frees numbers that were never released; without the guard the
	# counter never comes back down, the cap latches shut, and damage numbers
	# silently stop for the rest of the session.
	host.free()
	_expect(DamageNumber.alive_count() == 0,
		"an arena teardown returns every slot (got %d still counted)"
			% DamageNumber.alive_count())
	DamageNumber.reset_pool()
	_completes("damage_number_pool")


func _test_combat_vfx_pool() -> void:
	CombatVfx.reset_pool()
	var host := Node2D.new()
	root.add_child(host)
	var a: GPUParticles2D = CombatVfx.spawn_burst(
		host, Vector2.ZERO, Color(1, 0, 0, 1), Color(1, 0, 0, 0), 20, 0.2)
	_expect(a != null, "a burst emitter is returned")
	if a == null:
		host.free()
		CombatVfx.reset_pool()
		return  # no sentinel -> the suite fails
	_expect(a.amount == 20, "the emitter is sized to the requested amount")
	CombatVfx._recycle(a, 20)
	_expect(CombatVfx.pooled_count() == 1, "recycling banks the emitter")
	_expect(not a.visible, "a banked emitter is hidden (so it costs nothing parked)")
	var b: GPUParticles2D = CombatVfx.spawn_burst(
		host, Vector2(5, 5), Color(0, 0, 1, 1), Color(0, 0, 1, 0), 20, 0.2)
	_expect(b == a, "same `amount` reuses the banked emitter instead of allocating")
	_expect(b != null and b.visible, "a reused emitter is shown again")
	_expect(CombatVfx.pooled_count() == 0, "reuse empties the bucket")

	# THE INHERITANCE BUG THE BRANCH GUARDS. `material` is set on BOTH paths: an
	# additive spark burst leaves BLEND_MODE_ADD on the emitter, and a debris puff
	# that only ever SETS additive would silently come out white-hot.
	CombatVfx._recycle(b, 20)
	var c: GPUParticles2D = CombatVfx.spawn_burst(
		host, Vector2.ZERO, Color(1, 0, 0, 1), Color(1, 0, 0, 0), 20, 0.2,
		60.0, 130.0, 1.0, 3.0, 0.0, 0.0, true)
	_expect(c == b, "the additive burst reused the same emitter")
	_expect(c != null and c.material != null, "an additive burst gets the additive material")
	CombatVfx._recycle(c, 20)
	var d: GPUParticles2D = CombatVfx.spawn_burst(
		host, Vector2.ZERO, Color(1, 0, 0, 1), Color(1, 0, 0, 0), 20, 0.2)
	_expect(d == c, "still the same emitter")
	_expect(d != null and d.material == null,
		"a NON-additive reuse CLEARS the inherited additive blend")

	# `amount` is the bucket KEY. Reassigning amount on a recycled emitter
	# reallocates its GPU buffer, which is the exact cost the pool exists to
	# avoid, so a mismatched request must take a fresh node.
	CombatVfx._recycle(d, 20)
	var e: GPUParticles2D = CombatVfx.spawn_burst(
		host, Vector2.ZERO, Color(1, 0, 0, 1), Color(1, 0, 0, 0), 44, 0.2)
	_expect(e != d, "a different `amount` takes a fresh emitter, not a resized one")
	_expect(e != null and e.amount == 44, "and it is sized correctly")
	host.free()
	CombatVfx.reset_pool()
	_completes("combat_vfx_pool")


# --------------------------------------------------------------- atmosphere
func _emitters(n: Node, out: Array = []) -> Array:
	for c: Node in n.get_children():
		if c is GPUParticles2D:
			out.append(c)
		_emitters(c, out)
	return out


func _test_atmosphere_no_preprocess() -> void:
	var atm := Atmosphere.new()
	root.add_child(atm)
	atm.build_wash(Color(0.2, 0.3, 0.5), Color(0.8, 0.9, 1.0))
	var wash: Array = _emitters(atm)
	_expect(wash.size() >= 1, "build_wash makes a mote emitter")
	for p: GPUParticles2D in wash:
		# preprocess simulates its value * fixed_fps compute dispatches inside the
		# LOAD frame. 9.0 was a multi-hundred-millisecond hitch at every floor
		# transition on a phone.
		_expect(is_zero_approx(p.preprocess),
			"wash motes do not preprocess (got %.2f — the arena-entry stall is back)"
				% p.preprocess)
		_expect(p.fixed_fps == Atmosphere.MOTE_FIXED_FPS,
			"wash motes simulate at the trimmed rate")
		_expect(p.speed_scale > 1.0,
			"the spread-over-frames warm-up is running in place of preprocess")
	atm.free()

	var world := Atmosphere.new()
	root.add_child(world)
	world.build(Rect2(0.0, 0.0, 1200.0, 760.0))
	var motes: Array = _emitters(world)
	_expect(motes.size() >= 1, "build() makes a mote emitter")
	for p: GPUParticles2D in motes:
		_expect(is_zero_approx(p.preprocess),
			"world motes do not preprocess either (got %.2f)" % p.preprocess)
		_expect(p.fixed_fps == Atmosphere.MOTE_FIXED_FPS,
			"world motes simulate at the trimmed rate")
	world.free()
	_completes("atmosphere_no_preprocess")
