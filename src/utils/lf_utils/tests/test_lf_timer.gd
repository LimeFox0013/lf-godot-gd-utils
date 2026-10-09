extends GutTest

## Engine.time_scale and the tree's pause as they were before each test; after_each puts
## them back.
var _saved_time_scale := 1.0
var _saved_paused := false


func before_each():
	_saved_time_scale = Engine.time_scale
	_saved_paused = get_tree().paused


func after_each():
	Engine.time_scale = _saved_time_scale
	get_tree().paused = _saved_paused


func test_created_timer_fires_its_callback_exactly_once():
	# GDScript lambdas capture locals by value, so the counter must be boxed
	# (an Array) for the callback's mutation to be observable here.
	var calls := [0]
	var cb := func(): calls[0] += 1
	var timer = LFUtils.create_timer(10, cb)
	await timer.timeout
	assert_eq(calls[0], 1)


func test_timeout_runs_its_callback_before_the_awaiting_coroutine_resumes():
	var calls := [0]
	await LFUtils.timeout(20, func(): calls[0] += 1)
	assert_eq(calls[0], 1, 'the callback ran once by the time the await returned')


func test_timers_of_both_kinds_fire_while_the_tree_is_paused():
	var calls := [0]
	get_tree().paused = true
	var scaled_timer := LFUtils.create_timer(10, func(): calls[0] += 1)
	var real_timer := LFUtils.create_timer(10, func(): calls[0] += 1, true)
	await scaled_timer.timeout
	if real_timer.time_left > 0.0:
		await real_timer.timeout
	assert_eq(calls[0], 2)


func test_a_real_time_timer_ignores_the_time_scale():
	var timer := LFUtils.create_timer(1000, func(): pass, true)
	var scaled_timer := LFUtils.create_timer(1000)
	Engine.time_scale = 4.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(timer.time_left, scaled_timer.time_left, 'the scaled timer ran down faster')


func test_a_timer_without_a_callback_still_fires():
	var timer := LFUtils.create_timer(10)
	await timer.timeout
	assert_eq(timer.time_left, 0.0)


func test_timeout_follows_the_time_scale():
	Engine.time_scale = 4.0
	var real_timer := LFUtils.create_timer(400, func(): pass, true)

	await LFUtils.timeout(400)

	assert_gt(real_timer.time_left, 0.0, 'the scaled wait ended while 400 ms of real time had not yet passed')
