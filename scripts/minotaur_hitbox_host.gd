extends Node2D

@onready var hitbox: Area2D = $hitbox
@onready var minotaur = get_parent()

func _ready() -> void:
	# Add hitbox to group so player's hurtbox can detect it
	hitbox.add_to_group("hitbox")
	
	# Connect to area_entered to detect when player's hurtbox enters
	hitbox.area_entered.connect(_on_area_entered)
	
	# Ensure monitoring is OFF by default (controlled by minotaur attack timing)
	hitbox.monitoring = false
	hitbox.monitorable = false

func _on_area_entered(area: Area2D) -> void:
	# Only process hits when monitoring is active (during attack)
	if not hitbox.monitoring:
		return
	
	# Check if the area is the player's hurtbox
	# Find the player node by traversing up the tree
	var node = area
	var player = null
	
	# Traverse up the tree to find the player
	while node:
		if node.is_in_group("player"):
			player = node
			break
		node = node.get_parent()
	
	# If we found a player, deal damage to player
	if player and player.has_method("take_damage"):
		# Deal damage to player (pass minotaur's position for knockback)
		player.take_damage(minotaur.MINOTAUR_DAMAGE, minotaur.global_position)
		print("Minotaur hitbox: Dealt ", minotaur.MINOTAUR_DAMAGE, " damage to player")

