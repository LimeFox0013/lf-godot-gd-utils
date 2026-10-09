# LFTracker

> A marker on your game's screen (HUD) that follows a 3D object, and sticks to the screen edge pointing toward it when the object is off screen.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_tracker.gd` |
| **Tests** | `tests/test_lf_tracker.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils3D` (projection, `screen_direction`), `LFUtils2D` (`rect_edge_point`), `LFLogger` |

## When to use it

Use it for an arrow at the screen edge that points to an off-screen objective, an enemy
marker that sticks to the edge, or a name tag or button bar that follows a 3D object on
the HUD. Godot's `VisibleOnScreenNotifier3D` (a node that reports when something is visible) tells you when something enters or leaves
the screen, and `Camera3D.unproject_position` gives its screen point, but neither places
anything for a target off screen or behind the camera, where the projection is mirrored
or undefined. LFTracker places its node in each of these cases: on screen, beside or
behind the camera, and closer than the near plane. For the math alone (no node), use `LFUtils3D.screen_direction`
and `LFUtils2D.rect_edge_point`.

## Step by step

**Before you start:** you need a 3D scene with a camera and something to track. The steps below build one from scratch.

1. *Scene → New Scene*, then click **3D Scene**. Rename the root node to `Main`. Save it with *Ctrl+S* (*Cmd+S* on macOS) as `tracker_demo.tscn`.
2. Select `Main`, click **+ Add Child Node** (top of the Scene dock), pick **Camera3D** and click *Create*. Add a **MeshInstance3D** the same way and rename it `Objective`. In the Inspector, click the empty *Mesh* slot and choose *New BoxMesh*. In *Transform → Position* set **Z to -5**, so the box sits 5 units in front of the camera.
3. Select `Main` again, add a **CanvasLayer** (this is where on-screen interface goes) and rename it `HUD`. Select `HUD`, click **+ Add Child Node**, type `LFTracker` in the search box and create it. Select that `LFTracker` node, then add a **Label** as its child and type `Objective` in its *Text* property.
4. Select the `LFTracker` node and set these in the Inspector:
   - **Camera**: click *Assign...* and pick your `Camera3D`.
   - **Target**: click *Assign...* and pick `Objective`.
   - **Padding**: `100` (pixels kept free around the screen edge, so the label stays readable).
   - **Rotate To Target**: off (this label should not spin; turn it on for an arrow).
5. To see it move, right-click `Main` in the Scene dock, choose **Attach Script**, and click *Create*. Replace the contents with:

```gdscript
extends Node3D

@onready var objective: Node3D = $Objective
@onready var marker: LFTracker = $HUD/LFTracker


func _ready() -> void:
	# A signal is an event; these lines say what to do when the tracker reports a change.
	marker.screen_exited.connect(func() -> void: print("objective left the screen"))
	marker.screen_entered.connect(func() -> void: print("objective is back on screen"))


func _process(_delta: float) -> void:
	# Swing the objective left and right, 20 world units each way (about every 6 seconds).
	objective.position.x = sin(Time.get_ticks_msec() / 1000.0) * 20.0
```

6. Press **F6** (*Run Current Scene*). You should see the word "Objective" sitting on the box's position while the box swings left and right. When the box leaves the screen, the label stays glued to the left or right edge, 100 pixels in, and the *Output* panel prints "objective left the screen"; when it returns it prints "objective is back on screen".

To make an arrow instead of a label: give the tracker a child that points right (a `Sprite2D` with an arrow image) and leave **Rotate To Target** on, and turn on **Hide If On Screen** so the arrow only shows while the target is out of view.

## API

Everything the class offers; you only need the rows used above to get started.

### Signals

| Member | Signature | Description |
|---|---|---|
| `screen_exited` | `signal screen_exited` | Target went from on-screen to off-screen (or behind the camera), or an on-screen target was lost (null or freed). |
| `screen_entered` | `signal screen_entered` | Target went from off-screen to on-screen. |

### Exports

| Member | Signature | Description |
|---|---|---|
| `camera` | `@export var camera: Camera3D` | Projection camera; must render into this control's viewport. Null, freed or out of the tree counts as no target. |
| `target` | `@export var target: Node3D` | Tracked node. While null, freed or out of the tree the tracker hides itself. Its `visible` is not consulted: a hidden target is still tracked. |
| `DEFAULT_PADDING` | `const DEFAULT_PADDING := 32.0` | Default `padding`, in pixels. |
| `padding` | `@export var padding: float = DEFAULT_PADDING` (32.0) | Inset from each viewport edge, for both the on-screen test and edge placement. Clamped to half the viewport's smaller side; at that size or more it leaves no on-screen area, which is reported once as a warning (see Notes). |
| `hide_if_on_screen` | `@export var hide_if_on_screen: bool = false` | Hide while the target is on-screen (arrow indicators). |
| `hide_if_off_screen` | `@export var hide_if_off_screen: bool = false` | Hide while the target is off-screen or behind the camera (panels, followers). |
| `rotate_to_target` | `@export var rotate_to_target: bool = true` | Off screen, `rotation` points along the ray toward the target; on screen the tracker stands upright (0, compensating a rotated parent). When false, `rotation` is never written. |

### Properties

| Member | Signature | Description |
|---|---|---|
| `on_screen` | `var on_screen: bool` (read-only; writes are ignored) | The target was inside the padded rect and in front of the camera at the last evaluation. `false` before the first one. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `update_tracking` | `update_tracking() -> void` | Evaluates now (state, signals, visibility, placement, rotation). Runs every frame from `_process`; call it to place the tracker immediately. Does nothing outside the tree. |

Each evaluation: with no valid target or camera, hide (and emit `screen_exited` if the target was on screen). Otherwise the target is on screen when it is in front of the camera's near plane and its projection lies in the padded rect (edges included). Signals fire on a change; hide flags apply; then the tracker's **pivot** (`pivot_offset`) is put on the projection (on screen) or on `LFUtils2D.rect_edge_point(padded_rect, LFUtils3D.screen_direction(camera, target position))` (off screen), and with `rotate_to_target` the rotation is set to that direction's angle (0 on screen), compensating a rotated parent.

## Usage

```gdscript
# objective_markers.gd: attach to a CanvasLayer (your HUD) in a 3D scene that has a
# Camera3D at $"../Camera3D" and an objective Node3D at $"../Objective".
extends CanvasLayer

@onready var camera: Camera3D = $"../Camera3D"
@onready var objective: Node3D = $"../Objective"


func _ready() -> void:
	# 1. An arrow at the screen edge, pointing at the objective while it is off screen.
	var arrow := LFTracker.new()
	var icon := Polygon2D.new()  # a triangle pointing along +X (to the right)
	icon.polygon = PackedVector2Array([Vector2(16, 0), Vector2(-8, -10), Vector2(-8, 10)])
	arrow.add_child(icon)
	arrow.pivot_offset = Vector2.ZERO  # the point placed on the edge, and rotated around
	arrow.camera = camera
	arrow.target = objective
	arrow.hide_if_on_screen = true  # no arrow while the objective is visible
	arrow.screen_exited.connect(func() -> void: print("objective left the screen"))
	arrow.screen_entered.connect(func() -> void: print("objective is back on screen"))
	add_child(arrow)

	# 2. A label that follows the objective, hidden (and not clickable) off screen.
	var tag := LFTracker.new()
	var label := Label.new()
	label.text = "Objective"
	label.position = Vector2(-30, -40)  # drawn above the point
	tag.add_child(label)
	tag.rotate_to_target = false
	tag.hide_if_off_screen = true
	tag.padding = 0.0
	tag.camera = camera
	tag.target = objective
	add_child(tag)
	tag.update_tracking()  # place it now instead of next frame
	print("on screen: ", tag.on_screen)
```

## Notes

- The tracker's `pivot_offset` is placed on the point and the tracker rotates around it; set it to the graphic's center (or tip). Placement is converted through the parent's and the canvas transform, so the tracker can live under any parent, including a scaled or offset `CanvasLayer`.
- The camera must render into the tracker's viewport. A 3D `SubViewport` with the tracker in the root HUD would be placed in the wrong pixels.
- `visible` is written only while a hide flag is on (then on every evaluation, overriding your own `visible`), or to hide while there is no target. Whenever the tracker hid itself, it shows itself again once the reason is gone (a target returns, or the flag that hid it is turned off); with both flags off, a tracker you hid yourself stays hidden. A hidden control and its children take no clicks, unlike one faded out with `modulate.a`.
- While hidden by a flag, position and rotation are not updated.
- The first evaluation with a target always reports its state: `screen_entered` if the target starts visible, `screen_exited` if not. Losing the target resets this.
- `mouse_filter` defaults to `MOUSE_FILTER_IGNORE`, so the tracker's own rect never swallows clicks; children keep their own filters.
- A hidden target (`visible = false`, or under a hidden parent) is tracked like a visible one: the tracker stays on it, or on the edge pointing at it, and reports `on_screen` from its position alone. To stop tracking a target you hid (a pooled enemy put away, say), set `target = null`, or hide the tracker yourself.
- When `padding` is half the viewport's smaller side or more (the default 32 in a 64 x 64 viewport, the size of a headless run), the padded rect shrinks to a line or a point: `on_screen` is true only for a target projected exactly onto it, and the tracker sits on that line or point. The tracker reports this once with an `LFLogger` warning naming itself, the padding and the viewport size, and again only if the padding fitted in between. Lower `padding` for small viewports.
- The direction assumes a normal, centered camera view: it is wrong if you use the camera's `h_offset`/`v_offset` or its `Frustum` projection.
