extends TextureButton

## Try Again Button Script
## Revives the player and restarts gameplay

func _pressed() -> void:
	# Get the game_over root node (owner)
	var game_over = owner
	if game_over and game_over.has_method("try_again"):
		game_over.try_again()
	else:
		print("ERROR: Could not find game_over script or try_again method!")
