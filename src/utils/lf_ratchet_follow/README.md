# LFRatchetFollow

> A value that climbs smoothly after a target but only sinks slowly: the camera that follows a player up a tower.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_ratchet_follow.gd` |
| **Tests** | `tests/test_lf_ratchet_follow.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | nothing |

## When to use it

Use it for a camera (or a rising lava, a scrolling background) that should follow the player
**upward** but not jump back down when the player drops: climbing games, endless runners. It
is one number in, one number out, so it works for any axis, in 2D or 3D. For a camera that
follows in both directions use plain `lerp`; for an RTS camera use `LFOrbitCamera`.

## Step by step

This moves a square up after the mouse and lets it sink slowly.

1. In the editor choose *Scene → New Scene*, click **2D Scene**, then attach a script to the
   root `Node2D` (right-click → *Attach Script* → *Create*).
2. Replace the script's text with this:

```gdscript
extends Node2D

# Rises after the target (catch-up speed 2.0), sinks 40 pixels per second.
var _follow := LFRatchetFollow.new(2.0, 40.0)
var _height := -600.0   # the square starts 600 pixels down the screen

func _process(delta: float) -> void:
	var target := -get_global_mouse_position().y      # up is a higher number
	_height = _follow.step(_height, target, delta)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(300.0, -_height, 40.0, 40.0), Color.ORANGE)
```
3. Save and press **F6**. Move the mouse up: the square eases after it. Move the mouse down:
   the square sinks slowly and stops when it reaches the mouse.
4. Change `2.0` (how fast it catches up) and `40.0` (how fast it sinks; `0.0` = never).

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_FOLLOW_SPEED` | `const DEFAULT_FOLLOW_SPEED := 2.0` | Default catch-up speed. |
| `_init` | `LFRatchetFollow.new(initial_follow_speed := 2.0, initial_sink_speed := 0.0)` | |
| `follow_speed` | `var follow_speed: float` | Each step closes `1 - exp(-follow_speed * delta)` of the gap to a higher target, the same at any frame rate. 0 or less: never rises. |
| `sink_speed` | `var sink_speed: float` | Units per second the value drops towards a lower target. 0: never sinks. |
| `offset` | `var offset: float` | Added to the target (look above or below the player). |
| `min_value` | `var min_value: float` | The value never follows a target below this (the ground). Default `-INF`. |
| `step` | `step(current: float, target: float, delta: float) -> float` | The new value. `current` comes back unchanged for `delta <= 0` or a NaN. |

## Usage

A 3D camera rig that follows the player up from 4.5 units below them, never below the ground:

```gdscript
var _follow := LFRatchetFollow.new(2.0, 1.0)

func _ready() -> void:
	_follow.offset = -4.5
	_follow.min_value = 0.0

func _physics_process(delta: float) -> void:
	$CameraRig.position.y = _follow.step($CameraRig.position.y, player.global_position.y, delta)
```

## Notes

- It holds no per-value state: one follower object can drive any number of values, but give each its own if their speeds differ.
- The sink stops **at** the target, so a player standing still keeps the camera still.
- Read `current` from where the value really lives (the node's position), so other code that moves it stays respected.
