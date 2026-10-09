extends GutTest

func test_control_2d_anchor_syncs_target_position_on_entry_when_configured():
	var anchor = LFControl2D.new()
	anchor.sync_initial_position = true
	var target = add_child_autofree(Node2D.new())
	anchor.target = target

	add_child_autofree(anchor)

	assert_eq(target.global_position, LFControl.get_center_pos_on_viewport(anchor))


func test_control_2d_anchor_does_not_sync_when_not_configured():
	var anchor = LFControl2D.new()
	anchor.sync_initial_position = false
	var target = add_child_autofree(Node2D.new())
	target.global_position = Vector2(123, 456)
	anchor.target = target

	add_child_autofree(anchor)

	assert_eq(target.global_position, Vector2(123, 456))


func test_control_2d_anchor_still_registers_under_its_registry_id():
	var anchor = LFControl2D.new()
	anchor.registry_id = "control-2d-registers"
	add_child_autofree(anchor)
	assert_same(LFControl.by_id("control-2d-registers"), anchor)


func test_sync_with_no_target_warns_instead_of_crashing():
	var anchor = LFControl2D.new()
	anchor.sync_initial_position = true

	add_child_autofree(anchor)

	assert_push_warning("target", "a missing target is reported as a warning")
	assert_engine_error_count(0, "a missing target must not raise a script error")


func test_the_sync_happens_once_at_first_ready_not_on_every_tree_entry():
	var anchor = LFControl2D.new()
	anchor.sync_initial_position = true
	anchor.position = Vector2(40, 60)
	var target = add_child_autofree(Node2D.new())
	anchor.target = target
	add_child_autofree(anchor)
	await wait_process_frames(2) # past the post-layout resync
	assert_eq(target.global_position, Vector2(40, 60), "precondition: the initial sync ran")
	target.global_position = Vector2(123, 456)

	remove_child(anchor)
	add_child(anchor)
	await wait_process_frames(2)

	assert_eq(target.global_position, Vector2(123, 456), "re-entering the tree must not resync")


func test_an_anchor_inside_a_container_snaps_the_target_to_its_laid_out_center():
	var container = CenterContainer.new()
	container.position = Vector2(100, 100)
	container.size = Vector2(400, 300)
	add_child_autofree(container)
	var target = add_child_autofree(Node2D.new())
	var anchor = LFControl2D.new()
	anchor.custom_minimum_size = Vector2(20, 20)
	anchor.target = target
	anchor.sync_initial_position = true

	container.add_child(anchor)
	await wait_process_frames(2)

	assert_almost_eq(target.global_position, Vector2(300, 250), Vector2(0.01, 0.01), "the snap uses the center after the container's layout")


func test_an_anchor_under_a_canvas_layer_snaps_the_target_to_its_on_screen_center():
	var layer = add_child_autofree(CanvasLayer.new())
	layer.offset = Vector2(100, 0)
	layer.scale = Vector2(2, 2)
	var target = add_child_autofree(Node2D.new())
	var anchor = LFControl2D.new()
	anchor.position = Vector2(10, 10)
	anchor.size = Vector2(20, 20)
	anchor.target = target
	anchor.sync_initial_position = true

	layer.add_child(anchor)

	assert_almost_eq(target.global_position, Vector2(140, 40), Vector2(0.01, 0.01))


func test_a_target_in_another_canvas_layer_lands_on_the_same_screen_point():
	var target_layer = add_child_autofree(CanvasLayer.new())
	target_layer.offset = Vector2(50, 0)
	var target = Node2D.new()
	target_layer.add_child(target)
	var anchor = LFControl2D.new()
	anchor.position = Vector2(200, 100)
	anchor.target = target
	anchor.sync_initial_position = true

	add_child_autofree(anchor)

	assert_almost_eq(target.get_global_transform_with_canvas().origin, Vector2(200, 100), Vector2(0.01, 0.01))


func test_follow_keeps_the_target_on_the_anchor_as_it_moves():
	var target = add_child_autofree(Node2D.new())
	var anchor = LFControl2D.new()
	anchor.target = target
	anchor.follow = true
	add_child_autofree(anchor)

	anchor.position = Vector2(321, 123)
	await wait_process_frames(1)

	assert_almost_eq(target.global_position, Vector2(321, 123), Vector2(0.01, 0.01))


func test_without_follow_the_target_stays_put_once_synced():
	var target = add_child_autofree(Node2D.new())
	var anchor = LFControl2D.new()
	anchor.target = target
	anchor.sync_initial_position = true
	add_child_autofree(anchor)
	await wait_process_frames(2)

	anchor.position = Vector2(321, 123)
	await wait_process_frames(2)

	assert_eq(target.global_position, Vector2.ZERO)


func test_sync_target_snaps_on_demand():
	var target = add_child_autofree(Node2D.new())
	var anchor = LFControl2D.new()
	anchor.target = target
	add_child_autofree(anchor)
	anchor.position = Vector2(40, 60)

	anchor.sync_target()

	assert_almost_eq(target.global_position, Vector2(40, 60), Vector2(0.01, 0.01))


func test_follow_without_a_target_waits_silently_then_snaps_once_one_is_set():
	var anchor = LFControl2D.new()
	anchor.follow = true
	anchor.position = Vector2(50, 70)
	add_child_autofree(anchor)
	await wait_process_frames(3)

	assert_engine_error_count(0, "following nothing raises nothing")

	var target = add_child_autofree(Node2D.new())
	anchor.target = target
	await wait_process_frames(1)

	assert_almost_eq(target.global_position, Vector2(50, 70), Vector2(0.01, 0.01))


func test_sync_target_with_either_node_outside_the_tree_does_nothing():
	var target: Node2D = autofree(Node2D.new())
	target.position = Vector2(9, 9)
	var anchor: LFControl2D = autofree(LFControl2D.new())
	anchor.target = target

	anchor.sync_target()
	assert_eq(target.position, Vector2(9, 9), "neither in the tree")

	add_child(anchor)
	anchor.position = Vector2(40, 60)
	anchor.sync_target()
	assert_eq(target.position, Vector2(9, 9), "the target is still outside")
	remove_child(anchor)

	assert_engine_error_count(0)


func test_the_packaged_scene_attaches_the_control_2d_script():
	var node = load(_module_dir().path_join("lf_control_2d.tscn")).instantiate()
	assert_true(node is LFControl2D, "the scene must attach its LFControl2D script")
	node.free()


func test_processing_stops_after_the_one_post_layout_resync():
	var target = add_child_autofree(Node2D.new())
	var anchor = LFControl2D.new()
	anchor.target = target
	anchor.sync_initial_position = true
	add_child_autofree(anchor)
	assert_true(anchor.is_processing(), "waits one frame to resync after layout")

	await wait_process_frames(2)

	assert_false(anchor.is_processing(), "nothing left to do once resynced")


func test_turning_follow_off_stops_processing_and_tracking():
	var target = add_child_autofree(Node2D.new())
	var anchor = LFControl2D.new()
	anchor.target = target
	anchor.follow = true
	add_child_autofree(anchor)
	assert_true(anchor.is_processing())

	anchor.follow = false
	anchor.position = Vector2(80, 90)
	await wait_process_frames(2)

	assert_false(anchor.is_processing())
	assert_eq(target.global_position, Vector2.ZERO)


func test_following_a_target_that_gets_freed_reports_nothing():
	var target := Node2D.new()
	add_child(target)
	var anchor = LFControl2D.new()
	anchor.target = target
	anchor.follow = true
	add_child_autofree(anchor)
	await wait_process_frames(1)

	target.free()
	await wait_process_frames(2)

	assert_push_warning_count(0, "a freed target is not reported every frame")
	assert_engine_error_count(0)


func _module_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir().get_base_dir()
