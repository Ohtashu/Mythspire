extends Area2D

## Scene Transition Trigger (Debug Version)
## When player enters this area, transition to another scene

# Export variables
@export_file("*.tscn") var target_scene_path: String = ""  # Path to the target scene (e.g., "res://scene/dungeon_floor2.tscn")
@export var target_spawn_tag: String = ""  # Name of the Marker2D to spawn at in the target scene (e.g., "Entrance" or "SpawnPos_exit")

func _ready() -> void:
	# Debug: Print trigger ready
	print("--- Trigger Ready ---")
	print("SceneTrigger: Target scene: ", target_scene_path)
	print("SceneTrigger: Spawn tag: ", target_spawn_tag)
	
	# Validation: Check if target_scene_path is empty
	if target_scene_path == "":
		push_error("SceneTrigger: Target scene is empty! Set target_scene_path in the Inspector.")
	
	# Auto-Connect Signal: Connect body_entered signal via code
	# This ensures it works even if not connected in the Editor
	if not body_entered.is_connected(_on_body_entered):
		var error = body_entered.connect(_on_body_entered)
		if error != OK:
			push_error("SceneTrigger: Failed to connect body_entered signal! Error code: " + str(error))
		else:
			print("SceneTrigger: Successfully auto-connected body_entered signal")
	else:
		print("SceneTrigger: body_entered signal already connected")
	
	# Verify Area2D setup
	print("SceneTrigger: collision_layer = ", collision_layer)
	print("SceneTrigger: collision_mask = ", collision_mask)
	if not collision_layer:
		push_error("SceneTrigger: collision_layer is 0! Trigger may not detect anything.")
	if not collision_mask:
		push_error("SceneTrigger: collision_mask is 0! Trigger may not detect anything.")
	
	# Check for CollisionShape2D
	var collision_shape = get_node_or_null("CollisionShape2D")
	if not collision_shape:
		push_error("SceneTrigger: No CollisionShape2D child found! Trigger will not work.")
	elif not collision_shape.shape:
		push_error("SceneTrigger: CollisionShape2D has no shape assigned! Trigger will not work.")
	else:
		print("SceneTrigger: CollisionShape2D found and configured")

# Handle body_entered signal
func _on_body_entered(body: Node2D) -> void:
	# Debug: Print collision detection (CRUCIAL for debugging)
	print("Collision detected with: ", body.name, " (Type: ", body.get_class(), ")")
	
	# Validation: Check if body is the Player
	var is_player: bool = false
	
	# Check 1: Is it named "Player"?
	if body.name == "Player":
		is_player = true
		print("SceneTrigger: Body name matches 'Player'")
	
	# Check 2: Is it a CharacterBody2D? (Player is typically CharacterBody2D)
	if body is CharacterBody2D:
		is_player = true
		print("SceneTrigger: Body is CharacterBody2D")
	
	# Check 3: Is it in the "player" group?
	if body.is_in_group("player"):
		is_player = true
		print("SceneTrigger: Body is in 'player' group")
	
	# If not a player, exit early
	if not is_player:
		print("SceneTrigger: Body is not a player, ignoring")
		return
	
	print("SceneTrigger: ✓ Player confirmed! Processing scene transition...")
	
	# Get player's current health
	var player_hp: int = 100  # Default fallback
	
	# Use get() method to safely check for properties
	var health_value = body.get("current_health")
	if health_value != null:
		player_hp = health_value
		print("SceneTrigger: Found player.current_health = ", player_hp)
	else:
		health_value = body.get("health")
		if health_value != null:
			player_hp = health_value
			print("SceneTrigger: Found player.health = ", player_hp)
		else:
			print("SceneTrigger: WARNING - Could not find health property, using default 100")
	
	# Validation: Check if target_scene_path is empty
	if target_scene_path == "":
		push_error("SceneTrigger: target_scene_path is empty! Cannot change scene.")
		return
	
	if target_spawn_tag == "":
		push_error("SceneTrigger: target_spawn_tag is empty! Cannot determine spawn point.")
		return
	
	# Check if GameManager exists
	if not GameManager:
		push_error("SceneTrigger: GameManager autoload not found! Make sure it's set up in Project Settings.")
		return
	
	# Execute: Print and call GameManager
	print("Switching to: ", target_scene_path)
	print("SceneTrigger: Calling GameManager.load_level(", target_scene_path, ", ", target_spawn_tag, ")")
	# Task 3: Use load_level to swap maps
	GameManager.load_level(target_scene_path, target_spawn_tag)
