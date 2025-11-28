extends CharacterBody2D

const DamageIndicator = preload("res://scene/DamageIndicator.tscn")

# Signal for health changes (for UI updates)
signal health_changed(current_hp: int, max_hp: int)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox_area: Area2D = get_node_or_null("hitbox/hitbox")
@onready var hitbox_host: Node2D = get_node_or_null("hitbox")
@onready var damage_spawn_point: Marker2D = get_node_or_null("DamageSpawnPoint")

# Boss Stats
var max_hp: int = 500
var current_hp: int = 500
const SPEED: float = 50.0  # Slow walk speed
const CHARGE_SPEED: float = 180.0  # Fast charge speed (Phase 2)
var is_enraged: bool = false
const ATTACK_RANGE: float = 60.0
const DETECTION_RANGE: float = 250.0
const CHARGE_DISTANCE_THRESHOLD: float = 150.0  # Distance to trigger charge when enraged
const CHARGE_CHANCE: float = 0.3  # 30% chance to charge when conditions met

# Attack System
var can_attack: bool = true
const ATTACK_COOLDOWN: float = 2.0
var attack_timer: float = 0.0
var attack_windup_timer: float = 0.0
const ATTACK_WINDUP: float = 0.6  # Wind-up time before hitbox activates
const ATTACK_ACTIVE_DURATION: float = 0.2  # How long hitbox stays active
var attack_active_timer: float = 0.0
const MINOTAUR_DAMAGE: int = 8  # Boss damage to player

# Charge System
var charge_timer: float = 0.0
const CHARGE_DURATION: float = 1.5  # How long charge lasts
var charge_direction: Vector2 = Vector2.ZERO
var is_charging: bool = false

# State Machine
enum State {IDLE, NOTICE, CHASE, ATTACK, CHARGE, DEATH}
var current_state: State = State.IDLE
var desired_velocity: Vector2 = Vector2.ZERO
@export var friction: float = 10.0  # Velocity smoothing

# Reaction Time
var reaction_timer: float = 0.0
const REACTION_TIME: float = 1.0  # Time to notice player before chasing

# Player Reference
var player: CharacterBody2D = null

# Raycast for line of sight
var raycast: RayCast2D

# Death flag
var is_dying: bool = false

# Screen shake reference
var camera: Camera2D = null

func _ready() -> void:
	# Get player from GameManager
	if GameManager.player_ref:
		player = GameManager.player_ref
	else:
		# Fallback: try to find player in scene
		player = get_tree().get_first_node_in_group("player")
		if not player:
			var game_root = get_tree().current_scene
			if game_root:
				player = game_root.get_node_or_null("Player")
	
	# Add raycast for line of sight
	raycast = RayCast2D.new()
	raycast.collide_with_bodies = true
	raycast.collision_mask = 1  # World layer
	add_child(raycast)
	
	# Connect animation signals
	animated_sprite.animation_finished.connect(_on_animation_finished)
	
	# Initialize health
	current_hp = max_hp
	
	# Set collision mask to ignore player (layer 4), only collide with walls (layer 1)
	set_collision_mask_value(1, true)   # Collide with walls
	set_collision_mask_value(4, false)  # Don't collide with player
	
	# Disable hitbox by default (controlled by hitbox_host script)
	if hitbox_area:
		hitbox_area.monitoring = false
		hitbox_area.monitorable = false
	if hitbox_host and hitbox_host.has_method("_ready"):
		# Hitbox will be disabled by its own script
		pass
	
	# Get camera for screen shake
	camera = get_viewport().get_camera_2d()
	
	print("Minotaur Boss initialized - HP: ", current_hp, "/", max_hp)

func _physics_process(delta: float) -> void:
	# Skip normal behavior if dying
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	if not player:
		# Try to get player from GameManager again
		if GameManager.player_ref:
			player = GameManager.player_ref
		else:
			return
	
	# Update attack cooldown
	if not can_attack:
		attack_timer += delta
		if attack_timer >= ATTACK_COOLDOWN:
			can_attack = true
			attack_timer = 0.0
	
	# Handle attack timing (wind-up and active duration)
	if current_state == State.ATTACK:
		attack_windup_timer += delta
		
		# After wind-up, enable hitbox
		if attack_windup_timer >= ATTACK_WINDUP and attack_active_timer == 0.0:
			attack_active_timer = 0.001  # Start active timer
			if hitbox_area:
				hitbox_area.monitoring = true
				hitbox_area.monitorable = true
				print("Minotaur: Hitbox activated!")
		
		# After active duration, disable hitbox
		if attack_active_timer > 0.0:
			attack_active_timer += delta
			if attack_active_timer >= ATTACK_ACTIVE_DURATION:
				attack_active_timer = 0.0
				if hitbox_area:
					hitbox_area.monitoring = false
					hitbox_area.monitorable = false
					print("Minotaur: Hitbox deactivated!")
	
	# Handle charge timer
	if current_state == State.CHARGE:
		charge_timer += delta
		if charge_timer >= CHARGE_DURATION:
			# Charge finished, return to chase
			charge_timer = 0.0
			is_charging = false
			change_state(State.CHASE)
	
	var distance_to_player = global_position.distance_to(player.global_position)
	var can_see_player = check_line_of_sight()
	
	# State machine
	match current_state:
		State.IDLE:
			handle_idle(delta, distance_to_player, can_see_player)
		State.NOTICE:
			handle_notice(delta, distance_to_player, can_see_player)
		State.CHASE:
			handle_chase(delta, distance_to_player, can_see_player)
		State.ATTACK:
			handle_attack(delta)
		State.CHARGE:
			handle_charge(delta, distance_to_player)
		State.DEATH:
			handle_death(delta)
	
	# Smooth velocity changes
	if delta > 0:
		var lerp_factor = clamp(friction * delta, 0.0, 1.0)
		velocity = velocity.lerp(desired_velocity, lerp_factor)
	else:
		velocity = desired_velocity
	
	# Handle sprite flipping
	if velocity.x < 0:
		animated_sprite.flip_h = true
	elif velocity.x > 0:
		animated_sprite.flip_h = false
	
	# Update animation
	update_animation()
	
	# Move and handle collisions
	move_and_slide()
	
	# Check for wall collision during charge
	if current_state == State.CHARGE and is_charging:
		if is_on_wall():
			# Hit a wall, stop charge and shake screen
			is_charging = false
			charge_timer = 0.0
			_trigger_screen_shake(10.0, 0.3)
			change_state(State.CHASE)
			print("Minotaur: Charge stopped by wall!")

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
			desired_velocity = Vector2.ZERO
			reaction_timer = 0.0
		State.CHASE:
			desired_velocity = Vector2.ZERO
		State.ATTACK:
			desired_velocity = Vector2.ZERO
			attack_windup_timer = 0.0
			attack_active_timer = 0.0
			# Ensure hitbox is disabled at start
			if hitbox_area:
				hitbox_area.monitoring = false
				hitbox_area.monitorable = false
		State.CHARGE:
			if player:
				charge_direction = (player.global_position - global_position).normalized()
			is_charging = true
			charge_timer = 0.0
		State.DEATH:
			desired_velocity = Vector2.ZERO
			velocity = Vector2.ZERO

func handle_idle(_delta: float, distance: float, can_see: bool) -> void:
	"""IDLE: Wait for player to be valid and enter detection range"""
	desired_velocity = Vector2.ZERO
	
	if can_see and distance <= DETECTION_RANGE:
		change_state(State.NOTICE)

func handle_notice(delta: float, distance: float, can_see: bool) -> void:
	"""NOTICE: Stop and look at player for reaction time"""
	desired_velocity = Vector2.ZERO
	
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
	
	# If reaction time passed, start chasing
	if reaction_timer >= REACTION_TIME:
		change_state(State.CHASE)

func handle_chase(delta: float, distance: float, can_see: bool) -> void:
	"""CHASE: Walk towards player"""
	if not can_see:
		change_state(State.IDLE)
		return
	
	# Move towards player
	var direction = (player.global_position - global_position).normalized()
	var move_speed = CHARGE_SPEED if is_enraged else SPEED
	desired_velocity = direction * move_speed
	
	# Check for attack
	if distance <= ATTACK_RANGE and can_attack:
		change_state(State.ATTACK)
		return
	
	# Check for charge (only when enraged and player is far)
	if is_enraged and distance > CHARGE_DISTANCE_THRESHOLD:
		if randf() < CHARGE_CHANCE:
			change_state(State.CHARGE)
			return

func handle_attack(_delta: float) -> void:
	"""ATTACK: Melee attack with wind-up"""
	desired_velocity = Vector2.ZERO
	
	# Attack timing is handled in _physics_process
	# Wait for animation to finish to exit state

func handle_charge(delta: float, distance: float) -> void:
	"""CHARGE: Sprint at player at high speed"""
	if not is_charging:
		return
	
	# Move in locked direction at charge speed
	desired_velocity = charge_direction * CHARGE_SPEED
	
	# Check if we hit the player (close enough)
	if distance <= ATTACK_RANGE:
		# Hit player, stop charge and shake screen
		is_charging = false
		charge_timer = 0.0
		_trigger_screen_shake(10.0, 0.3)
		change_state(State.CHASE)
		print("Minotaur: Charge hit player!")

func handle_death(_delta: float) -> void:
	"""DEATH: Wait for death animation to finish"""
	desired_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	# Death is handled by animation_finished signal

func update_animation() -> void:
	if is_dying:
		return
	
	match current_state:
		State.IDLE:
			if animated_sprite.animation != "idle_animation":
				animated_sprite.play("idle_animation")
		State.NOTICE:
			if animated_sprite.animation != "idle_animation":
				animated_sprite.play("idle_animation")
		State.CHASE:
			if animated_sprite.animation != "walk_animation":
				animated_sprite.play("walk_animation")
		State.ATTACK:
			if animated_sprite.animation != "attack_animation":
				animated_sprite.play("attack_animation")
		State.CHARGE:
			if animated_sprite.animation != "walk_animation":
				animated_sprite.play("walk_animation")
		State.DEATH:
			if animated_sprite.animation != "death_animation":
				animated_sprite.play("death_animation")

func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	"""Super Armor: Take damage but no knockback, flash red"""
	if is_dying:
		return
	
	# Reduce HP
	current_hp -= amount
	if current_hp < 0:
		current_hp = 0
	
	# Emit health_changed signal for UI updates
	health_changed.emit(current_hp, max_hp)
	
	print("Minotaur took ", amount, " damage. HP: ", current_hp, "/", max_hp)
	
	# Spawn damage indicator
	_spawn_damage_indicator(amount)
	
	# Flash Red (Super Armor visual feedback)
	_trigger_red_flash()
	
	# Check for phase change (ENRAGE)
	if current_hp <= 250 and not is_enraged:
		enrage()
	
	# Handle death
	if current_hp <= 0:
		die()
	else:
		# If in NOTICE state and taking damage, immediately chase
		if current_state == State.NOTICE:
			change_state(State.CHASE)

func enrage() -> void:
	"""Phase 2: Turn red, increase speed"""
	if is_enraged:
		return
	
	is_enraged = true
	print("Minotaur ENRAGED! Phase 2 activated!")
	
	# Visual: Turn sprite red
	var tween = create_tween()
	tween.tween_property(animated_sprite, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.5)
	
	# Screen shake for phase change
	_trigger_screen_shake(15.0, 0.5)
	
	# Speed increase is handled in handle_chase (uses CHARGE_SPEED when enraged)

func _trigger_red_flash() -> void:
	"""Flash red for Super Armor visual feedback"""
	# Set to red
	animated_sprite.modulate = Color(1.0, 0.2, 0.2, 1.0)
	
	# Tween back to white (or enraged red if enraged)
	var target_color = Color(1.0, 0.3, 0.3, 1.0) if is_enraged else Color.WHITE
	var tween = create_tween()
	tween.tween_property(animated_sprite, "modulate", target_color, 0.15)

func _trigger_screen_shake(intensity: float, duration: float) -> void:
	"""Trigger screen shake effect on the camera"""
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(intensity, duration)

func _spawn_damage_indicator(amount: int) -> void:
	"""Spawn a floating damage number indicator"""
	var indicator = DamageIndicator.instantiate()
	if indicator:
		# Use DamageSpawnPoint if it exists, otherwise default to global_position
		var spawn_position: Vector2
		if damage_spawn_point:
			spawn_position = damage_spawn_point.global_position
		else:
			spawn_position = global_position
		
		# Add random offset to prevent overlapping
		spawn_position += Vector2(randf_range(-10, 10), randf_range(-10, 10))
		
		indicator.global_position = spawn_position
		indicator.set_amount(amount)
		
		# Add to current scene so it doesn't move with the enemy
		var current_scene = get_tree().current_scene
		if current_scene:
			current_scene.add_child(indicator)

func die() -> void:
	"""Death sequence"""
	if is_dying:
		return
	
	is_dying = true
	print("Minotaur Boss defeated!")
	
	# Stop all movement
	velocity = Vector2.ZERO
	desired_velocity = Vector2.ZERO
	
	# Disable collision and monitoring
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Disable hitbox
	if hitbox_area:
		hitbox_area.set_deferred("monitoring", false)
		hitbox_area.set_deferred("monitorable", false)
	
	# Give player EXP (boss reward)
	if player and player.has_method("gain_xp"):
		var exp_amount = randi_range(500, 750)
		player.gain_xp(exp_amount)
		print("Minotaur gave player ", exp_amount, " XP")
	
	# Notify GameManager that boss is defeated
	if GameManager:
		GameManager.boss_defeated()
	
	# Change to death state
	change_state(State.DEATH)
	
	# Play death animation
	if animated_sprite.sprite_frames:
		animated_sprite.sprite_frames.set_animation_loop("death_animation", false)
	animated_sprite.play("death_animation")

func _on_animation_finished() -> void:
	"""Handle animation completion"""
	if is_dying and animated_sprite.animation == "death_animation":
		# Death animation finished, remove boss
		queue_free()
		return
	
	# After attack animation, return to chase/idle
	if current_state == State.ATTACK and animated_sprite.animation == "attack_animation":
		# Start attack cooldown
		can_attack = false
		attack_timer = 0.0
		
		# Ensure hitbox is disabled
		if hitbox_area:
			hitbox_area.monitoring = false
			hitbox_area.monitorable = false
		
		# Return to appropriate state
		if player:
			var distance = global_position.distance_to(player.global_position)
			var can_see = check_line_of_sight()
			if can_see and distance <= DETECTION_RANGE:
				change_state(State.CHASE)
			else:
				change_state(State.IDLE)

