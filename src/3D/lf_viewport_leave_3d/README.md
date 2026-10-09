# LFViewportLeave3D

> A `VisibleOnScreenNotifier3D` that reports (signal `left_viewport` plus an optional callback) once its node has stayed off-screen for a delay, with a max-timeout fallback that reports on its own after that much enabled time. The 3D counterpart of `LFViewportLeave`.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_viewport_leave_3d.gd` |
| **Tests** | `tests/test_lf_viewport_leave_3d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFViewportLeaveCore` (`src/2D/lf_viewport_leave/lf_viewport_leave_core.gd`, the internal timing logic shared with `LFViewportLeave`) |

## When to use it

Use it to clean up or react to 3D things that leave the screen: free an arrow that flew
out of view, despawn a unit the camera left behind, or stop animating a far-away prop.
Add it as a child of the node to watch, set its `aabb` and enable it.

Godot's built-in `VisibleOnScreenNotifier3D` emits `screen_entered`/`screen_exited` on
changes only. This node adds a `delay` (a node that comes back in time is not
reported), an enable gate (`disabled`), a check when tracking starts (a node already
off-screen when it is enabled or enters the tree enabled, or that left while disabled,
is reported after the delay too) and a `max_timeout` fallback counted in enabled time,
for a node that never shows up on screen at all. If you only need "free it the moment it
leaves", the built-in notifier is enough. For 2D nodes use `LFViewportLeave`.

## Step by step

Goal: a cube that flies off the screen and reports it a moment later.

1. *Scene → New Scene*, pick *3D Scene* (a `Node3D` root).
2. Add three children with *+ Add Child Node*:
   - `Camera3D`: set *Transform → Position* to `0, 0, 5`.
   - `MeshInstance3D`: set *Mesh* to *New BoxMesh* (click the empty Mesh slot).
   - `LFViewportLeave3D` (search "LFViewportLeave3D"). In the Inspector: *Delay* `1` (seconds
     the node must stay off-screen before it is reported) and **untick *Disabled***. It starts
     ticked (off), and an off notifier reports nothing. Leave *Aabb* at its default
     (a 2-unit box around the origin), which is big enough for the cube.
3. Select the root, click *Attach Script*, *Create*, and replace the contents with:

   ```gdscript
   extends Node3D

   func _ready() -> void:
   	# A signal is an event other code can listen to; run our function when it fires.
   	$LFViewportLeave3D.left_viewport.connect(_on_left_viewport)

   func _process(delta: float) -> void:   # delta = seconds since the last frame
   	position.x += 3.0 * delta            # move right, 3 world units per second

   func _on_left_viewport() -> void:
   	print("left the screen for 1 s")
   	queue_free()                         # remove this node, as you would for an arrow
   ```
4. Save the scene and press *F6*.

You should see the cube drift to the right and out of view. About a second after all of
it is gone the *Output* panel prints `left the screen for 1 s` and the node is removed.
Only a running game that draws to a window can see this; a headless run never reports
by visibility.

## API

Everything the class offers; you only need the rows used above to get started.

The same members as `LFViewportLeave`; see its README for the full descriptions.

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_DELAY` | `const float = 1.0` (seconds) | Default `delay`. |
| `DEFAULT_MAX_TIMEOUT` | `const float = 300.0` (seconds) | Default `max_timeout`. |
| `_init` | `LFViewportLeave3D.new(on_leave := Callable(), delay_seconds := DEFAULT_DELAY, max_timeout_seconds := DEFAULT_MAX_TIMEOUT)` (1.0, 300.0) | `on_leave` becomes `callback`, the others set `delay` and `max_timeout`. All arguments optional. |
| `left_viewport` | signal `left_viewport()` | Emitted once the node is reported as having left. |
| `delay` | `@export float = DEFAULT_DELAY` (1.0 seconds) | Seconds off-screen before reporting; `<= 0` reports on the exit itself (deferred). A NaN is rejected: reported through `LFLogger` as an error, and the value is kept. |
| `max_timeout` | `@export float = DEFAULT_MAX_TIMEOUT` (300.0 seconds) | Seconds of enabled time before reporting regardless of visibility; `<= 0` means none. A NaN is rejected like `delay`. Changing it later keeps the enabled time already counted. |
| `disabled` | `@export bool = true` | Gate; starts disabled. Writing it is the same as `set_disabled`. |
| `callback` | `var callback: Callable` | Called with no arguments after `left_viewport`; skipped once its object is freed. |
| `timer` | `Timer` (read-only) | One-shot delay timer. |
| `max_timer` | `Timer` (read-only) | One-shot max-timeout timer; `null` when `max_timeout <= 0`. |
| `set_disabled` | `set_disabled(state: bool) -> void` | Enabling resumes the max-timeout and, after the next drawn frame, starts the delay if the node is off-screen. Writing the current value does nothing. |
| `add_to` | `add_to(parent_node: Node) -> LFViewportLeave3D` | Adds itself as a child of `parent_node`; returns `self`. |
| `_is_on_screen_now` | `_is_on_screen_now() -> bool` | Overridable visibility query (`is_on_screen()`). |

## Usage

The same thing built from code, with a time limit. In the script of the node to watch (here an arrow projectile):

```gdscript
extends Node3D   # arrow.gd

func _ready() -> void:
	# Free the arrow once it has been off-screen for 2 s, or after 60 s at the latest.
	var leave := LFViewportLeave3D.new(queue_free, 2.0, 60.0).add_to(self)
	leave.aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))   # the arrow's bounds
	leave.left_viewport.connect(func() -> void: print("arrow left the view"))
	leave.set_disabled(false)   # start tracking (it starts disabled)
```

## Notes

- Set `aabb` to the parent's bounds; the default is a 2-unit cube around the origin.
- Without rendering (a headless run or a dedicated server) nothing is drawn: the notifier never emits and the on-enable check never runs, so only the max-timeout reports. Do not drive gameplay that must also run on a server from screen visibility.
- The other notes of `LFViewportLeave` apply unchanged (one report per departure, enabling an enabled notifier does nothing, retiming `max_timeout`, internal timers, timers pause with the tree).
