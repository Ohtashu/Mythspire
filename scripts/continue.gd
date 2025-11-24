extends TextureButton

## Continue/Resume Button Script
## Unpauses the game and hides the pause menu

func _pressed() -> void:
	# Unpause the game
	get_tree().paused = false
	
	# Hide the pause menu (owner refers to the root pause_menu Control node)
	if owner:
		owner.hide()
