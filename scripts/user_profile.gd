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
	print("\n=== UserProfile: Button _ready() ===")
	print("UserProfile: Button name: ", name)
	var parent_node = get_parent()
	var parent_name = parent_node.name if parent_node else StringName("No parent")
	print("UserProfile: Button parent: ", parent_name)
	print("UserProfile: Button path: ", get_path())
	
	# Ensure the button is interactive
	if disabled:
		disabled = false
		print("UserProfile: Button was disabled, now enabled")
	
	# Force mouse filter to STOP so the button receives input
	mouse_filter = Control.MOUSE_FILTER_STOP
	print("UserProfile: Mouse filter set to STOP")
	
	# Connect button press signal - use direct method reference
	print("UserProfile: Attempting to connect pressed signal...")
	if not self.pressed.is_connected(_on_button_pressed):
		self.pressed.connect(_on_button_pressed)
		print("UserProfile: ✓ Signal connected successfully")
	else:
		print("UserProfile: Signal already connected")
	
	# Get the click_profile sound node from the parent player_hud
	# Structure: profile button (health_control) -> health_control -> player_hud (root) -> click_profile
	await get_tree().process_frame
	print("UserProfile: Looking for click_profile sound...")
	
	var click_profile_node = get_node_or_null("../../click_profile")
	if click_profile_node and click_profile_node is AudioStreamPlayer2D:
		click_profile_sound = click_profile_node
		print("UserProfile: ✓ Sound node found at ../../click_profile")
	else:
		print("UserProfile: ✗ click_profile sound NOT found at ../../click_profile")
		# Try alternative path through tree root
		var game_root = get_tree().root.get_child(0)
		if game_root:
			click_profile_node = game_root.get_node_or_null("player_hud/click_profile")
			if click_profile_node and click_profile_node is AudioStreamPlayer2D:
				click_profile_sound = click_profile_node
				print("UserProfile: ✓ Sound node found via game root path")
			else:
				print("UserProfile: ✗ Sound node not found via game root either")
	
	print("=== UserProfile: Ready Complete ===\n")

func _on_button_pressed() -> void:
	print("UserProfile: Button pressed!")
	
	# Play click sound effect
	if click_profile_sound:
		click_profile_sound.play()
		print("UserProfile: Click sound played")
	
	# Release focus immediately to prevent white border
	release_focus()
	
	if is_profile_open:
		close_profile()
	else:
		open_profile()

func _gui_input(event: InputEvent) -> void:
	"""Catch mouse clicks directly as a backup"""
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			print("UserProfile: Direct GUI input detected - calling button press")
			_on_button_pressed()
			# In Godot 4.5, use get_tree().root.gui_release_focus() or consume the event
			# We can also just return true to indicate the event was handled

func open_profile() -> void:
	if is_profile_open:
		print("UserProfile: Profile already open, returning")
		return
	
	print("UserProfile: Opening profile...")
	
	# Instantiate the player_profile scene (Control)
	player_profile_instance = player_profile_scene.instantiate()
	if not player_profile_instance:
		push_error("UserProfile: Failed to instantiate player_profile scene!")
		return
	
	# Create a dedicated CanvasLayer with high layer value to ensure it's always on top
	# This ensures the profile appears on screen regardless of camera position
	profile_canvas_layer = CanvasLayer.new()
	profile_canvas_layer.layer = 100  # Higher than the main HUD (which is typically layer 0 or 1)
	
	# Add the CanvasLayer to the scene tree root (this ensures it's independent of camera)
	var root = get_tree().root
	if root:
		root.add_child(profile_canvas_layer)
		print("UserProfile: CanvasLayer added to root")
		
		# Add the profile instance to the CanvasLayer
		profile_canvas_layer.add_child(player_profile_instance)
		print("UserProfile: Profile instance added to CanvasLayer")
		
		# Ensure the profile is visible and on top
		player_profile_instance.visible = true
		player_profile_instance.z_index = 100
		player_profile_instance.mouse_filter = Control.MOUSE_FILTER_STOP  # Allow input
		
		# Make sure the profile UI can still process input when paused
		# Set to WHEN_PAUSED so it only processes when game is paused (modal behavior)
		player_profile_instance.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		
		# Connect to tree_exited signal so we know when profile is closed
		if not player_profile_instance.tree_exited.is_connected(_on_profile_closed):
			player_profile_instance.tree_exited.connect(_on_profile_closed)
		
		# Pause the game (pause mode = PROCESS_MODE_PAUSED)
		get_tree().paused = true
		
		is_profile_open = true
		
		print("UserProfile: Profile opened successfully")
		print("UserProfile: Visible: ", player_profile_instance.visible, " | In tree: ", player_profile_instance.is_inside_tree(), " | Paused: ", get_tree().paused)
	else:
		push_error("UserProfile: Could not find root node to add CanvasLayer to!")
		is_profile_open = false

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
	print("UserProfile: Closing profile...")
	
	if not is_profile_open or not player_profile_instance:
		print("UserProfile: Profile not open or instance null, returning")
		return
	
	# Unpause the game first (before removing the node)
	var tree = get_tree()
	if tree:
		tree.paused = false
		print("UserProfile: Game unpaused")
	
	# Remove the profile instance
	if is_valid_instance(player_profile_instance):
		# Disconnect signals before freeing to avoid calling _on_profile_closed
		if player_profile_instance.tree_exited.is_connected(_on_profile_closed):
			player_profile_instance.tree_exited.disconnect(_on_profile_closed)
		player_profile_instance.queue_free()
		print("UserProfile: Profile instance queued for deletion")
	
	# Clean up the CanvasLayer
	if profile_canvas_layer and is_instance_valid(profile_canvas_layer):
		profile_canvas_layer.queue_free()
		print("UserProfile: CanvasLayer queued for deletion")
	
	profile_canvas_layer = null
	player_profile_instance = null
	is_profile_open = false
	
	print("UserProfile: Profile closed - game resumed")

func is_valid_instance(instance: Node) -> bool:
	return instance and is_instance_valid(instance) and instance.is_inside_tree()
