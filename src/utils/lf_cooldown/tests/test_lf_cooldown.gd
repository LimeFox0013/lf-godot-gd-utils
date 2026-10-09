extends GutTest

## The cooldown interval most tests use, in milliseconds.
const INTERVAL_MS := 500

var _now_ms := 0


func _clock() -> int:
	return _now_ms


func before_each():
	_now_ms = 10000


func test_a_fresh_cooldown_is_ready():
	assert_true(LFCooldown.new(INTERVAL_MS, _clock).is_ready())


func test_a_fresh_cooldown_is_ready_even_after_raising_the_interval():
	var cooldown := LFCooldown.new(100, _clock)
	cooldown.interval_ms = 1000
	assert_true(cooldown.try_use())


func test_constructing_never_reads_the_clock():
	var reads := [0]
	LFCooldown.new(100, func(): reads[0] += 1; return 0)
	assert_eq(reads[0], 0)


func test_using_starts_the_cooldown():
	var cooldown := LFCooldown.new(INTERVAL_MS, _clock)
	assert_true(cooldown.try_use())
	assert_false(cooldown.is_ready())
	assert_false(cooldown.try_use())


func test_a_failed_use_neither_resets_nor_extends_it():
	var cooldown := LFCooldown.new(INTERVAL_MS, _clock)
	cooldown.try_use()
	_now_ms += 300
	assert_false(cooldown.try_use())
	_now_ms += 200
	assert_true(cooldown.try_use(), 'still 500 ms from the first use, not from the failed one')


func test_ready_again_once_the_interval_has_passed():
	var cooldown := LFCooldown.new(INTERVAL_MS, _clock)
	cooldown.try_use()
	_now_ms += 499
	assert_false(cooldown.is_ready())
	_now_ms += 1
	assert_true(cooldown.is_ready())


func test_checking_readiness_never_changes_it():
	var cooldown := LFCooldown.new(INTERVAL_MS, _clock)
	for i in 3:
		assert_true(cooldown.is_ready())
	cooldown.start()
	for i in 3:
		assert_false(cooldown.is_ready())


func test_start_and_reset():
	var cooldown := LFCooldown.new(INTERVAL_MS, _clock)
	cooldown.start()
	assert_false(cooldown.is_ready(), 'start begins a cooldown whether or not it was ready')
	cooldown.reset()
	assert_true(cooldown.is_ready())


func test_remaining_ms():
	var cooldown := LFCooldown.new(INTERVAL_MS, _clock)
	assert_eq(cooldown.remaining_ms(), 0.0)
	cooldown.start()
	_now_ms += 120
	assert_eq(cooldown.remaining_ms(), 380.0)
	_now_ms += 1000
	assert_eq(cooldown.remaining_ms(), 0.0)


func test_lowering_the_interval_takes_effect_at_once():
	var cooldown := LFCooldown.new(INTERVAL_MS, _clock)
	cooldown.start()
	_now_ms += 100
	cooldown.interval_ms = 50
	assert_true(cooldown.is_ready())


func test_only_the_supplied_clock_readies_it():
	var cooldown := LFCooldown.new(50, _clock)
	cooldown.start()
	OS.delay_msec(80)
	assert_false(cooldown.is_ready(), 'wall time passed, the supplied clock did not')


func test_a_clock_that_runs_backwards_counts_as_elapsed():
	var cooldown := LFCooldown.new(INTERVAL_MS, _clock)
	cooldown.start()
	_now_ms -= 5000
	assert_true(cooldown.is_ready())


func test_an_unusable_clock_fails_closed():
	var holder := ClockHolder.new()
	var cooldown := LFCooldown.new(INTERVAL_MS, holder.now)
	holder.free()
	assert_false(cooldown.is_ready())
	assert_false(cooldown.try_use())
	assert_push_error('LFCooldown')


func test_an_unusable_clock_reports_the_full_interval_remaining_and_errors_once():
	var holder := ClockHolder.new()
	var cooldown := LFCooldown.new(INTERVAL_MS, holder.now)
	holder.free()
	assert_eq(cooldown.remaining_ms(), float(INTERVAL_MS))
	cooldown.is_ready()
	cooldown.try_use()
	assert_push_error_count(1, 'reported once, however often it is read')


func test_start_with_an_unusable_clock_does_not_mark_it_used():
	var holder := ClockHolder.new()
	var cooldown := LFCooldown.new(INTERVAL_MS, holder.now)
	holder.free()
	cooldown.start()
	assert_false(cooldown._used, 'start is a no-op without a time to start from')
	assert_push_error('LFCooldown')


func test_without_a_clock_it_runs_on_wall_time():
	var cooldown := LFCooldown.new(30)
	cooldown.start()
	assert_false(cooldown.is_ready())
	OS.delay_msec(40)
	assert_true(cooldown.is_ready())


class ClockHolder:
	extends Object
	func now() -> int:
		return 0


var _float_now_ms := 0.0


func _float_clock() -> float:
	return _float_now_ms


func test_fractional_intervals_and_clocks_are_not_truncated():
	var cooldown := LFCooldown.new(16.5, _float_clock)
	cooldown.start()
	_float_now_ms = 16.2
	assert_false(cooldown.is_ready(), '16.2 ms of a 16.5 ms interval have passed')
	assert_almost_eq(cooldown.remaining_ms(), 0.3, 0.0001)
	_float_now_ms = 16.5
	assert_true(cooldown.is_ready())


## A clock freed mid-interval: the cooldown stays closed instead of reading wall time,
## and a reset cannot open it either.
func test_a_clock_freed_after_a_use_keeps_it_closed():
	var holder := ClockHolder.new()
	var cooldown := LFCooldown.new(INTERVAL_MS, holder.now)
	assert_true(cooldown.try_use())
	holder.free()

	assert_false(cooldown.is_ready())
	assert_eq(cooldown.remaining_ms(), float(INTERVAL_MS))
	cooldown.reset()
	assert_false(cooldown.is_ready(), 'ready needs a usable clock')
	assert_push_error_count(1)


func test_remaining_ms_after_the_clock_ran_backwards_is_zero():
	var cooldown := LFCooldown.new(INTERVAL_MS, _clock)
	cooldown.start()
	_now_ms -= 100
	assert_eq(cooldown.remaining_ms(), 0.0)


func test_a_nan_interval_is_rejected_and_the_old_value_stays():
	var now := [0]
	var cooldown := LFCooldown.new(NAN, func(): return now[0])
	assert_push_error('NaN')
	assert_eq(cooldown.interval_ms, 0.0, 'rejected at construction: nothing was set')
	cooldown.interval_ms = 500.0
	cooldown.interval_ms = NAN
	assert_push_error('NaN')
	assert_eq(cooldown.interval_ms, 500.0)
	cooldown.start()
	now[0] = 499
	assert_false(cooldown.is_ready())
	now[0] = 500
	assert_true(cooldown.is_ready())


func test_the_clock_is_a_public_property_that_can_be_replaced():
	var first := [0]
	var cooldown := LFCooldown.new(100, func(): return first[0])
	cooldown.start()
	first[0] = 50
	assert_false(cooldown.is_ready())
	cooldown.clock_ms = func(): return 1000
	assert_true(cooldown.is_ready(), 'the new clock reads 1000, far past the first use')
