extends GutTest

var emitter: LFEventEmitter


func before_each():
	emitter = LFEventEmitter.new()


func test_emit_reaches_a_registered_handler_with_its_argument():
	var received := []
	emitter.on("greet", func(name): received.append(name))
	await emitter.emit("greet", "world")
	assert_eq(received, ["world"])


func test_emit_reaches_every_handler_registered_for_the_same_event():
	var called_a := [false]
	var called_b := [false]
	emitter.on("x", func(): called_a[0] = true)
	emitter.on("x", func(): called_b[0] = true)
	await emitter.emit("x")
	assert_true(called_a[0])
	assert_true(called_b[0])


func test_once_handler_runs_on_the_first_emit():
	var calls := [0]
	emitter.once("x", func(): calls[0] += 1)
	await emitter.emit("x")
	assert_eq(calls[0], 1)


func test_once_handler_does_not_run_again_on_a_second_emit():
	var calls := [0]
	emitter.once("x", func(): calls[0] += 1)
	await emitter.emit("x")
	await emitter.emit("x")
	assert_eq(calls[0], 1)


func test_once_handler_is_deregistered_before_its_single_invocation_completes():
	var call_order := []
	emitter.once("x", func(): call_order.append("handler ran"))
	emitter.on("x", func(): call_order.append("sibling ran"))
	await emitter.emit("x")
	await emitter.emit("x")
	# The once handler fires exactly once; the sibling keeps firing every time.
	assert_eq(call_order, ["handler ran", "sibling ran", "sibling ran"])


func test_off_with_a_specific_callback_only_removes_that_callback():
	var called_a := [false]
	var called_b := [false]
	var handler_a := func(): called_a[0] = true
	emitter.on("x", handler_a)
	emitter.on("x", func(): called_b[0] = true)

	emitter.off("x", handler_a)
	await emitter.emit("x")

	assert_false(called_a[0])
	assert_true(called_b[0])


func test_off_with_an_empty_callable_removes_nothing_and_reports_an_error():
	var called := [false]
	emitter.on("x", func(): called[0] = true)
	emitter.off("x", Callable())
	assert_push_error_count(1)
	await emitter.emit("x")
	assert_true(called[0], 'the handler stays')
	assert_eq(emitter.handler_count("x"), 1)


func test_clear_event_removes_every_handler_of_one_event_only():
	var called := [0]
	emitter.on("x", func(): called[0] += 1)
	emitter.once("x", func(): called[0] += 1)
	emitter.on("y", func(): called[0] += 10)
	emitter.clear_event("x")
	await emitter.emit("x")
	await emitter.emit("y")
	assert_eq(called[0], 10)


func test_emit_awaits_every_registered_handler_before_resolving():
	var order := []
	emitter.on("x", func():
		await get_tree().process_frame
		order.append("slow")
	)
	emitter.on("x", func():
		order.append("fast")
	)
	await emitter.emit("x")
	assert_eq(order, ["fast", "slow"])


func test_emit_waits_for_an_async_once_handler_and_returns_its_result():
	emitter.once("x", func():
		await LFUtils.timeout(50)
		return 1
	)
	var results = await emitter.emit("x")
	assert_eq(results, [1])


func test_emit_sync_calls_every_handler_at_once_in_order_and_once_handlers_once():
	var calls: Array = []
	emitter.on('e', func(value): calls.append(['on', value]))
	emitter.once('e', func(value): calls.append(['once', value]))

	emitter.emit_sync('e', 1)
	emitter.emit_sync('e', 2)
	emitter.emit_sync('nobody-listens', 3)

	assert_eq(calls, [['on', 1], ['once', 1], ['on', 2]])


## A `once` wrapper refers to itself; it must not keep itself (and what its callback
## holds) alive once fired or cleared.
func test_a_once_handler_is_freed_after_it_fires_or_is_cleared():
	var watch_fired := _once_holding('a')
	var watch_cleared := _once_holding('b')

	emitter.emit_sync('a')
	emitter.clear_event('b')

	assert_null(watch_fired.get_ref(), 'freed after firing')
	assert_null(watch_cleared.get_ref(), 'freed after its event was cleared')


## Registers a `once` handler holding a fresh object (from its own frame, so no stack slot
## here keeps the handler) and returns a watch on that object.
func _once_holding(event: String) -> WeakRef:
	var held := RefCounted.new()
	emitter.once(event, func(): return held)
	return weakref(held)


func test_emit_sync_v_takes_the_arguments_as_an_array():
	var seen := []
	emitter.on('e', func(a, b): seen.append([a, b]))
	emitter.emit_sync_v('e', [1, 2])
	assert_eq(seen, [[1, 2]])


# --- Lifetime and re-entrancy ---

func test_an_emitter_with_a_pending_once_can_be_freed():
	var local := LFEventEmitter.new()
	local.once('x', func(): pass)
	var watch: WeakRef = weakref(local)
	local = null
	assert_null(watch.get_ref())


func test_clearing_an_event_during_an_emit_skips_its_pending_once_without_error():
	var ran := [false]
	emitter.on('x', func(): emitter.clear_event('x'))
	emitter.once('x', func(): ran[0] = true)
	emitter.emit_sync('x')
	assert_false(ran[0])
	assert_false(emitter.has_handlers('x'))


func test_a_re_entrant_emit_runs_a_pending_once_exactly_once():
	var runs := [0]
	var depth := [0]
	emitter.on('x', func():
		depth[0] += 1
		if depth[0] == 1:
			emitter.emit_sync('x'))
	emitter.once('x', func(): runs[0] += 1)
	emitter.emit_sync('x')
	assert_eq(runs[0], 1)


func test_a_handler_added_during_an_emit_is_not_called_by_it():
	for existing in [1, 2]:
		var local := LFEventEmitter.new()
		var late := [0]
		for i in existing:
			local.on('x', func(): local.on('x', func(): late[0] += 1))
		local.emit_sync('x')
		assert_eq(late[0], 0, 'with %d handler(s) already there' % existing)
		local.clear() # the handlers capture `local`: break the cycle


func test_a_handler_removed_before_its_turn_is_not_called():
	var ran := [false]
	var second := func(): ran[0] = true
	emitter.on('x', func(): emitter.off('x', second))
	emitter.on('x', second)
	emitter.emit_sync('x')
	assert_false(ran[0])


func test_an_async_emit_gives_a_removed_handler_a_null_slot():
	var second := func(): return 'second'
	emitter.on('x', func(): emitter.off('x', second); return 'first')
	emitter.on('x', second)
	assert_eq(await emitter.emit('x'), ['first', null])


func test_off_removes_a_pending_once_by_its_callback():
	var ran := [false]
	var cb := func(): ran[0] = true
	emitter.once('x', cb)
	emitter.off('x', cb)
	emitter.emit_sync('x')
	assert_false(ran[0])


func test_clear_removes_every_handler_of_every_event():
	emitter.on('a', func(): pass)
	emitter.once('b', func(): pass)
	assert_eq(emitter.handler_count('a'), 1)
	emitter.clear()
	assert_false(emitter.has_handlers('a'))
	assert_false(emitter.has_handlers('b'))


func test_emit_with_no_handlers_resolves_empty():
	assert_eq(await emitter.emit('nothing'), [])


func test_emit_sync_starts_an_async_handler_without_awaiting_it():
	var done := [false]
	emitter.on('x', func():
		await get_tree().process_frame
		done[0] = true)
	emitter.emit_sync('x')
	assert_false(done[0])
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(done[0])


func test_a_callback_registered_twice_runs_twice_and_off_removes_one_copy():
	var calls := [0]
	var handler := func(): calls[0] += 1
	emitter.on('x', handler)
	emitter.on('x', handler)
	assert_eq(emitter.handler_count('x'), 2)
	emitter.emit_sync('x')
	assert_eq(calls[0], 2)
	emitter.off('x', handler)
	assert_eq(emitter.handler_count('x'), 1, 'off removes only the first copy')
	emitter.emit_sync('x')
	assert_eq(calls[0], 3)


func test_handler_count_drops_once_a_once_handler_fires():
	emitter.once('x', func(): pass)
	emitter.on('x', func(): pass)
	assert_eq(emitter.handler_count('x'), 2)
	emitter.emit_sync('x')
	assert_eq(emitter.handler_count('x'), 1)


func test_a_handler_whose_object_was_freed_does_nothing():
	var target := Counter.new()
	emitter.on('x', target.bump)
	target.free()
	emitter.emit_sync('x')
	assert_eq(await emitter.emit('x'), [null], 'emit resolves with a null slot for it')


class Counter:
	extends Object
	var count := 0
	func bump() -> int:
		count += 1
		return count


func test_clear_event_removes_only_that_events_handlers():
	var calls := []
	emitter.on("a", func(): calls.append("a"))
	emitter.once("a", func(): calls.append("a-once"))
	emitter.on("b", func(): calls.append("b"))
	emitter.clear_event("a")
	assert_false(emitter.has_handlers("a"))
	assert_eq(emitter.handler_count("b"), 1)
	emitter.emit_sync("a")
	emitter.emit_sync("b")
	assert_eq(calls, ["b"])


func test_off_for_an_unknown_event_or_an_unregistered_callback_changes_nothing():
	var calls := [0]
	emitter.on('x', func(): calls[0] += 1)
	emitter.off('never-registered', func(): pass)
	emitter.off('x', func(): pass)
	assert_eq(emitter.handler_count('x'), 1)
	emitter.emit_sync('x')
	assert_eq(calls[0], 1)


func test_counts_for_an_event_with_no_handlers_are_zero():
	assert_false(emitter.has_handlers('nothing'))
	assert_eq(emitter.handler_count('nothing'), 0)
	emitter.clear_event('nothing')
	assert_eq(emitter.handler_count('nothing'), 0, 'clearing an unknown event is a no-op')


func test_emit_passes_every_argument_and_returns_results_in_registration_order():
	emitter.on('sum', func(a, b):
		await get_tree().process_frame
		return a + b)
	emitter.on('sum', func(a, b): return a * b)
	assert_eq(await emitter.emit('sum', 3, 4), [7, 12])


## Many one-shot handlers mixed with lasting ones: each one-shot runs once, in
## registration order, and counts as gone the moment it fires (seen from a later handler
## of the same emit).
func test_many_once_handlers_fire_once_in_order_and_stop_counting_as_they_fire():
	var log := []
	var counts := []
	for i in 30:
		if i % 3 == 0:
			emitter.on("tick", func(): log.append("on%d" % i))
		else:
			emitter.once("tick", func():
				log.append("once%d" % i)
				counts.append(emitter.handler_count("tick")))
	emitter.emit_sync("tick")
	var expected := []
	for i in 30:
		expected.append(("on%d" if i % 3 == 0 else "once%d") % i)
	assert_eq(log, expected)
	assert_eq(counts[0], 29, 'the first one-shot no longer counts while it runs')
	assert_eq(counts[counts.size() - 1], 10, 'only the lasting ones are left by the last')
	assert_eq(emitter.handler_count("tick"), 10)
	log.clear()
	emitter.emit_sync("tick")
	assert_eq(log.size(), 10, 'the second emit calls only the lasting handlers')


## While an emit runs, adding and removing handlers and emitting again behave as before:
## an added one waits for the next emit, one removed before its turn is skipped, a nested
## emit sees the registrations as they are then, and a one-shot runs once overall.
func test_registrations_changed_during_an_emit_follow_the_documented_order():
	var log := []
	var late := func(): log.append("late")
	var doomed := func(): log.append("doomed")
	var nested := [true]
	emitter.on("e", func():
		log.append("first")
		emitter.on("e", late)
		emitter.on("e", late)
		emitter.off("e", doomed)
		if nested[0]:
			nested[0] = false
			emitter.emit_sync("e"))
	emitter.once("e", func(): log.append("one-shot"))
	emitter.on("e", doomed)
	emitter.emit_sync("e")
	assert_eq(log, ["first", "first", "one-shot", "late", "late"],
		'outer: first, then the nested emit (first again, the one-shot, the two added); the outer skips the one-shot and the removed one, and never calls the added ones')
	assert_eq(emitter.handler_count("e"), 5, 'first, and late twice from each of the two runs of first')
	log.clear()
	emitter.emit_sync("e")
	assert_eq(log.count("late"), 4)
	assert_false(log.has("one-shot"))
	assert_false(log.has("doomed"))


## Clearing an event during its emit and registering it again: the running emit calls
## nothing more, the new handler waits for the next emit, and the counts follow.
func test_clearing_and_re_registering_during_an_emit():
	var log := []
	emitter.on("e", func():
		log.append("a")
		emitter.clear_event("e")
		emitter.on("e", func(): log.append("new")))
	emitter.on("e", func(): log.append("b"))
	emitter.emit_sync("e")
	assert_eq(log, ["a"])
	assert_eq(emitter.handler_count("e"), 1)
	assert_true(emitter.has_handlers("e"))
	emitter.emit_sync("e")
	assert_eq(log, ["a", "new"])


## Registering outside an emit adds to the event's list in place; inside one it copies
## the list once (the emit keeps walking the original), however many are added.
func test_registering_copies_the_handler_list_only_while_an_emit_walks_it():
	for i in 100:
		emitter.on("e", func(): pass)
	var list: Array = emitter._handlers["e"]
	for i in 100:
		emitter.on("e", func(): pass)
	assert_true(is_same(emitter._handlers["e"], list), 'no copy outside an emit')
	assert_eq(list.size(), 200)
	var lists := []
	emitter.once("e", func():
		emitter.on("e", func(): pass)
		lists.append(emitter._handlers["e"])
		emitter.on("e", func(): pass)
		lists.append(emitter._handlers["e"]))
	emitter.emit_sync("e")
	assert_false(is_same(lists[0], list), 'copied once an emit walks it')
	assert_true(is_same(lists[1], lists[0]), 'the second add during the emit reuses that copy')
	assert_eq(emitter.handler_count("e"), 202)


## One-shot handlers fired by an emit leave the list together when it ends, and the event
## goes once none is left.
func test_fired_once_handlers_leave_the_list_when_the_emit_ends():
	for i in 50:
		emitter.once("e", func(): pass)
	var list: Array = emitter._handlers["e"]
	var sizes := []
	emitter.on("e", func(): sizes.append(list.size()))
	emitter.emit_sync("e")
	assert_eq(sizes, [51], 'nothing reshuffled while the emit walks the list')
	assert_eq(list.size(), 1, 'the fired ones dropped at the end')
	emitter.clear_event("e")
	assert_false(emitter.has_handlers("e"))
	for i in 5:
		emitter.once("f", func(): pass)
	emitter.emit_sync("f")
	assert_false(emitter.has_handlers("f"))
	assert_false(emitter._handlers.has("f"), 'an event left with no handler is forgotten')


## A nested emit walking a copy made during the outer one: a handler it adds goes into
## another copy, so the nested emit still never calls it.
func test_a_handler_added_during_a_nested_emit_waits_for_the_next_emit():
	var log := []
	var late2 := func(): log.append("late2")
	var late1_added := [false]
	var late1 := func():
		log.append("late1")
		if not late1_added[0]:
			late1_added[0] = true
			emitter.on("e", late2)
	var first_call := [true]
	emitter.on("e", func():
		log.append("h1")
		if first_call[0]:
			first_call[0] = false
			emitter.on("e", late1)
			emitter.emit_sync("e"))
	emitter.emit_sync("e")
	assert_eq(log, ["h1", "h1", "late1"], 'the nested emit calls late1 (added before it began), never late2')
	log.clear()
	emitter.emit_sync("e")
	assert_eq(log, ["h1", "late1", "late2"])


func _fails_after_a_frame() -> void:
	await get_tree().process_frame
	var nothing: Node = null
	nothing.queue_free()


func test_emit_resolves_with_null_for_a_handler_that_stops_with_a_script_error():
	var emitter := LFEventEmitter.new()
	emitter.on("boom", _fails_after_a_frame)
	emitter.on("boom", func(): return 7)
	var results: Array = await emitter.emit("boom")
	assert_eq(results, [null, 7])
	assert_engine_error('queue_free')
