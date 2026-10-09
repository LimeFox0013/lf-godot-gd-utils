# LFParallaxControl, LFParallaxLayer

> A `Control` that slides its picture layers at different speeds for a parallax (depth) effect: by a shared shift (each layer scaled by its own `motion_scale`), or to a numbered slide (each layer spread by its own width).

| | |
|---|---|
| **Files** | `lf_parallax_control.gd`, `lf_parallax_layer.gd` |
| **Tests** | `tests/test_lf_parallax_control.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFAnimate` (`control`), `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFParallaxControl` | Node: add it to a scene |
| `LFParallaxLayer` | Node: add it to a scene |

## When to use it

Use it for depth in menus and paged screens: a title screen whose sky, hills and trees
drift by different amounts as the player moves between pages, or a level-select carousel
whose wide background glides from the first slide to the last. It works in Control
(layout) space and tweens the layers to positions you choose. For a game world that
scrolls with a `Camera2D`, use Godot's `Parallax2D` instead, which follows the camera on
its own.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock. Save it.
2. Click **+ Add Child Node**, type `LFParallaxControl`, press *Create*. In the toolbar
   above the viewport open the **Layout** menu and choose *Full Rect*, so it fills the window.
3. With that node selected, **+ Add Child Node** twice, choosing `LFParallaxLayer` each
   time (a TextureRect: a picture). Rename them `Sky` and `Hills` (select, press F2).
   Put a picture in each one's *Texture* in the Inspector (drag it from the FileSystem
   dock). Order matters: layers lower in the list draw on top, so keep `Hills` below `Sky`.
4. Give each layer its speed in the Inspector, *Motion Scale*: `Sky` x = `0.2`, y = `0.2`
   (slow, far away), `Hills` x = `1`, y = `1` (full speed, close).
5. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control

   @onready var parallax: LFParallaxControl = $LFParallaxControl

   var page := 0


   func _input(event: InputEvent) -> void:   # runs for every key, click or button
   	if event.is_action_pressed("ui_right"):   # the right arrow key
   		page += 1
   	elif event.is_action_pressed("ui_left"):
   		page = maxi(page - 1, 0)
   	else:
   		return
   	# Slide the layers 200 px per page (a tween over the default 0.8 seconds). A tween
   	# is Godot's smooth movement from one value to another. The sky moves 0.2 x 200 = 40 px,
   	# the hills the full 200 px.
   	parallax.move(Vector2(page * 200.0, 0.0))
   ```
6. Press **F6** (*Run Current Scene*) and tap the right arrow key. Both pictures slide
   left, the hills five times as far as the sky, which reads as depth. Left arrow slides
   them back.

## API

Everything the class offers; you only need the rows used above to get started. (`Array[LFParallaxLayer]` is a list that holds only layers.)

### LFParallaxControl — Exports / Properties

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_DURATION` | `const float` (0.8) | Default `duration` of `move` and `move_by_slide`, in seconds. |
| `slides` | `@export var slides := 0` | Number of slides, used by `move_by_slide`. |
| `active_slide` | `@export var active_slide := 0` | Slide last moved to by `move_by_slide` (clamped). If non-zero at `_ready()`, the layers are placed on it at once. |
| `layers` | `var layers: Array[LFParallaxLayer]` | Tracked layers: rebuilt by `reset()`; freed layers are dropped on the next move. |
| `shift` | `var shift := Vector2(0.0, 0.0)` | Last shift passed to `move()`. |

### LFParallaxControl — Methods

| Member | Signature | Description |
|---|---|---|
| `reset` | `reset() -> void` | Rebuilds `layers` from current `LFParallaxLayer` children. Called by `_ready()`. |
| `move` | `move(new_shift: Vector2 = shift, duration := DEFAULT_DURATION) -> void` (0.8) | Shift mode. Stores `shift` and tweens each layer's `position` to `-(new_shift * layer.motion_scale)` over `duration` seconds (`EASE_IN_OUT`; at once when `duration <= 0`). A NaN or infinite shift pushes an error and changes nothing. |
| `move_by_slide` | `move_by_slide(slide_index: int, duration := DEFAULT_DURATION) -> void` (0.8) | Slide mode. Clamps the index to `[0, slides - 1]`, stores it in `active_slide`, and tweens each layer's `position.x` to `-(slide_space * index + size.x * index)`, where `slide_space = (layer.size.x - size.x * slides) / (slides - 1)` (`EASE_OUT`). Each layer keeps its `position.y`. Slide 0 aligns a layer's left edge with the control's, the last slide its right edge. `motion_scale` is not applied. |

### LFParallaxLayer — Exports

| Member | Signature | Description |
|---|---|---|
| `motion_scale` | `@export var motion_scale := Vector2(1.0, 1.0)` | Multiplier on the shared shift for this layer (shift mode only). |

## Usage

```gdscript
# title_screen.gd. In the scene: an LFParallaxControl named Parallax (anchors: Full
# Rect) with LFParallaxLayer children Sky (motion_scale 0.2, 0.2) and Hills
# (motion_scale 1, 1), each showing a texture.
extends Control

@onready var parallax: LFParallaxControl = $Parallax


# Shift mode: the sky drifts 80 px while the hills move 400 px per page.
func show_page(page: int) -> void:
	parallax.move(Vector2(page * 400.0, 0.0))        # 0.8 s tween


# Slide mode, for a carousel of 4 slides: each layer glides across its own width.
func show_slide(index: int) -> void:
	parallax.slides = 4
	parallax.move_by_slide(index, 0.5)               # 0.5 s tween
```

## Notes

- Adding or removing layer children is not detected; call `reset()` afterwards. A layer removed but not freed stays tracked (and keeps moving) until then; a freed layer is skipped.
- In slide mode the layers are placed again, at once, whenever the control is resized (a running slide tween is cut short and the layers jump to the active slide), so the first and last slides keep aligning the edges. A layer's own resize is not watched; call `move_by_slide(active_slide, 0.0)` after one. Shift mode does not depend on the control's size.
- With `slides` below 2 there is no spacing between slides; `move_by_slide` then stays at slide 0.
- Each call kills the layer's previous tween first (through `LFAnimate.control`, where `position` and `position:x` replace each other), so a newer `move`/`move_by_slide` always wins. With `t <= 0`, or for a layer outside the tree, the position is set at once with no tween. Tweens are bound to their layer and die with it.
- `shift` records only the last `move()`; `move_by_slide` does not change it.
