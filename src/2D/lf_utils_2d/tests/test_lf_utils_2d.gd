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


func test_random_point_in_circle_stays_inside_and_is_seedable():
	var rng := LFRandom.new(7)
	for i in 200:
		var point := LFUtils2D.random_point_in_circle(Vector2(10, -4), 5.0, rng)
		assert_lte(point.distance_to(Vector2(10, -4)), 5.0 + 0.0001)
	var a := LFUtils2D.random_point_in_circle(Vector2.ZERO, 3.0, LFRandom.new(1))
	var b := LFUtils2D.random_point_in_circle(Vector2.ZERO, 3.0, LFRandom.new(1))
	assert_eq(a, b, "same seed, same point")


func test_random_point_in_circle_is_uniform_by_area():
	var rng := LFRandom.new(3)
	var inner := 0
	for i in 2000:
		if LFUtils2D.random_point_in_circle(Vector2.ZERO, 2.0, rng).length() < 1.0:
			inner += 1
	# The inner half-radius disc holds a quarter of the area.
	assert_almost_eq(inner / 2000.0, 0.25, 0.04)


func test_random_point_in_circle_with_zero_radius_is_the_centre_and_works_without_rng():
	assert_eq(LFUtils2D.random_point_in_circle(Vector2(1, 2), 0.0), Vector2(1, 2))
	assert_lte(LFUtils2D.random_point_in_circle(Vector2.ZERO, 1.0).length(), 1.0001)


func test_random_point_outside_rect_lies_on_the_scaled_border():
	var rect := Rect2(0, 0, 200, 100)
	var rng := LFRandom.new(11)
	var sides_hit := {}
	for i in 300:
		var point := LFUtils2D.random_point_outside_rect(rect, Vector2(2.0, 2.0), rng)
		# Scaled by 2 about (100, 50): x in -100..300, y in -50..150.
		assert_true(Rect2(-100, -50, 400, 200).grow(0.001).has_point(point))
		assert_false(rect.has_point(point), "outside the rect")
		if is_equal_approx(point.y, -50.0):
			sides_hit["top"] = true
		if is_equal_approx(point.x, 300.0):
			sides_hit["right"] = true
		if is_equal_approx(point.y, 150.0):
			sides_hit["bottom"] = true
		if is_equal_approx(point.x, -100.0):
			sides_hit["left"] = true
	assert_eq(sides_hit.size(), 4, "every side is used")


func test_random_point_outside_rect_uses_the_scale_range_and_reads_a_negative_rect():
	var rng := LFRandom.new(5)
	for i in 100:
		var point := LFUtils2D.random_point_outside_rect(Rect2(100, 50, -200, -100), Vector2(1.1, 1.4), rng)
		var d := (point - Vector2.ZERO).abs()
		var edge_fraction := maxf(d.x / 100.0, d.y / 50.0)
		assert_between(edge_fraction, 1.1 - 0.0001, 1.4 + 0.0001, "on a border scaled by 1.1 to 1.4")


func test_random_point_outside_rect_default_range_and_global_rng():
	var point := LFUtils2D.random_point_outside_rect(Rect2(0, 0, 100, 100))
	assert_false(Rect2(0, 0, 100, 100).has_point(point))
	assert_eq(LFUtils2D.DEFAULT_OUTSIDE_SCALE_RANGE, Vector2(1.1, 1.4))


func test_max_pairwise_distance_of_few_points_is_zero():
	assert_eq(LFUtils2D.max_pairwise_distance(PackedVector2Array()), 0.0)
	assert_eq(LFUtils2D.max_pairwise_distance(PackedVector2Array([Vector2(5, 5)])), 0.0)
	assert_eq(LFUtils2D.max_pairwise_distance(PackedVector2Array([Vector2(5, 5), Vector2(5, 5)])), 0.0)


func test_max_pairwise_distance_of_simple_shapes():
	assert_almost_eq(LFUtils2D.max_pairwise_distance(PackedVector2Array([Vector2(0, 0), Vector2(3, 4)])), 5.0, 0.0001)
	var square := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0.5, 0.5)])
	assert_almost_eq(LFUtils2D.max_pairwise_distance(square), sqrt(2.0), 0.0001)
	var line := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(7, 0), Vector2(4, 0)])
	assert_almost_eq(LFUtils2D.max_pairwise_distance(line), 7.0, 0.0001, "collinear points")


func test_max_pairwise_distance_matches_brute_force_on_random_clouds():
	var rng := LFRandom.new(21)
	for round in 20:
		var points := PackedVector2Array()
		for i in rng.randi_range(2, 40):
			points.append(Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100)))
		var best := 0.0
		for a in points:
			for b in points:
				best = maxf(best, a.distance_to(b))
		assert_almost_eq(LFUtils2D.max_pairwise_distance(points), best, 0.0001)


func test_max_pairwise_distance_ignores_non_finite_points():
	var points := PackedVector2Array([Vector2(0, 0), Vector2(NAN, 1), Vector2(INF, 0), Vector2(0, 2)])
	assert_almost_eq(LFUtils2D.max_pairwise_distance(points), 2.0, 0.0001)


func test_fit_sprite_to_size_scales_the_texture_to_the_size():
	var sprite: Sprite2D = add_child_autofree(Sprite2D.new())
	sprite.texture = ImageTexture.create_from_image(Image.create(20, 10, false, Image.FORMAT_RGBA8))
	assert_true(LFUtils2D.fit_sprite_to_size(sprite, Vector2(100, 100)))
	assert_eq(sprite.scale, Vector2(5, 10))
	assert_eq(sprite.get_rect().size * sprite.scale, Vector2(100, 100))


func test_fit_sprite_to_size_keeps_a_flip_and_uses_the_visible_frame():
	var sprite: Sprite2D = add_child_autofree(Sprite2D.new())
	sprite.texture = ImageTexture.create_from_image(Image.create(40, 10, false, Image.FORMAT_RGBA8))
	sprite.hframes = 2
	sprite.scale = Vector2(-1, 1)
	assert_true(LFUtils2D.fit_sprite_to_size(sprite, Vector2(40, 10)))
	assert_eq(sprite.scale, Vector2(-2, 1), "a 20 x 10 frame shown at 40 x 10, still flipped")


func test_fit_sprite_to_size_without_a_texture_changes_nothing_and_reports():
	var sprite: Sprite2D = add_child_autofree(Sprite2D.new())
	sprite.scale = Vector2(3, 3)
	assert_false(LFUtils2D.fit_sprite_to_size(sprite, Vector2(10, 10)))
	assert_eq(sprite.scale, Vector2(3, 3))
	assert_false(LFUtils2D.fit_sprite_to_size(null, Vector2(10, 10)))
	assert_push_error_count(2)


func test_shape_size_of_a_rectangle_circle_and_capsule():
	var node: CollisionShape2D = add_child_autofree(CollisionShape2D.new())
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(30, 12)
	node.shape = rectangle
	assert_eq(LFUtils2D.shape_size(node), Vector2(30, 12))
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	node.shape = circle
	assert_eq(LFUtils2D.shape_size(node), Vector2(16, 16), "a circle is its diameter, not its radius")
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5.0
	capsule.height = 24.0
	node.shape = capsule
	assert_eq(LFUtils2D.shape_size(node), Vector2(10, 24))


func test_shape_size_without_a_shape_is_zero_and_reported():
	var node: CollisionShape2D = add_child_autofree(CollisionShape2D.new())
	assert_eq(LFUtils2D.shape_size(node), Vector2.ZERO)
	assert_eq(LFUtils2D.shape_size(null), Vector2.ZERO)
	assert_push_error_count(2)
