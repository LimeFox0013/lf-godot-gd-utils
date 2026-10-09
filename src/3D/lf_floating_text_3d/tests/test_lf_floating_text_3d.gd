extends GutTest

## Pop-up text: spawned above the given point, rises while it fades (the whole label,
## outline included) and frees itself.


func test_the_text_rises_fades_and_frees_itself():
	var parent: Node3D = add_child_autofree(Node3D.new())
	var label := LFFloatingText3D.spawn(parent, Vector3(1, 0, 2), "value", Color.YELLOW)
	assert_eq(parent.get_child(0), label)
	assert_eq(label.text, "value")
	assert_eq(label.modulate, Color.YELLOW)
	var start := label.position
	assert_eq(start, Vector3(1, 1.2, 2), "the default height above the point")
	var at_exit := {}
	label.tree_exiting.connect(func(): at_exit["position"] = label.position; at_exit["transparency"] = label.transparency)

	assert_true(await _freed(label), "the text frees itself when done")

	assert_almost_eq(at_exit["position"].y, start.y + 1.0, 0.001, "risen by the default rise")
	assert_almost_eq(at_exit["transparency"], 1.0, 0.001, "faded by transparency, outline included")


func test_the_label_is_a_camera_facing_overlay():
	var parent: Node3D = add_child_autofree(Node3D.new())
	var label := LFFloatingText3D.spawn(parent, Vector3.ZERO, "text_a", Color.WHITE)
	assert_eq(label.billboard, BaseMaterial3D.BILLBOARD_ENABLED)
	assert_true(label.no_depth_test)
	assert_eq(label.font_size, LFFloatingText3D.DEFAULT_FONT_SIZE)
	assert_eq(label.outline_size, LFFloatingText3D.DEFAULT_OUTLINE_SIZE)
	assert_true(await _freed(label))


func test_rise_height_size_and_duration_can_be_set():
	var parent: Node3D = add_child_autofree(Node3D.new())
	var before := get_tree().get_processed_tweens()
	var label := LFFloatingText3D.spawn(parent, Vector3.ZERO, "+5", Color.GREEN, 3.0, 0.1, 2.0, 20, 2)
	var tween := _new_tween(before)
	tween.pause()
	assert_eq(label.position, Vector3(0, 2, 0))
	assert_eq(label.font_size, 20)
	assert_eq(label.outline_size, 2)

	tween.custom_step(0.05)
	assert_almost_eq(label.position.y, 3.5, 0.001, "halfway through the 0.1 s, half the 3.0 rise")
	assert_false(label.is_queued_for_deletion())
	tween.custom_step(0.05)
	assert_almost_eq(label.position.y, 5.0, 0.001)
	assert_true(label.is_queued_for_deletion(), "done after its 0.1 s")


func test_a_zero_duration_frees_the_label_right_away():
	var parent: Node3D = add_child_autofree(Node3D.new())
	var label := LFFloatingText3D.spawn(parent, Vector3.ZERO, "x", Color.WHITE, 1.0, 0.0)
	assert_true(await _freed(label))


func test_the_label_waits_while_its_parent_is_outside_the_tree():
	var parent := Node3D.new()
	var label := LFFloatingText3D.spawn(parent, Vector3.ZERO, "x", Color.WHITE, 1.0, 0.05)
	await _advance_game_time(0.3)
	assert_true(is_instance_valid(label), "not animated outside the tree")
	assert_eq(label.transparency, 0.0)
	add_child_autofree(parent)
	assert_true(await _freed(label), "runs once the parent enters the tree")


func test_freeing_the_parent_mid_animation_frees_the_label_without_errors():
	var parent: Node3D = add_child_autofree(Node3D.new())
	var label := LFFloatingText3D.spawn(parent, Vector3.ZERO, "x", Color.WHITE, 1.0, 0.5)
	await get_tree().process_frame
	assert_true(is_instance_valid(label), "precondition: still animating")
	parent.free()
	assert_false(is_instance_valid(label), "the label lives and dies with its parent")
	await _advance_game_time(0.7)
	assert_engine_error_count(0)


func test_the_returned_label_is_a_floating_text():
	var parent: Node3D = add_child_autofree(Node3D.new())
	var label := LFFloatingText3D.spawn(parent, Vector3.ZERO, "x", Color.WHITE)
	assert_true(label is LFFloatingText3D)
	assert_true(await _freed(label))


## Waits process frames until `object` is freed; false when it is still alive after
## 3 seconds of process time (the time its tween counts).
func _freed(object: Object) -> bool:
	var ref: WeakRef = weakref(object)
	var elapsed := 0.0
	while ref.get_ref() != null:
		if elapsed > 3.0:
			return false
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return true


## The tween started since `before` was read (there must be exactly one).
func _new_tween(before: Array[Tween]) -> Tween:
	var started := get_tree().get_processed_tweens().filter(func(tween: Tween) -> bool: return not before.has(tween))
	assert_eq(started.size(), 1, "one tween started")
	return started[0]


## Waits process frames until timers and tweens have advanced by at least `seconds` of
## process time, however fast or slow the frames come. (`process_frame` fires before the
## frame's nodes process, so one more frame lets the last counted delta reach them.)
func _advance_game_time(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	await get_tree().process_frame
