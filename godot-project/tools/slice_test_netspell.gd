# Run: godot --headless --path godot-project --script tools/slice_test_netspell.gd
# CO-OP SPELL REPLICATION — the contract that keeps a rebuilt spell from dealing a
# second copy of its damage, plus the sync set, the ghost group and the status route.
#
# ⚠ WHAT THIS SUITE CANNOT DO, stated up front so nobody reads it as more than it is:
# a single headless process has no second peer, so it cannot prove a packet crosses a
# wire. That is what `python-tools/coop_smoketest.sh` (two real processes, loopback
# ENet, `[NET]` lines) is for, and the two are complementary rather than redundant.
# What THIS suite pins is the half that a two-process test cannot see clearly: the
# INVARIANTS a replicated spell has to satisfy, on a real Hero, in a real tree.
#
# The failure this is aimed at is a quiet one. If a rebuilt spell keeps its normal
# target group, nothing errors, nothing warns, and the only symptom is that co-op
# does 2x damage — which reads as "enemies feel squishy in multiplayer", which reads
# as a balance problem, and is chased for a week in the wrong file.
#
# Idiom (see tools/slice_test_loadout.gd, and never regress it): failures accumulate
# on the MEMBER `_fails`, and every test records a COMPLETION SENTINEL as its last
# line, so a test that aborts on a moved member fails the suite BY ABSENCE.
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"

## Hero members this suite reaches dynamically (Hero.gd declares no class_name, so
## every `hero.net_anim` is a runtime lookup that would abort silently if renamed).
const HERO_MEMBERS: Array[String] = [
	"net_anim", "net_aim", "net_element", "net_flags", "max_hp", "hp",
	"_replaying", "_replay_point", "_status", "hostile_group",
]

## The exact property set a hero streams to every other peer. Named here because the
## bug this guards against is a DELETION: a property quietly dropped from the sync
## config does not error, it just stops arriving, and the symptom (a teammate stuck
## in a run cycle, a health bar reading against the wrong denominator) looks like an
## animation bug rather than a networking one.
const SYNC_PROPS: Array[String] = [
	":position", ":velocity", ":facing", ":hp", ":max_hp", ":net_class",
	":downed", ":net_anim", ":net_aim", ":net_element", ":net_flags",
]

const TESTS: Array[String] = [
	"ghost_group_is_empty", "puppet_scans_ghost", "sync_set_complete",
	"sync_is_rate_limited", "publish_state", "replay_is_inert",
	"spell_lookup_by_id", "bolt_twin_hurts_nobody", "hero_takes_ailments",
	"status_router_local", "boss_phase_seam", "sp_is_unchanged",
	"replay_builds_a_spectacle", "disconnect_frees_the_puppet", "lan_discovery_api",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
## `SpellCaster.friendly_fire` as it was BEFORE this suite touched anything.
##
## ⚠ SNAPSHOT, NOT A HARD-CODED `true`, and the difference is not pedantry. The
## invariant this suite owns is "a replay BORROWS the toggle and puts it back" — the
## toggle's resting value belongs to `SpellCaster`, and asserting it here would make
## this file go red for reasons that have nothing to do with replication. That is not
## hypothetical: a static function in `SpellCaster` naming a class whose script calls
## an autoload fails to compile under `--script` (autoloads are not registered there),
## which leaves every `static var` in the file at its type default and would read as
## "the replay leaked" when nothing of the sort happened.
var _ff_baseline: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_ff_baseline = SpellCaster.friendly_fire
	_test_ghost_group_is_empty()
	_test_puppet_scans_ghost()
	_test_sync_set_complete()
	_test_sync_is_rate_limited()
	_test_publish_state()
	_test_replay_is_inert()
	_test_spell_lookup_by_id()
	_test_bolt_twin_hurts_nobody()
	_test_hero_takes_ailments()
	_test_status_router_local()
	_test_boss_phase_seam()
	_test_sp_is_unchanged()
	_test_replay_builds_a_spectacle()
	_test_disconnect_frees_the_puppet()
	_test_lan_discovery_api()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("NetSpell tests: %d FAILED" % _fails)
		quit(1)
		return true
	print("NetSpell tests: all PASS")
	quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	return hero


func _require_props(obj: Object, names: Array[String], owner_label: String) -> void:
	if obj == null:
		_expect(false, "%s exists (cannot check its members)" % owner_label)
		return
	var present: Dictionary = {}
	for p: Dictionary in obj.get_property_list():
		present[String(p["name"])] = true
	for n: String in names:
		_expect(present.has(n),
			"%s still declares `%s` (moved or renamed — assertions reading it are dead)"
				% [owner_label, n])


# ---------------------------------------------------------------- the tests
## THE WHOLE DISARM MECHANISM IN ONE ASSERTION. Every twin this feature builds is
## pointed at `Net.GHOST_GROUP`, and the only reason that disarms twenty-three
## spectacle scripts at once is that NOBODY IS IN IT. The day something joins that
## group — a stray `add_to_group("none")`, a group name typo'd into existence — every
## replicated spell in the game silently starts dealing a second copy of its damage.
func _test_ghost_group_is_empty() -> void:
	var net: Node = root.get_node_or_null("Net")
	_expect(net != null, "the Net autoload is present")
	if net == null:
		return
	var ghost: StringName = net.get("GHOST_GROUP")
	_expect(String(ghost) == "none",
		"the ghost group is `none` — the same dead group Boss._die already used")
	var hero: CharacterBody2D = _make_hero()
	_expect(get_nodes_in_group(String(ghost)).is_empty(),
		"nothing is in the ghost group (a member there re-arms every replicated spell)")
	hero.queue_free()
	_completes("ghost_group_is_empty")


## A hero that is NOT a networked puppet scans its faction exactly as before, and the
## ghost answer is reachable. `_is_net_puppet()` is false in a headless suite (no
## session), which is the single-player case and the one that must not move.
func _test_puppet_scans_ghost() -> void:
	var hero: CharacterBody2D = _make_hero()
	_require_props(hero, HERO_MEMBERS, "Hero")
	_expect(hero.has_method("attack_group"), "Hero still publishes attack_group()")
	_expect(hero.has_method("_is_net_puppet"), "Hero publishes the puppet predicate")
	_expect(not hero.call("_is_net_puppet"),
		"a hero in a headless (no-session) tree is NOT a puppet — SP must be untouched")
	_expect(String(hero.call("attack_group")) == String(SpellCaster.damage_group(&"enemy")),
		"a locally-owned hero's attacks still scan the friendly-fire group")
	_expect(String(hero.get("NET_GHOST_GROUP")) == "none",
		"Hero's ghost constant agrees with Net's")
	hero.queue_free()
	_completes("puppet_scans_ghost")


## THE SYNC SET. `max_hp` is called out by name because its absence was a live bug:
## `hp` streamed but `max_hp` did not, so a remote health bar drew a Juggernaut's 140
## hp against whatever denominator the local class happened to have.
func _test_sync_set_complete() -> void:
	var hero: CharacterBody2D = _make_hero()
	var cfg: SceneReplicationConfig = _sync_config(hero)
	if cfg == null:
		# No session in a headless run, so no synchronizer is built. Assert against
		# the source of truth instead of skipping — a skipped assertion is how a
		# suite goes green while testing nothing.
		_expect(_source_declares_sync_props(),
			"Hero._setup_net_sync lists every property in SYNC_PROPS")
		hero.queue_free()
		_completes("sync_set_complete")
		return
	var have: Dictionary = {}
	for p: NodePath in cfg.get_properties():
		have[String(p)] = true
	for p: String in SYNC_PROPS:
		_expect(have.has(p), "the hero sync set still carries `%s`" % p)
	hero.queue_free()
	_completes("sync_set_complete")


## Bandwidth is a DECISION here, not an accident, so it is pinned. Both bodies must
## stream at the same rate: an enemy on a different clock to the hero chasing it
## reads as stutter relative to them even when each is smooth alone.
func _test_sync_is_rate_limited() -> void:
	var hero_src: String = _read("res://scripts/combat/Hero.gd")
	var enemy_src: String = _read("res://scripts/combat/Enemy.gd")
	_expect(hero_src.contains("NET_TRANSFORM_HZ: float = 30.0"),
		"the hero transform stream is rate-limited to 30 Hz")
	_expect(enemy_src.contains("NET_TRANSFORM_HZ: float = 30.0"),
		"enemies stream on the SAME clock as heroes")
	_expect(hero_src.contains("sync.replication_interval"),
		"the hero synchronizer actually applies its interval")
	_expect(enemy_src.contains("sync.replication_interval"),
		"the enemy synchronizer actually applies its interval")
	_completes("sync_is_rate_limited")


## What the owner publishes has to describe what the body is DOING, not be inferred
## from velocity — that inference is exactly why teammates jogged through their casts.
func _test_publish_state() -> void:
	var hero: CharacterBody2D = _make_hero()
	_expect(hero.has_method("_publish_net_state"), "Hero publishes its visual state")
	hero.set("_aim_dir", Vector2.UP)
	hero.set("_element", Elements.Element.FIRE)
	hero.call("_publish_net_state")
	_expect(hero.get("net_aim") == Vector2.UP, "aim direction is published")
	_expect(int(hero.get("net_element")) == Elements.Element.FIRE, "element is published")
	_expect(int(hero.get("net_flags")) == 0, "an idle hero publishes no state flags")
	hero.set("is_dashing", true)
	hero.call("_publish_net_state")
	_expect((int(hero.get("net_flags")) & 8) != 0, "the dash bit is published (NET_F_DASH)")
	hero.set("is_dashing", false)
	hero.queue_free()
	_completes("publish_state")


## A replay onto a hero this peer OWNS must do nothing at all. That guard is what
## stops a broadcast that loops back (or a mis-addressed packet) from casting the
## same spell twice on the caster's own screen.
func _test_replay_is_inert() -> void:
	var hero: CharacterBody2D = _make_hero()
	_expect(hero.has_method("net_replay_action"), "Hero exposes the replay entry point")
	var before: int = get_nodes_in_group("player_spell").size()
	hero.call("net_replay_action", "pr", {"aim": Vector2.RIGHT, "pt": Vector2(100, 0), "el": 0})
	_expect(get_nodes_in_group("player_spell").size() == before,
		"replaying onto a hero we OWN spawns nothing (no double-cast on the caster's screen)")
	_expect(not bool(hero.get("_replaying")),
		"the replay flag is cleared again even on the early-out path")
	_expect(SpellCaster.friendly_fire == _ff_baseline,
		"friendly fire is put BACK after a replay (a leak here disarms the whole game)")
	hero.queue_free()
	_completes("replay_is_inert")


## A replayed cast carries a spell ID, so the lookup has to answer for every spell in
## the tree — including one the receiving hero's own class does not carry.
func _test_spell_lookup_by_id() -> void:
	var hero: CharacterBody2D = _make_hero()
	var all: Array = SpellLibrary.build_all()
	_expect(not all.is_empty(), "the spell library is non-empty")
	var missed: int = 0
	for s: SpellDef in all:
		if hero.call("_net_spell", s.id) == null:
			missed += 1
	_expect(missed == 0, "every spell in the tree resolves by id (%d did not)" % missed)
	_expect(hero.call("_net_spell", "") == null, "an empty id resolves to null, not a crash")
	_expect(hero.call("_net_spell", "no_such_spell") == null, "an unknown id resolves to null")
	hero.queue_free()
	_completes("spell_lookup_by_id")


## The bolt twin's contract: it stops on a body and hurts nothing. Driven through
## `_try_damage` directly, which is the seam the headless harness can reach (there is
## no physics world in a `--script` run, so the segment raycast no-ops by design).
func _test_bolt_twin_hurts_nobody() -> void:
	var bolt: Area2D = (load("res://scenes/combat/Spell.tscn") as PackedScene).instantiate()
	root.add_child(bolt)
	bolt.set("visual_only", true)
	bolt.set("damage", 40)
	var victim := _Dummy.new()
	victim.add_to_group("enemy")
	victim.add_to_group(String(SpellCaster.MORTAL_GROUP))
	root.add_child(victim)
	bolt.call("_try_damage", victim)
	_expect(victim.taken == 0, "a cosmetic twin deals NO damage to a fighter")
	_expect(bolt.get("_dead"), "...but it still CONSUMES itself, so the picture matches")

	# ...and the real bolt is unchanged, which is the half that proves the flag is
	# the only difference rather than a new damage path.
	var real: Area2D = (load("res://scenes/combat/Spell.tscn") as PackedScene).instantiate()
	root.add_child(real)
	real.set("damage", 40)
	var victim2 := _Dummy.new()
	victim2.add_to_group("enemy")
	root.add_child(victim2)
	real.call("_try_damage", victim2)
	_expect(victim2.taken == 40, "a REAL bolt still deals its damage (got %d)" % victim2.taken)

	# Cover is the deliberate exception — a twin breaks crates so the two phones'
	# geometry converges instead of diverging.
	var twin2: Area2D = (load("res://scenes/combat/Spell.tscn") as PackedScene).instantiate()
	root.add_child(twin2)
	twin2.set("visual_only", true)
	twin2.set("damage", 25)
	var crate := _Dummy.new()
	crate.add_to_group("destructible")
	root.add_child(crate)
	twin2.call("_try_damage", crate)
	_expect(crate.taken == 25,
		"a twin STILL breaks cover — that is what keeps both peers' geometry in step")
	for n: Node in [bolt, victim, real, victim2, twin2, crate]:
		n.queue_free()
	_completes("bolt_twin_hurts_nobody")


## Heroes had no `apply_status` at all, so every `has_method` guard in ~20 spell
## scripts silently answered false and elemental friendly fire did not exist.
func _test_hero_takes_ailments() -> void:
	var hero: CharacterBody2D = _make_hero()
	_expect(hero.has_method("apply_status"), "a hero can be set on fire at all")
	_expect(is_equal_approx(float(hero.call("_status_speed_mult")), 1.0),
		"an unafflicted hero moves at full speed")
	hero.call("apply_status", Elements.Element.ICE)
	_expect(hero.get("_status") != null, "the status component is created on first ailment")
	_expect(float(hero.call("_status_speed_mult")) < 1.0, "a chilled hero is slowed")
	# A revive cleanses — coming back up still burning is not a revive.
	hero.call("revive")
	_expect(is_equal_approx(float(hero.call("_status_speed_mult")), 1.0),
		"a revive clears ailments")
	hero.queue_free()
	_completes("hero_takes_ailments")


## Out of session the status router is a direct local call, byte-identical to the
## behaviour every single-player spell already had.
func _test_status_router_local() -> void:
	var net: Node = root.get_node_or_null("Net")
	if net == null:
		_expect(false, "the Net autoload is present")
		return
	_expect(net.has_method("deal_status"), "Net routes ailments the way it routes damage")
	var victim := _Dummy.new()
	root.add_child(victim)
	net.call("deal_status", victim, Elements.Element.FIRE)
	_expect(victim.status == Elements.Element.FIRE,
		"out of session, deal_status is a direct local call")
	net.call("deal_status", victim, -1)
	_expect(victim.status == Elements.Element.FIRE, "a negative element is ignored, not applied")
	net.call("deal_status", null, Elements.Element.FIRE)   # must not crash
	victim.queue_free()
	_completes("status_router_local")


## The boss's client-side seam. `net_apply_phase` must exist and must NOT run the
## host-only half (adds, attack cooldown) — a client that summoned its own adds would
## put enemies on one screen that exist on neither peer's authority.
func _test_boss_phase_seam() -> void:
	var src: String = _read("res://scripts/combat/Boss.gd")
	_expect(src.contains("func net_apply_phase"), "Boss exposes a client-side phase apply")
	_expect(src.contains("broadcast_boss_phase"), "Boss broadcasts its phase escalation")
	# Host and client run the SAME escalation with one flag between them — a copy is
	# how the two screens would silently drift apart on the next retint.
	_expect(src.contains("_apply_phase(p, true)") and src.contains("_apply_phase(p, false)"),
		"host and client share one phase function, differing only by `authoritative`")
	_expect(src.contains("if authoritative:\n\t\t\t\t_atk_summon()"),
		"the adds are behind the authority guard (a client must not mint enemies)")
	_expect(src.contains("if authoritative:\n\t\t_attack_cd"),
		"the attack clock is behind the authority guard")
	# Every attack the guardian owns has to reach a client. A silent omission here is
	# an attack that half the party cannot see coming.
	for kind: String in ["\"slam\"", "\"pillar\"", "\"beam\"", "\"ray\"", "\"meteor\"",
			"\"convergence\"", "\"nova\""]:
		_expect(src.contains("_bfx(" + kind), "the boss broadcasts its %s spectacle" % kind)
	_completes("boss_phase_seam")


## THE STANDING RULE OF THIS CODEBASE: single player must stay byte-identical. Every
## broadcast helper is a no-op with no session, and the group substitution that makes
## a twin harmless must never be left switched off.
func _test_sp_is_unchanged() -> void:
	var net: Node = root.get_node_or_null("Net")
	if net == null:
		_expect(false, "the Net autoload is present")
		return
	_expect(not net.call("is_active"),
		"is_active() is FALSE with no session (the OfflineMultiplayerPeer exclusion holds)")
	# These must all be silent no-ops rather than errors when nobody is connected.
	net.call("broadcast_hero_action", "pr", {})
	net.call("broadcast_boss_fx", "ray", {"pos": Vector2.ZERO})
	net.call("broadcast_boss_phase", null, 2)
	net.call("notify_arena_ready")
	var lone: CharacterBody2D = _make_hero()
	_expect(net.call("hero_for_peer", 1) == lone,
		"hero_for_peer finds a hero by AUTHORITY (default authority is 1)")
	_expect(net.call("hero_for_peer", 77) == null, "an unknown peer resolves to null")
	lone.queue_free()
	_expect(SpellCaster.friendly_fire == _ff_baseline,
		"the friendly-fire toggle is only ever borrowed, never left flipped")
	# The property the ghost mechanism actually leans on: converting twice is the
	# same as converting once, so `Hero` can pass `attack_group()` straight into
	# `SpellCaster.cast` without the stamp folding it somewhere else.
	var once: StringName = SpellCaster.damage_group(&"enemy")
	_expect(SpellCaster.damage_group(once) == once,
		"damage_group is idempotent (Hero passes an already-converted group into cast)")
	var hero: CharacterBody2D = _make_hero()
	var before: int = get_nodes_in_group("player_spell").size()
	hero.call("_net_send", "pr", {})
	_expect(get_nodes_in_group("player_spell").size() == before,
		"_net_send changes nothing in single player")
	hero.queue_free()
	_completes("sp_is_unchanged")


## A replay must actually BUILD something. `_spell_twins` in the two-process smoke
## test counts successful returns, and a return is only worth counting if the
## dispatch really produces a spectacle — otherwise "HERO_SPELLS=OK" would mean
## "a packet arrived", which is the weaker claim wearing the stronger one's name.
##
## Reachable headlessly by handing the hero away to a different authority id: that
## is the ONE precondition `net_replay_action` gates on, and it costs nothing.
func _test_replay_builds_a_spectacle() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.set_multiplayer_authority(2)   # "someone else owns this body"
	var before: int = get_nodes_in_group("player_spell").size()
	var ok: bool = bool(hero.call("net_replay_action", "pr",
		{"aim": Vector2.RIGHT, "pt": Vector2(300, 0), "el": Elements.Element.FIRE}))
	_expect(ok, "the replay reports that it ran to completion")
	_expect(get_nodes_in_group("player_spell").size() > before,
		"a replayed primary actually spawns a bolt on this screen")
	_expect(int(hero.get("net_element")) >= 0 and int(hero.get("_element")) == Elements.Element.FIRE,
		"the replay adopts the ORIGINATING hero's element, not ours")
	_expect(SpellCaster.friendly_fire == _ff_baseline,
		"the toggle is back where it started after the rebuild")
	_expect(not bool(hero.get("_replaying")), "the replay scope is closed again")
	# An unknown action kind must be a silent no-op, not a crash or a wrong spell.
	var mid: int = get_nodes_in_group("player_spell").size()
	_expect(bool(hero.call("net_replay_action", "zz", {})),
		"an unknown kind still returns cleanly")
	_expect(get_nodes_in_group("player_spell").size() == mid,
		"an unknown kind builds nothing")
	for n: Node in get_nodes_in_group("player_spell"):
		n.queue_free()
	hero.queue_free()
	_completes("replay_builds_a_spectacle")


## A DROPPED PHONE MUST NOT SOFT-LOCK THE RUN. The departed peer's Hero used to stay
## in the tree on every remaining peer as a frozen puppet: still in the `hero` group,
## never `downed`, so `Arena._check_party_wipe` waited forever for a body that could
## never go down. Nothing errored; the run simply stopped being winnable or losable.
func _test_disconnect_frees_the_puppet() -> void:
	var net: Node = root.get_node_or_null("Net")
	if net == null:
		_expect(false, "the Net autoload is present")
		return
	var mine: CharacterBody2D = _make_hero()
	var theirs: CharacterBody2D = _make_hero()
	theirs.set_multiplayer_authority(9)
	_expect(net.has_method("_free_peer_hero"), "Net can free a departed peer's hero")
	net.call("_free_peer_hero", 9)
	_expect(theirs.is_queued_for_deletion(), "the departed peer's hero is freed")
	_expect(not mine.is_queued_for_deletion(), "...and ONLY theirs — ours survives")
	# And the wipe check has to ignore a body that is on its way out, because
	# `queue_free` does not land until the end of the frame — one tick of a frozen,
	# never-downed puppet is enough to hold the party in an unwinnable fight.
	var arena_src: String = _read("res://scripts/combat/Arena.gd")
	_expect(arena_src.contains("is_queued_for_deletion"),
		"_check_party_wipe skips a hero that is already dying")
	mine.queue_free()
	_completes("disconnect_frees_the_puppet")


## LAN discovery: the socket path has to open and close cleanly, and the read side
## has to answer sensibly with nothing on the network. This deliberately does NOT
## assert that a beacon is received — a loopback broadcast round-trip depends on the
## host's network stack and firewall, and a test that is flaky for environmental
## reasons trains people to ignore red.
func _test_lan_discovery_api() -> void:
	var net: Node = root.get_node_or_null("Net")
	if net == null:
		_expect(false, "the Net autoload is present")
		return
	for m: String in ["start_beacon", "stop_beacon", "start_discovery", "stop_discovery",
			"discovered_hosts"]:
		_expect(net.has_method(m), "Net exposes `%s` for the Lobby to call" % m)
	_expect(net.has_signal("hosts_changed"), "Net signals when the host list changes")
	_expect((net.discovered_hosts() as Array).is_empty(),
		"no hosts are listed before discovery starts")
	var err: int = int(net.call("start_discovery"))
	_expect(err == OK or err == ERR_ALREADY_IN_USE,
		"the discovery socket binds (or reports the port busy) rather than crashing")
	_expect((net.discovered_hosts() as Array).is_empty(),
		"an empty network lists no hosts — never a phantom button")
	net.call("stop_discovery")
	net.call("start_beacon", "TEST HOST")
	net.call("stop_beacon")
	_expect(true, "beacon start/stop is clean")
	_completes("lan_discovery_api")


# ---------------------------------------------------------------- helpers
func _sync_config(hero: Node) -> SceneReplicationConfig:
	var sync: MultiplayerSynchronizer = hero.get_node_or_null("NetSync") as MultiplayerSynchronizer
	return sync.replication_config if sync != null else null


## Fallback for the no-session case: read the sync set out of the source rather than
## skip the assertion entirely.
func _source_declares_sync_props() -> bool:
	var src: String = _read("res://scripts/combat/Hero.gd")
	for p: String in SYNC_PROPS:
		if not src.contains("\"" + p + "\""):
			printerr("FAIL: Hero._setup_net_sync no longer lists `%s`" % p)
			return false
	return true


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


## Minimal victim: implements the two duck-typed methods every damage path looks for
## and records what it was handed. Deliberately NOT an Enemy — the point is to isolate
## the spell's decision from the victim's own routing.
class _Dummy extends Node2D:
	var taken: int = 0
	var status: int = -1

	func take_damage(amount: int) -> void:
		taken += amount

	func apply_status(element: int, _can_chain: bool = true) -> void:
		status = element

	func apply_knockback(_impulse: Vector2, _flop: bool = true) -> void:
		pass

	func damage_at(amount: int, _at: Vector2, _dir: Vector2) -> void:
		taken += amount
