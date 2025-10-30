extends Panel

onready var tab_container = $VBoxContainer/TabContainer
onready var trophy_grid = $VBoxContainer/TabContainer/Trophies/Scroll/TrophyGrid
onready var viewer_overlay = $ViewerOverlay
onready var viewer_image = $ViewerOverlay/Center/VBox/LargeImage
onready var viewer_label = $ViewerOverlay/Center/VBox/ItemLabel
var viewer_desc = null

var achievements = []
var current_index = -1

var _drag_active = false
var _drag_start = Vector2.ZERO

func _ready():
    load_achievements()
    var frames_tab = _get_node_or_null(tab_container, "Frames")
    if frames_tab:
        frames_tab.hide()
        frames_tab.queue_free()
    var root_vbox = tab_container.get_parent()
    if root_vbox and root_vbox is VBoxContainer:
        root_vbox.alignment = BoxContainer.ALIGN_CENTER
        var back_btn = _get_node_or_null(root_vbox, "BackButton")
        if back_btn == null:
            back_btn = Button.new()
            back_btn.name = "BackButton"
            root_vbox.add_child(back_btn)
        back_btn.text = "Back"
        back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        if not back_btn.is_connected("pressed", self, "_on_back_button_pressed"):
            back_btn.connect("pressed", self, "_on_back_button_pressed")
    if is_instance_valid(viewer_label):
        var vb = viewer_label.get_parent()
        if vb:
            viewer_desc = _get_node_or_null(vb, "DescLabel")
            if viewer_desc == null:
                viewer_desc = Label.new()
                viewer_desc.name = "DescLabel"
                vb.add_child(viewer_desc)
            viewer_desc.align = Label.ALIGN_CENTER
            viewer_desc.autowrap = true

func load_achievements():
    achievements.clear()
    for child in trophy_grid.get_children():
        child.queue_free()

    var achievement_manager = _get_achievement_manager()
    if achievement_manager == null:
        return

    var achievement_list = achievement_manager.get_achievements()
    for achievement_id in achievement_list:
        var achievement_res = achievement_manager.get_achievement_resource(achievement_id)
        if typeof(achievement_res) == TYPE_OBJECT and achievement_res != null:
            var id = str(achievement_res.id)
            var display = str(achievement_res.trophy_name)
            var unlocked = achievement_manager.is_unlocked(id)

            var unlocked_icon = achievement_res.unlocked_icon
            var locked_icon = achievement_res.locked_icon
            var display_icon = unlocked_icon if unlocked else locked_icon
            if display_icon == null:
                display_icon = unlocked_icon

            var item = {
                "id": id,
                "unlocked_icon": unlocked_icon,
                "locked_icon": locked_icon,
                "name": display,
                "unlocked": unlocked,
                "description": achievement_res.description
            }
            var idx = achievements.size()
            achievements.append(item)
            _add_thumbnail(idx, display_icon, display, unlocked)

# Frames are no longer shown here; Showcase is trophy-only

func _add_thumbnail(index, tex, label_text, unlocked):
    var vb = VBoxContainer.new()
    vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var thumb = TextureRect.new()
    thumb.texture = tex
    thumb.rect_min_size = Vector2(128, 128)
    thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    thumb.mouse_filter = Control.MOUSE_FILTER_STOP
    thumb.connect("gui_input", self, "_on_thumbnail_gui_input", [index])
    var lbl = Label.new()
    lbl.text = label_text
    lbl.align = Label.ALIGN_CENTER
    var status_text = "UNLOCKED"
    if not unlocked:
        status_text = "LOCKED"
    lbl.tooltip_text = status_text
    thumb.tooltip_text = status_text
    vb.add_child(thumb)
    vb.add_child(lbl)
    trophy_grid.add_child(vb)

func _open_viewer(index):
    current_index = index
    _update_viewer()
    viewer_overlay.show()

func _close_viewer():
    viewer_overlay.hide()
    current_index = -1

func _update_viewer():
    if current_index < 0:
        return
    if current_index >= achievements.size():
        return
    var item = achievements[current_index]
    var unlocked = bool(item.get("unlocked", false))
    var display_icon = unlocked and item.get("unlocked_icon") or item.get("locked_icon")
    if display_icon == null:
        display_icon = item.get("unlocked_icon")
    viewer_image.texture = display_icon
    var status_text = "UNLOCKED"
    if not unlocked:
        status_text = "LOCKED"
    viewer_label.text = item.get("name", "")
    if viewer_desc:
        viewer_desc.text = str(item.get("description", ""))
        viewer_desc.tooltip_text = status_text
    viewer_label.tooltip_text = status_text
    viewer_image.tooltip_text = status_text

func _viewer_next():
    if achievements.size() == 0:
        return
    current_index = (current_index + 1) % achievements.size()
    _update_viewer()

func _viewer_prev():
    if achievements.size() == 0:
        return
    current_index = (current_index - 1 + achievements.size()) % achievements.size()
    _update_viewer()

func _input(event):
    if not viewer_overlay.is_visible():
        return
    if event is InputEventMouseButton:
        if event.button_index == BUTTON_LEFT:
            if event.pressed:
                _drag_active = true
                _drag_start = event.position
            else:
                if _drag_active:
                    var delta = event.position - _drag_start
                    _drag_active = false
                    if abs(delta.x) > 60:
                        if delta.x > 0:
                            _viewer_prev()
                        else:
                            _viewer_next()
                    else:
                        _viewer_next()
    elif event is InputEventScreenTouch:
        if event.pressed:
            _drag_active = true
            _drag_start = event.position
        else:
            if _drag_active:
                var delta = event.position - _drag_start
                _drag_active = false
                if abs(delta.x) > 60:
                    if delta.x > 0:
                        _viewer_prev()
                    else:
                        _viewer_next()
                else:
                    _viewer_next()
    elif event.is_action_pressed("ui_right"):
        _viewer_next()
    elif event.is_action_pressed("ui_left"):
        _viewer_prev()
    elif event.is_action_pressed("ui_cancel"):
        _close_viewer()

func _on_back_button_pressed():
    get_tree().change_scene("res://Scenes/Menu.tscn")

func _on_thumbnail_gui_input(event, index):
    if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
        _open_viewer(index)

func _get_node_or_null(base, path):
    if base == null:
        return null
    if base.has_node(path):
        return base.get_node(path)
    return null

func _get_achievement_manager():
    if has_node("/root/AchievementManager"):
        return get_node("/root/AchievementManager")
    if Engine.has_singleton("AchievementManager"):
        return Engine.get_singleton("AchievementManager")
    return null
