extends Node

const GAME_SCENE_PATH = "res://Scenes/Game.tscn"

func _ready():
        print("[Loading.gd] _ready: Intermediate loading scene is ready.")
        _load_scene_sync()

func _change_to_loaded_scene(packed_scene):
        var tree = get_tree()
        if tree == null:
                push_error("[Loading.gd] _change_to_loaded_scene: SceneTree not available.")
                return
        tree.change_scene_to(packed_scene)

func _load_scene_sync():
        print("[Loading.gd] _load_scene_sync: Loading Game scene synchronously.")
        var packed_scene = ResourceLoader.load(GAME_SCENE_PATH)
        if packed_scene != null:
                call_deferred("_change_to_loaded_scene", packed_scene)
        else:
                push_error("[Loading.gd] _load_scene_sync: Failed to load Game scene.")
