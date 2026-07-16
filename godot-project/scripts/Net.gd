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

const DEFAULT_PORT: int = 24565
const DEFAULT_IP: String = "127.0.0.1"
const MAX_PLAYERS: int = 4

## peer_id -> selected class int (0..7). Host owns the table; clients push their
## pick and the host rebroadcasts the whole thing.
var peer_class: Dictionary = {}
var _pending_class: int = 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
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
		print("[NET] host sees peer %d, total=%d" % [id, multiplayer.get_peers().size() + 1]))
	var err: int = host(0)
	print("[NET] host start err=%d id=%d" % [err, my_id()])


func _cli_join(ip: String) -> void:
	join_ok.connect(func() -> void: print("[NET] client connected, my_id=%d" % multiplayer.get_unique_id()))
	join_failed.connect(func() -> void: print("[NET] client FAILED"))
	var err: int = join(ip, 0)
	print("[NET] client join err=%d" % err)
