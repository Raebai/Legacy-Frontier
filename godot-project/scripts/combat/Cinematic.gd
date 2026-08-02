class_name Cinematic
extends RefCounted
## CINEMATIC MODE — the one switch that takes the DIAGNOSTIC chrome off the screen so
## a frame can be posted.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS. The first bot-fight clip anybody tried to post had the clip
## engine's own tuning readout (`heat 0.73 [ROLLING]`) burned into the bottom-left of
## every frame and the touch PAUSE button burned into the top-right. Neither is a bug —
## the heat number is the ONLY instrument that says whether the director opened the
## shot too late, and the pause button is the phone's only way into the menu — but both
## are instruments, and an instrument in a marketing frame reads as an unfinished game.
##
## ⚠ SO NOTHING HERE IS DELETED, IT IS GATED. Deleting the readout would cost the next
## person tuning `HOT_THRESHOLD` the only number that tells them anything. The flag is
## OFF by default, which means:
##   * normal play, and all ~69 capture tools in `tools/`, are BYTE-IDENTICAL to before.
##     `touch_capture` still photographs the touch pad, `DirectorCapture` still
##     photographs the director. That default is load-bearing — several tools exist
##     precisely to photograph the thing this mode hides.
##   * `tools/directed_clip_capture.gd` turns it ON before it builds the scene, so
##     `python-tools/make_clip.py` needs no new argument and cannot forget.
##   * the DIRECTOR's VIEW tab (F1) toggles it live, so the maker can take a clean
##     screenshot mid-play without going near the clip tool.
##
## ---------------------------------------------------------------------------
## HOW IT WORKS — a GROUP, not a list of node paths.
##
## `BotMatch._hide_duplicate_chrome()` already established the idiom of a host reaching
## into someone else's tree and hiding what it does not want. That works when the host
## knows the whole tree. Cinematic mode does not: it has to hold across the bot match,
## the tower, free play and whatever the Director rebuilds under it. So the direction is
## INVERTED — each diagnostic node marks ITSELF once, at build time, and this class
## sweeps the group. Adding a new debug overlay to this project is therefore one
## `Cinematic.mark(self)` line in its `_ready`, and it is covered forever.
##
## ⚠ IT ONLY EVER HIDES, AND IT REMEMBERS WHAT IT HID. Several marked nodes are already
## conditionally invisible for their own reasons (`PerfOverlay` starts hidden;
## `VersusArena._intent_label` follows `duel_show_intent`; `TouchControls` hides itself
## on a desktop). A naive `visible = not enabled` would SHOW all of those the moment
## cinematic mode was turned back off — i.e. leaving the mode would litter the screen
## with debug overlays nobody asked for. So the pre-cinematic state is stashed in meta
## on the way in and restored verbatim on the way out.
##
## ⚠ NO AUTOLOADS, NO SCENE DEPENDENCIES, NO `class_name` CHAIN. This file references
## nothing. That is deliberate: `tools/directed_clip_capture.gd` runs under `--script`,
## where autoloads are NOT registered and naming a class that transitively touches one
## is a parse-time "Identifier not found" that silently produces a capture of an empty
## room (see that file's own header). Reaching this flag by `load()` + `set()` — the
## same way that tool already sets `BotMatch`'s statics — is safe from anywhere.

## The group every diagnostic node marks itself into.
const HIDE_GROUP: StringName = &"cinematic_chrome"
## Where a node's pre-cinematic visibility is stashed. Meta rather than a static
## dictionary keyed by instance id, which would leak a row for every node that ever
## existed — the same reasoning `BotMatch._off_taunt_cooldown` documents.
const WAS_VISIBLE_META: StringName = &"cinematic_was_visible"

## ⚠ OFF BY DEFAULT. See the header: every existing capture tool depends on this.
static var enabled: bool = false


## Register a node as diagnostic chrome, and apply the current mode to it immediately
## so a node built WHILE cinematic mode is on is born hidden rather than flashing for
## a frame.
##
## Typed `Node` and not `CanvasItem` on purpose: `CanvasLayer` is not a `CanvasItem`
## but does carry `visible`, and two of the things that need hiding (the pause button's
## layer, the perf overlay) are CanvasLayers precisely because they must survive a
## hidden Control parent.
static func mark(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if not (n is CanvasItem or n is CanvasLayer):
		return
	if not n.is_in_group(HIDE_GROUP):
		n.add_to_group(HIDE_GROUP)
	_apply_one(n)


## Turn the mode on or off and sweep everything already marked.
static func set_enabled(tree: SceneTree, on: bool) -> void:
	enabled = on
	refresh(tree)


## Re-apply the current mode to every marked node. Cheap enough to call after a scene
## rebuild; a null tree is a no-op so a headless caller with no tree can still flip the
## flag before anything is built.
static func refresh(tree: SceneTree) -> int:
	if tree == null:
		return 0
	var touched: int = 0
	for n: Node in tree.get_nodes_in_group(HIDE_GROUP):
		if is_instance_valid(n):
			_apply_one(n)
			touched += 1
	return touched


## Should a host that is about to SHOW a piece of chrome go ahead? Used by the handful
## of sites that re-assert visibility on their own schedule (`PauseMenu.close()` puts
## the pause button back), where the group sweep alone would be undone a frame later.
static func shows_chrome() -> bool:
	return not enabled


static func _apply_one(n: Node) -> void:
	if enabled:
		if not n.has_meta(WAS_VISIBLE_META):
			n.set_meta(WAS_VISIBLE_META, bool(n.get("visible")))
		n.set("visible", false)
	elif n.has_meta(WAS_VISIBLE_META):
		n.set("visible", bool(n.get_meta(WAS_VISIBLE_META)))
		n.remove_meta(WAS_VISIBLE_META)
