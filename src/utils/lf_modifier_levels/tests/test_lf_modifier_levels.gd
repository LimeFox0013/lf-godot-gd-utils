extends GutTest

var levels: LFModifierLevels


func before_each():
	levels = LFModifierLevels.new()
	levels.declare(&"mod_a", {"stat_a": 2.0}, [&"group_a"])
	levels.declare(&"mod_b", {"stat_b": 0.5, "stat_c": 0.1}, [&"group_a", &"group_b"])


func test_declaring_an_id_twice_is_rejected_and_keeps_the_first():
	assert_false(levels.declare(&"mod_a", {"stat_a": 99.0}))
	assert_push_error("already declared")
	levels.grant("a", &"mod_a", 5)
	assert_eq(levels.bonus_of("a", &"mod_a", "stat_a"), 2.0)


func test_an_undeclared_id_cannot_be_granted():
	assert_false(levels.grant("a", &"nope", 5))
	assert_push_error("not declared")


func test_declared_ids_and_groups():
	assert_eq(levels.declared_ids(), [&"mod_a", &"mod_b"])
	assert_eq(levels.ids_in(&"group_b"), [&"mod_b"])
	assert_eq(levels.ids_in(&"nobody"), [])


func test_a_levels_worth_is_level_times_its_bonus():
	levels.grant("a", &"mod_a", 5)
	levels.grant("a", &"mod_a", 5)
	assert_eq(levels.bonus_of("a", &"mod_a", "stat_a"), 4.0)


func test_one_level_feeds_every_key_of_its_modifier():
	levels.grant("a", &"mod_b", 5)
	assert_eq(levels.bonus_of("a", &"mod_b", "stat_b"), 0.5)
	assert_eq(levels.bonus_of("a", &"mod_b", "stat_c"), 0.1)
	assert_eq(levels.bonus_of("a", &"mod_b", "stat_d"), 0.0)


func test_total_of_sums_a_groups_modifiers_for_a_key():
	levels.declare(&"mod_c", {"stat_a": 1.0}, [&"group_a"])
	levels.grant("a", &"mod_a", 5)
	levels.grant("a", &"mod_c", 5)
	assert_eq(levels.total_of("a", "stat_a", &"group_a"), 3.0)


func test_a_shared_owners_levels_count_for_everyone():
	var shared_levels := LFModifierLevels.new("shared_levels")
	shared_levels.declare(&"mod_a", {"stat_a": 2.0})
	shared_levels.grant("shared_levels", &"mod_a", 3)
	shared_levels.grant("a", &"mod_a", 3)
	assert_eq(shared_levels.level_of("a", &"mod_a"), 2)
	assert_eq(shared_levels.own_level("a", &"mod_a"), 1)
	assert_eq(shared_levels.level_of("shared_levels", &"mod_a"), 1, "the shared owner is not counted twice")


func test_a_cap_bounds_an_owners_own_levels_only():
	var shared_levels := LFModifierLevels.new("shared_levels")
	shared_levels.declare(&"mod_a", {"stat_a": 1.0})
	shared_levels.grant("shared_levels", &"mod_a", 1)
	assert_true(shared_levels.grant("a", &"mod_a", 1))
	assert_eq(shared_levels.level_of("a", &"mod_a"), 2)


func test_a_cap_bonus_raises_the_cap_of_ids_that_accept_it():
	levels.add_cap_bonus("a", 2)
	assert_eq(levels.effective_cap("a", &"mod_a", 1), 3)
	for i in 3:
		assert_true(levels.grant("a", &"mod_a", 1))
	assert_false(levels.grant("a", &"mod_a", 1))


func test_an_id_declared_without_the_cap_bonus_ignores_it():
	levels.declare(&"mod_d", {}, [], false)
	levels.add_cap_bonus("a", 20)
	assert_true(levels.grant("a", &"mod_d", 1))
	assert_false(levels.grant("a", &"mod_d", 1))


func test_cap_bonuses_are_per_owner():
	levels.add_cap_bonus("a", 2)
	assert_eq(levels.cap_bonus_of("a"), 2)
	assert_eq(levels.cap_bonus_of("b"), 0)
	assert_true(levels.has_capacity("a", &"mod_a", 0))
	assert_false(levels.has_capacity("b", &"mod_a", 0))


func test_bonuses_for_sums_a_group():
	levels.grant("a", &"mod_a", 5)
	levels.grant("a", &"mod_b", 5)
	assert_eq(levels.bonuses_for("a", &"group_a"), {"stat_a": 2.0, "stat_b": 0.5, "stat_c": 0.1})
	assert_eq(levels.bonuses_for("a", &"group_b"), {"stat_b": 0.5, "stat_c": 0.1})


func test_a_snapshot_leaves_out_unowned_modifiers():
	levels.grant("a", &"mod_a", 5)
	assert_eq(levels.bonuses_for("a", &"group_a"), {"stat_a": 2.0})
	assert_eq(levels.bonuses_for("b", &"group_a"), {})


func test_a_snapshot_is_shared_until_a_level_feeding_it_changes():
	levels.grant("a", &"mod_a", 5)
	var before := levels.bonuses_for("a", &"group_a")
	assert_true(is_same(before, levels.bonuses_for("a", &"group_a")))
	levels.grant("a", &"mod_a", 5)
	var after := levels.bonuses_for("a", &"group_a")
	assert_false(is_same(before, after))
	assert_eq(before, {"stat_a": 2.0}, "a snapshot already handed out never changes")
	assert_eq(after, {"stat_a": 4.0})


func test_a_grant_to_another_owner_keeps_this_owners_snapshot():
	levels.grant("a", &"mod_a", 5)
	var before := levels.bonuses_for("a", &"group_a")
	levels.grant("b", &"mod_a", 5)
	assert_true(is_same(before, levels.bonuses_for("a", &"group_a")))


func test_a_grant_to_the_shared_owner_renews_every_owners_snapshot():
	var shared_levels := LFModifierLevels.new("shared_levels")
	shared_levels.declare(&"mod_a", {"stat_a": 2.0}, [&"group_a"])
	var before := shared_levels.bonuses_for("a", &"group_a")
	shared_levels.grant("shared_levels", &"mod_a", 5)
	assert_eq(shared_levels.bonuses_for("a", &"group_a"), {"stat_a": 2.0})
	assert_eq(before, {})


func test_a_snapshot_is_read_only():
	levels.grant("a", &"mod_a", 5)
	assert_true(levels.bonuses_for("a", &"group_a").is_read_only())


func test_a_raise_made_directly_on_the_tracker_still_renews_snapshots():
	var before := levels.bonuses_for("a", &"group_a")
	levels.tracker.try_raise("a", &"mod_a", 5)
	assert_eq(levels.bonuses_for("a", &"group_a"), {"stat_a": 2.0})
	assert_eq(before, {})


func test_a_shared_tracker_can_be_supplied():
	var tracker := LFCappedLevelTracker.new()
	var mine := LFModifierLevels.new(null, tracker)
	assert_true(is_same(mine.tracker, tracker))


func test_clear_drops_levels_and_cap_bonuses_but_keeps_declarations():
	levels.grant("a", &"mod_a", 5)
	levels.add_cap_bonus("a", 3)
	var before := levels.bonuses_for("a", &"group_a")
	levels.clear()
	assert_eq(levels.level_of("a", &"mod_a"), 0)
	assert_eq(levels.cap_bonus_of("a"), 0)
	assert_eq(levels.bonuses_for("a", &"group_a"), {})
	assert_eq(before, {"stat_a": 2.0})
	assert_true(levels.is_declared(&"mod_a"))


func test_raised_is_relayed():
	var seen := []
	levels.raised.connect(func(owner, id, level): seen.append([owner, id, level]))
	levels.grant("a", &"mod_a", 5)
	assert_eq(seen, [["a", &"mod_a", 1]])


func test_a_subclass_can_redefine_what_a_level_is_worth():
	var curved := Squared.new()
	curved.declare(&"mod_a", {"stat_a": 1.0}, [&"group_a"])
	for i in 3:
		curved.grant("a", &"mod_a", 5)
	assert_eq(curved.bonus_of("a", &"mod_a", "stat_a"), 9.0)
	assert_eq(curved.total_of("a", "stat_a", &"group_a"), 9.0)
	assert_eq(curved.bonuses_for("a", &"group_a"), {"stat_a": 9.0})


class Squared:
	extends LFModifierLevels
	func _bonus_at(id: StringName, key: Variant, level: int) -> float:
		return level * level * super(id, key, 1)


func test_declaring_into_a_group_renews_its_snapshots():
	var tracker := LFCappedLevelTracker.new()
	var first := LFModifierLevels.new(null, tracker)
	first.declare(&"mod_a", {"stat_a": 2.0}, [&"group_a"])
	var second := LFModifierLevels.new(null, tracker)
	second.declare(&"mod_e", {"stat_d": 1.0})
	second.grant("a", &"mod_e", 5)
	first.grant("a", &"mod_a", 5)
	assert_eq(first.bonuses_for("a", &"group_a"), {"stat_a": 2.0})
	first.declare(&"mod_e", {"stat_d": 3.0}, [&"group_a"])
	assert_eq(first.bonuses_for("a", &"group_a"), {"stat_a": 2.0, "stat_d": 3.0}, 'the level held through the shared tracker now counts')


func test_the_worth_of_an_undeclared_id_is_zero_and_reported():
	assert_eq(levels.bonus_of("a", &"nope", "stat_a"), 0.0)
	assert_push_error("not declared")


func test_totals_and_snapshots_only_ask_about_declared_keys():
	var everywhere := Everywhere.new()
	everywhere.declare(&"mod_a", {"stat_a": 1.0}, [&"group_a"])
	everywhere.grant("a", &"mod_a", 5)
	assert_eq(everywhere.bonus_of("a", &"mod_a", "stat_e"), 7.0, 'bonus_of asks about any key')
	assert_eq(everywhere.total_of("a", "stat_e", &"group_a"), 0.0, 'total_of only declared keys')
	assert_eq(everywhere.bonuses_for("a", &"group_a"), {"stat_a": 7.0})


class Everywhere:
	extends LFModifierLevels
	func _bonus_at(_id: StringName, _key: Variant, _level: int) -> float:
		return 7.0


func test_forget_drops_an_owners_levels_cap_bonus_and_snapshots():
	levels.grant("a", &"mod_a", 5)
	levels.add_cap_bonus("a", 2)
	levels.grant("b", &"mod_a", 5)
	var kept := levels.bonuses_for("b", &"group_a")
	assert_eq(levels.bonuses_for("a", &"group_a"), {"stat_a": 2.0})
	levels.forget("a")
	assert_eq(levels.level_of("a", &"mod_a"), 0)
	assert_eq(levels.cap_bonus_of("a"), 0)
	assert_eq(levels.bonuses_for("a", &"group_a"), {}, 'a fresh, empty snapshot')
	assert_same(levels.bonuses_for("b", &"group_a"), kept, 'other owners keep theirs')


func test_forgetting_the_shared_owner_renews_every_snapshot():
	var with_shared := LFModifierLevels.new("all")
	with_shared.declare(&"mod_a", {"stat_a": 2.0}, [&"group_a"])
	with_shared.grant("all", &"mod_a", 5)
	assert_eq(with_shared.bonuses_for("a", &"group_a"), {"stat_a": 2.0})
	with_shared.forget("all")
	assert_eq(with_shared.bonuses_for("a", &"group_a"), {})


func test_forgetting_through_a_shared_tracker_reaches_every_user():
	var tracker := LFCappedLevelTracker.new()
	var one := LFModifierLevels.new(null, tracker)
	one.declare(&"mod_a", {"stat_a": 2.0}, [&"group_a"])
	var service := LFModifierGrantService.new(tracker)
	one.add_cap_bonus("a", 1)
	one.grant("a", &"mod_a", 5)
	assert_eq(one.bonuses_for("a", &"group_a"), {"stat_a": 2.0})
	service.forget("a")
	assert_eq(one.cap_bonus_of("a"), 0)
	assert_eq(one.bonuses_for("a", &"group_a"), {})


func test_cap_bonus_for_honours_the_per_id_rule():
	levels.declare(&"capped", {}, [], false)
	levels.add_cap_bonus("a", 3)
	assert_eq(levels.cap_bonus_for("a", &"mod_a"), 3)
	assert_eq(levels.cap_bonus_for("a", &"capped"), 0)
	assert_eq(levels.cap_bonus_for("a", &"nope"), 0)


func test_a_forgotten_object_owner_is_released():
	var owner := RefCounted.new()
	var watch: WeakRef = weakref(owner)
	levels.grant(owner, &"mod_a", 5)
	levels.add_cap_bonus(owner, 1)
	levels.bonuses_for(owner, &"group_a")
	levels.forget(owner)
	owner = null
	assert_null(watch.get_ref())


func test_a_group_named_twice_in_one_declaration_counts_the_id_once():
	levels.declare(&"mod_c", {"stat_a": 1.0}, [&"group_c", &"group_c"])
	levels.grant("a", &"mod_c", 5)
	assert_eq(levels.ids_in(&"group_c"), [&"mod_c"])
	assert_eq(levels.total_of("a", "stat_a", &"group_c"), 1.0)
	assert_eq(levels.bonuses_for("a", &"group_c"), {"stat_a": 1.0})


func test_the_shared_owner_is_readable():
	assert_null(levels.shared_owner)
	assert_eq(LFModifierLevels.new("shared_levels").shared_owner, "shared_levels")


func test_the_shared_owner_spelled_as_a_string_name_is_still_the_shared_owner():
	var shared_levels := LFModifierLevels.new("shared_levels")
	shared_levels.declare(&"mod_a", {"stat_a": 2.0}, [&"group_a"])
	var before := shared_levels.bonuses_for("a", &"group_a")
	shared_levels.grant(&"shared_levels", &"mod_a", 3)
	assert_eq(shared_levels.level_of(&"shared_levels", &"mod_a"), 1, 'its levels are counted once')
	assert_eq(shared_levels.bonuses_for("a", &"group_a"), {"stat_a": 2.0}, 'every owner\'s snapshot is renewed')
	assert_eq(before, {})


func test_a_negative_cap_bonus_lowers_it_again():
	levels.add_cap_bonus("a", 3)
	levels.add_cap_bonus("a", -2)
	assert_eq(levels.cap_bonus_of("a"), 1)
	assert_eq(levels.effective_cap("a", &"mod_a", 1), 2)


func test_an_undeclared_id_keeps_its_cap_and_is_not_declared():
	levels.add_cap_bonus("a", 5)
	assert_eq(levels.effective_cap("a", &"nope", 2), 2)
	assert_false(levels.is_declared(&"nope"))
	assert_true(levels.is_declared(&"mod_a"))


func test_the_declared_bonus_is_copied():
	var bonus := {"stat_x": 1.0}
	var groups: Array[StringName] = [&"group_x"]
	levels.declare(&"mod_x", bonus, groups)
	bonus["stat_x"] = 50.0
	groups.append(&"group_y")
	levels.grant("a", &"mod_x", 5)
	assert_eq(levels.bonus_of("a", &"mod_x", "stat_x"), 1.0)
	assert_eq(levels.ids_in(&"group_y"), [])


func test_unknown_groups_add_nothing():
	levels.grant("a", &"mod_a", 5)
	assert_eq(levels.total_of("a", "stat_a", &"nobody"), 0.0)
	assert_eq(levels.bonuses_for("a", &"nobody"), {})


func test_a_grant_refused_at_the_cap_raises_nothing_and_keeps_the_snapshot():
	var seen := []
	levels.raised.connect(func(owner, id, level): seen.append([owner, id, level]))
	levels.grant("a", &"mod_a", 1)
	var before := levels.bonuses_for("a", &"group_a")
	assert_false(levels.grant("a", &"mod_a", 1))
	assert_eq(seen.size(), 1)
	assert_same(levels.bonuses_for("a", &"group_a"), before)


func test_returned_id_lists_are_copies():
	levels.declared_ids().clear()
	levels.ids_in(&"group_a").clear()
	assert_eq(levels.declared_ids(), [&"mod_a", &"mod_b"])
	assert_eq(levels.ids_in(&"group_a"), [&"mod_a", &"mod_b"])


func test_the_shared_owners_own_snapshot_counts_its_levels_once():
	var shared_levels := LFModifierLevels.new("all")
	shared_levels.declare(&"mod_a", {"stat_a": 2.0}, [&"group_a"])
	shared_levels.grant("all", &"mod_a", 5)
	assert_eq(shared_levels.bonuses_for("all", &"group_a"), {"stat_a": 2.0})
	assert_eq(shared_levels.total_of("all", "stat_a", &"group_a"), 2.0)
