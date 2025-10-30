extends Node

# This manager handles all the sound and music playback.

var sfx_players = []
var music_player = null

const MAX_SFX_PLAYERS = 8 # Max simultaneous sound effects

var sounds = {}
var music_tracks = {}

var music_bus_idx
var sfx_bus_idx

func _ready():
	# Create audio buses for music and SFX
	AudioServer.add_bus()
	music_bus_idx = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(music_bus_idx, "Music")
	
	AudioServer.add_bus()
	sfx_bus_idx = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(sfx_bus_idx, "SFX")

	# Create a pool of audio players for sound effects
	for i in range(MAX_SFX_PLAYERS):
		var player = AudioStreamPlayer.new()
		player.set_bus("SFX")
		add_child(player)
		sfx_players.append(player)

	# Create a dedicated player for music
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.set_bus("Music")
	add_child(music_player)

	# Preload all sounds and music
	load_sounds()
	load_music()

func load_sounds():
	sounds["match_pop"] = "res://Assets/Sounds/pop.ogg"
	sounds["match_chime"] = "res://Assets/Sounds/match_chime.ogg"
	sounds["match_fanfare"] = "res://Assets/Sounds/match_fanfare.ogg"
	sounds["dot_land"] = "res://Assets/Sounds/dot_land.ogg"
	sounds["ui_click"] = "res://Assets/Sounds/ui_click.ogg"
	sounds["game_start"] = "res://Assets/Sounds/game_start_swoosh.ogg"
	sounds["yawn"] = "res://Assets/Sounds/yawn.ogg"
	sounds["surprised"] = "res://Assets/Sounds/surprised.ogg"
	# Use dedicated shuffle SFX
	sounds["shuffle"] = "res://Assets/Sounds/shuffle.ogg"
	# New special match sounds (add these files under Assets/Sounds)
	sounds["line_clear"] = "res://Assets/Sounds/line_clear.ogg"
	sounds["wildcard_spawn"] = "res://Assets/Sounds/wildcard_spawn.ogg"
	# Slot machine SFX (if present)
	var slot_sounds = {
		"slot_spin": "res://Assets/Sounds/slot_spin.ogg",
		"slot_tick": "res://Assets/Sounds/slot_tick.ogg",
		"slot_stop": "res://Assets/Sounds/slot_stop.ogg",
		"slot_win": "res://Assets/Sounds/slot_win.ogg",
		"slot_fail": "res://Assets/Sounds/slot_fail.ogg"
	}
	for k in slot_sounds.keys():
		var path = slot_sounds[k]
		if ResourceLoader.exists(path):
			sounds[k] = path

func load_music():
	_add_music_track("login", "res://Assets/Sounds/music_login.ogg")
	_add_music_track("menu", "res://Assets/Sounds/music_menu.ogg")
	_add_music_track("ingame", "res://Assets/Sounds/music_ingame.ogg")

func _add_music_track(track_name, path):
	# Only register track if file exists and loads successfully
	if ResourceLoader.exists(path):
		music_tracks[track_name] = path
	else:
		# Silent skip to avoid noise when certain tracks are not present in a build
		pass

func play_sound(sound_name):
	if not sounds.has(sound_name):
		print("Sound not found: ", sound_name)
		return

	# Find an available player and play the sound
	for player in sfx_players:
		if not player.is_playing():
			player.stream = load(sounds[sound_name])
			player.play()
			return

func play_music(track_name, loop = true):
	var stream = null
	if music_tracks.has(track_name):
		stream = load(music_tracks[track_name])
	else:
		# Friendly fallback order
		var fallbacks = []
		match track_name:
			"login":
				fallbacks = ["menu", "ingame"]
			"menu":
				fallbacks = ["login", "ingame"]
			"ingame":
				fallbacks = ["menu", "login"]
			_:
				fallbacks = ["menu", "login", "ingame"]
		for alt in fallbacks:
			if music_tracks.has(alt):
				print("Music '", track_name, "' not found; falling back to '", alt, "'.")
				stream = load(music_tracks[alt])
				break
		if stream == null:
			print("Music not found and no fallback available: ", track_name)
			return

	stream.loop = loop
	music_player.stream = stream
	music_player.play()

func stop_music():
	music_player.stop()

func set_music_volume(volume_db):
	AudioServer.set_bus_volume_db(music_bus_idx, volume_db)

func set_sfx_volume(volume_db):
	AudioServer.set_bus_volume_db(sfx_bus_idx, volume_db)

func get_music_volume():
	return AudioServer.get_bus_volume_db(music_bus_idx)

func get_sfx_volume():
	return AudioServer.get_bus_volume_db(sfx_bus_idx)

func _exit_tree():
	# Stop any playing audio to avoid lingering objects at shutdown
	if music_player and music_player.is_playing():
		music_player.stop()
	for p in sfx_players:
		if p and p.is_playing():
			p.stop()
