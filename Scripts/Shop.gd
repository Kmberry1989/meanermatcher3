extends Control

onready var back_button = Button.new()
onready var coins_label = Label.new()

var _cards_row
var _scroll
var _prev_button
var _next_button
var _dots
var _snap_timer
var _is_animating = false
var _frame_ids = []

const BADGE_H := 24
const CARD_W := 220.0
const CARD_SEP := 10.0
const THUMB_H := 320.0 # normalized preview area height

var frames_catalog := {
	"frame_2": {"price": 100, "display": "avatar_frame_2.png"},
	"frame_3": {"price": 150, "display": "avatar_frame_3.png"},
	"frame_4": {"price": 200, "display": "avatar_frame_4.png"},
	"frame5":  {"price": 220, "display": "avatar_frame5.png"},
	"frame6":  {"price": 240, "display": "avatar_frame6.png"},
	"frame7":  {"price": 260, "display": "avatar_frame7.png"},
	"frame8":  {"price": 280, "display": "avatar_frame8.png"},
	"frame9":  {"price": 300, "display": "avatar_frame9.png"},
	"frame10": {"price": 350, "display": "avatar_frame10.png"},
	"frame11": {"price": 400, "display": "avatar_frame11.png"}
}

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_dynamic_frames()
	_build_ui()
	if Engine.has_singleton("PlayerManager") == false and typeof(PlayerManager) != TYPE_OBJECT:
		pass
	else:
		if PlayerManager != null:
			PlayerManager.connect("coins_changed", Callable(self, "_on_coins_changed"))
			PlayerManager.connect("frame_changed", Callable(self, "_on_frame_changed"))
	_refresh()
	call_deferred("_post_build_layout")

func _build_ui():
	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0
	vbox.anchor_right = 1
	vbox.anchor_top = 0
	vbox.anchor_bottom = 1
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGN_CENTER
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var title := Label.new()
	title.text = "Avatar Frame Shop"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	coins_label.align = Label.ALIGN_CENTER
	coins_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(coins_label)

	var nav := HBoxContainer.new()
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_theme_constant_override("separation", 6)
	vbox.add_child(nav)

	_prev_button = Button.new()
	_prev_button.text = "\u25C0"
	_prev_button.custom_minimum_size = Vector2(40, 40)
	_prev_button.connect("pressed", Callable(self, "_on_prev_pressed"))
	nav.add_child(_prev_button)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(_scroll)
	var bar := _scroll.get_h_scroll_bar()
	if bar:
		bar.connect("value_changed", Callable(self, "_on_scroll_changed"))

	_next_button = Button.new()
	_next_button.text = "\u25B6"
	_next_button.custom_minimum_size = Vector2(40, 40)
	_next_button.connect("pressed", Callable(self, "_on_next_pressed"))
	nav.add_child(_next_button)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 10)
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_cards_row)

	_frame_ids = _get_sorted_frame_ids()
	for frame_id in _frame_ids:
		var card := _make_frame_card(frame_id)
		_cards_row.add_child(card)

	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 6)
	_dots.alignment = BoxContainer.ALIGN_CENTER
	vbox.add_child(_dots)

	back_button.text = "Back"
	back_button.connect("pressed", Callable(self, "_on_back_pressed"))
	vbox.add_child(back_button)

func _post_build_layout():
	if not is_inside_tree():
		return
	_update_card_widths()
	_rebuild_dots()
	_update_pager_by_scroll()

# Scan res://Assets/Visuals for avatar_*.png and add frames not already listed
func _load_dynamic_frames():
	var root := "res://Assets/Visuals"
	var d := Directory.new()
	if d.open(root) != OK:
		return
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.to_lower().ends_with(".png"):
			if fname.begins_with("avatar_"):
				# Skip default frame provided for free
				if fname == "avatar_frame_2.png":
					fname = d.get_next()
					continue
				var id := fname.get_basename().replace("avatar_", "")
				# Normalize common "frameX" names to match existing style
				id = id
				if not frames_catalog.has(id):
					# Default price for discovered frames
					var price := 250
					# If name contains a number, scale price a bit
					var m := RegEx.new()
					m.compile(".*?(\d+)")
					var res := m.search(id)
					if res != null:
						var n := int(res.get_string(1))
						price = max(150, 100 + n * 20)
					frames_catalog[id] = {"price": price, "display": fname}
		fname = d.get_next()
	d.list_dir_end()

func _make_frame_card(frame_id):
	var data = frames_catalog[frame_id]
	var price = data["price"]
	var display_path = "res://Assets/Visuals/" + String(data["display"]) # filename only

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 480)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGN_CENTER
	panel.add_child(vb)

	var thumb := Control.new()
	# Normalize preview area so all frames appear consistent and centered
	thumb.custom_minimum_size = Vector2(0, THUMB_H)
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(thumb)

	var tex := TextureRect.new()
	tex.texture = load(display_path)
	# Keep aspect and center; rely on preview area height. Use a widely-supported expand mode.
	tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_preset(Control.PRESET_MODE_FULL_RECT)
	tex.tooltip_text = ""
	thumb.add_child(tex)

	var badge_bg := ColorRect.new()
	badge_bg.color = Color(0, 0, 0, 0.6)
	badge_bg.custom_minimum_size = Vector2(0, BADGE_H)
	vb.add_child(badge_bg)

	var badge := Label.new()
	badge.align = Label.ALIGN_CENTER
	badge.valign = Label.ALIGN_CENTER
	badge.custom_minimum_size = Vector2(0, BADGE_H)
	badge.add_theme_font_size_override("font_size", 14)
	badge.set_anchors_preset(Control.PRESET_MODE_FULL_RECT)
	badge_bg.add_child(badge)

	var name_label := Label.new()
	name_label.text = frame_id.capitalize()
	name_label.align = Label.ALIGN_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	vb.add_child(name_label)

	var price_label := Label.new()
	price_label.text = "Price: %d" % price
	price_label.align = Label.ALIGN_CENTER
	price_label.add_theme_font_size_override("font_size", 18)
	vb.add_child(price_label)

	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(btn)

	var owned = false
	if typeof(PlayerManager) == TYPE_OBJECT and PlayerManager != null:
		owned = frame_id in (PlayerManager.player_data.get("unlocks", {}).get("frames", []))
	if owned and typeof(PlayerManager) == TYPE_OBJECT:
		if PlayerManager.get_current_frame() == frame_id:
			btn.text = "Equipped"
			btn.disabled = true
			badge.text = "Equipped"
			badge_bg.color = Color(0.2, 0.6, 1.0, 0.7)
		else:
			btn.connect("pressed", self, "_on_equip_pressed", [frame_id])
		else:
			btn.text = "Equip"
			btn.disabled = false
			badge.text = "Owned"
			badge_bg.color = Color(0.2, 0.8, 0.2, 0.7)
	else:
		btn.text = "Buy"
		if typeof(PlayerManager) == TYPE_OBJECT and PlayerManager != null:
			btn.disabled = not PlayerManager.can_spend(price)
			btn.connect("pressed", self, "_on_buy_pressed", [price, frame_id])
		badge.text = "Price: %d" % price
		badge_bg.color = Color(1.0, 0.84, 0.0, 0.7)

	return panel
func _refresh():
	if typeof(PlayerManager) == TYPE_OBJECT and PlayerManager != null:
		coins_label.text = "Coins: %d" % PlayerManager.get_coins()
	else:
		coins_label.text = ""
	_frame_ids = _get_sorted_frame_ids()
	if is_instance_valid(_cards_row):
		for c in _cards_row.get_children():
			c.queue_free()
		for frame_id in _frame_ids:
			_cards_row.add_child(_make_frame_card(frame_id))
	_rebuild_dots()
	_update_pager_by_scroll()

func _get_sorted_frame_ids():
	var ids = []
	if typeof(PlayerManager) != TYPE_OBJECT or PlayerManager == null:
		for k in frames_catalog.keys():
			ids.append(k)
		return ids
	var owned_frames = PlayerManager.player_data.get("unlocks", {}).get("frames", [])
	var equipped: String = str(PlayerManager.get_current_frame())
	var owned_list: Array = []
	var unowned_list: Array = []
	for k in frames_catalog.keys():
		if k == equipped:
			continue
		if k in owned_frames:
			owned_list.append(k)
		else:
			unowned_list.append(k)
	_sort_by_price(owned_list)
	_sort_by_price(unowned_list)
	if equipped in frames_catalog:
		ids.append(equipped)
	for a in owned_list:
		ids.append(a)
	for b in unowned_list:
		ids.append(b)
	return ids

func _sort_by_price(arr: Array) -> void:
	for i in range(arr.size()):
		var min_i = i
		for j in range(i + 1, arr.size()):
			if int(frames_catalog[arr[j]]["price"]) < int(frames_catalog[arr[min_i]]["price"]):
				min_i = j
		if min_i != i:
			var tmp = arr[i]
			arr[i] = arr[min_i]
			arr[min_i] = tmp

func _on_prev_pressed():
	_scroll_by_pages(-1)

func _on_next_pressed():
	_scroll_by_pages(1)

func _scroll_by_pages(dir: int):
	if _scroll == null:
		return
	var bar := _scroll.get_h_scroll_bar()
	if bar == null:
		return
	var step := _card_step()
	var page_cards: int = int(max(1, int(floor(bar.page / step))))
	var current := int(round(bar.value / step))
	_animate_scroll_to(current + dir * page_cards)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://Scenes/Menu.tscn")

func _on_coins_changed(_amt):
	_refresh()

func _on_frame_changed(_frame):
	_refresh()

func _on_scroll_changed(_v):
	if not is_inside_tree() or _scroll == null:
		return
	if _is_animating:
		return
	if _snap_timer == null:
		_snap_timer = Timer.new()
		_snap_timer.one_shot = true
		add_child(_snap_timer)
		_snap_timer.connect("timeout", Callable(self, "_snap_to_nearest"))
	_snap_timer.start(0.2)
	_update_pager_by_scroll()

func _snap_to_nearest():
	if not is_inside_tree():
		return
	var bar := _scroll.get_h_scroll_bar()
	if bar == null:
		return
	var step := _card_step()
	if step <= 0:
		return
	var idx := int(round(bar.value / step))
	_animate_scroll_to(idx)

func _animate_scroll_to(index: int):
	if not is_inside_tree():
		return
	var bar := _scroll.get_h_scroll_bar()
	if bar == null:
		return
	var step := _card_step()
	var max_index: int = int(max(0, _frame_ids.size() - 1))
	index = int(clamp(index, 0, max_index))
	var target: float = float(clamp(index * step, 0.0, float(bar.max_value)))
	_is_animating = true
	var t := get_tree().create_tween()
	t.tween_property(bar, "value", target, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.finished.connect(func():
		_is_animating = false
		_highlight_dot(index)
	)

func _card_step() -> float:
	var step := CARD_W + CARD_SEP
	if is_instance_valid(_cards_row) and _cards_row.get_child_count() > 0:
		var first := _cards_row.get_child(0)
		step = float(first.size.x) + CARD_SEP
		if step <= 0:
			step = CARD_W + CARD_SEP
	return step

func _rebuild_dots():
	if _dots == null:
		return
	for c in _dots.get_children():
		c.queue_free()
	for i in range(_frame_ids.size()):
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.color = Color(0.5, 0.5, 0.5, 0.9)
		_dots.add_child(dot)
	_update_pager_by_scroll()

func _update_pager_by_scroll():
	var bar := _scroll.get_h_scroll_bar()
	if bar == null or _dots == null:
		return
	var step := _card_step()
	var idx := int(round(bar.value / step))
	_highlight_dot(idx)

func _highlight_dot(index: int):
	if _dots == null:
		return
	for i in range(_dots.get_child_count()):
		var c := _dots.get_child(i)
		if i == index:
			c.color = Color(1, 1, 1, 1)
			c.custom_minimum_size = Vector2(10, 10)
		else:
			c.color = Color(0.5, 0.5, 0.9, 0.9)
			c.custom_minimum_size = Vector2(8, 8)

func _update_card_widths():
	if not is_inside_tree():
		return
	if _scroll == null or _cards_row == null:
		return
	var avail_w: float = _scroll.size.x
	var avail_h: float = _scroll.size.y
	if avail_w <= 0.0 or avail_h <= 0.0:
		return
	for child in _cards_row.get_children():
		if child is Control:
			var panel := child as Control
			panel.custom_minimum_size = Vector2(avail_w, avail_h)

func _notification(what):
	if what == Control.NOTIFICATION_RESIZED:
		_update_card_widths()

func _on_equip_pressed(frame_id):
	PlayerManager.set_current_frame(frame_id)
	_refresh()