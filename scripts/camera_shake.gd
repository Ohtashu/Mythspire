extends Camera2D

## Camera Shake Script
## Provides screen shake effects for combat feedback

var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_timer: float = 0.0
var original_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Store the original offset (should be (0, 0) or whatever is set in the editor)
	original_offset = offset

func _process(delta: float) -> void:
	if shake_timer > 0.0:
		# Apply random shake offset
		var shake_offset = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
		offset = original_offset + shake_offset
		
		# Decrease timer
		shake_timer -= delta
		
		# Gradually reduce intensity over time
		shake_intensity = lerp(0.0, shake_intensity, shake_timer / shake_duration)
		
		if shake_timer <= 0.0:
			# Shake finished, reset to original offset
			offset = original_offset
			shake_intensity = 0.0
			shake_duration = 0.0

func apply_shake(intensity: float, duration: float) -> void:
	"""Apply screen shake effect
	
	Args:
		intensity: Maximum shake offset in pixels
		duration: How long the shake lasts in seconds
	"""
	# If already shaking, add to existing shake (for multiple hits)
	if shake_timer > 0.0:
		# Use the maximum intensity
		shake_intensity = max(shake_intensity, intensity)
		# Extend duration if new duration is longer
		shake_duration = max(shake_duration, duration)
		shake_timer = shake_duration
	else:
		# Start new shake
		shake_intensity = intensity
		shake_duration = duration
		shake_timer = duration

