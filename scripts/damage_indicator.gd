extends Node2D

@onready var label: Label = $Label

const FLOAT_DISTANCE: float = 40.0  # How far up it floats
const ANIMATION_DURATION: float = 0.8  # Total animation duration
const POP_SCALE: float = 1.3  # Scale up to this size for pop effect

var damage_amount: int = 0  # Store damage amount until label is ready

func _ready() -> void:
	# Set the label text if amount was set before _ready()
	if label and damage_amount > 0:
		label.text = str(damage_amount)
	# Start the animation
	animate()

func set_amount(value: int) -> void:
	damage_amount = value
	# If label is already ready, set it immediately
	if label:
		label.text = str(value)

func animate() -> void:
	# Create a Tween for the animation
	var tween = create_tween()
	tween.set_parallel(true)  # Allow multiple properties to animate simultaneously
	
	# Move upwards
	var start_pos = position
	var end_pos = start_pos + Vector2(0, -FLOAT_DISTANCE)
	tween.tween_property(self, "position", end_pos, ANIMATION_DURATION)
	
	# Scale animation (pop effect)
	var start_scale = Vector2(0.5, 0.5)  # Start small
	var pop_scale = Vector2(POP_SCALE, POP_SCALE)  # Pop to larger
	var end_scale = Vector2(1.0, 1.0)  # End at normal size
	
	scale = start_scale
	tween.tween_property(self, "scale", pop_scale, ANIMATION_DURATION * 0.3)  # Pop up quickly
	tween.tween_property(self, "scale", end_scale, ANIMATION_DURATION * 0.7).set_delay(ANIMATION_DURATION * 0.3)  # Scale down slower
	
	# Fade out
	if label:
		var start_modulate = label.modulate
		var end_modulate = Color(start_modulate.r, start_modulate.g, start_modulate.b, 0.0)
		tween.tween_property(label, "modulate", end_modulate, ANIMATION_DURATION).set_delay(ANIMATION_DURATION * 0.2)  # Start fading after 20% of duration
	
	# Clean up after animation
	tween.tween_callback(queue_free).set_delay(ANIMATION_DURATION)

