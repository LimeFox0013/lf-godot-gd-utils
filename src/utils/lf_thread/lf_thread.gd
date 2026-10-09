## Runs one slow task (a function) on a background thread, where the build supports
## threads, so the main thread doesn't freeze.
##
## A worker thread runs code in parallel with the main thread that draws the frames; it must
## not touch the scene tree (nodes). A task started with [method start_cancelable] gets a
## `should_stop` Callable to check now and then; [method request_stop] makes it return true.
## Nothing is reported until you call [method poll] (e.g. every frame in `_process`) or
## [method join_now], which collect a finished task and emit [signal finished] or
## [signal canceled]. Freeing a running instance asks the task to stop, then waits for it.
##
## Without thread support (a web export built without threads, the default since Godot 4.3,
## or [member force_main_thread] on) there is no worker: the task runs on the thread that
## calls [method poll] or [method join_now], at the first such call, and blocks it until it
## returns. The signals, return values and polling contract stay the same.
class_name LFThread
extends RefCounted

## Emitted by `start` once the task is accepted: the worker thread has been launched, or,
## without thread support, the task waits for the first [method poll].
signal started(id: String, key: String)
## Emitted by [method poll] or [method join_now] when the task has ended and no stop was
## requested. [param result] is the task's return value.
signal finished(id: String, key: String, result: Variant)
## Emitted instead of [signal finished] when [method request_stop] was called before the
## task was collected. [param result] is whatever the task returned.
signal canceled(id: String, key: String, result: Variant)

## Prefix of every generated [member id].
const _ID_PREFIX := 'lf-thread'
## Microseconds in one second, to turn the monotonic clock into seconds.
const _USEC_PER_SEC := 1000000.0
## The engine feature tag present on builds that can run threads.
const _THREADS_FEATURE := 'threads'

## Runs every task without a worker thread, as on a build without thread support (a
## process-wide switch, off by default). Meant for tests and for trying a game's
## no-threads behaviour on desktop; a run already started keeps its mode.
static var force_main_thread := false

## Optional label passed through every signal and `get_info`.
var key: String = ''
## Unique id of this thread wrapper, generated as `lf-thread-<uuid>`.
var id: String = LFUuid.gen(_ID_PREFIX)

var _thread: Thread
## The stop request, in a one-element box the worker reads without touching this object
## (`start`): the worker must never hold a reference to this object, or the last one
## could drop on the worker and free it there.
var _stop_box: Array = [false]
var _stop_flag: bool:
	get:
		return _stop_box[0]
## Unix timestamps in fractional seconds; 0.0 until set.
var _started_at := 0.0
var _ended_at := 0.0
## Monotonic microseconds, for the duration.
var _started_usec := 0
var _ended_usec := 0
var _result: Variant = null
var _running: bool = false
## The task waiting to run on the polling thread, when there is no worker; empty otherwise.
var _inline_task: Callable = Callable()
var _threaded := false


## Creates an idle thread wrapper. [param initial_key] becomes [member key].
func _init(initial_key: String = '') -> void:
	key = initial_key


## Whether a task started now would get a worker thread: the build supports threads and
## [member force_main_thread] is off. When false, tasks run (and block) at the first
## [method poll] or [method join_now].
static func threads_available() -> bool:
	return OS.has_feature(_THREADS_FEATURE) and not force_main_thread


## Runs `task` (called with no arguments) on a new worker thread. Returns true on
## success; false if already running or `task` is not a valid Callable (empty, or its
## object was freed). When no worker can be started ([method threads_available] is false,
## or `Thread.start` fails) it still returns true and the task runs, blocking, at the first
## [method poll] or [method join_now]. A method Callable does not keep its object alive
## until the call begins — capture what the task needs in a lambda instead.
func start(task: Callable) -> bool:
	return _launch(task, false)


## Like `start`, but `task` receives a `should_stop` Callable as its first argument, to
## poll and return early once `request_stop` was called (or the thread is being freed).
func start_cancelable(task: Callable) -> bool:
	return _launch(task, true)


func _launch(task: Callable, cancelable: bool) -> bool:
	if _running or not task.is_valid():
		return false
	_stop_box = [false]
	_result = null
	_started_at = Time.get_unix_time_from_system()
	_started_usec = Time.get_ticks_usec()
	_ended_at = 0.0

	# The worker runs only this lambda, which captures the task and the stop box, never
	# `self` — so nothing on the worker refers to this object.
	var stop_box := _stop_box
	var should_stop_now := func() -> bool: return stop_box[0]
	var job: Callable
	if cancelable:
		job = func() -> Variant: return task.call(should_stop_now)
	else:
		job = func() -> Variant: return task.call()

	_threaded = false
	_thread = null
	_inline_task = Callable()
	if threads_available():
		_thread = Thread.new()
		if _thread.start(job) == OK:
			_threaded = true
		else:
			_thread = null
	if not _threaded:
		_inline_task = job

	_running = true
	started.emit(id, key)
	return true


## Asks a cancelable task to stop as soon as it next checks. A request made before
## `start` does not carry over to the new run.
func request_stop() -> void:
	_stop_box[0] = true


## Whether a stop was requested for the current run.
func is_stop_requested() -> bool:
	return _stop_flag


## True when the thread was never started or has been finalized. A task that has
## ended but was not yet polled or joined still counts as running.
func is_done() -> bool:
	return not _running


## Whether the current (or last) run got a worker thread; false when it runs on the
## polling thread instead (see [method threads_available]) or was never started.
func is_threaded() -> bool:
	return _threaded


## Blocks (freezes the calling thread) until the task ends, then collects it like
## [method poll] does. Without a worker it runs the task here. Returns true if a join
## happened; false if nothing was running, or (without a worker) when the task itself calls
## it, since the task is then already running on this thread.
func join_now() -> bool:
	if not _running:
		return false
	if not _threaded:
		return _run_inline()
	var result: Variant = _thread.wait_to_finish()
	_finalize(result)
	return true


## Non-blocking while a worker runs the task; call it from your own loop. Once the task
## has ended, joins it, stores the result and emits `finished` or `canceled`. Without a
## worker, the first call runs the whole task here (blocking) and then does the same.
func poll() -> void:
	if not _running:
		return
	if not _threaded:
		_run_inline()
		return
	if not _thread.is_alive():
		var result: Variant = _thread.wait_to_finish()
		_finalize(result)


## The task's return value; null until finalized.
func get_result() -> Variant:
	return _result


## A status snapshot: id, key, running, threaded, started_at, ended_at, duration_sec,
## stop_requested. Timestamps are fractional unix
## seconds; `duration_sec` comes from the monotonic clock, so a clock change never skews it.
func get_info() -> Dictionary:
	return {
		'id': id,
		'key': key,
		'running': _running,
		'threaded': _threaded,
		'started_at': _started_at,
		'ended_at': _ended_at,
		'duration_sec': _duration_sec(),
		'stop_requested': _stop_flag
	}


func _duration_sec() -> float:
	if _ended_at > 0.0:
		return (_ended_usec - _started_usec) / _USEC_PER_SEC
	if _running:
		return (Time.get_ticks_usec() - _started_usec) / _USEC_PER_SEC
	return 0.0


## Freed while still running (its owner torn down mid-task): ask the task to stop, then
## join it, so the Thread is never destroyed unfinished. Safe, since the worker never
## refers to this object (`start`). A task that ignores the request is waited out. A task
## waiting for its first poll (no worker) is dropped without running.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _running and _thread != null:
		_stop_box[0] = true
		_thread.wait_to_finish()
		_running = false


## Runs the waiting task on the calling thread, then collects it. False, doing nothing,
## when no task is waiting: it is already running further up this thread's stack (the
## task itself called [method poll] or [method join_now]), and is collected when it returns.
func _run_inline() -> bool:
	var job := _inline_task
	if not job.is_valid():
		return false
	_inline_task = Callable()
	_finalize(job.call())
	return true


func _finalize(result: Variant) -> void:
	_running = false
	_result = result
	_ended_at = Time.get_unix_time_from_system()
	_ended_usec = Time.get_ticks_usec()

	(canceled if _stop_flag else finished).emit(id, key, _result)
