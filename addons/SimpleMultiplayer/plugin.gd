@tool
extends EditorPlugin

func _enable_plugin() -> void:
    add_autoload_singleton("WebSocketClient", "res://addons/SimpleMultiplayer/autoload/websocket_client.gd")
    add_autoload_singleton("MultiplayerManager", "res://addons/SimpleMultiplayer/autoload/multiplayer_manager.gd")
    if not ProjectSettings.has_setting("simple_multiplayer/server_url"):
        ProjectSettings.set_setting("simple_multiplayer/server_url", "ws://127.0.0.1:9090")
    ProjectSettings.save()

func _disable_plugin() -> void:
    remove_autoload_singleton("WebSocketClient")
    remove_autoload_singleton("MultiplayerManager")

