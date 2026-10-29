# LFClimbScore

> A score that pays only for new height reached, weighted by a multiplier and ignoring slow climbing.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_climb_score.gd` |
| **Tests** | `tests/test_lf_climb_score.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it for a climbing or endless-ascent game where the score is the height gained: it pays only above the highest point so far, so falling and climbing back costs and earns nothing. For a counter of things done use `LFExperienceLevels`; for a multiplier that grows with a streak use `LFStreakMultiplier` and pass its value in.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*.
3. Replace everything in the script with the code below (the `#` text is a note that Godot ignores):

   ```gdscript
   extends Node

   # Averages the climb rate over 1 second.
   var score := LFClimbScore.new()


   func _ready() -> void:
   	# Frames of 0.5 s: climb to 4 m, fall to 1 m, climb back to 6 m. The multiplier is x2,
   	# anything slower than 1 m/s is ignored.
   	for h in [2.0, 4.0, 1.0, 4.0, 6.0]:
   		score.step(h, 2.0, 1.0, 0.5)
   	print(score.peak)   # 6.0
   	print(score.score)  # 12.0: 4 + 4 for the climb to 4 m, 4 for the 4 m to 6 m
   ```
4. Press **F6** (*Run Current Scene*) and save the scene when asked, for example as `test.tscn`.
5. In the *Output* panel you should see the peak (`6.0`) and the score `12.0`: the fall to 1 m and the climb back to 4 m earn nothing.

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_RATE_WINDOW` | `1.0` | Default averaging window in seconds. |
| `new` | `LFClimbScore.new(rate_window := DEFAULT_RATE_WINDOW)` | A window of 0 or less, NaN or infinite is reported through `LFLogger` and the default is used. |
| `step` | `step(height, multiplier, min_rate, delta) -> float` | Advances `delta` seconds at `height`; pays height above the peak at `multiplier` if the window's climb rate is above `min_rate`; returns the points added. A NaN or infinite height, multiplier or min_rate, or a negative or non-finite delta, is reported and changes nothing. |
| `rate` | `rate() -> float` | The climb rate over the window now, height per second. |
| `reset` | `reset(start_height := 0.0) -> void` | Score 0, the peak at `start_height`, no history. |
| `score` | `var score: float` | Points so far. Read only. |
| `peak` | `var peak: float` | The highest height reached. Read only. |
| `changed` | `signal changed(score: float)` | After a `step` that raised the score. |

## Usage

Call `step` once per frame with the current height, your multiplier, the slowest climb rate worth paying (height per second) and the frame time. Read `score` and `peak` at any time, connect `changed` to refresh a display, and call `reset` when a run starts.

## Notes

- The peak rises even when the climb was too slow to pay, so slow height is never paid later.
- The rate is the height gained over the oldest kept sample divided by at least the window length, so the first moments after `reset` read as slow.
- Pass a minimum rate of 0 to pay every climb.
