extends CharacterBody2D

const DamageIndicator = preload("res://scene/DamageIndicator.tscn")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var sfx_get_hit: AudioStreamPlayer2D = $sfx_evil_sword_damaged
@onready var sfx_attack: AudioStreamPlayer2D = $sfx_evil_sword_attack
@onready var damage_spawn_point: Marker2D = get_node_or_null("DamageSpawnPoint")

enum State {IDLE, NOTICE, ORBIT, DASH, HURT}

var player: CharacterBody2D
var raycast: RayCast2D
const DETECTION_RANGE = 135.0  # Medium detection range
const ATTACK_RANGE = 40.0  # Range for dash attack to hit player
const ORBIT_DISTANCE = 80.0  # Preferred distance from player when orbiting
const ORBIT_SPEED = 35.0  # Speed when orbiting
const DASH_SPEED = 300.0  # Very high speed for dash attack
const DASH_COOLDOWN = 3.0  # Time between dashes
const DASH_TELEGRAPH = 0.3  # Brief pause before dashing
const BOBBING_AMPLITUDE = 5.0  # How much it bobs up and down
const BOBBING_SPEED = 3.0  # Speed of bobbing motion
const SEPARATION_FORCE = 50.0  # Force to push enemies apart
const SEPARATION_DISTANCE = 30.0  # Distance to start separating
@export var friction: float = 10.0  # Velocity smoothing factor (higher = smoother, use with delta)

var current_state = State.IDLE
var desired_velocity: Vector2 = Vector2.ZERO  # Target velocity for smoothing
var dash_timer: float = 0.0
var dash_telegraph_timer: float = 0.0
var dash_target: Vector2 = Vector2.ZERO
var dash_direction: Vector2 = Vector2.ZERO
var orbit_angle: float = 0.0  # Current angle around player
var bobbing_offset: float = 0.0  # For sine wave bobbing
var original_y: float = 0.0  # Store original Y position for bobbing
var is_knockback: bool = false
var knockback_timer: float = 0.0
const KNOCKBACK_FORCE = 110.0
const KNOCKBACK_DURATION = 0.2
var is_dying: bool = false  # Flag to prevent normal behavior during death animation
var death_animation_complete: bool = false  # Flag to track if death animation completed
var is_playing_damaged: bool = false  # Flag to track if damaged animation is playing
# Reaction Time system (replaces Grace Period)
var reaction_timer: float = 0.0
@export var reaction_time: float = 0.75  # Time to notice player before chasing (0.5-1.0 seconds)

# Knockback system (replaces Stun)
var knockback_velocity: Vector2 = Vector2.ZERO
@export var knockback_force: float = 150.0  # Force of knockback
@export var knockback_friction: float = 8.0  # Friction to slow down knockback

# Health system - Medium tier (between Slime 30 and Skeleton 25)
var max_health: int = 27
var current_health: int = 27
const EVIL_SWORD_DAMAGE = 4  # Medium damage (between Slime 3 and Skeleton 5)

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player:
		# Fallback: try to find Player as sibling in Game root
		var game_root = get_tree().current_scene
		if game_root:
			player = game_root.get_node_or_null("Player")

	# Add raycast for line of sight
	raycast = RayCast2D.new()
	raycast.collide_with_bodies = true
	raycast.collision_mask = 1  # World layer
	add_child(raycast)

	animated_sprite.animation_finished.connect(_on_animated_sprite_2d_animation_finished)
	animated_sprite.frame_changed.connect(_on_frame_changed)
	
	# Initialize health
	current_health = max_health
	
	# Initialize animation to idle
	animated_sprite.play("sword_idle")
	
	# Store original Y position for bobbing
	original_y = global_position.y
	
	# Y-sorting depth optimization: Enable Y-sorting for proper depth perception
	# This ensures enemies sort correctly based on their Y position
	y_sort_enabled = true
	
	# Task 2: Fix physics dragging - ensure collision mask ignores player (layer 4) but keeps walls (layer 1)
	# Player is on layer 4, walls are on layer 1
	set_collision_mask_value(1, true)   # Collide with walls (layer 1)
	set_collision_mask_value(4, false)  # Don't collide with player (layer 4)

func _physics_process(delta: float) -> void:
	# Skip normal behavior if dying
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	if not player:
		return

	# Task 2: Apply knockback friction (replaces stun)
	# Apply friction to velocity so enemy slides to a stop smoothly
	if knockback_velocity.length() > 0.1:
		# Apply friction to slow down knockback velocity
		var friction_factor = 1.0 - (knockback_friction * delta)
		friction_factor = max(0.0, friction_factor)
		knockback_velocity *= friction_factor
		# Apply friction to main velocity as well (lerp towards zero)
		velocity = velocity.lerp(Vector2.ZERO, knockback_friction * delta)
		# Add remaining knockback to velocity
		velocity += knockback_velocity * delta
		# Clear very small knockback
		if knockback_velocity.length() < 0.1:
			knockback_velocity = Vector2.ZERO
	
	var distance_to_player = global_position.distance_to(player.global_position)
	var can_see_player = check_line_of_sight()
	
	# Update bobbing offset (sine wave)
	bobbing_offset += delta * BOBBING_SPEED
	
	# State machine
	match current_state:
		State.IDLE:
			handle_idle(delta, distance_to_player, can_see_player)
		State.NOTICE:
			handle_notice(delta, distance_to_player, can_see_player)
		State.ORBIT:
			handle_orbit(delta, distance_to_player, can_see_player)
		State.DASH:
			handle_dash(delta)
		State.HURT:
			handle_hurt(delta)

	# Bug 2 Fix: Apply separation force AFTER state handlers (so it doesn't get overridden)
	# This prevents enemies from stacking on top of each other
	apply_separation_force()

	# Task 1: Smooth velocity changes to prevent jitter
	# Lerp towards desired velocity for smooth movement
	if delta > 0:
		var lerp_factor = clamp(friction * delta, 0.0, 1.0)
		velocity = velocity.lerp(desired_velocity, lerp_factor)
	else:
		velocity = desired_velocity

	# Bug 1 Fix: Ensure velocity is zero during HURT state
	# (DASH state should keep its velocity for the attack)
	if current_state == State.HURT:
		desired_velocity = Vector2.ZERO
		velocity = Vector2.ZERO  # Instant stop for this state

	# Handle sprite flipping
	if velocity.x < 0:
		animated_sprite.flip_h = true
	elif velocity.x > 0:
		animated_sprite.flip_h = false

	# Update animation
	update_animation(delta)

	# Move and handle collisions
	move_and_slide()
	
	# Task 1: Apply bobbing motion smoothly (prevents teleporting)
	# Use a smooth lerp approach instead of directly setting position
	if current_state == State.ORBIT or current_state == State.IDLE:
		# Calculate target bobbing offset
		var target_bobbing_y = sin(bobbing_offset) * BOBBING_AMPLITUDE
		var target_y = original_y + target_bobbing_y
		
		# Smoothly lerp towards target Y position (prevents snapping)
		var current_y = global_position.y
		var bobbing_speed = BOBBING_SPEED * 5.0  # Speed multiplier for smooth movement
		var new_y = lerp(current_y, target_y, bobbing_speed * delta)
		global_position.y = new_y
	else:
		# When not bobbing, update original_y to current position
		original_y = global_position.y

func check_line_of_sight() -> bool:
	if not raycast or not player:
		return false
	raycast.target_position = player.global_position - global_position
	raycast.force_raycast_update()
	return not raycast.is_colliding()

func change_state(new_state: State) -> void:
	current_state = new_state
	match new_state:
		State.IDLE:
			desired_velocity = Vector2.ZERO
		State.NOTICE:
			desired_velocity = Vector2.ZERO  # Stop and look at player
			reaction_timer = 0.0
		State.ORBIT:
			dash_timer = 0.0  # Reset dash cooldown
			# Task 1: Calculate orbit_angle based on current position to prevent teleporting
			if player:
				var to_player = global_position - player.global_position
				# Calculate angle from current position (prevents snapping)
				orbit_angle = atan2(to_player.y, to_player.x)
			else:
				orbit_angle = 0.0
		State.DASH:
			# Lock in target and direction
			if player:
				dash_target = player.global_position
				dash_direction = (dash_target - global_position).normalized()
			dash_telegraph_timer = 0.0
			desired_velocity = Vector2.ZERO  # Pause during telegraph
		State.HURT:
			desired_velocity = Vector2.ZERO  # Stop all movement during hurt state

func apply_separation_force() -> void:
	"""Apply separation force to prevent enemies from stacking (optimized)"""
	if current_state == State.HURT or current_state == State.DASH:
		return  # Don't separate during these states
	
	var separation = Vector2.ZERO
	# Include both enemies and bosses for separation
	var enemies = get_tree().get_nodes_in_group("enemies")
	var bosses = get_tree().get_nodes_in_group("boss")
	var all_entities = enemies + bosses
	
	for entity in all_entities:
		if entity == self or not is_instance_valid(entity) or not entity is CharacterBody2D:
			continue
		
		var distance = global_position.distance_to(entity.global_position)
		if distance < SEPARATION_DISTANCE and distance > 0:
			var direction = (global_position - entity.global_position).normalized()
			var force = (SEPARATION_DISTANCE - distance) / SEPARATION_DISTANCE
			separation += direction * force * SEPARATION_FORCE
	
	# Apply separation as additional velocity to desired_velocity
	if separation.length() > 0:
		desired_velocity += separation * get_physics_process_delta_time()

func handle_idle(_delta: float, distance: float, can_see: bool) -> void:
	"""IDLE: Stand still, transition to NOTICE if player detected"""
	desired_velocity = Vector2.ZERO
	
	# Task 2: Transition to NOTICE state when player is detected
	if can_see and distance <= DETECTION_RANGE:
		change_state(State.NOTICE)

func handle_notice(delta: float, distance: float, can_see: bool) -> void:
	"""NOTICE: Look at player, wait for reaction time before orbiting"""
	desired_velocity = Vector2.ZERO  # Stop movement, look at player
	
	# Face the player
	if player:
		var direction_to_player = (player.global_position - global_position).normalized()
		if direction_to_player.x < 0:
			animated_sprite.flip_h = true
		elif direction_to_player.x > 0:
			animated_sprite.flip_h = false
	
	# Check if player left range
	if not can_see or distance > DETECTION_RANGE:
		change_state(State.IDLE)
		return
	
	# Update reaction timer
	reaction_timer += delta
	
	# If reaction time passed, start orbiting
	if reaction_timer >= reaction_time:
		change_state(State.ORBIT)

func handle_orbit(delta: float, _distance: float, can_see: bool) -> void:
	"""ORBIT: Float around player at medium distance, encircle them"""
	if not can_see:
		change_state(State.IDLE)
		return
	
	# Update dash cooldown
	dash_timer += delta
	
	# Calculate orbit position
	# Orbit around player (encircle)
	orbit_angle += delta * 1.5  # Rotate around player
	var orbit_offset = Vector2(cos(orbit_angle), sin(orbit_angle)) * ORBIT_DISTANCE
	var orbit_target = player.global_position + orbit_offset
	
	# Move toward orbit position
	var move_direction = (orbit_target - global_position).normalized()
	desired_velocity = move_direction * ORBIT_SPEED
	
	# Check if it's time to dash
	if dash_timer >= DASH_COOLDOWN:
		change_state(State.DASH)

func handle_dash(delta: float) -> void:
	"""DASH: Lock on, pause briefly, then dash through player at high speed"""
	dash_telegraph_timer += delta
	
	# Telegraph phase: pause briefly
	if dash_telegraph_timer < DASH_TELEGRAPH:
		desired_velocity = Vector2.ZERO
		# Face the target
		if dash_direction.length() > 0:
			if dash_direction.x < 0:
				animated_sprite.flip_h = true
			elif dash_direction.x > 0:
				animated_sprite.flip_h = false
		return
	
	# Dash phase: move at high speed (instant velocity for dash attack)
	desired_velocity = dash_direction * DASH_SPEED
	velocity = desired_velocity  # Instant velocity for dash attack
	
	# Check if we've passed the target or moved far enough
	var distance_to_target = global_position.distance_to(dash_target)
	
	# If we've gone past the target or moved far enough, return to orbit
	if distance_to_target > 100.0 or velocity.length() < DASH_SPEED * 0.3:
		change_state(State.ORBIT)
	
	# Don't stop on collision - fly through (handled by move_and_slide)

func handle_hurt(_delta: float) -> void:
	"""HURT: Brief animation state - quickly return to appropriate state"""
	desired_velocity = Vector2.ZERO
	
	# Exit HURT state quickly - return to appropriate state based on player position
	if player:
		var distance_to_player = global_position.distance_to(player.global_position)
		var can_see_player = check_line_of_sight()
		if can_see_player and distance_to_player <= DETECTION_RANGE:
			change_state(State.ORBIT)
		else:
			change_state(State.IDLE)
	else:
		change_state(State.IDLE)

func take_knockback(direction: Vector2) -> void:
	if is_dying:
		return
	
	is_knockback = true
	knockback_timer = KNOCKBACK_DURATION
	velocity = direction * KNOCKBACK_FORCE

# Animation name constants (optimized)
const ANIM_IDLE = "sword_idle"
const ANIM_WALKING = "sword_walking"
const ANIM_ATTACK = "sword_attack"
const ANIM_DAMAGED = "sword_damaged"
const ANIM_DEATH = "sword_death"

func update_animation(_delta: float) -> void:
	# Don't change animation if dying or damaged animation playing
	if is_dying or is_playing_damaged:
		return
	
	# Early return for hurt state
	if current_state == State.HURT:
		return
	
	# Get current animation (cached)
	var current_anim = animated_sprite.animation
	
	# State-based animation (optimized)
	match current_state:
		State.DASH:
			if current_anim != ANIM_ATTACK:
				animated_sprite.play(ANIM_ATTACK)
		State.ORBIT:
			if current_anim != ANIM_WALKING:
				animated_sprite.play(ANIM_WALKING)
		State.NOTICE, State.IDLE:
			if current_anim != ANIM_IDLE:
				animated_sprite.play(ANIM_IDLE)
	if animated_sprite.animation != "sword_idle":
		animated_sprite.play("sword_idle")

func _on_frame_changed() -> void:
	# Track death animation completion
	if is_dying and animated_sprite.animation == "sword_die" and not death_animation_complete:
		if animated_sprite.sprite_frames:
			var frame_count = animated_sprite.sprite_frames.get_frame_count("sword_die")
			# Check if we're on the last frame (frame_count - 1)
			# When we reach the last frame, mark as complete and queue_free on next frame
			if animated_sprite.frame >= frame_count - 1:
				death_animation_complete = true
				# Use call_deferred to remove on next frame
				call_deferred("queue_free")
				return
	
	# Task 2 Alternative: Frame-based damage for AnimatedSprite2D
	# Deal damage on specific attack frame (frame 3 of sword_attack animation)
	if current_state == State.DASH and animated_sprite.animation == "sword_attack":
		if animated_sprite.frame == 3:  # Adjust this frame number to match your animation
			deal_damage()

func _on_animated_sprite_2d_animation_finished() -> void:
	# Check if death animation finished (if loop was disabled)
	if is_dying and animated_sprite.animation == "sword_die":
		# Actually remove the evil sword now
		queue_free()
		return
	
	# After damaged animation, exit HURT state (knockback continues in _physics_process)
	if animated_sprite.animation == "sword_damaged":
		is_playing_damaged = false
		# State will be changed from HURT to appropriate state
		return
	
	# Animation finished handlers for specific states
	if current_state == State.DASH:
		# Dash finished, return to orbit
		change_state(State.ORBIT)

func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	# Don't take damage if already dying
	if is_dying:
		return
	
	# Task 2: If in NOTICE state and taking damage, cancel reaction and immediately orbit
	if current_state == State.NOTICE:
		change_state(State.ORBIT)
	
	# Play damage sound
	if sfx_get_hit:
		sfx_get_hit.play()
	
	# Trigger screen shake
	_trigger_screen_shake(5.0, 0.2)
	
	# Spawn damage indicator
	_spawn_damage_indicator(amount)
	
	# Evil sword takes full damage (no reduction like skeleton)
	current_health -= amount
	if current_health < 0:
		current_health = 0
	# Handle death
	if current_health <= 0:
		die()
	else:
		# Task 3: Hit flash effect - flash white for 0.1 seconds
		_trigger_hit_flash()
		
		# Task 2: Apply knockback (replaces stun)
		# Calculate knockback direction and apply directly to velocity
		if source_position != Vector2.ZERO:
			var knockback_direction = (global_position - source_position).normalized()
			knockback_velocity = knockback_direction * knockback_force
			velocity = knockback_direction * knockback_force  # Direct velocity assignment
		else:
			# Fallback: knockback away from player if no source position
			if player:
				var knockback_direction = (global_position - player.global_position).normalized()
				knockback_velocity = knockback_direction * knockback_force
				velocity = knockback_direction * knockback_force  # Direct velocity assignment
		
		# Priority Interrupt: Cancel any current action
		desired_velocity = Vector2.ZERO
		
		# Play damaged animation immediately (interrupts any current animation)
		change_state(State.HURT)
		if not is_playing_damaged:
			is_playing_damaged = true
			# Ensure animation doesn't loop
			if animated_sprite.sprite_frames:
				animated_sprite.sprite_frames.set_animation_loop("sword_damaged", false)
			animated_sprite.speed_scale = 1.0  # Normal speed for knockback
			animated_sprite.play("sword_damaged")
		
		print("Evil Sword took ", amount, " damage. Health: ", current_health, "/", max_health, " [KNOCKBACK]")

func _trigger_screen_shake(intensity: float, duration: float) -> void:
	"""Trigger screen shake effect on the camera"""
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(intensity, duration)

func die() -> void:
	if is_dying:
		return  # Already dying, don't call again
	
	is_dying = true
	print("Evil Sword died! Playing death animation...")
	
	# Give player EXP (between Slime 80-120 and Skeleton 150-200, let's say 110-150)
	if player and player.has_method("gain_xp"):
		var exp_amount = randi_range(110, 150)
		player.gain_xp(exp_amount)
		print("Evil Sword gave player ", exp_amount, " XP")
	
	# Stop all movement and state changes
	velocity = Vector2.ZERO
	current_state = State.IDLE
	
	# Disable collision and monitoring
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Disable hitbox and hurtbox
	var hitbox_area = get_node_or_null("hitbox/hitbox")
	if hitbox_area:
		hitbox_area.set_deferred("monitoring", false)
		hitbox_area.set_deferred("monitorable", false)
	
	var hurtbox_area = get_node_or_null("hurtbox/hurtbox2")
	if hurtbox_area:
		hurtbox_area.set_deferred("monitoring", false)
		hurtbox_area.set_deferred("monitorable", false)
	
	# Disable looping for death animation so it only plays once
	if animated_sprite.sprite_frames:
		animated_sprite.sprite_frames.set_animation_loop("sword_die", false)
	
	# Reset completion flag
	death_animation_complete = false
	
	# Play death animation
	animated_sprite.play("sword_die")


func _spawn_damage_indicator(amount: int) -> void:
	"""Spawn a floating damage number indicator"""
	var indicator = DamageIndicator.instantiate()
	if indicator:
		# Task 3: Use DamageSpawnPoint if it exists, otherwise default to global_position
		var spawn_position: Vector2
		if damage_spawn_point:
			spawn_position = damage_spawn_point.global_position
		else:
			# Default to global_position if DamageSpawnPoint node is missing
			spawn_position = global_position
		
		# Add random offset to prevent overlapping
		spawn_position += Vector2(randf_range(-10, 10), randf_range(-10, 10))
		
		indicator.global_position = spawn_position
		indicator.set_amount(amount)
		
		# Add to current scene so it doesn't move with the enemy
		var current_scene = get_tree().current_scene
		if current_scene:
			current_scene.add_child(indicator)

func _trigger_hit_flash() -> void:
	"""Task 3: Flash white for 0.1 seconds when taking damage"""
	# Set modulate to white
	animated_sprite.modulate = Color.WHITE
	
	# Create a tween to fade back to normal color after 0.1 seconds
	var tween = create_tween()
	tween.tween_property(animated_sprite, "modulate", Color(1, 1, 1, 1), 0.1)

func deal_damage() -> void:
	"""Task 2: Deal damage to player when called from animation frame"""
	# This function will be called from AnimationPlayer's Call Method Track
	# Check if player is in range and can be hit
	if not player:
		return
	
	if current_state != State.DASH:
		return  # Only deal damage during dash attack
	
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player <= ATTACK_RANGE * 2.0:  # Extended range for dash
		# Deal damage to player
		if player.has_method("take_damage"):
			# Task 2: Pass evil_sword's position for knockback
			player.take_damage(EVIL_SWORD_DAMAGE, global_position)
