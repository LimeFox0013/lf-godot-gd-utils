## Decides when a server process should quit so it never outlives its job.
##
## Three reasons, checked in this order on every `tick`: the work is finished and a grace
## period has passed (`finish` starts it), nobody has been connected for `idle_seconds`, or
## the process that launched this one is gone (`parent_pid`, watched with
## [LFOS.PidWatchdog]). `tick` only says why; quitting is up to you. Runs on the `delta`
## you pass.
class_name LFServerLifetime
extends RefCounted

## Why `tick` says to quit.
enum Reason {
	## Keep running.
	NONE,
	## `finish` was called and `finished_seconds` have passed.
	FINISHED,
	## Nobody was connected for `idle_seconds`.
	IDLE,
	## The process `parent_pid` names is gone.
	PARENT_GONE,
}

## Seconds nobody may be connected before `Reason.IDLE`.
var idle_seconds: float
## Seconds after `finish` before `Reason.FINISHED`.
var finished_seconds: float
## The process to watch; 0 or less watches nothing. Read when the first check starts.
var parent_pid := 0
## Seconds between liveness checks of the parent. Read when the first check starts.
var parent_check_seconds: float
## The parent watcher, or null until the first tick that reaches the parent check.
var parent_watch: LFOS.PidWatchdog = null
var _idle_elapsed := 0.0
var _finished_elapsed := -1.0


func _init(idle: float, after_finish: float, check_seconds := LFOS.PidWatchdog.DEFAULT_CHECK_INTERVAL_SECONDS) -> void:
	idle_seconds = idle
	finished_seconds = after_finish
	parent_check_seconds = check_seconds


## The work is done: starts (or restarts) the `finished_seconds` countdown.
func finish() -> void:
	_finished_elapsed = 0.0


## Advances every clock by `delta` seconds; `connected_count` is how many clients are
## connected now (any above 0 resets the idle clock). Returns the first reason to quit, or
## `Reason.NONE`. A reason that fires stops the later checks for that tick.
func tick(delta: float, connected_count: int) -> Reason:
	if _finished_elapsed >= 0.0:
		_finished_elapsed += delta
		if _finished_elapsed >= finished_seconds:
			return Reason.FINISHED
	_idle_elapsed = 0.0 if connected_count > 0 else _idle_elapsed + delta
	if _idle_elapsed >= idle_seconds:
		return Reason.IDLE
	if parent_pid > 0:
		if parent_watch == null:
			parent_watch = LFOS.PidWatchdog.new(parent_pid, parent_check_seconds)
		if parent_watch.tick(delta):
			return Reason.PARENT_GONE
	return Reason.NONE
