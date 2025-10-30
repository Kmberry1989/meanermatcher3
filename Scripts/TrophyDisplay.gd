extends PanelContainer

@onready var icon = $HBoxContainer/Icon
@onready var trophy_name = $HBoxContainer/VBoxContainer/Name
@onready var description = $HBoxContainer/VBoxContainer/Description

func set_trophy(trophy_resource, unlocked):
    if unlocked:
        icon.texture = trophy_resource.unlocked_icon
        trophy_name.text = trophy_resource.trophy_name
        description.text = trophy_resource.description
    else:
        icon.texture = load("res://Assets/Visuals/container.png") # Placeholder locked icon
        trophy_name.text = "??????"
        description.text = "??????"



