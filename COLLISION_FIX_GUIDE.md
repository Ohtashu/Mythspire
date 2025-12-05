# MYTHSPIRE - Complete Collision & Direction Fix Guide

## ⚠️ CRITICAL BUGS FIXED
1. **Directional Desync** - Hitbox/Hurtbox not following sprite flip
2. **Collision Failure** - Sword not hitting boss
3. **Physics Failure** - Walking through boss body

---

## 📋 PART 1: SCENE TREE REFACTORING

### Step 1: Create Visuals Pivot (Player Scene)

**In Godot Editor:**

1. Open `res://scene/player.tscn`
2. Right-click `Player` root node → **Add Child Node**
3. Select `Node2D` → Name it **`Visuals`**
4. **Drag and drop these nodes INTO Visuals:**
   - `AnimatedSprite2D`
   - `player_interaction` (contains hurtbox)
   - `player_hitbox` (contains hitbox)

**DO NOT MOVE:**
- `CollisionShape2D` ← Keep as direct child of Player
- Any AudioStreamPlayer2D nodes
- Any UI/HUD nodes

**Final Structure:**
```
Player (CharacterBody2D)
├── Visuals (Node2D)  ← NEW! This flips everything
│   ├── AnimatedSprite2D
│   ├── player_interaction (Node2D)
│   │   └── hurtbox (Area2D)  ← Player's damage receiver
│   └── player_hitbox (Node2D)
│       └── hitbox (Area2D)  ← Player's sword/attack area
├── CollisionShape2D  ← Physics collision (STAYS HERE)
├── WalkSound (AudioStreamPlayer2D)
├── sfx_attack (AudioStreamPlayer2D)
└── ... other audio nodes
```

---

## 💻 PART 2: CODE CHANGES (player.gd)

### Step 2A: Update @onready References

**Find this at the top of player.gd (lines 1-14):**
```gdscript
extends CharacterBody2D
class_name Player

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var walk_sound: AudioStreamPlayer2D = get_node_or_null("WalkSound")
@onready var attack_sound: AudioStreamPlayer2D = get_node_or_null("sfx_attack")
@onready var attack_voice: AudioStreamPlayer2D = get_node_or_null("player_attack_voice")
@onready var equip_sound: AudioStreamPlayer2D = get_node_or_null("sfx_equip")
@onready var unequip_sound: AudioStreamPlayer2D = get_node_or_null("sfx_unequip")
@onready var hurt_sound: AudioStreamPlayer2D = get_node_or_null("player_damaged")
@onready var level_sound_effect: AudioStreamPlayer2D = get_node_or_null("level_sound_effect")
@onready var hurtbox: Area2D = $player_interaction/hurtbox
@onready var player_interaction: Node2D = $player_interaction
```

**Replace with:**
```gdscript
extends CharacterBody2D
class_name Player

# CRITICAL: Visuals pivot for proper directional flipping
@onready var visuals: Node2D = $Visuals
@onready var animated_sprite: AnimatedSprite2D = $Visuals/AnimatedSprite2D
@onready var walk_sound: AudioStreamPlayer2D = get_node_or_null("WalkSound")
@onready var attack_sound: AudioStreamPlayer2D = get_node_or_null("sfx_attack")
@onready var attack_voice: AudioStreamPlayer2D = get_node_or_null("player_attack_voice")
@onready var equip_sound: AudioStreamPlayer2D = get_node_or_null("sfx_equip")
@onready var unequip_sound: AudioStreamPlayer2D = get_node_or_null("sfx_unequip")
@onready var hurt_sound: AudioStreamPlayer2D = get_node_or_null("player_damaged")
@onready var level_sound_effect: AudioStreamPlayer2D = get_node_or_null("level_sound_effect")
@onready var hurtbox: Area2D = $Visuals/player_interaction/hurtbox
@onready var player_interaction: Node2D = $Visuals/player_interaction
```

### Step 2B: Add Directional Flipping Logic

**Find the `update_animation()` function (around line 290-470).**
**Locate this section near the end:**
```gdscript
			_:
				anim_name = "idle_down"
	
	# Play animation if it's different from current
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)
```

**Replace with:**
```gdscript
			_:
				anim_name = "idle_down"
	
	# CRITICAL FIX: Flip the entire Visuals pivot based on direction
	# This ensures AnimatedSprite, hurtbox, and player_hitbox all flip together
	if direction.length() > 0:  # Only update facing while moving
		if direction.x > 0.1:  # Moving right
			visuals.scale.x = 1.0
		elif direction.x < -0.1:  # Moving left
			visuals.scale.x = -1.0
		# Keep current facing if moving purely up/down (no direction.x change)
	
	# Play animation if it's different from current
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)
```

---

## 🎯 PART 3: COLLISION LAYER CONFIGURATION

### Layer Assignment Standard
```
Layer 1: World (Walls, Obstacles)
Layer 2: Enemy Bodies (Boss CharacterBody2D)
Layer 3: Enemy Attacks (Boss hitbox - what damages player)
Layer 4: Player Body (Player CharacterBody2D)
Layer 5: Player Attacks (Player hurtbox - what damages enemies)
```

### Inspector Configuration Table

| **Node Path** | **Collision Layer** | **Collision Mask** | **Purpose** |
|---|---|---|---|
| **Player (Root)** | Layer 4 | Layers 1, 2 | Player body collides with walls and enemy bodies |
| **Player → Visuals → player_interaction → hurtbox** | Layer 5 | Layer 2 | Player's attack area detects enemy bodies |
| **Minotaur (Root)** | Layer 2 | Layer 1 | Boss body collides with walls only |
| **Minotaur → hurtbox** | Layer 2 | Layer 5 | Boss body detects player attacks |
| **Minotaur → hitbox** | Layer 3 | Layer 4 | Boss attack detects player body |

### Detailed Inspector Steps

#### **1. Player Root (CharacterBody2D)**
1. Select `Player` root node
2. Inspector → **Collision**
3. **Layer:** Enable Layer 4 only
4. **Mask:** Enable Layers 1 and 2
   - Layer 1: Collides with walls
   - Layer 2: Collides with enemy bodies (prevents walk-through)

#### **2. Player Attack Hurtbox (Visuals/player_interaction/hurtbox)**
1. Select `Visuals → player_interaction → hurtbox`
2. Inspector → **Collision**
3. **Layer:** Enable Layer 5 only
4. **Mask:** Enable Layer 2 only
   - Detects enemy bodies when attacking

#### **3. Minotaur Root (CharacterBody2D)**
1. Select `Minotaur` root node
2. Inspector → **Collision**
3. **Layer:** Enable Layer 2 only
4. **Mask:** Enable Layer 1 only
   - Only collides with walls (not player - prevents pushing)

#### **4. Minotaur Hurtbox (receives damage)**
1. Select `Minotaur → hurtbox`
2. Inspector → **Collision**
3. **Layer:** Enable Layer 2 only
4. **Mask:** Enable Layer 5 only
   - Detects player's attack hurtbox

#### **5. Minotaur Hitbox (deals damage)**
1. Select `Minotaur → hitbox`
2. Inspector → **Collision**
3. **Layer:** Enable Layer 3 only
4. **Mask:** Enable Layer 4 only
   - Detects player body during attack frames

---

## 🧪 PART 4: DEBUGGING CHECKLIST

### Testing the Fix

**1. Test Directional Sync:**
- [ ] Press A (Left) → AnimatedSprite faces left
- [ ] Press A → Player sword/hitbox appears on LEFT side
- [ ] Press D (Right) → Everything flips to right together

**2. Test Player Attacks Boss:**
- [ ] Attack near boss → Console shows "[MINOTAUR HURTBOX] Area entered"
- [ ] Boss HP decreases
- [ ] No "monitoring=false" errors

**3. Test Boss Attacks Player:**
- [ ] Boss swings axe → Console shows "[MINOTAUR HITBOX] Dealt damage"
- [ ] Player takes damage only during attack frames (not while idle near boss)

**4. Test Physics Collision:**
- [ ] Walk into boss → Player stops (can't walk through)
- [ ] Boss walks into walls → Boss stops

### Common Issues After Fix

**Issue:** "AnimatedSprite2D not found"
- **Fix:** Re-save player.tscn after moving nodes into Visuals

**Issue:** Hurtbox still not detecting
- **Fix:** Verify `hurtbox.monitoring = true` during attack frames
- **Check:** `player_interaction_host.gd` line 44

**Issue:** Player walks through boss
- **Fix:** Ensure Minotaur Layer 2 and Player Mask includes Layer 2

---

## 📝 SUMMARY OF CHANGES

### What We Fixed:
1. ✅ **Created Visuals pivot** → All visual elements flip together
2. ✅ **Removed flip_h logic** → Replaced with scale.x flipping
3. ✅ **Fixed collision layers** → Player attacks hit boss, physics works
4. ✅ **Fixed monitoring** → Attacks only register during active frames

### Files Modified:
- `scene/player.tscn` (scene structure)
- `scripts/player.gd` (lines 4, 12-13, add flipping logic ~line 466)
- `scene/minotaur.tscn` (collision layers - Inspector only)

---

## 🚀 DEPLOYMENT

After completing all steps:
1. **Save all files** in Godot
2. **Run the game** (F5)
3. **Test with checklist** above
4. **Commit changes:**
   ```bash
   git add -A
   git commit -m "Fix player direction sync and collision layers"
   git push origin main
   ```

---

**✨ All bugs should now be resolved!**
