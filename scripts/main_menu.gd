extends Control

@onready var menu_background_music: AudioStreamPlayer2D = $menu_background_music

func _ready() -> void:
	# Start background music
	if menu_background_music:
		# Enable looping for background music
		if menu_background_music.stream:
			menu_background_music.stream.loop = true
		menu_background_music.play()

