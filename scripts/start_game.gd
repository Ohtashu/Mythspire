extends TextureButton

@onready var menu_hover: AudioStreamPlayer2D = get_node_or_null("../menu_hover")
@onready var button_click: AudioStreamPlayer2D = get_node_or_null("../button_click")

func _ready() -> void:
	# Connect button signals
	pressed.connect(_on_start_game_pressed)
	mouse_entered.connect(_on_mouse_entered)

func _on_mouse_entered() -> void:
	# Play hover sound
	if menu_hover:
		menu_hover.play()

func _on_start_game_pressed() -> void:
	# Play click sound
	if button_click:
		button_click.play()
	
	# Load the fade transition scene
	var fade_scene = preload("res://scene/face_trancision.tscn")
	var fade_transition = fade_scene.instantiate()
	
	# Add to scene tree (as a child of root so it persists across scene changes)
	get_tree().root.add_child(fade_transition)
	
	# Make sure it's on top (z-index)
	fade_transition.z_index = 1000
	
	# Change scene with fade transition
	fade_transition.change_scene_with_fade("res://scene/game.tscn")
