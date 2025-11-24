extends Control

## Pause Menu Root Script
## Handles showing/hiding the pause menu and toggling game pause state

func _ready() -> void:
	# Set process mode to ALWAYS so this can receive input even when the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Ensure the menu is hidden initially
	visible = false

func _input(event: InputEvent) -> void:
	# Check for Escape key (ui_cancel action)
	if event.is_action_pressed("ui_cancel"):
		print("PauseMenu: ESC key pressed!")
		# Toggle menu visibility
		visible = not visible
		print("PauseMenu: Visible = ", visible)
		
		# Toggle pause state to match visibility (Pause if showing, Unpause if hiding)
		get_tree().paused = visible
		print("PauseMenu: Game paused = ", get_tree().paused)
