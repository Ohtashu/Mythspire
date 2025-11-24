extends Node2D

func _ready() -> void:
	# Add the hitbox to the "hitbox" group so it can be detected by enemy hurtboxes
	$hitbox.add_to_group("hitbox")

