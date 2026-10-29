# LFExperienceLevels

> An experience track: gain experience, level up when a level's threshold is reached, and carry the left-over experience into the next levels.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_experience_levels.gd` |
| **Tests** | `tests/test_lf_experience_levels.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it for "kill enemies, collect experience, reach the next level": a character that
levels up in an action game, a weapon that gets better the more it is used, a battle pass.
You list how much experience each level step needs and call `gain(amount)`; it raises the
level (one big amount can raise several), keeps the remainder, and tells you with a signal.
It counts levels only. What a level gives (more damage, a new skill) is yours: keep it in
an array indexed by `level`. For upgrades bought with points use `LFUnlockTree`; for a
count of how often something was taken up to a cap use `LFCappedLevelTracker`; for
per-level bonuses that add up per stat use `LFModifierLevels`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	# Level 0 -> 1 needs 10 experience, 1 -> 2 needs 20, 2 -> 3 needs 40.
   	var track := LFExperienceLevels.new([10, 20, 40])
   	track.leveled_up.connect(func(new_level: int): print("reached level ", new_level))

   	track.gain(35)   # pays for level 1 (10) and level 2 (20); 5 is left over
   	print("level ", track.level, ", progress ", track.progress())
   ```
4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
5. In the *Output* panel you should see `reached level 1`, `reached level 2`, then `level 2, progress 0.125` (5 of the 40 needed for level 3).

## API

Everything the class offers; you only need the rows used above to get started. A *signal* is an event other code can listen to: `object.signal_name.connect(my_function)`.

| Member | Signature | Description |
|---|---|---|
| `new` | `LFExperienceLevels.new(thresholds: Array = [], start_level: int = 0)` | Thresholds are the experience each level step needs (numbers of 0 or more). A bad threshold is reported through `LFLogger` and counts as 0. An invalid `start_level` is reported and the track starts at 0. |
| `leveled_up` | `signal leveled_up(new_level: int)` | Once per level gained, in order. Not emitted by `set_level`, `set_thresholds` or `reset`. |
| `experience_gained` | `signal experience_gained(amount: float)` | At the end of every accepted `gain`, after the `leveled_up` signals. Not emitted at the top level. |
| `level` | `var level: int` | The current level, 0 to `max_level`. Read it; change it through the methods. |
| `experience` | `var experience: float` | Experience held toward the next level (0 at the top level). |
| `max_level` | `var max_level: int` | The highest level: the number of thresholds. |
| `gain` | `gain(amount: float) -> int` | Adds experience and returns how many levels it gained. A negative or non-finite amount is reported and ignored. Does nothing at the top level. |
| `set_level` | `set_level(new_level: int) -> bool` | Jumps to a level with no experience, no signal. False (and an error through `LFLogger`) when outside 0 to `max_level`. |
| `reset` | `reset() -> void` | Level 0, no experience, no signal. |
| `set_thresholds` | `set_thresholds(thresholds: Array, start_level: int = 0) -> void` | Replaces the thresholds and starts over at `start_level`. |
| `get_thresholds` | `get_thresholds() -> PackedFloat64Array` | A copy of the thresholds. |
| `is_max` | `is_max() -> bool` | True at the top level, and for a track with no thresholds. |
| `next_threshold` | `next_threshold() -> float` | Experience the current level step needs; `INF` at the top level. |
| `progress` | `progress() -> float` | 0.0 to 1.0 through the current level; 1.0 at the top level and when the step needs 0. |

## Usage

```gdscript
# A script on a character. What each level gives is a plain array in the game.
extends Node

const THRESHOLDS := [10, 20, 40, 80]
const DAMAGE_BY_LEVEL := [5.0, 6.0, 8.0, 11.0, 15.0]   # one more entry than thresholds

var levels := LFExperienceLevels.new(THRESHOLDS)


func _ready() -> void:
	levels.leveled_up.connect(_on_leveled_up)
	levels.experience_gained.connect(_on_experience_gained)


func damage() -> float:
	return DAMAGE_BY_LEVEL[levels.level]


func on_enemy_killed(reward: float) -> void:
	levels.gain(reward)


func _on_leveled_up(new_level: int) -> void:
	print("level ", new_level, ", max: ", levels.is_max())


func _on_experience_gained(_amount: float) -> void:
	print("xp bar at ", int(levels.progress() * 100.0), "%")
```

## Notes

- A level's threshold is the experience for that one step, not a running total: with `[10, 20]`, reaching level 2 takes 30 in all. Experience left over after a level-up counts toward the next step.
- A threshold of 0 is passed as soon as the track is asked to move: `gain(0)` is enough. `progress()` reports 1.0 for such a step instead of dividing by zero.
- At the top level experience is not kept: `experience` stays 0 and `gain` does nothing. Add your own total if you want a lifetime score.
- `set_level` and `reset` are for loading a save or starting over, so they stay silent; call your own refresh code after them.
- The class holds no per-level data and never touches the scene tree.
