# LFViewportLeave

> A `VisibleOnScreenNotifier2D` that reports (signal `left_viewport` plus an optional callback) once its node has stayed off-screen for a delay, with a max-timeout fallback that reports on its own after that much enabled time.

| | |
|---|---|
| **Files** | `lf_viewport_leave.gd`, `lf_viewport_leave_core.gd` (`LFViewportLeaveCore`: internal timing logic shared with `LFViewportLeave3D`) |
| **Tests** | `tests/test_lf_viewport_leave.gd`, `tests/test_lf_viewport_leave_core.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFViewportLeave` | Node: add it to a scene |
| `LFViewportLeaveCore` | Part of `LFViewportLeave`, created for you |

## When to use it

Use it to clean up or react to things that leave the screen: free a bullet two seconds
after it flies out of view, despawn an enemy the player ran away from, or pause an
expensive effect nobody can see. Add it as a child of the node to watch and enable it.

Godot's built-in `VisibleOnScreenNotifier2D` emits `screen_entered`/`screen_exited` on
changes only. This node adds:
- a `delay`: a node that comes back within it is not reported;
- an enable gate (`disabled`), so tracking starts when you choose;
- a check when tracking starts: a node that is already off-screen when it is enabled (or
  enters the tree enabled), or that left while disabled, is reported after the delay too
  (the built-in would never emit for it);
- a `max_timeout` fallback that reports after that many seconds of *enabled* time
  whatever the visibility, for a node that never shows up on screen at all.

If you only need "free it the moment it leaves", the built-in `VisibleOnScreenNotifier2D`
with `screen_exited.connect(queue_free)` is enough. For 3D nodes use `LFViewportLeave3D`
(`src/3D/lf_viewport_leave_3d`).

## Step by step

Goal: a sprite that flies off the screen and reports it a moment later.

1. *Scene → New Scene*, pick *2D Scene* (a `Node2D` root).
2. Add a child `Sprite2D` (*+ Add Child Node*, search "Sprite2D"). Drag `icon.svg` from
   the FileSystem dock onto its *Texture* property.
3. Select the root again and add another child: search "LFViewportLeave" and *Create*.
   (It is a `VisibleOnScreenNotifier2D` with extras.) In the Inspector:
   - *Rect*: the area to watch, in pixels, around the node's origin. For the 128 x 128
     icon use position `-64, -64` and size `128, 128`.
   - *Delay*: `1`. Seconds the node must stay off-screen before it is reported.
   - *Disabled*: **untick it**. It starts ticked (off), and an off notifier reports nothing.
4. Select the root, click *Attach Script*, *Create*, and replace the contents with:

   ```gdscript
   extends Node2D

   func _ready() -> void:
   	# A signal is an event other code can listen to; run our function when it fires.
   	$LFViewportLeave.left_viewport.connect(_on_left_viewport)

   func _process(delta: float) -> void:   # delta = seconds since the last frame
   	position.x += 300.0 * delta          # slide right, 300 pixels per second

   func _on_left_viewport() -> void:
   	print("left the screen for 1 s")
   	queue_free()                         # remove this node, as you would for a bullet
   ```
5. Move the root to the middle of the window (*Transform → Position*, for example
   `576, 324`), save the scene, and press *F6*.

You should see the icon slide off the right edge. About one second after it is fully
out of view the *Output* panel prints `left the screen for 1 s` and the node disappears.
The notifier works only in a running game that draws to a window, not in a headless run.

## API

Everything the class offers; you only need the rows used above to get started.

### Constants

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_DELAY` | `const float = 1.0` (seconds) | Default `delay`. |
| `DEFAULT_MAX_TIMEOUT` | `const float = 300.0` (seconds) | Default `max_timeout`. |

### Constructor

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFViewportLeave.new(on_leave := Callable(), delay_seconds := DEFAULT_DELAY, max_timeout_seconds := DEFAULT_MAX_TIMEOUT)` (1.0, 300.0) | `on_leave` becomes `callback`, the others set `delay` and `max_timeout`. All arguments are optional, so the node can also be placed in a scene and configured in the Inspector. |

### Signals

| Member | Signature | Description |
|---|---|---|
| `left_viewport` | `left_viewport()` | Emitted once the node is reported as having left (by the delay or the max-timeout). |

### Exports

| Member | Signature | Description |
|---|---|---|
| `delay` | `float = DEFAULT_DELAY` (1.0 seconds) | Seconds the node must stay off-screen before it is reported. `<= 0` reports on the exit itself (deferred to the end of the frame). A NaN is rejected: reported through `LFLogger` as an error, and the value is kept. |
| `max_timeout` | `float = DEFAULT_MAX_TIMEOUT` (300.0 seconds) | Seconds of enabled time after which the node is reported regardless of visibility. `<= 0` means no fallback; A NaN is rejected: reported through `LFLogger` as an error, and the value is kept. Setting it later adds, retimes or removes the fallback timer; a retimed fallback keeps the enabled time it already counted. |
| `disabled` | `bool = true` | While true, visibility changes are ignored, a pending delay is stopped and the max-timeout is paused. **Starts disabled.** Writing it is the same as `set_disabled`. |

### Properties

| Member | Signature | Description |
|---|---|---|
| `callback` | `var callback: Callable` | Called with no arguments after `left_viewport` when the node is reported; skipped once its object is freed. May change at any time. |
| `timer` | `Timer` (read-only) | One-shot delay timer (`wait_time = delay`). |
| `max_timer` | `Timer` (read-only) | One-shot max-timeout timer; `null` when `max_timeout <= 0`. Paused while disabled. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `set_disabled` | `set_disabled(state: bool) -> void` | Setter of `disabled`. Enabling resumes the max-timeout where it left off and, after the next drawn frame, starts the delay if the node is off-screen. Writing the current value does nothing. |
| `add_to` | `add_to(parent_node: Node) -> LFViewportLeave` | Adds itself as a child of `parent_node`; returns `self` for chaining. |
| `_is_on_screen_now` | `_is_on_screen_now() -> bool` | Overridable: whether the node is on screen right now (`is_on_screen()`). Override it to substitute visibility where nothing is drawn (tests, headless runs). |

## Usage

The same thing built from code, with a time limit. In the script of the node to watch (here a bullet):

```gdscript
extends Node2D   # bullet.gd

func _ready() -> void:
	# Free the bullet once it has been off-screen for 2 s, or after 60 s at the latest.
	var leave := LFViewportLeave.new(queue_free, 2.0, 60.0).add_to(self)
	leave.rect = Rect2(-8, -8, 16, 16)   # the bullet's bounds, in its local space
	leave.set_disabled(false)            # start tracking (it starts disabled)
```

Or placed in the scene as a child named `Leave` (set its `rect`, `delay` and
`max_timeout` in the Inspector), listening to the signal:

```gdscript
extends Node2D   # enemy.gd

func _ready() -> void:
	$Leave.left_viewport.connect(_on_left_viewport)
	$Leave.disabled = false


func _on_left_viewport() -> void:
	print("enemy lost from view")
	queue_free()
```

## Notes

- Visibility is computed while a frame is drawn, so the check made on enabling (or on entering the tree enabled) runs after the next drawn frame, never before: a node just added on screen is not mistaken for an off-screen one.
- Without rendering (a headless run or a dedicated server) nothing is drawn: the notifier never emits and the on-enable check never runs, so only the max-timeout reports. Do not drive gameplay that must also run on a server from screen visibility.
- One departure is reported once: whichever of the delay and the max-timeout fires first stops the other. Later exits still start the delay again; the max-timeout is one-shot.
- Writing `disabled = false` on a notifier that is already enabled does nothing: a running delay keeps running, and a node already reported is not reported again. To check a node again, disable it, then enable it.
- Changing `max_timeout` while the fallback counts keeps the enabled time already counted: lowering it from 300 to 60 after 100 s reports at once, raising it to 400 reports 300 s later.
- Timers only tick while the notifier is in the tree, and they pause with the tree.
- The timers are internal children: they are not listed by `get_children()` and never saved with a scene.
- The notifier's `rect` keeps the `VisibleOnScreenNotifier2D` default; set it to match the parent's bounds.
