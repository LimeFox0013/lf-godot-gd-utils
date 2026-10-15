## Keeps a press for a short time so a later event can still use it, and tells you once if it ran out unused.
##
## For "jump pressed a moment before landing": call `press` on the button, `take` when the
## event happens, and `tick(delta)` every frame; `tick` returns true on the one frame the
## window runs out with the press unused. Time is the `delta` you pass.
class_name LFInputBuffer
extends RefCounted

## Default seconds a press is kept.
const DEFAULT_WINDOW := 0.08

## Seconds a press is kept, counted from the latest `press`. Read only.
var window: float:
	get:
		return _window
## Whether a press is waiting to be taken. Read only.
var pending: bool:
	get:
		return _pending

## Seconds since the pending press, 0 when none waits. Read only.
var age: float:
	get:
		return _age if _pending else 0.0

var _window: float
var _pending := false
var _age := 0.0
var _log := LFLogger.new(['LFInputBuffer'])


## A buffer that keeps a press `window` seconds. A window of 0 or less, NaN or infinite is
## reported through `LFLogger` and the default is used.
func _init(window_seconds := DEFAULT_WINDOW) -> void:
	_window = window_seconds
	if not is_finite(window_seconds) or window_seconds <= 0.0:
		_log.error('the window must be finite and above 0, got', window_seconds)
		_window = DEFAULT_WINDOW


## Marks a press pending and restarts the window.
func press() -> void:
	_pending = true
	_age = 0.0


## True once while a press is pending, and clears it.
func take() -> bool:
	var was_pending := _pending
	_pending = false
	return was_pending


## Drops a pending press without reporting it as expired.
func clear() -> void:
	_pending = false


## Ages a pending press by `delta` seconds. Returns true on the one call where the window
## runs out with the press unused. A negative or NaN `delta` changes nothing.
func tick(delta: float) -> bool:
	if not _pending or is_nan(delta) or delta < 0.0:
		return false
	_age += delta
	if _age < _window:
		return false
	_pending = false
	return true
