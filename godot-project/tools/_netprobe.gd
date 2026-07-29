extends SceneTree
func _initialize() -> void:
	var p: MultiplayerPeer = root.multiplayer.multiplayer_peer
	print("peer=", p, " class=", (p.get_class() if p != null else "<null>"))
	if p != null:
		print("status=", p.get_connection_status(), " CONNECTED=", MultiplayerPeer.CONNECTION_CONNECTED)
	print("is OfflineMultiplayerPeer=", p is OfflineMultiplayerPeer)
	print("unique_id=", root.multiplayer.get_unique_id())
	quit(0)
