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


func test_encode_text_once_is_the_json_of_encode():
	var payload := {'x': 1, 'y': [2, 3], 'name': 'a "b"'}
	assert_eq(codec.encode_text_once(Kind.MOVE, payload), JSON.stringify({'type': 'move', 'payload': payload}))


func test_encode_text_once_reuses_the_text_for_the_same_object_only():
	var payload := {'x': 1, 'y': 2}
	var first := codec.encode_text_once(Kind.MOVE, payload)
	payload['x'] = 99
	assert_eq(codec.encode_text_once(Kind.MOVE, payload), first, 'the same object is not encoded again')
	assert_ne(codec.encode_text_once(Kind.MOVE, payload.duplicate()), first, 'an equal copy is encoded afresh')


func test_encode_text_once_encodes_again_for_another_kind():
	var payload := {}
	assert_eq(codec.encode_text_once(Kind.PING, payload), JSON.stringify({'type': 'ping', 'payload': {}}))
	assert_eq(codec.encode_text_once(Kind.MOVE, payload), JSON.stringify({'type': 'move', 'payload': {}}))


func test_splice_text_is_byte_for_byte_the_rest_then_the_field():
	var big := {'a': {'hp': 1.5}, 'b': [1, 2]}
	var payload := {'stage': 2, 'info': {'round': 3}, 'big': big}
	var expected := '{"type":"move","payload":{"info":{"round":3},"stage":2,"big":' + JSON.stringify(big) + '}}'
	assert_eq(codec.splice_text(Kind.MOVE, payload, 'big', JSON.stringify(big)), expected)
	assert_eq(payload.keys(), ['stage', 'info', 'big'], 'the payload is untouched')


func test_splice_text_of_a_payload_holding_only_the_field():
	var big := {'a': 1}
	assert_eq(codec.splice_text(Kind.MOVE, {'big': big}, 'big', JSON.stringify(big)), '{"type":"move","payload":{"big":{"a":1}}}')


func test_splice_text_parses_to_the_whole_message():
	var payload := {'x': 1, 'y': 2, 'big': {'k': [1, 2, 3]}}
	var spliced: Variant = JSON.parse_string(codec.splice_text(Kind.MOVE, payload, 'big', JSON.stringify(payload['big'])))
	assert_eq(spliced, JSON.parse_string(JSON.stringify(codec.encode(Kind.MOVE, payload))))
