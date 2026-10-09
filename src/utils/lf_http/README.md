# LFHttp

> Fetch something from a web server (or send it some data) with one line of code, and get the whole answer back, with JSON already parsed.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_http.gd` |
| **Tests** | `tests/test_lf_http.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUrl` (URL parsing and redirect resolution), `LFJson` (quiet parsing), `LFText` (lossy UTF-8), `LFUtils` (`tree_root`) |

## When to use it

Use it when your game talks to a web server from code: fetching a leaderboard, posting a
score, checking for news or calling a web API, written as one line you `await` ("wait
here until it finishes, while the game keeps running") instead of a node, signals and a
callback. Godot's `HTTPRequest` node works too and is the better pick for big downloads
straight to a file (`download_file`) or when you prefer signals. `LFHttp` adds a single
deadline for the whole request, redirect handling that drops your `Authorization`,
`Cookie` and other non-standard headers (where API keys usually go) when a redirect leads
to another site, size limits and JSON parsing in one call. For a live two-way connection
(chat, multiplayer) use `LFSocket` (WebSocket) instead.

## Step by step

**Before you start:** you need an internet connection, and a web address to ask. The
example uses `https://httpbin.org/get`, a public test site that answers with JSON; swap in
your own server's address. The tests run on desktop only (a local test server);
browser (web) exports are not tested, and there the browser makes the request (see Notes).

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock click **Other Node**,
   pick **Node**, and press *Create*. Save with *Ctrl+S* (Cmd+S on macOS) as `http_demo.tscn`.
2. Right-click the Node in the Scene dock and choose *Attach Script*, then press *Create*
   (the default settings are fine). The script editor opens.
3. Replace everything in the script with this:

```gdscript
extends Node


func _ready() -> void:
	# Ask the server. "await" waits here for the answer; the game keeps running meanwhile.
	# The arguments are: the method (GET = "give me data"), the address, extra headers
	# (a Dictionary: pairs of name and value), a body to send (none for GET), and a
	# deadline in milliseconds (5000 = 5 seconds).
	var result: Dictionary = await LFHttp.request(
			HTTPClient.METHOD_GET, "https://httpbin.org/get", {}, "", 5000)

	if result.ok:
		# "status" is the server's answer code: 200 means success.
		print("Status: ", result.status)
		# "json" holds the parsed JSON when the server sent JSON, otherwise null.
		print(result.json)
	else:
		# "error" says what went wrong (no connection, timeout, ...). If there is none,
		# the server answered but said no (for example 404 "not found").
		print("Failed: ", result.get("error", "server answered %d" % result.status))
```

4. Press *F6* (Run Current Scene). Look at the **Output** panel at the bottom of the editor:
   you should see `Status: 200`, followed by the answer as a Dictionary (key and value
   pairs). If you are offline you see a failure instead, usually `Failed: Cannot resolve host`,
   which also shows it works.
5. Make it yours: change the address; put headers such as `{"Accept": "application/json"}`
   in the third argument; change `5000` to the longest wait you accept, in milliseconds
   (`0` or less waits as long as the server stays connected); add a sixth argument, for example
   `1024 * 1024`, to refuse answers larger than that many bytes.
6. To send data, use `HTTPClient.METHOD_POST` with your text as the body; the Usage
   section below shows posting a score as JSON.

## API

Everything the class offers; you only need the rows used above to get started.

### Constants

| Member | Value | Description |
|---|---|---|
| `MAX_REDIRECTS` | `5` | Redirects followed; a chain of exactly 5 completes, a 6th fails with `Too many redirects`. |
| `DEFAULT_MAX_BODY_BYTES` | `16777216` | Default `max_body_bytes` of `request`: 16 MiB. |
| `DEFAULT_TIMEOUT_MS` | `30000` | Default `timeout_ms` of `request`: 30 seconds for the whole request. |
| `MAX_URL_LENGTH` | `8192` | Longest `url`, and longest redirect `Location` or resolved redirect target, in characters (the request-line limit common web servers use). |
| `MAX_RESPONSE_HEADERS` | `100` | Most response header lines accepted. |
| `MAX_RESPONSE_HEADER_CHARS` | `65536` | Most characters accepted across all response header lines together (64 KiB). |
| `KEY_OK` | `"ok"` | Result key `ok` (see the result dictionary below). |
| `KEY_STATUS` | `"status"` | Result key `status`. |
| `KEY_HEADERS` | `"headers"` | Result key `headers`. |
| `KEY_BODY_BYTES` | `"body_bytes"` | Result key `body_bytes`. |
| `KEY_BODY_TEXT` | `"body_text"` | Result key `body_text`. |
| `KEY_JSON` | `"json"` | Result key `json`. |
| `KEY_ERROR` | `"error"` | Result key `error`, present only on failure. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `request` | `static request(method: HTTPClient.Method, url: String, headers: Dictionary = {}, body: String = "", timeout_ms := DEFAULT_TIMEOUT_MS, max_body_bytes := DEFAULT_MAX_BODY_BYTES, max_redirects := MAX_REDIRECTS, redirect_validator := Callable()) -> Dictionary` (await) | The request entry point; see the rules below. `timeout_ms > 0` is a **total** deadline for the whole request, every redirect hop and phase included (30 s by default); `0` or less means none. `max_body_bytes > 0` fails the request with `Body too large` once the body (or its declared `Content-Length`) exceeds it; the default is 16 MiB, `0` or less means unlimited. `max_redirects` (clamped to 0-`MAX_REDIRECTS`) is how many redirects are followed; `0` follows none and returns the 3xx answer itself (`ok: true`, with its `Location` header). `redirect_validator` is an optional `func(target_url: String, status: int) -> bool` called before each redirect is followed; anything but `true` fails the request with `Redirect refused` and the target is never contacted. |

### Result dictionary (`request`)

Every result has every key below; `error` is present only on failure.

| Key | Meaning |
|---|---|
| `ok` | `true` for a complete response with status 200–399 (after following redirects). |
| `status` | Response code; `0` when no response arrived. On `Headers too large`, `Invalid Content-Length`, `Body too large`, `Body timeout`, `Truncated body`, `Insecure redirect`, `Invalid redirect`, `Redirect URL too long` and `Too many redirects` it is the code of the response that failed. |
| `headers` | Response headers (`{}` when none arrived). |
| `body_bytes` | Raw body; on `Body timeout` and `Truncated body`, the bytes received before the failure. |
| `body_text` | The body decoded as UTF-8 (a malformed byte becomes U+FFFD, with no engine error); `""` on failure. |
| `json` | Parsed body when `content-type` contains `application/json` and the body parses; otherwise `null`. Malformed JSON logs no engine error. |
| `error` | Why the request failed (table below). A completed non-2xx/3xx response is `ok: false` without an `error`. |

| `error` | Cause |
|---|---|
| `Invalid URL` | The URL is not a valid `http`/`https` URL for `LFUrl` (including any space or control character in it). Nothing is sent. |
| `URL too long` | The URL is longer than `MAX_URL_LENGTH`. Nothing is sent. |
| `Invalid header: <name>` | A caller header has an empty or non-token name, a control character (CR, LF, …) in its value, sets `Host`, `Content-Length` or `Transfer-Encoding` (any case), or repeats another name ignoring case. Nothing is sent. |
| `No SceneTree` | `Engine.get_main_loop()` is not a `SceneTree`. |
| `Connect error N`, `Request error N` | `HTTPClient.connect_to_host` / `request` returned error `N`. |
| `Cannot resolve host`, `Cannot connect`, `TLS handshake failed` | The connection could not be made. |
| `Connection lost` | The connection dropped before a response arrived (including a peer that closes without answering). |
| `Connect timeout`, `Header timeout`, `Body timeout` | The deadline passed in that phase. |
| `Headers too large` | The answer has more than `MAX_RESPONSE_HEADERS` header lines or more than `MAX_RESPONSE_HEADER_CHARS` characters of them. `headers` is `{}`. |
| `Invalid Content-Length` | A `Content-Length` that is not a non-negative integer of at most 18 digits, or two that differ. |
| `Body too large` | `max_body_bytes` exceeded. |
| `Truncated body` | The connection ended before the body did: fewer bytes than `Content-Length`, or a chunked body without its final chunk. On a web export only a connection that ended in an error counts (see Notes). |
| `Insecure redirect` | An https→http redirect. |
| `Invalid redirect` | A `Location` that does not resolve to an `http`/`https` URL. |
| `Redirect URL too long` | A `Location`, or the URL it resolves to, longer than `MAX_URL_LENGTH`. |
| `Too many redirects` | More than `max_redirects` (at most `MAX_REDIRECTS`) redirects. |
| `Redirect refused` | The `redirect_validator` did not return `true` for a redirect target. |
| `Body not resent to another origin` | A redirect that keeps the method and body (307, 308, or a 301/302 of a method other than POST) leads to another origin and the request has a non-empty body. |

## Rules

How it behaves in detail; skim this when something surprises you. The "origin" of an address is its scheme (`http`/`https`), host and port together.

- **Redirects** (301, 302, 303, 307, 308 with a `Location`) resolve against the current URL with `LFUrl.resolve` (`next`, `../x`, `?q`, `//host/x`, absolute, case-insensitive scheme). 301 and 302 turn a POST into a GET, and 303 turns any method but HEAD into a GET, each without the body and without the caller's `Content-*` headers; 307 and 308 resend the method and body, but only to the same origin: to another origin a request with a non-empty body fails with `Body not resent to another origin` (one without a body is followed). The `max_redirects` and `redirect_validator` options limit or vet every hop; `redirect_validator` sees the resolved absolute target, so use it to pin hosts. LFHttp does not itself refuse redirects to private or loopback addresses.
- **Windows, refused connections:** Godot 4.7.2 on Windows was seen never to report a refused loopback connection, so such a request ends with `Connect timeout` (when `timeout_ms` is set) instead of `Cannot connect`.
- **Credentials:** a redirect to another origin (scheme, host or effective port) resends only `Accept`, `Accept-Language`, `Content-Type`, `Content-Language` and `User-Agent`, so `Authorization`, `Cookie` and API-key headers never leave the first origin. Once dropped they stay dropped, even if a later redirect returns to the first origin.
- **Headers sent:** `Host` (bracketed for IPv6, with `:port` for a non-default port) and `Accept-Encoding: identity` are always set by the client (on a web export the browser sets its own `Accept-Encoding`); a caller `Accept-Encoding` is ignored. `User-Agent` defaults to `GodotHTTPClient/4.x` unless the caller sets one (any case).
- **Completeness:** a body is complete only when its `Content-Length` bytes arrived, a chunked body reached its final chunk, or a body without either ended with the connection. On a web export the length is not compared (see Notes). Anything else is `Truncated body`, and no JSON is parsed from it. A 1xx, 204 or 304 answer (and any answer to HEAD) has no body, even when it declares a `Content-Length`.

## Usage

```gdscript
# news_panel.gd: a script on any Node in your scene.
extends Node


func _ready() -> void:
	# GET with a 5 s deadline and a 1 MB size limit. The game keeps running meanwhile.
	var result: Dictionary = await LFHttp.request(
			HTTPClient.METHOD_GET, "https://api.example.com/news?page=1",
			{"Accept": "application/json"}, "", 5000, 1024 * 1024)
	if not result.ok:
		# "error" is set when no full answer arrived; otherwise the server said no (404, 500).
		push_warning("News failed: %s" % result.get("error", "status %d" % result.status))
		return
	if result.json != null:
		print(result.json)        # the parsed JSON: a Dictionary or an Array
	else:
		print(result.body_text)   # any other answer, as text


# POST a score as JSON. Returns true when the server accepted it.
func post_score(player_name: String, score: int) -> bool:
	var result: Dictionary = await LFHttp.request(
			HTTPClient.METHOD_POST, "https://api.example.com/scores",
			{"Content-Type": "application/json"},
			JSON.stringify({"name": player_name, "score": score}), 5000)
	return result.ok
```

## Notes

- **Deadline:** a request gives up after `DEFAULT_TIMEOUT_MS` (30 s) unless you pass another `timeout_ms`. With `timeout_ms = 0` it can wait forever on a server that keeps the connection open without finishing; one that closes the connection fails promptly with `Connection lost` or `Truncated body`. Pass a shorter deadline for anything a player waits on.
- **Hostile servers.** The header caps are checked after Godot's `HTTPClient` has read the whole header block: it buffers headers without a limit of its own, so a server that sends header lines without end is stopped only by the deadline. A `Content-Length` too large for a 64-bit integer, and malformed chunk sizes, make the engine itself log an error before `LFHttp` sees the answer; the request still fails (`Invalid Content-Length`, `Truncated body`). The URL cap also keeps a hostile `Location` from costing much to resolve.
- A redirect that keeps the body never sends it to another origin (see Rules), but it does resend it to the same origin, and `max_redirects = 0` is the way to take no redirect at all.
- The body is read at most 1 MiB per frame, so a fast or endless stream cannot freeze the game. The whole body is held in memory (and `body_text` and any parsed JSON are copies of it, so a body can cost several times its size); since 16 MiB is the default cap, a larger answer fails with `Body too large` unless you pass a bigger `max_body_bytes` or `0` (unlimited, which is only safe for servers you trust).
- A `user:password@` in the URL is not sent (no `Authorization` header is made from it).
- A repeated response header keeps only its last value in `headers` (several `Set-Cookie` lines collapse to one).
- A redirect status without a `Location` is returned as it is (`ok: true` for a 3xx).
- With two `Location` headers, the last one is followed.
- A body that is not valid UTF-8 is decoded into `body_text` with U+FFFD for each bad byte; use `body_bytes` for binary responses.
- **Web exports (untested).** Godot's `HTTPClient` goes through the browser's `fetch` there: the browser chooses `Accept-Encoding`, decompresses gzip/brotli bodies while `Content-Length` keeps the compressed size, and may hide headers of a cross-origin answer. So on the web `LFHttp` does not compare the body with `Content-Length`; a body is complete when the client ends in a connected or closed state, and `Truncated body` only comes from a connection that ended in an error. `max_body_bytes` still caps the bytes received. Cross-origin requests also need CORS headers from the server.
- The request body is a `String`, sent as UTF-8: there is no way to send a binary (`PackedByteArray`) request body.
- `request` needs a running scene tree (Godot's main loop), which exists whenever your game or a scene is running. If you call it from a command-line `-s` script, wait one frame first (`await` a frame) or you get `No SceneTree`. Always `await` it.
