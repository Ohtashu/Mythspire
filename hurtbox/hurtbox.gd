extends Area2D

# Universal hurtbox script - used by both player and enemies
# This script only handles basic setup. Combat logic is handled by parent controllers:
# - Player's hurtbox: controlled by player.gd and player_interaction_host.gd
# - Skeleton's hurtbox: controlled by skeleton_hurtbox.gd (direct Area2D, not using this scene)

func _ready() -> void:
	# Ensure monitorable is set correctly (hurtbox should be detectable by other areas)
	# Note: This can be overridden by parent controllers if needed
	monitorable = true
