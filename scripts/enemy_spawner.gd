extends Node2D

# Array of enemy scenes to randomly choose from
@export var enemy_scenes: Array[PackedScene] = [
	preload("res://scene/skeleton.tscn"),
	preload("res://scene/evil_sword.tscn"),
	preload("res://scene/slime.tscn")
]
# Spawn weights: [skeleton_weight, evil_sword_weight, slime_weight]
# Higher weight = more likely to spawn
# Slimes are easier, so they should spawn more often
# Evil Sword is middle-tier, so medium spawn rate
@export var spawn_weights: Array[int] = [1, 2, 3]  # 1:2:3 ratio = 16.7% skeleton, 33.3% evil_sword, 50% slime
@export var respawn_time: float = 30.0

var alive_count = 0
var spawn_points: Array[Vector2] = []  # Auto-detected spawn points
var player_ref: Node = null  # Player reference from GameManager
var dungeon_map: Node = null  # Parent node (the dungeon map)
var timer: Timer = null  # Timer (either from scene or created programmatically)

func _ready() -> void:
	# Get the parent (dungeon map) - this is where enemies will be spawned
	dungeon_map = get_parent()
	if not dungeon_map:
		push_error("EnemySpawner: Could not find parent node (dungeon map)!")
		return
	
	print("EnemySpawner: Parent dungeon map: ", dungeon_map.name)
	
	# Task 2: Auto-detect spawn points (Marker2D children of EnemySpawner OR siblings)
	detect_spawn_points()
	
	# Setup Timer - check if it exists in scene, otherwise create it
	timer = get_node_or_null("Timer")
	if not timer:
		timer = Timer.new()
		timer.name = "Timer"
		timer.wait_time = respawn_time
		timer.one_shot = true
		timer.timeout.connect(_on_timer_timeout)
		add_child(timer)
		print("EnemySpawner: Timer created programmatically")
	else:
		timer.wait_time = respawn_time
		timer.one_shot = true
		if not timer.timeout.is_connected(_on_timer_timeout):
			timer.timeout.connect(_on_timer_timeout)
		print("EnemySpawner: Using existing Timer from scene")
	
	# Task 1: Get player reference from GameManager (deferred to handle timing)
	call_deferred("_setup_player_reference")
	
	# Initial spawn - use call_deferred to ensure everything is ready
	call_deferred("spawn_wave")

func _setup_player_reference() -> void:
	"""Setup player reference from GameManager (called deferred to handle timing)"""
	if GameManager and GameManager.player_ref:
		player_ref = GameManager.player_ref
		print("EnemySpawner: Player reference obtained from GameManager: ", player_ref.name)
	else:
		# This is a warning, not an error, since enemies find the player themselves
		push_warning("EnemySpawner: Player not found in GameManager yet. Enemies will find player themselves.")

func detect_spawn_points() -> void:
	"""Auto-detect spawn points by finding Marker2D children of EnemySpawner OR siblings in dungeon map"""
	spawn_points.clear()
	
	# Method 1: Look for Marker2D children of EnemySpawner (Spawner1, Spawner2, etc.)
	for child in get_children():
		if child is Marker2D:
			spawn_points.append(child.global_position)
			print("EnemySpawner: Found spawn point (child): ", child.name, " at position: ", child.global_position)
	
	# Method 2: If no children found, look for Marker2D siblings in dungeon map (excluding Entrance/Exit)
	if spawn_points.is_empty() and dungeon_map:
		for child in dungeon_map.get_children():
			if child is Marker2D and child != self:
				var marker_name = child.name.to_lower()
				# Exclude entrance and exit markers (spawn points for player, not enemies)
				if "entrance" not in marker_name and "exit" not in marker_name:
					spawn_points.append(child.global_position)
					print("EnemySpawner: Found spawn point (sibling): ", child.name, " at position: ", child.global_position)
	
	# Fallback: If no markers found, use spawner's own position
	if spawn_points.is_empty():
		spawn_points.append(global_position)
		print("EnemySpawner: No spawn points found! Using spawner's own position as fallback: ", global_position)
	else:
		print("EnemySpawner: Detected ", spawn_points.size(), " spawn points")

func spawn_wave() -> void:
	# Task 4: Don't spawn if boss is active
	if GameManager and GameManager.is_boss_active:
		print("EnemySpawner: Boss is active, skipping spawn wave")
		return
	
	# Validate dungeon map
	if not dungeon_map:
		push_error("EnemySpawner: Cannot spawn - dungeon_map is null!")
		return
	
	# Check if spawn points are available
	if spawn_points.is_empty():
		push_error("EnemySpawner: No spawn points available!")
		return
	
	# Validate player reference (for debugging, enemies find player themselves)
	if not player_ref:
		push_warning("EnemySpawner: Player reference is null, but continuing spawn (enemies will find player themselves)")
	
	# Check if enemy scenes are loaded
	if enemy_scenes.is_empty():
		push_error("EnemySpawner: No enemy scenes loaded!")
		return
	
	# Spawn one enemy per spawn point (or a subset if you want fewer enemies)
	for spawn_point in spawn_points:
		# Randomly choose an enemy type with weighted probability
		var enemy_scene = get_weighted_random_enemy()
		if not enemy_scene:
			push_error("EnemySpawner: Enemy scene is null!")
			continue
		
		var enemy = enemy_scene.instantiate()
		if not enemy:
			push_error("EnemySpawner: Failed to instantiate enemy!")
			continue
		
		# Set position before adding to tree
		enemy.global_position = spawn_point
		
		# Task 3: Add enemy as child of parent (dungeon map), not the spawner
		dungeon_map.add_child(enemy)
		enemy.tree_exited.connect(_on_enemy_died)
		alive_count += 1
		print("EnemySpawner: Spawned enemy at position: ", enemy.global_position, " alive_count: ", alive_count)

func _on_enemy_died() -> void:
	# Check if we're still in the scene tree (scene might be changing)
	if not is_inside_tree():
		return
	
	alive_count -= 1
	print("EnemySpawner: Enemy died! alive_count: ", alive_count)
	if alive_count == 0:
		print("EnemySpawner: All enemies defeated!")
		
		# Check if this is dungeon_floor_2 - if so, spawn the boss
		if dungeon_map and "dungeon_floor_2" in dungeon_map.name:
			print("EnemySpawner: All enemies defeated in dungeon_floor_2! Triggering boss spawn...")
			# Call deferred to ensure everything is ready
			call_deferred("_trigger_boss_spawn")
		else:
			# Normal spawn cycle for other levels
			print("EnemySpawner: Not dungeon_floor_2 (map name: ", dungeon_map.name if dungeon_map else "null", "), resuming spawn cycle")
			if timer and timer.is_inside_tree():
				timer.start()

func _trigger_boss_spawn() -> void:
	"""Trigger boss spawn for dungeon_floor_2"""
	print("EnemySpawner: _trigger_boss_spawn() called")
	if GameManager:
		print("EnemySpawner: GameManager found, calling start_boss_sequence()")
		GameManager.start_boss_sequence("res://scene/minotaur.tscn", "BossSpawnPos")
	else:
		push_error("EnemySpawner: GameManager not found!")

func _on_timer_timeout() -> void:
	spawn_wave()

func get_weighted_random_enemy() -> PackedScene:
	# Weighted random selection based on spawn_weights
	# Example: weights [1, 3] means 1/4 chance for skeleton, 3/4 chance for slime
	if spawn_weights.size() != enemy_scenes.size():
		# Fallback to equal probability if weights don't match
		return enemy_scenes[randi() % enemy_scenes.size()]
	
	# Calculate total weight
	var total_weight = 0
	for weight in spawn_weights:
		total_weight += weight
	
	# Generate random number between 0 and total_weight
	var random_value = randi() % total_weight
	
	# Find which enemy to spawn based on weight
	var current_weight = 0
	for i in range(enemy_scenes.size()):
		current_weight += spawn_weights[i]
		if random_value < current_weight:
			return enemy_scenes[i]
	
	# Fallback (shouldn't reach here)
	return enemy_scenes[0]
