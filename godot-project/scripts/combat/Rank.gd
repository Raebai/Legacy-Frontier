extends Node
## Rank progression autoload: grinding kills accrues power, which maps to a
## tier (0..5) + title. A tier-up emits `rank_changed` — the hero's aura
## escalation plus the tiny HUD title ARE the feedback. No menus.
##
## ══ RANK IS WHAT YOU DID ON THIS ASCENT ═══════════════════════════════════════
## It used to be a career total: 6 tiers over 84 power at 3 power per kill, against
## a floor 1 that banks 28 kills and ~119 power. The fun audit measured the
## consequence — every tier landed inside the first ~40 seconds of the game, the
## number was PERSISTED, and from then on the channel was permanently maxed for that
## run AND for every future run. A progression fantasy that is over before the second
## floor is not a progression fantasy; it is a loading screen with a title on it.
##
## So the tier now reads `climb_power` — what you have earned since you walked into
## the tower — and `power` stays the lifetime total that `GameState` persists (a
## number for the results card and the town to talk about, not a difficulty input).
## `begin_climb()` zeroes the ascent when a run starts.
##
## ⚠ IT IS STILL A TITLE AND AN AURA, AND IT MUST STAY THAT WAY. The spec forbids
## permanent stat progression, so nothing here may ever grant HP, damage or speed.
## The whole point of resetting per climb is that the reward can be LOUD precisely
## because it is COSMETIC — a maxed aura on floor 5 costs the difficulty curve
## nothing.
##
## ══ HOW THE CURVE WAS SIZED ═══════════════════════════════════════════════════
## `tools/rank_sim.gd` walks the real floor tables against these constants and
## prints which floor each tier lands on. A full five-floor climb banks ~940 power
## (201 kills, 19 wave clears, ~10 boss phase breaks, plus a streak estimate), so
## the thresholds below are placed to land ROUGHLY ONE TIER PER FLOOR, with
## Ascendant deep inside the floor-5 guardian fight. A resumed two-floor climb
## therefore reaches Adept and no further — which is the correct reading, not a
## bug: Ascendant means "I climbed the whole tower in one breath".
##
## Re-run the sim after touching any of: these thresholds, KILL_POWER,
## Hype.WAVE_CLEAR_POWER, PHASE_BREAK_POWER, or a floor's wave budget.

const HudStyle := preload("res://scripts/ui/HudStyle.gd")

signal rank_changed(new_tier: int, new_title: String)

## Threshold CLIMB power per tier (index = tier). Reaching TIER_POWER[i] IS tier i.
const TIER_POWER: Array[int] = [0, 70, 195, 350, 545, 830]
const TIER_TITLE: Array[String] = [
	"Nameless", "Climber", "Ranked", "Adept", "Ranker", "Ascendant",
]
## Power granted per enemy kill (Enemy._die feeds this via /root/Rank).
const KILL_POWER: int = 3
## Power for breaking a boss PHASE (Boss._enter_phase feeds this via /root/Rank).
##
## The audit's other rank finding: a boss fight is the longest stretch in the game
## with NO reward event — Hype's streak and multi-kill channels both need a crowd
## and a 1v1 has none, so floor 5's climactic ~30 seconds paid out nothing at all.
## A phase break is the one beat a boss fight reliably produces, so it is the beat
## that pays. Worth ~3 kills, twice a fight.
const PHASE_BREAK_POWER: int = 10

## LIFETIME total. Persisted by GameState (`climber.json` "rank_power"); read by
## the run summary. NOT what the tier reads — see the header.
var power: int = 0
## THIS ASCENT. What `tier()` reads, zeroed by `begin_climb()`.
var climb_power: int = 0

var _hud_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	_refresh_hud()
	rank_changed.connect(_on_rank_changed)
	# Deferred because autoload _ready order is not a contract: at this point
	# /root/GameState may not exist yet. By the first idle frame every autoload
	# does. Guarded tree lookup rather than the bare identifier so a --script
	# harness (which registers no autoloads at all) simply finds nothing.
	call_deferred(&"_bind_run_start")


## Reset the ascent when a run begins. Connected to GameState.run_started, which is
## emitted AFTER GameState._restore_rank_power() has pushed the saved lifetime total
## back into `power` — so the order is "restore the career, then start the climb at
## zero", which is the one order that produces the right answer.
func _bind_run_start() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	var gs: Node = tree.root.get_node_or_null(^"GameState")
	if gs == null:
		return
	if gs.has_signal(&"run_started") and not gs.is_connected(&"run_started", begin_climb):
		gs.connect(&"run_started", begin_climb)
	# ⚠ AND THE VISIBILITY HAS TO BE RE-ASKED ON BOTH EDGES. `_refresh_hud` runs off
	# `rank_changed`, which only fires when the TIER FLIPS — so entering a run at
	# tier 0 (every run does) and leaving one at tier 0 would both change what the
	# label should be doing while emitting nothing at all.
	if gs.has_signal(&"run_started") and not gs.is_connected(&"run_started", _refresh_hud):
		gs.connect(&"run_started", _refresh_hud)
	if gs.has_signal(&"run_ended") and not gs.is_connected(&"run_ended", _on_run_ended):
		gs.connect(&"run_ended", _on_run_ended)
	_refresh_hud()   # and once now, for the boot frame this binds on


## Highest tier whose threshold this ASCENT's power meets, clamped to 0..5.
func tier() -> int:
	var t: int = 0
	for i: int in range(TIER_POWER.size()):
		if climb_power >= TIER_POWER[i]:
			t = i
	return clampi(t, 0, TIER_TITLE.size() - 1)


func title() -> String:
	return TIER_TITLE[tier()]


## Grant power (kills, wave clears, boss phase breaks). Feeds BOTH the lifetime
## total and this ascent. Emits rank_changed only when the tier actually flips.
func add_power(n: int) -> void:
	_apply(power + n, climb_power + n)


## Set power directly (demo / capture tools / tests). Sets the ascent too, so a
## driver that says "make the hero Ascendant" gets an Ascendant hero.
func set_power(n: int) -> void:
	_apply(n, n)


## A new ascent: the tier ladder starts over, the lifetime total does not.
## Takes no argument so it can be connected straight to GameState.run_started.
func begin_climb() -> void:
	_apply(power, 0)


func _apply(new_power: int, new_climb: int) -> void:
	var before: int = tier()
	power = new_power
	climb_power = new_climb
	var after: int = tier()
	if after != before:
		rank_changed.emit(after, title())


func _on_rank_changed(_new_tier: int, _new_title: String) -> void:
	_refresh_hud()


## `run_ended` carries the outcome dictionary; the label does not care what is in it.
func _on_run_ended(_outcome: Dictionary) -> void:
	_refresh_hud()


## Minimal HUD: one small outlined title label, top-center. Not a menu — the
## rank title + the aura escalation are the entire progression UI.
func _build_hud() -> void:
	var hud: CanvasLayer = CanvasLayer.new()
	# ⚠ 52, NOT 50. This label and `Arena`'s floor banner were BOTH on layer 50, both
	# `PRESET_TOP_WIDE`, both centred on x=320 — the rank title at y~2-25 and the
	# banner at y~18-41 — so their outline bands overlapped and which one won was
	# tree order. They are now one layer (52, "the banner layer") with two bands that
	# cannot touch: see the LAYERS AND BANDS block in `HudStyle`.
	hud.layer = HudStyle.LAYER_BANNER
	add_child(hud)
	_hud_label = Label.new()
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_label.offset_top = HudStyle.BAND_RANK[0]
	# The rect IS the band, so the test can measure it rather than infer it.
	_hud_label.custom_minimum_size = Vector2(0.0,
		HudStyle.BAND_RANK[1] - HudStyle.BAND_RANK[0])
	_hud_label.clip_text = true
	_hud_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	HudStyle.label(_hud_label, HudStyle.SMALL, HudStyle.CHALK)
	hud.add_child(_hud_label)


## ⚠ "NAMELESS · TIER 0" IS NOT A STATUS, IT IS A LABEL FOR NOTHING — and it was
## being printed over the TITLE SCREEN, where there is no climb to have a rank in.
##
## Maker, 2026-08-04: "remove that nameless tier 0". Two conditions hide it, and
## between them the label now only ever appears when it means something:
##
##   * NOT IN A RUN. `Rank` is an autoload, so its CanvasLayer outlived every scene
##     change and sat on the title screen, the Antechamber and the summary card.
##   * TIER 0. The bottom rung is the absence of a rank. Announcing it is the same
##     as an empty health bar labelled "alive": it costs a line of screen and tells
##     the player nothing they could act on.
##
## The first tier-up is therefore also the first time this text EXISTS, which makes
## it an event rather than a readout — the same reason the spec keeps rank cosmetic.
func _refresh_hud() -> void:
	if _hud_label == null:
		return
	_hud_label.text = "%s · Tier %d" % [title(), tier()]
	_hud_label.visible = tier() > 0 and _in_run()


## Is a climb actually happening? Guarded tree lookup rather than the bare autoload
## identifier, so a `--script` harness (which registers no autoloads) simply answers
## false instead of taking the compile down.
func _in_run() -> bool:
	if not is_inside_tree():
		return false
	var gs: Node = get_node_or_null(^"/root/GameState")
	return gs != null and gs.has_method(&"is_run_active") and bool(gs.call(&"is_run_active"))
