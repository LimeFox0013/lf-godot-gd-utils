## A countdown clock driven by your game's own time: `tick(delta)` moves it, nothing else does.
##
## It counts `duration` seconds down to 0 and tells you with signals: `ticked` at the end of
## every whole `tick_interval` (a second by default) and `finished` at 0. It can be started,
## paused, resumed, stopped and restarted, and `text()` gives the time left as a clock string
## through `LFText.clock`. It takes no wall clock, so a paused game or a slowed-down
## `delta` pauses or slows it as well.
##
## It is its own small class rather than an `LFIntervalTimer`: that timer reports at most one
## fire per `tick`, while a countdown must report every second a long `delta` covered, each with
## its exact time left.
class_name LFCountdown
extends RefCounted


## Emitted at the end of each whole `tick_interval` that has run, with the exact seconds left
## at that moment. A long `delta` emits it once per interval it covered, in order. The last
## one, at 0, is emitted just before `finished`.
signal ticked(remaining: float)
## Emitted once when the time left reaches 0.
signal finished

## Where a countdown is in its life.
enum State {
	## Not counting: at the start, after `stop`, or never started.
	STOPPED,
	## Counting down as `tick` is called.
	RUNNING,
	## Held by `pause`: `tick` changes nothing until `resume`.
	PAUSED,
	## Ran down to 0; `start` or `restart` begins again.
	FINISHED,
}

## The duration, in seconds, a countdown has when none is given.
const DEFAULT_DURATION_SECONDS := 60.0
## The seconds between `ticked` signals when none are given.
const DEFAULT_TICK_INTERVAL_SECONDS := 1.0
## The shortest accepted `tick_interval`, in seconds (a shorter one would emit endlessly).
const MIN_TICK_INTERVAL_SECONDS := 0.001
## Rounding slack, in seconds, when comparing summed deltas with an interval or the duration.
const _EPSILON_SECONDS := 1e-9

## How long the countdown runs, in seconds: finite and above 0, otherwise reported through
## `LFLogger` and ignored. A change takes effect at once: seconds already elapsed stay elapsed.
var duration: float = DEFAULT_DURATION_SECONDS:
	set(value):
		if not is_finite(value) or value <= 0.0:
			_log.error('the duration must be finite and above 0, got', value)
			return
		duration = value
## Seconds between `ticked` signals: at least `MIN_TICK_INTERVAL_SECONDS` and finite, otherwise
## reported through `LFLogger` and ignored.
var tick_interval: float = DEFAULT_TICK_INTERVAL_SECONDS:
	set(value):
		if not is_finite(value) or value < MIN_TICK_INTERVAL_SECONDS:
			_log.error('the tick interval must be finite and at least', MIN_TICK_INTERVAL_SECONDS, 'got', value)
			return
		tick_interval = value
## The seconds left, from `duration` down to 0. Read-only.
var remaining: float:
	get:
		return maxf(duration - _elapsed, 0.0)
## Where the countdown is now. Read-only.
var state: State = State.STOPPED:
	get:
		return _state

var _state: State = State.STOPPED
var _elapsed := 0.0
var _ticks_emitted := 0
## Bumped by `restart` and `stop`, so a `tick` in progress notices a signal handler that did one.
var _generation := 0
var _log := LFLogger.new(['LFCountdown'])


## A stopped countdown of `initial_duration` seconds that signals every `initial_tick_interval`
## seconds. Invalid values are reported through `LFLogger` and the defaults stay.
func _init(initial_duration: float = DEFAULT_DURATION_SECONDS, initial_tick_interval: float = DEFAULT_TICK_INTERVAL_SECONDS) -> void:
	duration = initial_duration
	tick_interval = initial_tick_interval


## Starts counting from the full duration. A paused countdown just resumes where it was, a
## running one is left alone, and a stopped or finished one starts over.
func start() -> void:
	match _state:
		State.RUNNING:
			return
		State.PAUSED:
			_state = State.RUNNING
		_:
			restart()


## Starts over from the full duration, from any state.
func restart() -> void:
	_generation += 1
	_elapsed = 0.0
	_ticks_emitted = 0
	_state = State.RUNNING


## Holds a running countdown. Does nothing in any other state.
func pause() -> void:
	if _state == State.RUNNING:
		_state = State.PAUSED


## Continues a paused countdown. Does nothing in any other state.
func resume() -> void:
	if _state == State.PAUSED:
		_state = State.RUNNING


## Stops counting and puts the full duration back, with no signal.
func stop() -> void:
	_generation += 1
	_elapsed = 0.0
	_ticks_emitted = 0
	_state = State.STOPPED


## Moves a running countdown by `delta` seconds, emitting `ticked` for each interval it
## covered and `finished` when it reaches 0 (any `delta` left over after that is dropped).
## Returns true on the call that finished it. A handler that calls `stop` or `restart`, or `pause`s, ends the call at once. A negative or non-finite `delta`, and any state
## but running, change nothing. A long `delta` emits one `ticked` per covered interval, so
## with a tiny `tick_interval` and a huge `delta` that is many signals.
func tick(delta: float) -> bool:
	if _state != State.RUNNING or not is_finite(delta) or delta < 0.0:
		return false
	_elapsed += delta
	var generation := _generation
	var last_tick := floori((minf(_elapsed, duration) + _EPSILON_SECONDS) / tick_interval)
	while _ticks_emitted < last_tick:
		_ticks_emitted += 1
		ticked.emit(maxf(duration - _ticks_emitted * tick_interval, 0.0))
		if _generation != generation or _state != State.RUNNING:
			return false
	if _elapsed >= duration - _EPSILON_SECONDS:
		_elapsed = duration
		_state = State.FINISHED
		finished.emit()
		return true
	return false


## The seconds left as a clock string, `m:ss` or `h:mm:ss`, from `LFText.clock`. A fraction of
## a second rounds up by default, so `0:00` shows only once time is up; `round_up = false`
## rounds down.
func text(round_up: bool = true) -> String:
	return LFText.clock(remaining, round_up)


## Whether the countdown is counting down right now.
func is_running() -> bool:
	return _state == State.RUNNING


## Whether the countdown is held by `pause`.
func is_paused() -> bool:
	return _state == State.PAUSED


## Whether the countdown ran down to 0 (until `start`, `restart` or `stop`).
func is_finished() -> bool:
	return _state == State.FINISHED


## How far through the duration the countdown is, from 0.0 (full) to 1.0 (finished).
func progress() -> float:
	return clampf(_elapsed / duration, 0.0, 1.0)
