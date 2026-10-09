extends GutTest

## Frame-driven tests run the real tree tick and then wait a couple of frames: the
## camera publishes its screen centre during its own processing, and the layers read it
## at the end of the frame.

const FRAMES := 3

var camera: Camera2D
var layer_a: LFInfiniteScrollSprite
var layer_b: LFInfiniteScrollSprite


class CameraMover extends Node:
	var cam: Camera2D
	var speed := 900.0

	func _process(delta: float) -> void:
		cam.global_position.x += speed * delta


class DeltaClock extends Node:
	var elapsed := 0.0

	func _process(delta: float) -> void:
		elapsed += delta


func before_each():
	camera = add_child_autofree(Camera2D.new())
	camera.make_current()
	layer_a = add_child_autofree(LFInfiniteScrollSprite.new())
	layer_a.track_camera = false # isolate apply_camera_delta()'s own effect from self-tracking
	layer_b = add_child_autofree(LFInfiniteScrollSprite.new())
	layer_b.track_camera = false


func _texture(size: Vector2i) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create(size.x, size.y, false, Image.FORMAT_RGBA8))


func _move_camera_and_settle(to: Vector2) -> void:
	await wait_process_frames(FRAMES)
	camera.global_position = to
	await wait_process_frames(FRAMES)


func test_apply_camera_delta_advances_the_region_position_incrementally_not_absolutely():
	layer_a.apply_camera_delta(Vector2(10, 0))
	assert_eq(layer_a.region_rect.position, Vector2(10, 0))

	layer_a.apply_camera_delta(Vector2(5, 3))
	assert_eq(layer_a.region_rect.position, Vector2(15, 3), "second call must add onto the first, not replace it")


func test_a_non_finite_delta_is_ignored_instead_of_poisoning_the_region():
	layer_a.texture = _texture(Vector2i(64, 64))
	layer_a.apply_camera_delta(Vector2(10, 0))
	layer_a.apply_camera_delta(Vector2(INF, 0))
	layer_a.apply_camera_delta(Vector2(0, NAN))
	assert_eq(layer_a.region_rect.position, Vector2(10, 0), "a non-finite movement changes nothing")
	layer_a.apply_camera_delta(Vector2(5, 0))
	assert_eq(layer_a.region_rect.position, Vector2(15, 0), "later movement still scrolls")


func test_position_factor_scales_the_applied_delta():
	layer_a.position_factor = 0.5
	layer_a.apply_camera_delta(Vector2(10, 10))
	assert_eq(layer_a.region_rect.position, Vector2(5, 5))


func test_a_scaled_layer_shifts_its_region_in_texels_so_the_texture_stays_world_fixed():
	layer_a.scale = Vector2(2, 2)
	layer_a.apply_camera_delta(Vector2(10, 0))
	assert_eq(layer_a.region_rect.position, Vector2(5, 0), "10 world px on a 2x layer is 5 texels")


func test_a_flipped_layer_shifts_its_region_the_other_way():
	layer_a.flip_h = true
	layer_a.flip_v = true
	layer_a.apply_camera_delta(Vector2(10, 4))
	assert_eq(layer_a.region_rect.position, Vector2(-10, -4))


func test_a_rotated_layer_shifts_its_region_along_its_own_axes():
	layer_a.rotation = PI / 2.0
	layer_a.apply_camera_delta(Vector2(10, 0))
	assert_almost_eq(layer_a.region_rect.position.x, 0.0, 0.001)
	assert_almost_eq(layer_a.region_rect.position.y, -10.0, 0.001)


func test_a_texel_stays_put_in_world_space_while_a_scaled_layer_tracks_the_camera():
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.scale = Vector2(2, 2)
	tracking.region_rect = Rect2(0, 0, 100, 100)
	tracking.camera = camera
	await wait_process_frames(FRAMES)
	# Local x of texel 30 on a centred, unflipped sprite: 30 - region.x - width / 2.
	var before: Vector2 = tracking.to_global(Vector2(30.0 - tracking.region_rect.position.x - 50.0, 0))

	await _move_camera_and_settle(Vector2(10, 0))

	var after: Vector2 = tracking.to_global(Vector2(30.0 - tracking.region_rect.position.x - 50.0, 0))
	assert_almost_eq(after.x, before.x, 0.001, "with position_factor 1 the texture must not drift")


func test_the_region_offset_wraps_modulo_the_texture_size():
	layer_a.texture = _texture(Vector2i(64, 32))

	layer_a.apply_camera_delta(Vector2(100, 70))
	assert_eq(layer_a.region_rect.position, Vector2(36, 6), "the offset must stay within one texture tile")

	layer_a.apply_camera_delta(Vector2(-40, -10))
	assert_eq(layer_a.region_rect.position, Vector2(60, 28), "negative offsets wrap into the tile too")


func test_without_a_texture_the_offset_is_not_wrapped():
	layer_a.apply_camera_delta(Vector2(1000, 0))
	assert_eq(layer_a.region_rect.position, Vector2(1000, 0))


func test_swapping_the_texture_re_wraps_the_offset_into_the_new_tile():
	layer_a.texture = _texture(Vector2i(64, 64))
	layer_a.apply_camera_delta(Vector2(60, 0))

	layer_a.texture = _texture(Vector2i(50, 50))

	assert_eq(layer_a.region_rect.position, Vector2(10, 0))


func test_self_tracking_advances_by_the_cameras_movement_not_its_position():
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.camera = camera
	await wait_process_frames(FRAMES)
	tracking.apply_camera_delta(Vector2(100, 0)) # an offset from elsewhere

	await _move_camera_and_settle(Vector2(10, 0))

	assert_eq(tracking.region_rect.position, Vector2(110, 0), "self-tracking must add the camera's delta, keeping earlier offsets")


func test_assigning_a_camera_after_ready_anchors_self_tracking_at_its_view():
	camera.global_position = Vector2(300, 0)
	await wait_process_frames(FRAMES)
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new()) # _ready() runs with no camera
	tracking.camera = camera

	await _move_camera_and_settle(Vector2(310, 0))

	assert_eq(tracking.region_rect.position, Vector2(10, 0), "the first frames must scroll only the camera's movement, not its whole position")


func test_reset_re_anchors_self_tracking_so_an_earlier_camera_jump_is_not_scrolled():
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.track_camera = false
	tracking.camera = camera
	await _move_camera_and_settle(Vector2(500, 0)) # a teleport while not tracking

	tracking.reset()
	tracking.track_camera = true
	await _move_camera_and_settle(Vector2(510, 0))

	assert_eq(tracking.region_rect.position, Vector2(10, 0), "only movement since reset() must scroll the region")


func test_reset_without_a_camera_is_a_no_op():
	var bare: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	bare.reset()
	assert_eq(bare.region_rect.position, Vector2.ZERO, "reset must not move the region")
	assert_eq(bare.last_camera_position, Vector2.ZERO)


func test_a_self_tracking_layer_sits_on_the_cameras_view_centre():
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.camera = camera

	await _move_camera_and_settle(Vector2(40, -20))

	assert_eq(tracking.global_position, Vector2(40, -20))


func test_a_self_tracking_layer_follows_what_a_smoothing_camera_shows_not_its_target():
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.camera = camera
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	await wait_process_frames(FRAMES)

	camera.global_position = Vector2(500, 0)
	await wait_process_frames(FRAMES)

	var shown: Vector2 = camera.get_screen_center_position()
	assert_lt(shown.x, 499.0, "precondition: the smoothed view lags the camera's target")
	assert_almost_eq(tracking.global_position.x, shown.x, 0.001)
	assert_almost_eq(tracking.region_rect.position.x, shown.x, 0.001, "the region scrolls by what the view moved")


func test_an_idle_layer_matches_a_camera_moved_every_idle_frame_on_every_frame():
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.camera = camera
	move_child(tracking, 0) # processed before the camera and the mover
	var mover: CameraMover = add_child_autofree(CameraMover.new())
	mover.cam = camera
	await wait_process_frames(FRAMES)

	var mismatched := 0
	for i in 30:
		await get_tree().process_frame
		if !tracking.global_position.is_equal_approx(camera.get_screen_center_position()):
			mismatched += 1

	assert_gt(camera.global_position.x, 0.0, "precondition: the camera moved")
	assert_eq(mismatched, 0, "the layer must sit on the view the frame renders, every frame")


func test_the_physics_process_callback_switches_the_layer_to_physics_processing():
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	assert_true(tracking.is_physics_processing())
	assert_false(tracking.is_processing())

	tracking.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	assert_true(tracking.is_processing())
	assert_false(tracking.is_physics_processing())


func test_a_physics_layer_still_follows_the_camera():
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	tracking.camera = camera
	await wait_physics_frames(FRAMES)
	camera.global_position = Vector2(70, 0)
	await wait_physics_frames(FRAMES)
	await wait_process_frames(FRAMES)
	await wait_physics_frames(FRAMES)

	assert_eq(tracking.global_position, Vector2(70, 0))


func test_autoscroll_drifts_the_texture_at_its_velocity_without_a_camera():
	var clock: DeltaClock = add_child_autofree(DeltaClock.new())
	layer_a.autoscroll = Vector2(30, 0)
	await wait_process_frames(10)

	assert_gt(clock.elapsed, 0.0)
	assert_almost_eq(layer_a.region_rect.position.x, -30.0 * clock.elapsed, 0.001,
		"a texture drifting right by velocity * time shows texels that much further left")


func test_autoscroll_is_measured_in_world_units_on_a_scaled_layer():
	layer_a.scale = Vector2(2, 2)
	layer_a.autoscroll = Vector2(30, 0)
	layer_b.autoscroll = Vector2(30, 0)
	await wait_process_frames(10)

	assert_almost_eq(layer_a.region_rect.position.x * 2.0, layer_b.region_rect.position.x, 0.001)


func test_zero_autoscroll_and_no_camera_leave_the_region_alone():
	await wait_process_frames(FRAMES)
	assert_eq(layer_a.region_rect.position, Vector2.ZERO)


func _controller(layers: Array[LFInfiniteScrollSprite]) -> LFBackgroundController:
	var controller: LFBackgroundController = add_child_autofree(LFBackgroundController.new())
	controller.scroll_layers = layers
	controller.camera = camera
	return controller


func test_controller_applies_the_same_camera_delta_to_every_configured_layer():
	var layer_c: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	layer_c.track_camera = false
	var layers: Array[LFInfiniteScrollSprite] = [layer_a, layer_b, layer_c]
	_controller(layers)

	await _move_camera_and_settle(Vector2(20, 15))

	for layer in layers:
		assert_eq(layer.region_rect.position, Vector2(20, 15))


func test_update_infinite_scroll_layers_skips_null_entries():
	var layers: Array[LFInfiniteScrollSprite] = [layer_a, null, layer_b]
	var controller := _controller(layers)

	controller.update_infinite_scroll_layers(Vector2(5, 0))

	assert_eq(layer_a.region_rect.position, Vector2(5, 0))
	assert_eq(layer_b.region_rect.position, Vector2(5, 0))


func test_controller_driven_layers_sit_on_the_cameras_view():
	var layers: Array[LFInfiniteScrollSprite] = [layer_a, layer_b]
	_controller(layers)

	await _move_camera_and_settle(Vector2(2000, 0))

	assert_eq(layer_a.global_position, Vector2(2000, 0))
	assert_eq(layer_b.global_position, Vector2(2000, 0))


func test_a_controller_that_does_not_follow_the_camera_leaves_its_layers_in_place():
	var layers: Array[LFInfiniteScrollSprite] = [layer_a]
	var controller := _controller(layers)
	controller.follow_camera = false

	await _move_camera_and_settle(Vector2(2000, 0))

	assert_eq(layer_a.global_position, Vector2.ZERO)
	assert_eq(layer_a.region_rect.position, Vector2(2000, 0), "the region still scrolls")


func test_a_controller_takes_over_its_layers_so_movement_is_applied_once():
	var self_tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	self_tracking.camera = camera
	var layers: Array[LFInfiniteScrollSprite] = [self_tracking]
	_controller(layers)

	assert_false(self_tracking.track_camera, "a controlled layer must stop tracking on its own")
	await _move_camera_and_settle(Vector2(30, 0))
	assert_eq(self_tracking.region_rect.position, Vector2(30, 0))


func test_a_layer_appended_after_assignment_is_taken_over_on_the_next_frame():
	var layers: Array[LFInfiniteScrollSprite] = []
	var controller := _controller(layers)
	var late: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	controller.scroll_layers.append(late)

	await wait_process_frames(FRAMES)

	assert_false(late.track_camera)


func test_assigning_the_controllers_camera_anchors_it_at_the_cameras_view():
	camera.global_position = Vector2(300, 0)
	await wait_process_frames(FRAMES)
	var layers: Array[LFInfiniteScrollSprite] = [layer_a]
	_controller(layers)

	await _move_camera_and_settle(Vector2(310, 0))

	assert_eq(layer_a.region_rect.position, Vector2(10, 0), "the first frames must forward only the camera's movement")


func test_the_controllers_reset_re_anchors_so_an_earlier_camera_jump_is_not_forwarded():
	var layers: Array[LFInfiniteScrollSprite] = [layer_a]
	var controller := _controller(layers)
	await wait_process_frames(FRAMES)
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	await _move_camera_and_settle(Vector2(800, 0)) # a teleport the controller does not see

	controller.reset()
	assert_eq(controller.last_camera_position, Vector2(800, 0))
	controller.process_mode = Node.PROCESS_MODE_INHERIT
	await _move_camera_and_settle(Vector2(810, 0))

	assert_eq(layer_a.region_rect.position, Vector2(10, 0), "only movement since reset() is forwarded")


func test_the_controllers_reset_without_a_camera_is_a_no_op():
	var controller: LFBackgroundController = add_child_autofree(LFBackgroundController.new())
	controller.reset()
	assert_eq(controller.last_camera_position, Vector2.ZERO)


func test_the_controller_follows_what_a_smoothing_camera_shows():
	var layers: Array[LFInfiniteScrollSprite] = [layer_a]
	var controller := _controller(layers)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	await wait_process_frames(FRAMES)

	camera.global_position = Vector2(500, 0)
	await wait_process_frames(FRAMES)

	var shown: Vector2 = camera.get_screen_center_position()
	assert_lt(shown.x, 499.0, "precondition: the smoothed view lags the camera's target")
	assert_almost_eq(controller.last_camera_position.x, shown.x, 0.001)
	assert_almost_eq(layer_a.region_rect.position.x, shown.x, 0.001)


func test_the_controllers_process_callback_selects_idle_or_physics():
	var controller: LFBackgroundController = add_child_autofree(LFBackgroundController.new())
	assert_true(controller.is_processing(), "idle by default, like Camera2D")
	controller.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	assert_true(controller.is_physics_processing())
	assert_false(controller.is_processing())


func test_a_freed_layer_left_in_the_controller_is_skipped():
	var doomed: LFInfiniteScrollSprite = LFInfiniteScrollSprite.new()
	add_child(doomed)
	var layers: Array[LFInfiniteScrollSprite] = [doomed, layer_a]
	var controller := _controller(layers)
	doomed.free()

	await _move_camera_and_settle(Vector2(20, 0))
	controller.update_infinite_scroll_layers(Vector2(5, 0))
	controller.scroll_layers = controller.scroll_layers

	assert_eq(layer_a.region_rect.position, Vector2(25, 0), "the live layer still scrolls")
	assert_engine_error_count(0)


func test_a_controller_without_a_camera_does_nothing():
	var controller: LFBackgroundController = add_child_autofree(LFBackgroundController.new())
	var layers: Array[LFInfiniteScrollSprite] = [layer_a]
	controller.scroll_layers = layers
	await wait_process_frames(FRAMES)
	assert_eq(layer_a.region_rect.position, Vector2.ZERO)


func test_the_packaged_sprite_scene_attaches_its_script_with_repeat_and_region_enabled():
	var node = load(_module_dir().path_join("lf_infinite_scroll_sprite.tscn")).instantiate()
	assert_true(node is LFInfiniteScrollSprite, "the scene must attach its LFInfiniteScrollSprite script")
	assert_true(node.region_enabled)
	assert_eq(node.texture_repeat, CanvasItem.TEXTURE_REPEAT_ENABLED)
	assert_eq(node.region_rect.position, Vector2.ZERO, "the scene starts with no scroll offset")
	node.free()


func test_the_packaged_controller_scene_attaches_its_script():
	var node = load(_module_dir().path_join("lf_background_controller.tscn")).instantiate()
	assert_true(node is LFBackgroundController, "the scene must attach its LFBackgroundController script")
	node.free()


## The module folder, wherever the library is installed.
func _module_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir().get_base_dir()


func test_a_layer_scaled_to_zero_keeps_its_region():
	layer_a.scale = Vector2.ZERO
	layer_a.apply_camera_delta(Vector2(10, 0))
	assert_eq(layer_a.region_rect.position, Vector2.ZERO, "no texels to scroll, and no garbage offset")


func test_a_camera_that_enters_the_tree_after_assignment_is_anchored_not_scrolled():
	var late_camera := Camera2D.new()
	late_camera.position = Vector2(500, 0)
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.camera = late_camera
	await wait_process_frames(FRAMES)

	add_child_autofree(late_camera)
	late_camera.make_current()
	await wait_process_frames(FRAMES)

	assert_eq(tracking.region_rect.position, Vector2.ZERO, "the camera's whole position must not be scrolled")
	assert_eq(tracking.global_position, Vector2(500, 0), "the layer still sits on the view")


func test_a_controller_anchors_a_camera_that_enters_the_tree_after_assignment():
	var late_camera := Camera2D.new()
	late_camera.position = Vector2(500, 0)
	var controller: LFBackgroundController = add_child_autofree(LFBackgroundController.new())
	var layers: Array[LFInfiniteScrollSprite] = [layer_a]
	controller.scroll_layers = layers
	controller.camera = late_camera
	await wait_process_frames(FRAMES)

	add_child_autofree(late_camera)
	late_camera.make_current()
	await wait_process_frames(FRAMES)
	late_camera.position = Vector2(510, 0)
	await wait_process_frames(FRAMES)

	assert_eq(layer_a.region_rect.position, Vector2(10, 0), "only movement made once the camera is in the tree")


func test_a_camera_that_leaves_the_tree_and_returns_elsewhere_is_re_anchored_not_scrolled():
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.camera = camera
	await _move_camera_and_settle(Vector2(10, 0))
	assert_eq(tracking.region_rect.position, Vector2(10, 0), "precondition: tracking")

	remove_child(camera)
	await wait_process_frames(FRAMES)
	camera.position = Vector2(800, 0)
	add_child(camera)
	camera.make_current()
	await wait_process_frames(FRAMES)

	assert_eq(tracking.region_rect.position, Vector2(10, 0), "the jump while away must not scroll")
	assert_eq(tracking.global_position, Vector2(800, 0), "the layer sits on the view again")


func test_a_controller_re_anchors_a_camera_that_leaves_the_tree_and_returns_elsewhere():
	var layers: Array[LFInfiniteScrollSprite] = [layer_a]
	_controller(layers)
	await _move_camera_and_settle(Vector2(10, 0))
	assert_eq(layer_a.region_rect.position, Vector2(10, 0), "precondition: forwarding")

	remove_child(camera)
	await wait_process_frames(FRAMES)
	camera.position = Vector2(800, 0)
	add_child(camera)
	camera.make_current()
	await _move_camera_and_settle(Vector2(805, 0))

	assert_eq(layer_a.region_rect.position, Vector2(15, 0), "only movement made after the camera returned")


func test_a_freed_camera_stops_tracking_without_errors():
	var doomed := Camera2D.new()
	add_child(doomed)
	doomed.make_current()
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.camera = doomed
	var layers: Array[LFInfiniteScrollSprite] = [layer_a]
	var controller: LFBackgroundController = add_child_autofree(LFBackgroundController.new())
	controller.scroll_layers = layers
	controller.camera = doomed
	await wait_process_frames(FRAMES)

	doomed.free()
	await wait_process_frames(FRAMES)

	assert_eq(tracking.region_rect.position, Vector2.ZERO)
	assert_eq(layer_a.region_rect.position, Vector2.ZERO)
	assert_engine_error_count(0)


func test_a_layer_that_does_not_track_leaves_the_camera_alone():
	var still: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	still.track_camera = false
	still.camera = camera
	await _move_camera_and_settle(Vector2(60, 40))

	assert_eq(still.region_rect.position, Vector2.ZERO, "no scrolling")
	assert_eq(still.global_position, Vector2.ZERO, "no following")


func test_autoscroll_adds_to_camera_tracking():
	var clock: DeltaClock = add_child_autofree(DeltaClock.new())
	var tracking: LFInfiniteScrollSprite = add_child_autofree(LFInfiniteScrollSprite.new())
	tracking.camera = camera
	await wait_process_frames(FRAMES)
	tracking.autoscroll = Vector2(30, 0)
	var drift_from := clock.elapsed
	camera.global_position = Vector2(100, 0)
	await wait_process_frames(10)
	tracking.autoscroll = Vector2.ZERO
	var drifted := clock.elapsed - drift_from

	assert_gt(drifted, 0.0)
	assert_almost_eq(tracking.region_rect.position.x, 100.0 - 30.0 * drifted, 0.01, "camera movement plus drift")


func test_a_texture_without_size_leaves_the_offset_unwrapped():
	layer_a.texture = ImageTexture.new()
	layer_a.apply_camera_delta(Vector2(500, -20))
	assert_eq(layer_a.region_rect.position, Vector2(500, -20), "no tile to wrap into, and no NaN")


func test_a_layer_outside_the_tree_converts_movement_through_its_own_transform():
	var loose := LFInfiniteScrollSprite.new()
	loose.scale = Vector2(2, 2)
	loose.apply_camera_delta(Vector2(10, 0))
	assert_eq(loose.region_rect.position, Vector2(5, 0))
	loose.free()


func test_the_controller_on_physics_frames_still_forwards_the_camera():
	var layers: Array[LFInfiniteScrollSprite] = [layer_a]
	var controller := _controller(layers)
	controller.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	await wait_physics_frames(FRAMES)
	camera.global_position = Vector2(30, 0)
	await wait_physics_frames(FRAMES)
	await wait_process_frames(FRAMES)
	await wait_physics_frames(FRAMES)

	assert_eq(layer_a.region_rect.position, Vector2(30, 0))
	assert_eq(layer_a.global_position, Vector2(30, 0))
