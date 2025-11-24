extends Control

@export var player: Player
@onready var health_bar: TextureProgressBar = $main_healthbar

func _ready() -> void:
	# Find player if not set via export
	if not player:
		player = get_tree().get_first_node_in_group("player")
	
	# Find health bar if not found
	if not health_bar:
		health_bar = get_node_or_null("main_healthbar")
	
	# Initialize health bar
	if player and health_bar:
		health_bar.max_value = player.max_health
		health_bar.value = player.current_health
		health_bar.min_value = 0
		
		# Connect to player's leveled up signal to update max health
		if not player.leveled_up.is_connected(_on_leveled_up):
			player.leveled_up.connect(_on_leveled_up)
		
		print("Health bar initialized: ", player.current_health, "/", player.max_health)
	else:
		if not player:
			print("Health bar: Player not found!")
		if not health_bar:
			print("Health bar: main_healthbar not found!")

func _on_leveled_up(_new_level: int, new_max_health: int, _new_damage: int, _new_defense: int) -> void:
	# Update max health when player levels up
	if health_bar:
		health_bar.max_value = new_max_health
		health_bar.value = player.current_health

func _process(_delta: float) -> void:
	# Update the health bar to match player's current health
	if player and health_bar:
		health_bar.max_value = player.max_health
		health_bar.value = player.current_health

