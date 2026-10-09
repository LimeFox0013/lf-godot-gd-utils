extends GutTest

var pager: LFCarousel
var slide_a: LFCarouselPage
var slide_b: LFCarouselPage


func before_each():
	pager = LFCarousel.new()
	pager.auto_setup = false
	slide_a = LFCarouselPage.new()
	slide_a.name = "A"
	slide_b = LFCarouselPage.new()
	slide_b.name = "B"
	pager.add_child(slide_a)
	pager.add_child(slide_b)
	add_child_autofree(pager)
	pager.setup("A")


func test_setup_leaves_exactly_one_slide_visible_at_rest():
	assert_true(slide_a.visible)
	assert_false(slide_b.visible)


func test_slides_are_switched_by_node_name():
	pager.slide_fn = func(_s, _n): pass # trivial swappable strategy
	await pager.activate_slide("B")

	assert_eq(pager.current_slide, "B")


func test_outgoing_slide_is_only_hidden_after_the_transition_completes():
	# Boxed (Array): a lambda captures locals BY VALUE in GDScript, so a plain
	# bool reassigned inside the lambda would only mutate its own copy.
	var was_still_visible_during_transition := [false]
	pager.slide_fn = func(s: LFCarousel, _next_name: String):
		# activate_slide has already emitted slide_switch_started and reassigned
		# z_index by this point — but must not have hidden A yet.
		was_still_visible_during_transition[0] = slide_a.visible
		s.set_slide_state(s.current_slide, false)

	await pager.activate_slide("B")

	assert_true(was_still_visible_during_transition[0])
	assert_false(slide_a.visible)


func test_activation_signal_fires_regardless_of_which_transition_strategy_is_plugged_in():
	var changed := []
	pager.slide_changed.connect(func(page_name): changed.append(page_name))
	var strategies := [
		func(_s, _n): pass, # does nothing itself
		LFCarousel.x_shift_out, # the default, tweened
		func(s: LFCarousel, n: String): s.set_slide_state(n, true), # instant cut
	]

	for strategy: Callable in strategies:
		pager.slide_fn = strategy
		var target := "A" if pager.current_slide == "B" else "B"
		await pager.activate_slide(target)
		assert_eq(pager.current_slide, target)

	assert_eq(changed, ["B", "A", "B"])


func test_activating_the_current_slide_is_a_noop():
	var switch_fired := [false]
	pager.slide_switch_started.connect(func(_f, _t): switch_fired[0] = true)

	await pager.activate_slide("A")

	assert_false(switch_fired[0])


func test_default_transition_strategy_switches_slides_end_to_end():
	await pager.activate_slide("B")

	assert_eq(pager.current_slide, "B")
	assert_true(slide_b.visible)
	assert_false(slide_a.visible)


func test_x_shift_out_hides_the_outgoing_page_of_the_carousel_it_is_given():
	var other: LFCarousel = LFCarousel.new()
	other.auto_setup = false
	var other_a := LFCarouselPage.new()
	other_a.name = "A"
	var other_b := LFCarouselPage.new()
	other_b.name = "B"
	other.add_child(other_a)
	other.add_child(other_b)
	add_child_autofree(other)
	other.setup("A")

	await LFCarousel.x_shift_out(other, "B")

	assert_false(other_a.visible, "the passed carousel's outgoing page must be hidden")
	assert_true(slide_a.visible, "the other carousel must be left alone")


func test_setup_puts_every_slide_back_at_the_origin():
	pager.size = Vector2(100, 50)
	await pager.activate_slide("B") # the default strategy leaves A shifted out
	assert_ne(slide_a.position, Vector2.ZERO, "precondition: the switch moved A")

	pager.setup("A")

	assert_eq(slide_a.position, Vector2.ZERO)
	assert_eq(slide_b.position, Vector2.ZERO)


func test_activating_an_unknown_slide_warns_and_changes_nothing():
	var switch_fired := [false]
	pager.slide_switch_started.connect(func(_f, _t): switch_fired[0] = true)

	await pager.activate_slide("Missing")

	assert_push_warning("Missing")
	assert_engine_error_count(0, "an unknown name must not raise a script error")
	assert_eq(pager.current_slide, "A")
	assert_false(switch_fired[0])


func test_a_switch_requested_while_one_is_running_is_ignored():
	var slide_c := LFCarouselPage.new()
	slide_c.name = "C"
	pager.add_child(slide_c)
	pager.setup("A")
	var gate := [false]
	pager.slide_fn = func(s: LFCarousel, _next: String):
		while not gate[0]:
			await get_tree().process_frame
		s.set_slide_state(s.current_slide, false)
	var started := []
	pager.slide_switch_started.connect(func(_f, t): started.append(t))

	pager.activate_slide("B") # not awaited: still running
	pager.activate_slide("C")
	gate[0] = true
	await wait_process_frames(3)

	assert_eq(started, ["B"], "the second request must not start a concurrent switch")
	assert_eq(pager.current_slide, "B")
	assert_false(pager.is_switching)


func test_move_slide_with_an_explicit_zero_from_jumps_to_the_origin():
	slide_b.position = Vector2(50, 0)

	await pager.move_slide("B", Vector2(10, 0), Vector2.ZERO, 0.0)

	assert_eq(slide_b.position, Vector2(10, 0))
	# The jump is observable through a tween that starts from it:
	slide_b.position = Vector2(50, 0)
	pager.move_slide("B", Vector2(100, 0), Vector2.ZERO, 10.0)
	assert_eq(slide_b.position, Vector2.ZERO, "Vector2.ZERO is a real start position, not 'no jump'")


func test_move_slide_without_from_starts_where_the_slide_is():
	slide_b.position = Vector2(50, 0)

	pager.move_slide("B", Vector2(100, 0), null, 10.0)

	assert_eq(slide_b.position, Vector2(50, 0))


## The tween `move_slide` just started, paused so the test steps it by hand.
func _held_tween() -> Tween:
	var tween: Tween = pager._tweens.back()
	tween.pause()
	return tween


func test_move_slide_eases_along_the_given_transition():
	pager.move_slide("B", Vector2(100, 0), Vector2.ZERO, 1.0, Tween.TRANS_QUAD, Tween.EASE_IN)

	_held_tween().custom_step(0.5)

	# Halfway through, linear motion is at 50; a quadratic ease-in at 0.5² x 100 = 25.
	assert_almost_eq(slide_b.position.x, 25.0, 0.01, "the ease shapes the motion once a curve is chosen")


func test_move_slide_moves_linearly_by_default():
	pager.move_slide("B", Vector2(100, 0), Vector2.ZERO, 1.0)

	_held_tween().custom_step(0.5)

	assert_almost_eq(slide_b.position.x, 50.0, 0.01)


func test_move_slide_takes_an_easing_and_still_arrives():
	slide_b.position = Vector2.ZERO

	await pager.move_slide("B", Vector2(100, 0), null, 0.05, Tween.TRANS_LINEAR, Tween.EASE_OUT)

	assert_eq(slide_b.position, Vector2(100, 0))
	assert_true(slide_b.visible)


func test_move_slide_defaults_to_a_short_tween():
	assert_lt(LFCarousel.DEFAULT_TWEEN_DURATION, 1.0, "the default duration must be UI-short")
	await pager.move_slide("B", Vector2(10, 0))

	assert_eq(slide_b.position, Vector2(10, 0))


func _visible_pages(carousel: LFCarousel) -> Array:
	var names := []
	for child in carousel.get_children():
		if child is Control and child.visible:
			names.append(String(child.name))
	return names


## Waits process frames while `carousel` is switching, for at most `seconds` of process
## time (what its tweens advance by), so a slow machine does not end the wait early.
func _wait_until_idle(carousel: LFCarousel, seconds := 2.0) -> void:
	var elapsed := 0.0
	while carousel.is_switching and elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## Waits process frames until tweens have advanced by at least `seconds` of process time,
## however fast or slow the frames come. (`process_frame` fires before the frame's nodes
## process, so one more frame lets the last counted delta reach them.)
func _advance_game_time(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	await get_tree().process_frame


func _three_page_carousel() -> LFCarousel:
	var carousel := LFCarousel.new()
	carousel.auto_setup = false
	carousel.size = Vector2(100, 50)
	for page_name in ["A", "B", "C"]:
		var page := LFCarouselPage.new()
		page.name = page_name
		carousel.add_child(page)
	add_child_autofree(carousel)
	carousel.setup()
	return carousel


func test_setup_with_an_unknown_name_warns_and_shows_the_first_page():
	pager.setup("Nope")

	assert_push_warning("Nope")
	assert_eq(pager.current_slide, "A")
	assert_eq(_visible_pages(pager), ["A"])


func test_a_switch_after_setup_with_an_unknown_name_still_works():
	pager.setup("Nope")

	await pager.activate_slide("B")

	assert_false(pager.is_switching)
	assert_eq(pager.current_slide, "B")
	assert_eq(_visible_pages(pager), ["B"])


func test_setup_without_pages_leaves_no_current_page():
	var empty := LFCarousel.new()
	empty.auto_setup = false
	add_child_autofree(empty)

	empty.setup()

	assert_eq(empty.current_slide, "")
	assert_eq(empty.slides_order, [] as Array[String])


func test_any_control_child_is_a_page():
	var plain := Control.new()
	plain.name = "Plain"
	pager.add_child(plain)
	pager.setup("A")

	assert_eq(pager.slides_order, ["A", "B", "Plain"] as Array[String])
	assert_false(plain.visible)

	await pager.activate_slide("Plain")

	assert_eq(pager.current_slide, "Plain")
	assert_eq(_visible_pages(pager), ["Plain"])


func test_children_that_are_not_controls_are_not_pages():
	var helper := Node.new()
	helper.name = "Helper"
	pager.add_child(helper)

	pager.setup("A")

	assert_false(pager.slides_map.has("Helper"))


func test_auto_setup_shows_the_first_page_on_ready():
	var carousel := LFCarousel.new()
	var first := LFCarouselPage.new()
	first.name = "First"
	var second := LFCarouselPage.new()
	second.name = "Second"
	carousel.add_child(first)
	carousel.add_child(second)

	add_child_autofree(carousel)

	assert_eq(carousel.current_slide, "First")
	assert_eq(_visible_pages(carousel), ["First"])


func test_freeing_the_outgoing_page_mid_switch_still_ends_the_switch():
	var carousel := _three_page_carousel()
	carousel.activate_slide("B")
	await get_tree().process_frame

	carousel.get_node("A").free()
	await _wait_until_idle(carousel)

	assert_false(carousel.is_switching)
	assert_eq(carousel.current_slide, "B")
	assert_eq(_visible_pages(carousel), ["B"])


func test_freeing_the_incoming_page_mid_switch_ends_the_switch_on_the_old_page():
	var carousel := _three_page_carousel()
	carousel.activate_slide("B")
	await get_tree().process_frame

	carousel.get_node("B").free()
	await _wait_until_idle(carousel)

	assert_false(carousel.is_switching)
	assert_eq(carousel.current_slide, "A")
	assert_eq(_visible_pages(carousel), ["A"])


func test_setup_during_a_switch_ends_it_and_shows_only_the_page_it_names():
	var carousel := _three_page_carousel()
	var changed := []
	carousel.slide_changed.connect(func(page_name): changed.append(page_name))
	carousel.activate_slide("C")
	await get_tree().process_frame

	carousel.setup("A")

	assert_false(carousel.is_switching, "setup must end a running switch at once")
	await _advance_game_time(2.0 * LFCarousel.DEFAULT_TWEEN_DURATION) # past where the cancelled switch would end
	assert_eq(carousel.current_slide, "A")
	assert_eq(_visible_pages(carousel), ["A"])
	assert_eq(carousel.get_node("A").position, Vector2.ZERO)
	assert_eq(changed, [], "the cancelled switch must not report a change")


func test_a_switch_works_again_after_setup_cancelled_one():
	var carousel := _three_page_carousel()
	carousel.activate_slide("C")
	await get_tree().process_frame
	carousel.setup("A")

	await carousel.activate_slide("B")

	assert_eq(carousel.current_slide, "B")
	assert_eq(_visible_pages(carousel), ["B"])


func test_a_strategy_that_does_not_hide_the_outgoing_page_still_leaves_one_page_visible():
	pager.slide_fn = func(s: LFCarousel, next_name: String): s.set_slide_state(next_name, true)

	await pager.activate_slide("B")

	assert_eq(_visible_pages(pager), ["B"])


func test_set_slide_state_and_move_slide_warn_on_an_unknown_name():
	pager.set_slide_state("Missing", true)
	await pager.move_slide("Missing", Vector2.ZERO, null, 0.0)

	assert_push_warning_count(2)
	assert_engine_error_count(0)


func test_x_shift_out_moves_forward_pages_in_from_the_right_and_backward_from_the_left():
	var carousel := _three_page_carousel()
	carousel.activate_slide("C")
	await get_tree().process_frame
	var c_x: float = carousel.get_node("C").position.x
	await _wait_until_idle(carousel)
	assert_gt(c_x, 0.0, "a later page comes in from the right")

	carousel.activate_slide("A")
	await get_tree().process_frame
	var a_x: float = carousel.get_node("A").position.x
	await _wait_until_idle(carousel)
	assert_lt(a_x, 0.0, "an earlier page comes in from the left")


func test_switching_away_from_a_freed_current_page_shows_the_new_one():
	slide_a.free()

	await pager.activate_slide("B")

	assert_false(pager.is_switching)
	assert_eq(pager.current_slide, "B")
	assert_true(slide_b.visible)


func test_set_slide_state_shows_a_page_on_top_and_hides_it_below():
	pager.set_slide_state("B", true)

	assert_true(slide_b.visible)
	assert_eq(slide_b.z_index, 1)

	pager.set_slide_state("B", false)

	assert_false(slide_b.visible)
	assert_eq(slide_b.z_index, 0)


func test_without_auto_setup_pages_are_left_alone_until_setup():
	var carousel := LFCarousel.new()
	carousel.auto_setup = false
	var first := LFCarouselPage.new()
	first.name = "First"
	first.position = Vector2(30, 0)
	var second := LFCarouselPage.new()
	second.name = "Second"
	carousel.add_child(first)
	carousel.add_child(second)

	add_child_autofree(carousel)

	assert_eq(carousel.current_slide, "")
	assert_eq(carousel.get_slide_index("First"), -1, "no page map yet")
	assert_eq(_visible_pages(carousel), ["First", "Second"], "nothing hidden")
	assert_eq(first.position, Vector2(30, 0), "nothing moved")

	carousel.setup()

	assert_eq(carousel.current_slide, "First")
	assert_eq(_visible_pages(carousel), ["First"])


func test_a_switch_reports_its_ends_and_is_busy_while_it_runs():
	var busy := [false]
	pager.slide_fn = func(s: LFCarousel, _next: String): busy[0] = s.is_switching
	var started := []
	pager.slide_switch_started.connect(func(from, to): started.append([from, to]))

	await pager.activate_slide("B")

	assert_eq(started, [["A", "B"]])
	assert_true(busy[0])
	assert_false(pager.is_switching)
	assert_eq(pager.get_slide_index("B"), 1)
	assert_eq(pager.slides_map["B"], slide_b)


func test_setup_called_from_slide_switch_started_cancels_the_switch_before_anything_moves():
	var carousel := _three_page_carousel()
	var ran := [false]
	carousel.slide_fn = func(c: LFCarousel, next_name: String) -> void:
		ran[0] = true
		await LFCarousel.x_shift_out(c, next_name)
	carousel.slide_switch_started.connect(func(_from, _to): carousel.setup("A"), CONNECT_ONE_SHOT)

	await carousel.activate_slide("C")

	assert_false(ran[0], "a switch cancelled by its own start signal never runs its transition")
	assert_false(carousel.is_switching)
	assert_eq(carousel.current_slide, "A")
	assert_eq(_visible_pages(carousel), ["A"])
	assert_eq(carousel.get_node("A").position, Vector2.ZERO)


func test_freeing_both_pages_mid_switch_falls_back_to_the_first_surviving_page():
	var carousel := _three_page_carousel()
	var changed := []
	carousel.slide_changed.connect(func(page_name): changed.append(page_name))
	carousel.activate_slide("B")
	await get_tree().process_frame

	carousel.get_node("A").free()
	carousel.get_node("B").free()
	await _wait_until_idle(carousel)

	assert_false(carousel.is_switching)
	assert_eq(carousel.current_slide, "C")
	assert_eq(_visible_pages(carousel), ["C"])
	assert_eq(changed, ["C"], "the fallback page is reported as the new one")


func test_a_switch_whose_incoming_page_was_freed_reports_no_change():
	var carousel := _three_page_carousel()
	var changed := []
	carousel.slide_changed.connect(func(page_name): changed.append(page_name))
	carousel.activate_slide("B")
	await get_tree().process_frame

	carousel.get_node("B").free()
	await _wait_until_idle(carousel)

	assert_eq(changed, [], "the carousel stayed on the old page, so nothing changed")


func test_switching_away_from_a_freed_current_page_reports_the_change_without_a_transition():
	var started := []
	var changed := []
	pager.slide_switch_started.connect(func(from, to): started.append([from, to]))
	pager.slide_changed.connect(func(page_name): changed.append(page_name))
	var ran := [false]
	pager.slide_fn = func(_c, _n): ran[0] = true
	slide_a.free()

	await pager.activate_slide("B")

	assert_false(ran[0], "with nothing to transition from, the page is shown at once")
	assert_eq(started, [])
	assert_eq(changed, ["B"])


func test_setup_without_a_name_keeps_the_current_page_and_resets_positions():
	pager.slide_fn = func(_c, _n): pass
	await pager.activate_slide("B")
	slide_b.position = Vector2(40, 0)
	slide_a.visible = true

	pager.setup()

	assert_eq(pager.current_slide, "B")
	assert_eq(_visible_pages(pager), ["B"])
	assert_eq(slide_b.position, Vector2.ZERO)
	assert_eq(slide_b.z_index, 1)
	assert_eq(slide_a.z_index, 0)


func test_move_slide_shows_a_hidden_page():
	assert_false(slide_b.visible)

	await pager.move_slide("B", Vector2(5, 0), null, 0.0)

	assert_true(slide_b.visible)
	assert_eq(slide_b.position, Vector2(5, 0))


func test_a_running_move_slide_returns_when_setup_ends_its_tween():
	var done := [false]
	var run := func() -> void:
		await pager.move_slide("B", Vector2(100, 0), Vector2.ZERO, 10.0)
		done[0] = true
	run.call()
	await get_tree().process_frame
	assert_false(done[0])

	pager.setup("A")

	assert_true(done[0], "setup jumps the tween to its end, so the awaiting coroutine returns")
	assert_eq(slide_b.position, Vector2.ZERO, "setup puts the page back at the origin after the jump")


func test_get_slide_index_of_an_unknown_page_is_minus_one():
	assert_eq(pager.get_slide_index("A"), 0)
	assert_eq(pager.get_slide_index("Missing"), -1)


func test_an_invalid_transition_is_reported_and_leaves_the_carousel_free():
	pager.slide_fn = Callable()

	await pager.activate_slide("B")

	assert_false(pager.is_switching)
	assert_eq(pager.current_slide, "A")
	assert_push_error("slide_fn")


func test_a_carousel_outside_the_tree_switches_at_once():
	var loose := LFCarousel.new()
	loose.auto_setup = false
	var page_a := LFCarouselPage.new()
	page_a.name = "A"
	var page_b := LFCarouselPage.new()
	page_b.name = "B"
	loose.add_child(page_a)
	loose.add_child(page_b)
	loose.setup("A")
	autofree(loose)

	await loose.activate_slide("B")

	assert_eq(loose.current_slide, "B")
	assert_false(loose.is_switching)
	assert_true(page_b.visible)
	assert_false(page_a.visible)
