extends GutTest

## Tolerance for comparing accumulated float seconds.
const EPSILON := 0.0001

func test_fires_once_the_interval_is_reached_and_carries_the_overshoot():
	var timer := LFIntervalTimer.new(1.0)

	assert_false(timer.tick(0.6))
	assert_true(timer.tick(0.6))
	assert_almost_eq(timer.elapsed, 0.2, EPSILON)
	assert_almost_eq(timer.time_left(), 0.8, EPSILON)


func test_a_long_delta_fires_once_per_call_and_the_carry_catches_up_later():
	var timer := LFIntervalTimer.new(1.0)

	assert_true(timer.tick(3.5), 'one fire for the call')
	assert_almost_eq(timer.elapsed, 2.5, EPSILON)
	assert_true(timer.tick(0.0))
	assert_true(timer.tick(0.0))
	assert_false(timer.tick(0.0))


func test_without_carry_a_fire_restarts_from_zero():
	var timer := LFIntervalTimer.new(1.0, false)

	timer.tick(1.4)

	assert_eq(timer.elapsed, 0.0)


func test_a_changed_interval_and_a_reset_apply_from_the_next_tick():
	var timer := LFIntervalTimer.new(5.0)
	timer.tick(2.0)

	timer.interval = 1.0
	assert_true(timer.tick(0.0))

	timer.tick(0.5)
	timer.restart()
	assert_eq(timer.time_left(), 1.0)


func test_a_non_positive_interval_fires_every_call_without_banking_time():
	# Nothing is banked while the interval is not positive, so a later positive interval
	# starts from zero rather than firing on time accumulated meanwhile.
	var timer := LFIntervalTimer.new(0.0)

	assert_true(timer.tick(5.0), 'a zero interval fires on every call')
	assert_eq(timer.elapsed, 0.0, 'nothing is banked while the interval is not positive')
	timer.interval = -1.0
	assert_true(timer.tick(3.0))
	assert_eq(timer.elapsed, 0.0)

	timer.interval = 2.0
	assert_false(timer.tick(0.5), 'the first positive interval starts from zero')
	assert_almost_eq(timer.time_left(), 1.5, EPSILON)


func test_a_non_finite_delta_is_ignored():
	var timer := LFIntervalTimer.new(1.0)
	for bad in [NAN, INF, -INF]:
		assert_false(timer.tick(bad))
	assert_eq(timer.elapsed, 0.0)
	assert_false(timer.tick(0.5))
	assert_true(timer.tick(0.5))


func test_a_negative_delta_never_moves_time_back():
	var timer := LFIntervalTimer.new(1.0)
	timer.tick(0.6)
	timer.tick(-5.0)
	assert_almost_eq(timer.elapsed, 0.6, 1e-9)


func test_drain_fires_every_banked_interval_at_once():
	var timer := LFIntervalTimer.new(1.0)
	assert_true(timer.tick(3.5))
	assert_eq(timer.drain(), 2, 'the two intervals the long frame banked beyond the first')
	assert_almost_eq(timer.elapsed, 0.5, 1e-9)
	assert_eq(timer.drain(), 0)


func test_drain_is_finite_at_a_zero_interval():
	var timer := LFIntervalTimer.new(0.0)
	timer.tick(10.0)
	assert_eq(timer.drain(), 0)


func test_fire_next_makes_the_next_tick_fire():
	var timer := LFIntervalTimer.new(5.0)
	timer.fire_next()
	assert_true(timer.tick(0.0))
	assert_false(timer.tick(0.0))


func test_the_default_interval_fires_every_tick():
	assert_true(LFIntervalTimer.new().tick(0.0))


func test_carry_can_be_switched_off_after_construction():
	var timer := LFIntervalTimer.new(1.0)
	assert_true(timer.carry, "carry is on by default")
	timer.carry = false
	assert_true(timer.tick(1.4))
	assert_eq(timer.elapsed, 0.0, "the overshoot is dropped once carry is off")


func test_a_nan_interval_at_construction_is_rejected_and_the_default_stays():
	var timer := LFIntervalTimer.new(NAN)
	assert_push_error('NaN')
	assert_eq(timer.interval, LFIntervalTimer.DEFAULT_INTERVAL_SECONDS)
	assert_true(timer.tick(1.0), 'the default interval fires on every tick')


func test_setting_a_nan_interval_is_rejected_and_the_old_value_stays():
	var timer := LFIntervalTimer.new(1.0)
	timer.tick(0.5)
	timer.interval = NAN
	assert_push_error('NaN')
	assert_eq(timer.interval, 1.0)
	assert_true(timer.tick(0.5), 'still the 1-second interval, 0.5 s banked')


func test_restart_starts_the_wait_over():
	var timer := LFIntervalTimer.new(1.0)
	timer.tick(0.9)
	timer.restart()
	assert_eq(timer.elapsed, 0.0)
	assert_false(timer.tick(0.5))


func test_an_infinite_interval_fires_only_when_asked_and_stays_finite():
	var timer := LFIntervalTimer.new(INF)
	assert_false(timer.tick(1000.0))
	timer.fire_next()
	assert_eq(timer.time_left(), 0.0)
	assert_eq(timer.drain(), 0, 'no whole interval of INF is ever banked')
	assert_true(timer.tick(0.0))
	assert_eq(timer.elapsed, 0.0, 'an infinite interval starts over from zero after a fire')
	assert_false(timer.tick(1.0))
	assert_eq(timer.time_left(), INF)


func test_time_left_is_never_negative_at_a_non_positive_interval():
	var timer := LFIntervalTimer.new(-2.0)
	assert_eq(timer.time_left(), 0.0)
	timer.fire_next()
	assert_eq(timer.elapsed, 0.0, 'fire_next banks nothing below a zero interval')
	assert_eq(timer.time_left(), 0.0)
	assert_true(timer.tick(0.0))


func test_drain_with_a_cap_consumes_only_that_many_intervals():
	var timer := LFIntervalTimer.new(1.0, false)
	timer.elapsed = 10.5
	assert_eq(timer.drain(3), 3)
	assert_almost_eq(timer.elapsed, 7.5, 1e-9, 'the rest stays banked')
	assert_eq(timer.drain(0), 0)
	assert_eq(timer.drain(-1), 7, 'a negative cap means no cap')


func test_drain_saturates_instead_of_overflowing_at_a_tiny_interval():
	var timer := LFIntervalTimer.new(1e-300)
	timer.elapsed = 1.0
	assert_eq(timer.drain(5), 5)
	assert_eq(timer.drain(), 9223372036854775807, 'saturates at the largest int')
