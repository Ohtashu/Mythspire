extends Button

var player: Player
var is_clicked: bool = false

func _ready() -> void:
	# Find the player
	player = get_tree().get_first_node_in_group("player")
	
	# Disable mouse clicking - button can only be activated by keyboard
	disabled = false  # Keep button enabled for visual feedback
	# Override mouse input to prevent clicking
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Initialize button state based on player's current spear state
	if player:
		is_clicked = player.use_spear_animations
		_update_button_visual_state()

func _process(_delta: float) -> void:
	# Check for number 1 key press (toggle_spear action)
	if Input.is_action_just_pressed("toggle_spear"):
		_toggle_spear()

func _toggle_spear() -> void:
	if not player:
		return
	
	# Toggle clicked state
	is_clicked = !is_clicked
	
	# Update player's spear state
	player.use_spear_animations = is_clicked
	
	# Play sound effects
	if is_clicked:
		var equip_sound = player.get_node_or_null("sfx_equip")
		if equip_sound:
			equip_sound.play()
	else:
		var unequip_sound = player.get_node_or_null("sfx_unequip")
		if unequip_sound:
			unequip_sound.play()
	
	# Update button visual state
	_update_button_visual_state()

func _update_button_visual_state() -> void:
	# Create or get theme override
	if not theme:
		theme = Theme.new()
	
	# Create style boxes for normal and pressed states
	var normal_style = StyleBoxFlat.new()
	var pressed_style = StyleBoxFlat.new()
	
	if is_clicked:
		# Button is clicked/active - add border
		pressed_style.bg_color = Color(0.3, 0.3, 0.3, 0.3)  # Slight background tint
		pressed_style.border_color = Color.html("#467ccd")  # Blue border
		pressed_style.border_width_left = 2
		pressed_style.border_width_top = 2
		pressed_style.border_width_right = 2
		pressed_style.border_width_bottom = 2
		pressed_style.corner_radius_top_left = 2
		pressed_style.corner_radius_top_right = 2
		pressed_style.corner_radius_bottom_left = 2
		pressed_style.corner_radius_bottom_right = 2
		
		# Normal style (when not hovered but clicked)
		normal_style.bg_color = Color(0.2, 0.2, 0.2, 0.2)
		normal_style.border_color = Color.html("#467ccd")  # Blue border
		normal_style.border_width_left = 2
		normal_style.border_width_top = 2
		normal_style.border_width_right = 2
		normal_style.border_width_bottom = 2
		normal_style.corner_radius_top_left = 2
		normal_style.corner_radius_top_right = 2
		normal_style.corner_radius_bottom_left = 2
		normal_style.corner_radius_bottom_right = 2
		
		# Apply pressed style as the normal style when clicked
		theme.set_stylebox("normal", "Button", pressed_style)
		theme.set_stylebox("pressed", "Button", pressed_style)
		theme.set_stylebox("hover", "Button", pressed_style)
		modulate = Color(1.1, 1.1, 1.1)  # Slightly brighter when active
	else:
		# Button is unclicked/inactive - no border
		normal_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent
		normal_style.border_color = Color(0.0, 0.0, 0.0, 0.0)  # No border
		normal_style.border_width_left = 0
		normal_style.border_width_top = 0
		normal_style.border_width_right = 0
		normal_style.border_width_bottom = 0
		
		# Apply normal style
		theme.set_stylebox("normal", "Button", normal_style)
		theme.set_stylebox("pressed", "Button", normal_style)
		theme.set_stylebox("hover", "Button", normal_style)
		modulate = Color(1.0, 1.0, 1.0)  # Normal color when inactive

# Override to prevent mouse clicks
func _gui_input(event: InputEvent) -> void:
	# Ignore all mouse input events
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return
