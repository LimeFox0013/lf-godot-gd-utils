extends GutTest

const FRAME := 1.0 / 60.0

var buffer: LFInputBuffer


func before_each():
	buffer = LFInputBuffer.new()


func test_take_after_a_press_is_true_once():
	buffer.press()
	assert_true(buffer.take())
	assert_false(buffer.take())


func test_take_with_nothing_pending_is_false():
	assert_false(buffer.take())


func test_pending_reflects_the_state():
	assert_false(buffer.pending)
	buffer.press()
	assert_true(buffer.pending)
	buffer.take()
	assert_false(buffer.pending)


func test_expires_on_the_fifth_tick_of_a_sixtieth_with_a_window_of_0_08():
	buffer.press()
	for i in 4:
		assert_false(buffer.tick(FRAME), 'tick %d' % (i + 1))
	assert_true(buffer.tick(FRAME))
	assert_false(buffer.pending)


func test_expiry_is_reported_only_once():
	buffer.press()
	assert_true(buffer.tick(1.0))
	assert_false(buffer.tick(1.0))


func test_a_take_before_expiry_cancels_the_expiry():
	buffer.press()
	buffer.tick(FRAME)
	buffer.take()
	assert_false(buffer.tick(1.0))


func test_a_second_press_restarts_the_window():
	buffer.press()
	for i in 4:
		buffer.tick(FRAME)
	buffer.press()
	for i in 4:
		assert_false(buffer.tick(FRAME))
	assert_true(buffer.tick(FRAME))


func test_clear_drops_the_press_without_an_expiry_report():
	buffer.press()
	buffer.clear()
	assert_false(buffer.pending)
	assert_false(buffer.take())
	assert_false(buffer.tick(1.0))


func test_tick_with_nothing_pending_is_false():
	assert_false(buffer.tick(1.0))


func test_a_window_at_or_below_zero_falls_back_with_a_report():
	buffer = LFInputBuffer.new(0.0)
	assert_push_error_count(1)
	assert_eq(buffer.window, LFInputBuffer.DEFAULT_WINDOW)


func test_nan_and_infinite_windows_fall_back_with_a_report():
	buffer = LFInputBuffer.new(NAN)
	buffer = LFInputBuffer.new(INF)
	assert_push_error_count(2)
	assert_eq(buffer.window, LFInputBuffer.DEFAULT_WINDOW)


func test_a_custom_window_is_used():
	buffer = LFInputBuffer.new(0.5)
	buffer.press()
	assert_false(buffer.tick(0.4))
	assert_true(buffer.tick(0.1))


func test_negative_and_nan_delta_change_nothing():
	buffer.press()
	assert_false(buffer.tick(-1.0))
	assert_false(buffer.tick(NAN))
	assert_true(buffer.pending)
	for i in 4:
		buffer.tick(FRAME)
	assert_true(buffer.tick(FRAME), 'the bad deltas aged nothing')
