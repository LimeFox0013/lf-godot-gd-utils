## The shared timing logic behind LFViewportLeave and LFViewportLeave3D; internal, so you
## never need to create one yourself.
##
## It holds a delay timer started by a screen exit (or by being off-screen when tracking
## starts), a max-timeout fallback that counts only enabled time, and the enable gate.
## The notifier owns it, forwards its visibility signals here and exposes its settings
## as properties.
class_name LFViewportLeaveCore
extends RefCounted

## Seconds after which a fallback already past a newly lowered limit fires.
const _SOON := 0.001
## Initial `delay`, in seconds, until the owning notifier sets its own.
const _INITIAL_DELAY := 1.0

## The VisibleOnScreenNotifier2D/3D this logic runs for; the timers are its children.
var notifier: Node
## One-shot delay timer; fires once the node stayed off-screen for `delay` seconds.
var timer := Timer.new()
## One-shot fallback timer; null when there is no max-timeout.
var max_timer: Timer
## Seconds the node must stay off-screen; <= 0 fires on the exit itself.
var delay := _INITIAL_DELAY
## Seconds of enabled time after which the fallback fires; <= 0 means none.
var max_timeout := 0.0
## While true, visibility changes are ignored and the fallback is paused.
var disabled := true

var _fire: Callable
var _is_on_screen: Callable
var _check_pending := false


## Adds the delay timer to `owner` as an internal child. `fire` runs when the node is
## reported as having left; `is_on_screen` returns whether it is visible right now.
func _init(owner: Node, fire: Callable, is_on_screen: Callable) -> void:
	notifier = owner
	_fire = fire
	_is_on_screen = is_on_screen
	timer.one_shot = true
	timer.timeout.connect(_report)
	owner.add_child(timer, false, Node.INTERNAL_MODE_FRONT)


## Sets `delay`; a positive value also becomes the delay timer's wait time.
func set_delay(value: float) -> void:
	delay = value
	if value > 0.0:
		timer.wait_time = value


## Sets `max_timeout`: <= 0 removes the fallback timer, a positive value creates it
## (paused while disabled) or changes its wait time. A fallback already counting keeps
## the enabled time it has counted: it fires once that time reaches the new value (at
## once if it already has). A fallback that already fired stays fired.
func set_max_timeout(value: float) -> void:
	var previous := max_timeout
	max_timeout = value
	if value <= 0.0:
		if max_timer != null:
			max_timer.stop()
			max_timer.timeout.disconnect(_report)
			max_timer.queue_free()
			max_timer = null
		return
	if max_timer == null:
		max_timer = Timer.new()
		max_timer.one_shot = true
		max_timer.autostart = true
		max_timer.timeout.connect(_report)
		max_timer.wait_time = value
		max_timer.paused = disabled
		notifier.add_child(max_timer, false, Node.INTERNAL_MODE_FRONT)
		if max_timer.is_inside_tree() and max_timer.is_stopped():
			max_timer.start()
	elif max_timer.is_stopped():
		max_timer.wait_time = value
	else:
		var remaining := value - (previous - max_timer.time_left)
		max_timer.start(maxf(remaining, _SOON))


## Sets `disabled`: disabling stops a pending delay; the fallback timer pauses while
## disabled; enabling resumes it and schedules a check of whether the node is off-screen.
## Writing the value it already has changes nothing.
func set_disabled(value: bool) -> void:
	if value == disabled:
		return
	disabled = value
	if disabled:
		timer.stop()
	if max_timer != null:
		max_timer.paused = disabled
	if !disabled:
		_schedule_check()


## Called when the notifier reports the node left the screen.
func _on_exited() -> void:
	if disabled:
		return
	if delay > 0.0:
		timer.start(delay)
	else:
		_report_deferred.call_deferred()


## Called when the notifier reports the node entered the screen.
func _on_entered() -> void:
	if !disabled:
		timer.stop()


## Judges, after the next drawn frame, whether the node is already off-screen, since
## the notifier reports only transitions. Visibility is computed while a frame is
## drawn, so it is not trusted earlier.
func _schedule_check() -> void:
	if _check_pending or disabled or !notifier.is_inside_tree():
		return
	_check_pending = true
	RenderingServer.frame_post_draw.connect(_on_frame_drawn, CONNECT_ONE_SHOT)


func _on_frame_drawn() -> void:
	# Visibility signals raised during that draw may still be queued; judge after them.
	_check_now.call_deferred()


func _check_now() -> void:
	_check_pending = false
	if disabled or !is_instance_valid(notifier) or !notifier.is_inside_tree():
		return
	if timer.is_stopped() and !_is_on_screen.call():
		_on_exited()


func _report_deferred() -> void:
	if !disabled and is_instance_valid(notifier):
		_report()


func _report() -> void:
	# One departure is reported once: whichever path fires first stands the other down.
	timer.stop()
	if max_timer != null:
		max_timer.stop()
	_fire.call()
