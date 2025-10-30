extends Node2D

enum {wait, move}
var state: int

export(int) var width
export(int) var height
export(int) var offset
export(float) var grid_scale = 1.0
export(Vector2) var grid_nudge = Vector2.ZERO # pixel offset applied after centering
export(int) var y_offset
export(bool) var AUTO_RESHUFFLE = true

var x_start: float
var y_start: float
onready var game_ui = get_node("../GameUI")

export(PoolVector2Array) var empty_spaces

# Preload scenes for dots and new visual effects
onready var possible_dots = [
	preload("res://Scenes/Dots/blue_dot.tscn"),
	preload("res://Scenes/Dots/green_dot.tscn"),
	preload("res://Scenes/Dots/pink_dot.tscn"),
	preload("res://Scenes/Dots/red_dot.tscn"),
	preload("res://Scenes/Dots/yellow_dot.tscn"),
	preload("res://Scenes/Dots/purple_dot.tscn"),
	preload("res://Scenes/Dots/orange_dot.tscn"),
	preload("res://Scenes/Dots/brown_dot.tscn"),
	preload("res://Scenes/Dots/gray_dot.tscn")
]
onready var match_particles: PackedScene = preload("res://Scenes/MatchParticles.tscn")
onready var match_label_scene: PackedScene = preload("res://Scenes/MatchLabel.tscn")
onready var xp_orb_texture: Texture = preload("res://Assets/Visuals/xp_orb.png")
onready var stage_banner_texture: Texture = preload("res://Assets/Visuals/stage_banner.png")
var xp_orb_colors: Dictionary = {
	"red": Color(1.0, 0.25, 0.25),
	"orange": Color(1.0, 0.6, 0.2),
	"yellow": Color(1.0, 0.94, 0.3),
	"green": Color(0.3, 1.0, 0.5),
	"blue": Color(0.3, 0.6, 1.0),
	"purple": Color(0.7, 0.4, 1.0),
	"pink": Color(1.0, 0.5, 0.8),
	"brown": Color(0.6, 0.4, 0.3),
	"gray": Color(0.7, 0.7, 0.7)
}

var destroy_timer: Timer = Timer.new()
var collapse_timer: Timer = Timer.new()
var refill_timer: Timer = Timer.new()
var idle_timer: Timer = Timer.new()
var inactivity_timer: Timer = Timer.new()

var all_dots: Array = []

var dot_one: Node2D = null
var dot_two: Node2D = null
var last_place = Vector2(0,0)
var last_direction = Vector2(0,0)
var move_checked: bool = false

# Dragging variables
var is_dragging: bool = false
var dragged_dot: Node2D = null
var drag_start_position: Vector2 = Vector2.ZERO

# Score variables
var score: int = 0
var combo_counter: int = 1

var possible_colors: Array = []
var _color_rotation_index: int = 0
const MAX_ACTIVE_COLORS = 6
var idle_hint_count: int = 0

var _xp_mult_value: int = 1
var _xp_mult_remaining: int = 0

# Track unsuccessful player attempts
var _failed_attempts: int = 0

func _ready():
	state = move
	setup_timers()
	randomize()
	# Apply grid-only scale by adjusting the cell size (offset).
	# This preserves collision/hit testing because grid_to_pixel/pixel_to_grid use the same offset.
	if grid_scale != 1.0:
		offset = int(round(offset * clamp(grid_scale, 0.5, 2.0)))
	
	for dot_scene in possible_dots:
		var dot_instance = dot_scene.instance()
		possible_colors.append(dot_instance.color)
		dot_instance.queue_free()
	
	# Compute centered start based on current viewport and new offset
	_recalc_start()
	all_dots = make_2d_array()
	spawn_dots()
	# Apply any pending bonus effects at stage start
	_apply_pending_bonus()
	# Optionally ensure the initial board always has at least one potential match
        if AUTO_RESHUFFLE:
                yield(ensure_moves_available(), "completed")
                # Start idle/yawn and inactivity timers
                _restart_idle_timers()

        # Hook level-up to play celebration animations (wave + dance + banner)
        # Use a small defer to ensure tree is ready.
        yield(get_tree(), "idle_frame")
        if PlayerManager != null and not PlayerManager.is_connected("level_up", self, "_on_level_up"):
                PlayerManager.connect("level_up", self, "_on_level_up")
	# Kick off the idle/yawn and inactivity timers after initial spawn
	_restart_idle_timers()



func _recalc_start():
	var s: Vector2 = get_viewport().get_visible_rect().size
	# Center the grid in the current visible size
	x_start = (s.x - float(width) * float(offset)) / 2.0 + float(offset) / 2.0
	y_start = (s.y + float(height) * float(offset)) / 2.0 - float(offset) / 2.0
	# Apply user-defined nudge (in pixels)
	x_start += grid_nudge.x
	y_start += grid_nudge.y

func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_recalc_start()
	# Other initialization is handled in _ready()

func update_score_display():
	game_ui.update_xp_label()

func setup_timers():
        destroy_timer.connect("timeout", self, "destroy_matches")
	destroy_timer.set_one_shot(true)
	destroy_timer.set_wait_time(0.6) # Tightened to align with last dot fade
	add_child(destroy_timer)
	
        collapse_timer.connect("timeout", self, "collapse_columns")
	collapse_timer.set_one_shot(true)
	collapse_timer.set_wait_time(0.2)
	add_child(collapse_timer)

        refill_timer.connect("timeout", self, "refill_columns")
	refill_timer.set_one_shot(true)
	refill_timer.set_wait_time(0.1)
	add_child(refill_timer)
	
        idle_timer.connect("timeout", self, "_on_idle_timer_timeout")
	idle_timer.set_one_shot(true)
	# Hint/yawn delay before suggesting a matchable trio
	idle_timer.set_wait_time(5.0)
	add_child(idle_timer)

	# Inactivity reshuffle timer (only used when AUTO_RESHUFFLE)
	if AUTO_RESHUFFLE:
                inactivity_timer.connect("timeout", self, "_on_inactivity_timeout")
		inactivity_timer.set_one_shot(true)
		# Longer window before reshuffling the board
		inactivity_timer.set_wait_time(25.0)
		add_child(inactivity_timer)

func _restart_idle_timers() -> void:
	if idle_timer != null:
		idle_timer.start()
	if AUTO_RESHUFFLE and inactivity_timer != null:
		inactivity_timer.start()

func restricted_fill(place):
	if is_in_array(empty_spaces, place):
		return true
	return false
	
func is_in_array(array, item):
	for i in range(array.size()):
		if array[i] == item:
			return true
	return false

func make_2d_array():
	var array = []
	for i in range(width):
		array.append([])
		for j in range(height):
			array[i].append(null)
	return array

func spawn_dots():
	for i in range(width):
		for j in range(height):
			if !restricted_fill(Vector2(i, j)):
				var pool = possible_colors
				var rand = floor(randf_range(0, pool.size()))
				var color = pool[rand]
				var loops = 0
				while (match_at(i, j, color) && loops < 100):
					rand = floor(randf_range(0, pool.size()))
					color = pool[rand]
					loops += 1
				
				var dot_scene_to_use
				for dot_scene in possible_dots:
					var dot_instance = dot_scene.instance()
					if dot_instance.color == color:
						dot_scene_to_use = dot_scene
						dot_instance.queue_free()
						break
					dot_instance.queue_free()

				var dot = dot_scene_to_use.instance()
				dot.z_index = height - j
				add_child(dot)
				dot.position = grid_to_pixel(i, j)
				all_dots[i][j] = dot
			
func match_at(i, j, color):
	if i > 1:
		if all_dots[i - 1][j] != null && all_dots[i - 2][j] != null:
			if all_dots[i - 1][j].color == color && all_dots[i - 2][j].color == color:
				return true
	if j > 1:
		if all_dots[i][j - 1] != null && all_dots[i][j - 2] != null:
			if all_dots[i][j - 1].color == color && all_dots[i][j - 2].color == color:
				return true
	return false

func grid_to_pixel(column, row):
	var new_x = x_start + offset * column
	var new_y = y_start + -offset * row
	return Vector2(new_x, new_y)
	
func pixel_to_grid(pixel_x,pixel_y):
	var new_x = round((pixel_x - x_start) / offset)
	var new_y = round((pixel_y - y_start) / -offset)
	return Vector2(new_x, new_y)

func is_in_grid(grid_position):
	if grid_position.x >= 0 and grid_position.x < width:
		if grid_position.y >= 0 and grid_position.y < height:
			return true
	return false

func _input(event):
        if state != move:
                return

        if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.is_pressed():
			_restart_idle_timers()
			idle_hint_count = 0
			var grid_pos = pixel_to_grid(event.position.x, event.position.y)
			if is_in_grid(grid_pos) and all_dots[grid_pos.x][grid_pos.y] != null:
				dragged_dot = all_dots[grid_pos.x][grid_pos.y]
				dragged_dot.z_index = 100 # Bring to front
				drag_start_position = event.position
				is_dragging = true
				dragged_dot.play_drag_sad_animation()
		else: # released
			if is_dragging and dragged_dot != null:
				is_dragging = false
				
				var start_grid_pos = pixel_to_grid(drag_start_position.x, drag_start_position.y)
				dragged_dot.z_index = height - start_grid_pos.y # Restore z-index
				var end_grid_pos = pixel_to_grid(event.position.x, event.position.y)
				
				var difference = end_grid_pos - start_grid_pos
				
				if difference.length() > 0.5: # Threshold for a swipe
					_restart_idle_timers()
					var direction = Vector2.ZERO
					if abs(difference.x) > abs(difference.y):
						if difference.x > 0:
							direction = Vector2.RIGHT
						else:
							direction = Vector2.LEFT
					else:
						if difference.y > 0:
							direction = Vector2.DOWN
						else:
							direction = Vector2.UP
                                        var swapped_state = swap_dots(start_grid_pos.x, start_grid_pos.y, direction)
                                        var swapped: bool = yield(swapped_state, "completed")
					if not swapped:
						dragged_dot.move(grid_to_pixel(start_grid_pos.x, start_grid_pos.y))
				else:
					# Not enough movement; return to start
					dragged_dot.move(grid_to_pixel(start_grid_pos.x, start_grid_pos.y))

				dragged_dot.set_normal_texture()
				dragged_dot = null
				_restart_idle_timers()
				
func swap_dots(column, row, direction) -> bool:
	var col: int = int(column)
	var r: int = int(row)
	var dx: int = int(direction.x)
	var dy: int = int(direction.y)
	# Guard bounds and types
	if col < 0 or col >= width or r < 0 or r >= height:
		return false
	var nx: int = col + dx
	var ny: int = r + dy
	if nx < 0 or nx >= width or ny < 0 or ny >= height:
		return false
	var first_dot = all_dots[col][r]
	var other_dot = all_dots[nx][ny]
	if first_dot != null && other_dot != null:
		# Reset dots to normal state before swapping
		first_dot.reset_to_normal_state()
		other_dot.reset_to_normal_state()
		
		var temp_z = first_dot.z_index
		first_dot.z_index = other_dot.z_index
		other_dot.z_index = temp_z
		store_info(first_dot, other_dot, Vector2(col, r), direction)
		state = wait
		all_dots[col][r] = other_dot
		all_dots[nx][ny] = first_dot
		first_dot.move(grid_to_pixel(nx, ny))
		other_dot.move(grid_to_pixel(col, r))

                yield(get_tree().create_timer(0.2), "timeout")

		if !move_checked:
			find_matches()
		return true
	return false
		
func store_info(first_dot, other_dot, place, direciton):
	dot_one = first_dot
	dot_two = other_dot
	last_place = place
	last_direction = direciton
		
func swap_back():
	if dot_one != null && dot_two != null:
		var first_dot = all_dots[last_place.x][last_place.y]
		var other_dot = all_dots[last_place.x + last_direction.x][last_place.y + last_direction.y]
		
		# Reset dots to normal state before swapping back
		first_dot.reset_to_normal_state()
		other_dot.reset_to_normal_state()
		
		var temp_z = first_dot.z_index
		first_dot.z_index = other_dot.z_index
		other_dot.z_index = temp_z
		
		all_dots[last_place.x][last_place.y] = other_dot
		all_dots[last_place.x + last_direction.x][last_place.y + last_direction.y] = first_dot
		
		first_dot.move(grid_to_pixel(last_place.x + last_direction.x, last_place.y + last_direction.y))
		other_dot.move(grid_to_pixel(last_place.x, last_place.y))

	state = move
	move_checked = false
	combo_counter = 1
	# Count failed attempts and reshuffle after 3
	_failed_attempts += 1
        if AUTO_RESHUFFLE and _failed_attempts >= 3:
                _failed_attempts = 0
                yield(reshuffle_board(), "completed")
                # Ensure at least one valid move exists, then yawn the next trio
                yield(ensure_moves_available(), "completed")
		var group = find_potential_match_group()
		if group.size() >= 3:
			# Yawn the three same-colored dots that would form the next match
			var target_color = group[0].color
			var trio: Array = []
			for d in group:
				if d != null and d.color == target_color:
					trio.append(d)
			if trio.size() >= 3:
				for d in trio:
					d.play_idle_animation()
		_restart_idle_timers()
	
func _process(_delta):
	if is_dragging and dragged_dot != null:
		dragged_dot.global_position = get_global_mouse_position()
		# If the mouse/touch was released over UI and the release event was consumed,
		# gracefully return the dot to its original cell.
        if not Input.is_mouse_button_pressed(BUTTON_LEFT) and not Input.is_action_pressed("ui_touch"):
			var start_grid_pos = pixel_to_grid(drag_start_position.x, drag_start_position.y)
			dragged_dot.move(grid_to_pixel(start_grid_pos.x, start_grid_pos.y))
			dragged_dot.set_normal_texture()
			dragged_dot = null
			is_dragging = false
	
func find_matches():
	var groups = _compute_match_groups()
	var matched_dots = _apply_specials_and_collect(groups)
	if matched_dots.size() > 0:
		process_match_animations(matched_dots)
		destroy_timer.start()
	else:
		swap_back()

func process_match_animations(dots_in_match):
	var unique_dots = []
	for dot in dots_in_match:
		if dot != null and not dot in unique_dots:
			unique_dots.append(dot)

	# Sort dots for systematic animation
	unique_dots.sort_custom(func(a, b): return a.position.x < b.position.x or (a.position.x == b.position.x and a.position.y < b.position.y))

	var delay = 0.0
	var matched_color = ""
	for dot in unique_dots:
		if not dot.matched:
			dot.matched = true
			# When each dot finishes fading out, spawn its XP orb immediately via signal
                        if not dot.is_connected("match_faded", self, "_on_dot_match_faded"):
                                dot.connect("match_faded", self, "_on_dot_match_faded")
			dot.play_match_animation(delay)
			delay += 0.05
			if matched_color == "":
				matched_color = dot.color

	# Trigger surprised animation for all non-matching dots
	for i in range(width):
		for j in range(height):
			var current_dot = all_dots[i][j]
			if current_dot != null and not current_dot.matched:
				current_dot.play_surprised_for_a_second()

func destroy_matches():
	var was_matched = false
	var points_earned = 0
	var match_center = Vector2.ZERO
	var match_count = 0
	for i in range(width):
		for j in range(height):
			if all_dots[i][j] != null and all_dots[i][j].matched:
				was_matched = true
				points_earned += 10 * combo_counter
				match_center += all_dots[i][j].position
				match_count += 1
				
				# Instantiate original particles
				var particles = match_particles.instance()
				particles.position = all_dots[i][j].position
				add_child(particles)
				# If an orb wasn't already spawned on fade completion, spawn it now as a fallback
				if not all_dots[i][j].orb_spawned:
					_spawn_xp_orb(all_dots[i][j].global_position, all_dots[i][j].color)
				if all_dots[i][j].float_tween:
					all_dots[i][j].float_tween.kill()
				if all_dots[i][j].pulse_tween:
					all_dots[i][j].pulse_tween.kill()
				all_dots[i][j].queue_free()
				all_dots[i][j] = null
	
	if points_earned > 0:
		# Multiplayer: report score delta
		if (Engine.has_singleton("MultiplayerManager") or (typeof(MultiplayerManager) != TYPE_NIL)) and (Engine.has_singleton("WebSocketClient") or (typeof(WebSocketClient) != TYPE_NIL)):
			var ng = get_tree().get_current_scene().get_node_or_null("NetGame")
			if ng != null and ng.has_method("report_local_score"):
				ng.call("report_local_score", points_earned)
			else:
				WebSocketClient.send_game_event("score", {"delta": points_earned})
		# Achievement: Beginner's Luck (first match)
		if Engine.has_singleton("AchievementManager") or (typeof(AchievementManager) != TYPE_NIL):
			AchievementManager.unlock_achievement("beginners_luck")
		if match_count >= 5:
			AudioManager.play_sound("match_fanfare")
		elif match_count == 4:
			AudioManager.play_sound("match_chime")
		else:
			AudioManager.play_sound("match_pop")
		score += points_earned
		PlayerManager.add_xp(points_earned)
		# Fill the MEANER METER by number of dots matched
		# Fill MEANER METER twice as fast by doubling the contribution
		PlayerManager.add_to_meaner_meter(match_count * 2)
		# Apply XP multiplier bonus if active
		if _xp_mult_remaining > 0:
			var boosted: int = int(points_earned * _xp_mult_value)
			# Subtract original already added; add the difference
			if boosted > points_earned:
				PlayerManager.add_xp(boosted - points_earned)
			_xp_mult_remaining -= 1
		PlayerManager.add_lines_cleared(match_count)
		PlayerManager.update_best_combo(combo_counter)
		combo_counter += 1
		_failed_attempts = 0
		_restart_idle_timers()
		update_score_display()
		
		# Instantiate new effects at the center of the match
		if match_count > 0:
			match_center /= match_count

			var match_label = match_label_scene.instance()
			match_label.text = "+" + str(points_earned)
			get_parent().get_node("CanvasLayer").add_child(match_label)
			match_label.global_position = match_center - Vector2(0, 20)
	
	move_checked = true
	if was_matched:
		collapse_timer.start()
	else:
		swap_back()

func _dots_match(a, b) -> bool:
	if a == null or b == null:
		return false
	# Godot has no hasattr(); identify Dot nodes by method and check property safely
	if a.has_method("set_wildcard") and a.get("is_wildcard"):
		return true
	if b.has_method("set_wildcard") and b.get("is_wildcard"):
		return true
	return a.color == b.color

func _apply_pending_bonus() -> void:
	if typeof(PlayerManager.player_data) != TYPE_DICTIONARY:
		return
	var pending: Dictionary = PlayerManager.player_data.get("pending_bonus", {})
	if typeof(pending) != TYPE_DICTIONARY or pending.size() == 0:
		return
	# Wildcards
	if pending.has("wildcards"):
		var count: int = int(pending["wildcards"])
		_apply_wildcards(count)
	# Row/Col clears
	if pending.has("clear_rows"):
		_apply_clear_rows(int(pending["clear_rows"]))
	if pending.has("clear_cols"):
		_apply_clear_cols(int(pending["clear_cols"]))
	# XP multiplier
	if pending.has("xp_multiplier"):
		var mult_data = pending["xp_multiplier"]
		if typeof(mult_data) == TYPE_DICTIONARY:
			_xp_mult_value = int(mult_data.get("mult", 1))
			_xp_mult_remaining = int(mult_data.get("matches", 0))
	# Clear pending once applied
	PlayerManager.player_data["pending_bonus"] = {}
	PlayerManager.save_player_data()
	# If any rows/cols flagged, destroy them now
	if destroy_timer != null:
		destroy_timer.start()

func _apply_wildcards(count: int) -> void:
	var positions: Array = []
	for i in range(width):
		for j in range(height):
			if all_dots[i][j] != null:
				positions.append(Vector2(i, j))
	positions.shuffle()
	var applied: int = 0
	for p in positions:
		if applied >= count:
			break
		var d = all_dots[p.x][p.y]
		if d != null and d.has_method("set_wildcard"):
			d.set_wildcard(true)
			applied += 1

func _apply_clear_rows(num: int) -> void:
	var rows: Array[int] = []
	for j in range(height):
		rows.append(j)
	rows.shuffle()
	for k in range(min(num, rows.size())):
		var row: int = rows[k]
		for x in range(width):
			if all_dots[x][row] != null:
				all_dots[x][row].matched = true

func _apply_clear_cols(num: int) -> void:
	var cols: Array[int] = []
	for i in range(width):
		cols.append(i)
	cols.shuffle()
	for k in range(min(num, cols.size())):
		var col: int = cols[k]
		for y in range(height):
			if all_dots[col][y] != null:
				all_dots[col][y].matched = true

func _compute_match_groups() -> Array:
	var groups: Array = []
	# Horizontal runs
	for j in range(height):
		var i = 0
		while i < width:
			var run: Array = []
			var start_i = i
			if all_dots[i][j] == null:
				i += 1
				continue
			run.append(Vector2(i, j))
			var k = i + 1
			while k < width and all_dots[k][j] != null and _dots_match(all_dots[k-1][j], all_dots[k][j]):
				run.append(Vector2(k, j))
				k += 1
			if run.size() >= 3:
				groups.append({"positions": run.duplicate(), "orientation": "h"})
			i = k if k > start_i else i + 1
	# Vertical runs
	for i in range(width):
		var j = 0
		while j < height:
			var run2: Array = []
			var start_j = j
			if all_dots[i][j] == null:
				j += 1
				continue
			run2.append(Vector2(i, j))
			var k2 = j + 1
			while k2 < height and all_dots[i][k2] != null and _dots_match(all_dots[i][k2-1], all_dots[i][k2]):
				run2.append(Vector2(i, k2))
				k2 += 1
			if run2.size() >= 3:
				groups.append({"positions": run2.duplicate(), "orientation": "v"})
			j = k2 if k2 > start_j else j + 1
	return groups

func _apply_specials_and_collect(groups: Array) -> Array:
	var to_match: Array = []
	var excluded_positions: Array = []
	for g in groups:
		var pos: Array = g["positions"]
		var orient: String = g["orientation"]
		if pos.size() >= 5:
			# Create a wildcard in the center of the run; exclude it from matching now
			var mid_index: int = pos.size() >> 1
			var p: Vector2 = pos[mid_index]
			var d = all_dots[p.x][p.y]
			if d != null:
				if d.has_method("set_wildcard"):
					d.set_wildcard(true)
				if AudioManager != null:
					AudioManager.play_sound("wildcard_spawn")
			# Achievement: Justify the Means (create wildcard)
			if Engine.has_singleton("AchievementManager") or (typeof(AchievementManager) != TYPE_NIL):
				AchievementManager.unlock_achievement("justify_the_means")
			excluded_positions.append(p)
			# Match the rest of the run
			for p2 in pos:
				if excluded_positions.find(p2) == -1:
					var dd = all_dots[p2.x][p2.y]
					if dd != null and not dd in to_match:
						to_match.append(dd)
		elif pos.size() == 4:
			# Line clear in the match direction
			if orient == "h":
				var row = pos[0].y
				for x in range(width):
					var drow = all_dots[x][row]
					if drow != null and not drow in to_match:
						to_match.append(drow)
				_spawn_row_sweep(row)
			else:
				var col = pos[0].x
				for y in range(height):
					var dcol = all_dots[col][y]
					if dcol != null and not dcol in to_match:
						to_match.append(dcol)
				_spawn_col_sweep(col)
			if AudioManager != null:
				AudioManager.play_sound("line_clear")
			# Achievement: On the Ball (clear a 4-in-a-row)
			if Engine.has_singleton("AchievementManager") or (typeof(AchievementManager) != TYPE_NIL):
				AchievementManager.unlock_achievement("on_the_ball")
		else:
			# Standard triple (or larger) – match all in this run
			for p3 in pos:
				var d3 = all_dots[p3.x][p3.y]
				if d3 != null and not d3 in to_match:
					to_match.append(d3)
	return to_match

# Visual sweep effects for line clears
var _white_tex: Texture = null

func _get_white_tex() -> Texture:
	if _white_tex != null:
		return _white_tex
	var img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(1,1,1,1))
	_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

func _spawn_row_sweep(row: int) -> void:
	var tex = _get_white_tex()
        var sprite = Sprite.new()
	sprite.texture = tex
	sprite.modulate = Color(1,1,1,0.45)
	sprite.z_index = 1000
	# Size
	var total_w = float(width - 1) * float(offset) + float(offset)
	var thickness = float(offset) * 0.6
	# Center position for the row
	var center_x = x_start + float(offset) * ((float(width) - 1.0) * 0.5)
	var center_y = y_start + -float(offset) * float(row)
	sprite.position = Vector2(center_x - 40.0, center_y)
	sprite.scale = Vector2(total_w, thickness)
	add_child(sprite)
	# Animate slight slide and fade out
	var t = get_tree().create_tween()
	t.tween_property(sprite, "position:x", center_x + 40.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
        t.parallel().tween_property(sprite, "modulate:a", 0.0, 0.22)
        t.connect("finished", sprite, "queue_free")

func _spawn_col_sweep(col: int) -> void:
	var tex = _get_white_tex()
        var sprite = Sprite.new()
	sprite.texture = tex
	sprite.modulate = Color(1,1,1,0.45)
	sprite.z_index = 1000
	# Size
	var total_h = float(height - 1) * float(offset) + float(offset)
	var thickness = float(offset) * 0.6
	# Center position for the column
	var center_x = x_start + float(offset) * float(col)
	var center_y = y_start + -float(offset) * ((float(height) - 1.0) * 0.5)
	sprite.position = Vector2(center_x, center_y - 40.0)
	sprite.scale = Vector2(thickness, total_h)
	add_child(sprite)
	# Animate slight slide and fade out
	var t = get_tree().create_tween()
	t.tween_property(sprite, "position:y", center_y + 40.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
        t.parallel().tween_property(sprite, "modulate:a", 0.0, 0.22)
        t.connect("finished", sprite, "queue_free")

func _spawn_xp_orb(from_global_pos: Vector2, color_name: String = ""):
	var layer = get_parent().get_node("CanvasLayer")
        var orb = Sprite.new()
	orb.texture = xp_orb_texture
	orb.scale = Vector2(0.45, 0.45)
	orb.global_position = from_global_pos
	var tint = xp_orb_colors.get(color_name, Color(1,1,1))
	orb.modulate = tint
	layer.add_child(orb)
	var target = game_ui.get_xp_anchor_pos()
	# Override X to center of the viewport; keep current Y
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	target.x = vp_size.x * 0.5

	# Swirl path: two control points offset around a curve toward the target
	var to_target = (target - from_global_pos)
	var perp = Vector2(-to_target.y, to_target.x).normalized()
	var cp1 = from_global_pos + to_target * 0.33 + perp * 60.0
	var cp2 = from_global_pos + to_target * 0.66 - perp * 40.0

	var t = get_tree().create_tween()
	t.tween_property(orb, "global_position", cp1, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(orb, "global_position", cp2, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(orb, "global_position", target, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Spin and fade near the end
	t.parallel().tween_property(orb, "rotation_degrees", orb.rotation_degrees + 360.0, 0.5)
        t.parallel().tween_property(orb, "modulate:a", 0.0, 0.15).set_delay(0.45)
        t.connect("finished", orb, "queue_free")

# Called when a dot finishes its match fade-out; spawns the orb immediately.
func _on_dot_match_faded(pos: Vector2, color_name: String):
	_spawn_xp_orb(pos, color_name)

func collapse_columns():
	for i in range(width):
		for j in range(height):
			if all_dots[i][j] == null and not restricted_fill(Vector2(i,j)):
				for k in range(j + 1, height):
					if all_dots[i][k] != null:
						all_dots[i][k].z_index = height - j
						all_dots[i][k].move(grid_to_pixel(i, j))
						all_dots[i][j] = all_dots[i][k]
						all_dots[i][k] = null
						break
	refill_timer.start()

func refill_columns():
	for i in range(width):
		for j in range(height):
			if all_dots[i][j] == null and not restricted_fill(Vector2(i,j)):
				# Choose color from active pool then instantiate matching scene
				var pool = possible_colors
				var rand = floor(randf_range(0, pool.size()))
				var desired_color = pool[rand]
				var dot_scene_to_use = null
				for dot_scene in possible_dots:
					var probe = dot_scene.instance()
					if probe.color == desired_color:
						dot_scene_to_use = dot_scene
						probe.queue_free()
						break
					probe.queue_free()
				var dot = dot_scene_to_use.instance()
				var loops = 0
				while (match_at(i, j, dot.color) && loops < 100):
					var pr = dot
					pr.queue_free()
					rand = floor(randf_range(0, pool.size()))
					desired_color = pool[rand]
					# Find scene for new desired color
					dot_scene_to_use = null
					for dot_scene in possible_dots:
						var probe2 = dot_scene.instance()
						if probe2.color == desired_color:
							dot_scene_to_use = dot_scene
							probe2.queue_free()
							break
						probe2.queue_free()
					dot = dot_scene_to_use.instance()
					loops += 1
				dot.z_index = height - j
				add_child(dot)
				dot.position = grid_to_pixel(i, j - y_offset)
				var move_tween = dot.move(grid_to_pixel(i,j), 0.12)
				all_dots[i][j] = dot
				
                                yield(move_tween, "finished")
				AudioManager.play_sound("dot_land")
	after_refill()
				
func after_refill():
	# Synchronize all dots' pulsing animation
	for i in range(width):
		for j in range(height):
			if all_dots[i][j] != null:
				all_dots[i][j].start_pulsing()

        state = wait
        yield(get_tree().create_timer(0.5), "timeout")
	
	var needs_another_pass = false
	for i in range(width):
		for j in range(height):
			if all_dots[i][j] != null:
				if match_at(i, j, all_dots[i][j].color):
					needs_another_pass = true
					break
			if needs_another_pass:
				break
			
	if needs_another_pass:
		find_matches_after_refill()
	else:
		state = move
		move_checked = false
                yield(ensure_moves_available(), "completed")
		state = move

func find_matches_after_refill():
	var groups = _compute_match_groups()
	var matched_dots = _apply_specials_and_collect(groups)
	if matched_dots.size() > 0:
		process_match_animations(matched_dots)
		destroy_timer.start()

func _on_idle_timer_timeout():
	# After short inactivity, gently hint a valid move by making that
	# No reshuffle here; this is just a suggestion.
	var dot_to_yawn = find_potential_match()
	if dot_to_yawn != null:
		dot_to_yawn.play_idle_animation()
	# Restart only the idle timer
	if idle_timer != null:
		idle_timer.start()

func _on_inactivity_timeout():
	# After a longer inactivity window, reshuffle (without immediate matches), then hint a move.
	if not AUTO_RESHUFFLE:
		return
        yield(reshuffle_board(), "completed")
        yield(ensure_moves_available(), "completed")
	var group = find_potential_match_group()
	if group.size() >= 3:
		var target_color = group[0].color
		var trio = []
		for d in group:
			if d != null and d.color == target_color:
				trio.append(d)
		if trio.size() >= 3:
			for d in trio:
				d.play_idle_animation()
	_restart_idle_timers()

func find_potential_match():
	for i in range(width):
		for j in range(height):
			if all_dots[i][j] == null: continue
			
			# Test swap right
			if i < width - 1 and all_dots[i+1][j] != null:
				var match_color = can_move_create_match(i, j, Vector2.RIGHT)
				if match_color != null:
					if all_dots[i][j].color == match_color:
						return all_dots[i][j]
					else:
						return all_dots[i+1][j]
		
			# Test swap down
			if j < height - 1 and all_dots[i][j+1] != null:
				var match_color = can_move_create_match(i, j, Vector2.DOWN)
				if match_color != null:
					if all_dots[i][j].color == match_color:
						return all_dots[i][j]
					else:
						return all_dots[i][j+1]
	return null

# Returns an array of Dot nodes (size >= 3) that would form a match if a single swap is made.
func find_potential_match_group():
	# Returns an array of the three Dot nodes (same color pre-swap) that would form a match after a swap.
	for i in range(width):
		for j in range(height):
			if all_dots[i][j] == null:
				continue
			# Test swap right
			if i < width - 1 and all_dots[i+1][j] != null and can_move_create_match(i, j, Vector2.RIGHT):
				var pos = _compute_yawn_group_for_swap(i, j, Vector2.RIGHT)
				if pos.size() >= 3:
					var nodes = []
					for p in pos:
						if all_dots[p.x][p.y] != null:
							nodes.append(all_dots[p.x][p.y])
					return nodes
			# Test swap down
			if j < height - 1 and all_dots[i][j+1] != null and can_move_create_match(i, j, Vector2.DOWN):
				var pos2 = _compute_yawn_group_for_swap(i, j, Vector2.DOWN)
				if pos2.size() >= 3:
					var nodes2 = []
					for p2 in pos2:
						if all_dots[p2.x][p2.y] != null:
							nodes2.append(all_dots[p2.x][p2.y])
					return nodes2
	return []

# Internal helper: returns the three board positions (Vector2) that would match after swapping (i,j) by direction.
func _compute_match_triplet_after_swap(i, j, direction):
	var di: int = int(direction.x)
	var dj: int = int(direction.y)
	var other_i: int = i + di
	var other_j: int = j + dj
	if other_i < 0 or other_i >= width or other_j < 0 or other_j >= height:
		return []
	if all_dots[i][j] == null or all_dots[other_i][other_j] == null:
		return []

	var original_color = all_dots[i][j].color
	var other_color = all_dots[other_i][other_j].color

	# Build a temp grid of colors
	var temp_all_dots = []
	for x in range(width):
		temp_all_dots.append([])
		for y in range(height):
			if all_dots[x][y] != null:
				temp_all_dots[x].append(all_dots[x][y].color)
			else:
				temp_all_dots[x].append(null)

	# Apply the swap
	temp_all_dots[i][j] = other_color
	temp_all_dots[other_i][other_j] = original_color

	# Check for triplets centered on the 'other' position
	# Horizontal center
	if other_i > 0 and other_i < width - 1:
		if temp_all_dots[other_i - 1][other_j] == other_color and temp_all_dots[other_i + 1][other_j] == other_color:
			return [Vector2(other_i - 1, other_j), Vector2(other_i, other_j), Vector2(other_i + 1, other_j)]
	# Vertical center
	if other_j > 0 and other_j < height - 1:
		if temp_all_dots[other_i][other_j - 1] == other_color and temp_all_dots[other_i][other_j + 1] == other_color:
			return [Vector2(other_i, other_j - 1), Vector2(other_i, other_j), Vector2(other_i, other_j + 1)]

	# Check for triplets centered on the original position
	# Note: After swap, original position (i,j) holds 'other_color'
	if i > 0 and i < width - 1:
		if temp_all_dots[i - 1][j] == other_color and temp_all_dots[i + 1][j] == other_color:
			return [Vector2(i - 1, j), Vector2(i, j), Vector2(i + 1, j)]
	if j > 0 and j < height - 1:
		if temp_all_dots[i][j - 1] == other_color and temp_all_dots[i][j + 1] == other_color:
			return [Vector2(i, j - 1), Vector2(i, j), Vector2(i, j + 1)]

	return []

# Internal helper: returns the three board positions (Vector2) that are the same color pre-swap
# and would be the matched set after swapping (i,j) by direction. This excludes the off-color
# dot that needs to move when the triplet is centered on the original position.
func _compute_yawn_group_for_swap(i, j, direction):
	var di: int = int(direction.x)
	var dj: int = int(direction.y)
	var other_i: int = i + di
	var other_j: int = j + dj
	if other_i < 0 or other_i >= width or other_j < 0 or other_j >= height:
		return []
	if all_dots[i][j] == null or all_dots[other_i][other_j] == null:
		return []

	var original_color = all_dots[i][j].color
	var other_color = all_dots[other_i][other_j].color

	# Build a temp grid of colors
	var temp_all_dots = []
	for x in range(width):
		temp_all_dots.append([])
		for y in range(height):
			if all_dots[x][y] != null:
				temp_all_dots[x].append(all_dots[x][y].color)
			else:
				temp_all_dots[x].append(null)

	# Apply the swap in the temp grid
	temp_all_dots[i][j] = other_color
	temp_all_dots[other_i][other_j] = original_color

	# Case 1: triplet centered on 'other' position
	if other_i > 0 and other_i < width - 1:
		if temp_all_dots[other_i - 1][other_j] == other_color and temp_all_dots[other_i + 1][other_j] == other_color:
			return [Vector2(other_i - 1, other_j), Vector2(other_i, other_j), Vector2(other_i + 1, other_j)]
	if other_j > 0 and other_j < height - 1:
		if temp_all_dots[other_i][other_j - 1] == other_color and temp_all_dots[other_i][other_j + 1] == other_color:
			return [Vector2(other_i, other_j - 1), Vector2(other_i, other_j), Vector2(other_i, other_j + 1)]

	# Case 2: triplet centered on 'original' position after swap: yaw should include the two like-colored
	# neighbors around the original position, plus the 'other' dot which shares that color pre-swap.
	if i > 0 and i < width - 1:
		if temp_all_dots[i - 1][j] == other_color and temp_all_dots[i + 1][j] == other_color:
			return [Vector2(i - 1, j), Vector2(i + 1, j), Vector2(other_i, other_j)]
	if j > 0 and j < height - 1:
		if temp_all_dots[i][j - 1] == other_color and temp_all_dots[i][j + 1] == other_color:
			return [Vector2(i, j - 1), Vector2(i, j + 1), Vector2(other_i, other_j)]

	return []

func ensure_moves_available(max_attempts = 10):
        var attempts = 0
        while find_potential_match() == null and attempts < max_attempts:
                attempts += 1
                var reshuffle_state = reshuffle_board()
                var shuffled = yield(reshuffle_state, "completed")
                if not shuffled:
                        break

	# If we still have no move after several reshuffles, just warn; stage rotations will manage variety
	if find_potential_match() == null:
		push_warning("Unable to find a valid move after reshuffling.")

	_restart_idle_timers()

# Returns true if the provided matrix of Dot nodes contains any immediate
# horizontal or vertical 3-in-a-row matches.
func _matrix_has_immediate_match(matrix: Array) -> bool:
	# Horizontal scan
	for j in range(height):
		for i in range(width - 2):
			var a = matrix[i][j]
			var b = matrix[i + 1][j]
			var c = matrix[i + 2][j]
			if a != null and b != null and c != null:
				if a.color == b.color and b.color == c.color:
					return true
	# Vertical scan
	for i in range(width):
		for j in range(height - 2):
			var a2 = matrix[i][j]
			var b2 = matrix[i][j + 1]
			var c2 = matrix[i][j + 2]
			if a2 != null and b2 != null and c2 != null:
				if a2.color == b2.color and b2.color == c2.color:
					return true
	return false

func reshuffle_board() -> bool:
	var dots: Array = []
	var occupied_cells: Array = []
	for i in range(width):
		for j in range(height):
			if all_dots[i][j] != null:
				dots.append(all_dots[i][j])
				occupied_cells.append(Vector2(i, j))

	if dots.size() <= 1:
		return false

	is_dragging = false
	dragged_dot = null

	state = wait
	if AudioManager != null:
		AudioManager.play_sound("shuffle")



	var valid_matrix: Array = []
	var target_cells: Array
	var final_target_cells: Array = []
	var attempts: int = 0
	var max_attempts: int = 200
	while attempts < max_attempts:
		attempts += 1
		target_cells = occupied_cells.duplicate()
		target_cells.shuffle()
		var candidate = make_2d_array()
		for idx in range(dots.size()):
			var dot = dots[idx]
			var target_cell: Vector2 = target_cells[idx]
			candidate[target_cell.x][target_cell.y] = dot
		# If the candidate contains any immediate matches, try again
		if _matrix_has_immediate_match(candidate):
			continue
		valid_matrix = candidate
		final_target_cells = target_cells.duplicate()
		break

	# If we failed to find a no-match layout, fall back to the last candidate
	# (very unlikely on typical boards). This keeps the game from freezing.
	if valid_matrix.size() == 0:
		valid_matrix = make_2d_array()
		var tc = occupied_cells.duplicate()
		tc.shuffle()
		for idx in range(dots.size()):
			var d = dots[idx]
			var cell: Vector2 = tc[idx]
			valid_matrix[cell.x][cell.y] = d
		final_target_cells = tc

	var tweens: Array = []
	var offset_range = offset * 0.3
	for idx in range(dots.size()):
		var dot2 = dots[idx]
		var target_cell2 = final_target_cells[idx]
		# Update z-order and flags prior to animation
		dot2.matched = false
		dot2.z_index = height - target_cell2.y
		var start_pos = dot2.position
		var target_pos = grid_to_pixel(target_cell2.x, target_cell2.y)
		var tween = get_tree().create_tween()
		var random_offset = Vector2(randf_range(-offset_range, offset_range), randf_range(-offset_range, offset_range))
		tween.tween_property(dot2, "position", start_pos + random_offset, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(dot2, "position", target_pos, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tweens.append(tween)

	all_dots = valid_matrix
	move_checked = false

        if tweens.size() > 0:
                yield(tweens.back(), "finished")

	state = move
	# Normalize dot animations after reshuffle
	for ii in range(width):
		for jj in range(height):
			var dnode = all_dots[ii][jj]
			if dnode == null:
				continue
			if dnode.has_method("start_floating"):
				dnode.start_floating()
			if dnode.has_method("start_pulsing"):
				dnode.start_pulsing()
	return true

func can_move_create_match(i, j, direction):
	var di: int = int(direction.x)
	var dj: int = int(direction.y)
	var other_i: int = i + di
	var other_j: int = j + dj
	if other_i < 0 or other_i >= width or other_j < 0 or other_j >= height:
		return null

	if all_dots[i][j] == null or all_dots[other_i][other_j] == null:
		return null

	var original_color = all_dots[i][j].color
	var other_color = all_dots[other_i][other_j].color

	var temp_all_dots = []
	for x in range(width):
		temp_all_dots.append([])
		for y in range(height):
			if all_dots[x][y] != null:
				temp_all_dots[x].append(all_dots[x][y].color)
			else:
				temp_all_dots[x].append(null)

	temp_all_dots[i][j] = other_color
	temp_all_dots[other_i][other_j] = original_color

	# Check for matches
	for x in range(width):
		for y in range(height):
			var color = temp_all_dots[x][y]
			if color == null: continue
			# Horizontal
			if x < width - 2 and temp_all_dots[x+1][y] == color and temp_all_dots[x+2][y] == color:
				return color
			# Vertical
			if y < height - 2 and temp_all_dots[x][y+1] == color and temp_all_dots[x][y+2] == color:
				return color
	return null

func _on_level_up(new_level):
        print("Level up to: " + str(new_level))
        yield(celebrate_stage_transition(new_level), "completed")
        # Clear and respawn for next stage

        for i in range(width):
                for j in range(height):
                        if all_dots[i][j] != null:
                                all_dots[i][j].queue_free()
        all_dots = make_2d_array()
        spawn_dots()

        yield(ensure_moves_available(), "completed")
        state = move

func celebrate_stage_transition(new_level):
        state = wait
        yield(play_wave_animation(), "completed")
        yield(play_dance_animation(), "completed")
        yield(show_stage_banner(new_level), "completed")
	state = move

func play_wave_animation():
	# Left-to-right stadium wave: each column rises then falls, delayed per column.
	var delay_per_column = 0.08
	var row_phase_offset = 0.015
	var rise = 0.12
	var fall = 0.12
	var height_px = 14.0
	var max_delay = 0.0
	for i in range(width):
		for j in range(height):
			var dot = all_dots[i][j]
			if dot == null:
				continue
			var delay = i * delay_per_column + j * row_phase_offset
			var tween = get_tree().create_tween()
			tween.tween_interval(delay)
			var up_pos = dot.position + Vector2(0, -height_px)
			tween.tween_property(dot, "position", up_pos, rise).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_property(dot, "position", dot.position, fall).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			if delay > max_delay:
				max_delay = delay
	# Allow final tweens to finish
        yield(get_tree().create_timer(max_delay + rise + fall), "timeout")
	# Smoothly return any rotation to 0 just in case
	for i in range(width):
		for j in range(height):
			var dot = all_dots[i][j]
			if dot == null:
				continue
			var tw = get_tree().create_tween()
			tw.tween_property(dot, "rotation_degrees", 0.0, 0.12)

# Synchronized level-up dances. Cycles through a few variants each level.

func play_dance_animation():
	# Small wiggle/scale for a short duration
	var max_duration = 0.6
	for i in range(width):
		for j in range(height):
			var dot = all_dots[i][j]
			if dot == null:
				continue
			var tween = get_tree().create_tween()
			tween.tween_property(dot, "rotation_degrees", 8, 0.15)
			tween.parallel().tween_property(dot, "scale", dot.scale * 1.08, 0.15)
			tween.tween_property(dot, "rotation_degrees", -8, 0.15)
			tween.parallel().tween_property(dot, "scale", dot.scale, 0.15)
        yield(get_tree().create_timer(max_duration), "timeout")

func show_stage_banner(new_level):
        var layer = get_parent().get_node("CanvasLayer")
        var tex: Texture = stage_banner_texture
	var vp = get_viewport().get_visible_rect().size
	var size = tex.get_size()
	var margin_y = 40.0

	var root = Control.new()
	root.name = "StageBanner"
	root.size = size
	root.position = Vector2((vp.x - size.x) * 0.5, vp.y - size.y - margin_y)
	layer.add_child(root)

	var banner = TextureRect.new()
	banner.texture = tex
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner.modulate.a = 0.0
	root.add_child(banner)

	var text = Label.new()
	text.text = "LEVEL UP!"
        text.align = Label.ALIGN_CENTER
        text.valign = Label.VALIGN_CENTER
        text.modulate = Color(1, 1, 1, 0.0)
        text.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.add_child(text)

        var t = get_tree().create_tween()
        t.tween_property(banner, "modulate:a", 1.0, 0.25)
        t.parallel().tween_property(text, "modulate:a", 1.0, 0.25)
        yield(t, "finished")
        yield(get_tree().create_timer(0.9), "timeout")
        var t2 = get_tree().create_tween()
        t2.tween_property(banner, "modulate:a", 0.0, 0.3)
        t2.parallel().tween_property(text, "modulate:a", 0.0, 0.3)
        yield(t2, "finished")
        root.queue_free()

func _exit_tree():
	# Stop any running timers to avoid lingering objects at shutdown
	for t in [destroy_timer, collapse_timer, refill_timer, idle_timer]:
		if t != null:
			t.stop()
