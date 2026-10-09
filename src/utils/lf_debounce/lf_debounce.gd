## Runs a callback once, a short delay after the last of a burst of calls.
##
## "Debounce" means: every call restarts the wait, and only the last call (with its
## arguments) runs once things go quiet for `delay_ms` milliseconds — e.g. saving a value
## 300 ms after the user stops dragging a slider. The delay is real time: it ignores
## `Engine.time_scale` and keeps running while the tree is paused, like `LFThrottle`.
## Needs a running SceneTree. Keep the instance referenced (a member variable): a freed
## debouncer's pending call never runs.
class_name LFDebounce

## Default delay in milliseconds: one 60 fps frame (about 16.7 ms).
const DEFAULT_DELAY_MS := 1000.0 / 60
## Milliseconds in one second, to turn `delay_ms` into the seconds a timer takes.
const _MS_PER_SECOND := 1000.0

## The wrapped callback.
var callback: Callable
## Delay in milliseconds after the latest `trigger()` before `callback` runs. A change
## applies from the next `trigger()`. A NaN is rejected: reported through `LFLogger` as an
## error, and the delay keeps its value.
var delay_ms: float:
	get:
		return _delay_ms
	set(value):
		if is_nan(value):
			_log.error('LFDebounce: a NaN delay_ms is rejected; keeping %s' % _delay_ms)
			return
		_delay_ms = value

static var _log := LFLogger.new()

var _delay_ms := DEFAULT_DELAY_MS
var _timer: SceneTreeTimer
## The latest call's arguments, until it runs or is dropped.
var _args: Array = []
var _scheduled := false


## A debouncer running `debounced_callback` `initial_delay_ms` milliseconds (sets
## `delay_ms`) after the latest `trigger()`. The default delay is one 60 fps frame (about
## 16.7 ms), also kept when `initial_delay_ms` is NaN (rejected).
func _init(debounced_callback: Callable, initial_delay_ms: float = DEFAULT_DELAY_MS) -> void:
	callback = debounced_callback
	delay_ms = initial_delay_ms


## Records these arguments and (re)starts the wait: `callback` runs `delay_ms` after the latest
## trigger, with the latest arguments. Rapid triggers restart one timer rather than
## creating one each. A callback whose object was freed is skipped without an error.
func trigger(...args: Array) -> void:
	_args = args
	if _scheduled and _timer != null and _timer.time_left > 0.0:
		_timer.time_left = delay_ms / _MS_PER_SECOND
		return
	_scheduled = true
	_timer = LFUtils.create_timer(delay_ms, _fire, true)


## Whether a call is scheduled and has not run yet.
func is_pending() -> bool:
	return _scheduled


## Drops the pending call, if any.
func cancel() -> void:
	if _timer != null and _timer.timeout.is_connected(_fire):
		_timer.timeout.disconnect(_fire)
	_timer = null
	_scheduled = false
	_args = []


## Runs the pending call now (once) instead of at the end of the delay; no-op if none.
func flush() -> void:
	if not _scheduled:
		return
	var args := _args
	cancel()
	_run(args)


func _fire() -> void:
	# Two triggers in one frame with a zero delay start two timers (the first one's
	# time_left is still 0); the second finds the call already run.
	if not _scheduled:
		return
	var args := _args
	_timer = null
	_scheduled = false
	_args = []
	_run(args)


func _run(args: Array) -> void:
	if callback.is_valid():
		callback.callv(args)


## Returns a Callable taking any arguments that, on each call, cancels any pending run and
## schedules `debounced_callback` with the latest arguments to run after `initial_delay_ms`
## milliseconds. Use `LFDebounce.new()` instead when you need `cancel()`/`flush()`.
static func fn(debounced_callback: Callable, initial_delay_ms: float = DEFAULT_DELAY_MS) -> Callable:
	var debouncer := LFDebounce.new(debounced_callback, initial_delay_ms)
	return func(...args: Array) -> void: debouncer.trigger.callv(args)
