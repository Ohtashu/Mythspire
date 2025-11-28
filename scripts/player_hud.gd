extends Control

## Player HUD Manager Script
## Manages the player HUD display with profile button and stats panel

# Node references using @onready
@onready var stats_panel = $CanvasLayer/StatsPanel
@onready var stats_label = $CanvasLayer/StatsPanel/StatsLabel

func _ready() -> void:
	# Find profile button and connect signal
	var profile_button = get_node_or_null("CanvasLayer/ProfileButton")
	if profile_button:
		if not profile_button.pressed.is_connected(_on_profile_button_pressed):
			profile_button.pressed.connect(_on_profile_button_pressed)
		print("PlayerHUD: Profile button signal connected")
	else:
		push_warning("PlayerHUD: ProfileButton not found!")
	
	# Initialize stats panel visibility
	if stats_panel:
		stats_panel.visible = false
		print("PlayerHUD: StatsPanel initialized and hidden")
	else:
		push_warning("PlayerHUD: StatsPanel not found!")
	
	# Initialize stats label
	if stats_label:
		stats_label.text = ""
		print("PlayerHUD: StatsLabel initialized")
	else:
		push_warning("PlayerHUD: StatsLabel not found!")

func _on_profile_button_pressed() -> void:
	"""Toggle stats panel visibility when profile button is pressed"""
	if not stats_panel:
		push_warning("PlayerHUD: StatsPanel not found!")
		return
	
	# Toggle visibility
	stats_panel.visible = not stats_panel.visible
	print("PlayerHUD: StatsPanel visibility toggled to ", stats_panel.visible)
	
	# Update stats display if panel becomes visible
	if stats_panel.visible:
		update_stats()

func update_stats() -> void:
	"""Update the stats label with current player information"""
	if not stats_label:
		push_warning("PlayerHUD: StatsLabel not found!")
		return
	
	# Get player reference from GameManager or search
	var player = GameManager.player_ref
	if not player:
		player = get_tree().get_first_node_in_group("player")
	
	if not player:
		stats_label.text = "No player found"
		print("PlayerHUD: Warning - Player not found!")
		return
	
	# Format stats text with player information
	var stats_text = ""
	
	if "level" in player:
		stats_text += "Level: %d\n" % player.level
	
	if "current_health" in player and "max_health" in player:
		stats_text += "Health: %d/%d\n" % [player.current_health, player.max_health]
	
	if "damage" in player:
		stats_text += "Damage: %d\n" % player.damage
	
	if "defense" in player:
		stats_text += "Defense: %d\n" % player.defense
	
	if "current_xp" in player:
		stats_text += "XP: %d\n" % player.current_xp
	
	# Update the label text
	stats_label.text = stats_text
	print("PlayerHUD: Stats updated")
