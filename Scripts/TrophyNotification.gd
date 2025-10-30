extends PanelContainer

onready var icon = $HBoxContainer/Icon
onready var trophy_name = $HBoxContainer/VBoxContainer/TrophyName
var _tween = null

func _ready():
	hide()

func show_notification(trophy_resource):
        icon.texture = trophy_resource.unlocked_icon
        trophy_name.text = trophy_resource.trophy_name

        show()
        var start_x = 250
        var start_pos = rect_position
        start_pos.x = start_x
        rect_position = start_pos

        if _tween != null:
                _tween.stop_all()
                _tween.queue_free()

        _tween = Tween.new()
        add_child(_tween)
        _tween.interpolate_property(self, "rect_position:x", start_x, 0, 0.5, Tween.TRANS_QUINT, Tween.EASE_OUT)
        _tween.interpolate_property(self, "rect_position:x", 0, 250, 0.5, Tween.TRANS_QUINT, Tween.EASE_IN, 3.5)
        _tween.interpolate_callback(self, 4.0, "_on_tween_finished")
        _tween.start()

func _on_tween_finished():
        hide()
        if _tween != null:
                _tween.queue_free()
                _tween = null


