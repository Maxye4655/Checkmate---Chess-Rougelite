extends Node
## Autoload ("NetworkManager"). Owns the ENet connection and every message the two
## players exchange. The board scene never touches the multiplayer API directly: it
## calls the send_* functions and listens to the signals below.
##
## Messages that arrive while the board scene is still loading are queued and
## delivered once the board calls set_board_ready(true). Without this, a host who
## plays White could move before the guest's board exists and the move would be lost.

signal connection_failed
signal upnp_finished(success: bool, external_ip: String)

# Everything below is only emitted while a board scene is listening.
signal opponent_left
signal move_received(from: Vector2i, to: Vector2i)
signal loadout_received(seq: int, loadout: Dictionary)          # guest -> host, each round
signal round_setup_received(seq: int, board: Array)             # host -> guest, each round
signal mate_verdict_received(used_life: bool, history_size: int)
signal undo_requested(target: int, history_size: int)
signal undo_answered(accepted: bool, target: int)

const PORT := 7777

var _peer: ENetMultiplayerPeer
var _board_ready := false
var _inbox: Array = []
var _upnp_thread: Thread


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()


# =============================================================================
# Connecting
# =============================================================================

func host_game() -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, 1)   # exactly one opponent
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	return OK


func join_game(address: String) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, PORT)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	return OK


func close() -> void:
	_inbox.clear()
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null


func get_local_ip() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			return address
	return "unknown"


## Asks the router (UPnP) to forward the game port so friends outside your network can
## join. Runs on a thread because discovery blocks for a couple of seconds.
func try_upnp() -> void:
	if _upnp_thread != null:
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker)


func _upnp_worker() -> void:
	var success := false
	var external_ip := ""
	var upnp := UPNP.new()
	if upnp.discover() == UPNP.UPNP_RESULT_SUCCESS:
		var gateway := upnp.get_gateway()
		if gateway != null and gateway.is_valid_gateway():
			var result := upnp.add_port_mapping(PORT, PORT, "Chess", "UDP", 3600)
			if result != UPNP.UPNP_RESULT_SUCCESS:
				result = upnp.add_port_mapping(PORT, PORT, "Chess", "UDP", 0)   # some routers refuse leases
			if result == UPNP.UPNP_RESULT_SUCCESS:
				success = true
				external_ip = upnp.query_external_address()
	_upnp_done.call_deferred(success, external_ip)


func _upnp_done(success: bool, external_ip: String) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	upnp_finished.emit(success, external_ip)


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# The host decides who is White for round one; the board swaps colours each round.
	var host_color: int = [ChessEngine.WHITE, ChessEngine.BLACK].pick_random()
	_start_match.rpc_id(id, -host_color)
	_start_match(host_color)


func _on_peer_disconnected(_id: int) -> void:
	_dispatch(&"opponent_left", [])


func _on_connection_failed() -> void:
	close()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	_dispatch(&"opponent_left", [])


@rpc("authority", "call_remote", "reliable")
func _start_match(my_color: int) -> void:
	GameConfig.mode = GameConfig.Mode.ONLINE
	GameConfig.player_color = my_color
	get_tree().change_scene_to_file("res://board.tscn")


# =============================================================================
# Delivery to the board scene
# =============================================================================

func set_board_ready(value: bool) -> void:
	_board_ready = value
	if not value:
		return
	var queued := _inbox.duplicate()
	_inbox.clear()
	for entry in queued:
		callv("emit_signal", [entry[0]] + entry[1])


func _dispatch(signal_name: StringName, args: Array) -> void:
	if _board_ready:
		callv("emit_signal", [signal_name] + args)
	else:
		_inbox.append([signal_name, args])


# =============================================================================
# Messages (send_* are what the board calls; _receive_* run on the other machine)
# =============================================================================

func send_move(from: Vector2i, to: Vector2i) -> void:
	if _peer != null:
		_receive_move.rpc(from, to)


@rpc("any_peer", "call_remote", "reliable")
func _receive_move(from: Vector2i, to: Vector2i) -> void:
	_dispatch(&"move_received", [from, to])


## Guest -> host at the start of every round: "here is what I own".
func send_loadout(seq: int, loadout: Dictionary) -> void:
	if _peer != null:
		_receive_loadout.rpc_id(1, seq, loadout)


@rpc("any_peer", "call_remote", "reliable")
func _receive_loadout(seq: int, loadout: Dictionary) -> void:
	_dispatch(&"loadout_received", [seq, loadout])


## Host -> guest: the finished starting board (promotions, removed pawns, queens...).
func send_round_setup(seq: int, board: Array) -> void:
	if _peer != null:
		_receive_round_setup.rpc(seq, board)


@rpc("authority", "call_remote", "reliable")
func _receive_round_setup(seq: int, board: Array) -> void:
	_dispatch(&"round_setup_received", [seq, board])


## Sent by the player who was just checkmated: did a Second Wind / Phoenix Feather save
## them? If so, history_size is how many moves the board was rewound to.
func send_mate_verdict(used_life: bool, history_size: int) -> void:
	if _peer != null:
		_receive_mate_verdict.rpc(used_life, history_size)


@rpc("any_peer", "call_remote", "reliable")
func _receive_mate_verdict(used_life: bool, history_size: int) -> void:
	_dispatch(&"mate_verdict_received", [used_life, history_size])


func send_undo_request(target: int, history_size: int) -> void:
	if _peer != null:
		_receive_undo_request.rpc(target, history_size)


@rpc("any_peer", "call_remote", "reliable")
func _receive_undo_request(target: int, history_size: int) -> void:
	_dispatch(&"undo_requested", [target, history_size])


func send_undo_answer(accepted: bool, target: int) -> void:
	if _peer != null:
		_receive_undo_answer.rpc(accepted, target)


@rpc("any_peer", "call_remote", "reliable")
func _receive_undo_answer(accepted: bool, target: int) -> void:
	_dispatch(&"undo_answered", [accepted, target])
