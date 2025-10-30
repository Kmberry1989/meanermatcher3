extends Control
class_name BonusSlotMachine

signal finished

const SYMBOL_SIZE: Vector2i = Vector2i(320, 320)
const SYMBOL_DIR: String = "res://Assets/BonusSlot"
# Preload textures in enum order: COIN, XP, WILDCARD, ROW_CLEAR, COL_CLEAR, MULT2X, MULT3X, FREE_SPIN
const SYMBOL_TEX: Array = [
	preload("res://Assets/BonusSlot/symbol_coin.png"),
	preload("res://Assets/BonusSlot/symbol_xp.png"),
	preload("res://Assets/BonusSlot/symbol_wildcard.png"),
	preload("res://Assets/BonusSlot/symbol_row_clear.png"),
	preload("res://Assets/BonusSlot/symbol_col_clear.png"),
	preload("res://Assets/BonusSlot/symbol_multiplier_2x.png"),
	preload("res://Assets/BonusSlot/symbol_multiplier_3x.png"),
	preload("res://Assets/BonusSlot/symbol_free_spin.png")
]
var _symbol_size: Vector2i = SYMBOL_SIZE

enum SymbolId { COIN, XP, WILDCARD, ROW_CLEAR, COL_CLEAR, MULT2X, MULT3X, FREE_SPIN }

var _symbols: Array = []
var _result_label: Label = null
var _spin_button: BaseButton = null
var _reels: Array[Control] = []
var _stops: Array[int] = []
var _spinning: bool = false
var _glows: Array[TextureRect] = []
var _finished: bool = false
var _reel_tracks: Array = []
var _reels_stopped: int = 0
var _stop_targets: Array[int] = []
var _reel_orders: Array = []
var _awaiting_ack: bool = false
var _post_ack_action: String = "close"  # "close" or "spin_again"

# Optional: manually assign textures per reel from the editor
@export var apply_manual_textures_on_ready: bool = false
@export var reel1_textures: Array[Texture2D] = []
@export var reel2_textures: Array[Texture2D] = []
@export var reel3_textures: Array[Texture2D] = []
@export var use_fallback_color_reels: bool = true
@export var use_placeholders_if_missing: bool = true
@export var placeholder_save_dir: String = "user://bonus_slot_placeholders"
@export var placeholder_overwrite_existing: bool = false

func _ready() -> void:
	_layout_for_viewport()
	_symbols = [
		{"id": SymbolId.COIN, "name": "COIN", "color": Color(1.0, 0.85, 0.2)},
		{"id": SymbolId.XP, "name": "XP", "color": Color(0.3, 0.7, 1.0)},
		{"id": SymbolId.WILDCARD, "name": "WILD", "color": Color(0.9, 0.4, 1.0)},
		{"id": SymbolId.ROW_CLEAR, "name": "ROW", "color": Color(0.9, 0.3, 0.3)},
		{"id": SymbolId.COL_CLEAR, "name": "COL", "color": Color(0.3, 0.9, 0.4)},
		{"id": SymbolId.MULT2X, "name": "2x", "color": Color(1.0, 0.6, 0.2)},
		{"id": SymbolId.MULT3X, "name": "3x", "color": Color(1.0, 0.3, 0.2)},
		{"id": SymbolId.FREE_SPIN, "name": "FREE", "color": Color(0.8, 0.8, 0.8)}
	]
	# Pre-attach preloaded textures so reels show art immediately
	for i in range(_symbols.size()):
		var sid: int = int(_symbols[i].get("id", -1))
		if sid >= 0 and sid < SYMBOL_TEX.size() and SYMBOL_TEX[sid] != null:
			_symbols[i]["tex"] = SYMBOL_TEX[sid]
	_result_label = $Panel/VBox/ResultLabel as Label
	_spin_button = $Panel/VBox/HBox/SpinButton as BaseButton
	_reels = [
		$Panel/VBox/Reels/Reel1 as Control,
		$Panel/VBox/Reels/Reel2 as Control,
		$Panel/VBox/Reels/Reel3 as Control
	]
	_glows = [
		$Panel/VBox/Reels/Reel1/Glow as TextureRect,
		$Panel/VBox/Reels/Reel2/Glow as TextureRect,
		$Panel/VBox/Reels/Reel3/Glow as TextureRect
	]
	# Ensure glows overlay exactly the reel window
	_align_glows_to_reels()
	# Load any provided symbol_* textures before building reels so tiles use your art
	_load_symbol_textures()
	for r in _reels:
		_build_reel(r)
	# Attach SlotReel behavior to each reel and configure textures
	var reel_script = load("res://Scripts/SlotReel.gd")
	var imgs: Array[Texture2D] = []
	for d in _symbols:
		var tex: Texture2D = d.get("tex", null)
		if tex != null:
			imgs.append(tex)
	for i in range(_reels.size()):
		var r = _reels[i]
		if r.get_script() == null:
			r.set_script(reel_script)
		if r.has_method("setup_reel"):
			r.call("setup_reel", imgs, 3, _symbol_size, 180.0)
		if r.has_signal("spin_finished"):
			var cb := Callable(self, "_on_slot_reel_finished").bind(i)
			if not r.is_connected("spin_finished", cb):
				r.connect("spin_finished", cb)
	# If requested, apply editor-provided textures per reel (visual only)
	_apply_manual_textures_from_exports()
	_apply_assets()
	_animate_in()

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		if not is_inside_tree():
			return
		_layout_for_viewport()
		_align_glows_to_reels()

func _build_reel(reel: Control) -> void:
	reel.clip_contents = true
	reel.custom_minimum_size = Vector2(_symbol_size)
	var track: VBoxContainer = VBoxContainer.new()
	track.name = "Track"
	track.position = Vector2.ZERO
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_FILL
	# Each symbol appears only once on the reel
	var order: Array = _symbols.duplicate()
	for s_idx in range(order.size()):
		var tile: Control = _make_symbol_tile(order[s_idx])
		track.add_child(tile)
	track.add_child(_make_symbol_tile(_symbols[0]))
	reel.add_child(track)
	_reel_tracks.append(track)
	_reel_orders.append(order)

func _make_symbol_tile(sym: Dictionary) -> Control:
	var tile: Panel = Panel.new()
	tile.custom_minimum_size = Vector2(_symbol_size)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(sym.get("color", Color(0.5,0.5,0.5)))
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0,0,0,0.6)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	tile.add_theme_stylebox_override("panel", sb)
	var tex: Texture2D = sym.get("tex", null)
	if (not use_fallback_color_reels) and tex != null:
		# Use your provided art; make tile background transparent so color doesn't cover it
		sb.bg_color = Color(0,0,0,0)
		var tex_rect: TextureRect = TextureRect.new()
		tex_rect.texture = tex
		# Fill the available tile while preserving aspect (250x250 assets fit cleanly)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile.add_child(tex_rect)
	else:
		var lbl: Label = Label.new()
		lbl.text = String(sym.get("name", "?"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 64)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile.add_child(lbl)
	return tile

# Replace the visuals in a reel with the provided textures (order should match the internal symbol order).
# This only affects the artwork; symbol IDs and payouts remain unchanged.
func set_reel_symbol_textures(reel_index: int, textures: Array[Texture2D]) -> void:
	if reel_index < 0 or reel_index >= _reels.size():
		return
	var reel: Control = _reels[reel_index]
	var track: VBoxContainer = reel.get_node_or_null("Track") as VBoxContainer
	if track == null:
		return
	var block: int = _symbols.size()
	var loops: int = 3
	var max_count: int = min(track.get_child_count(), loops * block)
	for loop_i in range(loops):
		for s_idx in range(block):
			var idx: int = loop_i * block + s_idx
			if idx >= max_count:
				continue
			var tile: Control = track.get_child(idx) as Control
			var tex: Texture2D = null
			if s_idx < textures.size():
				tex = textures[s_idx]
			_apply_texture_to_tile(tile, tex)
	# Also update the last wrap tile to match the first symbol
	if track.get_child_count() > max_count:
		var last_tile: Control = track.get_child(max_count) as Control
		var first_tex: Texture2D = textures[0] if textures.size() > 0 else null
		_apply_texture_to_tile(last_tile, first_tex)

func _apply_texture_to_tile(tile: Control, tex: Texture2D) -> void:
	if use_fallback_color_reels:
		return
	# Ensure the tile shows a TextureRect with the provided texture; fall back to label if null
	var tex_rect: TextureRect = null
	for c in tile.get_children():
		if c is TextureRect:
			tex_rect = c
			break
	if tex_rect == null and tex != null:
		# Remove any label child
		for c in tile.get_children():
			if c is Label:
				c.queue_free()
		tex_rect = TextureRect.new()
		tile.add_child(tex_rect)
	if tex_rect != null:
		tex_rect.texture = tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# If we have a texture, make the panel background transparent
	var sb: StyleBox = tile.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var sbf := sb as StyleBoxFlat
		sbf.bg_color = Color(0,0,0, 0.0 if tex != null else 1.0)

func _apply_manual_textures_from_exports() -> void:
	if not apply_manual_textures_on_ready or use_fallback_color_reels:
		return
	set_reel_symbol_textures(0, reel1_textures)
	set_reel_symbol_textures(1, reel2_textures)
	set_reel_symbol_textures(2, reel3_textures)

func _on_SpinButton_pressed() -> void:
	# If we are waiting for player acknowledgment of the result, treat this as "Continue"
	if _awaiting_ack and not _spinning and not _finished:
		_finish_from_player_ack()
		return
	if _spinning or _finished:
		return
	_spinning = true
	_reels_stopped = 0
	_result_label.text = ""
	_spin_button.disabled = true
	if AudioManager != null:
		AudioManager.play_sound("slot_spin")
	var runtime := 4.0
	var speed := 12.0
	for i in range(_reels.size()):
		var delay := 0.15 * float(i)
		var r = _reels[i]
		if r.has_method("start_spin"):
			r.call("start_spin", runtime, speed, delay)

func _start_cascade_spin() -> void:
	# Start each reel with a slight offset for cascade effect
	for i in range(_reels.size()):
		_spin_reel_cascade(i)
		await get_tree().create_timer(0.15).timeout

func _spin_reel_cascade(reel_index: int) -> void:
	var track: VBoxContainer = _reel_tracks[reel_index]
	var tile_h: float = float(_symbol_size.y)
	var total_h: float = tile_h * float(_symbols.size())
	# Reset to top boundary to begin
	track.position.y = 0.0
	# Fast loops
	var loops := 3 + reel_index
	var loop_dur := 0.24
	for _k in range(loops):
		var t1 := create_tween()
		t1.tween_property(track, "position:y", -total_h, loop_dur).set_trans(Tween.TRANS_LINEAR)
		await t1.finished
		# Wrap back to top for continuous spin
		track.position.y = 0.0
	# Decelerate to target stop within [0, -total_h]
	var target_index: int = _stop_targets[reel_index]
	var final_y: float = -float(target_index) * tile_h
	var decel_dur := 0.9 + 0.35 * float(reel_index)
	var t2 := create_tween()
	t2.tween_property(track, "position:y", final_y, decel_dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t2.finished
	# Snap to exact boundary
	var snapped_steps: int = int(round(-track.position.y / tile_h))
	track.position.y = -float(snapped_steps) * tile_h
	if AudioManager != null:
		AudioManager.play_sound("slot_stop")
	_on_reel_stopped(reel_index)

func _on_reel_stopped(_reel_index: int) -> void:
	_reels_stopped += 1
	if _reels_stopped >= _reels.size():
		_spinning = false
		_spin_button.disabled = false
		_evaluate_cascade_result()

func _on_slot_reel_finished(index: int) -> void:
	if AudioManager != null:
		AudioManager.play_sound("slot_stop")
	_on_reel_stopped(index)

func _current_top_index(reel_index: int) -> int:
	var track: VBoxContainer = _reel_tracks[reel_index]
	var tile_h: float = float(_symbol_size.y)
	var steps: int = int(round(-track.position.y / tile_h))
	var block := _symbols.size()
	return ((steps % block) + block) % block

func _evaluate_cascade_result() -> void:
	var a := _get_top_from_reel(0)
	var b := _get_top_from_reel(1)
	var c := _get_top_from_reel(2)
	var ids: Array[int] = [a, b, c]
	var msg: String = ""
	var mask: Array[bool] = [false, false, false]
	var wants_spin_again: bool = false
	if a == b and b == c and a >= 0:
		# 3 of a kind
		msg = _apply_payout_3(a)
		mask = [true, true, true]
		if AudioManager != null:
			AudioManager.play_sound("slot_win")
		_confetti_burst_from([true, true, true], 1.0)
		# If the symbol is FREE_SPIN, acknowledge then spin again after player input
		if a == SymbolId.FREE_SPIN:
			wants_spin_again = true
		# Achievement: One Win Ever
		if Engine.has_singleton("AchievementManager") or (typeof(AchievementManager) != TYPE_NIL):
			AchievementManager.unlock_achievement("one_win_ever")
	elif a == b or b == c or a == c:
		# 2 of a kind
		var sym2: int = _majority_symbol(ids)
		msg = _apply_payout_2(sym2)
		for i in range(3):
			if ids[i] == sym2:
				mask[i] = true
		if AudioManager != null:
			AudioManager.play_sound("slot_win")
		_confetti_burst_from(mask, 0.6)
		# Achievement: One Win Ever
		if Engine.has_singleton("AchievementManager") or (typeof(AchievementManager) != TYPE_NIL):
			AchievementManager.unlock_achievement("one_win_ever")
	else:
		msg = _apply_payout_mixed()
		if AudioManager != null:
			AudioManager.play_sound("slot_fail")
	
	_result_label.text = msg
	# Highlight winning reels if applicable
	_show_reel_glows(mask)

	if wants_spin_again:
		# Pause here for player input to acknowledge the result
		_enter_result_ack(msg, "spin_again")
	else:
		_finish_after_delay()

func _get_top_from_reel(i: int) -> int:
	if i < 0 or i >= _reels.size():
		return -1
	var r = _reels[i]
	if r.has_method("get_top_symbol_index"):
		return int(r.call("get_top_symbol_index"))
	return -1

func _pick_symbol_index() -> int:
	var weights: Array[int] = [25, 20, 10, 8, 8, 12, 5, 12]
	var total: int = 0
	for w in weights:
		total += w
	var r: float = randf() * float(total)
	var acc: float = 0.0
	for i in range(weights.size()):
		acc += float(weights[i])
		if r <= acc:
			return i
	return 0

func _spin_reel(reel: Control, stop_index: int, duration: float) -> void:
	var track: VBoxContainer = reel.get_node("Track") as VBoxContainer
	var tile_h: float = float(_symbol_size.y)
	var per_loop: int = _symbols.size()
	var loops: int = 2
	var final_index: int = per_loop * loops + stop_index
	var final_y: float = -tile_h * float(final_index)
	track.position = Vector2(0, 0)
	var tick: Timer = Timer.new()
	tick.one_shot = false
	tick.wait_time = 0.08
	add_child(tick)
	tick.timeout.connect(func():
		if AudioManager != null:
			AudioManager.play_sound("slot_tick")
	)
	tick.start()
	var t: Tween = create_tween()
	t.tween_property(track, "position:y", final_y, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished
	track.position = Vector2(0, -tile_h * float(stop_index))
	if tick != null:
		tick.stop()
		tick.queue_free()
	if AudioManager != null:
		AudioManager.play_sound("slot_stop")
	var last_reel: bool = (reel == _reels[_reels.size() - 1])
	if last_reel:
		_evaluate_result()

func _evaluate_result() -> void:
	_spinning = false
	_spin_button.disabled = false
	var ids: Array[int] = []
	for i in range(3):
		var idx: int = int(_stops[i])
		ids.append(int(_symbols[idx]["id"]))
	var msg: String = ""
	var _success: bool = false
	var free_spin: bool = false
	if ids[0] == ids[1] and ids[1] == ids[2]:
		msg = _apply_payout_3(ids[0])
		_show_reel_glows([true, true, true])
		if AudioManager != null:
			AudioManager.play_sound("slot_win")
		_confetti_burst_from([true, true, true], 1.0)
		# Special case: 3x FREE_SPIN grants an immediate extra spin and should not count against attempts
		if ids[0] == SymbolId.FREE_SPIN:
			free_spin = true
			_success = false
		else:
			_success = true
	elif ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]:
		var sym2: int = _majority_symbol(ids)
		msg = _apply_payout_2(sym2)
		var mask: Array[bool] = [false, false, false]
		for i in range(3):
			if ids[i] == sym2:
				mask[i] = true
		_show_reel_glows(mask)
		if AudioManager != null:
			AudioManager.play_sound("slot_win")
		_confetti_burst_from(mask, 0.6)
		_success = true
		# Achievement: One Win Ever
		if Engine.has_singleton("AchievementManager") or (typeof(AchievementManager) != TYPE_NIL):
			AchievementManager.unlock_achievement("one_win_ever")
	else:
		msg = _apply_payout_mixed()
		_show_reel_glows([false, false, false])
		if AudioManager != null:
			AudioManager.play_sound("slot_fail")
	
	_result_label.text = msg
	# Handle free spin: acknowledge, then spin again on player input
	if free_spin:
		_enter_result_ack(msg, "spin_again")
		return
	
	_finish_after_delay()

func _enter_result_ack(msg: String, next_action: String = "close") -> void:
	_awaiting_ack = true
	_post_ack_action = next_action
	_spinning = false
	if _spin_button != null:
		_spin_button.disabled = false
		# If it's a normal Button, present clear call-to-action
		var btn: Button = _spin_button as Button
		if btn != null:
			btn.text = "CONTINUE"
	# Add a subtle hint on the label
	if _result_label != null and msg != "":
		var hint: String = "\nTap to spin again" if next_action == "spin_again" else "\nTap to continue"
		_result_label.text = msg + hint

func _finish_from_player_ack() -> void:
	if _finished:
		return
	var action := _post_ack_action
	_awaiting_ack = false
	_post_ack_action = "close"

	if action == "spin_again":
		# Start a new spin without closing the bonus overlay
		_on_SpinButton_pressed()
		return

func _unhandled_input(event: InputEvent) -> void:
	if not _awaiting_ack:
		return
	if event is InputEventMouseButton and event.pressed:
		_finish_from_player_ack()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		_finish_from_player_ack()
		get_viewport().set_input_as_handled()

func _majority_symbol(ids: Array[int]) -> int:
	if ids[0] == ids[1]:
		return ids[0]
	if ids[1] == ids[2]:
		return ids[1]
	return ids[0]

func _apply_payout_3(sym_id: int) -> String:
	match sym_id:
		SymbolId.COIN:
			PlayerManager.player_data["coins"] = PlayerManager.get_coins() + 100
			PlayerManager.emit_signal("coins_changed", PlayerManager.get_coins())
			PlayerManager.save_player_data()
			return "You've won 100 coins, which have been added to your balance."
		SymbolId.XP:
			PlayerManager.add_xp(600)
			return "You've gained 600 experience points."
		SymbolId.WILDCARD:
			_set_pending_bonus({"wildcards": 3})
			return "You've earned 3 wildcards for the next stage."
		SymbolId.ROW_CLEAR:
			_set_pending_bonus({"clear_rows": 2})
			return "You've earned 2 row-clearing bonuses for the next stage."
		SymbolId.COL_CLEAR:
			_set_pending_bonus({"clear_cols": 2})
			return "You've earned 2 column-clearing bonuses for the next stage."
		SymbolId.MULT2X:
			_set_pending_bonus({"xp_multiplier": {"mult": 2, "matches": 3}})
			return "For your next 3 matches, you will receive double experience points."
		SymbolId.MULT3X:
			_set_pending_bonus({"xp_multiplier": {"mult": 3, "matches": 1}})
			return "For your next match, you will receive triple experience points."
		SymbolId.FREE_SPIN:
			return "You've won a free spin!"
		_:
			return ""

func _apply_payout_2(sym_id: int) -> String:
	match sym_id:
		SymbolId.COIN:
			PlayerManager.player_data["coins"] = PlayerManager.get_coins() + 20
			PlayerManager.emit_signal("coins_changed", PlayerManager.get_coins())
			PlayerManager.save_player_data()
			return "You've won 20 coins."
		SymbolId.XP:
			PlayerManager.add_xp(120)
			return "You've gained 120 experience points."
		SymbolId.WILDCARD:
			_set_pending_bonus({"wildcards": 1})
			return "You've earned a wildcard for the next stage."
		SymbolId.ROW_CLEAR:
			_set_pending_bonus({"clear_rows": 1})
			return "You've earned a row-clearing bonus for the next stage."
		SymbolId.COL_CLEAR:
			_set_pending_bonus({"clear_cols": 1})
			return "You've earned a column-clearing bonus for the next stage."
		SymbolId.MULT2X:
			_set_pending_bonus({"xp_multiplier": {"mult": 2, "matches": 1}})
			return "For your next match, you will receive double experience points."
		SymbolId.MULT3X:
			_set_pending_bonus({"xp_multiplier": {"mult": 3, "matches": 1}})
			return "For your next match, you will receive triple experience points."
		SymbolId.FREE_SPIN:
			return "You've come close to a free spin."
		_:
			return ""

func _apply_payout_mixed() -> String:
	PlayerManager.player_data["coins"] = PlayerManager.get_coins() + 10
	PlayerManager.emit_signal("coins_changed", PlayerManager.get_coins())
	PlayerManager.save_player_data()
	return "You've won a consolation prize of 10 coins."

func _set_pending_bonus(payload: Dictionary) -> void:
	var pending: Dictionary = {}
	if typeof(PlayerManager.player_data) == TYPE_DICTIONARY:
		pending = PlayerManager.player_data.get("pending_bonus", {})
		for k in payload.keys():
			pending[k] = payload[k]
		PlayerManager.player_data["pending_bonus"] = pending
		PlayerManager.save_player_data()

func _on_CloseButton_pressed() -> void:
	emit_signal("finished")
	queue_free()

func _apply_assets() -> void:
	var bg_path: String = "res://Assets/BonusSlot/slot_bg.png"
	var frame_path: String = "res://Assets/BonusSlot/slot_frame.png"
	var glow_path: String = "res://Assets/BonusSlot/slot_light.png"
	var btn_path: String = "res://Assets/BonusSlot/slot_button_spin.png"
	if FileAccess.file_exists(bg_path):
		var bg_tex: Texture2D = load(bg_path) as Texture2D
		var bg: TextureRect = get_node_or_null("Background") as TextureRect
		if bg != null and bg_tex != null:
			bg.texture = bg_tex
			bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if FileAccess.file_exists(frame_path):
		var fr_tex: Texture2D = load(frame_path) as Texture2D
		var frame: TextureRect = get_node_or_null("Frame") as TextureRect
		if frame != null and fr_tex != null:
			frame.texture = fr_tex
			frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if FileAccess.file_exists(btn_path):
		var btex: Texture2D = load(btn_path) as Texture2D
		if _spin_button != null and btex != null:
			var tb: TextureButton = _spin_button as TextureButton
			if tb != null:
				var b_hover_path: String = "res://Assets/BonusSlot/slot_button_spin_hover.png"
				var b_press_path: String = "res://Assets/BonusSlot/slot_button_spin_pressed.png"
				tb.texture_normal = btex
				if FileAccess.file_exists(b_hover_path):
					var bhov: Texture2D = load(b_hover_path) as Texture2D
					tb.texture_hover = bhov
				else:
					tb.texture_hover = btex
				if FileAccess.file_exists(b_press_path):
					var bprs: Texture2D = load(b_press_path) as Texture2D
					tb.texture_pressed = bprs
				else:
					tb.texture_pressed = btex
				tb.custom_minimum_size = btex.get_size()
			else:
				var btn: Button = _spin_button as Button
				if btn != null:
					btn.icon = btex
					btn.text = "SPIN"
					btn.expand_icon = true
					btn.icon_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
					btn.custom_minimum_size = btex.get_size()
	if FileAccess.file_exists(glow_path):
		var gtex: Texture2D = load(glow_path) as Texture2D
		for g in _glows:
			if g == null:
				continue
			g.texture = gtex
			g.visible = false
			var mat: CanvasItemMaterial = CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			g.material = mat
			g.modulate = Color(1,1,1,0.0)

func _load_symbol_textures() -> void:
	# Try exact filenames first; then fall back to a directory index with multiple naming variants
	var exact: Dictionary = {
		SymbolId.COIN: "res://Assets/BonusSlot/symbol_coin.png",
		SymbolId.XP: "res://Assets/BonusSlot/symbol_xp.png",
		SymbolId.WILDCARD: "res://Assets/BonusSlot/symbol_wildcard.png",
		SymbolId.ROW_CLEAR: "res://Assets/BonusSlot/symbol_row_clear.png",
		SymbolId.COL_CLEAR: "res://Assets/BonusSlot/symbol_col_clear.png",
		# Match actual filenames with underscores
		SymbolId.MULT2X: "res://Assets/BonusSlot/symbol_multiplier_2x.png",
		SymbolId.MULT3X: "res://Assets/BonusSlot/symbol_multiplier_3x.png",
		SymbolId.FREE_SPIN: "res://Assets/BonusSlot/symbol_free_spin.png"
	}
	var index: Dictionary = _index_assets_in_dir(SYMBOL_DIR)
	for i in range(_symbols.size()):
		var sym: Dictionary = _symbols[i]
		var sid: int = int(sym.get("id", -1))
		var tex: Texture2D = null
		if exact.has(sid):
			var path: String = exact[sid]
			tex = load(path) as Texture2D
		if tex == null:
			var bases: Array[String] = []
			match sid:
				SymbolId.COIN:
					bases = ["symbol_coin", "coin"]
				SymbolId.XP:
					bases = ["symbol_xp", "xp"]
				SymbolId.WILDCARD:
					bases = ["symbol_wildcard", "wildcard", "wild"]
				SymbolId.ROW_CLEAR:
					bases = ["symbol_row_clear", "row_clear", "row"]
				SymbolId.COL_CLEAR:
					bases = ["symbol_col_clear", "col_clear", "column"]
				SymbolId.MULT2X:
					bases = ["symbol_multiplier2x", "symbol_multiplier_2x", "multiplier2x", "multiplier_2x", "2x"]
				SymbolId.MULT3X:
					bases = ["symbol_multiplier3x", "symbol_multiplier_3x", "multiplier3x", "multiplier_3x", "3x"]
				SymbolId.FREE_SPIN:
					bases = ["symbol_free_spin", "free_spin", "free"]
				_:
					bases = []
			tex = _load_first_match_tex(index, bases)
		if tex == null and use_placeholders_if_missing:
			var base_col: Color = sym.get("color", Color(0.5,0.5,0.5))
			var nm: String = _symbol_name_for_sid(sid)
			var save_path: String = _placeholder_path_for_symbol(nm)
			# Generate placeholder image and texture
			var img_tex: Dictionary = _make_placeholder_tex(nm, base_col, save_path)
			tex = img_tex.get("tex", null)
		if tex != null:
			_symbols[i]["tex"] = tex

func _index_assets_in_dir(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var exts: Array[String] = [".png",".jpg",".jpeg"]
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return result
	d.list_dir_begin()
	var fn: String = d.get_next()
	while fn != "":
		if not d.current_is_dir():
			var lower: String = fn.to_lower()
			for e in exts:
				if lower.ends_with(e):
					result[lower] = dir_path.path_join(fn)
					break
		fn = d.get_next()
	d.list_dir_end()
	return result

func _load_first_match_tex(index: Dictionary, bases: Array) -> Texture2D:
	var exts: Array[String] = [".png",".jpg",".jpeg"]
	for b in bases:
		var base_lower: String = String(b).to_lower()
		for e in exts:
			var key: String = base_lower + e
			if index.has(key):
				var tex: Texture2D = load(index[key]) as Texture2D
				if tex != null:
					return tex
	return null

func _show_reel_glows(mask: Array) -> void:
	# Center each glow behind the winning result row (top row is the payline for this slot)
	var row_h: float = float(_symbol_size.y)
	var row_w: float = float(_symbol_size.x)
	var result_row_top: float = 0.0  # top row is the evaluated result
	for i in range(min(3, mask.size())):
		var g: TextureRect = _glows[i]
		if g == null:
			continue
		var target: float = 0.65 if mask[i] else 0.0
		# Position and size the glow so it sits directly behind the result tile
		# Use absolute offsets inside the reel, not full-rect anchors
		g.anchor_left = 0.0
		g.anchor_top = 0.0
		g.anchor_right = 0.0
		g.anchor_bottom = 0.0
		g.position = Vector2(0.0, result_row_top)
		g.size = Vector2(row_w, row_h)
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		g.visible = target > 0.0
		var t: Tween = create_tween()
		t.tween_property(g, "modulate:a", target, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if target > 0.0:
			g.scale = Vector2.ONE
			var p: Tween = create_tween()
			p.tween_property(g, "scale", Vector2(1.12, 1.12), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			p.tween_property(g, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _reel_centers_local() -> Array:
	var centers: Array = []
	for r in _reels:
		if r != null:
			centers.append(_to_local_canvas((r as Control).get_global_rect().get_center()))
		else:
			centers.append(Vector2.ZERO)
	return centers

func _to_local_canvas(global_point: Vector2) -> Vector2:
	var inv: Transform2D = get_global_transform_with_canvas().affine_inverse()
	return inv * global_point

func _make_placeholder_tex(_label: String, base: Color, save_path: String) -> Dictionary:
	# _label intentionally unused; rename to silence UNUSED_PARAMETER warning
	var w := 250
	var h := 250
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.lock()
	# fill background
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, base)
	# border
	var border := Color(0,0,0,0.6)
	for x in range(w):
		img.set_pixel(x, 0, border)
		img.set_pixel(x, h-1, border)
	for y in range(h):
		img.set_pixel(0, y, border)
		img.set_pixel(w-1, y, border)
	# diagonal stripes for contrast
	var stripe := Color(1,1,1,0.08)
	for y in range(0, h, 10):
		for x in range(w):
			var sx := (x + y) % 20
			if sx < 2:
				img.set_pixel(x, y, stripe)
				if y+1 < h:
					img.set_pixel(x, y+1, stripe)
	img.unlock()
	# Save to disk if requested
	var saved_path: String = ""
	if save_path != "":
		_ensure_placeholder_dir_exists(save_path)
		if placeholder_overwrite_existing or not FileAccess.file_exists(save_path):
			var err := img.save_png(save_path)
			if err == OK:
				saved_path = save_path
	var tex := ImageTexture.create_from_image(img)
	return {"tex": tex, "path": saved_path}

func _ensure_placeholder_dir_exists(path: String) -> void:
	# Create directories for a user:// path (or any path) as needed
	var dir_path := path
	var last_slash := dir_path.rfind("/")
	if last_slash >= 0:
		dir_path = dir_path.substr(0, last_slash)
	if dir_path.begins_with("user://"):
		var rel := dir_path.replace("user://", "")
		var d := DirAccess.open("user://")
		if d != null:
			d.make_dir_recursive(rel)
	else:
		# Try absolute recursive creation if supported
		var abs_path := ProjectSettings.globalize_path(dir_path)
		DirAccess.make_dir_recursive_absolute(abs_path)

func _symbol_name_for_sid(sid: int) -> String:
	match sid:
		SymbolId.COIN: return "symbol_coin"
		SymbolId.XP: return "symbol_xp"
		SymbolId.WILDCARD: return "symbol_wildcard"
		SymbolId.ROW_CLEAR: return "symbol_row_clear"
		SymbolId.COL_CLEAR: return "symbol_col_clear"
		SymbolId.MULT2X: return "symbol_multiplier_2x"
		SymbolId.MULT3X: return "symbol_multiplier_3x"
		SymbolId.FREE_SPIN:
			return "symbol_free_spin"
		_:
			return "symbol_unknown"

func _placeholder_path_for_symbol(base_name: String) -> String:
	var dir := placeholder_save_dir
	if dir == null or dir == "":
		dir = "user://bonus_slot_placeholders"
	if not dir.ends_with("/"):
		dir += "/"
	return dir + base_name + "_placeholder.png"

func _confetti_burst_from(mask: Array, intensity: float = 1.0) -> void:
	var centers: Array = _reel_centers_local()
	for i in range(min(mask.size(), centers.size())):
		if not mask[i]:
			continue
		var origin: Vector2 = centers[i]
		_spawn_confetti_at(origin, intensity)

func _spawn_confetti_at(origin: Vector2, intensity: float) -> void:
	var count: int = int(30.0 * clamp(intensity, 0.2, 2.0))
	var palette: Array = [
		Color(1.0, 0.3, 0.3),
		Color(1.0, 0.7, 0.2),
		Color(1.0, 1.0, 0.3),
		Color(0.3, 1.0, 0.5),
		Color(0.3, 0.6, 1.0),
		Color(0.7, 0.4, 1.0),
		Color(1.0, 0.5, 0.8),
		Color(1.0, 1.0, 1.0)
	]
	for j in range(count):
		var cr: ColorRect = ColorRect.new()
		cr.color = palette[randi() % palette.size()]
		var w: float = randf_range(6.0, 12.0)
		var h: float = randf_range(3.0, 8.0)
		cr.size = Vector2(w, h)
		cr.pivot_offset = cr.size * 0.5
		var jitter: Vector2 = Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
		cr.position = origin + jitter - cr.pivot_offset
		cr.z_index = 20
		add_child(cr)
		var base_ang: float = -PI * 0.5
		var spread: float = PI * 0.7
		var ang: float = base_ang + randf_range(-spread * 0.5, spread * 0.5)
		var dist: float = randf_range(180.0, 420.0) * intensity
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var rise: float = randf_range(80.0, 160.0)
		var fall: float = randf_range(160.0, 260.0)
		var peak: Vector2 = origin + dir * (dist * 0.55) + Vector2(0.0, -rise)
		var target: Vector2 = origin + dir * dist + Vector2(0.0, fall)
		var dur_up: float = randf_range(0.28, 0.38)
		var dur_down: float = randf_range(0.42, 0.58)
		var total_dur: float = dur_up + dur_down
		var rot: float = randf_range(-7.0, 7.0)
		var t_move: Tween = create_tween()
		t_move.tween_property(cr, "position", peak - cr.pivot_offset, dur_up).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t_move.tween_property(cr, "position", target - cr.pivot_offset, dur_down).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var t_rot: Tween = create_tween()
		t_rot.tween_property(cr, "rotation", rot, total_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var t_scale: Tween = create_tween()
		t_scale.tween_property(cr, "scale", Vector2(1.06, 1.06), dur_up * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t_scale.tween_property(cr, "scale", Vector2(1.0, 1.0), dur_down).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		var t_fade: Tween = create_tween()
		t_fade.tween_interval(total_dur * 0.75)
		t_fade.tween_property(cr, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t_fade.finished.connect(func():
			if is_instance_valid(cr):
				cr.queue_free()
		)

func _finish_after_delay() -> void:
	if _finished:
		return
	_finished = true
	_spin_button.disabled = true
	await get_tree().create_timer(3.0).timeout
	await _animate_out()
	emit_signal("finished")
	queue_free()

func _layout_for_viewport() -> void:
	# Compute responsive panel size and reel window size for portrait/landscape
	# Ensure the root fills the viewport at runtime (editor keeps a manageable default size)
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var is_portrait: bool = vp.y > vp.x
	var panel: Panel = get_node_or_null("Panel") as Panel
	if panel != null:
		# Fit panel within viewport with margins
		var margin_w: float = 40.0
		var margin_h: float = 80.0
		var panel_w: float = clamp(vp.x - margin_w, 360.0, 1280.0)
		var panel_h: float = clamp(vp.y - margin_h, 480.0, 1000.0)
		# Use more vertical space in portrait
		if is_portrait:
			panel_h = clamp(vp.y - margin_h, 640.0, 1200.0)
		panel.offset_left = -panel_w * 0.5
		panel.offset_right = panel_w * 0.5
		panel.offset_top = -panel_h * 0.5
		panel.offset_bottom = panel_h * 0.5
	# Compute reel window size so three reels fit horizontally with separation in portrait
	var sep: float = 24.0
	var usable_w: float = vp.x * 0.88 - 2.0 * sep
	var target: int = int(floor(usable_w / 3.0))
	# Clamp between 140 and base 320, then cap at 250 to match source art for crisp rendering
	target = clamp(target, 140, 320)
	target = min(target, 250)
	_symbol_size = Vector2i(target, target)

func _animate_in() -> void:
	var panel: Control = get_node_or_null("Panel") as Control
	var dimmer: CanvasItem = get_node_or_null("Dimmer") as CanvasItem
	if panel != null:
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.94, 0.94)
	var t: Tween = create_tween()
	if panel != null:
		t.tween_property(panel, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if dimmer != null:
		dimmer.modulate.a = 0.0
		var td: Tween = create_tween()
		td.tween_property(dimmer, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _animate_out() -> void:
	var panel: Control = get_node_or_null("Panel") as Control
	var dimmer: CanvasItem = get_node_or_null("Dimmer") as CanvasItem
	var t: Tween = create_tween()
	if panel != null:
		t.tween_property(panel, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(panel, "scale", Vector2(0.94, 0.94), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if dimmer != null:
		t.parallel().tween_property(dimmer, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished

func _align_glows_to_reels() -> void:
	for g in _glows:
		if g == null: continue
		# Stretch to cover the reel control fully and get clipped by it
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.offset_left = 0
		g.offset_top = 0
		g.offset_right = 0
		g.offset_bottom = 0
