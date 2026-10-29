extends GutTest

## LFSocket clients against a real LFSocketServer on 127.0.0.1 (a fresh OS-chosen port
## per test): requests, the offline queue across a real reconnect, event routing from the
## server's sends, and peer-group rooms sharing one server.

var server: LFSocketServer
var port: int
var sockets: Array[LFSocket] = []


const _REFUSAL_REASON := "Godot on Windows never reports a refused loopback connection (still connecting after 25 s)"


func _refusal_unreported() -> bool:
	return OS.get_name() == "Windows"


## What Godot on macOS 26 logs when a connection is refused: it fails to set TCP_NODELAY on the
## refused socket. It comes from the engine, not from the library, and GUT would count it as a
## failure of every test that dials a closed port.
const _MACOS_REFUSAL_NOISE := "Unable to set TCP no delay option"


## Marks that message as expected on macOS. A test that dials a closed port calls it as its last
## line (GUT counts engine errors before `after_each` runs); on other platforms, or for any other
## message, nothing is excused.
func _tolerate_macos_refusal_noise() -> void:
	if OS.get_name() != "macOS":
		return
	for error in get_errors():
		if error.contains_text(_MACOS_REFUSAL_NOISE):
			error.handled = true


func before_each():
	server = LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	port = server.get_local_port()
	sockets = []


func after_each():
	for socket in sockets:
		socket.disconnect_from_server()
	server.stop()


func _url() -> String:
	return 'ws://127.0.0.1:%d' % port


## A socket that reconnects quickly, already dialling the server.
func _open_socket(options := LFSocketOptions.new()) -> LFSocket:
	var socket := LFSocket.new()
	sockets.append(socket)
	socket.connect_to_server(_url(), options)
	return socket


func _fast_options() -> LFSocketOptions:
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 30
	options.max_reconnect_interval_ms = 60
	return options


## Waits until `predicate` holds or `ms` milliseconds pass; true when it held.
func _wait_ms(predicate: Callable, ms: int = 3000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()


func test_a_request_is_answered_by_the_server_with_a_matching_response():
	server.message_received.connect(func(peer_id: int, data: Dictionary):
		if data.get('type') == 'request':
			server.send_to(peer_id, {'type': 'response', 'id': data.get('id'), 'data': {'echo': data.get('payload')}}))
	var socket := _open_socket()
	assert_true(await _wait_ms(func(): return socket.is_connected_to_server()), 'reached before the timeout')

	var answer: Variant = await socket.request_message({'op': 'stats'}, 3000)

	assert_eq(answer, {'echo': {'op': 'stats'}})
	assert_eq(socket.get_status().pending_requests, 0)


func test_messages_queued_while_the_server_is_down_arrive_in_order_after_a_real_reconnect():
	var received := []
	server.message_received.connect(func(_peer_id: int, data: Dictionary): received.append(data.get('n')))
	var socket := _open_socket(_fast_options())
	assert_true(await _wait_ms(func(): return socket.is_connected_to_server()), 'reached before the timeout')

	server.stop()
	assert_true(await _wait_ms(func(): return !socket.is_connected_to_server()), 'reached before the timeout')
	for n in 3:
		socket.send_message({'n': n})
	assert_eq(socket.get_queue_size(), 3, 'queued while offline')
	await _wait_ms(func(): return false, 100)
	assert_eq(server.listen(port, '127.0.0.1'), OK)
	assert_true(await _wait_ms(func(): return received.size() == 3), 'reached before the timeout')

	assert_eq(received, [0.0, 1.0, 2.0])
	assert_eq(socket.get_queue_size(), 0)
	_tolerate_macos_refusal_noise()


func test_events_sent_with_send_to_reach_the_right_listeners():
	var socket := _open_socket()
	var greets := []
	var notes := []
	var everything := []
	socket.on_event('greet', func(data): greets.append(data))
	socket.on_event('note', func(data): notes.append(data))
	socket.on_event('*', func(event, _data): everything.append(event))
	assert_true(await _wait_ms(func(): return server.connected_peer_ids().size() == 1), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]

	server.send_to(peer_id, {'event': 'greet', 'data': 'hi'})
	server.send_to(peer_id, {'type': 'note', 'x': 1})
	assert_true(await _wait_ms(func(): return everything.size() == 2), 'reached before the timeout')

	assert_eq(greets, ['hi'])
	assert_eq(notes, [{'type': 'note', 'x': 1.0}], 'no data field: the whole message')
	assert_eq(everything, ['greet', 'note'])


func test_two_rooms_on_one_server_keep_their_broadcasts_and_closes_apart():
	var rooms := {'a': LFSocketPeerGroup.new(server), 'b': LFSocketPeerGroup.new(server)}
	server.message_received.connect(func(peer_id: int, data: Dictionary):
		if data.get('type') == 'join' and rooms.has(data.get('room')):
			rooms[data.get('room')].add_member(peer_id))
	var closes := []
	rooms['a'].peer_disconnected.connect(func(id): closes.append(['a', id]))
	rooms['b'].peer_disconnected.connect(func(id): closes.append(['b', id]))
	var alice := _open_socket()
	var bob := _open_socket()
	var heard := {'alice': [], 'bob': []}
	alice.on_event('news', func(data): heard['alice'].append(data))
	bob.on_event('news', func(data): heard['bob'].append(data))
	alice.send_message({'type': 'join', 'room': 'a'})
	bob.send_message({'type': 'join', 'room': 'b'})
	assert_true(await _wait_ms(func(): return rooms['a'].member_ids().size() == 1 and rooms['b'].member_ids().size() == 1), 'reached before the timeout')

	rooms['a'].broadcast({'event': 'news', 'data': 'for a'})
	rooms['b'].broadcast({'event': 'news', 'data': 'for b'})
	assert_true(await _wait_ms(func(): return heard['alice'].size() == 1 and heard['bob'].size() == 1), 'reached before the timeout')
	await _wait_ms(func(): return false, 100)

	assert_eq(heard, {'alice': ['for a'], 'bob': ['for b']})
	var bob_id: int = rooms['b'].member_ids()[0]
	bob.disconnect_from_server()
	assert_true(await _wait_ms(func(): return !closes.is_empty()), 'reached before the timeout')
	await _wait_ms(func(): return false, 100)
	assert_eq(closes, [['b', bob_id]], 'only the room bob was in reports his close')
	assert_eq(rooms['a'].member_ids().size(), 1)


## The usual login flow: a `connected` handler sends a login, and messages queued
## while offline follow it, so the server always sees the login first.
func test_a_message_sent_from_the_connected_handler_goes_before_the_offline_queue():
	var received := []
	server.message_received.connect(func(_peer_id: int, data: Dictionary): received.append(data.get('type')))
	var socket := LFSocket.new()
	sockets.append(socket)
	socket.connected.connect(func(): socket.send_message({'type': 'login'}))
	socket.send_message({'type': 'queued-1'})
	socket.send_message({'type': 'queued-2'})

	socket.connect_to_server(_url(), LFSocketOptions.new())
	assert_true(await _wait_ms(func(): return received.size() == 3), 'reached before the timeout')

	assert_eq(received, ['login', 'queued-1', 'queued-2'])
	assert_eq(socket.get_queue_size(), 0)


## A `connected` handler that hangs up at once has decided: the offline queue is not
## sent on the connection it just closed, and stays for the next one.
func test_a_connected_handler_that_disconnects_keeps_the_offline_queue():
	var received := []
	server.message_received.connect(func(_peer_id: int, data: Dictionary): received.append(data))
	var socket := LFSocket.new()
	sockets.append(socket)
	var hung_up := [false]
	socket.connected.connect(func():
		socket.disconnect_from_server()
		hung_up[0] = true, CONNECT_ONE_SHOT)
	socket.send_message({'type': 'queued'})

	socket.connect_to_server(_url(), LFSocketOptions.new())
	assert_true(await _wait_ms(func(): return hung_up[0]), 'reached before the timeout')
	await _wait_ms(func(): return false, 100)

	assert_false(socket.is_connected_to_server())
	assert_eq(received, [], 'nothing went out on the closed connection')
	assert_eq(socket.get_queue_size(), 1, 'the message waits for the next connection')


## The attempt number in `reconnect_scheduled` starts again at 1 once a connection opens.
func test_the_reconnect_attempt_count_starts_over_after_a_connection_opens():
	if _refusal_unreported():
		pending(_REFUSAL_REASON)
		return
	var attempts := []
	var socket := _open_socket(_fast_options())
	socket.reconnect_scheduled.connect(func(attempt): attempts.append(attempt))
	assert_true(await _wait_ms(func(): return socket.is_connected_to_server()), 'reached before the timeout')

	server.stop()
	assert_true(await _wait_ms(func(): return attempts.size() >= 2), 'reached before the timeout')
	assert_eq(attempts.slice(0, 2), [1, 2], 'refused redials count up while the server is down')
	assert_eq(server.listen(port, '127.0.0.1'), OK)
	assert_true(await _wait_ms(func(): return socket.is_connected_to_server()), 'reached before the timeout')
	assert_eq(socket.get_status().reconnect_attempts, 0)
	attempts.clear()

	server.stop()
	assert_true(await _wait_ms(func(): return !attempts.is_empty()), 'reached before the timeout')

	assert_eq(attempts[0], 1, 'the second outage counts from 1 again')
	_tolerate_macos_refusal_noise()


## A matched response goes only to the waiting request, never to `"*"` or `"response"`
## listeners.
func test_an_answered_request_reaches_no_listener():
	server.message_received.connect(func(peer_id: int, data: Dictionary):
		if data.get('type') == 'request':
			server.send_to(peer_id, {'type': 'response', 'id': data.get('id'), 'data': 42}))
	var socket := _open_socket()
	var heard := []
	socket.on_event('*', func(event, _data): heard.append(event))
	socket.on_event('response', func(data): heard.append(data))
	assert_true(await _wait_ms(func(): return socket.is_connected_to_server()), 'reached before the timeout')

	var answer: Variant = await socket.request_message('any JSON value', 3000)

	assert_eq(answer, 42.0)
	assert_eq(heard, [])


## The payload of a request can be any JSON value, not only a Dictionary.
func test_a_request_payload_can_be_an_array_a_string_or_null():
	var payloads := []
	server.message_received.connect(func(peer_id: int, data: Dictionary):
		if data.get('type') == 'request':
			payloads.append(data.get('payload'))
			server.send_to(peer_id, {'type': 'response', 'id': data.get('id')}))
	var socket := _open_socket()
	assert_true(await _wait_ms(func(): return socket.is_connected_to_server()), 'reached before the timeout')

	var answers := []
	for payload: Variant in [[1, 'two'], 'text', null]:
		answers.append(await socket.request_message(payload, 3000))

	assert_eq(payloads, [[1.0, 'two'], 'text', null])
	assert_eq(answers, [null, null, null], 'a response without data answers null')


## The push_warning texts this test produced that contain `text`; each is marked handled.
func _warnings_with(text: String) -> Array[String]:
	var found: Array[String] = []
	for err in gut.error_tracker.get_errors_for_test():
		if err.is_push_warning() and err.contains_text(text):
			err.handled = true
			found.append('%s %s' % [err.code, err.rationale])
	return found


## The peer id of the one socket connected to the server, once it is connected.
func _connected_peer(socket: LFSocket) -> int:
	assert_true(await _wait_ms(func(): return socket.is_connected_to_server() and server.connected_peer_ids().size() == 1), 'reached before the timeout')
	return server.connected_peer_ids()[0]


## A server sending junk cannot flood the client's log: the first few warnings of a kind
## quote a short, escaped preview; later ones are only counted.
func test_junk_frames_from_the_server_are_logged_briefly_and_rate_limited():
	var options := LFSocketOptions.new()
	options.buffer_size = 1 << 20
	var socket := _open_socket(options)
	var peer := await _connected_peer(socket)
	var junk := 'junk\u0001\u001b[31m\n"' + 'x'.repeat(500000)
	server.send_text_to(peer, junk)
	for i in 1001:
		server.send_text_to(peer, 'not json %d' % i)
	assert_true(await _wait_ms(func(): return _warnings_with('not a JSON object').size() >= 6, 5000), 'reached before the timeout')
	await _wait_ms(func(): return false, 200)

	var warnings := _warnings_with('not a JSON object')
	assert_eq(warnings.size(), 6, 'five in full, then one count at the 1000th')
	for warning in warnings:
		assert_lt(warning.length(), 400, 'a short preview, not the whole frame')
		for c in [0x01, 0x1b, 0x0a]:
			assert_false(warning.contains(String.chr(c)), 'no raw control character %d' % c)
	assert_string_contains(warnings[0], '\\u0001\\u001b[31m\\u000a\\"')
	assert_string_contains(warnings[0], '(%d characters)' % junk.length())
	assert_string_contains(warnings[-1], ': 1000 so far')


func test_responses_to_unknown_requests_are_warned_about_a_few_times_only():
	var socket := _open_socket()
	var peer := await _connected_peer(socket)
	for i in 50:
		server.send_to(peer, {'type': 'response', 'id': 'nobody-%d' % i})
	assert_true(await _wait_ms(func(): return _warnings_with('unknown request id').size() >= 5), 'reached before the timeout')
	await _wait_ms(func(): return false, 200)

	assert_eq(_warnings_with('unknown request id').size(), 5)


## Port nobody listens on: every dial is refused.
func _closed_port_url() -> String:
	var closed_port := LFSocketServer.free_port('127.0.0.1')
	return 'ws://127.0.0.1:%d' % closed_port


func test_a_message_queued_offline_is_sent_as_it_was_when_queued():
	var received := []
	server.message_received.connect(func(_peer_id: int, data: Dictionary): received.append(data))
	var socket := LFSocket.new()
	sockets.append(socket)
	var message := { 'event': 'a', 'data': { 'v': 1 } }
	socket.send_message(message)
	message['data']['v'] = 2

	socket.connect_to_server(_url())
	assert_true(await _wait_ms(func(): return received.size() == 1), 'reached before the timeout')

	assert_eq(int(received[0]['data']['v']), 1)


func test_a_reconnect_interval_of_zero_still_waits_between_dials():
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 0
	var attempts := [0]
	var socket := LFSocket.new()
	sockets.append(socket)
	socket.reconnect_scheduled.connect(func(attempt: int): attempts[0] = attempt)

	socket.connect_to_server(_closed_port_url(), options)
	await _wait_ms(func(): return false, 600)

	assert_lt(attempts[0], 20, 'about one dial per 40 ms at most, not one per frame')
	_tolerate_macos_refusal_noise()


func test_a_nan_decay_does_not_collapse_the_wait_to_zero():
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 100
	options.reconnect_decay = NAN
	var attempts := [0]
	var socket := LFSocket.new()
	sockets.append(socket)
	socket.reconnect_scheduled.connect(func(attempt: int): attempts[0] = attempt)

	socket.connect_to_server(_closed_port_url(), options)
	await _wait_ms(func(): return false, 600)

	assert_lt(attempts[0], 9, 'waits stay near 100 ms')
	_tolerate_macos_refusal_noise()


func test_the_first_reconnect_wait_is_capped_by_the_maximum():
	if _refusal_unreported():
		pending(_REFUSAL_REASON)
		return
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 60000
	options.max_reconnect_interval_ms = 100
	var attempts := [0]
	var socket := LFSocket.new()
	sockets.append(socket)
	socket.reconnect_scheduled.connect(func(attempt: int): attempts[0] = attempt)

	socket.connect_to_server(_closed_port_url(), options)

	assert_true(await _wait_ms(func(): return attempts[0] >= 2, 2000), 'a second dial happens within the cap')
	_tolerate_macos_refusal_noise()


func test_a_non_positive_buffer_size_falls_back_to_the_default():
	server.message_received.connect(func(peer_id: int, data: Dictionary):
		server.send_to(peer_id, { 'event': 'echo', 'data': data }))
	var options := LFSocketOptions.new()
	options.buffer_size = -1
	var socket := _open_socket(options)
	var echoed := []
	socket.on_dict_event('echo', func(data: Dictionary): echoed.append(data))
	assert_true(await _wait_ms(func(): return socket.is_connected_to_server()), 'reached before the timeout')

	socket.send_message({ 'text': 'x'.repeat(30000) })

	assert_true(await _wait_ms(func(): return echoed.size() == 1), 'a 30 kB message round-trips')
