# LFOrbitCamera

> A strategy-game camera: slide across the map, zoom in and out, and turn around the point you look at, driven by mouse or key movements you pass in.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_orbit_camera.gd` |
| **Tests** | `tests/test_lf_orbit_camera.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it for a top-down or three-quarter camera in a strategy, city-builder or tower-defense
game: right-drag to slide across the map, wheel to zoom, middle-drag to turn around the
point you are looking at. It holds no input code: you feed it pixel deltas from whatever
input you use (mouse drag, wheel, a gamepad stick scaled to pixels), and it keeps the
camera math in one place. A pan moves along the rig's own axes, so a drag feels the same
at any orbit angle, and its step grows with the camera distance, so it feels about the
same at any zoom (how closely it tracks the ground depends on `pan_units_per_pixel` and
the camera's field of view); a zoom step moves a fixed fraction of the distance, close in
and far out. For a third-person camera that follows a character, use a
`SpringArm3D` instead; for screen shake, put an `LFShaker` under its mount.

## Step by step

This builds a small scene you can pan, zoom and turn with the mouse. The class is not a
node: you create it in a script and give it the nodes to move.

1. *Scene → New Scene*, click **3D Scene** under "Create Root Node", rename the root
   `World`.
2. Build the camera rig. Select `World` and click **+ Add Child Node**; add a `Node3D` and
   rename it `Rig` (this is the point on the ground the camera looks at). With `Rig`
   selected add a child `Node3D` named `Mount`, and with `Mount` selected add a child
   `Camera3D`. The Scene dock should now read `World → Rig → Mount → Camera3D`.
3. Place them in the Inspector (the property panel on the right, under *Transform*):
   - `Mount`: *Position* `0, 30, -26`. This is the camera's distance and angle from the
     rig; the orbit camera keeps this angle and only scales the distance.
   - `Camera3D`: *Rotation* `-49, 180, 0` (degrees) so it looks down at the rig.
4. Something to look at: add to `World` a `DirectionalLight3D` (set *Rotation* `-50, 30, 0`),
   and a `MeshInstance3D` named `Floor`. In the Inspector click the empty *Mesh* slot, choose
   **New PlaneMesh**, click it and set *Size* to `100, 100`. Add another `MeshInstance3D`
   with **New BoxMesh** and set its *Position* to `0, 0.5, 0`, so there is a landmark.
5. Select `World`, click **Attach Script** (above the Scene dock), *Create*, and
   replace the contents with:

   ```gdscript
   extends Node3D

   # The orbit camera is not a node, so this script keeps it in a variable.
   var orbit: LFOrbitCamera


   func _ready() -> void:
   	# Tell it which node is the rig, which is the camera, and which is the mount.
   	orbit = LFOrbitCamera.new($Rig, $Rig/Mount/Camera3D, $Rig/Mount)
   	# Optional: the farthest it may zoom out, in world units.
   	orbit.max_distance = 80.0


   # Godot calls this for every input event nothing else used.
   func _unhandled_input(event: InputEvent) -> void:
   	var motion := event as InputEventMouseMotion
   	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
   		orbit.pan(motion.relative)     # hold right button and drag: slide across the map
   	elif motion != null and motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
   		orbit.rotate(motion.relative)  # hold middle button and drag: turn around the rig
   	var button := event as InputEventMouseButton
   	if button != null and button.pressed:
   		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
   			orbit.zoom(1.0)            # one step closer
   		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
   			orbit.zoom(-1.0)           # one step farther
   ```
6. Press **F6** (*Run Current Scene*) and save when asked. You should see the box from
   above. Hold the right mouse button and drag: the ground follows the cursor.
   Scroll the wheel: the view zooms in and out, never closer than 5 or farther than 80
   units. Hold the middle button and drag sideways: the view turns around the point you
   are looking at.
7. Tune it by setting the properties after `new`: `min_distance` / `max_distance` (world
   units), `pan_units_per_pixel` (higher pans faster), `zoom_step_fraction` (0.12 means
   each notch in multiplies the distance by 0.88, and each notch out divides it by 0.88,
   about 13.6% farther), `rotate_radians_per_pixel` (a radian is
   about 57 degrees). If a drag feels backwards, pass `-motion.relative` instead.

## API

Everything the class offers; you only need the rows used above to get started.

### Properties

| Member | Type / default | Description |
|---|---|---|
| `DEFAULT_MIN_DISTANCE` | `const := 5.0` | Default `min_distance`. |
| `DEFAULT_MAX_DISTANCE` | `const := 100.0` | Default `max_distance`. |
| `DEFAULT_PAN_UNITS_PER_PIXEL` | `const := 0.0018` | Default `pan_units_per_pixel`. |
| `DEFAULT_ZOOM_STEP_FRACTION` | `const := 0.12` | Default `zoom_step_fraction`. |
| `DEFAULT_ROTATE_RADIANS_PER_PIXEL` | `const := 0.006` | Default `rotate_radians_per_pixel`. |
| `min_distance` | `float = DEFAULT_MIN_DISTANCE` (5.0) | Closest camera distance from the rig. |
| `max_distance` | `float = DEFAULT_MAX_DISTANCE` (100.0) | Farthest camera distance from the rig. |
| `pan_units_per_pixel` | `float = DEFAULT_PAN_UNITS_PER_PIXEL` (0.0018) | World units per pixel of drag at distance 1 (the step is this times the distance). |
| `zoom_step_fraction` | `float = DEFAULT_ZOOM_STEP_FRACTION` (0.12) | Fraction of the distance one zoom-in step removes; a zoom-out step undoes one zoom-in step. |
| `rotate_radians_per_pixel` | `float = DEFAULT_ROTATE_RADIANS_PER_PIXEL` (0.006) | Yaw per pixel of orbit drag. |
| `rig` | `Node3D` | The ground pivot that pans and turns. |
| `camera` | `Camera3D` | The camera rendering the view. May be swapped; the offset stays on the mount set at construction. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFOrbitCamera.new(pivot: Node3D, view_camera: Camera3D, mount: Node3D = null)` | `pivot` becomes `rig`, `view_camera` becomes `camera`. The offset direction and starting distance come from the mount's (or camera's) local position, which must not be zero. |
| `get_camera` | `get_camera() -> Camera3D` | The camera to project input rays through. |
| `get_mount` | `get_mount() -> Node3D` | The node carrying the offset: the mount, or the camera. |
| `distance` | `distance() -> float` | The current camera distance. |
| `pan` | `pan(screen_delta: Vector2) -> void` | Moves the rig: x along its local X, y along its local Z, times `pan_units_per_pixel * distance()`. |
| `zoom` | `zoom(amount: float) -> void` | Multiplies the distance by `(1 - zoom_step_fraction) ^ amount`, clamped: `amount` > 0 zooms in, < 0 out, and `zoom(-n)` undoes `zoom(n)`. Never moves the rig. |
| `rotate` | `rotate(screen_delta: Vector2) -> void` | Turns the rig's yaw by `-screen_delta.x * rotate_radians_per_pixel`. Never moves the rig. |
| `frame` | `frame(center: Vector3, new_distance: float) -> void` | Puts the rig over `center`, a world (global) point, keeping its world height, and sets the distance to `new_distance`, clamped. Works under a moved, turned or scaled parent; a rig outside the tree takes `center` as its local position. |

## Usage

Keyboard and gamepad control, a "jump to base" button, and a screen shake, in a script on
the same `World` node (this one replaces the mouse code above; `ui_left`, `ui_right`,
`ui_up`, `ui_down` are Godot's built-in arrow-key and D-pad actions):

```gdscript
extends Node3D

var orbit: LFOrbitCamera


func _ready() -> void:
	orbit = LFOrbitCamera.new($Rig, $Rig/Mount/Camera3D, $Rig/Mount)


# `delta` is the seconds since the last frame, so movement is the same at any frame rate.
func _process(delta: float) -> void:
	# The arrow keys give a direction from -1 to 1 on each axis; 600 is "pixels per second".
	var stick := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	orbit.pan(stick * 600.0 * delta)
	if Input.is_key_pressed(KEY_Q):
		orbit.rotate(Vector2(-300.0 * delta, 0.0))
	if Input.is_key_pressed(KEY_E):
		orbit.rotate(Vector2(300.0 * delta, 0.0))


func jump_to_base(base_position: Vector3) -> void:
	orbit.frame(base_position, 30.0)  # centre over the base, 30 units away
```

To add screen shake, put an `LFShaker` between `Mount` and `Camera3D`
(`Mount/Shaker/Camera3D`) and pass the camera's new path; the orbit camera moves only the
mount, so the shake never fights it.

A camera with its own settings, as a subclass (a class that extends this one):

```gdscript
# my_camera.gd
class_name MyCamera
extends LFOrbitCamera


func _init(pivot: Node3D, view_camera: Camera3D, mount: Node3D = null) -> void:
	super(pivot, view_camera, mount)
	max_distance = 140.0
```

## Notes

- Which way a pan moves on screen depends on how the camera is turned under the rig: with a camera looking along the rig's +Z (turned 180° from Godot's default) a positive x drag drags the ground along with the cursor. Negate the delta for the other feel.
- Point the camera at the rig once (for example `look_at` in the editor); zooming only scales the offset along its direction, so the look direction never changes.
- With a mount, the camera's own local transform is never written, so an `LFShaker` between the mount and the camera shakes freely and settles back to rest.
- Changing `min_distance`/`max_distance` takes effect on the next `zoom` or `frame` (the starting distance is not clamped either); keep `min_distance` at or below `max_distance`. A NaN zoom amount or distance is ignored.
- `pan` uses the rig's local axes and `rotate` only the yaw (the turn around the vertical axis); tilt (pitch, looking up or down) is fixed by where you place the mount, so a closer zoom keeps the same viewing angle.
