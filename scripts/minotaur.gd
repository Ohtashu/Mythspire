extends CharacterBody2D

const DamageIndicator = preload("res://scene/DamageIndicator.tscn")

# Signals
signal health_changed(current_hp: int, max_hp: int)

# Node references
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_spawn_point: Marker2D = get_node_or_null("DamageSpawnPoint")
@onready var hurtbox: Area2D = get_node_or_null("hurtbox")
@onready var hitbox: Area2D = get_node_or_null("hitbox")
@onready var slash_sound: AudioStreamPlayer2D = get_node_or_null("slash")
@onready var stomp_sound: AudioStreamPlayer2D = get_node_or_null("stomp")
@onready var roar_sound: AudioStreamPlayer2D = get_node_or_null("roar")

# State Machine
enum State { IDLE, CHASE, ATTACK_AXE, ATTACK_STOMP, DAMAGED, RAGE_MODE, DEAD }
var current_state: State = State.IDLE
var previous_state: State = State.IDLE

# Boss Stats
var max_hp: int = 500
var current_hp: int = 500
const BASE_SPEED: float = 40.0
const RAGE_SPEED: float = 70.0
var current_speed: float = BASE_SPEED
const MINOTAUR_DAMAGE: int = 8

# Combat Ranges (optimized)
const AGGRO_RANGE: float = 200.0  # Reduced from 250 - more focused aggro
const CLOSE_RANGE: float = 55.0  # Slightly reduced for tighter axe attacks
const MEDIUM_RANGE: float = 100.0  # Reduced from 120 - more precise stomp range

# Attack System (optimized)
var can_attack: bool = true
var attack_cooldown_timer: float = 0.0
const NORMAL_ATTACK_COOLDOWN: float = 1.2  # Reduced from 1.5 - faster attacks
const RAGE_ATTACK_COOLDOWN: float = 0.8  # Reduced from 0.9 - more aggressive
var current_attack_cooldown: float = NORMAL_ATTACK_COOLDOWN

# Rage System
var is_enraged: bool = false
const RAGE_THRESHOLD: float = 0.4  # 40% HP

# Damage System
var is_damaged: bool = false
var damage_timer: float = 0.0
const DAMAGE_STUN_DURATION: float = 0.2
var damage_cooldown_timer: float = 0.0
const DAMAGE_COOLDOWN: float = 0.3  # Prevent taking damage multiple times from same attack
var last_damage_source: Node = null  # Track last damage source to prevent double hits

# Stomp Attack
const STOMP_RADIUS: float = 100.0
const STOMP_DAMAGE: int = 12

# Hitbox Frame Control (for axe attack)
const HITBOX_ACTIVE_FRAMES: Array = [2, 3, 4, 5]  # Frames where hitbox is active (expanded for reliability)
var last_attack_frame: int = -1
var has_hit_player_this_attack: bool = false  # Prevent multi-hit

# Animation Frame Offset Fix
# If the sprite moves out of center during attack_animation, set this to compensate
# The offset property adjusts where the sprite is drawn without changing its position
# Positive values move sprite right/down, negative values move left/up
@export var attack_offset_fix: Vector2 = Vector2(0, 0)  # Adjust in Inspector for attack_animation

# Roar System
var roar_timer: float = 0.0
const ROAR_INTERVAL_MIN: float = 5.0  # Minimum seconds between roars
const ROAR_INTERVAL_MAX: float = 6.0  # Maximum seconds between roars
var next_roar_time: float = 5.0

# Player & World
var player: CharacterBody2D = null
var raycast: RayCast2D = null
var camera: Camera2D = null
var is_dying: bool = false

# Movement
var desired_velocity: Vector2 = Vector2.ZERO
@export var friction: float = 10.0

func _ready() -> void:
	# Get player reference
	player = get_tree().get_first_node_in_group("player")
	if not player and GameManager.player_ref:
		player = GameManager.player_ref
	
	# Setup raycast for line of sight
	raycast = RayCast2D.new()
	raycast.collide_with_bodies = true
	raycast.collision_mask = 1  # World layer
	add_child(raycast)
	
	# Get camera for screen shake
	camera = get_viewport().get_camera_2d()
	
	# Connect signals
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.frame_changed.connect(_on_animated_sprite_frame_changed)
	
	# Y-sorting depth optimization: Enable Y-sorting for proper depth perception
	# This ensures the boss sorts correctly based on its Y position
	y_sort_enabled = true
	
	# Setup hurtbox (receives damage from player)
	if hurtbox:
		hurtbox.area_entered.connect(_on_hurtbox_area_entered)
		hurtbox.monitoring = true  # Always monitor for player attacks
		hurtbox.monitorable = true
		print("[MINOTAUR] Hurtbox setup - Layer: ", hurtbox.collision_layer, " | Mask: ", hurtbox.collision_mask)
	else:
		print("[MINOTAUR ERROR] Hurtbox not found!")
	
	# Setup hitbox (deals damage to player)
	if hitbox:
		hitbox.area_entered.connect(_on_hitbox_area_entered)
		hitbox.monitoring = false  # Start disabled, controlled by animation frames
		hitbox.monitorable = false
		print("[MINOTAUR] Hitbox setup - will be controlled by animation frames")
	else:
		print("[MINOTAUR ERROR] Hitbox not found!")
	
	# Setup collision
	set_collision_mask_value(1, true)   # Collide with walls
	set_collision_mask_value(4, false)  # Don't collide with player
	
	# Add to boss group
	add_to_group("boss")
	
	# Initialize
	current_hp = max_hp
	current_state = State.IDLE
	
	print("Minotaur Boss initialized - HP: ", max_hp, " | Player: ", player != null)

func _physics_process(delta: float) -> void:
	if is_dying:
		return
	
	# Update timers
	_update_timers(delta)
	
	# Debug: Print state and attack cooldown every 5 seconds (optimized - less spam)
	if Engine.get_physics_frames() % 300 == 0:  # Every 5 seconds at 60 FPS
		print("[MINOTAUR DEBUG] State: ", State.keys()[current_state], " | Can Attack: ", can_attack, " | HP: ", current_hp, "/", max_hp)
	
	# Get player info
	if not player:
		player = get_tree().get_first_node_in_group("player")
		if not player:
			velocity = Vector2.ZERO
			move_and_slide()
			return
	
	var distance = global_position.distance_to(player.global_position)
	var can_see = _check_line_of_sight()
	
	# State machine
	match current_state:
		State.IDLE:
			_handle_idle(delta, distance, can_see)
		State.CHASE:
			_handle_chase(delta, distance, can_see)
		State.ATTACK_AXE:
			_handle_attack_axe(delta)
		State.ATTACK_STOMP:
			_handle_attack_stomp(delta)
		State.DAMAGED:
			_handle_damaged(delta)
		State.RAGE_MODE:
			_handle_rage_mode(delta, distance, can_see)
		State.DEAD:
			_handle_dead(delta)
	
	# Bug Fix: Apply separation force to prevent stacking with other enemies
	_apply_separation_force()
	
	# Apply movement
	if delta > 0:
		var lerp_factor = clamp(friction * delta, 0.0, 1.0)
		velocity = velocity.lerp(desired_velocity, lerp_factor)
	
	# Flip sprite
	if velocity.x < 0:
		animated_sprite.flip_h = true
	elif velocity.x > 0:
		animated_sprite.flip_h = false
	
	# Update animation
	_update_animation()
	
	# Store collision count before moving
	var was_colliding = get_slide_collision_count() > 0
	
	# Move
	move_and_slide()
	
	# Bug Fix: Prevent minotaur from being dragged by player
	if player and was_colliding:
		var dist_to_player = global_position.distance_to(player.global_position)
		if dist_to_player < 30.0:  # Very close to player
			for i in range(get_slide_collision_count()):
				var collision = get_slide_collision(i)
				var collider = collision.get_collider()
				# If we collided with the player, prevent being pushed
				if collider == player or collider.is_in_group("player"):
					# Reset position to prevent being dragged
					# Only do this if we're not in attack state
					if current_state != State.ATTACK_AXE and current_state != State.ATTACK_STOMP:
						var push_back = (global_position - player.global_position).normalized() * 3.0
						global_position += push_back
					break

func _update_timers(delta: float) -> void:
	# Attack cooldown
	if not can_attack:
		attack_cooldown_timer += delta
		if attack_cooldown_timer >= current_attack_cooldown:
			can_attack = true
			attack_cooldown_timer = 0.0
			print("[MINOTAUR] Attack cooldown complete - ready to attack!")
	
	# Damage stun
	if is_damaged:
		damage_timer += delta
		if damage_timer >= DAMAGE_STUN_DURATION:
			is_damaged = false
			damage_timer = 0.0
			_change_state(previous_state)
	
	# Damage cooldown (prevent double damage from same attack)
	if damage_cooldown_timer > 0.0:
		damage_cooldown_timer -= delta
		if damage_cooldown_timer <= 0.0:
			damage_cooldown_timer = 0.0
			last_damage_source = null  # Reset after cooldown
	
	# Roar timer (periodic angry roar every 5-6 seconds when in combat)
	if current_state in [State.CHASE, State.RAGE_MODE, State.IDLE] and not is_dying:
		roar_timer += delta
		if roar_timer >= next_roar_time:
			if roar_sound and not roar_sound.playing:
				roar_sound.play()
				print("[MINOTAUR] ROAR! (angry)")
			roar_timer = 0.0
			# Randomize next roar time
			next_roar_time = randf_range(ROAR_INTERVAL_MIN, ROAR_INTERVAL_MAX)

# Separation constants
const SEPARATION_FORCE: float = 80.0  # Force to push enemies apart
const SEPARATION_DISTANCE: float = 50.0  # Distance to start separating

func _apply_separation_force() -> void:
	"""Apply separation force to prevent minotaur from stacking with other enemies"""
	if current_state == State.DAMAGED or current_state == State.DEAD:
		return  # Don't separate during these states
	
	var separation = Vector2.ZERO
	
	# Get all enemies and bosses
	var enemies = get_tree().get_nodes_in_group("enemies")
	var bosses = get_tree().get_nodes_in_group("boss")
	var all_entities = enemies + bosses
	
	for entity in all_entities:
		if entity == self:
			continue
		if not is_instance_valid(entity):
			continue
		if not entity is CharacterBody2D:
			continue
		
		var distance = global_position.distance_to(entity.global_position)
		if distance < SEPARATION_DISTANCE and distance > 0:
			var direction = (global_position - entity.global_position).normalized()
			var force = (SEPARATION_DISTANCE - distance) / SEPARATION_DISTANCE
			separation += direction * force * SEPARATION_FORCE
	
	# Apply separation as additional velocity to desired_velocity
	if separation.length() > 0:
		desired_velocity += separation * get_physics_process_delta_time()

func _check_line_of_sight() -> bool:
	if not raycast or not player:
		return false
	raycast.target_position = player.global_position - global_position
	raycast.force_raycast_update()
	return not raycast.is_colliding()

func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	
	previous_state = current_state
	current_state = new_state
	print("[MINOTAUR] State changed: ", State.keys()[previous_state], " -> ", State.keys()[current_state])
	
	match new_state:
		State.IDLE:
			desired_velocity = Vector2.ZERO
		State.CHASE:
			desired_velocity = Vector2.ZERO
		State.ATTACK_AXE:
			desired_velocity = Vector2.ZERO
			can_attack = false
			attack_cooldown_timer = 0.0
			has_hit_player_this_attack = false  # Reset hit flag
			_trigger_screen_shake(8.0, 0.25)
		State.ATTACK_STOMP:
			desired_velocity = Vector2.ZERO
			can_attack = false
			attack_cooldown_timer = 0.0
			has_hit_player_this_attack = false  # Reset hit flag
			_trigger_screen_shake(10.0, 0.3)
		State.DAMAGED:
			desired_velocity = Vector2.ZERO
			is_damaged = true
			damage_timer = 0.0
		State.RAGE_MODE:
			desired_velocity = Vector2.ZERO
			_activate_rage()
		State.DEAD:
			desired_velocity = Vector2.ZERO
			velocity = Vector2.ZERO

func _handle_idle(_delta: float, distance: float, can_see: bool) -> void:
	desired_velocity = Vector2.ZERO
	
	if can_see and distance <= AGGRO_RANGE:
		_change_state(State.CHASE)

func _handle_chase(_delta: float, distance: float, can_see: bool) -> void:
	if not can_see or distance > AGGRO_RANGE:
		_change_state(State.IDLE)
		return
	
	# Move towards player
	var direction = (player.global_position - global_position).normalized()
	desired_velocity = direction * current_speed
	
	# Attack selection based on distance
	if can_attack:
		print("[MINOTAUR] In range! Distance: ", distance, " | Close: ", CLOSE_RANGE, " | Medium: ", MEDIUM_RANGE)
		if distance <= CLOSE_RANGE:
			# Close range: Axe attack
			print("[MINOTAUR] Starting AXE attack!")
			_change_state(State.ATTACK_AXE)
		elif distance <= MEDIUM_RANGE:
			# Medium range: Stomp attack
			print("[MINOTAUR] Starting STOMP attack!")
			_change_state(State.ATTACK_STOMP)

func _handle_attack_axe(_delta: float) -> void:
	desired_velocity = Vector2.ZERO
	# Stay still during attack, hitbox controlled by minotaur_hitbox_host.gd
	# Exit to CHASE handled in _on_animation_finished

func _handle_attack_stomp(_delta: float) -> void:
	desired_velocity = Vector2.ZERO
	# Stay still during attack
	# AOE damage triggered on specific animation frames
	# Exit to CHASE handled in _on_animation_finished

func _handle_damaged(_delta: float) -> void:
	desired_velocity = Vector2.ZERO
	# Stun handled by _update_timers

func _handle_rage_mode(_delta: float, distance: float, can_see: bool) -> void:
	# Rage mode is just a more aggressive chase state
	if not can_see or distance > AGGRO_RANGE:
		_change_state(State.IDLE)
		return
	
	# Move faster towards player
	var direction = (player.global_position - global_position).normalized()
	desired_velocity = direction * current_speed
	
	# More aggressive attack selection
	if can_attack:
		if distance <= CLOSE_RANGE:
			_change_state(State.ATTACK_AXE)
		elif distance <= MEDIUM_RANGE:
			_change_state(State.ATTACK_STOMP)

func _handle_dead(_delta: float) -> void:
	desired_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	# Death handled by animation_finished

# Animation name constants (optimized)
const ANIM_IDLE = "idle_animation"
const ANIM_WALK = "walk_animation"
const ANIM_ATTACK = "attack_animation"
const ANIM_STOMP = "attack_stomp_animation"
const ANIM_DAMAGED = "damaged_animation"
const ANIM_DEATH = "death_animation"

func _update_animation() -> void:
	if current_state == State.DEAD:
		if animated_sprite.animation != ANIM_DEATH:
			animated_sprite.play(ANIM_DEATH)
		return
	
	# Get current animation (cached)
	var current_anim = animated_sprite.animation
	
	# State-based animation (optimized)
	match current_state:
		State.IDLE:
			if current_anim != ANIM_IDLE:
				animated_sprite.play(ANIM_IDLE)
		State.CHASE, State.RAGE_MODE:
			if current_anim != ANIM_WALK:
				animated_sprite.play(ANIM_WALK)
		State.ATTACK_AXE:
			if current_anim != ANIM_ATTACK:
				animated_sprite.play(ANIM_ATTACK)
		State.ATTACK_STOMP:
			if current_anim != ANIM_STOMP:
				animated_sprite.play(ANIM_STOMP)
		State.DAMAGED:
			if current_anim != ANIM_DAMAGED:
				animated_sprite.play(ANIM_DAMAGED)

func take_damage(amount: int, _source_position: Vector2 = Vector2.ZERO) -> void:
	if current_state == State.DEAD:
		return
	
	# Reduce HP
	current_hp -= amount
	if current_hp < 0:
		current_hp = 0
	
	# Emit signal for UI
	health_changed.emit(current_hp, max_hp)
	
	print("Minotaur took ", amount, " damage. HP: ", current_hp, "/", max_hp)
	
	# Spawn damage indicator
	_spawn_damage_indicator(amount)
	
	# Flash red
	_trigger_red_flash()
	
	# Check for rage mode activation
	if not is_enraged and current_hp <= int(max_hp * RAGE_THRESHOLD):
		_activate_rage()
	
	# Enter damaged state (brief stun)
	if current_state != State.DAMAGED:
		_change_state(State.DAMAGED)
	
	# Check for death
	if current_hp <= 0:
		die()

func _activate_rage() -> void:
	if is_enraged:
		return
	
	is_enraged = true
	current_speed = RAGE_SPEED
	current_attack_cooldown = RAGE_ATTACK_COOLDOWN
	
	print("MINOTAUR ENRAGED! Phase 2 activated!")
	
	# Visual: Turn sprite red
	var tween = create_tween()
	tween.tween_property(animated_sprite, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.5)
	
	# Screen shake for phase change
	_trigger_screen_shake(15.0, 0.5)

func _trigger_red_flash() -> void:
	# Flash red
	animated_sprite.modulate = Color(1.0, 0.2, 0.2, 1.0)
	
	# Tween back to normal or enraged color
	var target_color = Color(1.0, 0.3, 0.3, 1.0) if is_enraged else Color.WHITE
	var tween = create_tween()
	tween.tween_property(animated_sprite, "modulate", target_color, 0.15)

func _trigger_screen_shake(intensity: float, duration: float) -> void:
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(intensity, duration)

func _spawn_damage_indicator(amount: int) -> void:
	var indicator = DamageIndicator.instantiate()
	if indicator:
		var spawn_position: Vector2
		if damage_spawn_point:
			spawn_position = damage_spawn_point.global_position
		else:
			spawn_position = global_position
		
		spawn_position += Vector2(randf_range(-10, 10), randf_range(-10, 10))
		
		indicator.global_position = spawn_position
		indicator.set_amount(amount)
		
		var current_scene = get_tree().current_scene
		if current_scene:
			current_scene.add_child(indicator)

func die() -> void:
	if current_state == State.DEAD:
		return
	
	_change_state(State.DEAD)
	print("Minotaur Boss defeated!")
	
	# Stop movement
	velocity = Vector2.ZERO
	desired_velocity = Vector2.ZERO
	
	# Disable collision
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Give player EXP
	if player and player.has_method("gain_xp"):
		var exp_amount = randi_range(500, 750)
		player.gain_xp(exp_amount)
		print("Minotaur gave player ", exp_amount, " XP")
	
	# Notify GameManager
	if GameManager.has_method("boss_defeated"):
		GameManager.boss_defeated()

func _on_animation_finished() -> void:
	var anim_name = animated_sprite.animation
	
	match anim_name:
		ANIM_ATTACK:
			# Reset offset when attack animation finishes
			animated_sprite.offset = Vector2.ZERO
			# Axe attack finished, return to chase or rage mode
			_change_state(State.RAGE_MODE if is_enraged else State.CHASE)
		
		ANIM_STOMP:
			# Stomp attack finished, return to chase or rage mode
			_change_state(State.RAGE_MODE if is_enraged else State.CHASE)
		
		ANIM_DAMAGED:
			# Damage animation finished, already handled by _update_timers
			pass
		
		ANIM_DEATH:
			# Death animation finished, remove boss
			queue_free()

func _on_animated_sprite_frame_changed() -> void:
	var current_frame = animated_sprite.frame
	
	# Play slash sound on frame 1 of attack_animation (optimized)
	if animated_sprite.animation == ANIM_ATTACK and current_frame == 1:
		if slash_sound and not slash_sound.playing:
			slash_sound.play()
	
	# Play stomp sound on frame 2 of attack_stomp_animation (optimized)
	if animated_sprite.animation == ANIM_STOMP and current_frame == 2:
		if stomp_sound and not stomp_sound.playing:
			stomp_sound.play()
	
	# Fix alignment for attack_animation - use offset property (optimized)
	if animated_sprite.animation == ANIM_ATTACK:
		animated_sprite.offset = attack_offset_fix
	elif animated_sprite.offset != Vector2.ZERO:
		animated_sprite.offset = Vector2.ZERO
	
	# Handle axe attack hitbox (frame-based, optimized)
	if animated_sprite.animation == ANIM_ATTACK and hitbox:
		if current_frame in HITBOX_ACTIVE_FRAMES:
			if not hitbox.monitoring:
				hitbox.monitoring = true
				hitbox.monitorable = true
			
			# Check for damage on every active frame
			_deal_axe_damage()
			last_attack_frame = current_frame
		else:
			if hitbox.monitoring:
				hitbox.monitoring = false
				hitbox.monitorable = false
	
	# Trigger stomp AOE on specific frame
	if animated_sprite.animation == ANIM_STOMP and current_frame == 3:
		_trigger_stomp_aoe()

func _deal_axe_damage() -> void:
	"""Deal axe attack damage - called on active frames for reliable hit detection"""
	if not player:
		return
	
	if current_state != State.ATTACK_AXE:
		return
	
	# Prevent multi-hit
	if has_hit_player_this_attack:
		return
	
	# Check distance-based hit (optimized range)
	var attack_range = CLOSE_RANGE * 1.3  # Optimized range multiplier
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player <= attack_range:
		# Player is hit if they're within attack range
		if player.has_method("take_damage"):
			player.take_damage(MINOTAUR_DAMAGE, global_position)
			has_hit_player_this_attack = true

func _trigger_stomp_aoe() -> void:
	# Deal damage to player if in radius
	if not player:
		return
	
	var distance_to_player = global_position.distance_to(player.global_position)
	
	if distance_to_player <= STOMP_RADIUS:
		# Player is in AOE range, deal damage
		if player.has_method("take_damage"):
			player.take_damage(STOMP_DAMAGE)
			print("Minotaur: Stomp AOE hit player for ", STOMP_DAMAGE, " damage!")
		
		# Visual feedback (could add particle effect here)
		_trigger_screen_shake(12.0, 0.4)

func _on_hitbox_area_entered(area: Area2D) -> void:
	"""Hitbox entered - minotaur deals damage to player (optimized)"""
	if not hitbox or not hitbox.monitoring:
		return
	
	# Prevent multi-hit - only damage player once per attack
	if has_hit_player_this_attack:
		return
	
	# Find player by traversing up the tree
	var node = area
	var player_target = null
	
	while node:
		if node.is_in_group("player"):
			player_target = node
			break
		if node.is_in_group("enemy") or node.is_in_group("boss"):
			return  # Don't hit self or other enemies
		node = node.get_parent()
	
	# Deal damage to player
	if player_target and player_target.has_method("take_damage"):
		player_target.take_damage(MINOTAUR_DAMAGE, global_position)
		has_hit_player_this_attack = true

func _on_hurtbox_area_entered(area: Area2D) -> void:
	"""Hurtbox entered - minotaur receives damage from player (optimized)"""
	# CRITICAL: Only take damage if the player's attack hurtbox is monitoring (player is attacking)
	if not area.monitoring:
		return
	
	# Find the player node
	var node = area
	var attacker = null
	
	while node:
		if node.is_in_group("player"):
			attacker = node
			break
		if node.is_in_group("enemy") or node.is_in_group("boss"):
			return
		node = node.get_parent()
	
	# Prevent double damage from same attack
	if attacker:
		# Check if we're on damage cooldown from this same attacker
		if damage_cooldown_timer > 0.0 and last_damage_source == attacker:
			return
		
		# Take damage from player
		if attacker.has_method("calculate_damage"):
			var damage = attacker.calculate_damage()
			take_damage(damage, attacker.global_position)
			
			# Set damage cooldown to prevent double hits
			damage_cooldown_timer = DAMAGE_COOLDOWN
			last_damage_source = attacker
