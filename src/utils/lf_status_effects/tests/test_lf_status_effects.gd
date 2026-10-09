extends GutTest

## A negative duration or interval override: use the definition's value.
const FROM_DEF := -1.0
## A zero stack-cap override: use the definition's cap.
const FROM_DEF_CAP := 0

var effects: LFStatusEffects


func before_each():
	effects = LFStatusEffects.new()


func _independent(max_stacks := 3, overflow := LFStatusEffectDef.Overflow.DROP, duration := 3.0) -> LFStatusEffectDef:
	return LFStatusEffectDef.new(&'effect_a', LFStatusEffectDef.Accumulation.INDEPENDENT, duration, max_stacks, overflow)


func test_an_inactive_effect_reports_nothing():
	assert_false(effects.has(&'effect_a'))
	assert_eq(effects.count(&'effect_a'), 0)
	assert_eq(effects.remaining(&'effect_a'), 0.0)
	assert_eq(effects.stacks(&'effect_a').size(), 0)
	assert_true(effects.is_empty())


func test_independent_applications_each_add_a_stack():
	var def := _independent()
	effects.apply(def)
	assert_eq(effects.apply(def), 2, 'apply returns the resulting count')
	assert_eq(effects.count(&'effect_a'), 2)


func test_independent_stacks_expire_on_their_own_schedules():
	var def := _independent()
	effects.apply(def)
	effects.tick(1.0)
	effects.apply(def)
	effects.tick(2.0)
	assert_eq(effects.count(&'effect_a'), 1, 'the first stack expired at 3s, the second lives until 4s')
	effects.tick(1.0)
	assert_false(effects.has(&'effect_a'))


func test_drop_overflow_ignores_an_application_at_the_cap():
	var def := _independent(2)
	effects.apply(def)
	effects.tick(1.0)
	effects.apply(def)
	assert_eq(effects.apply(def), 2)
	effects.tick(2.0)
	assert_eq(effects.count(&'effect_a'), 1, 'the dropped application never started its own timer')


func test_replace_oldest_overflow_swaps_out_the_soonest_expiring_stack():
	var def := _independent(2, LFStatusEffectDef.Overflow.REPLACE_OLDEST)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), 'first')
	effects.tick(1.0)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), 'second')
	effects.tick(1.0)
	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), 'third'), 2, 'the cap still holds')
	var payloads := effects.stacks(&'effect_a').map(func(s: LFStatusStack): return s.data)
	assert_eq(payloads, ['second', 'third'], 'the oldest stack was the one replaced')
	effects.tick(1.5)
	assert_eq(effects.count(&'effect_a'), 2, 'the replacement carries a fresh full duration')


func test_shared_reapplication_refreshes_one_duration_and_raises_the_count_up_to_the_cap():
	var def := LFStatusEffectDef.new(&'effect_b', LFStatusEffectDef.Accumulation.SHARED, 2.0, 3)
	effects.apply(def)
	effects.tick(1.5)
	for i in 4:
		effects.apply(def)
	assert_eq(effects.count(&'effect_b'), 3, 'count is capped')
	assert_eq(effects.stacks(&'effect_b').size(), 1, 'shared never adds stacks')
	effects.tick(1.5)
	assert_true(effects.has(&'effect_b'), 'the refresh restarted the 2s duration')
	effects.tick(0.5)
	assert_false(effects.has(&'effect_b'))


func test_per_application_overrides_win_over_the_definition():
	var def := _independent(1)
	effects.apply(def, 10.0, FROM_DEF, 2)
	effects.apply(def, FROM_DEF, FROM_DEF, 2)
	assert_eq(effects.count(&'effect_a'), 2, 'the cap override allowed a second stack')
	effects.apply(def)
	assert_eq(effects.count(&'effect_a'), 2, 'the cap is judged per application: the default cap of 1 drops this one')
	assert_almost_eq(effects.remaining(&'effect_a'), 10.0, 0.001, 'the duration override is the longest-lived stack')


func test_a_tick_fires_once_per_elapsed_interval_and_never_past_expiry():
	var hits := [0]
	var def := LFStatusEffectDef.new(&'effect_d', LFStatusEffectDef.Accumulation.INDEPENDENT, 3.5, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_o, _s): hits[0] += 1)
	effects.apply(def)
	effects.tick(0.5)
	assert_eq(hits[0], 0)
	effects.tick(0.5)
	assert_eq(hits[0], 1)
	effects.tick(10.0)
	assert_eq(hits[0], 3, 'ticks at 2s and 3s catch up; none after the 3.5s expiry')
	assert_false(effects.has(&'effect_d'))


func test_on_tick_receives_the_owner_and_the_stack_payload():
	var seen := []
	var def := LFStatusEffectDef.new(&'effect_d', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 2,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(o, s: LFStatusStack): seen.append([o, s.data]))
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), 'source_a')
	effects.tick(1.0, 'owner')
	assert_eq(seen, [['owner', 'source_a']])


func test_a_per_stack_on_tick_overrides_the_definitions():
	var log := []
	var def := LFStatusEffectDef.new(&'effect_c', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 2,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_o, _s): log.append('def'))
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, func(_o, _s): log.append('stack'))
	effects.tick(1.0)
	assert_eq(log, ['stack'])


func test_stacks_with_their_own_intervals_tick_independently():
	var hits := [0]
	var def := LFStatusEffectDef.new(&'effect_c', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0, 5,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_o, _s): hits[0] += 1)
	effects.apply(def)
	effects.apply(def, FROM_DEF, 0.5)
	effects.tick(1.0)
	assert_eq(hits[0], 3, 'one tick at 1s interval plus two at 0.5s')


func test_changed_fires_on_apply_and_expiry_but_not_on_a_dropped_application():
	var fired := []
	effects.changed.connect(func(id): fired.append(id))
	var def := _independent(1)
	effects.apply(def)
	effects.apply(def)
	assert_eq(fired, [&'effect_a'])
	effects.tick(3.0)
	assert_eq(fired, [&'effect_a', &'effect_a'])


func test_a_non_ticking_effect_never_calls_back():
	var calls := [0]
	var def := LFStatusEffectDef.new(&'effect_f', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 1,
		LFStatusEffectDef.Overflow.DROP, 0.0, func(_o, _s): calls[0] += 1)
	effects.apply(def)
	var stack := effects.stacks(&'effect_f')[0]
	effects.tick(1.0)
	assert_eq(stack.next_tick_at, INF, 'a non-ticking effect never schedules a tick')
	assert_eq(calls[0], 0)
	assert_eq(effects.count(&'effect_f'), 1)


func test_differently_named_effects_coexist():
	effects.apply(_independent())
	effects.apply(LFStatusEffectDef.new(&'effect_i', LFStatusEffectDef.Accumulation.INDEPENDENT, 1.0))
	assert_eq(effects.ids().size(), 2)
	effects.tick(1.0)
	assert_eq(effects.ids(), [&'effect_a'], 'only the 1s effect expired')


func test_remove_and_clear():
	var fired := []
	effects.changed.connect(func(id): fired.append(id))
	effects.apply(_independent())
	effects.apply(LFStatusEffectDef.new(&'effect_i'))
	effects.remove(&'effect_a')
	assert_false(effects.has(&'effect_a'))
	effects.clear()
	assert_true(effects.is_empty())
	assert_eq(fired.count(&'effect_i'), 2, 'apply + clear')
	effects.tick(10.0)
	assert_true(effects.is_empty())


func test_a_tick_callback_that_clears_the_owner_stops_processing_safely():
	var hits := [0]
	var def := LFStatusEffectDef.new(&'effect_c', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 3,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_o, _s):
			hits[0] += 1
			effects.clear())
	effects.apply(def)
	effects.apply(def)
	effects.tick(1.0)
	assert_eq(hits[0], 1, 'the second stack never ticked after the owner was cleared')
	assert_true(effects.is_empty())


func test_a_tick_callback_that_applies_effects_does_not_corrupt_the_walk():
	var spawned := LFStatusEffectDef.new(&'effect_j', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 10)
	var def := LFStatusEffectDef.new(&'effect_c', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 3,
		LFStatusEffectDef.Overflow.DROP, 1.0)
	def.on_tick = func(_o, _s):
		effects.apply(spawned)
		effects.apply(def)
	effects.apply(def)
	effects.tick(1.0)
	assert_eq(effects.count(&'effect_c'), 2, 'the callback added one more stack')
	assert_eq(effects.count(&'effect_j'), 1)
	def.on_tick = Callable()  # the callback captures `def`: break the cycle so it is freed


func test_a_shorter_shared_refresh_never_moves_the_expiry_earlier():
	var def := LFStatusEffectDef.new(&'effect_f', LFStatusEffectDef.Accumulation.SHARED, 10.0, 3)
	effects.apply(def)
	effects.tick(1.0)

	effects.apply(def, 1.0) # would end at t=2, before the current t=10
	effects.tick(1.5)

	assert_true(effects.has(&'effect_f'), 'the longer expiry stands')
	assert_almost_eq(effects.remaining(&'effect_f'), 7.5, 0.0001)


func test_now_advances_with_tick_only_while_an_effect_is_active():
	effects.tick(5.0)
	assert_eq(effects.now(), 0.0, "an empty container's clock does not advance")

	effects.apply(_independent())
	effects.tick(1.0)
	effects.tick(0.5)
	assert_almost_eq(effects.now(), 1.5, 0.0001, "the clock advances by each tick's delta")


func test_stack_times_are_absolute_on_the_container_clock():
	effects.apply(_independent())
	effects.tick(1.0)
	effects.apply(_independent())
	assert_almost_eq(effects.stacks(&'effect_a').back().expires_at, effects.now() + 3.0, 0.0001)


func test_remaining_of_a_shared_effect_counts_down_and_restarts_on_refresh():
	var def := LFStatusEffectDef.new(&'effect_b', LFStatusEffectDef.Accumulation.SHARED, 2.0, 3)
	effects.apply(def)
	assert_almost_eq(effects.remaining(&'effect_b'), 2.0, 0.0001)

	effects.tick(1.5)
	assert_almost_eq(effects.remaining(&'effect_b'), 0.5, 0.0001, "remaining counts down with the clock")

	effects.apply(def)
	assert_almost_eq(effects.remaining(&'effect_b'), 2.0, 0.0001, "a refresh restarts the full duration")

	effects.apply(def, 0.75)
	assert_almost_eq(effects.remaining(&'effect_b'), 2.0, 0.0001, "a shorter refresh never shortens the remaining time")


func test_a_stack_evicted_by_its_own_tick_callback_stops_catching_up():
	var fired := [0]
	var def := LFStatusEffectDef.new(&'effect_e', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0, 1, LFStatusEffectDef.Overflow.REPLACE_OLDEST, 1.0)
	def.on_tick = func(_owner, _stack: LFStatusStack):
		fired[0] += 1
		effects.apply(def) # at the cap: evicts the ticking stack
	effects.apply(def)

	effects.tick(3.0) # three ticks were due on the original stack

	assert_eq(fired[0], 1, 'an evicted stack must not keep firing its remaining due ticks')
	assert_eq(effects.count(&'effect_e'), 1)
	def.on_tick = Callable()  # the callback captures `def`: break the cycle so it is freed


func test_an_expiry_is_still_announced_when_a_later_tick_callback_clears_the_owner():
	var fired: Array[StringName] = []
	effects.changed.connect(func(id): fired.append(id))
	var short := LFStatusEffectDef.new(&'short', LFStatusEffectDef.Accumulation.INDEPENDENT, 1.0)
	var clearing := LFStatusEffectDef.new(&'clearing', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_owner, _stack): effects.clear())
	effects.apply(short)
	effects.apply(clearing)
	fired.clear()

	effects.tick(1.0)

	assert_true(effects.is_empty())
	assert_true(fired.has(&'short'), 'the effect that expired before the clear is announced')
	assert_true(fired.has(&'clearing'), 'the cleared effect is announced by clear()')


func test_zero_overrides_are_honoured_and_only_negative_ones_fall_back():
	var ticking := LFStatusEffectDef.new(&'effect_c', LFStatusEffectDef.Accumulation.INDEPENDENT, 3.0, 2,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_o, _s): pass)
	effects.apply(ticking, FROM_DEF, 0.0)
	var stack: LFStatusStack = effects.stacks(&'effect_c')[0]
	assert_eq(stack.expires_at, 3.0, 'a negative duration falls back to the definition')
	assert_eq(stack.next_tick_at, INF, 'a zero tick interval override means the stack never ticks')

	effects.apply(ticking, 0.0)
	effects.tick(0.0001)
	assert_eq(effects.count(&'effect_c'), 1, 'a zero duration override expires on the next tick')


# --- Re-application never lowers the count ---

func test_a_lower_cap_shared_refresh_never_lowers_the_count():
	var def := LFStatusEffectDef.new(&'effect_b', LFStatusEffectDef.Accumulation.SHARED, 4.0, 5)
	for i in 5:
		effects.apply(def)
	var fired := [0]
	effects.changed.connect(func(_id): fired[0] += 1)

	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, 2), 5)
	assert_eq(effects.count(&'effect_b'), 5)
	assert_eq(fired[0], 1, 'a refresh is still announced')


func test_a_lower_cap_shared_refresh_still_refreshes_and_replaces_data():
	var def := LFStatusEffectDef.new(&'effect_b', LFStatusEffectDef.Accumulation.SHARED, 4.0, 5)
	for i in 4:
		effects.apply(def)
	effects.tick(3.0)
	effects.apply(def, FROM_DEF, FROM_DEF, 1, Callable(), 'weak')
	assert_almost_eq(effects.remaining(&'effect_b'), 4.0, 0.0001)
	assert_eq(effects.stacks(&'effect_b')[0].data, 'weak')


func test_replace_oldest_at_a_lower_cap_swaps_exactly_one_stack():
	var def := _independent(5, LFStatusEffectDef.Overflow.REPLACE_OLDEST)
	for i in 5:
		effects.apply(def)
		effects.tick(0.1)
	var oldest := effects.stacks(&'effect_a')[0]
	var fired := [0]
	effects.changed.connect(func(_id): fired[0] += 1)

	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, 2), 5)
	assert_false(effects.stacks(&'effect_a').has(oldest), 'the soonest-expiring stack made room')
	assert_eq(fired[0], 1)


func test_drop_at_a_lower_cap_changes_nothing():
	var def := _independent(5)
	for i in 4:
		effects.apply(def)
	var fired := [0]
	effects.changed.connect(func(_id): fired[0] += 1)
	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, 2), 4)
	assert_eq(effects.count(&'effect_a'), 4)
	assert_eq(fired[0], 0)


func test_the_first_definition_applied_governs_while_the_effect_is_active():
	var strong := LFStatusEffectDef.new(&'effect_g', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0, 5)
	var weak := LFStatusEffectDef.new(&'effect_g', LFStatusEffectDef.Accumulation.INDEPENDENT, 1.0, 1)
	effects.apply(strong)
	assert_eq(effects.apply(weak), 2, "the live definition's cap of 5 applies, not the later one's 1")
	assert_almost_eq(effects.stacks(&'effect_g').back().expires_at, 10.0, 0.0001, "and its duration")


# --- Ticking ---

func test_an_interval_without_any_callback_never_schedules_a_tick():
	var def := LFStatusEffectDef.new(&'effect_h', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0)
	effects.apply(def)
	var stack := effects.stacks(&'effect_h')[0]
	assert_eq(stack.next_tick_at, INF)
	assert_eq(stack.tick_interval, 0.0, 'the effective interval: it never ticks')


func test_a_per_application_interval_ticks_with_a_stack_callback():
	var hits := [0]
	var def := LFStatusEffectDef.new(&'effect_h', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 1)
	effects.apply(def, FROM_DEF, 1.0, FROM_DEF_CAP, func(_o, _s): hits[0] += 1)
	effects.tick(2.0)
	assert_eq(hits[0], 2)


func test_a_tick_landing_exactly_on_expiry_fires():
	var hits := [0]
	var def := LFStatusEffectDef.new(&'effect_c', LFStatusEffectDef.Accumulation.INDEPENDENT, 2.0, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_o, _s): hits[0] += 1)
	effects.apply(def)
	effects.tick(5.0)
	assert_eq(hits[0], 2)


func test_a_negative_nan_or_infinite_delta_is_ignored():
	effects.apply(_independent(3, LFStatusEffectDef.Overflow.DROP, 2.0))
	for bad in [-1.0, NAN, INF, -INF]:
		effects.tick(bad)
		assert_eq(effects.now(), 0.0)
	effects.tick(2.0)
	assert_false(effects.has(&'effect_a'), 'later expiries still happen')


func test_a_tick_callback_removing_its_own_effect_stops_the_walk():
	var hits := [0]
	var def := LFStatusEffectDef.new(&'effect_c', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 3,
		LFStatusEffectDef.Overflow.DROP, 1.0)
	def.on_tick = func(_o, _s):
		hits[0] += 1
		effects.remove(&'effect_c')
	effects.apply(def)
	effects.apply(def)
	effects.tick(3.0)
	assert_eq(hits[0], 1)
	assert_false(effects.has(&'effect_c'))


func test_removing_an_inactive_effect_announces_nothing():
	var fired := [0]
	effects.changed.connect(func(_id): fired[0] += 1)
	effects.remove(&'nothing')
	assert_eq(fired[0], 0)


func test_ids_are_typed():
	effects.apply(_independent())
	var ids: Array[StringName] = effects.ids()
	assert_eq(ids, [&'effect_a'])


# --- Per-source caps ---

func _per_source(max_stacks := 2, overflow := LFStatusEffectDef.Overflow.DROP) -> LFStatusEffectDef:
	var def := LFStatusEffectDef.new(&'effect_d', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, max_stacks, overflow)
	def.cap_per_source = true
	return def


func test_a_per_source_cap_counts_only_that_sources_stacks():
	var def := _per_source(2)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'a')
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'a')
	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'a'), 2, "a's third is dropped")
	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'b'), 3, 'b stacks on its own cap')
	assert_eq(effects.count(&'effect_d'), 3, 'count is the total')


func test_a_per_source_cap_honours_each_applications_own_cap():
	var def := _per_source(1)
	effects.apply(def, FROM_DEF, FROM_DEF, 3, Callable(), null, 'strong')
	effects.apply(def, FROM_DEF, FROM_DEF, 3, Callable(), null, 'strong')
	effects.apply(def, FROM_DEF, FROM_DEF, 1, Callable(), null, 'weak')
	assert_eq(effects.count(&'effect_d'), 3)


func test_per_source_replace_oldest_evicts_only_that_sources_stack():
	var def := _per_source(1, LFStatusEffectDef.Overflow.REPLACE_OLDEST)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'a')
	effects.tick(0.1)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'b')
	effects.tick(0.1)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'b')
	var sources := effects.stacks(&'effect_d').map(func(s: LFStatusStack): return s.source)
	sources.sort()
	assert_eq(sources, ['a', 'b'], "b replaced its own stack, a's stayed")


func test_without_a_per_source_cap_the_source_is_only_recorded():
	var def := _independent(1)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'a')
	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'b'), 1, 'the cap is the total')
	assert_eq(effects.stacks(&'effect_a')[0].source, 'a')


func test_sources_of_different_types_are_different_sources():
	var def := _per_source(1)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 1)
	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, '1'), 2)
	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 1), 2, 'the int source is at its cap')


func test_a_shared_refresh_keeps_the_first_interval_and_callback():
	var log := []
	var def := LFStatusEffectDef.new(&'effect_b', LFStatusEffectDef.Accumulation.SHARED, 10.0, 5,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_o, _s): log.append('first'))
	effects.apply(def)
	effects.apply(def, FROM_DEF, 0.1, FROM_DEF_CAP, func(_o, _s): log.append('second'))
	effects.tick(1.0)
	assert_eq(log, ['first'], 'still every second, through the first callback')
	assert_eq(effects.stacks(&'effect_b')[0].tick_interval, 1.0)


func test_a_shared_refresh_keeps_the_first_source():
	var def := LFStatusEffectDef.new(&'effect_b', LFStatusEffectDef.Accumulation.SHARED, 10.0, 5)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'first')
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, Callable(), null, 'second')
	assert_eq(effects.stacks(&'effect_b')[0].source, 'first')


func test_a_shared_refresh_at_the_cap_still_announces_a_change():
	var fired := []
	effects.changed.connect(func(id): fired.append(id))
	var def := LFStatusEffectDef.new(&'effect_b', LFStatusEffectDef.Accumulation.SHARED, 10.0, 1)
	effects.apply(def)
	assert_eq(effects.apply(def), 1, 'at the cap')
	assert_eq(fired, [&'effect_b', &'effect_b'])


func test_shared_definitions_are_one_object_per_policy():
	var Acc := LFStatusEffectDef.Accumulation
	var Over := LFStatusEffectDef.Overflow
	var a := LFStatusEffectDef.shared(&'test_shared_def', Acc.INDEPENDENT, Over.DROP)
	assert_same(LFStatusEffectDef.shared(&'test_shared_def', Acc.INDEPENDENT, Over.DROP), a)
	assert_eq(a.id, &'test_shared_def')
	assert_eq(a.accumulation, Acc.INDEPENDENT)
	assert_eq(a.overflow, Over.DROP)
	assert_false(a.cap_per_source)
	var others := [
		LFStatusEffectDef.shared(&'test_shared_def', Acc.SHARED, Over.DROP),
		LFStatusEffectDef.shared(&'test_shared_def', Acc.INDEPENDENT, Over.REPLACE_OLDEST),
		LFStatusEffectDef.shared(&'test_shared_def', Acc.INDEPENDENT, Over.DROP, true),
		LFStatusEffectDef.shared(&'test_shared_def_2', Acc.INDEPENDENT, Over.DROP),
	]
	for other in others:
		assert_ne(other, a)
	assert_true(others[2].cap_per_source)
	assert_eq(others[1].overflow, Over.REPLACE_OLDEST)
	assert_eq(others[0].accumulation, Acc.SHARED)


func _noop_tick(_owner: Variant, _stack: LFStatusStack) -> void:
	pass


func test_a_definition_keeps_every_constructor_argument():
	var def := LFStatusEffectDef.new(&'effect_e', LFStatusEffectDef.Accumulation.SHARED, 4.0, 3,
		LFStatusEffectDef.Overflow.REPLACE_OLDEST, 0.5, _noop_tick)
	assert_eq(def.id, &'effect_e')
	assert_eq(def.accumulation, LFStatusEffectDef.Accumulation.SHARED)
	assert_eq(def.duration, 4.0)
	assert_eq(def.max_stacks, 3)
	assert_eq(def.overflow, LFStatusEffectDef.Overflow.REPLACE_OLDEST)
	assert_eq(def.tick_interval, 0.5)
	assert_eq(def.on_tick, Callable(self, &'_noop_tick'))
	assert_false(def.cap_per_source)


func test_a_default_definition_is_one_second_one_stack_and_never_ticks():
	var def := LFStatusEffectDef.new()
	assert_eq(def.id, &'')
	assert_eq(def.accumulation, LFStatusEffectDef.Accumulation.INDEPENDENT)
	assert_eq(def.duration, 1.0)
	assert_eq(def.max_stacks, 1)
	assert_eq(def.overflow, LFStatusEffectDef.Overflow.DROP)
	assert_eq(def.tick_interval, 0.0)
	assert_false(def.on_tick.is_valid())


func test_a_stack_records_its_schedule_payload_and_source():
	var def := LFStatusEffectDef.new(&'effect_e', LFStatusEffectDef.Accumulation.INDEPENDENT, 4.0, 1,
		LFStatusEffectDef.Overflow.DROP, 0.5)
	effects.tick(1.0)
	effects.apply(def, FROM_DEF, FROM_DEF, FROM_DEF_CAP, _noop_tick, {'amount': 3}, &'source_c')
	var stack: LFStatusStack = effects.stacks(&'effect_e')[0]
	assert_eq(stack.expires_at, effects.now() + 4.0)
	assert_eq(stack.tick_interval, 0.5)
	assert_eq(stack.next_tick_at, effects.now() + 0.5)
	assert_eq(stack.count, 1)
	assert_eq(stack.data, {'amount': 3})
	assert_eq(stack.on_tick, Callable(self, &'_noop_tick'))
	assert_eq(stack.source, &'source_c')


func test_a_stack_built_directly_keeps_its_arguments():
	var stack := LFStatusStack.new(5.0, 1.0, 2.0, 'payload', _noop_tick)
	assert_eq(stack.expires_at, 5.0)
	assert_eq(stack.tick_interval, 1.0)
	assert_eq(stack.next_tick_at, 2.0)
	assert_eq(stack.data, 'payload')
	assert_eq(stack.on_tick, Callable(self, &'_noop_tick'))
	assert_eq(LFStatusStack.new().next_tick_at, INF, 'never ticks by default')


func test_applying_a_null_definition_is_reported_and_applies_nothing():
	assert_eq(effects.apply(null), 0)
	assert_push_error('null')
	assert_true(effects.is_empty())


func test_a_tick_callback_re_applying_an_effect_that_expires_in_the_same_pass_starts_it_afresh():
	var fired: Array[StringName] = []
	effects.changed.connect(func(id): fired.append(id))
	var buff := LFStatusEffectDef.new(&'buff', LFStatusEffectDef.Accumulation.SHARED, 1.0, 5)
	var ticker := LFStatusEffectDef.new(&'ticker', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_owner, _stack): effects.apply(buff))
	effects.apply(ticker) # walked before the buff in the pass
	effects.apply(buff)
	effects.apply(buff)
	fired.clear()

	effects.tick(1.0) # the buff expires and the ticker re-applies it, in one pass

	assert_eq(effects.count(&'buff'), 1, 'the expired buff is not revived: the re-application starts at 1')
	assert_eq(effects.remaining(&'buff'), 1.0)
	assert_eq(fired.count(&'buff'), 2, 'both the expiry and the re-application are announced')
	ticker.on_tick = Callable()  # the callback captures `buff` and `effects`: break the cycle


func test_a_drop_cap_never_counts_stacks_that_expire_in_the_same_pass():
	var buff := LFStatusEffectDef.new(&'buff', LFStatusEffectDef.Accumulation.INDEPENDENT, 1.0, 2)
	var ticker := LFStatusEffectDef.new(&'ticker', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_owner, _stack): effects.apply(buff))
	effects.apply(ticker)
	effects.apply(buff)
	effects.apply(buff) # at the cap of 2

	effects.tick(1.0) # both buff stacks expire as the ticker re-applies it

	assert_eq(effects.count(&'buff'), 1, 'the two expired stacks left room for the new one')
	ticker.on_tick = Callable()


func test_an_expiring_stack_still_fires_its_last_tick_when_another_callback_re_applies_it():
	var hits := [0]
	var dot := LFStatusEffectDef.new(&'dot', LFStatusEffectDef.Accumulation.INDEPENDENT, 1.0, 3,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_owner, _stack): hits[0] += 1)
	var ticker := LFStatusEffectDef.new(&'ticker', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_owner, _stack): effects.apply(dot))
	effects.apply(ticker)
	effects.apply(dot)

	effects.tick(1.0)

	assert_eq(hits[0], 1, 'the expiring stack ticked once, at its expiry; the new one ticks at 2s')
	assert_eq(effects.count(&'dot'), 1)
	ticker.on_tick = Callable()


## A tick callback of one effect removes another (a cleanse): the removed effect fires no
## tick after that, not even the last one of a stack that expired in the same pass.
func test_an_effect_removed_by_another_effects_tick_fires_no_more_ticks():
	var dot_hits := [0]
	var cleanse := LFStatusEffectDef.new(&'cleanse', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0, 1,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_owner, _stack): effects.remove(&'dot'))
	var dot := LFStatusEffectDef.new(&'dot', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0, 3,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(_owner, _stack): dot_hits[0] += 1)
	effects.apply(cleanse) # walked before the dot in the pass
	effects.apply(dot, 1.0) # expires at 1 s, its last tick due then
	effects.apply(dot) # lasts 5 s, ticking

	effects.tick(1.0)

	assert_eq(dot_hits[0], 0, 'the cleanse removed the dot before any of its ticks fired')
	assert_false(effects.has(&'dot'))
	cleanse.on_tick = Callable()  # the callback captures `effects`: break the cycle


func test_a_cap_below_one_counts_as_one():
	var def := LFStatusEffectDef.new(&'effect_z', LFStatusEffectDef.Accumulation.INDEPENDENT, 3.0, 0)
	effects.apply(def)
	assert_eq(effects.apply(def), 1, 'a definition cap of 0 still allows one stack')
	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, -2), 1, 'a negative override falls back to the definition')
	assert_eq(effects.apply(def, FROM_DEF, FROM_DEF, 2), 2, 'a positive override raises the cap')


func test_a_zero_duration_shared_effect_expires_on_the_next_tick():
	var def := LFStatusEffectDef.new(&'flash', LFStatusEffectDef.Accumulation.SHARED, 0.0)
	effects.apply(def)
	assert_true(effects.has(&'flash'))
	effects.tick(0.0)
	assert_false(effects.has(&'flash'))


func test_the_owner_passed_to_tick_reaches_every_callback():
	var owners := []
	var def := LFStatusEffectDef.new(&'effect_o', LFStatusEffectDef.Accumulation.INDEPENDENT, 2.0, 2,
		LFStatusEffectDef.Overflow.DROP, 1.0, func(owner, _stack): owners.append(owner))
	effects.apply(def)
	effects.apply(def)
	effects.tick(2.0, 'the owner')
	assert_eq(owners, ['the owner', 'the owner', 'the owner', 'the owner'], 'two stacks, two ticks each')


## A NaN duration or tick interval on a definition is rejected when it is set: reported,
## and the field keeps its value.
func test_a_nan_definition_duration_or_tick_interval_is_rejected():
	var def := LFStatusEffectDef.new(&'effect_a', LFStatusEffectDef.Accumulation.INDEPENDENT,
		NAN, 5, LFStatusEffectDef.Overflow.DROP, NAN)
	assert_push_error_count(2)
	assert_eq(def.duration, LFStatusEffectDef.DEFAULT_DURATION)
	assert_eq(def.tick_interval, LFStatusEffectDef.DEFAULT_TICK_INTERVAL)

	def.duration = 3.0
	def.tick_interval = 0.5
	def.duration = NAN
	def.tick_interval = NAN
	assert_push_error_count(4)
	assert_eq([def.duration, def.tick_interval], [3.0, 0.5], 'kept')


## A NaN override on apply() is rejected: reported, nothing applied, 0 returned.
func test_nan_overrides_are_rejected_and_apply_nothing():
	var def := LFStatusEffectDef.new(&'effect_a', LFStatusEffectDef.Accumulation.INDEPENDENT,
		1.0, 5, LFStatusEffectDef.Overflow.DROP, 0.5, func(_owner, _stack): pass)

	assert_eq(effects.apply(def, NAN), 0)
	assert_push_error('NaN duration')
	assert_eq(effects.apply(def, 2.0, NAN), 0)
	assert_push_error('NaN tick interval')

	assert_false(effects.has(&'effect_a'))
	assert_eq(effects.apply(def), 1, 'a good application still works')


var _changed_ids: Array[StringName] = []


func _on_changed(id: StringName) -> void:
	_changed_ids.append(id)


## One pass in which several effects end and others keep ticking: the ended ones are gone
## (and announced once each), the others keep their ticks and their next due time.
func test_effects_ending_in_a_pass_among_ones_still_ticking():
	effects.changed.connect(_on_changed)
	_changed_ids.clear()
	var ticks := {}
	var tick_long := func(_owner, _stack): ticks[&'long'] = ticks.get(&'long', 0) + 1
	var tick_short := func(_owner, _stack): ticks[&'short_b'] = ticks.get(&'short_b', 0) + 1
	var short_a := LFStatusEffectDef.new(&'short_a', LFStatusEffectDef.Accumulation.INDEPENDENT, 1.0)
	var short_b := LFStatusEffectDef.new(&'short_b', LFStatusEffectDef.Accumulation.INDEPENDENT, 1.0)
	var long := LFStatusEffectDef.new(&'long', LFStatusEffectDef.Accumulation.INDEPENDENT, 5.0)
	effects.apply(short_a)
	effects.apply(long, FROM_DEF, 0.5, FROM_DEF_CAP, tick_long)
	effects.apply(short_b, FROM_DEF, 0.5, FROM_DEF_CAP, tick_short)
	_changed_ids.clear()
	effects.tick(1.0)
	assert_eq(effects.ids(), [&'long'] as Array[StringName])
	assert_eq(_changed_ids, [&'short_a', &'short_b'] as Array[StringName])
	assert_eq(ticks, {&'long': 2, &'short_b': 2}, 'ticks up to and at the expiry still fire')
	effects.tick(0.5)
	assert_eq(ticks[&'long'], 3, 'the one left keeps ticking on time')


func test_a_tiny_tick_interval_is_raised_to_the_minimum_so_a_tick_always_ends():
	var ticks := [0]
	var def := LFStatusEffectDef.new(&'effect_a', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0, 1, LFStatusEffectDef.Overflow.DROP, 1e-300, func(_owner, _stack): ticks[0] += 1)
	effects.apply(def)
	var stack := effects.stacks(&'effect_a')[0]
	assert_eq(stack.tick_interval, LFStatusEffects.MIN_TICK_INTERVAL)
	effects.tick(1.0)
	assert_almost_eq(float(ticks[0]), 1.0 / LFStatusEffects.MIN_TICK_INTERVAL, 1.0)
