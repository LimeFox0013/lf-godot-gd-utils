extends GutTest

var control: LFParallaxControl
var layer_a: LFParallaxLayer
var layer_b: LFParallaxLayer

## Longer than any tween these tests start, in seconds.
const TWEEN_END_SEC := 10.0


func before_each():
	control = add_child_autofree(LFParallaxControl.new())
	# autofree (not just add_child_autofree on control): a test below detaches
	# layer_a from control before the test ends, which would otherwise leak it.
	layer_a = autofree(LFParallaxLayer.new())
	layer_a.motion_scale = Vector2(1.0, 1.0)
	layer_b = autofree(LFParallaxLayer.new())
	layer_b.motion_scale = Vector2(0.5, 0.5)
	control.add_child(layer_a)
	control.add_child(layer_b)
	control.reset()


## Steps every tween still running in the tree to its end, at once: what waiting out
## their durations would do, without depending on the frame rate.
func _finish_running_tweens() -> void:
	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.custom_step(TWEEN_END_SEC)


func test_move_scales_each_layers_offset_by_its_own_motion_scale():
	control.move(Vector2(100, 0), 0.0)
	await wait_process_frames(2)

	assert_eq(layer_a.position, Vector2(-100, 0))
	assert_eq(layer_b.position, Vector2(-50, 0))


func test_reset_does_not_pick_up_a_child_added_since_the_last_reset():
	var layer_c = LFParallaxLayer.new()
	control.add_child(layer_c)

	assert_eq(control.layers.size(), 2, "layer_c must not be tracked until reset() runs")


func test_reset_picks_up_a_child_added_since_the_last_reset_once_called():
	var layer_c = LFParallaxLayer.new()
	control.add_child(layer_c)

	control.reset()

	assert_eq(control.layers.size(), 3)
	assert_true(control.layers.has(layer_c))


func test_reset_does_not_drop_a_removed_child_until_called_again():
	control.remove_child(layer_a)

	assert_eq(control.layers.size(), 2, "layer_a must still be tracked until reset() runs")

	control.reset()

	assert_eq(control.layers.size(), 1)
	assert_false(control.layers.has(layer_a))


func test_move_by_slide_shifts_a_layer_by_whole_control_widths_plus_slide_spacing():
	control.size = Vector2(100, 50)
	control.slides = 3
	layer_a.size = Vector2(400, 50) # 100px of spacing spread over the 2 gaps

	control.move_by_slide(2, 0.0)
	await wait_process_frames(2)

	assert_eq(layer_a.position, Vector2(-300, 0))


func test_move_by_slide_with_a_single_slide_stays_at_the_origin():
	control.size = Vector2(100, 50)
	control.slides = 1
	layer_a.size = Vector2(100, 50)

	control.move_by_slide(0, 0.0)
	await wait_process_frames(2)

	assert_eq(layer_a.position, Vector2.ZERO, "one slide has no gaps to divide spacing across")


func test_a_new_move_replaces_a_running_tween_instead_of_fighting_it():
	control.move(Vector2(100, 0), 0.2)
	control.move(Vector2(200, 0), 0.0)
	_finish_running_tweens()

	assert_eq(layer_a.position, Vector2(-200, 0), "the earlier, slower tween must not land after the newer move")


func test_a_zero_duration_move_applies_immediately():
	control.move(Vector2(100, 0), 0.0)

	assert_eq(layer_a.position, Vector2(-100, 0))
	assert_eq(layer_b.position, Vector2(-50, 0))


func test_move_by_slide_updates_active_slide():
	control.size = Vector2(100, 50)
	control.slides = 3

	control.move_by_slide(2, 0.0)

	assert_eq(control.active_slide, 2)


func test_move_by_slide_aligns_the_last_slide_with_each_layers_right_edge_whatever_its_motion_scale():
	control.size = Vector2(100, 50)
	control.slides = 3
	layer_a.size = Vector2(400, 50)
	layer_b.size = Vector2(250, 50) # motion_scale 0.5 is not applied in slide mode

	control.move_by_slide(2, 0.0)
	await wait_process_frames(2)

	assert_eq(layer_a.position.x + layer_a.size.x, control.size.x)
	assert_eq(layer_b.position.x + layer_b.size.x, control.size.x)


func test_a_slide_move_replaces_a_running_shift_tween():
	control.size = Vector2(100, 50)
	control.slides = 2
	layer_a.size = Vector2(200, 50)
	control.move(Vector2(500, 0), 0.2)

	control.move_by_slide(0, 0.0)
	_finish_running_tweens()

	assert_eq(layer_a.position, Vector2.ZERO)


func test_a_freed_layer_is_skipped_and_the_others_still_move():
	layer_a.free()

	control.move(Vector2(10, 0), 0.0)

	assert_engine_error_count(0)
	assert_eq(layer_b.position, Vector2(-5, 0))
	assert_eq(control.layers, [layer_b] as Array[LFParallaxLayer], "the freed layer is dropped from the list")


func test_a_freed_layer_is_skipped_in_slide_mode():
	control.size = Vector2(100, 50)
	control.slides = 2
	layer_b.size = Vector2(200, 50)
	layer_a.free()

	control.move_by_slide(1, 0.0)

	assert_engine_error_count(0)
	assert_eq(layer_b.position.x, -100.0)


func test_reset_drops_the_running_tween_of_a_freed_layer():
	control.move(Vector2(100, 0), 5.0)
	layer_a.free()

	control.reset()

	assert_engine_error_count(0)
	assert_eq(control.layers, [layer_b] as Array[LFParallaxLayer])
	# The surviving layer's tween is still tracked, so a newer move still replaces it.
	control.move(Vector2(20, 0), 0.0)
	await wait_process_frames(2)
	assert_eq(layer_b.position, Vector2(-10, 0))


func test_slide_positions_follow_a_resize():
	control.size = Vector2(100, 50)
	control.slides = 3
	layer_a.size = Vector2(400, 50)
	control.move_by_slide(2, 0.0)

	control.size = Vector2(200, 50)

	assert_eq(layer_a.position.x + layer_a.size.x, control.size.x, "the last slide still aligns the right edges")


func test_the_slide_index_is_clamped_to_the_slide_count():
	control.size = Vector2(100, 50)
	control.slides = 3
	layer_a.size = Vector2(400, 50)

	control.move_by_slide(5, 0.0)
	assert_eq(control.active_slide, 2)
	assert_eq(layer_a.position.x, -300.0)

	control.move_by_slide(-1, 0.0)
	assert_eq(control.active_slide, 0)
	assert_eq(layer_a.position.x, 0.0)


func test_move_by_slide_keeps_each_layers_y():
	control.size = Vector2(100, 50)
	control.slides = 2
	layer_a.size = Vector2(200, 50)
	layer_a.position = Vector2(0, 30)

	control.move_by_slide(1, 0.0)
	assert_eq(layer_a.position, Vector2(-100, 30))

	control.move_by_slide(0, 0.1)
	_finish_running_tweens()
	assert_eq(layer_a.position, Vector2(0, 30))


func test_a_layer_outside_the_tree_is_placed_at_once():
	control.remove_child(layer_a)

	control.move(Vector2(10, 0), 0.1)

	assert_eq(layer_a.position, Vector2(-10, 0))


func test_a_non_finite_shift_is_rejected():
	control.move(Vector2(10, 0), 0.0)

	control.move(Vector2(NAN, 0), 0.0)
	control.move(Vector2(INF, 0), 0.0)

	assert_push_error_count(2)
	assert_eq(layer_a.position, Vector2(-10, 0))
	assert_eq(control.shift, Vector2(10, 0))


func test_move_records_the_shift():
	control.move(Vector2(40, 10), 0.0)

	assert_eq(control.shift, Vector2(40, 10))


func test_the_default_duration_tweens_rather_than_jumping():
	assert_gt(LFParallaxControl.DEFAULT_DURATION, 0.0, "the default duration is a tween, not a jump")
	control.move(Vector2(100, 0))

	assert_eq(layer_a.position, Vector2.ZERO, "nothing moves before the first frame")
	_finish_running_tweens()
	assert_eq(layer_a.position, Vector2(-100, 0))


func test_a_preset_active_slide_is_applied_on_ready():
	var preset := LFParallaxControl.new()
	preset.size = Vector2(100, 50)
	preset.slides = 2
	preset.active_slide = 1
	var layer := LFParallaxLayer.new()
	layer.size = Vector2(200, 50)
	preset.add_child(layer)

	add_child_autofree(preset)

	assert_eq(layer.position.x, -100.0)


func test_a_resize_after_a_shift_move_leaves_the_layers_alone():
	control.size = Vector2(100, 50)
	control.slides = 3
	layer_a.size = Vector2(400, 50)
	control.move(Vector2(20, 0), 0.0)

	control.size = Vector2(200, 50)

	assert_eq(layer_a.position, Vector2(-20, 0), "only slide mode follows the size")


func test_move_without_a_shift_reapplies_the_last_one_to_newly_tracked_layers():
	control.move(Vector2(30, 0), 0.0)
	var layer_c := LFParallaxLayer.new()
	layer_c.motion_scale = Vector2(2, 2)
	control.add_child(layer_c)
	control.reset()

	control.move()
	_finish_running_tweens()

	assert_eq(layer_c.position, Vector2(-60, 0))
	assert_eq(layer_a.position, Vector2(-30, 0))


func test_move_by_slide_leaves_the_recorded_shift_alone():
	control.move(Vector2(15, 5), 0.0)
	control.slides = 2

	control.move_by_slide(1, 0.0)

	assert_eq(control.shift, Vector2(15, 5))


func test_move_by_slide_without_slides_stays_on_slide_zero():
	control.size = Vector2(100, 50)
	layer_a.size = Vector2(300, 50)

	control.move_by_slide(3, 0.0)

	assert_eq(control.active_slide, 0)
	assert_eq(layer_a.position.x, 0.0)


func test_a_layer_moves_at_full_speed_by_default():
	var layer: LFParallaxLayer = autofree(LFParallaxLayer.new())
	assert_eq(layer.motion_scale, Vector2.ONE)


func test_a_resize_during_a_slide_tween_cuts_it_short_at_the_new_position():
	control.size = Vector2(100, 50)
	control.slides = 3
	layer_a.size = Vector2(400, 50)
	control.move_by_slide(2, 1.0)

	control.size = Vector2(200, 50)
	assert_eq(layer_a.position.x, -200.0, "placed at once for the new size")
	_finish_running_tweens()

	assert_eq(layer_a.position.x, -200.0, "the tween toward the old size's position no longer runs")
