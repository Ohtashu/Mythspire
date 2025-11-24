extends Button

## User Profile Button
## Opens the player_profile scene as a popup window and pauses the game

@onready var player_profile_scene = preload("res://scene/player_profile.tscn")
var player_profile_instance: Control = null
var profile_canvas_layer: CanvasLayer = null
var is_profile_open: bool = false

# Sound effect reference (click_profile is a child of player_hud root)
var click_profile_sound: AudioStreamPlayer2D = null

func _ready() -> void:
	# Connect button press signal
	if not pressed.is_connected(_on_button_pressed):
		pressed.connect(_on_button_pressed)
	
	# Get the click_profile sound node from the parent player_hud
	# Structure: profile button -> health_control -> player_hud (root) -> click_profile
	# Wait a frame to ensure the scene tree is fully ready
	await get_tree().process_frame
	var player_hud = get_node_or_null("../../click_profile")
	if player_hud and player_hud is AudioStreamPlayer2D:
		click_profile_sound = player_hud

func _on_button_pressed() -> void:
	# Play click sound effect
	if click_profile_sound:
		click_profile_sound.play()
	
	# Release focus immediately to prevent white border
	release_focus()
	
	if is_profile_open:
		close_profile()
	else:
		open_profile()

func open_profile() -> void:
	if is_profile_open:
		return
	
	# Instantiate the player_profile scene (Control)
	player_profile_instance = player_profile_scene.instantiate()
	
	# Create a dedicated CanvasLayer with high layer value to ensure it's always on top
	# This ensures the profile appears on screen regardless of camera position
	profile_canvas_layer = CanvasLayer.new()
	profile_canvas_layer.layer = 100  # Higher than the main HUD (which is typically layer 0 or 1)
	
	# Add the CanvasLayer to the scene tree root (this ensures it's independent of camera)
	var root = get_tree().root
	if root:
		root.add_child(profile_canvas_layer)
		
		# Add the profile instance to the CanvasLayer
		profile_canvas_layer.add_child(player_profile_instance)
		is_profile_open = true
		
		# Make sure the profile UI is visible
		player_profile_instance.visible = true
		player_profile_instance.z_index = 100
		
		# Make sure the profile UI can still process input when paused
		# Set to WHEN_PAUSED so it only processes when game is paused (modal behavior)
		player_profile_instance.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		
		# Connect to tree_exited signal so we know when profile is closed
		if not player_profile_instance.tree_exited.is_connected(_on_profile_closed):
			player_profile_instance.tree_exited.connect(_on_profile_closed)
		
		# Pause the game (pause mode = PROCESS_MODE_PAUSED)
		get_tree().paused = true
		
		print("UserProfile: Profile added to CanvasLayer (layer 100). Visible: ", player_profile_instance.visible, " In tree: ", player_profile_instance.is_inside_tree())
	else:
		push_error("UserProfile: Could not find root node to add CanvasLayer to!")

func _on_profile_closed() -> void:
	# Profile was closed (either by ESC or other means)
	is_profile_open = false
	
	# Clean up the CanvasLayer
	if profile_canvas_layer and is_instance_valid(profile_canvas_layer):
		profile_canvas_layer.queue_free()
	profile_canvas_layer = null
	player_profile_instance = null
	
	# Make sure game is unpaused (check if tree is still valid)
	var tree = get_tree()
	if tree and tree.paused:
		tree.paused = false
	
	print("Player profile closed - game resumed")

func close_profile() -> void:
	if not is_profile_open or not player_profile_instance:
		return
	
	# Unpause the game first (before removing the node)
	var tree = get_tree()
	if tree:
		tree.paused = false
	
	# Remove the profile instance
	if is_valid_instance(player_profile_instance):
		# Disconnect signals before freeing to avoid calling _on_profile_closed
		if player_profile_instance.tree_exited.is_connected(_on_profile_closed):
			player_profile_instance.tree_exited.disconnect(_on_profile_closed)
		player_profile_instance.queue_free()
	
	# Clean up the CanvasLayer
	if profile_canvas_layer and is_instance_valid(profile_canvas_layer):
		profile_canvas_layer.queue_free()
	
	profile_canvas_layer = null
	player_profile_instance = null
	is_profile_open = false
	
	print("Player profile closed - game resumed")

func is_valid_instance(instance: Node) -> bool:
	return instance and is_instance_valid(instance) and instance.is_inside_tree()
