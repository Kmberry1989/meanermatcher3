extends Node2D

const PULSE_SCALE_MAX = Vector2(0.2725, 0.2725)
const PULSE_SCALE_MIN = Vector2(0.2575, 0.2575)
const DOT_SCALE = 2.0 # Global multiplier to enlarge dot visuals
const REFERENCE_DOT_PX = 512.0

export var color = ""
onready var sprite = get_node("Sprite")
var matched = false
var scale_multiplier = 1.0
var is_wildcard = false

# Emitted when the match fade-out finishes; used to trigger XP orbs immediately.
signal match_faded(global_pos, color_name)

var pulse_tween = null
var float_tween = null
var shadow = null

# Whether an XP orb has already been spawned for this dot in the current match.
var orb_spawned = false

# Visual Effects
onready var flash_texture = preload("res://Assets/Visuals/bright_flash.png")

# Animation state and textures
var animation_state = "normal"  # normal, blinking, sad, idle, surprised
var normal_texture
var blink_texture
var sad_texture
var sleepy_texture
var surprised_texture
var yawn_texture

var last_yawn_time = 0
const YAWN_COOLDOWN = 2500 # 2.5 seconds in milliseconds

onready var blink_timer = Timer.new()
onready var wildcard_timer = Timer.new()
var wildcard_textures = []
var _wildcard_index = 0

# Mapping from color to character name
var color_to_character = {
	"yellow": "bethany",
	"brown": "caleb",
	"gray": "eric",
	"pink": "kristen",
	"green": "kyle",
	"purple": "connie",
	"red": "rochelle",
	"blue": "vickie",
	"orange": "maia"
}

# Mapping from color to pulse duration
var color_to_pulse_duration = {
	"red": 1,
	"orange": 1,
	"yellow": 1,
	"green": 1,
	"blue": 1,
	"purple": 1,
	"pink": 1,
	"brown": 1,
	"gray": 1
}

var mouse_inside = false

func _ready():
	load_textures()
	# Adjust dot scale based on texture size so in-game size stays consistent
	if sprite and sprite.texture:
		var tex_w = float(sprite.texture.get_width())
		var tex_h = float(sprite.texture.get_height())
		var max_dim = max(tex_w, tex_h)
		if max_dim > 0.0:
			scale_multiplier = (REFERENCE_DOT_PX / max_dim) * DOT_SCALE
	create_shadow()
	setup_blink_timer()
	setup_wildcard_timer()
	start_floating()
	start_pulsing()
	
	var area = Area2D.new()
	add_child(area)
	area.connect("mouse_entered", self, "_on_mouse_entered")
	area.connect("mouse_exited", self, "_on_mouse_exited")

	# Wait for the sprite texture to be loaded
	yield(get_tree(), "idle_frame")

	var texture = sprite.texture
	if texture:
		var collision_shape = CollisionShape2D.new()
		var square_shape = RectangleShape2D.new()
		var max_dimension = max(texture.get_width(), texture.get_height())
		var target_scale = max(PULSE_SCALE_MAX.x, PULSE_SCALE_MAX.y) * scale_multiplier
		var side_length = max_dimension * target_scale
		square_shape.extents = Vector2(side_length, side_length) / 2.0
		collision_shape.shape = square_shape
		area.add_child(collision_shape)

func _process(_delta):
	if mouse_inside:
		pass

func _on_mouse_entered():
	mouse_inside = true
	if pulse_tween:
		pulse_tween.stop_all()
	
	# Set scale to the largest size from the pulse animation
	sprite.scale = PULSE_SCALE_MAX * scale_multiplier
	play_surprised_animation()

func _on_mouse_exited():
	mouse_inside = false
	sprite.scale = PULSE_SCALE_MIN * scale_multiplier # Reset scale
	start_pulsing()
	set_normal_texture()

func play_surprised_animation():
	if animation_state == "normal":
		AudioManager.play_sound("surprised")
		animation_state = "surprised"
		sprite.texture = surprised_texture

func play_drag_sad_animation():
	animation_state = "sad"
	sprite.texture = sad_texture

func move(new_position, duration = 0.2):
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(self, "position", position, new_position, duration, Tween.TRANS_SINE, Tween.EASE_OUT)
	tween.start()
	return tween

func play_match_animation(delay):
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_callback(self, delay, "show_flash")
	tween.interpolate_property(self, "scale", scale, scale * 1.5, 0.3, Tween.TRANS_SINE, Tween.EASE_OUT, delay)
	tween.interpolate_property(self, "modulate:a", 1.0, 0.0, 0.3, Tween.TRANS_SINE, Tween.EASE_OUT, delay)
	tween.start()
	tween.connect("tween_all_completed", self, "_on_match_fade_finished")

func _on_match_fade_finished():
	if not orb_spawned:
		orb_spawned = true
		emit_signal("match_faded", global_position, color)

func show_flash():
	var flash = Sprite.new()
	flash.texture = flash_texture
	flash.centered = true
	flash.modulate = Color(1,1,1,0.7)
	add_child(flash)
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(flash, "scale", Vector2(1,1), Vector2(2,2), 0.3, Tween.TRANS_SINE, Tween.EASE_OUT)
	tween.interpolate_property(flash, "modulate:a", 0.7, 0.0, 0.3, Tween.TRANS_SINE, Tween.EASE_OUT)
	tween.interpolate_callback(flash, 0.3, "queue_free")
	tween.start()

func play_sad_animation():
	animation_state = "sad"
	sprite.texture = sad_texture

func play_surprised_for_a_second():
	if animation_state == "normal":
		AudioManager.play_sound("surprised")
		animation_state = "surprised"
		sprite.texture = surprised_texture
		var timer = Timer.new()
		add_child(timer)
		timer.one_shot = true
		timer.wait_time = 1.0
		timer.start()
		yield(timer, "timeout")
		timer.queue_free()
		if animation_state == "surprised":
			set_normal_texture()

func create_shadow():
	shadow = Sprite.new()
	var gradient = Gradient.new()
	gradient.colors = [Color(0,0,0,0.4), Color(0,0,0,0)] # Black center, transparent edge
	var gradient_tex = GradientTexture.new()
	gradient_tex.gradient = gradient
	gradient_tex.width = 64
	gradient_tex.height = 64
	shadow.texture = gradient_tex
	shadow.scale = Vector2(1, 0.5) # Make it oval
	shadow.z_index = -1
	shadow.position = Vector2(0, 35)
	add_child(shadow)
	# Hide shadow to remove it visually
	shadow.visible = false
	shadow.modulate.a = 0.0

func load_textures():
	var character = color_to_character.get(color, "bethany") # Default to bethany if color not found
	
	# Construct texture paths to use the 'Dots' subfolder.
	var base_path = "res://Assets/Dots/" + character + "avatar"
	normal_texture = load(base_path + ".png")
	blink_texture = load(base_path + "blink.png")
	sad_texture = load(base_path + "sad.png")
	sleepy_texture = load(base_path + "sleepy.png")
	surprised_texture = load(base_path + "surprised.png")
	yawn_texture = load(base_path + "yawn.png")
	
	sprite.texture = normal_texture

func set_normal_texture():
	if is_wildcard:
		return
	animation_state = "normal"
	sprite.texture = normal_texture

func reset_to_normal_state():
	if is_wildcard:
		return
	set_normal_texture()

func setup_blink_timer():
	blink_timer.connect("timeout", self, "_on_blink_timer_timeout")
	blink_timer.set_one_shot(true)
	add_child(blink_timer)
	blink_timer.start(rand_range(4.0, 12.0))

func setup_wildcard_timer():
	add_child(wildcard_timer)
	wildcard_timer.one_shot = false
	wildcard_timer.wait_time = 0.12
	wildcard_timer.connect("timeout", self, "_on_wildcard_tick")

func _on_wildcard_tick():
	if not is_wildcard:
		wildcard_timer.stop()
		return
	if wildcard_textures.size() == 0:
		return
	_wildcard_index = (_wildcard_index + 1) % wildcard_textures.size()
	sprite.texture = wildcard_textures[_wildcard_index]

func set_wildcard(enable = true):
	is_wildcard = enable
	if enable:
		animation_state = "wildcard"
		# Build a list of normal textures across all characters/colors
		wildcard_textures.clear()
		for col in color_to_character.keys():
			var character = color_to_character[col]
			var base_path = "res://Assets/Dots/" + character + "avatar"
			var tex = load(base_path + ".png")
			if tex:
				wildcard_textures.append(tex)
		if wildcard_textures.size() > 0:
			_wildcard_index = 0
			sprite.texture = wildcard_textures[_wildcard_index]
			wildcard_timer.start()
		# Make the shadow slightly brighter for wildcard
		if shadow:
			shadow.modulate = Color(0.2,0.2,0.2,0.6)
	else:
		wildcard_timer.stop()
		animation_state = "normal"
		set_normal_texture()

func start_floating():
	if float_tween:
		float_tween.stop_all()
	float_tween = Tween.new()
	add_child(float_tween)
	float_tween.interpolate_property(sprite, "position:y", 5, -5, 1.5, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	float_tween.interpolate_property(sprite, "position:y", -5, 5, 1.5, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 1.5)
	float_tween.start()
	float_tween.connect("tween_all_completed", self, "start_floating")

func start_pulsing():
	if pulse_tween:
		pulse_tween.stop_all()

	var pulse_duration = color_to_pulse_duration.get(color, 1.5) # Default to 1.5 if color not found

	pulse_tween = Tween.new()
	add_child(pulse_tween)
	pulse_tween.interpolate_property(sprite, "scale", PULSE_SCALE_MIN * scale_multiplier, PULSE_SCALE_MAX * scale_multiplier, pulse_duration, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	pulse_tween.interpolate_property(sprite, "scale", PULSE_SCALE_MAX * scale_multiplier, PULSE_SCALE_MIN * scale_multiplier, pulse_duration, Tween.TRANS_SINE, Tween.EASE_IN_OUT, pulse_duration)
	pulse_tween.start()
	pulse_tween.connect("tween_all_completed", self, "start_pulsing")

func _on_blink_timer_timeout():
	if animation_state == "normal":
		animation_state = "blinking"
		sprite.texture = blink_texture
		var timer = Timer.new()
		add_child(timer)
		timer.one_shot = true
		timer.wait_time = 0.15
		timer.start()
		yield(timer, "timeout")
		timer.queue_free()
		if animation_state == "blinking": # Ensure state wasn't changed by a higher priority animation
			set_normal_texture()
	
	blink_timer.start(rand_range(4.0, 12.0))

func play_idle_animation():
	var current_time = OS.get_ticks_msec()
	if current_time - last_yawn_time < YAWN_COOLDOWN:
		return # Cooldown is active, so we do nothing.

	if animation_state != "normal":
		return

	last_yawn_time = current_time
	animation_state = "idle"
	sprite.texture = sleepy_texture
	var timer = Timer.new()
	add_child(timer)
	timer.one_shot = true
	timer.wait_time = 2.5
	timer.start()
	yield(timer, "timeout")
	timer.queue_free()
	
	if animation_state == "idle": # Make sure we weren't interrupted
		sprite.texture = yawn_texture
		AudioManager.play_sound("yawn")
		
		var original_pos = self.position
		var original_shadow_scale = shadow.scale
		var original_shadow_opacity = shadow.modulate.a
		
		if pulse_tween:
			pulse_tween.stop_all()
		if float_tween:
			float_tween.stop_all()
			
		var tween = Tween.new()
		add_child(tween)
		# Lift and inflate over 1.5 seconds
		tween.interpolate_property(self, "position", original_pos, original_pos + Vector2(0, -15), 1.5, Tween.TRANS_QUINT, Tween.EASE_OUT)
		tween.interpolate_property(sprite, "scale", sprite.scale, (PULSE_SCALE_MIN * 1.5) * scale_multiplier, 1.5, Tween.TRANS_QUINT, Tween.EASE_OUT)
		tween.interpolate_property(shadow, "scale", original_shadow_scale, original_shadow_scale * 2.5, 1.5, Tween.TRANS_QUINT, Tween.EASE_OUT)
		tween.interpolate_property(shadow, "modulate:a", original_shadow_opacity, 0.0, 1.5, Tween.TRANS_QUINT, Tween.EASE_OUT)
		tween.start()
		yield(tween, "tween_all_completed")

		if animation_state == "idle":
			var down_tween = Tween.new()
			add_child(down_tween)
			down_tween.interpolate_property(self, "position", position, original_pos, 1.0)
			down_tween.interpolate_property(sprite, "scale", sprite.scale, PULSE_SCALE_MIN * scale_multiplier, 1.0)
			down_tween.interpolate_property(shadow, "scale", shadow.scale, original_shadow_scale, 1.0)
			down_tween.interpolate_property(shadow, "modulate:a", shadow.modulate.a, original_shadow_opacity, 1.0)
			down_tween.start()
			yield(down_tween, "tween_all_completed")
			set_normal_texture()
			start_pulsing()
