extends GutTest

func test_all_resolves_synchronously_completing_callables():
	# Every callable resolves synchronously, so completion happens before exec() could wait
	# for it; it must still resolve.
	var results = await LFAwait.all([func(): return "A", func(): return "B"])
	assert_eq(results, ["A", "B"])


func test_all_only_resolves_once_every_callable_has_completed():
	var order := []
	# "slow" genuinely suspends (a real frame boundary); "fast" resolves
	# synchronously. This makes the completion order deterministic instead of
	# racing two real-time delays against each other.
	var slow := func():
		await get_tree().process_frame
		order.append("slow")
		return "slow-result"
	var fast := func():
		order.append("fast")
		return "fast-result"

	var results = await LFAwait.all([slow, fast])

	assert_eq(order, ["fast", "slow"], "the slower callable must finish before all() resolves")
	assert_eq(results, ["slow-result", "fast-result"], "results stay ordered by input position")


func test_any_resolves_with_the_first_completing_callables_result():
	var results = await LFAwait.any([func(): return "first", func(): return "second"])
	assert_eq(results, "first")


func test_any_does_not_wait_for_the_remainder():
	var slow_finished := [false]
	var fast := func():
		await _after_frames(1)
		return "fast"
	var slow := func():
		await _after_frames(6)
		slow_finished[0] = true
		return "slow"

	var winner = await LFAwait.any([fast, slow])

	assert_eq(winner, "fast")
	assert_false(slow_finished[0], "any() must not wait for the slower callable")
	await wait_process_frames(8) # let the still-pending slow callable settle before teardown


func test_all_gives_the_same_callable_passed_twice_its_own_result_slot():
	var counter := [0]
	var next := func():
		counter[0] += 1
		return counter[0]

	var results = await LFAwait.all([next, next])

	assert_eq(results, [1, 2], "each position in the batch completes once and keeps its own result")


func test_next_tick_resolves_on_the_next_process_frame():
	var frames := []
	var counter := func(): frames.append(true)
	get_tree().process_frame.connect(counter)

	await LFAwait.next_tick
	var frames_seen := frames.size()
	get_tree().process_frame.disconnect(counter)

	assert_eq(frames_seen, 1, "next_tick must resume on the very next process_frame")


func test_reset_replaces_the_batch_and_clears_previous_results():
	var awaiter := LFAwait.new([func(): return "old"])
	await awaiter.exec()

	var returned = awaiter.reset([func(): return "x", func(): return "y"])

	assert_same(returned, awaiter, "reset returns self for chaining")
	assert_eq(awaiter.done_count(), 0)
	assert_false(awaiter.is_complete())


func test_reset_lets_the_same_awaiter_run_a_new_batch():
	var awaiter := LFAwait.new([func(): return "old"])
	await awaiter.exec()

	var results = await awaiter.reset([func(): return "x", func(): return "y"]).exec()

	assert_eq(results, ["x", "y"])


func test_on_fn_awaited_is_called_with_each_result_and_its_callable():
	var first := func(): return "A"
	var second := func(): return "B"
	var awaiter := LFAwait.new([first, second])
	var seen := []
	awaiter.on_fn_awaited = func(result, fn): seen.append([result, fn])

	await awaiter.exec()

	assert_eq(seen, [["A", first], ["B", second]], "on_fn_awaited fires once per callable as (result, fn)")


func _slow(ms: int) -> int:
	await get_tree().create_timer(ms / 1000.0).timeout
	return ms


## Finishes after `frames` process frames and returns `frames`: an order of finishing that
## no slow frame can change (two timers can expire in the same frame).
func _after_frames(frames: int) -> int:
	for i in frames:
		await get_tree().process_frame
	return frames


## `any` resolves with the first result and doesn't keep its awaiter alive afterwards —
## run ten times, nothing piles up. The object count is process-wide, so earlier tests'
## leftovers are let settle first, and the bound allows a little unrelated churn while
## still failing if even one awaiter per call stayed alive.
func test_any_does_not_keep_its_awaiter_alive():
	const CALLS := 10
	for i in 3:
		await get_tree().process_frame
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	var firsts := []
	for i in CALLS:
		firsts.append(await LFAwait.any([_slow.bind(10), _slow.bind(60)]))
	await get_tree().create_timer(0.15).timeout
	for i in 3:
		await get_tree().process_frame

	assert_eq(firsts, [10, 10, 10, 10, 10, 10, 10, 10, 10, 10])
	assert_lt(Performance.get_monitor(Performance.OBJECT_COUNT) - before, CALLS / 2.0, 'no awaiter left behind per call')


func test_an_async_callable_passed_twice_fills_both_of_its_slots():
	var counter := [0]
	var f := func():
		await LFUtils.timeout(5)
		counter[0] += 1
		return counter[0]

	var results = await LFAwait.all([f, f])

	assert_eq(results.size(), 2)
	assert_false(results.has(null), "neither slot is left empty")
	assert_eq(results[0] + results[1], 3, "each run's result lands in its own slot")


func test_a_second_exec_without_reset_does_not_run_the_batch_again():
	var runs := [0]
	var awaiter := LFAwait.new([func(): runs[0] += 1; return 1])
	await awaiter.exec()
	var again = await awaiter.exec()
	assert_eq(runs[0], 1)
	assert_eq(again, [1])


func test_results_already_returned_survive_a_reset():
	var awaiter := LFAwait.new([func(): return "kept"])
	var results = await awaiter.exec()
	awaiter.reset([func(): return "new"])
	assert_eq(results, ["kept"])


func test_a_callable_from_a_batch_that_was_reset_is_ignored():
	var awaiter := LFAwait.new([_slow.bind(30)])
	awaiter.exec()
	awaiter.reset([func(): return "fresh"])
	var results = await awaiter.exec()
	await get_tree().create_timer(0.06).timeout
	assert_eq(results, ["fresh"], "the old batch's late result never lands in the new one")
	assert_eq(awaiter.done_count(), 1)


func test_an_empty_batch_resolves_at_once():
	assert_eq(await LFAwait.all([]), [])
	assert_null(await LFAwait.any([]))


func test_any_resolves_with_an_async_winner():
	assert_eq(await LFAwait.any([_after_frames.bind(4), _after_frames.bind(1)]), 1)


func test_under_any_awaited_fires_on_the_first_finish_with_only_the_winners_slot():
	var awaiter := LFAwait.new([_after_frames.bind(4), _after_frames.bind(1)])
	awaiter._first_wins = true # what LFAwait.any sets up
	var emitted := []
	awaiter.awaited.connect(func(results): emitted.append(results.duplicate()))
	await awaiter.exec()
	assert_eq(emitted, [[null, 1]], 'emitted once, the loser slot still empty')
	await wait_process_frames(5) # let the loser finish before teardown
	assert_eq(emitted.size(), 1, 'the late finisher does not emit again')


func test_done_count_and_is_complete_track_the_run():
	var awaiter := LFAwait.new([func(): return 1, _slow.bind(20)])
	assert_eq(awaiter.done_count(), 0)
	awaiter.exec()
	assert_eq(awaiter.done_count(), 1, 'the synchronous callable finished at once')
	assert_false(awaiter.is_complete())
	await awaiter.awaited
	assert_eq(awaiter.done_count(), 2)
	assert_true(awaiter.is_complete())


func test_reset_without_a_batch_runs_the_current_one_again():
	var runs := [0]
	var awaiter := LFAwait.new([func(): runs[0] += 1; return runs[0]])
	await awaiter.exec()

	var again = await awaiter.reset().exec()

	assert_eq(runs[0], 2)
	assert_eq(again, [2])


func test_awaited_is_emitted_once_with_every_result_in_batch_order():
	var awaiter := LFAwait.new([_after_frames.bind(2), func(): return "sync"])
	var emitted := []
	awaiter.awaited.connect(func(results): emitted.append(results.duplicate()))

	await awaiter.exec()

	assert_eq(emitted, [[2, "sync"]])


func test_two_callers_awaiting_one_run_both_get_its_results():
	var runs := [0]
	var awaiter := LFAwait.new([func():
		runs[0] += 1
		await get_tree().process_frame
		return "done"])
	var second := [null]
	var other_caller := func() -> void: second[0] = await awaiter.exec()
	other_caller.call()

	var first = await awaiter.exec()
	await get_tree().process_frame

	assert_eq(first, ["done"])
	assert_eq(second[0], ["done"])
	assert_eq(runs[0], 1, "the batch ran once")


func test_under_any_the_losers_still_report_to_on_fn_awaited():
	var awaiter := LFAwait.new([_after_frames.bind(3), _after_frames.bind(1)])
	awaiter._first_wins = true # what LFAwait.any sets up
	var seen := []
	awaiter.on_fn_awaited = func(result, _fn): seen.append(result)

	await awaiter.exec()
	assert_eq(seen, [1])
	await wait_process_frames(4)

	assert_eq(seen, [1, 3], "a late finisher is reported, though the run is already complete")
	assert_eq(awaiter.done_count(), 2)


func test_reset_releases_a_caller_still_awaiting_the_earlier_run():
	var awaiter := LFAwait.new([_after_frames.bind(3)])
	var got := []
	var waiter := func() -> void:
		got.append(await awaiter.exec())
	waiter.call()
	awaiter.reset([func(): return "fresh"])
	assert_eq(got, [[null]], "released at once with the earlier run's results so far")
	assert_eq(await awaiter.exec(), ["fresh"], "the new run is unaffected")
	await wait_process_frames(4) # let the abandoned callable end before teardown


func test_changing_the_array_passed_in_does_not_change_the_batch():
	var batch := [_after_frames.bind(1), _after_frames.bind(2)]
	var awaiter := LFAwait.new(batch)
	var got := []
	var waiter := func() -> void:
		got.append(await awaiter.exec())
	waiter.call()
	batch.clear()
	await wait_process_frames(4)
	assert_eq(got, [[1, 2]])


func test_an_invalid_callable_counts_as_finished_with_null_and_reports_an_error():
	var results = await LFAwait.all([Callable(), func(): return 5])
	assert_eq(results, [null, 5])
	assert_push_error("not valid")


class Counter:
	extends RefCounted
	var calls := 0
	var succeed_on := 0 # the call number that returns "ok"; 0 never succeeds

	func attempt() -> Variant:
		calls += 1
		return "ok" if calls == succeed_on else null


func test_retry_returns_the_first_non_null_result_and_stops():
	var counter := Counter.new()
	counter.succeed_on = 2
	var result = await LFAwait.retry(counter.attempt, 5, 0.0)
	assert_eq(result, "ok")
	assert_eq(counter.calls, 2)


func test_retry_gives_null_after_the_last_attempt_and_makes_exactly_that_many_calls():
	var counter := Counter.new()
	var result = await LFAwait.retry(counter.attempt, 3, 0.0)
	assert_null(result)
	assert_eq(counter.calls, 3)


func test_retry_waits_between_attempts_but_not_after_the_last():
	var counter := Counter.new()
	var start := Time.get_ticks_msec()
	await LFAwait.retry(counter.attempt, 3, 60.0)
	var elapsed := Time.get_ticks_msec() - start
	assert_gte(elapsed, 100, 'two waits of 60 ms')
	assert_lt(elapsed, 170, 'no third wait')


func test_retry_backoff_multiplies_each_later_wait():
	var counter := Counter.new()
	var start := Time.get_ticks_msec()
	await LFAwait.retry(counter.attempt, 3, 40.0, 3.0) # waits 40 + 120
	var elapsed := Time.get_ticks_msec() - start
	assert_gte(elapsed, 150)


func test_retry_waits_for_an_async_fn():
	var counter := [0]
	var fn := func():
		await get_tree().process_frame
		counter[0] += 1
		return counter[0] if counter[0] == 2 else null
	assert_eq(await LFAwait.retry(fn, 4, 0.0), 2)


func test_retry_accept_decides_what_counts_as_success():
	var counter := [0]
	var fn := func():
		counter[0] += 1
		return counter[0]
	var result = await LFAwait.retry(fn, 10, 0.0, 1.0, func(value): return value >= 3)
	assert_eq(result, 3)


func test_retry_treats_false_as_a_result_unless_accept_refuses_it():
	var fn := func(): return false
	assert_eq(await LFAwait.retry(fn, 3, 0.0), false)


func test_retry_with_zero_attempts_has_no_limit():
	var counter := Counter.new()
	counter.succeed_on = 7
	assert_eq(await LFAwait.retry(counter.attempt, 0, 0.0), "ok")
	assert_eq(counter.calls, 7)


func test_retry_with_an_invalid_callable_reports_and_returns_null():
	assert_null(await LFAwait.retry(Callable(), 3, 0.0))
	assert_push_error("not valid")


func test_retry_reports_a_nan_delay_and_backoff_and_carries_on():
	var counter := Counter.new()
	counter.succeed_on = 2
	assert_eq(await LFAwait.retry(counter.attempt, 3, NAN, NAN), "ok")
	assert_push_error_count(2)


func test_retry_treats_negative_delay_and_backoff_as_zero():
	var counter := Counter.new()
	var start := Time.get_ticks_msec()
	await LFAwait.retry(counter.attempt, 3, -500.0, -2.0)
	assert_lt(Time.get_ticks_msec() - start, 200)
	assert_eq(counter.calls, 3)


func test_retry_with_an_invalid_accept_reports_once_and_calls_nothing():
	var counter := Counter.new()
	var dead := Node.new()
	var accept := dead.queue_free
	dead.free()
	assert_null(await LFAwait.retry(counter.attempt, 2, 0.0, 1.0, accept))
	assert_push_error_count(1)
	assert_eq(counter.calls, 0)
