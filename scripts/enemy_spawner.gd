extends Node2D

@onready var spawners = [$Spawner1, $Spawner2, $Spawner3, $Spawner4, $Spawner5, $"Spawner 6"]
@onready var timer: Timer = $Timer

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

func _ready() -> void:
	timer.wait_time = respawn_time
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	
	# Initial spawn - use call_deferred to ensure everything is ready
	call_deferred("spawn_wave")

func spawn_wave() -> void:
	# Get the Game root node (parent of EnemySpawner) for proper Y-sorting
	var game_root = get_parent()
	if not game_root:
		game_root = get_tree().current_scene
	
	if not game_root:
		print("ERROR: EnemySpawner could not find Game root node!")
		return
	
	# Check if spawners are ready
	if not spawners or spawners.size() == 0:
		print("ERROR: EnemySpawner spawners not found! Spawners: ", spawners)
		return
	
	for spawner in spawners:
		if not spawner:
			continue
		# Randomly choose an enemy type with weighted probability
		if enemy_scenes.is_empty():
			print("ERROR: No enemy scenes loaded!")
			return
		
		# Weighted random selection: slimes spawn more often than skeletons
		var enemy_scene = get_weighted_random_enemy()
		if not enemy_scene:
			print("ERROR: Enemy scene is null!")
			continue
		var enemy = enemy_scene.instantiate()
		if not enemy:
			print("ERROR: Failed to instantiate enemy!")
			continue
		# Set position before adding to tree
		enemy.position = spawner.global_position
		# Add enemy to Game root for proper Y-sorting with player
		game_root.add_child(enemy)
		enemy.tree_exited.connect(_on_enemy_died)
		alive_count += 1
		print("Spawned enemy at position: ", enemy.position, " alive_count: ", alive_count)

func _on_enemy_died() -> void:
	# Check if we're still in the scene tree (scene might be changing)
	if not is_inside_tree():
		return
	
	alive_count -= 1
	if alive_count == 0:
		# Check if timer is still in the tree before starting
		if timer and timer.is_inside_tree():
			timer.start()

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
