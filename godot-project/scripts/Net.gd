extends Node
## Co-op networking spine (autoload "Net"). Owns the ENetMultiplayerPeer,
## host/join/leave, the peer<->class table, and the "apply damage on the victim's
## authority" router. SINGLEPLAYER stays byte-identical: is_active()==false makes
## every helper a direct local call, so the whole game runs exactly as before
## unless a session is up. Host-authoritative world (enemies/run), client-owned
## heroes (each client drives its own hero input).

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_started
signal join_ok
signal join_failed
signal lobby_changed
signal net_floor_cleared   # host cleared the floor -> clients spawn the exit portal(s)
signal party_ready         # every peer's Arena has reported in -> safe to spawn heroes
signal hosts_changed       # LAN discovery: the visible-host list changed

const DEFAULT_PORT: int = 24565
const DEFAULT_IP: String = "127.0.0.1"

## THE GROUP NOBODY IS EVER IN. Every cosmetic "twin" this file builds — a remote
## hero's spell, a boss beam a client must see — is pointed at this group so its
## damage scan finds zero bodies. `Boss._die` already used the same trick for its
## visual-only finisher, so this is that precedent named rather than a new idea.
##
## ⚠ WHY A DEAD GROUP AND NOT A `visual_only` FLAG. Twenty-three spectacle scripts
## resolve victims through exactly one call, `get_nodes_in_group(target_group)`.
## Pointing that string at an empty group disarms all of them without editing any of
## them. A flag would have to be declared, read and respected by every one.
const GHOST_GROUP: StringName = &"none"
## The client-local spawn-mark twin (see broadcast_spawn_tell). Loaded by PATH
## rather than by `class_name`: the mark is a pure `_draw` node with no global
## class registration, so nothing here depends on the editor's class cache.
const SPAWN_TELL_SCRIPT: GDScript = preload("res://scripts/combat/SpawnTell.gd")
## THE TOWER spec caps a session at 2 players. This is a hard design cap, not a
## placeholder: the 25-entity budget, the one-screen arena and the friendly-fire
## social loop are all balanced around exactly two thumbs in one room.
const MAX_PLAYERS: int = 2

## peer_id -> selected class int (0..7). Host owns the table; clients push their
## pick and the host rebroadcasts the whole thing.
var peer_class: Dictionary = {}
## peer id -> that player's own saved climb floor. Announced on join exactly the
## way `peer_class` is, and read ONCE, by `start_coop_run`, to decide where the
## party begins. Before this the host's floor was simply imposed on everyone.
var peer_floor: Dictionary = {}
var _pending_class: int = 0
## True between a floor clearing and the party advancing — the host advances ONCE
## per clear, whichever hero reaches the exit first (debounces two near-simultaneous
## portal takes into a single floor step).
var _pending_advance: bool = false
## Count of attack-visual twins this peer has built from host broadcasts (client-side
## only; the host builds real nodes, never twins). Surfaced by the loopback smoke
## test to prove the tell/bolt RPC path delivers over the wire.
var _twins_built: int = 0
## Count of HERO-SPELL twins this peer has built from another peer's cast broadcast.
## Separate from `_twins_built` (host->client enemy visuals) because they prove
## different wires: enemy twins flow host->client, spell twins flow peer->peer.
var _spell_twins: int = 0
## Count of BOSS spectacle/phase twins built from the host's broadcasts.
var _boss_twins: int = 0
## Which boss-fx KINDS this peer has actually built, e.g. {"beam": 3, "zone": 1}.
##
## ⚠ A BARE COUNT CANNOT PROVE THE THING THAT WAS BROKEN. `_boss_twins` went up on
## the Ashspire Guardian alone, and the Guardian was the ONE boss already wired — so
## a green `boss_twins=7` said nothing about whether the Scribble, the Cartographer,
## the Illuminator or any modifier rider crossed the wire. The smoke test asserts on
## this breakdown instead, which is the difference between "a boss broadcast arrived"
## and "the boss you are actually fighting on floor 3 is visible".
var _boss_fx_kinds: Dictionary = {}
## Count of PROP states this peer has taken from the host (cover convergence).
var _prop_syncs: int = 0
## Count of PICKUPS this peer has resolved from the host's single award decision.
var _pickups_awarded: int = 0
## True once the party has entered the tower. Late joiners are refused after this —
## a hero spawned mid-floor has no encounter budget, no floor state and no way to
## catch up, so the honest answer is "the session is closed", not a broken puppet.
var _run_started: bool = false
## Spawn handshake: peer_id -> true once that peer's Arena has finished _ready and is
## able to RECEIVE replicated hero spawns. Replaces the 0.6 s guess in Arena.
var _arena_ready: Dictionary = {}
var _party_ready_sent: bool = false


func _ready() -> void:
	set_process(false)   # only the LAN beacon/discovery needs a frame pump
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Co-op: bridge the host's run-spine to the clients. These GameState signals only
	# fire on the host in a session (clients are guarded), and in SP is_host() is
	# false, so the handlers are no-ops unless a real co-op run is driving them.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.floor_advanced.connect(_on_gs_floor_advanced)
		gs.run_ended.connect(_on_gs_run_ended)
	_maybe_cli_autostart()


## True whenever a real ENet session is up (host or client). Singleplayer -> false.
##
## ⚠ THE `OfflineMultiplayerPeer` EXCLUSION IS LOAD-BEARING, NOT DEFENSIVE. A
## SceneTree with no session does NOT have a null peer: Godot installs an
## `OfflineMultiplayerPeer`, and that peer reports `CONNECTION_CONNECTED`. So the
## old two-clause test was **true in single player**, and since ~40 call sites
## across this codebase gate co-op behaviour on it under the stated rule "SP must
## stay byte-identical, everything co-op is gated on Net.is_active()", every one of
## those gates has silently been OPEN in single player.
##
## It was found the way this class of bug always gets found — by someone measuring
## rather than assuming, while asking why an un-factioned hero bolt could already
## damage another hero in a solo game. The damage-routing paths mostly no-op with
## one peer, which is exactly why it survived: it fails quietly and in the
## direction that still looks correct.
##
## Kept as an explicit type test rather than a `get_unique_id() != 1` check,
## because the host of a real session also has id 1.
func is_active() -> bool:
	var p: MultiplayerPeer = multiplayer.multiplayer_peer
	if p == null or p is OfflineMultiplayerPeer:
		return false
	return p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_active() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 1


# ---------------------------------------------------------------- host / join
func host(my_class: int, port: int = DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	peer_class = {1: my_class}
	peer_floor = {1: _my_climb_floor()}
	_arena_ready.clear()
	_party_ready_sent = false
	_run_started = false
	# ADVERTISE ON THE LAN the moment we start hosting. Done here rather than left to
	# the Lobby so the host half of discovery cannot be forgotten: "two phones in one
	# room" only works if the host is findable without anyone reading an IP aloud.
	# It stops itself when the run starts (the session is closed by then).
	start_beacon()
	server_started.emit()
	lobby_changed.emit()
	return OK


func join(ip: String = DEFAULT_IP, my_class: int = 0, port: int = DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_pending_class = my_class
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer_class.clear()
	peer_floor.clear()
	_pickup_awarded.clear()
	_arena_ready.clear()
	_party_ready_sent = false
	_run_started = false
	stop_beacon()
	stop_discovery()
	lobby_changed.emit()


## Every participating id incl. self, host (1) first.
func peers() -> Array:
	var ids: Array = [1]
	for p in multiplayer.get_peers():
		if not ids.has(p):
			ids.append(p)
	var me: int = my_id()
	if not ids.has(me):
		ids.append(me)
	ids.sort()
	return ids


func class_of(peer_id: int) -> int:
	return int(peer_class.get(peer_id, 0))


# ------------------------------------------------------------- signal handlers
## LATE JOINS ARE REFUSED, and both clauses are real failure modes rather than
## paranoia. `create_server(port, MAX_PLAYERS - 1)` caps CONCURRENT peers but says
## nothing about a third phone arriving the instant one drops, and nothing at all
## about someone joining ten floors into a climb — that peer gets a hero with no
## floor state, no encounter budget and no way to catch up, i.e. a puppet that
## permanently blocks `_check_party_wipe`. Refusing is the honest answer.
func _on_peer_connected(id: int) -> void:
	if is_host():
		var reason: String = ""
		if multiplayer.get_peers().size() + 1 > MAX_PLAYERS:
			reason = "session full"
		elif _run_started:
			reason = "run in progress"
		if reason != "":
			print("[NET] refusing peer %d (%s)" % [id, reason])
			_join_refused.rpc_id(id, reason)
			# Deferred: disconnecting inside the connected callback tears the ENet
			# peer down while the connection event is still being dispatched.
			(func() -> void:
				var p: MultiplayerPeer = multiplayer.multiplayer_peer
				if p is ENetMultiplayerPeer:
					(p as ENetMultiplayerPeer).disconnect_peer(id)).call_deferred()
			return
	player_connected.emit(id)
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _join_refused(reason: String) -> void:
	print("[NET] join refused: %s" % reason)
	join_failed.emit()


## A PHONE DROPPED. Erasing the class row was never enough: the departed peer's Hero
## node stays in the tree on every REMAINING peer as a frozen puppet — it still
## answers `get_nodes_in_group("hero")`, it is not `downed`, and so
## `Arena._check_party_wipe` waits forever for a body that will never go down. That
## is a soft-locked run, which is the worst outcome a dropped connection can have.
func _on_peer_disconnected(id: int) -> void:
	peer_class.erase(id)
	peer_floor.erase(id)
	_arena_ready.erase(id)
	_free_peer_hero(id)
	player_disconnected.emit(id)
	lobby_changed.emit()


## Free the hero owned by `peer_id` on THIS peer. Runs on every remaining peer
## (`peer_disconnected` is local to each), so the host's spawner despawn and this
## are belt-and-braces rather than a race — `queue_free` twice is a no-op.
func _free_peer_hero(peer_id: int) -> void:
	if not is_inside_tree():
		return
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if not is_instance_valid(h) or h.is_queued_for_deletion():
			continue
		if h.get_multiplayer_authority() == peer_id:
			h.queue_free()


# ---------------------------------------------------------- SPAWN HANDSHAKE
## Every peer's Arena calls this from its own `_ready`. The host spawns the party
## only once every peer has reported in, replacing `Arena`'s bare 0.6 s timer (whose
## own comment admitted a handshake was the right fix). A 4 s fallback still fires so
## one silent peer can never hang the whole party at a black screen.
func notify_arena_ready() -> void:
	if not is_active():
		return
	if is_host():
		_arena_ready[1] = true
		_check_party_ready()
		get_tree().create_timer(4.0).timeout.connect(_force_party_ready)
	else:
		_arena_ready_rpc.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _arena_ready_rpc() -> void:
	if not is_host():
		return
	_arena_ready[multiplayer.get_remote_sender_id()] = true
	_check_party_ready()


func _check_party_ready() -> void:
	if _party_ready_sent or not is_host():
		return
	for pid in peers():
		if not _arena_ready.has(int(pid)):
			return
	_party_ready_sent = true
	party_ready.emit()


## The handshake's safety valve: if a peer never reports (crashed loading, dropped
## mid-scene-change), spawn anyway rather than leaving everyone staring at an
## empty arena. Prints so the smoke test can tell a handshake from a timeout.
func _force_party_ready() -> void:
	if _party_ready_sent or not is_host():
		return
	print("[NET] handshake timed out — spawning party anyway")
	_party_ready_sent = true
	party_ready.emit()


func _on_connected_ok() -> void:
	join_ok.emit()
	_announce_class.rpc_id(1, _pending_class)
	_announce_floor.rpc_id(1, _my_climb_floor())


func _on_connected_fail() -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit()


## THE HOST QUIT. This used to drop the client into the parked v0.0 town, with no
## route out of it. The title screen is the boot scene and the one place a player
## can start something else from.
func _on_server_disconnected() -> void:
	leave()
	get_tree().change_scene_to_file(GameState.TITLE_SCENE)


# --------------------------------------------------------- class table (RPC)
## This peer's own saved climb floor, or 1 if there is no GameState to ask (a
## harness, or a build with the autoload absent). Guarded lookup, same shape as
## every other reach out of Net.
func _my_climb_floor() -> int:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("current_floor"):
		return maxi(int(gs.call("current_floor")), 1)
	return 1


@rpc("any_peer", "reliable")
func _announce_floor(floor: int) -> void:
	peer_floor[multiplayer.get_remote_sender_id()] = maxi(floor, 1)


@rpc("any_peer", "reliable")
func _announce_class(cls: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	peer_class[sender] = cls
	# ⚠ ONLY THE HOST REBROADCASTS. `_sync_class_table` is declared `@rpc("authority")`,
	# so a non-host sending it is refused by Godot anyway — this is inert today
	# because MAX_PLAYERS is 2 and there is never a third peer to receive it. It is a
	# trap the moment that cap moves: the guard costs nothing and the error it would
	# otherwise throw names the wrong thing.
	if is_host():
		_sync_class_table.rpc(peer_class)


@rpc("authority", "reliable")
func _sync_class_table(table: Dictionary) -> void:
	var clean: Dictionary = {}
	for k in table.keys():
		clean[int(k)] = int(table[k])
	peer_class = clean
	lobby_changed.emit()


# ============================================================ co-op run entry
## Host broadcasts "everyone into the tower". Sets the shared run state on every
## peer (host owns floor progression + climber.json thereafter) then loads Arena.
## `floor_override` exists for the headless two-process test and nothing else: the
## maker's live climber save sits on the LAST floor, where "advance" means CONQUER
## and tears the session down — so the smoke test could never observe a floor step
## actually crossing the wire. Defaulting to -1 keeps every real caller unchanged.
func start_coop_run(floor_override: int = -1) -> void:
	if not is_host():
		return
	# ⚠ THE PARTY START IS THE LOWEST CHECKPOINT, NOT THE HOST'S FLOOR.
	#
	# This used to read `gs.current_floor()` and impose it on everyone, so joining a
	# friend further up dragged you into content you had not earned — and joining a
	# friend further down silently cost you your progress. Neither is the model the
	# maker chose. `GameState.party_start_floor` owns the rule; see its ⚠ for why the
	# lowest CHECKPOINT (rather than the lowest floor) is what makes it self-levelling.
	var floor: int = 1
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("party_start_floor"):
		peer_floor[my_id()] = _my_climb_floor()   # refresh our own before deciding
		floor = int(gs.call("party_start_floor", peer_floor.values()))
	elif gs != null and gs.has_method("current_floor"):
		floor = int(gs.call("current_floor"))
	if floor_override > 0:
		floor = floor_override
	_run_started = true
	stop_beacon()   # the session is closed; stop advertising it on the LAN
	_enter_coop_run.rpc(floor)
	_enter_coop_run(floor)


@rpc("authority", "call_local", "reliable")
func _enter_coop_run(floor: int) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("enter_coop_run"):
		gs.enter_coop_run(floor)
	get_tree().change_scene_to_file("res://scenes/combat/Arena.tscn")


# ==================================================== co-op run-spine (floor sync)
## Host cleared the floor: arm the advance debounce + tell clients to spawn the exit
## portal(s) so ANY hero (host or client) can pull the party forward.
func broadcast_floor_cleared() -> void:
	if not is_host():
		return
	_pending_advance = true
	_client_cleared.rpc()


@rpc("authority", "call_remote", "reliable")
func _client_cleared() -> void:
	net_floor_cleared.emit()   # the client Arena spawns its exit portal(s)


## A hero took the exit portal. Client -> ask the host; host -> advance the party
## (once per clear). The host's advance_floor emits floor_advanced, which both
## rebuilds the host Arena AND rebroadcasts to every client below.
func request_advance() -> void:
	if not is_active():
		return
	if is_host():
		_do_host_advance()
	else:
		_req_advance.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_advance() -> void:
	if is_host():
		_do_host_advance()


func _do_host_advance() -> void:
	if not _pending_advance:
		return                          # already advanced this floor (debounce)
	_pending_advance = false
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.advance_floor()


## A hero took the RETURN-TO-TOWN portal. Client -> ask the host; host -> return the
## party to the hub (ends the run -> run_ended tears the session down for everyone).
func request_return() -> void:
	if not is_active():
		return
	if is_host():
		_do_host_return()
	else:
		_req_return.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_return() -> void:
	if is_host():
		_do_host_return()


func _do_host_return() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.return_to_hub()


## PARTY WIPE = GAME OVER. Every hero is a ghost, so the run ends for everyone.
##
## Replaces `request_fall` verbatim in shape (client asks, host decides) and only in
## outcome: the maker's 2026-08-01 rule is "if you all die then the game is over",
## not "drop a floor". The host's `GameState.game_over()` ends the run, which fires
## `run_ended` -> `_on_gs_run_ended` -> the session is torn down and every client
## bounces home on its own.
func request_party_wipe() -> void:
	if not is_active():
		return
	if is_host():
		_do_host_wipe()
	else:
		_req_wipe.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_wipe() -> void:
	if is_host():
		_do_host_wipe()


func _do_host_wipe() -> void:
	_pending_advance = false   # a wipe supersedes any pending advance
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("game_over"):
		gs.game_over()


# ============================================================= REVIVE (one award)
## PICKING A TEAMMATE UP, DECIDED ONCE. Modelled on the pickup race directly above:
## the peer that ran the channel REPORTS, the host DECIDES, and the award comes back
## as a `call_local` RPC so the host runs the byte-identical code path its client
## does. There is no second implementation of "apply a revive" that could drift.
##
## ⚠ WHY IT NEEDS A DECIDER AT ALL when a hero is already owned by its own peer. Both
## players can be channelling the same ghost, and either of them can finish on the
## same tick — and `Revive.apply` is not idempotent in the way that matters: two
## awards means two `_revives_applied`, two bursts, two dings, and (once anything
## charges for a revive) two payments for one body. `_host_award_revive` refuses the
## second one by asking the live hero whether it is still down, which is a question
## only the host's copy is entitled to answer.
##
## The KEY on the wire is the ghost's PEER ID, not a node path or a position: heroes
## come through a `MultiplayerSpawner` but `hero_for_peer` already keys identity on
## the multiplayer authority everywhere else in this file, and that is the one
## identifier both phones are guaranteed to agree on.
## Count of revives THIS peer has applied from the host's award. Surfaced by the
## loopback smoke test — a revive is the one thing in this feature that cannot be
## proven from inside a single process.
var _revives_applied: int = 0


## Called by `Revive._complete()` on the peer that finished the channel.
func request_revive(ghost: Node) -> void:
	if not is_active() or ghost == null or not is_instance_valid(ghost):
		return
	var pid: int = ghost.get_multiplayer_authority()
	if is_host():
		_host_award_revive(pid)
	else:
		_req_revive.rpc_id(1, pid)


@rpc("any_peer", "call_remote", "reliable")
func _req_revive(peer_id: int) -> void:
	if is_host():
		_host_award_revive(peer_id)


func _host_award_revive(peer_id: int) -> void:
	var hero: Node = hero_for_peer(peer_id)
	# Both refusals are NORMAL answers rather than errors: the hero may have been
	# freed (its player dropped), or a second channel may have finished a tick after
	# the first — a photo finish resolves once, for everyone.
	if hero == null or not hero.has_method(&"is_downed") or not bool(hero.call(&"is_downed")):
		return
	_client_revive.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _client_revive(peer_id: int) -> void:
	var hero: Node = hero_for_peer(peer_id)
	if hero == null:
		return
	# `Revive.apply` plays the FX on EVERY peer and mutates state only on the ghost's
	# owner — see its header for why the authority test lives inside rather than here.
	if Revive.apply(hero):
		_revives_applied += 1


# ---- host -> client rebroadcast of the run-spine signals (host-only; SP no-ops) ---
func _on_gs_floor_advanced(floor: int) -> void:
	# The floor's props are freed and rebuilt, so the award ledger must not survive:
	# positions are re-used across floors and a stale key would silently refuse the
	# NEXT floor's pickup to everyone.
	_pickup_awarded.clear()
	if is_host():
		_client_floor.rpc(floor)


func _on_gs_run_ended(_outcome: Dictionary) -> void:
	# Co-op run over (conquer / return / abandon): tear the session down. Clients get
	# server_disconnected -> they bounce home on their own. Deferred so the current
	# signal + the host's own scene change finish first.
	if is_host() and is_active():
		call_deferred("leave")


@rpc("authority", "call_remote", "reliable")
func _client_floor(floor: int) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("net_set_floor"):
		gs.net_set_floor(floor)


# =========================================================== DAMAGE ROUTER
## Damage is applied on the VICTIM's authority. Singleplayer -> direct call.
func deal_damage(target: Node, amount: int, tint: Color = Color(1, 1, 1, 0)) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	# ══════════════════════════════════════════════════════ FRIENDLY FIRE
	# ⚠ THIS IS THE ONLY PLACE IN THE CODEBASE WHERE HERO-ON-HERO DAMAGE IS
	# IDENTIFIABLE, and it is identifiable by construction rather than by guessing:
	#
	#   * `Spell.tscn` is instanced by `Hero` and nothing else (`Hero.gd:241`);
	#   * `Spell._damage_hero` is the ONLY caller of this router;
	#   * so a HERO arriving here is a hero's bolt landing on a hero.
	#
	# `Hero.take_damage(amount)` carries no attacker, so nothing downstream of the hit
	# can say who threw it — which is why friendly fire, the spec's whole social
	# engine, shipped with no acknowledgement anywhere in the game.
	#
	# TWO THINGS HAPPEN HERE, and the first one is why the player-facing dial is not
	# a lie. Turning friendly fire off re-points every SPECTACLE at a faction group,
	# but `Spell._damage_hero` permits a hero hit through its own clause
	# (`session and hostile_group == &"enemy"`) which never consults that static — so
	# "off" used to mean "off, except for the attack every class throws constantly".
	if is_active() and amount > 0 and target.is_in_group(&"hero"):
		if FriendlyFire.blocks_bolt():
			return                      # the dial is off: the bolt passes through
		_announce_friendly_fire(target, amount)
	if not is_active():
		_local_damage(target, amount, tint)
		return
	if target.get_multiplayer_authority() == multiplayer.get_unique_id():
		_local_damage(target, amount, tint)
	else:
		target.rpc_id(target.get_multiplayer_authority(), &"_net_take_damage", amount, tint)


func deal_knockback(target: Node, impulse: Vector2) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("apply_knockback"):
		return
	if not is_active():
		target.apply_knockback(impulse)
		return
	if target.get_multiplayer_authority() == multiplayer.get_unique_id():
		target.apply_knockback(impulse)
	else:
		target.rpc_id(target.get_multiplayer_authority(), &"_net_apply_knockback", impulse)


## Tell BOTH screens. The router runs on the ATTACKER's peer (the victim's copy gets
## a `_net_take_damage` RPC on `Hero`, which this file does not own), so without a
## broadcast the read would land only on the screen of the person who did it — i.e.
## on everyone except the person entitled to know.
##
## The attacker is `FriendlyFire.other_hero`: exact, not heuristic, and only because
## `MAX_PLAYERS == 2` is a hard design cap. A party of three would return null there
## and the toast fires without a name rather than blaming the wrong friend.
func _announce_friendly_fire(victim: Node, amount: int) -> void:
	var attacker: Node = FriendlyFire.other_hero(get_tree(), victim)
	_client_friendly_fire.rpc(
		victim.get_multiplayer_authority(),
		attacker.get_multiplayer_authority() if attacker != null else 0,
		amount)


## Count of friendly-fire READS this peer has rendered. Surfaced by the loopback
## smoke test: whether your friend's mistake is legible on YOUR screen is a
## two-process question, exactly like the revive.
var _friendly_hits: int = 0


@rpc("any_peer", "call_local", "reliable")
func _client_friendly_fire(victim_peer: int, attacker_peer: int, amount: int) -> void:
	var victim: Node = hero_for_peer(victim_peer)
	var attacker: Node = hero_for_peer(attacker_peer) if attacker_peer != 0 else null
	if FriendlyFire.report(victim, attacker, amount):
		_friendly_hits += 1


func _local_damage(target: Node, amount: int, tint: Color) -> void:
	if target.is_in_group("enemy"):
		target.take_damage(amount, tint)   # Enemy.take_damage(amount, tint)
	else:
		target.take_damage(amount)         # Hero.take_damage(amount)


# ===================================================== ATTACK-VISUAL REPLICATION
## Enemies are host-authoritative: their bodies + hp + damage replicate, but an
## attack's TELL (the Telegraph danger sigil) and a caster's BOLT are host-only
## nodes. A client would then be hit by a tell it never saw — unfair. The host
## broadcasts a cosmetic twin of each; every client builds a DAMAGE-FREE copy into
## its Arena so the whole roster's attacks READ on every screen. The twins carry
## NO gameplay (all damage/knockback stays host-authoritative via the router above);
## they exist purely to be seen, animate on their own _process, and free themselves.
## No-op in SP / when not the host. `data` is an RPC Dictionary (types preserved —
## no JSON float trap here), keyed by the Telegraph / EnemyProjectile fields.
func broadcast_telegraph(data: Dictionary) -> void:
	if is_host():
		_client_telegraph.rpc(data)


@rpc("authority", "call_remote", "reliable")
func _client_telegraph(data: Dictionary) -> void:
	var scene: Node = get_tree().current_scene
	if scene != null:
		_spawn_telegraph_twin(scene, data)


## THE SPAWN TELL, replicated for exactly the reason the attack tells above are:
## enemies are host-authoritative, so a client would otherwise watch bodies pop out
## of nothing while the host got a beat of warning. RELIABLE on purpose — a dropped
## mark is a body that arrives unannounced, which is the whole failure this feature
## exists to fix, so it does NOT go the unreliable route `_client_burst` takes.
##
## THE TWIN CARRIES NO GAMEPLAY AND CANNOT DESYNC. The host's Encounter owns the
## WAITING (it holds the spawn data for SPAWN_TELL_LEAD and counts the unborn body
## against its caps); the BODY still reaches every peer through the same
## MultiplayerSpawner at the same moment as before. This packet is a picture.
func broadcast_spawn_tell(data: Dictionary) -> void:
	if is_host():
		_client_spawn_tell.rpc(data)


@rpc("authority", "call_remote", "reliable")
func _client_spawn_tell(data: Dictionary) -> void:
	var scene: Node = get_tree().current_scene
	if scene != null:
		_twins_built += 1
		var t: Node2D = SPAWN_TELL_SCRIPT.new()
		t.position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
		t.call("configure", float(data.get("lead", 0.4)),
			data.get("tint", Color(0.95, 0.5, 0.25, 1)), float(data.get("heft", 0.42)))
		scene.add_child(t)


func broadcast_projectile(data: Dictionary) -> void:
	if is_host():
		_client_projectile.rpc(data)


@rpc("authority", "call_remote", "reliable")
func _client_projectile(data: Dictionary) -> void:
	var scene: Node = get_tree().current_scene
	if scene != null:
		_spawn_projectile_twin(scene, data)


## A damage-free Telegraph copy at the marked spot. Source-less (no caster tether —
## the client doesn't hold the host's enemy node) but the danger sigil itself reads.
## Style/geometry/timing come straight from the host's _emit_telegraph cfg.
func _spawn_telegraph_twin(scene: Node, data: Dictionary) -> void:
	_twins_built += 1
	var tele := Telegraph.new()
	scene.add_child(tele)
	tele.global_position = data.get("pos", Vector2.ZERO)
	tele.accent = data.get("accent", Telegraph.RING_COLOR)
	tele.style = data.get("style", Telegraph.Style.ZONE)   # Variant->enum (runtime-safe)
	tele.aim_dir = data.get("aim", Vector2.RIGHT)
	tele.reach = float(data.get("reach", 120.0))
	if bool(data.get("line", false)):
		tele.start_line(
			float(data.get("length", 0.0)), float(data.get("width", 0.0)),
			float(data.get("angle", 0.0)), float(data.get("windup", 0.5)))
	else:
		tele.start(float(data.get("radius", 40.0)), float(data.get("windup", 0.5)))


## A visual_only EnemyProjectile twin — flies, stops on walls, bursts for the look,
## never damages/clashes (visual_only gates all of that in EnemyProjectile).
func _spawn_projectile_twin(scene: Node, data: Dictionary) -> void:
	_twins_built += 1
	var proj := EnemyProjectile.new()
	proj.visual_only = true
	scene.add_child(proj)
	proj.global_position = data.get("pos", Vector2.ZERO)
	proj.launch(data.get("dir", Vector2.RIGHT))
	proj.set_element(int(data.get("element", -1)))


## DETONATION spectacle replication (backlog #2): the enemy MAGE's ground AoE and the
## BOMBER's blast render only on the host — the client sees the tell (above) but not
## the detonation art. The host broadcasts a damage-free twin of each. No-op in SP.
func broadcast_blast(pos: Vector2, element: int, radius: float) -> void:
	if is_host():
		_client_blast.rpc(pos, element, radius)


@rpc("authority", "call_remote", "reliable")
func _client_blast(pos: Vector2, element: int, radius: float) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	_twins_built += 1
	var blast := BlastSpell.new()
	scene.add_child(blast)
	blast.configure({"visual_only": true, "element_id": element, "radius": radius, "target_group": "hero"})
	blast.detonate_now(pos)


func broadcast_burst(pos: Vector2, c1: Color, c2: Color) -> void:
	if is_host():
		_client_burst.rpc(pos, c1, c2)


## BANDWIDTH: this one is PURE decoration (the bomber's puff). A dropped packet
## costs a puff nobody can act on, so it goes unreliable — unlike the telegraph and
## the projectile above, which are fairness signals and stay reliable on purpose.
@rpc("authority", "call_remote", "unreliable")
func _client_burst(pos: Vector2, c1: Color, c2: Color) -> void:
	var scene: Node = get_tree().current_scene
	if scene != null:
		_twins_built += 1
		CombatVfx.spawn_burst(scene, pos, c1, c2, 36, 0.45, 120.0, 260.0, 1.5, 4.0, 40.0, 90.0)


# ================================================= HERO SPELL REPLICATION
## THE HEADLINE. `SpellCaster` is deliberately net-blind and stays that way: it is a
## pure builder, and putting a wire inside it would mean every future spectacle had
## to think about networking. Instead the CAST SITE broadcasts — `Hero` is the only
## thing that knows a cast happened, and it knows everything about it — and every
## other peer rebuilds the same spectacle locally through the same dispatcher.
##
## ⚠ WHY THE REBUILT COPY CANNOT DAMAGE. Damage already resolves on the VICTIM's
## authority (`Hero.take_damage` / `Enemy.take_damage` forward to their owner), so a
## second live spectacle on a second peer would not desync hp — it would DOUBLE it.
## The twin is therefore disarmed at the only seam that matters: its `target_group`
## is `GHOST_GROUP`, a group with no members. See `Hero.attack_group()` for the
## persistent half of that rule (a puppet's melee resolves asynchronously, long
## after this call returns, so a transient flag would not have covered it).
##
## Broadcast is peer->peer (`any_peer`) rather than host-authoritative, because a
## hero is owned by its own player: the host has no more idea that a client cast a
## spell than the client does that the host did.
##
## RELIABLE ON PURPOSE. A dropped cast is INVISIBLE MAGIC — your friend's Void
## deleting you out of nowhere is precisely the moment this whole feature exists to
## make legible. This is the one place bandwidth loses the argument.
func broadcast_hero_action(kind: String, data: Dictionary) -> void:
	if is_active():
		_client_hero_action.rpc(kind, data)


@rpc("any_peer", "call_remote", "reliable")
func _client_hero_action(kind: String, data: Dictionary) -> void:
	var hero: Node = hero_for_peer(multiplayer.get_remote_sender_id())
	if hero == null or not hero.has_method("net_replay_action"):
		return
	# Counted on the ANSWER, not on the attempt. `net_replay_action` returns false
	# both when it declines and when it aborts on a moved member, so the smoke test's
	# `spell_twins` measures spectacles actually BUILT rather than packets received.
	if bool(hero.call("net_replay_action", kind, data)):
		_spell_twins += 1


## The live Hero owned by `peer_id`, or null. Identity across peers is the AUTHORITY,
## not the node name: `Arena._spawn_hero_net` names them `Hero_<peer>` but the
## authority is what every other co-op path already keys on, so this stays true even
## if the spawner renames.
func hero_for_peer(peer_id: int) -> Node:
	if not is_inside_tree():
		return null
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if not is_instance_valid(h) or h.is_queued_for_deletion():
			continue
		if h.get_multiplayer_authority() == peer_id:
			return h
	return null


# ===================================================== BOSS SPECTACLE REPLICATION
## `Boss.gd` shipped with ZERO broadcasts: its beam, meteors, pillars, rays, nova and
## every phase escalation rendered host-side only. Half the party could not see the
## climax of the floor — and worse, could not see the thing about to hit them, which
## breaks the boss's own "the shape you can see is the shape that will hurt" grammar.
##
## The tells already crossed (the Boss builds them through `Enemy._emit_telegraph`,
## which broadcasts). What did not was everything AFTER the tell.
##
## ⚠ THE ROSTER GREW AND THIS DID NOT — THE GAP THIS BLOCK NOW CLOSES. The arms
## below were written against the Ashspire Guardian's seven spectacles, and then
## three more bosses (Scribble / Cartographer / Illuminator) and six modifier riders
## landed with ZERO network references between them. On every floor that draws a new
## artist — which is most of them — a client watched a boss attack invisibly.
##
## So the arm list is no longer "the Guardian's moveset". It is the VOCABULARY every
## boss and every rider composes out of: the seven spell shapes, plus the summoning
## sigil (`circle`), the ground rot (`zone`), the shadow scrawl (`root`), the erase /
## redraw puff (`burst`), the streak flash (`dash`), the screen beat (`beat`) and the
## mirrored player spell (`spell`). A new boss that builds its moveset out of these
## replicates for free; one that invents a new shape adds one arm here, and the
## smoke test's kind breakdown is what catches it if it does not.
## XP EARNED BY THE PARTY, RELAYED.
##
## ⚠ WITHOUT THIS, A CLIENT LEVELS ONLY FROM FLOOR TRANSITIONS AND NEVER FROM
## FIGHTING. Enemies are host-authoritative, so `Enemy._die` — and therefore
## `notify_kill` — runs on the host and nowhere else. The client would watch bodies
## fall and bank nothing for them, which fails in the direction that still looks
## correct: XP would keep arriving (from clears), just far too little of it, and
## only a side-by-side comparison of two saves would ever show it.
##
## Everyone in the fight earned the kill, so the grant is relayed verbatim and each
## peer banks it into their OWN climber.json. It is not split — a co-op floor is not
## worth less per person than a solo one, or playing together would be a tax.
func broadcast_xp(amount: int, kind: String, where: Vector2 = Vector2.ZERO) -> void:
	if is_host():
		_client_xp.rpc(amount, kind, where)


@rpc("authority", "call_remote", "reliable")
func _client_xp(amount: int, kind: String, where: Vector2) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("receive_net_xp"):
		gs.call("receive_net_xp", int(amount), String(kind), where)


func broadcast_boss_fx(kind: String, data: Dictionary) -> void:
	if is_host():
		_client_boss_fx.rpc(kind, data)


@rpc("authority", "call_remote", "reliable")
func _client_boss_fx(kind: String, data: Dictionary) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	_boss_twins += 1
	_boss_fx_kinds[kind] = int(_boss_fx_kinds.get(kind, 0)) + 1
	var pos: Vector2 = data.get("pos", Vector2.ZERO)
	var col: Color = data.get("col", Color(1.0, 0.55, 0.2))
	var fx: String = String(data.get("fx", "fire"))
	var caster: Node = _node_at(String(data.get("src", "")))
	match kind:
		"beam":
			var beam := BeamSpell.new()
			beam.target_group = String(GHOST_GROUP)
			beam.element_id = int(data.get("el", -1))
			beam.caster_node = caster
			scene.add_child(beam)
			beam.fire(pos, data.get("dir", Vector2.RIGHT), col,
				float(data.get("len", 1400.0)), float(data.get("w", 34.0)), 0, fx)
		"pillar":
			var p := RockPillar.new()
			p.target_group = String(GHOST_GROUP)
			p.set("caster_node", caster)
			scene.add_child(p)
			p.erupt(pos, col, float(data.get("r", 66.0)), 0)
		"ray":
			var d := DivineRay.new()
			d.target_group = String(GHOST_GROUP)
			d.set("caster_node", caster)
			scene.add_child(d)
			d.strike(pos, col, float(data.get("r", 70.0)), 0, fx)
		"meteor":
			var m := MeteorSigil.new()
			m.target_group = String(GHOST_GROUP)
			m.set("caster_node", caster)
			scene.add_child(m)
			m.rain(pos, col, float(data.get("r", 170.0)), 0, int(data.get("n", 12)), fx)
			Juice.zoom_pull_camera(0.16, 0.5)
		"convergence":
			var s := StarConvergence.new()
			s.target_group = String(GHOST_GROUP)
			s.set("caster_node", caster)
			scene.add_child(s)
			s.converge(pos, col, float(data.get("r", 170.0)), 0, fx)
		"nova":
			var n: Node = load("res://scenes/combat/EnergyNova.tscn").instantiate()
			n.set("target_group", String(GHOST_GROUP))
			n.set("caster_node", caster)
			scene.add_child(n)
			n.call("activate_at", pos)
		"slam":
			var b := BlastSpell.new()
			scene.add_child(b)
			b.configure({"visual_only": true, "target_group": String(GHOST_GROUP),
				"radius": float(data.get("r", 100.0)), "windup": float(data.get("windup", 0.7)),
				"element_id": int(data.get("el", -1))})
			b.set("caster_node", caster)
			b.detonate_at(pos)
		"crater":
			GroundCrater.spawn(scene, pos, float(data.get("r", 64.0)), true)
			Juice.on_hit({"shake": 15.0, "sfx": "blast", "hitstop": 0.09})
		# ---- the roster's shared vocabulary (Scribble / Cartographer / Illuminator
		#      and the six modifier riders all compose out of these) ----------------
		"root":
			# The Scribble's scrawl across the floor. `erupt` parks the node at the
			# arena origin and draws from `pos` — see the standing note that a
			# spectacle's own global_position is NOT where the effect is.
			var rt := ShadowRoot.new()
			rt.set("target_group", String(GHOST_GROUP))
			rt.set("_target_group", String(GHOST_GROUP))
			rt.set("caster_node", caster)
			rt.set("element_id", int(data.get("el", -1)))
			scene.add_child(rt)
			rt.erupt(pos, data.get("aim", Vector2.RIGHT), col, float(data.get("r", 74.0)), 0, fx)
		"zone":
			# VOID-TOUCHED's rot field. Damage-free, but it must still LOOK like a
			# no-go area or the client is being evicted from ground it cannot see.
			var z := ZoneSpell.new()
			z.target_group = String(GHOST_GROUP)
			z.set("_target_group", String(GHOST_GROUP))
			z.caster_node = caster
			z.element_id = int(data.get("el", -1))
			scene.add_child(z)
			z.open(pos, col, float(data.get("r", 62.0)), 0, fx, float(data.get("life", 8.5)))
		"circle":
			# THE SUMMONING SIGIL, and on the new roster it is a FAIRNESS signal, not
			# decoration: the Cartographer's compass ring states its radius with one,
			# the Illuminator's Final Page states its size with one, MIRRORED announces
			# whose spell is coming back, and UNFINISHED's redraw mark IS the play
			# against it ("step off the mark"). A client without these is being asked
			# to dodge things it was never told about.
			var mc := MagicCircle.new()
			scene.add_child(mc)
			mc.global_position = pos
			mc.appear(col, float(data.get("r", 60.0)), float(data.get("grow", 0.2)))
			mc.set_signature(int(data.get("el", -1)), int(data.get("tier", -1)))
			if bool(data.get("ground", false)):
				mc.set_ground(0.34)
			mc.hold(float(data.get("hold", 0.6)), 0.22)
		"burst":
			CombatVfx.spawn_burst(scene, pos, col, data.get("col2", Color(col.r, col.g, col.b, 0.0)),
				int(data.get("n", 20)), float(data.get("life", 0.42)),
				float(data.get("v0", 60.0)), float(data.get("v1", 200.0)),
				float(data.get("s0", 0.8)), float(data.get("s1", 2.2)),
				0.0, 0.0, true)
		"dash":
			# The Scribble's streak. The BODY crosses the room for free (position is
			# replicated), so this is only the flash + the shake that sell it as a
			# launch rather than a teleport.
			if caster != null:
				var rg: Node = caster.get_node_or_null("Rig")
				if rg != null:
					rg.call("play", CharacterRig.State.DASH)
					rg.call("flash_color", Color(1.5, 1.2, 1.2), 0.12)
			Juice.shake_camera(float(data.get("shake", 5.5)))
		"beat":
			# One screen beat. Used for the moments that are host-side `Juice` calls
			# with no spectacle of their own: SPLIT's detonation, UNFINISHED's landing,
			# the Illuminator's Final Page climax.
			var opts: Dictionary = {
				"strength": float(data.get("str", 1.0)),
				"shake": float(data.get("shake", 10.0)),
				"sfx": String(data.get("sfx", "charge_up")),
			}
			if bool(data.get("frame", false)):
				opts["frame"] = true
				opts["at"] = pos
				opts["style"] = int(data.get("style", ImpactFrame.Style.SILHOUETTE))
			Juice.epic_moment(opts)
			if data.has("zoom"):
				Juice.zoom_pull_camera(float(data["zoom"]), float(data.get("zhold", 0.5)))
		"spell":
			# MIRRORED's answer: the player's own spell, thrown back. Rebuilt through
			# the same `SpellCaster.cast` dispatcher the host used — same geometry,
			# same element, same weight — and disarmed the one way that matters, by
			# pointing its victim scan at the group nobody is in.
			_spawn_mirrored_twin(scene, data, pos, col, caster)


## The MIRRORED rider's answer, rebuilt on this peer.
##
## ⚠ `friendly_fire` IS PARKED FOR THE DURATION, exactly as `Hero.net_replay_action`
## parks it. Under the friendly-fire rule `SpellCaster._stamp` REWRITES the target
## group to the everyone-group, which would put the teeth straight back into a
## spectacle whose entire disarming is the group it scans. Same trap, same fix.
func _spawn_mirrored_twin(scene: Node, data: Dictionary, at: Vector2, col: Color, caster: Node) -> void:
	var sid: String = String(data.get("sid", ""))
	if sid == "":
		return
	var spell: SpellDef = SpellLibrary._spell_by_id().get(sid) as SpellDef
	if spell == null:
		return
	var prev_ff: bool = SpellCaster.friendly_fire
	SpellCaster.friendly_fire = false
	SpellCaster.cast(spell, scene, at, data.get("pt", at + Vector2.RIGHT * 200.0),
		col, String(data.get("fx", spell.effect)), caster, GHOST_GROUP)
	SpellCaster.friendly_fire = prev_ff


## Phase escalation — the retint, the aura tier, the adornment, the epic beat. Host
## only advances phases (`Boss.take_damage` forwards a puppet hit before any phase
## logic), so without this a client watched a boss that never visibly escalated.
func broadcast_boss_phase(boss: Node, phase: int) -> void:
	if is_host() and boss != null and boss.is_inside_tree():
		_client_boss_phase.rpc(String(boss.get_path()), phase)


@rpc("authority", "call_remote", "reliable")
func _client_boss_phase(path: String, phase: int) -> void:
	var boss: Node = _node_at(path)
	if boss != null and boss.has_method("net_apply_phase"):
		_boss_twins += 1
		boss.call("net_apply_phase", phase)


## Resolve an absolute node path sent by another peer. Host and clients build the
## same nodes through the same MultiplayerSpawner, so paths match — but a node can
## die between send and receive, so null is a normal answer, not an error.
func _node_at(path: String) -> Node:
	if path == "" or not is_inside_tree():
		return null
	return get_node_or_null(NodePath(path))


# ============================================ DETERMINISTIC ENTITY KEYS
## ⚠ CRATES AND PICKUPS CANNOT USE `get_path()`, AND THE BOSS PATH TRICK ABOVE IS
## THE WRONG PRECEDENT FOR THEM.
##
## `_client_boss_phase` sends a NodePath because bosses come through a
## `MultiplayerSpawner`, which makes the host name authoritative on every peer.
## Crates and the floor's spell pickup do not: every peer builds its OWN from the
## same `LayoutDef` and the same seeded roll (`FloorBuilder` / `SpellDrops`), with
## no name set. Godot then auto-names them `@DestructibleProp@N` off a per-process
## counter — and by the time a floor is built the two peers have instanced
## different numbers of nodes (spell twins, spectacles, particles), so the SAME
## crate has a DIFFERENT name on the two phones. A path would resolve to null, or
## worse, to the wrong crate.
##
## What is identical across peers is where the thing STANDS: both built it at the
## same world point from the same data, and neither crates nor pickups ever move.
## So the wire key is the rounded position, and the receiver matches the nearest
## member of the group. Same idea as the seeded roll itself — derive identity from
## state both peers already share rather than paying a packet to agree on it.
const KEY_TOLERANCE: float = 6.0


## The wire identity of a static, deterministically-placed world object.
static func pos_key(n: Node2D) -> Vector2i:
	if n == null:
		return Vector2i.ZERO
	return Vector2i(roundi(n.global_position.x), roundi(n.global_position.y))


## The member of `group` standing at `key`, or null. Null is a NORMAL answer: the
## receiver may have already freed that crate, or be mid-floor-change.
func _find_at(group: StringName, key: Vector2i) -> Node:
	if not is_inside_tree():
		return null
	var want := Vector2(float(key.x), float(key.y))
	var best: Node = null
	var best_d: float = KEY_TOLERANCE * KEY_TOLERANCE
	for n: Node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(n) or n.is_queued_for_deletion() or not (n is Node2D):
			continue
		var d: float = (n as Node2D).global_position.distance_squared_to(want)
		if d <= best_d:
			best_d = d
			best = n
	return best


# ================================================= COVER (host-authoritative props)
## ENEMY-BROKEN COVER USED TO EXIST ON ONE PHONE ONLY, and that is a fairness bug
## rather than a cosmetic one: you take cover behind a crate your teammate cannot
## see, and they wonder why their bolt stopped in mid-air.
##
## The asymmetry is specific. HERO prop damage already converged for free: a hero's
## spell is rebuilt on the other peer as a twin, and although the twin's fighter
## scan is pointed at the dead `GHOST_GROUP`, every spectacle scans the
## `"destructible"` literal as a SECOND, un-stamped pass — so both peers apply the
## same damage to their own copy of the crate. ENEMY attacks have no such twin with
## teeth: `_client_blast` / `_spawn_projectile_twin` are explicitly `visual_only`,
## so the client watches the blast and the crate simply does not break.
##
## Rather than give enemy twins damage back (which would double-apply the moment an
## enemy hit a hero, the exact bug the twins exist to avoid), cover becomes
## HOST-AUTHORITATIVE: the host is the one peer that sees every damage source —
## enemies natively, and heroes through the twin it builds of the client's cast — so
## it can be the single writer. It broadcasts ABSOLUTE hp, not a delta, which is
## what lets the client keep applying its own hits locally for instant feedback
## without the two ever compounding. See `DestructibleProp.take_damage`.
# ============================================== ELITE VOICES (host-only triggers)
## A BODY THAT ONLY THE HOST CAN HEAR SPEAK.
##
## Most affix voices ride SYNCED state — `EliteQuickened` speaks off `velocity`,
## `EliteVolatile` off `hp` — so each peer runs the same check on the same numbers
## and speaks on its own screen with nothing sent. That is the cheap, correct
## pattern and it should stay the default.
##
## Two affixes have no synced twin for their trigger:
##   * HERALD howls from `_tick`, which `EliteRider._process` gates on authority. On
##     a client the surge is FELT — the bodies really do speed up, because
##     `move_speed` is synced — with no audible or visible cause. That is a fairness
##     bug, not a cosmetic one: the shout is the co-op callout the affix exists for.
##   * KEEN reads `_evade_cd`, local reflex state that is not in the puppet sync, so
##     its edge never fires on a client at all.
##
## Identity is the NodePath, which is valid here and NOT for crates: enemies come
## through the `MultiplayerSpawner` (`Encounter.set_net_spawner`), so both peers
## hold the same node under the same path. Statically-placed props do not, which is
## why those use `pos_key` instead.
##
## The voice ITSELF is already cross-peer deterministic — `elite_voice_seed()` folds
## the replicated spawn dict — so nothing about pitch or band needs to be sent.
func broadcast_voice(who: Node, event: StringName) -> void:
	if is_host() and who != null and who.is_inside_tree():
		_client_voice.rpc(who.get_path(), event)


@rpc("authority", "call_remote", "reliable")
func _client_voice(who_path: NodePath, event: StringName) -> void:
	var who: Node = get_node_or_null(who_path)
	# Null is a NORMAL answer: this peer may have already freed that body, or be
	# mid-floor-change. Same contract as every other receiving arm here.
	if who == null or not is_instance_valid(who):
		return
	Bark.say(who, event, true)


## Mouth only, no bubble — the `elite_voice` half of the same problem.
func broadcast_voice_only(who: Node, mood: int, syllables: int) -> void:
	if is_host() and who != null and who.is_inside_tree():
		_client_voice_only.rpc(who.get_path(), mood, syllables)


@rpc("authority", "call_remote", "reliable")
func _client_voice_only(who_path: NodePath, mood: int, syllables: int) -> void:
	var who: Node = get_node_or_null(who_path)
	if who == null or not is_instance_valid(who):
		return
	Bark.voice_only(who, mood, syllables)


func broadcast_prop_state(prop: Node2D, hp_now: int, shattered: bool) -> void:
	if is_host() and prop != null and prop.is_inside_tree():
		_client_prop_state.rpc(pos_key(prop), hp_now, shattered)


@rpc("authority", "call_remote", "reliable")
func _client_prop_state(key: Vector2i, hp_now: int, shattered: bool) -> void:
	var prop: Node = _find_at(&"destructible", key)
	if prop == null or not prop.has_method(&"net_apply_prop_state"):
		return
	_prop_syncs += 1
	prop.call(&"net_apply_prop_state", hp_now, shattered)


# ================================================ PICKUP RACE (one award, one owner)
## THE PHOTO FINISH. Both peers spawn the same seeded pickup in the same place —
## that half was always solid — but COLLECTION resolved locally on whichever peer
## saw the overlap, so two heroes arriving in the same tick could each be given the
## spell on their own screen, or the two screens could disagree about who got it.
## The spec's "visible and contested, both players can race for them" needs a race
## with ONE finish line.
##
## So: the owning peer REPORTS its overlap (only for a hero it actually drives — a
## puppet's overlap is a stale echo of a position this peer did not integrate), the
## host DECIDES, once, and the award is applied on every peer through
## `SpellPickup.collect_by`. First request to reach the host wins; every later
## request for the same pickup is dropped on the floor rather than raced.
##
## `call_local` on the award is deliberate: the host runs the identical code path
## its client does, so there is no second implementation of "apply a pickup" that
## could drift from the first.
var _pickup_awarded: Dictionary = {}   # host only: pos_key -> peer id


## Called by `SpellPickup` on the peer that owns the colliding hero.
func request_pickup(pickup: Node2D, peer_id: int) -> void:
	if not is_active() or pickup == null or not pickup.is_inside_tree():
		return
	if is_host():
		_host_award_pickup(pos_key(pickup), peer_id)
	else:
		_req_pickup.rpc_id(1, pos_key(pickup))


@rpc("any_peer", "call_remote", "reliable")
func _req_pickup(key: Vector2i) -> void:
	if is_host():
		_host_award_pickup(key, multiplayer.get_remote_sender_id())


func _host_award_pickup(key: Vector2i, peer_id: int) -> void:
	if _pickup_awarded.has(key):
		return   # already decided — a photo finish resolves once, for everyone
	_pickup_awarded[key] = peer_id
	_client_pickup.rpc(key, peer_id)


@rpc("authority", "call_local", "reliable")
func _client_pickup(key: Vector2i, peer_id: int) -> void:
	# BOTH pickup families race on the same finish line. `WeaponPickup` used to run a
	# bare local overlap test, so a photo finish handed the sword to a different hero
	# on each screen — and its `_consumed` latch made that permanent for the floor.
	# The award is keyed by position, and the two families never share one, so
	# checking the second group after the first misses cannot mis-award.
	var pickup: Node = _find_at(&"spell_pickup", key)
	if pickup == null:
		pickup = _find_at(&"weapon_pickup", key)
	var hero: Node = hero_for_peer(peer_id)
	# Both nulls are normal answers, not errors: this peer may already have freed the
	# pickup, or be mid-floor-change. The one lossy case is a winner who DROPPED
	# between the award and its arrival — this peer then keeps a pickup nobody can
	# take until the floor rebuilds. Narrow enough to name rather than machine around.
	if pickup == null or hero == null or not pickup.has_method(&"collect_by"):
		return
	if bool(pickup.call(&"collect_by", hero)):
		_pickups_awarded += 1


# ========================================================== STATUS ROUTER
## Elemental ailments on the victim's own authority, exactly like damage.
##
## THE BUG THIS FIXES: `Spell._damage_hero` applied `apply_status` ONLY on its
## non-session branch. In a live co-op game the session branch called
## `deal_damage`/`deal_knockback` and skipped the ailment entirely, so burning,
## chilling and shocking a teammate did nothing at all — elemental friendly fire
## did not exist. It failed silently and in the direction that still looks correct.
func deal_status(target: Node, element: int, can_chain: bool = true) -> void:
	if target == null or not is_instance_valid(target) or element < 0:
		return
	if not target.has_method("apply_status"):
		return
	if not is_active() or target.get_multiplayer_authority() == multiplayer.get_unique_id():
		target.call("apply_status", element, can_chain)
	else:
		target.rpc_id(target.get_multiplayer_authority(), &"_net_apply_status", element, can_chain)


# ======================================================= LAN AUTO-DISCOVERY
## "Two phones in one room" is the spec's whole picture, and typing an IP address is
## not that. A host advertises itself with a UDP broadcast beacon; a joining phone
## listens and shows each host as a button. Manual IP entry stays as the fallback for
## networks that block broadcast (some hotel/campus wifi does).
##
## ⚠ UI IS NOT WIRED HERE. `Lobby.gd` belongs to another workstream, so this file
## exposes the API only: `start_beacon()` / `start_discovery()` / `discovered_hosts()`
## / the `hosts_changed` signal. See the handoff note for the four lines the Lobby needs.
const BEACON_PORT: int = 24566
const BEACON_MAGIC: String = "TOWERLAN"
const BEACON_INTERVAL: float = 1.0
## A host that has not been heard from for this long drops off the list. Three missed
## beacons — long enough to ride out a wifi hiccup, short enough that a host who quit
## does not linger as a dead button.
const BEACON_TTL: float = 3.5

var _beacon: PacketPeerUDP = null
var _listener: PacketPeerUDP = null
var _beacon_timer: float = 0.0
var _beacon_name: String = ""
var _found: Dictionary = {}   # ip -> {"name": String, "port": int, "seen": float}


## Host side: start advertising this session on the local network.
func start_beacon(host_name: String = "") -> void:
	stop_beacon()
	_beacon_name = host_name if host_name != "" else _default_host_name()
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", BEACON_PORT)
	_beacon_timer = 0.0
	_pump_enabled()


func stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
	_beacon = null
	_pump_enabled()


## Client side: start listening for hosts. `discovered_hosts()` is the read side.
func start_discovery() -> int:
	stop_discovery()
	_listener = PacketPeerUDP.new()
	_listener.set_broadcast_enabled(true)
	var err: int = _listener.bind(BEACON_PORT)
	if err != OK:
		_listener = null
		return err
	_found.clear()
	_pump_enabled()
	return OK


func stop_discovery() -> void:
	if _listener != null:
		_listener.close()
	_listener = null
	_found.clear()
	_pump_enabled()


## Hosts heard from within BEACON_TTL: [{ip, port, name}], freshest first.
##
## ⚠ THE PAYLOAD SHAPE IS A CONTRACT. `Lobby`'s Join screen consumes exactly
## `{ip, port, name}` and takes the PORT off the beacon rather than assuming
## `DEFAULT_PORT`. Do not narrow these keys.
func discovered_hosts() -> Array:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var out: Array = []
	for ip: String in _found.keys():
		var row: Dictionary = _found[ip]
		if now - float(row.get("seen", 0.0)) > BEACON_TTL:
			continue
		out.append({"ip": ip, "port": int(row.get("port", DEFAULT_PORT)),
			"name": String(row.get("name", ip))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(_found[a["ip"]]["seen"]) > float(_found[b["ip"]]["seen"]))
	return out


## Drop every host we have not heard from in BEACON_TTL. Returns true if the list
## actually changed, so the caller emits `hosts_changed` exactly once per pump.
## PUBLIC-ish (used by the discovery test) but pumped from `_process`, which is the
## only place that runs while a listener is up.
func _reap_expired_hosts() -> bool:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var dead: Array[String] = []
	for ip: String in _found.keys():
		if now - float((_found[ip] as Dictionary).get("seen", 0.0)) > BEACON_TTL:
			dead.append(ip)
	for ip: String in dead:
		_found.erase(ip)
	return not dead.is_empty()


func _default_host_name() -> String:
	var n: String = OS.get_environment("COMPUTERNAME")
	if n == "":
		n = OS.get_environment("HOSTNAME")
	return n if n != "" else "THE TOWER"


func _pump_enabled() -> void:
	set_process(_beacon != null or _listener != null)


func _process(delta: float) -> void:
	if _beacon != null:
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			_beacon_timer = BEACON_INTERVAL
			var payload: Dictionary = {"m": BEACON_MAGIC, "port": DEFAULT_PORT,
				"name": _beacon_name, "players": peers().size(), "max": MAX_PLAYERS}
			_beacon.put_packet(JSON.stringify(payload).to_utf8_buffer())
	if _listener == null:
		return
	# A HOST THAT WALKS AWAY MUST ALSO CHANGE THE LIST. `hosts_changed` used to fire
	# only on an ARRIVAL (or on a session filling up); a host that closed the game or
	# left wifi range was reaped silently inside `discovered_hosts()`, so a
	# signal-only consumer kept a dead button on screen forever and tapping it was a
	# guaranteed failed join. The Lobby was covering that with a 1 Hz poll — an
	# autoload's correctness patched from a UI script. Reaping HERE, and emitting,
	# lets that poll be deleted.
	var changed: bool = _reap_expired_hosts()
	while _listener.get_available_packet_count() > 0:
		var raw: PackedByteArray = _listener.get_packet()
		var ip: String = _listener.get_packet_ip()
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if not (parsed is Dictionary):
			continue
		var d: Dictionary = parsed
		if String(d.get("m", "")) != BEACON_MAGIC:
			continue
		# A FULL SESSION IS NOT A BUTTON. The host refuses late joins anyway
		# (`_on_peer_connected`), so listing one would only offer a guaranteed failure.
		if int(d.get("players", 1)) >= int(d.get("max", MAX_PLAYERS)):
			if _found.erase(ip):
				changed = true
			continue
		if not _found.has(ip):
			changed = true
		_found[ip] = {"name": String(d.get("name", ip)), "port": int(d.get("port", DEFAULT_PORT)),
			"seen": float(Time.get_ticks_msec()) / 1000.0}
	if changed:
		hosts_changed.emit()


# --------------------------------------------------- headless two-instance test
## `-- --server` hosts; `-- --client [ip]` joins loopback. Prints `[NET]` lines that
## `python-tools/coop_smoketest.sh` greps. Deferred so the tree is ready.
##
## ⚠ THE TIMING IS THE TEST. The old schedule sampled the client FOUR seconds after
## it connected — one second after the host had already advanced the floor. On the
## maker's live climber save that advance is off the LAST floor, i.e. a conquer,
## which ends the run and tears the session down, so the client was always counted
## after its heroes had gone home. It has been printing `heroes=0` for that reason
## and not because anything was broken, which is the worst kind of green.
##
## Now: the client is sampled while the floor is LIVE, the run is forced to floor 1
## so "advance" is a real climb step rather than a victory, and both peers track
## PEAK counts so a sample landing on the wrong side of a scene change cannot lie.
const CLI_START_DELAY: float = 1.0     # peer connected -> enter the tower
const CLI_HOST_SAMPLE: float = 2.0     # ...-> host counts + fires every broadcast
const CLI_CLIENT_SAMPLE: float = 3.2   # join -> client counts (floor still live)
const CLI_ADVANCE_AT: float = 4.2      # ...-> host advances the party a floor
## THE REVIVE LEG, and its ORDERING is as much the test as its code is.
## The client puts its OWN hero down, waits for that flag to reach the host through
## the synchronizer, and only then asks for a revive — because the host's refusal
## check (`_host_award_revive`) reads the REPLICATED `downed`. A request that overtook
## its own state change would be refused for exactly the right reason at exactly the
## wrong time, and would read as a broken wire.
##
## ⚠ THE GAP AROUND `CLI_ADVANCE_AT` IS DELIBERATE. A floor advance stands the party's
## ghosts back up (`Arena._revive_local_heroes`), so a down that lands near it can be
## silently un-done between the two beats. These sit well clear of it — and
## `_cli_ask_revive` re-downs defensively anyway, because the two peers' clocks start
## from different events (`player_connected` on the host, `join_ok` on the client) and
## a test that depends on their exact skew is a test that goes green by luck.
const CLI_DOWN_AT: float = 6.2         # ...-> the client's hero becomes a ghost
const CLI_REVIVE_AT: float = 7.1       # ...-> the client asks the host to pick it up
const CLI_FINAL_SAMPLE: float = 8.0    # ...-> both count again + client's verdict

## Peak observations, so a sample that lands after a scene change cannot erase what
## was true a moment earlier.
var _cli_peak_heroes: int = 0
var _cli_peak_enemies: int = 0
var _cli_floor_start: int = -1
var _cli_floor_end: int = -1


func _maybe_cli_autostart() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--server"):
		call_deferred("_cli_host")
	elif args.has("--client"):
		var ip: String = DEFAULT_IP
		var idx: int = args.find("--client")
		if idx >= 0 and idx + 1 < args.size() and not args[idx + 1].begins_with("--"):
			ip = args[idx + 1]
		call_deferred("_cli_join", ip)


func _cli_after(t: float, fn: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(fn)


func _cli_host() -> void:
	player_connected.connect(func(id: int) -> void:
		print("[NET] host sees peer %d, total=%d" % [id, multiplayer.get_peers().size() + 1])
		_cli_after(CLI_START_DELAY, func() -> void:
			start_coop_run(1)   # floor 1 -> the advance below is a real climb step
			_cli_after(CLI_HOST_SAMPLE, func() -> void:
				_cli_count("host")
				_cli_floor_start = _cli_floor()
				_cli_fire_every_broadcast()
				_cli_after(CLI_ADVANCE_AT - CLI_HOST_SAMPLE, func() -> void:
					# Arm the debounce (simulate a clear) then advance the party.
					_pending_advance = true
					_do_host_advance()
					_cli_after(CLI_FINAL_SAMPLE - CLI_ADVANCE_AT,
						func() -> void: _cli_count("host2"))))))
	var err: int = host(0)
	print("[NET] host start err=%d id=%d" % [err, my_id()])


## Every wire this file owns, fired once, so the client's counters prove each one
## delivered rather than proving one of them did.
func _cli_fire_every_broadcast() -> void:
	# 1. Enemy attack visuals (the pre-existing pair).
	broadcast_telegraph({
		"style": 0, "pos": Vector2(400, 300), "accent": Color(1, 0.2, 0.15),
		"radius": 40.0, "windup": 0.6, "line": false,
	})
	broadcast_projectile({"pos": Vector2(400, 300), "dir": Vector2.RIGHT, "element": 0})
	# 2. HERO SPELLS — the headline. A primary and a signature eruption. The client
	#    should resolve the sender's hero, rebuild both through SpellCaster against
	#    the dead GHOST_GROUP, and report spell_twins=2.
	broadcast_hero_action("pr", {"aim": Vector2.RIGHT, "pt": Vector2(600, 300), "el": 0})
	broadcast_hero_action("cf", {"sid": "frostpiercer", "aim": Vector2.RIGHT,
		"pt": Vector2(700, 300), "el": 1, "sky": false, "sp": 0})
	# 3. BOSS spectacle (Boss.gd shipped with no broadcasts at all). These two are
	#    hand-fired and deliberately stay GUARDIAN-ONLY kinds — the roster and the
	#    modifier are proven separately, by real code, in `_cli_fire_roster()`.
	broadcast_boss_fx("ray", {"pos": Vector2(500, 320), "col": Color(1, 0.5, 0.2),
		"r": 70.0, "fx": "fire", "el": 0})
	broadcast_boss_fx("nova", {"pos": Vector2(500, 320)})
	# 3b. THE ROSTER + A MODIFIER, driven for real.
	_cli_fire_roster()
	# 4. COVER. An ENEMY-sourced crate break — the path that used to diverge, because
	#    enemy attack twins are visual_only and never touched the client's crate. The
	#    host applies + broadcasts absolute hp; the client should converge without
	#    ever having seen a blast.
	var crate: Node = _cli_first(&"destructible")
	if crate != null and crate.has_method(&"take_damage"):
		crate.call(&"take_damage", 9999)
	# 5. THE PICKUP RACE, from the far side: the host awards the floor drop to the
	#    CLIENT's hero. That is the exact shape of a photo finish the client won, and
	#    it is the case that used to be scored differently on each screen.
	var pick: Node = _cli_first(&"spell_pickup")
	var other: int = 0
	for p in multiplayer.get_peers():
		other = int(p)
		break
	if pick != null and other != 0:
		request_pickup(pick as Node2D, other)
	# 6. FRIENDLY FIRE — the spec's social engine, and the one beat that is worthless
	#    if it only renders on the screen of the person who caused it. The host hits
	#    the CLIENT's hero through the real router; the client should see the toast,
	#    the gold burst and the two lines, and report friendly_hits>=1.
	var mate: Node = hero_for_peer(other) if other != 0 else null
	if mate != null:
		deal_damage(mate, 6)


## A REAL NEW BOSS AND A REAL MODIFIER, DRIVEN THROUGH THEIR OWN CODE.
##
## ⚠ WHY THIS IS NOT ANOTHER PAIR OF HAND-FIRED `broadcast_boss_fx` CALLS. The gap
## this test exists to catch was never "the boss-fx wire is broken" — that wire
## worked. It was that three new bosses and six modifier riders were written with
## ZERO calls into it, so on most floors a client watched a boss attack invisibly.
## A hand-fired packet proves the postbox works while saying nothing about whether
## anybody posted a letter. So this spawns the CARTOGRAPHER carrying VOID-TOUCHED,
## through `Encounter.spawn_boss` (the same path the floor uses, so the body itself
## replicates through the MultiplayerSpawner), and then makes it fight.
##
## The verdict asserts on the KIND breakdown, not the count:
##   `circle` can only come from `TowerBoss.summon_circle` — no Guardian attack
##            opens one, so its arrival proves a new-roster boss cast something.
##   `zone`   can only come from `ModVoidTouched._open_field` — so its arrival
##            proves a modifier rider crossed the wire.
## Neither is reachable from the hand-fired pair above, which is the point.
func _cli_fire_roster() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or not scene.has_method("encounter"):
		print("[NET] roster: no Arena/Encounter — skipped")
		return
	var enc: Node = scene.call("encounter")
	if enc == null or not enc.has_method("spawn_boss"):
		print("[NET] roster: no Encounter — skipped")
		return
	enc.call("spawn_boss", 1.0, 1.0,
		BossRoster.CARTOGRAPHER, [BossModifier.VOID_TOUCHED], 4242)
	# ⚠ THE RETURN VALUE IS NULL IN CO-OP AND THAT IS NOT A FAILURE.
	# `Encounter._emit_enemy` hands the dict to the MultiplayerSpawner and returns
	# null on the replicated path (the spawner owns the node), returning the body
	# only on the single-player direct path. Reading it as "the spawn was refused"
	# skipped the whole roster leg of this test on its first run. So the boss is
	# found in the tree by the rider it is carrying, which is the thing we are here
	# to look for anyway.
	print("[NET] roster: spawned %s + [%s]" % [BossRoster.CARTOGRAPHER, BossModifier.VOID_TOUCHED])
	# The body needs its own `_ready` (rig, bar, riders' first frame) before it can
	# be told to fight, so the drive is deferred by a frame rather than run inline.
	(func() -> void: _cli_drive_boss(_cli_find_modded_boss())).call_deferred()


## The live boss carrying the void-touched rider, or null.
func _cli_find_modded_boss() -> Node:
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if e.get_node_or_null("Mod_" + BossModifier.VOID_TOUCHED) != null:
			return e
	return null


## Make the spawned boss do the things a player would see it do. Attacks are invoked
## directly rather than waited for: the boss opens on a 2.6 s intro and then picks at
## its own cadence, which is longer than this test's whole life.
func _cli_drive_boss(boss: Node) -> void:
	if boss == null or not is_instance_valid(boss) or not boss.is_inside_tree():
		print("[NET] roster: the modded boss never reached the tree")
		return
	print("[NET] roster: driving %s" % String(boss.call("boss_title")))
	boss.call("_enter_phase", 2)
	# COMPASS opens a summoning circle (-> "circle") and strikes a ring of marks
	# (-> "ray"); LATTICE raises a grid of columns (-> "pillar").
	boss.call("_run_attack", "compass")
	boss.call("_run_attack", "lattice")
	# The modifier's ground. `_tick` is the rider's host-only hook; handing it a fat
	# delta expires its own interval immediately instead of waiting 4 s for it.
	var rider: Node = boss.get_node_or_null("Mod_" + BossModifier.VOID_TOUCHED)
	if rider != null and rider.has_method("_tick"):
		rider.call("_tick", 9.0)
	else:
		print("[NET] roster: void-touched rider MISSING on the spawned boss")


func _cli_first(group: StringName) -> Node:
	for n: Node in get_tree().get_nodes_in_group(group):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			return n
	return null


func _cli_join(ip: String) -> void:
	join_ok.connect(func() -> void:
		print("[NET] client connected, my_id=%d" % multiplayer.get_unique_id())
		_cli_after(CLI_CLIENT_SAMPLE, func() -> void:
			_cli_count("client")
			_cli_floor_start = _cli_floor()
			_cli_after(CLI_DOWN_AT - CLI_CLIENT_SAMPLE, _cli_down_self)
			_cli_after(CLI_REVIVE_AT - CLI_CLIENT_SAMPLE, _cli_ask_revive)
			_cli_after(CLI_FINAL_SAMPLE - CLI_CLIENT_SAMPLE, func() -> void:
				_cli_count("client2")
				_cli_floor_end = _cli_floor()
				_cli_verdict())))
	join_failed.connect(func() -> void: print("[NET] client FAILED"))
	var err: int = join(ip, 0)
	print("[NET] client join err=%d" % err)


## GHOST FORM, ON THE WIRE. The client kills its own hero the way the game does, so
## the `downed` flag it publishes is the real one rather than a poked field.
func _cli_down_self() -> void:
	var mine: Node = hero_for_peer(multiplayer.get_unique_id())
	if mine == null or not mine.has_method(&"_enter_downed"):
		print("[NET] revive: no local hero to down — leg skipped")
		return
	mine.call(&"_enter_downed")
	print("[NET] revive: client hero is a ghost (downed=%s)" % [mine.get(&"downed")])


## …and then asks to be picked up. THE ONLY THING THAT CAN PROVE A REVIVE CROSSES THE
## WIRE. A single SceneTree has one MultiplayerAPI, so a `--script` suite can assert
## the routing and never the delivery: whether the host actually saw this peer's
## ghost, decided once, and replayed the identical apply on both screens is a
## two-process question. `_revives_applied` is the answer, counted on the client.
func _cli_ask_revive() -> void:
	var mine: Node = hero_for_peer(multiplayer.get_unique_id())
	if mine == null:
		print("[NET] revive: local hero gone before the request")
		return
	# SELF-HEALING, NOT SLOPPY. If the host's floor advance stood us back up between
	# the two beats, asking now would be refused because the hero is alive — a green
	# `REVIVE=NO` for a reason that has nothing to do with the wire. Go down again and
	# give the flag a tick to reach the host, so the leg always tests what it claims.
	if mine.has_method(&"is_downed") and not bool(mine.call(&"is_downed")):
		print("[NET] revive: hero was stood back up (floor advance) — re-downing")
		mine.call(&"_enter_downed")
		_cli_after(0.6, func() -> void:
			if is_instance_valid(mine):
				print("[NET] revive: client requests a revive (downed=%s)" % [mine.get(&"downed")])
				request_revive(mine))
		return
	print("[NET] revive: client requests a revive (downed=%s)" % [mine.get(&"downed")])
	request_revive(mine)


func _cli_floor() -> int:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("current_floor"):
		return int(gs.current_floor())
	return -1


## ONE GREPPABLE LINE that says whether co-op actually worked, instead of five rows
## a human has to cross-reference. Printed by the CLIENT, because the client is the
## peer every one of these features exists for.
func _cli_verdict() -> void:
	var heroes_ok: bool = _cli_peak_heroes >= 2
	var enemies_ok: bool = _cli_peak_enemies >= 1
	var twins_ok: bool = _twins_built >= 2
	var spells_ok: bool = _spell_twins >= 2
	var boss_ok: bool = _boss_twins >= 2
	var floor_ok: bool = _cli_floor_end > _cli_floor_start
	# COVER + PICKUP: both are "the two screens agree", which only a second process
	# can prove — a single-process suite can assert the routing but never the wire.
	var cover_ok: bool = _prop_syncs >= 1
	var pickup_ok: bool = _pickups_awarded >= 1
	# THE ROSTER AND THE MODIFIERS. `BOSS_FX` above went green for a year on the
	# Ashspire Guardian alone while three other bosses and six riders broadcast
	# nothing at all — so a count is not enough. These two ask for kinds that ONLY a
	# new-roster boss and a modifier rider can produce. See `_cli_fire_roster`.
	var roster_ok: bool = int(_boss_fx_kinds.get("circle", 0)) >= 1
	var mods_ok: bool = int(_boss_fx_kinds.get("zone", 0)) >= 1
	# REVIVE: this peer went down, asked the host to pick it up, and the host's single
	# award came back and was applied here. A ghost that cannot be revived across the
	# wire is a run that ends the first time anybody dies in co-op.
	var revive_ok: bool = _revives_applied >= 1
	# FRIENDLY_FIRE: the host hit THIS peer's hero and this peer rendered the read.
	# The damage always crossed (it routes on the victim's authority); what could not
	# be proven from inside one process is whether the victim is ever TOLD. A friendly
	# hit that reads exactly like an enemy hit is the whole reason the mechanic landed
	# as a tax rather than as a joke.
	var ff_ok: bool = _friendly_hits >= 1
	var all_ok: bool = (heroes_ok and enemies_ok and twins_ok and spells_ok and boss_ok
		and floor_ok and cover_ok and pickup_ok and roster_ok and mods_ok and revive_ok
		and ff_ok)
	print(("[NET] VERDICT heroes=%s enemies=%s enemy_twins=%s HERO_SPELLS=%s BOSS_FX=%s "
		+ "BOSS_ROSTER=%s BOSS_MODS=%s floor_sync=%s COVER=%s PICKUP=%s REVIVE=%s "
		+ "FRIENDLY_FIRE=%s => %s") % [
		_ok(heroes_ok), _ok(enemies_ok), _ok(twins_ok), _ok(spells_ok), _ok(boss_ok),
		_ok(roster_ok), _ok(mods_ok),
		_ok(floor_ok), _ok(cover_ok), _ok(pickup_ok), _ok(revive_ok), _ok(ff_ok),
		"PASS" if all_ok else "FAIL"])
	print("[NET] boss_twins=%d boss_fx_kinds=%s" % [_boss_twins, _cli_kinds()])


## The boss-fx kind breakdown as one sorted, greppable string.
func _cli_kinds() -> String:
	var keys: Array = _boss_fx_kinds.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for k in keys:
		parts.append("%s:%d" % [String(k), int(_boss_fx_kinds[k])])
	return "[" + ",".join(parts) + "]"


func _ok(b: bool) -> String:
	return "OK" if b else "NO"


func _cli_count(who: String) -> void:
	var heroes: int = get_tree().get_nodes_in_group("hero").size()
	var enemy_nodes: Array = get_tree().get_nodes_in_group("enemy")
	var enemies: int = enemy_nodes.size()
	_cli_peak_heroes = maxi(_cli_peak_heroes, heroes)
	_cli_peak_enemies = maxi(_cli_peak_enemies, enemies)
	# Prove the enemies are HOST-authoritative (authority==1) and that the client's
	# copies track the host's transform: print the count owned by peer 1 + the first
	# enemy's rounded position. Host + client rows should show the SAME position.
	var host_owned: int = 0
	var sample: String = "-"
	for e: Node in enemy_nodes:
		if e.get_multiplayer_authority() == 1:
			host_owned += 1
		if sample == "-" and e is Node2D:
			var p: Vector2 = (e as Node2D).global_position
			sample = "(%d,%d)" % [int(round(p.x)), int(round(p.y))]
	print(("[NET] %s heroes=%d(peak %d) enemies=%d host_owned=%d first_enemy_pos=%s "
		+ "floor=%d twins=%d spell_twins=%d boss_twins=%d boss_fx=%s prop_syncs=%d "
		+ "pickups=%d revives=%d friendly_hits=%d ghosts=%d crates=%d") % [
		who, heroes, _cli_peak_heroes, enemies, host_owned, sample, _cli_floor(),
		_twins_built, _spell_twins, _boss_twins, _cli_kinds(), _prop_syncs,
		_pickups_awarded, _revives_applied, _friendly_hits,
		get_tree().get_nodes_in_group(&"ghost").size(),
		get_tree().get_nodes_in_group(&"destructible").size()])
