extends Node

# Emitted when the server confirms a match has been found and the game should start.
signal game_started
# Emitted when the initial WebSocket connection fails.
signal connection_failed
# Emitted when the WebSocket connection is successfully established.
signal connection_succeeded
# Emitted when the connection to the server is lost.
signal server_disconnected
# Emitted when the opponent's score is received from the server.
signal opponent_score_updated(score)
# Emitted when the server tells us we are waiting for an opponent.
signal waiting_for_opponent

var peer: WebSocketPeer

func _process(_delta):
	# We must poll the peer regularly to process incoming messages.
	if peer == null:
		return
	peer.poll()
	var state = peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while peer.get_available_packet_count() > 0:
			var message = peer.get_packet().get_string_from_utf8()
			var data = JSON.parse_string(message)
			if data and data.has("type"):
				handle_server_message(data)
	elif state == WebSocketPeer.STATE_CLOSED:
		server_disconnected_handler()

# Handles the JSON messages received from the server.
func handle_server_message(data):
	var type = data.get("type")
	if type == "game_started":
		game_started.emit()
	elif type == "waiting":
		waiting_for_opponent.emit()
	elif type == "opponent_disconnected":
		server_disconnected_handler()
	elif type == "score_update":
		opponent_score_updated.emit(data.get("score", 0))

# Connects to the given WebSocket server URL.
func connect_to_server(url):
	peer = WebSocketPeer.new()
	var err = peer.connect_to_url(url)
	if err != OK:
		print("Failed to create WebSocket client.")
		connection_failed.emit()
		return
	# Set a timer to check for successful connection.
	get_tree().create_timer(0.1).connect("timeout", func(): 
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			connection_succeeded.emit()
	)

# Sends the player's score to the server.
func send_score_update(score):
	if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var payload = {
			"type": "score_update",
			"score": score
		}
		peer.send_text(JSON.stringify(payload))

# Handles disconnection from the server.
func server_disconnected_handler():
	if peer != null:
		peer.close()
		peer = null
		print("Disconnected from server.")
		server_disconnected.emit()

func _exit_tree():
	if peer != null:
		peer.close()
		peer = null
