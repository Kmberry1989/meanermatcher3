extends Control

@onready var resume_button = $Center/VBox/ResumeButton
@onready var shop_button = $Center/VBox/ShopButton
@onready var shop_panel = $Center/VBox/Shop
@onready var coins_label = $Center/VBox/Shop/Coins
@onready var buy_frame2 = $Center/VBox/Shop/BuyFrame2
@onready var buy_bg2 = $Center/VBox/Shop/BuyBG2
@onready var buy_bg3 = $Center/VBox/Shop/BuyBG3
@onready var buy_bg4 = $Center/VBox/Shop/BuyBG4
@onready var music_slider: HSlider = $Center/VBox/MusicVolume/MusicSlider
@onready var music_percent: Label = $Center/VBox/MusicVolume/MusicPercent
@onready var sfx_slider: HSlider = $Center/VBox/SfxVolume/SfxSlider
@onready var sfx_percent: Label = $Center/VBox/SfxVolume/SfxPercent

const PRICE_FRAME := 10
const PRICE_BG := 20

func _ready():
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	resume_button.connect("pressed", Callable(self, "_on_resume"))
	shop_button.connect("pressed", Callable(self, "_on_shop_toggle"))
	buy_frame2.connect("pressed", Callable(self, "_on_buy_frame2"))
	PlayerManager.coins_changed.connect(_on_coins_changed)
	_on_coins_changed(PlayerManager.get_coins())
	_populate_frame_shop()
	# Backgrounds are all unlocked and auto-cycle; hide background buttons for now.
	buy_bg2.visible = false
	buy_bg3.visible = false
	buy_bg4.visible = false
	# Initialize volume sliders
	_init_volume_sliders()

func show_menu():
	show()
	get_tree().paused = true

func _on_resume():
	hide()
	get_tree().paused = false

func _on_shop_toggle():
	shop_panel.visible = !shop_panel.visible

func _on_coins_changed(new_amount):
	coins_label.text = "Coins: " + str(new_amount)

func _on_buy_frame2():
	if PlayerManager.spend_coins(PRICE_FRAME):
		PlayerManager.unlock_frame("frame_2")
		PlayerManager.set_current_frame("frame_2")

func _on_buy_bg2():
	pass

func _on_buy_bg3():
	pass

func _on_buy_bg4():
	pass

func _populate_frame_shop():
	# Dynamically add buttons for all avatar_frame_*.png files (frame_2+)
	var visuals_path = "res://Assets/Visuals"
	var dir = DirAccess.open(visuals_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var frames := []
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.begins_with("avatar_frame_") and file_name.ends_with(".png"):
				var num_str = file_name.trim_prefix("avatar_frame_").trim_suffix(".png")
				if num_str.is_valid_int():
					var n = int(num_str)
					if n >= 2:
						frames.append(n)
		file_name = dir.get_next()
	dir.list_dir_end()
	frames.sort()
	for n in frames:
		if n == 2:
			continue # we already have a dedicated Frame 2 button
		var frame_name = "frame_" + str(n)
		var btn = Button.new()
		var unlocked = PlayerManager.player_data.get("unlocks", {}).get("frames", []).has(frame_name)
		btn.text = ("Use " if unlocked else "Buy ") + "Frame " + str(n) + ("" if unlocked else " (" + str(PRICE_FRAME) + ")")
		btn.pressed.connect(func():
			if not unlocked:
				if not PlayerManager.spend_coins(PRICE_FRAME):
					return
				PlayerManager.unlock_frame(frame_name)
			PlayerManager.set_current_frame(frame_name)
		)
		shop_panel.add_child(btn)

# Volume controls
func _init_volume_sliders():
	if AudioManager != null:
		var mdb = AudioManager.get_music_volume()
		var sdb = AudioManager.get_sfx_volume()
		music_slider.min_value = -60.0
		music_slider.max_value = 0.0
		sfx_slider.min_value = -60.0
		sfx_slider.max_value = 0.0
		music_slider.value = clamp(mdb, music_slider.min_value, music_slider.max_value)
		sfx_slider.value = clamp(sdb, sfx_slider.min_value, sfx_slider.max_value)
		_update_music_label(music_slider.value)
		_update_sfx_label(sfx_slider.value)
		music_slider.value_changed.connect(_on_music_slider_changed)
		sfx_slider.value_changed.connect(_on_sfx_slider_changed)

func _on_music_slider_changed(v):
	if AudioManager != null:
		AudioManager.set_music_volume(v)
	_update_music_label(v)

func _on_sfx_slider_changed(v):
	if AudioManager != null:
		AudioManager.set_sfx_volume(v)
	_update_sfx_label(v)

func _update_music_label(db):
	var pct = int(round(db_to_linear(db) * 100.0)) if typeof(db) != TYPE_NIL else 0
	music_percent.text = str(pct) + "%"

func _update_sfx_label(db):
	var pct = int(round(db_to_linear(db) * 100.0)) if typeof(db) != TYPE_NIL else 0
	sfx_percent.text = str(pct) + "%"
