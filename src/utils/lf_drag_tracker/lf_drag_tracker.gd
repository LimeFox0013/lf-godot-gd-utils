## Tells whether a mouse or touch press was a tap (a click) or a drag.
##
## Call `press`, `move` and `release` from your input code for one pointer button; it reads
## no input itself. Once the pointer moves more than `threshold` pixels from where the
## button went down, the press counts as a drag until it is released, even if the pointer
## comes back. So a press that turns into a camera pan does not also count as a tap
## (select, place) on release. Give it positions in one coordinate space.
class_name LFDragTracker
extends RefCounted

## The default `threshold`, in pixels.
const DEFAULT_THRESHOLD := 6.0

## Distance in pixels the pointer must move past (strictly more than) to become a drag.
var threshold: float
## Whether the button is down right now.
var pressed := false
## Whether the current (or last) press has moved past `threshold`.
var dragged := false
## Where the current (or last) press went down.
var down_position := Vector2.ZERO


## A tracker that calls a press a drag once it moves more than `drag_threshold` pixels.
func _init(drag_threshold: float = DEFAULT_THRESHOLD) -> void:
	threshold = drag_threshold


## The button went down at `position`: starts a fresh press, not yet a drag.
func press(position: Vector2) -> void:
	pressed = true
	dragged = false
	down_position = position


## The pointer moved to `position`. Returns whether the button is down and the press is a
## drag now; always false while the button is up.
func move(position: Vector2) -> bool:
	if not pressed:
		return false
	if not dragged and position.distance_to(down_position) > threshold:
		dragged = true
	return dragged


## The button came up. Returns whether the press was a tap rather than the end of a drag;
## false when the button was not down (a release whose press this tracker never saw).
func release() -> bool:
	if not pressed:
		return false
	pressed = false
	return not dragged
