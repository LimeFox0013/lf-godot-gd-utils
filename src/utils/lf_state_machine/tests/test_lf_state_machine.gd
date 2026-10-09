extends GutTest

const STATE_A := 0
const STATE_B := 1
const STATE_C := 2
const T_AB := 0
const T_BC := 1


func _make_config(hooks: Array[LFStateHook] = []) -> LFStateMachineConfig:
	return LFStateMachineConfig.new(STATE_A, [
		LFStateTransition.new(T_AB, [STATE_A], STATE_B),
		LFStateTransition.new(T_BC, [STATE_B], STATE_C),
	], hooks)


func test_a_transition_is_only_allowed_from_its_declared_source_states():
	var sm = LFStateMachine.new(_make_config())
	assert_false(sm.can_do(T_BC), "T_BC requires STATE_B, but the machine starts in STATE_A")
	assert_true(sm.can_do(T_AB))


func test_do_moves_through_the_declared_states_and_emits_lifecycle_signals():
	var sm = LFStateMachine.new(_make_config())
	watch_signals(sm)

	var ok = await sm.do(T_AB)

	assert_true(ok)
	assert_eq(sm.get_state(), STATE_B)
	assert_signal_emitted(sm, "state_exited")
	assert_signal_emitted(sm, "state_entered")
	assert_signal_emitted(sm, "transition_passed")


func test_a_transition_unavailable_from_the_current_state_is_rejected():
	var sm = LFStateMachine.new(_make_config())
	var ok = await sm.do(T_BC) # invalid from STATE_A
	assert_false(ok)
	assert_eq(sm.get_state(), STATE_A)


func test_only_one_transition_may_be_in_progress_at_a_time():
	# A guard waiting on a gate keeps the first do() in progress for as long as the test
	# wants — no timers to race.
	var gate := Gate.new()
	var guard := LFTransitionGuard.new([T_AB], func():
		await gate.opened
		return true
	)
	var sm := LFStateMachine.new(_make_config([guard]))
	var first := [null]
	var run := func(): first[0] = await sm.do(T_AB)
	run.call()
	assert_false(await sm.do(T_AB), 'refused while the first is in progress')
	gate.opened.emit()
	await get_tree().process_frame
	assert_eq(first[0], true)


class Gate:
	signal opened


func test_a_transition_guard_returning_false_prevents_the_transition():
	var guard = LFTransitionGuard.new([T_AB], func(): return false)
	var sm = LFStateMachine.new(_make_config([guard]))

	var ok = await sm.do(T_AB)

	assert_false(ok)
	assert_eq(sm.get_state(), STATE_A)


func test_a_guard_rejected_transition_does_not_permanently_lock_the_machine():
	var guard = LFTransitionGuard.new([T_AB], func(): return false)
	var sm = LFStateMachine.new(_make_config([guard]))
	await sm.do(T_AB) # rejected by the guard

	assert_true(sm.can_do(T_AB), "the machine must not stay stuck after a guard rejection")


func test_hooks_fire_only_for_their_declared_states_or_transitions():
	var left_a := []
	var left_c := []
	var hooks: Array[LFStateHook] = [
		LFStateExitHook.new([STATE_A], func(): left_a.append(true)),
		LFStateExitHook.new([STATE_C], func(): left_c.append(true)), # never applicable here
	]
	var sm = LFStateMachine.new(_make_config(hooks))

	await sm.do(T_AB) # leaves STATE_A

	assert_eq(left_a.size(), 1)
	assert_eq(left_c.size(), 0)


func test_after_transition_hook_fires_only_for_its_declared_transition():
	var after_ab := []
	var after_bc := []
	var hooks: Array[LFStateHook] = [
		LFAfterTransitionHook.new([T_AB], func(): after_ab.append(true)),
		LFAfterTransitionHook.new([T_BC], func(): after_bc.append(true)),
	]
	var sm = LFStateMachine.new(_make_config(hooks))

	await sm.do(T_AB)

	assert_eq(after_ab.size(), 1)
	assert_eq(after_bc.size(), 0)


func test_get_state_reports_the_current_state():
	var sm = LFStateMachine.new(_make_config())
	assert_eq(sm.get_state(), STATE_A)
	await sm.do(T_AB)
	assert_eq(sm.get_state(), STATE_B)


func test_between_states_the_machine_reports_no_state():
	var seen := []
	var box := [] # lambdas capture locals by value; the box lets the hook see the machine
	var hooks: Array[LFStateHook] = [LFStateExitHook.new([STATE_A], func(): seen.append(box[0].get_state()))]
	box.append(LFStateMachine.new(_make_config(hooks)))

	await box[0].do(T_AB)

	assert_eq(seen, [LFStateMachine.NO_STATE])


func test_an_unknown_transition_is_refused_not_an_error():
	var sm = LFStateMachine.new(_make_config())
	assert_null(sm.get_transition_def(99))
	assert_false(sm.can_do(99))
	assert_false(await sm.do(99))


func test_on_enter_state_hook_fires_only_for_its_declared_state():
	var entered_b := []
	var entered_c := []
	var hooks: Array[LFStateHook] = [
		LFStateEnterHook.new([STATE_B], func(): entered_b.append(true)),
		LFStateEnterHook.new([STATE_C], func(): entered_c.append(true)),
	]
	var sm = LFStateMachine.new(_make_config(hooks))

	await sm.do(T_AB)
	assert_eq(entered_b.size(), 1, "entering STATE_B fires its hook")
	assert_eq(entered_c.size(), 0, "STATE_C's hook must not fire on entering STATE_B")

	await sm.do(T_BC)
	assert_eq(entered_b.size(), 1)
	assert_eq(entered_c.size(), 1, "entering STATE_C fires its hook")


func test_on_enter_state_hook_runs_in_the_new_state_before_the_state_entered_signal():
	var log := []
	var box := [] # lambdas capture locals by value; the box lets the hook see the machine
	var hooks: Array[LFStateHook] = [LFStateEnterHook.new([STATE_B], func(): log.append(["hook", box[0].get_state()]))]
	box.append(LFStateMachine.new(_make_config(hooks)))
	box[0].state_entered.connect(func(state): log.append(["signal", state]))

	await box[0].do(T_AB)

	assert_eq(log, [["hook", STATE_B], ["signal", STATE_B]], "the enter hook sees the new state and runs before state_entered")


func test_an_awaiting_on_enter_state_hook_delays_the_rest_of_the_transition():
	var gate := Gate.new()
	var hooks: Array[LFStateHook] = [LFStateEnterHook.new([STATE_B], func(): await gate.opened)]
	var sm = LFStateMachine.new(_make_config(hooks))
	watch_signals(sm)
	var results := []
	var run = func(): results.append(await sm.do(T_AB))

	run.call()
	assert_eq(sm.get_state(), STATE_B, "the machine is already in the entered state while its hook awaits")
	assert_signal_not_emitted(sm, "state_entered", "state_entered waits for the enter hook")
	assert_false(sm.can_do(T_BC), "the machine stays locked while the enter hook awaits")

	gate.opened.emit()
	assert_eq(results, [true])
	assert_signal_emitted(sm, "transition_passed", "the transition completes after the awaited enter hook")


func test_an_on_enter_state_hook_declaring_several_states_fires_for_each():
	var entered := []
	var hooks: Array[LFStateHook] = [LFStateEnterHook.new([STATE_B, STATE_C], func(): entered.append(true))]
	var sm = LFStateMachine.new(_make_config(hooks))

	await sm.do(T_AB)
	await sm.do(T_BC)

	assert_eq(entered.size(), 2)


func test_an_state_entered_listener_can_request_a_follow_up_transition():
	var box := [] # lambdas capture locals by value; the box lets the listener see the machine
	var follow_ups := []
	box.append(LFStateMachine.new(_make_config()))
	box[0].state_entered.connect(func(state):
		if state == STATE_B:
			follow_ups.append(await box[0].do(T_BC))
	)

	assert_true(await box[0].do(T_AB))

	assert_eq(follow_ups, [true], "the follow-up transition requested from state_entered is accepted")
	assert_eq(box[0].get_state(), STATE_C)


func test_after_transition_hooks_run_before_the_state_entered_signal_while_still_locked():
	var log := []
	var box := []
	var hooks: Array[LFStateHook] = [LFAfterTransitionHook.new([T_AB], func(): log.append(["after", box[0].can_do(T_BC)]))]
	box.append(LFStateMachine.new(_make_config(hooks)))
	box[0].state_entered.connect(func(state): log.append(["signal", box[0].can_do(T_BC)]))

	await box[0].do(T_AB)

	assert_eq(log, [["after", false], ["signal", true]], "after-transition hooks run locked; state_entered is emitted unlocked")


func test_a_guard_returning_null_does_not_veto():
	# Only an explicit `false` vetoes; a guard that returns nothing lets the transition pass.
	var guard = LFTransitionGuard.new([T_AB], func(): return null)
	var sm = LFStateMachine.new(_make_config([guard]))

	assert_true(await sm.do(T_AB))
	assert_eq(sm.get_state(), STATE_B)


func test_listeners_hear_every_state_in_order_when_one_chains_a_transition():
	var sm := LFStateMachine.new(_make_config())
	var heard := []
	sm.state_entered.connect(func(state):
		if state == STATE_B:
			sm.do(T_BC))
	sm.state_entered.connect(func(state): heard.append(state))
	assert_true(await sm.do(T_AB))
	assert_eq(heard, [STATE_B, STATE_C], 'B is heard before C, and the last heard is the real state')
	assert_eq(sm.get_state(), STATE_C)


func test_a_chained_transition_reports_its_own_result():
	var sm := LFStateMachine.new(_make_config())
	var results := []
	sm.state_entered.connect(func(state):
		if state == STATE_B:
			results.append(await sm.do(T_BC))
			results.append(await sm.do(T_AB)))
	await sm.do(T_AB)
	await get_tree().process_frame
	assert_eq(results, [true, false], 'T_BC runs; T_AB is not available from C')


func test_duplicate_transition_names_are_reported():
	var duplicate := LFStateMachineConfig.new(STATE_A, [
		LFStateTransition.new(T_AB, [STATE_A], STATE_B),
		LFStateTransition.new(T_AB, [STATE_A], STATE_C),
	])
	var sm := LFStateMachine.new(duplicate)
	assert_push_error('declared twice')
	await sm.do(T_AB)
	assert_eq(sm.get_state(), STATE_B, 'the first declaration wins')


func test_the_no_state_marker_cannot_be_used_as_a_state():
	LFStateMachine.new(LFStateMachineConfig.new(LFStateMachine.NO_STATE, []))
	assert_push_error('NO_STATE')
	LFStateMachine.new(LFStateMachineConfig.new(STATE_A, [LFStateTransition.new(T_AB, [STATE_A], LFStateMachine.NO_STATE)]))
	assert_push_error('NO_STATE')


func test_a_missing_config_is_reported():
	var sm := LFStateMachine.new(null)
	assert_push_error('config')
	assert_false(await sm.do(T_AB))


func test_the_machine_is_reference_counted():
	var sm := LFStateMachine.new(_make_config())
	assert_true(sm is RefCounted)
	var watch: WeakRef = weakref(sm)
	sm = null
	assert_null(watch.get_ref())


func test_state_exited_carries_the_previous_state_and_transition_passed_its_id():
	var sm := LFStateMachine.new(_make_config())
	watch_signals(sm)
	await sm.do(T_AB)
	assert_signal_emitted_with_parameters(sm, "state_exited", [STATE_A])
	assert_signal_emitted_with_parameters(sm, "state_entered", [STATE_B])
	assert_signal_emitted_with_parameters(sm, "transition_passed", [T_AB])


func test_several_hooks_of_one_kind_run_in_declaration_order_each_awaited():
	var gate := Gate.new()
	var log := []
	var sm := LFStateMachine.new(_make_config([
		LFStateEnterHook.new([STATE_B], func():
			log.append("first-start")
			await gate.opened
			log.append("first-end")),
		LFStateEnterHook.new([STATE_B], func(): log.append("second")),
	]))
	var run := func(): await sm.do(T_AB)
	run.call()
	assert_eq(log, ["first-start"], "the second waits for the first to finish")
	gate.opened.emit()
	assert_eq(log, ["first-start", "first-end", "second"])


func test_a_do_from_a_state_exited_listener_is_refused():
	var sm := LFStateMachine.new(LFStateMachineConfig.new(STATE_A, [
		LFStateTransition.new(T_AB, [STATE_A], STATE_B),
		LFStateTransition.new(T_BC, [STATE_A, STATE_B], STATE_C),
	]))
	var inner := [null]
	sm.state_exited.connect(func(_state): inner[0] = await sm.do(T_BC), CONNECT_ONE_SHOT)
	assert_true(await sm.do(T_AB))
	assert_eq(inner[0], false, "still locked while state_exited is emitted")
	assert_eq(sm.get_state(), STATE_B)


func test_an_unknown_hook_type_is_reported_and_ignored():
	var sm := LFStateMachine.new(_make_config([LFStateHook.new()]))
	assert_push_error("unknown hook type")
	assert_true(await sm.do(T_AB), "the machine still works")


func test_a_guard_listing_several_transitions_guards_each():
	var allow := [false]
	var sm := LFStateMachine.new(_make_config([
		LFTransitionGuard.new([T_AB, T_BC], func(): return allow[0]),
	]))
	assert_false(await sm.do(T_AB))
	allow[0] = true
	assert_true(await sm.do(T_AB))
	allow[0] = false
	assert_false(await sm.do(T_BC), "the same guard vetoes the second transition")
	allow[0] = true
	assert_true(await sm.do(T_BC))
	assert_eq(sm.get_state(), STATE_C)


func test_a_guard_without_a_callback_lets_the_transition_pass():
	var guard := LFTransitionGuard.new([T_AB])
	assert_eq(guard.transitions, [T_AB])
	var sm := LFStateMachine.new(_make_config([guard]))
	assert_true(await sm.do(T_AB))
	assert_eq(sm.get_state(), STATE_B)


func test_hooks_and_config_expose_their_constructor_arguments():
	var callback := func(): pass
	var leave := LFStateExitHook.new([STATE_A], callback)
	var enter := LFStateEnterHook.new([STATE_B], callback)
	var after := LFAfterTransitionHook.new([T_AB], callback)
	assert_eq(leave.states, [STATE_A])
	assert_eq(enter.states, [STATE_B])
	assert_eq(after.transitions, [T_AB])
	assert_eq(after.callback, callback)
	var config := _make_config([leave])
	assert_eq(config.initial_state, STATE_A)
	assert_eq(config.transitions.size(), 2)
	assert_eq(config.hooks.size(), 1)
	var transition := LFStateMachine.new(config).get_transition_def(T_AB)
	assert_eq([transition.name, transition.from, transition.to], [T_AB, [STATE_A], STATE_B])


func test_only_an_exact_false_vetoes():
	for passing: Variant in [0, '', [], true]:
		var sm := LFStateMachine.new(_make_config([LFTransitionGuard.new([T_AB], func(): return passing)]))
		assert_true(await sm.do(T_AB), 'a guard returning %s does not veto' % [var_to_str(passing)])


func test_a_vetoed_transition_leaves_nothing_and_emits_nothing():
	var log := []
	var sm := LFStateMachine.new(_make_config([
		LFTransitionGuard.new([T_AB], func(): return false),
		LFStateExitHook.new([STATE_A], func(): log.append('left A')),
		LFStateEnterHook.new([STATE_B], func(): log.append('entered B')),
		LFAfterTransitionHook.new([T_AB], func(): log.append('after AB')),
	]))
	watch_signals(sm)
	assert_false(await sm.do(T_AB))
	assert_eq(log, [], 'no hook runs after a veto')
	assert_signal_not_emitted(sm, 'state_exited')
	assert_signal_not_emitted(sm, 'state_entered')
	assert_signal_not_emitted(sm, 'transition_passed')


func test_a_second_guard_is_not_asked_once_the_first_vetoes():
	var asked := []
	var sm := LFStateMachine.new(_make_config([
		LFTransitionGuard.new([T_AB], func():
			asked.append('first')
			return false),
		LFTransitionGuard.new([T_AB], func():
			asked.append('second')
			return true),
	]))
	assert_false(await sm.do(T_AB))
	assert_eq(asked, ['first'])


func test_an_awaiting_guard_that_vetoes_unlocks_the_machine():
	var gate := Gate.new()
	var sm := LFStateMachine.new(_make_config([LFTransitionGuard.new([T_AB], func():
		await gate.opened
		return false)]))
	var result := [null]
	var run := func(): result[0] = await sm.do(T_AB)
	run.call()
	assert_false(sm.can_do(T_AB), 'locked while the guard awaits')
	gate.opened.emit()
	assert_eq(result[0], false)
	assert_true(sm.can_do(T_AB), 'unlocked after the veto')
	assert_eq(sm.get_state(), STATE_A)


func test_a_from_state_of_no_state_is_reported():
	LFStateMachine.new(LFStateMachineConfig.new(STATE_A, [LFStateTransition.new(T_AB, [LFStateMachine.NO_STATE], STATE_B)]))
	assert_push_error('NO_STATE')


func test_a_machine_without_a_config_reports_no_state():
	var sm := LFStateMachine.new(null)
	assert_push_error('config')
	assert_eq(sm.get_state(), LFStateMachine.NO_STATE)
	assert_false(sm.can_do(T_AB))


func test_signals_of_a_chained_transition_follow_those_of_the_first():
	var sm := LFStateMachine.new(_make_config())
	var log := []
	sm.state_exited.connect(func(state): log.append(['exited', state]))
	sm.state_entered.connect(func(state): log.append(['entered', state]))
	sm.transition_passed.connect(func(transition):
		log.append(['passed', transition])
		if transition == T_AB:
			sm.do(T_BC))
	assert_true(await sm.do(T_AB))
	assert_eq(log, [
		['exited', STATE_A], ['entered', STATE_B], ['passed', T_AB],
		['exited', STATE_B], ['entered', STATE_C], ['passed', T_BC],
	], 'a do() from transition_passed is queued until the first transition is fully announced')


func test_a_do_from_a_hook_is_refused():
	var inner := [null]
	var box := []
	box.append(LFStateMachine.new(_make_config([LFStateEnterHook.new([STATE_B], func(): inner[0] = await box[0].do(T_BC))])))
	assert_true(await box[0].do(T_AB))
	assert_eq(inner[0], false, 'the machine is locked while its hooks run')
	assert_eq(box[0].get_state(), STATE_B)
	box.clear()


func test_a_hook_with_an_invalid_callback_is_reported_and_does_not_lock_the_machine():
	var sm := LFStateMachine.new(_make_config([
		LFTransitionGuard.new([T_AB], Callable()),
		LFStateExitHook.new([STATE_A], Callable()),
		LFStateEnterHook.new([STATE_B], Callable()),
		LFAfterTransitionHook.new([T_AB], Callable()),
	]))
	assert_true(await sm.do(T_AB), 'invalid hooks are skipped')
	assert_push_error_count(4)
	assert_eq(sm.get_state(), STATE_B)
	assert_true(sm.can_do(T_BC), 'unlocked')


func test_a_hook_whose_object_was_freed_is_skipped():
	var node := Node.new()
	var sm := LFStateMachine.new(_make_config([LFStateEnterHook.new([STATE_B], Callable(node, 'queue_free'))]))
	node.free()
	assert_true(await sm.do(T_AB))
	assert_push_error('invalid')
	assert_true(sm.can_do(T_BC))


func test_a_null_transition_is_reported_and_ignored():
	var sm := LFStateMachine.new(LFStateMachineConfig.new(STATE_A, [null, LFStateTransition.new(T_AB, [STATE_A], STATE_B)]))
	assert_push_error('null transition')
	assert_true(await sm.do(T_AB))
