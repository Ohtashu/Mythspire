extends CanvasLayer

## UI Manager Script
## Handles boss health bar and victory screen

@export var boss_health_bar: TextureProgressBar = null
@onready var boss_warning_label: Label = get_node_or_null("BossWarningLabel")
var pause_menu: Control = null

func _ready() -> void:
	# Find boss health bar if not set in editor
	if not boss_health_bar:
		boss_health_bar = get_node_or_null("BossHealthBar")
	
	# Find boss warning label
	if not boss_warning_label:
		boss_warning_label = get_node_or_null("BossWarningLabel")
	
	# Find pause menu in the scene tree (Game scene)
	var game_root = get_tree().current_scene
	if game_root:
		# Try pause_menu_layer path first
		pause_menu = game_root.get_node_or_null("pause_menu_layer/pause_menu")
		# If not found, try direct path
		if not pause_menu:
			pause_menu = game_root.get_node_or_null("pause_menu")
	
	# Force hide boss health bar initially (even if left visible in editor)
	if boss_health_bar:
		boss_health_bar.visible = false
		boss_health_bar.max_value = 500
		boss_health_bar.value = 500
	
	# Force hide warning label initially (even if left visible in editor)
	if boss_warning_label:
		boss_warning_label.visible = false
		boss_warning_label.modulate.a = 1.0  # Reset alpha

func update_boss_health(current: int, max_hp: int) -> void:
	"""Update boss health bar with current and max HP"""
	if not boss_health_bar:
		push_warning("UI: BossHealthBar not found!")
		return
	
	# Make sure health bar is visible (will be on first call)
	if not boss_health_bar.visible:
		boss_health_bar.visible = true
	
	boss_health_bar.max_value = max_hp
	boss_health_bar.value = current
	print("UI: Boss health updated - ", current, "/", max_hp)

func show_boss_health_bar() -> void:
	"""Show the boss health bar"""
	if boss_health_bar:
		boss_health_bar.visible = true
		print("UI: Boss health bar shown")

func hide_boss_health_bar() -> void:
	"""Hide the boss health bar"""
	if boss_health_bar:
		boss_health_bar.visible = false
		print("UI: Boss health bar hidden")

func show_boss_warning() -> void:
	"""Show and flash the boss warning label"""
	if not boss_warning_label:
		push_warning("UI: BossWarningLabel not found!")
		return
	
	# Make label visible
	boss_warning_label.visible = true
	boss_warning_label.modulate.a = 1.0  # Ensure full opacity at start
	
	# Flash effect: fade in and out
	var tween = create_tween()
	tween.set_loops(6)  # Flash 3 times (in + out = 2 loops per flash)
	tween.tween_property(boss_warning_label, "modulate:a", 0.3, 0.3)
	tween.tween_property(boss_warning_label, "modulate:a", 1.0, 0.3)
	
	# Hide after flashing (3 seconds total)
	await tween.finished
	boss_warning_label.visible = false
	print("UI: Boss warning shown and hidden")

func show_victory_screen() -> void:
	"""Show victory screen using pause menu"""
	if not pause_menu:
		push_error("UI: PauseMenu not found! Cannot show victory screen.")
		return
	
	# Find the title label in pause menu (path: ContentContainer/pause_panel/TitleLabel)
	var title_label = pause_menu.get_node_or_null("ContentContainer/pause_panel/TitleLabel")
	if not title_label:
		# Try alternative path
		title_label = pause_menu.get_node_or_null("pause_panel/TitleLabel")
	
	if title_label:
		title_label.text = "YOU DEFEATED THE BEAST"
		print("UI: Victory title set")
	else:
		push_warning("UI: TitleLabel not found in pause menu!")
	
	# Show the pause menu
	pause_menu.visible = true
	
	# Pause the game
	get_tree().paused = true
	print("UI: Victory screen shown and game paused")

