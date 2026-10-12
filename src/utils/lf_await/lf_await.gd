## Waits for several coroutines at once: until all of them finish, or until the first one does.
##
## Runs a batch of callables (functions, possibly using `await` inside) together on the
## calling thread (they interleave at their `await`s; nothing moves to another thread) and
## resolves when all of them (`all`) or the first one (`any`) has finished — like
## JavaScript's `Promise.all`/`Promise.race`. Most code only needs the static
## `LFAwait.all(fns)` / `LFAwait.any(fns)`; an instance adds progress (`done_count`) and a
## per-callable hook (`on_fn_awaited`).
##
## A batch runs once per `reset()`: a second `exec()` waits for (or returns) the same run
## rather than starting the callables again. A callable whose owner is freed while it
## awaits never finishes, so neither does the batch — don't put such a callable in one.
## An invalid callable (empty, or its object already freed) counts as finished with `null`
## and reports an error.
class_name LFAwait

## The `backoff` of `retry` when none is given: every wait is as long as the first.
const DEFAULT_RETRY_BACKOFF := 1.0
## The delay `retry` uses in place of a NaN `delay_ms` or `backoff` (after reporting it).
const FALLBACK_RETRY_DELAY_MS := 0.0

static var _log := LFLogger.new()


## Emitted with the results once every callable has finished (or, under `any`, on the
## first finish).
signal awaited(results: Array)
## Emitted when a run ends, by completing or by `reset()`; wakes the callers of `exec()`.
signal _settled

## Called as `(result, fn)` after each callable in the batch finishes (for a progress bar,
## say). Leave it empty when not needed.
var on_fn_awaited: Callable

var _fns: Array = []
var _results: Array = []
var _done := 0
var _complete := false
var _started := false
## Under `any`: the first finisher completes the run and is the result.
var _first_wins := false
var _winner: Variant = null
## Bumped by `reset()`, so a callable still running from an earlier batch is ignored.
var _generation := 0


## Creates an awaiter for `batch`, an Array of Callables. Nothing runs until `exec()`.
func _init(batch: Array = []) -> void:
	reset(batch)


## Starts over with `batch` (the current one when omitted; the array is copied) and returns
## `self`. Results an earlier run returned are left as they were. A caller still awaiting
## `exec()` of the earlier run is released with that run's results so far (`null` in the
## slots of callables that had not finished).
func reset(batch: Array = _fns) -> LFAwait:
	_generation += 1
	_fns = batch.duplicate()
	_results = []
	_results.resize(batch.size())
	_done = 0
	_complete = false
	_started = false
	_winner = null
	_settled.emit()
	return self


## How many callables of the current batch have finished.
func done_count() -> int:
	return _done


## Whether the current run has completed.
func is_complete() -> bool:
	return _complete


## Coroutine (use it with `await`). Starts the batch (once per `reset()`), waits until
## every callable has finished, and returns their results in batch order (`[]` for an
## empty batch).
func exec() -> Array:
	var results := _results
	if not _started:
		_started = true
		var generation := _generation
		for index in _fns.size():
			@warning_ignore("missing_await")
			_run(_fns[index], index, generation)
	if not _complete and _done < _fns.size():
		await _settled
	return results


## Coroutine (use it with `await`). Runs every callable in `fns` together and resolves with
## their results in input order once all have finished; `[]` for an empty array.
static func all(fns: Array) -> Array:
	return await LFAwait.new(fns).exec()


## Coroutine. Runs every callable in `fns` and resolves with the first one to finish's
## result; the rest keep running. `null` for an empty batch.
static func any(fns: Array) -> Variant:
	if fns.is_empty():
		return null
	var awaiter := LFAwait.new(fns)
	awaiter._first_wins = true
	await awaiter.exec()
	return awaiter._winner


## Coroutine. Calls `fn` (which may `await`) until it gives a result `accept` takes, and
## resolves with that result; `null` when the last attempt fails too. Without `accept` (an
## empty Callable) a result is taken when it is not `null`; with one, `accept.call(result)`
## must return `true`. At most `attempts` calls are made, and `attempts` of 0 or less
## means no limit (it retries until one succeeds, so give it a way out). Between two
## attempts it waits `delay_ms` milliseconds of game time (like `LFUtils.timeout`), and
## each later wait is the previous one times `backoff` (2.0 doubles it; 1.0 keeps it
## constant). There is no wait after the last attempt. A negative `delay_ms` or `backoff`
## counts as 0. A NaN `delay_ms` or `backoff` is reported through `LFLogger` as an error
## and replaced by `FALLBACK_RETRY_DELAY_MS` / `DEFAULT_RETRY_BACKOFF`. An invalid `fn`
## (empty, or its object freed) is reported and resolves `null` without a call; an
## `accept` that is set but invalid is reported and likewise resolves `null` without a call.
static func retry(fn: Callable, attempts: int, delay_ms: float, backoff := DEFAULT_RETRY_BACKOFF, accept := Callable()) -> Variant:
	if not fn.is_valid():
		_log.error("LFAwait.retry: the callable is not valid")
		return null
	if not accept.is_null() and not accept.is_valid():
		_log.error("LFAwait.retry: the accept callable is not valid")
		return null
	if is_nan(delay_ms):
		_log.error("LFAwait.retry: delay_ms is NaN; using %s" % FALLBACK_RETRY_DELAY_MS)
		delay_ms = FALLBACK_RETRY_DELAY_MS
	if is_nan(backoff):
		_log.error("LFAwait.retry: backoff is NaN; using %s" % DEFAULT_RETRY_BACKOFF)
		backoff = DEFAULT_RETRY_BACKOFF
	var wait_ms := maxf(delay_ms, 0.0)
	var growth := maxf(backoff, 0.0)
	var attempt := 0
	while attempts <= 0 or attempt < attempts:
		attempt += 1
		var result: Variant = await fn.call()
		if _retry_accepts(result, accept):
			return result
		if attempts > 0 and attempt >= attempts:
			break
		await LFUtils.timeout(wait_ms)
		wait_ms *= growth
	return null


## The scene tree's `process_frame` signal: `await LFAwait.next_tick` waits one frame.
## Needs a running SceneTree.
static var next_tick: Signal:
	get(): return LFUtils.tree_root.process_frame


func _run(fn: Callable, index: int, generation: int) -> void:
	var result: Variant = null
	if fn.is_valid():
		result = await fn.call()
	else:
		push_error("LFAwait: callable %d of the batch is not valid" % index)
	if generation != _generation:
		return
	_results[index] = result
	_done += 1
	if on_fn_awaited.is_valid():
		on_fn_awaited.call(result, fn)
	if _complete:
		return
	if _first_wins:
		_winner = result
		_complete = true
		awaited.emit(_results)
		_settled.emit()
	elif _done == _fns.size():
		_complete = true
		awaited.emit(_results)
		_settled.emit()


static func _retry_accepts(result: Variant, accept: Callable) -> bool:
	if accept.is_null():
		return result != null
	return accept.call(result) == true
