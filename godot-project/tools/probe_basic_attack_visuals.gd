# ══ WHAT DOES A LEFT-CLICK ATTACK ACTUALLY DRAW? ═══════════════════════════════
#
# Maker: *"Don't show the deflect thing when punching with brawler. Any and every
# left-click attack, there shouldn't be a deflect thing shown - check which ones
# have that and remove it"* and *"Swordsaint - remove that goofy large pink
# barrier thing as well in its left-click attack"*.
#
# "CHECK WHICH ONES HAVE THAT" is an instruction to MEASURE, not to guess. Two
# classes were noticed; nine exist. This probe presses the LMB primary on every
# one of them and prints what appeared on screen, so the cut list is a reading
# rather than a hunch.
#
# It reports, per class:
#   TELEGRAPH  the swing tell: style / shape / radius / half-angle / light /
#              accent colour. A CONE tell draws a rim arc plus two limit rays
#              AROUND THE BODY - the same shape as CharacterRig's white parry
#              shell, which is why it reads as "a deflect thing".
#   SHIELD     rig._parry_timer > 0 - the literal white curved band that
#              `CharacterRig._draw_parry_shield` paints. If a basic attack arms
#              this, the maker's "little white bar" is literal.
#   GUARD      a live ParryRing / SigilGuard on the body (the magic-circle and
#              shrinking-ring guards). A basic attack must not open either.
#   SWINGARC   the explanatory crescent thrown WITH a blade swing.
#
# Run: godot --headless --path godot-project --script tools/probe_basic_attack_visuals.gd
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
const CLASS_NAMES: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut",
	"Cleric", "Cryomancer", "Stormcaller", "Warlock", "Swordsaint",
]
var _ran: bool = false


class StubEnemy:
	extends Node2D
	var hp: int = 100
	func take_damage(a: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
		hp -= a
	func apply_knockback(_v: Vector2) -> void:
		pass
	func apply_status(_e: int, _c: bool = true) -> void:
		pass


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	print("class          | primary       | telegraph style/shape        | radius | half-deg | light | accent            | shield | guard | swingarc")
	for cls: int in range(CLASS_NAMES.size()):
		var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
		root.add_child(hero)
		hero.configure_class(cls)
		var e := StubEnemy.new()
		e.add_to_group("enemy")
		e.add_to_group(SpellCaster.MORTAL_GROUP)
		e.global_position = hero.global_position + Vector2(38.0, 0.0)
		root.add_child(e)
		hero.set("_aim_dir", Vector2.RIGHT)
		hero.set("facing", Vector2.RIGHT)
		var rig: Node = hero.get_node("Rig")
		# Baseline: nothing must be armed BEFORE the press, or the reading is noise.
		var shield_before: float = float(rig.get("_parry_timer"))
		# ⚠ THE FIRST VERSION OF THIS PROBE LIED, AND THE LIE IS WORTH KEEPING ON
		# RECORD. It read `get_nodes_in_group("telegraph")[0]` after each press and
		# freed the hero with `queue_free()`. No real frames pass in this synchronous
		# loop, so nothing queued was ever actually freed — every class after the
		# Brawler reported the BRAWLER's telegraph (58 px, 72.5 deg, orange) and the
		# table read as though all nine classes drew one identical tell. The
		# before/after instance-id diff below is what makes each row this class's.
		var before: Dictionary = _telegraph_ids()
		var arcs_before: Dictionary = _swing_arc_ids()
		hero.call("_cast")
		var tele: Node = _new_telegraph(before)
		var shield_after: float = float(rig.get("_parry_timer"))
		var arc: Node = _new_swing_arc(arcs_before)
		var guards: String = _guard_nodes(hero)
		var style_s: String = "-"
		var shape_s: String = "-"
		var radius_s: String = "-"
		var half_s: String = "-"
		var light_s: String = "-"
		var accent_s: String = "-"
		if tele != null:
			style_s = _style_name(int(tele.get("style")))
			shape_s = _shape_name(int(tele.get("_shape")))
			radius_s = "%6.1f" % float(tele.get("_radius"))
			half_s = "%8.1f" % rad_to_deg(float(tele.get("_half_angle")))
			light_s = "%5s" % str(bool(tele.get("_cone_light")))
			var c: Color = tele.get("accent")
			accent_s = "%.2f,%.2f,%.2f %s" % [c.r, c.g, c.b, _hue_word(c)]
		print("%-14s | %-13s | %-8s %-19s | %s | %s | %s | %-17s | %s | %-5s | %s" % [
			CLASS_NAMES[cls],
			String(hero.get("_cfg").get("primary", "bolt(default)")),
			style_s, shape_s, radius_s, half_s, light_s, accent_s,
			("%.2f>%.2f" % [shield_before, shield_after]),
			guards,
			"yes" if arc != null else "no",
		])
		# ⚠ AND `free()` WAS THE WRONG CORRECTION — the second version of this probe
		# tried to hard-free every root child between classes and tore out nodes the
		# rig still held references to ("Invalid access to property 'rank_changed' on
		# a previously freed object"), which silently zeroed SIX of the nine rows.
		# The id-diff above is the whole fix; leaked nodes are harmless once each
		# reading is scoped to what THIS press created.
		hero.queue_free()
		e.queue_free()
	quit(0)
	return true


## Instance ids of every telegraph alive right now, so the press's own tell can be
## told apart from anything a previous iteration left standing.
func _telegraph_ids() -> Dictionary:
	var out: Dictionary = {}
	for n: Node in get_nodes_in_group(&"telegraph"):
		if is_instance_valid(n):
			out[n.get_instance_id()] = true
	return out


func _new_telegraph(before: Dictionary) -> Node:
	for n: Node in get_nodes_in_group(&"telegraph"):
		if is_instance_valid(n) and not before.has(n.get_instance_id()):
			return n
	return null


func _swing_arc_ids() -> Dictionary:
	var out: Dictionary = {}
	for n: Node in root.get_children():
		if _is_swing_arc(n):
			out[n.get_instance_id()] = true
	return out


func _new_swing_arc(before: Dictionary) -> Node:
	for n: Node in root.get_children():
		if _is_swing_arc(n) and not before.has(n.get_instance_id()):
			return n
	return null


func _is_swing_arc(n: Node) -> bool:
	if not is_instance_valid(n) or n.get_script() == null:
		return false
	return String(n.get_script().resource_path).ends_with("SwingArc.gd")


## Any guard object the press may have opened. ParryRing is a RefCounted held in
## `Hero._guard` (so it is a field, not a child); SigilGuard is a child node.
func _guard_nodes(hero: Node) -> String:
	var out: PackedStringArray = PackedStringArray()
	var ring: Variant = hero.get("_guard")
	if ring != null and (ring as Object).has_method("quality"):
		if int(ring.call("quality")) != 0:
			out.append("ring")
	if hero.get_node_or_null("SigilGuard") != null:
		out.append("sigil")
	return "none" if out.is_empty() else ",".join(out)


func _style_name(s: int) -> String:
	var names: Array[String] = ["ZONE", "MUZZLE", "LANE", "DART", "GATHER",
		"BOMB", "FIST", "CRESCENT", "CONE"]
	return names[s] if s >= 0 and s < names.size() else str(s)


func _shape_name(s: int) -> String:
	var names: Array[String] = ["CIRCLE", "LINE", "CONE"]
	return names[s] if s >= 0 and s < names.size() else str(s)


func _hue_word(c: Color) -> String:
	if c.r > 0.8 and c.b > 0.6 and c.g < 0.6:
		return "(PINK/MAGENTA)"
	if c.r > 0.8 and c.g < 0.6 and c.b < 0.4:
		return "(ORANGE)"
	if c.r > 0.85 and c.g > 0.85 and c.b > 0.85:
		return "(WHITE)"
	return ""
