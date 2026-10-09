## A WebSocket client for talking to a server that redials on its own when the connection
## drops.
##
## Messages are JSON objects. An incoming message is routed to listeners by its `event`
## field (or its `type` field), and listeners get its `data` field. When the connection
## drops, the socket redials on its own, waiting a little longer after each failed attempt
## (exponential backoff); a server that closes it with [constant DISCONNECTED_BY_SERVER_CODE]
## is not redialled. A heartbeat (a small "ping" every [member LFSocketOptions.heartbeat_interval_ms],
## answered with "pong") spots a connection that died silently. Messages sent while offline are queued
## and sent once the connection opens. [method request_message] sends a request and waits
## for the server's answer.[br][br]
## It polls itself once per SceneTree frame, so nothing needs to call a `poll()` method.
## Keep a reference to it: a socket nobody holds is freed and closes its connection.
class_name LFSocket
extends RefCounted

## The `type` of the heartbeat message the socket sends: `{"type": "ping"}`.
const PING_TYPE := 'ping'
## The `type` of the heartbeat answer a server must send back: `{"type": "pong"}`.
const PONG_TYPE := 'pong'
## The `type` of a message [method request_message] sends:
## `{"type": "request", "id": ..., "payload": ...}`.
const REQUEST_TYPE := 'request'
## The `type` of the server's answer to a request: `{"type": "response", "id": ..., "data": ...}`.
const RESPONSE_TYPE := 'response'
## Message key holding the message's kind (`ping`, `pong`, `request`, `response`), and
## the event name when [constant EVENT_KEY] is absent.
const TYPE_KEY := 'type'
## Message key holding the event name listeners are routed by.
const EVENT_KEY := 'event'
## Message key holding the value listeners (and a waiting request) receive.
const DATA_KEY := 'data'
## Message key holding a request's id, echoed back in its response.
const ID_KEY := 'id'
## Message key holding what a request sends.
const PAYLOAD_KEY := 'payload'
## The event name that registers a listener for every text event.
const WILDCARD_EVENT := '*'
## Default `timeout_ms` of [method request_message], in milliseconds.
const DEFAULT_REQUEST_TIMEOUT_MS := 5000
## WebSocket close code a server sends when it deliberately disconnects this client (e.g.
## [method LFSocketServer.disconnect_peer]: a kick, a full room). A connection closed with
## it is not redialled. It lies in the 4000-4999 range the WebSocket standard leaves to
## applications.
const DISCONNECTED_BY_SERVER_CODE := 4000

## Prefix of this socket's id, shown in its log lines.
const _UID_PREFIX := 'socket-instance'
## Log line prefix; `%s` is the socket's id.
const _LOG_PREFIX_FORMAT := '[LFSocket] (%s):'
## A request id: `%d` the send time in msec, then `%d` a per-socket counter.
const _REQUEST_ID_FORMAT := 'req_%d_%d'
## Key of a pending request's answer callback.
const _CALLBACK_KEY := 'callback'
## Bytes of the little-endian u32 event-name length that starts a binary frame.
const _BINARY_LENGTH_BYTES := 4
## Shortest wait before a redial, in milliseconds, whatever the options say (so an interval
## of 0 or a decay below 1 cannot make the socket redial every frame).
const _MIN_RECONNECT_DELAY_MS := 50
## Lowest factor a reconnect delay is scaled by (-20 %), so clients that lost the same
## server spread their redials out.
const _JITTER_MIN := 0.8
## Highest factor a reconnect delay is scaled by (+20 %).
const _JITTER_MAX := 1.2
## Close code the engine reports while no handshake has completed (no close code yet).
const _NO_CLOSE_CODE := -1
## Ready state names for the state-change log line.
const _STATE_NAMES := {
	WebSocketPeer.STATE_CONNECTING: 'CONNECTING',
	WebSocketPeer.STATE_OPEN: 'OPEN',
	WebSocketPeer.STATE_CLOSING: 'CLOSING',
	WebSocketPeer.STATE_CLOSED: 'CLOSED',
}
## Name logged for a ready state outside [constant _STATE_NAMES] (none seen yet).
const _UNKNOWN_STATE_NAME := 'UNKNOWN'
## Warnings caused by what the server sends (a bad frame, an unknown request id) logged in
## full per kind and socket; after that only every [constant _WARNING_SUMMARY_EVERY]th is,
## as a count.
const _WARNINGS_IN_FULL := 5
## A warning kind past [constant _WARNINGS_IN_FULL] is reported again at every multiple of this.
const _WARNING_SUMMARY_EVERY := 1000
## Characters of server-sent text a warning quotes; the rest is replaced by its length.
const _PREVIEW_CHARS := 120
## Lowest code point that is not a C0 control character.
const _FIRST_PRINTABLE := 0x20
## DEL, the C0 range's companion control character.
const _DEL := 0x7f
## Last C1 control character (U+0080 to U+009F).
const _LAST_C1_CONTROL := 0x9f


var _socket: WebSocketPeer
var _url: String
var _uid := LFUuid.gen(_UID_PREFIX)
var _logger := LFLogger.new([_LOG_PREFIX_FORMAT % [_uid]])
## When `true`, every message sent and received (and each heartbeat) is logged, not just
## connects and disconnects. Off by default: on a live connection that is many lines a
## second, each formatting the whole payload. Shared by every LFSocket in the process.
static var log_traffic := false
var _connected: bool = false
## Defaults until connect_to_server() supplies the real ones, so sending first queues.
var _options: LFSocketOptions = LFSocketOptions.new()
## event -> Array of [callback, dict_only] pairs, in registration order.
var _listeners: Dictionary = {}
var _binary_listeners: Dictionary = {} # event -> Array[Callable]
## [callback, dict_only] pairs for every text event (WILDCARD_EVENT), in registration order.
var _wildcard_listeners: Array = []
var _pending_requests: Dictionary = {} # request_id -> { callback, timeout }
var _request_counter: int = 0
var _message_queue: Array[Dictionary] = []  # offline messages, oldest first
var _should_reconnect: bool = true
## Set once `disconnect_from_server()` is called — the background poll loop stops on
## this flag alone, whatever state the socket's own close handshake is in.
var _intentionally_disconnected: bool = false
var _reconnect_attempts: int = 0
var _current_reconnect_interval: int = 0
var _last_heartbeat_time: int = 0
var _waiting_for_pong: bool = false
var _ping_sent_at: int = 0
## Bumped by every _start_polling(); a loop whose generation is stale exits on its own,
## so a reconnect can never leave two loops polling the same (or a replaced) peer.
var _poll_generation: int = 0
## The current poll loop's driver; replacing it retires the old loop.
var _poller: _Poller
## Bumped by every connect, disconnect and newly scheduled reconnect; a reconnect timer
## whose generation is stale does nothing, so it can never replace a live socket.
var _reconnect_generation: int = 0
## Ready state seen by the previous poll, for logging transitions.
var _last_state: int = -1
## How many warnings of each server-caused kind this socket has had.
var _warning_counts: Dictionary = {}  # kind (String) -> int

## The connection opened: messages can now be sent. The offline queue is sent right after
## this signal's handlers return, so a message a handler sends (e.g. a login) goes first.
signal connected
## An open connection ended: the server closed it, the heartbeat timed out, or
## [method disconnect_from_server] closed it. Never fires for a connection that never opened.
signal disconnected
## A connect attempt failed (the URL could not be dialled, or the connection closed
## before it opened, e.g. the server refused it), or the reconnect attempt limit was
## reached. `message` says which. Fires for every failed attempt, whether or not a
## reconnect follows.
signal error_occurred(message: String)
## A reconnect was scheduled. `attempt` counts from 1 since the last open connection.
signal reconnect_scheduled(attempt: int)

func _init() -> void:
	_socket = WebSocketPeer.new()

## Returns `url` as it is written to log lines: the user name and password before an
## `@` are removed, and a query (`?` and everything after it, a fragment included) is
## replaced by `?...`. Scheme, host, port and path stay, so the line still says where the
## socket dials; put no secret in a path. Works on any text, including a malformed URL.
static func redact_url(url: String) -> String:
	var cut := url.length()
	for mark: Variant in ['?', '#']:
		var at := url.find(mark)
		if at != -1:
			cut = mini(cut, at)
	var out := url.substr(0, cut)
	var scheme_end := out.find('://')
	var authority_start := scheme_end + 3 if scheme_end != -1 else 0
	var authority_end := out.find('/', authority_start)
	if authority_end == -1:
		authority_end = out.length()
	var at_sign := out.rfind('@', authority_end - 1)
	if at_sign >= authority_start:
		out = out.substr(0, authority_start) + out.substr(at_sign + 1)
	return out + '?...' if cut < url.length() else out


## Starts connecting to `url` (e.g. `"ws://127.0.0.1:9080"`) with `options`, and starts
## the per-frame poll loop. The reconnect attempt count starts again from zero. A
## connection that is open or still opening is closed first (emitting [signal disconnected]
## if it was open). Returns `true` once the dial has started (the connection opens later,
## see [signal connected]); returns `false`, emits [signal error_occurred] and schedules a reconnect
## if the URL cannot be dialled at all (e.g. it is malformed).
func connect_to_server(url: String, options := LFSocketOptions.new()) -> bool:
	_logger.log('Initializing connection to: %s' % redact_url(url))
	if _socket != null and _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_close(false)
	_socket = WebSocketPeer.new()
	_url = url
	_options = options if options != null else LFSocketOptions.new()
	# Re-arms reconnecting after an earlier disconnect_from_server() disabled it.
	_should_reconnect = true
	_reconnect_generation += 1 # retire any pending reconnect timer
	_reconnect_attempts = 0
	_current_reconnect_interval = _options.reconnect_interval_ms
	_logger.log('Configuration - heartbeat: %dms, max_queue: %d, auto_reconnect: %s' % [_options.heartbeat_interval_ms, _options.max_queue_size, _options.auto_reconnect])
	return _attempt_connection()

func _attempt_connection() -> bool:
	_logger.log('Attempting connection to: %s' % redact_url(_url))
	# Every attempt gets a poll loop; only a disconnect_from_server() after it stops one.
	_intentionally_disconnected = false

	# Buffer sizes only take effect before the peer connects.
	var buffer_size := _options.buffer_size if _options.buffer_size > 0 else LFSocketOptions.DEFAULT_BUFFER_SIZE
	_socket.inbound_buffer_size = buffer_size
	_socket.outbound_buffer_size = buffer_size
	var err := _socket.connect_to_url(_url, _options.tls_options)
	if err != OK:
		_logger.error('Failed to initiate connection to %s (error %s)' % [redact_url(_url), error_string(err)])
		var generation := _reconnect_generation
		_trigger_error('Connection failed: error %d' % err)
		# An error handler that connected or disconnected has decided what happens next.
		if generation == _reconnect_generation:
			_schedule_reconnect()
		return false
	_logger.log('Connection initiated')
	_start_polling()
	return true

## Closes the connection and stops the poll loop; emits [signal disconnected] if it was
## open. Pending [method request_message] calls return `null`. The close is immediate:
## messages sent in the same frame that have not gone out yet are lost. By default the
## socket then stays closed; with `disable_reconnect` set to `false` a reconnect is
## scheduled (if [member LFSocketOptions.auto_reconnect] is on and the attempt limit
## allows). Safe to call when not connected.
func disconnect_from_server(disable_reconnect: bool = true) -> void:
	_close(disable_reconnect)
	if !disable_reconnect:
		_schedule_reconnect()

func _close(disable_reconnect: bool) -> void:
	_logger.log('Disconnecting from server, disable_reconnect: %s' % disable_reconnect)
	_should_reconnect = !disable_reconnect
	_intentionally_disconnected = true
	_reconnect_generation += 1 # retire any pending reconnect timer
	if _socket:
		_logger.log('Closing socket, current state: %d' % _socket.get_ready_state())
		_socket.close()
	var was_connected := _connected
	_connected = false
	_fail_pending_requests()
	if was_connected:
		disconnected.emit()

## Returns `true` while the connection is open, `false` while connecting, reconnecting or closed.
func is_connected_to_server() -> bool:
	return _connected

## Sends `message` to the server as JSON text. While offline the message is queued and
## sent when the connection opens (as a deep copy taken now), if both `queue_if_offline` and
## [member LFSocketOptions.queue_offline_messages] allow it; otherwise it is dropped with a
## logged warning. Use `queue_if_offline = false` for messages that are stale a moment later
## (e.g. a cursor position).
func send_message(message: Dictionary, queue_if_offline: bool = true) -> void:
	if log_traffic:
		_logger.log('send_message():', message, 'connected: %s' % [_connected])
	if !_connected and queue_if_offline and _options.queue_offline_messages:
		if log_traffic:
			_logger.log('Not connected, queueing message...')
		_queue_message(message.duplicate(true))
	else:
		_send_json(message)


## Sends raw bytes tagged with `event`, for data that isn't JSON (an image, a file).
## The frame is a 4-byte little-endian length of the event name, the name as UTF-8, then
## `data`. Never queued: while offline it is dropped with a logged warning.
func emit_binary(event: String, data: PackedByteArray) -> void:
	if log_traffic:
		_logger.log('emit_binary() called for event: %s, data size: %d bytes' % [event, data.size()])
	if !_socket or !_connected:
		_logger.warning('Cannot send binary data when not connected')
		return
	var event_bytes := event.to_utf8_buffer()
	var full_data := PackedByteArray()
	full_data.resize(_BINARY_LENGTH_BYTES)
	full_data.encode_u32(0, event_bytes.size())
	full_data.append_array(event_bytes)
	full_data.append_array(data)
	var err := _socket.send(full_data)
	if err != OK:
		_logger.error('Failed to send binary data (error %d)' % err)
	elif log_traffic:
		_logger.log('Binary data sent, total size: %d bytes' % full_data.size())

## Sends `{"type": "request", "id": ..., "payload": payload}` and waits (use `await`) for
## the server's `{"type": "response", "id": <same id>, "data": ...}`, then returns its
## `data`. `payload` can be any JSON value (Dictionary, Array, String, number, bool, null).
## Returns `null` at once while offline, when the connection closes before the answer, or
## after `timeout_ms` milliseconds (`<= 0` means no time limit: it waits for the answer or
## the close). Never queued.
func request_message(payload: Variant, timeout_ms := DEFAULT_REQUEST_TIMEOUT_MS) -> Variant:
	if !_connected:
		_logger.warning('request_message while not connected -- returning null')
		return null
	_request_counter += 1
	var request_id := _REQUEST_ID_FORMAT % [Time.get_ticks_msec(), _request_counter]
	if log_traffic:
		_logger.log('request_message() -', payload, 'id: %s, timeout: %dms' % [request_id, timeout_ms])

	# Boxed in an Array: a lambda captures locals by value, so assigning a plain local
	# inside it would never be seen by the loop below.
	var response_state := [false, null] # [received, data]
	_pending_requests[request_id] = {
		_CALLBACK_KEY: func(data_response: Variant) -> void:
			response_state[1] = data_response
			response_state[0] = true,
	}
	_send_json({ TYPE_KEY: REQUEST_TYPE, ID_KEY: request_id, PAYLOAD_KEY: payload })

	var start_time := Time.get_ticks_msec()
	while !response_state[0]:
		if timeout_ms > 0 and (Time.get_ticks_msec() - start_time) > timeout_ms:
			_pending_requests.erase(request_id)
			_logger.warning('Request timeout for (id: %s)' % [request_id])
			return null
		await LFAwait.next_tick

	if log_traffic:
		_logger.log('Received response for request id: %s' % request_id)
	_pending_requests.erase(request_id)
	return response_state[1]

## Calls `callback(data)` for every incoming message whose event name is `event`. The
## event `"*"` ([constant WILDCARD_EVENT]) instead calls `callback(event_name, data)` for every
## message except `{"type": "response"}` frames, which go only to [method request_message]. `data` is
## whatever JSON value the server sent, so check its type before using it, or use
## [method on_dict_event]. Registering the same callback twice calls it twice. A listener
## whose object was freed (a node that never called [method off_event]) is skipped and
## removed. Binary frames go to [method on_binary_event] listeners instead.
func on_event(event: String, callback: Callable) -> void:
	_add_listener(event, callback, false)

## Like [method on_event], but `callback` runs only when the message's data is a
## Dictionary; data of any other type (a string, a number or an array) is skipped for it,
## so a callback typed `func(data: Dictionary)` never fails on unexpected input.
func on_dict_event(event: String, callback: Callable) -> void:
	_add_listener(event, callback, true)

## Removes a listener added with [method on_event] or [method on_dict_event] (pass `"*"`
## for a wildcard listener). Removes one registration per call; does nothing if the
## callback isn't registered for that event.
func off_event(event: String, callback: Callable) -> void:
	var entries: Array = _wildcard_listeners if event == WILDCARD_EVENT else _listeners.get(event, [])
	for i in entries.size():
		if entries[i][0] == callback:
			entries.remove_at(i)
			return

func _add_listener(event: String, callback: Callable, dict_only: bool) -> void:
	if event == WILDCARD_EVENT:
		_wildcard_listeners.append([callback, dict_only])
		return
	if !_listeners.has(event):
		_listeners[event] = []
	_listeners[event].append([callback, dict_only])

## Calls `callback(data: PackedByteArray)` for every binary frame tagged with `event`
## (see [method emit_binary]).
func on_binary_event(event: String, callback: Callable) -> void:
	if !_binary_listeners.has(event):
		_binary_listeners[event] = []
	_binary_listeners[event].append(callback)

## Removes a listener added with [method on_binary_event]; does nothing if it isn't registered.
func off_binary_event(event: String, callback: Callable) -> void:
	if _binary_listeners.has(event):
		_binary_listeners[event].erase(callback)

## Returns how many messages are waiting in the offline queue.
func get_queue_size() -> int:
	return _message_queue.size()

## Throws away every message waiting in the offline queue.
func clear_queue() -> void:
	_message_queue.clear()

## Closes the current connection (if any) and dials again right away, with the reconnect
## delay and attempt count reset, and reconnecting turned back on after a
## [method disconnect_from_server]. A dial still in progress is abandoned in favour of the
## new one. Use it when you know the network came back. Before any
## [method connect_to_server] there is no URL to dial: it reports an error through the
## socket's logger and does nothing else (no [signal error_occurred], no reconnect scheduled).
func force_reconnect() -> void:
	if _url == '':
		_logger.error('force_reconnect: no URL to dial yet; call connect_to_server() first')
		return
	if _connected or (_socket != null and _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED):
		_close(false) # redials below, so no delayed reconnect is scheduled
	# Retire the old dial's poll loop: it would otherwise poll the new peer too, and report
	# a dial that fails at once a second time.
	_poll_generation += 1
	# Re-arms reconnecting after an earlier disconnect_from_server() disabled it.
	_should_reconnect = true
	_reconnect_attempts = 0
	_reconnect_generation += 1 # retire any pending reconnect timer
	_current_reconnect_interval = _options.reconnect_interval_ms
	_socket = WebSocketPeer.new() # a closed peer cannot be redialled
	_attempt_connection()

## Returns a snapshot for debugging: `connected` (bool), `url` (String), `state` (a
## `WebSocketPeer.State` value), `pending_requests` (int), `queued_messages` (int),
## `reconnect_attempts` (int) and `auto_reconnect` (bool).
func get_status() -> Dictionary:
	return {
		'connected': _connected,
		'url': _url,
		'state': _socket.get_ready_state() if _socket else WebSocketPeer.STATE_CLOSED,
		'pending_requests': _pending_requests.size(),
		'queued_messages': _message_queue.size(),
		'reconnect_attempts': _reconnect_attempts,
		'auto_reconnect': _options.auto_reconnect if _options else false
	}

func _send_json(data: Dictionary) -> void:
	if !_connected:
		_logger.warning('Cannot send message when not connected, socket state: %d' % _socket.get_ready_state())
		return

	var json_str := JSON.stringify(data)
	if log_traffic:
		_logger.log('Sending JSON message, type: %s, size: %d bytes' % [data.get(TYPE_KEY, 'unknown'), json_str.length()])
	var err := _socket.send_text(json_str)
	if err != OK:
		_logger.error('Failed to send message (error %d)' % err)

func _queue_message(message: Dictionary) -> void:
	if _options.max_queue_size <= 0:
		_logger.warning('The offline queue holds no messages (max_queue_size %d), dropping it' % _options.max_queue_size)
		return
	# A while, not an if: the limit may have shrunk since the queue filled.
	while _message_queue.size() >= _options.max_queue_size:
		_message_queue.pop_front()
		_logger.warning('Message queue full (%d messages), removed oldest message' % _options.max_queue_size)
	_message_queue.append(message)
	if log_traffic:
		_logger.log('Message queued, queue size: %d/%d' % [_message_queue.size(), _options.max_queue_size])

func _flush_queue() -> void:
	if _message_queue.is_empty():
		return
	if log_traffic:
		_logger.log('Flushing %d queued messages' % _message_queue.size())
	for message in _message_queue:
		_send_json(message)
	_message_queue.clear()

func _start_polling() -> void:
	if LFUtils.tree_root == null:
		_logger.error('SceneTree not available')
		return

	_logger.log('Starting polling loop')
	_poll_generation += 1
	_last_state = -1
	_poller = _Poller.new(self, _poll_generation)
	@warning_ignore("missing_await")
	LFUtils.poll_each_frame(_poller, &'step')

## Drives one poll loop. The socket holds it and it holds the socket only weakly, so a
## socket its owner dropped is freed (closing its connection) and the loop ends with it;
## a newer loop replaces the poller, which ends the old loop too.
class _Poller extends RefCounted:
	var _socket_ref: WeakRef
	var _generation: int

	func _init(socket: LFSocket, generation: int) -> void:
		_socket_ref = weakref(socket)
		_generation = generation

	## One poll; false when this loop should stop.
	func step() -> bool:
		var socket: LFSocket = _socket_ref.get_ref()
		return socket != null and socket._poll_once(_generation)

## One poll of the socket; false when this loop should stop.
func _poll_once(generation: int) -> bool:
	if generation != _poll_generation:
		_logger.log('A newer poll loop took over -- stopping this one')
		return false
	if _intentionally_disconnected:
		_logger.log('Intentionally disconnected -- stopping the poll loop')
		return false
	_socket.poll()
	var state := _socket.get_ready_state()
	if state != _last_state:
		_logger.log('State changed: %s -> %s' % [_STATE_NAMES.get(_last_state, _UNKNOWN_STATE_NAME), _STATE_NAMES.get(state, _UNKNOWN_STATE_NAME)])
		_last_state = state

	if state == WebSocketPeer.STATE_OPEN and !_connected:
		if !_handle_opened(generation):
			return false

	if !_read_packets(generation):
		return false

	if state == WebSocketPeer.STATE_CLOSED:
		_handle_closed(generation)
		return false

	if _connected and _options.heartbeat_interval_ms > 0:
		_check_heartbeat()
	return true

## The socket just reached OPEN: reports the connection, flushes the queue and starts the
## heartbeat. False when a listener disconnected or replaced the socket meanwhile.
func _handle_opened(generation: int) -> bool:
	_logger.log('Connection established successfully!')
	_connected = true
	_reconnect_attempts = 0
	_current_reconnect_interval = _options.reconnect_interval_ms
	connected.emit()
	if !_is_current(generation):
		return false
	_flush_queue()
	_start_heartbeat()
	return true


## Reads whatever is available, even in a closing state. (The engine itself discards frames
## that arrive in the same poll as the peer's close.) False when a listener disconnected or
## replaced the socket meanwhile.
func _read_packets(generation: int) -> bool:
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if _socket.was_string_packet():
			var json_str := LFText.decode_utf8_lossy(packet)
			if log_traffic:
				_logger.log('Received text message: %s' % json_str)
			_handle_message(json_str)
		else:
			if log_traffic:
				_logger.log('Received binary message, size: %d bytes' % packet.size())
			_handle_binary_message(packet)
		# A listener may have disconnected or replaced the socket.
		if !_is_current(generation):
			return false
	return true


## The socket is CLOSED: reports which of the three ways it got there this was.
func _handle_closed(generation: int) -> void:
	if _connected:
		_logger.log('Connection closed (code %d)' % _socket.get_close_code())
		_connected = false
		_stop_reconnecting_if_sent_away()
		_fail_pending_requests()
		disconnected.emit()
	# Opened and closed within one poll (the handshake answer arrived together with a
	# frame over `buffer_size`, which closes with 1009): the server did accept, so it
	# reports as a connection that opened and closed. A close code only exists once the
	# handshake completed; queued messages stay queued for the next connection.
	elif _socket.get_close_code() != _NO_CLOSE_CODE:
		_logger.log('Connection opened and closed in one poll (code %d)' % _socket.get_close_code())
		_stop_reconnecting_if_sent_away()
		_reconnect_attempts = 0
		_current_reconnect_interval = _options.reconnect_interval_ms
		connected.emit()
		if !_is_current(generation):
			return
		_fail_pending_requests()
		disconnected.emit()
	# An attempt that never opened: closed after CONNECTING, or already closed on the
	# very first poll (a refused connection, e.g. the server isn't listening yet).
	else:
		_logger.log('Connection failed - never reached OPEN (code %d)' % _socket.get_close_code())
		_trigger_error('Connection failed')
	if _should_reconnect and _is_current(generation):
		_schedule_reconnect()


## A server that closed the connection with DISCONNECTED_BY_SERVER_CODE meant it: turns
## reconnecting off, as disconnect_from_server() does (connect_to_server() or
## force_reconnect() turn it back on).
func _stop_reconnecting_if_sent_away() -> void:
	if _socket.get_close_code() == DISCONNECTED_BY_SERVER_CODE:
		_logger.log('The server disconnected this client on purpose -- not reconnecting')
		_should_reconnect = false

## Returns the close code of the last connection that closed (e.g. 1000 for a normal
## close, [constant DISCONNECTED_BY_SERVER_CODE] when the server sent this client away),
## or -1 while no close code is known (connecting, open, or never connected).
func get_close_code() -> int:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		return _NO_CLOSE_CODE
	return _socket.get_close_code()

func _is_current(generation: int) -> bool:
	return _socket != null and generation == _poll_generation and !_intentionally_disconnected

func _handle_message(json_str: String) -> void:
	var parsed: Variant = LFJson.parse_object(json_str)
	if parsed == null:
		_warn_from_server('Ignoring a text frame that is not a JSON object', ': %s' % _preview(json_str))
		return
	var message: Dictionary = parsed
	if log_traffic:
		_logger.log('Parsed message', message)

	# Frames come from the network: a field of the wrong type is treated as absent,
	# never trusted as a String.
	var type_name := _string_field(message, TYPE_KEY)
	var event_name := _string_field(message, EVENT_KEY)
	if event_name.is_empty():
		event_name = type_name

	if type_name == PONG_TYPE:
		if log_traffic:
			_logger.log('Received pong, heartbeat acknowledged')
		_waiting_for_pong = false
	if type_name == RESPONSE_TYPE:
		var request_id := _string_field(message, ID_KEY)
		if log_traffic:
			_logger.log('Received response for request id: %s' % request_id)
		if !request_id.is_empty() and _pending_requests.has(request_id):
			# Answered: forget it now, so a close before the waiting request resumes
			# (or a duplicate response) cannot overwrite the answer.
			var pending: Dictionary = _pending_requests[request_id]
			_pending_requests.erase(request_id)
			pending[_CALLBACK_KEY].call(message.get(DATA_KEY))
		else:
			_warn_from_server('Received response for unknown request id', ': %s' % _preview(request_id))
		return

	if !_wildcard_listeners.is_empty():
		if log_traffic:
			_logger.log('Triggering %d wildcard listener(s) for event: %s' % [_wildcard_listeners.size(), event_name])
		var data: Variant = message.get(DATA_KEY, message)
		for entry: Array in _wildcard_listeners.duplicate():
			if _is_listener_gone(entry[0], _wildcard_listeners, entry):
				continue
			if !entry[1] or data is Dictionary:
				entry[0].call(event_name, data)
	if event_name != '' and _listeners.has(event_name):
		if log_traffic:
			_logger.log('Triggering %d listener(s) for event: %s' % [_listeners[event_name].size(), event_name])
		var data: Variant = message.get(DATA_KEY, message)
		var entries: Array = _listeners[event_name]
		for entry: Array in entries.duplicate():
			if _is_listener_gone(entry[0], entries, entry):
				continue
			if !entry[1] or data is Dictionary:
				entry[0].call(data)


## Logs a warning caused by what the server sent: `kind` plus `detail` for the first
## _WARNINGS_IN_FULL of that kind, then only a running count at every
## _WARNING_SUMMARY_EVERY, so a server sending junk cannot flood the log.
func _warn_from_server(kind: String, detail: String) -> void:
	var count := int(_warning_counts.get(kind, 0)) + 1
	_warning_counts[kind] = count
	if count < _WARNINGS_IN_FULL:
		_logger.warning(kind + detail)
	elif count == _WARNINGS_IN_FULL:
		_logger.warning('%s%s (further ones are only counted, reported every %d)' % [kind, detail, _WARNING_SUMMARY_EVERY])
	elif count % _WARNING_SUMMARY_EVERY == 0:
		_logger.warning('%s: %d so far' % [kind, count])


## Server-sent `text` made safe to log: at most _PREVIEW_CHARS characters, quoted, with
## backslashes, quotes and control characters escaped, and the full length when cut.
static func _preview(text: String) -> String:
	var shown := text.substr(0, _PREVIEW_CHARS)
	var escaped := PackedStringArray()
	for i in shown.length():
		var c := shown.unicode_at(i)
		if c < _FIRST_PRINTABLE or (c >= _DEL and c <= _LAST_C1_CONTROL):
			escaped.append('\\u%04x' % c)
		elif shown[i] == '\\' or shown[i] == '"':
			escaped.append('\\' + shown[i])
		else:
			escaped.append(shown[i])
	var quoted := '"%s"' % ''.join(escaped)
	if text.length() > _PREVIEW_CHARS:
		quoted += '... (%d characters)' % text.length()
	return quoted


## True when `callback`'s object was freed (e.g. a node freed without calling off_event);
## removes `entry` from `entries` so it is skipped from now on.
static func _is_listener_gone(callback: Callable, entries: Array, entry: Variant) -> bool:
	if callback.is_valid():
		return false
	entries.erase(entry)
	return true

## message[key] when it is a String, "" otherwise.
static func _string_field(message: Dictionary, key: String) -> String:
	var value: Variant = message.get(key)
	return value if value is String else ''

## Resolves every pending request_message with null (the connection is gone).
func _fail_pending_requests() -> void:
	if _pending_requests.is_empty():
		return
	var pending := _pending_requests
	_pending_requests = {}
	for request_id: Variant in pending:
		pending[request_id][_CALLBACK_KEY].call(null)

func _handle_binary_message(packet: PackedByteArray) -> void:
	if packet.size() < _BINARY_LENGTH_BYTES:
		_warn_from_server('Binary message too short', ' (size: %d)' % packet.size())
		return
	var event_length := packet.decode_u32(0)
	if packet.size() < _BINARY_LENGTH_BYTES + event_length:
		_warn_from_server('Binary message malformed', ' - expected at least %d bytes, got %d' % [_BINARY_LENGTH_BYTES + event_length, packet.size()])
		return
	var event := LFText.decode_utf8_lossy(packet.slice(_BINARY_LENGTH_BYTES, _BINARY_LENGTH_BYTES + event_length))
	var data := packet.slice(_BINARY_LENGTH_BYTES + event_length)
	if log_traffic:
		_logger.log('Binary message event: %s, data size: %d bytes' % [event, data.size()])
	if _binary_listeners.has(event):
		if log_traffic:
			_logger.log('Triggering %d listener(s) for binary event: %s' % [_binary_listeners[event].size(), event])
		var callbacks: Array = _binary_listeners[event]
		for callback: Callable in callbacks.duplicate():
			if _is_listener_gone(callback, callbacks, callback):
				continue
			callback.call(data)
	elif log_traffic:
		_logger.log('No listeners registered for binary event: %s' % event)

func _start_heartbeat() -> void:
	if _options.heartbeat_interval_ms <= 0:
		_logger.log('Heartbeat disabled (interval: 0)')
		return
	_logger.log('Starting heartbeat with interval: %dms' % _options.heartbeat_interval_ms)
	_last_heartbeat_time = Time.get_ticks_msec()
	_waiting_for_pong = false

func _check_heartbeat() -> void:
	var now := Time.get_ticks_msec()

	if _waiting_for_pong:
		if now - _ping_sent_at >= _options.heartbeat_timeout_ms:
			_logger.warning('Heartbeat timeout, no pong received. Reconnecting...')
			_drop_dead_connection()
		return

	if now - _last_heartbeat_time >= _options.heartbeat_interval_ms:
		if log_traffic:
			_logger.log('Sending heartbeat ping')
		send_message({ TYPE_KEY: PING_TYPE })
		_waiting_for_pong = true
		_ping_sent_at = now
		_last_heartbeat_time = now

## The peer stopped answering: close it, report the loss, and reconnect (subject to
## auto_reconnect and the attempt limit). Unlike disconnect_from_server(), this is not
## a caller's decision, so it never suppresses reconnection.
func _drop_dead_connection() -> void:
	_waiting_for_pong = false
	_poll_generation += 1 # retire the current poll loop
	_socket.close()
	var generation := _reconnect_generation
	if _connected:
		_connected = false
		_fail_pending_requests()
		disconnected.emit()
	# A disconnected handler that connected or disconnected has decided what happens next.
	if generation == _reconnect_generation:
		_schedule_reconnect()

func _schedule_reconnect() -> void:
	if !_options.auto_reconnect:
		_logger.log('Auto-reconnect disabled, not attempting to reconnect')
		return
	if _options.max_reconnect_attempts > 0 and _reconnect_attempts >= _options.max_reconnect_attempts:
		_logger.error('Max reconnection attempts reached (%d attempts)' % _reconnect_attempts)
		_trigger_error('Max reconnection attempts reached')
		return
	_reconnect_attempts += 1
	_logger.log('Reconnection attempt #%d' % _reconnect_attempts)
	reconnect_scheduled.emit(_reconnect_attempts)

	if LFUtils.tree_root == null:
		_logger.error('Cannot schedule reconnect, SceneTree not available')
		return

	var wait_ms := clampi(_current_reconnect_interval, _MIN_RECONNECT_DELAY_MS, maxi(_options.max_reconnect_interval_ms, _MIN_RECONNECT_DELAY_MS))
	var delay_ms := maxi(_jittered_ms(wait_ms, _options.rng), _MIN_RECONNECT_DELAY_MS)
	_logger.log('Scheduling reconnection in %dms (attempt %d/%s)...' % [
		delay_ms,
		_reconnect_attempts,
		'∞' if _options.max_reconnect_attempts == 0 else str(_options.max_reconnect_attempts)
	])
	# Exponential backoff: the next attempt waits longer, up to the cap.
	# Written as `>= 1.0` so NaN falls to 1.0 too; it would otherwise zero every later wait.
	var decay := _options.reconnect_decay if _options.reconnect_decay >= 1.0 else 1.0
	_current_reconnect_interval = int(min(wait_ms * decay, _options.max_reconnect_interval_ms))
	_reconnect_generation += 1
	_redial_after(weakref(self), _reconnect_generation, delay_ms)

## `ms` scaled by a random factor in [_JITTER_MIN, _JITTER_MAX], so many clients that lost the same
## server do not all redial at the same moment. Draws from `rng`, or from the global
## generator when it is null.
static func _jittered_ms(ms: int, rng: RandomNumberGenerator = null) -> int:
	var factor := rng.randf_range(_JITTER_MIN, _JITTER_MAX) if rng != null else randf_range(_JITTER_MIN, _JITTER_MAX)
	return int(round(ms * factor))

## Redials after `delay_ms` if the socket still exists and the timer is still current.
## Holds the socket only weakly, so a socket its owner dropped stops reconnecting.
static func _redial_after(ref: WeakRef, generation: int, delay_ms: int) -> void:
	LFUtils.create_timer(delay_ms, func() -> void:
		var sock: LFSocket = ref.get_ref()
		if sock != null:
			sock._redial(generation))

func _redial(generation: int) -> void:
	# A connect, disconnect or newer reconnect since scheduling makes this timer stale.
	if generation != _reconnect_generation or !_should_reconnect:
		return
	_socket = WebSocketPeer.new()
	_attempt_connection()

func _trigger_error(msg: String) -> void:
	_logger.log('Error occurred: %s' % msg)
	error_occurred.emit(msg)
