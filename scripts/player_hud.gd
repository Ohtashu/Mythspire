extends CanvasLayer

## Player HUD Manager Script
## Manages the player HUD display with boss UI elements

# Node references using @onready
@onready var boss_warning_label = $BossWarningLabel
@onready var boss_health_bar = $BossHealthBar

func _ready() -> void:
	print("PlayerHUD: Initialized")
	
	# Ensure boss UI elements are hidden initially
	if boss_warning_label:
		boss_warning_label.visible = false
	if boss_health_bar:
		boss_health_bar.visible = false

# ===== BOSS FIGHT UI FUNCTIONS =====

func show_boss_warning() -> void:
	"""Flash the boss warning label"""
	if not boss_warning_label:
		push_warning("PlayerHUD: BossWarningLabel not found!")
		return
	
	boss_warning_label.visible = true
	
	# Create flashing tween animation
	var tween = create_tween()
	tween.set_loops(6)  # Flash 6 times
	tween.tween_property(boss_warning_label, "modulate:a", 0.3, 0.3)
	tween.tween_property(boss_warning_label, "modulate:a", 1.0, 0.3)
	
	# Hide after animation completes
	await tween.finished
	boss_warning_label.visible = false
	print("PlayerHUD: Boss warning displayed")

func update_boss_health(current_hp: int, max_hp: int) -> void:
	"""Update boss health bar and make it visible"""
	if not boss_health_bar:
		push_warning("PlayerHUD: BossHealthBar not found!")
		return
	
	# Make health bar visible if it's not already
	if not boss_health_bar.visible:
		boss_health_bar.visible = true
		print("PlayerHUD: Boss health bar now visible")
	
	# Update health bar values
	boss_health_bar.max_value = max_hp
	boss_health_bar.value = current_hp
	
	print("PlayerHUD: Boss health updated - ", current_hp, "/", max_hp)

func hide_boss_health_bar() -> void:
	"""Hide the boss health bar"""
	if not boss_health_bar:
		push_warning("PlayerHUD: BossHealthBar not found!")
		return
	
	boss_health_bar.visible = false
	print("PlayerHUD: Boss health bar hidden")
