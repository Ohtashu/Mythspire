extends TextureButton

## Main Menu Button Script
## Returns to the main menu scene

func _pressed() -> void:
	# CRUCIAL: Unpause the game first before changing scenes
	get_tree().paused = false
	
	# Change scene to main menu
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")
