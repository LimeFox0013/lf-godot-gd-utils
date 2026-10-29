## A bar that shows a current value out of a maximum, such as health, mana or progress.
##
## Give it numbers with `set_values(current, maximum)`, or connect it to a source with
## `bind`, which re-reads the numbers whenever a signal you name is emitted. With
## `ease_seconds` above 0 the fill slides to the new value instead of jumping. The bar knows nothing about
## what the numbers mean. It is a `ProgressBar` without the percent text; style it with
## `fill_color` and `back_color` or with theme overrides.
class_name LFValueBar
extends ProgressBar

## Emitted after `set_values` changed the numbers, with the new ones (the drawn fill may still be easing).
signal values_changed(current: float, maximum: float)

## Default `ease_seconds`: 0 jumps at once.
const DEFAULT_EASE_SECONDS := 0.0
## Default `fill_color`.
const DEFAULT_FILL_COLOR := Color(0.8, 0.2, 0.2)
## Default `back_color`.
const DEFAULT_BACK_COLOR := Color(0.1, 0.1, 0.1, 0.8)
## Default height in pixels of the bar.
const DEFAULT_HEIGHT := 12.0
## Largest `max_value` the bar is given when the maximum is 0 or less (an empty bar needs a positive range).
const EMPTY_RANGE := 1.0
## Theme stylebox of the filled part.
const _FILL_STYLE := &"fill"
## Theme stylebox of the background.
const _BACK_STYLE := &"background"

## Seconds the fill takes to slide to a new value; 0 or less jumps at once.
@export var ease_seconds := DEFAULT_EASE_SECONDS
## Colour of the filled part.
@export var fill_color := DEFAULT_FILL_COLOR:
	set(value):
		fill_color = value
		add_theme_stylebox_override(_FILL_STYLE, LFStyle.flat(value))
## Colour behind the fill.
@export var back_color := DEFAULT_BACK_COLOR:
	set(value):
		back_color = value
		add_theme_stylebox_override(_BACK_STYLE, LFStyle.flat(value))

## The current number last given (never below 0).
var current := 0.0
## The maximum last given (never below 0).
var maximum := 0.0

var _tween: Tween
var _bound_source: Object
var _bound_signal := &""
var _bound_read := Callable()

static var _log := LFLogger.new(['LFValueBar'])


func _init() -> void:
	show_percentage = false
	custom_minimum_size.y = DEFAULT_HEIGHT
	min_value = 0.0
	step = 0.0
	max_value = EMPTY_RANGE
	value = 0.0
	fill_color = DEFAULT_FILL_COLOR
	back_color = DEFAULT_BACK_COLOR


## Shows `new_current` out of `new_maximum`. Negative numbers count as 0 and a current
## above the maximum is shown as full (the stored `current` keeps it). A NaN in either is
## reported through `LFLogger` as an error and ignored. The fill eases over `ease_seconds`.
func set_values(new_current: float, new_maximum: float) -> void:
	if is_nan(new_current) or is_nan(new_maximum):
		_log.error('set_values got NaN')
		return
	current = maxf(new_current, 0.0)
	maximum = maxf(new_maximum, 0.0)
	max_value = maximum if maximum > 0.0 else EMPTY_RANGE
	var target := minf(current, maximum)
	if _tween != null:
		_tween.kill()
		_tween = null
	if ease_seconds > 0.0 and is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(self, 'value', target, ease_seconds)
	else:
		value = target
	values_changed.emit(current, maximum)


## The fill as a share of the maximum, 0 to 1 (0 when the maximum is 0), from the numbers
## given, not from the drawn fill that may still be easing.
func ratio() -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(current / maximum, 0.0, 1.0)


## Follows a source: whenever `source` emits `signal_name`, `read` is called with no arguments and
## must return a `Vector2` (x = current, y = maximum), which goes to `set_values`. Reads once now. Replaces an
## earlier binding. Unbinds itself when the source is freed. A missing signal or an invalid
## `read` is reported through `LFLogger` as an error and nothing is bound.
func bind(source: Object, signal_name: StringName, read: Callable) -> void:
	unbind()
	if not is_instance_valid(source) or not source.has_signal(signal_name) or not read.is_valid():
		_log.error('bind needs a source with the signal and a valid read Callable')
		return
	_bound_source = source
	_bound_signal = signal_name
	_bound_read = read
	source.connect(signal_name, _on_source_signal)
	_refresh_from_source()


## Stops following the bound source.
func unbind() -> void:
	if is_instance_valid(_bound_source) and _bound_source.is_connected(_bound_signal, _on_source_signal):
		_bound_source.disconnect(_bound_signal, _on_source_signal)
	_bound_source = null
	_bound_signal = &""
	_bound_read = Callable()


## Reads the bound source now, as when its signal fires. Does nothing when nothing is bound.
func refresh() -> void:
	_refresh_from_source()


func _on_source_signal(..._args: Array) -> void:
	_refresh_from_source()


func _refresh_from_source() -> void:
	if not _bound_read.is_valid():
		return
	var pair: Variant = _bound_read.call()
	if pair is Vector2:
		set_values((pair as Vector2).x, (pair as Vector2).y)
	else:
		_log.error('the read Callable must return a Vector2')
