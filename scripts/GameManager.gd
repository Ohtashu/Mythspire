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

# Boss Fight System
var ui_layer: CanvasLayer = null  # Reference to UI layer (player_hud)
var music_player: AudioStreamPlayer = null  # Reference to MusicPlayer
var sfx_player: AudioStreamPlayer = null  # Reference to SFXPlayer
var is_boss_active: bool = false  # Flag to track if boss is currently active
var current_boss: Node = null  # Reference to current boss instance
const BOSS_MUSIC_PATH = "res://audio/background/13 - Decisive Battle 1 - Don't Be Afraid.mp3"
const VICTORY_MUSIC_PATH = "res://audio/background/06 - Victory!.mp3"

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

# Boss Fight System Functions
func setup_ui_references(ui: CanvasLayer, music: AudioStreamPlayer, sfx: AudioStreamPlayer) -> void:
	"""Setup references to UI layer, music player, and SFX player"""
	ui_layer = ui
	music_player = music
	sfx_player = sfx
	print("GameManager: UI references set - UI: ", ui_layer, " | Music: ", music_player, " | SFX: ", sfx_player)

func start_boss_sequence(boss_scene_path: String, spawn_pos_name: String = "BossSpawnPos") -> void:
	"""Orchestrate the boss fight sequence: Warning -> Music -> Spawn -> Health Bar"""
	print("GameManager: Starting boss sequence...")
	
	# Validate references
	if not ui_layer:
		push_error("GameManager: ui_layer is null! Call setup_ui_references() first.")
		return
	
	# Set boss active flag
	is_boss_active = true
	
	# Step 1: Play Boss Music
	if music_player:
		var boss_music = load(BOSS_MUSIC_PATH) as AudioStream
		if boss_music:
			music_player.stream = boss_music
			music_player.play()
			print("GameManager: Boss music started")
		else:
			push_warning("GameManager: Failed to load boss music!")
	
	# Step 2: Disable normal EnemySpawner
	var enemy_spawners = get_tree().get_nodes_in_group("enemy_spawner")
	for spawner in enemy_spawners:
		if spawner.has_method("set_enabled"):
			spawner.set_enabled(false)
		else:
			# Disable by stopping the timer
			var timer = spawner.get_node_or_null("Timer")
			if timer:
				timer.stop()
		print("GameManager: Disabled enemy spawner: ", spawner.name)
	
	# Step 3: Show Boss Warning Label (flash it)
	if ui_layer.has_method("show_boss_warning"):
		ui_layer.show_boss_warning()
		# Wait for warning to finish (it handles its own timing)
		await get_tree().create_timer(3.6).timeout  # 6 loops * 0.6s = 3.6s
	else:
		# Fallback: find warning label directly
		var warning_label = ui_layer.get_node_or_null("BossWarningLabel")
		if warning_label:
			warning_label.visible = true
			# Simple flash effect
			var tween = ui_layer.create_tween()
			tween.set_loops(6)
			tween.tween_property(warning_label, "modulate:a", 0.3, 0.3)
			tween.tween_property(warning_label, "modulate:a", 1.0, 0.3)
			await tween.finished
			warning_label.visible = false
	
	# Step 4: Wait 3 seconds
	await get_tree().create_timer(3.0).timeout
	
	# Step 5: Spawn Minotaur at BossSpawnPos
	var current_map = current_map_node
	if not current_map:
		push_error("GameManager: current_map_node is null! Cannot spawn boss.")
		return
	
	# Find spawn position
	var spawn_pos = current_map.find_child(spawn_pos_name, true, false)
	if not spawn_pos or not spawn_pos is Marker2D:
		push_error("GameManager: Could not find Marker2D '", spawn_pos_name, "' in current map!")
		return
	
	# Load and instantiate boss
	var boss_scene = load(boss_scene_path) as PackedScene
	if not boss_scene:
		push_error("GameManager: Failed to load boss scene: ", boss_scene_path)
		return
	
	var boss = boss_scene.instantiate()
	if not boss:
		push_error("GameManager: Failed to instantiate boss!")
		return
	
	# Set position and add to map
	boss.global_position = spawn_pos.global_position
	current_map.add_child(boss)
	current_boss = boss
	print("GameManager: Boss spawned at position: ", boss.global_position)
	
	# Step 6: Connect boss health_changed signal to UI update method
	if boss.has_signal("health_changed"):
		boss.health_changed.connect(ui_layer.update_boss_health)
		print("GameManager: Connected boss health_changed signal to UI")
	
	# Initialize health bar with boss's current HP (this will also make it visible)
	if "current_hp" in boss and "max_hp" in boss:
		ui_layer.update_boss_health(boss.current_hp, boss.max_hp)
	
	print("GameManager: Boss sequence complete!")

func _on_boss_health_changed(current_hp: int, max_hp: int) -> void:
	"""Callback for boss health_changed signal"""
	if ui_layer and ui_layer.has_method("update_boss_health"):
		ui_layer.update_boss_health(current_hp, max_hp)

func boss_defeated() -> void:
	"""Handle boss defeat: Stop music, hide health bar, show victory screen"""
	print("GameManager: Boss defeated!")
	
	# Step 1: Stop Boss Music
	if music_player:
		music_player.stop()
		print("GameManager: Boss music stopped")
	
	# Step 2: Play Victory Sound
	if sfx_player:
		var victory_sound = load(VICTORY_MUSIC_PATH) as AudioStream
		if victory_sound:
			sfx_player.stream = victory_sound
			sfx_player.play()
			print("GameManager: Victory sound played")
	
	# Step 3: Hide Boss Health Bar
	if ui_layer and ui_layer.has_method("hide_boss_health_bar"):
		ui_layer.hide_boss_health_bar()
	
	# Step 4: Show Victory Screen
	if ui_layer and ui_layer.has_method("show_victory_screen"):
		ui_layer.show_victory_screen()
	
	# Clear boss active flag
	is_boss_active = false
	current_boss = null
	
	print("GameManager: Boss defeat sequence complete!")
