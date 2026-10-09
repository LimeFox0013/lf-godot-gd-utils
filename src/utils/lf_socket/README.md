# LFSocket, LFSocketOptions

> A WebSocket client that redials on its own after the connection drops (until a limit you set, or the server sends it away), checks the line with a heartbeat, queues messages while offline, routes events to listeners, and does request/response.

| | |
|---|---|
| **Files** | `lf_socket.gd`, `lf_socket_options.gd` |
| **Tests** | `tests/test_lf_socket.gd`, `tests/test_lf_socket_loopback.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUuid`, `LFLogger`, `LFAwait` (`next_tick` in `request_message`), `LFJson` (quiet parsing), `LFText` (lossy UTF-8), `LFUtils` (`tree_root`, `poll_each_frame`, `create_timer`); tests use `LFSocketServer` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFSocket` | Object: create it with `.new()` |
| `LFSocketOptions` | Object: create it with `.new()` |

## When to use it

Use `LFSocket` when your game talks to a server over WebSocket (a long-lived, two-way connection: either side can send at any time): an online lobby, a chat,
a leaderboard service, or the client side of a multiplayer match. Godot's `WebSocketPeer`
only opens one connection and must be polled every frame; `LFSocket` polls itself, redials
when the connection drops (waiting a little longer after each failure, "exponential
backoff"), notices a connection that died silently (a "heartbeat": a small ping every few
seconds that the server answers), keeps messages sent while offline until it reconnects,
and calls your listener for each named event. When the server sends it away on purpose
(`LFSocketServer.disconnect_peer`), it does not redial. For the server side, use `LFSocketServer`.
For plain HTTP calls (one request, one answer, no open connection), use `LFHttp`
instead. For Godot's high-level multiplayer (RPCs, `MultiplayerSynchronizer`),
use `WebSocketMultiplayerPeer`.

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
| `PING_TYPE` | `'ping'` | The `type` of the heartbeat message the client sends. |
| `PONG_TYPE` | `'pong'` | The `type` of the heartbeat answer the server sends back. |
| `REQUEST_TYPE` | `'request'` | The `type` of a message `request_message` sends. |
| `RESPONSE_TYPE` | `'response'` | The `type` of the server's answer to a request. |
| `TYPE_KEY` | `'type'` | Message key for the message's kind; also the event name when `event` is absent. |
| `EVENT_KEY` | `'event'` | Message key for the event name listeners are routed by. |
| `DATA_KEY` | `'data'` | Message key for the value listeners and a waiting request receive. |
| `ID_KEY` | `'id'` | Message key for a request's id, echoed back in its response. |
| `PAYLOAD_KEY` | `'payload'` | Message key for what a request sends. |
| `WILDCARD_EVENT` | `'*'` | The event name that registers a listener for every text event. |
| `DEFAULT_REQUEST_TIMEOUT_MS` | `5000` | Default `timeout_ms` of `request_message`, in milliseconds. |
| `DISCONNECTED_BY_SERVER_CODE` | `4000` | WebSocket close code a server sends when it disconnects this client on purpose (`LFSocketServer.disconnect_peer` does). A connection closed with it is not redialled. |

### Signals

| Member | Signature | Description |
|---|---|---|
| `connected` | `connected` | The connection opened (`STATE_OPEN`). The offline queue is sent right after the handlers return, so a message a handler sends (a login, say) goes first. |
| `disconnected` | `disconnected` | An open connection ended: the peer closed, a heartbeat timed out, or `disconnect_from_server()` closed it. Never fires for a connection that did not open. `get_close_code()` then tells why. |
| `error_occurred` | `error_occurred(message: String)` | A connect attempt failed, or the reconnect attempt limit was reached. An attempt fails either at once (`connect_to_url` rejects the URL; `connect_to_server` returns `false`) or later, when the connection closes before it opened (refused, unreachable, handshake rejected): both emit `error`, with or without `auto_reconnect`, before any reconnect is scheduled. |
| `reconnect_scheduled` | `reconnect_scheduled(attempt: int)` | A reconnect was scheduled; `attempt` counts from 1 since the last open connection. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `connect_to_server` | `connect_to_server(url: String, options := LFSocketOptions.new()) -> bool` | Starts connecting and the per-frame poll loop on a fresh `WebSocketPeer`, with a fresh reconnect attempt budget. A connection that is open or still opening is closed first (emitting `disconnected` if it was open). Returns `false` (emitting `error` and scheduling a reconnect) if `connect_to_url` fails immediately, e.g. for a malformed URL. `null` options mean the defaults. |
| `disconnect_from_server` | `disconnect_from_server(disable_reconnect: bool = true) -> void` | Closes the socket at once, stops the poll loop and emits `disconnected` if the connection was open. Messages sent in the same frame that have not gone out yet are lost. With `disable_reconnect = false` it then schedules a reconnect (subject to `auto_reconnect` and `max_reconnect_attempts`); the default stops reconnecting. |
| `is_connected_to_server` | `is_connected_to_server() -> bool` | `true` while open. |
| `send_message` | `send_message(message: Dictionary, queue_if_offline: bool = true) -> void` | Sends `JSON.stringify(message)`. While offline it queues a deep copy of the message if both the argument and `options.queue_offline_messages` allow it; otherwise it warns and drops it. |
| `emit_binary` | `emit_binary(event: String, data: PackedByteArray) -> void` | Sends `[u32 LE event length][event utf8][data]`. Never queued; warns and drops when offline. |
| `request_message` | `request_message(payload: Variant, timeout_ms := DEFAULT_REQUEST_TIMEOUT_MS) -> Variant` (5000) (await) | Sends `{type:"request", id, payload}` and waits for `{type:"response", id, data}`, then returns `data`. `payload` is any JSON value. Returns `null` (and removes the pending entry) on timeout, at once when called offline, and as soon as the connection closes. `timeout_ms <= 0` means no timer: it waits for the response or the close. |
| `on_event` | `on_event(event: String, callback: Callable) -> void` | `callback(data)` for that event. `"*"` registers `callback(event_name, data)` for every text event (not `{type:"response"}` frames, which go only to `request_message`). A listener whose object was freed (a node that never called `off_event`) is skipped and removed, never an error. |
| `on_dict_event` | `on_dict_event(event: String, callback: Callable) -> void` | Like `on_event`, but `callback` runs only when the event's data is a `Dictionary`; data of any other type is dropped for it, so a listener typed `data: Dictionary` never sees a string, number or array from an untrusted peer. `"*"` works as with `on_event`. Listeners of both kinds run in registration order. |
| `off_event` | `off_event(event: String, callback: Callable) -> void` | Removes a listener added with `on_event` or `on_dict_event` (`"*"` for wildcard listeners), one registration per call; an unregistered callback is ignored. Adding or removing listeners inside a listener takes effect from the next event; the event being dispatched still reaches every listener registered when it arrived. |
| `on_binary_event` / `off_binary_event` | `on_binary_event(event: String, callback: Callable) -> void` / `off_binary_event(event: String, callback: Callable) -> void` | `callback(data: PackedByteArray)` for binary frames carrying that event. Binary frames go only here. |
| `get_queue_size` / `clear_queue` | `get_queue_size() -> int` / `clear_queue() -> void` | Inspect or empty the offline queue. |
| `force_reconnect` | `force_reconnect() -> void` | Closes the connection, or abandons a dial still in progress (without scheduling a delayed reconnect), resets the backoff and redials right away on a fresh `WebSocketPeer`. A redial that fails at once emits one `error` and schedules one reconnect. Turns reconnecting back on after a `disconnect_from_server()`. Before any `connect_to_server()` there is no URL: it reports an error through its logger and does nothing else (no `error` signal, no reconnect). |
| `get_close_code` | `get_close_code() -> int` | The close code of the connection that last closed (`1000` normal, `1009` message too big, `DISCONNECTED_BY_SERVER_CODE`…), or `-1` while connecting, open, or never connected. |
| `get_status` | `get_status() -> Dictionary` | A snapshot for debugging: `{connected, url, state, pending_requests, queued_messages, reconnect_attempts, auto_reconnect}`. |

### Static property

| Member | Signature | Description |
|---|---|---|
| `log_traffic` | `static var log_traffic := false` | When `true`, every message sent and received (and each heartbeat) is logged, for every socket in the process. |

### Static method

| Member | Signature | Description |
|---|---|---|
| `redact_url` | `static redact_url(url: String) -> String` | `url` as it is logged: no `user:password@`, and the query and fragment replaced by `?...`. Works on malformed text too. |

### LFSocketOptions (constants)

| Member | Value | Description |
|---|---|---|
| `DEFAULT_RECONNECT_INTERVAL_MS` | `1000` | Default `reconnect_interval_ms`. |
| `DEFAULT_MAX_RECONNECT_INTERVAL_MS` | `30000` | Default `max_reconnect_interval_ms`. |
| `DEFAULT_RECONNECT_DECAY` | `1.5` | Default `reconnect_decay`. |
| `DEFAULT_HEARTBEAT_INTERVAL_MS` | `30000` | Default `heartbeat_interval_ms`. |
| `DEFAULT_HEARTBEAT_TIMEOUT_MS` | `5000` | Default `heartbeat_timeout_ms`. |
| `DEFAULT_MAX_QUEUE_SIZE` | `100` | Default `max_queue_size`. |
| `DEFAULT_BUFFER_SIZE` | `1 << 22` (4 MiB) | Default `buffer_size`. |

### LFSocketOptions (properties)

| Member | Signature | Description |
|---|---|---|
| `auto_reconnect` | `bool = true` | Schedule reconnects after a close or a failed attempt. |
| `reconnect_interval_ms` | `int = DEFAULT_RECONNECT_INTERVAL_MS` (1000) | First reconnect delay. Every wait, whatever the options, is at least 50 ms. |
| `max_reconnect_interval_ms` | `int = DEFAULT_MAX_RECONNECT_INTERVAL_MS` (30000) | Upper limit for the backoff delay (the first wait too), before the ±20 % variation; at least 50. |
| `reconnect_decay` | `float = DEFAULT_RECONNECT_DECAY` (1.5) | Delay multiplier applied after each attempt; below 1 (or NaN) counts as 1. Each actual delay is jittered by up to ±20 %. |
| `max_reconnect_attempts` | `int = 0` | `0` means unlimited. The count resets when a connection opens and at every `connect_to_server`. |
| `heartbeat_interval_ms` | `int = DEFAULT_HEARTBEAT_INTERVAL_MS` (30000) | How often a `{type:"ping"}` is sent. `<= 0` disables the heartbeat. |
| `heartbeat_timeout_ms` | `int = DEFAULT_HEARTBEAT_TIMEOUT_MS` (5000) | How long a sent ping may stay unanswered before the connection is declared dead (`0` or less: on the first poll after the ping). |
| `queue_offline_messages` | `bool = true` | Global switch for offline queueing. |
| `max_queue_size` | `int = DEFAULT_MAX_QUEUE_SIZE` (100) | When the queue is full the oldest message is evicted. `0` (or less) queues nothing. |
| `buffer_size` | `int = DEFAULT_BUFFER_SIZE` (`1 << 22`, 4 MiB) | Sets both the inbound and outbound `WebSocketPeer` buffer size before each dial, i.e. the largest message either way (Godot's default is 64 KiB). `0` or less uses the default. Applies at the next (re)connect. |
| `rng` | `RandomNumberGenerator = null` | Draws the reconnect jitter. `null` uses the global generator; give the socket its own so reconnecting never advances the global one a seeded game relies on. |
| `tls_options` | `TLSOptions = null` | TLS settings for a `wss://` URL, applied at the next (re)connect. `null` uses `TLSOptions.client()`: the server's certificate must be valid for its host name and issued by an authority in Godot's bundled trust list (or `network/tls/certificate_bundle_override`). `TLSOptions.client(certificate)` trusts one certificate of your own (e.g. self-signed); `TLSOptions.client_unsafe()` skips the check (testing only: still encrypted, but anyone in between can pose as the server). Ignored for `ws://`. |

## Usage

A script on any node (for example an autoload called `Net`) that connects, listens for
chat messages, sends one and asks the server a question:

```gdscript
extends Node

var sock := LFSocket.new() # keep this reference: a dropped socket closes

func _ready() -> void:
	var options := LFSocketOptions.new()
	options.max_reconnect_attempts = 5 # give up after 5 failed redials

	sock.connected.connect(func() -> void: print("connected"))
	sock.error_occurred.connect(func(message: String) -> void: push_warning(message))
	# Runs for {"event": "chat:message", "data": {...}} from the server.
	sock.on_dict_event("chat:message", func(data: Dictionary) -> void: print(data.get("text")))
	sock.connect_to_server("ws://127.0.0.1:9080", options)

	# Sent at once if connected, otherwise queued until the connection opens.
	sock.send_message({"event": "chat:send", "data": {"text": "hi"}})

func ask_for_stats() -> void:
	var stats: Variant = await sock.request_message({"op": "getStats"}, 3000)
	if stats == null:
		push_warning("no answer within 3 s (or offline)")
	else:
		print(stats)

func _exit_tree() -> void:
	sock.disconnect_from_server()
```

### Connect and react to the connection

```gdscript
var sock := LFSocket.new()

func _ready() -> void:
	sock.connected.connect(func() -> void: print("open"))
	sock.disconnected.connect(func() -> void: print("closed"))
	sock.reconnect_scheduled.connect(func(attempt: int) -> void: print("reconnect attempt ", attempt))
	sock.error_occurred.connect(func(message: String) -> void: push_warning(message))
	sock.connect_to_server("ws://127.0.0.1:9080")
```

### Tune reconnection and the heartbeat

These lines go inside a function of a script, with `sock` an `LFSocket` you created earlier (as above).

```gdscript
var options := LFSocketOptions.new()
options.reconnect_interval_ms = 500       # first retry delay
options.reconnect_decay = 2.0             # 500, 1000, 2000, ... ms
options.max_reconnect_interval_ms = 10000 # cap the delay
options.max_reconnect_attempts = 5        # 0 = keep trying forever
options.heartbeat_interval_ms = 5000      # send {type: "ping"} every 5 s
options.heartbeat_timeout_ms = 2000       # no pong within 2 s = connection lost
options.rng = RandomNumberGenerator.new() # keep the jitter off the global generator
sock.connect_to_server("ws://127.0.0.1:9080", options)
```

### The offline queue

These lines go inside a function, with `sock` an `LFSocket` you created earlier.

```gdscript
sock.send_message({"event": "player:move", "data": {"x": 150.0, "y": 200.0}}) # queued while offline
sock.send_message({"event": "cursor", "data": {"x": 1}}, false)                # dropped while offline
print(sock.get_queue_size())
sock.clear_queue()
```

### Receive events

This is part of a node's script that declares `sock` as above (`var sock := LFSocket.new()`).

```gdscript
func _ready() -> void:
	sock.on_event("chat:message", _on_chat)
	sock.on_event("*", func(event_name: String, data: Variant) -> void: print(event_name, " -> ", data))

func _on_chat(data: Variant) -> void:
	if data is Dictionary:
		print(data.get("text"))

func _exit_tree() -> void:
	sock.off_event("chat:message", _on_chat)
```

### Request / response

These lines go inside a function (it waits, because of `await`), with `sock` an `LFSocket` you created earlier.

```gdscript
var stats: Variant = await sock.request_message({"op": "getStats"}, 3000)
if stats == null:
	push_warning("no answer within 3 s")
```

The server answers `{"type": "request", "id": <id>, "payload": <payload>}` with `{"type": "response", "id": <same id>, "data": <result>}`; see the `LFSocketServer` README for a server that does.

### Binary data

These lines go inside a function, with `sock` an `LFSocket` you created earlier and `image` an `Image`.

```gdscript
sock.emit_binary("avatar:upload", image.save_png_to_buffer())
sock.on_binary_event("avatar:upload", func(bytes: PackedByteArray): print(bytes.size()))
```

`LFSocketServer` drops binary frames, so binary data needs a server that reads them.

### Shut down

Each of these lines goes inside a function, with `sock` an `LFSocket` you created earlier; they are alternatives, not a sequence.

```gdscript
sock.disconnect_from_server()      # closes and stops reconnecting
sock.disconnect_from_server(false) # closes, then schedules a reconnect (auto_reconnect permitting)
sock.force_reconnect()             # drop the current connection and redial now
```

## Notes

- `LFSocket.log_traffic` (static, off by default) logs every message sent and received and each heartbeat. Connection lifecycle lines (connecting, state changes, reconnect scheduling) go through `LFLogger.log`, so they print only after `LFLogger.enable_print_logs = true`; warnings and errors print by default. Turn `log_traffic` on only to debug a protocol, since on a live connection it formats every payload, and it logs received text in full, as the server sent it.
- **Reconnecting after a close:** every close of an open connection schedules a reconnect (with `auto_reconnect`), except `disconnect_from_server()` and a server close with `DISCONNECTED_BY_SERVER_CODE` (a kick, a full room). After that close, `connect_to_server()` or `force_reconnect()` dial again. A server that is not `LFSocketServer` can send the same code to keep the client away.
- **TLS:** use a `wss://` URL. A server's certificate is checked against Godot's bundled trusted authorities and the URL's host name unless `LFSocketOptions.tls_options` says otherwise. Tested against `LFSocketServer` with a self-signed certificate on desktop.
- **Wire format:** for incoming text the event name is `message.event`, falling back to `message.type`, and listeners receive `message.data`, falling back to the whole message. Frames are untrusted: an `event`, `type` or `id` that is not a String is treated as absent (never a script error). `{type:"response"}` frames go only to pending requests; one with an unknown id reaches nobody. `{type:"pong"}` clears the heartbeat flag and is also passed to listeners.
- **Untrusted bytes:** text frames and binary event names are decoded as UTF-8 with U+FFFD for each malformed byte, and a text frame that is not a JSON object (invalid JSON, an array, a scalar) is dropped with a logged warning. Neither raises an engine error, except that a number too large for a float (`1e99999`) makes Godot's JSON parser print an "Exponent too high" warning of its own (see `LFJson`).
- **Warnings caused by the server** (a text frame that is not a JSON object, a response to an unknown request id, a malformed binary frame): the frame's text or the id is quoted with at most 120 characters, in double quotes with backslashes, quotes and control characters escaped (`\u001b`), plus the full length when cut; a binary frame is described by its size only. Each kind is logged in full 5 times per socket; after that only a count, every 1000th time (`...: 1000 so far`), so a server sending junk cannot flood the log.
- **Logs redact the URL:** connection log lines (including the `error`-level one for a URL that cannot be dialled) show the URL without its `user:password@` and with the query and fragment replaced by `?...` (`LFSocket.redact_url(url)` does this for your own logging). Scheme, host, port and path are still logged, so keep secrets out of the path. `get_status()['url']` still returns the full URL, and the engine's own error messages (outside the library) may quote it as you wrote it.
- **Self-polling:** a loop runs once per `SceneTree.process_frame` (`LFUtils.poll_each_frame`), so a `SceneTree` main loop is required.
- **Lifetime:** the poll loop and reconnect timers hold the socket only weakly. Keep a reference for as long as you want the connection: a socket you drop is freed, which closes its connection and ends any reconnecting. While a `request_message` is waiting, the waiting call keeps the socket alive, so it is freed only after the request returns. Call `disconnect_from_server()` to end it explicitly.
- **Reconnect storms:** each reconnect delay is scaled by a random factor between 0.8 and 1.2, which spreads out the redials of clients that lost the same server (it does not guarantee they never coincide).
- **Last messages:** Godot's `WebSocketPeer` discards frames that arrive in the same poll as the other side's close, and messages still waiting to go out when it closes. A server that sends a goodbye and closes at once can lose it (`LFSocketServer.disconnect_peer` waits for its queue first); likewise `send_message` immediately followed by `disconnect_from_server()` loses the message. To be sure a last message arrives, send it with `request_message` and close after the answer.
- Listeners receive whatever `data` the peer sent, of any JSON type (a listener typed `data: Dictionary` raises a script error on anything else); check it with `is` when the peer is untrusted.
- **Windows, refused connections:** in the Windows CI run Godot 4.7.2 never reported a refused loopback connection (the peer was still connecting after 25 s), so no `error` or reconnect schedule follows a refusal there; the tests of that behaviour are skipped on Windows. Elsewhere a refusal is reported at once.
- A frame larger than `buffer_size` closes the connection with code 1009, which then reconnects like any other close (against a server that closes on a too-large frame, `LFSocketServer` on Windows, the client was seen to get close code `-1` instead of 1009: the close reset the connection before the close frame was read).
- **Heartbeat:** a `{type:"ping"}` is sent every `heartbeat_interval_ms` (it also keeps the client from being dropped by `LFSocketServer.idle_timeout_ms`, 60 s by default; a client with the heartbeat off must send something that often). If no `{type:"pong"}` arrives within `heartbeat_timeout_ms`, the socket closes the peer, emits `disconnected` and schedules a reconnect (subject to `auto_reconnect` and `max_reconnect_attempts`). `LFSocketServer` answers pings automatically; any other server must reply `{type:"pong"}` or set `heartbeat_interval_ms = 0`.
- `disconnect_from_server()` emits `disconnected` when it closes an open connection. A `disconnected` or `error_occurred` handler may call `connect_to_server` or `disconnect_from_server`; the socket then schedules no reconnect of its own. Each poll loop is tagged with a generation, so a reconnect never leaves two loops polling. Reconnect timers carry their own generation, bumped by every connect, disconnect, `force_reconnect` and newly scheduled reconnect, so a stale timer never replaces a live socket.
- Before `connect_to_server`, default `LFSocketOptions` apply, so an early `send_message` is queued.
- `request_message` doesn't queue: offline it returns `null` at once (with a warning).
- Binary frames are passed only to `on_binary_event` listeners for the decoded event name, never to `on_event` or `"*"` listeners. A binary frame shorter than its 4-byte header or its declared name is dropped.
- A frame larger than `buffer_size` that arrives in the same poll as the handshake answer still reports as a connection that opened and closed with 1009: `connected`, then `disconnected`, then a reconnect. Messages queued before it stay queued for the next connection. Only a refused attempt (no handshake) reports `error`.
