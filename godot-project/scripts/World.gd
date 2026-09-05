extends Node2D
## THE TOWN — the game's front door.
##
## ══ WHY IT EXISTS AGAIN, AND WHAT WOULD MAKE IT WORTHLESS ═══════════════════
## The maker played this an hour before it was rewritten and ruled: "it's just
## another layer that doesn't add any value." That verdict stands and this file is
## written against it. A town you have to WALK ACROSS TO REACH A MENU is friction,
## and on a phone it is worse than friction. Three rules follow, and every layout
## number below is one of them:
##
##   1. **THE TOWN IS THE INTERFACE, NOT A LOBBY YOU WALK TO A MENU INSIDE.** The
##      statue IS class select, the rack IS the armory, the lectern IS your three
##      spells, the door IS the tower. There is no "open the menu" step anywhere.
##   2. **YOU SPAWN ON THE DOORSTEP.** `PLAYER_SPAWN` is `TOWER_X - 104` — inside
##      the door's own proximity ring. The hint is already up on the first frame,
##      so the town costs ONE key press to leave and ZERO steps of walking. Every
##      station is BEHIND you; you go to them because you want something, never
##      because the route to the tower runs through them.
##   3. **THERE IS ALWAYS A FASTER PATH.** The title screen still opens with
##      CLIMB, which never enters the town at all. Nobody who just wants to fight
##      is ever taken on a tour.
##
## ══ NO LLM, ANYWHERE ═══════════════════════════════════════════════════════
## The v0.0 town's two anchors talked to a local Ollama server. That whole stack —
## the `Conversation` autoload, the four-layer memory files, the consolidation
## pipeline — is deleted. Townspeople speak in `Bark`'s voice: one line over a
## head, then gone. See `NPC.gd`.
##
## Side-on, same look and feel as the arena, under the shared `Atmosphere` sky.

const TOWN_WIDTH: float = 1180.0
const GROUND_Y: float = 452.0
const GROUND_THICKNESS: float = 260.0

## ══ YOU CANNOT LEAVE THE TOWN ═══════════════════════════════════════════════════
## Maker: *"please make sure people cannot jump off the left panel in the lobby to get
## out the map, and if they fall out to respawn at the entrance"*.
##
## ⚠ THE LEFT PANEL IS THE LOFT AND THE NUMBERS SAY IT IS REACHABLE. `_build_ground`
## lays ONE slab from -100 to TOWN_WIDTH+100 and there was nothing at either end — no
## wall, no catch, nothing. The loft (`LOFT_CENTER` 215, `LOFT_SIZE` 300) starts at
## x 65 and sits 118 px up, so a running jump off its LEFT edge gets the full ~127 px
## of horizontal reach PLUS the extra airtime of falling 118 px to the ground — about
## 180 px in total, from x 65. That lands at roughly x -115, and the ground stops at
## -100. The player is then in open space with no floor under them, falling forever.
##
## So: real walls at the slab's own edges, and a catch under the world in case anything
## ever gets past them.
##
## ⚠ THE LEFT WALL MOVED OUT, AND THE CAMERA MOVED WITH IT. Maker: *"the far left side
## of the lobby can be a little further out before the invisible barrier"*. -100 put the
## wall's inner face at -76 — but the town camera's `limit_left` was 0, so the last
## ~76 px of legal floor were floor the camera COULD NOT FRAME: you walked off the left
## edge of the picture and then hit something you could not see. Handing back more room
## without moving the clamp would have made that corridor longer, not better.
##
## So both numbers move together and the new room is FRAMED. -196 puts the inner face at
## -172 (a body reaches about x -163) and `_place_player` sets `limit_left` to -210, so
## at the far wall the player still stands ~47 px inside the frame. It is also what the
## bar in `AntechamberBackdrop` is drawn into — a room does not need more empty floor,
## it needs somewhere else to be.
const BOUND_LEFT: float = -196.0
const BOUND_RIGHT: float = TOWN_WIDTH + 100.0
## What the town camera is allowed to show past the left wall. See the ⚠ above: it is
## OUTSIDE `BOUND_LEFT` on purpose, so the wall is a place you arrive at rather than the
## edge of the picture. The floor slab and the drawn room both run further still.
const CAM_LIMIT_LEFT: float = -210.0
## Thick enough that a body moving fast cannot tunnel through it in one physics step.
const BOUND_THICKNESS: float = 48.0
## Tall enough that no jump, and no jump off the loft, clears the top. The loft is
## 118 px up and a jump adds ~105, so 420 is well clear of anything reachable.
const BOUND_HEIGHT: float = 420.0
## How far BELOW the ground a body has to be before it counts as having left the world.
## Generous, so a body merely clipping into the floor is never teleported mid-stride.
const FALL_OUT_MARGIN: float = 260.0

## ══ THE PAD ROW — TWO PADS, AND THAT IS THE WHOLE ROW ═══════════════════════
## Maker, asked which of the four pads to keep: *"I only want one for class within
## which I can edit spells, and one for armoury where I can look at my equipment"*.
##
## So the row is TWO discs and nothing else:
##
##   * `ARMORY_X` ⚔ — equipment. Opens `Loadout` (3 slots x 19 pieces).
##   * `CLASS_X`  ☗ — WHO YOU ARE **AND** WHAT YOU CARRY, on one screen. Pressing it
##     opens the `Outfitter`, whose top row is a full-width button carrying your class
##     name; that button opens `ClassSelect` on top. Two taps to change class, one tap
##     to change a spell, no keyboard anywhere — see the merge note on `open_outfitter`.
##
## ⚠ THE LECTERN AND THE ARCHIVIST ARE DELETED, and the archivist is the interesting
## one. `"spells"` was a second pad for a screen the class pad now contains, i.e. the
## fourth-and-fifth pad of a row whose complaint was already that it was a row. `"tree"`
## opened `SpellTreeScreen`, which SPENDS REAL POINTS and changes nothing that reaches a
## fight: `SpellTree.bindable_spells()` — the function the whole economy exists to feed
## — has no caller anywhere outside its own suite. A pad that takes something from the
## player and gives back nothing is worse than a missing pad, so it went first. See the
## header of `scripts/ui/SpellTreeScreen.gd` for exactly what has to become true before
## it comes back.
##
## ⚠ THE STEP IS NOT A LOOK, IT IS THE PROXIMITY RING. `ArmoryStation.PROXIMITY_RADIUS`
## is 46, so two pads closer than 92 px put two "[E] ..." hints on screen at once and
## the player cannot tell which one the key will press. `PAD_STEP` still describes the
## row honestly: it is the centre-to-centre stride, a third pad would land at
## `PAD_FIRST_X + PAD_STEP * 2.0`, and `tools/slice_test_town.gd` asserts the gap
## against the ring rather than against this constant, so shrinking it fails loudly.
##
## ⚠ AND THE ROW MOVED RIGHT, WHICH IS THE PART A RESPACING BREAKS SILENTLY. The old
## first pad sat at 380 and the WARDEN patrols 320 +/- 24 with a 40 px hint ring, so his
## ring reached x=384 and overlapped the armoury pad — for part of every lap, standing ON
## the pad lit two prompts and the `talk` press went to him. `Interactables` arbitrates
## that by distance so it was survivable, but the honest fix for a two-pad row with a
## whole empty street to spend is to not overlap at all. 460 puts the armoury ring's left
## edge at 414, a clear 30 px beyond the warden's reach; `tools/probe_town_pads.gd`
## prints that gap and `slice_test_town_interact` fails if it ever goes negative.
const PAD_FIRST_X: float = 460.0
const PAD_STEP: float = 120.0
const ARMORY_X: float = PAD_FIRST_X                    # ⚔ your equipment
const CLASS_X: float = PAD_FIRST_X + PAD_STEP          # ☗ your class AND your spells
## THE HEARTH. Still named for the campfire it used to be — the constant is what
## `_spawn_ambience` hands `HubAmbience`, and renaming it would churn a public seam for
## a comment's worth of clarity. It is a stone fireplace set into the tavern's back wall
## now (see `HubAmbience._draw_hearth`); the x is unchanged, so the warm middle of the
## room is where it always was.
const CAMPFIRE_X: float = 800.0      # the warm middle; nothing to press

## ══ THE DUMMY YARD ═══════════════════════════════════════════════════════════
## Maker: "you should be able to cast spells and stuff within the lobby instead of a
## training ground — just have standing immortal test dummies on one side of the hub
## area."
##
## So the sparring PAD is gone. It was a teleport out of the room to `FreePlay`, which
## is a whole second scene with its own stage, its own camera and its own control card
## — an entire mode to answer "what does this spell look like". You cast where you are
## standing now, and the things you cast at are three bodies at the far end.
##
## ⚠ THEY ARE HERO BODIES, NOT PROPS, and that is the whole reason this works: a
## `Hero` with 9999 HP on a faction nothing is hostile to is already the shipped
## practice dummy (`VersusArena._rebuild_dummies`), so every spell, reaction, element
## and impact frame in the game treats it exactly as it treats a real target. A drawn
## scarecrow would have been a lie you could not hit.
const DUMMY_FIRST_X: float = 110.0
const DUMMY_STEP: float = 62.0
const DUMMY_COUNT: int = 3
## Nothing in the town can hurt anything, but the number still has to be big enough
## that a full ult does not visibly move the bar — that is what "immortal" reads as.
const DUMMY_HP: int = 9999
## Straw. Deliberately outside every class colourway in `ClassInfo`, so a dummy can
## never be mistaken for a fighter — least of all for your teammate.
const DUMMY_COLOR: Color = Color(0.66, 0.58, 0.38)
## The party stone stands between the campfire and the door, so the last thing you
## pass on the way out is the answer to "is my friend actually here".
const PARTY_X: float = 860.0
## ⚠ FURTHER RIGHT AND MUCH TALLER. Maker: "the tower should be way higher and further
## out to the right slightly and just look cooler". The height is `TowerDoor`'s; this
## is the "further right", and it also buys the shaft room to rise without the sign
## and the campfire crowding its base.
const TOWER_X: float = 980.0         # the way out

## ON THE DOORSTEP. See rule 2 above — this is the single most important number
## in the file. `TowerDoor.PROXIMITY_RADIUS` is sized to reach it.
## ⚠ 54 PUT YOU INSIDE THE DOORWAY. The door is 96 px wide now and you walk INTO it to
## descend, so spawning 54 px from its centre put the player on the threshold — a town
## you enter and immediately leave. 104 stands you just outside it, still well inside
## `TowerDoor.PROXIMITY_RADIUS`, so the room still costs zero steps to leave.
##
## ⚠ 104 PUT THE PLAYER INSIDE THE DOORKEEPER'S LAP, which is a different bug from the
## one above and a worse one. The doorkeeper ambled x=838..886 and the player spawned
## at x=876 -- INSIDE that span, not merely inside his 40 px hint ring. So every boot
## of the town opened with him frozen mid-stride and hint-lit, because `_player_in_
## range` was true before either of them had moved, and he could never amble or hop
## again until you walked away from your own spawn point. The whole "townsfolk have
## personality" feature was switched off for the one townsperson you always meet.
##
## 128 stands the player clear of his lap (see TOWNSFOLK, where he also moved) and
## still inside `TowerDoor.PROXIMITY_RADIUS` (150) -- and that ring is a 2D CIRCLE, so
## the door sitting 62 px above the ground line costs real budget that reasoning in x
## alone does not see: 140 px of x measures 153.3 px of distance and `slice_test_town`
## rejected it outright. 128 measures 142.4. The door's WALK-IN box is `ENTER_W` 68
## wide, i.e. x 946..1014 -- not the 96 an older comment here claimed -- so the new
## spawn at 852 is nowhere near the threshold.
const PLAYER_SPAWN: Vector2 = Vector2(TOWER_X - 128.0, GROUND_Y)

## Where the three townspeople stand, and how far they wander from it. They are
## posted NEXT TO the thing they talk about, so a bark is a signpost as well as a
## bit of character, and their wander ranges are small enough that they never
## drift into a station's own hint and make two prompts fight for the same corner.
##
## ⚠ TWO, NOT FOUR. Maker, walking the room: "townsfolk need PERSONALITY — have them
## jump around. Fewer of them." Four people in a room this size is a crowd you walk
## through; two is a place with somebody in it.
##
## WHICH TWO, AND WHY THE OTHER TWO WENT. Each one had a job (spec §7) and only two of
## those jobs survive the pads. The Quartermaster said what a gear slot TRADES AWAY and
## the Scribe said how the tree is priced — both are SIGNPOSTING, and signposting is
## exactly what the teleport pads and the signboard now do with a picture instead of a
## paragraph. What no pad can say is kept:
##
##   * the WARDEN teaches the three mechanics that are invisible until they kill you —
##     a thing you cannot learn from a glyph on the floor;
##   * the DOORKEEPER reads your climb back to you (floor, best, falls, level, through
##     `NPC._fill`). That is the deleted AI-NPC stack's actual job, and it turns out it
##     never needed a language model. It needed four numbers and a token in a string.
##
## The two lost `.tres` files are NOT deleted — a townsperson is one line in this table,
## so putting either back costs one line and no content.
const TOWNSFOLK: Array[Dictionary] = [
	# ⚠ THE WARDEN MOVED OFF THE DUMMY YARD, AND IT WAS A MEASURED BUG, not a taste
	# call. `NPC.tscn` is a StaticBody2D on collision layer 1 — which is
	# `CharacterRig.GROUND_MASK` — so a townsperson standing among the dummies becomes
	# FLOOR to their downward probes. `probe_town_feet` caught the third dummy reading
	# its ground line at 436 instead of 452: it was standing on the Warden's head.
	{"res": "res://data/npcs/warden.tres", "x": 320.0, "range": 24.0},   # by the pads
	# ⚠ MOVED OFF THE PLAYER'S SPAWN (see PLAYER_SPAWN). At 862 +/- 24 he walked
	# 838..886 and the player materialised at 876, so he was permanently in range and
	# permanently frozen. 920 +/- 20 walks 900..940: it clears the new spawn at 852 by
	# 48 px (his ring is 40), and stops 6 px short of the door's walk-in box at 946, so
	# he never stands in the doorway you are trying to walk through either.
	# ⚠ RANGE 0 — HE DOES NOT PACE, AND THAT IS A RULING. Maker: *"the doorkeeper has
	# too much text, it should be clear what he does, and he should stand still in front of
	# the tower"*. He is the only townsperson with a JOB (he owns the climb reset), and a
	# body that wanders is read as scenery — you look for a shopkeeper behind a counter, not
	# walking laps past one. The warden still ambles, so the room keeps its motion.
	#
	# 930 puts him just outside the door's walk-in box (`TowerDoor.ENTER_W` 68 at
	# `TOWER_X` 980 = x 946..1014), so he stands AT the tower without standing IN the
	# doorway you are trying to walk through — he is a StaticBody-layer body and would
	# block it. It also clears the player spawn at 852 by 78 px against his 40 px hint
	# ring, so the town no longer opens with his prompt already up.
	{"res": "res://data/npcs/doorkeeper.tres", "x": 930.0, "range": 0.0},  # AT the door
]

## Decoration only — a raised deck up-left. It used to be where the armory lived,
## behind a jump. Nothing a phone player needs is up a platform any more.
##
## ⚠ IT IS THE TAVERN'S GALLERY NOW, and it finally has a reason to be reachable:
## `AntechamberBackdrop._draw_stair` draws a stringer and seven treads under these two
## slabs, so the loft reads as the upstairs and the STEP reads as the landing. The
## numbers are unchanged — only the thing drawn behind them is.
## ── THE SIGNBOARD ────────────────────────────────────────────────────────────
## Maker: "a SIGN in the background, part of the map, telling you where to go."
##
## ⚠ IT REPLACED A SENTENCE, IT DID NOT ADD TO ONE. The town used to carry a line of
## HUD text along the bottom of the screen — "walk left: gear · spells · class · the
## tower is right here · Esc: title" — which is thirteen words of chrome floating over
## a room that could simply contain a sign. The board is IN the world, it is where a
## sign would actually be (between you and the shops, facing the door you spawn on),
## and the HUD line is gone. Same information, no chrome, and it obeys the standing
## rule: remove the words, keep the picture.
## ⚠ 852 PUT IT BEHIND THE TOWER DOOR. Judged from `town_capture`, not from the
## number: the door's silhouette is ~80 px wide at x=900 and it ate the whole right
## arm, so the sign said "◂ stations" and nothing else. 700 sits it between the last
## pad and the campfire, still inside the frame you spawn looking at (the town camera
## is zoom 1.2, so spawn sees x≈579..1113).
## ⚠ MOVED TO THE MIDDLE OF THE ROOM AND MADE THE TALLEST THING IN IT. Maker: "the
## sign should be in the middle of the hub and the first thing you see". It was tucked
## by the door at 770 — the last thing you passed rather than the first thing you saw.
## 630 is the middle of the walkable street and sits between the third and fourth pad,
## so its post lands in a gap rather than on a disc.
const SIGN_X: float = 630.0
const SIGN_TOP: float = GROUND_Y - 150.0
const SIGN_POST: Color = Color(0.29, 0.22, 0.16)
const SIGN_BOARD: Color = Color(0.42, 0.32, 0.22)

const LOFT_CENTER: Vector2 = Vector2(215.0, GROUND_Y - 118.0)
const LOFT_SIZE: Vector2 = Vector2(300.0, 16.0)
const STEP_CENTER: Vector2 = Vector2(340.0, GROUND_Y - 58.0)
const STEP_SIZE: Vector2 = Vector2(120.0, 14.0)

## ⚠ THE FLOOR IS BOARDS NOW, NOT DIRT, AND THE RIM IS NOT MOSS. The old pair was a
## neutral grey-blue ground under a MOSSY GREEN lip, which was right for a forest
## clearing and is the single loudest wrong colour in a tavern — a cold floor with a
## green edge under warm lamplight reads as outdoors no matter what is drawn behind it.
## The ground is now dark oak and the lip is the `StageLayers` grammar's own warm cap
## (rule 1: a bright warm line along a top edge = you can stand on this), which is the
## colour every ledge in every fight already wears.
const GROUND_COLOR: Color = Color(0.121, 0.086, 0.064)
const GROUND_RIM: Color = Color(0.52, 0.39, 0.24)
## Floorboard seams. Drawn as thin darker lines across the slab — the only texture the
## floor gets, and what stops a gradient reading as a painted block under the lamps.
const BOARD_STEP: float = 96.0
const BOARD_SEAM: Color = Color(0.06, 0.042, 0.032, 0.85)
const CHALK: Color = Color(0.93, 0.92, 0.86)
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)

const TOWER_DOOR_SCRIPT: Script = preload("res://scripts/TowerDoor.gd")
const STATION_SCRIPT: Script = preload("res://scripts/ArmoryStation.gd")
const HUB_AMBIENCE_SCRIPT: Script = preload("res://scripts/HubAmbience.gd")
## The sky band ABOVE the forest: the colossal spire, the moon, the ridges, the drifting
## cloud and the petals. `preload`ed rather than named, like every other drawer here —
## it has no `class_name`, so it can never hit the global-class-cache trap.
const ANTECHAMBER_BACKDROP_SCRIPT: Script = preload("res://scripts/ui/AntechamberBackdrop.gd")
const NPC_SCENE: PackedScene = preload("res://scenes/NPC.tscn")
## ⚠ REACHED BY PATH, NEVER PRELOADED. `Hero.tscn` drags the whole combat dependency
## chain — SpellCaster, every spectacle, the bot stack — and a `preload` here would
## compile all of it at THIS script's parse time, which is the trap every capture tool
## in this project documents. `load()` at spawn time pays the same cost once, later,
## on a frame where the player is already looking at a loading screen.
const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"

## Every tappable target in the town clears this, in base units, matching the
## floor `Outfitter` and `Lobby` hold themselves to.
const MIN_TAP: float = 30.0

var _outfitter_layer: CanvasLayer = null
var _outfitter: Control = null


func _ready() -> void:
	_build_backdrop()
	_build_ground()
	_build_bounds()
	_build_ledges()
	# ⚠ `_build_loft()` USED TO BE HERE. Maker: *"remove the platforms on the training
	# area at the entrance on the left"* — the two decks above the dummy yard. The
	# function and its constants stay: `LOFT_CENTER` / `LOFT_SIZE` are read by
	# `slice_test_town_bounds`, which teleports the player up there and fires them off
	# at speed as its worst-case bounds case. That test never needed a real platform to
	# stand on (it sets the position directly), so it keeps passing — but deleting the
	# constants would take the stress case with them.
	#
	# The file already called them decoration: "nothing a phone player needs is up a
	# platform any more". This is that sentence finished.
	_build_signboard()
	_spawn_ambience()
	_place_player()
	# AFTER `_place_player`, so the peer bodies are laid out relative to a doorstep
	# the local player is already standing on rather than to wherever Main.tscn
	# happened to park it.
	_setup_peer_bodies()
	_spawn_tower_entrance()
	_spawn_stations()
	_spawn_dummy_yard()
	_spawn_townsfolk()
	_spawn_hud()
	_spawn_touch_pad()
	_reflect_selected_class()

	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("play_hub"):
		music.play_hub()

	# The bark/voice observer normally installs itself from Sfx on the first frame
	# a scene exists; re-ensuring it is free and covers entering the town directly.
	VoiceDirector.ensure(get_tree())


# ------------------------------------------------------------------- environment
## ⚠ THE SKY GOT DEEPER AND THE ROOM GOT A TOWER IN IT. Maker: *"optimise the lobby
## area where they can enter the tower, make it feel way more epic, change the
## background to make it feel cooler … I'll add some cool anime peaceful music for the
## entry area"*.
##
## ⚠ AND THEN THE WHOLE ROOM WENT INDOORS. Maker, later: *"make the lobby very
## different like a tavern vibe I like that feel way more — not outside at a campfire
## but instead inside of a tavern with warm lit and cool graphics"*. The verdict above
## still holds and the epic is still here; what changed is WHERE you are standing while
## you look at it. `AntechamberBackdrop` is now a tavern shell — plank wall, tie-beam,
## hanging lamps, a bar — and the spire, the moon and the night are seen THROUGH its
## three windows. See the brainstorm at the top of that file for what an interior
## excludes and why nothing here was merely re-tinted.
##
## The room itself is `AntechamberBackdrop`, and it is a SEPARATE node on a separate
## rung for the reasons written at the top of that file. `Atmosphere` still owns the
## sky gradient and the distant spires — which are now what shows through the glass.
func _build_backdrop() -> void:
	var atmo := Atmosphere.new()
	add_child(atmo)
	# ⚠ THIS IS NOW THE NIGHT SEEN THROUGH THREE WINDOWS, NOT THE ROOM'S OWN SKY, AND
	# THAT IS WHY IT GOT COLDER. `AntechamberBackdrop` paints an opaque plank wall over
	# this whole rung and stops the paint at its window openings — so every pixel of
	# `Atmosphere` that survives is framed by timber, and its job changed from "the dusk
	# you are standing in" to "the cold thing the tavern is warm against". A dusk violet
	# read as a second warm light source through the glass and killed the contrast the
	# whole room is built on. Deep night blue does not.
	#
	# ⚠ AND IT IS NOT DELETED, THOUGH NOTHING BUT THE WINDOWS SHOWS IT. It is what makes
	# the openings holes rather than blue rectangles: the sky gradient and the distant
	# spires slide behind the frames exactly as a view does.
	var sky_bottom := Color(0.105, 0.118, 0.235)
	var accent := Color(0.62, 0.70, 1.0)
	atmo.build(Rect2(Vector2(-400.0, -320.0), Vector2(TOWN_WIDTH + 800.0, GROUND_Y + 760.0)), {
		"sky_top": Color(0.020, 0.024, 0.062),
		"sky_bottom": sky_bottom,
		"silhouette_far": Color(0.048, 0.056, 0.120),
		"silhouette_near": Color(0.026, 0.030, 0.068),
		"accent": accent,
	})
	# THE SPIRE, THE MOON, THE RIDGES, THE CLOUD AND THE PETALS. Added AFTER the
	# Atmosphere so tree order agrees with the z ladder rather than fighting it — the
	# backdrop parks itself on `StageLayers.MOUNTAIN` (-18), in front of Atmosphere's
	# SKYLINE (-22) and behind the forest (-6).
	var spire: Node2D = ANTECHAMBER_BACKDROP_SCRIPT.new()
	add_child(spire)
	spire.call("build", TOWN_WIDTH, GROUND_Y, TOWER_X, sky_bottom, accent)


func _spawn_ambience() -> void:
	var amb: Node2D = HUB_AMBIENCE_SCRIPT.new()
	add_child(amb)
	amb.call("build", TOWN_WIDTH, GROUND_Y, CAMPFIRE_X)


func _build_ground() -> void:
	var body := StaticBody2D.new()
	# ⚠ THE SLAB IS DERIVED FROM THE WALLS NOW, NOT FROM `TOWN_WIDTH`. It used to be
	# `TOWN_WIDTH + 200` centred on the town, i.e. -100..1280 — which happened to end
	# exactly at the old `BOUND_LEFT`. Moving that wall out by 96 px would have left the
	# player standing on nothing, and the bug would have looked like a physics fault
	# rather than an arithmetic one. Spanning the bounds with 100 px of overhang at each
	# end makes it impossible to move a wall past the floor again.
	var slab_l: float = BOUND_LEFT - 100.0
	var slab_r: float = BOUND_RIGHT + 100.0
	body.position = Vector2((slab_l + slab_r) * 0.5, GROUND_Y + GROUND_THICKNESS * 0.5)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(slab_r - slab_l, GROUND_THICKNESS)
	cs.shape = shape
	body.add_child(cs)
	var grad := Gradient.new()
	grad.set_color(0, GROUND_COLOR.lightened(0.10))
	grad.set_color(1, GROUND_COLOR.darkened(0.4))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = shape.size
	rect.position = -shape.size * 0.5
	rect.z_index = -5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rect)
	var rim := ColorRect.new()
	rim.color = GROUND_RIM
	rim.size = Vector2(shape.size.x, 4.0)
	rim.position = Vector2(-shape.size.x * 0.5, -shape.size.y * 0.5)
	rim.z_index = -4
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rim)
	# FLOORBOARD SEAMS. Cheap `ColorRect`s rather than a `_draw`, so the floor stays a
	# node with no script and no redraw cost at all — they are static, and a static
	# thing that never animates has no business owning a paint callback.
	#
	# ⚠ THEY ARE PERPENDICULAR TO THE BOARDS YOU'D EXPECT. This is a SIDE-ON room, so
	# the floor is seen edge-on: what a player can actually see of a board is its END,
	# which is a vertical seam. A horizontal "plank" line here would read as a step.
	var seam_x: float = slab_l + BOARD_STEP
	while seam_x < slab_r:
		var seam := ColorRect.new()
		seam.color = BOARD_SEAM
		seam.size = Vector2(1.0, 14.0)
		seam.position = Vector2(seam_x - body.position.x, -shape.size.y * 0.5 + 4.0)
		seam.z_index = -4
		seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(seam)
		seam_x += BOARD_STEP
	add_child(body)


func _build_loft() -> void:
	_make_platform(LOFT_CENTER, LOFT_SIZE)
	_make_platform(STEP_CENTER, STEP_SIZE)


## ══ THE TWO LEDGES, AND WHY THEY ARE NOT THE ONES THAT WERE DELETED ═════════
## Maker: *"add ledge where you think they could be helpful"*. The same maker had the
## LOFT and the STEP removed from this room hours earlier (*"remove the platforms on
## the training area at the entrance on the left"*), so "add a ledge" cannot mean "put
## those back". What was wrong with them is the thing this avoids:
##
##   1. THEY WERE FLOATING SLABS. A dark rectangle hanging in the air over the dummy
##      yard is level geometry, not a room. Both ledges here are the TOP OF SOMETHING
##      THAT IS ALREADY DRAWN — the bar counter and the barrel stack beside it — so
##      they read as furniture you climbed onto, which is what a tavern ledge is.
##   2. THEY WERE IN THE WAY. They sat over the training dummies. These are in the
##      strip the left wall gave back (`BOUND_LEFT` moved out to -196), west of the
##      first dummy at x 110, so nothing in the room has to be walked around.
##
## The stack is a real two-step traversal: floor -> barrel (y 379) -> bar top (y 393)
## is wrong-way-round on paper, so it is floor -> bar top -> barrel, i.e. a short hop
## up and then a taller one, which is the shape that is worth doing at all.
##
## ⚠ COLLIDER-ONLY, VIA `_make_ledge` RATHER THAN `_make_platform`. The visual already
## exists in `AntechamberBackdrop._draw_bar`, and `_make_platform` paints its own dark
## slab plus a rim — running it here would draw a grey plank straight through the
## counter it is meant to BE.
const LEDGE_BAR_CENTER: Vector2 = Vector2(-59.0, 398.0)
const LEDGE_BAR_SIZE: Vector2 = Vector2(238.0, 10.0)
## ⚠ ITS RIGHT EDGE IS x 90 AND THE FIRST DUMMY STANDS AT 110. See `BARREL_DX` in
## `AntechamberBackdrop`: a ledge reaching under a dummy makes the dummy read its ground
## line off the ledge instead of the floor, which is the fault `probe_town_feet` exists
## to catch.
const LEDGE_BARREL_CENTER: Vector2 = Vector2(68.0, 383.0)
const LEDGE_BARREL_SIZE: Vector2 = Vector2(44.0, 8.0)


func _build_ledges() -> void:
	_make_ledge(LEDGE_BAR_CENTER, LEDGE_BAR_SIZE)
	_make_ledge(LEDGE_BARREL_CENTER, LEDGE_BARREL_SIZE)


## A standable surface with NO visual of its own — for ledges whose picture is drawn by
## the scenery. Same layer/mask contract as `_build_bounds`: layer 1 is what `Hero`
## collides with, mask 0 because a ledge detects nothing.
func _make_ledge(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## A two-armed signpost: one arm pointing back at the pads, one at the door.
##
## ⚠ NO COLLISION. It is scenery you read, not a thing you bump into — the room's
## whole complaint was that it made you walk around objects.
func _build_signboard() -> void:
	var post := ColorRect.new()
	post.color = SIGN_POST
	post.size = Vector2(5.0, GROUND_Y - SIGN_TOP)
	post.position = Vector2(SIGN_X - 2.5, SIGN_TOP)
	post.z_index = -3
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(post)
	# LEFT arm: what is behind you. RIGHT arm: the way out. The arrow is part of the
	# string so the plank and the direction can never disagree.
	# ⚠ THE OLD LEFT ARM LISTED A GLYPH THAT NO LONGER EXISTS (◎, the deleted sparring
	# pad) and both arms overflowed their planks — maker: "the symbols do not fit,
	# neither does the tower text". The planks are measured from their own strings now,
	# so an arm cannot be narrower than what is written on it.
	# ⚠ TWO GLYPHS, BECAUSE THERE ARE TWO PADS. It listed four (⚔ ☗ ✦ ❖) and the last
	# two are the deleted lectern and Archivist — the same failure the arm already had
	# once, when it advertised the removed sparring pad's ◎. A sign that names a door
	# that is not there is worse than no sign, because the player goes looking.
	_sign_arm("◂  ⚔ ☗", -1.0, SIGN_TOP + 10.0)
	_sign_arm("THE TOWER  ▸", 1.0, SIGN_TOP + 42.0)


## One plank, hanging off the post on `side`. The label is drawn on the plank rather
## than beside it so the two move together at any window size.
## ⚠ THE PLANK IS MEASURED FROM THE TEXT, NOT GUESSED. Both arms were fixed-width and
## both clipped what was written on them. `Font.get_string_size` is the only thing that
## knows how wide a string actually is at a given size — a hand-picked width is a
## measurement taken once, by eye, that then has to be re-taken every time a word
## changes and never is.
func _sign_arm(text: String, side: float, y: float) -> void:
	const FONT_SIZE: int = 13
	const PAD_X: float = 14.0
	const H: float = 24.0
	var font: Font = ThemeDB.fallback_font
	var width: float = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + PAD_X * 2.0
	var plank := ColorRect.new()
	plank.color = SIGN_BOARD
	plank.size = Vector2(width, H)
	plank.position = Vector2(SIGN_X + (0.0 if side > 0.0 else -width), y)
	plank.z_index = -3
	plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plank)
	var label := Label.new()
	label.text = text
	label.size = Vector2(width, H)
	label.position = plank.position
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", CHALK)
	label.z_index = -2
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)



## Invisible walls at either end of the ground slab. See the BOUND_* block for the
## measurement that says the loft could clear the left edge.
##
## ⚠ COLLISION-ONLY, and deliberately so: the town's own stated complaint was that it
## "made you walk around objects", so these are placed at the very edge of the drawn
## ground where nothing is, and they are invisible because a visible wall would read as
## somewhere you were supposed to be able to go.
func _build_bounds() -> void:
	for x: float in [BOUND_LEFT, BOUND_RIGHT]:
		var body := StaticBody2D.new()
		# collision_layer 1 is what `Hero` collides with; mask 0 because a wall does
		# not need to detect anything, it only needs to be detected.
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector2(x, GROUND_Y - BOUND_HEIGHT * 0.5)
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(BOUND_THICKNESS, BOUND_HEIGHT)
		cs.shape = shape
		body.add_child(cs)
		add_child(body)


## The belt to the walls' braces: anything that ends up under the world goes back to
## the doorstep. Maker: *"if they fall out to respawn at the entrance"*.
##
## ⚠ THIS IS NOT REDUNDANT WITH THE WALLS AND IT SHOULD NOT BE REMOVED IF THEY HOLD.
## A wall stops the case we know about — the loft. A catch stops every case we do not:
## a knockback through a seam, a spawn in the wrong place, a platform edited later that
## reaches further than this comment's arithmetic. The tower already learned this the
## expensive way; `Arena._catch_fallen_heroes` exists for the same reason.
##
## The entrance IS `PLAYER_SPAWN` — the tower doorstep you arrive on — so a fall puts
## you back where you came in rather than somewhere new to be confused by.
func _catch_fallen() -> void:
	var limit: float = GROUND_Y + FALL_OUT_MARGIN
	for n: Node in get_tree().get_nodes_in_group("player"):
		var body := n as Node2D
		if body == null or not is_instance_valid(body):
			continue
		if body.global_position.y <= limit:
			continue
		body.global_position = PLAYER_SPAWN
		# Zeroed, or the body arrives at the doorstep carrying the whole fall and
		# immediately punches back through the floor it just landed on.
		if &"velocity" in body:
			body.set(&"velocity", Vector2.ZERO)


func _process(_delta: float) -> void:
	_catch_fallen()


func _make_platform(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var rect := ColorRect.new()
	rect.color = Color(0.14, 0.12, 0.11)
	rect.size = size
	rect.position = -size * 0.5
	rect.z_index = -5
	body.add_child(rect)
	var rim := ColorRect.new()
	rim.color = GROUND_RIM
	rim.size = Vector2(size.x, 3.0)
	rim.position = Vector2(-size.x * 0.5, -size.y * 0.5)
	rim.z_index = -4
	body.add_child(rim)
	add_child(body)


# --------------------------------------------------------------------- placement
## ══ THE TEAMMATE'S BODY ═══════════════════════════════════════════════════════
## Maker: "a teammate spawns into the antechamber with you".
##
## Host and client both ROUTE here and the session is live, but peer bodies were
## spawned by `Arena._spawn_hero_net` through a `MultiplayerSpawner` plus the
## `party_ready` handshake — and none of that machinery existed in this file, so the
## room was a co-op lobby you stood in alone.
##
## ⚠ THIS IS A PORT, NOT A COPY. Three things differ from the Arena, and each of
## them is the reason a straight copy would have been wrong:
##
##   1. **The body is `Player`, not `Hero`.** The town walker is a different scene
##      with a different script. Spawning a `Hero` here would put a combat body with
##      spells, cooldowns and a damage model into a room with nothing to fight.
##   2. **The LOCAL player already exists.** `Main.tscn` parks one Player in the
##      scene and `_place_player` moves it to the doorstep. So the spawner must
##      create bodies for the OTHER peers only — spawning one for yourself would
##      leave you standing inside a twin.
##   3. **The handshake is tagged "antechamber".** See the `party_ready` note in
##      Net.gd: sharing the arena's one-shot would have meant nobody spawns in the
##      actual fight.
var _peers_root: Node2D = null
var _peer_spawner: MultiplayerSpawner = null

## Far enough apart that two stick figures do not overlap at the door, near enough
## that you can see who arrived without turning the camera.
const PARTY_SPAWN_GAP: float = 46.0


func _setup_peer_bodies() -> void:
	var net: Node = get_node_or_null("/root/Net")
	if net == null or not net.is_active():
		return
	_peers_root = Node2D.new()
	_peers_root.name = "Peers"
	add_child(_peers_root)

	_peer_spawner = MultiplayerSpawner.new()
	_peer_spawner.name = "PeerSpawner"
	add_child(_peer_spawner)
	_peer_spawner.spawn_path = _peers_root.get_path()
	_peer_spawner.spawn_function = Callable(self, "_spawn_peer_body")

	net.call("rearm_handshake", "antechamber")
	if net.is_host() and not net.party_ready.is_connected(_spawn_all_peer_bodies):
		net.party_ready.connect(_spawn_all_peer_bodies)
	net.call("notify_arena_ready", "antechamber")


func _spawn_all_peer_bodies(tag: String = "antechamber") -> void:
	if tag != "antechamber":
		return
	var net: Node = get_node_or_null("/root/Net")
	if net == null or not net.is_host() or _peer_spawner == null:
		return
	var i: int = 1
	for pid in net.peers():
		# ⚠ SKIP EVERY PEER THAT ALREADY HAS A BODY IN THIS ROOM — which, for the
		# local player, is always. `Main.tscn` parks one Player in the scene; spawning
		# a second for the same person puts you inside your own twin.
		if int(pid) == int(net.my_id()):
			continue
		var x: float = PLAYER_SPAWN.x - PARTY_SPAWN_GAP * float(i)
		_peer_spawner.spawn({"peer": int(pid), "cls": int(net.class_of(pid)), "x": x, "y": PLAYER_SPAWN.y})
		i += 1


## Runs on EVERY peer with identical data, so authority assignment is deterministic.
## Props are set BEFORE the spawner adds the node, exactly as `Arena._spawn_hero_net`
## does — a property written after `add_child` has already missed `_ready`.
func _spawn_peer_body(data: Dictionary) -> Node:
	var p: Node = load("res://scenes/Player.tscn").instantiate()
	p.name = "Peer_%d" % int(data["peer"])
	(p as Node2D).position = Vector2(float(data["x"]), float(data["y"]))
	p.set_multiplayer_authority(int(data["peer"]))
	# ⚠ OUT OF THE "player" GROUP. `_place_player`, every station's proximity check
	# and the town's overlay freeze all resolve the local player through that group —
	# `get_first_node_in_group("player")` would start returning whichever body was
	# added most recently, so your friend walking past the lectern would open YOUR
	# armoury. The group is local identity, not "is a person".
	p.remove_from_group("player")
	p.add_to_group("town_peer")
	if p.has_method("set_class_tint"):
		p.call("set_class_tint", ClassInfo.color_for(int(data["cls"])))
	return p


## ══ THE BODY YOU DRIVE IN THE TOWN IS A HERO ════════════════════════════════
## Maker: "you should be able to cast spells and stuff within the lobby."
##
## It used to be `Player.tscn` — a walker with move, jump, dash and an interact key
## and no combat verbs at all, which is why casting needed a whole second scene to
## teleport out to. A `Hero` is the same body the tower runs, so the lobby gets every
## spell, the ult, blink, nova, parry and melee for free, and — the part that matters
## more — they behave IDENTICALLY here and there, because they are not a second
## implementation.
##
## ⚠ IT JOINS THE "player" GROUP, WHICH IT IS NOT NORMALLY IN. Every station's
## proximity check, the tower door, the peer-body guard and this function all resolve
## the local body through `get_first_node_in_group("player")`. `Hero.tscn` ships in
## group "hero" only, so without this line the town would build correctly and nothing
## in it would react to you.
##
## ⚠ AND ITS FACTION IS SET, which is not cosmetic. A `Hero` defaults to hostile
## toward "enemy", a group with nothing in it here — its auto-target reads would point
## at an empty set and the dummy yard would be unhittable. Player and dummies are put
## on teams that are hostile to each other and to nothing else.
func _spawn_hero_body() -> Node2D:
	var packed: PackedScene = load(HERO_SCENE)
	if packed == null:
		return null
	var hero: Node = packed.instantiate()
	add_child(hero)
	(hero as Node2D).global_position = PLAYER_SPAWN
	hero.add_to_group("player")
	# ⚠ IT STAYS OFF COLLISION LAYER 1, AND THAT COST A MEASUREMENT TO LEARN. The pads
	# went silent when the town body became a Hero — `Player.tscn` is on layer 1,
	# `Hero.tscn` is on layer 2, and every proximity ring in this room is an `Area2D`
	# with the default mask of 1, so they all went blind. Putting the hero on layer 1
	# fixes the prompts and breaks something worse: layer 1 is `CharacterRig.GROUND_MASK`,
	# so every rig's downward floor probe — including the hero's own — starts finding
	# the HERO instead of the floor. `probe_town_feet` caught it immediately: the ground
	# line jumped from 452 to 433.93, which is exactly the top of the hero's own box.
	# The rings are what were too narrow, so the rings are what widened.
	hero.call("set_faction", &"town_player", &"town_dummy")
	hero.set("facing", Vector2.LEFT)
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and hero.has_method("configure_class"):
		hero.call("configure_class", int(gs.get("selected_class")))
	return hero as Node2D


func _place_player() -> void:
	# `Main.tscn` no longer parks a body — the town mints its own, because the body it
	# wants is a combat one and a scene file cannot set a faction or a group at spawn.
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		player = _spawn_hero_body()
	if player == null or not player is Node2D:
		return
	(player as Node2D).global_position = PLAYER_SPAWN
	for c: Node in player.get_children():
		if c is Camera2D:
			var cam := c as Camera2D
			# ⚠ 0 -> `CAM_LIMIT_LEFT`. See the ⚠ on `BOUND_LEFT`: the wall and this
			# clamp are one number in two places, and at 0 the last 76 px of walkable
			# floor were unframed.
			cam.limit_left = int(CAM_LIMIT_LEFT)
			cam.limit_top = -420   # the tower shaft rises ~300 px above its own arch
			cam.limit_right = int(TOWN_WIDTH)
			# ⚠ 60 -> 18, AND IT IS THE SKY THAT PAYS FOR IT. `limit_bottom` is what the
			# camera CLAMPS against, and at this zoom the clamp — not the offset — was
			# deciding the framing: 0.72 zoom on a 360-line viewport shows 500 world px,
			# so the lowest legal centre was `limit_bottom - 250`. At 512 that pinned the
			# centre at 262 and the visible band at y 12..512, i.e. SIXTY PIXELS OF
			# OPAQUE DIRT below the ground line and only 120 px of sky above the
			# treeline. The room's whole backdrop was competing for a twelfth of the
			# frame. 18 spends that dirt on sky instead, and nothing is lost: there is
			# nothing under the ground to look at.
			cam.limit_bottom = int(GROUND_Y + 18.0)
			# ⚠ 1.2 WAS TOO CLOSE. Maker: "zoom out, we are too close to the figure right
			# now". At 1.2 the 640-wide base view showed 533 px of a 1180 px street, so
			# the room was a corridor you read one object at a time; 0.85 shows 753 and
			# the pad row, the sign and the tower can be in frame together.
			# ...and again, 0.85 -> 0.72: "zoom out a little more generally speaking".
			# 0.72 shows 889 px of the 1180 px street, so the pad row, the sign, the
			# campfire and the tower are all in one frame from the spawn point.
			cam.zoom = Vector2(0.72, 0.72)
			# ⚠ -54 -> -96, WHICH ONLY DOES ANYTHING NOW THAT `limit_bottom` MOVED. The
			# offset was being eaten by the clamp above (it asked for a centre at 398 and
			# got 262), so raising it alone would have changed nothing at all — the two
			# numbers have to move together. With the clamp at 470-250=220 the requested
			# 356 still clamps, but the frame is now y -30..470: the player stands in the
			# lower third looking up at the tower, which is the shot this room is for.
			cam.offset = Vector2(0.0, -96.0)


## The townspeople, instanced here rather than parked in `Main.tscn` so the town's
## cast is one editable list (`TOWNSFOLK`) instead of a scene diff.
func _spawn_townsfolk() -> void:
	for entry: Dictionary in TOWNSFOLK:
		var path: String = String(entry.get("res", ""))
		if not ResourceLoader.exists(path):
			continue
		var npc: Node2D = NPC_SCENE.instantiate()
		npc.set("data", load(path))
		add_child(npc)
		npc.global_position = Vector2(float(entry.get("x", 0.0)), GROUND_Y)
		if npc.has_method("set_hub_patrol"):
			npc.call("set_hub_patrol", float(entry.get("x", 0.0)), float(entry.get("range", 40.0)))


# ----------------------------------------------------------------- the stations
func _spawn_tower_entrance() -> void:
	var door: StaticBody2D = TOWER_DOOR_SCRIPT.new()
	add_child(door)
	door.global_position = Vector2(TOWER_X, GROUND_Y)


## THE RACK and THE CLASS PAD. Both are `ArmoryStation.gd` pointed at a different
## screen — see the header there. The rack is on the GROUND now: it used to sit on
## the loft behind a jump, and behind `if false:`, so in practice the whole armory
## (3 slots x 19 pieces, with live effect bags) had never been reachable in play.
##
## ⚠ TWO PADS, NOT FOUR. See the `PAD_FIRST_X` block for the maker's ruling and for
## why the Archivist in particular had to go rather than merely move.
func _spawn_stations() -> void:
	# ⚠ THE CLASS ALTAR IS A STATION NOW, not its own script. `ClassAltar.gd` was a
	# fourth hand-written copy of walk-up-and-press-E with its own hint, its own
	# proximity ring and its own overlay guard — and the maker's ruling was that ALL
	# the stations become pads, so keeping a separate one meant maintaining two
	# answers to the same question.
	var altar: StaticBody2D = STATION_SCRIPT.new()
	altar.set("kind", "class")
	add_child(altar)
	altar.global_position = Vector2(CLASS_X, GROUND_Y)

	var rack: StaticBody2D = STATION_SCRIPT.new()
	rack.set("kind", "armory")
	add_child(rack)
	rack.global_position = Vector2(ARMORY_X, GROUND_Y)

	# ⚠ THE PARTY STONE ONLY EXISTS IN A PARTY. A station that says "nobody here" to
	# a solo player is a dead object teaching them the room has broken parts — and
	# this room already had to answer the maker asking "what do I do there".
	if _session_is_party():
		var stone: StaticBody2D = STATION_SCRIPT.new()
		stone.set("kind", "party")
		add_child(stone)
		stone.global_position = Vector2(PARTY_X, GROUND_Y)


## THE DUMMY YARD. Three immortal hero bodies at the far end from the door, facing
## the room, standing still.
##
## ⚠ PHYSICS OFF, AND IT IS NOT AN OPTIMISATION. A `Hero` with no controller falls
## through to the real `Input` singleton in `Hero._pressed` — so a dummy with physics
## running mirrors every button the player presses and the yard walks at you in
## lockstep. `set_physics_process(false)` is what makes it stand there. Same trap,
## same fix, as `VersusArena._rebuild_dummies`, and it is worth knowing that the
## symptom is "the dummies are copying me", not "the dummies are broken".
func _spawn_dummy_yard() -> void:
	var hero_scene: PackedScene = load(HERO_SCENE)
	if hero_scene == null:
		return
	for i: int in DUMMY_COUNT:
		var d: Node = hero_scene.instantiate()
		add_child(d)
		# ⚠ NOT AT `GROUND_Y` — THAT IS THE FLOOR SURFACE, NOT WHERE A BODY RESTS ON IT.
		# A `Hero`'s origin is the CENTRE of its collider, so parking one at the surface
		# buries the lower half; with physics off nothing ever resolves it, and the
		# maker's report was exactly "the dummies are stuck in the ground". Measured at
		# 15.5 px of sink by `tools/probe_town_feet.gd`. Derived from the collider so it
		# cannot drift if the box is ever resized.
		(d as Node2D).global_position = Vector2(
			DUMMY_FIRST_X + DUMMY_STEP * float(i), GROUND_Y - _body_half(d))
		d.set("max_hp", DUMMY_HP)
		d.set("hp", DUMMY_HP)
		# On a team the player is hostile to, hostile to nobody: hittable, never hits
		# back. The player's own faction is set to match in `_place_player`.
		d.call("set_faction", &"town_dummy", &"nobody")
		d.set("facing", Vector2.RIGHT)
		d.add_to_group(&"town_dummy")
		# ⚠ A CONTROLLER THAT PRESSES NOTHING, RATHER THAN PHYSICS TURNED OFF. Maker:
		# "make all the other stickmen in the hub the same as mine in terms of ragdoll
		# physics." A controller-less `Hero` falls through to the GLOBAL `Input`
		# singleton, so the yard used to walk, jump and cast in lockstep with the
		# player; the fix for that was `set_physics_process(false)`, which also took
		# away gravity, knockback, flinch, landing and the ragdoll — a dummy became a
		# photograph. `IdleController` answers "no" to the six polling methods instead,
		# so the body runs its whole normal physics and simply never chooses anything.
		d.set("controller", IdleController.new())
		var rig: Node = d.get_node_or_null(^"Rig")
		if rig != null:
			# STRAW, not a class colour. A dummy tinted like a hero reads as a person —
			# and in a co-op lobby, as your teammate. It has to look like a target.
			rig.call("set_tint", DUMMY_COLOR)
		for c: Node in d.get_children():
			# Its camera would fight the player's for the viewport — `Hero.tscn` carries
			# one and only disables it in a networked session.
			if c is Camera2D:
				(c as Camera2D).enabled = false
			# ⚠ AND ITS HEALTH BAR GOES. A full bar over something that cannot lose
			# health is a readout with one possible value, and three of them across the
			# yard is the "random UI pieces we don't need" the maker keeps cutting. The
			# damage NUMBERS still fly, which is the feedback a practice target is for.
			if c is CharacterBars:
				(c as CanvasItem).visible = false


## Half-height of a body's own rectangle collider — how far its ORIGIN sits above the
## floor when it is resting on one. Zero for a body with no box, which then simply
## parks at the surface as before.
func _body_half(body: Node) -> float:
	for c: Node in body.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			return ((c as CollisionShape2D).shape as RectangleShape2D).size.y * 0.5
	return 0.0


## Is this a co-op visit? Reads `GameState.session_kind`, which the title screen
## sets before it sends you here — so the room knows what kind of visit this is
## without asking the network, which may not have connected yet.
func _session_is_party() -> bool:
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs == null:
		return false
	return int(gs.get("session_kind")) != 0


## ══ THE CLASS PAD'S SCREEN — CLASS **AND** SPELLS, MERGED ═══════════════════
## Maker: *"I only want one for class within which I can edit spells"*.
##
## The Outfitter IS that screen. It already answered "which of my class's five roles do
## I carry"; it now carries a full-width button along its top edge reading your class
## name, which opens `ClassSelect` on top of it and re-aims this screen at whatever you
## pick (`Outfitter.show_class_picker` / `ClassSelect.class_picked`).
##
## ⚠ WHY THIS SHAPE AND NOT THE OTHER TWO. The obvious alternative was to CHAIN — open
## `ClassSelect` first, and open the Outfitter when a card is tapped. It is wrong on the
## one constraint that decides everything in this room (D-011: virtual joystick and a
## tap, nothing else): a player who only wants to swap a spell would have to re-pick the
## class they are already in to get past the first screen, and a player who taps away to
## dismiss the grid gets nothing at all. The other alternative — one panel holding a 3x3
## class grid AND the role list — does not fit: the grid alone is ~390x190 and the base
## viewport is 640x360, so the role list would have to scroll away and the hand would
## stop reading as three. A screen with a header button is both, in the order you use
## them, at one tap each.
##
## A `Control`, so it needs a `CanvasLayer` of its own to sit above a `Node2D` world;
## grouped `town_overlay` so the player and every station freeze underneath it without
## any of them knowing what it is.
##
## ⚠ THE LAYER IS 80 AND IT USED TO BE 95, WHICH WAS A MEASURED BUG. `ClassSelect` and
## `Loadout` are both autoloads that draw on their OWN `CanvasLayer` at layer **90**. At
## 95 this layer sat ON TOP of both of them — so the Outfitter's existing "⚒ Armory"
## button opened the armory *behind* this screen's 0.93-opaque dimmer and the player saw
## nothing happen, and the new class button would have done exactly the same. 80 is above
## the town HUD (40) and the touch pad (70) and below the two autoload panels, which is
## the only ordering in which every route out of this screen is visible.
const OVERLAY_LAYER: int = 80


func open_outfitter() -> void:
	if _outfitter != null and is_instance_valid(_outfitter):
		return
	if _outfitter_layer == null:
		_outfitter_layer = CanvasLayer.new()
		_outfitter_layer.layer = OVERLAY_LAYER
		add_child(_outfitter_layer)
	_outfitter = Outfitter.new()
	# ⚠ SET BEFORE `add_child`, AND THAT IS NOT A STYLE CHOICE. `Outfitter._ready` runs
	# the moment the node enters the tree and `_build()` is what decides whether the class
	# button exists at all — a property written afterwards has already missed it. Same
	# rule, same reason, as `World._spawn_peer_body`.
	#
	# ⚠ AND IT IS A FLAG RATHER THAN ALWAYS-ON. The Lobby (the title screen) opens the
	# same `Outfitter` against its OWN `_selected_class`, which is not `GameState`'s; a
	# class button there would write the global and leave the two disagreeing about which
	# class the screen is showing. The town is the one place that owns the global, so the
	# town is the one place that gets the button.
	_outfitter.set("show_class_picker", true)
	_outfitter.add_to_group("town_overlay")
	_outfitter_layer.add_child(_outfitter)
	var gs: Node = get_node_or_null("/root/GameState")
	_outfitter.call("set_class", int(gs.get("selected_class")) if gs != null else 0)
	if _outfitter.has_signal(&"closed"):
		_outfitter.connect(&"closed", _on_outfitter_closed)


## ⚠ THERE IS NO `open_spell_tree()` ANY MORE, AND ITS ABSENCE IS DELIBERATE. It opened
## `SpellTreeScreen` for the Archivist pad, which is deleted — see the `PAD_FIRST_X`
## block for why. The screen file is KEPT (the spell trees are designed-but-unbuilt work:
## `docs/superpowers/specs/2026-08-04-spell-trees-and-progression-design.md`), and its own
## header now says so and lists what has to become true before a pad points at it again.
## A public opener that nothing calls would read as "the town can still do this", which is
## the kind of half-wired path the next reader has to disprove by grep.
func _on_outfitter_closed() -> void:
	if _outfitter != null and is_instance_valid(_outfitter):
		# Out of the group in the same frame it closes, so the player is not frozen
		# for the frame between `closed` and `queue_free` landing.
		_outfitter.remove_from_group("town_overlay")
		_outfitter.queue_free()
	_outfitter = null


# ---------------------------------------------------------------------- the HUD
## ONE line. Who you are. Everything else the town has to say, the town says with
## objects — see `_build_signboard`.
func _spawn_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)

	# ⚠ THE SPELL SLOTS BELONG HERE NOW. Maker: "the spell slots and stuff should also
	# be visible in the hub." They were an arena-only HUD, which was right while the
	# town was a walker with no kit; you cast in the lobby now, so a room with a dummy
	# yard and no hotbar is a room that will not tell you what your four buttons are.
	# `AbilityBar` polls `get_first_node_in_group("hero")` and draws nothing when there
	# is none, so it costs exactly nothing in a scene without a fighter.
	layer.add_child(AbilityBar.new())

	var who := Label.new()
	who.add_to_group("class_hud_label")
	who.position = Vector2(14, 10)
	who.add_theme_font_size_override("font_size", 16)
	who.add_theme_color_override("font_color", CHALK)
	who.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	who.add_theme_constant_override("outline_size", 4)
	layer.add_child(who)

	# ⚠ THE GUIDE LINE IS GONE, ON PURPOSE. It read "walk left: gear · spells · class ·
	# the tower is right here · Esc: title" — thirteen words of chrome describing a room
	# the player is standing in. `_build_signboard` says the same thing with two arrows,
	# in the world, where a sign belongs. The maker's standing rule: "this game has too
	# much text and too many random UI pieces — every screen should be cut, not added
	# to." One line of class name is what is left, and it is the one fact the room
	# itself cannot show you.


## A MINIMAL TOUCH PAD, and deliberately not `TouchControls`. That layer is the
## combat one: twin sticks, a cast button and a spell row, all of which mean
## nothing here and one of which (`cast`) would be actively wrong. The town needs
## exactly three verbs, so it gets three pads that press the same NAMED ACTIONS a
## keyboard does — no raw keycodes anywhere, per the mobile-input rule.
##
## Hidden unless the device actually has a touchscreen, so desktop is untouched.
func _spawn_touch_pad() -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	# Walk: two wide pads in the bottom-left, thumb-sized.
	_pad(layer, "move_left", "◂", Vector2(14.0, -14.0 - 46.0), Vector2(52.0, 46.0), false)
	_pad(layer, "move_right", "▸", Vector2(72.0, -14.0 - 46.0), Vector2(52.0, 46.0), false)
	# Jump and interact under the other thumb. INTERACT is the biggest thing on the
	# screen because it is the only one that does anything in a town.
	_pad(layer, "jump", "▲", Vector2(-14.0 - 52.0, -14.0 - 46.0), Vector2(52.0, 46.0), true)
	_pad(layer, "talk", "E", Vector2(-14.0 - 52.0 - 74.0, -14.0 - 52.0), Vector2(68.0, 52.0), true)
	# BACK. A touch player has no Esc key, so without this the only exit from the
	# town on the target platform is to start a run.
	_pad(layer, "ui_cancel", "✕", Vector2(-14.0 - 38.0, -360.0), Vector2(38.0, 32.0), true)


## One pad, pressing one named action. `anchor_right` places it from the right edge
## when `from_right`, so the layout survives any window the game is opened at.
func _pad(layer: CanvasLayer, action: String, glyph: String, offset: Vector2,
		size: Vector2, from_right: bool) -> void:
	var b := Button.new()
	b.text = glyph
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(maxf(size.x, MIN_TAP), maxf(size.y, MIN_TAP))
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	if from_right:
		b.anchor_left = 1.0
		b.anchor_right = 1.0
	b.offset_left = offset.x
	b.offset_right = offset.x + size.x
	b.offset_top = offset.y
	b.offset_bottom = offset.y + size.y
	b.add_theme_font_size_override("font_size", 20)
	b.modulate = Color(1.0, 1.0, 1.0, 0.62)
	# Press/release rather than a one-shot `pressed`, so holding ◂ walks.
	b.button_down.connect(func() -> void: Input.action_press(action, 1.0))
	b.button_up.connect(func() -> void: Input.action_release(action))
	# A pad that is still held when the town unloads would leave the action stuck
	# down for the whole run underneath it.
	b.tree_exiting.connect(func() -> void: Input.action_release(action))
	layer.add_child(b)


## THE WAY OUT THAT ISN'T THE TOWER. `PauseMenu` is spawned by the arena, not by
## this scene, so without this the only exit from the town was to start a run —
## a front door you can only leave by going upstairs is a trap, not a front door.
## Esc / Back goes to the title, and only when no panel is up (a panel eats its own
## ui_cancel first, so this never steals a "close this screen").
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel != null and sel.has_method("is_open") and sel.is_open():
		return
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("is_open") and lo.is_open():
		return
	for o: Node in get_tree().get_nodes_in_group("town_overlay"):
		if o is CanvasItem and (o as CanvasItem).visible:
			return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("go_to_title"):
		get_viewport().set_input_as_handled()
		gs.call("go_to_title")


func _reflect_selected_class() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var idx: int = int(gs.get("selected_class")) if gs != null else 0
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_class_tint"):
		player.call("set_class_tint", ClassInfo.color_for(idx))
	for label: Node in get_tree().get_nodes_in_group("class_hud_label"):
		if label is Label:
			(label as Label).text = "%s" % ClassInfo.name_for(idx)
