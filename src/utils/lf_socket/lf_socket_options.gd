## Connection settings passed to [method LFSocket.connect_to_server].
##
## Create one with `LFSocketOptions.new()`, change the fields you care about, and pass it
## in. Covers reconnecting, the heartbeat, the offline queue, the largest message size
## and TLS.
class_name LFSocketOptions

## Default [member reconnect_interval_ms], in milliseconds.
const DEFAULT_RECONNECT_INTERVAL_MS := 1000
## Default [member max_reconnect_interval_ms], in milliseconds.
const DEFAULT_MAX_RECONNECT_INTERVAL_MS := 30000
## Default [member reconnect_decay], a multiplier (each wait 50% longer than the last).
const DEFAULT_RECONNECT_DECAY := 1.5
## Default [member heartbeat_interval_ms], in milliseconds.
const DEFAULT_HEARTBEAT_INTERVAL_MS := 30000
## Default [member heartbeat_timeout_ms], in milliseconds.
const DEFAULT_HEARTBEAT_TIMEOUT_MS := 5000
## Default [member max_queue_size], in messages.
const DEFAULT_MAX_QUEUE_SIZE := 100
## Default [member buffer_size], in bytes (4 MiB).
const DEFAULT_BUFFER_SIZE := 1 << 22

## Whether the socket redials on its own after the connection closes or an attempt fails.
var auto_reconnect: bool = true
## Milliseconds to wait before the first reconnect attempt. Every wait is at least 50 ms.
var reconnect_interval_ms: int = DEFAULT_RECONNECT_INTERVAL_MS
## Longest wait between reconnect attempts, in milliseconds, however many have failed
## (not counting the random variation of up to 20% described at [member reconnect_decay]); at
## least 50.
var max_reconnect_interval_ms: int = DEFAULT_MAX_RECONNECT_INTERVAL_MS
## How much longer each reconnect wait is than the one before (1.5 = 50% longer); a value
## below 1 (or NaN) counts as 1. Each actual wait also varies randomly by up to 20% either way.
var reconnect_decay: float = DEFAULT_RECONNECT_DECAY
## Reconnect attempts allowed before giving up (emitting [signal LFSocket.error_occurred]); 0 means
## keep trying forever. The count starts over when a connection opens.
var max_reconnect_attempts: int = 0
## How often, in milliseconds, a `{"type": "ping"}` is sent while connected; `<= 0`
## turns the heartbeat off. The server must answer each ping with `{"type": "pong"}`.
var heartbeat_interval_ms: int = DEFAULT_HEARTBEAT_INTERVAL_MS
## Milliseconds a ping may go unanswered before the connection counts as dead and is
## closed and redialled (`0` or less: dead on the first poll after the ping).
var heartbeat_timeout_ms: int = DEFAULT_HEARTBEAT_TIMEOUT_MS
## Whether messages sent while offline are kept and sent once the connection opens.
var queue_offline_messages: bool = true
## Most messages the offline queue holds; when full, the oldest one is thrown away. `0`
## (or less) queues nothing.
var max_queue_size: int = DEFAULT_MAX_QUEUE_SIZE
## Largest message, in bytes, the socket can send or receive (default 4 MiB). Godot's own
## default is 64 KiB, which a large message (e.g. a full state snapshot) outgrows. A
## bigger incoming message closes the connection. Applies from the next connect; `0` or
## less uses the default.
var buffer_size: int = DEFAULT_BUFFER_SIZE
## Draws the reconnect jitter. Null uses the global generator; pass a generator of your
## own so reconnecting never advances the global one (which seeded code may rely on).
var rng: RandomNumberGenerator = null
## TLS settings for a `wss://` URL. Null uses `TLSOptions.client()`: the server's
## certificate must be valid for its host name and signed by an authority Godot trusts. Pass
## `TLSOptions.client(certificate)` to trust one certificate of your own, or
## `TLSOptions.client_unsafe()` to skip the check (only for local testing: the connection
## is encrypted but anyone in between can impersonate the server). Ignored for `ws://`.
var tls_options: TLSOptions = null
