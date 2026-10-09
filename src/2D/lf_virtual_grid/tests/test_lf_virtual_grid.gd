extends GutTest

var camera: Camera2D
var tracker: Node2D
var grid: LFVirtualGrid

## Row height the fixture grid uses, in world units.
const ROW_HEIGHT := 100.0


class CameraMover extends Node:
	var cam: Camera2D
	var step := 60.0

	func _process(_delta: float) -> void:
		cam.global_position.y += step


func before_each():
	camera = add_child_autofree(Camera2D.new())
	tracker = add_child_autofree(Node2D.new())
	tracker.global_position = Vector2.ZERO
	grid = add_child_autofree(LFVirtualGrid.new())
	grid.camera = camera
	grid.viewport_tracker = tracker
	grid.draw_area = Vector2(100, 250) # fixed, viewport-independent view size
	grid.row_height = ROW_HEIGHT
	grid.reset(Vector2.ZERO)


func test_effective_view_rect_follows_the_tracker_when_one_is_set():
	tracker.global_position = Vector2(500, 500)
	var rect = grid.get_effective_view_rect_world()
	assert_eq(rect.get_center(), Vector2(500, 500))


func test_a_tracker_without_a_draw_area_centres_the_cameras_view_size_on_itself():
	grid.draw_area = Vector2.ZERO
	tracker.global_position = Vector2(500, -200)

	var rect := grid.get_effective_view_rect_world()

	assert_eq(rect.get_center(), Vector2(500, -200))
	assert_almost_eq(rect.size, LFUtils2D.camera_world_rect(camera).size, Vector2.ONE * 0.01)


func test_effective_view_rect_ignores_the_trackers_position_once_it_is_unset():
	tracker.global_position = Vector2(999, 999)
	grid.viewport_tracker = null

	var rect = grid.get_effective_view_rect_world()

	assert_almost_eq(rect.get_center(), LFUtils2D.camera_world_rect(camera).get_center(), Vector2.ONE * 0.01, "centred on the camera's view")
	assert_eq(rect.size, Vector2(100, 250), "still sized by draw_area")


func test_moving_the_tracker_draws_newly_visible_rows_and_erases_ones_no_longer_visible():
	var drawn := []
	var erased := []
	grid.rows_entered.connect(func(rows): drawn.append_array(rows))
	grid.rows_exited.connect(func(rows): erased.append_array(rows))

	tracker.global_position = Vector2(0, 1000) # view moves from y -125..125 to 875..1125
	grid.update_grid()

	assert_eq(drawn, [8, 9, 10, 11], "the rows now in view")
	assert_eq(erased, [-2, -1, 0, 1], "the rows that were in view")


func test_update_grid_emits_nothing_when_the_visible_row_range_is_unchanged():
	var drawn := []
	var erased := []
	grid.rows_entered.connect(func(rows): drawn.append_array(rows))
	grid.rows_exited.connect(func(rows): erased.append_array(rows))

	grid.update_grid() # tracker has not moved since reset()

	assert_eq(drawn, [])
	assert_eq(erased, [])


func test_a_row_is_erased_only_after_having_been_drawn():
	# Seed with the baseline rows reset() already drew silently in
	# before_each(), before these listeners existed to observe it.
	var drawn_so_far := {}
	for r in grid.get_current_visible_rows():
		drawn_so_far[r] = true
	var erased_never_drawn := []
	grid.rows_entered.connect(func(rows):
		for r in rows:
			drawn_so_far[r] = true
	)
	grid.rows_exited.connect(func(rows):
		for r in rows:
			if !drawn_so_far.has(r):
				erased_never_drawn.append(r)
	)

	for step in [Vector2(0, 300), Vector2(0, -600), Vector2(0, 900)]:
		tracker.global_position = step
		grid.update_grid()

	assert_eq(erased_never_drawn, [])


func test_the_packaged_scene_attaches_the_virtual_grid_script():
	var node = load(_module_dir().path_join("lf_virtual_grid.tscn")).instantiate()
	assert_true(node is LFVirtualGrid, "the scene must attach its LFVirtualGrid script")
	node.free()


func test_rows_drawn_from_an_offset_base_are_the_rows_whose_rects_are_in_view():
	var drawn := []
	grid.rows_entered.connect(func(rows): drawn.append_array(rows))
	tracker.global_position = Vector2(0, 1125) # view spans y 1000..1250

	grid.reset(Vector2(0, 1000)) # the grid's row 0 now starts at y=1000

	assert_eq(drawn, [0, 1, 2], "row indices must count from base_position, like get_row_rect_world does")
	var view: Rect2 = grid.get_effective_view_rect_world()
	for r in drawn:
		assert_true(grid.get_row_rect_world(r).intersects(view), "row %s was drawn but its rect is out of view" % r)


func test_a_grid_entering_the_tree_without_a_camera_draws_nothing_and_does_not_fail():
	var drawn := []
	var bare := LFVirtualGrid.new()
	bare.rows_entered.connect(func(rows): drawn.append_array(rows))

	add_child_autofree(bare)
	bare.update_grid()

	assert_eq(drawn, [])
	assert_engine_error_count(0)


func test_camera_viewport_rect_is_the_visible_viewport_mapped_into_world_space():
	var vp_rect: Rect2 = camera.get_viewport().get_visible_rect()
	var inv: Transform2D = camera.get_canvas_transform().affine_inverse()

	var rect: Rect2 = grid.get_camera_viewport_rect_world(camera)

	assert_eq(rect.position, inv * vp_rect.position, "top-left must be the screen top-left in world space")
	assert_eq(rect.end, inv * vp_rect.end, "bottom-right must be the screen bottom-right in world space")


func test_camera_viewport_rect_shrinks_in_world_units_when_the_canvas_is_zoomed_in():
	var vp_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var original := camera.get_viewport().canvas_transform
	camera.get_viewport().canvas_transform = Transform2D().scaled(Vector2(2, 2))

	var rect: Rect2 = grid.get_camera_viewport_rect_world(camera)
	camera.get_viewport().canvas_transform = original

	assert_eq(rect.size, vp_size / 2.0, "a 2x canvas zoom must show half the world size")


func test_row_rect_screen_is_the_world_row_rect_mapped_through_the_camera():
	var xform: Transform2D = camera.get_canvas_transform()
	var world: Rect2 = grid.get_row_rect_world(1)

	var screen: Rect2 = grid.get_row_rect_screen(1)

	assert_eq(screen.position, xform * world.position)
	assert_eq(screen.end, xform * world.end)


func test_screen_rects_of_consecutive_rows_stack_without_gaps():
	var row0: Rect2 = grid.get_row_rect_screen(0)
	var row1: Rect2 = grid.get_row_rect_screen(1)

	assert_almost_eq(row1.position.y, row0.end.y, 0.001, "row 1 must start on screen where row 0 ends")


func test_clear_all_erases_every_visible_row_and_leaves_none_visible():
	var erased := []
	grid.rows_exited.connect(func(rows): erased.append_array(rows))
	var visible := grid.get_current_visible_rows()
	assert_true(visible.size() > 0, "precondition: reset() made some rows visible")

	grid.clear_all()

	assert_eq(erased, visible, "every visible row must be erased")
	assert_eq(grid.get_current_visible_rows(), [], "no rows remain visible after clear_all")


func test_clear_all_on_an_already_empty_grid_emits_nothing():
	grid.clear_all()
	var erased := []
	grid.rows_exited.connect(func(rows): erased.append_array(rows))

	grid.clear_all()

	assert_eq(erased, [], "nothing visible means nothing to erase")


func test_the_next_update_after_clear_all_redraws_the_visible_rows():
	var drawn := []
	grid.rows_entered.connect(func(rows): drawn.append_array(rows))
	var visible := grid.get_current_visible_rows()

	grid.clear_all()
	grid.update_grid()

	assert_eq(drawn, visible, "rows still in view must be drawn again after a clear")


func test_row_zero_starts_at_the_grids_world_position_under_an_offset_parent():
	var parent: Node2D = add_child_autofree(Node2D.new())
	parent.position = Vector2(0, 1000)
	var nested := LFVirtualGrid.new()
	nested.camera = camera
	nested.viewport_tracker = tracker
	nested.draw_area = Vector2(100, 250)
	nested.row_height = ROW_HEIGHT
	tracker.global_position = Vector2(0, 1125) # view spans y 1000..1250
	parent.add_child(nested) # _ready() resets from the node's own position
	var drawn := []
	nested.rows_entered.connect(func(rows): drawn.append_array(rows))

	nested.reset()

	assert_eq(nested.base_position, Vector2(0, 1000), "base_position is the grid's world position")
	assert_eq(nested.global_position, Vector2(0, 1000), "reset() must not move the grid")
	assert_eq(nested.get_row_rect_world(0).position.y, 1000.0, "row 0 starts at the grid's world y")
	assert_eq(drawn, [0, 1, 2])


func test_reset_to_a_world_position_places_the_grid_there_under_an_offset_parent():
	var parent: Node2D = add_child_autofree(Node2D.new())
	parent.position = Vector2(0, 1000)
	var nested := LFVirtualGrid.new()
	parent.add_child(nested)

	nested.reset(Vector2(0, 300))

	assert_eq(nested.global_position, Vector2(0, 300), "reset(p) takes a world position")


func test_rows_that_leave_are_erased_before_rows_that_enter_are_drawn():
	var events: Array[String] = []
	grid.rows_entered.connect(func(rows: Array[int]): events.append("draw"))
	grid.rows_exited.connect(func(rows: Array[int]): events.append("erase"))

	tracker.global_position = Vector2(0, 150)
	grid.update_grid()

	assert_eq(events, ["erase", "draw"])


func test_a_recycler_never_needs_more_cells_than_visible_rows():
	var live := {}
	var peak := [0]
	grid.clear_all()
	grid.rows_exited.connect(func(rows: Array[int]):
		for r in rows:
			live.erase(r)
	)
	grid.rows_entered.connect(func(rows: Array[int]):
		for r in rows:
			live[r] = true
		peak[0] = maxi(peak[0], live.size())
	)
	grid.update_grid()
	var visible := grid.get_current_visible_rows().size()

	for y in [50, 120, 260, 5000, 4990, -300]:
		tracker.global_position = Vector2(0, y)
		grid.update_grid()

	assert_eq(peak[0], visible, "erasing first lets the drawn rows reuse the erased rows' cells")


func test_a_row_that_only_touches_the_bottom_edge_of_the_view_is_not_drawn():
	grid.draw_area = Vector2(100, 300)
	tracker.global_position = Vector2(0, 150) # view spans y 0..300 exactly
	grid.reset(Vector2.ZERO)

	assert_eq(grid.get_current_visible_rows(), [0, 1, 2], "row 3 starts at y 300, where the view ends")
	var view: Rect2 = grid.get_effective_view_rect_world()
	for r in grid.get_current_visible_rows():
		assert_true(grid.get_row_rect_world(r).intersects(view), "row %s was drawn but its rect is out of view" % r)


func test_a_row_that_only_touches_the_top_edge_of_the_view_is_not_drawn():
	grid.draw_area = Vector2(100, 300)
	tracker.global_position = Vector2(0, 250) # view spans y 100..400
	grid.reset(Vector2.ZERO)

	assert_eq(grid.get_current_visible_rows(), [1, 2, 3])


func test_changing_the_row_height_redraws_every_visible_row():
	var drawn: Array[int] = []
	var erased: Array[int] = []
	var before := grid.get_current_visible_rows()
	grid.rows_entered.connect(func(rows: Array[int]): drawn.append_array(rows))
	grid.rows_exited.connect(func(rows: Array[int]): erased.append_array(rows))

	grid.row_height = 50.0

	assert_eq(erased, before, "every row laid out with the old height must be erased")
	assert_eq(drawn, grid.get_current_visible_rows(), "every visible row must be drawn at the new height")
	assert_eq(drawn, [-3, -2, -1, 0, 1, 2])


func test_a_row_height_of_zero_or_less_is_rejected():
	grid.row_height = 0.0
	assert_push_error("row_height")
	assert_eq(grid.row_height, ROW_HEIGHT, "the previous height is kept")

	grid.row_height = -10.0
	assert_push_error_count(2)
	assert_eq(grid.row_height, ROW_HEIGHT)
	assert_eq(grid.get_current_visible_rows(), [-2, -1, 0, 1])


func test_a_non_finite_row_height_is_rejected():
	for bad: float in [NAN, INF]:
		grid.row_height = bad
		assert_push_error("row_height")
		assert_eq(grid.row_height, ROW_HEIGHT, "the previous height is kept")
	assert_eq(grid.get_current_visible_rows(), [-2, -1, 0, 1], "the visible rows are untouched")


func test_a_row_count_bounds_the_drawn_rows():
	var drawn: Array[int] = []
	grid.rows_entered.connect(func(rows: Array[int]): drawn.append_array(rows))
	grid.row_count = 3
	grid.reset(Vector2.ZERO)

	assert_eq(drawn, [0, 1])

	tracker.global_position = Vector2(0, 1000)
	grid.update_grid()
	assert_eq(grid.get_current_visible_rows(), [], "no row past the count is drawn")


func test_changing_the_row_count_draws_or_erases_only_the_difference():
	var drawn: Array[int] = []
	var erased: Array[int] = []
	grid.row_count = 2
	grid.rows_entered.connect(func(rows: Array[int]): drawn.append_array(rows))
	grid.rows_exited.connect(func(rows: Array[int]): erased.append_array(rows))

	grid.row_count = 1
	assert_eq(erased, [1])
	assert_eq(drawn, [])

	grid.row_count = -1
	assert_eq(drawn, [-2, -1, 1], "an unbounded grid draws the negative rows too")


func test_refresh_redraws_every_visible_row_in_place():
	var drawn: Array[int] = []
	var erased: Array[int] = []
	var visible := grid.get_current_visible_rows()
	grid.rows_entered.connect(func(rows: Array[int]): drawn.append_array(rows))
	grid.rows_exited.connect(func(rows: Array[int]): erased.append_array(rows))

	grid.refresh()

	assert_eq(erased, visible)
	assert_eq(drawn, visible)
	assert_eq(grid.base_position, Vector2.ZERO)


func test_refresh_does_not_draw_twice_rows_an_erase_listener_already_redrew():
	var drawn: Array[int] = []
	grid.rows_entered.connect(func(rows: Array[int]): drawn.append_array(rows))
	grid.rows_exited.connect(func(_rows: Array[int]): grid.update_grid())

	grid.refresh()

	assert_eq(drawn, grid.get_current_visible_rows(), "each visible row is drawn once")


func test_a_tracker_and_a_draw_area_need_no_camera_in_the_tree():
	var off_tree_camera := Camera2D.new()
	var bare: LFVirtualGrid = add_child_autofree(LFVirtualGrid.new())
	bare.camera = off_tree_camera
	bare.viewport_tracker = tracker
	bare.draw_area = Vector2(100, 250)

	bare.reset(Vector2.ZERO)

	assert_eq(bare.get_current_visible_rows(), [-2, -1, 0, 1])
	off_tree_camera.free()


func test_a_camera_outside_the_tree_draws_nothing_and_does_not_fail():
	var off_tree_camera := Camera2D.new()
	var bare: LFVirtualGrid = add_child_autofree(LFVirtualGrid.new())
	bare.camera = off_tree_camera

	bare.reset(Vector2.ZERO)
	bare.update_grid()

	assert_eq(bare.get_current_visible_rows(), [])
	off_tree_camera.free()


func test_a_rotated_cameras_view_rect_bounds_all_four_corners():
	var vp_rect: Rect2 = camera.get_viewport().get_visible_rect()
	var original := camera.get_viewport().canvas_transform
	camera.get_viewport().canvas_transform = Transform2D(PI / 2.0, Vector2.ZERO)

	var rect: Rect2 = grid.get_camera_viewport_rect_world(camera)
	camera.get_viewport().canvas_transform = original

	assert_almost_eq(rect.size.x, vp_rect.size.y, 0.01, "a quarter turn swaps the view's width and height")
	assert_almost_eq(rect.size.y, vp_rect.size.x, 0.01)


func test_the_grid_draws_its_rows_on_the_first_frame_for_listeners_connected_after_ready():
	var late: LFVirtualGrid = LFVirtualGrid.new()
	late.camera = camera
	late.viewport_tracker = tracker
	late.draw_area = Vector2(100, 250)
	add_child_autofree(late)
	var drawn: Array[int] = []
	late.rows_entered.connect(func(rows: Array[int]): drawn.append_array(rows))

	await wait_process_frames(3)

	assert_eq(drawn, [-2, -1, 0, 1])


func test_an_idle_grid_covers_the_view_a_camera_moved_every_idle_frame_shows():
	var follower: LFVirtualGrid = LFVirtualGrid.new()
	follower.camera = camera
	add_child_autofree(follower)
	move_child(follower, 0) # processed before the camera and the mover
	var mover: CameraMover = add_child_autofree(CameraMover.new())
	mover.cam = camera
	await wait_process_frames(3)

	var uncovered := 0
	var view_size: Vector2 = camera.get_viewport().get_visible_rect().size
	for i in 30:
		await get_tree().process_frame
		var top := camera.get_screen_center_position().y - view_size.y * 0.5
		var bottom := top + view_size.y
		if floori(top / follower.row_height) < follower.current_first_row \
				or ceili(bottom / follower.row_height) - 1 > follower.current_last_row:
			uncovered += 1

	assert_gt(camera.global_position.y, 0.0, "precondition: the camera moved")
	assert_eq(uncovered, 0, "every row in the rendered view must already be drawn")


func test_the_process_callback_selects_idle_or_physics_updates():
	assert_true(grid.is_processing(), "idle by default, like Camera2D")
	assert_false(grid.is_physics_processing())

	grid.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS

	assert_true(grid.is_physics_processing())
	assert_false(grid.is_processing())


func test_row_rect_screen_without_a_camera_is_empty():
	grid.camera = null
	assert_eq(grid.get_row_rect_screen(0), Rect2())
	assert_engine_error_count(0)


## The module folder, wherever the library is installed.
func _module_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir().get_base_dir()


## The caller's row nodes must not outlive the view: losing it erases what was drawn.
func test_losing_the_view_erases_every_visible_row():
	grid.viewport_tracker = null
	grid.draw_area = Vector2.ZERO
	grid.update_grid()
	var visible := grid.get_current_visible_rows()
	assert_false(visible.is_empty(), 'the camera shows some rows')
	var erased := []
	grid.rows_exited.connect(func(rows): erased.append_array(rows))

	remove_child(camera)
	grid.update_grid()
	add_child(camera)

	assert_eq(erased, visible)
	assert_true(grid.get_current_visible_rows().is_empty())


func test_a_freed_camera_erases_the_drawn_rows_without_errors():
	var doomed := Camera2D.new()
	add_child(doomed)
	doomed.make_current()
	var bare: LFVirtualGrid = add_child_autofree(LFVirtualGrid.new())
	bare.camera = doomed
	await wait_process_frames(2)
	var visible := bare.get_current_visible_rows()
	assert_false(visible.is_empty(), "precondition: the camera shows some rows")
	var erased: Array[int] = []
	bare.rows_exited.connect(func(rows: Array[int]): erased.append_array(rows))

	doomed.free()
	await wait_process_frames(2)

	assert_eq(erased, visible)
	assert_eq(bare.get_row_rect_screen(0), Rect2())
	assert_engine_error_count(0)


func test_a_freed_tracker_falls_back_to_the_camera():
	grid.draw_area = Vector2.ZERO
	tracker.global_position = Vector2(0, 5000)
	tracker.free()

	var view := grid.get_effective_view_rect_world()
	var camera_view := LFUtils2D.camera_world_rect(camera)
	assert_almost_eq(view.position, camera_view.position, Vector2.ONE * 0.01)
	assert_almost_eq(view.size, camera_view.size, Vector2.ONE * 0.01)


func test_a_row_count_below_minus_one_means_unbounded():
	grid.row_count = -7
	assert_eq(grid.row_count, LFVirtualGrid.DEFAULT_ROW_COUNT)
	assert_eq(grid.get_current_visible_rows(), [-2, -1, 0, 1])


func test_a_row_count_of_zero_draws_no_row():
	var erased: Array[int] = []
	grid.rows_exited.connect(func(rows: Array[int]): erased.append_array(rows))
	grid.row_count = 0
	assert_eq(erased, [-2, -1, 0, 1])
	assert_eq(grid.get_current_visible_rows(), [])


func test_reset_outside_the_tree_places_the_grid_and_draws_once_it_has_a_view():
	var loose := LFVirtualGrid.new()
	var drawn: Array[int] = []
	loose.rows_entered.connect(func(rows: Array[int]): drawn.append_array(rows))

	loose.reset(Vector2(0, 100))
	assert_eq(loose.position, Vector2(0, 100))
	assert_eq(loose.base_position, Vector2(0, 100))
	assert_eq(drawn, [], "no view, nothing drawn")

	loose.viewport_tracker = tracker
	loose.draw_area = Vector2(100, 250)
	add_child_autofree(loose)
	await wait_process_frames(2)
	assert_eq(drawn, [-3, -2, -1, 0], "rows laid out from y = 100")


func test_a_grid_outside_the_tree_with_a_tracker_and_draw_area_draws_at_once():
	var loose := LFVirtualGrid.new()
	loose.viewport_tracker = tracker
	loose.draw_area = Vector2(100, 250)
	loose.reset(Vector2.ZERO)
	assert_eq(loose.get_current_visible_rows(), [-2, -1, 0, 1], "the tracker and draw_area are the whole view")
	loose.free()


func test_reset_without_a_position_keeps_the_grids_world_position():
	grid.global_position = Vector2(0, 50)
	grid.reset()
	assert_eq(grid.base_position, Vector2(0, 50))
	assert_eq(grid.get_row_rect_world(0).position.y, 50.0)


func test_a_row_rect_works_for_a_row_far_out_of_view():
	var rect := grid.get_row_rect_world(-40)
	assert_eq(rect.position, Vector2(-50, -4000))
	assert_eq(rect.size, Vector2(100, ROW_HEIGHT))


func test_changing_the_row_height_outside_the_tree_draws_nothing():
	var loose := LFVirtualGrid.new()
	var drawn: Array[int] = []
	loose.rows_entered.connect(func(rows: Array[int]): drawn.append_array(rows))
	loose.row_height = 20.0
	assert_eq(loose.row_height, 20.0)
	assert_eq(drawn, [])
	loose.free()
