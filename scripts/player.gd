extends CharacterBody2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var walk_sound: AudioStreamPlayer2D = get_node_or_null("WalkSound")

const SPEED = 200.0
const STEP_INTERVAL = 0.4  # Time between step sounds (in seconds)

var last_direction: String = "down"
var was_moving: bool = false
var step_timer: float = 0.0

func _physics_process(delta: float) -> void:
	# Get input direction for top-down movement
	var input_vector := Vector2.ZERO
	input_vector.x = Input.get_axis("move_left", "move_right")
	input_vector.y = Input.get_axis("move_up", "move_down")
	
	# Normalize diagonal movement
	if input_vector.length() > 0:
		input_vector = input_vector.normalized()
	
	# Apply movement
	velocity = input_vector * SPEED
	move_and_slide()
	
	# Update animation based on movement
	update_animation(input_vector, delta)

func update_animation(direction: Vector2, delta: float) -> void:
	var anim_name: String = ""
	
	# Determine if player is moving
	var is_moving := direction.length() > 0
	
	# Handle walking sound
	handle_walk_sound(is_moving, delta)
	
	if is_moving:
		# Logic based on user requirements:
		# W = forward/up → use "top" animations
		# S = backward/down → use "down" animations
		# A/D = left/right → use "left"/"right" animations
		# Diagonal up+left/right → use "top_left"/"top_right" animations
		# Diagonal down+left/right → use "down" animations
		
		var moving_up := direction.y < -0.1  # W key (negative Y in Godot)
		var moving_down := direction.y > 0.1   # S key (positive Y in Godot)
		var moving_left := direction.x < -0.1  # A key (negative X)
		var moving_right := direction.x > 0.1  # D key (positive X)
		
		if moving_up:
			# Moving up (W key) - use "top" animations
			if moving_left:
				# Up + Left = top_left
				anim_name = "walk_top_left"
				last_direction = "top_left"
			elif moving_right:
				# Up + Right = top_right
				anim_name = "walk_top_right"
				last_direction = "top_right"
			else:
				# Pure up
				anim_name = "walk_top"
				last_direction = "top"
		elif moving_down:
			# Moving down (S key) - use "down" animations
			# Note: No specific diagonal down animations, so always use walk_down
			anim_name = "walk_down"
			last_direction = "down"
		elif moving_left:
			# Moving left (A key) - use "left" animations
			anim_name = "walk_left"
			last_direction = "left"
		elif moving_right:
			# Moving right (D key) - use "right" animations
			anim_name = "walk_right"
			last_direction = "right"
		else:
			# Fallback (shouldn't happen if is_moving is true)
			anim_name = "walk_down"
			last_direction = "down"
	else:
		# Use idle animation based on last direction
		match last_direction:
			"right":
				anim_name = "idle_right"
			"left":
				anim_name = "idle_left"
			"top":
				anim_name = "idle_top"
			"top_right":
				anim_name = "idle_top_right"
			"top_left":
				anim_name = "idle_top_left"
			_:
				anim_name = "idle_down"
	
	# Play animation if it's different from current
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)

func handle_walk_sound(is_moving: bool, delta: float) -> void:
	# Only handle sound if AudioStreamPlayer2D exists
	if not walk_sound:
		return
	
	if is_moving:
		# Update step timer
		step_timer += delta
		
		# Play step sound at intervals
		if step_timer >= STEP_INTERVAL:
			walk_sound.play()
			step_timer = 0.0  # Reset timer
		
		# If just started moving, play immediately
		if not was_moving:
			walk_sound.play()
			step_timer = 0.0
	else:
		# Not moving - reset timer
		step_timer = 0.0
	
	was_moving = is_moving
