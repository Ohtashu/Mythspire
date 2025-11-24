# Y-Sorting Fix Guide

## Overview
This guide explains how to properly configure Y-sorting (depth sorting) in your Godot game so that characters, enemies, and structures render in the correct order based on their Y position.

---

## 1. Hierarchy Fix: Scene Tree Organization

### Current Structure (Correct)
```
Game (YSort) ← Main sorting container
├── Player (CharacterBody2D) ← Direct child
├── EnemySpawner (Node2D)
├── dungeon_scene (Node2D with y_sort_enabled)
│   ├── ground (TileMapLayer) ← Floor layer
│   ├── outer_wall (TileMapLayer) ← Wall layer with y_sort_enabled
│   ├── inner_wall (TileMapLayer) ← Wall layer with y_sort_enabled
│   ├── structure (TileMapLayer) ← Structure layer with y_sort_enabled
│   ├── decoration (TileMapLayer) ← Decoration layer with y_sort_enabled
│   └── torch_animated* (Node2D with y_sort_enabled) ← Environment objects
└── player_hud (Control) ← UI, not affected by Y-sorting
```

### Key Principles:
1. **YSort Node**: The Game root must be a `YSort` node (not just `Node2D` with `y_sort_enabled`)
2. **Direct Children**: Player and Enemies should be **direct children** of the YSort node
3. **TileMapLayers**: Wall/structure TileMapLayers should have `y_sort_enabled = true`
4. **Environment Objects**: Torches, candles, etc. should have `y_sort_enabled = true` on their root Node2D

### Why This Works:
- **YSort** automatically sorts all its descendants by their Y position
- Objects with higher Y values (lower on screen) render **in front**
- Objects with lower Y values (higher on screen) render **behind**
- All sortable objects must be descendants of the YSort node

---

## 2. Script Fix: LevelManager.gd

### Usage:
1. Attach `LevelManager.gd` to your **Game** node (the YSort root)
2. The script automatically runs in `_ready()` and configures everything

### What It Does:
- ✅ Finds Player and sets `y_sort_enabled = true`
- ✅ Finds all Enemies and sets `y_sort_enabled = true`
- ✅ Finds all TileMapLayers and configures them appropriately:
  - **Floor layers**: `y_sort_enabled = false`, `z_index = -10` (always below)
  - **Wall/Structure layers**: `y_sort_enabled = true`, `z_index = 0`
- ✅ Finds environment objects (torches, candles) and enables Y-sorting
- ✅ Sets appropriate `z_index` values to ensure proper layering

### Configuration Variables:
```gdscript
@export var floor_z_index: int = -10      # Floor always below
@export var wall_z_index: int = 0          # Walls at same level as characters
@export var character_z_index: int = 0     # Characters at same level as walls
@export var structure_z_index: int = 0    # Structures at same level
```

### Manual Configuration (if not using script):
If you prefer manual setup, ensure:
- **Game node**: Type = `YSort` (not `Node2D`)
- **Player**: `y_sort_enabled = true` on CharacterBody2D
- **Enemies**: `y_sort_enabled = true` on CharacterBody2D root
- **Wall TileMapLayers**: `y_sort_enabled = true`
- **Floor TileMapLayers**: `y_sort_enabled = false`, `z_index = -10`

---

## 3. Texture Origin Fix: Y-Sort Origin for Walls

### The Problem:
Walls are sorting incorrectly because their **Y-sort origin** (pivot point) is in the center of the tile, not at the bottom where the wall meets the ground.

### The Solution:
The **Y-sort origin** must be set at the **bottom** of the wall tile (where it touches the ground).

### How Y-Sort Origin Works:
- **Y-sort origin** is the Y-coordinate within the tile that's used for sorting
- It's measured in **pixels from the top** of the tile
- When comparing two objects for sorting:
  - Object A's Y position + its Y-sort origin = sorting Y
  - Object B's Y position + its Y-sort origin = sorting Y
  - Higher sorting Y = renders in front

### For Vertical Wall Tiles:
```
┌─────────────┐
│             │  ← Top of wall (y_sort_origin = 0)
│             │
│   WALL      │
│             │
│             │
├─────────────┤  ← Bottom of wall (y_sort_origin = tile_height)
│   GROUND    │
└─────────────┘
```

**Correct Y-Sort Origin**: Set to the **tile height** (e.g., if tile is 16px tall, set `y_sort_origin = 16`)

### How to Set Y-Sort Origin in Godot:
1. Open your **TileSet** resource
2. Select the **wall tile** you want to configure
3. In the **TileSet** editor, find the **Y-Sort Origin** property
4. Set it to the **height of the tile** (or slightly less if the wall has a base)
5. For a 16x16 tile wall: `y_sort_origin = 16`
6. For a 32x32 tile wall: `y_sort_origin = 32`

### Example Values:
- **Short wall** (16px tall): `y_sort_origin = 16`
- **Medium wall** (24px tall): `y_sort_origin = 24`
- **Tall wall** (32px tall): `y_sort_origin = 32`
- **Very tall wall** (48px tall): `y_sort_origin = 48`

### Visual Explanation:
```
Player Y = 100, CharacterBody2D position (feet at Y = 100)
Wall tile Y = 100, y_sort_origin = 16 (bottom of wall)

Player sorting Y = 100 + 0 = 100
Wall sorting Y = 100 + 16 = 116

Since 116 > 100, Wall renders IN FRONT of Player ✅
```

But if the player moves down:
```
Player Y = 120, CharacterBody2D position (feet at Y = 120)
Wall tile Y = 100, y_sort_origin = 16

Player sorting Y = 120 + 0 = 120
Wall sorting Y = 100 + 16 = 116

Since 120 > 116, Player renders IN FRONT of Wall ✅
```

### Current TileSet Analysis:
Looking at your `dungeon.tscn`, I can see various `y_sort_origin` values:
- Some tiles have `y_sort_origin = 60` (very tall walls)
- Some have `y_sort_origin = 40` (medium walls)
- Some have `y_sort_origin = 20` (short structures)
- Some have `y_sort_origin = 4` (very short objects)

**These values should match the visual height of the tile from top to bottom.**

---

## 4. Troubleshooting

### Problem: Characters render behind walls when they should be in front
**Solution**: Check that:
1. Game root is a `YSort` node (not `Node2D`)
2. Wall tiles have correct `y_sort_origin` set to tile height
3. Player/Enemies have `y_sort_enabled = true` on CharacterBody2D

### Problem: Floor renders on top of everything
**Solution**: Set floor TileMapLayer `z_index = -10` and `y_sort_enabled = false`

### Problem: Enemies don't sort correctly
**Solution**: Ensure enemies are direct children of Game (YSort) node, not nested in other nodes

### Problem: Walls sort incorrectly
**Solution**: Adjust `y_sort_origin` in TileSet editor to match the bottom of the wall tile

---

## 5. Quick Checklist

- [ ] Game root node is type `YSort`
- [ ] Player has `y_sort_enabled = true` on CharacterBody2D
- [ ] Enemies have `y_sort_enabled = true` on CharacterBody2D
- [ ] Wall TileMapLayers have `y_sort_enabled = true`
- [ ] Floor TileMapLayers have `z_index = -10` and `y_sort_enabled = false`
- [ ] Wall tiles have `y_sort_origin` set to tile height in TileSet editor
- [ ] Environment objects (torches, candles) have `y_sort_enabled = true`
- [ ] LevelManager.gd script is attached to Game node (optional but recommended)

---

## Summary

**Hierarchy**: YSort → Player/Enemies/TileMaps (all direct or nested descendants)

**Script**: LevelManager.gd automatically configures everything on scene load

**Texture Origins**: Set `y_sort_origin` to tile height for wall tiles (bottom of tile)

This ensures proper depth sorting where objects lower on screen render in front of objects higher on screen! 🎮

