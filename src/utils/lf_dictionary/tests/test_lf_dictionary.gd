extends GutTest

var data: Dictionary


func before_each():
	data = {"a": {"b": {"c": 1}}, "top": "value"}


func test_get_by_path_returns_nested_value():
	assert_eq(LFDictionary.get_by_path(data, "a.b.c"), 1)


func test_get_by_path_returns_top_level_value():
	assert_eq(LFDictionary.get_by_path(data, "top"), "value")


func test_get_by_path_returns_intermediate_dictionary():
	assert_eq(LFDictionary.get_by_path(data, "a.b"), {"c": 1})


func test_set_by_path_writes_nested_value():
	LFDictionary.set_by_path(data, "a.b.c", 2)
	assert_eq(data.a.b.c, 2)


func test_set_by_path_writes_top_level_value():
	LFDictionary.set_by_path(data, "top", "changed")
	assert_eq(data.top, "changed")


func test_set_by_path_returns_the_same_dictionary_instance():
	var result = LFDictionary.set_by_path(data, "a.b.c", 3)
	assert_same(result, data)


func test_erase_by_path_removes_nested_key():
	LFDictionary.erase_by_path(data, "a.b.c")
	assert_false(data.a.b.has("c"))


func test_erase_by_path_removes_top_level_key():
	LFDictionary.erase_by_path(data, "top")
	assert_false(data.has("top"))


func test_get_by_path_on_missing_key_returns_null():
	assert_eq(LFDictionary.get_by_path(data, "a.missing"), null)


func test_get_by_path_through_a_missing_intermediate_is_null():
	assert_null(LFDictionary.get_by_path(data, "nope.deeper.still"))


func test_set_by_path_creates_missing_intermediate_dictionaries():
	LFDictionary.set_by_path(data, "new.inner.value", 7)
	assert_eq(data["new"], {"inner": {"value": 7}})


func test_erase_by_path_through_a_missing_intermediate_is_a_no_op():
	LFDictionary.erase_by_path(data, "nope.deeper")
	assert_eq(data, {"a": {"b": {"c": 1}}, "top": "value"})


func test_segments_never_resolve_object_properties():
	var holder := Node.new()
	holder.name = "should-not-be-read"
	var with_object := {"node": holder}

	assert_null(LFDictionary.get_by_path(with_object, "node.name"), "only dictionary keys are path segments")
	holder.free()


func test_set_by_path_overwrites_a_non_dictionary_intermediate():
	var data := {"a": 5, "b": [1, 2]}
	LFDictionary.set_by_path(data, "a.x", 1)
	LFDictionary.set_by_path(data, "b.y", 2)
	assert_eq(data, {"a": {"x": 1}, "b": {"y": 2}}, "the old scalar and array are replaced by dictionaries")


func test_get_by_walks_dictionaries_and_objects():
	var node := Node.new()
	node.name = 'inner'
	assert_eq(LFDictionary.get_by({"a": {"b": 5}}, "a.b"), 5)
	assert_eq(LFDictionary.get_by({"n": node}, "n.name"), &'inner')
	node.free()


func test_get_by_returns_the_default_as_soon_as_a_step_is_missing():
	assert_null(LFDictionary.get_by({"a": {"b": 5}}, "a.missing.c"))
	assert_eq(LFDictionary.get_by({}, "a", "none"), "none")


func test_get_by_never_errors_on_a_scalar_or_freed_step():
	for scalar in [5, 2.5, true, "abc", [1, 2]]:
		assert_null(LFDictionary.get_by({"a": scalar}, "a.b"))
	assert_null(LFDictionary.get_by(7, "x"), "a scalar root resolves to the default too")
	var node := Node.new()
	var holder := {"n": node}
	node.free()
	assert_null(LFDictionary.get_by(holder, "n.name"))


func test_get_by_path_rejects_a_step_delta_outside_the_path():
	assert_null(LFDictionary.get_by_path({"a": {"b": 1}}, "a.b", -1))
	assert_push_error('step_delta')
	assert_null(LFDictionary.get_by_path({"a": {"b": 1}}, "a.b", 3))
	assert_push_error('step_delta')
	assert_eq(LFDictionary.get_by_path({"a": {"b": 1}}, "a.b", 2), {"a": {"b": 1}}, 'the whole path stepped back is the root')


func test_get_by_steps_with_no_steps_returns_the_source():
	assert_eq(LFDictionary.get_by_steps(data, PackedStringArray()), data)


func test_erase_by_path_through_an_object_is_a_no_op():
	var node := Node.new()
	node.name = 'kept'
	var with_object := {"node": node, "deep": {"node": node}}

	LFDictionary.erase_by_path(with_object, "node.name")
	LFDictionary.erase_by_path(with_object, "deep.node.name")

	assert_eq(node.name, &'kept')
	assert_eq(with_object.size(), 2)
	assert_eq(with_object["deep"], {"node": node})
	node.free()


func test_diff_reports_a_new_key_as_changed():
	var delta := LFDictionary.diff({}, {"key_a": {"x": 0}})

	assert_eq(delta["changed"], {"key_a": {"x": 0}})
	assert_eq(delta["removed"], [])


func test_diff_reports_a_changed_value_as_changed():
	var delta := LFDictionary.diff({"key_a": {"x": 0}}, {"key_a": {"x": 5}})

	assert_eq(delta["changed"], {"key_a": {"x": 5}})


func test_diff_omits_a_value_that_did_not_change():
	var state := {"x": 3, "tags": [1, 2]}
	var delta := LFDictionary.diff({"key_a": state}, {"key_a": state.duplicate(true)})

	assert_true(delta["changed"].is_empty(), 'an equal value in a different instance is not resent')


func test_diff_compares_values_like_deep_equal():
	var delta := LFDictionary.diff({"a": 1, "b": "x"}, {"a": 1.0, "b": &"x"})

	assert_true(delta["changed"].is_empty(), 'an int equals the same float; a String equals the same StringName')


func test_diff_reports_a_vanished_key_as_removed():
	var delta := LFDictionary.diff({"key_a": 1}, {})

	assert_eq(delta["removed"], ["key_a"])
	assert_true(delta["changed"].is_empty())


func test_diff_never_modifies_its_inputs():
	var previous := {"a": 1, "gone": 2}
	var next := {"a": 3, "new": 4}
	LFDictionary.diff(previous, next)

	assert_eq(previous, {"a": 1, "gone": 2})
	assert_eq(next, {"a": 3, "new": 4})


func test_apply_diff_reconstructs_the_dictionary_the_diff_was_computed_from():
	var previous := {"key_a": [0, 0], "key_b": [1, 1]}
	var next := {"key_a": [9, 0], "key_c": [2, 2]}

	assert_eq(LFDictionary.apply_diff(previous, LFDictionary.diff(previous, next)), next)


func test_apply_diff_never_modifies_the_base():
	var base := {"a": 1, "b": 2}
	var result := LFDictionary.apply_diff(base, {"changed": {"a": 5}, "removed": ["b"]})

	assert_eq(base, {"a": 1, "b": 2})
	assert_eq(result, {"a": 5})


func test_a_diff_round_trips_through_json_and_still_applies():
	var previous := {"key_a": [0, 0, 0]}
	var next := {"key_a": [7, 0, 0]}
	var wire: Dictionary = JSON.parse_string(JSON.stringify(LFDictionary.diff(previous, next)))

	var rebuilt := LFDictionary.apply_diff(previous, wire)

	assert_true(LFUtils.deep_equal(rebuilt, next))


func test_apply_diff_treats_missing_parts_as_empty():
	assert_eq(LFDictionary.apply_diff({"a": 1}, {}), {"a": 1})
	assert_eq(LFDictionary.apply_diff({"a": 1}, {"removed": ["a"]}), {})


func test_invert_swaps_keys_and_values():
	assert_eq(LFDictionary.invert({"key_a": 1, "key_b": 2}), {1: "key_a", 2: "key_b"})
	assert_eq(LFDictionary.invert({}), {})


func test_invert_lets_the_later_key_win_a_shared_value():
	assert_eq(LFDictionary.invert({"first": 1, "second": 1}), {1: "second"})



func test_diff_does_not_report_an_unchanged_nan_field():
	var delta := LFDictionary.diff({"speed": NAN, "pos": Vector2(NAN, 0)}, {"speed": NAN, "pos": Vector2(NAN, 0)})
	assert_eq(delta[LFDictionary.KEY_CHANGED], {})


func test_get_by_returns_the_default_for_a_property_the_object_lacks():
	var node := Node.new()
	assert_eq(LFDictionary.get_by({"n": node}, "n.no_such_property", -1), -1)
	assert_eq(LFDictionary.get_by_steps({"n": node}, PackedStringArray(["n", "nope"]), "fallback"), "fallback")
	node.free()


func test_apply_diff_ignores_parts_of_the_wrong_type():
	var base := {"a": 1, "b": 2}
	var malformed := {"changed": ["not", "a", "dictionary"], "removed": "b"}

	assert_eq(LFDictionary.apply_diff(base, malformed), {"a": 1, "b": 2}, 'a wrong-typed part counts as empty')


func test_invert_does_not_modify_its_input():
	var source := {"a": 1}
	LFDictionary.invert(source)
	assert_eq(source, {"a": 1})


## A replication-sized snapshot: most units unchanged (a NaN, an int stored as a float and
## a StringName among their fields), a few changed deep inside, one changing type.
func test_diff_of_a_large_snapshot_reports_exactly_the_changed_units():
	var previous := {}
	var next := {}
	for i in 300:
		previous[i] = {"p": Vector3(i, NAN, 0), "hp": 100, "tags": [1, "walk"], "fx": {"slow": NAN}}
		next[i] = {"p": Vector3(i, NAN, 0), "hp": 100.0, "tags": [1.0, &"walk"], "fx": {"slow": NAN}}
	next[7]["fx"] = {"slow": 0.5}
	next[42]["tags"] = [1, "run"]
	next[99] = "gone to string"
	next[300] = {"p": Vector3.ZERO}
	previous.erase(5)
	next.erase(6)

	var delta := LFDictionary.diff(previous, next)

	var changed: Array = delta[LFDictionary.KEY_CHANGED].keys()
	changed.sort()
	assert_eq(changed, [5, 7, 42, 99, 300])
	assert_eq(delta[LFDictionary.KEY_REMOVED], [6])


func _nested(layers: int, leaf: Variant) -> Variant:
	var value: Variant = leaf
	for i in layers:
		value = [value] if i % 2 == 0 else {"k": value}
	return value


func test_diff_reports_a_change_nested_past_the_engines_equality_limit():
	var result := LFDictionary.diff({"a": _nested(75, 1), "b": _nested(75, 1)}, {"a": _nested(75, 2), "b": _nested(75, 1)})
	assert_eq(result[LFDictionary.KEY_CHANGED].keys(), ["a"])
	# Godot's own == logs "Max recursion reached" while comparing values nested that deep.
	for error in get_errors():
		assert_string_contains(error.code, "Max recursion reached")
		error.handled = true
