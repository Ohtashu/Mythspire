extends Node

## GameManager Autoload
## Handles map swapping and persistent player data

# Task 2: Reference variables for persistent Game scene
var player_ref: Node = null  # Reference to the Player node
var level_container_ref: Node = null  # Reference to the LevelContainer node
var current_map_node: Node = null  # Reference to the currently loaded map

# Persistent data variables
var player_health: int = 100  # Player's current health (default to 100 or max health)
var target_spawn_tag: String = ""  # Name of the Marker2D to spawn at in the next scene

func _ready() -> void:
	print("GameManager: Autoload initialized")

# Task 2: Setup systems from LevelManager
func setup_systems(player: Node, container: Node) -> void:
	"""Store references to Player and LevelContainer, and detect the starting map"""
	player_ref = player
	level_container_ref = container
	
	# Crucial: Check if container has any children (the starting map placed in editor)
	if level_container_ref and level_container_ref.get_child_count() > 0:
		current_map_node = level_container_ref.get_child(0)
		print("GameManager: Systems Linked. Starting Map Detected: ", current_map_node.name)
		print("GameManager: Stored references - Player: ", player_ref.name, " | Container: ", level_container_ref.name)
	else:
		print("GameManager: LevelContainer has no children (no starting map found)")

# Task 2: Load level (map swapping)
func load_level(scene_path: String, spawn_tag: String) -> void:
	"""Swap maps inside LevelContainer - delete old map, add new map"""
	print("GameManager: Loading level - Scene: ", scene_path, " | Spawn tag: ", spawn_tag)
	
	# Validate references
	if not player_ref:
		push_error("GameManager: player_ref is null! Call setup_systems() first.")
		return
	
	if not level_container_ref:
		push_error("GameManager: level_container_ref is null! Call setup_systems() first.")
		return
	
	if scene_path == "":
		push_error("GameManager: scene_path is empty!")
		return
	
	# Save player health before swapping
	if "current_health" in player_ref:
		player_health = player_ref.current_health
		print("GameManager: Saved player health - ", player_health)
	
	# Use call_deferred to avoid physics callback issues
	call_deferred("_load_level_deferred", scene_path, spawn_tag)

func _load_level_deferred(scene_path: String, spawn_tag: String) -> void:
	"""Internal function to load new level (called deferred to avoid physics callback issues)"""
	
	# Step A (Cleanup): Remove current map if it exists
	if current_map_node:
		print("GameManager: Removing current map: ", current_map_node.name)
		current_map_node.queue_free()
		current_map_node = null
	
	# Step B (Load): Instantiate the new map from scene_path
	var new_map_scene = load(scene_path) as PackedScene
	if not new_map_scene:
		push_error("GameManager: Failed to load scene from path: " + scene_path)
		return
	
	var new_map = new_map_scene.instantiate()
	if not new_map:
		push_error("GameManager: Failed to instantiate scene from: " + scene_path)
		return
	
	# Step C (Add): Add the new map as a child of level_container_ref
	level_container_ref.add_child(new_map)
	print("GameManager: Added new map to LevelContainer: ", new_map.name)
	
	# Step D (Update Ref): Set current_map_node to this new instance
	current_map_node = new_map
	
	# Step D.5: Setup Y-sorting for the new map
	var level_manager = level_container_ref.get_parent()
	if level_manager and "setup_y_sorting_for_map" in level_manager:
		level_manager.setup_y_sorting_for_map(new_map)
		print("GameManager: Y-sorting configured for new map")
	else:
		push_warning("GameManager: Could not find LevelManager to setup Y-sorting for new map!")
	
	# Step E (Teleport): Find Marker2D and teleport player
	if spawn_tag != "":
		var spawn_point = new_map.find_child(spawn_tag, true, false)
		if spawn_point and spawn_point is Marker2D:
			player_ref.global_position = spawn_point.global_position
			print("GameManager: Teleported player to spawn point '", spawn_tag, "' at position ", spawn_point.global_position)
		else:
			push_error("GameManager: Could not find Marker2D with name '", spawn_tag, "' in new map!")
	else:
		print("GameManager: No spawn tag specified, player position unchanged")
	
	print("GameManager: Successfully loaded level: ", scene_path)

# Legacy function for backwards compatibility (if needed)
func change_scene(new_scene_path: String, spawn_tag: String, current_hp: int) -> void:
	"""Legacy function - redirects to load_level for map swapping"""
	print("GameManager: change_scene() called - redirecting to load_level()")
	player_health = current_hp
	load_level(new_scene_path, spawn_tag)

# Legacy alias for backwards compatibility
func load_new_level(scene_path: String, spawn_tag: String) -> void:
	"""Legacy alias - redirects to load_level()"""
	load_level(scene_path, spawn_tag)
