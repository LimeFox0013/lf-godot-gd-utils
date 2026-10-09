# LFDragTracker

> Tells a quick click or tap apart from a press-and-drag.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_drag_tracker.gd` |
| **Tests** | `tests/test_lf_drag_tracker.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it when the same mouse button (or finger) does two things: a quick click selects a
unit, but holding and moving pans the camera. Without it, the click that starts a pan also
selects whatever was under the cursor. The tracker remembers where the press began and
calls it a drag once the pointer has moved more than a few pixels. For a button that only
clicks, Godot's `InputEventMouseButton` is enough; for dragging UI items between slots, use
Godot's built-in `_get_drag_data`/`_drop_data` on Controls.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **2D Scene**. This creates a `Node2D`.
2. Right-click the `Node2D`, choose **Attach Script**, and press *Create*.
3. Select everything in the script and replace it with:

```gdscript
extends Node2D

# One tracker per mouse button. More than 6 pixels of movement counts as a drag.
var _left := LFDragTracker.new(6.0)


# Godot calls this function for every input event (mouse, keyboard...) nobody else used.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left.press(event.position)  # the button went down here
		elif _left.release():            # the button came up: was it a tap?
			print("tap")
		else:
			print("drag")
```

4. Press **F6** (*Run Current Scene*) and save the scene when asked.
5. Click the game window quickly without moving the mouse: the **Output** panel prints `tap`. Press, move the mouse about 10 pixels or more, then let go: it prints `drag`.
6. To make dragging harder or easier, change `6.0`. It is measured in pixels of the game window.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_THRESHOLD` | `const DEFAULT_THRESHOLD := 6.0` | The default drag threshold, in pixels. |
| `_init` | `LFDragTracker.new(drag_threshold: float = DEFAULT_THRESHOLD)` (6.0) | A tracker that calls a press a drag once it moves more than `drag_threshold` pixels. |
| `threshold` | `var threshold: float` | Distance the pointer must move past (strictly more than) to become a drag. May change at any time. |
| `pressed` | `var pressed: bool` | Whether the button is down right now. |
| `dragged` | `var dragged: bool` | Whether the current (or last) press moved past `threshold`. |
| `down_position` | `var down_position: Vector2` | Where the current (or last) press went down. |
| `press` | `press(position: Vector2) -> void` | The button went down: starts a fresh press, not yet a drag. |
| `move` | `move(position: Vector2) -> bool` | The pointer moved: whether the button is down and the press is a drag now. Always `false` while the button is up. |
| `release` | `release() -> bool` | The button came up: whether the press was a tap. `false` when the button was not down (a release with no `press` before it). |

## Usage

```gdscript
extends Node2D

var _left := LFDragTracker.new(6.0)  # more than 6 px of movement = a drag


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left.press(event.position)
		elif _left.release():
			print("tap at ", event.position)  # select something, not the end of a pan
	elif event is InputEventMouseMotion and _left.move(event.position):
		print("dragging by ", event.relative)  # pan the camera
```

## Notes

- Once a press passes the threshold it stays a drag until released, even if the pointer
  comes back to where it started.
- Moving exactly `threshold` pixels is still a tap.
- A `release` with no `press` before it (the press landed on a UI control or happened
  before the tracker existed) is not a tap.
- Use one tracker per button, and feed positions in one coordinate space (usually viewport
  pixels, as in `event.position`).
