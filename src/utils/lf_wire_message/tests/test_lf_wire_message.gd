extends GutTest

enum Kind { PING, MOVE }

var codec: LFWireMessage


func before_each():
	codec = LFWireMessage.new({Kind.PING: 'ping', Kind.MOVE: 'move'}, {Kind.MOVE: ['x', 'y']})


func test_encode_names_the_kind():
	assert_eq(codec.encode(Kind.MOVE, {'x': 1, 'y': 2}), {'type': 'move', 'payload': {'x': 1, 'y': 2}})


func test_decode_round_trips():
	var decoded: Dictionary = codec.decode(codec.encode(Kind.MOVE, {'x': 1, 'y': 2}))
	assert_eq(decoded['kind'], Kind.MOVE)
	assert_eq(decoded['payload'], {'x': 1, 'y': 2})


func test_a_kind_without_required_keys_needs_no_payload():
	assert_eq(codec.decode({'type': 'ping'})['kind'], Kind.PING)


func test_decode_rejects_unknown_types_and_missing_type():
	assert_null(codec.decode({'type': 'nope'}))
	assert_null(codec.decode({}))


func test_decode_rejects_a_missing_required_key_or_a_non_dictionary_payload():
	assert_null(codec.decode({'type': 'move', 'payload': {'x': 1}}))
	assert_null(codec.decode({'type': 'move', 'payload': [1, 2]}))
	assert_null(codec.decode({'type': 'ping', 'payload': 'text'}))
