## Reports each multiple of a fixed step the first time a value reaches it.
##
## Call `advance` with the current value (a height, a distance, a count). It returns the
## milestones crossed for the first time by that call, in order. Falling back and rising again
## reports nothing. Every `big_every`-th milestone is marked big.
class_name LFMilestones
extends RefCounted

## Default distance between milestones.
const DEFAULT_STEP := 10.0
## Default: every fifth milestone is big.
const DEFAULT_BIG_EVERY := 5
## The most milestones one `advance` call will report. A jump past it is refused.
const MAX_PER_CALL := 10000

## The distance between milestones. Read only.
var step: float:
	get:
		return _step
## The highest milestone number reported so far (0 before the first). Read only.
var reached: int:
	get:
		return _reached

var _step: float
var _big_every: int
var _reached := 0
var _log := LFLogger.new(['LFMilestones'])


## Milestones at `step`, `2 * step`, ... A step of 0 or less (or NaN or infinite) uses the
## default step; `big_every` below 1 uses the default.
func _init(step_size := DEFAULT_STEP, big_every := DEFAULT_BIG_EVERY) -> void:
	_step = step_size
	if not is_finite(step_size) or step_size <= 0.0:
		_log.error('the step must be finite and above 0, got', step_size)
		_step = DEFAULT_STEP
	_big_every = big_every
	if big_every < 1:
		_log.error('big_every must be at least 1, got', big_every)
		_big_every = DEFAULT_BIG_EVERY


## Milestones first reached at `value`, oldest first, each `{ "value": float, "number": int,
## "big": bool }`. A NaN or infinite value is reported and returns nothing. A value that would
## report more than `MAX_PER_CALL` milestones is reported and returns nothing, and nothing is
## counted as reached.
func advance(value: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_finite(value):
		_log.error('the value must be finite, got', value)
		return out
	var wanted: float = floor(value / _step)
	if wanted - float(_reached) > float(MAX_PER_CALL):
		_log.error('the value would report more than', MAX_PER_CALL, 'milestones in one call, got', value)
		return out
	var number := int(wanted)
	while _reached < number:
		_reached += 1
		out.append({
			'value': _reached * _step,
			'number': _reached,
			'big': _reached % _big_every == 0,
		})
	return out


## Forgets every milestone reported.
func reset() -> void:
	_reached = 0
