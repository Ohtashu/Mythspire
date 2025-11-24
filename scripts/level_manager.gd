extends Node2D
class_name LevelManager

## LevelManager - Handles Y-Sorting setup for the entire level
## 
## This script should be attached to the main Game/Level node (which should be a YSort node)
## It automatically configures Y-sorting for Player, Enemies, and TileMaps

@export var floor_z_index: int = -10
@export var wall_z_index: int = 0
@export var character_z_index: int = 0
@export var structure_z_index: int = 0

func _ready() -> void:
	print("LevelManager: Initializing Y-sorting configuration...")
	setup_y_sorting()
	print("LevelManager: Y-sorting configuration complete!")

func setup_y_sorting() -> void:
	# Ensure this node is a Node2D (YSort extends Node2D)
	if not self is Node2D:
		push_error("LevelManager must be attached to a Node2D or YSort node!")
		return
	
	# YSort nodes automatically have y_sort_enabled
	# If this is a regular Node2D, we should enable y_sort_enabled manually
	# Check if y_sort_enabled property exists and enable it if needed
	if "y_sort_enabled" in self:
		var current_value = get("y_sort_enabled")
		if not current_value:
			set("y_sort_enabled", true)
			print("LevelManager: Enabled y_sort_enabled on Node2D")
		else:
			print("LevelManager: y_sort_enabled already enabled")
	
	# Configure Player
	setup_player()
	
	# Configure Enemies
	setup_enemies()
	
	# Configure TileMaps
	setup_tilemaps()
	
	# Configure other sortable objects (torches, candles, etc.)
	setup_environment_objects()

func setup_player() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		# Try to find Player as direct child
		player = get_node_or_null("Player")
	
	if player:
		print("LevelManager: Configuring Player Y-sorting...")
		# Ensure Player has y_sort_enabled
		if player is CharacterBody2D:
			player.y_sort_enabled = true
			player.z_index = character_z_index
			
			# Configure Player's children
			configure_node_children(player, false)  # Don't enable y_sort on children
		
		# Connect player_died signal to game_over screen
		var game_over = get_node_or_null("game_over_layer/game_over")
		if game_over and player.has_signal("player_died"):
			player.player_died.connect(game_over.show_game_over)
			print("LevelManager: Connected player_died signal to game_over screen")
		else:
			if not game_over:
				push_warning("LevelManager: game_over screen not found!")
			if not player.has_signal("player_died"):
				push_warning("LevelManager: player_died signal not found on player!")
		
		print("LevelManager: Player configured at position: ", player.global_position)
	else:
		push_warning("LevelManager: Player not found!")

func setup_enemies() -> void:
	# Find all enemies (they should be direct children of this YSort node)
	var enemies: Array[Node] = []
	
	# Method 1: Find by group
	enemies.append_array(get_tree().get_nodes_in_group("enemy"))
	
	# Method 2: Find direct children that are CharacterBody2D (enemies)
	for child in get_children():
		if child is CharacterBody2D and child != get_node_or_null("Player"):
			if not child in enemies:
				enemies.append(child)
	
	# Method 3: Find enemies spawned by EnemySpawner (they're added as direct children)
	# This is already handled by method 2
	
	print("LevelManager: Found ", enemies.size(), " enemies")
	
	for enemy in enemies:
		if enemy is CharacterBody2D:
			enemy.y_sort_enabled = true
			enemy.z_index = character_z_index
			# Don't enable y_sort on enemy children - only the root CharacterBody2D
			configure_node_children(enemy, false)
			print("LevelManager: Configured enemy: ", enemy.name, " at position: ", enemy.global_position)

func setup_tilemaps() -> void:
	# Find all TileMapLayer nodes in the scene
	var tilemaps: Array[Node] = []
	
	# Recursively find all TileMapLayer nodes
	find_tilemap_layers_recursive(self, tilemaps)
	
	print("LevelManager: Found ", tilemaps.size(), " TileMapLayer nodes")
	
	for tilemap in tilemaps:
		if tilemap is TileMapLayer:
			var layer_name = tilemap.name.to_lower()
			
			# Enable Y-sorting on TileMapLayers that need it (walls, structures, decorations)
			if "wall" in layer_name or "structure" in layer_name or "decoration" in layer_name:
				tilemap.y_sort_enabled = true
				tilemap.z_index = wall_z_index
				print("LevelManager: Configured TileMapLayer (Y-sort enabled): ", tilemap.name)
			elif "ground" in layer_name or "floor" in layer_name:
				# Floor layers don't need Y-sorting, but set z_index to be below everything
				tilemap.y_sort_enabled = false
				tilemap.z_index = floor_z_index
				print("LevelManager: Configured TileMapLayer (floor): ", tilemap.name, " z_index: ", floor_z_index)
			else:
				# Other layers - enable Y-sorting by default
				tilemap.y_sort_enabled = true
				tilemap.z_index = structure_z_index
				print("LevelManager: Configured TileMapLayer (default): ", tilemap.name)

func find_tilemap_layers_recursive(node: Node, result: Array) -> void:
	if node is TileMapLayer:
		result.append(node)
	
	for child in node.get_children():
		find_tilemap_layers_recursive(child, result)

func setup_environment_objects() -> void:
	# Find and configure torches, candles, and other environment objects
	var env_objects: Array[Node] = []
	
	# Recursively find Node2D objects that should participate in Y-sorting
	find_environment_objects_recursive(self, env_objects)
	
	print("LevelManager: Found ", env_objects.size(), " environment objects")
	
	for obj in env_objects:
		if obj is Node2D and obj != get_node_or_null("Player"):
			# Check if it's an environment object (torch, candle, etc.)
			var obj_name = obj.name.to_lower()
			if "torch" in obj_name or "candle" in obj_name or "pedestal" in obj_name:
				obj.y_sort_enabled = true
				obj.z_index = structure_z_index
				print("LevelManager: Configured environment object: ", obj.name)

func find_environment_objects_recursive(node: Node, result: Array) -> void:
	# Skip certain node types
	if node is Camera2D or node is Control or node is AudioStreamPlayer2D:
		return
	
	if node is Node2D and node.name != "Player":
		# Check if it's a potential environment object
		var node_name = node.name.to_lower()
		if "torch" in node_name or "candle" in node_name or "pedestal" in node_name:
			result.append(node)
	
	for child in node.get_children():
		find_environment_objects_recursive(child, result)

func configure_node_children(node: Node, enable_y_sort: bool = false) -> void:
	# Configure children of a node for Y-sorting
	# For CharacterBody2D, we typically DON'T want y_sort_enabled on children
	# Only the root CharacterBody2D should have it
	for child in node.get_children():
		if child is AnimatedSprite2D or child is CollisionShape2D:
			# These should NOT have y_sort_enabled - only the parent CharacterBody2D should
			if "y_sort_enabled" in child:
				child.set("y_sort_enabled", enable_y_sort)
