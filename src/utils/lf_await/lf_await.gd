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
