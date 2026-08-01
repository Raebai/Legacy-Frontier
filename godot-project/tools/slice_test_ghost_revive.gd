# Run: godot --headless --path godot-project --script tools/slice_test_ghost_revive.gd
#
# GHOST FORM + REVIVE — the 2026-08-01 death rule:
#   "dying cost is a life in ghost form until your teammate revives you;
#    if you all die then the game is over"
#
# WHAT THIS SUITE CAN AND CANNOT JUDGE. It pins STATE AND WIRING — that a ghost
# leaves the groups that make it a target, that it stops being a collision target,
# that `exit` puts back exactly what `enter` took, that the touch pad presses the same
# action the keyboard does, that the two surfaced policy dials are wired to the code
# that reads them, and that the old fall rule stays deleted. It CANNOT judge whether
# the ghost reads at 640x360, whether 92 px is the right revive range, or whether two
# seconds of standing still is brave or annoying. `tools/ghost_revive_capture.gd`
# renders it so it can at least be LOOKED at, and only a phone settles the rest.
#
# ⚠ ASSERTED AGAINST A REAL `Hero.tscn`, NOT A STUB. A hand-written fixture that
# declares members the shipped class does not is a fixture more generous than
# reality — that is exactly how `SpellHandoff` shipped asking heroes for `bot_driven`
# and `_bot` (members existing nowhere), had every call silently abort on
# `bool(null)`, and never once worked in the real game while its suite stayed green.
# The hero is instantiated but NEVER added to the tree: `Hero._ready` reaches the
# `Rank` autoload, and autoloads do not exist under `--script`.
#
# ⚠ THE IDIOM. Failures accumulate on the MEMBER `_fails` and every test records a
# COMPLETION SENTINEL as its last line, so a test that aborts part-way fails the suite
# BY ABSENCE. Never `_fails += _test_x()`.
extends SceneTree

const TESTS: Array[String] = [
	"the_two_surfaced_decisions_are_real_knobs",
	"revive_hp_is_never_full_and_never_zero",
	"a_ghost_leaves_the_target_groups",
	"a_ghost_keeps_the_hero_group",
	"exit_restores_exactly_what_enter_took",
	"enter_is_idempotent",
	"ghost_form_is_derivable_from_the_node",
	"the_mortal_literal_still_matches_spellcaster",
	"hero_declares_every_member_this_feature_reaches_by_name",
	"revive_pad_drives_the_keyboard_action",
	"revive_pad_releases_the_action_when_the_offer_ends",
	"revive_and_handoff_pads_cannot_overlap",
	"net_carries_the_revive_and_wipe_wires",
]

const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"

## Every member/method this feature reaches BY STRING from another file. A rename is
## otherwise silent — `get()` on an absent property returns null, and casting a null
## ABORTS the enclosing function and hands back the type's zero.
const HERO_MEMBERS: Array[String] = ["downed", "controller", "faction_group", "collision_layer"]
const HERO_METHODS: Array[String] = ["is_downed", "is_ghost", "revive", "awaiting_second_wind"]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_the_two_surfaced_decisions_are_real_knobs()
	_test_revive_hp_is_never_full_and_never_zero()
	_test_a_ghost_leaves_the_target_groups()
	_test_a_ghost_keeps_the_hero_group()
	_test_exit_restores_exactly_what_enter_took()
	_test_enter_is_idempotent()
	_test_ghost_form_is_derivable_from_the_node()
	_test_the_mortal_literal_still_matches_spellcaster()
	_test_hero_declares_every_member_this_feature_reaches_by_name()
	# ⚠ ORDER IS LOAD-BEARING. `Input.is_action_just_pressed` stays true for the WHOLE
	# frame in which it was pressed, and this whole suite runs inside one frame — so
	# every test that touches `talk` goes last and clears it on the way out.
	_test_revive_pad_drives_the_keyboard_action()
	_test_revive_pad_releases_the_action_when_the_offer_ends()
	_test_revive_and_handoff_pads_cannot_overlap()
	_test_net_carries_the_revive_and_wipe_wires()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Ghost/revive tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Ghost/revive tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ helpers
## A REAL hero, off-tree. `add_to_group` / `remove_from_group` / `add_child` all work
## outside the tree; `_ready` (and the autoloads it reaches) never runs.
func _real_hero() -> Node:
	var scene: PackedScene = load(HERO_SCENE) as PackedScene
	if scene == null:
		return null
	return scene.instantiate()


func _clear_talk() -> void:
	if Input.is_action_pressed(Revive.REVIVE_ACTION):
		Input.action_release(Revive.REVIVE_ACTION)


func _revive_node(force_pad: bool) -> Revive:
	var r := Revive.new()
	r.force_pad = force_pad
	root.add_child(r)
	return r


## Immediate, not `queue_free`: everything here runs inside one `_process`, and a
## queued free does not land until the frame ends, so a "cleaned up" fixture is still
## in its groups for the next test.
func _kill(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	for g: StringName in n.get_groups():
		n.remove_from_group(g)
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.free()


func _pad_of(r: Revive) -> Revive.RevivePad:
	for layer: Node in r.get_children():
		for c: Node in layer.get_children():
			if c is Revive.RevivePad:
				return c as Revive.RevivePad
	return null


# ------------------------------------------------------------------- tests
## THE TWO DECISIONS THE MAKER ASKED TO HAVE SURFACED. Pinned to their SHIPPED values
## and to the code that reads them, so flipping one is a deliberate two-file change
## rather than something that drifts.
func _test_the_two_surfaced_decisions_are_real_knobs() -> void:
	_expect(DeathRules.SOLO_SELF_REVIVE_CHARGES == 0,
		"DECISION 1 ships at 0 — solo death ends the run")
	_expect(DeathRules.RESET_CLIMB_ON_GAME_OVER == false,
		"DECISION 2 ships at false — a game over KEEPS the climb")
	# The knobs are not decoration: something has to read them.
	var hero: Node = _real_hero()
	if hero == null:
		_expect(false, "Hero.tscn did not load")
		_completes("the_two_surfaced_decisions_are_real_knobs")
		return
	var src: String = (hero.get_script() as GDScript).source_code
	_expect(src.contains("DeathRules.SOLO_SELF_REVIVE_CHARGES"),
		"Hero reads SOLO_SELF_REVIVE_CHARGES (the charge knob is wired, not aspirational)")
	_expect(src.contains("DeathRules.SECOND_WIND_DELAY"),
		"…and schedules a SECOND WIND from it")
	hero.free()
	_completes("the_two_surfaced_decisions_are_real_knobs")


## A revive that lands you at full hp makes dying a free heal; one that lands you at
## zero is not a revive. Both ends are pinned.
func _test_revive_hp_is_never_full_and_never_zero() -> void:
	_expect(DeathRules.REVIVE_HP_FRACTION > 0.0 and DeathRules.REVIVE_HP_FRACTION < 1.0,
		"REVIVE_HP_FRACTION is a real fraction (got %f)" % DeathRules.REVIVE_HP_FRACTION)
	_expect(int(DeathRules.revive_hp(100)) == int(round(100.0 * DeathRules.REVIVE_HP_FRACTION)),
		"revive_hp scales off max hp")
	_expect(int(DeathRules.revive_hp(1)) >= 1, "revive_hp never returns 0 (1 hp hero)")
	_expect(int(DeathRules.revive_hp(0)) >= 1, "…nor on a degenerate 0-max hero")
	_completes("revive_hp_is_never_full_and_never_zero")


## THE CORE OF GHOST FORM. `Hero.take_damage` already returns early while downed, so
## this is not about immunity — it is about being UNTARGETABLE. A ghost still in
## `mortal` soaks a friendly Meteor's radius scan, eats its hit-stop and its damage
## number, and reads on screen as a body being hit.
func _test_a_ghost_leaves_the_target_groups() -> void:
	var hero: Node = _real_hero()
	if hero == null:
		_expect(false, "Hero.tscn did not load")
		_completes("a_ghost_leaves_the_target_groups")
		return
	hero.add_to_group(GhostForm.MORTAL_GROUP)
	hero.set(&"faction_group", &"team_a")
	hero.add_to_group(&"team_a")
	var layer_before: int = int(hero.get(&"collision_layer"))
	_expect(layer_before != 0, "a live hero has a collision layer to lose (got %d)" % layer_before)
	GhostForm.enter(hero)
	_expect(not hero.is_in_group(GhostForm.MORTAL_GROUP), "a ghost left `mortal`")
	_expect(not hero.is_in_group(&"team_a"), "a ghost left its faction team")
	_expect(int(hero.get(&"collision_layer")) == 0,
		"a ghost has no collision layer — projectiles and pickup areas pass through")
	_expect(hero.is_in_group(GhostForm.GHOST_GROUP), "…and joined `ghost` so Revive can find it")
	hero.free()
	_completes("a_ghost_leaves_the_target_groups")


## …AND KEEPS `hero`. That group is identity: the camera's fit-all framing, the
## party-wipe verdict and `Net.hero_for_peer` all read it. Dropping it would make a
## ghost invisible to the thing that ends the run — the exact group-drift trap this
## codebase has been bitten by twice ("hero" tower vs "player" hub).
func _test_a_ghost_keeps_the_hero_group() -> void:
	var hero: Node = _real_hero()
	if hero == null:
		_expect(false, "Hero.tscn did not load")
		_completes("a_ghost_keeps_the_hero_group")
		return
	_expect(hero.is_in_group(&"hero"), "Hero.tscn ships in the `hero` group")
	GhostForm.enter(hero)
	_expect(hero.is_in_group(&"hero"),
		"a ghost is STILL in `hero` — the party-wipe verdict has to be able to count it")
	hero.free()
	_completes("a_ghost_keeps_the_hero_group")


## Being revived has to put the body back exactly as it was, including the arrangement
## a SOLO hero has (no faction group at all) versus a co-op one.
func _test_exit_restores_exactly_what_enter_took() -> void:
	# Co-op shape: mortal + a team.
	var coop: Node = _real_hero()
	if coop == null:
		_expect(false, "Hero.tscn did not load")
		_completes("exit_restores_exactly_what_enter_took")
		return
	coop.add_to_group(GhostForm.MORTAL_GROUP)
	coop.set(&"faction_group", &"team_b")
	coop.add_to_group(&"team_b")
	var layer: int = int(coop.get(&"collision_layer"))
	GhostForm.enter(coop)
	GhostForm.exit(coop)
	_expect(coop.is_in_group(GhostForm.MORTAL_GROUP), "revived: back in `mortal`")
	_expect(coop.is_in_group(&"team_b"), "revived: back on its team")
	_expect(int(coop.get(&"collision_layer")) == layer, "revived: collision layer restored")
	_expect(not coop.is_in_group(GhostForm.GHOST_GROUP), "revived: out of `ghost`")
	_expect(coop.get_node_or_null(NodePath(String(GhostForm.NODE_NAME))) == null,
		"revived: the ghost node is gone")
	coop.free()
	# Solo shape: mortal, NO team. `exit` must not invent a faction that never existed.
	var solo: Node = _real_hero()
	solo.add_to_group(GhostForm.MORTAL_GROUP)
	GhostForm.enter(solo)
	GhostForm.exit(solo)
	_expect(solo.is_in_group(GhostForm.MORTAL_GROUP), "solo revived: back in `mortal`")
	_expect(solo.get_groups().size() == 2,
		"solo revived: exactly `hero` + `mortal`, no invented team (got %s)" % [solo.get_groups()])
	solo.free()
	# `exit` on a hero that was never a ghost is a normal answer, not a crash.
	var never: Node = _real_hero()
	GhostForm.exit(never)
	_expect(true, "exit on a never-ghosted hero is safe")
	never.free()
	_completes("exit_restores_exactly_what_enter_took")


## Both the local death path and the replicated-flag path can reach `enter`. A second
## ghost node would double the smudge, double the ring, and — worse — capture an
## already-zeroed collision layer as the thing to restore.
func _test_enter_is_idempotent() -> void:
	var hero: Node = _real_hero()
	if hero == null:
		_expect(false, "Hero.tscn did not load")
		_completes("enter_is_idempotent")
		return
	hero.add_to_group(GhostForm.MORTAL_GROUP)
	var layer: int = int(hero.get(&"collision_layer"))
	var a: GhostForm = GhostForm.enter(hero)
	var b: GhostForm = GhostForm.enter(hero)
	_expect(a == b, "the second enter returns the SAME node")
	var ghost_children: int = 0
	for c: Node in hero.get_children():
		if c is GhostForm:
			ghost_children += 1
	_expect(ghost_children == 1, "exactly one GhostForm child (got %d)" % ghost_children)
	GhostForm.exit(hero)
	_expect(int(hero.get(&"collision_layer")) == layer,
		"…so the restored layer is the LIVE one, not the zeroed one")
	hero.free()
	_completes("enter_is_idempotent")


## `is_ghosted` derives from the node rather than from a flag, so what the code
## believes and what is on screen cannot disagree.
func _test_ghost_form_is_derivable_from_the_node() -> void:
	var hero: Node = _real_hero()
	if hero == null:
		_expect(false, "Hero.tscn did not load")
		_completes("ghost_form_is_derivable_from_the_node")
		return
	_expect(not GhostForm.is_ghosted(hero), "a live hero is not ghosted")
	GhostForm.enter(hero)
	_expect(GhostForm.is_ghosted(hero), "…a downed one is")
	GhostForm.exit(hero)
	_expect(not GhostForm.is_ghosted(hero), "…and a revived one is not again")
	_expect(not GhostForm.is_ghosted(null), "null is a normal answer, not a crash")
	hero.free()
	_completes("ghost_form_is_derivable_from_the_node")


## `GhostForm` duplicates the group name as a LITERAL so it survives `--script` (see
## its header). This is the assertion that keeps the duplicate honest.
func _test_the_mortal_literal_still_matches_spellcaster() -> void:
	_expect(GhostForm.MORTAL_GROUP == SpellCaster.MORTAL_GROUP,
		"GhostForm.MORTAL_GROUP '%s' == SpellCaster.MORTAL_GROUP '%s'"
			% [GhostForm.MORTAL_GROUP, SpellCaster.MORTAL_GROUP])
	_expect(String(Revive.REVIVE_ACTION) == String(SpellHandoff.HANDOFF_ACTION),
		"revive and handoff share the one contextual action — if they ever diverge, "
		+ "the phone needs a second pad")
	_expect(InputMap.has_action(Revive.REVIVE_ACTION),
		"'%s' is a real action" % Revive.REVIVE_ACTION)
	_completes("the_mortal_literal_still_matches_spellcaster")


## THE ASSERTION THAT WOULD HAVE CAUGHT THE BUG THAT KILLED THE SPELL HANDOFF.
## Every one of these is reached BY STRING from `GhostForm`, `Revive`, `Net` or
## `Arena`. A rename is silent everywhere else.
func _test_hero_declares_every_member_this_feature_reaches_by_name() -> void:
	var hero: Node = _real_hero()
	if hero == null:
		_expect(false, "Hero.tscn did not load")
		_completes("hero_declares_every_member_this_feature_reaches_by_name")
		return
	var props: Dictionary = {}
	for p: Dictionary in hero.get_property_list():
		props[String(p.get("name", ""))] = true
	for m: String in HERO_MEMBERS:
		_expect(props.has(m), "Hero still declares `%s` (reached by name)" % m)
	for m: String in HERO_METHODS:
		_expect(hero.has_method(m), "Hero still has `%s()` (reached by name)" % m)
	# `revive` takes the hp fraction. Called with one arg by Revive/Arena and with
	# none by nothing any more — a 0-arg-only signature would abort both call sites.
	var arity_ok: bool = false
	for m: Dictionary in hero.get_method_list():
		if String(m.get("name", "")) == "revive":
			arity_ok = (m.get("args", []) as Array).size() >= 1
	_expect(arity_ok, "Hero.revive(hp_fraction) takes the fraction a real revive needs")
	hero.free()
	_completes("hero_declares_every_member_this_feature_reaches_by_name")


## ON A PHONE THE PAD IS THE ONLY WAY IN. It presses the SAME action the keyboard
## polls — one input path, so a change to when a revive is legal cannot land on
## desktop and miss the phone.
func _test_revive_pad_drives_the_keyboard_action() -> void:
	var r: Revive = _revive_node(true)
	var pad: Revive.RevivePad = _pad_of(r)
	_expect(pad != null, "the revive node builds a pad when forced")
	if pad != null:
		_expect(not pad.visible, "…hidden with no ghost to pick up")
		pad.press()
		_expect(Input.is_action_pressed(Revive.REVIVE_ACTION),
			"pressing the pad holds '%s'" % Revive.REVIVE_ACTION)
		pad.release()
		_expect(not Input.is_action_pressed(Revive.REVIVE_ACTION), "lifting releases it")
	_kill(r)
	_clear_talk()
	_completes("revive_pad_drives_the_keyboard_action")


## THE STUCK-BUTTON CASE. The ghost gets picked up (or drifts away) mid-press: the pad
## vanishes, and if it vanished still holding `talk` that action is held forever —
## every later revive would start the instant it became legal with nobody pressing.
func _test_revive_pad_releases_the_action_when_the_offer_ends() -> void:
	var r: Revive = _revive_node(true)
	var pad: Revive.RevivePad = _pad_of(r)
	if pad == null:
		_expect(false, "no pad to press")
		_kill(r)
		_completes("revive_pad_releases_the_action_when_the_offer_ends")
		return
	pad.visible = true
	pad.press()
	_expect(Input.is_action_pressed(Revive.REVIVE_ACTION), "held mid-press")
	# No ghost anywhere -> `_sync_pad` must hide it AND let go.
	r._sync_pad()
	_expect(not pad.visible, "the offer ended -> the pad goes away")
	_expect(not Input.is_action_pressed(Revive.REVIVE_ACTION),
		"…and it does NOT leave the action held")
	_kill(r)
	_clear_talk()
	_completes("revive_pad_releases_the_action_when_the_offer_ends")


## Both pads live in the centre dead band and both press `talk`. They are close to
## mutually exclusive by construction, but "close to" is not a layout guarantee — so
## the two rectangles are asserted disjoint. A thumb must never be able to hit both.
func _test_revive_and_handoff_pads_cannot_overlap() -> void:
	var revive_top: float = Revive.PAD_LIFT + Revive.PAD_SIZE.y
	var revive_bottom: float = Revive.PAD_LIFT
	var handoff_top: float = TouchControls.HANDOFF_LIFT + TouchControls.HANDOFF_SIZE.y
	var handoff_bottom: float = TouchControls.HANDOFF_LIFT
	# Both are measured UP from the bottom edge, so "revive is above handoff" is
	# revive_bottom >= handoff_top.
	_expect(revive_bottom >= handoff_top,
		"the revive pad sits clear above the handoff pad (revive bottom %.0f vs handoff top %.0f)"
			% [revive_bottom, handoff_top])
	_expect(revive_top > revive_bottom and handoff_top > handoff_bottom, "both pads have height")
	_completes("revive_and_handoff_pads_cannot_overlap")


## THE WIRE. A revive is one authoritative decision replayed on both peers, and a
## party wipe is a host verdict — neither is observable from inside one process (see
## `python-tools/coop_smoketest.sh` for the part that is). What IS checkable here is
## that the wires exist under the names the callers use, and that the old fall wire
## is gone rather than sitting next to the new one.
func _test_net_carries_the_revive_and_wipe_wires() -> void:
	var net: GDScript = load("res://scripts/Net.gd") as GDScript
	if net == null:
		_expect(false, "Net.gd did not load")
		_completes("net_carries_the_revive_and_wipe_wires")
		return
	var n: Node = net.new()
	for m: String in ["request_revive", "_req_revive", "_host_award_revive", "_client_revive",
			"request_party_wipe", "_req_wipe", "_do_host_wipe", "hero_for_peer"]:
		_expect(n.has_method(m), "Net has `%s()`" % m)
	_expect(not n.has_method("request_fall"), "the old fall wire is gone, not shadowed")
	_expect(not n.has_method("_do_host_fall"), "…including its host half")
	var props: Dictionary = {}
	for p: Dictionary in n.get_property_list():
		props[String(p.get("name", ""))] = true
	_expect(props.has("_revives_applied"),
		"Net counts applied revives — the smoke test's only proof the wire delivers")
	n.free()
	_completes("net_carries_the_revive_and_wipe_wires")
