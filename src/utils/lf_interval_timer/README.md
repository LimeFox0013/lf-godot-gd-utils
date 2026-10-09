# LFIntervalTimer

> Does something every N seconds of your game's own time, driven by the delta you pass in; fires at most once per tick.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_interval_timer.gd` |
| **Tests** | `tests/test_lf_interval_timer.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` (reports a rejected NaN interval) |

## When to use it

Use it for "every N seconds" logic inside code you already tick yourself: spawn an enemy
every 2 s, deal poison damage every 0.5 s, regenerate 1 mana per second. It is a plain
object, not a node, so you can keep hundreds of them (one per unit) and it pauses, speeds
up or replays exactly with whatever delta you feed it. For a one-off timer in a scene a
Godot `Timer` node or `LFUtils.timeout` is simpler; for limiting how often the player may
do something use `LFCooldown`.

## Step by step

This timer does not run by itself: you feed it the *delta* (the seconds since the last
frame) and it tells you when the interval has passed.

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock (top left) click
   *Other Node*, pick *Node*, and press *Create*.
2. Right-click the new node and choose *Attach Script*. Keep the defaults in the dialog
   and press *Create*. The script editor opens.
3. Select everything in the script and replace it with this code:

```gdscript
extends Node

# Fire every 2.0 seconds of game time.
var _timer := LFIntervalTimer.new(2.0)

# Godot calls _process every frame and gives the seconds since the last frame as `delta`.
func _process(delta: float) -> void:
	if _timer.tick(delta):   # true on the frame the 2 seconds are up
		print("Two seconds passed")
```
4. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
5. In the *Output* panel a line should appear every 2 seconds, for as long as the game
   runs.
6. Change `2.0` to your interval in seconds, and put your own action (spawn an enemy,
   deal poison damage) where the `print` is. `_timer.time_left()` tells you the seconds
   until the next fire, handy for a countdown bar. Use one timer per thing that needs its own
   rhythm.

## API

Everything the class offers; you only need the rows used above to get started.

### Properties

| Member | Signature | Description |
|---|---|---|
| `interval` | `var interval: float` | Seconds between fires; 0 or less fires on every tick; `INF` never fires on its own (only after `fire_next()`). A NaN is rejected: reported through `LFLogger` as an error, and the interval keeps its value. A change applies from the next `tick()`. |
| `carry` | `var carry: bool` | `true` keeps the overshoot past `interval`; `false` restarts from zero. An `INF` interval always restarts from zero. |
| `elapsed` | `var elapsed := 0.0` | Seconds accumulated toward the next fire. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_INTERVAL_SECONDS` | `const float = 0.0` (seconds) | Default `interval_seconds`: fires on every tick. |
| `_init` | `LFIntervalTimer.new(interval_seconds := DEFAULT_INTERVAL_SECONDS, carry_overshoot := true)` (0.0) | Sets `interval` (NaN: rejected, so 0.0 stays) and `carry`; `elapsed` starts at 0. |
| `tick` | `tick(delta: float) -> bool` | Adds `delta` (a non-finite or negative delta adds nothing); `true` when the interval was reached. Fires at most once per call. With `interval <= 0` it fires on every call and banks nothing (`elapsed` stays 0). |
| `drain` | `drain(max_fires := -1) -> int` | Consumes the whole intervals already banked, at most `max_fires` (negative: no cap), and returns how many (0 at `interval <= 0` or `INF`). Saturates at the largest int, so cap it when the interval is tiny next to `elapsed`. |
| `fire_next` | `fire_next() -> void` | The next `tick()` fires. |
| `time_left` | `time_left() -> float` | Seconds until the next fire, never negative. |
| `restart` | `restart() -> void` | Starts the current interval over (`elapsed` back to 0). Not `LFCooldown.reset`, which makes a cooldown ready at once. |

## Usage

```gdscript
# spawner.gd — on a Node2D that spawns enemies
extends Node2D

@export var enemy_scene: PackedScene

var _spawn_timer := LFIntervalTimer.new(2.0)   # every 2 s of game time

func _process(delta: float) -> void:
	if _spawn_timer.tick(delta):
		_spawn()
	# A long frame (e.g. after a hitch) may cover several intervals: catch up now.
	for i in _spawn_timer.drain():
		_spawn()

func _spawn() -> void:
	var enemy := enemy_scene.instantiate()
	add_child(enemy)
```

## Notes

- Simulation time, not real-world (wall-clock) time: it only advances by the deltas you pass, so it pauses
  and scales with whatever drives it. For wall-clock rate limiting use `LFThrottle`; for
  a wall-clock cooldown use `LFCooldown`.
- A delta covering several intervals (say a slow frame) fires once per call. With `carry` (keep the leftover time) the leftover
  fires on the following calls; to catch up within one frame, add `timer.drain()` fires after
  the `tick()` (never loop on `tick(0.0)`: at an interval of 0 that never ends).
- An `interval` of 0 or less fires every call without accumulating time, so switching to a
  positive interval later starts that interval from zero rather than firing on banked time.
