extends GutTest

const TURN := 10.0
const STAGE := 75.0


## Every cycle `_cycle` made, so `after_each` can break the reference cycles of the tests'
## lambdas that capture their cycle.
var _made: Array[LFTurnCycle] = []


func _cycle(order: Array = ['a', 'b']) -> LFTurnCycle:
	var cycle := LFTurnCycle.new(order, TURN, STAGE)
	_made.append(cycle)
	return cycle


func after_each():
	for cycle in _made:
		cycle.auto_resolve = Callable()
		LFUtils.disconnect_all(cycle.turn_started)
	_made.clear()


func test_turns_go_round_in_order():
	var cycle := _cycle(['a', 'b', 'c'])
	cycle.start()
	assert_eq(cycle.current(), 'a')
	cycle.end_turn()
	assert_eq(cycle.current(), 'b')
	cycle.end_turn()
	cycle.end_turn()
	assert_eq(cycle.current(), 'a', 'back to the first after the last')


func test_the_order_is_copied():
	var order := ['a', 'b']
	var cycle := LFTurnCycle.new(order, TURN, STAGE)
	order.clear()
	assert_eq(cycle.order(), ['a', 'b'])


func test_a_timed_out_turn_loses_only_that_turn():
	var cycle := _cycle()
	cycle.start()
	cycle.tick(TURN + 0.1)
	assert_eq(cycle.current(), 'b')
	cycle.tick(TURN + 0.1)
	assert_eq(cycle.current(), 'a', 'a acts again once its turn comes round')
	assert_false(cycle.is_finished())


func test_the_turn_timer_restarts_each_turn():
	var cycle := _cycle()
	cycle.start()
	cycle.tick(4.0)
	assert_almost_eq(cycle.turn_time_left(), TURN - 4.0, 0.0001)
	cycle.end_turn()
	assert_almost_eq(cycle.turn_time_left(), TURN, 0.0001)
	assert_almost_eq(cycle.stage_time_left(), STAGE - 4.0, 0.0001, 'the stage timer keeps running')


func test_time_left_is_never_negative():
	var cycle := _cycle()
	cycle.start()
	cycle.tick(STAGE * 2)
	assert_eq(cycle.turn_time_left(), 0.0)
	assert_eq(cycle.stage_time_left(), 0.0)


func test_a_negative_or_non_finite_delta_adds_nothing():
	var cycle := _cycle()
	cycle.start()
	cycle.tick(-5.0)
	cycle.tick(NAN)
	cycle.tick(INF)
	assert_almost_eq(cycle.turn_time_left(), TURN, 0.0001)
	assert_eq(cycle.current(), 'a')


func test_mark_done_takes_a_participant_out_and_the_cycle_finishes_when_everyone_is_done():
	var cycle := _cycle()
	watch_signals(cycle)
	cycle.start()
	assert_true(cycle.mark_done('a'))
	assert_eq(cycle.current(), 'b', 'marking the current one done ends its turn')
	assert_true(cycle.is_done('a'))
	assert_true(cycle.mark_done('b'))
	assert_true(cycle.is_finished())
	assert_null(cycle.current())
	assert_signal_emit_count(cycle, 'finished', 1)


func test_done_participants_are_passed_over():
	var cycle := _cycle(['a', 'b', 'c'])
	cycle.start()
	cycle.mark_done('b')
	assert_eq(cycle.current(), 'a', 'marking another one done leaves the turn alone')
	cycle.end_turn()
	assert_eq(cycle.current(), 'c')
	assert_eq(cycle.done_ids(), ['b'])


func test_mark_done_refuses_an_unknown_or_repeated_id_or_a_finished_cycle():
	var cycle := _cycle()
	cycle.start()
	assert_false(cycle.mark_done('z'))
	assert_true(cycle.mark_done('b'))
	assert_false(cycle.mark_done('b'))
	cycle.mark_done('a')
	assert_true(cycle.is_finished())
	var other := _cycle()
	other.start()
	other.tick(STAGE)
	assert_false(other.mark_done('a'), 'nothing changes once finished')


func test_marking_the_last_one_done_when_it_is_not_its_turn_finishes():
	var cycle := _cycle(['a', 'b'])
	cycle.start()
	cycle.mark_done('b')
	cycle.mark_done('a')
	assert_true(cycle.is_finished())


func test_marking_everyone_done_before_start_finishes_only_at_start():
	for marks in [['a', 'b'], ['b', 'a']]:
		var cycle := _cycle(['a', 'b'])
		var finishes := [0]
		cycle.finished.connect(func(): finishes[0] += 1)
		for id in marks:
			assert_true(cycle.mark_done(id))
		assert_false(cycle.is_finished(), 'nothing runs before start (%s)' % [marks])
		assert_eq(finishes[0], 0)
		cycle.start()
		assert_true(cycle.is_finished(), 'start finishes a cycle whose participants are all done')
		assert_eq(finishes[0], 1)


func test_a_shared_done_array_is_used_not_copied():
	var done_ids: Array[String] = []
	var cycle := LFTurnCycle.new(['a', 'b'], TURN, STAGE, done_ids)
	cycle.start()
	cycle.mark_done('a')
	assert_eq(done_ids, ['a'] as Array[String], 'mark_done writes into the caller array')
	done_ids.append('b')
	assert_true(cycle.is_done('b'), 'ids the caller adds count as done')
	assert_eq(cycle.done_ids(), ['a', 'b'])


func test_cycles_without_a_done_array_never_share_one():
	var first := _cycle()
	var second := _cycle()
	first.mark_done('a')
	assert_false(second.is_done('a'), 'each cycle gets its own empty done array')


func test_skipped_turns_are_passed_over_and_add_up():
	var cycle := _cycle()
	cycle.start()
	cycle.skip_turns('b', 1)
	cycle.skip_turns('b', 1)
	assert_eq(cycle.skips_left('b'), 2)
	cycle.end_turn()
	assert_eq(cycle.current(), 'a', "b's first turn is skipped")
	cycle.end_turn()
	assert_eq(cycle.current(), 'a', 'and its second')
	cycle.end_turn()
	assert_eq(cycle.current(), 'b')
	assert_eq(cycle.skips_left('b'), 0)


func test_a_non_positive_skip_changes_nothing():
	var cycle := _cycle()
	cycle.skip_turns('a', 0)
	cycle.skip_turns('a', -2)
	assert_eq(cycle.skips_left('a'), 0)


func test_the_stage_timer_ends_a_cycle_nobody_finishes():
	var cycle := _cycle()
	watch_signals(cycle)
	cycle.start()
	var ticks := 0
	while not cycle.is_finished() and ticks < 100:
		cycle.tick(TURN)
		ticks += 1
	assert_eq(ticks, ceili(STAGE / TURN), 'ended by the stage timer, not by anyone being done')
	assert_signal_emit_count(cycle, 'finished', 1)
	cycle.end_turn()
	cycle.tick(TURN)
	assert_signal_emit_count(cycle, 'finished', 1, 'nothing happens once finished')


func test_an_empty_order_finishes_at_start():
	var cycle := LFTurnCycle.new([], TURN, STAGE)
	cycle.start()
	assert_true(cycle.is_finished())
	assert_null(cycle.current())


func test_turn_started_fires_for_each_turn_but_not_for_done_or_skipped_ones():
	var cycle := _cycle(['a', 'b', 'c'])
	var started := []
	cycle.turn_started.connect(func(id): started.append(id))
	cycle.mark_done('b')
	cycle.skip_turns('c', 1)
	cycle.start()
	cycle.end_turn()
	cycle.end_turn()
	assert_eq(started, ['a', 'a', 'c'])


# --- auto_resolve ---

func test_auto_resolve_can_take_out_a_participant_that_has_nothing_to_do():
	var cycle := _cycle()
	var idle := {'a': false, 'b': true}
	cycle.auto_resolve = func(id):
		if idle[id]:
			cycle.mark_done(id)
		return false
	cycle.start()
	cycle.end_turn()
	assert_eq(cycle.current(), 'a', "b is out, so it is a's turn again")
	assert_true(cycle.is_done('b'))


func test_auto_resolve_returning_true_ends_the_turn():
	var cycle := _cycle()
	cycle.auto_resolve = func(id): return id == 'a'
	cycle.start()
	assert_eq(cycle.current(), 'b')


func test_an_auto_run_participant_acts_on_each_turn_until_it_is_out():
	# a acts for itself twice (one item per turn) and is then out; b has nothing to do.
	var items := {'a': 2, 'b': 0}
	var cycle := _cycle()
	cycle.auto_resolve = func(id):
		if items[id] == 0:
			cycle.mark_done(id)
		else:
			items[id] -= 1
			cycle.end_turn()
		return false
	watch_signals(cycle)
	cycle.start()
	assert_true(cycle.is_finished(), 'every turn resolved itself')
	assert_eq(items['a'], 0)
	assert_signal_emit_count(cycle, 'finished', 1)


func test_starting_again_mid_turn_re_asks_auto_resolve_for_the_current_turn():
	var cycle := _cycle()
	var auto := {'a': false}
	cycle.auto_resolve = func(id): return auto.get(id, false)
	cycle.start()
	cycle.tick(3.0)
	assert_eq(cycle.current(), 'a')
	auto['a'] = true
	cycle.start()
	assert_eq(cycle.current(), 'b')


func test_restarting_without_a_change_keeps_the_turn_and_its_timer():
	var cycle := _cycle()
	cycle.start()
	cycle.tick(3.0)
	cycle.start()
	assert_eq(cycle.current(), 'a')
	assert_almost_eq(cycle.turn_time_left(), TURN - 3.0, 0.0001)


func test_the_loop_guard_stops_a_run_of_auto_resolved_turns_that_never_ends():
	var cycle := _cycle(['a', 'b'])
	var calls := [0]
	cycle.auto_resolve = func(_id):
		calls[0] += 1
		return true
	cycle.start()
	assert_eq(calls[0], 2 * 2 + 1, 'stopped after order.size() * 2 + 1 auto-resolved turns')
	assert_false(cycle.is_finished())
	var waiting: Variant = cycle.current()
	assert_eq(cycle.turn_time_left(), TURN, 'the turn it stopped on waits for its timer')
	cycle.tick(TURN)
	assert_eq(calls[0], 2 * (2 * 2 + 1), 'the timeout starts a fresh run, guarded again')
	assert_ne(waiting, null)


func test_the_loop_guard_limit_can_be_set():
	var cycle := _cycle(['a', 'b'])
	cycle.max_auto_turns = 3
	var calls := [0]
	cycle.auto_resolve = func(_id):
		calls[0] += 1
		return true
	cycle.start()
	assert_eq(calls[0], 3)


func test_someone_marked_done_resets_the_loop_guard():
	# a acts for itself on every turn (6 times, then is out); b passes until it goes out.
	# That is 9 auto-resolved turns: past the guard of 5, but b going out restarts the count.
	var cycle := _cycle(['a', 'b'])
	var left := {'a': 6}
	cycle.auto_resolve = func(id):
		if id == 'b':
			if left['a'] <= 4:
				cycle.mark_done('b')
			return true
		if left['a'] == 0:
			cycle.mark_done('a')
			return false
		left['a'] -= 1
		return true
	cycle.start()
	assert_true(cycle.is_finished())
	assert_eq(left['a'], 0)


func test_end_turn_from_a_turn_started_listener_moves_on():
	var cycle := _cycle()
	cycle.turn_started.connect(func(id):
		if id == 'a':
			cycle.end_turn(), CONNECT_ONE_SHOT)
	cycle.start()
	assert_eq(cycle.current(), 'b')


func test_auto_resolve_returning_anything_but_true_waits_for_input():
	for value in [1, 'yes', null, false]:
		var cycle := _cycle()
		cycle.auto_resolve = func(_id): return value
		cycle.start()
		assert_eq(cycle.current(), 'a', 'a return of %s does not end the turn' % [value])


func test_the_turn_and_stage_limits_can_change_mid_cycle():
	var cycle := _cycle()
	assert_eq(cycle.turn_seconds, TURN)
	assert_eq(cycle.stage_seconds, STAGE)
	cycle.start()
	cycle.turn_seconds = 2.0
	assert_eq(cycle.turn_time_left(), 2.0)
	cycle.tick(2.0)
	assert_eq(cycle.current(), 'b', 'the shorter turn limit ended the turn')
	cycle.stage_seconds = 3.0
	cycle.tick(1.0)
	assert_true(cycle.is_finished(), 'the shorter stage limit finished the cycle')


func test_mark_done_works_with_ids_of_mixed_types():
	var cycle := _cycle([1, 'bot'])
	cycle.start()
	assert_true(cycle.mark_done('bot'), 'comparing "bot" with the current 1 is no error')
	assert_eq(cycle.current(), 1)
	assert_true(cycle.mark_done(1))
	assert_true(cycle.is_finished())


func test_tick_and_end_turn_before_start_do_nothing():
	var cycle := _cycle(['a', 'b'])
	var started := []
	cycle.turn_started.connect(func(id): started.append(id))
	cycle.tick(TURN + 1.0)
	cycle.end_turn()
	assert_almost_eq(cycle.turn_time_left(), TURN, 0.0001, 'the timers wait for start()')
	cycle.start()
	assert_eq(started, ['a'], 'the first turn starts with start(), announced')
	assert_eq(cycle.current(), 'a')


func test_marking_the_first_participant_done_before_start_skips_it_at_start():
	var cycle := _cycle(['a', 'b'])
	assert_true(cycle.mark_done('a'))
	cycle.start()
	assert_eq(cycle.current(), 'b')


func test_listeners_that_end_every_turn_are_stopped_by_the_loop_guard():
	# Every participant is a bot that ends its turn as soon as it starts, from a turn_started
	# listener: without the guard, settling would never return.
	var cycle := _cycle(['a', 'b'])
	var starts := [0]
	cycle.turn_started.connect(func(_id):
		starts[0] += 1
		cycle.end_turn())
	cycle.start()
	assert_eq(starts[0], 2 * 2 + 1 + 1, 'the guard lets order.size() * 2 + 1 turns end, then stops on the next')
	assert_false(cycle.is_finished())
	assert_eq(cycle.turn_time_left(), TURN, 'the turn it stopped on waits for its timer')


func test_a_listener_ending_turns_alongside_auto_resolve_is_guarded_too():
	var cycle := _cycle(['a', 'b'])
	var calls := [0]
	cycle.auto_resolve = func(_id):
		calls[0] += 1
		return false
	cycle.turn_started.connect(func(_id): cycle.end_turn())
	cycle.start()
	assert_false(cycle.is_finished())
	assert_eq(calls[0], 0, 'a turn the listener already ended is not handed to auto_resolve')


func test_an_infinite_stage_never_finishes_by_time():
	var cycle := LFTurnCycle.new(['a', 'b'], TURN, INF)
	cycle.start()
	for i in 1000:
		cycle.tick(TURN)
	assert_false(cycle.is_finished())
	assert_eq(cycle.stage_time_left(), INF)


func test_before_start_the_current_participant_is_the_first():
	assert_eq(_cycle(['a', 'b']).current(), 'a')
	assert_null(LFTurnCycle.new([], TURN, STAGE).current())


func test_the_stage_running_out_on_the_same_tick_as_a_turn_finishes_without_a_new_turn():
	var cycle := LFTurnCycle.new(['a', 'b'], TURN, TURN)
	var started := []
	cycle.turn_started.connect(func(id): started.append(id))
	cycle.start()
	cycle.tick(TURN)
	assert_true(cycle.is_finished())
	assert_eq(started, ['a'], 'no turn starts after the stage ended')


func test_mark_done_of_another_participant_from_a_listener_is_honoured():
	var cycle := _cycle(['a', 'b', 'c'])
	cycle.turn_started.connect(func(id):
		if id == 'a':
			cycle.mark_done('b'), CONNECT_ONE_SHOT)
	cycle.start()
	assert_eq(cycle.current(), 'a', 'marking someone else done leaves the turn waiting')
	cycle.end_turn()
	assert_eq(cycle.current(), 'c', 'b was passed over')
