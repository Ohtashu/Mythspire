extends TextureProgressBar

@export var player: Player

func _ready() -> void:
	# If player is not set via export, try to find it
	if not player:
		player = get_tree().get_first_node_in_group("player")
	
	# Set up the progress bar
	if player:
		max_value = player.max_health
		value = player.current_health
		min_value = 0
	else:
		print("Health progress bar: Player not found!")

func _process(_delta: float) -> void:
	# Update the health bar to match player's current health
	if player:
		value = player.current_health
