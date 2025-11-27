extends Node2D

@onready var player = get_parent()
@onready var hurtbox = $hurtbox

func _ready() -> void:
	# Connect to hurtbox's area_entered signal to detect when player hits enemies
	hurtbox.area_entered.connect(_on_area_entered)

func _process(_delta: float) -> void:
	if player and hurtbox:
		var dir = player.last_direction
		match dir:
			"right":
				hurtbox.position = Vector2(15, 0)
				hurtbox.rotation = PI / 2  # Landscape mode
			"left":
				hurtbox.position = Vector2(-15, 0)
				hurtbox.rotation = PI / 2
			"up":
				hurtbox.position = Vector2(0, -15)
				hurtbox.rotation = 0  # Portrait mode
			"down":
				hurtbox.position = Vector2(0, 15)
				hurtbox.rotation = 0
			"up_right":
				hurtbox.position = Vector2(10, -10)
				hurtbox.rotation = 0
			"up_left":
				hurtbox.position = Vector2(-10, -10)
				hurtbox.rotation = 0
			"down_right":
				hurtbox.position = Vector2(10, 10)
				hurtbox.rotation = 0
			"down_left":
				hurtbox.position = Vector2(-10, 10)
				hurtbox.rotation = 0
			_:
				hurtbox.position = Vector2(0, 15)
				hurtbox.rotation = 0

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
