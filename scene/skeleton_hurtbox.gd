extends Node2D

@onready var hurtbox: Area2D = $hurtbox
@onready var skeleton = get_parent()
@onready var animated_sprite: AnimatedSprite2D = skeleton.get_node("AnimatedSprite2D")

# Attack frames where the hurtbox should be active (adjust as needed)
const ATTACK_ACTIVE_FRAMES = [3, 4]

var check_overlaps_next_frame = false

func _ready() -> void:
	# Ensure monitoring is OFF by default
	hurtbox.monitoring = false
	hurtbox.area_entered.connect(_on_area_entered)
	
	# Connect to animation signals for frame-perfect timing
	if animated_sprite:
		animated_sprite.frame_changed.connect(_on_frame_changed)
		animated_sprite.animation_finished.connect(_on_animation_finished)

func _process(_delta: float) -> void:
	# Check overlaps on the next frame after monitoring turns on
	if check_overlaps_next_frame and hurtbox.monitoring:
		check_overlaps_next_frame = false
		_check_overlapping_areas()

func _on_frame_changed() -> void:
	# Logic Requirement B: Only enable monitoring during active attack frames
	if animated_sprite.animation == "skeleton_attack":
		# Enable monitoring only on the active swing frames
		if animated_sprite.frame in ATTACK_ACTIVE_FRAMES:
			hurtbox.monitoring = true
			# Schedule overlap check for next frame (physics needs to update)
			check_overlaps_next_frame = true
		else:
			# Immediately turn off when not on active frames
			hurtbox.monitoring = false
			check_overlaps_next_frame = false
	else:
		# Ensure monitoring is OFF for all other animations (idle, walk, chase, etc.)
		hurtbox.monitoring = false
		check_overlaps_next_frame = false

func _check_overlapping_areas() -> void:
	# Check for areas that are already overlapping when monitoring turns on
	# This must be called after monitoring is enabled and physics has updated
	if not hurtbox.monitoring:
		return
	
	# Check if CollisionShape2D is enabled
	var collision_shape = hurtbox.get_node_or_null("CollisionShape2D")
	if collision_shape and collision_shape.disabled:
		collision_shape.disabled = false
	
	var overlapping_areas = hurtbox.get_overlapping_areas()
	
	# Get skeleton hurtbox shape info
	var hurtbox_shape = hurtbox.get_node_or_null("CollisionShape2D")
	var hurtbox_radius = 0.0
	if hurtbox_shape and hurtbox_shape.shape is CircleShape2D:
		hurtbox_radius = hurtbox_shape.shape.radius
	
	# If no overlaps found but player is close, manually check distance and apply knockback
	if overlapping_areas.size() == 0 and skeleton.player:
		var player_hitbox = skeleton.player.get_node_or_null("player_hitbox/hitbox")
		if player_hitbox:
			var distance = player_hitbox.global_position.distance_to(hurtbox.global_position)
			var player_shape = player_hitbox.get_node_or_null("CollisionShape2D")
			var player_radius = 0.0
			if player_shape and player_shape.shape is CircleShape2D:
				player_radius = player_shape.shape.radius
			
			var total_radius = hurtbox_radius + player_radius
			
			# If they should overlap but don't, manually trigger the hit
			if distance < total_radius:
				_on_area_entered(player_hitbox)
	
	for area in overlapping_areas:
		_on_area_entered(area)

func _on_animation_finished() -> void:
	# Logic Requirement B: Turn off monitoring when attack animation finishes
	if animated_sprite.animation == "skeleton_attack":
		hurtbox.monitoring = false

func _on_area_entered(area: Area2D) -> void:
	# Logic Requirement C: Only process hits when monitoring is active
	# This is a safety check - monitoring should already be controlled by frame timing
	if not hurtbox.monitoring:
		return
	
	# The area should be a hitbox (player's or enemy's)
	# Find the player node by traversing up the tree
	# Structure: hitbox -> player_hitbox (Node2D) -> Player (CharacterBody2D)
	var node = area
	var player = null
	
	# Traverse up the tree to find the player
	while node:
		if node.is_in_group("player"):
			player = node
			break
		node = node.get_parent()
	
	# If we found a player, apply knockback and damage
	if player and player.has_method("take_knockback"):
		# Calculate knockback direction: from skeleton to player
		var knockback_direction = (player.global_position - skeleton.global_position).normalized()
		player.take_knockback(knockback_direction)
		# Deal damage to player
		if player.has_method("take_damage"):
			player.take_damage(skeleton.SKELETON_DAMAGE)
