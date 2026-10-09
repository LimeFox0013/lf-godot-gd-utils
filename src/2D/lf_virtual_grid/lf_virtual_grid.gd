## Tells you which rows of a long vertical list in the 2D world are in view, so you
## build only those.
##
## The rows are fixed-height bands stacked downward from `base_position` (row 0 on top,
## row 1 below it, ...). As the camera moves, the grid emits `rows_exited` for rows that
## leave the view and `rows_entered` for rows that enter it, so callers create (or
## recycle) nodes for the visible rows only. This is "virtualization": the grid's own work per
## update depends on how many rows are visible, not on how long the list is. It works in
## world space under a Camera2D; for UI lists made of Controls use Godot's containers
## instead.
class_name LFVirtualGrid
extends Node2D

## Emitted with the indices of rows that are no longer visible: free or recycle their
## nodes. Always emitted before `rows_entered` within one update, so their nodes can be
## reused for the rows that enter.
signal rows_exited(rows: Array[int])
## Emitted with the indices of rows that just became visible: build or place their
## nodes (`get_row_rect_world(row)` says where).
signal rows_entered(rows: Array[int])

## Default `row_height`, in world units.
const DEFAULT_ROW_HEIGHT := 100.0
## Default `row_count`: -1, unbounded in both directions.
const DEFAULT_ROW_COUNT := -1

## The `row_count` that means unbounded; lower values are raised to it.
const _UNBOUNDED_ROW_COUNT := -1
## The (first, last) row span meaning no row is visible: last below first.
const _NO_ROWS := Vector2i(0, -1)
## Lower end of the Inspector slider for `row_height`, in world units.
const _ROW_HEIGHT_HINT_MIN := 0.01
## Upper end of the Inspector slider for `row_height`, in world units (larger typed
## values are allowed).
const _ROW_HEIGHT_HINT_MAX := 1000.0
## Step of the Inspector slider for `row_height`, in world units.
const _ROW_HEIGHT_HINT_STEP := 0.01
## Upper end of the Inspector slider for `row_count`, in rows (larger typed values are
## allowed).
const _ROW_COUNT_HINT_MAX := 100000

static var _log := LFLogger.new()

## The camera whose view decides which rows are visible; it should be its viewport's
## current camera (Godot updates the view of that one only). Not needed when both
## `viewport_tracker` and `draw_area` are set. Without a view nothing is drawn.
@export var camera: Camera2D
## Height of one row in world units; must be finite and greater than zero (other values are
## rejected with an error and the old height is kept). Changing it redraws every
## visible row.
@export_range(_ROW_HEIGHT_HINT_MIN, _ROW_HEIGHT_HINT_MAX, _ROW_HEIGHT_HINT_STEP, "or_greater", "suffix:px") var row_height: float = DEFAULT_ROW_HEIGHT:
	set(value):
		if !(value > 0.0 and is_finite(value)):
			_log.error("LFVirtualGrid: row_height must be finite and greater than zero, got %s" % value)
			return
		row_height = value
		if is_inside_tree():
			refresh()

## Optional node the view rect is centred on instead of the camera (e.g. a steadier
## rig the camera hangs from, or the node the camera follows).
@export var viewport_tracker: Node2D

## Custom view size in world units; (0, 0) uses the camera's real view size. A larger
## area draws rows ahead of time, before they scroll into view.
@export var draw_area: Vector2 = Vector2.ZERO

## Number of rows: only rows 0 to `row_count - 1` are drawn. -1 (the default) means
## unbounded in both directions, negative rows included; values below -1 become -1.
## Changing it draws or erases just the difference.
@export_range(_UNBOUNDED_ROW_COUNT, _ROW_COUNT_HINT_MAX, 1, "or_greater") var row_count: int = DEFAULT_ROW_COUNT:
	set(value):
		row_count = maxi(value, _UNBOUNDED_ROW_COUNT)
		if is_inside_tree():
			update_grid()

## When the grid updates: on idle frames (default, like Camera2D) or on physics frames.
## Match the camera's own `process_callback`.
@export var process_callback: Camera2D.Camera2DProcessCallback = Camera2D.CAMERA2D_PROCESS_IDLE:
	set(value):
		process_callback = value
		LFUtils2D.apply_process_callback(self, value)

## World position row 0's top edge is laid out from (only its y is used). Captured from
## the node's world position when it becomes ready and by `reset()`; moving the node
## afterwards does not move the rows until the next `reset()`.
var base_position: Vector2 = Vector2.ZERO

## Index of the first visible row. Read it; the grid updates it.
var current_first_row: int = _NO_ROWS.x
## Index of the last visible row; less than `current_first_row` means no rows are
## visible. Read it; the grid updates it.
var current_last_row: int = _NO_ROWS.y

var _update_queued := false


# Captures base_position from the node's world position. The visible rows are drawn
# on the first update, so listeners connected in a parent's _ready() see them.
func _ready() -> void:
	process_callback = process_callback
	base_position = global_position


func _process(_delta: float) -> void:
	_queue_update()


func _physics_process(_delta: float) -> void:
	_queue_update()


## Sets `base_position` to `new_position` (world space; defaults to the node's current
## world position), moves the node there and redraws every visible row (`refresh()`).
func reset(new_position: Vector2 = _world_position()) -> void:
	base_position = new_position
	if is_inside_tree():
		global_position = base_position
	else:
		position = base_position
	refresh()


## Erases every visible row, then draws the rows in view again, e.g. after the data
## behind the rows changed. Draws immediately; draws nothing without a view. Rows a
## `rows_exited` listener already drew again (by calling `update_grid()`) are not drawn
## twice.
func refresh() -> void:
	clear_all()
	update_grid()


## Marks no rows visible, then emits `rows_exited` for every row that was visible
## (nothing when none was). The next update draws the rows in view again.
func clear_all() -> void:
	var rows_to_erase: Array[int] = get_current_visible_rows()
	current_first_row = _NO_ROWS.x
	current_last_row = _NO_ROWS.y
	if rows_to_erase.size() > 0:
		rows_exited.emit(rows_to_erase)


## Returns the indices of the visible rows, `current_first_row` to `current_last_row`
## in order; empty when none is visible.
func get_current_visible_rows() -> Array[int]:
	var rows: Array[int] = []
	for r in range(current_first_row, current_last_row + 1):
		rows.append(r)
	return rows


## Compares the rows in view with the visible ones: emits `rows_exited` for rows that
## left, then `rows_entered` for rows that entered. Emits nothing if the range is
## unchanged.
## When the view is gone (the camera left the tree or was freed, with no tracker and
## `draw_area` to stand in), every visible row is erased (`clear_all`) and none is drawn.
## Runs by itself at the end of every frame; call it to update sooner.
func update_grid() -> void:
	if !_has_view():
		clear_all()
		return

	var span := _visible_span(get_effective_view_rect_world())
	var new_first_row := span.x
	var new_last_row := span.y
	if new_first_row == current_first_row and new_last_row == current_last_row:
		return

	var rows_to_erase: Array[int] = []
	for r in range(current_first_row, current_last_row + 1):
		if r < new_first_row or r > new_last_row:
			rows_to_erase.append(r)

	var rows_to_draw: Array[int] = []
	for r in range(new_first_row, new_last_row + 1):
		if r < current_first_row or r > current_last_row:
			rows_to_draw.append(r)

	current_first_row = new_first_row
	current_last_row = new_last_row

	if rows_to_erase.size() > 0:
		rows_exited.emit(rows_to_erase)
	if rows_to_draw.size() > 0:
		rows_entered.emit(rows_to_draw)


## Returns `cam`'s real view in world coordinates: the bounding box of the viewport's
## four corners mapped through the camera's canvas transform (zoom, offset, rotation).
## An empty `Rect2()` when the camera is null or not in the tree. Same as
## `LFUtils2D.camera_world_rect`.
func get_camera_viewport_rect_world(cam: Camera2D) -> Rect2:
	return LFUtils2D.camera_world_rect(cam)


## Returns the rect, in world coordinates, that decides which rows are visible: sized by
## `draw_area` if set (otherwise the camera's view size), centred on `viewport_tracker`
## if set (otherwise the camera's view centre). An empty `Rect2()` when the camera is
## needed but not in the tree.
func get_effective_view_rect_world() -> Rect2:
	var tracked := is_instance_valid(viewport_tracker) and viewport_tracker.is_inside_tree()
	var size: Vector2 = draw_area
	var center: Vector2
	if !tracked or draw_area == Vector2.ZERO:
		if !_camera_in_tree():
			return Rect2()
		var base_view: Rect2 = get_camera_viewport_rect_world(camera)
		if draw_area == Vector2.ZERO:
			size = base_view.size
		center = base_view.get_center()
	if tracked:
		center = viewport_tracker.global_position
	return Rect2(center - size * 0.5, size)


## Returns where row `row` is in the world: as wide as the effective view,
## `row_height` tall, its top at `base_position.y + row * row_height`. Works for any
## row, visible or not.
func get_row_rect_world(row: int) -> Rect2:
	var view: Rect2 = get_effective_view_rect_world()
	var row_top_y: float = base_position.y + float(row) * row_height
	return Rect2(Vector2(view.position.x, row_top_y), Vector2(view.size.x, row_height))


## Returns `get_row_rect_world(row)` in screen (viewport) pixels: its top-left and
## bottom-right corners mapped through the camera's canvas transform. Exact without
## camera rotation; with a rotated camera the two corners do not bound the row on
## screen. An empty `Rect2()` without a camera in the tree.
func get_row_rect_screen(row: int) -> Rect2:
	if !_camera_in_tree():
		return Rect2()
	var world_rect: Rect2 = get_row_rect_world(row)
	var cam_xform: Transform2D = camera.get_canvas_transform()
	var screen_top_left: Vector2 = cam_xform * world_rect.position
	var screen_bottom_right: Vector2 = cam_xform * world_rect.end
	return Rect2(screen_top_left, screen_bottom_right - screen_top_left)


# The grid reads the view at the end of the frame, after every node (the camera
# included) has processed, so the drawn rows match the view that frame renders
# whatever the tree order.
func _queue_update() -> void:
	if _update_queued:
		return
	_update_queued = true
	_update_now.call_deferred()


func _update_now() -> void:
	_update_queued = false
	# A camera moved this frame publishes its new view only once its pending transform
	# change is handled; a smoothing camera already stepped during its own processing.
	LFUtils2D.settle(camera)
	update_grid()


func _has_view() -> bool:
	if draw_area != Vector2.ZERO and is_instance_valid(viewport_tracker) and viewport_tracker.is_inside_tree():
		return true
	return _camera_in_tree()


func _camera_in_tree() -> bool:
	return LFUtils2D.camera_ready(camera)


# The node's world position; its local position while outside the tree (where the
# two coincide for a parentless node and global_position is unavailable).
func _world_position() -> Vector2:
	return global_position if is_inside_tree() else position


# The [first, last] rows whose rects overlap `view` (a row merely touching an edge is
# out), clamped to [0, row_count) when a count is set; (0, -1) when none.
func _visible_span(view: Rect2) -> Vector2i:
	var first := floori((view.position.y - base_position.y) / row_height)
	var last := ceili((view.end.y - base_position.y) / row_height) - 1
	if row_count > _UNBOUNDED_ROW_COUNT:
		first = maxi(first, 0)
		last = mini(last, row_count - 1)
	if last < first:
		return _NO_ROWS
	return Vector2i(first, last)
