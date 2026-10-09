extends GutTest

## Driven by calling the per-frame evaluation directly rather than waiting on real
## frames, for deterministic, fast tests. The camera sits at the origin facing -Z.

const EPS := Vector2(0.01, 0.01)

var camera: Camera3D
var target: Node3D
var tracker: LFTracker


func before_each():
	camera = add_child_autofree(Camera3D.new())
	target = add_child_autofree(Node3D.new())
	tracker = add_child_autofree(LFTracker.new())
	tracker.camera = camera
	tracker.target = target
	tracker.padding = 10.0


func _step(t: LFTracker = tracker) -> void:
	t.update_tracking()


func _viewport_size() -> Vector2:
	return tracker.get_viewport_rect().size


func _center() -> Vector2:
	return _viewport_size() * 0.5


func _pivot_on_screen(t: LFTracker = tracker) -> Vector2:
	return t.get_global_transform_with_canvas() * t.pivot_offset


func _assert_inside_padded_rect(point: Vector2, padding: float) -> void:
	var vp := _viewport_size()
	assert_between(point.x, padding - 0.01, vp.x - padding + 0.01)
	assert_between(point.y, padding - 0.01, vp.y - padding + 0.01)


func _assert_on_padded_border(point: Vector2, padding: float) -> void:
	var vp := _viewport_size()
	var on_vertical := absf(point.x - padding) < 0.01 or absf(point.x - (vp.x - padding)) < 0.01
	var on_horizontal := absf(point.y - padding) < 0.01 or absf(point.y - (vp.y - padding)) < 0.01
	assert_true(on_vertical or on_horizontal, "%s lies on the padded border" % point)
	_assert_inside_padded_rect(point, padding)


# --- placement and pointing ---


func test_offscreen_target_clamps_the_tracker_within_the_padded_rect():
	target.global_position = Vector3(1000, 1000, -10) # far to the side, but in front
	_step()

	_assert_on_padded_border(_pivot_on_screen(), tracker.padding)


func test_a_far_side_target_sits_where_the_ray_from_the_center_meets_the_edge():
	target.global_position = Vector3(1000, 300, -10) # in front, far right and a bit up
	_step()

	var expected_angle := Vector2(1000, -300).angle()
	var pivot := _pivot_on_screen()
	_assert_on_padded_border(pivot, tracker.padding)
	assert_almost_eq((pivot - _center()).angle(), expected_angle, 0.0001, "placed on the ray toward the target")
	assert_almost_eq(tracker.rotation, expected_angle, 0.0001, "points along the same ray")


func test_the_trackers_pivot_sits_on_the_edge_point_for_a_target_level_and_to_the_right():
	tracker.pivot_offset = Vector2(8, 8)
	target.global_position = Vector3(1000, 0, -10)
	_step()

	var expected := Vector2(_viewport_size().x - tracker.padding, _center().y)
	assert_almost_eq(_pivot_on_screen(), expected, EPS, "the pivot, not the top-left corner, is placed on the point")
	assert_almost_eq(tracker.rotation, 0.0, 0.0001)


func test_off_screen_tracker_points_left_for_a_target_on_the_left():
	target.global_position = Vector3(-1000, 0, -10)
	_step()

	assert_almost_eq(absf(tracker.rotation), PI, 0.0001, "a target straight to the left points along -X")
	assert_almost_eq(_pivot_on_screen(), Vector2(tracker.padding, _center().y), EPS)


func test_a_target_directly_behind_the_camera_sits_on_the_bottom_edge_pointing_down():
	target.global_position = Vector3(0, 0, 10)
	_step()

	assert_almost_eq(_pivot_on_screen(), Vector2(_center().x, _viewport_size().y - tracker.padding), EPS)
	assert_almost_eq(tracker.rotation, PI * 0.5, 0.0001)


func test_a_target_behind_and_to_the_right_sits_on_the_right_on_its_true_direction():
	target.global_position = Vector3(10, 3, 10) # behind, to the right and a bit up
	_step()

	var expected_angle := Vector2(10, -3).angle()
	var pivot := _pivot_on_screen()
	_assert_on_padded_border(pivot, tracker.padding)
	assert_almost_eq(pivot.x, _viewport_size().x - tracker.padding, 0.01, "the target's own side, not mirrored")
	assert_almost_eq((pivot - _center()).angle(), expected_angle, 0.0001)
	assert_almost_eq(tracker.rotation, expected_angle, 0.0001)


func test_a_target_on_the_camera_plane_points_to_its_side_without_engine_errors():
	target.global_position = Vector3(5, 0, 0)
	_step()

	assert_engine_error_count(0, "no projection of a point on the camera plane")
	assert_almost_eq(_pivot_on_screen(), Vector2(_viewport_size().x - tracker.padding, _center().y), EPS)
	assert_almost_eq(tracker.rotation, 0.0, 0.0001)
	assert_false(tracker.on_screen)


func test_a_target_at_the_camera_sits_on_the_bottom_edge_without_engine_errors():
	target.global_position = Vector3.ZERO
	_step()

	assert_engine_error_count(0)
	assert_almost_eq(_pivot_on_screen(), Vector2(_center().x, _viewport_size().y - tracker.padding), EPS)


func test_a_target_closer_than_the_near_plane_points_to_its_own_side():
	target.global_position = Vector3(5, 0, -0.01)
	_step()

	assert_almost_eq(_pivot_on_screen(), Vector2(_viewport_size().x - tracker.padding, _center().y), EPS)
	assert_almost_eq(tracker.rotation, 0.0, 0.0001)


func test_an_on_screen_target_puts_the_pivot_on_its_projection_without_rotation():
	tracker.rotation = 1.0
	target.global_position = Vector3(2, 2, -10)
	_step()

	assert_almost_eq(_pivot_on_screen(), camera.unproject_position(target.global_position), EPS)
	assert_almost_eq(tracker.rotation, 0.0, 0.0001, "on the target there is nothing to point at")


func test_panel_mode_never_rotates_the_panel():
	tracker.hide_if_off_screen = true
	target.global_position = Vector3(2, 2, -10) # on screen, up and to the right
	_step()

	assert_true(tracker.visible)
	assert_almost_eq(tracker.rotation, 0.0, 0.0001)

	target.global_position = Vector3(-1000, 300, -10) # off screen: hidden, not turned
	_step()
	assert_false(tracker.visible)
	assert_almost_eq(tracker.rotation, 0.0, 0.0001)

	target.global_position = Vector3(-2, -2, -10)
	_step()
	assert_true(tracker.visible)
	assert_almost_eq(tracker.rotation, 0.0, 0.0001)


func test_with_rotate_to_target_off_rotation_is_left_to_the_caller():
	tracker.rotate_to_target = false
	tracker.rotation = 0.3
	target.global_position = Vector3(1000, 300, -10)
	_step()

	assert_almost_eq(tracker.rotation, 0.3, 0.0001)
	_assert_on_padded_border(_pivot_on_screen(), tracker.padding)


func test_padding_larger_than_half_the_screen_is_clamped():
	tracker.padding = 100000.0
	target.global_position = Vector3(0, 0, -10) # dead ahead
	_step()

	assert_engine_error_count(0, "no negative rect")
	assert_true(tracker.on_screen, "the screen center still counts as on-screen")
	assert_almost_eq(_pivot_on_screen(), _center(), EPS)
	assert_push_warning('no on-screen area')


func test_padding_that_leaves_no_on_screen_area_is_reported_once_until_it_fits_again():
	# The default padding (32) in a viewport whose smaller side is 64, as in a headless run.
	tracker.padding = minf(_viewport_size().x, _viewport_size().y) * 0.5
	target.global_position = Vector3(0.5, 0.2, -10) # ahead, a little off the exact center
	for i in 3:
		_step()
	assert_false(tracker.on_screen, "the padded rect is a point: nothing off it is on screen")
	assert_push_warning_count(1, "reported once, not every frame")

	tracker.padding = 1.0
	_step()
	assert_true(tracker.on_screen)
	tracker.padding = 100000.0
	_step()
	_step()
	assert_push_warning_count(2, "reported again after the padding fitted in between")


func test_padding_that_leaves_an_on_screen_area_reports_nothing():
	tracker.padding = minf(_viewport_size().x, _viewport_size().y) * 0.5 - 1.0
	target.global_position = Vector3(0, 0, -10)
	_step()
	assert_true(tracker.on_screen)
	assert_push_warning_count(0)


# --- a hidden target ---


func test_a_hidden_target_is_still_tracked_on_and_off_screen():
	target.visible = false
	target.global_position = Vector3(0, 0, -10) # dead ahead
	_step()
	assert_true(tracker.on_screen, "the target's own visible is not consulted")
	assert_true(tracker.visible)
	assert_almost_eq(_pivot_on_screen(), _center(), EPS)

	target.global_position = Vector3(1000, 0, -10) # far to the right
	_step()
	assert_false(tracker.on_screen)
	assert_true(tracker.visible, "an arrow still points at a hidden target")
	_assert_on_padded_border(_pivot_on_screen(), tracker.padding)


func test_placement_follows_a_canvas_layer_parent():
	var layer = add_child_autofree(CanvasLayer.new())
	layer.offset = Vector2(100, 50)
	layer.scale = Vector2(2, 2)
	var nested = LFTracker.new()
	nested.camera = camera
	nested.target = target
	nested.padding = 10.0
	layer.add_child(nested)
	target.global_position = Vector3(1000, 0, -10)

	_step(nested)

	assert_almost_eq(_pivot_on_screen(nested), Vector2(_viewport_size().x - 10.0, _center().y), EPS)


func test_a_tracker_under_an_offset_parent_is_placed_in_viewport_coordinates():
	var parent = add_child_autofree(Control.new())
	parent.position = Vector2(100, 50)
	var nested = LFTracker.new()
	nested.camera = camera
	nested.target = target
	nested.padding = 10.0
	parent.add_child(nested)
	target.global_position = Vector3(1000, 0, -10)

	_step(nested)

	var expected := Vector2(_viewport_size().x - nested.padding, _center().y)
	assert_almost_eq(_pivot_on_screen(nested), expected, EPS, "a parent's offset must not shift the tracker off its screen point")


func test_under_a_rotated_parent_the_arrow_still_points_at_the_target_on_screen():
	var parent = add_child_autofree(Control.new())
	parent.rotation = 0.5
	var nested = LFTracker.new()
	nested.camera = camera
	nested.target = target
	parent.add_child(nested)
	target.global_position = Vector3(1000, 0, -10)

	_step(nested)

	assert_almost_eq(nested.get_global_transform_with_canvas().get_rotation(), 0.0, 0.0001, "points right, at the target")
	assert_almost_eq(_pivot_on_screen(nested), Vector2(_viewport_size().x - nested.padding, _center().y), EPS,
		"placed on the right edge despite the rotated parent")


# --- on/off-screen state and signals ---


func test_on_off_screen_signals_fire_only_on_a_state_transition():
	var off_count := [0]
	var on_count := [0]
	tracker.screen_exited.connect(func(): off_count[0] += 1)
	tracker.screen_entered.connect(func(): on_count[0] += 1)

	target.global_position = Vector3(1000, 1000, -10) # offscreen
	_step()
	assert_eq(off_count[0], 1)

	_step() # still offscreen, no repeat signal
	assert_eq(off_count[0], 1)

	target.global_position = Vector3(0, 0, -10) # back onscreen
	_step()
	assert_eq(on_count[0], 1)

	_step() # still onscreen, no repeat signal
	assert_eq(on_count[0], 1)


func test_a_target_visible_on_the_first_frame_reports_screen_entered():
	var on_count := [0]
	tracker.screen_entered.connect(func(): on_count[0] += 1)
	target.global_position = Vector3(0, 0, -10) # straight ahead

	_step()

	assert_eq(on_count[0], 1, "the first evaluation is a transition from unknown")


func test_on_screen_is_false_before_the_first_evaluation_and_cannot_be_written():
	var fresh = LFTracker.new()
	assert_false(fresh.on_screen)
	fresh.on_screen = true
	assert_false(fresh.on_screen, "it reports the tracker's own evaluation only")
	fresh.free()


# --- visibility ---


func test_hide_if_off_screen_hides_the_tracker_when_the_target_is_off_screen():
	tracker.hide_if_off_screen = true
	target.global_position = Vector3(1000, 1000, -10)
	_step()
	assert_false(tracker.visible)


func test_hide_if_off_screen_hides_the_tracker_when_the_target_is_behind_the_camera():
	tracker.hide_if_off_screen = true
	target.global_position = Vector3(0, 0, 10)
	_step()
	assert_false(tracker.visible)


func test_hide_if_off_screen_shows_the_tracker_again_when_the_target_returns():
	tracker.hide_if_off_screen = true
	target.global_position = Vector3(1000, 0, -10)
	_step()

	target.global_position = Vector3(0, 0, -10)
	_step()

	assert_true(tracker.visible)


func test_without_hide_flags_an_off_screen_target_keeps_the_tracker_shown():
	target.global_position = Vector3(1000, 1000, -10)
	_step()
	assert_true(tracker.visible)


func test_hide_if_on_screen_hides_the_tracker_while_the_target_on_screen():
	tracker.hide_if_on_screen = true
	target.global_position = Vector3(0, 0, -10)

	_step()

	assert_false(tracker.visible, "an arrow indicator must hide while its target is visible")


func test_hide_if_on_screen_shows_the_tracker_again_once_the_target_leaves_the_screen():
	tracker.hide_if_on_screen = true
	target.global_position = Vector3(0, 0, -10)
	_step()

	target.global_position = Vector3(1000, 0, -10)
	_step()

	assert_true(tracker.visible, "the arrow must reappear when the target goes off-screen")


func test_without_hide_flags_the_tracker_leaves_visibility_to_the_caller():
	tracker.visible = false
	target.global_position = Vector3(1000, 0, -10)

	_step()

	assert_false(tracker.visible, "visibility is only driven when a hide_if_* flag is on")


func test_turning_off_the_hide_flag_that_hid_the_tracker_shows_it_again():
	tracker.hide_if_on_screen = true
	target.global_position = Vector3(0, 0, -10)
	_step()
	assert_false(tracker.visible)

	tracker.hide_if_on_screen = false
	_step()

	assert_true(tracker.visible, "no tracker stuck hidden by a flag that is now off")
	assert_almost_eq(_pivot_on_screen(), _center(), EPS, "and placed again")


func test_a_freed_target_hides_the_tracker():
	target.global_position = Vector3(1000, 0, -10)
	_step()

	target.free()
	_step()

	assert_false(tracker.visible, "no stale arrow toward a target that is gone")


func test_a_null_target_hides_the_tracker_and_a_new_one_shows_it_again():
	tracker.target = null
	_step()
	assert_false(tracker.visible)

	tracker.target = target
	target.global_position = Vector3(1000, 0, -10)
	_step()
	assert_true(tracker.visible)


func test_no_camera_or_a_target_outside_the_tree_hides_the_tracker():
	target.global_position = Vector3(1000, 0, -10)
	tracker.camera = null
	_step()
	assert_false(tracker.visible, "no camera")

	tracker.camera = camera
	_step()
	assert_true(tracker.visible)

	remove_child(target)
	_step()
	assert_false(tracker.visible, "a target outside the tree")
	add_child(target)


func test_losing_an_on_screen_target_reports_screen_exited():
	var off_count := [0]
	tracker.screen_exited.connect(func(): off_count[0] += 1)
	target.global_position = Vector3(0, 0, -10)
	_step()

	tracker.target = null
	_step()

	assert_eq(off_count[0], 1)
	assert_false(tracker.on_screen)


# --- defaults and statics ---


func test_the_tracker_lets_clicks_through_by_default():
	assert_eq(autofree(LFTracker.new()).mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_a_tracker_the_caller_hid_stays_hidden_when_a_lost_target_returns():
	tracker.visible = false
	tracker.target = null
	_step()

	tracker.target = target
	target.global_position = Vector3(1000, 0, -10)
	_step()

	assert_false(tracker.visible, "it only shows itself again after hiding itself")


func test_losing_an_off_screen_target_reports_nothing_and_a_new_target_reports_its_state():
	var off_count := [0]
	var on_count := [0]
	tracker.screen_exited.connect(func(): off_count[0] += 1)
	tracker.screen_entered.connect(func(): on_count[0] += 1)
	target.global_position = Vector3(1000, 0, -10)
	_step()
	assert_eq(off_count[0], 1, "the first evaluation reports off-screen too")

	tracker.target = null
	_step()
	assert_eq(off_count[0], 1, "an off-screen target leaving changes nothing")

	tracker.target = target
	_step()
	assert_eq(off_count[0], 2, "a target acquired again is evaluated afresh")
	assert_eq(on_count[0], 0)


func test_a_freed_camera_hides_the_tracker():
	target.global_position = Vector3(0, 0, -10)
	_step()

	camera.free()
	_step()

	assert_false(tracker.visible)
	assert_false(tracker.on_screen)
	assert_engine_error_count(0)


func test_the_tracker_follows_its_target_every_frame_on_its_own():
	target.global_position = Vector3(0, 0, -10)

	await wait_process_frames(2)

	assert_true(tracker.on_screen)
	assert_almost_eq(_pivot_on_screen(), _center(), EPS)


func test_evaluating_a_tracker_that_is_not_in_the_tree_does_nothing():
	var loose := LFTracker.new()
	loose.camera = camera
	loose.target = target
	autofree(loose)

	loose.update_tracking()

	assert_false(loose.on_screen)
	assert_true(loose.visible)
	assert_eq(loose.position, Vector2.ZERO)
