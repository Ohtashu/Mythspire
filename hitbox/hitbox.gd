extends Area2D

# Universal hitbox script - used by both player and enemies
# This ensures the hitbox is monitorable and in the correct group

func _ready() -> void:
	# Make sure the hitbox is monitorable so it can be detected by hurtboxes
	monitorable = true
	# Add to "hitbox" group so it can be detected by enemy hurtboxes
	add_to_group("hitbox")
