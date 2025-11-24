extends CharacterBody2D

const DamageIndicator = preload("res://scene/DamageIndicator.tscn")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var sfx_footstep: AudioStreamPlayer2D = get_node_or_null("slime_walk")
@onready var sfx_get_damaged: AudioStreamPlayer2D = get_node_or_null("slime_get_damaged")
@onready var damage_spawn_point: Marker2D = get_node_or_null("DamageSpawnPoint")

enum State {IDLE, PREPARE, LUNGE, RECOVERY, HURT}

var player: CharacterBody2D
var raycast: RayCast2D
const DETECTION_RANGE = 120.0  # Shorter detection range
const PREPARE_RANGE = 80.0  # Start preparing when within this range
const LUNGE_RANGE = 60.0  # Lunge when within this range
const HOP_SPEED = 80.0  # Speed for small hops in IDLE
const LUNGE_SPEED = 200.0  # High speed for lunge attack
const PREPARE_DURATION = 0.5  # Time to squash before lunging
const RECOVERY_DURATION = 1.0  # Time to recover after landing
const HOP_INTERVAL = 1.5  # Time between hops in IDLE
const SEPARATION_FORCE = 50.0  # Force to push enemies apart
const SEPARATION_DISTANCE = 30.0  # Distance to start separating
@export var friction: float = 10.0  # Velocity smoothing factor (higher = smoother, use with delta)

var current_state = State.IDLE
var desired_velocity: Vector2 = Vector2.ZERO  # Target velocity for smoothing
var lunge_target: Vector2 = Vector2.ZERO  # Target position for lunge
var lunge_direction: Vector2 = Vector2.ZERO  # Direction for lunge (locked)
var prepare_timer: float = 0.0
var recovery_timer: float = 0.0
var hop_timer: float = 0.0
var hop_direction: Vector2 = Vector2.ZERO
var original_scale: Vector2 = Vector2.ONE
var is_knockback: bool = false
var knockback_timer: float = 0.0
const KNOCKBACK_FORCE = 100.0
const KNOCKBACK_DURATION = 0.2
var is_dying: bool = false  # Flag to prevent normal behavior during death animation
var death_animation_complete: bool = false  # Flag to track if death animation completed
var is_playing_damaged: bool = false  # Flag to track if damaged animation is playing
var is_stunned: bool = false  # Flag to track if slime is stunned
var stun_timer: float = 0.0  # Timer for stun duration
@export var hit_stun_duration: float = 0.15  # Duration of stun in seconds (0.15s = 150ms micro-stun)

# Grace period system
var can_attack_player: bool = false  # Can only attack player after grace period or if attacked
var grace_period_timer: Timer
const GRACE_PERIOD_DURATION: float = 4.0  # 4 seconds grace period

# Health system
var max_health: int = 30  # Less health than skeleton
var current_health: int = 30
const SLIME_DAMAGE = 3  # Less damage than skeleton (reduced for level 1 balance)

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
	animated_sprite.play("slime_idle")
	
	# Store original scale for squash effect
	original_scale = animated_sprite.scale
	
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
			change_state(State.IDLE)
	
	var distance_to_player = global_position.distance_to(player.global_position)
	var can_see_player = check_line_of_sight()
	
	# State machine (only if not stunned/HURT)
	match current_state:
		State.IDLE:
			handle_idle(delta, distance_to_player, can_see_player)
		State.PREPARE:
			handle_prepare(delta, distance_to_player)
		State.LUNGE:
			handle_lunge(delta)
		State.RECOVERY:
			handle_recovery(delta, distance_to_player, can_see_player)
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
	
	# Bug 1 Fix: Ensure velocity is zero during PREPARE, RECOVERY, and HURT states
	# (LUNGE state should keep its velocity for the attack)
	if current_state == State.PREPARE or current_state == State.RECOVERY or current_state == State.HURT:
		desired_velocity = Vector2.ZERO
		velocity = Vector2.ZERO  # Instant stop for these states

	# Handle sprite flipping
	if velocity.x < 0:
		animated_sprite.flip_h = true
	elif velocity.x > 0:
		animated_sprite.flip_h = false

	# Update animation
	update_animation(delta)

	# Move and handle collisions
	var was_colliding = get_slide_collision_count() > 0
	move_and_slide()
	
	# Fix: Prevent slime from being dragged by player when too close
	# Check if we collided with something and are very close to player
	if player and was_colliding:
		if distance_to_player < 20.0:  # Very close to player
			# Check if we're being pushed by checking collision
			for i in range(get_slide_collision_count()):
				var collision = get_slide_collision(i)
				var collider = collision.get_collider()
				# If we collided with the player, prevent being pushed
				if collider == player or collider.is_in_group("player"):
					# Reset position to prevent being dragged
					# Only do this if we're not in lunge state (allow attacks to work)
					if current_state != State.LUNGE:
						# Move back slightly to prevent overlap
						var push_back = (global_position - player.global_position).normalized() * 2.0
						global_position += push_back
					break

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
			hop_timer = 0.0
		State.PREPARE:
			desired_velocity = Vector2.ZERO
			prepare_timer = 0.0
			# Start squash animation (scale down Y)
			animated_sprite.scale = Vector2(original_scale.x, original_scale.y * 0.7)
		State.LUNGE:
			# Lock in direction and target
			if player:
				lunge_target = player.global_position
				lunge_direction = (lunge_target - global_position).normalized()
			desired_velocity = lunge_direction * LUNGE_SPEED
			# Reset scale
			animated_sprite.scale = original_scale
		State.RECOVERY:
			desired_velocity = Vector2.ZERO
			recovery_timer = 0.0
		State.HURT:
			desired_velocity = Vector2.ZERO  # Stop all movement during hurt state
			# Reset scale
			animated_sprite.scale = original_scale

func apply_separation_force() -> void:
	"""Apply separation force to prevent enemies from stacking"""
	if current_state == State.HURT or current_state == State.LUNGE:
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

func handle_idle(delta: float, distance: float, can_see: bool) -> void:
	"""IDLE: Random hops in small areas"""
	if not can_attack_player:
		desired_velocity = Vector2.ZERO
		return
	
	hop_timer += delta
	
	# Make small hops
	if hop_timer >= HOP_INTERVAL:
		hop_timer = 0.0
		# Choose random direction for hop
		var angle = randf() * 2 * PI
		hop_direction = Vector2(cos(angle), sin(angle))
	
	# Apply hop movement to desired_velocity
	if hop_direction.length() > 0:
		desired_velocity = hop_direction * HOP_SPEED
	else:
		desired_velocity = Vector2.ZERO
	
	# Transition to PREPARE if player is close
	if can_see and distance <= PREPARE_RANGE:
		change_state(State.PREPARE)

func handle_prepare(delta: float, distance: float) -> void:
	"""PREPARE: Stop and squash before lunging"""
	prepare_timer += delta
	desired_velocity = Vector2.ZERO
	
	# Continue squashing (scale animation)
	var squash_amount = 0.7 + (prepare_timer / PREPARE_DURATION) * 0.1  # Slight bounce
	animated_sprite.scale = Vector2(original_scale.x, original_scale.y * squash_amount)
	
	# Transition to LUNGE after prepare duration
	if prepare_timer >= PREPARE_DURATION:
		if distance <= LUNGE_RANGE:
			change_state(State.LUNGE)
		else:
			# Player moved away, go back to IDLE
			animated_sprite.scale = original_scale
			change_state(State.IDLE)

func handle_lunge(_delta: float) -> void:
	"""LUNGE: Launch rapidly toward player (direction locked)"""
	# Direction is locked, set desired velocity directly (no smoothing for lunge)
	desired_velocity = lunge_direction * LUNGE_SPEED
	velocity = desired_velocity  # Instant velocity for lunge attack
	
	# Check if we've passed the target or hit something
	var distance_to_target = global_position.distance_to(lunge_target)
	
	# If we've gone past the target or moved far enough, start recovery
	if distance_to_target > 50.0 or velocity.length() < LUNGE_SPEED * 0.5:
		change_state(State.RECOVERY)
	
	# Check collision - if we hit something, start recovery
	if get_slide_collision_count() > 0:
		change_state(State.RECOVERY)

func handle_recovery(delta: float, distance: float, can_see: bool) -> void:
	"""RECOVERY: Land and pause before moving again"""
	recovery_timer += delta
	desired_velocity = Vector2.ZERO
	
	if recovery_timer >= RECOVERY_DURATION:
		# Return to appropriate state
		if can_see and distance <= PREPARE_RANGE:
			change_state(State.PREPARE)
		else:
			change_state(State.IDLE)

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
				if can_see_player and distance_to_player <= PREPARE_RANGE:
					change_state(State.PREPARE)
				else:
					change_state(State.IDLE)
			else:
				change_state(State.IDLE)
	
	desired_velocity = Vector2.ZERO
	# Reset scale
	animated_sprite.scale = original_scale

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
	
	if current_state == State.PREPARE:
		# Keep idle animation during prepare
		if animated_sprite.animation != "slime_idle":
			animated_sprite.play("slime_idle")
		return
	
	if current_state == State.LUNGE:
		# Play attack animation during lunge
		if animated_sprite.animation != "slime_attack":
			animated_sprite.play("slime_attack")
		return
	
	if current_state == State.RECOVERY:
		# Play idle during recovery
		if animated_sprite.animation != "slime_idle":
			animated_sprite.play("slime_idle")
		return

	# IDLE state: Check if moving (velocity length > small threshold)
	if velocity.length() > 0.1:
		if animated_sprite.animation != "slime_walk":
			animated_sprite.play("slime_walk")
		# Play footstep sound when moving (with cooldown to avoid spam)
		if sfx_footstep and not sfx_footstep.playing:
			# Only play footstep sound occasionally while moving
			if randf() < 0.15:  # 15% chance per frame when moving (slime is squishier)
				sfx_footstep.play()
	else:
		if animated_sprite.animation != "slime_idle":
			animated_sprite.play("slime_idle")

func _on_frame_changed() -> void:
	# Track death animation completion
	if is_dying and animated_sprite.animation == "slime_die" and not death_animation_complete:
		if animated_sprite.sprite_frames:
			var frame_count = animated_sprite.sprite_frames.get_frame_count("slime_die")
			# Check if we're on the last frame (frame_count - 1)
			# When we reach the last frame, mark as complete and queue_free on next frame
			if animated_sprite.frame >= frame_count - 1:
				death_animation_complete = true
				# Use call_deferred to remove on next frame
				call_deferred("queue_free")
				return
	
	# Task 2 Alternative: Frame-based damage for AnimatedSprite2D
	# Deal damage on specific attack frame (frame 3 of slime_attack animation)
	if current_state == State.LUNGE and animated_sprite.animation == "slime_attack":
		if animated_sprite.frame == 3:  # Adjust this frame number to match your animation
			deal_damage()

func _on_animated_sprite_2d_animation_finished() -> void:
	# Check if death animation finished (if loop was disabled)
	if is_dying and animated_sprite.animation == "slime_die":
		# Actually remove the slime now
		queue_free()
		return
	
	# After damaged animation, wait for stun to finish (handled in _physics_process)
	if animated_sprite.animation == "slime_damaged":
		is_playing_damaged = false
		# Reset animation speed to normal
		animated_sprite.speed_scale = 1.0
		# State will be changed from HURT to IDLE/CHASE after stun timer expires
		return
	
	# Animation finished handlers for specific states
	if current_state == State.LUNGE:
		# Lunge animation finished, go to recovery
		change_state(State.RECOVERY)

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
	if sfx_get_damaged:
		sfx_get_damaged.play()
	
	# Trigger screen shake
	_trigger_screen_shake(5.0, 0.2)
	
	# Spawn damage indicator
	_spawn_damage_indicator(amount)
	
	# Slime takes full damage (no reduction like skeleton)
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
		# Reset scale if preparing
		if current_state == State.PREPARE:
			animated_sprite.scale = original_scale
		
		# Trigger stun state (HURT takes priority)
		is_stunned = true
		stun_timer = hit_stun_duration
		change_state(State.HURT)
		
		# Play damaged animation immediately (interrupts any current animation)
		if not is_playing_damaged:
			is_playing_damaged = true
			# Ensure animation doesn't loop
			if animated_sprite.sprite_frames:
				animated_sprite.sprite_frames.set_animation_loop("slime_damaged", false)
			# Speed up animation to match short stun duration
			animated_sprite.speed_scale = 2.0  # Play animation 2x faster
			animated_sprite.play("slime_damaged")
		
		print("Slime took ", amount, " damage. Health: ", current_health, "/", max_health, " [STUNNED]")

func _trigger_screen_shake(intensity: float, duration: float) -> void:
	"""Trigger screen shake effect on the camera"""
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(intensity, duration)

func die() -> void:
	if is_dying:
		return  # Already dying, don't call again
	
	is_dying = true
	print("Slime died! Playing death animation...")
	
	# Give player EXP (less than skeleton, let's say 80-120)
	if player and player.has_method("gain_xp"):
		var exp_amount = randi_range(80, 120)
		player.gain_xp(exp_amount)
		print("Slime gave player ", exp_amount, " XP")
	
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
	
	var hurtbox_area = get_node_or_null("hurtbox/hurtbox")
	if hurtbox_area:
		hurtbox_area.set_deferred("monitoring", false)
		hurtbox_area.set_deferred("monitorable", false)
	
	# Disable looping for death animation so it only plays once
	if animated_sprite.sprite_frames:
		animated_sprite.sprite_frames.set_animation_loop("slime_die", false)
	
	# Reset completion flag
	death_animation_complete = false
	
	# Play death animation
	animated_sprite.play("slime_die")

func start_grace_period() -> void:
	"""Start the grace period where enemy ignores player unless attacked"""
	can_attack_player = false
	if grace_period_timer:
		grace_period_timer.start()
		print("Slime: Grace period started (4 seconds)")

func _on_grace_period_timeout() -> void:
	"""Grace period ended, enemy can now attack player"""
	can_attack_player = true
	print("Slime: Grace period ended, can now attack player")

func _spawn_damage_indicator(amount: int) -> void:
	"""Spawn a floating damage number indicator"""
	var indicator = DamageIndicator.instantiate()
	if indicator:
		# Set position - use DamageSpawnPoint if it exists, otherwise use a position above the slime
		var spawn_position: Vector2
		if damage_spawn_point:
			spawn_position = damage_spawn_point.global_position
		else:
			# Fallback: spawn above the slime (offset by sprite height)
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
	# After 0.1 seconds, the modulate will be white (normal, no tint)

func deal_damage() -> void:
	"""Task 2: Deal damage to player when called from animation frame"""
	# This function will be called from AnimationPlayer's Call Method Track
	# Check if player is in range and can be hit
	if not player:
		return
	
	if current_state != State.LUNGE:
		return  # Only deal damage during lunge attack
	
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player <= LUNGE_RANGE * 1.5:  # Slightly extended range for lunge
		# Deal damage to player
		if player.has_method("take_damage"):
			player.take_damage(SLIME_DAMAGE)
