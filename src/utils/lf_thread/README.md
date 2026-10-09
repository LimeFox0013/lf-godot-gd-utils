# LFThread

> Runs one slow job on a background thread, where the build supports threads, so the game doesn't freeze, and tells you when it is done.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_thread.gd` |
| **Tests** | `tests/test_lf_thread.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUuid` (default `id`) |

## When to use it

Use it for one slow, self-contained job that would otherwise freeze the game for a
moment: generating a big map, building a pathfinding grid, parsing a large save file. The
job runs in parallel (on a "thread": a second line of work the computer does at the same
time as the one that draws the game) on builds with thread support; you call `poll()` every
frame and get `finished` with its result.
A job started with `start_cancelable` can be told to stop early (the player left the
screen). The job must not touch nodes or the scene tree. For many small jobs, Godot's
`WorkerThreadPool` is a better fit; to unzip in the background use `LFZipExtractor`, and
to run another program use `LFProcess`.

## Step by step

Tested in the editor on desktop. On a build without thread support (a web export with
*Thread Support* off, the default since Godot 4.3) there is no background thread: the job
runs at your first `poll()` and the game freezes until it returns (see Notes).

1. Choose *Scene → New Scene*, click **Other Node** in the Scene dock and pick a plain
   **Node**. Save it (Ctrl+S) as `thread_demo.tscn`.
2. Right-click the Node and choose **Attach Script**, then **Create**.
3. Replace the script's contents with this:

```gdscript
extends Node

# One background job. Keep it in a variable so it is not thrown away mid-run.
# The text is a label that comes back with the result.
var job := LFThread.new("add-numbers")


func _ready() -> void:
	# A signal is an event other code can listen to. "finished" fires with the result.
	job.finished.connect(_on_job_finished)

	# Start the slow work. The function in here runs on the background thread, so it
	# must not touch nodes. Whatever it returns is the result.
	job.start(func() -> int:
		var total := 0
		for i in 2_000_000:   # change this to make the job shorter or longer
			total += i
		return total
	)
	print("job started; the game keeps running")


func _process(_delta: float) -> void:
	# Called every frame. The job's result is only collected when you poll.
	job.poll()


func _on_job_finished(_id: String, label: String, result: Variant) -> void:
	print(label, " finished: ", result)
```

4. Press **F6** (*Run Current Scene*). The Output panel shows `job started; the game keeps
   running`, and a moment later `add-numbers finished: 1999999000000`.
5. To make the job cancelable, start it with `job.start_cancelable(...)`: your function
   then receives a `should_stop` Callable (a function passed around as a value) as its
   one argument, and checks `should_stop.call()` inside its loop. Call `job.request_stop()` to ask it to stop; the
   `canceled` signal then fires instead of `finished`. See Usage below for a full example.

## API

Everything the class offers; you only need the rows used in the steps above to get started.

### Signals

| Member | Signature | Description |
|---|---|---|
| `started` | `started(id: String, key: String)` | Emitted synchronously by a successful `start` (also when the task waits for the first `poll()` because there is no worker). |
| `finished` | `finished(id: String, key: String, result: Variant)` | Emitted at finalization when no stop was requested. |
| `canceled` | `canceled(id: String, key: String, result: Variant)` | Emitted instead of `finished` when a stop was requested. |

### Properties

| Member | Signature | Description |
|---|---|---|
| `key` | `var key: String = ''` | Optional label (set via constructor). |
| `id` | `var id: String` | Generated `LFUuid.gen('lf-thread')`. |
| `force_main_thread` | `static var force_main_thread := false` | Process-wide: run every task without a worker, as on a build without thread support. For tests, or to try the no-threads path on desktop. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFThread.new(initial_key: String = '')` | An idle wrapper; `initial_key` becomes `key`. |
| `threads_available` | `static threads_available() -> bool` | `OS.has_feature("threads")` and `force_main_thread` off: whether a task started now gets a worker. |
| `start` | `start(task: Callable) -> bool` | Runs `task()` on a new thread. Returns `false` if a task is already running (the running one is kept) or `task` is not a valid Callable (empty, or its object was freed). With no worker available (`threads_available()` false, or `Thread.start` fails) it still returns `true`; the task then runs on the calling thread at the first `poll()` / `join_now()`. |
| `start_cancelable` | `start_cancelable(task: Callable) -> bool` | Like `start`, but calls `task(should_stop)`: a Callable the task polls to return early. |
| `request_stop` | `request_stop() -> void` | Sets the cooperative stop flag for the current run (a request before `start` does not carry over). |
| `is_stop_requested` | `is_stop_requested() -> bool` | Whether a stop was requested — for the owner; the task polls its `should_stop` Callable. |
| `poll` | `poll() -> void` | Non-blocking while a worker runs the task. If the thread has ended, joins it, stores the result and emits `finished` or `canceled`. Without a worker, the first call runs the whole task (**blocking**) and then does the same. |
| `join_now` | `join_now() -> bool` | **Blocks** until the thread ends (or, without a worker, runs the task here), then finalizes. Returns `false` if nothing was running, or, without a worker, when the task itself calls it (the task is already running on that thread, and is collected when it returns; a `poll()` from inside the task likewise does nothing). |
| `is_threaded` | `is_threaded() -> bool` | Whether the current or last run got a worker thread. |
| `is_done` | `is_done() -> bool` | `true` when it was never started or has been finalized. A task that has ended but was not yet polled/joined still counts as running (`false`). |
| `get_result` | `get_result() -> Variant` | The task's return value (`null` until finalized). |
| `get_info` | `get_info() -> Dictionary` | `{id, key, running, threaded, started_at, ended_at, duration_sec, stop_requested}`. Timestamps are fractional unix seconds (0.0 until set); `duration_sec` comes from the monotonic clock. |

## Usage

A script on any node:

```gdscript
extends Node

var job := LFThread.new("count")


func _ready() -> void:
	job.finished.connect(_on_job_finished)
	# The task runs on another thread: it must not touch nodes.
	job.start_cancelable(func(should_stop: Callable) -> int:
		var n := 0
		while n < 1_000_000 and not should_stop.call():
			n += 1
		return n
	)


func _process(_delta: float) -> void:
	job.poll()   # nothing is emitted until you poll (or join_now)


func _on_job_finished(_id: String, key: String, result: Variant) -> void:
	print(key, " -> ", result)


func _exit_tree() -> void:
	job.request_stop()   # leaving early: let the task return at its next check
```

## Notes

- **Polling is required.** The object doesn't touch the scene tree, so a task that has ended is never finalized and no signal fires until you call `poll()` or `join_now()`. Until then `is_done()` is `false`, `get_info().running` is `true` and `get_result()` is `null`.
- Signals are emitted on whichever thread calls `poll()` / `join_now()` / `start()`, which is normally the main thread (the one running your game).
- With a worker thread the task runs off the main thread, so it must not touch the scene tree. Without thread support it runs on the thread that polls (see the next point); write it the same way, so it works in both.
- **No thread support.** Godot's `threads` feature tag is missing on a web export built without thread support (the default web export since Godot 4.3). Then `start` keeps its contract (returns `true`, emits `started`) but no worker exists: the task runs on whichever thread calls the first `poll()` or `join_now()`, blocking it until the task returns, and the signal follows straight after. A long job therefore freezes the game for its whole length there; split it up or check `LFThread.threads_available()` first. The same happens if `Thread.start` fails. An instance freed before that first poll drops the task without running it. Not tested on an actual web export; the tests force this path with `force_main_thread`.
- Classes built on it (`LFZipExtractor`, `LFFlowFieldService`) inherit this: without thread support their work runs, blocking, in the frame where they poll their `LFThread`.
- Cancellation is cooperative: a task that never calls `should_stop` runs to completion, and still reports `canceled` if a stop was requested before it was joined.
- A method Callable (`obj.work`, a function of an object passed as a value) doesn't keep `obj` alive until the call begins; capture what the task needs in a lambda (an inline function, as in the example).
- The worker runs only the task (and its `should_stop` check); it never holds a reference to the `LFThread`, so the object is always freed on the thread that let go of it. Freeing an instance whose task is still running requests a stop, then blocks until the task ends (no signal fires) — short for a cancelable task, the whole run for one that never checks.
