extends Node

## GameManager Autoload
## Handles scene transitions and persistent player data

# Step 1: Persistent data variables
var player_health: int = 100  # Player's current health (default to 100 or max health)
var target_spawn_tag: String = ""  # Name of the Marker2D to spawn at in the next scene

func _ready() -> void:
	print("GameManager: Autoload initialized")

# Step 1: Change scene function
func change_scene(new_scene_path: String, spawn_tag: String, current_hp: int) -> void:
	"""Save player health and spawn tag, then switch to target scene"""
	print("GameManager: Changing scene to ", new_scene_path, " with spawn tag '", spawn_tag, "'")
	
	# Update player health
	player_health = current_hp
	print("GameManager: Saved player health - ", player_health)
	
	# Update target spawn tag
	target_spawn_tag = spawn_tag
	
	# Change scene using call_deferred to avoid physics callback issues
	if new_scene_path != "":
		# Use call_deferred to change scene after physics step completes
		call_deferred("_change_scene_deferred", new_scene_path)
	else:
		push_error("GameManager: new_scene_path is empty!")

func _change_scene_deferred(scene_path: String) -> void:
	"""Internal function to change scene (called deferred to avoid physics callback issues)"""
	var error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("GameManager: Failed to change scene: " + str(error))
	else:
		print("GameManager: Successfully changed scene to ", scene_path)
