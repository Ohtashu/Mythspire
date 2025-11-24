extends CharacterBody2D

const DamageIndicator = preload("res://scene/DamageIndicator.tscn")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var sfx_get_hit: AudioStreamPlayer2D = $sfx_evil_sword_damaged
@onready var sfx_attack: AudioStreamPlayer2D = $sfx_evil_sword_attack
@onready var damage_spawn_point: Marker2D = get_node_or_null("DamageSpawnPoint")

enum State {IDLE, ORBIT, DASH, HURT}

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
var is_stunned: bool = false  # Flag to track if evil sword is stunned
var stun_timer: float = 0.0  # Timer for stun duration
@export var hit_stun_duration: float = 0.15  # Duration of stun in seconds (0.15s = 150ms micro-stun)

# Grace period system
var can_attack_player: bool = false  # Can only attack player after grace period or if attacked
var grace_period_timer: Timer
const GRACE_PERIOD_DURATION: float = 4.0  # 4 seconds grace period

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
	
	# Setup grace period timer
	grace_period_timer = Timer.new()
	grace_period_timer.wait_time = GRACE_PERIOD_DURATION
	grace_period_timer.one_shot = true
	grace_period_timer.timeout.connect(_on_grace_period_timeout)
	add_child(grace_period_timer)
	
	# Start grace period on spawn
	start_grace_period()

func _physics_process(delta: float) -> void:
	# Skip normal behavior if dying
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	if not player:
		return

	# PRIORITY: HURT state takes priority over everything
	if is_stunned or current_state == State.HURT:
		handle_hurt(delta)
		move_and_slide()
		return

	if is_knockback:
		knockback_timer -= delta
		if knockback_timer <= 0:
			is_knockback = false
			change_state(State.ORBIT)
	
	var distance_to_player = global_position.distance_to(player.global_position)
	var can_see_player = check_line_of_sight()
	
	# Update bobbing offset (sine wave)
	bobbing_offset += delta * BOBBING_SPEED
	
	# State machine (only if not stunned/HURT)
	match current_state:
		State.IDLE:
			handle_idle(delta, distance_to_player, can_see_player)
		State.ORBIT:
			handle_orbit(delta, distance_to_player, can_see_player)
		State.DASH:
			handle_dash(delta)
		State.HURT:
			handle_hurt(delta)  # Should not reach here due to priority check above

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
	
	# Apply bobbing motion for ORBIT and IDLE states (floating effect)
	if current_state == State.ORBIT or current_state == State.IDLE:
		var bobbing_y = sin(bobbing_offset) * BOBBING_AMPLITUDE
		global_position.y = original_y + bobbing_y

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
		State.ORBIT:
			dash_timer = 0.0  # Reset dash cooldown
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
	"""Apply separation force to prevent enemies from stacking"""
	if current_state == State.HURT or current_state == State.DASH:
		return  # Don't separate during these states
	
	var separation = Vector2.ZERO
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	for enemy in enemies:
		if enemy == self:
			continue
		if not is_instance_valid(enemy):
			continue
		
		var distance = global_position.distance_to(enemy.global_position)
		if distance < SEPARATION_DISTANCE and distance > 0:
			var direction = (global_position - enemy.global_position).normalized()
			var force = (SEPARATION_DISTANCE - distance) / SEPARATION_DISTANCE
			separation += direction * force * SEPARATION_FORCE
	
	# Apply separation as additional velocity to desired_velocity
	if separation.length() > 0:
		desired_velocity += separation * get_physics_process_delta_time()

func handle_idle(_delta: float, distance: float, can_see: bool) -> void:
	"""IDLE: Stand still, transition to ORBIT if player detected"""
	if not can_attack_player:
		desired_velocity = Vector2.ZERO
		return
	
	desired_velocity = Vector2.ZERO
	
	# Transition to ORBIT if player is detected
	if can_see and distance <= DETECTION_RANGE:
		change_state(State.ORBIT)

func handle_orbit(delta: float, _distance: float, can_see: bool) -> void:
	"""ORBIT: Float around player at medium distance, encircle them"""
	if not can_attack_player:
		velocity = Vector2.ZERO
		return
	
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

func handle_hurt(delta: float) -> void:
	"""HURT: Stunned state - no movement or AI"""
	# Handle stun timer
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0:
			is_stunned = false
			stun_timer = 0.0
			# Exit HURT state after stun - return to appropriate state
			if player:
				var distance_to_player = global_position.distance_to(player.global_position)
				var can_see_player = check_line_of_sight()
				if can_see_player and distance_to_player <= DETECTION_RANGE:
					change_state(State.ORBIT)
				else:
					change_state(State.IDLE)
			else:
				change_state(State.IDLE)
	
	desired_velocity = Vector2.ZERO

func take_knockback(direction: Vector2) -> void:
	if is_dying:
		return
	
	is_knockback = true
	knockback_timer = KNOCKBACK_DURATION
	velocity = direction * KNOCKBACK_FORCE

func update_animation(_delta: float) -> void:
	# Don't change animation if dying
	if is_dying:
		return
	
	# Don't change animation if damaged animation is playing or stunned
	if is_playing_damaged or is_stunned:
		return
	
	if current_state == State.HURT:
		return  # Let hurt animation play
	
	if current_state == State.DASH:
		# Play attack animation during dash
		if animated_sprite.animation != "sword_attack":
			animated_sprite.play("sword_attack")
		return
	
	if current_state == State.ORBIT:
		# Play walking animation while orbiting
		if animated_sprite.animation != "sword_walking":
			animated_sprite.play("sword_walking")
		return

	# IDLE state
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
	
	# After damaged animation, wait for stun to finish (handled in _physics_process)
	if animated_sprite.animation == "sword_damaged":
		is_playing_damaged = false
		# Reset animation speed to normal
		animated_sprite.speed_scale = 1.0
		# State will be changed from HURT to IDLE/CHASE after stun timer expires
		return
	
	# Animation finished handlers for specific states
	if current_state == State.DASH:
		# Dash finished, return to orbit
		change_state(State.ORBIT)

func take_damage(amount: int) -> void:
	# Don't take damage if already dying
	if is_dying:
		return
	
	# Cancel grace period if enemy takes damage (player attacked first)
	if not can_attack_player:
		can_attack_player = true
		if grace_period_timer:
			grace_period_timer.stop()
	
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
		
		# Priority Interrupt: Cancel any current action
		desired_velocity = Vector2.ZERO
		velocity = Vector2.ZERO
		
		# Trigger stun state (HURT takes priority)
		is_stunned = true
		stun_timer = hit_stun_duration
		change_state(State.HURT)
		
		# Play damaged animation immediately (interrupts any current animation)
		if not is_playing_damaged:
			is_playing_damaged = true
			# Ensure animation doesn't loop
			if animated_sprite.sprite_frames:
				animated_sprite.sprite_frames.set_animation_loop("sword_damaged", false)
			# Speed up animation to match short stun duration
			animated_sprite.speed_scale = 2.0  # Play animation 2x faster
			animated_sprite.play("sword_damaged")
		
		print("Evil Sword took ", amount, " damage. Health: ", current_health, "/", max_health, " [STUNNED]")

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

func start_grace_period() -> void:
	"""Start the grace period where enemy ignores player unless attacked"""
	can_attack_player = false
	if grace_period_timer:
		grace_period_timer.start()
		print("Evil Sword: Grace period started (4 seconds)")

func _on_grace_period_timeout() -> void:
	"""Grace period ended, enemy can now attack player"""
	can_attack_player = true
	print("Evil Sword: Grace period ended, can now attack player")

func _spawn_damage_indicator(amount: int) -> void:
	"""Spawn a floating damage number indicator"""
	var indicator = DamageIndicator.instantiate()
	if indicator:
		# Set position - use DamageSpawnPoint if it exists, otherwise use a position above the evil sword
		var spawn_position: Vector2
		if damage_spawn_point:
			spawn_position = damage_spawn_point.global_position
		else:
			# Fallback: spawn above the evil sword (offset by sprite height)
			spawn_position = global_position + Vector2(0, -20)
		
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
			player.take_damage(EVIL_SWORD_DAMAGE)
