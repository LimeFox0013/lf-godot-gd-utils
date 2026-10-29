## A score built from new height only: climbing above the highest point reached earns points.
##
## Call `step` every frame with the current height. Height gained above the peak so far is paid
## at the multiplier you give, but only while the recent climb rate (averaged over a window) is
## above a minimum. Moving down, and regaining a height already reached, earn nothing and lose
## nothing. Bad arguments are reported through `LFLogger` and the call changes nothing.
class_name LFClimbScore
extends RefCounted

## Emitted after a `step` that raised the score.
signal changed(score: float)

## Default length of the window the climb rate is averaged over, in seconds.
const DEFAULT_RATE_WINDOW := 1.0

## Points so far. Read only: it changes with `step` and `reset`.
var score: float:
	get:
		return _score
## The highest height reached. Read only.
var peak: float:
	get:
		return _peak

var _window: float
var _score := 0.0
var _peak := 0.0
var _clock := 0.0
## Recent (time, height) samples, oldest first; the first one is at or just before the window start.
var _times: Array[float] = []
var _heights: Array[float] = []
var _log := LFLogger.new(['LFClimbScore'])


## A score whose climb rate is averaged over `rate_window` seconds. A window of 0 or less, or a
## NaN or infinite one, uses the default.
func _init(rate_window := DEFAULT_RATE_WINDOW) -> void:
	_window = rate_window
	if not is_finite(rate_window) or rate_window <= 0.0:
		_log.error('the rate window must be finite and above 0, got', rate_window)
		_window = DEFAULT_RATE_WINDOW
	reset()


## Zero score, `start_height` as the peak, no climb history.
func reset(start_height := 0.0) -> void:
	_score = 0.0
	_peak = start_height if is_finite(start_height) else 0.0
	_clock = 0.0
	_times.clear()
	_heights.clear()
	_times.append(0.0)
	_heights.append(_peak)


## Advances `delta` seconds at `height`. Height above the peak is added to the score times
## `multiplier`, unless the climb rate over the window is not above `min_rate`; the peak rises
## either way. Returns the points added by this call.
func step(height: float, multiplier: float, min_rate: float, delta: float) -> float:
	if not (is_finite(height) and is_finite(multiplier) and is_finite(min_rate)):
		_log.error('height, multiplier and min_rate must be finite, got', height, multiplier, min_rate)
		return 0.0
	if not is_finite(delta) or delta < 0.0:
		_log.error('delta must be finite and not negative, got', delta)
		return 0.0
	_clock += delta
	_remember(height)
	var climb_rate := _rate(height)
	var added := 0.0
	if height > _peak:
		if climb_rate > min_rate and multiplier > 0.0:
			added = (height - _peak) * multiplier
		_peak = height
	if added > 0.0:
		_score += added
		changed.emit(_score)
	return added


## Climb rate over the window in height per second, from the oldest sample still kept. The
## divisor is never shorter than the window, so a run's first moments read as slow.
func rate() -> float:
	return _rate(_heights[_heights.size() - 1])


func _rate(height: float) -> float:
	var span := maxf(_clock - _times[0], _window)
	return (height - _heights[0]) / span


func _remember(height: float) -> void:
	_times.append(_clock)
	_heights.append(height)
	# Keep one sample at or before the window start, drop what is older than that.
	while _times.size() > 2 and _times[1] <= _clock - _window:
		_times.pop_front()
		_heights.pop_front()
