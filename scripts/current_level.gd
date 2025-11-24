extends Label

@export var player: Player

func _ready() -> void:
	# Find player if not set via export
	if not player:
		player = get_tree().get_first_node_in_group("player")
	
	# Set initial level display
	if player:
		text = str(player.level)
		
		# Connect to player's leveled up signal
		if not player.leveled_up.is_connected(_on_leveled_up):
			player.leveled_up.connect(_on_leveled_up)
	else:
		print("Level label: Player not found!")
		text = "1"

func _on_leveled_up(new_level: int, _new_max_health: int, _new_damage: int, _new_defense: int) -> void:
	text = str(new_level)

func _process(_delta: float) -> void:
	# Update the level display to match player's current level
	if player:
		text = str(player.level)
