## A health pool: points that damage lowers, healing raises, and a maximum that bounds them.
##
## It holds only numbers and tells you what happened with signals, so it knows nothing about
## armor, stats or what dying means in your game: compute the final damage yourself and pass it
## in. `points` always stays between 0 and `max_points`. Dying is reaching 0: `died` is emitted
## once, and a dead pool ignores `damage` and `heal` until `reset()`.
class_name LFHealth
extends RefCounted


## Emitted by `damage` with the amount of health actually removed (never more than the pool
## held), before `died` when that damage was lethal.
signal damaged(amount: float)
## Emitted by `heal` with the amount of health actually restored (never more than the room left).
signal healed(amount: float)
## Emitted once when damage takes `points` to 0.
signal died
## Emitted by `set_max` when the maximum changed, with the new maximum.
signal max_changed(new_max: float)

## The maximum a pool has when none is given.
const DEFAULT_MAX_POINTS := 1.0
## What `percent()` multiplies the ratio by.
const PERCENT := 100.0

## The health now, from 0 to `max_points`. Read it; change it through the methods.
var points: float = DEFAULT_MAX_POINTS
## The most health the pool can hold. Change it with `set_max`.
var max_points: float = DEFAULT_MAX_POINTS

var _log := LFLogger.new(['LFHealth'])


## A full pool holding `initial_max` points (finite and above 0; otherwise reported through
## `LFLogger` and `DEFAULT_MAX_POINTS` is used).
func _init(initial_max: float = DEFAULT_MAX_POINTS) -> void:
	if _is_valid_max(initial_max):
		max_points = initial_max
	else:
		_log.error('the maximum must be finite and above 0, got', initial_max)
	points = max_points


## Removes `amount` points (0 or more; INF empties the pool) and returns `points` afterwards.
## Emits `damaged` with what was really removed, then `died` if the pool reached 0. An
## `amount` that is negative or NaN is reported through `LFLogger` and ignored. Does nothing,
## and emits nothing, for an amount of 0 or when the pool is already dead.
func damage(amount: float) -> float:
	if not _is_valid_amount(amount):
		return points
	if amount == 0.0 or is_dead():
		return points
	var removed := minf(amount, points)
	points -= removed
	damaged.emit(removed)
	if is_dead():
		died.emit()
	return points


## Restores `amount` points (0 or more), up to `max_points`, and returns `points` afterwards.
## Emits `healed` with what was really restored. An `amount` that is negative or NaN is
## reported through `LFLogger` and ignored. Does nothing, and emits nothing, for an amount of
## 0, a full pool or a dead one (use `reset` to bring it back).
func heal(amount: float) -> float:
	if not _is_valid_amount(amount):
		return points
	if amount == 0.0 or is_dead():
		return points
	var restored := minf(amount, max_points - points)
	if restored <= 0.0:
		return points
	points += restored
	healed.emit(restored)
	return points


## Sets the maximum (finite and above 0). With `grow_current`, raising the maximum raises
## `points` by the same difference (a living pool only; a dead one stays at 0); without it
## `points` stays as it is. Lowering the maximum lowers `points` to it when it is now above.
## Emits `max_changed` when the value changed, and neither `damaged` nor `healed`. An invalid
## value is reported through `LFLogger`, ignored, and returns false.
func set_max(new_max: float, grow_current: bool = true) -> bool:
	if not _is_valid_max(new_max):
		_log.error('the maximum must be finite and above 0, got', new_max)
		return false
	if new_max == max_points:
		return true
	if grow_current and new_max > max_points and not is_dead():
		points += new_max - max_points
	max_points = new_max
	points = minf(points, max_points)
	max_changed.emit(max_points)
	return true


## Fills the pool to `max_points`, bringing a dead one back. Emits no signal.
func reset() -> void:
	points = max_points


## Whether `points` is 0.
func is_dead() -> bool:
	return points <= 0.0


## Whether `points` equals `max_points`.
func is_full() -> bool:
	return points >= max_points


## `points` as a fraction of `max_points`, from 0.0 to 1.0.
func ratio() -> float:
	return clampf(points / max_points, 0.0, 1.0)


## `points` as a percentage of `max_points`, from 0.0 to 100.0.
func percent() -> float:
	return ratio() * PERCENT


func _is_valid_amount(amount: float) -> bool:
	if is_nan(amount) or amount < 0.0:
		_log.error('an amount must be 0 or more, got', amount)
		return false
	return true


func _is_valid_max(value: float) -> bool:
	return is_finite(value) and value > 0.0
