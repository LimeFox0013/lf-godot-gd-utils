extends GutTest

const ZOOMS := Vector2(0.5, 1.0)       # (widest, closest)
const SPREADS := Vector2(100.0, 300.0)  # (closest until, widest from)


func _positions(points: Array) -> PackedVector2Array:
	return PackedVector2Array(points)


func test_framing_of_nothing_is_empty():
	assert_true(LFGroupCamera2D.framing(PackedVector2Array(), ZOOMS, SPREADS).is_empty())
	assert_true(LFGroupCamera2D.framing(_positions([Vector2(NAN, 0)]), ZOOMS, SPREADS).is_empty())


func test_framing_one_target_centres_on_it_at_the_closest_zoom():
	var pose := LFGroupCamera2D.framing(_positions([Vector2(40, -20)]), ZOOMS, SPREADS)
	assert_eq(pose.center, Vector2(40, -20))
	assert_eq(pose.zoom, 1.0)
	assert_eq(pose.spread, 0.0)


func test_framing_centres_on_the_average():
	var pose := LFGroupCamera2D.framing(_positions([Vector2(0, 0), Vector2(100, 0), Vector2(50, 90)]), ZOOMS, SPREADS)
	assert_eq(pose.center, Vector2(50, 30))


func test_framing_zoom_blends_with_the_spread():
	var near := LFGroupCamera2D.framing(_positions([Vector2.ZERO, Vector2(100, 0)]), ZOOMS, SPREADS)
	assert_eq(near.zoom, 1.0, "at the closest-view spread")
	var middle := LFGroupCamera2D.framing(_positions([Vector2.ZERO, Vector2(200, 0)]), ZOOMS, SPREADS)
	assert_almost_eq(middle.zoom, 0.75, 0.0001)
	var far := LFGroupCamera2D.framing(_positions([Vector2.ZERO, Vector2(900, 0)]), ZOOMS, SPREADS)
	assert_eq(far.zoom, 0.5, "past the widest-view spread")


func test_framing_spread_is_the_largest_distance_not_the_distance_from_the_centre():
	var pose := LFGroupCamera2D.framing(_positions([Vector2(0, 0), Vector2(30, 0), Vector2(0, 400)]), ZOOMS, SPREADS)
	assert_almost_eq(pose.spread, Vector2(30, 0).distance_to(Vector2(0, 400)), 0.0001)
	assert_eq(pose.zoom, 0.5)


func test_framing_ignores_non_finite_positions():
	var pose := LFGroupCamera2D.framing(_positions([Vector2(0, 0), Vector2(INF, 0), Vector2(10, 0)]), ZOOMS, SPREADS)
	assert_eq(pose.center, Vector2(5, 0))


func test_framing_with_no_spread_range_switches_at_the_spread():
	var flat := Vector2(100.0, 100.0)
	assert_eq(LFGroupCamera2D.framing(_positions([Vector2.ZERO, Vector2(100, 0)]), ZOOMS, flat).zoom, 1.0)
	assert_eq(LFGroupCamera2D.framing(_positions([Vector2.ZERO, Vector2(101, 0)]), ZOOMS, flat).zoom, 0.5)


func test_smoothed_zoom_moves_a_share_of_the_gap():
	assert_almost_eq(LFGroupCamera2D.smoothed_zoom(1.0, 0.0, 1.0, 1.0), exp(-1.0), 0.0001)


func test_smoothed_zoom_does_not_depend_on_the_frame_rate():
	var one_step := LFGroupCamera2D.smoothed_zoom(1.0, 0.5, 2.0, 1.0)
	var many := 1.0
	for i in 60:
		many = LFGroupCamera2D.smoothed_zoom(many, 0.5, 2.0, 1.0 / 60.0)
	assert_almost_eq(many, one_step, 0.0001)


func test_smoothed_zoom_ignores_bad_inputs():
	assert_eq(LFGroupCamera2D.smoothed_zoom(1.0, 0.5, 0.0, 1.0), 1.0)
	assert_eq(LFGroupCamera2D.smoothed_zoom(1.0, 0.5, 2.0, 0.0), 1.0)
	assert_eq(LFGroupCamera2D.smoothed_zoom(1.0, 0.5, 2.0, NAN), 1.0)
	assert_eq(LFGroupCamera2D.smoothed_zoom(1.0, NAN, 2.0, 1.0), 1.0)


func test_default_spreads_come_from_the_viewport():
	var spreads := LFGroupCamera2D.default_spreads(Vector2(1000, 600), 0.5)
	assert_almost_eq(spreads.x, 300.0, 0.0001, "half the shorter side")
	assert_almost_eq(spreads.y, 1600.0, 0.0001, "0.8 of the wider side of the area at zoom 0.5")
	assert_eq(LFGroupCamera2D.default_spreads(Vector2(1000, 600), 0.0).y, 800.0, "a zoom of 0 counts as 1")


func _camera() -> LFGroupCamera2D:
	var camera: LFGroupCamera2D = add_child_autofree(LFGroupCamera2D.new())
	camera.min_spread = 100.0
	camera.max_spread = 300.0
	return camera


func _target(at: Vector2) -> Node2D:
	var node: Node2D = add_child_autofree(Node2D.new())
	node.global_position = at
	return node


func test_the_camera_moves_to_the_middle_of_its_targets():
	var camera := _camera()
	camera.add_target(_target(Vector2(0, 0)))
	camera.add_target(_target(Vector2(200, 100)))
	camera.update_framing(0.0)
	assert_eq(camera.global_position, Vector2(100, 50))
	assert_eq(camera.zoom, Vector2.ONE, "a delta of 0 leaves the zoom alone")


func test_snap_to_targets_sets_position_and_zoom_at_once():
	var camera := _camera()
	camera.add_target(_target(Vector2(0, 0)))
	camera.add_target(_target(Vector2(1000, 0)))
	camera.snap_to_targets()
	assert_eq(camera.global_position, Vector2(500, 0))
	assert_eq(camera.zoom, Vector2(0.5, 0.5))


func test_the_zoom_eases_toward_the_goal():
	var camera := _camera()
	camera.add_target(_target(Vector2(0, 0)))
	camera.add_target(_target(Vector2(1000, 0)))
	camera.update_framing(0.1)
	assert_lt(camera.zoom.x, 1.0)
	assert_gt(camera.zoom.x, 0.5)


func test_a_freed_target_is_skipped_and_dropped():
	var camera := _camera()
	var kept := _target(Vector2(10, 10))
	var gone := Node2D.new()
	add_child(gone)
	gone.global_position = Vector2(1000, 1000)
	camera.add_target(kept)
	camera.add_target(gone)
	gone.free()
	camera.update_framing(0.0)
	assert_eq(camera.global_position, Vector2(10, 10), "the freed target does not pull the middle")
	assert_eq(camera.targets.size(), 1)


func test_a_target_outside_the_tree_is_skipped():
	var camera := _camera()
	var loose := Node2D.new()
	camera.add_target(_target(Vector2(4, 4)))
	camera.add_target(loose)
	assert_eq(camera.target_positions().size(), 1)
	loose.free()


func test_no_targets_leave_the_camera_alone():
	var camera := _camera()
	camera.global_position = Vector2(7, 7)
	camera.update_framing(1.0)
	camera.snap_to_targets()
	assert_eq(camera.global_position, Vector2(7, 7))


func test_add_target_ignores_null_and_duplicates():
	var camera := _camera()
	var node := _target(Vector2.ZERO)
	camera.add_target(null)
	camera.add_target(node)
	camera.add_target(node)
	assert_eq(camera.targets.size(), 1)
	camera.remove_target(node)
	assert_eq(camera.targets.size(), 0)


func test_pixel_snap_rounds_the_position():
	var camera := _camera()
	camera.pixel_snap = true
	camera.add_target(_target(Vector2(0.4, 0.6)))
	camera.update_framing(0.0)
	assert_eq(camera.global_position, Vector2(0, 1))


func test_set_world_rect_sets_the_limits_with_a_margin():
	var camera := _camera()
	camera.set_world_rect(Rect2(0, 0, 1000, 600), 50.0)
	assert_eq(camera.limit_left, -50)
	assert_eq(camera.limit_top, -50)
	assert_eq(camera.limit_right, 1050)
	assert_eq(camera.limit_bottom, 650)


func test_spreads_left_at_zero_come_from_the_viewport():
	var camera: LFGroupCamera2D = add_child_autofree(LFGroupCamera2D.new())
	var viewport := camera.get_viewport_rect().size
	var wanted := LFGroupCamera2D.default_spreads(viewport, camera.min_zoom)
	camera.add_target(_target(Vector2.ZERO))
	camera.add_target(_target(Vector2(wanted.y * 2.0, 0)))
	camera.snap_to_targets()
	assert_eq(camera.zoom, Vector2(camera.min_zoom, camera.min_zoom))
