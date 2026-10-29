## A small icon that drains like a clock as time runs out: the fraction remaining of a duration.
##
## It is a `TextureProgressBar` drawing `icon` twice: dimmed underneath, and bright on top
## up to the fraction remaining (`fraction`, 1 = all the time left, 0 = none). Set the
## fraction yourself with `set_fraction`, or hand it a `Timer` with `track` and the icon
## follows `time_left / wait_time` every frame until `stop_tracking`. A tracked timer that is
## stopped shows `stopped_fraction`. Typical use: a buff or debuff icon on a character.
class_name LFTimerIcon
extends TextureProgressBar

## Emitted when a tracked timer is stopped or has run out (its `time_left` reached 0),
## once per run of the timer.
signal finished

## Default `stopped_fraction`: a timer that is not running shows a full icon.
const DEFAULT_STOPPED_FRACTION := 1.0
## Default colour multiplied into the dimmed icon under the bright one.
const DEFAULT_UNDER_TINT := Color(0.35, 0.35, 0.35, 0.8)
## Smallest fraction.
const MIN_FRACTION := 0.0
## Largest fraction.
const MAX_FRACTION := 1.0
## Smallest step between two shown values, so the fill moves smoothly.
const FRACTION_STEP := 0.001

## What a stopped timer shows (0 to 1). Used while a tracked timer is not running.
@export_range(0.0, 1.0, 0.01) var stopped_fraction := DEFAULT_STOPPED_FRACTION
## The icon drawn dimmed and bright. Null draws nothing.
@export var icon: Texture2D:
	set(value):
		icon = value
		texture_under = value
		texture_progress = value
## Colour multiplied into the dimmed icon underneath.
@export var under_tint := DEFAULT_UNDER_TINT:
	set(value):
		under_tint = value
		tint_under = value

## The fraction remaining now, 0 to 1.
var fraction: float:
	get:
		return value
	set(new_fraction):
		set_fraction(new_fraction)

## The tracked timer, or null.
var timer: Timer

var _expired := false

static var _log := LFLogger.new(['LFTimerIcon'])


func _init() -> void:
	min_value = MIN_FRACTION
	max_value = MAX_FRACTION
	step = FRACTION_STEP
	value = DEFAULT_STOPPED_FRACTION
	tint_under = under_tint
	set_process(false)


## Shows `new_fraction` (clamped to 0 to 1). A NaN is reported through `LFLogger` as an
## error and ignored. Does not stop a tracked timer's updates; call `stop_tracking` first.
func set_fraction(new_fraction: float) -> void:
	if is_nan(new_fraction):
		_log.error('set_fraction got NaN')
		return
	value = clampf(new_fraction, MIN_FRACTION, MAX_FRACTION)


## Follows `new_timer`: from now on the fraction is its `time_left / wait_time` each frame (or
## `stopped_fraction` while it is stopped). Replaces any earlier timer. `null` is
## `stop_tracking`. Updates the fraction at once.
func track(new_timer: Timer) -> void:
	if new_timer == null:
		stop_tracking()
		return
	timer = new_timer
	_expired = false
	set_process(true)
	_update()


## Stops following the timer; the fraction stays as it was.
func stop_tracking() -> void:
	timer = null
	set_process(false)


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if timer == null:
		return
	if not is_instance_valid(timer):
		stop_tracking()
		return
	if timer.is_stopped():
		set_fraction(stopped_fraction)
		if not _expired:
			_expired = true
			finished.emit()
		return
	_expired = false
	if timer.wait_time <= 0.0:
		set_fraction(MIN_FRACTION)
		return
	set_fraction(timer.time_left / timer.wait_time)
