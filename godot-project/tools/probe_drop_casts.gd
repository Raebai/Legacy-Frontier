extends SceneTree
## DOES A SHOWCASE BOT EVER CAST THE TIER 3 DROP IT WAS GIVEN?
##
## Measured across 14 clip takes: `ults 0` every time, and `spells 6` (three distinct
## per fighter) where a drops-off bout gets 8 (four each). `SpellGrant.TIER3_SLOT` IS
## `SpellTier.ULT_SLOT`, so the showcase drop does not sit alongside the ultimate — it
## REPLACES it. If the drop is then never cast, a showcase bout is strictly less
## spectacular than one with the feature turned off: the bots lost their ult and do not
## use what took its place.
##
## This prints, per fighter: what is actually installed in every slot, and how many
## times each spell id was cast. If the drop is in the slot and the count is zero, the
## fault is the brain's scoring, not the grant.
##
## Run:
##   godot --headless --path godot-project --script tools/probe_drop_casts.gd

const MATCH_SCENE := "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT := "res://scripts/combat/BotMatch.gd"
const SETTLE: int = 90
const FRAMES: int = 4200
const PAIRS: Array[Array] = [[6, 8], [3, 6], [0, 1]]
const NAMES: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut", "Cleric",
	"Cryomancer", "Stormcaller", "Necromancer", "Swordsaint",
]

var _casts: Dictionary = {}


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	root.size = Vector2i(1366, 768)
	await process_frame
	for pair: Array in PAIRS:
		await _run(int(pair[0]), int(pair[1]))
	quit()


func _on_cast(id: String, is_ult: bool) -> void:
	var key: String = "%s%s" % [id, "  (ULT)" if is_ult else ""]
	_casts[key] = int(_casts.get(key, 0)) + 1


func _run(a: int, b: int) -> void:
	_casts = {}
	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	script.set("class_a", a)
	script.set("class_b", b)
	script.set("drops", true)          # the SHIPPED showcase configuration
	script.set("auto_rematch", false)
	var m: Node = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(m)
	for i: int in SETTLE:
		await process_frame
	print("")
	print("=== %s vs %s ===" % [NAMES[a], NAMES[b]])
	var fighters: Array[Node] = []
	for n: Node in root.get_tree().get_nodes_in_group(&"hero"):
		if is_instance_valid(n):
			fighters.append(n)
			if n.has_signal("spell_cast") and not n.is_connected("spell_cast", _on_cast):
				n.connect("spell_cast", _on_cast)
	for f: Node in fighters:
		_dump_slots(f)
	# ⚠ IS SLOT 3 EVER AVAILABLE? A long cooldown cannot explain a spell that is
	# never cast if the slot starts READY — the bot would simply fire it once and
	# then sit on it. So sample the slot's own readiness rather than inferring it.
	var ready_frames: int = 0
	var first_ready: int = -1
	for i: int in FRAMES:
		await process_frame
		if fighters.is_empty() or not is_instance_valid(fighters[0]):
			continue
		var cd: float = _slot_cd(fighters[0], SpellTier.ULT_SLOT)
		if cd <= 0.0:
			ready_frames += 1
			if first_ready < 0:
				first_ready = i
	print("  slot %d ready on %d/%d frames (first ready at frame %d)" % [
		SpellTier.ULT_SLOT, ready_frames, FRAMES, first_ready])
	print("  --- casts over %d frames ---" % FRAMES)
	if _casts.is_empty():
		print("    (nothing cast at all)")
	var keys: Array = _casts.keys()
	keys.sort()
	for k: String in keys:
		print("    %-34s %d" % [k, int(_casts[k])])
	m.queue_free()
	await process_frame


## Seconds of cooldown left on a slot, or 0 when it is ready to cast.
func _slot_cd(hero: Node, slot: int) -> float:
	var hand: Variant = hero.get("_hand")
	if hand == null:
		return -1.0
	# ⚠ THE INDEX OFFSET. `HandSlots` keeps FISTS at index 0, so signature slot `i`
	# lives at hand index `i + 1`. Indexing with the signature index directly reads a
	# DIFFERENT spell's cooldown — which would have made this probe answer confidently
	# about the wrong slot.
	return float((hand as Object).call("cooldown", slot + 1))


## What is actually in each slot right now, and which one is the drop.
func _dump_slots(hero: Node) -> void:
	var spells: Variant = hero.get("_signatures")
	if spells == null:
		print("  %s: no _signatures array" % hero.name)
		return
	var arr: Array = spells as Array
	var ult_slot: int = SpellTier.ULT_SLOT
	print("  %s — %d slots (slot %d is the ULT/TIER3 slot)" % [hero.name, arr.size(), ult_slot])
	for i: int in arr.size():
		var s: Variant = arr[i]
		if s == null:
			print("    slot %d: (empty)" % i)
			continue
		var sd: SpellDef = s as SpellDef
		var tier: int = SpellTier.of(sd)
		var tier_name: String = ["QUICK", "HEAVY", "ULT"][clampi(tier, 0, 2)]
		print("    slot %d: %-22s kind=%-11s tier=%-5s charges=%2d cd=%5.1f mp=%3d  (hero mp %.0f/%d)" % [
			i, sd.id, _kind_name(sd.kind), tier_name, sd.charges, sd.cooldown,
			sd.mp_cost, float(hero.get("mp")), int(hero.get("max_mp"))])


func _kind_name(kind: int) -> String:
	for k: String in SpellDef.Kind.keys():
		if int(SpellDef.Kind[k]) == kind:
			return k
	return str(kind)
