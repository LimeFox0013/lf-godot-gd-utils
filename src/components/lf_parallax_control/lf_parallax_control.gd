## A Control that slides its picture layers at different speeds for a parallax (depth) effect in menus.
##
## It moves its child LFParallaxLayer nodes in one of two modes:
## proportionally to a shared shift value (`move`, each layer scaled by its own
## `motion_scale`), or at a numbered slide (`move_by_slide`, each layer spread by its own
## width so the first and last slides align its edges with the control's). Both tween
## over `duration` seconds, or apply at once when `duration <= 0` (and for a layer outside
## the tree); a new move replaces a layer's running tween. In slide mode the layers are
## placed again, at once, when the control's size changes, cutting a running slide tween
## short.
## The tracked layer list only refreshes on `reset()`; a freed layer is skipped and
## dropped from it.
class_name LFParallaxControl
extends Control

static var _log := LFLogger.new()

enum _Mode { NONE, SHIFT, SLIDE }

## Default seconds `move` and `move_by_slide` tween over.
const DEFAULT_DURATION := 0.8

## Property a layer tweens in shift mode.
const _POSITION_PATH := ^"position"
## Property a layer tweens in slide mode: its X only.
const _POSITION_X_PATH := ^"position:x"

## Number of slides `move_by_slide` spreads the layers across.
@export var slides := 0
## Slide index last moved to by `move_by_slide`; when non-zero at `_ready()`, the
## layers are placed on it at once.
@export var active_slide := 0

## The LFParallaxLayer children being moved, as of the last `reset()` (which `_ready()`
## calls). Read it; call `reset()` after adding or removing layers.
var layers: Array[LFParallaxLayer] = []
## The shift last passed to `move` (0, 0 before any move). `move_by_slide` does not
## change it.
var shift := Vector2(0.0, 0.0)

## Mode of the last move, re-applied on resize when it is SLIDE.
var _mode := _Mode.NONE


func _ready() -> void:
	resized.connect(_on_resized)
	reset()
	if active_slide != 0:
		move_by_slide(active_slide, 0.0)


## Rebuilds `layers` from the current LFParallaxLayer children.
func reset() -> void:
	layers.clear()
	for child in get_children():
		if child is LFParallaxLayer:
			layers.append(child)


## Moves every layer's position to `-new_shift * motion_scale` over `duration` seconds (at
## once when `duration <= 0`). A shift that is not finite (NaN or infinite) pushes an error and
## changes nothing.
func move(new_shift: Vector2 = shift, duration := DEFAULT_DURATION) -> void:
	if not new_shift.is_finite():
		_log.error("LFParallaxControl: shift must be finite, got %s" % new_shift)
		return
	shift = new_shift
	_mode = _Mode.SHIFT
	for layer in _live_layers():
		LFAnimate.control(layer, _POSITION_PATH, -(new_shift * layer.motion_scale), duration, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)


## Moves every layer horizontally to slide `slide_index`, clamped to `[0, slides - 1]`
## (whole control widths plus the layer's spare width spread over the gaps), over
## `duration` seconds (at once when `duration <= 0`). Each layer keeps its Y.
## `motion_scale` is not applied: each layer's own width sets how far it travels.
func move_by_slide(slide_index: int, duration := DEFAULT_DURATION) -> void:
	active_slide = clampi(slide_index, 0, maxi(slides - 1, 0))
	_mode = _Mode.SLIDE
	for layer in _live_layers():
		# With fewer than two slides there are no gaps to spread the spacing over.
		var slide_space := (layer.size.x - size.x * slides) / (slides - 1) if slides > 1 else 0.0
		var layer_shift := slide_space * active_slide + size.x * active_slide
		LFAnimate.control(layer, _POSITION_X_PATH, -layer_shift, duration, Tween.TRANS_LINEAR, Tween.EASE_OUT)


## The tracked layers that still exist; freed ones are dropped from `layers`.
func _live_layers() -> Array[LFParallaxLayer]:
	for i in range(layers.size() - 1, -1, -1):
		if not is_instance_valid(layers[i]):
			layers.remove_at(i)
	return layers.duplicate()


func _on_resized() -> void:
	if _mode == _Mode.SLIDE:
		move_by_slide(active_slide, 0.0)
