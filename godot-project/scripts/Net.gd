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

const DEFAULT_PORT: int = 24565
const DEFAULT_IP: String = "127.0.0.1"
const MAX_PLAYERS: int = 4

## peer_id -> selected class int (0..7). Host owns the table; clients push their
## pick and the host rebroadcasts the whole thing.
var peer_class: Dictionary = {}
var _pending_class: int = 0
## True between a floor clearing and the party advancing — the host advances ONCE
## per clear, whichever hero reaches the exit first (debounces two near-simultaneous
## portal takes into a single floor step).
var _pending_advance: bool = false
## Count of attack-visual twins this peer has built from host broadcasts (client-side
## only; the host builds real nodes, never twins). Surfaced by the loopback smoke
## test to prove the tell/bolt RPC path delivers over the wire.
var _twins_built: int = 0


func _ready() -> void:
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
		gs.fell.connect(_on_gs_fell)
		gs.run_ended.connect(_on_gs_run_ended)
	_maybe_cli_autostart()


## True whenever a real ENet session is up (host or client). Singleplayer -> false.
func is_active() -> bool:
	var p: MultiplayerPeer = multiplayer.multiplayer_peer
	return p != null and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


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
func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)
	lobby_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	peer_class.erase(id)
	player_disconnected.emit(id)
	lobby_changed.emit()


func _on_connected_ok() -> void:
	join_ok.emit()
	_announce_class.rpc_id(1, _pending_class)


func _on_connected_fail() -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


# --------------------------------------------------------- class table (RPC)
@rpc("any_peer", "reliable")
func _announce_class(cls: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	peer_class[sender] = cls
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
func start_coop_run() -> void:
	if not is_host():
		return
	var floor: int = 1
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("current_floor"):
		floor = int(gs.current_floor())
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


## Party wipe (Task 4): a hero requests the host to drop the party a floor. Client ->
## ask the host; host -> fall (drops 2, rebuilds, revives everyone via the fell sync).
func request_fall() -> void:
	if not is_active():
		return
	if is_host():
		_do_host_fall()
	else:
		_req_fall.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_fall() -> void:
	if is_host():
		_do_host_fall()


func _do_host_fall() -> void:
	_pending_advance = false   # a fall supersedes any pending advance
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("fall"):
		gs.fall()


# ---- host -> client rebroadcast of the run-spine signals (host-only; SP no-ops) ---
func _on_gs_floor_advanced(floor: int) -> void:
	if is_host():
		_client_floor.rpc(floor, false)


func _on_gs_fell(floor: int) -> void:
	if is_host():
		_client_floor.rpc(floor, true)


func _on_gs_run_ended(_outcome: Dictionary) -> void:
	# Co-op run over (conquer / return / abandon): tear the session down. Clients get
	# server_disconnected -> they bounce home on their own. Deferred so the current
	# signal + the host's own scene change finish first.
	if is_host() and is_active():
		call_deferred("leave")


@rpc("authority", "call_remote", "reliable")
func _client_floor(floor: int, is_fall: bool) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("net_set_floor"):
		gs.net_set_floor(floor, is_fall)


# =========================================================== DAMAGE ROUTER
## Damage is applied on the VICTIM's authority. Singleplayer -> direct call.
func deal_damage(target: Node, amount: int, tint: Color = Color(1, 1, 1, 0)) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return
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


# --------------------------------------------------- headless two-instance test
## `-- --server` hosts; `-- --client [ip]` joins loopback. Prints [NET] lines the
## PowerShell two-process test greps for. Deferred so the tree is ready.
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


func _cli_host() -> void:
	player_connected.connect(func(id: int) -> void:
		print("[NET] host sees peer %d, total=%d" % [id, multiplayer.get_peers().size() + 1])
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			start_coop_run()
			get_tree().create_timer(2.0).timeout.connect(func() -> void:
				_cli_count("host")
				# Prove ATTACK-VISUAL replication end-to-end: broadcast one tell + one
				# bolt twin over the wire (host builds none locally; the client should
				# build both -> its _twins_built rises to 2, reported by _cli_count).
				broadcast_telegraph({
					"style": 0, "pos": Vector2(400, 300), "accent": Color(1, 0.2, 0.15),
					"radius": 40.0, "windup": 0.6, "line": false,
				})
				broadcast_projectile({"pos": Vector2(400, 300), "dir": Vector2.RIGHT, "element": 0})
				# Prove the floor-advance broadcast: arm the debounce (simulate a clear)
				# + advance the party, then re-report so the client's floor should follow.
				_pending_advance = true
				_do_host_advance()
				get_tree().create_timer(2.0).timeout.connect(_cli_count.bind("host2")))))
	var err: int = host(0)
	print("[NET] host start err=%d id=%d" % [err, my_id()])


func _cli_join(ip: String) -> void:
	join_ok.connect(func() -> void:
		print("[NET] client connected, my_id=%d" % multiplayer.get_unique_id())
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			_cli_count("client")
			get_tree().create_timer(2.0).timeout.connect(_cli_count.bind("client2"))))
	join_failed.connect(func() -> void: print("[NET] client FAILED"))
	var err: int = join(ip, 0)
	print("[NET] client join err=%d" % err)


func _cli_count(who: String) -> void:
	var heroes: int = get_tree().get_nodes_in_group("hero").size()
	var enemy_nodes: Array = get_tree().get_nodes_in_group("enemy")
	var enemies: int = enemy_nodes.size()
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
	var floor: int = -1
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("current_floor"):
		floor = int(gs.current_floor())
	print("[NET] %s heroes=%d enemies=%d host_owned=%d first_enemy_pos=%s floor=%d twins=%d" % [who, heroes, enemies, host_owned, sample, floor, _twins_built])
