## A cooldown: an action may run again only once `interval_ms` has passed since its last use.
##
## Always ready before its first use. Check it with `is_ready()`, or check and spend it in
## one call with `try_use()` — e.g. an action usable once every 1.5 s.
##
## Time comes from `clock_ms` — a Callable returning milliseconds — or, without one, the
## wall clock (`Time.get_ticks_msec()`). A simulation on its own time (paused, sped up,
## replayed from a seed) passes its own clock; then only that clock readies it. A supplied
## clock that becomes unusable (its object freed) keeps the cooldown closed and reports an
## error, rather than silently switching to wall time.
class_name LFCooldown

static var _log := LFLogger.new()


## Milliseconds that must pass after a use before the next (may be fractional; 0 or less is
## always ready, INF never ready after a use). A NaN is rejected: reported through
## `LFLogger` as an error, and the interval keeps its value (0 right after construction).
## May change at any time; every check reads the current value.
var interval_ms: float:
	get:
		return _interval_ms
	set(value):
		if is_nan(value):
			_log.error("LFCooldown: a NaN interval is rejected; keeping %s" % _interval_ms)
			return
		_interval_ms = value

## Returns "now" in milliseconds as an int or a float. Empty: the wall clock
## (`Time.get_ticks_msec()`). Replaceable at any time, e.g. by a simulation's own clock.
var clock_ms: Callable

var _interval_ms: float
var _used := false
var _last_ms := 0.0
var _clock_error_reported := false


## A cooldown of `initial_interval_ms` milliseconds, ready at once. `initial_clock_ms`, when given,
## is a Callable returning the current time in milliseconds as an int or a float (a
## simulation's own clock); without it the wall clock is used. Constructing never reads
## the clock.
func _init(initial_interval_ms: float, initial_clock_ms := Callable()) -> void:
	interval_ms = initial_interval_ms
	clock_ms = initial_clock_ms


## Whether a use would pass now. Never changes the cooldown. A clock reading earlier than the
## last use (it was reset or rewound) counts as elapsed.
func is_ready() -> bool:
	if !_used:
		return _clock_usable()
	var now: Variant = _now()
	if now == null:
		return false
	return now < _last_ms or now - _last_ms >= interval_ms


## Uses the cooldown if it is ready: starts a new interval and returns true; otherwise
## returns false and leaves it untouched.
func try_use() -> bool:
	if !is_ready():
		return false
	start()
	return true


## Starts a new interval now, whether or not the cooldown was ready. Does nothing when a
## supplied clock can no longer be called.
func start() -> void:
	var now: Variant = _now()
	if now == null:
		return
	_used = true
	_last_ms = now


## Makes the cooldown ready immediately.
func reset() -> void:
	_used = false


## Milliseconds until the cooldown is ready; 0 when it already is (handy for a "2.3 s"
## label on a button). With an unusable clock, the full `interval_ms`.
func remaining_ms() -> float:
	if is_ready():
		return 0.0
	var now: Variant = _now()
	if now == null: # the supplied clock's object was freed
		return interval_ms
	return maxf(interval_ms - (now - _last_ms), 0.0)


func _clock_usable() -> bool:
	if clock_ms.is_null() or clock_ms.is_valid():
		return true
	_report_clock_error()
	return false


## The current time in milliseconds, or null when a supplied clock can no longer be called.
func _now() -> Variant:
	if clock_ms.is_null():
		return float(Time.get_ticks_msec())
	if !clock_ms.is_valid():
		_report_clock_error()
		return null
	return float(clock_ms.call())


func _report_clock_error() -> void:
	if !_clock_error_reported:
		_clock_error_reported = true
		_log.error("LFCooldown: its clock can no longer be called; the cooldown stays closed")
