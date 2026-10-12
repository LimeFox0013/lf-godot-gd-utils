extends GutTest

var _now_ms := 0


func _clock() -> int:
	return _now_ms


func before_each():
	_now_ms = 1000


func test_with_no_gates_it_fires_with_the_context():
	var seen := []
	var proc := LFProc.new(func(ctx): seen.append(ctx))
	assert_true(proc.fire(LFRandom.new(1), 'subject'))
	assert_eq(seen, ['subject'])


func test_certain_chances_consume_no_roll():
	var rng := LFRandom.new(2)
	var before := rng.state
	assert_true(LFProc.new(func(_c): pass).with_chance(1.0).fire(rng))
	assert_false(LFProc.new(func(_c): pass).with_chance(0.0).fire(rng))
	assert_eq(rng.state, before)


func test_a_chance_rolls_exactly_like_lfrandom_chance():
	var rng := LFRandom.new(3)
	var twin := LFRandom.new(3)
	var proc := LFProc.new(func(_c): pass).with_chance(0.25)
	for i in 500:
		assert_eq(proc.fire(rng), twin.chance(0.25))
	assert_eq(rng.state, twin.state)


func test_the_chance_getter_is_read_at_every_check_with_the_context():
	var chance := [0.0]
	var seen := []
	var proc := LFProc.new(func(_c): pass).with_chance_getter(func(ctx): seen.append(ctx); return chance[0])
	var rng := LFRandom.new(4)
	assert_false(proc.fire(rng, 'x'))
	chance[0] = 1.0
	assert_true(proc.fire(rng, 'y'))
	assert_eq(seen, ['x', 'y'])


func test_a_failed_condition_consumes_nothing():
	var rng := LFRandom.new(5)
	var before := rng.state
	var cooldown := LFCooldown.new(500, _clock)
	var proc := LFProc.new(func(_c): pass).with_condition(func(_c): return false).with_chance(0.5).with_cooldown(cooldown).with_charges(1)
	assert_false(proc.fire(rng))
	assert_eq(rng.state, before, 'no roll')
	assert_true(cooldown.is_ready(), 'no cooldown')
	assert_eq(proc.charges_left, 1, 'no charge')


func test_a_cooldown_gates_before_the_roll_and_starts_only_on_a_fire():
	var rng := LFRandom.new(6)
	var cooldown := LFCooldown.new(500, _clock)
	var miss := LFProc.new(func(_c): pass).with_chance(0.0001).with_cooldown(cooldown)
	assert_false(miss.fire(rng))
	assert_true(cooldown.is_ready(), 'a missed chance leaves the cooldown ready')
	var proc := LFProc.new(func(_c): pass).with_cooldown(cooldown)
	assert_true(proc.fire(rng))
	var before := rng.state
	assert_false(miss.fire(rng))
	assert_eq(rng.state, before, 'on cooldown: no roll')
	_now_ms += 500
	assert_true(proc.fire(rng))


func test_charges_are_spent_only_by_a_fire():
	var rng := LFRandom.new(7)
	var chance := [0.0]
	var proc := LFProc.new(func(_c): pass).with_chance_getter(func(_c): return chance[0]).with_charges(1)
	assert_false(proc.fire(rng))
	assert_eq(proc.charges_left, 1, 'a missed chance spends nothing')
	chance[0] = 1.0
	assert_true(proc.fire(rng))
	assert_true(proc.is_spent())
	assert_false(proc.fire(rng))


func test_unlimited_charges_by_default():
	var proc := LFProc.new(func(_c): pass)
	for i in 5:
		assert_true(proc.fire(null))
	assert_false(proc.is_spent())


func test_a_chance_proc_without_a_generator_never_fires_and_reports():
	assert_false(LFProc.new(func(_c): pass).with_chance(0.5).fire(null))
	assert_push_error('LFProc')
	assert_true(LFProc.new(func(_c): pass).fire(null), 'no chance, no generator needed')


func test_a_nan_chance_never_fires():
	var rng := LFRandom.new(8)
	var before := rng.state
	assert_false(LFProc.new(func(_c): pass).with_chance(NAN).fire(rng))
	assert_eq(rng.state, before)


func test_check_commits_without_running_the_action():
	var ran := [false]
	var cooldown := LFCooldown.new(500, _clock)
	var proc := LFProc.new(func(_c): ran[0] = true).with_cooldown(cooldown)
	assert_true(proc.check(null))
	assert_false(ran[0])
	assert_false(cooldown.is_ready())


func test_builders_return_the_same_proc():
	var proc := LFProc.new(func(_c): pass)
	assert_true(is_same(proc.with_chance(0.5), proc))
	assert_true(is_same(proc.with_charges(2), proc))


func test_a_chance_getter_overrides_a_fixed_chance():
	var never := LFProc.new(func(_c): pass).with_chance(1.0).with_chance_getter(func(_c): return 0.0)
	var always := LFProc.new(func(_c): pass).with_chance_getter(func(_c): return 1.0).with_chance(0.0)
	var rng := LFRandom.new(3)
	for i in 20:
		assert_false(never.fire(rng))
		assert_true(always.fire(rng))


func test_zero_charges_never_fire():
	var fired := [0]
	var proc := LFProc.new(func(_c): fired[0] += 1).with_charges(0)
	assert_true(proc.is_spent())
	assert_false(proc.fire(LFRandom.new(1)))
	assert_eq(fired[0], 0)


class _Subject extends Object:
	func act(_context: Variant) -> void:
		pass


func test_a_proc_with_an_invalid_action_does_not_fire_and_commits_nothing():
	var subject := _Subject.new()
	var cooldown := LFCooldown.new(1000)
	var proc := LFProc.new(subject.act).with_charges(2).with_cooldown(cooldown).with_chance(0.5)
	subject.free()
	var rng := LFRandom.new(1)
	var untouched := LFRandom.new(1)
	assert_false(proc.fire(rng), 'there is nothing to run')
	assert_eq(proc.charges_left, 2, 'no charge is spent')
	assert_true(cooldown.is_ready(), 'no cooldown is started')
	assert_eq(rng.randf(), untouched.randf(), 'no roll is spent')
	assert_false(LFProc.new(Callable()).fire(rng), 'an empty action does not fire either')


func test_a_passing_condition_sees_the_context_and_lets_the_proc_fire():
	var seen := []
	var proc := LFProc.new(func(_c): pass).with_condition(func(ctx): seen.append(ctx); return true)
	assert_true(proc.fire(null, 'subject'))
	assert_eq(seen, ['subject'])
	assert_true(is_same(proc.with_condition(func(_c): return true), proc))
	assert_true(is_same(proc.with_cooldown(null), proc))
	assert_true(is_same(proc.with_chance_getter(func(_c): return 1.0), proc))


func test_the_action_can_be_read_and_replaced():
	var seen := []
	var first := func(ctx): seen.append(['first', ctx])
	var proc := LFProc.new(first)
	assert_eq(proc.action, first)
	proc.action = func(ctx): seen.append(['second', ctx])
	proc.fire(null, 1)
	assert_eq(seen, [['second', 1]])


func test_charges_left_can_be_refilled_directly():
	var proc := LFProc.new(func(_c): pass).with_charges(1)
	proc.fire(null)
	assert_true(proc.is_spent())
	proc.charges_left = 2
	assert_false(proc.is_spent())
	assert_true(proc.fire(null))
	assert_eq(proc.charges_left, 1)


func test_a_new_proc_has_unlimited_charges():
	assert_eq(LFProc.new(func(_c): pass).charges_left, LFProc.UNLIMITED_CHARGES)


func test_a_plain_random_number_generator_rolls_like_an_lfrandom_with_the_same_seed():
	var plain := RandomNumberGenerator.new()
	plain.seed = 5
	var twin := LFRandom.new(5)
	var proc := LFProc.new(func(_c): pass).with_chance(0.4)
	for i in 200:
		assert_eq(proc.fire(plain), twin.chance(0.4))
	assert_eq(plain.state, twin.state)


func test_a_chance_above_one_or_below_zero_spends_no_roll():
	var rng := LFRandom.new(9)
	var before := rng.state
	assert_true(LFProc.new(func(_c): pass).with_chance(2.0).fire(rng))
	assert_false(LFProc.new(func(_c): pass).with_chance(-0.5).fire(rng))
	assert_false(LFProc.new(func(_c): pass).with_chance_getter(func(_c): return NAN).fire(rng))
	assert_eq(rng.state, before)


func test_a_passing_cooldown_is_started_by_the_fire():
	var cooldown := LFCooldown.new(500, _clock)
	var proc := LFProc.new(func(_c): pass).with_cooldown(cooldown)
	assert_true(proc.fire(null))
	assert_false(cooldown.is_ready())
	assert_false(proc.fire(null), 'on cooldown')
	_now_ms += 499
	assert_false(proc.fire(null))
	_now_ms += 1
	assert_true(proc.fire(null))


func test_a_failed_roll_spends_no_charge_and_starts_no_cooldown():
	var cooldown := LFCooldown.new(500, _clock)
	var proc := LFProc.new(func(_c): pass).with_chance(0.000001).with_cooldown(cooldown).with_charges(3)
	var rng := LFRandom.new(1)
	assert_false(proc.fire(rng))
	assert_eq(proc.charges_left, 3)
	assert_true(cooldown.is_ready())


func test_with_cooldown_null_removes_the_cooldown():
	var cooldown := LFCooldown.new(500, _clock)
	var proc := LFProc.new(func(_c): pass).with_cooldown(cooldown)
	proc.fire(null)
	proc.with_cooldown(null)
	assert_true(proc.fire(null))


func test_fire_collect_appends_the_action_result_when_it_fires():
	var results := ['kept']
	var proc := LFProc.new(func(ctx): return ctx + 1)
	assert_true(proc.fire_collect(LFRandom.new(1), results, 4))
	assert_eq(results, ['kept', 5], 'appended, not cleared')


func test_fire_collect_appends_null_for_an_action_returning_nothing():
	var results := []
	assert_true(LFProc.new(func(_c): pass).fire_collect(LFRandom.new(1), results))
	assert_eq(results, [null])


func test_fire_collect_appends_nothing_when_a_gate_fails():
	var results := []
	var proc := LFProc.new(func(_c): return 1).with_charges(0)
	assert_false(proc.fire_collect(LFRandom.new(1), results))
	assert_eq(results, [])
