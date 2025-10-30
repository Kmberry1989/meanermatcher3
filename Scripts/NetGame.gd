extends Node

var mode: String = "" # "coop" or "vs"
var target: int = 0
var seed: int = 0

var _scores: Dictionary = {} # id -> score
var _team_score: int = 0
var _hud: Control = null
var _label: Label = null

func _ready() -> void:
	# Pull session config from MultiplayerManager (autoload)
	if Engine.has_singleton("MultiplayerManager") or (typeof(MultiplayerManager) != TYPE_NIL):
		mode = String(MultiplayerManager.session_mode)
		target = int(MultiplayerManager.session_target)
		seed = int(MultiplayerManager.session_seed)

	# If not in a multiplayer game, do nothing.
	if mode != "coop" and mode != "vs":
		print("NetGame: Not in a multiplayer mode ('%s'), disabling." % mode)
		return

	_build_hud()
	_connect_net()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NetHUD"
	add_child(layer)
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.0
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.0
	panel.offset_left = -160
	panel.offset_right = 160
	panel.offset_top = 8
	panel.offset_bottom = 48
	layer.add_child(panel)
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(lbl)
	_hud = panel
	_label = lbl
	_update_hud()

func _connect_net() -> void:
	if Engine.has_singleton("WebSocketClient") or (typeof(WebSocketClient) != TYPE_NIL):
		if not WebSocketClient.game_event.is_connected(_on_game_event):
			WebSocketClient.game_event.connect(_on_game_event)

func _on_game_event(payload: Dictionary) -> void:
	if String(payload.get("type", "")) != "game":
		return
	var ev := String(payload.get("event", ""))
	if ev == "score":
		var pid := String(payload.get("id", ""))
		var delta := int(payload.get("delta", 0))
		if pid == "":
			return
		_scores[pid] = int(_scores.get(pid, 0)) + delta
		_team_score += delta
		_update_hud()
		_check_win()

func _update_hud() -> void:
	if _label == null:
		return
	if mode == "vs":
		# Show each player's score (IDs truncated)
		var parts: Array = []
		for k in _scores.keys():
			var short_id: String = String(k)
			if short_id.length() > 4:
				short_id = short_id.substr(max(0, short_id.length() - 4))
			parts.append("P" + short_id + ": " + str(_scores[k]))
		if parts.is_empty():
			_label.text = "VS: waiting for scores..." + (" (to " + str(target) + ")" if target > 0 else "")
		else:
			_label.text = "VS " + ("(to " + str(target) + ") " if target > 0 else "") + " | ".join(parts)
	else:
		_label.text = "CO-OP Score: " + str(_team_score) + (" / " + str(target) if target > 0 else "")

func _check_win() -> void:
	if target <= 0:
		return
	if mode == "vs":
		for pid in _scores.keys():
			if int(_scores[pid]) >= target:
				_announce_winner("Player " + pid + " wins!")
				break
	else:
		if _team_score >= target:
			_announce_winner("Team reached " + str(target) + "!")

func _announce_winner(msg: String) -> void:
	if _hud == null:
		return
	var popup := AcceptDialog.new()
	popup.dialog_text = msg
	_hud.add_child(popup)
	popup.popup_centered_ratio(0.3)

func report_local_score(delta: int) -> void:
	# Send to peers and self update
	if delta <= 0:
		return
	if Engine.has_singleton("WebSocketClient") or (typeof(WebSocketClient) != TYPE_NIL):
		WebSocketClient.send_game_event("score", {"delta": delta})
