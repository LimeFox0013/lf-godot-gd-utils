extends GutTest

## Durations are a few hundredths of a second, or tweens are stepped by hand with
## custom_step, so the suite stays fast; the assertions are about end states.

const DEADLINE_MSEC := 3000


## Awaits frames until `condition` holds or the deadline passes; returns whether it held.
func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + DEADLINE_MSEC
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


## Awaits frames until `object` is freed or the deadline passes; returns whether it was freed.
func _until_freed(object: Object) -> bool:
	var ref: WeakRef = weakref(object)
	return await _until(func() -> bool: return ref.get_ref() == null)


# --- control ---------------------------------------------------------------

func test_control_tween_reaches_the_target_value_when_finished():
	var control = add_child_autofree(Control.new())
	control.modulate = Color(1, 1, 1, 0)

	var tween = LFAnimate.control(control, "modulate:a", 1.0, 0.05)
	await tween.finished

	assert_almost_eq(control.modulate.a, 1.0, 0.01)


func test_control_binds_its_tween_to_the_node_so_it_pauses_with_the_node():
	var node: Control = add_child_autofree(Control.new())
	node.modulate.a = 0.0
	node.process_mode = Node.PROCESS_MODE_DISABLED

	var tween := LFAnimate.control(node, "modulate:a", 1.0, 0.05)
	await wait_process_frames(5)

	assert_eq(node.modulate.a, 0.0, "a node-bound tween does not run while its node is not processing")
	tween.kill()


func test_control_accepts_any_node_with_the_property():
	var node: Node3D = add_child_autofree(Node3D.new())

	var tween := LFAnimate.control(node, "position:x", 10.0, 0.02)
	await tween.finished

	assert_almost_eq(node.position.x, 10.0, 0.01)


func test_control_applies_the_given_transition_and_ease():
	var node: Control = add_child_autofree(Control.new())
	node.modulate.a = 0.0

	var tween := LFAnimate.control(node, "modulate:a", 1.0, 1.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.pause()
	tween.custom_step(0.5)

	assert_almost_eq(node.modulate.a, 0.25, 0.01, "quad ease-in is at a quarter halfway through")
	tween.kill()


func test_control_replaces_an_earlier_tween_on_the_same_property():
	var node: Control = add_child_autofree(Control.new())
	node.modulate.a = 0.5

	var first := LFAnimate.control(node, "modulate:a", 1.0, 0.4)
	var second := LFAnimate.control(node, "modulate:a", 0.0, 0.05)
	assert_false(first.is_valid(), "the earlier tween on the property is killed")
	await second.finished
	await wait_process_frames(3)

	assert_almost_eq(node.modulate.a, 0.0, 0.01, "the newest tween has the last word")


func test_control_leaves_tweens_on_other_properties_running():
	var node: Control = add_child_autofree(Control.new())

	var fade := LFAnimate.control(node, "modulate:a", 0.0, 0.4)
	LFAnimate.control(node, "position:x", 5.0, 0.4)

	assert_true(fade.is_valid())
	fade.kill()


func test_control_without_replace_keeps_the_earlier_tween():
	var node: Control = add_child_autofree(Control.new())

	var first := LFAnimate.control(node, "modulate:a", 0.0, 0.4)
	LFAnimate.control(node, "modulate:a", 1.0, 0.4, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT, false)

	assert_true(first.is_valid())


func test_a_whole_property_and_one_of_its_parts_replace_each_other():
	var node: Control = add_child_autofree(Control.new())

	var whole := LFAnimate.control(node, "position", Vector2(50, 50), 0.4)
	var part := LFAnimate.control(node, "position:x", 10.0, 0.4)
	assert_false(whole.is_valid(), "position:x reaches into position")

	LFAnimate.control(node, "position", Vector2.ZERO, 0.4)
	assert_false(part.is_valid(), "and the other way round")


func test_paths_that_only_share_a_prefix_do_not_overlap():
	var node: Control = add_child_autofree(Control.new())

	var fade := LFAnimate.control(node, "modulate", Color.RED, 0.4)
	LFAnimate.control(node, "self_modulate", Color.BLUE, 0.4)
	LFAnimate.control(node, "position:x", 3.0, 0.4)
	var y := LFAnimate.control(node, "position:y", 3.0, 0.4)

	assert_true(fade.is_valid())
	assert_true(y.is_valid(), "position:x and position:y are different parts")
	fade.kill()
	y.kill()


func test_a_zero_duration_sets_the_value_at_once_and_stops_the_running_tween():
	var node: Control = add_child_autofree(Control.new())
	var running := LFAnimate.control(node, "position:x", 100.0, 0.4)

	var tween := LFAnimate.control(node, "position", Vector2(7, 8), 0.0)

	assert_eq(node.position, Vector2(7, 8), "set before the call returns")
	assert_false(running.is_valid())
	assert_not_null(tween)
	await tween.finished
	assert_eq(node.position, Vector2(7, 8))


func test_a_node_outside_the_tree_gets_the_value_at_once():
	var node: Control = autofree(Control.new())

	var tween := LFAnimate.control(node, "modulate:a", 0.25, 0.4)

	assert_almost_eq(node.modulate.a, 0.25, 0.001)
	await tween.finished


func test_a_duplicated_node_does_not_replace_the_originals_tweens():
	# Node.duplicate() copies metas; the copy's tweens must not reach the original's.
	var node: Control = add_child_autofree(Control.new())
	var fade := LFAnimate.control(node, "modulate:a", 0.0, 0.4)
	var punch := LFAnimate.punch_scale(node, 2.0, 0.4)
	var copy: Control = add_child_autofree(node.duplicate())
	copy.scale = Vector2.ONE

	LFAnimate.control(copy, "modulate:a", 1.0, 0.4)
	LFAnimate.punch_scale(copy, 1.5, 0.4)

	assert_true(fade.is_valid(), "the original's fade keeps running")
	assert_true(punch.is_valid(), "and so does its punch")
	assert_eq(copy.scale, Vector2.ONE * 1.5, "the copy punches from its own scale")
	fade.kill()
	punch.kill()


# --- comics_pop_appear / comics_pop_disappear -------------------------------

func test_comics_pop_appear_settles_at_original_scale_and_full_opacity():
	var node = add_child_autofree(Control.new())
	node.scale = Vector2(2, 2)

	await LFAnimate.comics_pop_appear(node, 0.05)

	assert_eq(node.scale, Vector2(2, 2))
	assert_almost_eq(node.modulate.a, 1.0, 0.01)


func test_overlapping_pop_ins_never_leave_the_node_grown():
	var node: Control = add_child_autofree(Control.new())
	var first_result := [null]
	var first := func() -> void:
		first_result[0] = await LFAnimate.comics_pop_appear(node, 0.6)
	first.call()
	assert_true(await _until(func() -> bool: return node.scale.x > 1.05), "precondition: the first pop is in its overshoot")

	assert_true(await LFAnimate.comics_pop_appear(node, 0.05))

	assert_eq(node.scale, Vector2.ONE, "the second pop settles at the true rest scale")
	assert_true(await _until(func() -> bool: return first_result[0] != null), "the replaced pop returns")
	assert_false(first_result[0], "and reports it did not finish")


func test_a_pop_pivots_a_control_about_its_centre():
	var node: Control = add_child_autofree(Control.new())
	node.size = Vector2(100, 40)
	var pivots := []
	var watch := func() -> void:
		while is_instance_valid(node) and node.scale != Vector2.ONE:
			pivots.append(node.pivot_offset)
			await get_tree().process_frame
	LFAnimate.comics_pop_appear(node, 0.1)
	watch.call()
	await _until(func() -> bool: return node.scale == Vector2.ONE)

	assert_false(pivots.is_empty())
	for pivot in pivots:
		assert_eq(pivot, Vector2(50, 20), "the scale grows out of the middle")


func test_pop_appear_on_a_node2d():
	var node: Node2D = add_child_autofree(Node2D.new())
	node.position = Vector2(0, 100)

	assert_true(await LFAnimate.comics_pop_appear(node, 0.05, 1.2, 30.0))

	assert_eq(node.scale, Vector2.ONE)
	assert_eq(node.position, Vector2(0, 70))


func test_the_pop_tilt_comes_from_the_given_generator_without_touching_the_global_one():
	var a: Control = add_child_autofree(Control.new())
	var b: Control = add_child_autofree(Control.new())
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 7
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 7
	seed(42)
	var expected_global := randf()
	seed(42)

	await LFAnimate.comics_pop_appear(a, 0.02, 1.2, 60.0, 20.0, rng_a)
	await LFAnimate.comics_pop_appear(b, 0.02, 1.2, 60.0, 20.0, rng_b)

	assert_eq(randf(), expected_global, "the global generator is untouched")
	assert_ne(a.rotation, 0.0)
	assert_eq(a.rotation, b.rotation, "the same seed gives the same tilt")


func test_a_zero_tilt_pops_upright():
	var node: Control = add_child_autofree(Control.new())

	await LFAnimate.comics_pop_appear(node, 0.02, 1.2, 60.0, 0.0)

	assert_eq(node.rotation, 0.0)


func test_comics_pop_disappear_restores_position_and_fades_out():
	var node = add_child_autofree(Control.new())
	node.position = Vector2(10, 20)

	await LFAnimate.comics_pop_disappear(node, 0.05)

	assert_eq(node.position, Vector2(10, 20))
	assert_almost_eq(node.modulate.a, 0.0, 0.01)


func test_comics_pop_appear_keeps_the_nodes_tint():
	var node: Control = add_child_autofree(Control.new())
	node.modulate = Color(1, 0, 0, 1)

	await LFAnimate.comics_pop_appear(node, 0.05)

	assert_eq(node.modulate, Color(1, 0, 0, 1), "the pop must fade in the node's own tint, not force white")


func test_comics_pop_disappear_keeps_the_nodes_tint_while_fading_out():
	var node: Control = add_child_autofree(Control.new())
	node.modulate = Color(0, 1, 0, 1)

	await LFAnimate.comics_pop_disappear(node, 0.05)

	assert_eq(node.modulate, Color(0, 1, 0, 0))


func test_repeated_pop_ins_do_not_ratchet_the_position():
	var node: Control = add_child_autofree(Control.new())
	node.position = Vector2(10, 100)

	await LFAnimate.comics_pop_appear(node, 0.05)
	await LFAnimate.comics_pop_appear(node, 0.05)

	assert_eq(node.position, Vector2(10, 40), "a second pop drifts from the original position, not the drifted one")


func test_a_pop_out_after_a_pop_in_returns_the_node_to_its_original_position_and_clears_the_meta():
	var node: Control = add_child_autofree(Control.new())
	node.position = Vector2(10, 100)

	await LFAnimate.comics_pop_appear(node, 0.05)
	assert_true(node.has_meta(LFAnimate.POP_ORIGIN_META))
	await LFAnimate.comics_pop_disappear(node, 0.05)

	assert_eq(node.position, Vector2(10, 100))
	assert_false(node.has_meta(LFAnimate.POP_ORIGIN_META))


func test_a_pop_out_during_a_pop_in_ends_at_the_rest_scale_and_position():
	var node: Control = add_child_autofree(Control.new())
	node.position = Vector2(10, 100)
	LFAnimate.comics_pop_appear(node, 0.6)
	assert_true(await _until(func() -> bool: return node.scale.x > 1.05), "precondition: the pop-in is in its overshoot")

	assert_true(await LFAnimate.comics_pop_disappear(node, 0.05))

	assert_eq(node.scale, Vector2.ONE)
	assert_eq(node.position, Vector2(10, 100))
	assert_almost_eq(node.modulate.a, 0.0, 0.01)


func test_the_pop_helpers_return_true_when_they_animate_and_false_for_other_nodes():
	var node: Control = add_child_autofree(Control.new())
	var other: Node = add_child_autofree(Node.new())

	assert_true(await LFAnimate.comics_pop_appear(node, 0.02))
	assert_true(await LFAnimate.comics_pop_disappear(node, 0.02))
	assert_false(await LFAnimate.comics_pop_appear(other, 0.02))
	assert_false(await LFAnimate.comics_pop_disappear(other, 0.02))


func test_a_pop_returns_when_its_tween_is_killed_elsewhere():
	var node: Control = add_child_autofree(Control.new())
	var result := [null]
	var run := func() -> void:
		result[0] = await LFAnimate.comics_pop_disappear(node, 5.0)
	run.call()
	await wait_process_frames(2)

	for tween in get_tree().get_processed_tweens():
		tween.kill()

	assert_true(await _until(func() -> bool: return result[0] != null), "the coroutine must not wait forever")
	assert_false(result[0])


func test_a_pop_returns_false_when_the_node_leaves_the_tree():
	var node: Control = autofree(Control.new())
	add_child(node)
	var result := [null]
	var run := func() -> void:
		result[0] = await LFAnimate.comics_pop_appear(node, 5.0)
	run.call()
	await wait_process_frames(2)

	remove_child(node)

	assert_true(await _until(func() -> bool: return result[0] != null))
	assert_false(result[0])


func test_a_pop_on_a_node_outside_the_tree_returns_false():
	var node: Control = autofree(Control.new())

	assert_false(await LFAnimate.comics_pop_appear(node, 0.02))


# --- fall_paper --------------------------------------------------------------

func test_fall_paper_frees_the_node_once_the_fall_completes():
	var node = Control.new()
	add_child(node) # not autofree: fall_paper frees it itself

	await LFAnimate.fall_paper(node, 0.05)
	await get_tree().process_frame # let queue_free() actually take effect

	assert_false(is_instance_valid(node))


func test_fall_paper_wobbles_both_ways_and_falls_just_past_the_viewport_bottom():
	var paper := Control.new()
	add_child(paper) # fall_paper frees it itself
	var rotations := []
	var final_y := [0.0]
	paper.tree_exiting.connect(func(): final_y[0] = paper.global_position.y)
	var expected_end_y: float = paper.get_viewport().get_visible_rect().end.y + 40.0

	LFAnimate.fall_paper(paper, 0.3, 50.0, 10.0, 40.0)
	while is_instance_valid(paper) and paper.is_inside_tree():
		rotations.append(paper.rotation_degrees)
		await get_tree().process_frame

	assert_lt(rotations.min(), -5.0, "the wobble must swing one way")
	assert_gt(rotations.max(), 5.0, "and back the other way")
	assert_almost_eq(final_y[0], expected_end_y, 1.0)


func test_fall_paper_under_an_offset_parent_still_ends_just_past_the_bottom():
	var parent: Node2D = add_child_autofree(Node2D.new())
	parent.position = Vector2(0, 400)
	var paper := Node2D.new()
	parent.add_child(paper)
	var final_y := [0.0]
	paper.tree_exiting.connect(func(): final_y[0] = paper.global_position.y)
	var expected_end_y: float = paper.get_viewport().get_visible_rect().end.y + 100.0

	await LFAnimate.fall_paper(paper, 0.05)
	assert_true(await _until_freed(paper))

	assert_almost_eq(final_y[0], expected_end_y, 1.0)


func test_fall_paper_with_a_scrolled_canvas_ends_just_past_the_visible_bottom():
	var viewport := get_viewport()
	var saved := viewport.canvas_transform
	viewport.canvas_transform = Transform2D(0.0, Vector2(0, -500)) # the view scrolled 500 px down
	var paper := Node2D.new()
	add_child(paper)
	var final_y := [0.0]
	paper.tree_exiting.connect(func(): final_y[0] = paper.global_position.y)
	var expected_end_y: float = viewport.get_visible_rect().end.y + 500.0 + 100.0

	await LFAnimate.fall_paper(paper, 0.05)
	await _until_freed(paper)
	viewport.canvas_transform = saved

	assert_almost_eq(final_y[0], expected_end_y, 1.0)


func test_fall_paper_returns_if_the_node_is_freed_mid_fall():
	var paper := Control.new()
	add_child(paper)
	var result := [null]
	var run := func():
		result[0] = await LFAnimate.fall_paper(paper, 5.0)
	run.call()
	await wait_process_frames(2)

	paper.free()

	assert_true(await _until(func() -> bool: return result[0] != null), "fall_paper must not wait forever on a tween that died with its node")
	assert_false(result[0])


func test_fall_paper_returns_false_at_once_when_the_node_leaves_the_tree_mid_fall():
	var paper := Control.new()
	add_child(paper)
	var result := [null]
	var run := func():
		result[0] = await LFAnimate.fall_paper(paper, 5.0)
	run.call()
	await wait_process_frames(2)

	remove_child(paper)
	await wait_process_frames(1)

	assert_eq(result[0], false, "returned at once, not after the fall's duration")
	assert_true(is_instance_valid(paper), "a removed node is not freed")
	add_child(paper)
	var at := paper.position
	var tilt := paper.rotation
	await wait_process_frames(5)
	assert_eq(paper.position, at, "its tweens were killed: back in the tree it no longer falls")
	assert_eq(paper.rotation, tilt)
	paper.free()


func test_fall_paper_on_an_already_freed_node_returns_false():
	var paper := Control.new()
	paper.free()

	assert_false(await LFAnimate.fall_paper(paper, 0.05))


func test_fall_paper_drops_and_frees_a_node2d_too():
	var paper := Node2D.new()
	add_child(paper)

	await LFAnimate.fall_paper(paper, 0.05)
	await get_tree().process_frame

	assert_false(is_instance_valid(paper))


# --- punch_scale -------------------------------------------------------------

func test_punch_scale_jumps_to_the_peak_about_the_centre_and_settles_back():
	var node: Control = add_child_autofree(Control.new())
	node.size = Vector2(100, 40)

	var tween := LFAnimate.punch_scale(node, 1.5, 0.3)
	assert_eq(node.scale, Vector2.ONE * 1.5)
	assert_eq(node.pivot_offset, Vector2(50, 20))
	tween.custom_step(0.35)

	assert_eq(node.scale, Vector2.ONE)


func test_punch_scale_without_center_pivot_leaves_the_pivot_alone():
	var node: Control = add_child_autofree(Control.new())
	node.size = Vector2(100, 40)
	node.pivot_offset = Vector2(3, 4)

	var tween := LFAnimate.punch_scale(node, 1.5, 0.3, false)

	assert_eq(node.pivot_offset, Vector2(3, 4))
	tween.kill()


func test_overlapping_punches_settle_at_the_true_rest_scale():
	var node: Node2D = add_child_autofree(Node2D.new())
	node.scale = Vector2(2, 2)

	var first := LFAnimate.punch_scale(node, 1.5, 0.3)
	first.custom_step(0.1)
	var second := LFAnimate.punch_scale(node, 1.5, 0.3)
	assert_false(first.is_valid(), "the earlier punch is replaced")
	assert_eq(node.scale, Vector2(3, 3), "the peak is relative to the rest scale, not the mid-punch one")
	second.custom_step(0.35)

	assert_eq(node.scale, Vector2(2, 2))


func test_a_pop_in_during_a_punch_settles_at_the_rest_scale_before_the_punch():
	var node: Control = add_child_autofree(Control.new())
	node.scale = Vector2(2, 2)
	LFAnimate.punch_scale(node, 1.5, 0.6)
	assert_eq(node.scale, Vector2(3, 3), "precondition: the punch is at its peak")

	assert_true(await LFAnimate.comics_pop_appear(node, 0.05))

	assert_eq(node.scale, Vector2(2, 2), "the pop's rest scale is the punch's rest, not its peak")


func test_a_punch_during_a_pop_in_settles_at_the_rest_scale_before_the_pop():
	var node: Node2D = add_child_autofree(Node2D.new())
	node.scale = Vector2(2, 2)
	LFAnimate.comics_pop_appear(node, 0.6)
	assert_true(await _until(func() -> bool: return node.scale.x > 2.1), "precondition: the pop is in its overshoot")

	await LFAnimate.punch_scale(node, 1.5, 0.05).finished

	assert_eq(node.scale, Vector2(2, 2), "the punch's rest scale is the pop's rest, not its mid-pop scale")


func test_punch_scale_works_on_a_node3d():
	var node: Node3D = add_child_autofree(Node3D.new())

	var tween := LFAnimate.punch_scale(node, 1.2, 0.2)
	assert_eq(node.scale, Vector3.ONE * 1.2)
	tween.custom_step(0.25)

	assert_eq(node.scale, Vector3.ONE)


func test_punch_scale_on_a_node_without_scale_returns_null():
	var node: Node = add_child_autofree(Node.new())

	assert_null(LFAnimate.punch_scale(node))


# --- one_shot ----------------------------------------------------------------

func test_one_shot_with_a_property_the_node_lacks_reports_it_and_still_frees_the_node():
	var node := Node2D.new()
	add_child(node) # one_shot frees it

	LFAnimate.one_shot(node, {"no_such_property": 1.0, "position:x": 4.0}, 0.05)

	assert_true(await _until_freed(node), "a bad path does not keep the node alive")
	assert_engine_error("no_such_property")


func test_one_shot_on_a_node_outside_the_tree_waits_until_the_node_enters_it():
	var node := Node2D.new()
	LFAnimate.one_shot(node, {"position:x": 10.0}, 0.05)
	await wait_process_frames(10)
	assert_eq(node.position.x, 0.0, "nothing runs outside the tree")
	assert_true(is_instance_valid(node))

	add_child(node)

	assert_true(await _until_freed(node), "it runs and frees the node once inside")


func test_control_with_a_property_the_node_lacks_returns_a_finished_tween_and_sets_nothing():
	var node: Control = add_child_autofree(Control.new())

	var tween := LFAnimate.control(node, "no_such_property", 1.0, 0.05)

	assert_not_null(tween, "callers that await it still get a tween")
	await tween.finished
	assert_engine_error("no_such_property")


func test_one_shot_tweens_every_property_in_parallel_then_frees_the_node():
	var node := Node3D.new()
	add_child(node) # one_shot frees it
	var at_exit := {}
	node.tree_exiting.connect(func(): at_exit["y"] = node.position.y; at_exit["scale"] = node.scale)

	LFAnimate.one_shot(node, {"position:y": 2.0, "scale": Vector3.ONE * 3.0}, 0.05)

	assert_true(await _until_freed(node), "the node frees itself when done")
	assert_almost_eq(at_exit["y"], 2.0, 0.001)
	assert_eq(at_exit["scale"], Vector3.ONE * 3.0)


func test_one_shot_reaches_into_a_resource_property():
	var node := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	node.material_override = material
	add_child(node)

	LFAnimate.one_shot(node, {"material_override:albedo_color:a": 0.0}, 0.05)

	assert_true(await _until_freed(node))
	assert_almost_eq(material.albedo_color.a, 0.0, 0.001)


func test_one_shot_returns_the_tween_bound_to_the_node():
	var node: Node3D = add_child_autofree(Node3D.new())

	var tween := LFAnimate.one_shot(node, {"position:x": 1.0}, 1.0)
	tween.pause()
	tween.custom_step(0.5)

	assert_almost_eq(node.position.x, 0.5, 0.001)
	tween.kill()


func test_one_shot_with_nothing_to_tween_still_frees_the_node_after_its_duration():
	var node := Node3D.new()
	add_child(node)

	var tween := LFAnimate.one_shot(node, {}, 1.0)
	tween.pause()
	tween.custom_step(0.9)
	await get_tree().process_frame
	assert_true(is_instance_valid(node), "not freed before the duration")
	tween.custom_step(0.2)

	assert_true(await _until_freed(node))


func test_a_one_shot_whose_tween_is_killed_never_frees_the_node():
	var node: Node3D = add_child_autofree(Node3D.new())

	var tween := LFAnimate.one_shot(node, {"position:x": 1.0}, 0.05)
	tween.kill()
	await wait_seconds(0.15)

	assert_true(is_instance_valid(node))


func test_aliased_properties_replace_each_other():
	var node: Control = add_child_autofree(Control.new())

	var degrees := LFAnimate.control(node, "rotation_degrees", 90.0, 0.4)
	LFAnimate.control(node, "rotation", 0.0, 0.4)
	assert_false(degrees.is_valid(), "rotation and rotation_degrees turn the same node")

	var global_x := LFAnimate.control(node, "global_position:x", 10.0, 0.4)
	LFAnimate.control(node, "position", Vector2.ZERO, 0.4)
	assert_false(global_x.is_valid(), "global_position and position move the same node")

	var node_2d: Node2D = add_child_autofree(Node2D.new())
	var scale := LFAnimate.control(node_2d, "scale", Vector2.ONE * 2.0, 0.4)
	var keep := LFAnimate.control(node_2d, "modulate", Color.RED, 0.4)
	LFAnimate.control(node_2d, "transform", Transform2D(), 0.4)
	assert_false(scale.is_valid(), "a transform sets the scale too")
	assert_true(keep.is_valid())
	keep.kill()


func test_a_later_animation_replaces_a_paper_fall():
	var node := Control.new()
	add_child_autofree(node)
	var result := [null]
	var fall := func() -> void: result[0] = await LFAnimate.fall_paper(node, 0.5)
	fall.call()
	await get_tree().process_frame

	LFAnimate.control(node, "position", Vector2(5, 5), 0.05)
	assert_true(await _until(func() -> bool: return result[0] != null), "the fall returns")
	assert_false(result[0], "it was cut short")
	assert_true(is_instance_valid(node), "a replaced fall does not free the node")


func test_a_zero_duration_without_replace_leaves_the_running_tween_alone():
	var node: Control = add_child_autofree(Control.new())
	var running := LFAnimate.control(node, "position:x", 100.0, 0.4)

	LFAnimate.control(node, "position", Vector2(7, 8), 0.0, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT, false)

	assert_eq(node.position, Vector2(7, 8))
	assert_true(running.is_valid(), "replace = false kills nothing")
	running.kill()


func test_the_defaults_are_the_documented_ones():
	var node: Control = add_child_autofree(Control.new())

	var punch := LFAnimate.punch_scale(node)
	assert_eq(node.scale, Vector2.ONE * LFAnimate.DEFAULT_PUNCH_PEAK)
	punch.kill()
	assert_eq([LFAnimate.DEFAULT_DURATION, LFAnimate.DEFAULT_PUNCH_PEAK, LFAnimate.DEFAULT_PUNCH_DURATION], [0.3, 1.15, 0.35])
	assert_eq([LFAnimate.DEFAULT_POP_DURATION, LFAnimate.DEFAULT_POP_OVERSHOOT, LFAnimate.DEFAULT_POP_DRIFT, LFAnimate.DEFAULT_POP_TILT_DEGREES], [0.35, 1.2, 60.0, 20.0])
	assert_eq([LFAnimate.DEFAULT_FALL_DURATION, LFAnimate.DEFAULT_FALL_DISTANCE], [0.55, 300.0])
	assert_eq([LFAnimate.DEFAULT_PAPER_DURATION, LFAnimate.DEFAULT_PAPER_SWAY_AMPLITUDE, LFAnimate.DEFAULT_PAPER_ROTATION_AMPLITUDE, LFAnimate.DEFAULT_PAPER_EXTRA_VERTICAL_MARGIN], [2.0, 100.0, 15.0, 100.0])


func test_a_control_without_a_duration_takes_the_default():
	var node: Control = add_child_autofree(Control.new())
	node.modulate.a = 0.0

	var tween := LFAnimate.control(node, "modulate:a", 1.0)
	tween.pause()
	tween.custom_step(LFAnimate.DEFAULT_DURATION / 2.0)
	assert_almost_eq(node.modulate.a, 0.5, 0.01, "halfway at half the default duration")
	tween.custom_step(LFAnimate.DEFAULT_DURATION)
	assert_almost_eq(node.modulate.a, 1.0, 0.001)


func test_every_documented_alias_replaces_its_counterpart():
	var node: Node2D = add_child_autofree(Node2D.new())
	var pairs := [
		["global_rotation", "rotation"],
		["global_rotation_degrees", "rotation_degrees"],
		["global_scale", "scale"],
		["transform", "position"],
		["transform", "rotation"],
		["transform", "skew"],
		["global_transform", "global_scale"],
		["scale", "transform"],
		["global_position:y", "global_transform"],
	]
	var values := {
		"global_rotation": 1.0, "rotation": 0.5, "global_rotation_degrees": 10.0, "rotation_degrees": 20.0,
		"global_scale": Vector2(2, 2), "scale": Vector2(3, 3), "transform": Transform2D(), "position": Vector2(1, 1),
		"skew": 0.2, "global_transform": Transform2D(), "global_position:y": 5.0,
	}
	for pair: Array in pairs:
		var first := LFAnimate.control(node, pair[0], values[pair[0]], 0.4)
		var second := LFAnimate.control(node, pair[1], values[pair[1]], 0.4)
		assert_false(first.is_valid(), "%s is replaced by %s" % pair)
		second.kill()


func test_a_transform_does_not_replace_unrelated_properties():
	var node: Node2D = add_child_autofree(Node2D.new())

	var tint := LFAnimate.control(node, "self_modulate", Color.RED, 0.4)
	var z := LFAnimate.control(node, "z_index", 3, 0.4)
	LFAnimate.control(node, "global_transform", Transform2D(), 0.4)

	assert_true(tint.is_valid())
	assert_true(z.is_valid())
	tint.kill()
	z.kill()


func test_the_pop_helpers_return_false_for_null_freed_or_3d_nodes():
	var freed := Control.new()
	freed.free()
	var node_3d: Node3D = add_child_autofree(Node3D.new())

	assert_false(await LFAnimate.comics_pop_appear(null))
	assert_false(await LFAnimate.comics_pop_appear(freed))
	assert_false(await LFAnimate.comics_pop_disappear(null))
	assert_false(await LFAnimate.comics_pop_disappear(freed))
	assert_false(await LFAnimate.comics_pop_disappear(autofree(Control.new())), "outside the tree")
	assert_false(await LFAnimate.fall_paper(node_3d, 0.02))
	assert_false(await LFAnimate.fall_paper(autofree(Node2D.new()), 0.02), "outside the tree")
	assert_true(is_instance_valid(node_3d), "a refused node is not freed")


func test_a_pop_out_on_a_node2d_falls_and_comes_back():
	var node: Node2D = add_child_autofree(Node2D.new())
	node.position = Vector2(5, 5)
	var lowest := [0.0]
	var watch := func() -> void:
		while is_instance_valid(node) and node.modulate.a > 0.0:
			lowest[0] = maxf(lowest[0], node.position.y)
			await get_tree().process_frame
	watch.call()

	assert_true(await LFAnimate.comics_pop_disappear(node, 0.1, 40.0))

	assert_gt(lowest[0], 5.0, "it dropped")
	assert_eq(node.position, Vector2(5, 5))


## The sway and wobble are separate tweens on their own paths: another helper can take
## them over while the fall goes on and still frees the node at the end.
func test_replacing_the_sway_or_wobble_does_not_stop_the_fall():
	var paper := Control.new()
	add_child(paper) # fall_paper frees it
	var result := [null]
	var fall := func() -> void: result[0] = await LFAnimate.fall_paper(paper, 0.15)
	fall.call()
	await get_tree().process_frame

	LFAnimate.control(paper, "rotation", 0.0, 0.0)
	LFAnimate.control(paper, "global_position:x", 0.0, 0.0)

	assert_true(await _until(func() -> bool: return result[0] != null))
	assert_true(result[0], "the fall still finished")
	await get_tree().process_frame # let queue_free() take effect
	assert_false(is_instance_valid(paper), "and freed the node")


## The original and its duplicate keep separate records as both keep animating: each new
## call replaces only that node's own earlier tween on the path.
func test_a_node_and_its_duplicate_replace_only_their_own_tweens_over_several_calls():
	var node: Control = add_child_autofree(Control.new())
	var first := LFAnimate.control(node, "modulate:a", 0.0, 0.4)
	var copy: Control = add_child_autofree(node.duplicate())
	var copy_first := LFAnimate.control(copy, "modulate:a", 0.5, 0.4)
	var second := LFAnimate.control(node, "modulate:a", 1.0, 0.4)
	assert_false(first.is_valid(), "the original's own earlier tween is replaced")
	assert_true(copy_first.is_valid(), "the copy's is not")
	var copy_second := LFAnimate.control(copy, "modulate", Color.RED, 0.4)
	assert_false(copy_first.is_valid(), "the copy replaces its own")
	assert_true(second.is_valid(), "and leaves the original's")
	var position := LFAnimate.control(node, "position:x", 10.0, 0.4)
	assert_true(second.is_valid(), "another path replaces nothing")
	for tween in [second, copy_second, position]:
		tween.kill()
