extends Control

signal spin_finished

@export var images: Array[Texture2D] = []
@export var rows_visible: int = 3
@export var tile_size: Vector2i = Vector2i(250, 250)
@export var spin_up_distance: float = 180.0

var _container: Control
var _clip: Control
var _canvas: Node2D
var _anim: AnimationPlayer
var _tiles: Array = []
var _extra_tiles: int = 0
var _height: int = 0

func setup_reel(p_images: Array, p_rows_visible: int, p_tile_size: Vector2i, p_spin_up: float) -> void:
	images = p_images
	rows_visible = p_rows_visible
	tile_size = p_tile_size
	spin_up_distance = p_spin_up
	_ensure_built()

func _ready():
	_ensure_built()

func _ensure_built() -> void:
	if _canvas != null:
		return
	clip_contents = true
	_height = tile_size.y * rows_visible
	# Root clipping container is this Control; create a Node2D canvas for sprites
	_canvas = Node2D.new()
	_canvas.name = "Canvas"
	add_child(_canvas)
	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	add_child(_anim)
	var lib = AnimationLibrary.new()
	_anim.add_animation_library("", lib)
	# Build tiles with extra buffer above/below
	# Add a small safety margin so spin-up wiggle never exposes blanks
	var extra_each_side := int(ceil(spin_up_distance / float(tile_size.y))) + 1
	_extra_tiles = extra_each_side * 2
	var total := rows_visible + _extra_tiles
	var start_row := -extra_each_side
	for i in range(total):
		var spr := Sprite2D.new()
		spr.centered = false
		spr.position = Vector2(0, (start_row + i) * tile_size.y)
		_assign_random_texture(spr)
		_canvas.add_child(spr)
		_tiles.append(spr)

func _assign_random_texture(spr: Sprite2D) -> void:
	if images.size() == 0:
		spr.texture = null
		spr.set_meta("idx", -1)
		return
	var idx := randi() % images.size()
	spr.texture = images[idx]
	spr.set_meta("idx", idx)
	spr.scale = Vector2(float(tile_size.x) / max(1.0, float(spr.texture.get_width())), float(tile_size.y) / max(1.0, float(spr.texture.get_height())))

func start_spin(runtime_s: float, speed_tiles_per_sec: float, delay_s: float = 0.0) -> void:
	await get_tree().create_timer(max(delay_s, 0.0)).timeout
	await _spin_up()
	var moves: int = int(round(runtime_s * speed_tiles_per_sec))
	var step_time: float = 1.0 / max(speed_tiles_per_sec, 0.001)
	for _i in range(moves):
		await _step_down(step_time)
		_wrap_and_randomize_if_needed()
	await _spin_down()
	emit_signal("spin_finished")

func _spin_up() -> void:
	# Create a simple bezier-like ease using AnimationPlayer on canvas y
	var anim := Animation.new()
	anim.resource_name = "spin_up"
	var t := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t, NodePath("Canvas:position:y"))
	# Longer wobble so there is visible motion right away
	anim.track_insert_key(t, 0.0, 0.0)
	anim.track_insert_key(t, 0.2, spin_up_distance * 0.5)   # downwards
	anim.track_insert_key(t, 0.35, -spin_up_distance * 0.25) # slight reverse
	anim.track_insert_key(t, 0.6, spin_up_distance)         # stronger downwards
	anim.track_insert_key(t, 0.85, 0.0)
	# Register animation in the default library (Godot 4 uses AnimationLibrary)
	var lib: AnimationLibrary = _anim.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		_anim.add_animation_library("", lib)
	if lib.has_animation("spin_up"):
		lib.remove_animation("spin_up")
	lib.add_animation("spin_up", anim)
	_anim.play("spin_up")
	await _anim.animation_finished

func _spin_down() -> void:
	var anim := Animation.new()
	anim.resource_name = "spin_down"
	var t := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t, NodePath("Canvas:position:y"))
	var y0 := _canvas.position.y
	anim.track_insert_key(t, 0.0, y0)
	anim.track_insert_key(t, 0.25, y0 + 30.0)
	anim.track_insert_key(t, 0.5, 0.0)
	var lib: AnimationLibrary = _anim.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		_anim.add_animation_library("", lib)
	if lib.has_animation("spin_down"):
		lib.remove_animation("spin_down")
	lib.add_animation("spin_down", anim)
	_anim.play("spin_down")
	await _anim.animation_finished
	_canvas.position.y = 0.0

func _step_down(step_time: float) -> void:
	if Engine.has_singleton("AudioServer") and (typeof(AudioManager) != TYPE_NIL):
		AudioManager.play_sound("slot_tick")
	var twn := create_tween()
	twn.tween_property(_canvas, "position:y", _canvas.position.y + float(tile_size.y), step_time).set_trans(Tween.TRANS_LINEAR)
	await twn.finished

func _wrap_and_randomize_if_needed() -> void:
	# Move tiles that left the viewport to above and give them new textures
	var total_span: float = float(rows_visible + _extra_tiles) * float(tile_size.y)
	for spr in _tiles:
		var gy: float = _canvas.position.y + spr.position.y
		if gy >= _height:
			spr.position.y -= total_span
			_assign_random_texture(spr)

func get_top_symbol_index() -> int:
	var idx: int = -1
	var best_dist: float = 1000000000.0
	for spr in _tiles:
		var gy: float = _canvas.position.y + spr.position.y
		var dist: float = abs(gy - 0.0)
		if gy >= -1.0 and gy < float(tile_size.y) + 1.0:
			var cand := int(spr.get_meta("idx", -1))
			return cand
		if dist < best_dist:
			best_dist = dist
			idx = int(spr.get_meta("idx", -1))
	return idx
