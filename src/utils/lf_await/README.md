# LFAwait

> Waits for several coroutines at once: until all of them finish, or until the first one does.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_await.gd` |
| **Tests** | `tests/test_lf_await.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils` (for `next_tick`, `retry`), `LFLogger` |

## When to use it

GDScript's `await` waits for one thing at a time. Use `LFAwait.all` to start several
coroutines together and continue when every one has finished — fade out three panels at
once, wait for two async loads you started — and `LFAwait.any` to continue as soon as
the first finishes, e.g. "wait for the player's click or a 10 s timeout, whichever comes
first". `await LFAwait.next_tick` waits one frame from anywhere. To wait for a single
signal or timer, a plain `await` (or `LFUtils.timeout`) is enough.

## Step by step

Normally `await` waits for one thing ("wait here until it finishes"). `LFAwait` waits
for several at once. Each job is a function that may itself use `await` (such a
function is called a *coroutine*); you pass them in a list.

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock (top left) click
   *Other Node*, pick *Node*, and press *Create*.
2. Right-click the new node and choose *Attach Script*. Keep the defaults in the dialog
   and press *Create*. The script editor opens.
3. Select everything in the script and replace it with this code:

```gdscript
extends Node

func _ready() -> void:
	print("Starting three jobs...")
	# Start all three at the same time; continue when ALL are done.
	# `.bind("A", 500)` fills in the job's arguments in advance.
	var results: Array = await LFAwait.all([
		_job.bind("A", 500),
		_job.bind("B", 1500),
		_job.bind("C", 1000),
	])
	print("All done: ", results)   # the results, in the order of the list

	# Continue as soon as the FIRST one is done.
	var first: String = await LFAwait.any([_job.bind("slow", 2000), _job.bind("quick", 300)])
	print("First to finish: ", first)

# A job: wait some milliseconds, then hand back its name.
func _job(job_name: String, wait_ms: int) -> String:
	await LFUtils.timeout(wait_ms)
	print("Job ", job_name, " finished")
	return job_name
```
4. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
5. In the *Output* panel you should see jobs `A`, `C`, `B` finish after 0.5, 1 and 1.5
   seconds (not one after another: the whole group takes 1.5 s), then
   `All done: ["A", "B", "C"]`. Next `quick` finishes after 0.3 s and
   `First to finish: quick` prints. The `slow` job keeps running and prints a line two
   seconds in; that is expected.
6. To use your own jobs, write a function (with `await` inside if it takes time) and put
   `my_function.bind(arguments)` in the list. To wait just one frame from anywhere, write
   `await LFAwait.next_tick`.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `awaited` | `signal awaited(results: Array)` | Once every callable has finished; under `any`, on the first finish. |
| `on_fn_awaited` | `var on_fn_awaited: Callable` | Called as `(result, fn)` after each callable finishes. |
| `_init` | `LFAwait.new(batch: Array = [])` | Calls `reset(batch)`. Nothing runs until `exec()`. |
| `reset` | `reset(batch: Array = _fns) -> LFAwait` | Starts over with a copy of `batch` (the current batch when omitted); returns `self`. Results an earlier run returned are left as they were; a callable still running from the old batch is ignored; a caller still awaiting `exec()` of the old run is released with that run's results so far. |
| `exec` | `exec() -> Array` | Coroutine. Starts the batch (once per `reset`), waits until every callable has finished, returns the results in batch order. A second call waits for or returns the same run. |
| `done_count` | `done_count() -> int` | How many callables of the current batch have finished. |
| `is_complete` | `is_complete() -> bool` | Whether the current run has completed. |
| `all` | `static all(fns: Array) -> Array` | Coroutine. Results in input order once every callable finished. |
| `any` | `static any(fns: Array) -> Variant` | Coroutine. The first finished callable's result; the rest keep running. `null` for an empty batch. |
| `retry` | `static retry(fn: Callable, attempts: int, delay_ms: float, backoff := 1.0, accept := Callable()) -> Variant` | Coroutine. Calls `fn` (may `await`) up to `attempts` times; resolves with the first result that is not `null` (or that `accept.call(result)` approves with `true`), waiting `delay_ms` game-time milliseconds between tries, times `backoff` more on each later one; `null` after the last failure. `attempts <= 0` means no limit. NaN `delay_ms`/`backoff` is reported and replaced by 0 / 1.0; negatives count as 0; an invalid `fn` or `accept` is reported and gives `null` without a call. |
| `DEFAULT_RETRY_BACKOFF` | `const DEFAULT_RETRY_BACKOFF := 1.0` | The `backoff` of `retry` when none is given. |
| `FALLBACK_RETRY_DELAY_MS` | `const FALLBACK_RETRY_DELAY_MS := 0.0` | What `retry` uses in place of a NaN `delay_ms` (after reporting it). |
| `next_tick` | `static var next_tick: Signal` | `LFUtils.tree_root.process_frame`: `await LFAwait.next_tick` waits one frame. |

## Usage

```gdscript
# menu.gd — on a Control holding three panels
extends Control

func _fade(panel: Control) -> void:
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	await tween.finished

func close_all() -> void:
	# Fade the three panels at the same time and continue when all are done.
	await LFAwait.all([
		_fade.bind($Left),
		_fade.bind($Center),
		_fade.bind($Right),
	])
	hide()

func wait_for_click_or_timeout() -> String:
	# Whichever finishes first wins; the other keeps running in the background.
	var clicked := func() -> String:
		await $OkButton.pressed
		return "clicked"
	var timed_out := func() -> String:
		await LFUtils.timeout(10000)
		return "timeout"
	return await LFAwait.any([clicked, timed_out])

func connect_with_retries() -> Variant:
	# Up to 5 tries, 1 s then 2 s then 4 s apart; the first non-null answer wins.
	return await LFAwait.retry(_try_connect, 5, 1000.0, 2.0)

func _try_connect() -> Variant:
	await LFUtils.timeout(100)
	return null   # null = failed this time (return a value when it worked)
```

## Notes

- A callable (a function passed as a value) whose owner node is freed while it waits never finishes, so neither does `all`. A callable that is already invalid when the batch starts counts as finished with `null` and reports an error.
- Callables are started in order on the calling frame; synchronous ones finish immediately (handled: `exec` does not hang).
- Everything runs on the calling thread: the callables interleave at their `await`s, they don't run on other threads. Work with no `await` in it is not sped up.
- `any()` leaves the losers running; their results still land in the abandoned awaiter.
- Each position in `fns` owns its result slot, so the same Callable may appear more than once (sync or async).
- There is no timeout: a job that never returns keeps `all()` waiting forever. To add one, put `LFAwait.any` around the job and a timer.
- `retry` is for "try again until it works": `attempts <= 0` retries until one attempt succeeds, so pair it with a cap or a way to stop. It waits with `LFUtils.timeout` (game time: follows `Engine.time_scale`, needs a running SceneTree), never after the last attempt. A result that is `false`, `0` or `""` counts as success unless you pass `accept`; only `null` means failure by default. It cannot tell a failed result from a legitimate `null` answer.
- `any([])` returns `null`; `all([])` returns `[]`.
- `next_tick` needs a running SceneTree.
