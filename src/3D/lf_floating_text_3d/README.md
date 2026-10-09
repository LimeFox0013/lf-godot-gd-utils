# LFFloatingText3D

> Pop-up text in the 3D world, like a damage number: it appears above a point, floats up while fading away, then deletes itself.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_floating_text_3d.gd` |
| **Tests** | `tests/test_lf_floating_text_3d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFAnimate` (`one_shot`) |

## When to use it

Use it for short feedback that floats up over something in a 3D scene and disappears on
its own: damage numbers over an enemy that was hit, "+5 gold" over a chest, "MISS" over a
dodging unit. One call shows it; you never keep a reference or free it yourself. For text
that should stay put (a name tag, a health label) use a plain `Label3D`. For 2D games or
HUD text use a `Label` with `LFAnimate` instead.

## Step by step

This builds a tiny scene where pressing Space makes a number float up.

1. In the editor choose *Scene → New Scene*, then click **3D Scene** under "Create Root
   Node". The root is a `Node3D`; double-click its name in the Scene dock and call it `World`.
2. Select `World`, click **+ Add Child Node** (top of the Scene dock), search for
   `Camera3D` and press *Create*. In the Inspector (the property panel on the right) open
   *Transform* and set *Position* to `0, 1.5, 5`. A camera looks along -Z by default, so
   this one looks at the middle of the world from 5 units away.
3. Select `World` again and click the **Attach Script** button (the scroll icon above the
   Scene dock). Keep the defaults and press *Create*.
4. Replace the script's contents with this:

   ```gdscript
   extends Node3D


   func _unhandled_input(event: InputEvent) -> void:
   	# Space (or Enter) is the built-in "ui_accept" action.
   	if event.is_action_pressed("ui_accept"):
   		# Show a yellow "-12" in this scene (self), at the world's centre (0, 0, 0).
   		LFFloatingText3D.spawn(self, Vector3.ZERO, "-12", Color(1.0, 0.85, 0.15))
   		# A smaller, quicker white "MISS" to the right: rises 0.6 units over 0.5 seconds.
   		LFFloatingText3D.spawn(self, Vector3(1.5, 0.0, 0.0), "MISS", Color.WHITE, 0.6, 0.5)
   ```

   (`_unhandled_input` is a function Godot calls for every key or mouse press nobody else
   used. A `Color` is red, green, blue from 0 to 1.)
5. Press **F6** (*Run Current Scene*) and save the scene when asked. Press Space: a yellow
   "-12" rises about one unit and fades out over 0.8 seconds, and a white "MISS" does the
   same a little faster. Both vanish by themselves. Press Space repeatedly to stack several.
6. Make it your own with the extra arguments, in this order after `color`:
   `rise` (how far it floats up, in world units), `duration` (seconds), `height` (how far
   above the point it starts, in world units), `label_font_size` and `outline` (both in
   pixels). Use `parent.to_local(world_point)` if you have a world position.

## API

Everything the class offers; you only need `spawn` to get started.

### Methods

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_RISE` | `const DEFAULT_RISE := 1.0` | Default `rise`, world units. |
| `DEFAULT_DURATION` | `const DEFAULT_DURATION := 0.8` | Default `duration`, seconds. |
| `DEFAULT_HEIGHT` | `const DEFAULT_HEIGHT := 1.2` | Default `height` above `at`, world units. |
| `DEFAULT_FONT_SIZE` | `const DEFAULT_FONT_SIZE := 48` | Default `label_font_size`, pixels. |
| `DEFAULT_OUTLINE_SIZE` | `const DEFAULT_OUTLINE_SIZE := 8` | Default `outline`, pixels. |
| `spawn` | `static spawn(parent: Node, at: Vector3, label_text: String, color: Color, rise := DEFAULT_RISE, duration := DEFAULT_DURATION, height := DEFAULT_HEIGHT, label_font_size := DEFAULT_FONT_SIZE, outline := DEFAULT_OUTLINE_SIZE) -> Label3D` (1.0, 0.8, 1.2, 48, 8) | Adds a camera-facing, no-depth-test label to `parent` at `at + (0, height, 0)` (parent space), tinted `color`, with font size `label_font_size` and outline `outline` (pixels); it rises `rise` units and fades to fully transparent over `duration` seconds, then frees itself. Returns the label (an `LFFloatingText3D`). |

## Usage

A script on an enemy (a `Node3D` that has a parent in the 3D scene):

```gdscript
extends Node3D


func take_damage(amount: float) -> void:
	# A yellow "-12" that floats up from 1.2 units above the enemy.
	LFFloatingText3D.spawn(get_parent(), position, "-%d" % roundi(amount), Color(1.0, 0.85, 0.15))


func dodge() -> void:
	# A smaller, quicker "MISS": rise 0.6 units over 0.5 seconds.
	LFFloatingText3D.spawn(get_parent(), position, "MISS", Color.WHITE, 0.6, 0.5)
```

Spawn it on the enemy's parent, not on the enemy itself, so the text keeps floating even
if the enemy dies and is freed right after.

## Notes

- It fades through `transparency`, not `modulate.a`: that fades the outline too, and changing the colour of a `Label3D` forces it to rebuild its text, which adds up with a crowd's worth of numbers.
- The label is freed only when its animation finishes; leave its `position` and `transparency` to it. Freeing `parent` frees it early; while `parent` is outside the scene tree the label waits, unanimated.
- `at` is in the parent's space (its local `position`), not world space; pass a sibling's `position`, or `parent.to_local(world_point)`.
- The text is drawn over walls and units (so it stays readable); it still sorts with other see-through objects.
- Keep the formatting (signs, rounding, colours) in your own wrapper; this class only draws and animates.
