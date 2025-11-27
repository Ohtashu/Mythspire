extends CharacterBody2D
class_name Player

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var walk_sound: AudioStreamPlayer2D = get_node_or_null("WalkSound")
@onready var attack_sound: AudioStreamPlayer2D = get_node_or_null("sfx_attack")
@onready var attack_voice: AudioStreamPlayer2D = get_node_or_null("player_attack_voice")
@onready var equip_sound: AudioStreamPlayer2D = get_node_or_null("sfx_equip")
@onready var unequip_sound: AudioStreamPlayer2D = get_node_or_null("sfx_unequip")
@onready var hurt_sound: AudioStreamPlayer2D = get_node_or_null("player_damaged")
@onready var level_sound_effect: AudioStreamPlayer2D = get_node_or_null("level_sound_effect")
@onready var hurtbox: Area2D = $player_interaction/hurtbox
@onready var player_interaction: Node2D = $player_interaction

func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.frame_changed.connect(_on_frame_changed)
	if equip_sound:
		equip_sound.pitch_scale = 2.0
	if unequip_sound:
		unequip_sound.pitch_scale = 2.0

	add_to_group("player")
	
	# Initialize leveling system
	level = 1
	current_xp = 0
	xp_to_next_level = 100
	
	# Initialize base stats (these are modified by leveling)
	base_damage = 3
	base_defense = 0
	base_max_health = 20
	base_speed = BASE_SPEED
	crit_damage = 2.0  # Starting crit damage multiplier (2.0x = 200%, will be modified by STR)
	
	# Apply initial stat formulas (calculates derived stats from base + attributes)
	apply_stat_formulas()
	
	# Step 3: Restore health from GameManager if transitioning from another scene
	if GameManager and GameManager.player_health > 0:
		# Restore saved health (but don't exceed current max_health if player leveled up)
		current_health = min(GameManager.player_health, max_health)
		print("Player: Restored health from GameManager - ", current_health, "/", max_health)
	else:
		# First time loading or no saved data, use full health
		current_health = max_health
	
	# Verify sound nodes are found
	if not attack_sound:
		print("WARNING: attack_sound (sfx_attack) not found!")
	if not attack_voice:
		print("WARNING: attack_voice (player_attack_voice) not found!")
	if not hurt_sound:
		print("WARNING: hurt_sound (player_damaged) not found!")
	
	# Store initial spawn position for respawn
	spawn_position = global_position
	
	# Step 3: Restore position from spawn point if transitioning from another scene
	if GameManager and GameManager.target_spawn_tag != "":
		# Find the Marker2D in the current scene with matching name
		var current_scene = get_tree().current_scene
		if current_scene:
			var spawn_point = current_scene.find_child(GameManager.target_spawn_tag, true, false)
			if spawn_point and spawn_point is Marker2D:
				# Move player to spawn point
				global_position = spawn_point.global_position
				spawn_position = global_position  # Update spawn position too
				print("Player: Moved to spawn point '", GameManager.target_spawn_tag, "' at position ", global_position)
			else:
				print("Player: WARNING - Could not find Marker2D with name '", GameManager.target_spawn_tag, "'")
		
		# Clear the spawn tag after use
		GameManager.target_spawn_tag = ""

# Base speed constant (will be modified by DEX)
const BASE_SPEED = 80.0

var last_direction: String = "down"
var use_spear_animations: bool = false
var is_attacking: bool = false
var is_moving: bool = false
var is_running: bool = false
var is_dying: bool = false  # Flag to prevent normal behavior during death animation
var death_animation_complete: bool = false  # Flag to track if death animation completed
var spawn_position: Vector2  # Store initial spawn position for respawn

# Knockback system (replaces stun)
var knockback_velocity: Vector2 = Vector2.ZERO
@export var knockback_force: float = 300.0  # Force of knockback when hit
@export var knockback_friction: float = 10.0  # Friction to slow down knockback
var input_lock_timer: float = 0.0  # Timer to lock input during knockback (0.2s)
const INPUT_LOCK_DURATION: float = 0.2  # Duration to lock input after being hit

# Invincibility system
var is_invincible: bool = false  # Flag for invincibility frames
var invincibility_timer: float = 0.0  # Timer for invincibility
const INVINCIBILITY_DURATION: float = 1.0  # 1 second of invincibility after being hit

# Health system
var max_health: int = 20  # Starting health (will increase with levels)
var current_health: int = 20
var damage: int = 3  # Starting damage (will increase with levels)
var defense: int = 0  # Starting defense (will increase on even levels)

# EXP and Leveling system
var level: int = 1
var current_xp: int = 0
var xp_to_next_level: int = 100
const MAX_LEVEL: int = 30

# Stat upgrade system
var stat_points: int = 0  # Points available to spend on upgrades
var strength: int = 0  # Strength upgrade level (0-50)
var dexterity: int = 0  # Dexterity upgrade level (0-50)
var vitality: int = 0  # Vitality upgrade level (0-50)
const MAX_STAT_LEVEL: int = 50  # Maximum upgrade level for each stat (hard cap)

# Base stats (from leveling)
var base_max_health: int = 20
var base_damage: int = 3
var base_defense: int = 0
var base_speed: float = 80.0
var crit_damage: float = 2.0  # Crit damage multiplier (e.g., 2.0x = 200% damage on crit, affected by STR)

# Signals
signal xp_changed(current_xp: int, xp_to_next: int)
signal leveled_up(new_level: int, new_max_health: int, new_damage: int, new_defense: int)
signal stat_points_changed(new_points: int)
signal stat_upgraded(stat_name: String, new_level: int)
signal player_died  # Emitted when player dies (for game over screen)

const PLAYER_DAMAGE = 20  # Damage player deals to enemies (will be replaced by damage variable)

func _physics_process(delta: float) -> void:
	# Skip normal behavior if dying
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	# Task 1: Handle knockback friction and input lock
	if knockback_velocity.length() > 0.1:
		# Apply friction to slow down knockback
		var friction_factor = 1.0 - (knockback_friction * delta)
		friction_factor = max(0.0, friction_factor)
		knockback_velocity *= friction_factor
		# Add knockback to velocity
		velocity += knockback_velocity * delta
		# Clear very small knockback
		if knockback_velocity.length() < 0.1:
			knockback_velocity = Vector2.ZERO
	
	# Handle input lock timer (prevents player from moving during knockback)
	if input_lock_timer > 0.0:
		input_lock_timer -= delta
		if input_lock_timer <= 0.0:
			input_lock_timer = 0.0
	
	# Handle invincibility timer and flashing
	if is_invincible:
		invincibility_timer -= delta
		if invincibility_timer <= 0.0:
			is_invincible = false
			invincibility_timer = 0.0
			# Restore normal modulate
			if animated_sprite:
				animated_sprite.modulate = Color.WHITE
		else:
			# Flash effect during invincibility (blink every 0.1 seconds)
			if animated_sprite:
				var flash_cycle = int(invincibility_timer * 10) % 2
				animated_sprite.modulate = Color.WHITE if flash_cycle == 0 else Color(1, 1, 1, 0.5)
	
	# Only process input if not locked
	if input_lock_timer <= 0.0:
		# Get input direction for top-down movement
		var input_vector := Vector2.ZERO
		if not is_attacking:
			input_vector.x = Input.get_axis("move_left", "move_right")
			input_vector.y = Input.get_axis("move_up", "move_down")

			# Normalize diagonal movement
			if input_vector.length() > 0:
				input_vector = input_vector.normalized()

		# Toggle running on left shift press
		if Input.is_action_just_pressed("run"):
			is_running = !is_running

		# Apply movement (only if not attacking)
		var current_speed = get_movement_speed() * (2.0 if is_running else 1.0)
		velocity = input_vector * current_speed

		# Update is_moving
		is_moving = input_vector.length() > 0 and not is_attacking

		# Handle spear attack (left mouse button)
		if Input.is_action_just_pressed("attack") and use_spear_animations and not is_attacking:
			is_attacking = true
			perform_spear_attack()

		# Update animation based on movement
		update_animation(input_vector, delta, is_running)
	else:
		# During input lock, apply friction to velocity (knockback is already applied above)
		# This allows the player to slide to a stop smoothly
		velocity = velocity.lerp(Vector2.ZERO, knockback_friction * delta)
		is_moving = false

	move_and_slide()

func perform_spear_attack() -> void:
	var attack_anim_name := ""
	var direction_key = last_direction

	# Normalize direction keys
	if direction_key == "top":
		direction_key = "up"
	elif direction_key == "top_right":
		direction_key = "up_right"
	elif direction_key == "top_left":
		direction_key = "up_left"

	match direction_key:
		"right":
			attack_anim_name = "attack_spear_right"
		"left":
			attack_anim_name = "attack_spear_left"
		"up":
			attack_anim_name = "attack_spear_up"
		"down":
			attack_anim_name = "attack_spear_down"
		"up_right":
			attack_anim_name = "attack_spear_right_up"
		"up_left":
			attack_anim_name = "attack_spear_left_up"
		"down_left":
			attack_anim_name = "attack_spear_left_down"
		"down_right":
			attack_anim_name = "attack_spear_right_down"
		_:
			attack_anim_name = "attack_spear_down"

	animated_sprite.play(attack_anim_name)
	
	# Play attack sound and voice immediately when attack starts
	if attack_sound:
		attack_sound.play()
	if attack_voice:
		attack_voice.play()

func _on_animation_finished() -> void:
	# Check if death animation finished
	if is_dying:
		# Check which death animation finished
		var current_anim = animated_sprite.animation
		if current_anim.begins_with("normal_death"):
			# Death animation completed, emit signal for game over screen
			# Don't auto-respawn anymore - game over screen handles it
			player_died.emit()
			return
	
	if is_attacking:
		is_attacking = false
		hurtbox.monitoring = false

func _on_frame_changed() -> void:
	# Track death animation completion (fallback if animation loops)
	if is_dying and not death_animation_complete:
		var current_anim = animated_sprite.animation
		if current_anim.begins_with("normal_death"):
			if animated_sprite.sprite_frames:
				var frame_count = animated_sprite.sprite_frames.get_frame_count(current_anim)
				# Check if we're on the last frame
				if animated_sprite.frame >= frame_count - 1:
					death_animation_complete = true
					# Emit signal for game over screen (don't auto-respawn)
					player_died.emit()
					return
	
	if is_moving and walk_sound and (animated_sprite.frame == 1 or animated_sprite.frame == 5):
		walk_sound.play()
	if is_attacking and animated_sprite.frame == 4:
		# Enable hurtbox monitoring on attack frame
		hurtbox.monitoring = true
		# Check for overlapping areas when monitoring turns on
		# (in case enemy was already inside when monitoring activated)
		_check_overlapping_enemies()

func update_animation(direction: Vector2, _delta: float, running: bool) -> void:
	# Don't change animation while dying, attacking, or stunned
	if is_dying or is_attacking or input_lock_timer > 0.0:
		return

	var anim_name: String = ""

	# Determine if player is moving
	var moving := direction.length() > 0
	
	if moving:
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

		var base_anim_name := ""

		if running and not use_spear_animations:
			# Use run animations
			if moving_up:
				if moving_left:
					base_anim_name = "normal_up_left_run"
					last_direction = "up_left"
				elif moving_right:
					base_anim_name = "normal_up_right_run"
					last_direction = "up_right"
				else:
					base_anim_name = "normal_up_run"
					last_direction = "up"
			elif moving_down:
				if moving_left:
					base_anim_name = "normal_down_left_run"
					last_direction = "down_left"
				elif moving_right:
					base_anim_name = "normal_down_right_run"
					last_direction = "down_right"
				else:
					base_anim_name = "normal_down_run"
					last_direction = "down"
			elif moving_left:
				base_anim_name = "normal_left_run"
				last_direction = "left"
			elif moving_right:
				base_anim_name = "normal_right_run"
				last_direction = "right"
			else:
				base_anim_name = "normal_down_run"
				last_direction = "down"
		else:
			# Use walk or sprint animations
			if moving_up:
				# Moving up (W key) - use "up" animations
				if moving_left:
					# Up + Left = walk_left_up
					base_anim_name = "walk_left_up"
					last_direction = "up_left"
				elif moving_right:
					# Up + Right = walk_right_up (using the actual animation name from scene)
					base_anim_name = "walk_right_up"
					last_direction = "up_right"
				else:
					# Pure up
					base_anim_name = "walk_up"
					last_direction = "up"
			elif moving_down:
				# Moving down (S key) - use "down" animations
				if moving_left:
					# Down + Left = walk_left_down
					base_anim_name = "walk_left_down"
					last_direction = "down_left"
				elif moving_right:
					# Down + Right = walk_right_down
					base_anim_name = "walk_right_down"
					last_direction = "down_right"
				else:
					# Pure down
					base_anim_name = "walk_down"
					last_direction = "down"
			elif moving_left:
				# Moving left (A key) - use "left" animations
				base_anim_name = "walk_left"
				last_direction = "left"
			elif moving_right:
				# Moving right (D key) - use "right" animations
				base_anim_name = "walk_right"
				last_direction = "right"
			else:
				# Fallback (shouldn't happen if moving is true)
				base_anim_name = "walk_down"
				last_direction = "down"

			# Use spear animations if spear is equipped
			if use_spear_animations:
				if running:
					# Use sprint spear animations
					anim_name = base_anim_name.replace("walk_", "sprint_spear_")
				else:
					# Use spear walk animations
					anim_name = base_anim_name.replace("walk_", "walk_spear_")
			else:
				anim_name = base_anim_name

		if running and not use_spear_animations:
			anim_name = base_anim_name
	else:
		# Use idle animation based on last direction and spear mode
		var direction_key = last_direction
		
		# Normalize direction keys (handle old "top" naming)
		if direction_key == "top":
			direction_key = "up"
		elif direction_key == "top_right":
			direction_key = "up_right"
		elif direction_key == "top_left":
			direction_key = "up_left"
		
		if use_spear_animations:
			# Use spear idle animations
			match direction_key:
				"right":
					anim_name = "idle_spear_right"
				"left":
					anim_name = "idle_spear_left"
				"up":
					anim_name = "idle_spear_up"
				"down":
					anim_name = "idle_spear_down"
				"up_right":
					anim_name = "idle_spear_right_up"
				"up_left":
					anim_name = "idle_spear_left_up"
				"down_left":
					anim_name = "idle_spear_left_down"
				"down_right":
					anim_name = "idle_spear_right_down"
				_:
					anim_name = "idle_spear_down"
		else:
			# Use regular idle animations
			match direction_key:
				"right":
					anim_name = "idle_right"
				"left":
					anim_name = "idle_left"
				"up":
					anim_name = "idle_up"
				"down":
					anim_name = "idle_down"
				"up_right":
					anim_name = "idle_right_up"
				"up_left":
					anim_name = "idle_left_up"
				"down_left":
					anim_name = "idle_left_down"
				"down_right":
					anim_name = "idle_right_down"
				_:
					anim_name = "idle_down"
	
	# Play animation if it's different from current
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)


func get_direction_rotation(dir: String) -> float:
	match dir:
		"right":
			return 0
		"left":
			return PI
		"up":
			return -PI / 2
		"down":
			return PI / 2
		"up_right":
			return -PI / 4
		"up_left":
			return -3 * PI / 4
		"down_right":
			return PI / 4
		"down_left":
			return 3 * PI / 4
		_:
			return 0


func _check_overlapping_enemies() -> void:
	# Check for enemies that are already overlapping when monitoring turns on
	if not hurtbox.monitoring:
		return
	
	var overlapping_areas = hurtbox.get_overlapping_areas()
	
	for area in overlapping_areas:
		if area.is_in_group("hitbox"):
			# IMPORTANT: Check if this is the player's own hitbox - if so, ignore it
			var node_check = area
			var is_player_hitbox = false
			while node_check:
				if node_check.is_in_group("player"):
					# This is the player's own hitbox, skip it
					is_player_hitbox = true
					break
				node_check = node_check.get_parent()
			
			if is_player_hitbox:
				continue  # Skip player's own hitbox
			
			# Find the enemy node
			var node = area
			var enemy = null
			while node:
				if node.has_method("take_knockback"):
					enemy = node
					break
				node = node.get_parent()
			
			# Apply knockback and damage if enemy found
			if enemy and enemy.has_method("take_knockback"):
				var knockback_direction = (enemy.global_position - global_position).normalized()
				enemy.take_knockback(knockback_direction)
				# Deal damage to enemy (use damage variable instead of constant)
				if enemy.has_method("take_damage"):
					enemy.take_damage(damage, global_position)

func take_damage(amount: int, source_pos: Vector2 = Vector2.ZERO) -> void:
	# Don't take damage if already dying or invincible
	if is_dying or is_invincible:
		return
	
	# Apply defense reduction
	var final_damage = amount - defense
	if final_damage < 1:
		final_damage = 1  # Always take at least 1 damage
	
	# Play hurt sound
	if hurt_sound:
		hurt_sound.play()
	
	current_health -= final_damage
	if current_health < 0:
		current_health = 0
	# Handle death
	if current_health <= 0:
		die()
	else:
		# Priority Interrupt: Cancel any current action (especially attacking)
		if is_attacking:
			is_attacking = false
			hurtbox.monitoring = false
		
		# Task 1: Apply knockback (replaces stun)
		if source_pos != Vector2.ZERO:
			var direction = (global_position - source_pos).normalized()
			knockback_velocity = direction * knockback_force
			velocity = direction * knockback_force  # Direct velocity assignment
		else:
			# Fallback: if no source position, don't apply knockback
			knockback_velocity = Vector2.ZERO
		
		# Task 1: Lock input for 0.2 seconds so player slides back
		input_lock_timer = INPUT_LOCK_DURATION
		is_moving = false
		
		# Task 1: Start invincibility frames (1 second)
		is_invincible = true
		invincibility_timer = INVINCIBILITY_DURATION
		
		# Start flashing effect
		if animated_sprite:
			animated_sprite.modulate = Color(1, 1, 1, 0.5)
		
		print("Player took ", final_damage, " damage (", amount, " - ", defense, " defense). Health: ", current_health, "/", max_health, " [KNOCKBACK]")

func die() -> void:
	if is_dying:
		return  # Already dying, don't call again
	
	is_dying = true
	print("Player died! Playing death animation...")
	
	# Stop all movement and input
	velocity = Vector2.ZERO
	is_attacking = false
	is_moving = false
	
	# Disable collision temporarily
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Disable hurtbox
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	
	# Determine death animation based on last direction
	var death_anim_name = "normal_death_down"  # Default
	
	# Normalize direction keys
	var direction_key = last_direction
	if direction_key == "top":
		direction_key = "up"
	elif direction_key == "top_right":
		direction_key = "up_right"
	elif direction_key == "top_left":
		direction_key = "up_left"
	
	match direction_key:
		"right":
			death_anim_name = "normal_death_right"
		"left":
			death_anim_name = "normal_death_left"
		"up":
			death_anim_name = "normal_death_up"
		"down":
			death_anim_name = "normal_death_down"
		"up_right":
			death_anim_name = "normal_death_right_up"
		"up_left":
			death_anim_name = "normal_death_left_up"
		"down_left":
			death_anim_name = "normal_death_left_down"
		"down_right":
			death_anim_name = "normal_death_right_down"
		_:
			death_anim_name = "normal_death_down"
	
	# Disable looping for death animation so it only plays once
	if animated_sprite.sprite_frames:
		animated_sprite.sprite_frames.set_animation_loop(death_anim_name, false)
	
	# Reset completion flag
	death_animation_complete = false
	
	# Play death animation
	animated_sprite.play(death_anim_name)

func revive() -> void:
	"""Revive the player at their current location with full HP"""
	print("Player reviving...")
	
	# Reset health to full
	current_health = max_health
	
	# Reset all states
	is_dying = false
	death_animation_complete = false
	is_attacking = false
	is_moving = false
	knockback_velocity = Vector2.ZERO
	input_lock_timer = 0.0
	is_invincible = false
	invincibility_timer = 0.0
	velocity = Vector2.ZERO
	
	# Re-enable collision
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	
	# Re-enable hurtbox
	if hurtbox:
		hurtbox.set_deferred("monitoring", true)
		hurtbox.set_deferred("monitorable", true)
	
	# Play idle animation (not death animation)
	update_animation(Vector2.ZERO, 0.0, false)
	
	print("Player revived! Health: ", current_health, "/", max_health)

func gain_xp(amount: int) -> void:
	# Add amount to current_xp
	current_xp += amount
	
	# While current_xp >= xp_to_next_level, trigger level_up() (handle multiple level ups)
	while current_xp >= xp_to_next_level and level < MAX_LEVEL:
		level_up()
	
	# Emit signal for UI updates
	xp_changed.emit(current_xp, xp_to_next_level)
	print("Player gained ", amount, " XP. Current: ", current_xp, "/", xp_to_next_level, " (Level ", level, ")")

func level_up() -> void:
	# Don't level up past max level
	if level >= MAX_LEVEL:
		return
	
	# Increment level by 1
	level += 1
	
	# Play level up sound effect
	if level_sound_effect:
		level_sound_effect.play()
	
	# Subtract xp_to_next_level from current_xp (carry over overflow)
	current_xp -= xp_to_next_level
	
	# Increase xp_to_next_level by multiplying it by 1.5 (and round to nearest int)
	xp_to_next_level = int(xp_to_next_level * 1.5)
	
	# Stat Buffs (base stats from leveling):
	# Increase base_max_health by 5
	base_max_health += 5
	
	# Increase base_damage by 1
	base_damage += 1
	
	# Increase base_defense by 1 ONLY if the new level is an Even number (2, 4, 6, etc)
	if level % 2 == 0:
		base_defense += 1
	
	# Recalculate derived stats from base + attributes
	apply_stat_formulas()
	
	# Give stat points on level up (3 points per level)
	stat_points += 3
	stat_points_changed.emit(stat_points)
	
	# Heal the player to full max_health
	current_health = max_health
	
	# Emit signal 'leveled_up' passing the new stats
	leveled_up.emit(level, max_health, damage, defense)
	
	print("LEVEL UP! Level ", level, " | Max Health: ", max_health, " | Damage: ", damage, " | Defense: ", defense, " | Stat Points: ", stat_points)
	
	# Check if we can level up again (handle multiple level ups from huge XP gains)
	if current_xp >= xp_to_next_level and level < MAX_LEVEL:
		level_up()

# Stat formulas: Calculate derived stats from base stats + attributes
func apply_stat_formulas() -> void:
	# 1 STR = +2 Physical Damage AND +0.1 Crit Damage
	damage = base_damage + (strength * 2)
	crit_damage = 2.0 + (strength * 0.1)  # Base 2.0x + 0.1x per STR point
	
	# 1 VIT = +10 Max Health and +1 Defense
	max_health = base_max_health + (vitality * 10)
	defense = base_defense + vitality
	
	# Ensure current health doesn't exceed new max
	if current_health > max_health:
		current_health = max_health

# Get cost for upgrading a stat based on current level
func get_stat_upgrade_cost(stat_level: int) -> int:
	if stat_level < 10:
		return 1
	elif stat_level < 30:
		return 2
	else:  # 30-50
		return 3

# Stat upgrade functions
func upgrade_strength() -> bool:
	var cost = get_stat_upgrade_cost(strength)
	if stat_points < cost or strength >= MAX_STAT_LEVEL:
		return false
	stat_points -= cost
	strength += 1
	apply_stat_formulas()  # Immediately apply stat changes
	stat_points_changed.emit(stat_points)
	stat_upgraded.emit("strength", strength)
	print("Upgraded Strength to ", strength, " | Remaining points: ", stat_points)
	return true

func upgrade_dexterity() -> bool:
	var cost = get_stat_upgrade_cost(dexterity)
	if stat_points < cost or dexterity >= MAX_STAT_LEVEL:
		return false
	stat_points -= cost
	dexterity += 1
	apply_stat_formulas()  # Immediately apply stat changes
	stat_points_changed.emit(stat_points)
	stat_upgraded.emit("dexterity", dexterity)
	print("Upgraded Dexterity to ", dexterity, " | Remaining points: ", stat_points)
	return true

func upgrade_vitality() -> bool:
	var cost = get_stat_upgrade_cost(vitality)
	if stat_points < cost or vitality >= MAX_STAT_LEVEL:
		return false
	stat_points -= cost
	vitality += 1
	apply_stat_formulas()  # Immediately apply stat changes
	stat_points_changed.emit(stat_points)
	stat_upgraded.emit("vitality", vitality)
	print("Upgraded Vitality to ", vitality, " | Remaining points: ", stat_points)
	return true

# Get derived stats for display/preview
func get_crit_chance() -> float:
	# 1 DEX = +1% Crit Chance
	return dexterity * 1.0

func get_movement_speed() -> float:
	# 1 DEX = +1 Movement Speed
	return BASE_SPEED + dexterity
