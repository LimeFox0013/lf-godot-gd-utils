extends GutTest

## A press that moves no further than the threshold is a tap; one that moves past it is a
## drag until released.

## The threshold the shared tracker uses, in pixels.
const THRESHOLD := 6.0

var drag: LFDragTracker


func before_each():
	drag = LFDragTracker.new(THRESHOLD)


func test_the_default_threshold_is_six_pixels():
	assert_eq(LFDragTracker.new().threshold, LFDragTracker.DEFAULT_THRESHOLD)
	assert_eq(LFDragTracker.DEFAULT_THRESHOLD, 6.0)


func test_a_press_released_in_place_is_a_tap():
	drag.press(Vector2(100, 100))

	assert_true(drag.pressed)
	assert_eq(drag.down_position, Vector2(100, 100))
	assert_true(drag.release())
	assert_false(drag.pressed)


func test_moving_within_the_threshold_is_still_a_tap():
	drag.press(Vector2(100, 100))

	assert_false(drag.move(Vector2(106, 100)), 'exactly the threshold is not past it')
	assert_true(drag.release())


func test_moving_past_the_threshold_drags_until_release_even_back_over_the_start():
	drag.press(Vector2(100, 100))

	assert_true(drag.move(Vector2(107, 100)))
	assert_true(drag.move(Vector2(100, 100)), 'once dragging, coming back does not make it a tap')
	assert_true(drag.dragged)
	assert_false(drag.release())


func test_moving_with_the_button_up_is_never_a_drag():
	assert_false(drag.move(Vector2(500, 500)))

	drag.press(Vector2(0, 0))
	drag.move(Vector2(50, 0))
	drag.release()

	assert_false(drag.move(Vector2(100, 0)), 'released')


func test_a_new_press_starts_a_fresh_tap():
	drag.press(Vector2(0, 0))
	drag.move(Vector2(50, 0))
	drag.release()

	drag.press(Vector2(50, 0))

	assert_false(drag.dragged)
	assert_true(drag.release())


func test_the_threshold_given_to_the_constructor_is_used_and_may_change():
	var wide := LFDragTracker.new(20.0)
	wide.press(Vector2.ZERO)

	assert_eq(wide.threshold, 20.0)
	assert_false(wide.move(Vector2(15, 0)), 'within 20 px')

	wide.threshold = 10.0

	assert_true(wide.move(Vector2(15, 0)), 'past the new threshold')


func test_a_release_without_a_press_is_not_a_tap():
	assert_false(drag.release(), 'the press went elsewhere (a UI control, another window)')

	drag.press(Vector2.ZERO)
	drag.release()

	assert_false(drag.release(), 'a second release of the same press is not another tap')
