extends GutTest

var health: LFHealth


func before_each():
	health = LFHealth.new(100.0)
	watch_signals(health)


func test_starts_full():
	assert_eq(health.points, 100.0)
	assert_eq(health.max_points, 100.0)
	assert_true(health.is_full())
	assert_false(health.is_dead())


func test_the_default_pool_holds_the_default_maximum():
	assert_eq(LFHealth.new().max_points, LFHealth.DEFAULT_MAX_POINTS)


func test_an_invalid_initial_maximum_is_reported_and_replaced_by_the_default():
	var bad := LFHealth.new(-5.0)
	assert_push_error('maximum')
	assert_eq(bad.max_points, LFHealth.DEFAULT_MAX_POINTS)
	assert_eq(bad.points, LFHealth.DEFAULT_MAX_POINTS)


func test_damage_lowers_points_and_reports_the_amount():
	assert_eq(health.damage(30.0), 70.0)
	assert_signal_emitted_with_parameters(health, 'damaged', [30.0])
	assert_signal_not_emitted(health, 'died')


func test_lethal_damage_clamps_at_zero_and_emits_damaged_then_died_once():
	health.damage(40.0)
	assert_eq(health.damage(500.0), 0.0)
	assert_signal_emit_count(health, 'died', 1)
	assert_signal_emitted_with_parameters(health, 'damaged', [60.0], 1)
	assert_true(health.is_dead())


func test_infinite_damage_empties_the_pool():
	health.damage(INF)
	assert_eq(health.points, 0.0)
	assert_signal_emitted_with_parameters(health, 'damaged', [100.0])


func test_a_dead_pool_ignores_damage_and_heal():
	health.damage(100.0)
	health.damage(5.0)
	health.heal(5.0)
	assert_eq(health.points, 0.0)
	assert_signal_emit_count(health, 'died', 1)
	assert_signal_emit_count(health, 'damaged', 1)
	assert_signal_not_emitted(health, 'healed')


func test_zero_damage_and_zero_heal_emit_nothing():
	health.damage(0.0)
	health.damage(10.0)
	health.heal(0.0)
	assert_signal_emit_count(health, 'damaged', 1)
	assert_signal_not_emitted(health, 'healed')


func test_heal_raises_points_up_to_the_maximum_and_reports_what_was_restored():
	health.damage(30.0)
	assert_eq(health.heal(50.0), 100.0)
	assert_signal_emitted_with_parameters(health, 'healed', [30.0])


func test_healing_a_full_pool_emits_nothing():
	health.heal(10.0)
	assert_signal_not_emitted(health, 'healed')


func test_nan_and_negative_amounts_are_reported_and_ignored():
	health.damage(NAN)
	health.damage(-1.0)
	health.heal(NAN)
	health.heal(-1.0)
	assert_push_error_count(4)
	assert_eq(health.points, 100.0)
	assert_signal_not_emitted(health, 'damaged')
	assert_signal_not_emitted(health, 'healed')


func test_raising_the_maximum_grows_points_by_the_difference():
	health.damage(40.0)
	assert_true(health.set_max(150.0))
	assert_eq(health.max_points, 150.0)
	assert_eq(health.points, 110.0)
	assert_signal_emitted_with_parameters(health, 'max_changed', [150.0])


func test_raising_the_maximum_without_growing_keeps_points():
	health.damage(40.0)
	health.set_max(150.0, false)
	assert_eq(health.points, 60.0)


func test_lowering_the_maximum_clamps_points():
	health.set_max(80.0)
	assert_eq(health.points, 80.0)
	health.damage(70.0)
	health.set_max(50.0)
	assert_eq(health.points, 10.0)


func test_raising_the_maximum_of_a_dead_pool_does_not_revive_it():
	health.damage(100.0)
	health.set_max(200.0)
	assert_eq(health.points, 0.0)
	assert_true(health.is_dead())


func test_setting_the_same_maximum_emits_nothing():
	assert_true(health.set_max(100.0))
	assert_signal_not_emitted(health, 'max_changed')


func test_an_invalid_maximum_is_reported_and_keeps_the_pool():
	for bad in [NAN, 0.0, -3.0, INF]:
		assert_false(health.set_max(bad))
	assert_push_error_count(4)
	assert_eq(health.max_points, 100.0)
	assert_eq(health.points, 100.0)


func test_reset_refills_and_revives_without_signals():
	health.damage(100.0)
	health.reset()
	assert_eq(health.points, 100.0)
	assert_false(health.is_dead())
	assert_signal_emit_count(health, 'damaged', 1)


func test_ratio_and_percent():
	health.damage(25.0)
	assert_almost_eq(health.ratio(), 0.75, 0.0001)
	assert_almost_eq(health.percent(), 75.0, 0.0001)
	health.damage(100.0)
	assert_eq(health.percent(), 0.0)
