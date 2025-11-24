extends Control

## Player Profile UI Manager
## Connects all UI elements to the player's stats and leveling system
## Implements hover previews, stat upgrades, cost scaling, and immediate stat application

@onready var player: Player = get_tree().get_first_node_in_group("player")

# UI References - Level and EXP
@onready var level_value: Label = $ContentContainer/player_stats/level_value
@onready var exp_progressbar: TextureProgressBar = $ContentContainer/player_stats/TextureProgressBar
@onready var current_exp: Label = $ContentContainer/player_stats/current_exp
@onready var current_points: Label = $ContentContainer/player_stats/current_points  # The "0 Points" label

# UI References - Stat Progressbars
@onready var strength_progressbar: TextureProgressBar = $ContentContainer/player_boost_stats/str/strenght_progressbar
@onready var dexterity_progressbar: TextureProgressBar = $ContentContainer/player_boost_stats/dex/dexterity_progressbar
@onready var vitality_progressbar: TextureProgressBar = $ContentContainer/player_boost_stats/vitality/vitality_progressbar

# UI References - Upgrade Buttons (the "+" buttons)
@onready var str_plus: TextureButton = $ContentContainer/player_boost_stats/str/upgrade_str
@onready var dex_plus: TextureButton = $ContentContainer/player_boost_stats/dex/upgrade_dex
@onready var vit_plus: TextureButton = $ContentContainer/player_boost_stats/vitality/upgrade_vit

# UI References - Cost Labels (if they exist, otherwise we'll create them or use existing labels)
var str_spend_point: Label = null
var dex_spend_point: Label = null
var vit_spend_point: Label = null

# UI References - Output Stat Labels
@onready var damage_value: Label = $ContentContainer/player_attributes/attack_label/attack_damage_display
@onready var health_value: Label = $ContentContainer/player_attributes/hp_label/hp_value
@onready var def_value: Label = $ContentContainer/player_attributes/defence_label/defence_value
@onready var crit_value: Label = $ContentContainer/player_attributes/crit_label/crit_value  # Crit Damage (multiplier)
@onready var luk_value: Label = $ContentContainer/player_attributes/luk_label/luk_value  # Crit Chance (%)
var speed_value: Label = null  # May not exist in scene yet

# Sound effect reference
@onready var upgrade_button_sound: AudioStreamPlayer2D = $upgrade_button

# Preview state tracking
var is_previewing: bool = false
var preview_stat: String = ""  # "strength", "dexterity", or "vitality"

func _ready() -> void:
	# Ensure this Control is visible
	visible = true
	
	# Set process mode to WHEN_PAUSED so this UI can process input when game is paused
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	# Set high z_index to ensure it's on top
	z_index = 100
	
	# Center the stats panel content on the viewport
	center_popup()
	
	# Find player if not found
	if not player:
		player = get_tree().get_first_node_in_group("player")
	
	if not player:
		push_error("PlayerProfile: Player not found!")
		return
	
	# Try to find cost labels (they may not exist yet)
	str_spend_point = get_node_or_null("ContentContainer/player_boost_stats/str/spend_point")
	dex_spend_point = get_node_or_null("ContentContainer/player_boost_stats/dex/spend_point")
	vit_spend_point = get_node_or_null("ContentContainer/player_boost_stats/vitality/spend_point")
	
	# Try to find speed_value label
	speed_value = get_node_or_null("ContentContainer/player_attributes/speed_label/speed_value")
	
	# Connect player signals
	if not player.xp_changed.is_connected(_on_xp_changed):
		player.xp_changed.connect(_on_xp_changed)
	if not player.leveled_up.is_connected(_on_leveled_up):
		player.leveled_up.connect(_on_leveled_up)
	if not player.stat_points_changed.is_connected(_on_stat_points_changed):
		player.stat_points_changed.connect(_on_stat_points_changed)
	if not player.stat_upgraded.is_connected(_on_stat_upgraded):
		player.stat_upgraded.connect(_on_stat_upgraded)
	
	# Connect button press signals
	if str_plus:
		str_plus.pressed.connect(_on_strength_button_pressed)
		# Connect hover signals for preview
		if not str_plus.mouse_entered.is_connected(_on_str_mouse_entered):
			str_plus.mouse_entered.connect(_on_str_mouse_entered)
		if not str_plus.mouse_exited.is_connected(_on_str_mouse_exited):
			str_plus.mouse_exited.connect(_on_str_mouse_exited)
	
	if dex_plus:
		dex_plus.pressed.connect(_on_dexterity_button_pressed)
		# Connect hover signals for preview
		if not dex_plus.mouse_entered.is_connected(_on_dex_mouse_entered):
			dex_plus.mouse_entered.connect(_on_dex_mouse_entered)
		if not dex_plus.mouse_exited.is_connected(_on_dex_mouse_exited):
			dex_plus.mouse_exited.connect(_on_dex_mouse_exited)
	
	if vit_plus:
		vit_plus.pressed.connect(_on_vitality_button_pressed)
		# Connect hover signals for preview
		if not vit_plus.mouse_entered.is_connected(_on_vit_mouse_entered):
			vit_plus.mouse_entered.connect(_on_vit_mouse_entered)
		if not vit_plus.mouse_exited.is_connected(_on_vit_mouse_exited):
			vit_plus.mouse_exited.connect(_on_vit_mouse_exited)
	
	# Initialize UI with current player values
	update_all_ui()

func _input(event: InputEvent) -> void:
	# Close profile with ESC key
	if event.is_action_pressed("ui_cancel"):
		close_profile()

func close_profile() -> void:
	# Reset preview state
	reset_preview()
	
	# Unpause the game
	var tree = get_tree()
	if tree:
		tree.paused = false
	
	# Close and remove this window
	queue_free()

func update_all_ui() -> void:
	if not player:
		return
	
	# Update level display
	if level_value:
		level_value.text = str(player.level)
	
	# Update EXP progressbar
	if exp_progressbar:
		exp_progressbar.max_value = player.xp_to_next_level
		exp_progressbar.value = player.current_xp
		exp_progressbar.min_value = 0
	
	# Update current_exp label (e.g., "500exp to level 10")
	if current_exp:
		var exp_needed = player.xp_to_next_level - player.current_xp
		var next_level = player.level + 1
		if player.level >= player.MAX_LEVEL:
			current_exp.text = "MAX LEVEL"
		else:
			current_exp.text = str(exp_needed) + "exp to level " + str(next_level)
	
	# Update stat points display
	if current_points:
		current_points.text = str(player.stat_points) + " Points"
	
	# Update stat progressbars (cap at 50)
	if strength_progressbar:
		strength_progressbar.max_value = player.MAX_STAT_LEVEL  # 50
		strength_progressbar.value = player.strength
	
	if dexterity_progressbar:
		dexterity_progressbar.max_value = player.MAX_STAT_LEVEL  # 50
		dexterity_progressbar.value = player.dexterity
	
	if vitality_progressbar:
		vitality_progressbar.max_value = player.MAX_STAT_LEVEL  # 50
		vitality_progressbar.value = player.vitality
	
	# Update cost labels
	update_cost_labels()
	
	# Update output stat labels
	update_output_stats()
	
	# Update button states (disable if maxed or no points)
	update_button_states()

func update_cost_labels() -> void:
	if not player:
		return
	
	# Update STR cost label
	if str_spend_point:
		var cost = player.get_stat_upgrade_cost(player.strength)
		str_spend_point.text = str(cost)
	
	# Update DEX cost label
	if dex_spend_point:
		var cost = player.get_stat_upgrade_cost(player.dexterity)
		dex_spend_point.text = str(cost)
	
	# Update VIT cost label
	if vit_spend_point:
		var cost = player.get_stat_upgrade_cost(player.vitality)
		vit_spend_point.text = str(cost)

func update_output_stats() -> void:
	if not player:
		return
	
	# Update damage (base_damage + STR * 2)
	if damage_value:
		damage_value.text = str(player.damage)
	
	# Update health (base_max_health + VIT * 10)
	if health_value:
		health_value.text = str(player.max_health)
	
	# Update defense (base_defense + VIT)
	if def_value:
		def_value.text = str(player.defense)
	
	# Update crit damage (base 2.0x + STR * 0.1)
	if crit_value:
		crit_value.text = "%.1fx" % player.crit_damage
	
	# Update crit chance (DEX * 1%) - shown in LUK label
	if luk_value:
		var crit_chance = player.get_crit_chance()
		luk_value.text = str(crit_chance) + "%"
	
	# Update speed (BASE_SPEED + DEX)
	if speed_value:
		var speed = player.get_movement_speed()
		speed_value.text = str(int(speed))

func update_button_states() -> void:
	if not player:
		return
	
	# Strength button - disable if maxed, no points, or can't afford cost
	if str_plus:
		var cost = player.get_stat_upgrade_cost(player.strength)
		str_plus.disabled = (player.strength >= player.MAX_STAT_LEVEL or player.stat_points < cost)
	
	# Dexterity button
	if dex_plus:
		var cost = player.get_stat_upgrade_cost(player.dexterity)
		dex_plus.disabled = (player.dexterity >= player.MAX_STAT_LEVEL or player.stat_points < cost)
	
	# Vitality button
	if vit_plus:
		var cost = player.get_stat_upgrade_cost(player.vitality)
		vit_plus.disabled = (player.vitality >= player.MAX_STAT_LEVEL or player.stat_points < cost)

# Helper function to update preview labels with color formatting
func update_preview_label(label: Label, current: int, new: int) -> void:
	if not label:
		return
	
	if current == new:
		# Unchanged - show just the number in white
		label.text = str(current)
		label.modulate = Color.WHITE
	else:
		# Changed - show "current -> new" with color
		label.text = str(current) + " -> " + str(new)
		if new > current:
			# Increase - green
			label.modulate = Color.GREEN
		else:
			# Decrease - red (shouldn't happen with upgrades, but handle it)
			label.modulate = Color.RED

# Calculate preview stats if a stat were upgraded
func calculate_preview_stats(stat_name: String) -> Dictionary:
	if not player:
		return {}
	
	var preview = {}
	
	# Get current stat values
	var current_str = player.strength
	var current_dex = player.dexterity
	var current_vit = player.vitality
	
	# Simulate upgrade
	match stat_name:
		"strength":
			current_str += 1
		"dexterity":
			current_dex += 1
		"vitality":
			current_vit += 1
	
	# Calculate preview derived stats
	# 1 STR = +2 Physical Damage AND +0.1 Crit Damage
	var preview_damage = player.base_damage + (current_str * 2)
	var preview_crit_damage = 2.0 + (current_str * 0.1)  # Base 2.0x + 0.1x per STR
	
	# 1 VIT = +10 Max Health and +1 Defense
	var preview_max_health = player.base_max_health + (current_vit * 10)
	var preview_defense = player.base_defense + current_vit
	
	# 1 DEX = +1% Crit Chance AND +1 Movement Speed
	var preview_crit_chance = current_dex * 1.0
	var preview_speed = player.BASE_SPEED + current_dex
	
	preview["damage"] = preview_damage
	preview["max_health"] = preview_max_health
	preview["defense"] = preview_defense
	preview["crit_chance"] = preview_crit_chance
	preview["crit_damage"] = preview_crit_damage
	preview["speed"] = preview_speed
	
	return preview

# Hover preview functions
func _on_str_mouse_entered() -> void:
	if not player or player.strength >= player.MAX_STAT_LEVEL:
		return
	
	is_previewing = true
	preview_stat = "strength"
	show_preview("strength")

func _on_str_mouse_exited() -> void:
	reset_preview()

func _on_dex_mouse_entered() -> void:
	if not player or player.dexterity >= player.MAX_STAT_LEVEL:
		return
	
	is_previewing = true
	preview_stat = "dexterity"
	show_preview("dexterity")

func _on_dex_mouse_exited() -> void:
	reset_preview()

func _on_vit_mouse_entered() -> void:
	if not player or player.vitality >= player.MAX_STAT_LEVEL:
		return
	
	is_previewing = true
	preview_stat = "vitality"
	show_preview("vitality")

func _on_vit_mouse_exited() -> void:
	reset_preview()

func show_preview(stat_name: String) -> void:
	if not player:
		return
	
	var preview = calculate_preview_stats(stat_name)
	
	# Update output labels with preview values
	if damage_value:
		update_preview_label(damage_value, player.damage, preview["damage"])
	
	if health_value:
		update_preview_label(health_value, player.max_health, preview["max_health"])
	
	if def_value:
		update_preview_label(def_value, player.defense, preview["defense"])
	
	# Crit damage (changes with STR)
	if crit_value:
		var current_crit_damage = player.crit_damage
		var new_crit_damage = preview["crit_damage"]
		if abs(current_crit_damage - new_crit_damage) > 0.01:  # Float comparison with tolerance
			crit_value.text = "%.1fx -> %.1fx" % [current_crit_damage, new_crit_damage]
			crit_value.modulate = Color.GREEN
		else:
			crit_value.text = "%.1fx" % current_crit_damage
			crit_value.modulate = Color.WHITE
	
	# Crit chance (shown in LUK label) - changes with DEX
	if luk_value:
		var current_crit_chance = player.get_crit_chance()
		var new_crit_chance = preview["crit_chance"]
		if current_crit_chance != new_crit_chance:
			luk_value.text = str(current_crit_chance) + "% -> " + str(new_crit_chance) + "%"
			luk_value.modulate = Color.GREEN
		else:
			luk_value.text = str(current_crit_chance) + "%"
			luk_value.modulate = Color.WHITE
	
	if speed_value:
		var current_speed = player.get_movement_speed()
		var new_speed = preview["speed"]
		if current_speed != new_speed:
			speed_value.text = str(int(current_speed)) + " -> " + str(int(new_speed))
			speed_value.modulate = Color.GREEN
		else:
			speed_value.text = str(int(current_speed))
			speed_value.modulate = Color.WHITE

func reset_preview() -> void:
	if not is_previewing:
		return
	
	is_previewing = false
	preview_stat = ""
	
	# Reset all labels to show current actual values in white
	update_output_stats()
	
	# Reset all label colors to white
	if damage_value:
		damage_value.modulate = Color.WHITE
	if health_value:
		health_value.modulate = Color.WHITE
	if def_value:
		def_value.modulate = Color.WHITE
	if crit_value:
		crit_value.modulate = Color.WHITE
	if luk_value:
		luk_value.modulate = Color.WHITE
	if speed_value:
		speed_value.modulate = Color.WHITE

# Signal handlers
func _on_xp_changed(current_xp: int, xp_to_next: int) -> void:
	# Update EXP progressbar
	if exp_progressbar:
		exp_progressbar.max_value = xp_to_next
		exp_progressbar.value = current_xp
	
	# Update current_exp label
	if current_exp:
		var exp_needed = xp_to_next - current_xp
		var next_level = player.level + 1
		if player.level >= player.MAX_LEVEL:
			current_exp.text = "MAX LEVEL"
		else:
			current_exp.text = str(exp_needed) + "exp to level " + str(next_level)

func _on_leveled_up(new_level: int, _new_max_health: int, _new_damage: int, _new_defense: int) -> void:
	# Update level display
	if level_value:
		level_value.text = str(new_level)
	
	# Update current_exp label (level changed, so exp needed changed)
	if current_exp:
		var exp_needed = player.xp_to_next_level - player.current_xp
		var next_level = new_level + 1
		if new_level >= player.MAX_LEVEL:
			current_exp.text = "MAX LEVEL"
		else:
			current_exp.text = str(exp_needed) + "exp to level " + str(next_level)
	
	# Update all UI to reflect new stats
	update_all_ui()

func _on_stat_points_changed(new_points: int) -> void:
	# Update stat points display
	if current_points:
		current_points.text = str(new_points) + " Points"
	
	# Update button states and cost labels
	update_button_states()
	update_cost_labels()

func _on_stat_upgraded(stat_name: String, new_level: int) -> void:
	# Update the corresponding progressbar
	match stat_name:
		"strength":
			if strength_progressbar:
				strength_progressbar.value = new_level
		"dexterity":
			if dexterity_progressbar:
				dexterity_progressbar.value = new_level
		"vitality":
			if vitality_progressbar:
				vitality_progressbar.value = new_level
	
	# Update all output stats (since stats affect multiple derived values)
	update_output_stats()
	
	# Update button states and cost labels
	update_button_states()
	update_cost_labels()
	
	# Reset preview if we were previewing this stat
	if is_previewing and preview_stat == stat_name:
		reset_preview()

# Button press handlers
func _on_strength_button_pressed() -> void:
	if not player:
		return
	
	# Check if player has enough points and stat is under cap
	var cost = player.get_stat_upgrade_cost(player.strength)
	if player.stat_points < cost or player.strength >= player.MAX_STAT_LEVEL:
		return
	
	# Play upgrade sound effect
	if upgrade_button_sound:
		upgrade_button_sound.play()
	
	# Upgrade the stat (this will immediately apply stat formulas)
	if player.upgrade_strength():
		# UI will update via signals, but refresh everything to be safe
		update_all_ui()
		# Reset preview if active
		if is_previewing:
			reset_preview()

func _on_dexterity_button_pressed() -> void:
	if not player:
		return
	
	# Check if player has enough points and stat is under cap
	var cost = player.get_stat_upgrade_cost(player.dexterity)
	if player.stat_points < cost or player.dexterity >= player.MAX_STAT_LEVEL:
		return
	
	# Play upgrade sound effect
	if upgrade_button_sound:
		upgrade_button_sound.play()
	
	# Upgrade the stat (this will immediately apply stat formulas)
	if player.upgrade_dexterity():
		# UI will update via signals, but refresh everything to be safe
		update_all_ui()
		# Reset preview if active
		if is_previewing:
			reset_preview()

func _on_vitality_button_pressed() -> void:
	if not player:
		return
	
	# Check if player has enough points and stat is under cap
	var cost = player.get_stat_upgrade_cost(player.vitality)
	if player.stat_points < cost or player.vitality >= player.MAX_STAT_LEVEL:
		return
	
	# Play upgrade sound effect
	if upgrade_button_sound:
		upgrade_button_sound.play()
	
	# Upgrade the stat (this will immediately apply stat formulas)
	if player.upgrade_vitality():
		# UI will update via signals, but refresh everything to be safe
		update_all_ui()
		# Reset preview if active
		if is_previewing:
			reset_preview()

func center_popup() -> void:
	# Wait for the next frame to ensure viewport is ready
	await get_tree().process_frame
	
	# ContentContainer is already centered using anchors (preset 8 = center)
	# The anchors will automatically center it on the screen
	# No additional positioning needed - the anchors handle centering
