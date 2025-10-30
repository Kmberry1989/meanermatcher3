extends Node2D

var _is_local: bool = false
var _speed: float = 240.0

func set_is_local(v: bool) -> void:
    _is_local = v
    # Tint local differently
    var cr := $Marker as ColorRect
    if cr != null:
        cr.color = Color(0.3, 1.0, 0.4, 0.9) if _is_local else Color(0.2, 0.8, 1.0, 0.9)

func _process(delta: float) -> void:
    if not _is_local:
        return
    var mv := Vector2.ZERO
    if Input.is_action_pressed("ui_left"): mv.x -= 1
    if Input.is_action_pressed("ui_right"): mv.x += 1
    if Input.is_action_pressed("ui_up"): mv.y -= 1
    if Input.is_action_pressed("ui_down"): mv.y += 1
    if mv.length() > 0.0:
        position += mv.normalized() * _speed * delta
        _send_state()

func apply_remote_state(pos: Vector2) -> void:
    if _is_local:
        return
    position = pos

func _send_state() -> void:
    if Engine.has_singleton("WebSocketClient") or (typeof(WebSocketClient) != TYPE_NIL):
        WebSocketClient.send_state({"id": WebSocketClient.get_player_id(), "x": position.x, "y": position.y})

