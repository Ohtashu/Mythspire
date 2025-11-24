extends ColorRect

@onready var animation_player: AnimationPlayer = $AnimationPlayer

signal fade_in_completed
signal fade_out_completed

func _ready() -> void:
	# Make sure the ColorRect covers the entire screen
	# Set anchors to full screen
	anchors_preset = Control.PRESET_FULL_RECT
	# Start with black screen (fully opaque)
	color = Color(0, 0, 0, 1)
	
	# Connect animation signals
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

func fade_in() -> void:
	# Fade to black (opaque)
	if animation_player:
		animation_player.play("fade_in")
	else:
		# If no animation player, just set color directly
		color = Color(0, 0, 0, 1)
		fade_in_completed.emit()

func fade_out() -> void:
	# Fade from black to transparent
	if animation_player:
		animation_player.play("fade_out")
	else:
		# If no animation player, just set color directly
		color = Color(0, 0, 0, 0)
		fade_out_completed.emit()

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "fade_in":
		fade_in_completed.emit()
	elif anim_name == "fade_out":
		fade_out_completed.emit()

func change_scene_with_fade(scene_path: String) -> void:
	# Fade in (to black)
	fade_in()
	await fade_in_completed
	
	# Change scene
	get_tree().change_scene_to_file(scene_path)
	
	# Wait a frame for the new scene to load
	await get_tree().process_frame
	
	# Fade out (from black)
	fade_out()
