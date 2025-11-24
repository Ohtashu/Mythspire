extends CharacterBody2D

const DamageIndicator = preload("res://scene/DamageIndicator.tscn")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var sfx_get_hit: AudioStreamPlayer2D = $sfx_get_hit
@onready var sfx_shield_hit: AudioStreamPlayer2D = $sfx_shield_hit
@onready var sfx_footstep: AudioStreamPlayer2D = get_node_or_null("skeleton_walk")
@onready var sfx_growl: AudioStreamPlayer2D = get_node_or_null("skeleton_growl")
@onready var damage_spawn_point: Marker2D = get_node_or_null("DamageSpawnPoint")

enum State {IDLE, CHASE, BLOCK, ATTACK, HURT}

var player: CharacterBody2D
var raycast: RayCast2D
const SPEED = 25.0  # Slow, steady walk
const DETECTION_RANGE = 150.0
const ATTACK_RANGE = 30.0
const BLOCK_CHANCE = 0.4  # 40% chance to block
const BLOCK_DURATION_MIN = 1.0  # Minimum block duration
const BLOCK_DURATION_MAX = 2.0  # Maximum block duration
const SEPARATION_FORCE = 50.0  # Force to push enemies apart
const SEPARATION_DISTANCE = 30.0  # Distance to start separating
@export var friction: float = 10.0  # Velocity smoothing factor (higher = smoother, use with delta)

var current_state = State.IDLE
var desired_velocity: Vector2 = Vector2.ZERO  # Target velocity for smoothing
var block_timer: float = 0.0
var block_duration: float = 0.0
var should_counter_attack: bool = false  # Flag for counter-attack after shield hit
var is_knockback: bool = false
var knockback_timer: float = 0.0
const KNOCKBACK_FORCE = 120.0
const KNOCKBACK_DURATION = 0.2
var is_defending: bool = false
var shield_hit_count: int = 0
var defend_timer: float = 0.0
var is_dying: bool = false  # Flag to prevent normal behavior during death animation
var death_animation_complete: bool = false  # Flag to track if death animation completed
var is_playing_damaged: bool = false  # Flag to track if damaged animation is playing
var is_stunned: bool = false  # Flag to track if skeleton is stunned
var stun_timer: float = 0.0  # Timer for stun duration
@export var hit_stun_duration: float = 0.15  # Duration of stun in seconds (0.15s = 150ms micro-stun)
var growl_timer: float = 0.0
const GROWL_INTERVAL: float = 10.0  # Play growl every 10 seconds

# Grace period system
var can_attack_player: bool = false  # Can only attack player after grace period or if attacked
var grace_period_timer: Timer
const GRACE_PERIOD_DURATION: float = 4.0  # 4 seconds grace period

# Health system
var max_health: int = 25  # Reduced from 50 (was too high)
var current_health: int = 25
const SKELETON_DAMAGE = 5  # Damage skeleton deals to player (reduced for level 1 balance)
const SKELETON_DAMAGE_DEFENDING = 2  # Reduced damage when skeleton is defending

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

	# Play growl sound every 10 seconds
	if sfx_growl:
		growl_timer += delta
		if growl_timer >= GROWL_INTERVAL:
			growl_timer = 0.0
			if not sfx_growl.playing:
				sfx_growl.play()

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
	
	# Check if player is attacking (for block decision)
	var player_is_attacking = false
	if player and "is_attacking" in player:
		player_is_attacking = player.is_attacking
	
	# State machine (only if not stunned/HURT)
	match current_state:
		State.IDLE:
			handle_idle(delta, distance_to_player, can_see_player, player_is_attacking)
		State.CHASE:
			handle_chase(delta, distance_to_player, can_see_player, player_is_attacking)
		State.BLOCK:
			handle_block(delta, distance_to_player, can_see_player)
		State.ATTACK:
			handle_attack(delta, distance_to_player)
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

	# Bug 1 Fix: Ensure velocity is zero during ATTACK, BLOCK, and HURT states
	if current_state == State.ATTACK or current_state == State.BLOCK or current_state == State.HURT:
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
	
	# Fix: Prevent skeleton from being dragged by player when too close
	# Check if we collided with something and are very close to player
	if player and was_colliding:
		var dist_to_player = global_position.distance_to(player.global_position)
		if dist_to_player < 20.0:  # Very close to player
			# Check if we're being pushed by checking collision
			for i in range(get_slide_collision_count()):
				var collision = get_slide_collision(i)
				var collider = collision.get_collider()
				# If we collided with the player, prevent being pushed
				if collider == player or collider.is_in_group("player"):
					# Reset position to prevent being dragged
					# Only do this if we're not in attack state (allow attacks to work)
					if current_state != State.ATTACK:
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
		State.CHASE:
			pass  # Will be set in handle_chase
		State.BLOCK:
			desired_velocity = Vector2.ZERO
			is_defending = true
			block_duration = randf_range(BLOCK_DURATION_MIN, BLOCK_DURATION_MAX)
			block_timer = 0.0
		State.ATTACK:
			desired_velocity = Vector2.ZERO
			is_defending = false  # Stop defending when attacking
		State.HURT:
			desired_velocity = Vector2.ZERO  # Stop all movement during hurt state
			is_defending = false

func apply_separation_force() -> void:
	"""Apply separation force to prevent enemies from stacking"""
	if current_state == State.HURT or current_state == State.BLOCK:
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

func handle_idle(_delta: float, distance: float, can_see: bool, _player_attacking: bool) -> void:
	"""IDLE: Stand still, transition to CHASE if player detected"""
	if not can_attack_player:
		desired_velocity = Vector2.ZERO
		return
	
	desired_velocity = Vector2.ZERO
	
	# Transition to CHASE if player is detected
	if can_see and distance <= DETECTION_RANGE:
		change_state(State.CHASE)

func handle_chase(_delta: float, distance: float, can_see: bool, player_attacking: bool) -> void:
	"""CHASE: Slow walk toward player, may block if player attacks"""
	if not can_attack_player:
		desired_velocity = Vector2.ZERO
		return
	
	if not can_see:
		change_state(State.IDLE)
		return
	
	# Check if should block (40% chance if player is attacking or looking at skeleton)
	if player_attacking and randf() < BLOCK_CHANCE:
		change_state(State.BLOCK)
		return
	
	# Walk slowly toward player
	var direction = (player.global_position - global_position).normalized()
	desired_velocity = direction * SPEED
	
	# Transition to ATTACK if close enough
	if distance <= ATTACK_RANGE:
		change_state(State.ATTACK)

func handle_block(delta: float, distance: float, can_see: bool) -> void:
	"""BLOCK: Raise shield, no movement, 80% damage reduction"""
	block_timer += delta
	desired_velocity = Vector2.ZERO  # No movement while blocking
	
	# After block duration, transition to attack
	if block_timer >= block_duration:
		if distance <= ATTACK_RANGE and can_see:
			change_state(State.ATTACK)
		else:
			change_state(State.CHASE)
	
	# If counter-attack flag is set (from shield hit), attack immediately
	if should_counter_attack:
		should_counter_attack = false
		if distance <= ATTACK_RANGE * 1.5:  # Slightly extended range for counter
			change_state(State.ATTACK)

func handle_attack(_delta: float, distance: float) -> void:
	"""ATTACK: Standard swing"""
	if distance <= ATTACK_RANGE:
		attack()
	elif distance > ATTACK_RANGE * 1.5:  # Give buffer before switching back
		change_state(State.CHASE)

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
				if can_see_player and distance_to_player <= ATTACK_RANGE:
					change_state(State.ATTACK)
				elif can_see_player and distance_to_player <= DETECTION_RANGE:
					change_state(State.CHASE)
				else:
					change_state(State.IDLE)
			else:
				change_state(State.IDLE)
	
	desired_velocity = Vector2.ZERO
	is_defending = false

func attack() -> void:
	current_state = State.ATTACK
	animated_sprite.play("skeleton_attack")
	velocity = Vector2.ZERO


func take_knockback(direction: Vector2) -> void:
	if is_defending or current_state == State.BLOCK:
		if sfx_shield_hit:
			sfx_shield_hit.play()
		# Push player back
		if player and player.has_method("take_knockback"):
			player.take_knockback(-direction)
		# Set counter-attack flag
		should_counter_attack = true
		return  # No knockback when defending

	if sfx_get_hit:
		sfx_get_hit.play()
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
	
	if current_state == State.ATTACK:
		return  # Let attack animation finish
	
	if current_state == State.HURT:
		return  # Let hurt animation play

	if is_defending or current_state == State.BLOCK:
		animated_sprite.play("skeleton_defend")
		return

	# Check if moving (use small threshold to avoid floating point issues)
	if velocity.length() > 0.1:
		# Only change to move animation if not already playing it
		if animated_sprite.animation != "skeleton_move":
			animated_sprite.play("skeleton_move")
		# Play footstep sound when moving (with cooldown to avoid spam)
		if sfx_footstep and not sfx_footstep.playing:
			# Only play footstep sound occasionally while moving
			if randf() < 0.1:  # 10% chance per frame when moving
				sfx_footstep.play()
	else:
		# Only change to idle animation if not already playing it
		if animated_sprite.animation != "skeleton_idle":
			animated_sprite.play("skeleton_idle")

func _on_frame_changed() -> void:
	# Track death animation completion
	if is_dying and animated_sprite.animation == "skeleton_death" and not death_animation_complete:
		if animated_sprite.sprite_frames:
			var frame_count = animated_sprite.sprite_frames.get_frame_count("skeleton_death")
			# Check if we're on the last frame (frame_count - 1)
			# When we reach the last frame, mark as complete and queue_free on next frame
			if animated_sprite.frame >= frame_count - 1:
				death_animation_complete = true
				# Use call_deferred to remove on next frame
				call_deferred("queue_free")
				return
	
	# Task 2 Alternative: Frame-based damage for AnimatedSprite2D
	# Deal damage on specific attack frame (frame 3 of skeleton_attack animation)
	if current_state == State.ATTACK and animated_sprite.animation == "skeleton_attack":
		if animated_sprite.frame == 3:  # Adjust this frame number to match your animation
			deal_damage()

func _on_animated_sprite_2d_animation_finished() -> void:
	# Check if death animation finished (if loop was disabled)
	if is_dying and animated_sprite.animation == "skeleton_death":
		# Actually remove the skeleton now
		queue_free()
		return
	
	# After damaged animation, wait for stun to finish (handled in _physics_process)
	if animated_sprite.animation == "skeleton_damaged":
		is_playing_damaged = false
		# Reset animation speed to normal
		animated_sprite.speed_scale = 1.0
		# State will be changed from HURT to IDLE/CHASE after stun timer expires
		return
	
	if current_state == State.ATTACK:
		# After attack, transition back to appropriate state based on player position
		if player:
			var distance_to_player = global_position.distance_to(player.global_position)
			var can_see_player = check_line_of_sight()
			if distance_to_player <= DETECTION_RANGE and can_see_player:
				change_state(State.CHASE)
			else:
				change_state(State.IDLE)
		else:
			change_state(State.IDLE)
	if is_defending:
		is_defending = false
		shield_hit_count = 0

func take_damage(amount: int) -> void:
	# Don't take damage if already dying
	if is_dying:
		return
	
	# Cancel grace period if enemy takes damage (player attacked first)
	if not can_attack_player:
		can_attack_player = true
		if grace_period_timer:
			grace_period_timer.stop()
	
	# Play audio based on defense state
	if is_defending:
		# Play shield hit sound when blocking
		if sfx_shield_hit:
			sfx_shield_hit.play()
	else:
		# Play regular hit sound
		if sfx_get_hit:
			sfx_get_hit.play()
	
	# Trigger screen shake
	_trigger_screen_shake(5.0, 0.2)
	
	# Reduce damage taken more when defending (but still take some damage)
	var damage_reduction = 0.5  # Base 50% reduction
	if is_defending:
		damage_reduction = 0.8  # 80% reduction when defending (take only 20% damage)
	
	var reduced_damage = int(amount * (1.0 - damage_reduction))
	if reduced_damage < 1:
		reduced_damage = 1  # Always take at least 1 damage
	
	# Spawn damage indicator (show reduced damage)
	_spawn_damage_indicator(reduced_damage)
	
	current_health -= reduced_damage
	if current_health < 0:
		current_health = 0
	# Handle death
	if current_health <= 0:
		die()
	else:
		# SKELETON EXCEPTION: If defending/BLOCKING, don't interrupt or stun
		if is_defending or current_state == State.BLOCK:
			var status = " (defending)"
			print("Skeleton took ", reduced_damage, " damage (reduced from ", amount, status, "). Health: ", current_health, "/", max_health)
			return  # Exit early - no stun or animation interrupt when defending
		
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
				animated_sprite.sprite_frames.set_animation_loop("skeleton_damaged", false)
			# Speed up animation to match short stun duration
			animated_sprite.speed_scale = 2.0  # Play animation 2x faster
			animated_sprite.play("skeleton_damaged")
		
		print("Skeleton took ", reduced_damage, " damage (reduced from ", amount, "). Health: ", current_health, "/", max_health, " [STUNNED]")

func die() -> void:
	if is_dying:
		return  # Already dying, don't call again
	
	is_dying = true
	print("Skeleton died! Playing death animation...")
	
	# Give player EXP (150-200)
	if player and player.has_method("gain_xp"):
		var exp_amount = randi_range(150, 200)
		player.gain_xp(exp_amount)
		print("Skeleton gave player ", exp_amount, " XP")
	
	# Stop all movement and state changes
	velocity = Vector2.ZERO
	current_state = State.IDLE
	
	# Disable collision and monitoring
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Disable hitbox and hurtbox
	var hitbox_area = get_node_or_null("skeleton_hitbox/hitbox")
	if hitbox_area:
		hitbox_area.set_deferred("monitoring", false)
		hitbox_area.set_deferred("monitorable", false)
	
	var hurtbox_area = get_node_or_null("skeleton_hurtbox/hurtbox")
	if hurtbox_area:
		hurtbox_area.set_deferred("monitoring", false)
		hurtbox_area.set_deferred("monitorable", false)
	
	# Disable looping for death animation so it only plays once
	if animated_sprite.sprite_frames:
		animated_sprite.sprite_frames.set_animation_loop("skeleton_death", false)
	
	# Reset completion flag
	death_animation_complete = false
	
	# Play death animation
	animated_sprite.play("skeleton_death")

func start_grace_period() -> void:
	"""Start the grace period where enemy ignores player unless attacked"""
	can_attack_player = false
	if grace_period_timer:
		grace_period_timer.start()
		print("Skeleton: Grace period started (4 seconds)")

func _on_grace_period_timeout() -> void:
	"""Grace period ended, enemy can now attack player"""
	can_attack_player = true
	print("Skeleton: Grace period ended, can now attack player")

func _trigger_screen_shake(intensity: float, duration: float) -> void:
	"""Trigger screen shake effect on the camera"""
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(intensity, duration)

func _spawn_damage_indicator(amount: int) -> void:
	"""Spawn a floating damage number indicator"""
	var indicator = DamageIndicator.instantiate()
	if indicator:
		# Set position - use DamageSpawnPoint if it exists, otherwise use a position above the skeleton
		var spawn_position: Vector2
		if damage_spawn_point:
			spawn_position = damage_spawn_point.global_position
		else:
			# Fallback: spawn above the skeleton (offset by sprite height)
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
	
	if current_state != State.ATTACK:
		return  # Only deal damage during attack
	
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player <= ATTACK_RANGE * 1.2:  # Slightly extended range
		# Deal damage to player
		if player.has_method("take_damage"):
			player.take_damage(SKELETON_DAMAGE)
