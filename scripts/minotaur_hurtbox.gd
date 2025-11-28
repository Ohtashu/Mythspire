extends Node2D

@onready var hurtbox: Area2D = $hurtbox
@onready var minotaur = get_parent()

func _ready() -> void:
	# Ensure monitoring is ON by default (boss can always take damage from player)
	hurtbox.monitoring = true
	hurtbox.area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	# Only process hits when monitoring is active
	if not hurtbox.monitoring:
		return
	
	# Check if the area is a hitbox (player's hitbox)
	if not area.is_in_group("hitbox"):
		return
	
	# IMPORTANT: Check if this is the minotaur's own hitbox - if so, ignore it
	var node_check = area
	while node_check:
		if node_check == minotaur or node_check.get_parent() == minotaur:
			# This is the minotaur's own hitbox, don't process it
			return
		node_check = node_check.get_parent()
	
	# The area should be a hitbox (player's hitbox)
	# Find the player node by traversing up the tree
	var node = area
	var player = null
	
	# Traverse up the tree to find the player
	while node:
		if node.is_in_group("player"):
			player = node
			break
		node = node.get_parent()
	
	# If we found a player, deal damage to minotaur (boss receives damage)
	if player and minotaur.has_method("take_damage"):
		# Pass player's position for damage calculation (though minotaur has super armor)
		minotaur.take_damage(player.damage, player.global_position)

