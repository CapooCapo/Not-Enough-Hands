extends SceneTree

## Two real ENet processes pin bladder ownership and toilet-result
## reconciliation. The server gives the host and client deliberately different
## values; the client must receive only its own, then keep its completed toilet
## result after the reliable acknowledgement arrives.

const PORT := 47323
const RESULT_PATH := "res://.godot/bladder_multiplayer_pair_result.txt"
const TIMEOUT := 10.0
const HOST_BLADDER := 31.0
const CLIENT_BLADDER := 82.0
const REMOTE_SENTINEL := 7.0

var _is_client := false
var _elapsed := 0.0
var _report_sent := false
var _done := false
var _client_pid := -1
var _client_peer_id := 0
var _host_player: CharacterBody3D
var _client_player: CharacterBody3D
var _toilet: Node
var _dev_tools: DevTools


func _initialize() -> void:
	_is_client = "--client" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	var manager := root.get_node_or_null(^"/root/NetworkManager")
	if manager == null:
		return _fail("NetworkManager must be an autoload.")

	var peer := ENetMultiplayerPeer.new()
	if _is_client:
		var registered := Callable(manager, "_on_connected_to_server")
		if get_multiplayer().connected_to_server.is_connected(registered):
			get_multiplayer().connected_to_server.disconnect(registered)
		if peer.create_client("127.0.0.1", PORT) != OK:
			return _fail("Client could not open its socket.")
		get_multiplayer().multiplayer_peer = peer
		manager.set("session_active", true)
		var deadline := Time.get_ticks_msec() + 4000
		while peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			if Time.get_ticks_msec() > deadline:
				return _fail("Client connection timed out.")
			await process_frame
		_build_world()
		return

	if FileAccess.file_exists(RESULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))
	if peer.create_server(PORT, 1) != OK:
		return _fail("Server could not bind UDP %d." % PORT)
	get_multiplayer().multiplayer_peer = peer
	manager.set("session_active", true)
	_build_world()
	get_multiplayer().peer_connected.connect(func(peer_id: int) -> void:
		_client_peer_id = peer_id
		_client_player.owner_peer_id = peer_id
		manager.call("_mark_replication_ready", peer_id)
	)
	get_multiplayer().peer_disconnected.connect(func(peer_id: int) -> void:
		if _client_peer_id == peer_id:
			_client_peer_id = 0
	)
	_client_pid = OS.create_process(OS.get_executable_path(), [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path("res://.godot/bladder_multiplayer_pair_client.log"),
		"--script", "tests/bladder_multiplayer_pair_smoke.gd",
		"--", "--client",
	])
	if _client_pid <= 0:
		return _fail("Could not start the client process.")


func _build_world() -> void:
	var world := Node3D.new()
	world.name = "BladderPairWorld"
	root.add_child(world)
	current_scene = world

	_toilet = Node.new()
	_toilet.name = "Toilet"
	world.add_child(_toilet)

	_host_player = _make_player("Player", 1)
	_client_player = _make_player(
		"PlayerClient",
		get_multiplayer().get_unique_id() if _is_client else 0
	)
	world.add_child(_host_player)
	world.add_child(_client_player)
	_dev_tools = (load("res://ui/dev_tools.tscn") as PackedScene).instantiate() as DevTools
	_dev_tools.name = "DevTools"
	world.add_child(_dev_tools)
	_host_player.set_physics_process(false)
	_client_player.set_physics_process(false)
	_host_player.bladder.bladder_fill_rate = 0.0
	_client_player.bladder.bladder_fill_rate = 0.0

	if _is_client:
		# A remote replica starts at a distinct sentinel. Owner-only bladder
		# snapshots must leave it untouched while updating the client-owned body.
		_host_player.set_bladder(REMOTE_SENTINEL)
	else:
		_host_player.set_bladder(HOST_BLADDER)
		_client_player.set_bladder(CLIENT_BLADDER)
		_client_player.set("_remote_encounter_target", _toilet)
		_client_player.set("_remote_encounter_starter", &"start_toilet_minigame")


func _make_player(node_name: String, peer_id: int) -> CharacterBody3D:
	var instance := (load("res://player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	instance.name = node_name
	instance.owner_peer_id = peer_id
	return instance


func _process(delta: float) -> bool:
	if _done or not is_instance_valid(_client_player):
		return false
	_elapsed += delta

	if not _is_client:
		if _client_peer_id > 0:
			_host_player.call("_send_network_state", _client_peer_id)
			_client_player.call("_send_network_state", _client_peer_id)
		if FileAccess.file_exists(RESULT_PATH):
			_done = true
			var verdict := FileAccess.get_file_as_string(RESULT_PATH).strip_edges()
			if verdict != "PASS":
				return _fail("the client reported: " + verdict)
			if not is_equal_approx(_host_player.get_bladder(), HOST_BLADDER):
				return _fail("the client's toilet report changed the host bladder")
			if not is_zero_approx(_client_player.get_bladder()):
				return _fail("the server did not apply the client's completed toilet result")
			print("Bladder multiplayer pair smoke test passed: owner-only snapshots and toilet acknowledgement stayed isolated per player.")
			quit()
			return false
		if _elapsed >= TIMEOUT:
			return _fail("The client never reported within %.0f seconds." % TIMEOUT)
		return false

	if not _report_sent and _elapsed >= 1.0:
		_dev_tools.call("_bind_bladder_slider")
		if _dev_tools.call("_player") != _client_player:
			return _write_client_result("DevTools selected the host replica instead of the local player")
		if _dev_tools.get("_bound_bladder") != _client_player.bladder:
			return _write_client_result("DevTools bladder slider bound to another player")
		if not is_equal_approx(_client_player.get_bladder(), CLIENT_BLADDER):
			return _write_client_result(
				"local player received %.2f instead of its own %.2f"
				% [_client_player.get_bladder(), CLIENT_BLADDER]
			)
		if not is_equal_approx(_host_player.get_bladder(), REMOTE_SENTINEL):
			return _write_client_result(
				"host bladder leaked into the client replica: %.2f"
				% _host_player.get_bladder()
			)
		_report_sent = true
		_client_player.set_bladder(0.0)
		_client_player.call("_on_toilet_session_ended", true, _toilet)

	if _report_sent \
		and not bool(_client_player.get("_bladder_report_pending")):
		if not is_zero_approx(_client_player.get_bladder()):
			return _write_client_result("completed toilet value was overwritten by a snapshot")
		if not is_equal_approx(_host_player.get_bladder(), REMOTE_SENTINEL):
			return _write_client_result("another player's bladder overwrote the remote sentinel")
		return _write_client_result("PASS")

	if _elapsed >= TIMEOUT - 1.0:
		return _write_client_result("toilet result was never acknowledged")
	return false


func _write_client_result(result: String) -> bool:
	_done = true
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("Client could not write its verdict.")
	file.store_string(result)
	file.close()
	quit(0 if result == "PASS" else 1)
	return false


func _fail(message: String) -> bool:
	_done = true
	if _client_pid > 0:
		OS.kill(_client_pid)
	push_error("Bladder multiplayer pair smoke test failed: " + message)
	print("Bladder multiplayer pair smoke test FAILED: " + message)
	quit(1)
	return false
