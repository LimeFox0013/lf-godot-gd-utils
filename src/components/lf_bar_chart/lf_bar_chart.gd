## A small bar chart you can put anywhere in your UI: one bar per number in `values`.
##
## Bars go left to right in `values` order, scaled so the largest value reaches
## `top_padding` below the top edge (a chart of zeros stays flat). Each bar has its value
## printed above it (hidden with `show_values` off) and stands on a baseline. Setting
## `values` or any exported style property redraws it.
class_name LFBarChart
extends Control

## Default fill of the bars.
const DEFAULT_BAR_COLOR := Color("#5a8dee")
## Default colour of the value labels.
const DEFAULT_LABEL_COLOR := Color(0.9, 0.9, 0.9)
## Default colour of the baseline.
const DEFAULT_AXIS_COLOR := Color(0.5, 0.5, 0.5)
## Default font size of the value labels, in pixels.
const DEFAULT_FONT_SIZE := 11
## Default share of each bar's slot the bar fills, 0..1.
const DEFAULT_BAR_RATIO := 0.6
## Default pixels kept free above the tallest bar.
const DEFAULT_TOP_PADDING := 24.0
## Default pixels between the baseline and the bottom edge.
const DEFAULT_BOTTOM_PADDING := 4.0

## Smallest `bar_ratio` the Inspector offers.
const _MIN_BAR_RATIO := 0.05
## Thinnest a bar is drawn, in pixels, however many bars share the width.
const _MIN_BAR_WIDTH := 1.0
## Pixels between a bar's top and the baseline of its value label.
const _LABEL_GAP := 4.0
## Width of the baseline, in pixels.
const _AXIS_WIDTH := 1.0
## Decimals a value with a fraction is printed with.
const _FRACTION_DECIMALS := 2
## Step a value is rounded to before printing: one unit of the last printed decimal.
const _FRACTION_STEP := 0.01
## Magnitude from which a value prints through `String.num` without decimals instead of
## `int()`: past 2^53 a float holds no fraction, and `int()` would overflow near 2^63.
const _INT_PRINT_LIMIT := 9.0e15
## Label of a NaN value.
const _NAN_TEXT := 'nan'
## Label of positive infinity.
const _INF_TEXT := 'inf'
## Label of negative infinity.
const _NEG_INF_TEXT := '-inf'

## The numbers to chart, left to right (ints or floats). The array is copied on set, so
## changing your array later does not change the chart; assign again to update it.
## Negative values, NaN, infinities and anything that is not an int or float draw as 0 (their labels still print the value).
var values: Array = []:
	set(value):
		values = value.duplicate()
		queue_redraw()
## Fill of the bars.
@export var bar_color := DEFAULT_BAR_COLOR:
	set(value):
		bar_color = value
		queue_redraw()
## Colour of the value labels.
@export var label_color := DEFAULT_LABEL_COLOR:
	set(value):
		label_color = value
		queue_redraw()
## Colour of the baseline.
@export var axis_color := DEFAULT_AXIS_COLOR:
	set(value):
		axis_color = value
		queue_redraw()
## Font size of the value labels, in pixels.
@export var font_size := DEFAULT_FONT_SIZE:
	set(value):
		font_size = value
		queue_redraw()
## Share of each bar's slot the bar fills (the rest is the gap), 0..1.
@export_range(_MIN_BAR_RATIO, 1.0) var bar_ratio := DEFAULT_BAR_RATIO:
	set(value):
		bar_ratio = value
		queue_redraw()
## Whether each bar's value is printed above it.
@export var show_values := true:
	set(value):
		show_values = value
		queue_redraw()
## Pixels kept free above the tallest bar, for its label.
@export var top_padding := DEFAULT_TOP_PADDING:
	set(value):
		top_padding = value
		queue_redraw()
## Pixels between the baseline and the bottom edge.
@export var bottom_padding := DEFAULT_BOTTOM_PADDING:
	set(value):
		bottom_padding = value
		queue_redraw()
## Optional `func(value) -> String` that makes each value's label (for example
## `func(v): return "%d pts" % v`). Unset, each value is rounded to two decimals and
## printed without trailing zeros (`3`, `2.5`, `3.14`). Setting it does not redraw; call
## `queue_redraw()` if needed.
var value_text: Callable


## Returns the rectangle of each bar in this control's local coordinates, in `values`
## order: exactly what is drawn. Empty when `values` is empty.
func bar_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if values.is_empty():
		return rects
	var top := 0.0
	for value: Variant in values:
		top = maxf(top, _bar_value(value))
	if top <= 0.0:
		top = 1.0
	var slot := size.x / values.size()
	var width := maxf(slot * clampf(bar_ratio, 0.0, 1.0), _MIN_BAR_WIDTH)
	var base := size.y - bottom_padding
	var full := maxf(base - top_padding, 0.0)
	for i in values.size():
		var height := full * _bar_value(values[i]) / top
		rects.append(Rect2(i * slot + (slot - width) / 2.0, base - height, width, height))
	return rects


## Returns where each value label is drawn, in `values` order and local coordinates:
## the rect of its text (`format_value`) in the theme's default font at `font_size`,
## centred on its bar and with its bottom 4 px above the bar's top. Empty
## when `values` is empty or there is no font.
func value_label_rects() -> Array[Rect2]:
	var labels: Array[Rect2] = []
	var font := get_theme_default_font()
	if font == null:
		return labels
	var rects := bar_rects()
	for i in rects.size():
		var text_size := font.get_string_size(format_value(values[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var bottom := rects[i].position.y - _LABEL_GAP
		labels.append(Rect2(Vector2(rects[i].get_center().x - text_size.x / 2.0, bottom - text_size.y), text_size))
	return labels


## Returns the label text printed above a bar showing `value`: from `value_text` when it
## is set, otherwise the number rounded to two decimals and printed without trailing
## zeros (`2.999` prints `3`, `123456.78` stays `123456.78`), `inf` / `nan` as such. A
## value that is not an int or float prints as its text.
func format_value(value: Variant) -> String:
	if value_text.is_valid():
		return str(value_text.call(value))
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return str(value) if value != null else '<null>'
	var number := float(value)
	if is_nan(number):
		return _NAN_TEXT
	if is_inf(number):
		return _NEG_INF_TEXT if number < 0.0 else _INF_TEXT
	if absf(number) >= _INT_PRINT_LIMIT:
		return String.num(number, 0)
	var rounded := snappedf(number, _FRACTION_STEP)
	if rounded != roundf(rounded):
		return String.num(rounded, _FRACTION_DECIMALS)
	return str(int(rounded))


## The height a value draws at, before scaling: negatives, NaN, infinities and non-numbers count as 0.
func _bar_value(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0
	var number := float(value)
	return number if is_finite(number) and number > 0.0 else 0.0


func _draw() -> void:
	for rect in bar_rects():
		draw_rect(rect, bar_color)
	var base := size.y - bottom_padding
	draw_line(Vector2(0, base), Vector2(size.x, base), axis_color, _AXIS_WIDTH)
	if not show_values:
		return
	var font := get_theme_default_font()
	var labels := value_label_rects()
	for i in labels.size():
		# draw_string takes the text's baseline: the bottom of its rect minus the descent.
		var baseline := Vector2(labels[i].position.x, labels[i].end.y - font.get_descent(font_size))
		draw_string(font, baseline, format_value(values[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
