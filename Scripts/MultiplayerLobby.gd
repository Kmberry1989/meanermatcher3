extends Control

onready var status_label: Label = $Panel/VBox/Status
onready var btn_find_match: Button = $Panel/VBox/Buttons/FindMatch
onready var btn_cancel_match: Button = $Panel/VBox/Buttons/CancelMatch
onready var btn_leave: Button = $Panel/VBox/Buttons/Leave
onready var btn_ready: Button = $Panel/VBox/Buttons/Ready
onready var btn_start: Button = $Panel/VBox/Buttons/Start
onready var mode_opt: OptionButton = $Panel/VBox/ModeHBox/Mode
onready var target_spin: SpinBox = $Panel/VBox/TargetHBox/Target

var _joined: bool = false
var _finding_match: bool = false

func _ready() -> void:
	var url: String = ProjectSettings.get_setting("simple_multiplayer/server_url", "ws://127.0.0.1:9090")
	$Panel/VBox/Url.text = "Server: " + url
	_wire_buttons()
	_update_buttons()
	if Engine.has_singleton("WebSocketClient") or (typeof(WebSocketClient) != TYPE_NIL):
		WebSocketClient.connection_succeeded.connect(_on_connected)
		WebSocketClient.connection_failed.connect(_on_connection_failed)
		WebSocketClient.disconnected.connect(_on_disconnected)
		WebSocketClient.room_joined.connect(_on_room_joined)
		WebSocketClient.start_game.connect(_on_start_game)
		WebSocketClient.match_found.connect(_on_match_found)

	var return_button = Button.new()
	return_button.text = "Return to Main Menu"
	$Panel/VBox.add_child(return_button)
	return_button.pressed.connect(_on_return_to_menu_pressed)

func _on_return_to_menu_pressed():
	if _joined:
		WebSocketClient.leave_room()
	
	if WebSocketClient.is_ws_connected():
		WebSocketClient.disconnect_from_server()

	get_tree().change_scene_to_file("res://Scenes/Menu.tscn")

func _wire_buttons() -> void:
	btn_find_match.pressed.connect(_on_find_match)
	btn_cancel_match.pressed.connect(_on_cancel_match)
	btn_leave.pressed.connect(_on_leave)
	btn_ready.pressed.connect(_on_ready)
	btn_start.pressed.connect(_on_start)

func _update_buttons() -> void:
	btn_find_match.disabled = _finding_match or _joined
	btn_cancel_match.disabled = not _finding_match
	btn_leave.disabled = not _joined
	btn_ready.disabled = not _joined
	btn_start.disabled = not _joined

func _on_connected() -> void:
	status_label.text = "Connected."

func _on_connection_failed() -> void:
	status_label.text = "Failed to connect."

func _on_disconnected() -> void:
	status_label.text = "Disconnected."
	_joined = false
	_finding_match = false
	_update_buttons()

func _on_find_match() -> void:
	_finding_match = true
	_update_buttons()
	var m := mode_opt.get_selected_id()
	var mode := ("vs" if m == 1 else "coop")
	WebSocketClient.find_match({"mode": mode})
	status_label.text = "Finding match..."

func _on_cancel_match() -> void:
	_finding_match = false
	_update_buttons()
	WebSocketClient.cancel_match()
	status_label.text = "Matchmaking canceled."

func _on_leave() -> void:
	WebSocketClient.leave_room()
	status_label.text = "Left room."
	_joined = false
	_update_buttons()

func _on_ready() -> void:
	WebSocketClient.send_ready()
	status_label.text = "Ready. Waiting for others..."

func _on_start() -> void:
	var m := mode_opt.get_selected_id()
	var mode := ("vs" if m == 1 else "coop")
	var target := int(target_spin.value)
	var seed_value := int(Time.get_unix_time_from_system())
	WebSocketClient.request_start_game({"mode": mode, "target": target, "seed": seed_value})
	status_label.text = "Starting (" + mode + ")..."

func _on_match_found(code: String, player_id: String) -> void:
	_on_room_joined(code, player_id)

func _on_room_joined(code: String, _id: String) -> void:
	status_label.text = "Joined room: " + code
	_joined = true
	_finding_match = false
	_update_buttons()

func _on_start_game() -> void:
	status_label.text = "Game starting..."
	# Transition to the actual game scene
	get_tree().change_scene_to_file("res://Scenes/Game.tscn")
