extends GutTest

var item_a: Dictionary
var item_b: Dictionary
var item_c: Dictionary
var index: LFInvertIndex


func before_each():
	item_a = {"id": 1, "type": "kind_a", "tags": ["tag_a", "tag_b"]}
	item_b = {"id": 2, "type": "kind_b", "tags": ["tag_c"]}
	item_c = {"id": 3, "type": "kind_a", "tags": ["tag_b"]}
	index = LFInvertIndex.new([
		LFIndexingRule.new("type"),
		LFIndexingRule.new("tags", LFIndexingRule.Target.ARRAY),
	])
	index.add(item_a)
	index.add(item_b)
	index.add(item_c)


func test_lookup_by_single_value_rule_returns_every_matching_item():
	var result = index.get_by_values("type", ["kind_a"])
	assert_eq(result.size(), 2)
	assert_true(result.has(item_a))
	assert_true(result.has(item_c))


func test_lookup_by_array_rule_returns_items_sharing_a_value():
	var result = index.get_by_values("tags", ["tag_b"])
	assert_eq(result.size(), 2)
	assert_true(result.has(item_a))
	assert_true(result.has(item_c))


func test_lookup_by_a_value_no_item_has_returns_empty():
	assert_eq(index.get_by_values("type", ["nonexistent"]), [])


func test_remove_erases_item_from_every_rule_bucket_it_was_indexed_under():
	index.remove(item_a)
	assert_false(index.get_by_values("type", ["kind_a"]).has(item_a))
	assert_false(index.get_by_values("tags", ["tag_a"]).has(item_a))
	assert_false(index.get_by_values("tags", ["tag_b"]).has(item_a))


func test_remove_leaves_other_items_in_the_same_bucket_untouched():
	index.remove(item_a)
	assert_true(index.get_by_values("tags", ["tag_b"]).has(item_c))


func test_remove_of_an_object_never_added_is_a_no_op():
	var untracked = {"id": 99, "type": "kind_a"}
	index.remove(untracked)
	assert_eq(index.get_by_values("type", ["kind_a"]).size(), 2)


func test_lookup_by_an_unregistered_property_path_raises_and_returns_empty():
	var result = index.get_by_values("unregistered-path", ["kind_a"])
	assert_push_error("does not exist")
	assert_eq(result, [])


func test_adding_an_object_again_reindexes_it_without_leaving_stale_entries():
	index.add(item_a)
	index.remove(item_a)

	assert_false(index.get_by_values("type", ["kind_a"]).has(item_a), "no bucket may still hold item_a")
	assert_false(index.get_by_values("tags", ["tag_a", "tag_b"]).has(item_a))
	assert_false(index.has(item_a))


func test_dictionary_keys_rule_indexes_an_item_under_each_key():
	var item_x = {"weights": {"key_a": 0.5, "key_b": 0.1}}
	var item_y = {"weights": {"key_c": 1.0}}
	var key_index := LFInvertIndex.new([
		LFIndexingRule.new("weights", LFIndexingRule.Target.DICTIONARY_KEYS),
	])
	key_index.add(item_x)
	key_index.add(item_y)

	assert_eq(key_index.get_by_values("weights", ["key_b"]), [item_x])
	assert_eq(key_index.get_by_values("weights", ["key_c"]), [item_y])
	assert_eq(key_index.get_by_values("weights", [0.5]), [], "values must not be indexed by a keys rule")


func test_dictionary_values_rule_indexes_an_item_under_each_value():
	var item_x = {"parts": {"part_a": "value_a", "part_b": "value_b"}}
	var item_y = {"parts": {"part_b": "value_c"}}
	var value_index := LFInvertIndex.new([
		LFIndexingRule.new("parts", LFIndexingRule.Target.DICTIONARY_VALUES),
	])
	value_index.add(item_x)
	value_index.add(item_y)

	assert_eq(value_index.get_by_values("parts", ["value_b"]), [item_x])
	assert_eq(value_index.get_by_values("parts", ["value_c", "value_a"]).size(), 2)
	assert_eq(value_index.get_by_values("parts", ["part_b"]), [], "keys must not be indexed by a values rule")


func test_an_object_whose_path_crosses_a_scalar_is_simply_not_indexed():
	var odd = {"type": 3}
	var nested_index := LFInvertIndex.new([LFIndexingRule.new("type.name")])
	nested_index.add(odd)
	assert_eq(nested_index.get_by_values("type.name", [3]), [])


func test_an_item_changed_after_add_can_still_be_removed():
	item_a["type"] = "kind_b"
	index.remove(item_a)
	assert_false(index.get_by_values("type", ["kind_a"]).has(item_a))
	assert_false(index.has(item_a))


func test_two_equal_dictionaries_are_two_items():
	var twin := item_c.duplicate(true)
	index.add(twin)
	index.remove(item_c)
	var kind_a := index.get_by_values("type", ["kind_a"])
	assert_eq(kind_a.size(), 2)
	assert_true(is_same(kind_a[1], twin))


func test_two_rules_on_one_path_need_their_own_names():
	LFInvertIndex.new([LFIndexingRule.new("tags"), LFIndexingRule.new("tags", LFIndexingRule.Target.ARRAY)])
	assert_push_error("two rules are named")
	var named := LFInvertIndex.new([
		LFIndexingRule.new("tags"),
		LFIndexingRule.new("tags", LFIndexingRule.Target.ARRAY, "tag"),
	])
	named.add(item_a)
	assert_eq(named.get_by_values("tag", ["tag_a"]), [item_a])
	assert_eq(named.get_by_values("tags", [["tag_a", "tag_b"]]), [item_a])


func test_a_value_of_the_wrong_shape_indexes_nothing():
	var odd := {"tags": "not-an-array"}
	index.add(odd)
	assert_eq(index.get_by_values("tags", ["not-an-array"]), [])
	assert_true(index.has(odd))


func test_an_object_item_is_tracked_by_identity():
	var node := Node.new()
	node.name = 'node_a'
	var by_name := LFInvertIndex.new([LFIndexingRule.new("name")])
	by_name.add(node)
	assert_eq(by_name.get_by_values("name", [&'node_a']), [node])
	by_name.remove(node)
	assert_eq(by_name.size(), 0)
	node.free()


func test_an_item_listing_one_value_twice_is_returned_once():
	var dup := {"type": "x", "tags": ["a", "a"]}
	index.add(dup)
	assert_eq(index.get_by_values("tags", ["a"]), [dup])


func test_clear_empties_the_index_but_keeps_its_rules():
	index.clear()
	assert_eq(index.size(), 0)
	assert_false(index.has(item_a))
	assert_eq(index.get_by_values("type", ["kind_a"]), [])
	assert_eq(index.get_by_values("tags", ["tag_b"]), [])
	assert_push_error_count(0, 'every rule still answers')
	index.add(item_b)
	assert_eq(index.get_by_values("tags", ["tag_c"]), [item_b])


func test_items_is_a_copy_in_insertion_order():
	var listed := index.items()
	assert_eq(listed.size(), 3)
	assert_true(is_same(listed[0], item_a) and is_same(listed[1], item_b) and is_same(listed[2], item_c))
	listed.clear()
	assert_eq(index.size(), 3, 'changing the copy changes nothing')


func test_re_adding_an_item_moves_it_to_the_end_of_items():
	index.add(item_a)
	var listed := index.items()
	assert_true(is_same(listed[0], item_b) and is_same(listed[1], item_c) and is_same(listed[2], item_a))
	index.remove(item_b)
	listed = index.items()
	assert_eq(listed.size(), 2)
	assert_true(is_same(listed[0], item_c) and is_same(listed[1], item_a))


func test_values_of_spreads_a_packed_array_under_array():
	var rule := LFIndexingRule.new("tags", LFIndexingRule.Target.ARRAY)
	assert_eq(rule.values_of({"tags": PackedStringArray(["a", "b"])}), ["a", "b"])
	assert_eq(rule.values_of({"tags": PackedInt32Array([4])}), [4])


func test_values_of_reads_a_nested_path_inside_an_object():
	var holder := Holder.new()
	holder.meta = {"tags": PackedStringArray(["tag_a"])}
	var rule := LFIndexingRule.new("meta.tags", LFIndexingRule.Target.ARRAY)
	assert_eq(rule.values_of(holder), ["tag_a"])
	var by_tag := LFInvertIndex.new([rule])
	by_tag.add(holder)
	assert_eq(by_tag.get_by_values("meta.tags", ["tag_a"]), [holder])


class Holder:
	extends RefCounted
	var meta := {}


func test_a_rule_keeps_its_path_and_target_and_is_named_after_its_path_by_default():
	var plain := LFIndexingRule.new("meta.kind")
	var named := LFIndexingRule.new("tags", LFIndexingRule.Target.ARRAY, "tag")

	assert_eq(plain.path, "meta.kind")
	assert_eq(plain.name, "meta.kind")
	assert_eq(plain.target, LFIndexingRule.Target.VALUE)
	assert_eq(named.path, "tags")
	assert_eq(named.name, "tag")
	assert_eq(named.target, LFIndexingRule.Target.ARRAY)


func test_values_match_like_dictionary_keys():
	var by_count := LFInvertIndex.new([LFIndexingRule.new("count")])
	var parsed := {"count": 1.0}
	by_count.add(parsed)

	assert_eq(by_count.get_by_values("count", [1.0]), [parsed])
	assert_eq(by_count.get_by_values("count", [1]), [], 'an int is not the float a JSON number became')
	assert_eq(index.get_by_values("type", [&"kind_a"]).size(), 2, 'a StringName finds its String')


func test_a_value_of_the_wrong_shape_for_a_dictionary_target_indexes_nothing():
	var keys := LFIndexingRule.new("weights", LFIndexingRule.Target.DICTIONARY_KEYS)
	var values := LFIndexingRule.new("weights", LFIndexingRule.Target.DICTIONARY_VALUES)
	for odd in [{"weights": ["key_a"]}, {"weights": "key_a"}, {"other": {"key_a": 1}}]:
		assert_eq(keys.values_of(odd), [], 'keys of %s' % [odd])
		assert_eq(values.values_of(odd), [], 'values of %s' % [odd])
	assert_eq(LFIndexingRule.new("type").values_of({"id": 1}), [], 'a missing path indexes nothing')


func test_re_adding_a_changed_object_refiles_it_under_its_new_value():
	var unit := Holder.new()
	unit.meta = {"kind": "melee"}
	var other := Holder.new()
	other.meta = {"kind": "melee"}
	var by_kind := LFInvertIndex.new([LFIndexingRule.new("meta.kind", LFIndexingRule.Target.VALUE, "kind")])
	by_kind.add(unit)
	by_kind.add(other)

	unit.meta["kind"] = "ranged"
	by_kind.add(unit)

	assert_eq(by_kind.get_by_values("kind", ["melee"]), [other])
	assert_eq(by_kind.get_by_values("kind", ["ranged"]), [unit])
	assert_eq(by_kind.size(), 2, 're-adding does not duplicate the object')
	by_kind.remove(unit)
	assert_eq(by_kind.get_by_values("kind", ["ranged"]), [])
	assert_eq(by_kind.items(), [other])


func test_an_object_freed_without_remove_is_still_returned_as_a_freed_instance():
	var by_name := LFInvertIndex.new([LFIndexingRule.new("name")])
	var live := Node.new()
	live.name = 'unit'
	var doomed := Node.new()
	doomed.name = 'unit'
	by_name.add(doomed)
	by_name.add(live)
	doomed.free()

	var found := by_name.get_by_values("name", [&'unit'])
	assert_eq(found.size(), 2, 'the freed object still sits in its bucket')
	assert_false(is_instance_valid(found[0]))
	assert_true(is_same(found[1], live))
	assert_true(by_name.has(live))
	by_name.remove(live)
	assert_eq(by_name.size(), 1, 'only the freed object is left')
	live.free()


func test_a_freed_object_can_still_be_removed():
	var by_name := LFInvertIndex.new([LFIndexingRule.new("name")])
	var doomed := Node.new()
	doomed.name = 'unit'
	by_name.add(doomed)
	var held: Variant = doomed
	doomed.free()

	by_name.remove(held)

	assert_eq(by_name.size(), 0)
	assert_false(by_name.has(held))
	assert_eq(by_name.get_by_values("name", [&'unit']), [])
	by_name.add(Node.new())
	assert_eq(by_name.size(), 1, 'the index keeps working')
	by_name.items()[0].free()


class _Mob:
	var tag := "fast"
	var id := 0


func _perf_index() -> LFInvertIndex:
	return LFInvertIndex.new([LFIndexingRule.new("tag")] as Array[LFIndexingRule])


func test_many_objects_under_one_tag_add_look_up_and_remove_in_bounded_time():
	var index := _perf_index()
	var mobs: Array = []
	var started := Time.get_ticks_msec()
	for i in 16000:
		var mob := _Mob.new()
		mob.id = i
		mobs.append(mob)
		index.add(mob)
	assert_eq(index.size(), 16000)
	assert_eq(index.get_by_values("tag", ["fast"]).size(), 16000)
	assert_true(index.has(mobs[8000]))
	for mob in mobs:
		index.remove(mob)
	assert_eq(index.size(), 0)
	assert_eq(index.get_by_values("tag", ["fast"]), [])
	# Measured in well under a second; the quadratic version took 7 to 19 seconds.
	assert_lt(Time.get_ticks_msec() - started, 4000)


func test_many_dictionaries_under_one_tag_add_look_up_and_remove_in_bounded_time():
	var index := _perf_index()
	var dicts: Array = []
	var started := Time.get_ticks_msec()
	for i in 16000:
		var d := {"tag": "fast", "id": i}
		dicts.append(d)
		index.add(d)
	assert_eq(index.size(), 16000)
	assert_eq(index.get_by_values("tag", ["fast"]).size(), 16000)
	for d in dicts:
		index.remove(d)
	assert_eq(index.size(), 0)
	assert_lt(Time.get_ticks_msec() - started, 4000)


func test_a_changed_dictionary_added_again_is_one_item_not_two():
	var index := LFInvertIndex.new([LFIndexingRule.new("tag")] as Array[LFIndexingRule])
	var a := {"tag": "x"}
	var b := {"tag": "x"}
	index.add(a)
	index.add(b)
	a["tag"] = "y"
	index.add(a)
	assert_eq(index.size(), 2)
	assert_eq(index.get_by_values("tag", ["x"]).size(), 1)
	assert_eq(index.get_by_values("tag", ["y"]).size(), 1)
	assert_true(is_same(index.get_by_values("tag", ["y"])[0], a))
	assert_true(is_same(index.items()[1], a), "re-adding moves it to the end")


func test_a_dictionary_changed_twice_between_reads_is_still_one_item():
	var index := LFInvertIndex.new([LFIndexingRule.new("tag")] as Array[LFIndexingRule])
	var a := {"tag": "x"}
	index.add(a)
	a["tag"] = "y"
	index.add(a)
	a["tag"] = "z"
	index.add(a)
	assert_eq(index.size(), 1)
	assert_eq(index.get_by_values("tag", ["z"]).size(), 1)
	assert_eq(index.get_by_values("tag", ["x", "y"]).size(), 0)
	index.remove(a)
	assert_eq(index.size(), 0)


func test_a_changed_dictionary_is_found_and_removed_after_other_adds():
	var index := LFInvertIndex.new([LFIndexingRule.new("tag")] as Array[LFIndexingRule])
	var a := {"tag": "x"}
	index.add(a)
	for i in 50:
		index.add({"tag": "n%d" % i})
	a["tag"] = "changed"
	assert_true(index.has(a))
	index.remove(a)
	assert_false(index.has(a))
	assert_eq(index.get_by_values("tag", ["x"]).size(), 0)
	assert_eq(index.size(), 50)


func test_mutate_then_add_twice_leaves_one_record_under_the_new_value():
	var index := LFInvertIndex.new([LFIndexingRule.new("k")] as Array[LFIndexingRule])
	var d := {"k": 0}
	index.add(d)
	assert_eq(index.size(), 1)
	d["k"] = 1
	index.add(d)
	index.add(d)
	assert_eq(index.size(), 1)
	assert_eq(index.get_by_values("k", [0]).size(), 0)
	assert_eq(index.get_by_values("k", [1]).size(), 1)
	index.remove(d)
	assert_false(index.has(d))
	assert_eq(index.size(), 0)


func test_randomized_operations_match_a_naive_model():
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	for round in 40:
		var index := LFInvertIndex.new([LFIndexingRule.new("k")] as Array[LFIndexingRule])
		var pool: Array = []
		for i in 6:
			pool.append({"id": i, "k": 0})
		# Model: id -> value the item was last filed under, in insertion order.
		var filed: Array = []
		var filed_value := {}
		for step in 60:
			var d: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			var op := rng.randi_range(0, 5)
			match op:
				0, 1:
					index.add(d)
					filed.erase(d["id"])
					filed.append(d["id"])
					filed_value[d["id"]] = d["k"]
				2:
					d["k"] = rng.randi_range(0, 3)
				3:
					index.remove(d)
					filed.erase(d["id"])
				4:
					assert_eq(index.has(d), filed.has(d["id"]), "has r%d s%d" % [round, step])
				5:
					assert_eq(index.size(), filed.size(), "size r%d s%d" % [round, step])
					var want: Array = []
					for id: int in filed:
						if filed_value[id] == 1:
							want.append(id)
					var got: Array = []
					for item: Dictionary in index.get_by_values("k", [1]):
						got.append(item["id"])
					assert_eq(got, want, "lookup r%d s%d" % [round, step])
		assert_eq(index.size(), filed.size(), "final size r%d" % round)
		var order: Array = []
		for item: Dictionary in index.items():
			order.append(item["id"])
		assert_eq(order, filed, "final order r%d" % round)
