extends GutTest


func test_camera_ready_needs_a_live_camera_in_the_tree():
	assert_false(LFUtils2D.camera_ready(null))
	var outside := Camera2D.new()
	assert_false(LFUtils2D.camera_ready(outside))
	outside.free()
	var inside: Camera2D = add_child_autofree(Camera2D.new())
	assert_true(LFUtils2D.camera_ready(inside))


func test_settled_view_center_sees_a_move_made_this_frame():
	var camera: Camera2D = add_child_autofree(Camera2D.new())
	camera.make_current()
	await get_tree().process_frame
	camera.global_position = Vector2(300, -120)
	assert_eq(LFUtils2D.settled_view_center(camera), Vector2(300, -120))


func test_settled_view_center_leaves_a_smoothing_camera_where_it_stepped():
	var camera: Camera2D = add_child_autofree(Camera2D.new())
	camera.make_current()
	camera.position_smoothing_enabled = true
	await get_tree().process_frame
	var before := camera.get_screen_center_position()
	camera.global_position = Vector2(500, 0)
	assert_eq(LFUtils2D.settled_view_center(camera), before, 'no extra smoothing step')


func test_settle_publishes_a_move_made_this_frame():
	var camera: Camera2D = add_child_autofree(Camera2D.new())
	camera.make_current()
	await get_tree().process_frame
	camera.global_position = Vector2(-40, 75)
	LFUtils2D.settle(camera)
	assert_eq(camera.get_screen_center_position(), Vector2(-40, 75))


func test_settle_without_a_camera_in_the_tree_does_nothing():
	LFUtils2D.settle(null)
	var outside := Camera2D.new()
	LFUtils2D.settle(outside)
	outside.free()
	assert_engine_error_count(0)


func test_settled_view_center_without_a_camera_is_zero():
	assert_eq(LFUtils2D.settled_view_center(null), Vector2.ZERO)


func test_camera_world_rect_covers_the_viewport_around_the_camera_and_scales_with_zoom():
	var camera: Camera2D = add_child_autofree(Camera2D.new())
	camera.make_current()
	camera.global_position = Vector2(100, 50)
	camera.zoom = Vector2(2, 2)
	LFUtils2D.settle(camera)
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var rect := LFUtils2D.camera_world_rect(camera)
	assert_almost_eq(rect.get_center(), Vector2(100, 50), Vector2.ONE * 0.01)
	assert_almost_eq(rect.size, viewport_size / 2.0, Vector2.ONE * 0.01)


func test_camera_world_rect_without_a_camera_in_the_tree_is_empty():
	var camera := Camera2D.new()
	assert_eq(LFUtils2D.camera_world_rect(camera), Rect2())
	camera.free()


func test_apply_process_callback_switches_between_idle_and_physics():
	var node: Node = add_child_autofree(Node.new())
	LFUtils2D.apply_process_callback(node, Camera2D.CAMERA2D_PROCESS_PHYSICS)
	assert_false(node.is_processing())
	assert_true(node.is_physics_processing())
	LFUtils2D.apply_process_callback(node, Camera2D.CAMERA2D_PROCESS_IDLE)
	assert_true(node.is_processing())
	assert_false(node.is_physics_processing())


func test_rect_edge_point_meets_the_border_along_the_direction():
	var rect := Rect2(0, 0, 200, 100)
	assert_eq(LFUtils2D.rect_edge_point(rect, Vector2.RIGHT), Vector2(200, 50))
	assert_eq(LFUtils2D.rect_edge_point(rect, Vector2.UP), Vector2(100, 0))
	assert_almost_eq(LFUtils2D.rect_edge_point(rect, Vector2(1, 1).normalized()), Vector2(150, 100), Vector2.ONE * 0.001, 'the nearer border wins')
	assert_eq(LFUtils2D.rect_edge_point(rect, Vector2.ZERO), Vector2(100, 50))


func test_rect_edge_point_depends_only_on_the_directions_angle_however_short():
	var rect := Rect2(0, 0, 200, 100)
	assert_almost_eq(LFUtils2D.rect_edge_point(rect, Vector2(1e-6, 1e-6)), Vector2(150, 100), Vector2.ONE * 0.001)
	assert_almost_eq(LFUtils2D.rect_edge_point(rect, Vector2(500, 0)), Vector2(200, 50), Vector2.ONE * 0.001)


func test_rect_edge_point_keeps_the_angle_of_a_direction_too_short_to_normalize():
	var rect := Rect2(0, 0, 200, 100)
	assert_almost_eq(LFUtils2D.rect_edge_point(rect, Vector2(1e-30, 0)), Vector2(200, 50), Vector2.ONE * 0.001)
	assert_almost_eq(LFUtils2D.rect_edge_point(rect, Vector2(1e-30, 1e-30)), Vector2(150, 100), Vector2.ONE * 0.001)


func test_rect_edge_point_returns_the_centre_for_a_non_finite_direction():
	var rect := Rect2(0, 0, 200, 100)
	assert_eq(LFUtils2D.rect_edge_point(rect, Vector2(NAN, 1)), Vector2(100, 50))
	assert_eq(LFUtils2D.rect_edge_point(rect, Vector2(INF, 0)), Vector2(100, 50))


func test_rect_edge_point_reads_a_negative_size_rect_as_the_same_area():
	var flipped := Rect2(200, 100, -200, -100)
	assert_eq(LFUtils2D.rect_edge_point(flipped, Vector2.RIGHT), Vector2(200, 50))


func test_apply_process_callback_ignores_a_missing_node():
	LFUtils2D.apply_process_callback(null, Camera2D.CAMERA2D_PROCESS_IDLE)
	assert_engine_error_count(0)


func test_the_camera_functions_answer_a_freed_camera_without_errors():
	var camera: Camera2D = Camera2D.new()
	add_child(camera)
	camera.make_current()
	camera.free()
	assert_false(LFUtils2D.camera_ready(camera))
	LFUtils2D.settle(camera)
	assert_eq(LFUtils2D.settled_view_center(camera), Vector2.ZERO)
	assert_eq(LFUtils2D.camera_world_rect(camera), Rect2())
	assert_engine_error_count(0)


func test_apply_process_callback_ignores_a_freed_node():
	var node: Node = Node.new()
	node.free()
	LFUtils2D.apply_process_callback(node, Camera2D.CAMERA2D_PROCESS_IDLE)
	assert_engine_error_count(0)


## A live object that is not a camera is a mistake in the caller (unlike a freed camera,
## which these functions answer silently): it counts as no camera and is reported.
func test_anything_but_a_camera_counts_as_no_camera_and_is_reported():
	var node: Node2D = add_child_autofree(Node2D.new())
	assert_false(LFUtils2D.camera_ready(node))
	assert_eq(LFUtils2D.settled_view_center(node), Vector2.ZERO)
	assert_eq(LFUtils2D.camera_world_rect(node), Rect2())
	LFUtils2D.settle(node)
	assert_false(LFUtils2D.camera_ready(Vector2.ONE))
	LFUtils2D.apply_process_callback(RefCounted.new(), Camera2D.CAMERA2D_PROCESS_IDLE)
	assert_push_error_count(6, 'one report per call: four for the Node2D, one for the Vector2, one for the RefCounted')
	assert_engine_error_count(0)


func test_settle_leaves_a_rotation_smoothing_camera_alone():
	var camera: Camera2D = add_child_autofree(Camera2D.new())
	camera.make_current()
	camera.rotation_smoothing_enabled = true
	await get_tree().process_frame
	var before := camera.get_screen_center_position()
	camera.global_position = Vector2(-300, 0)
	LFUtils2D.settle(camera)
	assert_eq(camera.get_screen_center_position(), before, 'no extra smoothing step')


func test_camera_world_rect_of_a_rotated_camera_is_the_bounding_box_of_the_view():
	var camera: Camera2D = add_child_autofree(Camera2D.new())
	camera.ignore_rotation = false
	camera.make_current()
	camera.rotation = PI / 2.0
	LFUtils2D.settle(camera)
	await get_tree().process_frame
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var rect := LFUtils2D.camera_world_rect(camera)
	assert_almost_eq(rect.size, Vector2(viewport_size.y, viewport_size.x), Vector2.ONE * 0.01, 'a quarter turn swaps width and height')
	assert_almost_eq(rect.get_center(), Vector2.ZERO, Vector2.ONE * 0.01)


func test_camera_world_rect_of_a_camera_that_is_not_current_is_what_the_viewport_shows():
	var current: Camera2D = add_child_autofree(Camera2D.new())
	current.make_current()
	current.global_position = Vector2(100, 0)
	LFUtils2D.settle(current)
	var other: Camera2D = add_child_autofree(Camera2D.new())
	other.global_position = Vector2(-900, 0)
	assert_almost_eq(LFUtils2D.camera_world_rect(other).get_center(), Vector2(100, 0), Vector2.ONE * 0.01)


func test_rect_edge_point_on_a_zero_size_rect_is_its_position():
	assert_eq(LFUtils2D.rect_edge_point(Rect2(5, 7, 0, 0), Vector2.RIGHT), Vector2(5, 7))
