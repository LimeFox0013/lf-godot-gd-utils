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
