extends GutTest

var rig: Node3D
var camera: Camera3D
var orbit: LFOrbitCamera


class TunedOrbit extends LFOrbitCamera:
	func _init(pivot: Node3D, view_camera: Camera3D) -> void:
		super(pivot, view_camera)
		min_distance = 2.0
		max_distance = 300.0


func before_each():
	rig = add_child_autofree(Node3D.new())
	camera = Camera3D.new()
	camera.position = Vector3(0, 30, -26)
	rig.add_child(camera)
	orbit = LFOrbitCamera.new(rig, camera)


func test_get_camera_returns_the_wired_camera():
	assert_eq(orbit.get_camera(), camera)
	assert_eq(orbit.get_mount(), camera, "without a mount the camera carries the offset")


func test_distance_starts_at_the_cameras_offset():
	assert_almost_eq(orbit.distance(), Vector3(0, 30, -26).length(), 0.0001)


func test_panning_moves_the_rig_not_the_camera():
	var rig_before := rig.position
	var camera_before := camera.position
	orbit.pan(Vector2(100, 0))
	assert_ne(rig.position, rig_before)
	assert_eq(camera.position, camera_before)


func test_panning_right_and_left_move_opposite_ways():
	orbit.pan(Vector2(100, 0))
	var after_right := rig.position
	rig.position = Vector3.ZERO
	orbit.pan(Vector2(-100, 0))
	assert_almost_eq(after_right.x, -rig.position.x, 0.001)


func test_panning_follows_the_rigs_yaw_and_scales_with_distance():
	rig.rotation.y = PI / 2.0
	orbit.pan(Vector2(100, 0))
	assert_almost_eq(rig.position.x, 0.0, 0.0001, "local X now points along world -Z")
	var near_step := rig.position.length()
	var near_distance := orbit.distance()
	rig.position = Vector3.ZERO
	orbit.zoom(-3.0)
	orbit.pan(Vector2(100, 0))
	assert_almost_eq(rig.position.length() / near_step, orbit.distance() / near_distance, 0.0001, "the step grows in proportion to the distance")
	assert_gt(rig.position.length(), near_step, "farther out, the same drag covers more ground")


func test_zooming_in_brings_the_camera_closer_and_out_farther():
	var start := camera.position.length()
	orbit.zoom(1.0)
	var after_in := camera.position.length()
	assert_lt(after_in, start)
	assert_almost_eq(after_in, start * (1.0 - orbit.zoom_step_fraction), 0.001)
	orbit.zoom(-2.0)
	assert_almost_eq(camera.position.length(), after_in / pow(1.0 - orbit.zoom_step_fraction, 2.0), 0.001, "each step out divides by the same factor")
	orbit.zoom(1.0)
	assert_almost_eq(camera.position.length(), start, 0.001, "in, out twice, in again: back to the start")


func test_zoom_keeps_the_offset_direction():
	var direction := camera.position.normalized()
	orbit.zoom(2.0)
	assert_almost_eq(camera.position.normalized(), direction, Vector3.ONE * 0.0001)


func test_zoom_is_clamped_to_the_min_and_max_distance():
	for i in 100:
		orbit.zoom(1.0)
	assert_almost_eq(camera.position.length(), orbit.min_distance, 0.01)
	for i in 100:
		orbit.zoom(-1.0)
	assert_almost_eq(camera.position.length(), orbit.max_distance, 0.01)


func test_a_subclass_sets_its_own_tunables():
	var tuned := TunedOrbit.new(rig, camera)
	for i in 100:
		tuned.zoom(-1.0)
	assert_almost_eq(tuned.distance(), 300.0, 0.01)


func test_zoom_never_moves_the_rig():
	var before := rig.position
	orbit.zoom(1.0)
	assert_eq(rig.position, before)


func test_rotating_turns_the_rigs_yaw_and_never_moves_it():
	var before := rig.position
	var yaw := rig.rotation.y
	orbit.rotate(Vector2(50, 0))
	assert_almost_eq(rig.rotation.y, yaw - 50 * orbit.rotate_radians_per_pixel, 0.0001)
	assert_eq(rig.position, before)


func test_rotating_opposite_ways_yaws_opposite_ways():
	orbit.rotate(Vector2(50, 0))
	var after_right := rig.rotation.y
	rig.rotation.y = 0.0
	orbit.rotate(Vector2(-50, 0))
	assert_almost_eq(after_right, -rig.rotation.y, 0.0001)


func test_frame_centres_the_rig_and_sets_a_clamped_distance():
	rig.position.y = 2.0
	orbit.frame(Vector3(7, 9, -3), 20.0)
	assert_eq(rig.position, Vector3(7, 2, -3), "the rig keeps its height")
	assert_almost_eq(orbit.distance(), 20.0, 0.0001)
	assert_almost_eq(camera.position.length(), 20.0, 0.0001)
	orbit.frame(Vector3.ZERO, 1000.0)
	assert_almost_eq(orbit.distance(), orbit.max_distance, 0.0001)


## With a mount, the rig moves the mount and leaves the camera under it alone, so a node
## between them (a shaker) can move the camera freely.
func test_with_a_mount_zoom_and_frame_move_the_mount_not_the_camera():
	var mounted: Node3D = add_child_autofree(Node3D.new())
	var mount := Node3D.new()
	mount.position = Vector3(0, 30, -26)
	mounted.add_child(mount)
	var inner := Camera3D.new()
	mount.add_child(inner)
	var mounted_orbit := LFOrbitCamera.new(mounted, inner, mount)

	mounted_orbit.zoom(1.0)
	mounted_orbit.frame(Vector3(4, 0, 4), 20.0)

	assert_almost_eq(mount.position.length(), 20.0, 0.001)
	assert_eq(inner.position, Vector3.ZERO)
	assert_eq(mounted_orbit.get_camera(), inner)
	assert_eq(mounted_orbit.get_mount(), mount)


func test_a_pan_step_is_pixels_times_units_per_pixel_times_distance():
	orbit.pan_units_per_pixel = 0.01
	orbit.pan(Vector2(10, 20))
	var step := 0.01 * orbit.distance()
	assert_almost_eq(rig.position, Vector3(10 * step, 0, 20 * step), Vector3.ONE * 0.0001)


func test_a_swapped_camera_leaves_the_offset_on_the_original_mount():
	var other := Camera3D.new()
	rig.add_child(other)
	orbit.camera = other
	orbit.zoom(1.0)
	assert_eq(orbit.get_camera(), other)
	assert_eq(orbit.get_mount(), camera, 'the mount set at construction')
	assert_almost_eq(camera.position.length(), orbit.distance(), 0.0001, 'zoom still moves it')
	assert_eq(other.position, Vector3.ZERO, 'the new camera is not moved')


func test_a_nan_zoom_or_frame_distance_keeps_the_current_distance():
	var before := orbit.distance()
	orbit.zoom(NAN)
	orbit.frame(Vector3(1, 0, 1), NAN)
	assert_almost_eq(orbit.distance(), before, 0.0001)
	assert_almost_eq(camera.position.length(), before, 0.0001)
	assert_eq(rig.position, Vector3(1, 0, 1), 'frame still moves the rig')


## `center` is a world point: a rig under a moved, turned parent still ends up over it.
func test_frame_takes_a_world_point_under_a_transformed_parent():
	var parent: Node3D = add_child_autofree(Node3D.new())
	parent.position = Vector3(100, 5, 50)
	parent.rotation.y = PI / 2.0
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.global_position = Vector3(0, 8, 0)
	var view := Camera3D.new()
	view.position = Vector3(0, 10, -10)
	pivot.add_child(view)
	var parented := LFOrbitCamera.new(pivot, view)

	parented.frame(Vector3(7, 0, -3), 20.0)

	assert_almost_eq(pivot.global_position.x, 7.0, 0.0001)
	assert_almost_eq(pivot.global_position.z, -3.0, 0.0001)
	assert_almost_eq(pivot.global_position.y, 8.0, 0.0001, 'the rig keeps its world height')


func test_a_new_orbit_has_the_documented_tunables():
	assert_eq(orbit.min_distance, 5.0)
	assert_eq(orbit.max_distance, 100.0)
	assert_eq(orbit.pan_units_per_pixel, 0.0018)
	assert_eq(orbit.zoom_step_fraction, 0.12)
	assert_eq(orbit.rotate_radians_per_pixel, 0.006)
	assert_eq(orbit.rig, rig)


func test_an_infinite_zoom_lands_on_the_clamps():
	orbit.zoom(INF)
	assert_almost_eq(orbit.distance(), orbit.min_distance, 0.0001)
	orbit.zoom(-INF)
	assert_almost_eq(orbit.distance(), orbit.max_distance, 0.0001)
	assert_almost_eq(camera.position.length(), orbit.max_distance, 0.001)


func test_changed_limits_apply_at_the_next_zoom():
	orbit.max_distance = 10.0
	assert_almost_eq(orbit.distance(), Vector3(0, 30, -26).length(), 0.0001, 'not yet')
	orbit.zoom(0.0)
	assert_almost_eq(orbit.distance(), 10.0, 0.0001)


func test_rotating_ignores_the_vertical_drag():
	orbit.rotate(Vector2(0, 80))
	assert_eq(rig.rotation, Vector3.ZERO)


func test_frame_on_a_rig_outside_the_tree_sets_its_local_position():
	var loose := Node3D.new()
	loose.position = Vector3(0, 3, 0)
	var view := Camera3D.new()
	view.position = Vector3(0, 10, -10)
	loose.add_child(view)
	var loose_orbit := LFOrbitCamera.new(loose, view)

	loose_orbit.frame(Vector3(6, 50, 2), 8.0)

	assert_eq(loose.position, Vector3(6, 3, 2))
	assert_almost_eq(view.position.length(), 8.0, 0.0001)
	loose.free()


func test_a_camera_at_the_rig_has_no_offset_to_zoom():
	var flat: Node3D = add_child_autofree(Node3D.new())
	var view := Camera3D.new()
	flat.add_child(view)
	var flat_orbit := LFOrbitCamera.new(flat, view)

	flat_orbit.zoom(-1.0)

	assert_eq(view.position, Vector3.ZERO, 'no direction to move along')
	assert_almost_eq(flat_orbit.distance(), flat_orbit.min_distance, 0.0001, 'the recorded distance is still clamped')
