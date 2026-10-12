extends GutTest

## Connection behaviour runs against real sockets (LFSocketServer, or a bare TCPServer
## with WebSocketPeer where the test needs a server that misbehaves). Queueing and
## message routing are driven through the internal handlers with `_connected` set by
## hand, so no socket I/O starts for them.

var sock: LFSocket


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
	sock = LFSocket.new()
	sock._options = LFSocketOptions.new()


func after_each():
	# Retires any lingering poll loop and pending reconnect timer for good.
	sock._poll_generation += 1
	sock._reconnect_generation += 1


## The poll loop stops on disconnect_from_server() itself, whatever state the socket's
## close handshake is in.
func test_disconnect_from_server_sets_the_intentionally_disconnected_flag():
	sock._socket = WebSocketPeer.new()
	sock.disconnect_from_server()
	assert_true(sock._intentionally_disconnected, "the poll loop must stop on this alone, even if the socket itself never reaches STATE_CLOSED")


func test_attempt_connection_clears_the_intentionally_disconnected_flag():
	sock._intentionally_disconnected = true
	sock._socket = WebSocketPeer.new()
	sock._url = "ws://127.0.0.1:1"

	sock._attempt_connection()

	assert_false(sock._intentionally_disconnected, "a fresh attempt (an initial connect, or a reconnect after this same flag was set by an earlier disconnect) must always get a real poll loop")
	sock._poll_generation += 1 # retires the poll loop _attempt_connection() just started


func test_a_connection_attempt_sizes_both_buffers_from_the_options():
	assert_gt(LFSocketOptions.new().buffer_size, 65535, "the default outgrows Godot's own 64 KiB")
	sock._options.buffer_size = 1 << 20
	var peer := WebSocketPeer.new()
	sock._socket = peer
	sock._url = "ws://127.0.0.1:1"

	sock._attempt_connection()

	assert_eq(peer.inbound_buffer_size, 1 << 20)
	assert_eq(peer.outbound_buffer_size, 1 << 20)
	sock._poll_generation += 1


func test_sending_while_disconnected_queues_the_message():
	sock.send_message({"a": 1})
	assert_eq(sock.get_queue_size(), 1)


func test_queue_evicts_the_oldest_message_once_the_limit_is_reached():
	sock._options.max_queue_size = 2
	sock.send_message({"id": 1})
	sock.send_message({"id": 2})
	sock.send_message({"id": 3})

	assert_eq(sock.get_queue_size(), 2)
	assert_eq(sock._message_queue[0].id, 2)
	assert_eq(sock._message_queue[1].id, 3)


func test_queueing_can_be_disabled_per_send():
	sock.send_message({"a": 1}, false)
	assert_eq(sock.get_queue_size(), 0)


func test_clear_queue_empties_it():
	sock.send_message({"a": 1})
	sock.clear_queue()
	assert_eq(sock.get_queue_size(), 0)


func test_flushing_the_queue_drains_it_once_reconnected():
	sock.send_message({"a": 1})
	sock.send_message({"a": 2})
	assert_eq(sock.get_queue_size(), 2)

	sock._connected = true # simulates the connection reopening
	sock._flush_queue()
	# _connected=true is a fake-out — the underlying WebSocketPeer was never
	# really opened, so each flushed send (one per queued message) fails at
	# the engine level. That's expected here; only the queue-draining
	# contract is under test. Each assert only consumes one occurrence.
	assert_engine_error("ready_state")
	assert_engine_error("ready_state")
	assert_push_error_count(2)

	assert_eq(sock.get_queue_size(), 0)


func test_on_event_listener_receives_the_matching_events_data():
	var received := []
	sock.on_event("greet", func(data): received.append(data))
	sock._handle_message(JSON.stringify({"event": "greet", "data": "hello"}))
	assert_eq(received, ["hello"])


func test_on_event_listener_does_not_receive_other_events():
	var received := []
	sock.on_event("greet", func(data): received.append(data))
	sock._handle_message(JSON.stringify({"event": "other", "data": "hello"}))
	assert_eq(received, [])


func test_off_event_stops_a_listener_from_receiving_further_events():
	var received := []
	var handler := func(data): received.append(data)
	sock.on_event("greet", handler)
	sock.off_event("greet", handler)
	sock._handle_message(JSON.stringify({"event": "greet", "data": "hello"}))
	assert_eq(received, [])


func test_wildcard_listener_receives_every_event_with_its_name():
	var received := []
	sock.on_event("*", func(event, data): received.append([event, data]))
	sock._handle_message(JSON.stringify({"event": "greet", "data": "hi"}))
	assert_eq(received, [["greet", "hi"]])


func test_binary_message_dispatches_to_the_listener_for_its_event():
	var received := []
	var json_received := []
	sock.on_binary_event("bin-event", func(data): received.append(data))
	sock.on_event("bin-event", func(data): json_received.append(data))

	var event_bytes := "bin-event".to_utf8_buffer()
	var header := PackedByteArray()
	header.append(event_bytes.size() & 0xFF)
	header.append((event_bytes.size() >> 8) & 0xFF)
	header.append((event_bytes.size() >> 16) & 0xFF)
	header.append((event_bytes.size() >> 24) & 0xFF)
	var payload := PackedByteArray([1, 2, 3])
	var packet := PackedByteArray()
	packet.append_array(header)
	packet.append_array(event_bytes)
	packet.append_array(payload)

	sock._handle_binary_message(packet)

	assert_eq(received.size(), 1)
	assert_eq(received[0], payload)
	assert_eq(json_received, [], "binary frames never reach JSON event listeners")


func test_off_binary_event_removes_a_binary_listener():
	var received := []
	var handler := func(data): received.append(data)
	sock.on_binary_event("bin", handler)
	sock.off_binary_event("bin", handler)
	var frame := PackedByteArray([3, 0, 0, 0])
	frame.append_array("bin".to_utf8_buffer())
	sock._handle_binary_message(frame)
	assert_eq(received, [])


func test_request_message_times_out_and_clears_its_pending_entry_if_unanswered():
	sock._connected = true

	var result = await sock.request_message({"x": 1}, 30)
	# _connected=true is a fake-out (see test_flushing_the_queue... above) —
	# the request's own initial send fails at the engine level.
	assert_engine_error("ready_state")
	assert_push_error_count(1)

	assert_null(result)
	assert_eq(sock.get_status().pending_requests, 0)


func test_request_message_resolves_when_a_matching_response_arrives():
	sock._connected = true

	var results = await LFAwait.all([
		func(): return await sock.request_message({"x": 1}, 3000),
		func():
			# Wait until request_message has registered its pending entry,
			# then discover the request id it was assigned and answer it.
			var deadline = Time.get_ticks_msec() + 1000
			while sock._pending_requests.is_empty() and Time.get_ticks_msec() < deadline:
				await Engine.get_main_loop().process_frame
			var request_id = sock._pending_requests.keys()[0]
			sock._handle_message(JSON.stringify({"type": "response", "id": request_id, "data": "the-answer"}))
			return null,
	])
	# _connected=true is a fake-out — the request's own initial send fails
	# at the engine level (the injected response above is what's under test).
	assert_engine_error("ready_state")
	assert_push_error_count(1)

	assert_eq(results[0], "the-answer")


func test_reconnect_stops_once_the_attempt_limit_is_reached():
	sock._options.auto_reconnect = true
	sock._options.max_reconnect_attempts = 2
	sock._options.reconnect_interval_ms = 60000 # large enough to never actually fire in this test
	# _schedule_reconnect() reads _current_reconnect_interval (only normally
	# seeded from _options.reconnect_interval_ms by connect_to_server(), which
	# this test bypasses) — without setting it too, the background reconnect
	# timer below would fire with its 0-default delay almost immediately.
	sock._current_reconnect_interval = 60000
	sock._url = "ws://127.0.0.1:1/unreachable"

	sock._schedule_reconnect()
	assert_eq(sock._reconnect_attempts, 1)
	sock._schedule_reconnect()
	assert_eq(sock._reconnect_attempts, 2)

	watch_signals(sock)
	sock._schedule_reconnect() # exceeds the limit
	assert_push_error("Max reconnection attempts reached")
	assert_eq(sock._reconnect_attempts, 2, "must not increment past the configured limit")
	assert_signal_emitted(sock, "error_occurred")


## A client often connects to a server it just launched, before that server is
## listening. A refused connection is already STATE_CLOSED on the very first poll;
## that first failed attempt must still schedule a reconnect, or the loop polls a
## dead socket forever.
func test_a_refused_first_attempt_schedules_a_reconnect():
	if _refusal_unreported():
		pending(_REFUSAL_REASON)
		return
	var options := LFSocketOptions.new()
	options.auto_reconnect = true
	options.reconnect_interval_ms = 60000 # never actually fires within this test
	var port := LFSocketServer.free_port()

	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	await _wait_ms(func(): return sock._reconnect_attempts > 0)

	assert_eq(sock._reconnect_attempts, 1)
	sock.disconnect_from_server()
	_tolerate_macos_refusal_noise()


## A bare WebSocket server that accepts connections but never answers pings
## (LFSocketServer does answer them): the client declares the connection dead after
## heartbeat_timeout_ms and reconnects on its own.
func test_a_heartbeat_timeout_drops_the_connection_and_reconnects():
	var tcp := TCPServer.new()
	assert_eq(tcp.listen(0, '127.0.0.1'), OK)
	var port := tcp.get_local_port()
	var peers: Array[WebSocketPeer] = []

	var options := LFSocketOptions.new()
	options.heartbeat_interval_ms = 50
	options.heartbeat_timeout_ms = 50
	options.reconnect_interval_ms = 30
	watch_signals(sock)
	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)

	for i in 600:
		while tcp.is_connection_available():
			var peer := WebSocketPeer.new()
			peer.accept_stream(tcp.take_connection())
			peers.append(peer)
		for peer in peers:
			peer.poll() # completes handshakes; incoming pings are read and ignored
			while peer.get_available_packet_count() > 0:
				peer.get_packet()
		if peers.size() >= 2:
			break
		await get_tree().process_frame

	assert_gte(peers.size(), 2, "the client must reconnect after the unanswered ping")
	assert_signal_emitted(sock, "disconnected")
	sock.disconnect_from_server()
	tcp.stop()


func test_disconnecting_an_open_connection_emits_disconnected():
	sock._socket = WebSocketPeer.new()
	sock._connected = true
	watch_signals(sock)

	sock.disconnect_from_server()

	assert_signal_emitted(sock, "disconnected")


func test_disconnect_without_disabling_reconnect_reconnects():
	var tcp := TCPServer.new()
	assert_eq(tcp.listen(0, '127.0.0.1'), OK)
	var port := tcp.get_local_port()
	var peers: Array[WebSocketPeer] = []

	var options := LFSocketOptions.new()
	options.heartbeat_interval_ms = 0
	options.reconnect_interval_ms = 30
	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)

	var disconnected_once := false
	for i in 600:
		while tcp.is_connection_available():
			var peer := WebSocketPeer.new()
			peer.accept_stream(tcp.take_connection())
			peers.append(peer)
		for peer in peers:
			peer.poll()
		if sock.is_connected_to_server() and !disconnected_once:
			disconnected_once = true
			sock.disconnect_from_server(false)
		if peers.size() >= 2 and sock.is_connected_to_server():
			break
		await get_tree().process_frame

	assert_true(disconnected_once, "the first connection never opened")
	assert_gte(peers.size(), 2, "disconnect_from_server(false) must leave auto-reconnect armed")
	assert_true(sock.is_connected_to_server(), "the reconnect must reach OPEN")
	sock.disconnect_from_server()
	for i in 5: # let the server side see the close before it is torn down
		for peer in peers:
			peer.poll()
		await get_tree().process_frame
	tcp.stop()


func test_connecting_again_after_a_plain_disconnect_rearms_auto_reconnect():
	sock.disconnect_from_server()
	assert_false(sock._should_reconnect, "a plain disconnect disables reconnecting")
	sock.connect_to_server('ws://127.0.0.1:1', LFSocketOptions.new())
	assert_true(sock._should_reconnect, "a new connect_to_server must re-arm auto-reconnect")
	sock.disconnect_from_server()
	_tolerate_macos_refusal_noise()


func test_disconnect_with_the_default_does_not_schedule_a_reconnect():
	sock._socket = WebSocketPeer.new()
	sock._connected = true
	sock._current_reconnect_interval = 60000

	sock.disconnect_from_server()

	assert_eq(sock._reconnect_attempts, 0)


func test_force_reconnect_dials_once_without_scheduling_a_second_reconnect():
	var tcp := TCPServer.new() # accepts the dial so it is not refused (which would rightly schedule a retry)
	assert_eq(tcp.listen(0, '127.0.0.1'), OK)
	var port := tcp.get_local_port()
	sock._socket = WebSocketPeer.new()
	sock._connected = true
	sock._url = 'ws://127.0.0.1:%d' % port
	sock._current_reconnect_interval = 60000

	sock.force_reconnect()

	assert_eq(sock._reconnect_attempts, 0, "force_reconnect redials immediately; it must not also queue a delayed reconnect")
	sock.disconnect_from_server()
	tcp.stop()


## A forced reconnect while the previous dial is still opening replaces that dial: when
## the new dial fails at once, the old dial's poll loop must not also report the new,
## closed peer as a second failure and schedule a second reconnect.
func test_force_reconnect_during_a_dial_that_then_fails_reports_one_error_and_one_reconnect():
	var tcp := TCPServer.new() # accepts the first dial but never answers, so it stays opening
	assert_eq(tcp.listen(0, '127.0.0.1'), OK)
	var port := tcp.get_local_port()
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 60000 # never actually fires within this test
	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	for i in 5:
		await get_tree().process_frame
	assert_eq(sock._socket.get_ready_state(), WebSocketPeer.STATE_CONNECTING, "the first dial is still in progress")
	var errors := []
	var attempts := []
	sock.error_occurred.connect(func(message): errors.append(message))
	sock.reconnect_scheduled.connect(func(attempt): attempts.append(attempt))

	sock._url = 'http://127.0.0.1:1' # not a WebSocket scheme: the redial below fails at once
	sock.force_reconnect()
	for i in 10:
		await get_tree().process_frame

	assert_engine_error('scheme')
	assert_push_error('Failed to initiate connection')
	assert_eq(errors.size(), 1, "one failed dial is one error")
	assert_eq(attempts, [1], "one failed dial schedules one reconnect")
	sock.disconnect_from_server()
	tcp.stop()


func test_force_reconnect_dials_on_a_fresh_peer_not_the_closing_one():
	var closing := WebSocketPeer.new()
	sock._socket = closing
	sock._connected = true
	sock._url = "ws://127.0.0.1:1"

	sock.force_reconnect()

	assert_ne(sock._socket, closing, "a peer that was just closed cannot be redialled")
	sock.disconnect_from_server()


func test_a_heartbeat_answered_by_lf_socket_server_keeps_one_connection_alive():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var connections := [0]
	server.peer_connected.connect(func(_id): connections[0] += 1)

	var options := LFSocketOptions.new()
	options.heartbeat_interval_ms = 30
	options.heartbeat_timeout_ms = 400 # generous: a slow frame must not look like a lost pong
	options.reconnect_interval_ms = 30
	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)

	var until := Time.get_ticks_msec() + 1200 # many heartbeat rounds, longer than interval + timeout
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

	assert_eq(connections[0], 1, "answered pings must never trigger a reconnect")
	assert_true(sock.is_connected_to_server())
	sock.disconnect_from_server()
	server.stop()


func test_sending_before_any_connect_queues_with_default_options():
	var fresh := LFSocket.new()

	fresh.send_message({"early": true})

	assert_eq(fresh.get_queue_size(), 1, "a message sent before connect_to_server() is queued, not a crash")


func test_a_non_object_json_frame_is_ignored():
	var calls := []
	sock.on_event("*", func(_name, data): calls.append(data))

	sock._handle_message("[1, 2, 3]")

	assert_eq(calls, [])


## A bare WebSocket server (TCPServer + accept_stream) so binary frames reach the test —
## LFSocketServer drops them. Accepts and polls every peer once per call.
func _pump_raw_server(tcp: TCPServer, peers: Array) -> void:
	while tcp.is_connection_available():
		var peer := WebSocketPeer.new()
		peer.accept_stream(tcp.take_connection())
		peers.append(peer)
	for peer in peers:
		peer.poll()


func _binary_frame(event: String, payload: PackedByteArray) -> PackedByteArray:
	var event_bytes := event.to_utf8_buffer()
	var frame := PackedByteArray([event_bytes.size() & 0xFF, (event_bytes.size() >> 8) & 0xFF, (event_bytes.size() >> 16) & 0xFF, (event_bytes.size() >> 24) & 0xFF])
	frame.append_array(event_bytes)
	frame.append_array(payload)
	return frame


func test_emit_binary_sends_a_length_prefixed_frame_and_a_binary_reply_reaches_its_listener():
	var tcp := TCPServer.new()
	assert_eq(tcp.listen(0, '127.0.0.1'), OK)
	var port := tcp.get_local_port()
	var peers := []
	var options := LFSocketOptions.new()
	options.heartbeat_interval_ms = 0 # keep pings out of the server's packet stream
	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	for i in 300:
		_pump_raw_server(tcp, peers)
		if sock.is_connected_to_server():
			break
		await get_tree().process_frame
	assert_true(sock.is_connected_to_server(), "the client must connect to the raw server")

	sock.emit_binary("upload", PackedByteArray([7, 8, 9]))
	var server_got := []
	for i in 300:
		_pump_raw_server(tcp, peers)
		if !peers.is_empty() and peers[0].get_available_packet_count() > 0:
			var packet: PackedByteArray = peers[0].get_packet()
			server_got.append([packet, peers[0].was_string_packet()])
			break
		await get_tree().process_frame

	assert_eq(server_got.size(), 1, "the server must receive the binary frame")
	if server_got.size() == 1:
		assert_eq(server_got[0][0], _binary_frame("upload", PackedByteArray([7, 8, 9])), "[u32 LE length][event utf8][data]")
		assert_false(server_got[0][1], "emit_binary sends a binary frame, not text")

	var received := []
	sock.on_binary_event("download", func(data): received.append(data))
	peers[0].send(_binary_frame("download", PackedByteArray([4, 5])))
	for i in 300:
		_pump_raw_server(tcp, peers)
		if !received.is_empty():
			break
		await get_tree().process_frame

	assert_eq(received, [PackedByteArray([4, 5])], "a binary frame from the server reaches the listener for its decoded event")
	sock.disconnect_from_server()
	tcp.stop()


func test_emit_binary_while_offline_is_dropped_not_queued():
	sock.emit_binary("upload", PackedByteArray([1]))
	assert_eq(sock.get_queue_size(), 0, "binary data is never queued")


func test_connected_and_disconnected_fire_on_connect_and_disconnect():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var events := []
	sock.connected.connect(func(): events.append("open"))
	sock.disconnected.connect(func(): events.append("close"))

	sock.connect_to_server('ws://127.0.0.1:%d' % port, LFSocketOptions.new())
	assert_true(await _wait_ms(func(): return sock.is_connected_to_server()), 'reached before the timeout')
	assert_eq(events, ["open"], "connected fires once when the connection opens")

	sock.disconnect_from_server()
	sock.disconnect_from_server()
	assert_eq(events, ["open", "close"], "disconnected fires once, when the open connection is closed")
	server.stop()


func test_reconnecting_carries_the_attempt_number_after_a_refused_connection():
	if _refusal_unreported():
		pending(_REFUSAL_REASON)
		return
	var attempts := []
	sock.reconnect_scheduled.connect(func(attempt): attempts.append(attempt))
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 60000 # never actually fires within this test

	sock.connect_to_server('ws://127.0.0.1:%d' % LFSocketServer.free_port(), options)
	assert_true(await _wait_ms(func(): return !attempts.is_empty()), 'reached before the timeout')

	assert_eq(attempts, [1])
	sock.disconnect_from_server()
	_tolerate_macos_refusal_noise()


func test_disconnecting_a_socket_that_never_opened_emits_nothing():
	watch_signals(sock)
	sock.disconnect_from_server()
	sock.disconnect_from_server()
	assert_signal_not_emitted(sock, "disconnected")


func test_reconnect_delays_are_jittered_by_up_to_a_fifth():
	var seen := {}
	for i in 200:
		var delay := LFSocket._jittered_ms(1000)
		assert_between(delay, 800, 1200)
		seen[delay] = true
	assert_gt(seen.size(), 10, "delays spread out rather than repeat")


func test_the_backoff_grows_by_the_decay_up_to_the_cap():
	sock._options.reconnect_decay = 2.0
	sock._options.max_reconnect_interval_ms = 300
	sock._options.max_reconnect_attempts = 0
	sock._current_reconnect_interval = 100
	sock._url = "ws://127.0.0.1:1"
	var intervals := []
	for i in 4:
		sock._schedule_reconnect()
		intervals.append(sock._current_reconnect_interval)
	sock.disconnect_from_server() # retires every pending timer
	assert_eq(intervals, [200, 300, 300, 300])


func test_non_string_event_type_and_id_fields_never_abort_the_handler():
	var received := []
	sock.on_event("5", func(data): received.append(data))
	sock._handle_message('{"event": 5, "data": "x"}')
	sock._handle_message('{"type": 7, "data": "y"}')
	sock._handle_message('{"type": "response", "id": 3, "data": "z"}')
	sock._handle_message('{"event": ["a"], "type": {"b": 1}}')
	assert_eq(received, [], "a non-string event name never matches a listener")
	assert_engine_error_count(0, "untrusted frame fields must not raise script errors")


func test_a_stale_reconnect_timer_never_replaces_a_live_socket():
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 60000
	sock._options.auto_reconnect = true
	sock._current_reconnect_interval = 40
	sock._url = "ws://127.0.0.1:1"
	sock._schedule_reconnect() # the stale timer

	var tcp := TCPServer.new() # accepts the dial so it is not refused
	assert_eq(tcp.listen(0, '127.0.0.1'), OK)
	var port := tcp.get_local_port()
	sock.disconnect_from_server(false)
	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	var live := sock._socket

	var until := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

	assert_same(sock._socket, live, "the stale timer must not swap the socket")
	sock.disconnect_from_server()
	tcp.stop()


func test_pending_requests_resolve_null_when_the_connection_closes():
	sock._socket = WebSocketPeer.new()
	sock._connected = true
	var started := Engine.get_process_frames()

	var results = await LFAwait.all([
		func(): return await sock.request_message({"x": 1}, 0),
		func():
			await get_tree().process_frame
			sock.disconnect_from_server()
			return null,
	])
	assert_engine_error("ready_state") # the fake-connected send fails at the engine level
	assert_push_error_count(1)

	assert_null(results[0])
	# Counted in frames, not milliseconds, so a slow machine can't fail it: the close
	# comes one frame in, and the request (no time limit) ends within the next poll.
	assert_lte(Engine.get_process_frames() - started, 3, "a closed connection fails the request at once")
	assert_eq(sock.get_status().pending_requests, 0)


func test_a_request_while_offline_returns_null_at_once():
	var started := Engine.get_process_frames()
	var result = await sock.request_message({"x": 1}, 2000)
	assert_null(result)
	assert_eq(Engine.get_process_frames(), started, "offline requests are not queued and do not wait a single frame")
	assert_eq(sock.get_status().pending_requests, 0)


## Waits until `predicate` holds or `ms` milliseconds pass; true when it held.
func _wait_ms(predicate: Callable, ms: int = 3000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()


func test_a_refused_connection_with_reconnecting_off_emits_error():
	if _refusal_unreported():
		pending(_REFUSAL_REASON)
		return
	var options := LFSocketOptions.new()
	options.auto_reconnect = false
	var errors := []
	sock.error_occurred.connect(func(message): errors.append(message))

	sock.connect_to_server('ws://127.0.0.1:%d' % LFSocketServer.free_port(), options)
	assert_true(await _wait_ms(func(): return !errors.is_empty()), 'reached before the timeout')

	assert_eq(errors.size(), 1, 'an attempt that never opens is reported')
	sock.disconnect_from_server()
	_tolerate_macos_refusal_noise()


func test_connecting_again_after_the_attempt_limit_starts_a_fresh_budget():
	if _refusal_unreported():
		pending(_REFUSAL_REASON)
		return
	var options := LFSocketOptions.new()
	options.max_reconnect_attempts = 1
	options.reconnect_interval_ms = 20
	var url := 'ws://127.0.0.1:%d' % LFSocketServer.free_port()
	var attempts := []
	var errors := []
	sock.reconnect_scheduled.connect(func(attempt): attempts.append(attempt))
	sock.error_occurred.connect(func(message): errors.append(message))
	sock.connect_to_server(url, options)
	assert_true(await _wait_ms(func(): return errors.has('Max reconnection attempts reached')), 'reached before the timeout')
	attempts.clear()

	sock.connect_to_server(url, options)
	assert_true(await _wait_ms(func(): return !attempts.is_empty()), 'reached before the timeout')

	assert_eq(attempts, [1], 'a new connect may reconnect again')
	sock.disconnect_from_server()
	assert_push_error('Max reconnection attempts reached')
	_tolerate_macos_refusal_noise()


func test_a_listener_removing_itself_does_not_make_the_next_one_miss_the_event():
	var calls := []
	var once := [Callable()]
	once[0] = func(_data):
		calls.append('once')
		sock.off_event('e', once[0])
	sock.on_event('e', once[0])
	sock.on_event('e', func(_data): calls.append('second'))
	var wild_once := [Callable()]
	wild_once[0] = func(_name, _data):
		calls.append('wild-once')
		sock.off_event('*', wild_once[0])
	sock.on_event('*', wild_once[0])
	sock.on_event('*', func(_name, _data): calls.append('wild-second'))

	sock._handle_message(JSON.stringify({ 'event': 'e' }))
	sock._handle_message(JSON.stringify({ 'event': 'e' }))

	assert_eq(calls, ['wild-once', 'wild-second', 'once', 'second', 'wild-second', 'second'])


## Builds a socket that keeps redialling a closed port and returns only a weak reference.
func _orphan_redialling_socket(port: int) -> WeakRef:
	var orphan := LFSocket.new()
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 30
	orphan.connect_to_server('ws://127.0.0.1:%d' % port, options)
	return weakref(orphan)


func test_a_socket_dropped_by_its_owner_stops_redialling():
	var tcp := TCPServer.new()
	var port := LFSocketServer.free_port()
	var ref := _orphan_redialling_socket(port)

	var freed := await _wait_ms(func(): return ref.get_ref() == null, 2000)

	assert_true(freed, 'nothing keeps an unowned socket alive')
	assert_eq(tcp.listen(port, '127.0.0.1'), OK)
	await _wait_ms(func(): return false, 300)
	assert_false(tcp.is_connection_available(), 'it no longer dials')
	tcp.stop()


func test_a_socket_dropped_while_open_closes_its_connection():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var gone := []
	server.peer_disconnected.connect(func(peer_id): gone.append(peer_id))
	var holder := [LFSocket.new()]
	holder[0].connect_to_server('ws://127.0.0.1:%d' % port, LFSocketOptions.new())
	assert_true(await _wait_ms(func(): return server.connected_peer_ids().size() == 1), 'reached before the timeout')

	holder.clear()
	var closed := await _wait_ms(func(): return !gone.is_empty())

	assert_true(closed, 'the server sees the dropped socket leave')
	server.stop()


func test_a_message_sent_just_before_the_server_disconnects_reaches_its_listener():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	server.peer_connected.connect(func(peer_id):
		server.send_to(peer_id, { 'event': 'bye', 'data': { 'reason': 'full' } })
		server.disconnect_peer(peer_id))
	var options := LFSocketOptions.new()
	options.auto_reconnect = false
	var received := []
	sock.on_event('bye', func(data): received.append(data))

	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	assert_true(await _wait_ms(func(): return !received.is_empty()), 'reached before the timeout')

	assert_eq(received, [{ 'reason': 'full' }])
	sock.disconnect_from_server()
	server.stop()


# ---- routing details

func test_the_event_name_falls_back_to_type_and_the_data_to_the_whole_message():
	var received := []
	sock.on_event("greet", func(data): received.append(data))
	sock._handle_message(JSON.stringify({"type": "greet", "x": 1}))

	assert_eq(received, [{"type": "greet", "x": 1.0}])


func test_off_event_removes_a_wildcard_listener():
	var received := []
	var handler := func(event, data): received.append([event, data])
	sock.on_event("*", handler)
	sock.off_event("*", handler)
	sock._handle_message(JSON.stringify({"event": "greet", "data": "hi"}))

	assert_eq(received, [])


func test_a_pong_clears_the_heartbeat_flag_and_still_reaches_listeners():
	var received := []
	sock.on_event("*", func(event, data): received.append([event, data]))
	sock._waiting_for_pong = true

	sock._handle_message(JSON.stringify({"type": "pong"}))

	assert_false(sock._waiting_for_pong)
	assert_eq(received, [["pong", {"type": "pong"}]])


func test_a_response_with_an_unknown_id_reaches_no_listener():
	var received := []
	sock.on_event("*", func(event, data): received.append([event, data]))
	sock.on_event("response", func(data): received.append(data))

	sock._handle_message(JSON.stringify({"type": "response", "id": "nobody", "data": 1}))

	assert_eq(received, [])


func test_a_binary_frame_too_short_for_its_header_or_its_name_is_dropped():
	var received := []
	sock.on_binary_event("", func(data): received.append(data))
	sock.on_binary_event("bin", func(data): received.append(data))

	sock._handle_binary_message(PackedByteArray([1, 0]))
	var truncated := PackedByteArray([10, 0, 0, 0])
	truncated.append_array("bin".to_utf8_buffer())
	sock._handle_binary_message(truncated)

	assert_eq(received, [])
	assert_engine_error_count(0)


func test_a_dict_listener_hears_only_dictionary_data():
	var received := []
	sock.on_dict_event("state", func(data: Dictionary): received.append(data))
	sock.on_dict_event("*", func(event: String, data: Dictionary): received.append([event, data]))

	for data in ["text", 5, [1], null, {"ok": true}]:
		sock._handle_message(JSON.stringify({"event": "state", "data": data}))

	assert_eq(received, [["state", {"ok": true}], {"ok": true}])
	assert_engine_error_count(0, "a typed listener never sees a wrong type")


func test_a_dict_listener_with_no_data_field_hears_the_whole_message():
	var received := []
	sock.on_dict_event("state", func(data: Dictionary): received.append(data))

	sock._handle_message(JSON.stringify({"event": "state", "n": 1}))

	assert_eq(received, [{"event": "state", "n": 1.0}])


func test_off_event_removes_a_dict_listener_and_keeps_registration_order():
	var calls := []
	var dict_handler := func(_data): calls.append("dict")
	sock.on_event("e", func(_data): calls.append("first"))
	sock.on_dict_event("e", dict_handler)
	sock.on_event("e", func(_data): calls.append("last"))

	sock._handle_message(JSON.stringify({"event": "e", "data": {}}))
	sock.off_event("e", dict_handler)
	sock._handle_message(JSON.stringify({"event": "e", "data": {}}))

	assert_eq(calls, ["first", "dict", "last", "first", "last"])


# ---- jitter generator

func test_the_jitter_draws_from_the_options_generator_and_leaves_the_global_one_alone():
	var a := RandomNumberGenerator.new()
	a.seed = 7
	var b := RandomNumberGenerator.new()
	b.seed = 7
	seed(123)
	var expected_global := randf()
	seed(123)

	var first := LFSocket._jittered_ms(1000, a)
	var second := LFSocket._jittered_ms(1000, b)

	assert_eq(first, second, "one seed, one delay")
	assert_between(first, 800, 1200)
	assert_eq(randf(), expected_global, "the global generator did not move")


func test_reconnect_scheduling_uses_the_options_generator():
	if _refusal_unreported():
		pending(_REFUSAL_REASON)
		return
	var options := LFSocketOptions.new()
	options.rng = RandomNumberGenerator.new()
	options.rng.seed = 99
	options.reconnect_interval_ms = 50
	var state_before := options.rng.state
	var url := 'ws://127.0.0.1:%d' % LFSocketServer.free_port()
	options.auto_reconnect = true
	options.max_reconnect_attempts = 1

	sock.connect_to_server(url, options)
	assert_true(await _wait_ms(func(): return sock._reconnect_attempts == 1), 'reached before the timeout')

	assert_ne(options.rng.state, state_before, "the jitter came from the given generator")
	sock.disconnect_from_server()
	_tolerate_macos_refusal_noise()


# ---- status and oversized frames (real server)

func test_get_status_reports_every_key():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var url := 'ws://127.0.0.1:%d' % port
	var options := LFSocketOptions.new()
	options.auto_reconnect = false

	sock.connect_to_server(url, options)
	assert_true(await _wait_ms(func(): return sock.is_connected_to_server()), 'reached before the timeout')

	assert_eq(sock.get_status(), {
		'connected': true,
		'url': url,
		'state': WebSocketPeer.STATE_OPEN,
		'pending_requests': 0,
		'queued_messages': 0,
		'reconnect_attempts': 0,
		'auto_reconnect': false,
	})
	sock.disconnect_from_server()
	sock.send_message({'later': true})
	var after := sock.get_status()
	assert_false(after.connected)
	assert_eq(after.queued_messages, 1)
	server.stop()


## The server greets a new peer at once with a frame over the client's buffer, so the
## handshake answer and the oversized frame arrive in the same poll: the connection did
## open, so it reports as one that opened and closed with 1009 — not a refused attempt —
## and keeps what was queued for the next connection.
func test_an_oversized_frame_with_the_handshake_reports_an_open_then_a_1009_close():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var opened := []
	server.peer_connected.connect(func(peer_id):
		opened.append(peer_id)
		if opened.size() == 1:
			server.send_to(peer_id, {'event': 'big', 'data': 'x'.repeat(8192)}))
	var received := []
	server.message_received.connect(func(_peer_id, message): received.append(message))
	var options := LFSocketOptions.new()
	options.buffer_size = 1024
	options.reconnect_interval_ms = 30
	var events := []
	var close_codes := []
	sock.connected.connect(func(): events.append('connected'))
	sock.disconnected.connect(func():
		close_codes.append(sock._socket.get_close_code())
		events.append('disconnected'))
	sock.error_occurred.connect(func(_message): events.append('error'))
	sock.reconnect_scheduled.connect(func(attempt): events.append('reconnecting %d' % attempt))
	sock.send_message({'queued': true})

	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	assert_true(await _wait_ms(func(): return opened.size() == 2 and sock.is_connected_to_server() and received.size() == 1), 'reached before the timeout')

	assert_eq(events, ['connected', 'disconnected', 'reconnecting 1', 'connected'])
	assert_eq(close_codes, [1009])
	assert_eq(received, [{'queued': true}], 'the queued message waited for the connection that stayed open')
	sock.disconnect_from_server()
	server.stop()


func test_a_frame_larger_than_the_buffer_closes_with_1009_and_reconnects():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var opened := []
	server.peer_connected.connect(func(peer_id): opened.append(peer_id))
	var options := LFSocketOptions.new()
	options.buffer_size = 1024
	options.reconnect_interval_ms = 30
	var events := []
	var close_codes := []
	sock.disconnected.connect(func():
		close_codes.append(sock._socket.get_close_code())
		events.append('disconnected'))
	sock.reconnect_scheduled.connect(func(attempt): events.append('reconnecting %d' % attempt))

	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	assert_true(await _wait_ms(func(): return opened.size() == 1 and sock.is_connected_to_server()), 'reached before the timeout')
	server.send_to(opened[0], {'event': 'big', 'data': 'x'.repeat(8192)})
	assert_true(await _wait_ms(func(): return opened.size() == 2 and sock.is_connected_to_server()), 'reached before the timeout')

	assert_eq(opened.size(), 2, "the socket came back after the oversized frame")
	assert_eq(events, ['disconnected', 'reconnecting 1'])
	assert_eq(close_codes, [1009])
	sock.disconnect_from_server()
	server.stop()


# ---- reconnecting the same socket

func test_connecting_again_after_a_disconnect_reaches_open():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var url := 'ws://127.0.0.1:%d' % port
	sock.connect_to_server(url, LFSocketOptions.new())
	assert_true(await _wait_ms(func(): return sock.is_connected_to_server()), 'reached before the timeout')
	sock.disconnect_from_server()

	sock.connect_to_server(url, LFSocketOptions.new())
	var opened := await _wait_ms(func(): return sock.is_connected_to_server())

	assert_true(opened, 'the second connect opens')
	sock.disconnect_from_server()
	server.stop()


func test_connecting_while_open_closes_the_old_connection_first():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var url := 'ws://127.0.0.1:%d' % port
	var events := []
	sock.connected.connect(func(): events.append('connected'))
	sock.disconnected.connect(func(): events.append('disconnected'))
	sock.connect_to_server(url, LFSocketOptions.new())
	assert_true(await _wait_ms(func(): return sock.is_connected_to_server()), 'reached before the timeout')

	sock.connect_to_server(url, LFSocketOptions.new())
	assert_true(await _wait_ms(func(): return events.size() == 3), 'reached before the timeout')
	await _wait_ms(func(): return false, 100)

	assert_eq(events, ['connected', 'disconnected', 'connected'])
	assert_eq(server.connected_peer_ids().size(), 1, 'the old connection is gone')
	sock.disconnect_from_server()
	server.stop()


func test_a_url_that_cannot_be_dialled_returns_false_and_reports_an_error():
	var options := LFSocketOptions.new()
	options.auto_reconnect = false
	watch_signals(sock)

	var dialled := sock.connect_to_server('http://127.0.0.1:1', options) # not a WebSocket scheme

	assert_false(dialled)
	assert_signal_emitted(sock, 'error_occurred')
	assert_engine_error('scheme')
	assert_push_error('Failed to initiate connection')


func test_with_offline_queueing_off_a_message_sent_offline_is_dropped():
	sock._options.queue_offline_messages = false
	sock.send_message({'a': 1})
	assert_eq(sock.get_queue_size(), 0)


func test_a_disconnected_handler_that_connects_elsewhere_after_a_heartbeat_timeout_is_not_overridden():
	var tcp := TCPServer.new() # answers no pings
	assert_eq(tcp.listen(0, '127.0.0.1'), OK)
	var silent_port := tcp.get_local_port()
	var peers: Array[WebSocketPeer] = []
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var options := LFSocketOptions.new()
	options.heartbeat_interval_ms = 30
	options.heartbeat_timeout_ms = 30
	options.reconnect_interval_ms = 30
	var good := LFSocketOptions.new()
	good.reconnect_interval_ms = 30
	var attempts := []
	sock.reconnect_scheduled.connect(func(attempt): attempts.append(attempt))
	sock.disconnected.connect(func(): sock.connect_to_server('ws://127.0.0.1:%d' % port, good), CONNECT_ONE_SHOT)
	sock.connect_to_server('ws://127.0.0.1:%d' % silent_port, options)

	assert_true(await _wait_ms(func():
		_pump_raw_server(tcp, peers)
		for peer in peers:
			while peer.get_available_packet_count() > 0:
				peer.get_packet()
		return sock.is_connected_to_server() and sock.get_status().url.ends_with(str(port))), 'reached before the timeout')
	await _wait_ms(func(): _pump_raw_server(tcp, peers); return false, 200)

	assert_eq(attempts, [], 'no reconnect to the silent server is scheduled')
	assert_eq(peers.size(), 1, 'the silent server is not dialled again')
	assert_true(sock.is_connected_to_server())
	sock.disconnect_from_server()
	server.stop()
	tcp.stop()


func test_log_traffic_logs_messages_without_changing_delivery():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var received := []
	server.message_received.connect(func(peer_id, data):
		received.append(data)
		server.send_to(peer_id, {'event': 'echo', 'data': data}))
	var echoed := []
	sock.on_event('echo', func(data): echoed.append(data))
	var was := LFSocket.log_traffic
	var printed := LFLogger.enable_print_logs
	LFSocket.log_traffic = true
	LFLogger.enable_print_logs = false

	sock.connect_to_server('ws://127.0.0.1:%d' % port, LFSocketOptions.new())
	sock.send_message({'n': 1})
	assert_true(await _wait_ms(func(): return !echoed.is_empty()), 'reached before the timeout')

	LFSocket.log_traffic = was
	LFLogger.enable_print_logs = printed
	assert_eq(received, [{'n': 1.0}])
	assert_eq(echoed, [{'n': 1.0}])
	sock.disconnect_from_server()
	server.stop()


func test_the_heartbeat_types_are_the_wire_strings_servers_rely_on():
	assert_eq(LFSocket.PING_TYPE, 'ping')
	assert_eq(LFSocket.PONG_TYPE, 'pong')


func test_the_message_keys_and_types_are_the_wire_strings_servers_rely_on():
	assert_eq(LFSocket.REQUEST_TYPE, 'request')
	assert_eq(LFSocket.RESPONSE_TYPE, 'response')
	assert_eq(LFSocket.TYPE_KEY, 'type')
	assert_eq(LFSocket.EVENT_KEY, 'event')
	assert_eq(LFSocket.DATA_KEY, 'data')
	assert_eq(LFSocket.ID_KEY, 'id')
	assert_eq(LFSocket.PAYLOAD_KEY, 'payload')
	assert_eq(LFSocket.WILDCARD_EVENT, '*')
	assert_eq(LFSocket.DEFAULT_REQUEST_TIMEOUT_MS, 5000)


func test_options_start_at_their_documented_defaults():
	var options := LFSocketOptions.new()
	assert_true(options.auto_reconnect)
	assert_eq(options.reconnect_interval_ms, 1000)
	assert_eq(options.max_reconnect_interval_ms, 30000)
	assert_eq(options.reconnect_decay, 1.5)
	assert_eq(options.max_reconnect_attempts, 0)
	assert_eq(options.heartbeat_interval_ms, 30000)
	assert_eq(options.heartbeat_timeout_ms, 5000)
	assert_true(options.queue_offline_messages)
	assert_eq(options.max_queue_size, 100)
	assert_eq(options.buffer_size, 1 << 22)
	assert_null(options.rng)


func test_options_defaults_come_from_the_public_default_constants():
	var options := LFSocketOptions.new()
	assert_eq(options.reconnect_interval_ms, LFSocketOptions.DEFAULT_RECONNECT_INTERVAL_MS)
	assert_eq(options.max_reconnect_interval_ms, LFSocketOptions.DEFAULT_MAX_RECONNECT_INTERVAL_MS)
	assert_eq(options.reconnect_decay, LFSocketOptions.DEFAULT_RECONNECT_DECAY)
	assert_eq(options.heartbeat_interval_ms, LFSocketOptions.DEFAULT_HEARTBEAT_INTERVAL_MS)
	assert_eq(options.heartbeat_timeout_ms, LFSocketOptions.DEFAULT_HEARTBEAT_TIMEOUT_MS)
	assert_eq(options.max_queue_size, LFSocketOptions.DEFAULT_MAX_QUEUE_SIZE)
	assert_eq(options.buffer_size, LFSocketOptions.DEFAULT_BUFFER_SIZE)


# ---- edge cases

func test_an_answer_survives_a_close_before_the_waiting_request_resumes():
	sock._socket = WebSocketPeer.new()
	sock._connected = true

	var results = await LFAwait.all([
		func(): return await sock.request_message({"x": 1}, 0),
		func():
			await get_tree().process_frame
			var request_id: String = sock._pending_requests.keys()[0]
			# The answer and then a kick, handled before the request's coroutine resumes.
			sock._handle_message(JSON.stringify({"type": "response", "id": request_id, "data": "kept"}))
			sock.disconnect_from_server()
			return null,
	])
	assert_engine_error("ready_state") # the fake-connected send fails at the engine level
	assert_push_error_count(1)

	assert_eq(results[0], "kept")


func test_force_reconnect_after_a_plain_disconnect_turns_reconnecting_back_on():
	if _refusal_unreported():
		pending(_REFUSAL_REASON)
		return
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 60000 # never actually fires within this test
	sock.connect_to_server('ws://127.0.0.1:%d' % LFSocketServer.free_port(), options)
	sock.disconnect_from_server()
	var attempts := []
	sock.reconnect_scheduled.connect(func(attempt): attempts.append(attempt))

	sock.force_reconnect() # the port is closed, so this attempt is refused
	assert_true(await _wait_ms(func(): return !attempts.is_empty()), 'reached before the timeout')

	assert_eq(attempts, [1], "the refused attempt schedules a reconnect")
	sock.disconnect_from_server()
	_tolerate_macos_refusal_noise()


func test_a_queue_size_of_zero_queues_nothing():
	sock._options.max_queue_size = 0
	sock.send_message({"a": 1})
	assert_eq(sock.get_queue_size(), 0)


func test_a_shrunken_queue_limit_evicts_down_to_the_new_size():
	for i in 5:
		sock.send_message({"id": i})
	sock._options.max_queue_size = 2

	sock.send_message({"id": 5})

	assert_eq(sock._message_queue, [{"id": 4}, {"id": 5}] as Array[Dictionary])


func test_null_options_connect_with_the_defaults():
	var dialled := sock.connect_to_server('ws://127.0.0.1:%d' % LFSocketServer.free_port(), null)

	assert_true(dialled)
	assert_eq(sock.get_status().auto_reconnect, true)
	sock.disconnect_from_server()


class _Listener extends RefCounted:
	var calls := []
	func on_text(data: Variant) -> void:
		calls.append(data)
	func on_any(event_name: String, _data: Variant) -> void:
		calls.append(event_name)
	func on_bytes(data: PackedByteArray) -> void:
		calls.append(data)


func test_a_listener_whose_object_was_freed_is_skipped_and_removed():
	var gone := Node.new()
	sock.on_event("e", Callable(gone, &"queue_free"))
	sock.on_event("*", Callable(gone, &"queue_free"))
	sock.on_binary_event("bin", Callable(gone, &"queue_free"))
	var alive := _Listener.new()
	sock.on_event("e", alive.on_text)
	sock.on_event("*", alive.on_any)
	sock.on_binary_event("bin", alive.on_bytes)
	gone.free()

	sock._handle_message(JSON.stringify({"event": "e", "data": 1}))
	sock._handle_binary_message(_binary_frame("bin", PackedByteArray([9])))

	assert_eq(alive.calls, ["e", 1.0, PackedByteArray([9])], "the live listeners still hear everything")
	assert_eq(sock._listeners["e"].size(), 1)
	assert_eq(sock._wildcard_listeners.size(), 1)
	assert_eq(sock._binary_listeners["bin"].size(), 1)
	assert_engine_error_count(0)


# ---- a server that sends the client away

func test_a_client_the_server_disconnects_on_purpose_does_not_reconnect():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var joins := []
	server.peer_connected.connect(func(peer_id):
		joins.append(peer_id)
		server.disconnect_peer(peer_id))
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 30
	var reconnects := []
	sock.reconnect_scheduled.connect(func(attempt): reconnects.append(attempt))

	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	assert_true(await _wait_ms(func(): return sock.get_close_code() == LFSocket.DISCONNECTED_BY_SERVER_CODE), 'reached before the timeout')
	# A window in which a redial would show up; it is expected to run out.
	await _wait_ms(func(): return joins.size() > 1, 400)

	assert_eq(sock.get_close_code(), LFSocket.DISCONNECTED_BY_SERVER_CODE)
	assert_eq(joins.size(), 1, 'the client stayed away')
	assert_eq(reconnects, [], 'no reconnect was scheduled')
	sock.disconnect_from_server()
	server.stop()


func test_a_server_that_stops_is_still_redialled():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	var options := LFSocketOptions.new()
	options.reconnect_interval_ms = 30
	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	assert_true(await _wait_ms(func(): return sock.is_connected_to_server()), 'reached before the timeout')

	server.stop()
	assert_true(await _wait_ms(func(): return !sock.is_connected_to_server()), 'reached before the timeout')
	assert_eq(server.listen(port, '127.0.0.1'), OK, 'the port it just let go of')
	var back := await _wait_ms(func(): return sock.is_connected_to_server())

	assert_true(back, 'a stop is not a kick, so the client comes back')
	sock.disconnect_from_server()
	server.stop()


func test_get_close_code_is_unknown_until_a_connection_closes():
	assert_eq(sock.get_close_code(), -1)


# ---- TLS

## A self-signed certificate made on the spot: the server encrypts with it, and a client
## that trusts exactly that certificate connects over wss://.
func test_a_tls_server_talks_to_a_wss_client():
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var cert := crypto.generate_self_signed_certificate(key, 'CN=localhost,O=LF test,C=US')
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1', TLSOptions.server(key, cert)), OK)
	var port := server.get_local_port()
	server.message_received.connect(func(peer_id, data): server.send_to(peer_id, { 'event': 'echo', 'data': data }))
	var options := LFSocketOptions.new()
	options.tls_options = TLSOptions.client(cert, 'localhost')
	var received := []
	sock.on_event('echo', func(data): received.append(data))

	sock.connect_to_server('wss://127.0.0.1:%d' % port, options)
	sock.send_message({ 'hello': 'tls' })
	assert_true(await _wait_ms(func(): return !received.is_empty()), 'reached before the timeout')

	assert_eq(received, [{ 'hello': 'tls' }])
	assert_eq(server.peer_address(server.connected_peer_ids()[0]), '127.0.0.1')
	sock.disconnect_from_server()
	server.stop()


func test_a_plain_ws_client_cannot_connect_to_a_tls_server():
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var cert := crypto.generate_self_signed_certificate(key, 'CN=localhost,O=LF test,C=US')
	var server := LFSocketServer.new()
	server.handshake_timeout_ms = 300
	assert_eq(server.listen(0, '127.0.0.1', TLSOptions.server(key, cert)), OK)
	var port := server.get_local_port()
	var options := LFSocketOptions.new()
	options.auto_reconnect = false
	var errors := []
	sock.error_occurred.connect(func(message): errors.append(message))

	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	assert_true(await _wait_ms(func(): return !errors.is_empty()), 'reached before the timeout')

	assert_false(sock.is_connected_to_server())
	assert_eq(server.connected_peer_ids(), [])
	# The engine logs the failed server-side handshake when the server next polls; whether
	# that is before or after the client reports its error depends on the platform, so wait
	# for it and claim it rather than let it count as unexpected.
	var logged := func() -> bool:
		return get_errors().any(func(e): return e.is_engine_error() and e.contains_text('TLS handshake'))
	await _wait_ms(logged, 1000)
	if logged.call():
		assert_engine_error('TLS handshake', 'the engine reports the failed handshake too')
	server.stop()


func test_listen_refuses_client_tls_options():
	var server := LFSocketServer.new()
	assert_eq(server.listen(0, '127.0.0.1', TLSOptions.client()), ERR_INVALID_PARAMETER)
	assert_false(server.is_listening())


# ---- listener bookkeeping

func test_a_callback_registered_twice_runs_twice_and_off_event_removes_one_at_a_time():
	var calls := []
	var handler := func(data): calls.append(data)
	sock.on_event("e", handler)
	sock.on_event("e", handler)

	sock._handle_message(JSON.stringify({"event": "e", "data": 1}))
	sock.off_event("e", handler)
	sock._handle_message(JSON.stringify({"event": "e", "data": 2}))
	sock.off_event("e", handler)
	sock._handle_message(JSON.stringify({"event": "e", "data": 3}))

	assert_eq(calls, [1.0, 1.0, 2.0])


func test_removing_a_listener_that_is_not_registered_changes_nothing():
	var calls := []
	var handler := func(data): calls.append(data)
	sock.on_event("e", handler)

	sock.off_event("e", func(_data): pass)
	sock.off_event("never-registered", handler)
	sock.off_event("*", handler)
	sock.off_binary_event("never-registered", handler)
	sock._handle_message(JSON.stringify({"event": "e", "data": 1}))

	assert_eq(calls, [1.0])


func test_a_binary_frame_reaches_neither_wildcard_nor_text_listeners():
	var heard := []
	sock.on_event("*", func(event, _data): heard.append(event))
	sock.on_binary_event("other", func(data): heard.append(data))

	sock._handle_binary_message(_binary_frame("bin", PackedByteArray([1])))

	assert_eq(heard, [], "no listener for its event, and wildcards never hear binary frames")


## With the heartbeat off the client sends no pings at all, so a server that does not
## answer them keeps the connection.
func test_a_heartbeat_interval_of_zero_sends_no_pings():
	var tcp := TCPServer.new()
	assert_eq(tcp.listen(0, '127.0.0.1'), OK)
	var port := tcp.get_local_port()
	var peers := []
	var options := LFSocketOptions.new()
	options.heartbeat_interval_ms = 0
	options.heartbeat_timeout_ms = 1
	sock.connect_to_server('ws://127.0.0.1:%d' % port, options)
	sock.send_message({"type": "hello"})

	var texts := []
	var pump := func() -> bool:
		_pump_raw_server(tcp, peers)
		for peer: WebSocketPeer in peers:
			while peer.get_available_packet_count() > 0:
				texts.append(peer.get_packet().get_string_from_utf8())
		return !texts.is_empty()
	assert_true(await _wait_ms(pump), 'the queued message arrived')
	await _wait_ms(func(): pump.call(); return false, 300)

	assert_eq(texts, [JSON.stringify({"type": "hello"})], "only the message, no ping")
	assert_true(sock.is_connected_to_server(), "no unanswered ping, so no timeout")
	assert_eq(peers.size(), 1, "never redialled")
	sock.disconnect_from_server()
	tcp.stop()


## Before any connect_to_server() there is nothing to redial: the call is reported and
## neither dials, nor emits error, nor schedules a reconnect.
func test_force_reconnect_before_any_connect_is_reported_and_does_nothing():
	var fresh := LFSocket.new()
	var errors := []
	var attempts := []
	fresh.error_occurred.connect(func(message): errors.append(message))
	fresh.reconnect_scheduled.connect(func(attempt): attempts.append(attempt))

	fresh.force_reconnect()
	await wait_process_frames(3)

	assert_push_error("connect_to_server")
	assert_push_error_count(1, "only the report: no failed dial of an empty URL")
	assert_eq(errors, [], "no error signal: nothing was dialled")
	assert_eq(attempts, [], "no reconnect scheduled")
	assert_eq(fresh.get_status().reconnect_attempts, 0)
	assert_eq(fresh.get_status().state, WebSocketPeer.STATE_CLOSED)


# ---- URL redaction in logs

func test_redact_url_removes_userinfo_and_query():
	assert_eq(LFSocket.redact_url('wss://user:pw@game.example:8443/play?token=abc#frag'), 'wss://game.example:8443/play?...')
	assert_eq(LFSocket.redact_url('ws://127.0.0.1:9080'), 'ws://127.0.0.1:9080', 'a plain URL is unchanged')
	assert_eq(LFSocket.redact_url('ws://host/path'), 'ws://host/path')
	assert_eq(LFSocket.redact_url('ws://a@b@host/x'), 'ws://host/x', 'the last @ ends the userinfo')
	assert_eq(LFSocket.redact_url('ws://host/mail@x'), 'ws://host/mail@x', 'an @ in the path stays')
	assert_eq(LFSocket.redact_url('ws://host?k=v'), 'ws://host?...')
	assert_eq(LFSocket.redact_url('ws://host#only-fragment'), 'ws://host?...')
	assert_eq(LFSocket.redact_url('ws://[::1]:90/p?x=1'), 'ws://[::1]:90/p?...')
	assert_eq(LFSocket.redact_url('user:pw@nonsense?q=1'), 'nonsense?...', 'malformed text is still cleaned')
	assert_eq(LFSocket.redact_url(''), '')


func test_the_error_for_an_undialable_url_does_not_carry_its_secrets():
	var options := LFSocketOptions.new()
	options.auto_reconnect = false

	sock.connect_to_server('http://user:secret@127.0.0.1:1/p?token=abc', options) # not a WebSocket scheme

	assert_engine_error('scheme')
	assert_push_error('http://127.0.0.1:1/p?...')
	assert_push_error_count(1, 'only the redacted report')
