extends GutTest

var tracker: LFCappedLevelTracker


func before_each():
	tracker = LFCappedLevelTracker.new()


func test_level_for_an_ungranted_modifier_is_zero():
	assert_eq(tracker.level_for("owner-1", "key_a"), 0)


func test_try_raise_raises_the_level_and_returns_true_within_cap():
	var raised = tracker.try_raise("owner-1", "key_a", 3)
	assert_true(raised)
	assert_eq(tracker.level_for("owner-1", "key_a"), 1)


func test_try_raise_accumulates_across_repeated_calls():
	tracker.try_raise("owner-1", "key_a", 3)
	tracker.try_raise("owner-1", "key_a", 3)
	assert_eq(tracker.level_for("owner-1", "key_a"), 2)


func test_try_raise_rejects_and_leaves_level_unchanged_at_cap():
	tracker.try_raise("owner-1", "key_a", 1)
	var raised_past_cap = tracker.try_raise("owner-1", "key_a", 1)
	assert_false(raised_past_cap)
	assert_eq(tracker.level_for("owner-1", "key_a"), 1)


func test_has_capacity_reflects_the_current_level_against_a_cap():
	tracker.try_raise("owner-1", "key_a", 5)
	assert_true(tracker.has_capacity("owner-1", "key_a", 5))
	tracker.try_raise("owner-1", "key_a", 5)
	tracker.try_raise("owner-1", "key_a", 5)
	tracker.try_raise("owner-1", "key_a", 5)
	tracker.try_raise("owner-1", "key_a", 5)
	assert_false(tracker.has_capacity("owner-1", "key_a", 5))


func test_two_modifier_ids_for_the_same_owner_are_tracked_independently():
	tracker.try_raise("owner-1", "key_a", 5)
	assert_eq(tracker.level_for("owner-1", "key_b"), 0)


func test_two_owner_keys_are_tracked_independently_of_each_other():
	tracker.try_raise("owner-1", "key_a", 5)
	assert_eq(tracker.level_for("owner-42", "key_a"), 0)


func test_clear_clears_every_owner_and_modifier():
	tracker.try_raise("owner-1", "key_a", 5)
	tracker.try_raise("owner-42", "key_b", 5)
	tracker.clear()
	assert_eq(tracker.level_for("owner-1", "key_a"), 0)
	assert_eq(tracker.level_for("owner-42", "key_b"), 0)


func test_a_cap_of_zero_or_less_always_rejects():
	assert_false(tracker.try_raise("owner-1", "key_c", 0))
	assert_false(tracker.try_raise("owner-1", "key_c", -2))
	assert_eq(tracker.level_for("owner-1", "key_c"), 0)


func test_a_lower_cap_later_keeps_the_existing_level():
	for i in 3:
		tracker.try_raise("owner-1", "key_c", 5)
	assert_false(tracker.try_raise("owner-1", "key_c", 2))
	assert_eq(tracker.level_for("owner-1", "key_c"), 3)


func test_reads_create_no_record():
	tracker.level_for("ghost", "key_c")
	tracker.has_capacity("ghost", "key_c", 3)
	assert_eq(tracker._levels.size(), 0)


func test_raised_announces_each_successful_raise_only():
	var seen := []
	tracker.raised.connect(func(owner, id, level): seen.append([owner, id, level]))
	tracker.try_raise("owner-1", "key_c", 2)
	tracker.try_raise("owner-1", "key_c", 2)
	tracker.try_raise("owner-1", "key_c", 2)
	assert_eq(seen, [["owner-1", &"key_c", 1], ["owner-1", &"key_c", 2]])


func test_clear_announces_cleared():
	var fired := [0]
	tracker.cleared.connect(func(): fired[0] += 1)
	tracker.clear()
	assert_eq(fired[0], 1)


func test_a_string_and_a_string_name_id_are_the_same_record():
	tracker.try_raise("owner-1", "key_c", 5)
	assert_eq(tracker.level_for("owner-1", &"key_c"), 1)


func test_owner_keys_keep_their_type():
	tracker.try_raise(1, "key_c", 5)
	assert_eq(tracker.level_for(1, "key_c"), 1)
	assert_eq(tracker.level_for("1", "key_c"), 0)


var _forgotten: Array = []


func _on_forgotten(owner: Variant) -> void:
	_forgotten.append(owner)


func test_forget_drops_one_owners_levels_and_announces_it():
	_forgotten.clear()
	tracker.forgotten.connect(_on_forgotten)
	tracker.try_raise("owner-1", &"key_c", 3)
	tracker.try_raise("owner-2", &"key_c", 3)
	tracker.forget("owner-1")
	assert_eq(tracker.level_for("owner-1", &"key_c"), 0)
	assert_eq(tracker.level_for("owner-2", &"key_c"), 1, 'other owners keep theirs')
	assert_eq(_forgotten, ["owner-1"])
	assert_true(tracker.try_raise("owner-1", &"key_c", 1), 'raised again from zero')


func test_forgetting_an_unknown_owner_still_announces_it():
	_forgotten.clear()
	tracker.forgotten.connect(_on_forgotten)
	tracker.forget("nobody")
	assert_eq(_forgotten, ["nobody"])


func test_a_forgotten_object_owner_is_released():
	var owner := RefCounted.new()
	var watch: WeakRef = weakref(owner)
	tracker.try_raise(owner, &"key_c", 3)
	tracker.forget(owner)
	owner = null
	assert_null(watch.get_ref())


func test_has_capacity_for_an_unseen_owner_and_for_caps_of_zero_or_less():
	assert_true(tracker.has_capacity("ghost", "key_c", 1))
	assert_false(tracker.has_capacity("ghost", "key_c", 0))
	assert_false(tracker.has_capacity("ghost", "key_c", -1))


func test_a_raise_after_clear_starts_from_zero_and_announces_level_one():
	tracker.try_raise("owner-1", "key_c", 5)
	tracker.try_raise("owner-1", "key_c", 5)
	tracker.clear()
	var seen := []
	tracker.raised.connect(func(owner, id, level): seen.append([owner, id, level]))

	assert_true(tracker.try_raise("owner-1", "key_c", 1))
	assert_eq(seen, [["owner-1", &"key_c", 1]])
