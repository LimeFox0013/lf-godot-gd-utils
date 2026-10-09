## A UI anchor that moves a Node2D onto the screen point at its centre.
##
## Lay this control out like any UI element, set `target` to a Node2D, and the Node2D is
## placed on the control's on-screen centre: on demand with `sync_target()`, every frame
## with `follow`, or, with `sync_initial_position`, once when the control is first ready
## and again after the first layout pass. The target may live in another canvas (the world under a Camera2D,
## another CanvasLayer); it still lands on the same screen point. The control itself is
## click-through (see `LFLayoutControl`).
class_name LFControl2D
extends LFLayoutControl

static var _log := LFLogger.new()

## The Node2D to place on this control's on-screen centre. Null places nothing.
@export var target: Node2D
## When true, the target is snapped to this control's center at the first `_ready()`,
## and once more on the first frame after it, once any Container has laid it out.
## Later tree entries do not resync.
@export var sync_initial_position := false
## When true, the target is snapped to this control's center every frame.
@export var follow := false:
	set(value):
		follow = value
		_update_processing()

var _resync_after_layout := false


func _ready() -> void:
	if sync_initial_position:
		sync_target()
		_resync_after_layout = true
	_update_processing()


func _process(_delta: float) -> void:
	if (_resync_after_layout or follow) and is_instance_valid(target):
		sync_target()
	_resync_after_layout = false
	_update_processing()


## Moves `target` now so it sits on this control's on-screen centre, converting through
## both canvas transforms. Pushes a warning and does nothing when there is no target;
## does nothing while the target or this control is outside the tree.
func sync_target() -> void:
	if not is_instance_valid(target):
		_log.warning("LFControl2D: no target to place")
		return
	if not target.is_inside_tree() or not is_inside_tree():
		return
	var screen_point: Vector2 = LFControl.get_center_pos_on_viewport(self)
	target.global_position = target.get_canvas_transform().affine_inverse() * screen_point


func _update_processing() -> void:
	set_process(follow or _resync_after_layout)
