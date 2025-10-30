extends Control

onready var player_name_label = $MarginContainer/HBoxContainer/PlayerInfo/HBox/AvatarFrame/PlayerNameLabel
onready var level_label = $MarginContainer/HBoxContainer/PlayerInfo/HBox/AvatarFrame/LevelLabel
onready var xp_label = $MarginContainer/HBoxContainer/PlayerInfo/HBox/AvatarFrame/XpLabel
onready var coins_label = $MarginContainer/HBoxContainer/PlayerInfo/HBox/AvatarFrame/CoinsLabel
# Pause button is looked up safely at runtime to avoid errors when missing
onready var frame_sprite = $MarginContainer/HBoxContainer/PlayerInfo/HBox/AvatarFrame/AvatarFrame2
var _avatar_photo = null

# MEANER METER UI reference
var _meaner_bar = null
var _meaner_label = null

func _ready():
	set_player_name(PlayerManager.get_player_name())
	update_level_label(PlayerManager.get_current_level())
	update_xp_label()
	PlayerManager.connect("level_up", self, "update_level_label")
	PlayerManager.connect("coins_changed", self, "_on_coins_changed")
	PlayerManager.connect("frame_changed", self, "_on_frame_changed")
	_on_coins_changed(PlayerManager.get_coins())
	_apply_current_frame()
	# Add a subtle gold border overlay around the screen while in-game
	_add_gold_border()
	# Add MEANER METER UI and connect signals
	_add_meaner_meter_ui()
	if not PlayerManager.is_connected("meaner_meter_changed", self, "_on_meaner_meter_changed"):
		PlayerManager.connect("meaner_meter_changed", self, "_on_meaner_meter_changed")
	if not PlayerManager.is_connected("meaner_meter_filled", self, "_on_meaner_meter_filled"):
		PlayerManager.connect("meaner_meter_filled", self, "_on_meaner_meter_filled")
	# Initialize bar to current value
	_on_meaner_meter_changed(PlayerManager.get_meaner_meter_current(), PlayerManager.get_meaner_meter_max())
	# Ensure pause/home/shop buttons are clickable above other UI (guard if not found)
	_wire_button("PauseButton", "_on_pause_pressed")
	_wire_button("HomeButton", "_on_home_pressed")
	_wire_button("ShopButton", "_on_shop_pressed")
	# React to avatar changes
	if PlayerManager.has_signal("avatar_changed") and not PlayerManager.is_connected("avatar_changed", self, "_on_avatar_changed"):
		PlayerManager.connect("avatar_changed", self, "_on_avatar_changed")

func set_player_name(p_name):
	player_name_label.text = p_name

func update_level_label(level):
	level_label.text = "Level: " + str(level)

func update_xp_label():
	var current_xp = PlayerManager.get_current_xp()
	var xp_needed = PlayerManager.get_xp_for_next_level()
	xp_label.text = "XP: " + str(current_xp) + "/" + str(xp_needed)

func _on_coins_changed(new_amount):
	coins_label.text = "Coins: " + str(new_amount)

func _on_frame_changed(_frame_name):
	_apply_current_frame()

func _apply_current_frame():
	var frame_name = PlayerManager.get_current_frame()
	var tex_path = _frame_to_texture_path(frame_name)
	var tex = load(tex_path)
	if tex:
		frame_sprite.texture = tex
		frame_sprite.z_index = 1000
		_fit_sprite_to_height(frame_sprite, 160.0)
		_update_avatar_photo()

func _frame_to_texture_path(frame_name):
	if frame_name == "default":
		# Use an existing avatar frame as the default visual now that frame_standard.png is removed
		return "res://Assets/Visuals/avatar_frame_2.png"
	# e.g., frame_2 -> avatar_frame_2.png
	return "res://Assets/Visuals/" + "avatar_" + frame_name + ".png"

func _fit_sprite_to_height(sprite, target_h):
	if sprite.texture == null:
		return
	var h = float(sprite.texture.get_height())
	if h <= 0.0:
		return
	# Do not upscale frames; only downscale if larger than target height
	var sf = target_h / h
	if sf > 1.0:
		sf = 1.0
	sprite.scale = Vector2(sf, sf)

func _ensure_avatar_photo_node():
	if _avatar_photo != null and is_instance_valid(_avatar_photo):
		return
	var parent_node = frame_sprite.get_parent()
	if parent_node == null:
		return
	var existing = parent_node.get_node_or_null("AvatarPhoto")
	if existing != null and existing is Sprite:
		_avatar_photo = existing
		return
	_avatar_photo = Sprite.new()
	_avatar_photo.name = "AvatarPhoto"
	_avatar_photo.z_index = max(frame_sprite.z_index - 1, -100)
	_avatar_photo.position = frame_sprite.position
	parent_node.add_child(_avatar_photo)

func _update_avatar_photo():
	_ensure_avatar_photo_node()
	if _avatar_photo == null:
		return
	var path = "user://avatars/" + PlayerManager.get_player_name() + ".png"
	var tex = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_avatar_photo.texture = tex
	if tex != null:
		# Fit just inside the frame so it doesn't get blocked too much
		_fit_sprite_to_height(_avatar_photo, 150.0)
		_avatar_photo.visible = true
	else:
		_avatar_photo.visible = false

func _on_pause_pressed():
	var root = get_tree().get_current_scene()
	if root == null:
		return
	# Find or create the CanvasLayer to host overlays
	var layer = root.get_node_or_null("CanvasLayer")
	if layer == null:
		layer = root.find("CanvasLayer", true, false)
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "CanvasLayer"
		root.add_child(layer)

	var existing = layer.get_node_or_null("PauseMenu")
	if existing != null:
		if existing.has_method("show_menu"):
			existing.call("show_menu")
		return
	var pause_menu = preload("res://Scenes/PauseMenu.tscn").instance()
	pause_menu.name = "PauseMenu"
	layer.add_child(pause_menu)
	if pause_menu.has_method("show_menu"):
		pause_menu.call("show_menu")

func _unhandled_input(event):
	# Fallback: allow Esc/back to open pause
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == KEY_ESCAPE:
			_on_pause_pressed()

func get_xp_anchor_pos():
	if is_instance_valid(xp_label):
		return xp_label.get_global_transform().origin
	return Vector2.ZERO

func _wire_button(node_name, handler):
	var n = get_node_or_null(node_name)
	if n == null:
		n = find_node(node_name, true, false)
	var c = n as Control
	if c != null:
		c.z_index = 1000
		c.mouse_filter = Control.MOUSE_FILTER_STOP
	var b = n as Button
	if b != null and not b.is_connected("pressed", self, handler):
		b.connect("pressed", self, handler)

func _on_home_pressed():
	if AudioManager != null:
		AudioManager.play_sound("ui_click")
	get_tree().change_scene("res://Scenes/Menu.tscn")

func _on_shop_pressed():
	if AudioManager != null:
		AudioManager.play_sound("ui_click")
	get_tree().change_scene("res://Scenes/Shop.tscn")

# MEANER METER: when filled, show the bonus slot
func _on_meaner_meter_filled():
	_show_bonus_slot()

func _ensure_canvas_layer():
	var root = get_tree().get_current_scene()
	if root == null:
		return null
	var layer = root.get_node_or_null("CanvasLayer")
	if layer == null:
		layer = root.find_node("CanvasLayer", true, false)
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "CanvasLayer"
		root.add_child(layer)
	return layer

func _show_bonus_slot():
	var layer = _ensure_canvas_layer()
	if layer == null:
		return
	var existing = layer.get_node_or_null("BonusSlot")
	if existing != null:
		return
	var slot_scene = preload("res://Scenes/BonusSlotMachine.tscn")
	var slot = slot_scene.instance()
	# Safety: ensure the correct script is attached in case the scene was saved with a wrong script
	var expected_script_path = "res://Scripts/BonusSlotMachine.gd"
	# Force-attach the correct script to avoid stale/cached wrong scripts
	slot.set_script(load(expected_script_path))
	slot.name = "BonusSlot"
	if slot.has_signal("finished"):
		slot.connect("finished", self, "_on_bonus_slot_closed")
	layer.add_child(slot)

func _on_bonus_slot_closed():
	# Reset the meter after the bonus has been played
	PlayerManager.reset_meaner_meter()
	# Track frequent flyer achievement progress
	if PlayerManager != null and PlayerManager.has_method("increment_bonus_spins"):
		PlayerManager.increment_bonus_spins()

func _on_meaner_meter_changed(cur, mx):
	if _meaner_bar != null:
		_meaner_bar.max_value = float(mx)
		_meaner_bar.value = float(cur)
	# Gauge already conveys percentage; keep label simple
	if _meaner_label != null:
		_meaner_label.text = "MEANER METER"

func _add_meaner_meter_ui():
	# Avoid duplicates
	if get_node_or_null("MeanerMeterPanel") != null:
		return
	var panel = Panel.new()
	panel.name = "MeanerMeterPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 1004
	# Top-center anchored bar
	panel.anchor_left = 0.5
	panel.anchor_top = 0.0
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.0
	panel.margin_left = -220.0
	panel.margin_right = 220.0
	panel.margin_top = 10.0
	panel.margin_bottom = 80.0
	var psb = StyleBoxFlat.new()
	psb.bg_color = Color(0, 0, 0, 0.4)
	psb.border_color = Color(1.0, 0.84, 0.0, 1.0)
	psb.border_width_top = 2
	psb.border_width_bottom = 2
	psb.border_width_left = 2
	psb.border_width_right = 2
	psb.corner_radius_top_left = 10
	psb.corner_radius_top_right = 10
	psb.corner_radius_bottom_left = 10
	psb.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", psb)
	add_child(panel)

	var vb = VBoxContainer.new()
	vb.anchor_left = 0
	vb.anchor_top = 0
	vb.anchor_right = 1
	vb.anchor_bottom = 1
	vb.margin_left = 10
	vb.margin_top = 6
	vb.margin_right = -10
	vb.margin_bottom = -6
	panel.add_child(vb)

	var lbl = Label.new()
	lbl.text = "MEANER METER:"
	lbl.align = HALIGN_CENTER
	lbl.add_font_size_override("font_size", 18)
	vb.add_child(lbl)
	_meaner_label = lbl

	var pb = ProgressBar.new()
	pb.min_value = 0
	pb.max_value = 100
	pb.value = 0
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Style the fill and background for visibility
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	pb.add_theme_stylebox_override("background", sb_bg)
	var sb_fill = StyleBoxFlat.new()
	sb_fill.bg_color = Color(1.0, 0.84, 0.0, 1.0)
	pb.add_theme_stylebox_override("fill", sb_fill)
	vb.add_child(pb)
	_meaner_bar = pb

# Adds a gold border to the outside edge of the display.
# Implemented as a full-screen Panel with a StyleBoxFlat border.
func _add_gold_border():
	# Avoid duplicates if _ready is called again
	var existing = get_node_or_null("GoldBorderPanel")
	if existing != null:
		return
	var panel = Panel.new()
	panel.name = "GoldBorderPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 1000
	# Full-rect anchors
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.margin_left = 0.0
	panel.margin_top = 0.0
	panel.margin_right = 0.0
	panel.margin_bottom = 0.0
	# Gold-looking color and thickness
	var border_thickness = 8
	var gold = Color(1.0, 0.84, 0.0, 1.0)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0) # transparent center
	sb.border_color = gold
	sb.border_width_top = border_thickness
	sb.border_width_bottom = border_thickness
	sb.border_width_left = border_thickness
	sb.border_width_right = border_thickness
	# Optional rounded corners for a polished look
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	# Very thin black inside stroke around the inner edge of the gold border
	var inner = Panel.new()
	inner.name = "GoldBorderInnerStroke"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.z_index = 1001
	# Anchor full, then inset by the gold thickness so the stroke hugs the inner edge
	inner.anchor_left = 0.0
	inner.anchor_top = 0.0
	inner.anchor_right = 1.0
	inner.anchor_bottom = 1.0
	inner.margin_left = border_thickness
	inner.margin_top = border_thickness
	inner.margin_right = -border_thickness
	inner.margin_bottom = -border_thickness
	var inner_sb = StyleBoxFlat.new()
	inner_sb.bg_color = Color(0, 0, 0, 0)
	inner_sb.border_color = Color(0, 0, 0, 1)
	# Thicker inner stroke
	var inner_w = 3
	inner_sb.border_width_top = inner_w
	inner_sb.border_width_bottom = inner_w
	inner_sb.border_width_left = inner_w
	inner_sb.border_width_right = inner_w
	# Match corner radius to sit inside the outer radius
	# Rounder inner corners to better match the outer border
	var inner_radius = 8
	inner_sb.corner_radius_top_left = inner_radius
	inner_sb.corner_radius_top_right = inner_radius
	inner_sb.corner_radius_bottom_left = inner_radius
	inner_sb.corner_radius_bottom_right = inner_radius
	inner.add_theme_stylebox_override("panel", inner_sb)
	panel.add_child(inner)

	# Gold border gradient: fade from gold at the outer edge to white toward the inner edge
	var grad = ColorRect.new()
	grad.name = "GoldBorderGradient"
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Place above panel and stroke; will not cover stroke due to inner cut below
	grad.z_index = 1003
	grad.anchor_left = 0.0
	grad.anchor_top = 0.0
	grad.anchor_right = 1.0
	grad.anchor_bottom = 1.0
	grad.margin_left = 0.0
	grad.margin_top = 0.0
	grad.margin_right = 0.0
	grad.margin_bottom = 0.0
	var min_dim = min(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y)
	var thickness_norm = 0.06
	var inner_cut_norm = 0.0
	if min_dim > 0.0:
		thickness_norm = float(border_thickness) / min_dim
		inner_cut_norm = float(inner_w) / min_dim
	var gsh = Shader.new()
	gsh.code = "shader_type canvas_item;\n"
	gsh.code += "uniform float thickness = 0.06;\n"
	gsh.code += "uniform float inner_cut = 0.0;\n"
	gsh.code += "uniform vec4 outer_color : hint_color = vec4(1.0, 0.84, 0.0, 1.0);\n"
	gsh.code += "uniform vec4 inner_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);\n"
	gsh.code += "void fragment() {\n"
	gsh.code += "    vec2 uv = UV;\n"
	gsh.code += "    float d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));\n"
	gsh.code += "    float usable = max(thickness - inner_cut, 0.0);\n"
	gsh.code += "    float a = step(d, usable);\n"
	gsh.code += "    float denom = max(usable, 1e-6);\n"
	gsh.code += "    float t = clamp(d / denom, 0.0, 1.0);\n"
	gsh.code += "    vec4 col = mix(outer_color, inner_color, t);\n"
	gsh.code += "    COLOR = vec4(col.rgb, col.a * a);\n"
	gsh.code += "}\n"
	var gmat = ShaderMaterial.new()
	gmat.shader = gsh
	gmat.set_shader_param("thickness", thickness_norm)
	gmat.set_shader_param("inner_cut", inner_cut_norm)
	gmat.set_shader_param("outer_color", gold)
	gmat.set_shader_param("inner_color", Color(1, 1, 1, 1))
	grad.material = gmat
	panel.add_child(grad)

	# Subtle black inner glow vignette inside the inner stroke
	var glow = ColorRect.new()
	glow.name = "GoldBorderInnerGlow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = 1002
	# Inset so the glow starts at the inner stroke edge
	glow.anchor_left = 0.0
	glow.anchor_top = 0.0
	glow.anchor_right = 1.0
	glow.anchor_bottom = 1.0
	var inset = float(border_thickness + inner_w)
	glow.margin_left = inset
	glow.margin_top = inset
	glow.margin_right = -inset
	glow.margin_bottom = -inset
	# CanvasItem shader to draw a soft inner black glow using UV distance to edges
	var sh = Shader.new()
	sh.code = "shader_type canvas_item;\n"
	sh.code += "uniform float thickness : hint_range(0.0, 0.2) = 0.03;\n"
	sh.code += "uniform float strength : hint_range(0.0, 1.0) = 0.5;\n"
	sh.code += "void fragment() {\n"
	sh.code += "    vec2 uv = UV;\n"
	sh.code += "    float d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));\n"
	sh.code += "    float a = smoothstep(thickness, 0.0, d) * strength;\n"
	sh.code += "    COLOR = vec4(0.0, 0.0, 0.0, a);\n"
	sh.code += "}\n"
	var mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_param("thickness", 0.03)
	mat.set_shader_param("strength", 0.5)
	glow.material = mat
	panel.add_child(glow)
