extends GutTest

## Real socket I/O, deliberately — unlike `test_lf_socket.gd`'s internal-methods
## approach, there's no equivalent shortcut for "a TCP server actually accepted a
## connection and completed a WebSocket handshake." A raw `WebSocketPeer` (not
## `LFSocket`) is the test client, keeping this module's tests decoupled from
## `LFSocket`'s.

var server: LFSocketServer
var client: WebSocketPeer
var port: int


func before_each():
	server = LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	port = server.get_local_port()
	client = WebSocketPeer.new()


func after_each():
	server.stop()
	if client:
		client.close()


func _wait_until(predicate: Callable, max_frames: int = 120) -> bool:
	for i in max_frames:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _connect_client() -> void:
	client.connect_to_url('ws://127.0.0.1:%d' % port)
	assert_true(await _wait_until(func(): client.poll(); return client.get_ready_state() == WebSocketPeer.STATE_OPEN), 'reached before the timeout')


## Boxed in a Dictionary: a lambda captures locals by value, so a plain local assigned
## inside the callback would never be seen here.
func test_a_real_client_connection_is_accepted_and_fires_peer_connected():
	var received := { 'peer_id': -1 }
	server.peer_connected.connect(func(peer_id): received['peer_id'] = peer_id)

	await _connect_client()

	assert_true(received['peer_id'] > 0, 'a connecting client should be assigned a positive peer id')
	assert_true(server.connected_peer_ids().has(received['peer_id']))


func test_a_json_message_from_the_client_is_received_parsed():
	await _connect_client()
	var received := { 'peer_id': null, 'data': null }
	server.message_received.connect(func(peer_id, data): received['peer_id'] = peer_id; received['data'] = data)

	client.send_text(JSON.stringify({ 'type': 'hello', 'payload': { 'n': 42 } }))
	assert_true(await _wait_until(func(): client.poll(); return received['data'] != null), 'reached before the timeout')

	assert_eq(received['data']['type'], 'hello')
	assert_eq(int(received['data']['payload']['n']), 42)


func test_send_to_delivers_a_message_to_the_right_peer():
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]

	server.send_to(peer_id, { 'type': 'greeting', 'payload': { 'text': 'hi' } })

	var received := { 'text': '' }
	assert_true(await _wait_until(func():
		client.poll()
		if client.get_available_packet_count() > 0:
			received['text'] = client.get_packet().get_string_from_utf8()
			return true
		return false
	), 'reached before the timeout')

	var parsed = JSON.parse_string(received['text'])
	assert_eq(parsed['type'], 'greeting')
	assert_eq(parsed['payload']['text'], 'hi')


func test_send_text_to_delivers_already_encoded_text_and_refuses_an_unknown_peer():
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]

	assert_eq(server.send_text_to(peer_id + 999, '{}'), ERR_DOES_NOT_EXIST)
	server.send_text_to(peer_id, '{"type":"pre-encoded"}')

	var received := { 'text': '' }
	assert_true(await _wait_until(func():
		client.poll()
		if client.get_available_packet_count() > 0:
			received['text'] = client.get_packet().get_string_from_utf8()
			return true
		return false
	), 'reached before the timeout')
	assert_eq(received['text'], '{"type":"pre-encoded"}')


func test_disconnecting_the_client_fires_peer_disconnected():
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var received := { 'peer_id': -1 }
	server.peer_disconnected.connect(func(peer_id): received['peer_id'] = peer_id)

	client.close()
	assert_true(await _wait_until(func(): client.poll(); return received['peer_id'] != -1), 'reached before the timeout')

	assert_true(received['peer_id'] > 0)
	assert_true(server.connected_peer_ids().is_empty())


func test_two_concurrent_clients_get_distinct_peer_ids():
	var second_client := WebSocketPeer.new()
	var peer_ids := []
	server.peer_connected.connect(func(peer_id): peer_ids.append(peer_id))

	await _connect_client()
	second_client.connect_to_url('ws://127.0.0.1:%d' % port)
	assert_true(await _wait_until(func(): second_client.poll(); return second_client.get_ready_state() == WebSocketPeer.STATE_OPEN), 'reached before the timeout')
	assert_true(await _wait_until(func(): return peer_ids.size() >= 2), 'reached before the timeout')

	assert_eq(peer_ids.size(), 2)
	assert_ne(peer_ids[0], peer_ids[1])

	second_client.close()


## LFSocket's heartbeat sends {type: ping} and drops the connection if no pong comes
## back, so the server half must answer it — and keep it out of the application's messages.
func test_a_ping_is_answered_with_a_pong_and_not_surfaced_as_a_message():
	await _connect_client()
	var messages := []
	server.message_received.connect(func(_peer_id, data): messages.append(data))

	client.send_text(JSON.stringify({ 'type': 'ping' }))
	var reply := { 'data': null }
	assert_true(await _wait_until(func():
		client.poll()
		while client.get_available_packet_count() > 0:
			reply['data'] = JSON.parse_string(client.get_packet().get_string_from_utf8())
		return reply['data'] != null), 'reached before the timeout')

	assert_eq(reply['data'], { 'type': 'pong' })
	assert_eq(messages, [], 'heartbeat traffic is not application data')


func test_broadcast_skips_peers_still_mid_handshake():
	var raw := StreamPeerTCP.new() # a TCP connection that never speaks WebSocket
	raw.connect_to_host('127.0.0.1', port)
	# Peer ids start at 1 on a fresh server: id 1 exists once the connection is accepted.
	assert_true(await _wait_ms(func(): raw.poll(); return server.send_text_to(1, '{}') != ERR_DOES_NOT_EXIST), 'reached before the timeout')

	server.broadcast({ 'type': 'hello' })

	assert_eq(server.connected_peer_ids(), [])
	assert_engine_error_count(0, 'nothing was sent to the peer that is not open yet')
	raw.disconnect_from_host()


func test_stop_reports_every_connected_peer_as_disconnected():
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var gone := []
	server.peer_disconnected.connect(func(peer_id): gone.append(peer_id))
	var ids = server.connected_peer_ids()

	server.stop()

	assert_eq(gone, ids)


func test_is_listening_is_true_only_between_listen_and_stop():
	var fresh := LFSocketServer.new()
	assert_false(fresh.is_listening(), 'a server never told to listen is not listening')

	assert_eq(fresh.listen(0, '127.0.0.1'), OK)
	var fresh_port := fresh.get_local_port()
	assert_true(fresh.is_listening(), 'a successful listen starts listening')

	fresh.stop()
	assert_false(fresh.is_listening(), 'stop ends listening')


func test_get_local_port_reads_back_the_port_listen_0_was_given():
	var fresh := LFSocketServer.new()
	assert_eq(fresh.get_local_port(), 0, 'not listening yet')
	assert_eq(fresh.listen(0, '127.0.0.1'), OK)
	var bound := fresh.get_local_port()

	assert_between(bound, 1, 65535)
	var probe := TCPServer.new()
	assert_ne(probe.listen(bound, '127.0.0.1'), OK, 'the server holds the port it reports')
	fresh.stop()
	assert_eq(fresh.get_local_port(), 0, 'stopped')


func test_a_failed_listen_leaves_the_server_not_listening():
	var second := LFSocketServer.new()

	var err := second.listen(port, '127.0.0.1') # already bound by before_each's server

	assert_ne(err, OK, 'binding a port already in use must fail')
	assert_false(second.is_listening(), 'a failed bind must not report listening')


func test_disconnect_peer_with_an_unknown_id_is_a_no_op():
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')

	server.disconnect_peer(9999)
	await get_tree().process_frame

	assert_eq(server.connected_peer_ids().size(), 1, 'other peers stay connected')


func test_disconnect_peer_closes_that_peers_connection():
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]

	server.disconnect_peer(peer_id)
	assert_true(await _wait_until(func(): client.poll(); return client.get_ready_state() == WebSocketPeer.STATE_CLOSED), 'reached before the timeout')

	assert_eq(client.get_ready_state(), WebSocketPeer.STATE_CLOSED, 'the client sees the connection closed')
	assert_false(server.connected_peer_ids().has(peer_id), 'the closed peer is no longer connected')


func test_disconnect_peer_fires_peer_disconnected_once_the_close_completes():
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]
	var gone := []
	server.peer_disconnected.connect(func(id): gone.append(id))

	server.disconnect_peer(peer_id)
	assert_true(await _wait_until(func(): client.poll(); return !gone.is_empty(), 300), 'reached before the timeout')

	assert_eq(gone, [peer_id], "a peer closed from the server side is still reported as disconnected")


func test_a_message_larger_than_godots_64_kib_default_reaches_the_client():
	client.inbound_buffer_size = 1 << 22
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var big := 'x'.repeat(200 * 1024)

	assert_eq(server.send_to(server.connected_peer_ids()[0], { 'type': 'big', 'payload': big }), OK)

	var received := { 'text': '' }
	assert_true(await _wait_until(func():
		client.poll()
		if client.get_available_packet_count() > 0:
			received['text'] = client.get_packet().get_string_from_utf8()
			return true
		return false
	), 'reached before the timeout')
	assert_eq(str(JSON.parse_string(received['text'])['payload']).length(), big.length())


func test_a_connection_beyond_max_peers_is_refused():
	server.max_peers = 1
	var connected := []
	server.peer_connected.connect(func(peer_id): connected.append(peer_id))
	await _connect_client()
	var second := WebSocketPeer.new()
	second.connect_to_url('ws://127.0.0.1:%d' % port)

	var closed := await _wait_until(func(): second.poll(); return second.get_ready_state() == WebSocketPeer.STATE_CLOSED, 300)

	assert_true(closed, 'the extra connection is closed by the server')
	assert_eq(connected.size(), 1, 'only the first peer is reported as connected')
	assert_eq(server.connected_peer_ids().size(), 1)


func test_max_peers_zero_means_unlimited():
	server.max_peers = 0
	await _connect_client()
	var second := WebSocketPeer.new()
	second.connect_to_url('ws://127.0.0.1:%d' % port)
	var opened := await _wait_until(func(): second.poll(); return second.get_ready_state() == WebSocketPeer.STATE_OPEN)
	assert_true(opened)
	second.close()


func test_a_single_poll_handles_at_most_the_packet_budget_per_peer():
	server.packets_per_poll = 2
	await _connect_client()
	var frames := []
	server.message_received.connect(func(_peer_id, _data): frames.append(Engine.get_process_frames()))
	for i in 6:
		client.send_text(JSON.stringify({ 'type': 'n', 'i': i }))
	client.poll()

	assert_true(await _wait_until(func(): client.poll(); return frames.size() >= 6, 300), 'reached before the timeout')

	assert_eq(frames.size(), 6, 'every message is still delivered, over several polls')
	var per_frame := {}
	for f in frames:
		per_frame[f] = per_frame.get(f, 0) + 1
	assert_lte(per_frame.values().max(), 2, 'no single poll delivers more than the budget')


func test_a_malformed_frame_is_dropped_quietly():
	await _connect_client()
	var received := []
	server.message_received.connect(func(_peer_id, data): received.append(data))
	client.send_text('{not json')
	client.send_text(JSON.stringify({ 'type': 'after' }))

	assert_true(await _wait_until(func(): client.poll(); return received.size() >= 1), 'reached before the timeout')

	assert_eq(received.size(), 1)
	assert_engine_error_count(0, 'a malformed frame is dropped without an engine error')


## Polls `client` and collects every text frame it has received into `into`.
func _drain(peer: WebSocketPeer, into: Array) -> void:
	peer.poll()
	while peer.get_available_packet_count() > 0:
		into.append(peer.get_packet().get_string_from_utf8())


## Waits until `predicate` holds or `ms` milliseconds pass; true when it held.
func _wait_ms(predicate: Callable, ms: int = 3000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()


func _open_extra_client() -> WebSocketPeer:
	var extra := WebSocketPeer.new()
	extra.connect_to_url('ws://127.0.0.1:%d' % port)
	assert_true(await _wait_ms(func(): extra.poll(); return extra.get_ready_state() == WebSocketPeer.STATE_OPEN), 'reached before the timeout')
	return extra


func test_frames_with_wrongly_typed_fields_never_raise_or_delay_other_peers():
	await _connect_client()
	var victim := await _open_extra_client()
	assert_true(await _wait_ms(func(): return server.connected_peer_ids().size() == 2), 'reached before the timeout')
	var victim_got := []
	var others := []
	server.message_received.connect(func(_peer_id, data):
		if data.get('who') is String and data.get('who') == 'victim':
			victim_got.append(Engine.get_process_frames())
		else:
			others.append(data))
	for i in 20:
		client.send_text('{"type": 1}')
		client.send_text('{"type": [1]}')
		client.send_text('{"type": {"a": 1}}')
		client.send_text('[1, 2]')
		client.send_text('"text"')
	client.poll()
	victim.send_text(JSON.stringify({ 'who': 'victim' }))
	var sent_at := Engine.get_process_frames()

	assert_true(await _wait_ms(func(): client.poll(); victim.poll(); return !victim_got.is_empty()), 'reached before the timeout')

	assert_eq(victim_got.size(), 1, "the other peer's message arrives")
	if !victim_got.is_empty():
		assert_lte(victim_got[0] - sent_at, 10, 'it is not held back behind the bad frames')
	assert_engine_error_count(0, 'wrongly typed fields never raise a script error')
	assert_true(await _wait_ms(func(): client.poll(); return others.size() >= 60, 2000), 'reached before the timeout')
	assert_eq(others.size(), 60, 'objects with odd field types are still delivered as messages')
	victim.close()


func test_an_idle_tcp_connection_is_dropped_after_the_handshake_timeout():
	server.max_pending_handshakes = 1
	server.handshake_timeout_ms = 100
	var raw := StreamPeerTCP.new() # connects but never speaks WebSocket
	raw.connect_to_host('127.0.0.1', port)
	assert_true(await _wait_ms(func(): raw.poll(); return raw.get_status() == StreamPeerTCP.STATUS_CONNECTED), 'reached before the timeout')
	assert_true(await _wait_ms(func(): return server.peer_address(1) == '127.0.0.1'), 'the server accepted it first')

	var opened := await _wait_ms(func():
		if client.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			client = WebSocketPeer.new()
			client.connect_to_url('ws://127.0.0.1:%d' % port)
		client.poll()
		return client.get_ready_state() == WebSocketPeer.STATE_OPEN, 3000)

	assert_true(opened, 'the idle connection frees its slot for a real client')
	raw.disconnect_from_host()


## The code the sender of an oversized frame sees: 1009. On Windows the server's close can
## reset the connection before the client reads the close frame, which leaves -1.
func _too_big_close_code() -> int:
	return -1 if OS.get_name() == "Windows" else 1009


func test_the_default_inbound_buffer_is_small_and_an_oversized_frame_closes_only_that_peer():
	assert_lte(server.inbound_buffer_size, 1 << 18, 'each peer reserves its inbound buffer up front')
	assert_gt(server.outbound_buffer_size, 1 << 16, 'large outgoing state still fits')
	await _connect_client()
	var other := await _open_extra_client()
	assert_true(await _wait_ms(func(): return server.connected_peer_ids().size() == 2), 'reached before the timeout')
	client.outbound_buffer_size = 1 << 22

	client.send_text('{"x":"%s"}' % 'y'.repeat(server.inbound_buffer_size * 2))
	var closed := await _wait_ms(func(): client.poll(); other.poll(); return client.get_ready_state() == WebSocketPeer.STATE_CLOSED)

	assert_true(closed, 'the peer that sent the oversized frame is closed')
	assert_eq(client.get_close_code(), _too_big_close_code(), 'with "message too big"')
	assert_eq(server.connected_peer_ids().size(), 1, 'the other peer stays connected')
	other.close()


func test_stop_from_a_message_handler_is_safe_with_several_peers():
	await _connect_client()
	var second := await _open_extra_client()
	assert_true(await _wait_ms(func(): return server.connected_peer_ids().size() == 2), 'reached before the timeout')
	var gone := []
	server.peer_disconnected.connect(func(peer_id): gone.append(peer_id))
	server.message_received.connect(func(_peer_id, _data): server.stop())

	client.send_text('{"type":"a"}')
	client.send_text('{"type":"b"}')
	second.send_text('{"type":"c"}')
	assert_true(await _wait_ms(func(): client.poll(); second.poll(); return !server.is_listening()), 'reached before the timeout')
	await get_tree().process_frame

	assert_false(server.is_listening())
	assert_eq(gone.size(), 2, 'every open peer is reported once')
	assert_engine_error_count(0, 'the poll in progress survives the stop')
	second.close()


func test_disconnect_peer_from_a_message_handler_stops_reading_that_peer():
	await _connect_client()
	var received := []
	server.message_received.connect(func(peer_id, data):
		received.append(data)
		server.disconnect_peer(peer_id))
	for i in 5:
		client.send_text(JSON.stringify({ 'i': i }))

	assert_true(await _wait_ms(func(): client.poll(); return client.get_ready_state() == WebSocketPeer.STATE_CLOSED), 'reached before the timeout')

	assert_eq(received.size(), 1, 'frames after the disconnect are not delivered')
	assert_engine_error_count(0)


func test_a_message_sent_just_before_disconnect_peer_is_delivered():
	client.inbound_buffer_size = 1 << 22
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]
	var big := 'y'.repeat(1 << 20)

	server.send_to(peer_id, { 'type': 'bye' })
	server.send_to(peer_id, { 'type': 'big', 'payload': big })
	server.disconnect_peer(peer_id)
	var got := []
	assert_true(await _wait_ms(func(): _drain(client, got); return client.get_ready_state() == WebSocketPeer.STATE_CLOSED), 'reached before the timeout')

	assert_eq(got.size(), 2, 'both queued messages arrive before the close')
	if got.size() == 2:
		assert_eq(JSON.parse_string(got[0]), { 'type': 'bye' })
		assert_eq(str(JSON.parse_string(got[1])['payload']).length(), big.length())
	assert_eq(client.get_ready_state(), WebSocketPeer.STATE_CLOSED, 'and the peer is closed afterwards')


func test_a_peer_being_disconnected_is_no_longer_listed_or_sendable():
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]

	server.disconnect_peer(peer_id)

	assert_eq(server.connected_peer_ids(), [], 'a closing peer is not reported as connected')
	assert_eq(server.send_to(peer_id, { 'type': 'late' }), ERR_UNAVAILABLE)


func test_sending_to_a_peer_still_mid_handshake_fails_quietly():
	var raw := StreamPeerTCP.new() # connects but never speaks WebSocket
	raw.connect_to_host('127.0.0.1', port)
	var result := [ERR_DOES_NOT_EXIST]
	assert_true(await _wait_ms(func():
		raw.poll()
		result[0] = server.send_text_to(1, '{}') # the first peer a fresh server accepts
		return result[0] != ERR_DOES_NOT_EXIST), 'reached before the timeout')

	assert_eq(result[0], ERR_UNAVAILABLE)
	assert_engine_error_count(0, 'no engine error for a peer that is not open yet')
	raw.disconnect_from_host()


## A peer's address is what a server rate-limits or bans by; it is known from the moment
## the connection is accepted, and an unknown id has none.
func test_peer_address_is_the_connecting_clients_ip():
	var received := { 'peer_id': -1 }
	server.peer_connected.connect(func(peer_id): received['peer_id'] = peer_id)

	await _connect_client()

	assert_eq(server.peer_address(received['peer_id']), '127.0.0.1')
	assert_eq(server.peer_address(9999), '', 'an unknown peer has no address')


func test_free_port_returns_a_port_the_os_just_had_free():
	var free := LFSocketServer.free_port()

	assert_between(free, 1, 65535)
	var probe := TCPServer.new()
	assert_eq(probe.listen(free, '127.0.0.1'), OK, 'the returned port can be bound')
	probe.stop()


func test_free_port_in_range_skips_taken_and_busy_ports_in_order():
	var asked := []
	var is_free := func(port: int) -> bool:
		asked.append(port)
		return port >= 5004
	var taken := func(port: int) -> bool: return port == 5003 or port == 5004
	assert_eq(LFSocketServer.free_port_in_range(5001, 5009, taken, is_free), 5005)
	assert_eq(asked, [5001, 5002, 5005], 'is_free is skipped for taken ports and stops at the answer')


func test_free_port_in_range_is_minus_one_when_nothing_fits():
	assert_eq(LFSocketServer.free_port_in_range(5001, 5003, Callable(), func(_port: int) -> bool: return false), -1)
	assert_eq(LFSocketServer.free_port_in_range(5003, 5001, Callable(), func(_port: int) -> bool: return true), -1, 'a reversed range is empty')


func test_free_port_in_range_defaults_to_the_real_port_probe():
	var free := LFSocketServer.free_port()
	assert_eq(LFSocketServer.free_port_in_range(free, free), free)
	var held := TCPServer.new()
	assert_eq(held.listen(0, '127.0.0.1'), OK)
	var busy := held.get_local_port()
	assert_eq(LFSocketServer.free_port_in_range(busy, busy), -1)
	held.stop()


func test_free_port_returns_minus_one_for_an_address_it_cannot_bind():
	assert_eq(LFSocketServer.free_port('203.0.113.1'), -1)


# ---- port probing

func test_a_port_held_on_one_address_is_not_free():
	var held := TCPServer.new()
	assert_eq(held.listen(0, '127.0.0.1'), OK)
	var held_port := held.get_local_port()

	assert_false(LFSocketServer.is_port_free(held_port), 'a loopback-only listener still owns the port')
	held.stop()
	assert_true(LFSocketServer.is_port_free(held_port))


func test_a_port_held_on_every_address_is_not_free():
	var held := TCPServer.new()
	assert_eq(held.listen(0, '*'), OK)
	var held_port := held.get_local_port()

	assert_false(LFSocketServer.is_port_free(held_port))
	held.stop()


# ---- lifetime and the poll loop

func test_peer_ids_are_never_reused_across_stop_and_listen():
	var ids := []
	server.peer_connected.connect(func(peer_id): ids.append(peer_id))
	await _connect_client()
	assert_true(await _wait_ms(func(): return ids.size() == 1), 'reached before the timeout')
	server.stop()
	client.close()

	assert_eq(server.listen(0, '127.0.0.1'), OK)
	port = server.get_local_port()
	client = WebSocketPeer.new()
	await _connect_client()
	assert_true(await _wait_ms(func(): return ids.size() == 2), 'reached before the timeout')

	assert_eq(ids.size(), 2)
	if ids.size() == 2:
		assert_gt(ids[1], ids[0])


func test_stop_then_listen_in_one_frame_keeps_a_single_poll_loop():
	server.stop()
	assert_eq(server.listen(port, '127.0.0.1'), OK)
	server.packets_per_poll = 1
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var frames := []
	server.message_received.connect(func(_peer_id, _data): frames.append(Engine.get_process_frames()))

	client.send_text(JSON.stringify({ 'n': 1 }))
	client.send_text(JSON.stringify({ 'n': 2 }))
	assert_true(await _wait_ms(func(): client.poll(); return frames.size() == 2), 'reached before the timeout')

	assert_eq(frames.size(), 2)
	if frames.size() == 2:
		assert_ne(frames[0], frames[1], 'one loop reads one packet per frame; two loops would read both in one')


func test_a_server_dropped_without_stop_releases_its_port():
	var dropped := LFSocketServer.new()
	assert_eq(dropped.listen(0, '127.0.0.1'), OK)
	var dropped_port := dropped.get_local_port()
	var ref: WeakRef = weakref(dropped)

	dropped = null
	await get_tree().process_frame

	assert_null(ref.get_ref(), 'the poll loop does not keep the server alive')
	var probe := TCPServer.new()
	assert_eq(probe.listen(dropped_port, '127.0.0.1'), OK, 'the port is free again')
	probe.stop()


func test_a_peer_whose_queue_never_drains_is_closed_at_the_flush_deadline():
	server.outbound_buffer_size = 1 << 25
	server.disconnect_flush_timeout_ms = 1000 # far past the 100 ms check below, even on a slow machine
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]
	var chunk := 'z'.repeat(1 << 20)
	for i in 24:
		server.send_text_to(peer_id, chunk)
	var socket: WebSocketPeer = server._peers[peer_id]

	server.disconnect_peer(peer_id)
	await _wait_ms(func(): return false, 100)
	assert_eq(socket.get_ready_state(), WebSocketPeer.STATE_OPEN, 'still flushing before the deadline')
	assert_gt(socket.get_current_outbound_buffered_amount(), 0, 'the client never reads, so the queue is stuck')

	assert_true(await _wait_ms(func(): return socket.get_ready_state() != WebSocketPeer.STATE_OPEN, 4000), 'reached before the timeout')
	assert_ne(socket.get_ready_state(), WebSocketPeer.STATE_OPEN, 'closed at the deadline anyway')
	var disconnected := []
	server.peer_disconnected.connect(func(id): disconnected.append(id))
	assert_true(await _wait_ms(func():
		var drained := []
		_drain(client, drained)
		return disconnected == [peer_id], 5000), 'reached before the timeout')
	assert_eq(disconnected, [peer_id])


## A raw TCP client that sends its WebSocket upgrade request and a first text frame in
## one write, before the server has answered.
func _pipelined_handshake_and_frame(text: String) -> StreamPeerTCP:
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host('127.0.0.1', port)
	var request := ('GET / HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
		'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n') % port
	var payload := text.to_utf8_buffer()
	var mask := PackedByteArray([1, 2, 3, 4])
	var frame := PackedByteArray([0x81, 0x80 | payload.size()])
	frame.append_array(mask)
	for i in payload.size():
		frame.append(payload[i] ^ mask[i % 4])
	var bytes := request.to_utf8_buffer()
	bytes.append_array(frame)
	var deadline := Time.get_ticks_msec() + 2000
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		tcp.poll()
	tcp.put_data(bytes)
	return tcp


func test_a_message_that_arrives_with_the_handshake_is_read_in_the_poll_that_reports_the_open():
	var events := []
	server.peer_connected.connect(func(_id): events.append(['connected', Engine.get_process_frames()]))
	server.message_received.connect(func(_id, data): events.append([str(data.get('type')), Engine.get_process_frames()]))

	var tcp := _pipelined_handshake_and_frame(JSON.stringify({ 'type': 'early' }))
	assert_true(await _wait_ms(func(): return events.size() >= 2), 'reached before the timeout')
	tcp.disconnect_from_host()

	assert_eq(events.size(), 2)
	if events.size() == 2:
		assert_eq([events[0][0], events[1][0]], ['connected', 'early'])
		assert_eq(events[0][1], events[1][1], 'both in one poll')


## stop() lets messages already sent go out before it closes each peer, even when the
## server is dropped right after.
func test_messages_sent_just_before_stop_are_delivered_even_if_the_server_is_dropped():
	client.inbound_buffer_size = 1 << 22
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var big := 'y'.repeat(1 << 20)

	server.broadcast({ 'type': 'bye' })
	server.broadcast({ 'type': 'big', 'payload': big })
	server.stop()
	server = LFSocketServer.new()
	var got := []
	assert_true(await _wait_ms(func(): _drain(client, got); return client.get_ready_state() == WebSocketPeer.STATE_CLOSED), 'reached before the timeout')

	assert_eq(got.size(), 2, 'both queued messages arrive before the close')
	if got.size() == 2:
		assert_eq(JSON.parse_string(got[0]), { 'type': 'bye' })
		assert_eq(str(JSON.parse_string(got[1])['payload']).length(), big.length())
	assert_eq(client.get_ready_state(), WebSocketPeer.STATE_CLOSED, 'and the peer is closed afterwards')


## While its peers flush, the server is already stopped: not listening, no peers, the
## port free, every open peer reported gone.
func test_a_flushing_stop_releases_the_port_and_reports_peers_at_once():
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var ids := server.connected_peer_ids()
	var gone := []
	server.peer_disconnected.connect(func(peer_id): gone.append(peer_id))

	server.stop()

	assert_eq(gone, ids)
	assert_false(server.is_listening())
	assert_eq(server.connected_peer_ids(), [])
	var probe := TCPServer.new()
	assert_eq(probe.listen(port, '127.0.0.1'), OK, 'the port is free again')
	probe.stop()


func test_a_flushing_stop_closes_a_peer_whose_queue_never_drains_at_the_deadline():
	server.outbound_buffer_size = 1 << 25
	server.disconnect_flush_timeout_ms = 1000 # far past the 100 ms check below, even on a slow machine
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]
	var chunk := 'z'.repeat(1 << 20)
	for i in 24:
		server.send_text_to(peer_id, chunk)
	var socket: WebSocketPeer = server._peers[peer_id]

	server.stop()
	await _wait_ms(func(): return false, 100)
	assert_eq(socket.get_ready_state(), WebSocketPeer.STATE_OPEN, 'still flushing before the deadline')

	assert_true(await _wait_ms(func(): return socket.get_ready_state() != WebSocketPeer.STATE_OPEN, 4000), 'reached before the timeout')
	assert_ne(socket.get_ready_state(), WebSocketPeer.STATE_OPEN, 'closed at the deadline anyway')


func test_stop_without_flush_closes_every_peer_at_once():
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var socket: WebSocketPeer = server._peers[server.connected_peer_ids()[0]]

	server.stop(false)

	assert_ne(socket.get_ready_state(), WebSocketPeer.STATE_OPEN)


func test_frames_a_peer_sends_while_its_close_is_in_flight_are_dropped():
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]
	var received := []
	server.message_received.connect(func(_peer_id, data): received.append(data))

	server.disconnect_peer(peer_id)
	assert_true(await _wait_ms(func():
		client.send_text(JSON.stringify({ 'late': true }))
		client.poll()
		return client.get_ready_state() == WebSocketPeer.STATE_CLOSED), 'reached before the timeout')
	await _wait_ms(func(): return false, 100)

	assert_eq(received, [], 'nothing from a peer being disconnected is delivered')


func test_send_to_an_unknown_peer_is_refused():
	assert_eq(server.send_to(9999, { 'type': 'x' }), ERR_DOES_NOT_EXIST)


func test_settings_start_at_their_documented_defaults():
	var fresh := LFSocketServer.new()
	assert_eq(fresh.inbound_buffer_size, 1 << 16)
	assert_eq(fresh.outbound_buffer_size, 1 << 22)
	assert_eq(fresh.max_peers, 64)
	assert_eq(fresh.max_pending_handshakes, 32)
	assert_eq(fresh.max_pending_handshakes_per_address, 4)
	assert_eq(fresh.packets_per_poll, 64)
	assert_eq(fresh.handshake_timeout_ms, 3000)
	assert_eq(fresh.disconnect_flush_timeout_ms, 2000)
	assert_eq(fresh.idle_timeout_ms, 60000)
	assert_false(fresh.is_listening())
	assert_eq(fresh.connected_peer_ids(), [])


func test_settings_defaults_come_from_the_public_default_constants():
	var fresh := LFSocketServer.new()
	assert_eq(fresh.inbound_buffer_size, LFSocketServer.DEFAULT_INBOUND_BUFFER_SIZE)
	assert_eq(fresh.outbound_buffer_size, LFSocketServer.DEFAULT_OUTBOUND_BUFFER_SIZE)
	assert_eq(fresh.max_peers, LFSocketServer.DEFAULT_MAX_PEERS)
	assert_eq(fresh.max_pending_handshakes, LFSocketServer.DEFAULT_MAX_PENDING_HANDSHAKES)
	assert_eq(fresh.max_pending_handshakes_per_address, LFSocketServer.DEFAULT_MAX_PENDING_HANDSHAKES_PER_ADDRESS)
	assert_eq(fresh.packets_per_poll, LFSocketServer.DEFAULT_PACKETS_PER_POLL)
	assert_eq(fresh.handshake_timeout_ms, LFSocketServer.DEFAULT_HANDSHAKE_TIMEOUT_MS)
	assert_eq(fresh.disconnect_flush_timeout_ms, LFSocketServer.DEFAULT_DISCONNECT_FLUSH_TIMEOUT_MS)
	assert_eq(fresh.idle_timeout_ms, LFSocketServer.DEFAULT_IDLE_TIMEOUT_MS)
	assert_gt(LFSocketServer.DEFAULT_IDLE_TIMEOUT_MS, LFSocketOptions.DEFAULT_HEARTBEAT_INTERVAL_MS + LFSocketOptions.DEFAULT_HEARTBEAT_TIMEOUT_MS,
			"a default client's heartbeat keeps it from idling out")
	assert_eq(LFSocketServer.DEFAULT_FREE_PORT_IP, '127.0.0.1')
	assert_eq(LFSocketServer.DEFAULT_LISTEN_HOST, '*', 'the default listens on every interface')


func test_listen_while_listening_is_refused_quietly_and_keeps_the_port():
	await _connect_client()
	assert_eq(server.listen(0, '127.0.0.1'), ERR_ALREADY_IN_USE, 'any other port is refused too')

	assert_engine_error_count(0)
	assert_true(server.is_listening())
	var probe := TCPServer.new()
	assert_ne(probe.listen(port, '127.0.0.1'), OK, 'the first port is still held')
	assert_engine_error_count(0)
	probe.stop()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	assert_eq(server.connected_peer_ids().size(), 1, 'the open peer is untouched')


func test_a_peer_that_goes_silent_is_dropped_after_the_idle_timeout():
	server.idle_timeout_ms = 200
	var gone := []
	server.peer_disconnected.connect(func(id): gone.append(id))
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]

	# The client keeps its connection but never sends anything (as if its machine vanished).
	var dropped := await _wait_ms(func(): return !gone.is_empty(), 2000)

	assert_true(dropped)
	assert_eq(gone, [peer_id])
	assert_eq(server.connected_peer_ids(), [])
	assert_eq(server.peer_address(peer_id), '', 'the dropped peer is forgotten')


func test_a_peer_that_keeps_sending_is_not_dropped():
	server.idle_timeout_ms = 200
	var gone := []
	server.peer_disconnected.connect(func(id): gone.append(id))
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')

	var until := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < until:
		client.send_text(JSON.stringify({ 'type': 'ping' }))
		await _wait_ms(func(): client.poll(); return false, 50)

	assert_eq(gone, [], 'a heartbeat every 50 ms keeps it in')
	assert_eq(server.connected_peer_ids().size(), 1)


func test_an_idle_timeout_of_zero_never_drops_a_quiet_peer():
	server.idle_timeout_ms = 0
	await _connect_client()
	assert_true(await _wait_ms(func(): return server.connected_peer_ids().size() == 1), 'the server lists the peer first')
	await _wait_ms(func(): client.poll(); return false, 300)

	assert_eq(server.connected_peer_ids().size(), 1)


func test_disconnect_peer_closes_with_the_code_that_stops_reconnecting():
	await _connect_client()
	assert_true(await _wait_until(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')

	server.disconnect_peer(server.connected_peer_ids()[0])
	assert_true(await _wait_until(func(): client.poll(); return client.get_ready_state() == WebSocketPeer.STATE_CLOSED), 'reached before the timeout')

	assert_eq(client.get_close_code(), LFSocket.DISCONNECTED_BY_SERVER_CODE)


func test_a_tls_connection_that_never_handshakes_is_dropped_after_the_handshake_timeout():
	server.stop()
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	server.handshake_timeout_ms = 200
	assert_eq(server.listen(port, '127.0.0.1', TLSOptions.server(key, crypto.generate_self_signed_certificate(key))), OK)
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host('127.0.0.1', port)
	var held := func() -> int: return server._peers.size() + server._tls_pending.size()
	assert_true(await _wait_ms(func(): return held.call() == 1, 1000), 'reached before the timeout')
	assert_eq(server.peer_address(server._next_peer_id - 1), '127.0.0.1', 'the address is known before the handshake')

	var freed := await _wait_ms(func(): return held.call() == 0, 2000)

	assert_true(freed, 'the silent connection gave its slot back')
	assert_eq(server.connected_peer_ids(), [])
	tcp.disconnect_from_host()


# ---- dropped frames, slots and closes of peers that never opened

func test_binary_frames_and_non_object_json_are_dropped_and_later_messages_still_arrive():
	await _connect_client()
	var received := []
	server.message_received.connect(func(_peer_id, data): received.append(data))
	client.send(PackedByteArray([0x7b, 0x7d])) # "{}" sent as a binary frame
	client.send_text('[1, 2]')
	client.send_text('"text"')
	client.send_text(JSON.stringify({ 'type': 'after' }))

	assert_true(await _wait_ms(func(): client.poll(); return !received.is_empty()), 'reached before the timeout')
	await _wait_ms(func(): client.poll(); return false, 100)

	assert_eq(received, [{ 'type': 'after' }])
	assert_engine_error_count(0)


func test_a_handshake_timeout_of_zero_lets_a_silent_connection_keep_its_slot():
	server.max_pending_handshakes = 1
	server.handshake_timeout_ms = 0
	var raw := StreamPeerTCP.new() # connects but never speaks WebSocket
	raw.connect_to_host('127.0.0.1', port)
	assert_true(await _wait_ms(func(): raw.poll(); return server.peer_address(1) == '127.0.0.1'), 'reached before the timeout')
	await _wait_ms(func(): return false, 300)

	client.connect_to_url('ws://127.0.0.1:%d' % port)
	var refused := await _wait_ms(func(): client.poll(); return client.get_ready_state() == WebSocketPeer.STATE_CLOSED)

	assert_true(refused, 'the silent connection still holds the only slot')
	assert_eq(server.peer_address(1), '127.0.0.1')
	raw.disconnect_from_host()


func test_disconnect_peer_twice_closes_once_and_reports_once():
	await _connect_client()
	assert_true(await _wait_ms(func(): return !server.connected_peer_ids().is_empty()), 'reached before the timeout')
	var peer_id: int = server.connected_peer_ids()[0]
	var gone := []
	server.peer_disconnected.connect(func(id): gone.append(id))

	server.disconnect_peer(peer_id)
	server.disconnect_peer(peer_id)
	assert_true(await _wait_ms(func(): client.poll(); return !gone.is_empty()), 'reached before the timeout')
	await _wait_ms(func(): client.poll(); return false, 100)

	assert_eq(gone, [peer_id])
	assert_eq(client.get_close_code(), LFSocket.DISCONNECTED_BY_SERVER_CODE)


## A connection still in its WebSocket handshake is closed at once; it never opened, so
## no signal fires, and its slot is free again.
func test_disconnect_peer_on_a_connection_mid_handshake_frees_its_slot_without_signals():
	server.max_pending_handshakes = 1
	server.handshake_timeout_ms = 0
	var events := []
	server.peer_connected.connect(func(id): events.append(['connected', id]))
	server.peer_disconnected.connect(func(id): events.append(['disconnected', id]))
	var raw := StreamPeerTCP.new() # connects but never speaks WebSocket
	raw.connect_to_host('127.0.0.1', port)
	assert_true(await _wait_ms(func(): raw.poll(); return server.peer_address(1) == '127.0.0.1'), 'reached before the timeout')

	server.disconnect_peer(1)
	assert_true(await _wait_ms(func(): return server.peer_address(1) == ''), 'reached before the timeout')

	assert_eq(server.peer_address(1), '', 'the connection is gone')
	await _connect_client()
	assert_eq(client.get_ready_state(), WebSocketPeer.STATE_OPEN, 'its slot went to the next client')
	assert_eq(events, [['connected', 2]], 'the dropped connection never reported anything')
	raw.disconnect_from_host()


func _listen_with_tls() -> void:
	server.stop()
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	server.handshake_timeout_ms = 0
	assert_eq(server.listen(port, '127.0.0.1', TLSOptions.server(key, crypto.generate_self_signed_certificate(key))), OK)


## A `wss://` connection whose client never sends its TLS hello has not opened: a kick
## closes it without a signal, and the client sees the close.
func test_disconnect_peer_on_a_tls_connection_that_never_handshakes_closes_it_without_signals():
	await _listen_with_tls()
	var events := []
	server.peer_disconnected.connect(func(id): events.append(id))
	var raw := StreamPeerTCP.new() # never starts its TLS handshake
	raw.connect_to_host('127.0.0.1', port)
	var first := server._next_peer_id
	assert_true(await _wait_ms(func(): raw.poll(); return server.peer_address(first) == '127.0.0.1'), 'reached before the timeout')

	server.disconnect_peer(first)
	var forgotten := await _wait_ms(func(): return server.peer_address(first) == '')

	assert_true(forgotten, 'the connection is gone')
	var closed := await _wait_ms(func():
		raw.poll()
		return raw.get_status() != StreamPeerTCP.STATUS_CONNECTED or raw.get_partial_data(1)[0] != OK, 1000)
	assert_true(closed, 'the client sees its connection closed')
	assert_eq(events, [], 'it never opened, so nothing is reported')
	raw.disconnect_from_host()


func test_stop_closes_tls_connections_that_never_finished_their_handshake():
	await _listen_with_tls()
	var raw := StreamPeerTCP.new() # never starts its TLS handshake
	raw.connect_to_host('127.0.0.1', port)
	var first := server._next_peer_id
	assert_true(await _wait_ms(func(): raw.poll(); return server.peer_address(first) == '127.0.0.1'), 'reached before the timeout')

	server.stop()

	var closed := await _wait_ms(func():
		raw.poll()
		return raw.get_status() != StreamPeerTCP.STATUS_CONNECTED or raw.get_partial_data(1)[0] != OK, 1000)
	assert_true(closed, 'the client sees its connection closed')
	raw.disconnect_from_host()


## The inbound buffer is read when a peer is accepted: shrinking it later limits only
## peers accepted afterwards.
func test_a_changed_inbound_buffer_applies_only_to_peers_accepted_afterwards():
	var received := []
	server.message_received.connect(func(peer_id, _data): received.append(peer_id))
	client.outbound_buffer_size = 1 << 20
	await _connect_client()
	assert_true(await _wait_ms(func(): return server.connected_peer_ids().size() == 1), 'reached before the timeout')
	var early: int = server.connected_peer_ids()[0]
	server.inbound_buffer_size = 1024
	var late := WebSocketPeer.new()
	late.outbound_buffer_size = 1 << 20
	late.connect_to_url('ws://127.0.0.1:%d' % port)
	# Open on both ends: the server can list the peer a poll before the client reads the
	# handshake answer, and a frame sent before then is never sent at all.
	assert_true(await _wait_ms(func(): late.poll(); return late.get_ready_state() == WebSocketPeer.STATE_OPEN and server.connected_peer_ids().size() == 2), 'reached before the timeout')
	var frame := '{"x":"%s"}' % 'y'.repeat(8192)

	client.send_text(frame)
	late.send_text(frame)
	assert_true(await _wait_ms(func(): client.poll(); late.poll(); return !received.is_empty() and late.get_ready_state() == WebSocketPeer.STATE_CLOSED), 'reached before the timeout')

	assert_eq(received, [early], 'the peer accepted before the change still takes 8 KiB')
	assert_eq(late.get_ready_state(), WebSocketPeer.STATE_CLOSED)
	assert_eq(late.get_close_code(), _too_big_close_code(), 'the later peer is limited to 1 KiB')


# ---- connections that never finish their handshake

## Opens `count` raw TCP connections from the loopback address that never speak WebSocket.
func _silent_connections(count: int) -> Array[StreamPeerTCP]:
	var conns: Array[StreamPeerTCP] = []
	for i in count:
		var raw := StreamPeerTCP.new()
		raw.connect_to_host('127.0.0.1', port)
		conns.append(raw)
	return conns


## Polls `conns` and, every 250 ms, re-opens each one the server closed, as an attacker
## holding slots does. (One that re-opens as fast as it is refused floods the operating
## system's short queue of not-yet-accepted connections instead; see the README's Notes.)
func _keep_open(conns: Array[StreamPeerTCP], last_reopen: Dictionary) -> void:
	for raw in conns:
		raw.poll()
	var now := Time.get_ticks_msec()
	if now - int(last_reopen.get('at', 0)) < 250:
		return
	last_reopen['at'] = now
	for i in conns.size():
		var status := conns[i].get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED and status != StreamPeerTCP.STATUS_CONNECTING:
			conns[i] = StreamPeerTCP.new()
			conns[i].connect_to_host('127.0.0.1', port)


## One machine holding more silent connections than the server has slots, re-opening the
## ones the server closes, must not lock out a real client connecting from another address
## (here the IPv6 loopback, on a server listening on every interface).
func test_silent_connections_from_one_address_do_not_lock_out_a_client_from_another():
	server.stop()
	assert_eq(server.listen(port, '*'), OK)
	var probe := StreamPeerTCP.new()
	if probe.connect_to_host('::1', port) != OK:
		pending('this machine has no IPv6 loopback to connect from')
		return
	probe.disconnect_from_host()
	var flood := _silent_connections(75)
	var last_reopen := {}
	await _wait_ms(func(): _keep_open(flood, last_reopen); return false, 500)

	# A real client retries when it is refused.
	var opened := await _wait_ms(func():
		_keep_open(flood, last_reopen)
		if client.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			client = WebSocketPeer.new()
			client.connect_to_url('ws://[::1]:%d' % port)
		client.poll()
		return client.get_ready_state() == WebSocketPeer.STATE_OPEN, 10000)

	assert_true(opened, 'the real client connected while the flood went on')
	assert_eq(server.connected_peer_ids().size(), 1)
	assert_lte(server._handshake_started.size(), LFSocketServer.DEFAULT_MAX_PENDING_HANDSHAKES_PER_ADDRESS, 'the flooding address holds only its per-address share')
	for raw in flood:
		raw.disconnect_from_host()


## Each address gets its own share: a connection over the cap from that address is closed
## at once, and the server keeps no record of it.
func test_a_handshake_beyond_the_per_address_cap_is_closed_at_once():
	server.max_pending_handshakes_per_address = 2
	server.handshake_timeout_ms = 0
	var conns := _silent_connections(3)
	assert_true(await _wait_ms(func(): _poll_all(conns); return server._next_peer_id > 2), 'reached before the timeout')
	var refused := await _wait_ms(func():
		_poll_all(conns)
		for raw in conns:
			if raw.get_status() != StreamPeerTCP.STATUS_CONNECTED or raw.get_partial_data(1)[0] != OK:
				return true
		return false, 1000)

	assert_true(refused, 'one of the three connections was closed by the server')
	assert_eq(server._handshake_started.size(), 2, 'two are held, mid-handshake')
	for raw in conns:
		raw.disconnect_from_host()


func _poll_all(conns: Array[StreamPeerTCP]) -> void:
	for raw in conns:
		raw.poll()


## Handshakes are counted apart from open peers: connections stuck in their handshake use
## max_pending_handshakes, not max_peers, so clients can still open up to max_peers.
func test_pending_handshakes_do_not_take_open_peers_slots():
	server.max_peers = 2
	server.max_pending_handshakes = 8
	server.max_pending_handshakes_per_address = 0
	server.handshake_timeout_ms = 0
	var flood := _silent_connections(3)
	assert_true(await _wait_ms(func(): _poll_all(flood); return server._handshake_started.size() == 3), 'reached before the timeout')

	await _connect_client()
	var second := await _open_extra_client()

	assert_true(await _wait_ms(func(): _poll_all(flood); return server.connected_peer_ids().size() == 2), 'both clients opened alongside the stuck handshakes')
	assert_eq(server._handshake_started.size(), 3, 'the stuck handshakes are still held')
	second.close()
	for raw in flood:
		raw.disconnect_from_host()


## The pending cap covers every address together: with it reached, one more connection is
## closed at once.
func test_a_handshake_beyond_the_total_pending_cap_is_closed_at_once():
	server.max_pending_handshakes = 3
	server.max_pending_handshakes_per_address = 0
	server.handshake_timeout_ms = 0
	var flood := _silent_connections(3)
	assert_true(await _wait_ms(func(): _poll_all(flood); return server._handshake_started.size() == 3), 'reached before the timeout')

	client.connect_to_url('ws://127.0.0.1:%d' % port)
	var refused := await _wait_ms(func(): _poll_all(flood); client.poll(); return client.get_ready_state() == WebSocketPeer.STATE_CLOSED)

	assert_true(refused, 'the fourth handshake was refused')
	assert_eq(server._handshake_started.size(), 3)
	for raw in flood:
		raw.disconnect_from_host()


func test_listen_refuses_a_port_outside_zero_to_65535():
	var other := LFSocketServer.new()

	assert_eq(other.listen(-1, '127.0.0.1'), ERR_INVALID_PARAMETER)
	assert_eq(other.listen(65536, '127.0.0.1'), ERR_INVALID_PARAMETER)
	assert_false(other.is_listening())
	assert_eq(other.get_local_port(), 0)


func test_a_port_outside_1_to_65535_is_not_free():
	assert_false(LFSocketServer.is_port_free(-1))
	assert_false(LFSocketServer.is_port_free(0))
	assert_false(LFSocketServer.is_port_free(65536))


func test_a_non_positive_inbound_buffer_size_uses_the_default():
	var other := LFSocketServer.new()
	other.inbound_buffer_size = -5
	other.outbound_buffer_size = 0
	assert_eq(other.listen(0, '127.0.0.1'), OK)
	port = other.get_local_port()
	var received := { 'data': null }
	other.message_received.connect(func(_peer_id, data): received['data'] = data)
	var peer_ids := []
	other.peer_connected.connect(func(peer_id): peer_ids.append(peer_id))

	await _connect_client()
	client.send_text(JSON.stringify({ 'n': 1 }))
	assert_true(await _wait_until(func(): client.poll(); return received['data'] != null), 'a message arrives')
	assert_eq(other.send_to(peer_ids[0], { 'back': 1 }), OK)
	assert_true(await _wait_until(func(): client.poll(); return client.get_available_packet_count() > 0), 'a reply arrives')

	other.stop()


## --- open peers per address ---

const _ORIGIN_OK := 'https://game.example'
const _ORIGIN_EVIL := 'https://evil.example'
## Peers one address is allowed in the per-address tests.
const _ADDRESS_CAP := 2


func _origin_client(origin: String) -> WebSocketPeer:
	var c := WebSocketPeer.new()
	if !origin.is_empty():
		c.handshake_headers = PackedStringArray(['Origin: ' + origin])
	c.connect_to_url('ws://127.0.0.1:%d' % port)
	return c


func _opens(c: WebSocketPeer, ms := 3000) -> bool:
	return await _wait_ms(func(): c.poll(); return c.get_ready_state() == WebSocketPeer.STATE_OPEN, ms)


func _is_refused(c: WebSocketPeer, ms := 3000) -> bool:
	return await _wait_ms(func(): c.poll(); return c.get_ready_state() == WebSocketPeer.STATE_CLOSED, ms)


func test_the_per_address_open_peer_cap_defaults_to_eight_and_negative_means_unlimited():
	var fresh := LFSocketServer.new()
	assert_eq(fresh.max_peers_per_address, 8)
	assert_eq(fresh.max_peers_per_address, LFSocketServer.DEFAULT_MAX_PEERS_PER_ADDRESS)
	fresh.max_peers_per_address = -3
	assert_eq(fresh.max_peers_per_address, 0, 'a negative cap is stored as 0, which means unlimited')


func test_one_address_cannot_take_every_open_peer_slot():
	server.max_peers_per_address = _ADDRESS_CAP
	var opened: Array[WebSocketPeer] = []
	for i in _ADDRESS_CAP:
		var c := _origin_client('')
		assert_true(await _opens(c), 'client %d opened' % i)
		opened.append(c)

	var over := _origin_client('')
	assert_true(await _is_refused(over), 'the client over the cap is closed')

	assert_eq(server.connected_peer_ids().size(), _ADDRESS_CAP)
	assert_eq(server._open_by_address.get('127.0.0.1'), _ADDRESS_CAP)
	for c in opened:
		c.close()


func test_a_closed_peer_frees_its_address_slot():
	server.max_peers_per_address = 1
	var first := _origin_client('')
	assert_true(await _opens(first))
	first.close()
	assert_true(await _wait_ms(func(): first.poll(); return server.connected_peer_ids().is_empty()), 'the server noticed the close')
	assert_false(server._open_by_address.has('127.0.0.1'), 'no leftover count')

	var again := _origin_client('')
	assert_true(await _opens(again), 'the freed slot can be used again')
	again.close()


func test_a_per_address_cap_of_zero_is_unlimited():
	server.max_peers_per_address = 0
	var opened: Array[WebSocketPeer] = []
	for i in LFSocketServer.DEFAULT_MAX_PEERS_PER_ADDRESS + 2:
		var c := _origin_client('')
		assert_true(await _opens(c), 'client %d opened' % i)
		opened.append(c)
	assert_eq(server.connected_peer_ids().size(), opened.size())
	for c in opened:
		c.close()


## --- origin allow-list ---

func _origin_server(origins: Array, allow_missing := true) -> void:
	server.stop()
	server = LFSocketServer.new()
	server.allowed_origins = PackedStringArray(origins)
	server.allow_missing_origin = allow_missing
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	port = server.get_local_port()


func test_origin_checking_is_off_by_default():
	assert_true(server.allowed_origins.is_empty())
	var c := _origin_client(_ORIGIN_EVIL)
	assert_true(await _opens(c), 'with no allow-list any origin connects')
	c.close()


func test_a_listed_origin_connects_and_exchanges_messages_both_ways():
	_origin_server([_ORIGIN_OK])
	var got := { 'data': null, 'id': -1 }
	server.message_received.connect(func(peer_id, data): got['id'] = peer_id; got['data'] = data)
	var c := _origin_client(_ORIGIN_OK)
	assert_true(await _opens(c), 'a listed origin gets through')

	c.send_text(JSON.stringify({ 'n': 7 }))
	assert_true(await _wait_ms(func(): c.poll(); return got['data'] != null), 'a message reaches the server')
	assert_eq(got['data']['n'], 7.0)
	server.send_to(got['id'], { 'back': 1 })
	assert_true(await _wait_ms(func(): c.poll(); return c.get_available_packet_count() > 0), 'and the answer comes back')
	assert_eq(JSON.parse_string(c.get_packet().get_string_from_utf8())['back'], 1.0)
	assert_eq(server.peer_address(got['id']), '127.0.0.1', 'the peer keeps its real address')
	c.close()


func test_a_large_message_survives_the_origin_relay():
	_origin_server([_ORIGIN_OK])
	var got := { 'len': 0 }
	server.inbound_buffer_size = 1 << 20
	server.message_received.connect(func(_id, data): got['len'] = str(data['x']).length())
	var c := _origin_client(_ORIGIN_OK)
	c.outbound_buffer_size = 1 << 20
	assert_true(await _opens(c))

	c.send_text(JSON.stringify({ 'x': 'z'.repeat(300000) }))

	assert_true(await _wait_ms(func(): c.poll(); return got['len'] == 300000, 5000), 'all 300000 characters arrive')
	c.close()


func test_an_unlisted_origin_is_refused_with_403_and_never_becomes_a_peer():
	_origin_server([_ORIGIN_OK])
	var seen := []
	server.peer_connected.connect(func(id): seen.append(id))
	var c := _origin_client(_ORIGIN_EVIL)

	assert_true(await _is_refused(c), 'the handshake fails')
	assert_engine_error_count(2, 'the engine client reports the 403 answer, as expected')
	assert_true(seen.is_empty())
	assert_true(server.connected_peer_ids().is_empty())
	assert_eq(server._peers.size(), 0)


func test_the_refusal_is_an_http_403():
	_origin_server([_ORIGIN_OK])
	var raw := StreamPeerTCP.new()
	raw.connect_to_host('127.0.0.1', port)
	var request := 'GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nOrigin: %s\r\n\r\n' % _ORIGIN_EVIL
	var reply := { 'text': '' }
	var sent := { 'done': false }
	assert_true(await _wait_ms(func():
		raw.poll()
		if raw.get_status() == StreamPeerTCP.STATUS_CONNECTED and !sent['done']:
			raw.put_data(request.to_utf8_buffer())
			sent['done'] = true
		if sent['done'] and raw.get_available_bytes() > 0:
			reply['text'] += raw.get_utf8_string(raw.get_available_bytes())
		return reply['text'].contains('\r\n\r\n')), 'an answer arrived')

	assert_true(reply['text'].begins_with('HTTP/1.1 403'))
	raw.disconnect_from_host()


func test_origin_matching_ignores_case_and_a_trailing_slash():
	_origin_server(['HTTPS://Game.Example/'])
	var c := _origin_client('https://GAME.example')
	assert_true(await _opens(c))
	c.close()


func test_a_missing_origin_follows_allow_missing_origin():
	_origin_server([_ORIGIN_OK], true)
	var native := _origin_client('')
	assert_true(await _opens(native), 'a native client without Origin passes by default')
	native.close()

	_origin_server([_ORIGIN_OK], false)
	var strict := _origin_client('')
	assert_true(await _is_refused(strict), 'and is refused when missing origins are not allowed')
	assert_engine_error_count(2, 'the engine client reports the 403 answer, as expected')


func test_origin_allowed_rules():
	var allowed := PackedStringArray([_ORIGIN_OK])
	var check := LFSocketServer._OriginRelay.origin_allowed
	assert_true(check.call('GET / HTTP/1.1\r\norigin: https://game.example', allowed, false))
	assert_false(check.call('GET / HTTP/1.1\r\nOrigin: https://game.example.evil.com', allowed, true), 'a prefix is not a match')
	assert_false(check.call('GET / HTTP/1.1\r\nOrigin: null', allowed, true), 'the opaque origin is not listed')
	assert_false(check.call('GET / HTTP/1.1\r\nOrigin: https://game.example\r\nOrigin: https://game.example', allowed, true), 'two Origin headers are refused')
	assert_true(check.call('GET / HTTP/1.1\r\nHost: x', allowed, true))
	assert_false(check.call('GET / HTTP/1.1\r\nHost: x', allowed, false))


func test_a_request_head_that_never_ends_is_refused():
	_origin_server([_ORIGIN_OK])
	var raw := StreamPeerTCP.new()
	raw.connect_to_host('127.0.0.1', port)
	var flooded := { 'done': false }
	assert_true(await _wait_ms(func():
		raw.poll()
		if raw.get_status() == StreamPeerTCP.STATUS_CONNECTED and !flooded['done']:
			raw.put_data(('X-Pad: ' + 'a'.repeat(9000)).to_utf8_buffer())
			flooded['done'] = true
		if flooded['done']:
			raw.poll()
			return raw.get_status() != StreamPeerTCP.STATUS_CONNECTED or raw.get_available_bytes() > 0
		return false), 'the server answered or closed')
	assert_eq(server._relays.size(), 0 if raw.get_status() != StreamPeerTCP.STATUS_CONNECTED else server._relays.size())
	raw.disconnect_from_host()


func test_a_silent_connection_is_dropped_by_the_handshake_timeout_with_the_check_on():
	server.stop()
	server = LFSocketServer.new()
	server.allowed_origins = PackedStringArray([_ORIGIN_OK])
	server.handshake_timeout_ms = 300
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	port = server.get_local_port()
	var raw := StreamPeerTCP.new()
	raw.connect_to_host('127.0.0.1', port)
	assert_true(await _wait_ms(func(): raw.poll(); return !server._relays.is_empty()), 'the server holds it')

	assert_true(await _wait_ms(func(): raw.poll(); return server._relays.is_empty(), 3000), 'and drops it after the timeout')
	raw.disconnect_from_host()


func test_closing_works_in_both_directions_through_the_relay():
	_origin_server([_ORIGIN_OK])
	var gone := []
	server.peer_disconnected.connect(func(id): gone.append(id))
	var c := _origin_client(_ORIGIN_OK)
	assert_true(await _opens(c))
	assert_true(await _wait_ms(func(): return server.connected_peer_ids().size() == 1))
	var id: int = server.connected_peer_ids()[0]

	server.disconnect_peer(id)
	assert_true(await _is_refused(c), 'the client sees the server close')
	assert_eq(c.get_close_code(), LFSocket.DISCONNECTED_BY_SERVER_CODE)
	assert_true(await _wait_ms(func(): return gone.has(id)), 'peer_disconnected fires')

	var c2 := _origin_client(_ORIGIN_OK)
	assert_true(await _opens(c2))
	c2.close()
	assert_true(await _wait_ms(func(): c2.poll(); return gone.size() == 2), 'a client close reaches the server')
	assert_true(await _wait_ms(func(): return server._relays.is_empty()), 'and the relay is released')


func test_stop_releases_the_relays():
	_origin_server([_ORIGIN_OK])
	var c := _origin_client(_ORIGIN_OK)
	assert_true(await _opens(c))
	server.stop()
	assert_true(server._relays.is_empty())
	assert_true(await _is_refused(c), 'the client is disconnected')


func test_the_origin_check_also_works_over_wss():
	server.stop()
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var cert := crypto.generate_self_signed_certificate(key, 'CN=localhost,O=LF test,C=US')
	server = LFSocketServer.new()
	server.allowed_origins = PackedStringArray([_ORIGIN_OK])
	assert_eq(server.listen(0, '127.0.0.1', TLSOptions.server(key, cert)), OK)
	port = server.get_local_port()
	var good := WebSocketPeer.new()
	good.handshake_headers = PackedStringArray(['Origin: ' + _ORIGIN_OK])
	good.connect_to_url('wss://127.0.0.1:%d' % port, TLSOptions.client(cert, 'localhost'))
	var bad := WebSocketPeer.new()
	bad.handshake_headers = PackedStringArray(['Origin: ' + _ORIGIN_EVIL])
	bad.connect_to_url('wss://127.0.0.1:%d' % port, TLSOptions.client(cert, 'localhost'))

	assert_true(await _wait_ms(func(): good.poll(); bad.poll(); return good.get_ready_state() == WebSocketPeer.STATE_OPEN and bad.get_ready_state() == WebSocketPeer.STATE_CLOSED, 8000), 'listed origin opens, unlisted is refused')

	assert_eq(server.connected_peer_ids().size(), 1)
	assert_engine_error_count(2, 'the engine client reports the 403 answer, as expected')
	good.close()


func _broadcast_then_stop_arrives(c: WebSocketPeer) -> bool:
	assert_true(await _opens(c))
	assert_true(await _wait_ms(func(): return server.connected_peer_ids().size() == 1))
	server.broadcast({'type': 'bye', 'data': 1})
	server.stop()
	var got := []
	assert_true(await _wait_ms(func():
		c.poll()
		while c.get_available_packet_count() > 0:
			got.append(c.get_packet().get_string_from_utf8())
		return !got.is_empty()), 'the goodbye arrives')
	return !got.is_empty() and 'bye' in got[0]


func test_stop_flushes_a_broadcast_without_the_origin_check():
	_origin_server([])
	assert_true(await _broadcast_then_stop_arrives(_origin_client('')))


func test_stop_flushes_a_broadcast_through_the_origin_relay():
	_origin_server([_ORIGIN_OK])
	var c := _origin_client(_ORIGIN_OK)
	assert_true(await _broadcast_then_stop_arrives(c))
	assert_true(await _is_refused(c), 'and the connection closes afterwards')
	assert_true(server._relays.is_empty())
