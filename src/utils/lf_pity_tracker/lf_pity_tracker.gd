## Bad-luck protection ("pity"): after too many poor results in a row, it raises the minimum tier for the next roll.
##
## Record each outcome's tier (a quality level as an int, e.g. 0 low, 1 high). Every
## outcome below `threshold` is a miss and extends the streak; once the streak reaches
## `streak_length`, `floor_tier()` raises the minimum tier of the next roll to `threshold`,
## until a hit (an outcome at or above `threshold`) resets the streak. It rolls nothing:
## the guarantee holds only if your roll honours `floor_tier()`. One tracker is one shared
## streak across everything recorded into it.
class_name LFPityTracker


## Emitted when a miss brings the streak to exactly `streak_length` and the guarantee
## turns on — once per streak, not again for later misses of the same streak. Lowering
## `streak_length` to or below the current streak turns the guarantee on without it.
signal activated

## Misses in a row needed by default before the guarantee turns on.
const DEFAULT_STREAK_LENGTH := 10
## The tier an outcome must reach by default to count as a hit.
const DEFAULT_THRESHOLD := 1
## The shortest `streak_length` that keeps the guarantee on; any shorter turns it off.
const _MIN_STREAK_LENGTH := 1

## Misses in a row needed to turn the guarantee on; below 1, the guarantee is off.
## May be changed at any time.
var streak_length: int
## The tier an outcome must reach to count as a hit, and the minimum tier while the
## guarantee is on.
var threshold: int
## Misses in a row so far (0 after a hit or `reset()`).
var streak := 0


## A tracker that turns on after `initial_streak_length` outcomes in a row below
## `initial_threshold`.
func _init(initial_streak_length := DEFAULT_STREAK_LENGTH, initial_threshold := DEFAULT_THRESHOLD) -> void:
	streak_length = initial_streak_length
	threshold = initial_threshold


## Whether the guarantee is on: the streak has reached `streak_length` (never with a
## length below 1). Stays on until a hit.
func is_active() -> bool:
	return streak_length >= _MIN_STREAK_LENGTH and streak >= streak_length


## The minimum tier for the next outcome: `base` (your usual minimum), raised to
## `threshold` while the guarantee is on. Changes nothing.
func floor_tier(base := 0) -> int:
	return maxi(base, threshold) if is_active() else base


## Records an outcome by its tier: at or above `threshold` is a hit (resets the streak),
## below it a miss (extends it, emitting `activated` when it reaches `streak_length`).
func record(tier: int) -> void:
	record_outcome(tier >= threshold)


## Records an outcome without a tier: `hit` true resets the streak, false extends it
## (emitting `activated` when it reaches `streak_length`). For yes/no outcomes such as
## "did the roll give anything".
func record_outcome(hit: bool) -> void:
	if hit:
		streak = 0
		return
	streak += 1
	if streak_length >= _MIN_STREAK_LENGTH and streak == streak_length:
		activated.emit()


## Clears the streak (the guarantee turns off) without emitting anything.
func reset() -> void:
	streak = 0
