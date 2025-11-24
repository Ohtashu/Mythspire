extends Control

## Game Over Screen Script
## Handles game over UI, pausing, and player revival

@onready var tryagain_button: TextureButton = get_node_or_null("ContentContainer/tryagain_button")
@onready var game_over_music: AudioStreamPlayer2D = get_node_or_null("game_over_music")

# Retry Configuration - Hard Reset Settings
@export var game_scene_path: String = "res://scene/game.tscn"  # Path to the main game scene to reload

var player: CharacterBody2D

func _ready() -> void:
	# Hide the screen initially
	visible = false
	
	# Set process mode to always so it can receive input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find player reference
	player = get_tree().get_first_node_in_group("player")
	if not player:
		# Fallback: try to find Player in Game root
		var game_root = get_tree().current_scene
		if game_root:
			player = game_root.get_node_or_null("Player")
	
	# Note: tryagain_button has its own script (tryagain.gd) that will call _on_try_again_pressed()
	# We don't need to connect it here since the button script handles it

func show_game_over() -> void:
	# Pause the game
	get_tree().paused = true
	
	# Show the screen
	visible = true
	
	# Play the music
	if game_over_music:
		game_over_music.play()
	else:
		print("WARNING: game_over_music not found!")

func try_again() -> void:
	"""Called by tryagain.gd when the Try Again button is pressed - Performs a Hard Reset"""
	# Stop the music first
	if game_over_music:
		game_over_music.stop()
	
	# Unpause the game before changing scenes (required for scene change to work)
	get_tree().paused = false
	
	# Hide the screen
	visible = false
	
	# Hard Reset: Reload the entire game scene
	# This will reset:
	# - Player position to starting point
	# - Player health, stats, level, XP to defaults
	# - All enemies to their initial state
	# - All game state variables
	# - Enemy spawner to initial state
	print("Hard Reset: Reloading game scene from beginning...")
	
	# Reload the game scene - this completely resets everything
	get_tree().change_scene_to_file(game_scene_path)
