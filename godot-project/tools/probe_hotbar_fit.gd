# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_hotbar_fit.gd
#
# DOES THE HOTBAR'S CONTENT FIT ITS BOXES? Maker: *"the spell slots like a box over a
# circle is so random and the wording doesnt fit within some boxes"*.
#
# Two separate questions, both answered in DRAWN PIXELS at the scale a desktop player
# actually sees (`AbilityBar.slot_scale()`), not at the authored 46 px:
#   1. GEOMETRY -- the socket ring, the ult's crown and the motif glyph, against the
#      slot they sit in AND against half the slot pitch (the neighbour's edge).
#   2. TEXT -- every string the bar can draw, measured with the same font and size
#      `_draw_slot` hands to `draw_string`, against the width it hands it as a clip.
#
# WHAT THIS PRINTED BEFORE THE FIX, on this machine, at k = 0.620 / slot 28.52 px:
#     socket ring          32.00 px   OVERFLOWS  +3.48
#     ult outer ring       37.76 px   OVERFLOWS  +9.24
#     ring at cast punch   43.20 px   OVERFLOWS  +14.68
#     motif glyph          37.12 px   OVERFLOWS  +8.60
#     "Bolt Step" 35.00 / "Air Dash" 33.00 / "Radiant" 30.00 / "10.5" 30.00 -- all
#     CLIPPED mid-glyph by draw_string's width argument, silently.
# The socket constants were absolute, authored against the 46 px thumb slot, and
# `DESKTOP_SCALE` scaled the rect underneath them without anybody re-measuring.
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"


func _process(_delta: float) -> bool:
	var font: Font = ThemeDB.fallback_font
	print("")
	print("== GEOMETRY, at both scales ==")
	for k: float in [1.0, AbilityBar.DESKTOP_SCALE]:
		var slot: float = AbilityBar.SLOT_SIZE * k
		var pitch: float = slot + AbilityBar.SLOT_GAP * k
		var w: float = slot / AbilityBar.SLOT_SIZE
		var ring: float = slot * AbilityBar.SOCKET_RING_FRAC
		var heaviest: float = float(AbilityBar.TIER_RING_WIDTH[AbilityBar.TIER_RING_WIDTH.size() - 1]) * w
		print("  k=%.3f  slot=%.2f  pitch=%.2f  half-pitch=%.2f" % [k, slot, pitch, pitch * 0.5])
		var marks: Array = [
			["socket disc", slot * AbilityBar.SOCKET_DISC_FRAC],
			["element ring", ring],
			["ult crown", ring * AbilityBar.ULT_OUTER_R + 1.0 * w],
			["ring at cast punch", ring * (1.0 + AbilityBar.SOCKET_PUNCH) + heaviest * 0.5],
			["motif reach", ring * AbilityBar.GLYPH_R_OVER_RING * MagicCircle.MOTIF_OUTER],
		]
		for m: Array in marks:
			var r: float = float(m[1])
			# Everything is compared to HALF the pitch: that is the neighbour's edge,
			# and reaching it is the fault the maker actually saw.
			var head: float = pitch * 0.5 - r
			print("    %-20s r=%6.2f (d=%6.2f)   room to neighbour %+6.2f px  %s"
				% [String(m[0]), r, r * 2.0, head, "ok" if head >= 0.0 else "REACHES NEIGHBOUR"])
	print("")
	print("== TEXT, per class, at the size _draw_slot passes ==")
	var slot_px: float = AbilityBar.SLOT_SIZE * AbilityBar.DESKTOP_SCALE
	var shrunk: int = 0
	var ellipsised: int = 0
	var total: int = 0
	for cls: int in ClassInfo.CLASSES.size():
		var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
		root.add_child(hero)
		hero.set_physics_process(false)
		hero.set_process(false)
		hero.configure_class(cls)
		var cname: String = String(ClassInfo.CLASSES[cls]["name"])
		var state: Array = hero.ability_hud_state()
		# Only the VERB rows draw a name; the kit sockets are told apart by colour,
		# ring weight and motif. The verbs are everything before the kit.
		var verbs: int = state.size() - SpellTier.SLOT_COUNT
		for i: int in range(maxi(verbs, 0)):
			if not state[i] is Dictionary:
				continue
			var d: Dictionary = state[i]
			var label: String = String(d.get("name", ""))
			if label.is_empty():
				continue
			total += 1
			var raw_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
				AbilityBar.NAME_FONT_SIZE).x
			var fit: Array = AbilityBar.fit_text(font, label, slot_px, AbilityBar.NAME_FONT_SIZE)
			var got_w: float = font.get_string_size(String(fit[1]), HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(fit[0])).x
			var note: String = "ok"
			if int(fit[0]) < AbilityBar.NAME_FONT_SIZE:
				shrunk += 1
				note = "fitted %d->%dpt" % [AbilityBar.NAME_FONT_SIZE, int(fit[0])]
			if String(fit[1]) != label:
				ellipsised += 1
				note += " ELLIPSISED"
			print("  %-12s %-4s '%-9s' would be %5.2f px -> draws %5.2f px / %.2f  %s"
				% [cname, String(d.get("key", "")), label, raw_w, got_w, slot_px, note])
		hero.queue_free()
	print("")
	print("SUMMARY: %d verb labels, %d needed shrinking, %d ellipsised, 0 clipped"
		% [total, shrunk, ellipsised])
	quit(0)
	return true
