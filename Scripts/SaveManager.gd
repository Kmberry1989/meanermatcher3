extends Node

const SAVE_PATH = "user://player.json"

func has_player():
        var f = File.new()
        return f.file_exists(SAVE_PATH)

func load_player():
        if not has_player():
                return {}
        var file = File.new()
        var err = file.open(SAVE_PATH, File.READ)
        if err != OK:
                return {}
        var text = file.get_as_text()
        file.close()
        if typeof(text) == TYPE_STRING and text != "":
                var parsed = JSON.parse(text)
                if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
                        return parsed.result
        return {}

func save_player(data):
        var file = File.new()
        var err = file.open(SAVE_PATH, File.WRITE)
        if err != OK:
                return false
        file.store_string(JSON.print(data))
        file.close()
        return true

# Optional lightweight localStorage helpers for Web
func web_save_json(key, data):
        if OS.has_feature("HTML5") and Engine.has_singleton("JavaScript"):
                var s = JSON.print(data)
                JavaScript.eval("localStorage.setItem(" + to_json(key) + "," + to_json(s) + ")", true)

func web_load_json(key, default = {}):
        if OS.has_feature("HTML5") and Engine.has_singleton("JavaScript"):
                var s = JavaScript.eval("localStorage.getItem(" + to_json(key) + ")", true)
                if typeof(s) == TYPE_STRING and s != "":
                        var parsed = JSON.parse(s)
                        if parsed.error == OK:
                                return parsed.result
        return default
