## Shows one child page at a time and animates switching between them.
##
## Every Control child is a page (a menu screen, a tab, a step of a wizard); pages are
## looked up and switched by node name with `activate_slide`. After `setup()`, exactly one
## page is visible at rest (as long as nothing else changes page visibility). The switch
## animation is a swappable function (`slide_fn`); the default slides the old page out and the new one in. A page freed mid-switch, or `setup()` called
## mid-switch, does not leave the carousel busy; a custom `slide_fn` that never returns
## does, until the next `setup()`.
class_name LFCarousel
extends Control

## Emitted when a switch starts, before the transition runs.
signal slide_switch_started(from: String, to: String)
## Emitted after the transition finishes and `current_slide` is updated.
signal slide_changed(slide_name: String)

static var _log := LFLogger.new()

## Default `move_slide` duration in seconds.
const DEFAULT_TWEEN_DURATION := 0.25
## Seconds `x_shift_out` takes to slide the current page out.
const _SHIFT_OUT_DURATION := 0.28
## Seconds `x_shift_out` takes to slide the next page in.
const _SHIFT_IN_DURATION := 0.21
## `z_index` of the page in front (the shown or incoming one).
const _FRONT_Z := 1
## `z_index` of every page behind it.
const _BACK_Z := 0
## Page property `move_slide` tweens.
const _POSITION_PROPERTY := ^"position"

## When true, `_ready()` calls `setup()`.
@export var auto_setup := true
## Transition strategy `func(carousel: LFCarousel, next_slide_name: String)`, awaited by
## `activate_slide`. Once it returns, every page but the new current one is hidden.
var slide_fn: Callable = LFCarousel.x_shift_out

## Name of the active page.
var current_slide: String
## Pages (Control children) keyed by node name, as of the last `setup()`.
var slides_map: Dictionary[String, Control] = {}
## Page names in child order, as of the last `setup()`.
var slides_order: Array[String]
## True while `activate_slide` runs a transition; further requests are ignored.
var is_switching := false

## Bumped by `setup()`, so a switch it cancelled does not apply its result.
var _generation := 0
## Tweens started by `move_slide` that are still running.
var _tweens: Array[Tween] = []


func _ready() -> void:
	if auto_setup:
		setup()


## Ends any running switch, rebuilds the page map from the Control children, puts every
## page back at the origin, shows `init_slide_name` and hides the rest. An empty name
## picks the first page; an unknown one warns and picks the first page.
func setup(init_slide_name := current_slide) -> void:
	_cancel_switch()
	slides_map.clear()
	slides_order.clear()
	for child in get_children():
		if child is not Control:
			continue
		var page: Control = child
		page.position = Vector2.ZERO
		slides_map.set(page.name, page)
		slides_order.append(page.name)
	if init_slide_name and not slides_map.has(init_slide_name):
		_log.warning("LFCarousel: unknown slide '%s', showing the first one" % init_slide_name)
		init_slide_name = ""
	if not init_slide_name and not slides_order.is_empty():
		init_slide_name = slides_order[0]
	current_slide = init_slide_name
	_show_only(current_slide)


## The page's index in `slides_order` (child order), or -1 when there is no such page.
func get_slide_index(slide_name: String) -> int:
	return slides_order.find(slide_name)


## Shows (`state` true, z_index 1) or hides (false, z_index 0) the named page. An
## unknown or freed page is reported with a warning and ignored.
func set_slide_state(slide_name: String, state: bool) -> void:
	var page := _page_or_warn(slide_name)
	if page == null:
		return
	page.visible = state
	page.z_index = _FRONT_Z if state else _BACK_Z


## Coroutine (call it with `await` to wait for the animation): switches to `slide_name`
## through `slide_fn` and emits `slide_switch_started` / `slide_changed`. A no-op when it is
## already current or a switch is running; an unknown name is reported with a warning
## and ignored; an invalid `slide_fn` is reported and ignored. When the transition returns, exactly one page is visible: the new one,
## or the old one if the new one was freed meanwhile. A switch that `setup()` cancelled
## (even from a `slide_switch_started` handler) changes nothing more and emits nothing more.
func activate_slide(slide_name: String) -> void:
	if current_slide == slide_name or is_switching:
		return
	if not slide_fn.is_valid():
		_log.error('LFCarousel.activate_slide needs a valid slide_fn')
		return
	if _page(slide_name) == null:
		_log.warning("LFCarousel: unknown slide '%s'" % slide_name)
		return
	var previous := current_slide
	if _page(previous) == null:
		# Nothing valid to transition from: show the new page at once.
		current_slide = slide_name
		_show_only(current_slide)
		slide_changed.emit(current_slide)
		return

	is_switching = true
	var generation := _generation
	_page(previous).z_index = _BACK_Z
	_page(slide_name).z_index = _FRONT_Z
	slide_switch_started.emit(previous, slide_name)
	if generation != _generation:
		return  # a `slide_switch_started` handler called `setup()`
	await slide_fn.call(self, slide_name)
	if generation != _generation:
		return
	is_switching = false
	if _page(slide_name) != null:
		current_slide = slide_name
	elif _page(previous) == null:
		current_slide = _first_page_name()
	_show_only(current_slide)
	if current_slide != previous:
		slide_changed.emit(current_slide)


## Default strategy: slides `carousel`'s current page out and the next in from the
## opposite side (a later page comes in from the right), then hides the old page.
static func x_shift_out(carousel: LFCarousel, next_slide_name: String) -> void:
	var outgoing := carousel.current_slide
	var is_next_slide_before_current := carousel.get_slide_index(outgoing) > carousel.get_slide_index(next_slide_name)
	var direction := 1 if is_next_slide_before_current else -1
	await LFAwait.all([
		carousel.move_slide.bind(outgoing, Vector2(carousel.size.x * direction, 0), null, _SHIFT_OUT_DURATION),
		carousel.move_slide.bind(next_slide_name, Vector2.ZERO, Vector2(carousel.size.x * (-direction), 0), _SHIFT_IN_DURATION),
	])
	if carousel._page(outgoing) != null:
		carousel.set_slide_state(outgoing, false)


## Strategy for `slide_fn`: switches with no animation (the carousel hides the other pages).
static func instant(carousel: LFCarousel, next_slide_name: String) -> void:
	carousel.set_slide_state(next_slide_name, true)


## Coroutine (`await` it to wait for the tween): shows the page, jumps it to `from` when
## given (a Vector2; null keeps its current position), and tweens its position to `to`
## over `duration` seconds along the `tween_trans` curve (linear by default) with
## `tween_ease` easing, which shapes any curve but linear; `duration <= 0`, or a carousel outside
## the tree, moves it at once. The parameter order matches `LFAnimate.control` (duration, curve, easing). The
## tween belongs to the carousel, so it still finishes when the page is freed, and `setup()` ends it at once. An unknown or freed page warns and returns.
func move_slide(
	slide_name: String,
	to: Vector2,
	from: Variant = null,
	duration := DEFAULT_TWEEN_DURATION,
	tween_trans := Tween.TRANS_LINEAR,
	tween_ease := Tween.EASE_IN,
) -> void:
	var page := _page_or_warn(slide_name)
	if page == null:
		return
	if from != null:
		page.position = from
	page.visible = true
	if duration <= 0.0 or not is_inside_tree():
		page.position = to
		return

	var tween := create_tween()
	tween.set_trans(tween_trans)
	tween.set_ease(tween_ease)
	tween.tween_property(page, _POSITION_PROPERTY, to, duration)
	_tweens.append(tween)
	await tween.finished
	_tweens.erase(tween)


## The named page, or null when it is unknown or freed.
func _page(slide_name: String) -> Control:
	var page: Variant = slides_map.get(slide_name)
	if page == null or not is_instance_valid(page):
		return null
	return page


func _page_or_warn(slide_name: String) -> Control:
	var page := _page(slide_name)
	if page == null:
		_log.warning("LFCarousel: unknown slide '%s'" % slide_name)
	return page


func _first_page_name() -> String:
	for page_name in slides_order:
		if _page(page_name) != null:
			return page_name
	return ""


## Shows `slide_name` (z_index 1) and hides every other page (z_index 0).
func _show_only(slide_name: String) -> void:
	for page_name in slides_order:
		var page := _page(page_name)
		if page == null:
			continue
		page.visible = page_name == slide_name
		page.z_index = _FRONT_Z if page.visible else _BACK_Z


## Ends a running switch: the switch's result is dropped and its tweens jump to their
## end, so every coroutine awaiting them returns now.
func _cancel_switch() -> void:
	_generation += 1
	is_switching = false
	var running := _tweens.duplicate()
	_tweens.clear()
	for tween: Tween in running:
		if tween.is_valid():
			tween.custom_step(INF)
