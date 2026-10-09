## Does something every N seconds of your game's own time: `tick(delta)` says when.
##
## A repeating interval advanced by the elapsed time you pass in (simulation time, not
## the wall clock): call `tick(delta)` from `_process` or `_physics_process` and it returns
## true each time `interval` seconds have accumulated — e.g. emit a pulse every 2 s.
## With `carry`, the overshoot past the interval counts toward the next one.
class_name LFIntervalTimer

## Default seconds between fires: 0, which fires on every tick.
const DEFAULT_INTERVAL_SECONDS := 0.0

static var _log := LFLogger.new()

## Seconds between fires; 0 or less fires on every tick, INF never fires on its own (only
## after `fire_next()`). A NaN is rejected: reported through `LFLogger` as an error, and the
## interval keeps its value. A change applies from the next `tick()`.
var interval: float:
	get:
		return _interval
	set(value):
		if is_nan(value):
			_log.error('LFIntervalTimer: a NaN interval is rejected; keeping %s' % _interval)
			return
		_interval = value
## Keep the overshoot past `interval` (true), or restart from zero after a fire (false).
## An infinite interval always restarts from zero.
var carry: bool
## Seconds accumulated toward the next fire.
var elapsed := 0.0

var _interval := DEFAULT_INTERVAL_SECONDS


## A timer firing every `interval_seconds` (0 or less: every tick; INF: never on its own;
## NaN: rejected, so `DEFAULT_INTERVAL_SECONDS` stays); `carry_overshoot` sets `carry`. `elapsed` starts at 0.
func _init(interval_seconds := DEFAULT_INTERVAL_SECONDS, carry_overshoot := true) -> void:
	interval = interval_seconds
	carry = carry_overshoot


## Adds `delta` (a non-finite or negative delta adds nothing) and returns true when the
## interval was reached — at most once per call; `drain()` fires what a long delta banked.
func tick(delta: float) -> bool:
	if _interval <= 0.0:
		elapsed = 0.0
		return true
	if is_finite(delta) and delta > 0.0:
		elapsed += delta
	if elapsed < _interval:
		return false
	elapsed = elapsed - _interval if carry and is_finite(_interval) else 0.0
	return true


## Consumes the whole intervals already banked, at most `max_fires` of them (a negative
## `max_fires` means no cap), and returns how many — the catch-up for a delta that covered
## several intervals. The count saturates at the largest int, so with an interval tiny next
## to `elapsed` pass a cap. Always 0 at an interval of 0 or less, or INF.
func drain(max_fires := -1) -> int:
	if _interval <= 0.0 or not is_finite(_interval) or elapsed < _interval or max_fires == 0:
		return 0
	var ratio := elapsed / _interval
	# int() of a float past the int range is platform-defined (INT_MIN on x86), so clamp first.
	var fires := 9223372036854775807 if ratio >= 9.2233720368547758e18 else int(ratio)
	if max_fires > 0:
		fires = mini(fires, max_fires)
	elapsed -= fires * _interval
	return fires


## Makes the next `tick()` fire.
func fire_next() -> void:
	elapsed = maxf(_interval, 0.0)


## Seconds until the next fire, never negative.
func time_left() -> float:
	return 0.0 if elapsed >= _interval else _interval - elapsed


## Starts the current interval over.
func restart() -> void:
	elapsed = 0.0
