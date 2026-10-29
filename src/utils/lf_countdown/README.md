# LFCountdown

> A countdown clock driven by your game's own time: start, pause, resume, stop, restart, a signal every second and one at the end.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_countdown.gd` |
| **Tests** | `tests/test_lf_countdown.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger`, `LFText` |

## When to use it

Use it for a round timer, a bomb fuse, a "get ready" count, a wave break: anything that
counts down to zero and needs to show the time left. You call `tick(delta)` from
`_process` (so pausing the game or slowing time affects it too) and it emits `ticked`
every second and `finished` at the end; `text()` gives `1:05`-style text for a label.
For "do something every N seconds forever" use `LFIntervalTimer`; for a wait that
must follow the real clock, use a Godot `Timer` or `LFCooldown`; for timed turns
between participants use `LFTurnCycle`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node

   var countdown := LFCountdown.new(5.0)   # 5 seconds


   func _ready() -> void:
   	countdown.ticked.connect(func(remaining: float): print("left: ", countdown.text()))
   	countdown.finished.connect(func(): print("time is up"))
   	countdown.start()


   func _process(delta: float) -> void:
   	countdown.tick(delta)   # moves the countdown by the time since the last frame
   ```
4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
5. In the *Output* panel you should see `left: 0:04`, `left: 0:03`, ... `left: 0:00`, one line per second, then `time is up`.

## API

Everything the class offers; you only need the rows used above to get started. A *signal* is an event other code can listen to: `object.signal_name.connect(my_function)`.

| Member | Signature | Description |
|---|---|---|
| `new` | `LFCountdown.new(initial_duration: float = DEFAULT_DURATION_SECONDS, initial_tick_interval: float = DEFAULT_TICK_INTERVAL_SECONDS)` | A stopped countdown. Invalid values are reported through `LFLogger` and the defaults stay. |
| `DEFAULT_DURATION_SECONDS`, `DEFAULT_TICK_INTERVAL_SECONDS`, `MIN_TICK_INTERVAL_SECONDS` | `60.0`, `1.0`, `0.001` | Defaults and the shortest accepted tick interval. |
| `State` | `enum State { STOPPED, RUNNING, PAUSED, FINISHED }` | Where the countdown is. |
| `ticked` | `signal ticked(remaining: float)` | At the end of each whole tick interval, with the exact time left. A long `delta` emits one per covered interval. The last one, at 0, comes just before `finished`. |
| `finished` | `signal finished` | Once, when the time left reaches 0. |
| `duration` | `var duration: float` | Seconds in all; finite and above 0 (else reported and ignored). Changing it keeps the elapsed time. |
| `tick_interval` | `var tick_interval: float` | Seconds between `ticked` signals; at least `MIN_TICK_INTERVAL_SECONDS`. |
| `remaining` | `var remaining: float` | Seconds left. Read-only. |
| `state` | `var state: State` | Read-only. |
| `start` | `start() -> void` | Starts from the full duration; resumes a paused one; leaves a running one alone; starts a finished one over. |
| `pause` / `resume` | `pause() -> void`, `resume() -> void` | Hold and continue. Each does nothing in other states. |
| `stop` | `stop() -> void` | Stops and puts the full time back. No signal. |
| `restart` | `restart() -> void` | Starts over from the full duration, from any state. |
| `tick` | `tick(delta: float) -> bool` | Moves a running countdown. True on the call that finished it. Negative or non-finite `delta`: ignored. |
| `text` | `text(round_up: bool = true) -> String` | The time left as `m:ss` / `h:mm:ss` via `LFText.clock`. |
| `is_running`, `is_paused`, `is_finished` | `-> bool` | State checks. |
| `progress` | `progress() -> float` | 0.0 (full) to 1.0 (finished). |

## Usage

```gdscript
# A round timer in a script on a Node, shown in a Label named "TimerLabel".
extends Node

@onready var label: Label = $TimerLabel
var round_timer := LFCountdown.new(90.0)


func _ready() -> void:
	round_timer.ticked.connect(_refresh)
	round_timer.finished.connect(_on_round_over)
	round_timer.start()
	_refresh(round_timer.remaining)


func _process(delta: float) -> void:
	round_timer.tick(delta)


func set_paused(paused: bool) -> void:
	if paused:
		round_timer.pause()
	else:
		round_timer.resume()


func _refresh(_remaining: float) -> void:
	label.text = round_timer.text()


func _on_round_over() -> void:
	print("round over")
```

## Notes

- It takes no clock: it only moves when you call `tick`. A game that stops calling `tick` (a pause menu) stops the countdown.
- The countdown is not an `LFIntervalTimer` inside: that timer reports at most one fire per call, while a countdown must report every second a long `delta` covered, each with its own time left.
- Sums of small deltas are compared with a tiny slack (a billionth of a second), so ten steps of `0.1` finish a 1-second countdown instead of stopping a float error short.
- `delta` left over after the end is dropped. A tiny `tick_interval` with a huge `delta` emits that many `ticked` signals in one call.
- A signal handler that calls `stop`, `restart` or `pause` ends the `tick` in progress at once, so no stale signals follow.
- Changing `duration` while running keeps the seconds already elapsed: making it shorter than that finishes the countdown on the next `tick`.
