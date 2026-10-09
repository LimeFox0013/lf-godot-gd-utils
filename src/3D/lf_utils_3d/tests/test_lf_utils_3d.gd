extends GutTest

## The documented default `flatten` of a flat ring.
const EXPECTED_DEFAULT_FLATTEN := 0.1


func test_no_camera_projects_to_nothing():
	assert_null(LFUtils3D.world_to_canvas_position(null, Vector3(1, 2, 3)))


func test_a_point_behind_the_camera_projects_to_nothing():
	var camera = add_child_autofree(Camera3D.new())
	assert_null(LFUtils3D.world_to_canvas_position(camera, Vector3(0, 0, 10)), 'behind, not mirrored onto the screen')
	assert_not_null(LFUtils3D.world_to_canvas_position(camera, Vector3(0, 0, -10)))


func test_projects_an_on_axis_world_position_near_the_viewport_center():
	var camera = add_child_autofree(Camera3D.new())
	var result = LFUtils3D.world_to_canvas_position(camera, Vector3(0, 0, -10))

	var vp = camera.get_viewport().get_visible_rect().size
	assert_almost_eq(result.x, vp.x / 2.0, 5.0)
	assert_almost_eq(result.y, vp.y / 2.0, 5.0)


func test_random_point_in_circle_stays_within_radius_and_keeps_center_y():
	var center := Vector3(10.0, 3.0, -20.0)
	for i in 200:
		var point = LFUtils3D.random_point_in_circle_xz(center, 5.0)
		assert_true(Vector2(point.x - center.x, point.z - center.z).length() <= 5.0 + 0.0001)
		assert_eq(point.y, center.y)


func test_random_point_in_circle_of_zero_radius_returns_the_center():
	assert_eq(LFUtils3D.random_point_in_circle_xz(Vector3(1, 2, 3), 0.0), Vector3(1, 2, 3))


func test_a_camera_outside_the_tree_projects_to_nothing_without_an_engine_error():
	var camera := Camera3D.new()
	assert_null(LFUtils3D.world_to_canvas_position(camera, Vector3(0, 0, -10)))
	assert_engine_error_count(0)
	camera.free()


func _ground_camera() -> Camera3D:
	var camera: Camera3D = add_child_autofree(Camera3D.new())
	camera.position = Vector3(0, 10, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	return camera


func _center(camera: Camera3D) -> Vector2:
	return camera.get_viewport().get_visible_rect().size / 2.0


func test_raycast_from_screen_hits_the_collider_under_the_point():
	var camera := _ground_camera()
	var body: StaticBody3D = add_child_autofree(StaticBody3D.new())
	body.collision_layer = 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 4)
	shape.shape = box
	body.add_child(shape)
	await get_tree().physics_frame

	var hit := LFUtils3D.raycast_from_screen(camera, _center(camera), 4)

	assert_eq(hit.get('collider'), body)
	assert_almost_eq((hit['position'] as Vector3).y, 1.0, 0.01, 'the box top')
	assert_eq(LFUtils3D.raycast_from_screen(camera, _center(camera), 2), {}, 'another layer misses')
	assert_eq(LFUtils3D.raycast_from_screen(camera, _center(camera), 4, 5.0), {}, 'too short to reach')


func test_raycast_from_screen_without_a_camera_in_the_tree_is_empty():
	var camera := Camera3D.new()
	assert_eq(LFUtils3D.raycast_from_screen(camera, Vector2.ZERO, 1), {})
	camera.free()


func test_screen_to_plane_finds_the_ground_point_under_the_screen_point():
	var camera := _ground_camera()
	var point = LFUtils3D.screen_to_plane(camera, _center(camera), Plane(Vector3.UP, 2.0))
	assert_almost_eq(point, Vector3(0, 2, 0), Vector3.ONE * 0.01)


func test_screen_to_plane_is_null_when_the_ray_misses():
	var camera := _ground_camera()
	assert_null(LFUtils3D.screen_to_plane(camera, _center(camera), Plane(Vector3.UP, 20.0)), 'plane behind the ray')


func test_screen_distance_to_segment_measures_pixels_to_the_projected_segment():
	var camera := _ground_camera()
	var center := _center(camera)
	var a := Vector3(0, 0, 0)
	var b := Vector3(0, 0, -1)
	assert_almost_eq(LFUtils3D.screen_distance_to_segment(camera, center, a, b), 0.0, 0.01)
	var beside := center + Vector2(30, 0)
	var segment_x: float = camera.unproject_position(a).x
	assert_almost_eq(LFUtils3D.screen_distance_to_segment(camera, beside, a, b), beside.x - segment_x, 0.5)


func test_screen_distance_to_segment_is_inf_when_an_end_is_behind_the_camera():
	var camera := _ground_camera()
	assert_eq(LFUtils3D.screen_distance_to_segment(camera, _center(camera), Vector3.ZERO, Vector3(0, 20, 0)), INF)


func test_screen_direction_points_toward_the_targets_side():
	var camera: Camera3D = add_child_autofree(Camera3D.new())
	assert_almost_eq(LFUtils3D.screen_direction(camera, Vector3(5, 0, -10)), Vector2.RIGHT, Vector2.ONE * 0.5)
	assert_almost_eq(LFUtils3D.screen_direction(camera, Vector3(0, 5, 10)), Vector2.UP, Vector2.ONE * 0.001, 'above and behind still reads as up')
	assert_eq(LFUtils3D.screen_direction(camera, Vector3(0, 0, 10)), Vector2.DOWN, 'straight behind')
	assert_eq(LFUtils3D.screen_direction(camera, Vector3(0, 0, -10)), Vector2.DOWN, 'straight ahead, on the view axis')


func test_translucent_material_is_unlit_alpha_and_two_sided_by_default():
	var material := LFUtils3D.translucent_material(Color(1, 0, 0, 0.5))
	assert_eq(material.albedo_color, Color(1, 0, 0, 0.5))
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(material.cull_mode, BaseMaterial3D.CULL_DISABLED)
	assert_eq(LFUtils3D.translucent_material(Color.WHITE, BaseMaterial3D.CULL_BACK).cull_mode, BaseMaterial3D.CULL_BACK)


func test_flat_ring_is_a_squashed_torus_with_the_material():
	var material := LFUtils3D.translucent_material(Color.RED)
	var ring: MeshInstance3D = autofree(LFUtils3D.flat_ring(1.5, 2.0, material))
	var torus := ring.mesh as TorusMesh
	assert_eq(torus.inner_radius, 1.5)
	assert_eq(torus.outer_radius, 2.0)
	assert_almost_eq(ring.scale.y, EXPECTED_DEFAULT_FLATTEN, 0.0001)
	assert_eq(LFUtils3D.DEFAULT_RING_FLATTEN, EXPECTED_DEFAULT_FLATTEN)
	assert_eq(ring.material_override, material)
	var flatter: MeshInstance3D = autofree(LFUtils3D.flat_ring(1.0, 2.0, material, 0.02))
	assert_almost_eq(flatter.scale.y, 0.02, 0.0001)


func test_screen_direction_without_a_camera_in_the_tree_is_down_without_an_engine_error():
	var camera := Camera3D.new()
	assert_eq(LFUtils3D.screen_direction(camera, Vector3(5, 0, -10)), Vector2.DOWN)
	assert_eq(LFUtils3D.screen_direction(null, Vector3(5, 0, -10)), Vector2.DOWN)
	assert_engine_error_count(0)
	camera.free()


func test_screen_to_plane_and_segment_distance_without_a_camera_in_the_tree():
	var camera := Camera3D.new()
	assert_null(LFUtils3D.screen_to_plane(camera, Vector2.ZERO, Plane(Vector3.UP, 0.0)))
	assert_null(LFUtils3D.screen_to_plane(null, Vector2.ZERO, Plane(Vector3.UP, 0.0)))
	assert_eq(LFUtils3D.screen_distance_to_segment(camera, Vector2.ZERO, Vector3.ZERO, Vector3.UP), INF)
	assert_eq(LFUtils3D.screen_distance_to_segment(null, Vector2.ZERO, Vector3.ZERO, Vector3.UP), INF)
	assert_engine_error_count(0)
	camera.free()


func test_screen_distance_to_segment_is_inf_when_the_first_end_is_behind_the_camera():
	var camera := _ground_camera()
	assert_eq(LFUtils3D.screen_distance_to_segment(camera, _center(camera), Vector3(0, 20, 0), Vector3.ZERO), INF)


func test_screen_direction_at_the_cameras_own_position_is_down():
	var camera: Camera3D = add_child_autofree(Camera3D.new())
	camera.position = Vector3(3, 4, 5)
	assert_eq(LFUtils3D.screen_direction(camera, Vector3(3, 4, 5)), Vector2.DOWN)


func test_screen_direction_follows_a_turned_camera():
	var camera: Camera3D = add_child_autofree(Camera3D.new())
	camera.rotation.y = PI / 2.0 # looks down -X; its right is -Z
	assert_almost_eq(LFUtils3D.screen_direction(camera, Vector3(-10, 0, -5)), Vector2.RIGHT, Vector2.ONE * 0.5)
	assert_almost_eq(LFUtils3D.screen_direction(camera, Vector3(-10, 0, 5)), Vector2.LEFT, Vector2.ONE * 0.5)


func test_a_moved_camera_projects_a_point_off_centre_to_its_side():
	var camera: Camera3D = add_child_autofree(Camera3D.new())
	camera.position = Vector3(-5, 0, 0)
	var result: Vector2 = LFUtils3D.world_to_canvas_position(camera, Vector3(0, 0, -10))
	assert_gt(result.x, _center(camera).x, "a point right of the camera shows right of centre")


## A script keeps its camera in a variable; the scene changes and frees it. Every camera
## function then answers "no camera" instead of failing on the freed object.
func test_the_camera_functions_answer_a_freed_camera_without_errors():
	var camera := _ground_camera()
	assert_not_null(LFUtils3D.world_to_canvas_position(camera, Vector3.ZERO), 'live, it projects')
	camera.free()

	assert_null(LFUtils3D.world_to_canvas_position(camera, Vector3.ZERO))
	assert_eq(LFUtils3D.raycast_from_screen(camera, Vector2.ZERO, 1), {})
	assert_null(LFUtils3D.screen_to_plane(camera, Vector2.ZERO, Plane(Vector3.UP, 0.0)))
	assert_eq(LFUtils3D.screen_distance_to_segment(camera, Vector2.ZERO, Vector3.ZERO, Vector3.UP), INF)
	assert_eq(LFUtils3D.screen_direction(camera, Vector3(5, 0, -10)), Vector2.DOWN)
	assert_engine_error_count(0)


## A live object that is not a camera is a mistake in the caller (unlike a freed camera,
## which these functions answer silently): it counts as no camera and is reported.
func test_anything_but_a_camera_3d_counts_as_no_camera_and_is_reported():
	var node: Node3D = add_child_autofree(Node3D.new())

	assert_null(LFUtils3D.world_to_canvas_position(node, Vector3.ZERO))
	assert_eq(LFUtils3D.raycast_from_screen(node, Vector2.ZERO, 1), {})
	assert_null(LFUtils3D.screen_to_plane(node, Vector2.ZERO, Plane(Vector3.UP, 0.0)))
	assert_eq(LFUtils3D.screen_distance_to_segment(node, Vector2.ZERO, Vector3.ZERO, Vector3.UP), INF)
	assert_eq(LFUtils3D.screen_direction(node, Vector3(5, 0, -10)), Vector2.DOWN)
	assert_false(LFUtils3D.camera_ready(42))
	assert_push_error_count(6, 'one report per call: five for the Node3D, one for the number')
	assert_engine_error_count(0)
