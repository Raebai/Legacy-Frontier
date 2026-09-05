# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_hero_hud.gd
#
# WHAT THE PLAYER'S HUD ACTUALLY MEASURES, on the two logical viewports this game gets
# and across the whole range the camera moves through. A probe, not a suite: it asserts
# nothing and fails nothing, it prints numbers so a claim about the HUD can be checked
# instead of believed.
#
# ⚠ TWO WIDTHS, BECAUSE THERE ARE TWO. `project.godot` runs `stretch=canvas_items` with
# `aspect="expand"`, so the HEIGHT is pinned at 360 and the WIDTH grows: a 16:9 screen
# gives 640x360, a 20:9 phone about 800x360. Anything anchored to the left edge survives
# that and anything anchored to the right edge does not, and a HUD measured only at 640
# has not been measured on the device the game is for.
#
# ⚠ AND HEADLESS HAS NO WINDOW, SO IT HAS NO ASPECT: `get_visible_rect()` falls back to
# a SQUARE 640x640 unless `root.size` is set and a frame is waited for. Every number
# below would otherwise be taken against a screen that does not exist.
extends SceneTree

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const BARS := preload("res://scripts/combat/CharacterBars.gd")


class Fighter extends Node2D:
	var max_hp: int = 100
	var hp: float = 100.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("")
	print("═══ THE PLAYER'S HUD, MEASURED ══════════════════════════════════════════")
	print("base viewport %s | stretch canvas_items / expand | camera %.2f..%.2f (ref %.2f)"
		% [HudStyle.BASE_VIEWPORT, HudStyle.ZOOM_WIDE, HudStyle.ZOOM_TIGHT,
			HudStyle.ZOOM_REF])
	await _section_zoom()
	await _section_plate()
	_section_pause_corner()
	_section_bands()
	_section_boss_ladder()
	print("═══ END ═════════════════════════════════════════════════════════════════")
	quit(0)


# ══════════════════════════════════════════════════════════ 1. the zoom problem
## What a WORLD-space readout does across the camera's range, with and without the
## compensation — i.e. the problem the player's bar used to have and no longer has.
func _section_zoom() -> void:
	root.size = Vector2i(640, 360)
	await process_frame
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	var probe := Node2D.new()
	root.add_child(probe)
	print("")
	print("── 1. BODY-ATTACHED vs SCREEN-SPACE ─────────────────────────────────────")
	print("   the OLD player bar was 52x7 WORLD px at y-26 over a ~31px rig.")
	print("   zoom | raw 52x7 on screen  | compensated | plate (screen-space)")
	for z: float in [HudStyle.ZOOM_WIDE, 1.0, HudStyle.ZOOM_REF, HudStyle.ZOOM_TIGHT]:
		cam.zoom = Vector2(z, z)
		await process_frame
		var ui: float = HudStyle.ui_scale(probe)
		print("   %.2f | %6.1f x %-5.1f       | %6.1f x %-5.1f | %6.1f x %-5.1f"
			% [z, 52.0 * z, 7.0 * z, 52.0 * z * ui, 7.0 * z * ui,
				HudStyle.HERO_PLATE_SIZE.x, HudStyle.HERO_PLATE_SIZE.y])
	print("   ^ the raw column is a 5.6x swing DURING a fight. the plate column is a")
	print("     constant because a CanvasLayer is not transformed by the camera at all.")
	cam.queue_free()
	probe.queue_free()
	await process_frame


# ══════════════════════════════════════════════════════ 2. the plate, live
## The rect the VIEWER gets, read off a real `Control` on a real `CanvasLayer` under a
## real camera, at both widths. `get_global_transform_with_canvas()` rather than
## `get_global_rect()` — see `CharacterBars.plate_rect` for why the difference is the
## whole measurement.
func _section_plate() -> void:
	print("")
	print("── 2. THE PLAYER PLATE, AS DRAWN ────────────────────────────────────────")
	var hero_l: Node2D = _fighter()
	var hero_r: Node2D = _fighter()
	var bars_l: CharacterBars = _bars(hero_l)
	var bars_r: CharacterBars = _bars(hero_r)
	_hotbar(hero_l, false)
	_hotbar(hero_r, true)
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	cam.zoom = Vector2.ONE * HudStyle.ZOOM_REF
	for w: int in [640, 800]:
		root.size = Vector2i(w, 360)
		await process_frame
		await process_frame
		await process_frame
		var view: Vector2 = root.get_visible_rect().size
		print("   viewport %s   hotbar reserves %.1f px of the bottom (slot_scale %.2f)"
			% [view, AbilityBar.occupied_height(), AbilityBar.slot_scale()])
		for pair: Array in [[bars_l, "P1 (dock left) "], [bars_r, "P2 (dock right)"]]:
			var b: CharacterBars = pair[0]
			var r: Rect2 = b.plate_rect()
			print("     %s plate %s  right-inset %.1f  bottom-inset %.1f  head bar: %s"
				% [pair[1], r, view.x - (r.position.x + r.size.x),
					view.y - (r.position.y + r.size.y), b.draws_head_bar()])
	# ...and the same node at the camera's two extremes, to show the plate does not move.
	root.size = Vector2i(640, 360)
	await process_frame
	print("   the plate across the camera's range (it must not move or resize):")
	for z: float in [HudStyle.ZOOM_WIDE, HudStyle.ZOOM_REF, HudStyle.ZOOM_TIGHT]:
		cam.zoom = Vector2(z, z)
		await process_frame
		await process_frame
		print("     zoom %.2f -> %s" % [z, bars_l.plate_rect()])
	cam.queue_free()


func _fighter() -> Node2D:
	var f := Fighter.new()
	f.add_to_group(&"hero")
	root.add_child(f)
	return f


func _bars(target: Node2D) -> CharacterBars:
	var b: CharacterBars = BARS.new()
	target.add_child(b)
	b.configure(target, true, -26.0)   # `true` is what Hero.gd:1820 passes
	return b


func _hotbar(hero: Node2D, dock_right: bool) -> void:
	var layer := CanvasLayer.new()
	layer.layer = HudStyle.LAYER_HUD
	root.add_child(layer)
	var bar := AbilityBar.new()
	bar.bound_hero = hero
	bar.dock_right = dock_right
	layer.add_child(bar)


# ══════════════════════════════════════════════ 3. the pause corner's real shape
## ⚠ A KNOWN FAULT THAT IS STILL LOAD-BEARING. `HudStyle.PAUSE_CORNER` is a FIXED rect
## at x 580..640, and `PauseMenu` anchors its 44x44 button to the RIGHT EDGE at a 10px
## margin. On the expanded viewport a 20:9 phone actually gets, the const points at empty
## screen and the real button is 160px away — so every "does this clear the pause button"
## check made against the const on a phone is a check against nothing. Two tool files had
## each already written this down in a comment and worked around it with local literals;
## `HudStyle.pause_corner(view)` is the shape that is actually right, and this prints the
## gap so migrating the remaining callers has a number attached to it.
func _section_pause_corner() -> void:
	print("")
	print("── 3. THE PAUSE CORNER ──────────────────────────────────────────────────")
	print("   width | const PAUSE_CORNER | pause_corner(view)  | error")
	for w: float in [640.0, 800.0]:
		var view := Vector2(w, 360.0)
		var real: Rect2 = HudStyle.pause_corner(view)
		print("   %5.0f | x %.0f..%.0f          | x %.0f..%.0f           | %.0f px"
			% [w, HudStyle.PAUSE_CORNER.position.x,
				HudStyle.PAUSE_CORNER.position.x + HudStyle.PAUSE_CORNER.size.x,
				real.position.x, real.position.x + real.size.x,
				absf(real.position.x - HudStyle.PAUSE_CORNER.position.x)])


# ══════════════════════════════════════════════════ 4. the plate against the bands
func _section_bands() -> void:
	print("")
	print("── 4. THE PLATE AGAINST THE ALLOCATION ──────────────────────────────────")
	var bands: Array = [
		["rank", HudStyle.BAND_RANK], ["floor banner", HudStyle.BAND_FLOOR_BANNER],
		["boss bar", HudStyle.BAND_BOSS_BAR], ["boss mods", HudStyle.BAND_BOSS_MODS],
		["affix card", HudStyle.BAND_AFFIX], ["shout", HudStyle.BAND_SHOUT],
	]
	for band: Array in bands:
		print("   %-13s y %6.1f .. %-6.1f" % [band[0], float(band[1][0]),
			float(band[1][1])])
	# The two hotbar heights the game produces: `occupied_height()` is 69 * slot_scale().
	for h: float in [69.0 * 0.62, 69.0]:
		var r: Rect2 = HudStyle.hero_plate_rect(Vector2(640.0, 360.0), false, h)
		var framed: Rect2 = r.grow(HudStyle.HERO_PLATE_FRAME)
		print("   plate (hotbar %5.1f) y %6.1f .. %-6.1f   framed y %.1f .. %.1f"
			% [h, r.position.y, r.position.y + r.size.y, framed.position.y,
				framed.position.y + framed.size.y])
	print("   ^ the plate is BELOW every band and ABOVE the hotbar, at both device")
	print("     scales. it is not a band: bands are full-width strips of the ROOM's")
	print("     stack at the top of the screen, and this is the PLAYER's stack.")


# ══════════════════════════════════════ 5. does the boss bar actually escalate
## The fault: the phase ladder was lerped 55% toward each boss's own accent at every
## rung, so a boss with a cool accent got a cool "about to die" colour. `heat` is r-g,
## because the red CHANNEL alone calls P1's gold hotter than P3's red.
func _section_boss_ladder() -> void:
	print("")
	print("── 5. DOES THE BOSS BAR ESCALATE ────────────────────────────────────────")
	print("   accent          | P1 heat | P2 heat | P3 heat | monotonic | hot at P3")
	var accents: Array = [
		["EMBER (default)", HudStyle.EMBER], ["DANGER", HudStyle.DANGER],
		["GOLD", HudStyle.GOLD], ["AZURE (cool)", HudStyle.AZURE],
		["MINT (cool)", HudStyle.MINT], ["cyan (coolest)", Color(0.0, 1.0, 1.0)],
	]
	for a: Array in accents:
		var h: Array[float] = []
		for phase: int in 3:
			h.append(BossBar.heat(BossBar.phase_fill(phase, a[1])))
		print("   %-15s | %+7.3f | %+7.3f | %+7.3f | %-9s | %s"
			% [a[0], h[0], h[1], h[2],
				"yes" if h[0] < h[1] and h[1] < h[2] else "*** NO ***",
				"yes" if h[2] > 0.0 else "*** NO ***"])
	print("   ^ with the old flat 0.55 accent pull, cyan's P3 heat was -0.248: the")
	print("     bar escalated from cyan, through cyan, to cyan.")
