## Tells you when a 3D node has stayed off-screen for a while, for example to free a
## node that left the view.
##
## The 3D counterpart of LFViewportLeave. Add it as a child of the node to watch. It is a
## VisibleOnScreenNotifier3D (set its `aabb` to the parent's bounds) that emits
## `left_viewport`, and calls an optional callback, once the node has stayed continuously
## off-screen for `delay` seconds. It adds the same delay, enable gate, check when
## tracking starts (a node already off-screen, or one that left while disabled, is
## reported too) and `max_timeout` fallback counted in enabled time. Starts disabled: set
## `disabled = false` to begin tracking.
class_name LFViewportLeave3D
extends VisibleOnScreenNotifier3D

## Emitted once the node is reported as having left the viewport (by the delay or the
## max-timeout).
signal left_viewport

## Default `delay`, in seconds.
const DEFAULT_DELAY := 1.0
## Default `max_timeout`, in seconds.
const DEFAULT_MAX_TIMEOUT := 300.0

static var _log := LFLogger.new()

## Upper end of the Inspector slider for `delay`, in seconds (larger typed values are allowed).
const _DELAY_HINT_MAX := 60.0
## Step of the Inspector slider for `delay`, in seconds.
const _DELAY_HINT_STEP := 0.05
## Upper end of the Inspector slider for `max_timeout`, in seconds (larger typed values
## are allowed).
const _MAX_TIMEOUT_HINT_MAX := 600.0
## Step of the Inspector slider for `max_timeout`, in seconds.
const _MAX_TIMEOUT_HINT_STEP := 1.0

## Seconds the node must stay off-screen before it is reported; 0 or less reports on
## the exit itself (at the end of that frame). Setting it later retimes the next wait. A NaN
## is rejected: reported through `LFLogger` as an error, and the value is kept.
@export_range(0.0, _DELAY_HINT_MAX, _DELAY_HINT_STEP, "or_greater", "suffix:s") var delay := DEFAULT_DELAY:
	set(value):
		if is_nan(value):
			_log.error('LFViewportLeave3D: a NaN delay is rejected; keeping %s' % delay)
			return
		delay = value
		_core.set_delay(value)
## Seconds of enabled time after which the node is reported regardless of visibility;
## 0 or less means no fallback. Setting it later adds, retimes or removes the fallback;
## a retimed fallback keeps the enabled time it already counted (and fires at once if
## that is past the new value). A NaN is rejected like `delay`.
@export_range(0.0, _MAX_TIMEOUT_HINT_MAX, _MAX_TIMEOUT_HINT_STEP, "or_greater", "suffix:s") var max_timeout := DEFAULT_MAX_TIMEOUT:
	set(value):
		if is_nan(value):
			_log.error('LFViewportLeave3D: a NaN max_timeout is rejected; keeping %s' % max_timeout)
			return
		max_timeout = value
		_core.set_max_timeout(value)
## While true, visibility changes are ignored, a pending delay is stopped and the
## max-timeout is paused. Enabling resumes the max-timeout and, after the next drawn
## frame, starts the delay if the node is off-screen.
@export var disabled := true:
	set = set_disabled

## Called with no arguments when the node is reported as having left, after
## `left_viewport`; skipped once its object is freed. May be changed at any time.
var callback: Callable
## The one-shot delay timer (`wait_time = delay`), for reading `time_left`. Read-only;
## an internal child, so it never shows in `get_children()` or a saved scene.
var timer: Timer:
	get:
		return _core.timer
## One-shot max-timeout timer; null when `max_timeout <= 0`. Paused while disabled.
var max_timer: Timer:
	get:
		return _core.max_timer

var _core := LFViewportLeaveCore.new(self, _report, _is_on_screen_now)


## Creates the notifier: `on_leave` is called when the node is reported (optional;
## `left_viewport` is emitted either way), `delay_seconds` sets `delay` and
## `max_timeout_seconds` sets `max_timeout`. All arguments are optional, so the node can
## also be placed in a scene and set up in the Inspector.
func _init(on_leave := Callable(), delay_seconds := DEFAULT_DELAY, max_timeout_seconds := DEFAULT_MAX_TIMEOUT) -> void:
	callback = on_leave
	delay = delay_seconds
	max_timeout = max_timeout_seconds
	screen_exited.connect(_core._on_exited)
	screen_entered.connect(_core._on_entered)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_core._schedule_check()


## Enables (`state = false`) or disables (`state = true`) exit tracking; the same as
## writing `disabled`. Enabling resumes the max-timeout where it stopped and, after the
## next drawn frame, starts the delay if the node is already off-screen. Writing the
## value it already has does nothing.
func set_disabled(state: bool) -> void:
	disabled = state
	_core.set_disabled(state)


## Adds this notifier as a child of `parent_node` and returns it, so creation, adding and
## setup fit in one line.
func add_to(parent_node: Node) -> LFViewportLeave3D:
	parent_node.add_child(self)
	return self


## Whether the node is on screen right now. Override to substitute visibility where
## nothing is drawn (headless runs, tests).
func _is_on_screen_now() -> bool:
	return is_on_screen()


func _report() -> void:
	left_viewport.emit()
	if callback.is_valid():
		callback.call()
