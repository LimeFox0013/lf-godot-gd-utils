## A multiplier that grows by a fixed step with every consecutive good result, up to a ceiling.
##
## Call `hit` on each good result and `reset` when the streak breaks. The value is computed
## from the hit count, not accumulated, so it never drifts. Bad arguments are reported
## through `LFLogger` and replaced by the defaults.
class_name LFStreakMultiplier
extends RefCounted

## Emitted after a `hit` or `reset` that changed the value.
signal changed(value: float)

## Default value with no streak.
const DEFAULT_BASE := 1.0
## Default growth per hit.
const DEFAULT_STEP := 0.2
## Default highest value.
const DEFAULT_CEILING := 5.0

## The value now. Read only: change it with `hit` and `reset`.
var value: float:
	get:
		return minf(_base + _step * _count, _ceiling)
## Hits since the last `reset`, including hits made at the ceiling. Read only.
var count: int:
	get:
		return _count

var _base: float
var _step: float
var _ceiling: float
var _count := 0
var _log := LFLogger.new(['LFStreakMultiplier'])


## A multiplier resting at `base`, growing `step` per hit, never above `ceiling`. A step of 0
## or less, a ceiling below `base` and any NaN or infinite argument use the default.
func _init(base := DEFAULT_BASE, step := DEFAULT_STEP, ceiling := DEFAULT_CEILING) -> void:
	_base = base
	if not is_finite(base):
		_log.error('the base must be finite, got', base)
		_base = DEFAULT_BASE
	_step = step
	if not is_finite(step) or step <= 0.0:
		_log.error('the step must be finite and above 0, got', step)
		_step = DEFAULT_STEP
	_ceiling = ceiling
	if not is_finite(ceiling) or ceiling < _base:
		_log.error('the ceiling must be finite and not below the base, got', ceiling)
		_ceiling = maxf(DEFAULT_CEILING, _base)


## Counts a hit, raises the value by one step up to the ceiling and returns it.
func hit() -> float:
	var before := value
	_count += 1
	var after := value
	if after != before:
		changed.emit(after)
	return after


## Ends the streak: the value returns to the base and the count to 0.
func reset() -> void:
	var before := value
	_count = 0
	if value != before:
		changed.emit(value)
