extends Node

@export var player_scene_path: String = "res://Scenes/NetPlayer.tscn"

var _players: Dictionary = {}
var _local_id: String = ""
var session_mode: String = ""
var session_target: int = 0
var session_seed: int = 0

func _ready() -> void:
	if Engine.has_singleton("WebSocketClient") or (typeof(WebSocketClient) != TYPE_NIL):
		WebSocketClient.connection_succeeded.connect(_on_connected)
		WebSocketClient.room_joined.connect(_on_room_joined)
		WebSocketClient.room_state.connect(_on_room_state)
		WebSocketClient.player_joined.connect(_on_player_joined)
		WebSocketClient.player_left.connect(_on_player_left)
		WebSocketClient.message_received.connect(_on_message)
		WebSocketClient.start_game.connect(_on_start_game)
		
func _on_connected() -> void:
	# No-op
	pass

func _on_room_joined(_code: String, id: String) -> void:
	_local_id = id

func _on_room_state(players: Array) -> void:
	# Spawn any listed players (including local)
	for pid in players:
		_ensure_player(String(pid))

func _on_player_joined(pid: String) -> void:
	_ensure_player(pid)

func _on_player_left(pid: String) -> void:
	if _players.has(pid):
		var n: Node = _players[pid]
		if is_instance_valid(n):
			n.queue_free()
		_players.erase(pid)

func _on_start_game(payload: Dictionary = {}) -> void:
	# Ensure all current players exist
	if Engine.has_singleton("WebSocketClient") or (typeof(WebSocketClient) != TYPE_NIL):
		# Spawn local player explicitly
		if _local_id != "":
			_ensure_player(_local_id)
	# Stash session config
	session_mode = String(payload.get("mode", session_mode if session_mode != "" else "coop"))
	session_target = int(payload.get("target", session_target if session_target > 0 else 100))
	session_seed = int(payload.get("seed", session_seed if session_seed > 0 else Time.get_unix_time_from_system()))

func _on_message(msg: Dictionary) -> void:
	var t = String(msg.get("type", ""))
	if t == "state":
		var pid := String(msg.get("id", ""))
		if pid == "":
			return
		var pos: Vector2 = Vector2(msg.get("x", 0.0), msg.get("y", 0.0))
		var p = _players.get(pid, null)
		if p != null and is_instance_valid(p):
			if p.has_method("apply_remote_state"):
				p.call("apply_remote_state", pos)

func _ensure_player(pid: String) -> void:
	if _players.has(pid) and is_instance_valid(_players[pid]):
		return
	var cont := _get_player_container()
	if cont == null:
		push_warning("MultiplayerManager: Node 'PlayerContainer' not found in the current scene.")
		return
	var scene: PackedScene = load(player_scene_path)
	if scene == null:
		push_error("MultiplayerManager: player scene missing at: " + player_scene_path)
		return
	var inst = scene.instantiate()
	inst.name = "Player_" + pid
	cont.add_child(inst)
	var local := (pid == _local_id)
	if inst.has_method("set_is_local"):
		inst.call("set_is_local", local)
	_players[pid] = inst

func _get_player_container() -> Node:
	var scene_root := get_tree().get_current_scene()
	if scene_root == null:
		return null
	var cont := scene_root.get_node_or_null("PlayerContainer")
	if cont == null:
		cont = scene_root.find_child("PlayerContainer", true, false)
	return cont
