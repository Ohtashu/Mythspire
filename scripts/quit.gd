extends TextureButton

@onready var menu_hover: AudioStreamPlayer2D = get_node_or_null("../menu_hover")
@onready var button_click: AudioStreamPlayer2D = get_node_or_null("../button_click")

func _ready() -> void:
	# Connect button signals
	pressed.connect(_on_quit_pressed)
	mouse_entered.connect(_on_mouse_entered)

func _on_mouse_entered() -> void:
	# Play hover sound
	if menu_hover:
		menu_hover.play()

func _on_quit_pressed() -> void:
	# Play click sound
	if button_click:
		button_click.play()
	
	# Quit the game
	get_tree().quit()
