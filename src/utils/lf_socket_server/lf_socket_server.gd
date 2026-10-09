## A WebSocket server that several clients (such as [LFSocket]) can connect to at once, up
## to [member max_peers].
##
## Each client that connects (a "peer") gets an integer peer id: 1, 2, 3 and so on, never
## reused by this server object. Messages are JSON objects in both directions. Call [method listen] to start; the
## server then polls itself once per SceneTree frame, so nothing needs to call a `poll()`
## method. It answers [LFSocket]'s heartbeat pings by itself, and closes a peer it has not
## heard from in [member idle_timeout_ms]. With a [TLSOptions] passed to [method listen]
## it serves `wss://` (encrypted) instead of `ws://`.[br][br]
## Keep a reference to it: a server nobody holds is freed, which closes its port and every
## connection.
class_name LFSocketServer
extends RefCounted

## Default [member inbound_buffer_size], in bytes (64 KiB).
const DEFAULT_INBOUND_BUFFER_SIZE := 1 << 16
## Default [member outbound_buffer_size], in bytes (4 MiB).
const DEFAULT_OUTBOUND_BUFFER_SIZE := 1 << 22
## Default [member max_peers].
const DEFAULT_MAX_PEERS := 64
## Default [member max_peers_per_address].
const DEFAULT_MAX_PEERS_PER_ADDRESS := 8
## Default [member max_pending_handshakes].
const DEFAULT_MAX_PENDING_HANDSHAKES := 32
## Default [member max_pending_handshakes_per_address].
const DEFAULT_MAX_PENDING_HANDSHAKES_PER_ADDRESS := 4
## Default [member packets_per_poll].
const DEFAULT_PACKETS_PER_POLL := 64
## Default [member handshake_timeout_ms], in milliseconds.
const DEFAULT_HANDSHAKE_TIMEOUT_MS := 3000
## Default [member disconnect_flush_timeout_ms], in milliseconds.
const DEFAULT_DISCONNECT_FLUSH_TIMEOUT_MS := 2000
## Default [member idle_timeout_ms], in milliseconds: twice [LFSocket]'s default
## heartbeat interval, so a live default client sends a ping well within it (unless its
## frames or the network stall for more than 30 seconds).
const DEFAULT_IDLE_TIMEOUT_MS := 60000
## Default `ip` of [method free_port]: the loopback address.
const DEFAULT_FREE_PORT_IP := '127.0.0.1'
## Default `host` of [method listen]: every network interface.
const DEFAULT_LISTEN_HOST := '*'

## Largest message, in bytes, a peer can send (default 64 KiB). Every accepted peer reserves at least this
## much memory up front, so keep it small; a larger frame closes that peer with code 1009. Read at
## each accept, so a change affects only peers accepted afterwards. `0` or less uses the default.
var inbound_buffer_size := DEFAULT_INBOUND_BUFFER_SIZE
## Largest message, in bytes, the server can send to one peer (default 4 MiB), e.g. a
## large state snapshot.
## Memory is used only as messages are queued. Read at each accept. `0` or less uses the default.
var outbound_buffer_size := DEFAULT_OUTBOUND_BUFFER_SIZE
## Most open peers (handshake finished) held at once. While this many are open a new
## connection is closed as soon as it is accepted; a handshake that finishes while the
## server is full is closed without [signal peer_connected]. Connections still in their
## handshake are counted by [member max_pending_handshakes] instead, so they cannot take an
## open peer's slot. 0 means unlimited.
var max_peers := DEFAULT_MAX_PEERS
## Most open peers one remote IP address (see [method peer_address]) may hold at once;
## one more from that address is closed as soon as it is accepted, or, when its handshake
## finishes while the address is at the cap, closed without [signal peer_connected]. It
## keeps one machine from taking every slot of [member max_peers]. It does not stop an
## attacker using many addresses, and behind a reverse proxy or NAT every client shares one
## address, so there it limits all clients together: raise it (or set it to 0, meaning
## unlimited). Negative values count as 0.
var max_peers_per_address := DEFAULT_MAX_PEERS_PER_ADDRESS:
	set(value):
		max_peers_per_address = maxi(value, 0)
## Most connections still in their TLS or WebSocket handshake held at once, from all
## addresses together; a connection beyond it is closed as soon as it is accepted. This
## bounds what connections that never finish their handshake can hold (each for up to
## [member handshake_timeout_ms]). 0 means unlimited.
var max_pending_handshakes := DEFAULT_MAX_PENDING_HANDSHAKES
## Most connections still in their handshake held at once from one remote IP address (see
## [method peer_address]); one more from that address is closed as soon as it is accepted.
## It keeps a single machine from filling [member max_pending_handshakes]. It does not stop
## an attacker using many addresses, and behind a reverse proxy every connection has the
## proxy's address, so there it limits all clients together: raise it (or set it to 0,
## meaning unlimited) when the server runs behind one.
var max_pending_handshakes_per_address := DEFAULT_MAX_PENDING_HANDSHAKES_PER_ADDRESS
## Origins allowed to open a WebSocket, e.g. `['https://game.example']`; empty (the
## default) checks nothing. **Off by default, so any web page a visitor opens can make that
## visitor's browser connect here (cross-site WebSocket hijacking): a server that
## authenticates by cookie or by being on the visitor's own network, and a server meant for
## browser clients in general, should set this.** Each entry is compared with the request's
## `Origin` header as a whole, ignoring case and a trailing `/`
## (`scheme://host[:port]`). A request whose `Origin` is not listed (or, with
## [member allow_missing_origin] off, has none) gets `403 Forbidden` and never becomes a
## peer. The header is a browser's promise: a native client can send any value, so this
## stops other web pages, not other programs.[br][br]
## Read by [method listen]. Godot's `WebSocketPeer` does not expose the request headers, so
## with this set the server reads the request itself and relays each connection's bytes to
## the engine's WebSocket through a private loopback socket. That costs one more local
## socket pair per connection, up to a frame of latency each way, and moves at most
## about 256 KiB per frame in each direction per connection. Nothing else on the machine
## can use that socket to skip the check without already knowing a connection's local port.
var allowed_origins := PackedStringArray()
## Whether a handshake without an `Origin` header passes when [member allowed_origins] is
## set. Browsers always send one; native clients such as [LFSocket] on desktop do not, so
## the default `true` lets them in. Set `false` for a server only browsers should reach.
var allow_missing_origin := true
## Most packets read from one peer in one poll (one frame); the rest wait for the next
## poll, which bounds how much one flooding peer adds to a frame (each packet can still
## be up to [member inbound_buffer_size]). 0 means unlimited.
var packets_per_poll := DEFAULT_PACKETS_PER_POLL
## A connection that has not completed its WebSocket handshake this many milliseconds
## after it was accepted is closed, freeing its slot. 0 means no limit. (The handshake is
## the short exchange that turns a plain TCP connection into a WebSocket.)
var handshake_timeout_ms := DEFAULT_HANDSHAKE_TIMEOUT_MS
## Longest time, in milliseconds, [method disconnect_peer] or a flushing [method stop]
## waits for a peer's queued messages to go out before closing the connection anyway.
var disconnect_flush_timeout_ms := DEFAULT_DISCONNECT_FLUSH_TIMEOUT_MS
## An open peer that has sent nothing (no message, no heartbeat ping) for this many
## milliseconds is closed and reported with [signal peer_disconnected], so a client whose
## machine or network vanished without closing does not hold its slot forever. 0 means no
## limit. A client must send something more often than this: [LFSocket]'s heartbeat does
## by default; one with its heartbeat turned off is dropped after this long without
## messages.
var idle_timeout_ms := DEFAULT_IDLE_TIMEOUT_MS

## After a closing peer's send queue empties, the frame being written may still be in
## flight (the engine reports only queued frames), so the close waits this much longer.
const _CLOSE_LINGER_MS := 100
## The id the first accepted peer gets; later ones count up from it.
const _FIRST_PEER_ID := 1
## Most connections taken from the listening socket in one poll; the rest wait for the
## next poll. Refusing one costs little, so this is high enough that a burst of refused
## connections does not keep a real client waiting in the operating system's queue.
const _MAX_ACCEPTS_PER_POLL := 256
## Port number that asks the operating system for any free port.
const _ANY_PORT := 0
## Lowest TCP port number.
const _MIN_PORT := 1
## Highest TCP port number.
const _MAX_PORT := 65535
## Loopback address the origin check's private socket binds.
const _GATE_HOST := '127.0.0.1'
## The wildcard bind addresses [method is_port_free] always probes.
const _WILDCARD_ADDRESSES: Array[String] = ['*', '0.0.0.0']

var _tcp := TCPServer.new()
var _peers: Dictionary = {}  # peer_id (int) -> WebSocketPeer
## Accepted peers still in their TLS handshake, before they get a WebSocketPeer.
var _tls_pending: Dictionary = {}  # peer_id (int) -> StreamPeerTLS
## The remote address of every accepted peer, read when it was accepted.
var _addresses: Dictionary = {}  # peer_id (int) -> String
## When each open peer last sent a frame (msec).
var _last_heard: Dictionary = {}  # peer_id (int) -> int
## Set by listen(); null serves plain ws://.
var _tls_options: TLSOptions = null
## Accept time (msec) of each peer still mid-handshake (TLS or WebSocket).
var _handshake_started: Dictionary = {}  # peer_id (int) -> int
## How many peers in _handshake_started each remote address has.
var _pending_by_address: Dictionary = {}  # address (String) -> int
## Peers that reached STATE_OPEN; only these are reported as disconnected. Tracked
## separately because a server-side close passes through CLOSING, never OPEN -> CLOSED.
var _opened_peers: Dictionary = {}  # peer_id (int) -> true
## How many peers in _opened_peers each remote address has.
var _open_by_address: Dictionary = {}  # address (String) -> int
## Peers a disconnect_peer() is closing once their send queue drains.
var _closing: Dictionary = {}  # peer_id (int) -> _ClosingPeer
## The origin check's relays, by peer id; empty when [member allowed_origins] was empty
## at [method listen].
var _relays: Dictionary = {}  # peer_id (int) -> _OriginRelay
## Loopback listener the relays hand the engine's WebSocket its end of the connection on.
var _gate := TCPServer.new()
## Whether [member allowed_origins] was non-empty when [method listen] ran.
var _origin_check := false
var _next_peer_id := _FIRST_PEER_ID
var _listening := false
## True while a per-frame poll loop runs. A stop() then listen() inside one frame keeps
## that loop rather than starting a second one.
var _polling := false

## A client finished connecting (its WebSocket handshake completed); it can now be sent
## messages. A raw TCP connection that never completes the handshake doesn't fire it.
signal peer_connected(peer_id: int)
## A peer that had finished connecting closed (by either side), went silent for longer
## than [member idle_timeout_ms], or was closed by [method stop]. Its id is no longer
## valid afterwards.
signal peer_disconnected(peer_id: int)
## A peer sent a JSON object. Other frames (binary, invalid JSON, arrays, plain values)
## and heartbeat pings are dropped. The fields of `data` can hold any JSON type, so check
## a field's type before using it.
signal message_received(peer_id: int, data: Dictionary)


## Reads one connection's HTTP upgrade request, checks its `Origin`, and then copies bytes
## between the real connection and a loopback connection whose far end the engine's
## WebSocket owns (Godot does not expose a server-side request's headers).
class _OriginRelay extends RefCounted:
	enum State { SNIFFING, PIPING, CLOSED }

	## Largest request head read before the connection is refused.
	const MAX_HEAD_BYTES := 8192
	## Bytes buffered per direction before reading more from the source.
	const CHUNK_BYTES := 65536
	## Copy rounds per frame and direction.
	const ROUNDS_PER_FRAME := 4
	const REFUSAL := 'HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
	const MALFORMED := 'HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'

	var state := State.SNIFFING
	## The real connection (TCP or TLS).
	var outer: StreamPeer
	## This side of the loopback connection.
	var inner := StreamPeerTCP.new()
	## The far end of `inner`, once the private listener accepted it; set by the server.
	var accepted: StreamPeerTCP = null
	## The local port of `inner`, which the listener's accepted connection reports as its remote port.
	var inner_port := 0
	var _head := PackedByteArray()
	var _to_inner := PackedByteArray()
	var _to_outer := PackedByteArray()
	var _gate_port: int

	func _init(stream: StreamPeer, gate_port: int) -> void:
		outer = stream
		_gate_port = gate_port

	func close() -> void:
		state = State.CLOSED
		if outer is StreamPeerTLS:
			(outer as StreamPeerTLS).disconnect_from_stream()
		elif outer is StreamPeerTCP:
			(outer as StreamPeerTCP).disconnect_from_host()
		inner.disconnect_from_host()
		if accepted != null:
			accepted.disconnect_from_host()

	func step(allowed: PackedStringArray, allow_missing: bool) -> void:
		if state == State.CLOSED:
			return
		outer.poll()
		if !_outer_connected():
			close()
			return
		if state == State.SNIFFING:
			_sniff(allowed, allow_missing)
		elif state == State.PIPING:
			_pipe()

	func _outer_connected() -> bool:
		if outer is StreamPeerTLS:
			return (outer as StreamPeerTLS).get_status() == StreamPeerTLS.STATUS_CONNECTED
		return (outer as StreamPeerTCP).get_status() == StreamPeerTCP.STATUS_CONNECTED

	func _sniff(allowed: PackedStringArray, allow_missing: bool) -> void:
		var n := mini(outer.get_available_bytes(), MAX_HEAD_BYTES + 4 - _head.size())
		if n > 0:
			_head.append_array(outer.get_data(n)[1])
		var text := _head.get_string_from_ascii()
		var end := text.find('\r\n\r\n')
		if end == -1:
			if _head.size() > MAX_HEAD_BYTES:
				_refuse(MALFORMED)
			return
		if !origin_allowed(text.substr(0, end), allowed, allow_missing):
			_refuse(REFUSAL)
			return
		_to_inner = _head
		if inner.connect_to_host(_GATE_HOST, _gate_port) != OK:
			close()
			return
		inner_port = inner.get_local_port()
		state = State.PIPING

	func _refuse(response: String) -> void:
		outer.put_partial_data(response.to_ascii_buffer())
		close()

	func _pipe() -> void:
		inner.poll()
		var status := inner.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTING:
			return
		if status != StreamPeerTCP.STATUS_CONNECTED:
			# The engine's WebSocket closed its end: pass on what it said last, then close.
			_to_outer = _copy(inner, outer, _to_outer, true)
			if _to_outer.is_empty():
				close()
			return
		_to_inner = _copy(outer, inner, _to_inner, false)
		_to_outer = _copy(inner, outer, _to_outer, false)

	## Copies bytes from `src` to `dst` through `buffer`, returning what is still unsent.
	static func _copy(src: StreamPeer, dst: StreamPeer, buffer: PackedByteArray, src_closed: bool) -> PackedByteArray:
		for _round in ROUNDS_PER_FRAME:
			if buffer.size() < CHUNK_BYTES and !src_closed:
				var n := mini(src.get_available_bytes(), CHUNK_BYTES)
				if n > 0:
					buffer.append_array(src.get_data(n)[1])
			if buffer.is_empty():
				break
			var result := dst.put_partial_data(buffer)
			var sent: int = result[1]
			if result[0] != OK or sent <= 0:
				break
			buffer = buffer.slice(sent)
		return buffer

	## Whether the request `head` (everything before the blank line) passes the origin
	## check: its single `Origin` header is in `allowed` (ignoring case and a trailing
	## slash); a missing one passes only with `allow_missing`; two are refused.
	static func origin_allowed(head: String, allowed: PackedStringArray, allow_missing: bool) -> bool:
		var found: Array[String] = []
		for line in head.split('\r\n'):
			if line.to_lower().begins_with('origin:'):
				found.append(line.substr(7).strip_edges())
		if found.is_empty():
			return allow_missing
		if found.size() > 1:
			return false
		var origin := found[0].to_lower().trim_suffix('/')
		for entry in allowed:
			if entry.to_lower().strip_edges().trim_suffix('/') == origin:
				return true
		return false


class _ClosingPeer:
	var deadline_ms: int
	## When the send queue was first seen empty; -1 until then.
	var drained_at_ms := -1


## Returns a TCP port on `ip` that the operating system reported free just now (it binds
## port 0 and reads back the port it was given), or -1 when nothing can be bound on `ip`
## (e.g. an address this machine doesn't have). Another process may take the port before
## you bind it.
static func free_port(ip := DEFAULT_FREE_PORT_IP) -> int:
	var probe := TCPServer.new()
	if probe.listen(_ANY_PORT, ip) != OK:
		return -1
	var port := probe.get_local_port()
	probe.stop()
	return port


## Returns `true` when TCP `port` could be bound just now on the wildcard addresses and on
## every local address that is not link-local (`LFOS.local_addresses()`); a listener on a
## link-local address is not detected. A listener on one address does not stop a bind on another,
## so a single wildcard probe would miss a service on `127.0.0.1` or a LAN address. An
## address that cannot be bound at all right now is skipped. Another process may take the
## port right after this returns. `false` for a port outside 1-65535.
static func is_port_free(port: int) -> bool:
	if port < _MIN_PORT or port > _MAX_PORT:
		return false
	var addresses: Array[String] = []
	addresses.append_array(_WILDCARD_ADDRESSES)
	addresses.append_array(LFOS.local_addresses())
	for address in addresses:
		var probe := TCPServer.new()
		var bound := probe.listen(port, address) == OK
		probe.stop()
		if !bound and free_port(address) != -1:
			return false
	return true


## Starts accepting clients on `port` and starts the per-frame poll loop. Returns `OK`, or
## the error from binding the port (e.g. `ERR_ALREADY_IN_USE` when another program holds
## it) or `ERR_INVALID_PARAMETER` for a port outside 0-65535 (0 picks a free one), in
## which case the server stays stopped. Calling it while already listening returns
## `ERR_ALREADY_IN_USE` and changes nothing; call [method stop] first. Returns
## `ERR_UNCONFIGURED` when the engine's main loop is not a SceneTree (nothing could poll
## the server). The default `host`
## `'*'` listens on every network interface, so other machines can connect; pass
## `'127.0.0.1'` to accept only clients on this machine.[br][br]
## With `tls_options` (from `TLSOptions.server(key, certificate)`) every connection must
## complete a TLS handshake first, so clients connect with `wss://` and the traffic is
## encrypted; a plain `ws://` client fails to connect. The TLS handshake must finish within
## [member handshake_timeout_ms] as well, and runs on the main thread (its key exchange
## costs some milliseconds per connection).
func listen(port: int, host: String = DEFAULT_LISTEN_HOST, tls_options: TLSOptions = null) -> Error:
	if _listening:
		return ERR_ALREADY_IN_USE
	if port < _ANY_PORT or port > _MAX_PORT or (tls_options != null and !tls_options.is_server()):
		return ERR_INVALID_PARAMETER
	if LFUtils.tree_root == null:
		return ERR_UNCONFIGURED
	var err := _tcp.listen(port, host)
	if err != OK:
		return err
	_origin_check = !allowed_origins.is_empty()
	if _origin_check and _gate.listen(_ANY_PORT, _GATE_HOST) != OK:
		_tcp.stop()
		return ERR_CANT_CREATE
	_tls_options = tls_options
	_listening = true
	_start_polling()
	return OK


## Stops listening and polling, lets go of every peer and emits [signal peer_disconnected]
## for each open one, all at once: the port is free and connected_peer_ids() is empty when
## this returns. With `flush` (the default) each open peer's queued messages still go out
## before its connection closes, at most disconnect_flush_timeout_ms later, even if the
## server is freed meanwhile, so a goodbye broadcast just before stop() arrives unless the
## queue takes longer than that to drain. Without
## it every connection closes at once and queued messages are lost. Safe to call from
## any of this server's signal handlers.
func stop(flush := true) -> void:
	_listening = false
	_tcp.stop()
	var open_ids := _opened_peers.keys()
	var sockets := _peers.values()
	var peers_by_id := _peers.duplicate()
	for tls: StreamPeerTLS in _tls_pending.values():
		tls.disconnect_from_stream()
	_peers.clear()
	_tls_pending.clear()
	_addresses.clear()
	_last_heard.clear()
	_opened_peers.clear()
	_open_by_address.clear()
	# A draining socket's bytes still travel through its origin relay, so those relays live on
	# (stepped by the flush) and every other relay closes now.
	var draining_relays: Array = []
	for peer_id: int in _relays.keys():
		var relay: _OriginRelay = _relays[peer_id]
		var socket: WebSocketPeer = peers_by_id.get(peer_id)
		if flush and socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			draining_relays.append(relay)
		else:
			relay.close()
	_relays.clear()
	_gate.stop()
	_handshake_started.clear()
	_pending_by_address.clear()
	_closing.clear()
	var draining: Array[WebSocketPeer] = []
	for socket: WebSocketPeer in sockets:
		if flush and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			draining.append(socket)
		else:
			socket.close()
	if !draining.is_empty():
		@warning_ignore("missing_await")
		_flush_then_close(draining, disconnect_flush_timeout_ms, draining_relays, allowed_origins, allow_missing_origin)
	for peer_id: Variant in open_ids:
		peer_disconnected.emit(peer_id)


## Returns `true` between a successful [method listen] and [method stop].
func is_listening() -> bool:
	return _listening


## The TCP port this server is bound to while listening, or 0 when it is not. After
## [code]listen(0)[/code] it is the port the operating system picked, so a caller can bind
## any free port and then read it back, with no window for another process to take it.
func get_local_port() -> int:
	return _tcp.get_local_port() if _listening else 0


## Returns the ids of the peers a message can be sent to now: finished connecting and not
## being disconnected.
func connected_peer_ids() -> Array:
	var ids := []
	for peer_id: Variant in _peers.keys():
		if _is_sendable(peer_id):
			ids.append(peer_id)
	return ids


## Returns the IP address the peer's TCP connection comes from, which is what a server
## rate-limits or bans by (see [method LFStrikeGuard.address_key]). Known from the moment
## the connection is accepted; `''` for an unknown id. Behind a reverse proxy or a load
## balancer this is the proxy's address for every peer, not the player's.
func peer_address(peer_id: int) -> String:
	return _addresses.get(peer_id, '')


## Sends `data` as JSON text to one peer. Returns `OK`, `ERR_DOES_NOT_EXIST` for an
## unknown id, or `ERR_UNAVAILABLE` for a peer still connecting or being disconnected.
func send_to(peer_id: int, data: Dictionary) -> Error:
	if !_peers.has(peer_id):
		return ERR_DOES_NOT_EXIST
	return send_text_to(peer_id, JSON.stringify(data))


## Sends text that is already encoded (e.g. with `JSON.stringify`) to one peer, so a
## payload several peers get is encoded only once. Returns the same errors as [method send_to].
func send_text_to(peer_id: int, text: String) -> Error:
	if !_peers.has(peer_id):
		return ERR_DOES_NOT_EXIST
	if !_is_sendable(peer_id):
		return ERR_UNAVAILABLE
	return (_peers[peer_id] as WebSocketPeer).send_text(text)


## Sends `data` to every peer in [method connected_peer_ids], encoding it only once.
func broadcast(data: Dictionary) -> void:
	var text := JSON.stringify(data)
	for peer_id: Variant in connected_peer_ids():
		send_text_to(peer_id, text)


## Closes that peer's connection once the messages already sent to it have gone out (at
## most [member disconnect_flush_timeout_ms] later), so a "goodbye" sent just before still
## arrives unless the queue takes longer than that to drain. From this call on the peer is left out of [method connected_peer_ids], sends to
## it fail and its incoming messages are dropped; [signal peer_disconnected] fires once the
## close completes. The close carries [constant LFSocket.DISCONNECTED_BY_SERVER_CODE], so
## an [LFSocket] client does not reconnect on its own. A peer that has not finished
## connecting is closed at once instead, without that code or a signal. An unknown id is
## ignored.
func disconnect_peer(peer_id: int) -> void:
	if _tls_pending.has(peer_id):
		(_tls_pending[peer_id] as StreamPeerTLS).disconnect_from_stream()
		_forget(peer_id)
		return
	if !_peers.has(peer_id) or _closing.has(peer_id):
		return
	var socket: WebSocketPeer = _peers[peer_id]
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		socket.close()
		return
	var closing := _ClosingPeer.new()
	closing.deadline_ms = Time.get_ticks_msec() + disconnect_flush_timeout_ms
	_closing[peer_id] = closing


func _is_sendable(peer_id: int) -> bool:
	return !_closing.has(peer_id) \
		and (_peers[peer_id] as WebSocketPeer).get_ready_state() == WebSocketPeer.STATE_OPEN


## A server freed while listening closes its port and every peer. Being deleted, it can't
## call its own methods or emit signals, so no peer_disconnected is reported.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_tcp.stop()
		for socket: WebSocketPeer in _peers.values():
			socket.close()
		for tls: StreamPeerTLS in _tls_pending.values():
			tls.disconnect_from_stream()
		for relay: _OriginRelay in _relays.values():
			relay.close()
		_gate.stop()


func _start_polling() -> void:
	if _polling or LFUtils.tree_root == null:
		return
	_polling = true
	@warning_ignore("missing_await")
	LFUtils.poll_each_frame(self, &'_poll_step')


## One frame of the poll loop; false (ending the loop) once the server stopped.
func _poll_step() -> bool:
	if _listening:
		var accepts := 0
		while accepts < _MAX_ACCEPTS_PER_POLL and _tcp.is_connection_available():
			_accept_pending()
			accepts += 1
		_poll_peers()
	_polling = _listening
	return _polling


func _accept_pending() -> void:
	var tcp_peer := _tcp.take_connection()
	if tcp_peer == null:
		return
	var address := tcp_peer.get_connected_host()
	if (max_peers > 0 and _opened_peers.size() >= max_peers) \
			or (max_peers_per_address > 0 and int(_open_by_address.get(address, 0)) >= max_peers_per_address) \
			or (max_pending_handshakes > 0 and _handshake_started.size() >= max_pending_handshakes) \
			or (max_pending_handshakes_per_address > 0 \
				and int(_pending_by_address.get(address, 0)) >= max_pending_handshakes_per_address):
		tcp_peer.disconnect_from_host()
		return
	var peer_id := _next_peer_id
	_next_peer_id += 1
	_addresses[peer_id] = address
	_handshake_started[peer_id] = Time.get_ticks_msec()
	_pending_by_address[address] = int(_pending_by_address.get(address, 0)) + 1
	if _tls_options != null:
		var tls := StreamPeerTLS.new()
		if tls.accept_stream(tcp_peer, _tls_options) != OK:
			tcp_peer.disconnect_from_host()
			_forget(peer_id)
			return
		_tls_pending[peer_id] = tls
		return
	_admit(peer_id, tcp_peer)
	# The handshake isn't complete yet — `_poll_peers()` notices the transition into
	# `STATE_OPEN` on a later poll and fires `peer_connected` then, not here.


## Gives a connection whose transport is ready its WebSocket, through an origin relay when
## the check is on.
func _admit(peer_id: int, stream: StreamPeer) -> void:
	if _origin_check:
		_relays[peer_id] = _OriginRelay.new(stream, _gate.get_local_port())
	else:
		_peers[peer_id] = _new_socket(stream)


func _drop_relay(peer_id: int) -> void:
	var relay: _OriginRelay = _relays.get(peer_id)
	if relay != null:
		relay.close()
		_relays.erase(peer_id)


## Advances every origin relay: a refused or dead one is dropped, a vetted one gets its
## WebSocket once the engine's end of the connection arrived on the private socket.
func _poll_relays(now: int) -> void:
	while _gate.is_connection_available():
		var conn := _gate.take_connection()
		var matched := false
		for relay: _OriginRelay in _relays.values():
			if relay.accepted == null and relay.inner_port == conn.get_connected_port():
				relay.accepted = conn
				matched = true
				break
		if !matched:
			conn.disconnect_from_host()
	for peer_id: int in _relays.keys():
		var relay: _OriginRelay = _relays[peer_id]
		relay.step(allowed_origins, allow_missing_origin)
		if relay.state == _OriginRelay.State.CLOSED and !_peers.has(peer_id):
			_forget(peer_id)
		elif relay.accepted != null and !_peers.has(peer_id) and relay.state == _OriginRelay.State.PIPING:
			_peers[peer_id] = _new_socket(relay.accepted)
		elif !_peers.has(peer_id) and handshake_timeout_ms > 0 \
				and now - int(_handshake_started.get(peer_id, now)) >= handshake_timeout_ms:
			_forget(peer_id)


func _new_socket(stream: StreamPeer) -> WebSocketPeer:
	var socket := WebSocketPeer.new()
	socket.inbound_buffer_size = inbound_buffer_size if inbound_buffer_size > 0 else DEFAULT_INBOUND_BUFFER_SIZE
	socket.outbound_buffer_size = outbound_buffer_size if outbound_buffer_size > 0 else DEFAULT_OUTBOUND_BUFFER_SIZE
	socket.accept_stream(stream)
	return socket


## Advances every TLS handshake; a finished one gets its WebSocketPeer, a failed or timed
## out one is dropped (it never opened, so no signal fires).
func _poll_tls_handshakes(now: int) -> void:
	for peer_id: int in _tls_pending.keys():
		var tls: StreamPeerTLS = _tls_pending[peer_id]
		tls.poll()
		var status := tls.get_status()
		if status == StreamPeerTLS.STATUS_CONNECTED:
			_tls_pending.erase(peer_id)
			_admit(peer_id, tls)
		elif status != StreamPeerTLS.STATUS_HANDSHAKING \
				or (handshake_timeout_ms > 0 and now - int(_handshake_started[peer_id]) >= handshake_timeout_ms):
			tls.disconnect_from_stream()
			_forget(peer_id)


func _poll_peers() -> void:
	var now := Time.get_ticks_msec()
	if !_tls_pending.is_empty():
		_poll_tls_handshakes(now)
	if _origin_check:
		_poll_relays(now)
	for peer_id: int in _peers.keys():
		# A handler run earlier in this loop may have stopped the server or dropped peers.
		if !_listening:
			return
		if !_peers.has(peer_id):
			continue
		var socket: WebSocketPeer = _peers[peer_id]
		var was_open := socket.get_ready_state() == WebSocketPeer.STATE_OPEN
		socket.poll()
		var state := socket.get_ready_state()

		if state == WebSocketPeer.STATE_CLOSED:
			_forget(peer_id)
			continue

		if state == WebSocketPeer.STATE_OPEN and !was_open:
			_end_handshake(peer_id)
			var address: String = _addresses.get(peer_id, '')
			if (max_peers > 0 and _opened_peers.size() >= max_peers) \
					or (max_peers_per_address > 0 and int(_open_by_address.get(address, 0)) >= max_peers_per_address):
				socket.close()
				_forget(peer_id)
				continue
			_opened_peers[peer_id] = true
			_open_by_address[address] = int(_open_by_address.get(address, 0)) + 1
			_last_heard[peer_id] = now
			peer_connected.emit(peer_id)
			if !_listening or !_peers.has(peer_id):
				continue

		if _handshake_started.has(peer_id):
			if handshake_timeout_ms > 0 and now - int(_handshake_started[peer_id]) >= handshake_timeout_ms:
				socket.close()
				_forget(peer_id)
			continue

		if _closing.has(peer_id):
			_poll_closing(peer_id, socket, now)
			continue

		if socket.get_available_packet_count() > 0:
			_last_heard[peer_id] = now
		elif idle_timeout_ms > 0 and now - int(_last_heard.get(peer_id, now)) >= idle_timeout_ms:
			socket.close()
			_forget(peer_id)
			continue

		_read_packets(peer_id, socket)


## Reads up to packets_per_poll frames from one open peer, stopping early when a handler
## disconnects that peer or stops the server.
func _read_packets(peer_id: int, socket: WebSocketPeer) -> void:
	var budget := packets_per_poll
	while socket.get_available_packet_count() > 0:
		if !_listening or !_peers.has(peer_id) or _closing.has(peer_id):
			return
		if packets_per_poll > 0:
			if budget <= 0:
				return
			budget -= 1
		var packet := socket.get_packet()
		if !socket.was_string_packet():
			continue
		var parsed: Variant = LFJson.parse_object(LFText.decode_utf8_lossy(packet))
		if parsed == null:
			continue
		var message: Dictionary = parsed
		# LFSocket's heartbeat: answer it here so every server built on this one keeps
		# its clients alive, and keep it out of the application's message stream.
		var type: Variant = message.get(LFSocket.TYPE_KEY)
		if type is String and type == LFSocket.PING_TYPE:
			socket.send_text(JSON.stringify({ LFSocket.TYPE_KEY: LFSocket.PONG_TYPE }))
			continue
		message_received.emit(peer_id, message)


## Drops a closing peer's incoming frames and closes it once its send queue has stayed
## empty for _CLOSE_LINGER_MS, or at its deadline.
func _poll_closing(peer_id: int, socket: WebSocketPeer, now: int) -> void:
	while socket.get_available_packet_count() > 0:
		socket.get_packet()
	var closing: _ClosingPeer = _closing[peer_id]
	if socket.get_current_outbound_buffered_amount() > 0:
		closing.drained_at_ms = -1
	elif closing.drained_at_ms < 0:
		closing.drained_at_ms = now
	var flushed := closing.drained_at_ms >= 0 and now - closing.drained_at_ms >= _CLOSE_LINGER_MS
	if flushed or now >= closing.deadline_ms:
		_closing.erase(peer_id)
		socket.close(LFSocket.DISCONNECTED_BY_SERVER_CODE)


## Polls `sockets` every frame, dropping what they receive, and closes each once its send
## queue has stayed empty for _CLOSE_LINGER_MS, or all of them at `timeout_ms`; then keeps
## polling until the closes complete (at most `timeout_ms` more). Static, so it holds the
## sockets itself and outlives the server that stopped.
static func _flush_then_close(sockets: Array[WebSocketPeer], timeout_ms: int, relays: Array = [], allowed: PackedStringArray = PackedStringArray(), allow_missing := false) -> void:
	var tree := LFUtils.tree_root
	if tree == null:
		for socket in sockets:
			socket.close()
		for relay: _OriginRelay in relays:
			relay.close()
		return
	var deadline := Time.get_ticks_msec() + timeout_ms
	var drained_at: Dictionary = {}  # WebSocketPeer -> msec its queue was first seen empty
	var open := sockets.duplicate()
	while !open.is_empty():
		var now := Time.get_ticks_msec()
		for socket: WebSocketPeer in open.duplicate():
			socket.poll()
			while socket.get_available_packet_count() > 0:
				socket.get_packet()
			if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
				open.erase(socket)
				continue
			if socket.get_current_outbound_buffered_amount() > 0:
				drained_at.erase(socket)
			elif !drained_at.has(socket):
				drained_at[socket] = now
			var flushed: bool = drained_at.has(socket) and now - int(drained_at[socket]) >= _CLOSE_LINGER_MS
			if flushed or now >= deadline:
				socket.close()
				open.erase(socket)
		_step_relays(relays, allowed, allow_missing)
		if !open.is_empty():
			await tree.process_frame
	# A close sends a close frame, which also goes out only while the socket is polled.
	var close_deadline := Time.get_ticks_msec() + timeout_ms
	var closing := sockets.duplicate()
	while Time.get_ticks_msec() < close_deadline:
		for socket: WebSocketPeer in closing.duplicate():
			socket.poll()
			if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				closing.erase(socket)
		_step_relays(relays, allowed, allow_missing)
		if closing.is_empty() and !_any_relay_open(relays):
			break
		await tree.process_frame
	for relay: _OriginRelay in relays:
		relay.close()


static func _step_relays(relays: Array, allowed: PackedStringArray, allow_missing: bool) -> void:
	for relay: _OriginRelay in relays:
		relay.step(allowed, allow_missing)


static func _any_relay_open(relays: Array) -> bool:
	for relay: _OriginRelay in relays:
		if relay.state != _OriginRelay.State.CLOSED:
			return true
	return false


func _forget(peer_id: int) -> void:
	_peers.erase(peer_id)
	_tls_pending.erase(peer_id)
	_end_handshake(peer_id)
	var was_open := _opened_peers.erase(peer_id)
	if was_open:
		var address: String = _addresses.get(peer_id, '')
		var left := int(_open_by_address.get(address, 0)) - 1
		if left > 0:
			_open_by_address[address] = left
		else:
			_open_by_address.erase(address)
	_addresses.erase(peer_id)
	_last_heard.erase(peer_id)
	_closing.erase(peer_id)
	_drop_relay(peer_id)
	if was_open:
		peer_disconnected.emit(peer_id)


## Drops a peer from the handshake bookkeeping (no-op once it has left it). Reads its
## address, so call it before _addresses forgets the peer.
func _end_handshake(peer_id: int) -> void:
	if !_handshake_started.erase(peer_id):
		return
	var address: String = _addresses.get(peer_id, '')
	var left := int(_pending_by_address.get(address, 0)) - 1
	if left > 0:
		_pending_by_address[address] = left
	else:
		_pending_by_address.erase(address)
