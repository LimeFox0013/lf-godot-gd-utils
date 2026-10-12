extends GutTest

## Resource.duplicate() (used internally by merge_resource) only copies @export'd
## properties, so this fixture must export x/y to be a valid target.
class Point extends Resource:
	@export var x: int = 0
	@export var y: int = 0


func test_merge_arrays_appends_every_source_into_a_copy_of_the_target():
	var target = [1, 2]
	var result = LFUtils.merge_arrays(target, [3, 4], [5])
	assert_eq(result, [1, 2, 3, 4, 5])


func test_merge_arrays_never_mutates_the_target_array():
	var target = [1, 2]
	LFUtils.merge_arrays(target, [3, 4])
	assert_eq(target, [1, 2])


func test_merge_arrays_never_mutates_the_source_arrays():
	var source = [3, 4]
	LFUtils.merge_arrays([1, 2], source)
	assert_eq(source, [3, 4])


func test_merge_resource_applies_dictionary_properties_onto_a_copy_of_the_target():
	var target = Point.new()
	target.x = 1
	var result: Point = LFUtils.merge_resource(target, {"y": 9})
	assert_eq(result.x, 1)
	assert_eq(result.y, 9)


func test_merge_resource_never_mutates_the_target_resource():
	var target = Point.new()
	target.x = 1
	LFUtils.merge_resource(target, {"x": 99})
	assert_eq(target.x, 1)


func test_merge_resource_applies_dictionaries_in_order_so_the_later_wins():
	var result: Point = LFUtils.merge_resource(Point.new(), {"x": 1, "y": 1}, {"x": 2})
	assert_eq(result.x, 2)
	assert_eq(result.y, 1)


func test_merge_arrays_deep_copies_the_target_but_shares_appended_elements():
	var nested_target := [1]
	var nested_source := [2]
	var result = LFUtils.merge_arrays([nested_target], [nested_source])

	nested_target.append(9)
	nested_source.append(9)

	assert_eq(result[0], [1], 'the target was deep-copied')
	assert_eq(result[1], [2, 9], 'an appended element is the same reference')


func test_merge_resource_ignores_a_key_that_is_not_a_property_and_warns_once_naming_it():
	var result: Point = LFUtils.merge_resource(Point.new(), {"x": 4, "not_a_property": 1}, {"not_a_property": 2})
	assert_eq(result.x, 4)
	assert_null(result.get("not_a_property"))
	assert_push_warning("not_a_property")


func test_merge_resource_reports_a_key_repeated_in_several_dictionaries_once():
	LFUtils.merge_resource(Point.new(), {"nope": 1}, {"nope": 2})
	assert_push_warning_count(1)


func test_merge_resource_with_only_real_properties_warns_of_nothing():
	LFUtils.merge_resource(Point.new(), {"x": 4, "y": 5})
	assert_push_warning_count(0)


func test_merge_arrays_with_nothing_to_append_is_a_deep_copy():
	var inner := [1]
	var result = LFUtils.merge_arrays([inner])
	inner.append(2)
	assert_eq(result, [[1]])


class Item extends Resource:
	@export var value: int = 0
	@export var inner: Resource


func test_merge_arrays_shares_resource_elements_of_the_target():
	var item := Item.new()
	var result = LFUtils.merge_arrays([item])
	assert_same(result[0], item, 'a Resource is not copied by duplicate(true)')


func test_merge_arrays_copies_nested_arrays_and_dictionaries_but_shares_the_resources_in_them():
	var item := Item.new()
	var nested := [[item], {"key": item}]
	var result = LFUtils.merge_arrays(nested)
	assert_not_same(result[0], nested[0], 'the nested array was copied')
	assert_not_same(result[1], nested[1], 'the nested dictionary was copied')
	assert_same(result[0][0], item)
	assert_same(result[1]["key"], item)


func test_merge_arrays_deep_copies_resources_in_the_target_at_any_depth():
	var item := Item.new()
	item.value = 3
	item.inner = Item.new()
	var result = LFUtils.merge_arrays_deep([item, [item], {"key": item}])
	assert_not_same(result[0], item)
	assert_eq(result[0].value, 3, 'the copy carries the values')
	assert_not_same(result[0].inner, item.inner, 'sub-resources are copied')
	assert_not_same(result[1][0], item)
	assert_not_same(result[2]["key"], item)
	result[0].value = 9
	assert_eq(item.value, 3, 'changing the copy leaves the original alone')


func test_merge_arrays_deep_keeps_a_sub_resource_saved_in_a_file_shared():
	var saved := Item.new()
	saved.take_over_path("res://lf_merge_probe_not_a_real_file.tres")
	var item := Item.new()
	item.inner = saved
	var result = LFUtils.merge_arrays_deep([item])
	assert_not_same(result[0], item, 'the element is copied')
	assert_same(result[0].inner, saved, 'a file-backed sub-resource is shared')
	saved.take_over_path("")


func test_merge_arrays_deep_shares_appended_elements_and_does_not_change_inputs():
	var item := Item.new()
	var extra := Item.new()
	var target := [item]
	var result = LFUtils.merge_arrays_deep(target, [extra])
	assert_same(result[1], extra)
	assert_eq(target.size(), 1)
	assert_same(target[0], item)


func test_append_unique_adds_only_items_the_base_lacks():
	assert_eq(LFUtils.append_unique([1, 2], [2, 3, 1, 4]), [1, 2, 3, 4])


func test_append_unique_returns_a_new_array_and_leaves_both_inputs_alone():
	var base := [1, 2]
	var extra := [2, 3]
	var result = LFUtils.append_unique(base, extra)
	assert_eq(base, [1, 2])
	assert_eq(extra, [2, 3])
	assert_not_same(result, base)


func test_append_unique_compares_arrays_and_dictionaries_by_content():
	var result = LFUtils.append_unique([[1, 2], {"a": 1}], [[1, 2], {"a": 1}, [3], {"a": 2}])
	assert_eq(result, [[1, 2], {"a": 1}, [3], {"a": 2}])


func test_append_unique_treats_an_int_and_the_float_of_the_same_number_as_equal():
	assert_eq(LFUtils.append_unique([1], [1.0, 2.0]), [1, 2.0])


func test_append_unique_adds_a_repeated_new_item_once_and_keeps_duplicates_already_in_base():
	assert_eq(LFUtils.append_unique([1, 1], [5, 5]), [1, 1, 5])


func test_append_unique_compares_resources_by_identity():
	var a := Item.new()
	var b := Item.new()
	var result = LFUtils.append_unique([a], [a, b])
	assert_eq(result.size(), 2)
	assert_same(result[1], b)


func test_append_unique_with_empty_arrays():
	assert_eq(LFUtils.append_unique([], []), [])
	assert_eq(LFUtils.append_unique([], [1, 1]), [1])
	assert_eq(LFUtils.append_unique([1], []), [1])
