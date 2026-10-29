## Runs a slow, awaitable per-frame update without ever running it twice at once.
##
## Some updates take several frames to finish (they `await` something). Call `feed(delta)`
## every frame: when the update is idle it runs with all the time banked so far, and when
## it is still running the time is banked and handed to the next run, so no time is lost
## and the update is never re-entered. A banked frame waits for the next `feed` after the
## running update finishes; nothing runs on its own.
class_name LFCoalescedTick
extends RefCounted

## `tick_fn.call(delta: float)`: the update. It may `await`.
var tick_fn: Callable
var _pending := 0.0
var _running := false


func _init(update: Callable) -> void:
	tick_fn = update


## Banks `delta`. If the update is idle, runs it with everything banked and waits for it to
## finish. Call it without `await` from a per-frame function, or the caller waits too.
func feed(delta: float) -> void:
	_pending += delta
	if _running:
		return
	_running = true
	var run_delta := _pending
	_pending = 0.0
	await tick_fn.call(run_delta)
	_running = false


## Whether the update is running now.
func is_running() -> bool:
	return _running


## Seconds banked for the next run.
func pending_seconds() -> float:
	return _pending
