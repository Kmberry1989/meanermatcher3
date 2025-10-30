extends Control

var status_label: Label
var offline_button: TextureButton
var profile_button: TextureButton
var showcase_button: TextureButton
var shop_button: TextureButton
var logout_button: TextureButton
var multiplayer_button: TextureButton
@onready var firebase = get_node_or_null("/root/Firebase")

func _ready():
	status_label = Label.new()
	offline_button = TextureButton.new()
	profile_button = TextureButton.new()
	showcase_button = TextureButton.new()
	shop_button = TextureButton.new()
	logout_button = TextureButton.new()
	multiplayer_button = TextureButton.new()

	# Background image (cover)
	var bg = TextureRect.new()
	bg.texture = load("res://Assets/Visuals/main_menu_background.png")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Ensure it stays behind the rest of UI
	move_child(bg, 0)

	# Use a CenterContainer to ensure all elements are perfectly centered
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center_container)

	# Add a small downward offset so the menu sits ~25px lower than center
	var offset_container = MarginContainer.new()
	offset_container.add_theme_constant_override("margin_top", 200)
	center_container.add_child(offset_container)

	# VBoxContainer holds our UI elements vertically
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	offset_container.add_child(vbox)

	# Title Label
	var title = Label.new()
	title.text = " " # Updated game title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	# Margin for spacing
	var margin = Control.new()
	margin.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(margin)

	# Load button textures
	var normal_tex = load("res://Assets/Visuals/button_normal.svg")
	var hover_tex = load("res://Assets/Visuals/button_hover.svg")
	var pressed_tex = load("res://Assets/Visuals/button_pressed.svg")

	# Play Button
	offline_button.texture_normal = normal_tex
	offline_button.texture_pressed = pressed_tex
	offline_button.texture_hover = hover_tex
	offline_button.connect("pressed", _on_offline_button_pressed)
	offline_button.scale = Vector2(0.8, 0.8)
	vbox.add_child(offline_button)

	var offline_label = Label.new()
	offline_label.text = "Play"
	offline_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	offline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	offline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	offline_label.add_theme_font_size_override("font_size", 32)
	offline_button.add_child(offline_label)

	# Profile Button
	profile_button.texture_normal = normal_tex
	profile_button.texture_pressed = pressed_tex
	profile_button.texture_hover = hover_tex
	profile_button.connect("pressed", _on_profile_button_pressed)
	profile_button.scale = Vector2(0.8, 0.8)
	vbox.add_child(profile_button)

	var profile_label = Label.new()
	profile_label.text = "Profile"
	profile_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	profile_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	profile_label.add_theme_font_size_override("font_size", 32)
	profile_button.add_child(profile_label)

	# Showcase Button
	showcase_button.texture_normal = normal_tex
	showcase_button.texture_pressed = pressed_tex
	showcase_button.texture_hover = hover_tex
	showcase_button.connect("pressed", _on_showcase_button_pressed)
	showcase_button.scale = Vector2(0.8, 0.8)
	vbox.add_child(showcase_button)

	var showcase_label = Label.new()
	showcase_label.text = "Showcase"
	showcase_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	showcase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	showcase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	showcase_label.add_theme_font_size_override("font_size", 32)
	showcase_button.add_child(showcase_label)

	# Shop Button
	shop_button.texture_normal = normal_tex
	shop_button.texture_pressed = pressed_tex
	shop_button.texture_hover = hover_tex
	shop_button.connect("pressed", _on_shop_button_pressed)
	shop_button.scale = Vector2(0.8, 0.8)
	vbox.add_child(shop_button)

	var shop_label = Label.new()
	shop_label.text = "Shop"
	shop_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shop_label.add_theme_font_size_override("font_size", 32)
	shop_button.add_child(shop_label)

	# Multiplayer Button
	multiplayer_button.texture_normal = normal_tex
	multiplayer_button.texture_pressed = pressed_tex
	multiplayer_button.texture_hover = hover_tex
	multiplayer_button.connect("pressed", _on_multiplayer_button_pressed)
	multiplayer_button.scale = Vector2(0.8, 0.8)
	vbox.add_child(multiplayer_button)

	var mp_label = Label.new()
	mp_label.text = "Multiplayer"
	mp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	mp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mp_label.add_theme_font_size_override("font_size", 32)
	multiplayer_button.add_child(mp_label)

	# Logout Button (shown only if Firebase is present and logged in)
	logout_button.texture_normal = normal_tex
	logout_button.texture_pressed = pressed_tex
	logout_button.texture_hover = hover_tex
	logout_button.connect("pressed", _on_logout_button_pressed)
	logout_button.scale = Vector2(0.8, 0.8)
	vbox.add_child(logout_button)

	var logout_label = Label.new()
	logout_label.text = "Logout"
	logout_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	logout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logout_label.add_theme_font_size_override("font_size", 32)
	logout_button.add_child(logout_label)

	_update_logout_visibility()

	# Status Label
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size = Vector2(300, 50)
	vbox.add_child(status_label)

	# Play menu music
	AudioManager.play_music("menu")

	# Keep logout visibility in sync with auth state
	if firebase != null:
		firebase.Auth.login_succeeded.connect(Callable(self, "_update_logout_visibility"))
		firebase.Auth.logged_out.connect(Callable(self, "_update_logout_visibility"))

func _on_offline_button_pressed():
	print("[Menu.gd] Play button pressed.")
	AudioManager.play_sound("ui_click")
	_start_game()

func _on_profile_button_pressed():
	AudioManager.play_sound("ui_click")
	get_tree().change_scene_to_file("res://Scenes/Profile.tscn")

func _on_showcase_button_pressed():
	AudioManager.play_sound("ui_click")
	get_tree().change_scene_to_file("res://Scenes/Showcase.tscn")

func _on_shop_button_pressed():
	AudioManager.play_sound("ui_click")
	get_tree().change_scene_to_file("res://Scenes/Shop.tscn")

func _on_multiplayer_button_pressed():
	AudioManager.play_sound("ui_click")
	get_tree().change_scene_to_file("res://Scenes/MultiplayerLobby.tscn")

func _start_game():
	print("[Menu.gd] _start_game: Stopping music and playing sound.")
	AudioManager.stop_music()
	AudioManager.play_sound("game_start")
	print("[Menu.gd] _start_game: Setting session mode to single-player.")
	if Engine.has_singleton("MultiplayerManager"):
		MultiplayerManager.session_mode = "singleplayer"
	print("[Menu.gd] _start_game: Changing to intermediate Loading scene.")
	get_tree().change_scene_to_file("res://Scenes/Loading.tscn")

func _update_logout_visibility():
	var logout_visible = false
	if firebase != null:
		logout_visible = firebase.Auth.is_logged_in()
	logout_button.visible = logout_visible

func _on_logout_button_pressed():
	AudioManager.play_sound("ui_click")
	if firebase != null:
		firebase.Auth.logout()
	# Optionally clear some local player data if desired
	PlayerManager.player_uid = ""
	get_tree().change_scene_to_file("res://Scenes/Login.tscn")
