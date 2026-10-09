extends GutTest

const PROPERTIES := {
	'count': {'type': 'integer'},
	'name': {'type': 'string'},
	'x': {'type': 'number'},
	'locked': {'type': 'boolean'},
	'tags': {'type': 'array'},
}


func test_define_builds_a_closed_object_schema_from_copies():
	var properties := {'level': {'type': 'integer'}}
	var required := ['level']

	var tool := LFLlmTool.define('set_volume', 'Set the volume.', properties, required)
	properties['level']['type'] = 'string'
	required.append('other')

	assert_eq(tool, {
		'name': 'set_volume',
		'description': 'Set the volume.',
		'parameters': {'type': 'object', 'properties': {'level': {'type': 'integer'}}, 'required': ['level'], 'additionalProperties': false},
	})


func test_define_with_no_properties_takes_no_arguments():
	assert_eq(LFLlmTool.define('finish', 'Finish the task.')['parameters']['properties'], {})


func test_find_tool_looks_up_by_name():
	var tools := [LFLlmTool.define('a', 'A'), LFLlmTool.define('b', 'B')]

	assert_eq(LFLlmTool.find_tool(tools, 'b')['description'], 'B')
	assert_eq(LFLlmTool.find_tool(tools, 'missing'), {})


func test_coerce_args_keeps_only_schema_keys_cast_to_their_types():
	var input := {'count': 2.0, 'name': 7, 'x': '1.5', 'locked': 'true', 'tags': ['a'], 'extra': 1}

	assert_eq(LFLlmTool.coerce_args(PROPERTIES, input), {'count': 2, 'name': '7', 'x': 1.5, 'locked': true, 'tags': ['a']})


func test_coerce_args_leaves_out_skipped_and_unreadable_values():
	var input := {'count': ['not', 'a', 'number'], 'x': 3, 'name': 'n'}

	assert_eq(LFLlmTool.coerce_args(PROPERTIES, input, ['x']), {'name': 'n'})


func test_a_numeric_string_reads_as_an_integer():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': '3'}), {'count': 3})
	assert_eq(typeof(LFLlmTool.coerce_args(PROPERTIES, {'count': '3'})['count']), TYPE_INT)


func test_a_null_value_is_left_out_whatever_its_type():
	var input := {'count': null, 'name': null, 'x': null, 'locked': null, 'tags': null}

	assert_eq(LFLlmTool.coerce_args(PROPERTIES, input), {})


func test_booleans_read_from_numbers_and_words_only():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': 0}), {'locked': false})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': 'FALSE'}), {'locked': false})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': 'yes'}), {})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': true}), {'count': 1})


func test_a_property_without_a_type_keeps_its_value():
	assert_eq(LFLlmTool.coerce_args({'any': {}, 'raw': 'not a schema'}, {'any': [1], 'raw': 2}), {'any': [1], 'raw': 2})


func test_infinite_nan_or_out_of_range_numbers_are_left_out():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': INF, 'x': NAN}), {})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': 1e30, 'x': '1e999'}), {}, 'an int cannot hold 1e30; 1e999 parses as infinity')
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': -1e18}), {'count': -1000000000000000000})


func test_an_integer_with_a_fraction_is_left_out_not_truncated():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': '2.9'}), {}, 'a numeric string')
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': 2.9}), {}, 'a number')
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': -0.5}), {})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': 4.0}), {'count': 4}, 'a whole float is an integer')
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': '4.0'}), {'count': 4})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'x': '2.9'}), {'x': 2.9}, 'a number keeps its fraction')


func test_is_valid_tool_checks_the_neutral_shape():
	assert_true(LFLlmTool.is_valid_tool(LFLlmTool.define('move', 'Move.')))
	assert_false(LFLlmTool.is_valid_tool({'name': 'move', 'parameters': {}}), 'no description')
	assert_false(LFLlmTool.is_valid_tool({'name': '', 'description': 'd', 'parameters': {}}), 'an empty name')
	assert_false(LFLlmTool.is_valid_tool({'name': 'move', 'description': 'd', 'parameters': []}), 'parameters not an object')
	assert_false(LFLlmTool.is_valid_tool('move'))


func test_find_tool_skips_entries_that_are_not_dictionaries():
	var tools := ['b', null, 3, LFLlmTool.define('b', 'B')]
	assert_eq(LFLlmTool.find_tool(tools, 'b')['description'], 'B')
	assert_eq(LFLlmTool.find_tool([], 'b'), {})


func test_a_non_numeric_string_or_a_container_is_not_a_number():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'x': 'fast', 'count': 'three'}), {})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'x': {'v': 1}, 'count': [3]}), {})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'x': ' 2.5 ', 'count': ' 7 '}), {'x': 2.5, 'count': 7}, 'surrounding spaces are ignored')
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'x': true}), {'x': 1.0}, 'a bool reads as 0 or 1')


func test_a_numeric_string_with_an_exponent_is_read_within_range_only():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': '2e3', 'x': '1.5E2'}), {'count': 2000, 'x': 150.0})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'x': '1e-400'}), {}, 'an exponent beyond -300 is left out too')
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'x': '1e+301'}), {})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': '1e19'}), {}, 'beyond the 64-bit range')
	assert_engine_error_count(0, 'no engine error from a huge exponent')


func test_an_integer_inside_the_64_bit_range_is_kept_up_to_its_edge():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': 9_210_000_000_000_000_000}), {'count': 9_210_000_000_000_000_000})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': 9.21e18}), {'count': 9_210_000_000_000_000_000})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': 9.3e18}), {}, 'past 2^63 an int cannot hold it')


func test_a_boolean_reads_any_non_zero_number_as_true_and_nothing_else():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': 0.5}), {'locked': true})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': -3}), {'locked': true})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': 'True'}), {'locked': true})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': [true]}), {})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': false}), {'locked': false})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': INF}), {}, 'an infinite number is no answer')
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'locked': NAN}), {})


func test_a_string_property_turns_any_value_into_text():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'name': 2.5}), {'name': '2.5'})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'name': true}), {'name': 'true'})


func test_find_tool_skips_entries_whose_name_is_not_text():
	var go := LFLlmTool.define('go', 'Go.')
	assert_eq(LFLlmTool.find_tool([{'name': 0}, {'name': null}, {'name': ['x']}, go], 'go'), go)
	assert_eq(LFLlmTool.find_tool([{'name': 0}], 'x'), {})
	assert_engine_error_count(0)


## An exponent too long for a 64-bit int is still recognised as out of range, without the
## engine error reading it as a number would raise.
func test_an_exponent_beyond_the_64_bit_range_is_left_out_without_an_error():
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'x': '1e99999999999999999999'}), {})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'count': '1e-99999999999999999999'}), {})
	assert_eq(LFLlmTool.coerce_args(PROPERTIES, {'x': '1e+0000000000000000000002'}), {'x': 100.0}, 'leading zeros do not count')
	assert_engine_error_count(0)


const BOUNDED := {
	'level': {'type': 'integer', 'minimum': 1, 'maximum': 5},
	'ratio': {'type': 'number', 'minimum': 0.0, 'maximum': 1.0},
	'mode': {'type': 'string', 'enum': ['fast', 'slow']},
	'size': {'type': 'integer', 'enum': [1, 2, 4]},
	'note': {'type': 'string', 'maxLength': 5},
}


func test_coerce_args_keeps_values_inside_the_schema_limits():
	var input := {'level': 5, 'ratio': 1.0, 'mode': 'slow', 'size': 4, 'note': 'abcde'}
	assert_eq(LFLlmTool.coerce_args(BOUNDED, input), {'level': 5, 'ratio': 1.0, 'mode': 'slow', 'size': 4, 'note': 'abcde'})
	assert_eq(LFLlmTool.coerce_args(BOUNDED, {'level': 1, 'ratio': 0}), {'level': 1, 'ratio': 0.0})
	assert_push_warning_count(0)


func test_coerce_args_rejects_a_number_outside_minimum_and_maximum():
	var out := LFLlmTool.coerce_args(BOUNDED, {'level': 6, 'ratio': -0.1})
	assert_eq(out, {}, 'rejected, not clamped')
	assert_eq(LFLlmTool.coerce_args(BOUNDED, {'level': 0}), {})
	assert_eq(LFLlmTool.coerce_args(BOUNDED, {'level': '9'}), {}, 'the limit applies after the cast')
	assert_push_warning_count(4)


func test_coerce_args_rejects_a_value_missing_from_the_enum():
	assert_eq(LFLlmTool.coerce_args(BOUNDED, {'mode': 'turbo', 'size': 3}), {})
	assert_eq(LFLlmTool.coerce_args(BOUNDED, {'size': '4'}), {'size': 4}, 'the enum is checked after the cast')
	assert_push_warning_count(2)


func test_coerce_args_enum_does_not_confuse_types():
	var props := {'v': {'enum': [1, 'a']}}
	assert_eq(LFLlmTool.coerce_args(props, {'v': 1}), {'v': 1})
	assert_eq(LFLlmTool.coerce_args(props, {'v': 1.0}), {'v': 1.0})
	assert_eq(LFLlmTool.coerce_args(props, {'v': '1'}), {})
	assert_eq(LFLlmTool.coerce_args(props, {'v': true}), {})
	assert_eq(LFLlmTool.coerce_args(props, {'v': 'a'}), {'v': 'a'})
	assert_push_warning_count(2)


func test_coerce_args_rejects_a_string_longer_than_max_length():
	assert_eq(LFLlmTool.coerce_args(BOUNDED, {'note': 'abcdef'}), {})
	assert_eq(LFLlmTool.coerce_args(BOUNDED, {'note': 'héllo'}), {'note': 'héllo'}, 'characters, not bytes')
	assert_eq(LFLlmTool.coerce_args(BOUNDED, {'note': 123456}), {}, 'a number cast to a string counts too')
	assert_push_warning_count(2)


func test_coerce_args_ignores_limits_that_are_not_numbers_or_lists():
	var props := {'a': {'type': 'integer', 'minimum': 'x', 'maximum': null, 'enum': 'no'}, 'b': {'type': 'string', 'maxLength': 'x'}}
	assert_eq(LFLlmTool.coerce_args(props, {'a': 99, 'b': 'long text'}), {'a': 99, 'b': 'long text'})
	assert_push_warning_count(0)
