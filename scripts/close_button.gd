extends TextureButton

## Close Button Script
## Closes the player profile window when clicked

func _pressed() -> void:
	# Get the player_profile root node
	# Try owner first (scene root)
	var player_profile = owner
	
	# If owner doesn't have the method, try traversing up the parent chain
	if not player_profile or not player_profile.has_method("close_profile"):
		var current = get_parent()
		while current:
			if current.has_method("close_profile"):
				player_profile = current
				break
			current = current.get_parent()
	
	# Call close_profile if found
	if player_profile and player_profile.has_method("close_profile"):
		player_profile.close_profile()
	else:
		print("ERROR: Could not find player_profile script or close_profile method!")
