extends GutTest


func test_parse_returns_the_encoded_value():
	assert_eq(LFJson.parse('{"a": [1, "x", true, null]}'), {"a": [1.0, "x", true, null]})
	assert_eq(LFJson.parse('3'), 3.0)
	assert_eq(LFJson.parse('"text"'), "text")


func test_parse_returns_the_default_on_malformed_input_without_logging():
	for bad in ['', '{', '{"a": }', 'not json', '[1, 2', "{'single': 1}"]:
		assert_null(LFJson.parse(bad), bad)
		assert_eq(LFJson.parse(bad, 'fallback'), 'fallback', bad)
	assert_engine_error_count(0, 'bad input never logs an engine error')


func test_parse_keeps_a_valid_null_apart_from_the_default():
	assert_null(LFJson.parse('null', 'fallback'), 'a valid null is the value, not a parse failure')


func test_parse_object_returns_only_dictionaries():
	assert_eq(LFJson.parse_object('{"type": "ping"}'), {"type": "ping"})
	assert_null(LFJson.parse_object('[1, 2]'))
	assert_null(LFJson.parse_object('"text"'))
	assert_null(LFJson.parse_object('{broken'))
	assert_engine_error_count(0)


func test_vec3_and_vec2_encode_as_number_arrays():
	assert_eq(LFJson.vec3(Vector3(1, 2.5, -3)), [1.0, 2.5, -3.0])
	assert_eq(LFJson.vec3(Vector3i(1, 2, 3)), [1, 2, 3])
	assert_eq(LFJson.vec2(Vector2(4, 5)), [4.0, 5.0])


func test_to_vec3_round_trips_through_real_json():
	var wire: Variant = JSON.parse_string(JSON.stringify({"p": LFJson.vec3(Vector3(1, 2, 3))}))
	assert_eq(LFJson.to_vec3(wire["p"]), Vector3(1, 2, 3))
	assert_eq(LFJson.to_vec2([7, 8.5]), Vector2(7, 8.5), 'ints and floats both count')


func test_to_vec3_rejects_the_wrong_length():
	var fallback := Vector3(9, 9, 9)
	assert_eq(LFJson.to_vec3([1, 2], fallback), fallback)
	assert_eq(LFJson.to_vec3([1, 2, 3, 4], fallback), fallback)
	assert_eq(LFJson.to_vec3([]), Vector3.ZERO, 'the default fallback is the origin')
	assert_eq(LFJson.to_vec2([1, 2, 3]), Vector2.ZERO)


func test_to_vec3_rejects_non_numbers():
	assert_eq(LFJson.to_vec3([1, "2", 3]), Vector3.ZERO)
	assert_eq(LFJson.to_vec3([1, null, 3]), Vector3.ZERO)
	assert_eq(LFJson.to_vec3([true, 0, 0]), Vector3.ZERO, 'a bool is not a number')
	assert_eq(LFJson.to_vec3(null), Vector3.ZERO)
	assert_eq(LFJson.to_vec3("1,2,3"), Vector3.ZERO)
	assert_eq(LFJson.to_vec3({"x": 1, "y": 2, "z": 3}), Vector3.ZERO)


func test_to_vec3_rejects_nan_and_infinity():
	assert_eq(LFJson.to_vec3([NAN, 0, 0]), Vector3.ZERO)
	assert_eq(LFJson.to_vec3([0, INF, 0]), Vector3.ZERO)
	assert_eq(LFJson.to_vec2([-INF, 0]), Vector2.ZERO)


func test_to_vec3_accepts_packed_number_arrays():
	assert_eq(LFJson.to_vec3(PackedFloat32Array([1, 2, 3])), Vector3(1, 2, 3))
	assert_eq(LFJson.to_vec2(PackedInt32Array([1, 2])), Vector2(1, 2))
	assert_eq(LFJson.to_vec2(PackedFloat64Array([NAN, 2])), Vector2.ZERO)


func test_parse_returns_every_number_as_a_float():
	assert_eq(typeof(LFJson.parse('3')), TYPE_FLOAT)
	assert_eq(typeof(LFJson.parse('[7]')[0]), TYPE_FLOAT)


func test_to_vec3_rejects_a_finite_number_too_big_for_a_vector():
	assert_eq(LFJson.to_vec3([1e39, 0, 0]), Vector3.ZERO, 'it would become an infinite coordinate')
	assert_eq(LFJson.to_vec2([0, -1e300]), Vector2.ZERO)
	assert_eq(LFJson.to_vec3(LFJson.parse('[1e39, 0, 0]')), Vector3.ZERO, 'straight from the wire')


func test_vec2_and_vec3_read_any_value_with_the_named_components():
	assert_eq(LFJson.vec2(Vector2i(3, -4)), [3, -4])
	assert_eq(LFJson.vec3(Vector4(1, 2, 3, 4)), [1.0, 2.0, 3.0], 'w is left out')
	assert_eq(LFJson.vec2({"x": 5, "y": 6}), [5, 6], 'a Dictionary with x and y is read as well')


func test_to_vec3_accepts_a_packed_int64_array_and_returns_the_fallback_for_other_packed_arrays():
	assert_eq(LFJson.to_vec3(PackedInt64Array([1, 2, 3])), Vector3(1, 2, 3))
	assert_eq(LFJson.to_vec3(PackedStringArray(["1", "2", "3"]), Vector3.ONE), Vector3.ONE)
	assert_eq(LFJson.to_vec2(PackedVector2Array([Vector2.ONE, Vector2.ONE])), Vector2.ZERO)
