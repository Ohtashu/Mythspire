# AnimationPlayer Call Method Track Setup Guide

## Task 2: Sync Attack Damage with Animation Frames

This guide explains how to set up **Call Method Tracks** in Godot's AnimationPlayer to trigger `deal_damage()` at the exact frame when the attack animation hits.

---

## Step-by-Step Instructions

### For Slime (slime_attack animation):

1. **Open the Slime Scene** (`scene/slime.tscn`)
2. **Select the AnimatedSprite2D node**
3. **Open the AnimationPlayer** (or find the SpriteFrames resource)
4. **Select the `slime_attack` animation**
5. **Add a Call Method Track:**
   - Click the **"+" button** in the animation timeline (or right-click the track list)
   - Select **"Add Call Method Track"**
   - In the dialog, select the **Slime node** (the root CharacterBody2D)
   - The track will appear in the timeline
6. **Add a Keyframe at the Hit Frame:**
   - Scrub through the animation to find the frame where the slime actually makes contact (usually middle frames, e.g., frame 3-4 of 6)
   - **Right-click** on the Call Method track at that frame
   - Select **"Insert Key"**
   - In the method selector, choose **`deal_damage`**
   - The keyframe will appear on the timeline
7. **Test:** Play the animation and verify `deal_damage()` is called at the correct frame

### For Skeleton (skeleton_attack animation):

1. **Open the Skeleton Scene** (`scene/skeleton.tscn`)
2. **Select the AnimatedSprite2D node**
3. **Open the AnimationPlayer** (or find the SpriteFrames resource)
4. **Select the `skeleton_attack` animation**
5. **Add a Call Method Track:**
   - Click the **"+" button** in the animation timeline
   - Select **"Add Call Method Track"**
   - Select the **Skeleton node** (the root CharacterBody2D)
6. **Add a Keyframe at the Hit Frame:**
   - Find the frame where the sword/claw actually hits (usually middle frames)
   - **Right-click** on the Call Method track at that frame
   - Select **"Insert Key"**
   - Choose **`deal_damage`**
7. **Test:** Play the animation and verify damage is dealt at the correct frame

### For Evil Sword (sword_attack animation):

1. **Open the Evil Sword Scene** (`scene/evil_sword.tscn`)
2. **Select the AnimatedSprite2D node**
3. **Open the AnimationPlayer** (or find the SpriteFrames resource)
4. **Select the `sword_attack` animation**
5. **Add a Call Method Track:**
   - Click the **"+" button** in the animation timeline
   - Select **"Add Call Method Track"**
   - Select the **Evil Sword node** (the root CharacterBody2D)
6. **Add a Keyframe at the Hit Frame:**
   - Find the frame where the sword pierces through (usually middle frames)
   - **Right-click** on the Call Method track at that frame
   - Select **"Insert Key"**
   - Choose **`deal_damage`**
7. **Test:** Play the animation and verify damage is dealt at the correct frame

---

## Important Notes:

- **If using SpriteFrames (AnimatedSprite2D):** You may need to use an **AnimationPlayer node** instead, or connect to the `frame_changed` signal in code to call `deal_damage()` at specific frames.

- **Alternative Approach (if Call Method Track doesn't work with SpriteFrames):**
  - In the enemy script, add a check in `_on_frame_changed()`:
    ```gdscript
    func _on_frame_changed() -> void:
        if current_state == State.ATTACK and animated_sprite.animation == "skeleton_attack":
            if animated_sprite.frame == 3:  # Frame where hit occurs
                deal_damage()
    ```

- **Remove Old Damage Code:** Make sure to remove any immediate damage code from the `attack()` or state transition functions, as damage should only come from `deal_damage()`.

---

## Verification:

After setting up the Call Method Tracks:
1. Play the game
2. Attack the player with each enemy
3. Verify damage is only dealt when the animation reaches the hit frame
4. Check that there's no damage on state entry (only on the specific frame)

