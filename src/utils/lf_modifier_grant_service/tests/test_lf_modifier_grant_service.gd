extends GutTest

var service: LFModifierGrantService
var _bonus := 0


func _cap_bonus(_owner: Variant) -> int:
	return _bonus


func before_each():
	_bonus = 0
	service = LFModifierGrantService.new()


func test_below_the_cap_a_grant_counts_and_runs_on_grant():
	var seen := []
	var outcome := service.grant("a", &"id_a", 2, func(): seen.append(service.count_for("a", &"id_a")))
	assert_eq(outcome, LFModifierGrantService.Outcome.GRANTED)
	assert_eq(seen, [1], "on_grant runs after the grant is counted")


func test_at_the_cap_without_on_overflow_it_is_a_hard_stop():
	service.grant("a", &"id_a", 1)
	var ran := [false]
	var outcome := service.grant("a", &"id_a", 1, func(): ran[0] = true)
	assert_eq(outcome, LFModifierGrantService.Outcome.REJECTED)
	assert_false(ran[0])
	assert_eq(service.count_for("a", &"id_a"), 1)


func test_at_the_cap_with_on_overflow_it_converts():
	service.grant("a", &"id_a", 1)
	var converted := [0]
	var outcome := service.grant("a", &"id_a", 1, Callable(), func(): converted[0] += 1)
	assert_eq(outcome, LFModifierGrantService.Outcome.CONVERTED)
	assert_eq(converted[0], 1)
	assert_eq(service.count_for("a", &"id_a"), 1, "a conversion doesn't count")


func test_exactly_one_signal_per_attempt():
	var log := []
	service.granted.connect(func(o, id, n): log.append(["granted", o, id, n]))
	service.rejected.connect(func(o, id): log.append(["rejected", o, id]))
	service.converted.connect(func(o, id): log.append(["converted", o, id]))
	service.grant("a", &"id_a", 1)
	service.grant("a", &"id_a", 1)
	service.grant("a", &"id_a", 1, Callable(), func(): pass)
	assert_eq(log, [["granted", "a", &"id_a", 1], ["rejected", "a", &"id_a"], ["converted", "a", &"id_a"]])


func test_the_cap_bonus_is_read_at_every_attempt():
	service = LFModifierGrantService.new(null, _cap_bonus)
	assert_eq(service.grant("a", &"id_a", 1), LFModifierGrantService.Outcome.GRANTED)
	assert_eq(service.grant("a", &"id_a", 1), LFModifierGrantService.Outcome.REJECTED)
	_bonus = 1
	assert_eq(service.effective_cap("a", &"", 1), 2)
	assert_true(service.has_capacity("a", &"id_a", 1))
	assert_eq(service.grant("a", &"id_a", 1), LFModifierGrantService.Outcome.GRANTED)


func test_two_services_on_one_tracker_draw_down_one_cap():
	var tracker := LFCappedLevelTracker.new()
	var service_a := LFModifierGrantService.new(tracker)
	var service_b := LFModifierGrantService.new(tracker)
	service_a.grant("a", &"id_a", 2)
	service_b.grant("a", &"id_a", 2, Callable(), func(): pass)
	assert_eq(service_a.grant("a", &"id_a", 2), LFModifierGrantService.Outcome.REJECTED)
	assert_true(is_same(service_a.tracker, tracker))


func test_owners_and_ids_are_independent():
	service.grant("a", &"id_a", 1)
	assert_eq(service.grant("b", &"id_a", 1), LFModifierGrantService.Outcome.GRANTED)
	assert_eq(service.grant("a", &"other", 1), LFModifierGrantService.Outcome.GRANTED)


func test_clear_forgets_every_grant():
	service.grant("a", &"id_a", 1)
	service.clear()
	assert_eq(service.count_for("a", &"id_a"), 0)


func test_a_two_argument_cap_bonus_gets_the_id():
	var asked: Array = []
	var bonus_for := func(owner: Variant, id: StringName) -> int:
		asked.append([owner, id])
		return 1 if id == &"id_a" else 0
	var per_id := LFModifierGrantService.new(null, bonus_for)
	assert_eq(per_id.grant("a", &"id_a", 1), LFModifierGrantService.Outcome.GRANTED)
	assert_eq(per_id.grant("a", &"id_a", 1), LFModifierGrantService.Outcome.GRANTED, 'the bonus raised this id\'s cap')
	assert_eq(per_id.grant("a", &"other", 1), LFModifierGrantService.Outcome.GRANTED)
	assert_eq(per_id.grant("a", &"other", 1), LFModifierGrantService.Outcome.REJECTED, 'not this one\'s')
	assert_true(asked.has(["a", &"other"]))
	assert_eq(per_id.effective_cap("a", &"id_a", 2), 3)


func test_a_modifier_levels_per_id_cap_bonus_pairs_with_the_service():
	var levels := LFModifierLevels.new()
	levels.declare(&"open", {})
	levels.declare(&"fixed", {}, [], false)
	levels.add_cap_bonus("a", 1)
	var paired := LFModifierGrantService.new(levels.tracker, levels.cap_bonus_for)
	assert_true(paired.has_capacity("a", &"open", 0), 'the bonus applies')
	assert_false(paired.has_capacity("a", &"fixed", 0), 'the id refuses it')


func test_a_one_argument_cap_bonus_still_applies_to_every_id():
	_bonus = 1
	var service_with_bonus := LFModifierGrantService.new(null, _cap_bonus)
	assert_eq(service_with_bonus.effective_cap("a", &"", 2), 3)
	assert_eq(service_with_bonus.effective_cap("a", &"anything", 2), 3)


func test_forget_drops_one_owners_grants():
	service.grant("a", &"id_a", 1)
	service.grant("b", &"id_a", 1)
	service.forget("a")
	assert_eq(service.count_for("a", &"id_a"), 0)
	assert_eq(service.count_for("b", &"id_a"), 1)
	assert_eq(service.grant("a", &"id_a", 1), LFModifierGrantService.Outcome.GRANTED)


func test_a_per_id_cap_bonus_asked_without_an_id_gets_an_empty_id():
	var asked: Array = []
	var bonus_for := func(owner: Variant, id: StringName) -> int:
		asked.append([owner, id])
		return 2
	var per_id := LFModifierGrantService.new(null, bonus_for)
	assert_eq(per_id.effective_cap("a", &"", 1), 3)
	assert_eq(asked, [["a", &""]])


func test_without_a_bonus_callback_the_cap_is_the_cap():
	assert_eq(service.effective_cap("a", &"id_a", 4), 4)
	assert_false(service.has_capacity("a", &"id_a", 0))
	assert_true(service.has_capacity("a", &"id_a", 1))


func test_granted_fires_after_on_grant_and_on_overflow_runs_before_converted():
	var order := []
	service.granted.connect(func(_o, _id, _n): order.append("granted"))
	service.converted.connect(func(_o, _id): order.append("converted"))
	service.grant("a", &"id_a", 1, func(): order.append("on_grant"))
	service.grant("a", &"id_a", 1, Callable(), func(): order.append("on_overflow"))
	assert_eq(order, ["on_grant", "granted", "on_overflow", "converted"])


func test_a_counted_grant_also_fires_the_trackers_raised():
	var raised := []
	service.tracker.raised.connect(func(owner, id, level): raised.append([owner, id, level]))
	service.grant("a", &"id_a", 2)
	service.grant("a", &"id_a", 2)
	service.grant("a", &"id_a", 2)
	assert_eq(raised, [["a", &"id_a", 1], ["a", &"id_a", 2]], 'a rejected grant raises nothing')


func test_clear_and_forget_are_announced_by_the_tracker():
	var heard := []
	service.tracker.cleared.connect(func(): heard.append("cleared"))
	service.tracker.forgotten.connect(func(owner): heard.append(["forgotten", owner]))
	service.grant("a", &"id_a", 1)
	service.forget("a")
	service.clear()
	assert_eq(heard, [["forgotten", "a"], "cleared"])


func test_a_rejected_or_converted_grant_does_not_run_on_grant():
	service.grant("a", &"id_a", 1)
	var ran := [0]
	service.grant("a", &"id_a", 1, func(): ran[0] += 1, func(): pass)
	assert_eq(ran[0], 0)
