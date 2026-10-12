## A multi-line text field that grows as you type, between a smallest and a largest size.
##
## The width follows the longest line until `max_size.x`, where long lines start to wrap; the
## height follows the wrapped text until `max_size.y`, where the field scrolls. It sets
## `custom_minimum_size`, so put it in a container (or give it no fixed size) and the layout
## does the rest. The measuring is in the static `fitted_size`, which needs no scene.
class_name LFAutoSizeTextEdit
extends TextEdit


## The smallest size, when none is set.
const DEFAULT_MIN_SIZE := Vector2(120.0, 40.0)
## The largest size, when none is set.
const DEFAULT_MAX_SIZE := Vector2(800.0, 400.0)
## Extra width after the longest line, in pixels, so the caret at the end of a line is not clipped.
const DEFAULT_EXTRA_WIDTH_PADDING := 4.0

## The smallest size the field takes (an empty field has exactly this).
@export var min_size := DEFAULT_MIN_SIZE:
	set(value):
		min_size = value
		_queue_refit()
## The largest size: past it the text wraps (width) and scrolls (height). A value below
## `min_size` counts as `min_size`.
@export var max_size := DEFAULT_MAX_SIZE:
	set(value):
		max_size = value
		_queue_refit()
## Pixels added to the width of the longest line.
@export var extra_width_padding := DEFAULT_EXTRA_WIDTH_PADDING:
	set(value):
		extra_width_padding = value
		_queue_refit()

var _refit_queued := false


func _init() -> void:
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_changed.connect(_queue_refit)
	text_set.connect(_queue_refit)
	theme_changed.connect(_queue_refit)
	visibility_changed.connect(_queue_refit)


func _ready() -> void:
	refit()


## The size a field with this `content` takes: the width of the longest line plus `margins.x`
## and `extra_width`, kept between `smallest.x` and `largest.x`; the height of the text wrapped
## to that width (never less than one line) plus `margins.y`, kept between `smallest.y` and
## `largest.y`. `margins` is the space the field's background style leaves around the text.
## A `largest` below `smallest` counts as `smallest`. The wrapped height is measured with a
## `TextParagraph` breaking at words and, for a word wider than the field, between characters;
## the field's own layout may differ from it by a line in unusual texts.
static func fitted_size(content: String, font: Font, font_size: int, margins: Vector2, smallest: Vector2, largest: Vector2, extra_width := DEFAULT_EXTRA_WIDTH_PADDING) -> Vector2:
	var limit := Vector2(maxf(largest.x, smallest.x), maxf(largest.y, smallest.y))
	var longest := 0.0
	for line in content.split('\n'):
		longest = maxf(longest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	var width := clampf(ceilf(longest) + margins.x + extra_width, smallest.x, limit.x)
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND
	paragraph.add_string(content, font, font_size)
	paragraph.width = maxf(width - margins.x, 0.0)
	var text_height := maxf(paragraph.get_size().y, font.get_height(font_size))
	var height := clampf(ceilf(text_height) + margins.y, smallest.y, limit.y)
	return Vector2(width, height)


## Measures the text now and sets `custom_minimum_size` to the result, which it returns.
## The field does this by itself when the text, the theme, the visibility or the three size
## properties change; call it to force a measurement, for example after changing the font in
## code. Does nothing and returns `custom_minimum_size` while outside the scene tree.
func refit() -> Vector2:
	_refit_queued = false
	if not is_inside_tree():
		return custom_minimum_size
	var style := get_theme_stylebox('normal')
	var margins := Vector2.ZERO
	if style != null:
		margins = style.get_minimum_size()
	custom_minimum_size = fitted_size(text, get_theme_font('font'), get_theme_font_size('font_size'), margins, min_size, max_size, extra_width_padding)
	return custom_minimum_size


# Measures once at the end of the frame, however many changes came in.
func _queue_refit() -> void:
	if _refit_queued:
		return
	_refit_queued = true
	refit.call_deferred()
