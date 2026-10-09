extends GutTest

## How long a busy task sleeps between stop checks, in milliseconds.
const CHECK_INTERVAL_MSEC := 5
## How far the monotonic duration may drift from the wall-clock one, in seconds.
const DURATION_TOLERANCE_SEC := 0.05
## A task that runs until stopped gives up on its own after this long, in milliseconds.
const LONG_TASK_MSEC := 3000

var lf_thread: LFThread
## LFThread.force_main_thread as it was before each test; after_each puts it back.
var _saved_force_main_thread := false


func before_each():
	_saved_force_main_thread = LFThread.force_main_thread
	lf_thread = LFThread.new("test")


func after_each():
	LFThread.force_main_thread = _saved_force_main_thread
	if !lf_thread.is_done():
		lf_thread.request_stop()
		lf_thread.join_now()


func _wait_until_done(thread: LFThread, max_ms := 2000):
	var deadline = Time.get_ticks_msec() + max_ms
	while !thread.is_done() and Time.get_ticks_msec() < deadline:
		thread.poll()
		await get_tree().process_frame
	assert_true(thread.is_done(), "thread did not finish within %sms" % max_ms)


func test_finished_fires_when_the_thread_completes_without_a_stop_request():
	watch_signals(lf_thread)
	lf_thread.start(func(): return 42)

	await _wait_until_done(lf_thread)

	assert_signal_emitted(lf_thread, "finished")
	assert_signal_not_emitted(lf_thread, "canceled")
	assert_eq(lf_thread.get_result(), 42)


func test_canceled_fires_instead_of_finished_when_stopped_before_completion():
	watch_signals(lf_thread)
	lf_thread.start_cancelable(func(should_stop):
		while !should_stop.call():
			OS.delay_msec(CHECK_INTERVAL_MSEC)
		return "stopped-early"
	)
	await get_tree().process_frame
	lf_thread.request_stop()

	await _wait_until_done(lf_thread)

	assert_signal_emitted(lf_thread, "canceled")
	assert_signal_not_emitted(lf_thread, "finished")
	assert_eq(lf_thread.get_result(), "stopped-early")


func test_starting_while_already_running_is_rejected_not_replaced():
	lf_thread.start(func():
		OS.delay_msec(80)
		return "first"
	)

	var second_started = lf_thread.start(func(): return "second")
	assert_false(second_started)

	await _wait_until_done(lf_thread)
	assert_eq(lf_thread.get_result(), "first")


func test_canceled_is_declared_with_the_arguments_it_is_emitted_with():
	var declared := []
	for s in lf_thread.get_signal_list():
		if s.name == "canceled":
			declared = s.args.map(func(a): return a.name)
	assert_eq(declared, ["id", "key", "result"], "a handler written to the declared signature must match the emission")

	var received := []
	lf_thread.canceled.connect(func(id: String, key: String, result): received.append([id, key, result]))
	lf_thread.start_cancelable(func(should_stop):
		while !should_stop.call():
			OS.delay_msec(CHECK_INTERVAL_MSEC)
		return "stopped-early"
	)
	await get_tree().process_frame
	lf_thread.request_stop()
	await _wait_until_done(lf_thread)

	assert_eq(received, [[lf_thread.id, "test", "stopped-early"]])


func test_get_info_reports_identity_and_an_idle_state_before_start():
	var info = lf_thread.get_info()
	assert_eq(info.id, lf_thread.id)
	assert_eq(info.key, "test")
	assert_false(info.running, "a never-started thread is not running")
	assert_eq(info.started_at, 0.0)
	assert_eq(info.ended_at, 0.0)
	assert_eq(info.duration_sec, 0.0)
	assert_false(info.stop_requested)


func test_get_info_tracks_running_stop_requested_and_end_time():
	lf_thread.start_cancelable(func(should_stop):
		while !should_stop.call():
			OS.delay_msec(CHECK_INTERVAL_MSEC)
	)
	var running = lf_thread.get_info()
	assert_true(running.running, "a started thread reports running")
	assert_gt(running.started_at, 0.0, "started_at is set on start")
	assert_eq(running.ended_at, 0.0, "ended_at stays 0 until finalized")

	lf_thread.request_stop()
	assert_true(lf_thread.get_info().stop_requested)
	lf_thread.join_now()

	var ended = lf_thread.get_info()
	assert_false(ended.running, "a joined thread is no longer running")
	assert_gte(ended.ended_at, ended.started_at, "ended_at is set at finalization")
	assert_almost_eq(ended.duration_sec, ended.ended_at - ended.started_at, DURATION_TOLERANCE_SEC)


func test_join_now_returns_false_when_nothing_is_running():
	assert_false(lf_thread.join_now(), "nothing to join before start")


func test_join_now_blocks_until_the_task_ends_and_finalizes_without_polling():
	watch_signals(lf_thread)
	lf_thread.start(func():
		OS.delay_msec(60)
		return "joined"
	)

	assert_true(lf_thread.join_now(), "a running thread is joined")

	assert_true(lf_thread.is_done())
	assert_eq(lf_thread.get_result(), "joined", "the result is available right after join_now returns")
	assert_signal_emitted(lf_thread, "finished")
	assert_false(lf_thread.join_now(), "a second join has nothing left to join")


## Dropping the last reference to a running thread (its owner torn down mid-compute) joins
## the worker instead of freeing a Thread that is still running.
func test_freeing_a_running_thread_joins_it_first():
	var ran := []
	var thread := LFThread.new()
	thread.start(func():
		OS.delay_msec(150)
		ran.append(true)
		return 1)
	thread = null

	assert_eq(ran, [true], 'the worker finished before the thread was freed')


## The worker never holds a reference to the thread object, so the last reference can
## never drop on the worker (freeing it there, where it can't join itself).
func test_a_running_worker_holds_no_reference_to_the_thread_object():
	var thread := LFThread.new()
	thread.start_cancelable(func(should_stop: Callable):
		var until := Time.get_ticks_msec() + 300
		while Time.get_ticks_msec() < until and !should_stop.call():
			OS.delay_msec(CHECK_INTERVAL_MSEC)
		return 1)
	OS.delay_msec(60)

	assert_eq(thread.get_reference_count(), 1, 'only this test holds it')
	thread.request_stop()
	thread.join_now()


func test_timestamps_are_fractional_seconds():
	lf_thread.start(func(): OS.delay_msec(20))
	lf_thread.join_now()
	var info = lf_thread.get_info()
	assert_eq(typeof(info.started_at), TYPE_FLOAT)
	assert_eq(typeof(info.duration_sec), TYPE_FLOAT)
	assert_gt(info.duration_sec, 0.0, "a 20 ms task has a non-zero duration")


func test_a_finished_but_unpolled_thread_still_reports_running():
	watch_signals(lf_thread)
	lf_thread.start(func(): return 7)
	OS.delay_msec(50)

	assert_false(lf_thread.is_done(), "not done until polled or joined")
	assert_true(lf_thread.get_info().running)
	assert_null(lf_thread.get_result())
	assert_signal_not_emitted(lf_thread, "finished")

	var deadline := Time.get_ticks_msec() + 2000
	while !lf_thread.is_done() and Time.get_ticks_msec() < deadline:
		lf_thread.poll()
		OS.delay_msec(CHECK_INTERVAL_MSEC)
	assert_true(lf_thread.is_done())
	assert_eq(lf_thread.get_result(), 7)
	assert_signal_emitted(lf_thread, "finished")


func test_start_never_passes_a_stop_check_even_to_optional_or_bound_parameters():
	lf_thread.start(func(x = 5): return x)
	lf_thread.join_now()
	assert_eq(lf_thread.get_result(), 5)
	var bound := LFThread.new()
	bound.start((func(a, b = 'b'): return [a, b]).bind(7))
	bound.join_now()
	assert_eq(bound.get_result(), [7, 'b'])


func test_start_cancelable_passes_the_stop_check_first():
	lf_thread.start_cancelable((func(should_stop: Callable, label): return [should_stop.call(), label]).bind('x'))
	lf_thread.join_now()
	assert_eq(lf_thread.get_result(), [false, 'x'])


func test_is_stop_requested_follows_request_stop():
	lf_thread.start_cancelable(func(should_stop):
		while !should_stop.call():
			OS.delay_msec(CHECK_INTERVAL_MSEC))
	assert_false(lf_thread.is_stop_requested())
	lf_thread.request_stop()
	assert_true(lf_thread.is_stop_requested())
	lf_thread.join_now()


## A task that only ends when asked to stop would otherwise block whoever drops the
## last reference for as long as it runs.
func test_freeing_a_running_thread_asks_it_to_stop_first():
	var thread := LFThread.new()
	var ended_by_stop := []
	thread.start_cancelable(func(should_stop: Callable):
		var until := Time.get_ticks_msec() + LONG_TASK_MSEC
		while Time.get_ticks_msec() < until and !should_stop.call():
			OS.delay_msec(CHECK_INTERVAL_MSEC)
		ended_by_stop.append(should_stop.call())
		return 1)
	OS.delay_msec(20)
	thread = null # joins the worker before it returns
	assert_eq(ended_by_stop, [true], 'the task saw the stop request, so it was stopped, not waited out')


func test_started_fires_on_start():
	watch_signals(lf_thread)
	lf_thread.start(func(): return 1)
	assert_signal_emitted_with_parameters(lf_thread, 'started', [lf_thread.id, 'test'])
	lf_thread.join_now()


func test_a_stop_requested_before_start_does_not_carry_over():
	lf_thread.request_stop()
	lf_thread.start_cancelable(func(should_stop: Callable): return should_stop.call())
	lf_thread.join_now()
	assert_eq(lf_thread.get_result(), false)


func test_a_thread_can_run_again_after_it_finished():
	lf_thread.start(func(): return 1)
	lf_thread.join_now()
	assert_true(lf_thread.start(func(): return 2))
	lf_thread.join_now()
	assert_eq(lf_thread.get_result(), 2)


func test_an_invalid_task_is_refused_without_starting_a_thread():
	watch_signals(lf_thread)
	assert_false(lf_thread.start(Callable()))
	assert_false(lf_thread.start_cancelable(Callable()))
	var gone := RefCounted.new()
	var method := Callable(gone, &'get_reference_count')
	gone = null
	assert_false(lf_thread.start(method), 'a method of a freed object')
	assert_true(lf_thread.is_done())
	assert_signal_not_emitted(lf_thread, 'started')


func test_a_build_with_threads_runs_the_task_on_a_worker():
	assert_true(LFThread.threads_available(), "desktop test runs have thread support")
	lf_thread.start(func(): return OS.get_thread_caller_id())
	assert_true(lf_thread.is_threaded())
	lf_thread.join_now()
	assert_ne(lf_thread.get_result(), OS.get_main_thread_id())


## Without thread support (forced here, as on a web export built without threads) the task
## waits for the first poll and runs there, on the main thread, with the same signals.
func test_without_threads_the_task_runs_at_the_first_poll_on_the_main_thread():
	LFThread.force_main_thread = true
	assert_false(LFThread.threads_available())
	watch_signals(lf_thread)
	var ran := []
	assert_true(lf_thread.start(func():
		ran.append(true)
		return OS.get_thread_caller_id()), "start still succeeds")
	assert_signal_emitted(lf_thread, "started")
	assert_false(lf_thread.is_threaded())
	assert_false(lf_thread.get_info().threaded)
	assert_eq(ran, [], "nothing runs inside start")
	assert_false(lf_thread.is_done())

	lf_thread.poll()

	assert_eq(ran, [true])
	assert_true(lf_thread.is_done())
	assert_eq(lf_thread.get_result(), OS.get_main_thread_id())
	assert_signal_emitted_with_parameters(lf_thread, "finished", [lf_thread.id, "test", OS.get_main_thread_id()])


func test_without_threads_join_now_runs_the_task_and_a_stop_request_reports_canceled():
	LFThread.force_main_thread = true
	watch_signals(lf_thread)
	lf_thread.start_cancelable(func(should_stop: Callable): return should_stop.call())
	lf_thread.request_stop()
	assert_true(lf_thread.join_now())
	assert_eq(lf_thread.get_result(), true, "the task sees the stop request")
	assert_signal_emitted(lf_thread, "canceled")
	assert_signal_not_emitted(lf_thread, "finished")
	assert_false(lf_thread.join_now(), "nothing left to join")


func test_without_threads_a_thread_freed_before_its_first_poll_never_runs_the_task():
	LFThread.force_main_thread = true
	var ran := []
	var thread := LFThread.new()
	thread.start(func(): ran.append(true))
	thread = null
	assert_eq(ran, [])


func test_each_instance_gets_its_own_prefixed_id_and_an_empty_default_key():
	var a := LFThread.new()
	var b := LFThread.new()
	assert_true(a.id.begins_with("lf-thread-"), a.id)
	assert_ne(a.id, b.id)
	assert_eq(a.key, "")
	assert_eq(lf_thread.key, "test", "the constructor argument becomes the key")


func test_poll_on_an_idle_thread_does_nothing():
	watch_signals(lf_thread)
	lf_thread.poll()
	assert_true(lf_thread.is_done())
	assert_null(lf_thread.get_result())
	assert_signal_not_emitted(lf_thread, "finished")
	assert_signal_not_emitted(lf_thread, "canceled")


func test_the_duration_grows_while_the_task_is_still_running():
	lf_thread.start_cancelable(func(should_stop):
		while !should_stop.call():
			OS.delay_msec(CHECK_INTERVAL_MSEC))
	OS.delay_msec(30)
	var running: float = lf_thread.get_info().duration_sec
	assert_gt(running, 0.0, "a running task reports the time so far")
	OS.delay_msec(30)
	assert_gt(lf_thread.get_info().duration_sec, running)
	lf_thread.request_stop()
	lf_thread.join_now()


func test_a_run_keeps_its_mode_when_force_main_thread_changes_mid_run():
	LFThread.force_main_thread = true
	var ran := []
	lf_thread.start(func(): ran.append(true); return OS.get_thread_caller_id())
	LFThread.force_main_thread = false
	assert_false(lf_thread.is_threaded(), "started without a worker, stays so")
	lf_thread.poll()
	assert_eq(ran, [true])
	assert_eq(lf_thread.get_result(), OS.get_main_thread_id())

	assert_true(lf_thread.start(func(): return OS.get_thread_caller_id()))
	assert_true(lf_thread.is_threaded(), "the next run gets a worker again")
	LFThread.force_main_thread = true
	lf_thread.join_now()
	assert_ne(lf_thread.get_result(), OS.get_main_thread_id(), "a worker run stays on its worker")


func test_without_threads_a_task_is_refused_while_one_waits_for_its_poll():
	LFThread.force_main_thread = true
	assert_true(lf_thread.start(func(): return "first"))
	assert_false(lf_thread.start(func(): return "second"), "the waiting task counts as running")
	lf_thread.poll()
	assert_eq(lf_thread.get_result(), "first")


## Without a worker the task runs inside poll(); a task that polls (or joins) its own
## thread from there must not collect itself early with no result.
func test_without_threads_a_task_that_polls_its_own_thread_finishes_once_with_its_result():
	LFThread.force_main_thread = true
	var results := []
	lf_thread.finished.connect(func(_id: String, _key: String, result: Variant): results.append(result))
	var thread := lf_thread
	var inner_join := []
	lf_thread.start(func():
		thread.poll()
		inner_join.append(thread.join_now())
		return "real")
	lf_thread.poll()
	assert_eq(results, ["real"])
	assert_eq(inner_join, [false], "nothing to join from inside the task")
	assert_eq(lf_thread.get_result(), "real")
