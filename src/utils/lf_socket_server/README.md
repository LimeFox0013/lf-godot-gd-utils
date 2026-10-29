# LFSocketServer, LFSocketPeerGroup

> A WebSocket server for several clients at once (at most `max_peers`, 64 by default, all polled from GDScript once per frame), plus peer groups that split one server into rooms.

| | |
|---|---|
| **Files** | `lf_socket_server.gd`, `lf_socket_peer_group.gd` |
| **Tests** | `tests/test_lf_socket_server.gd`, `tests/test_lf_socket_peer_group.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFSocket` (`PING_TYPE`, `PONG_TYPE`, `TYPE_KEY`, `DISCONNECTED_BY_SERVER_CODE`), `LFOS` (`local_addresses` in `is_port_free`), `LFJson` (quiet parsing), `LFText` (lossy UTF-8), `LFUtils` (`tree_root`, `poll_each_frame`) |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFSocketServer` | Object: create it with `.new()` |
| `LFSocketPeerGroup` | Object: create it with `.new()` |

## When to use it

Use `LFSocketServer` when your game (or a small dedicated server written in Godot) must
accept WebSocket connections (long-lived, two-way connections: either side can send at any time): a lobby server, a chat relay, a match host that `LFSocket`
clients connect to. Each client gets an integer peer id, messages are JSON objects both
ways, the server polls itself every frame, answers `LFSocket`'s heartbeat pings, drops
clients that went silent, can serve `wss://` (encrypted) with a certificate you supply, and a
"goodbye" sent just before a disconnect still arrives if it goes out within
`disconnect_flush_timeout_ms`. Use `LFSocketPeerGroup` to run
several rooms or matches on one port: each group sees and reaches only its own members.
For Godot's high-level multiplayer (RPCs, `MultiplayerSynchronizer`), use
`WebSocketMultiplayerPeer` instead; for the client side, use `LFSocket`.

## Step by step

Send a message from a client to a server and get an answer back, all on your own computer, in one scene.

**Before you start:** this works on desktop (Windows, macOS, Linux) only, not in a web export. Nothing else needs to be running: the scene starts its own server. Port 9080 must be free on your machine; if the Output panel shows "Could not start the server", change `9080` in the script (in both places) to another number between 1024 and 65535.

1. Create a new scene: *Scene → New Scene*, then click *Other Node* under "Create Root Node", pick **Node** and click *Create*. Save it with Ctrl+S (for example as `socket_demo.tscn`).
2. Right-click the root node in the Scene dock and choose *Attach Script*. Keep the defaults (it extends `Node`) and click *Create*. The script editor opens.
3. Replace everything in the script with the code below. It does both jobs: the **server** (`LFSocketServer`) waits for clients and the **client** (`LFSocket`) connects to it. Each is an object you create with `.new()`; they sit in variables because an object nobody refers to is freed, and a freed server or client stops working.

```gdscript
extends Node

var server := LFSocketServer.new() # the listening side
var client := LFSocket.new()       # the connecting side

func _ready() -> void:
	# A signal is an event other code can listen to; connect() says which
	# function to call when it happens.
	server.message_received.connect(_on_server_message)
	# Start listening on port 9080. "127.0.0.1" means this computer only.
	var err := server.listen(9080, "127.0.0.1")
	if err != OK:
		push_error("Could not start the server: %s" % error_string(err))
		return

	client.connected.connect(func() -> void: print("Client: connected"))
	# When the server sends {"event": "greeting", ...}, call _on_greeting
	# with that message's "data".
	client.on_dict_event("greeting", _on_greeting)
	# Dial the server. "ws://" is the WebSocket address prefix.
	client.connect_to_server("ws://127.0.0.1:9080")
	# A message is a Dictionary (a set of named values). It is queued
	# and sent as soon as the connection opens.
	client.send_message({"event": "hello", "data": {"text": "Hello server!"}})

# Runs on the server for every message a client sends.
func _on_server_message(peer_id: int, message: Dictionary) -> void:
	print("Server got: ", message)
	# peer_id numbers the client; answer that client only.
	server.send_to(peer_id, {"event": "greeting", "data": {"text": "Hello client!"}})

# Runs on the client when the server's "greeting" arrives.
func _on_greeting(data: Dictionary) -> void:
	print("Client got: ", data.get("text"))

# Tidy up when the scene closes.
func _exit_tree() -> void:
	client.disconnect_from_server()
	server.stop()
```

4. Save the script (Ctrl+S) and run the scene with **F6** (*Run Current Scene*).
5. Look at the *Output* panel at the bottom of the editor. Within a second you should see `Client: connected`, `Server got: { "data": { "text": "Hello server!" }, "event": "hello" }` (the client sends the keys sorted, `JSON.stringify`'s default, and Godot prints a Dictionary in the order its keys arrived) and `Client got: Hello client!`. If you see all three, a message travelled to the server and an answer came back.
6. To make it your own, change the event names (`"hello"`, `"greeting"`: any text you like, as long as sender and listener agree) and put your own values in `"data"`. Messages can hold numbers, text, true/false, lists and nested dictionaries.
7. To run the two sides separately, split the script in two: put the `server` lines in a scene for one Godot instance and the `client` lines in another scene, and run both (*Debug → Customize Run Instances…* lets you start several copies of the game at once). To reach a server on another computer, start it with `server.listen(9080)` (all network interfaces) and give the client `ws://<that computer's address>:9080`.

## API

Everything the class offers; you only need the rows used above to get started.

### Constants

| Member | Value | Description |
|---|---|---|
| `DEFAULT_INBOUND_BUFFER_SIZE` | `1 << 16` (64 KiB) | Default `inbound_buffer_size`. |
| `DEFAULT_OUTBOUND_BUFFER_SIZE` | `1 << 22` (4 MiB) | Default `outbound_buffer_size`. |
| `DEFAULT_MAX_PEERS` | `64` | Default `max_peers`. |
| `DEFAULT_MAX_PEERS_PER_ADDRESS` | `8` | Default `max_peers_per_address`. |
| `DEFAULT_MAX_PENDING_HANDSHAKES` | `32` | Default `max_pending_handshakes`. |
| `DEFAULT_MAX_PENDING_HANDSHAKES_PER_ADDRESS` | `4` | Default `max_pending_handshakes_per_address`. |
| `DEFAULT_PACKETS_PER_POLL` | `64` | Default `packets_per_poll`. |
| `DEFAULT_HANDSHAKE_TIMEOUT_MS` | `3000` | Default `handshake_timeout_ms`. |
| `DEFAULT_DISCONNECT_FLUSH_TIMEOUT_MS` | `2000` | Default `disconnect_flush_timeout_ms`. |
| `DEFAULT_IDLE_TIMEOUT_MS` | `60000` | Default `idle_timeout_ms`: twice `LFSocket`'s default heartbeat interval. |
| `DEFAULT_FREE_PORT_IP` | `'127.0.0.1'` | Default `ip` of `free_port`: the loopback address. |
| `DEFAULT_LISTEN_HOST` | `'*'` | Default `host` of `listen`: every network interface. |

### Signals

| Member | Signature | Description |
|---|---|---|
| `peer_connected` | `peer_connected(peer_id: int)` | The peer's WebSocket handshake finished (`STATE_OPEN`). Accepting the TCP connection alone doesn't fire it. |
| `peer_disconnected` | `peer_disconnected(peer_id: int)` | A peer that had been open closed (by either side), was silent longer than `idle_timeout_ms`, or was closed by `stop()`. |
| `message_received` | `message_received(peer_id: int, data: Dictionary)` | A text frame that parsed as a JSON **object**. Its fields can hold any JSON type: check a field's type before comparing it. |

### Properties

| Member | Signature | Description |
|---|---|---|
| `inbound_buffer_size` | `var inbound_buffer_size := DEFAULT_INBOUND_BUFFER_SIZE` (`1 << 16`, 64 KiB) | Largest message a peer can send (`0` or less uses the default). Every accepted peer reserves at least this much memory up front, so keep it small; a larger frame closes that peer with code 1009 (on Windows the peer was seen to get `-1` instead, no close code, because the close can reset the connection first). Read at each accept. |
| `outbound_buffer_size` | `var outbound_buffer_size := DEFAULT_OUTBOUND_BUFFER_SIZE` (`1 << 22`, 4 MiB) | Largest message the server can send to one peer (`0` or less uses the default). Memory is used only while messages are queued. Read at each accept. |
| `max_peers` | `var max_peers := DEFAULT_MAX_PEERS` (64) | Most open peers (handshake finished) held at once. While this many are open, a new connection is closed right after it is accepted and never gets a peer id; a handshake that finishes while the server is full is closed without `peer_connected`. Connections still in their handshake count toward `max_pending_handshakes` instead. `0` means unlimited. |
| `max_peers_per_address` | `var max_peers_per_address := DEFAULT_MAX_PEERS_PER_ADDRESS` (8) | Most **open** peers one remote IP (`peer_address`) holds at once, so one machine cannot take every `max_peers` slot. One more from that address is closed right after it is accepted, or when its handshake finishes at the cap (no `peer_connected`). Negative values are stored as `0`, which means unlimited. Behind a reverse proxy or NAT all clients share one address: raise it or set `0` there. It does not stop an attacker with many addresses. |
| `allowed_origins` | `var allowed_origins := PackedStringArray()` (empty) | **Origin allow-list for browsers; empty = no check (the default).** Read by `listen`. See Notes → Cross-site WebSocket hijacking. |
| `allow_missing_origin` | `var allow_missing_origin := true` | With `allowed_origins` set: whether a handshake with no `Origin` header (native clients such as `LFSocket` on desktop) is let in. |
| `max_pending_handshakes` | `var max_pending_handshakes := DEFAULT_MAX_PENDING_HANDSHAKES` (32) | Most connections still in their TLS or WebSocket handshake held at once, all addresses together. One more is closed right after it is accepted. `0` means unlimited. |
| `max_pending_handshakes_per_address` | `var max_pending_handshakes_per_address := DEFAULT_MAX_PENDING_HANDSHAKES_PER_ADDRESS` (4) | Most connections still in their handshake held at once from one remote IP (`peer_address`). One more from that address is closed right after it is accepted. Behind a reverse proxy every connection has the proxy's address, so raise it or set it to `0` (unlimited) there. See Notes → Connections that never finish their handshake. |
| `packets_per_poll` | `var packets_per_poll := DEFAULT_PACKETS_PER_POLL` (64) | Most packets read from one peer per poll (one frame); the rest wait for the next poll, which bounds how much one flooding peer adds to a frame (each packet can still be up to `inbound_buffer_size`). `0` means unlimited. |
| `handshake_timeout_ms` | `var handshake_timeout_ms := DEFAULT_HANDSHAKE_TIMEOUT_MS` (3000) | A connection that has not completed its WebSocket handshake this long after it was accepted is closed, freeing its slot. `0` means no limit. |
| `disconnect_flush_timeout_ms` | `var disconnect_flush_timeout_ms := DEFAULT_DISCONNECT_FLUSH_TIMEOUT_MS` (2000) | Longest `disconnect_peer` (or a flushing `stop`) waits for a peer's queued messages to go out before it closes the connection anyway. |
| `idle_timeout_ms` | `var idle_timeout_ms := DEFAULT_IDLE_TIMEOUT_MS` (60000) | An open peer that sent nothing (no message, no heartbeat ping) for this long is closed and reported with `peer_disconnected`, so a client whose machine or network vanished without closing gives its slot back. `0` means no limit. `LFSocket`'s default heartbeat (a ping every 30 s) keeps a live client in; a client with its heartbeat off must send something this often. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `free_port` | `static free_port(ip := DEFAULT_FREE_PORT_IP) -> int` ('127.0.0.1') | A TCP port on `ip` that the OS reported free just now: it binds port 0 and reads back the port it was given. Returns `-1` when nothing can be bound on `ip`. Another process may take the port before you bind it. |
| `is_port_free` | `static is_port_free(port: int) -> bool` | Whether TCP `port` could be bound just now on the wildcard addresses and on every non-link-local local address (`LFOS.local_addresses()`; a listener on a link-local address is not detected), because a listener on `127.0.0.1` or one LAN address does not stop a wildcard bind. An address that can't be bound at all right now is skipped. Racy like `free_port`. `false` for a port outside 1-65535. |
| `free_port_in_range` | `static free_port_in_range(first: int, last: int, taken := Callable(), is_free := Callable()) -> int` | The first port in `first`..`last` that `taken.call(port)` does not claim and `is_free.call(port)` accepts (default `is_port_free`); -1 when none. |
| `listen` | `listen(port: int, host: String = DEFAULT_LISTEN_HOST, tls_options: TLSOptions = null) -> Error` ('*') | Binds the `TCPServer` and starts the self-polling loop. Returns the bind error if binding fails, `ERR_ALREADY_IN_USE` (changing nothing) when already listening, `ERR_INVALID_PARAMETER` for client `TLSOptions` or a port outside 0-65535 (`0` picks a free port), and `ERR_UNCONFIGURED` when the main loop is not a `SceneTree`. **The default `'*'` listens on every network interface**, so other machines can connect; pass `'127.0.0.1'` for a local-only server. With `tls_options` from `TLSOptions.server(key, certificate)` it serves `wss://`: every connection must finish a TLS handshake (within `handshake_timeout_ms`) before its WebSocket handshake, and a plain `ws://` client cannot connect. See Notes → TLS. |
| `stop` | `stop(flush := true) -> void` | Stops polling and listening, lets go of every peer and emits `peer_disconnected` for each one that was open, all before it returns: the port is free and `connected_peer_ids()` is empty. With `flush` (the default) each open peer's queued messages still go out before its connection closes (at most `disconnect_flush_timeout_ms` later, even if the server is freed meanwhile), so a goodbye broadcast just before `stop()` arrives (with `allowed_origins` set too: the origin relays stay open while the flush runs) unless the queue takes longer than that to drain. `stop(false)` closes every connection at once and drops what was queued. Safe to call from any of this server's signal handlers. |
| `get_local_port` | `get_local_port() -> int` | The TCP port the server is bound to while listening, `0` when it is not. After `listen(0)` it is the port the OS picked: bind any free port, then read it back, with no window for another process to take it (unlike `free_port`). |
| `is_listening` | `is_listening() -> bool` | `true` between a successful `listen` and `stop`. |
| `connected_peer_ids` | `connected_peer_ids() -> Array` | Ids of peers that are open and not being disconnected. Peers still mid-handshake are left out. |
| `peer_address` | `peer_address(peer_id: int) -> String` | The IP address the peer's TCP connection comes from — what a server rate-limits or bans by (key it with `LFStrikeGuard.address_key`). Known from the moment the connection is accepted (also during a TLS handshake); `''` for an unknown id. **Behind a reverse proxy or load balancer it is the proxy's address for every peer**; the player's address (e.g. an `X-Forwarded-For` header) is not available. |
| `send_to` | `send_to(peer_id: int, data: Dictionary) -> Error` | `send_text(JSON.stringify(data))`. Returns `ERR_DOES_NOT_EXIST` for an unknown id and `ERR_UNAVAILABLE` (without an engine error) for a peer still mid-handshake or being disconnected. |
| `send_text_to` | `send_text_to(peer_id: int, text: String) -> Error` | Sends already-encoded text, for a payload several peers get so it is encoded once. Same errors as `send_to`. |
| `broadcast` | `broadcast(data: Dictionary) -> void` | Encodes `data` once and sends it to every peer in `connected_peer_ids()`. |
| `disconnect_peer` | `disconnect_peer(peer_id: int) -> void` | Closes that peer once the messages already sent to it have gone out (at most `disconnect_flush_timeout_ms` later), so a "goodbye" sent just before arrives unless the queue takes longer than that to drain. From the call on, the peer is left out of `connected_peer_ids()`, sends to it fail and its incoming frames are dropped. `peer_disconnected` fires once the close completes. The close carries code `LFSocket.DISCONNECTED_BY_SERVER_CODE` (4000), which tells an `LFSocket` client not to reconnect on its own. A peer that has not finished connecting (TLS or WebSocket handshake) is closed at once, without that code, and is gone by the next poll; it never opened, so no signal fires. An unknown id is ignored. |

### LFSocketPeerGroup

A view of some of an `LFSocketServer`'s peers with the server's sending surface and signals, so code written against a server (a lobby, a room) that uses only that surface (sends, `broadcast`, `disconnect_peer`, `peer_address`, the signals) runs unchanged on a group of a shared server's peers; `listen`, `free_port` and the server's settings stay on the server. Sends and broadcasts reach members only, a member's messages and closes are re-emitted, and peers outside the group are never touched. The owner decides who is in it.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_socket_peer_group.gd` |

#### Signals

| Member | Signature | Description |
|---|---|---|
| `peer_disconnected` | `peer_disconnected(peer_id: int)` | A member's connection closed (by either side, or by the server stopping). It has already left the group. |
| `message_received` | `message_received(peer_id: int, data: Dictionary)` | A member sent a message (with `forward_messages` on), or the owner passed one on with `deliver()`. |

#### Properties

| Member | Signature | Description |
|---|---|---|
| `forward_messages` | `var forward_messages := true` | `true`: every message a member sends the server is re-emitted. `false`: the owner routes messages itself and hands a member's on with `deliver()`. |

#### Methods

| Member | Signature | Description |
|---|---|---|
| `_init` | `new(server: LFSocketServer)` | An empty group over `server`. The group holds the server; the server does not hold the group. |
| `get_server` | `get_server() -> LFSocketServer` | The server this group is a view of. |
| `add_member` / `remove_member` | `add_member(peer_id: int)` / `remove_member(peer_id: int)` | Adds or removes a member. Removing never disconnects the peer and emits nothing. |
| `has_member` / `member_ids` | `has_member(peer_id: int) -> bool` / `member_ids() -> Array` | Membership, in the order members were added, whether or not the server can send to them now. |
| `stop` | `stop() -> void` | Lets go of every member without disconnecting anyone or emitting a signal. The server keeps running and the group can take members again. |
| `is_listening` | `is_listening() -> bool` | Whether the server is listening. |
| `connected_peer_ids` | `connected_peer_ids() -> Array` | Members the server can send to now (open, not being disconnected). |
| `peer_address` | `peer_address(peer_id: int) -> String` | A member's remote IP; `''` for a peer outside the group. |
| `send_to` / `send_text_to` | `send_to(peer_id: int, data: Dictionary) -> Error` / `send_text_to(peer_id: int, text: String) -> Error` | The server's send for a member; `ERR_DOES_NOT_EXIST` for anyone else. |
| `broadcast` | `broadcast(data: Dictionary) -> void` | Encodes `data` once and sends it to every member in `connected_peer_ids()`. |
| `disconnect_peer` | `disconnect_peer(peer_id: int) -> void` | The server's flush-then-close for a member; `peer_disconnected` fires once the close completes. A peer outside the group is ignored. |
| `deliver` | `deliver(peer_id: int, data: Dictionary) -> bool` | Emits `message_received` for a member as if it had just sent `data`; `false` (nothing emitted) for anyone else. |

## Usage

A script on a node in your server scene. It greets each client, relays chat to everyone,
answers `LFSocket.request_message` calls, and says goodbye on shutdown:

```gdscript
extends Node

var server := LFSocketServer.new() # keep this reference: a dropped server closes

func _ready() -> void:
	server.peer_connected.connect(_on_peer_connected)
	server.peer_disconnected.connect(func(peer_id: int) -> void: print("peer ", peer_id, " left"))
	server.message_received.connect(_on_message)
	var err := server.listen(9080, "127.0.0.1") # "127.0.0.1": this machine only
	if err != OK:
		push_error("listen failed: %s" % error_string(err))

func _on_peer_connected(peer_id: int) -> void:
	server.send_to(peer_id, {"event": "welcome", "data": {"id": peer_id}})

func _on_message(peer_id: int, message: Dictionary) -> void:
	# Fields can hold any JSON type: compare them as strings.
	match str(message.get("type", message.get("event", ""))):
		"request": # LFSocket.request_message() expects a "response" with the same id
			server.send_to(peer_id, {"type": "response", "id": message.get("id"), "data": {"kills": 12}})
		"chat:send":
			server.broadcast({"event": "chat:message", "data": message.get("data")})
		"leave":
			server.send_to(peer_id, {"event": "bye"})
			server.disconnect_peer(peer_id) # closes after "bye" has gone out

func _exit_tree() -> void:
	server.broadcast({"event": "closing"}) # still arrives: stop() flushes first
	server.stop()
```

### Rooms with LFSocketPeerGroup

```gdscript
extends Node

var server := LFSocketServer.new()
var rooms: Dictionary[String, LFSocketPeerGroup] = {}

func _ready() -> void:
	server.message_received.connect(_on_message)
	server.listen(9080, "127.0.0.1")

func _on_message(peer_id: int, message: Dictionary) -> void:
	if str(message.get("type", "")) != "join":
		return
	var room_name := str(message.get("room", ""))
	if !rooms.has(room_name):
		var room := LFSocketPeerGroup.new(server)
		# A room's own handlers see only its members:
		room.message_received.connect(func(id: int, msg: Dictionary) -> void: rooms[room_name].broadcast({"from": id, "said": msg}))
		rooms[room_name] = room
	rooms[room_name].add_member(peer_id)
	rooms[room_name].broadcast({"type": "joined", "id": peer_id})
```

## Notes

- **Self-polling:** `listen()` starts a loop that runs once per `SceneTree.process_frame`, so you never call a `poll()`. It needs `Engine.get_main_loop()` to be a `SceneTree`; if it isn't, `listen` returns `ERR_UNCONFIGURED` and binds nothing. A `stop()` and `listen()` in one frame keep the one loop running; there is never more than one.
- **Lifetime:** the loop holds the server only weakly. Keep a reference for as long as it should serve: a server you drop is freed, which closes its port and its peers at once (no `peer_disconnected` is emitted, since a freed object can't emit). Call `stop()` to end it explicitly.
- Each frame takes at most 256 waiting TCP connections from the listening socket; the rest wait for the next frame.
- Frames are untrusted. Binary frames, and text frames that aren't a JSON object (arrays, scalars, invalid JSON), are dropped silently: decoding (malformed UTF-8 becomes U+FFFD) and parsing are quiet, so a malformed frame logs no engine error. One exception comes from Godot's JSON parser: a number too large for a float (`1e99999`) is valid JSON, read as `inf`, and the engine prints an "Exponent too high" warning that no script can silence (see `LFJson`), so a peer can still add lines to the log that way. A JSON object whose fields have unexpected types is delivered as is and never raises inside the server, so one peer cannot hold up the others.
- **Cross-site WebSocket hijacking (read this before exposing a server to browsers).** In general a browser lets a web page open a WebSocket to any address it can reach, including `localhost`, a LAN address or your public server (newer browser restrictions on local-network access may limit this), and it may send the visitor's cookies for that address, depending on the browser's cookie rules. The only thing that tells your server which page asked is the `Origin` header. **`allowed_origins` is empty by default, which checks nothing**, so out of the box any page a visitor opens can try to connect to your server. Recommended: for any server browsers can reach (a web export of your game, a lobby on a public host, a local server a page could poke), set `server.allowed_origins = PackedStringArray(['https://your-game.example'])` before `listen`, and `allow_missing_origin = false` if only browsers should connect. A request whose `Origin` is listed passes; one whose `Origin` is not listed, or that carries two `Origin` headers, gets `403 Forbidden` and never becomes a peer; one with no `Origin` header passes unless `allow_missing_origin` is `false`. Limits, stated plainly: the header is only a promise, since a native program can send any `Origin`, so this blocks other web pages and not other programs (use authentication for those); Godot's `WebSocketPeer` does not expose request headers to scripts, so with the check on the server reads each request itself and forwards the connection's bytes to the engine's WebSocket through a private socket on `127.0.0.1` (one extra local socket pair per connection, up to a frame of added latency each way, and about 256 KiB per frame per direction at most), and a request head over 8 KiB is refused with `400`. Other programs on the machine reach that private socket only by guessing a pending connection's local port. With the check off, none of this applies and connections go straight to the engine.
- **Memory:** each accepted peer reserves at least `inbound_buffer_size` at once, and up to `max_peers` open peers plus `max_pending_handshakes` connections mid-handshake can be held at a time, so the worst case is their sum times `inbound_buffer_size`. Raise `inbound_buffer_size` only when clients really send large messages.
- **Slots:** `max_peers` counts open peers only (and `max_peers_per_address` caps each address's share of them, 8 by default: more than 8 clients from one machine or NAT are refused until you raise it); connections still mid-handshake (TLS or WebSocket) count toward `max_pending_handshakes` and `max_pending_handshakes_per_address`. `handshake_timeout_ms` frees the slots of connections that never complete a handshake, and `idle_timeout_ms` those of open peers that went silent.
- **Connections that never finish their handshake.** Opening plain TCP connections and never speaking WebSocket costs an attacker almost nothing. With the per-address cap (4 by default) one machine holds at most 4 handshake slots, however many connections it opens, and open players never lose their slots to such connections, so a client from another address can still get in. What it does not stop: an attacker with more addresses than `max_pending_handshakes / max_pending_handshakes_per_address` (8 with the defaults) can still fill the handshake slots; a single address that re-opens connections as fast as they are refused can fill the operating system's short queue of connections not yet accepted (Godot's `TCPServer` keeps a small one), delaying everyone's connect; and behind a reverse proxy or NAT the cap applies to the shared address, so it limits all clients behind it together (see `peer_address`). Those need a firewall, rate limit or proxy in front of the server. The cap also applies to honest clients that share an address: more than 4 clients on one machine or behind one NAT (local bots, a LAN party) starting their handshakes in the same moment get the extras refused, and an `LFSocket` retries those after its reconnect delay; raise the cap where that is expected.
- **TLS (`wss://`).** Pass `TLSOptions.server(key, certificate)` to `listen`. For players on the internet the certificate must be one their client trusts for your host name, e.g. from Let's Encrypt: load it with `X509Certificate.new().load("res://…/fullchain.pem")` and the key with `CryptoKey.new().load("…/privkey.pem")` (keep the key out of the exported game). A self-signed certificate (`Crypto.generate_self_signed_certificate`) works for testing: give the client `TLSOptions.client(certificate)` in `LFSocketOptions.tls_options`. Each TLS handshake runs on the main thread. Alternatively, run the server on `ws://` bound to `127.0.0.1` behind a TLS reverse proxy (nginx, Caddy); then `peer_address` is the proxy's address. The TLS server path is tested on desktop with a self-signed certificate only.
- **Closes and reconnects:** `disconnect_peer` closes with `LFSocket.DISCONNECTED_BY_SERVER_CODE`, so `LFSocket` clients stay away; `stop()` closes with the normal code 1000 and an idle drop lets the connection go without waiting for a close handshake; either way `LFSocket` clients reconnect (a restarted server gets them back).
- **Heartbeat:** a `{type:"ping"}` from a client (`LFSocket.PING_TYPE`, sent by its heartbeat) is answered with `{type:"pong"}` (`LFSocket.PONG_TYPE`) and is not emitted as `message_received`.
- **Closing:** the engine discards a peer's unsent messages when it is closed, and reports only the messages still queued, not the one being written. `disconnect_peer` and a flushing `stop()` therefore wait until the queue is empty and then about 100 ms more before they close; `stop(false)` closes at once. A flushing `stop()` keeps polling the closing connections by itself, so a client may see its connection close up to `disconnect_flush_timeout_ms` after `stop()` returned.
- Messages from a peer that opens are read in the same poll that reports `peer_connected`.
- A message a client sends right before it closes can be lost: Godot's `WebSocketPeer` discards frames that arrive in the same poll as the close, so no `message_received` fires for them. A client that must be heard before leaving should wait for the server's answer, then close.
- `free_port` and `is_port_free` are racy: another process can bind the port between the probe and your own `listen`. To serve on any free port without that race, `listen(0)` and read the port back with `get_local_port()`.
- Peer ids keep increasing and are never reused by one server object, including after `stop()` and a second `listen()`; a new `LFSocketServer` starts again at 1.
- **Groups:** a peer can be in several groups at once; each re-emits its messages and its close.
- **Groups:** a member's close is handled after any handler connected to the server's `peer_disconnected` before the group was created.
- **Groups:** with `forward_messages` on, a member's messages reach the group's listeners as well as the server's own; with it off the owner filters or rewrites them and calls `deliver()`.
