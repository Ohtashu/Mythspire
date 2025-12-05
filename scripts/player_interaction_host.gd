extends Node2D

@onready var player = get_parent().get_parent()  # Go up through Visuals to Player
@onready var hurtbox = $hurtbox

# Hurtbox positioning constants
const HURTBOX_DISTANCE: float = 20.0  # Small gap between player and hurtbox (optimized)

# Direction to angle mapping for smooth positioning (like clock hand)
var direction_angles = {
	"right": 0.0,           # 3 o'clock
	"down_right": PI / 4,   # 4:30
	"down": PI / 2,         # 6 o'clock
	"down_left": 3 * PI / 4, # 7:30
	"left": PI,             # 9 o'clock
	"up_left": -3 * PI / 4, # 10:30
	"up": -PI / 2,          # 12 o'clock
	"up_right": -PI / 4    # 1:30
}

func _ready() -> void:
	# Connect to hurtbox's area_entered signal to detect when player hits enemies
	hurtbox.area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if not player or not hurtbox:
		return
	
	# Get player's movement direction (prefer actual velocity, fallback to last_direction)
	var direction_vector: Vector2 = Vector2.ZERO
	var target_angle: float = 0.0
	
	# Try to use actual velocity if player is moving
	if "velocity" in player and player.velocity.length() > 5.0:
		direction_vector = player.velocity.normalized()
		target_angle = atan2(direction_vector.y, direction_vector.x)
	else:
		# Use last_direction as fallback
		var dir = player.last_direction
		if dir in direction_angles:
			target_angle = direction_angles[dir]
		else:
			target_angle = PI / 2  # Default to down (6 o'clock)
		direction_vector = Vector2(cos(target_angle), sin(target_angle))
	
	# Calculate position with small gap in the direction player is facing/moving
	# Like a clock hand pointing in that direction
	var target_position = direction_vector * HURTBOX_DISTANCE
	
	# Smoothly interpolate position for smooth movement (orbits around player like clock hand)
	hurtbox.position = hurtbox.position.lerp(target_position, delta * 12.0)
	
	# Rotate the hurtbox to point in the direction (like an arrow)
	# The hurtbox is a vertical rectangle by default (14x25.5, taller than wide)
	# We want the "point" (right side of box) to face the direction:
	# - Down (PI/2): Vertical (|) pointing down = rotation 0
	# - Right (0): Horizontal (----) pointing right = rotation -PI/2
	# - Left (PI): Horizontal (----) pointing left = rotation PI/2  
	# - Up (-PI/2): Vertical (|) pointing up = rotation PI
	
	# Convert direction angle to rotation: subtract PI/2
	# This makes: down→0, right→-PI/2, left→PI/2, up→PI
	var target_rotation = target_angle - PI / 2
	
	hurtbox.rotation = lerp_angle(hurtbox.rotation, target_rotation, delta * 15.0)

func _on_area_entered(area: Area2D) -> void:
	# Only process hits when monitoring is active (during attack frames)
	if not hurtbox.monitoring:
		return
	
	# Check if the area is a hitbox (enemy's hitbox)
	if not area.is_in_group("hitbox"):
		return
	
	# IMPORTANT: Check if this is the player's own hitbox - if so, ignore it
	var node_check = area
	while node_check:
		if node_check.is_in_group("player"):
			# This is the player's own hitbox, don't process it
			return
		node_check = node_check.get_parent()
	
	# Find the skeleton/enemy node by traversing up the tree
	# Structure: hitbox -> skeleton_hitbox (Node2D) -> Skeleton (CharacterBody2D)
	var node = area
	var enemy = null
	
	# Traverse up the tree to find the enemy
	while node:
		# Check if it's a skeleton or other enemy
		if node.has_method("take_knockback"):
			enemy = node
			break
		node = node.get_parent()
	
	# If we found an enemy, apply knockback and damage
	if enemy and enemy.has_method("take_knockback"):
		# Check if enemy is defending (for skeleton)
		# Safely check for is_defending property - only skeleton has it
		var is_defending = false
		if "is_defending" in enemy:
			is_defending = enemy.is_defending
		
		# Calculate knockback direction: from player to enemy
		var knockback_direction = (enemy.global_position - player.global_position).normalized()
		enemy.take_knockback(knockback_direction)
		
		# Only deal damage if enemy is not defending
		if not is_defending and enemy.has_method("take_damage"):
			enemy.take_damage(player.damage, player.global_position)
