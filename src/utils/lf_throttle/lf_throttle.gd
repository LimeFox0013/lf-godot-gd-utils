## Limits how often a callback runs, however often it is called: at most once per interval.
##
## For example, a drag preview updated at most every 100 ms while the mouse moves every
## frame. The interval is `interval_ms` of real (wall-clock) time. "Leading edge": the call
## that opens a window runs at once. "Trailing edge": the latest call the leading edge did
## not deliver runs when the window ends. The trailing wait ignores `Engine.time_scale`,
## like `LFDebounce`, and needs a running SceneTree.
##
## Use an instance for control (`trigger`, `cancel`, `flush`, `is_pending`), or `fn()` for a
## plain wrapped Callable. Keep the instance referenced (a member variable): a freed
## throttle's waiting trailing call never runs.
class_name LFThrottle

## Default window length in milliseconds: one 60 fps frame (about 16.7 ms).
const DEFAULT_INTERVAL_MS := 1000.0 / 60
## Window start before the first call, so the first call always opens a window.
const _NO_WINDOW_START := -INF

static var _log := LFLogger.new()


## Window length in real (wall-clock) milliseconds; may be fractional (ticks are whole
## milliseconds, so a window effectively lasts the next whole millisecond up). A NaN is
## rejected: reported through `LFLogger` as an error, and the interval keeps its value.
var interval_ms: float:
	get:
		return _interval_ms
	set(value):
		if is_nan(value):
			_log.error('LFThrottle: a NaN interval_ms is rejected; keeping %s' % _interval_ms)
			return
		_interval_ms = value
## Run the call that opens a window at once.
var leading: bool
## Run the latest undelivered call when the window ends. With this off, a call inside a
## window is dropped: nothing becomes pending and `flush()` has nothing to run.
var trailing: bool

var _interval_ms := DEFAULT_INTERVAL_MS
var _callback: Callable
var _window_start := _NO_WINDOW_START
var _pending := false
var _args: Array = []
var _scheduled := false
## Bumped by `cancel`/`flush`, so a trailing wait already underway knows it is stale.
var _generation := 0


## A throttle running `callback` at most once per `initial_interval_ms` milliseconds
## (sets `interval_ms`); `run_leading` and `run_trailing` set `leading` and `trailing`.
## At least one of them must be on: with neither, nothing could ever run, so the
## configuration is reported through `LFLogger` and the throttle stays as configured,
## never running (`trigger` does nothing until an edge is switched on).
func _init(callback: Callable, initial_interval_ms: float = DEFAULT_INTERVAL_MS, run_leading := true, run_trailing := false) -> void:
	_callback = callback
	interval_ms = initial_interval_ms
	leading = run_leading
	trailing = run_trailing
	if not leading and not trailing:
		_log.error("LFThrottle: leading and trailing are both false, so the callback could never run")


## Wraps `callback` in a new throttle (same arguments as `new()`) and returns a Callable
## taking any arguments that calls its `trigger`. Use `LFThrottle.new()` instead when you need
## `cancel()`/`flush()`.
static func fn(callback: Callable, initial_interval_ms: float = DEFAULT_INTERVAL_MS, run_leading := true, run_trailing := false) -> Callable:
	var throttle := LFThrottle.new(callback, initial_interval_ms, run_leading, run_trailing)
	return func(...args: Array) -> void: throttle.trigger.callv(args)


## A call through the throttle with `args`: runs `callback` now, later (trailing edge) or
## not at all, depending on the window and the edges. A callback whose object was freed
## is skipped without an error.
func trigger(...args: Array) -> void:
	if not leading and not trailing:
		return
	var now := Time.get_ticks_msec()
	if now - _window_start >= interval_ms:
		_window_start = now
		if leading:
			_pending = false
			_args = []
			_run(args)
			return
	if not trailing:
		# Leading only: a call inside a window is dropped, not kept for later.
		return
	_args = args
	_pending = true
	if not _scheduled:
		@warning_ignore("missing_await")
		_schedule()


## Whether a trailing call is waiting (always false with `trailing` off).
func is_pending() -> bool:
	return _pending


## Drops the waiting trailing call, if any.
func cancel() -> void:
	_generation += 1
	_scheduled = false
	_pending = false
	_args = []


## Runs the waiting trailing call now (opening a new window), if any; a no-op with
## `trailing` off, since nothing is ever kept.
func flush() -> void:
	if not _pending:
		return
	var args := _args
	cancel()
	_window_start = Time.get_ticks_msec()
	_run(args)


func _schedule() -> void:
	_scheduled = true
	var generation := _generation
	var wait_ms := maxf(_window_start + interval_ms - Time.get_ticks_msec(), 0.0)
	await LFUtils.create_timer(wait_ms, func() -> void: pass, true).timeout
	if generation != _generation:
		return
	_scheduled = false
	if not _pending:
		return
	if Time.get_ticks_msec() - _window_start < interval_ms:
		# A leading run moved the window while this waited: wait out the new one.
		@warning_ignore("missing_await")
		_schedule()
		return
	_pending = false
	_window_start = Time.get_ticks_msec()
	var args := _args
	_args = []
	_run(args)


func _run(args: Array) -> void:
	if _callback.is_valid():
		_callback.callv(args)
