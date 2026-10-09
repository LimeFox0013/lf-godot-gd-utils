extends GutTest

var procs: LFTriggerSet
var rng: LFRandom


func before_each():
	procs = LFTriggerSet.new()
	rng = LFRandom.new(9)


func _logging(log: Array, name: String, result: Variant = null) -> LFProc:
	return LFProc.new(func(ctx): log.append([name, ctx]); return result)


func test_only_the_exact_key_fires_in_registration_order():
	var log := []
	procs.add(&'event_a', _logging(log, 'a'))
	procs.add(&'event_a', _logging(log, 'b'))
	procs.add(&'event_b', _logging(log, 'c'))
	assert_eq(procs.fire(&'event_a', rng, 'x'), 2)
	assert_eq(log, [['a', 'x'], ['b', 'x']])


func test_an_unknown_key_does_nothing_and_rolls_nothing():
	var before := rng.state
	assert_eq(procs.fire(&'nothing', rng), 0)
	assert_eq(rng.state, before)


func test_the_count_is_only_what_fired():
	procs.add(&'event_a', LFProc.new(func(_c): pass))
	procs.add(&'event_a', LFProc.new(func(_c): pass).with_chance(0.0))
	assert_eq(procs.fire(&'event_a', rng), 1)


func test_adding_the_same_proc_twice_under_a_key_registers_it_once():
	var log := []
	var proc := _logging(log, 'a')
	procs.add(&'event_a', proc)
	procs.add(&'event_a', proc)
	procs.add(&'event_b', proc)
	assert_eq(procs.count(&'event_a'), 1)
	procs.fire(&'event_a', rng)
	procs.fire(&'event_b', rng)
	assert_eq(log.size(), 2, 'once per key')


func test_removing_the_last_proc_under_a_key_drops_the_key():
	var proc := LFProc.new(func(_c): pass)
	procs.add(&'event_a', proc)
	assert_false(procs.remove(&'event_a', LFProc.new(func(_c): pass)))
	assert_true(procs.remove(&'event_a', proc))
	assert_false(procs.has(&'event_a'), 'an emptied key is gone')


func test_a_null_key_is_an_error_and_stores_nothing():
	procs.add(null, LFProc.new(func(_c): pass))
	assert_push_error('LFTriggerSet')
	assert_false(procs.has(null))


func test_a_null_proc_is_an_error_and_stores_nothing():
	procs.add(&'on_hit', null)
	assert_push_error('LFTriggerSet')
	assert_false(procs.has(&'on_hit'))
	assert_eq(procs.fire(&'on_hit', RandomNumberGenerator.new()), 0)


func test_keys_keep_their_variant_identity():
	procs.add(1, LFProc.new(func(_c): pass))
	assert_eq(procs.fire(1.0, rng), 0, 'an int key and a float key differ')
	assert_eq(procs.fire(1, rng), 1)


func test_a_string_and_a_string_name_with_the_same_text_are_one_key():
	procs.add('event_a', LFProc.new(func(_c): pass))
	assert_eq(procs.fire(&'event_a', rng), 1)
	assert_true(procs.has(&'event_a'))


func test_changes_during_a_fire_take_effect_from_the_next():
	var log := []
	var late := _logging(log, 'late')
	var first := LFProc.new(func(_c):
		log.append(['first', null])
		procs.add(&'event_a', late)
		procs.remove(&'event_a', second_proc))
	second_proc = _logging(log, 'second')
	procs.add(&'event_a', first)
	procs.add(&'event_a', second_proc)
	procs.fire(&'event_a', rng)
	assert_eq(log, [['first', null], ['second', null]], 'this fire walks the old list')
	log.clear()
	procs.fire(&'event_a', rng)
	assert_eq(log.map(func(e): return e[0]), ['first', 'late'])

var second_proc: LFProc


func test_clear_during_a_fire_is_safe():
	var log := []
	procs.add(&'event_a', LFProc.new(func(_c): log.append('a'); procs.clear()))
	procs.add(&'event_a', LFProc.new(func(_c): log.append('b')))
	procs.fire(&'event_a', rng)
	assert_eq(log, ['a', 'b'])
	assert_false(procs.has(&'event_a'))


func test_fire_until_handled_stops_at_the_first_true():
	var log := []
	procs.add(&'event_c', _logging(log, 'a', false))
	procs.add(&'event_c', _logging(log, 'b', true))
	var never := LFProc.new(func(_c): log.append(['c', null])).with_chance(0.5)
	procs.add(&'event_c', never)
	var before := rng.state
	assert_true(procs.fire_until_handled(&'event_c', rng))
	assert_eq(log.map(func(e): return e[0]), ['a', 'b'])
	assert_eq(rng.state, before, 'the proc after the handler was never checked')


func test_fire_until_handled_spends_a_charge_even_when_not_handling():
	var proc := LFProc.new(func(_c): return false).with_charges(1)
	procs.add(&'event_c', proc)
	assert_false(procs.fire_until_handled(&'event_c', rng))
	assert_true(proc.is_spent())


func test_procs_for_is_a_copy():
	procs.add(&'event_a', LFProc.new(func(_c): pass))
	procs.procs_for(&'event_a').clear()
	assert_eq(procs.count(&'event_a'), 1)


## The object count is process-wide (another test's worker thread may add or free a few
## meanwhile), so the bound is "fewer than one object per ten calls", which still fails if
## a call creates even one object that stays.
func test_firing_creates_no_objects():
	procs.add(&'event_a', LFProc.new(func(_c): pass).with_chance(0.5))
	procs.fire(&'event_a', rng, self)
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 1000:
		procs.fire(&'event_a', rng, self)
	assert_lt(Performance.get_monitor(Performance.OBJECT_COUNT) - before, 1000 / 10.0, 'no object kept per call')


func test_only_an_action_returning_exactly_true_handles_the_trigger():
	var log := []
	procs.add(&'event_d', _logging(log, 'one', 1))
	procs.add(&'event_d', _logging(log, 'text', 'yes'))
	procs.add(&'event_d', _logging(log, 'nothing', null))
	procs.add(&'event_d', _logging(log, 'handled', true))
	procs.add(&'event_d', _logging(log, 'never', true))
	assert_true(procs.fire_until_handled(&'event_d', rng, 'x'))
	assert_eq(log.map(func(entry): return entry[0]), ['one', 'text', 'nothing', 'handled'], 'truthy non-bools keep the walk going')


func test_a_plain_random_number_generator_is_accepted():
	var plain := RandomNumberGenerator.new()
	plain.seed = 9
	var log := []
	procs.add(&'event_a', _logging(log, 'a', true))
	procs.add(&'event_a', LFProc.new(func(_c): pass).with_chance(0.5))
	assert_eq(procs.fire(&'event_a', plain, 'x'), procs.fire(&'event_a', rng, 'x'))
	assert_true(procs.fire_until_handled(&'event_a', plain))


func test_lookups_of_a_key_with_no_procs():
	assert_eq(procs.count(&'none'), 0)
	assert_eq(procs.procs_for(&'none'), [] as Array[LFProc])
	assert_false(procs.remove(&'none', LFProc.new(func(_c): pass)))
	assert_false(procs.fire_until_handled(&'none', rng))


func test_procs_for_lists_firing_order_and_clear_drops_every_key():
	var a := LFProc.new(func(_c): pass)
	var b := LFProc.new(func(_c): pass)
	procs.add(&'event_a', a)
	procs.add(&'event_a', b)
	procs.add(&'event_b', a)
	assert_eq(procs.procs_for(&'event_a'), [a, b] as Array[LFProc])
	procs.clear()
	assert_false(procs.has(&'event_a'))
	assert_false(procs.has(&'event_b'))
	assert_eq(procs.fire(&'event_a', rng), 0)


class _Owner extends Object:
	func act(_context: Variant) -> bool:
		return true


func test_fire_until_handled_passes_over_a_proc_whose_action_was_freed():
	var gone := _Owner.new()
	var stale := LFProc.new(gone.act).with_charges(2)
	gone.free()
	var log := []
	procs.add(&'event_c', stale)
	procs.add(&'event_c', _logging(log, 'next', true))
	assert_true(procs.fire_until_handled(&'event_c', rng))
	assert_eq(log.size(), 1, 'the next proc handled it')
	assert_eq(stale.charges_left, 2, 'the stale proc is skipped before its gates, so nothing is spent')


func test_fire_skips_a_proc_whose_action_was_freed_without_counting_it():
	var gone := _Owner.new()
	var stale := LFProc.new(gone.act).with_charges(2)
	gone.free()
	var log := []
	procs.add(&'event_c', stale)
	procs.add(&'event_c', _logging(log, 'next'))
	assert_eq(procs.fire(&'event_c', rng), 1, 'only the live proc fired')
	assert_eq(stale.charges_left, 2)


func test_fire_until_handled_with_nobody_handling_returns_false():
	procs.add(&'event_c', LFProc.new(func(_c): return false))
	procs.add(&'event_c', LFProc.new(func(_c): return true).with_chance(0.0))
	assert_false(procs.fire_until_handled(&'event_c', rng))


func test_changes_during_fire_until_handled_take_effect_from_the_next():
	var log := []
	var late := _logging(log, 'late', true)
	procs.add(&'event_c', LFProc.new(func(_c):
		log.append(['first', null])
		procs.add(&'event_c', late)
		return false))
	assert_false(procs.fire_until_handled(&'event_c', rng), 'the proc added mid-walk is not reached')
	log.clear()
	assert_true(procs.fire_until_handled(&'event_c', rng))
	assert_eq(log.map(func(e): return e[0]), ['first', 'late'])
	assert_eq(procs.count(&'event_c'), 2, 'the same proc is not added twice')


var _nested_log: Array = []
var _nested_depth := 0


func _fire_again_then_add(_context: Variant) -> void:
	_nested_log.append('outer')
	if _nested_depth == 0:
		_nested_depth += 1
		procs.fire(&'event_a', rng)
		procs.add(&'event_a', LFProc.new(_log_added))


func _log_added(_context: Variant) -> void:
	_nested_log.append('added')


func test_a_fire_from_inside_a_fire_runs_the_same_bucket_again():
	_nested_log = []
	_nested_depth = 0
	procs.add(&'event_a', LFProc.new(_fire_again_then_add))
	procs.fire(&'event_a', rng)
	assert_eq(_nested_log, ['outer', 'outer'], 'the add made inside the nested fire is not reached by either walk')
	_nested_log.clear()
	procs.fire(&'event_a', rng)
	assert_eq(_nested_log, ['outer', 'added'], 'it counts from the next fire')
