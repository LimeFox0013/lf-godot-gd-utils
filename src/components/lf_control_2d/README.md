# LFControl2D

> A click-through layout control that pins a `Node2D` to its on-screen center: on demand, once when first ready (with `sync_initial_position`), or every frame (with `follow`).

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_control_2d.gd`, `lf_control_2d.tscn` |
| **Tests** | `tests/test_lf_control_2d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLayoutControl`, `LFControl`, `LFLogger` |

## When to use it

Use it to put a 2D world object, or a node on another `CanvasLayer`, on a spot laid out in
the UI: a 3-2-1 countdown sprite that should sit over the "Start" panel, or a particle
burst that plays where a HUD slot is. Place the `LFControl2D` with anchors or inside a
Container, set its `target`, and it converts the control's screen centre through both
canvas transforms (camera included). With `sync_initial_position` it snaps once at
`_ready()` and again one frame later, after a Container has laid it out. If the
`Node2D` can simply be a child of the control, you don't need this: a `Node2D` under a
`Control` already draws in the control's space.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock. Save it.
2. Add the thing to move: **+ Add Child Node**, type `Sprite2D`, press *Create*. In the
   Inspector, drag a picture from the FileSystem dock (for example `icon.svg`) onto its
   *Texture* slot.
3. Add the anchor: click the root node, then the **Instantiate Child Scene** button (the
   chain-link icon in the Scene dock) and pick `lf_control_2d.tscn` from the library's folder
   (`src/components/lf_control_2d/`). It fills the window by default; to pin the sprite
   somewhere else, change its anchors with the *Layout* menu in the toolbar above the
   viewport, or resize it.
4. Select the LFControl2D node. In the Inspector click *Target → Assign…* and choose the
   Sprite2D, and tick **Follow** (on: the sprite is moved every frame; off: only when you
   call `sync_target()`).
5. Press **F6** (*Run Current Scene*). You should see the sprite jump to the middle of the
   window, the centre of the anchor. Resize the window and it stays in the middle.
6. Optional: untick *Follow* and move the sprite once, on demand, from a script
   (right-click the root → **Attach Script**):

   ```gdscript
   extends Control


   func _ready() -> void:
   	$LFControl2D.sync_target()   # put the target on the control's centre right now
   ```

## API

Everything the class offers; you only need the rows used above to get started. (`@export` properties are the ones you can set in the Inspector.)

### Exports

| Member | Signature | Description |
|---|---|---|
| `target` | `@export var target: Node2D` | Node placed on this control's on-screen center. |
| `sync_initial_position` | `@export var sync_initial_position := false` | When true, the target is snapped at the first `_ready()` and once more on the first frame after it (after any Container has laid the control out). |
| `follow` | `@export var follow := false` | When true, the target is snapped every frame. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `sync_target` | `sync_target() -> void` | Snaps the target now: `target.global_position = target.get_canvas_transform().affine_inverse() * LFControl.get_center_pos_on_viewport(self)`. Warns when there is no target; does nothing while either node is outside the tree. |

Inherited: `registry_id` (see `LFControl`), click-through mouse/focus settings (see `LFLayoutControl`).

## Usage

```gdscript
# game.gd, on the scene root. $World/Beacon is a Node2D seen through a Camera2D;
# $HUD is a CanvasLayer (or any Control) holding the UI.
extends Node2D


func _ready() -> void:
	var anchor := LFControl2D.new()
	anchor.set_anchors_preset(Control.PRESET_CENTER)   # the middle of the screen
	anchor.target = $World/Beacon                      # still lands on that screen point
	anchor.follow = true                               # keep it there every frame
	$HUD.add_child(anchor)

	# Or snap just once, whenever you choose:
	# anchor.sync_target()
```

## Notes

- Without `follow`, the snap happens at the first `_ready()` and on the next frame only; removing and re-adding the node does not resync. Call `sync_target()` for more.
- The target must render into the same viewport as the control; the canvas transforms of both sides are applied, the viewport's stretch transform is not needed.
- With `sync_initial_position` on and no `target`, `_ready()` pushes a warning. `follow` without a target waits silently until one is set.
- A set `registry_id` registers the node like any `LFControl`.
