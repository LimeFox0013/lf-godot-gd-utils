extends GutTest


func test_misses_build_a_streak_and_a_hit_resets_it():
	var pity := LFPityTracker.new(3, 2)
	pity.record(0)
	pity.record(1)
	assert_eq(pity.streak, 2)
	pity.record(2)
	assert_eq(pity.streak, 0, 'at the threshold is a hit')


func test_it_activates_at_exactly_the_streak_length():
	var pity := LFPityTracker.new(3, 2)
	pity.record(0)
	pity.record(0)
	assert_false(pity.is_active())
	pity.record(0)
	assert_true(pity.is_active())


func test_the_floor_is_the_threshold_while_active():
	var pity := LFPityTracker.new(1, 3)
	assert_eq(pity.floor_tier(), 0)
	assert_eq(pity.floor_tier(1), 1)
	pity.record(0)
	assert_eq(pity.floor_tier(), 3)
	assert_eq(pity.floor_tier(4), 4, 'a higher base floor wins')


func test_activated_is_announced_once_on_reaching_the_length():
	var pity := LFPityTracker.new(2, 1)
	var fired := [0]
	pity.activated.connect(func(): fired[0] += 1)
	for i in 4:
		pity.record(0)
	assert_eq(fired[0], 1)


func test_outcomes_can_be_recorded_as_hit_or_miss():
	var pity := LFPityTracker.new(2)
	pity.record_outcome(false)
	pity.record_outcome(false)
	assert_true(pity.is_active())
	pity.record_outcome(true)
	assert_false(pity.is_active())


func test_a_length_below_one_never_activates():
	var pity := LFPityTracker.new(0, 1)
	for i in 10:
		pity.record(0)
	assert_false(pity.is_active())
	assert_eq(pity.floor_tier(), 0)


func test_reset_turns_the_guarantee_off_and_trackers_are_independent():
	var a := LFPityTracker.new(2, 1)
	var b := LFPityTracker.new(5, 3)
	a.record(0)
	a.record(0)
	assert_true(a.is_active())
	assert_eq(b.streak, 0)
	a.reset()
	assert_eq(a.streak, 0)
	assert_false(a.is_active())


func test_the_length_and_threshold_can_change_later():
	var pity := LFPityTracker.new()
	assert_eq(pity.streak_length, 10)
	assert_eq(pity.threshold, 1)
	pity.streak_length = 2
	pity.threshold = 3
	pity.record(2)
	pity.record(2)
	assert_true(pity.is_active(), 'tier 2 is a miss under the raised threshold')
	assert_eq(pity.floor_tier(), 3)


func test_activated_is_announced_again_for_a_new_streak():
	var pity := LFPityTracker.new(1, 1)
	var fired := [0]
	pity.activated.connect(func(): fired[0] += 1)
	pity.record(0)
	pity.record(1)
	pity.record(0)
	assert_eq(fired[0], 2)


func test_lowering_the_length_below_the_streak_turns_the_guarantee_on_silently():
	var pity := LFPityTracker.new(10, 1)
	var fired := [0]
	pity.activated.connect(func(): fired[0] += 1)
	for i in 5:
		pity.record(0)
	pity.streak_length = 3
	assert_true(pity.is_active())
	pity.record(0)
	assert_eq(fired[0], 0, 'the streak passed the new length without landing on it')


func test_the_defaults_are_the_named_constants():
	var pity := LFPityTracker.new()
	assert_eq(pity.streak_length, LFPityTracker.DEFAULT_STREAK_LENGTH)
	assert_eq(pity.threshold, LFPityTracker.DEFAULT_THRESHOLD)


func test_reset_announces_nothing_and_a_new_streak_announces_again():
	var pity := LFPityTracker.new(1, 1)
	var fired := [0]
	pity.activated.connect(func(): fired[0] += 1)
	pity.record(0)
	pity.reset()
	assert_eq(fired[0], 1, 'reset is silent')
	pity.record(0)
	assert_eq(fired[0], 2)


func test_dropping_the_length_below_one_turns_an_active_guarantee_off():
	var pity := LFPityTracker.new(2, 1)
	pity.record(0)
	pity.record(0)
	assert_true(pity.is_active())
	pity.streak_length = 0
	assert_false(pity.is_active())
	assert_eq(pity.floor_tier(), 0)
	pity.streak_length = -3
	pity.record(0)
	assert_false(pity.is_active(), 'a negative length is off too')


func test_raising_the_length_past_the_streak_turns_the_guarantee_off_until_it_is_reached():
	var pity := LFPityTracker.new(2, 1)
	var fired := [0]
	pity.activated.connect(func(): fired[0] += 1)
	pity.record(0)
	pity.record(0)
	pity.streak_length = 3
	assert_false(pity.is_active())
	pity.record(0)
	assert_true(pity.is_active())
	assert_eq(fired[0], 2, 'reaching the new length announces it')


func test_a_tier_above_the_threshold_is_a_hit_too():
	var pity := LFPityTracker.new(3, 1)
	pity.record(0)
	pity.record(5)
	assert_eq(pity.streak, 0)
