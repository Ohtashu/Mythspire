extends TextureProgressBar

@export var player: Player

func _ready() -> void:
	# Find player if not set via export
	if not player:
		player = get_tree().get_first_node_in_group("player")
	
	# Set up the progress bar
	if player:
		max_value = player.xp_to_next_level
		value = player.current_xp
		min_value = 0
		
		# Connect to player's XP changed signal
		if not player.xp_changed.is_connected(_on_xp_changed):
			player.xp_changed.connect(_on_xp_changed)
	else:
		print("EXP bar: Player not found!")

func _on_xp_changed(current_xp: int, xp_to_next: int) -> void:
	if player:
		max_value = xp_to_next
		value = current_xp

func _process(_delta: float) -> void:
	# Update the EXP bar to match player's current XP
	if player:
		max_value = player.xp_to_next_level
		value = player.current_xp
