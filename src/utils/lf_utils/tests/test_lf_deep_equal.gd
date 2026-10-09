extends GutTest

class Point extends Resource:
	var x: int = 0
	var y: int = 0
	var label: String = ""


func test_equal_scalars():
	assert_true(LFUtils.deep_equal(1, 1))
	assert_false(LFUtils.deep_equal(1, 2))


func test_values_of_unrelated_types_are_never_equal():
	assert_false(LFUtils.deep_equal(1, "1"))
	assert_false(LFUtils.deep_equal([1, 2], {"0": 1, "1": 2}))


func test_nested_arrays_compare_structurally():
	assert_true(LFUtils.deep_equal([1, [2, 3]], [1, [2, 3]]))
	assert_false(LFUtils.deep_equal([1, [2, 3]], [1, [2, 4]]))
	assert_false(LFUtils.deep_equal([1, 2], [1, 2, 3]))


func test_nested_dictionaries_compare_structurally():
	assert_true(LFUtils.deep_equal({"a": {"b": 1}}, {"a": {"b": 1}}))
	assert_false(LFUtils.deep_equal({"a": 1}, {"a": 2}))
	assert_false(LFUtils.deep_equal({"a": 1}, {"a": 1, "b": 2}))


func test_are_resources_equal_only_considers_the_explicitly_listed_properties():
	var a = Point.new()
	a.x = 1
	a.y = 2
	a.label = "a"
	var b = Point.new()
	b.x = 1
	b.y = 2
	b.label = "b"
	# "label" differs but is not in the compared property list, so it's ignored.
	assert_true(LFUtils.are_resources_equal(["x", "y"], a, b))
	assert_false(LFUtils.are_resources_equal(["x", "y", "label"], a, b))


func test_are_resources_equal_compares_against_every_given_resource():
	var a = Point.new()
	var b = Point.new()
	var c = Point.new()
	c.x = 5
	assert_true(LFUtils.are_resources_equal(["x"], a, b))
	assert_false(LFUtils.are_resources_equal(["x"], a, b, c))


func test_an_int_and_a_float_of_the_same_number_are_equal_like_same_value():
	# deep_equal and same_value agree: int vs float compare as numbers, at any depth.
	assert_true(LFUtils.deep_equal(1, 1.0))
	assert_true(LFUtils.deep_equal({"a": [1, 2]}, {"a": [1.0, 2]}))
	assert_false(LFUtils.deep_equal(1, 1.5))
	assert_eq(LFUtils.deep_equal(2, 2.0), LFUtils.same_value(2, 2.0))
	assert_true(LFUtils.deep_equal("a", &"a"), "a String and a StringName compare by content")
	assert_false(LFUtils.deep_equal("1", 1), "other differing types stay unequal")


func test_are_resources_equal_is_false_for_a_null_resource_and_true_for_none():
	var a := Point.new()
	assert_false(LFUtils.are_resources_equal(["x"], a, null))
	assert_true(LFUtils.are_resources_equal(["x"], a), 'no resources to compare is vacuously equal')


func test_are_resources_equal_reads_a_property_one_resource_lacks_as_null():
	var a := Point.new()
	var b := Point.new()
	assert_true(LFUtils.are_resources_equal(["missing"], a, b), 'both read null')


func test_same_value_table():
	var cases := [
		[1, 1.0, true, 'an int and a float of the same number'],
		[1, 1.5, false, 'different numbers'],
		['a', &'a', true, 'a String and a StringName with the same text'],
		['a', &'b', false, 'different text'],
		[[], null, false, 'an Array against null'],
		[null, null, true, 'null against null'],
		[Vector2(1, 2), Vector2i(1, 2), false, 'a Vector2 against a Vector2i'],
		[1, '1', false, 'a number against its text'],
		[true, 1, false, 'a bool against an int'],
	]
	for c in cases:
		assert_eq(LFUtils.same_value(c[0], c[1]), c[2], c[3])
		assert_eq(LFUtils.same_value(c[1], c[0]), c[2], '%s (swapped)' % c[3])



func test_nan_equals_nan_in_floats_containers_and_vectors():
	assert_true(LFUtils.deep_equal(NAN, NAN))
	assert_true(LFUtils.deep_equal([1, NAN], [1, NAN]))
	assert_true(LFUtils.deep_equal({"hp": NAN}, {"hp": NAN}))
	assert_true(LFUtils.deep_equal(Vector3(NAN, 1, 2), Vector3(NAN, 1, 2)))
	assert_true(LFUtils.deep_equal(Color(NAN, 0, 0), Color(NAN, 0, 0)))
	assert_true(LFUtils.deep_equal(PackedFloat32Array([NAN, 1]), PackedFloat32Array([NAN, 1])))
	assert_false(LFUtils.deep_equal(NAN, 1.0))
	assert_false(LFUtils.deep_equal(Vector2(NAN, 1), Vector2(NAN, 2)))
	assert_false(LFUtils.deep_equal(PackedFloat64Array([NAN]), PackedFloat64Array([NAN, 1])))


func test_dictionaries_with_different_keys_of_the_same_count_differ():
	assert_false(LFUtils.deep_equal({"a": 1}, {"b": 1}))


func test_every_float_vector_type_compares_component_wise_with_nan():
	assert_true(LFUtils.deep_equal(Vector2(NAN, 1), Vector2(NAN, 1)))
	assert_true(LFUtils.deep_equal(Vector4(1, NAN, 2, 3), Vector4(1, NAN, 2, 3)))
	assert_true(LFUtils.deep_equal(Quaternion(NAN, 0, 0, 1), Quaternion(NAN, 0, 0, 1)))
	assert_true(LFUtils.deep_equal(PackedFloat64Array([NAN, 2]), PackedFloat64Array([NAN, 2])))
	assert_false(LFUtils.deep_equal(Vector4(1, NAN, 2, 3), Vector4(1, NAN, 2, 4)))
	assert_false(LFUtils.deep_equal(Color(NAN, 0, 0), Color(0, 0, 0)))
	assert_true(LFUtils.deep_equal(Vector3(1, 2, 3), Vector3(1, 2, 3)), 'equal without NaN')


func test_other_values_compare_with_double_equals():
	var a := Point.new()
	var b := Point.new()
	assert_true(LFUtils.deep_equal(a, a), 'the same object')
	assert_false(LFUtils.deep_equal(a, b), 'objects compare by identity, not content')
	assert_true(LFUtils.deep_equal(Vector2i(1, 2), Vector2i(1, 2)))
	assert_true(LFUtils.deep_equal(null, null))


func test_are_resources_equal_is_false_for_something_that_is_not_a_resource():
	var a := Point.new()
	var node := Node.new()
	assert_false(LFUtils.are_resources_equal(["x"], a, node))
	assert_false(LFUtils.are_resources_equal(["x"], a, 5))
	node.free()


func test_are_resources_equal_sees_a_property_only_one_side_has():
	var a := Point.new()
	var b := Labeled.new()
	b.extra = 3
	assert_false(LFUtils.are_resources_equal(["extra"], a, b), 'null on the target, 3 on the other')
	b.extra = null
	assert_true(LFUtils.are_resources_equal(["extra"], a, b), 'both read null')


class Labeled extends Resource:
	var extra: Variant = null


## deep_equal asks the engine's == first for arrays and dictionaries, so whenever that
## reports two values of one type equal, deep_equal must agree; and it still finds equal
## what == calls different (an int and a float inside an array, a NaN).
func test_deep_equal_agrees_with_engine_equality_and_goes_beyond_it():
	var node := Node.new()
	var values: Array = [0, 1, 1.0, -0.0, NAN, true, null, "a", &"a", Vector3(NAN, 0, 0), Vector3(-0.0, 0, 0),
		[1], [1.0], [NAN], ["a"], [&"a"], Array([1], TYPE_INT, "", null), {"a": 1}, {"a": 1.0}, {&"a": 1},
		{"a": NAN}, {"b": 1, "a": 2}, {"a": 2, "b": 1}, [[1]], [[1.0]], [Vector3(NAN, 0, 0)],
		PackedFloat32Array([NAN]), {"x": [1, {"y": 2}]}, {"x": [1.0, {"y": 2.0}]}, node, [node], {}, []]
	for a in values:
		for b in values:
			if typeof(a) == typeof(b) and a == b:
				assert_true(LFUtils.deep_equal(a, b), '%s == %s' % [var_to_str(a), var_to_str(b)])
	assert_true(LFUtils.deep_equal([1, {"y": NAN}], [1.0, {"y": NAN}]))
	assert_true(LFUtils.deep_equal({"x": [1, &"s"]}, {"x": [1.0, "s"]}))
	assert_false(LFUtils.deep_equal({"x": [1, {"y": 2}]}, {"x": [1, {"y": 3}]}))
	assert_false(LFUtils.deep_equal({"a": 1, "b": 2}, {"a": 1, "c": 2}))
	node.free()


## Nested `{a: {...}, n: i}` dictionaries that differ in `n` at every level, `depth` deep.
func _deep_pair(depth: int) -> Array:
	var left := {}
	var right := {}
	for i in depth:
		left = {"a": left, "n": i}
		right = {"a": right, "n": i + 1}
	return [left, right]


## A 1,100-level document that differs at every level (what a hostile JSON input can
## be): the walk stops at DEEP_EQUAL_MAX_DEPTH with a warning instead of overflowing the
## script stack, and answers "different". The engine's own == reports its own limit on
## the way ("Max recursion reached").
func test_a_structure_nested_past_the_limit_is_walked_no_deeper_than_it():
	var pair := _deep_pair(1100)
	assert_false(LFUtils.deep_equal(pair[0], pair[1]))
	assert_false(LFDictionary.diff({"s": pair[0]}, {"s": pair[1]})[LFDictionary.KEY_CHANGED].is_empty())
	var shallow := _deep_pair(LFUtils.DEEP_EQUAL_MAX_DEPTH / 2)
	assert_false(LFUtils.deep_equal(shallow[0], shallow[1]))
	assert_true(LFUtils.deep_equal(shallow[0], shallow[0].duplicate(true)), "within the limit, exact")
	var walk_stops := 0
	var others := []
	for error in get_errors():
		if error.contains_text("Max recursion reached"):
			error.handled = true
		elif error.contains_text("nested more than %d levels" % LFUtils.DEEP_EQUAL_MAX_DEPTH):
			error.handled = true
			walk_stops += 1
		else:
			others.append(error.code if error.rationale != "" else error.code)
	assert_eq(walk_stops, 2, "the walk stopped once in each comparison, with a warning")
	assert_eq(others, [], "nothing but the engine's own == limit and the walk's warning")



func _nested(layers: int, leaf: Variant) -> Variant:
	var value: Variant = leaf
	for i in layers:
		value = [value] if i % 2 == 0 else {"k": value}
	return value


## Godot's own `==` logs "Max recursion reached" while it compares values nested past its
## limit; those logs are expected, and nothing else may be logged.
func _expect_engine_recursion_logs() -> void:
	for error in get_errors():
		assert_string_contains(error.code, "Max recursion reached")
		error.handled = true


func test_a_difference_nested_past_the_engines_equality_limit_is_found():
	for layers in [51, 75, 100]:
		assert_false(LFUtils.deep_equal(_nested(layers, 1), _nested(layers, 2)), "differs at %d layers" % layers)
	_expect_engine_recursion_logs()
	assert_push_warning_count(0)


func test_equal_values_nested_past_the_engines_equality_limit_stay_equal():
	for layers in [51, 75, 100]:
		assert_true(LFUtils.deep_equal(_nested(layers, 1), _nested(layers, 1)), "equal at %d layers" % layers)
	_expect_engine_recursion_logs()


func test_reordered_dictionaries_are_equal_at_any_depth():
	var a := {"x": {"p": 1, "q": 2}, "y": 3}
	var b := {"y": 3, "x": {"q": 2, "p": 1}}
	assert_true(LFUtils.deep_equal(a, b))
	assert_true(LFUtils.deep_equal(_nested(60, a), _nested(60, b)))
	_expect_engine_recursion_logs()


func test_the_hash_check_still_tells_deep_values_apart():
	# deep_equal relies on hash() following nesting as deep as DEEP_EQUAL_MAX_DEPTH.
	assert_ne(hash(_nested(LFUtils.DEEP_EQUAL_MAX_DEPTH, 1)), hash(_nested(LFUtils.DEEP_EQUAL_MAX_DEPTH, 2)))
	_expect_engine_recursion_logs()
