extends GutTest


func test_a_member_is_always_allied_with_itself():
	var alliances := LFAllianceGroups.new()
	assert_true(alliances.are_allied("a", "a"))
	alliances.configure([["b", "c"]])
	assert_true(alliances.are_allied("z", "z"), "even a member named in no group")


func test_members_are_hostile_when_nothing_is_configured():
	assert_false(LFAllianceGroups.new().are_allied("a", "b"))


func test_members_of_one_group_are_allied_both_ways():
	var alliances := LFAllianceGroups.new()
	alliances.configure([["a", "b"]])
	assert_true(alliances.are_allied("a", "b"))
	assert_true(alliances.are_allied("b", "a"))


func test_members_of_different_groups_stay_hostile():
	var alliances := LFAllianceGroups.new()
	alliances.configure([["a", "b"], ["c", "d"]])
	assert_false(alliances.are_allied("a", "c"))
	assert_false(alliances.are_allied("b", "d"))


func test_members_in_no_group_are_hostile_to_everyone_including_each_other():
	var alliances := LFAllianceGroups.new()
	alliances.configure([["a", "b"]])
	assert_false(alliances.are_allied("c", "d"))
	assert_false(alliances.are_allied("a", "c"))
	assert_false(alliances.are_allied("c", "a"))


func test_configure_replaces_the_previous_groups():
	var alliances := LFAllianceGroups.new()
	alliances.configure([["a", "b"]])
	alliances.configure([["c", "d"]])
	assert_false(alliances.are_allied("a", "b"))
	assert_true(alliances.are_allied("c", "d"))
	alliances.configure([])
	assert_false(alliances.are_allied("c", "d"))


func test_instances_do_not_share_groups():
	var first := LFAllianceGroups.new()
	var second := LFAllianceGroups.new()
	first.configure([["a", "b"]])
	assert_false(second.are_allied("a", "b"))


func test_ids_can_be_numbers_and_a_member_in_two_groups_keeps_the_last():
	var alliances := LFAllianceGroups.new()
	alliances.configure([[1, 2], [2, 3]])
	assert_true(alliances.are_allied(2, 3))
	assert_false(alliances.are_allied(1, 2))


func test_group_zero_and_a_member_repeated_in_one_group_work():
	var alliances := LFAllianceGroups.new()
	alliances.configure([["a", "a", "b"], []])
	assert_true(alliances.are_allied("a", "b"), "the first group is index 0")
	assert_false(alliances.are_allied("a", "c"))
