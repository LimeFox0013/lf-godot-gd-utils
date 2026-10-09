## Sends a web request (GET, POST, ...) and gives back the whole answer in one `await`.
##
## A coroutine HTTP client built on Godot's `HTTPClient` (a coroutine is a function you
## `await`; the rest of the program keeps running while it waits). It follows up to
## `MAX_REDIRECTS` redirects by default (301/302/303/307/308), uses TLS (encryption) for https, bounds the whole request by one deadline, refuses
## answers whose connection ended early and caller headers that could break the request,
## and parses JSON responses. All functions are static; call `LFHttp.request(...)`, never
## create an instance. Tested on desktop only; on a web export the browser makes the
## request and decompresses the body, so `Content-Length` is not used to judge completeness
## there.
class_name LFHttp

## HTTP status: moved permanently (a POST becomes a GET).
const _STATUS_MOVED_PERMANENTLY := 301
## HTTP status: found (a POST becomes a GET).
const _STATUS_FOUND := 302
## HTTP status: see other (every method but HEAD becomes a GET).
const _STATUS_SEE_OTHER := 303
## HTTP status: temporary redirect (method and body resent).
const _STATUS_TEMPORARY_REDIRECT := 307
## HTTP status: permanent redirect (method and body resent).
const _STATUS_PERMANENT_REDIRECT := 308
## HTTP status: no content (never has a body).
const _STATUS_NO_CONTENT := 204
## HTTP status: not modified (never has a body).
const _STATUS_NOT_MODIFIED := 304
## First status of the informational 1xx range (never has a body).
const _STATUS_INFORMATIONAL_MIN := 100
## First status of the 2xx success range; also the end (exclusive) of the 1xx range.
const _STATUS_SUCCESS_MIN := 200
## End (exclusive) of the statuses reported as `ok` (2xx and 3xx).
const _STATUS_OK_END := 400
## Statuses that are redirects when they carry a Location header.
const _REDIRECT_CODES := [
	_STATUS_MOVED_PERMANENTLY, _STATUS_FOUND, _STATUS_SEE_OTHER,
	_STATUS_TEMPORARY_REDIRECT, _STATUS_PERMANENT_REDIRECT,
]
## How many redirects are followed; one more fails the request with `Too many redirects`.
const MAX_REDIRECTS := 5
## Default `max_body_bytes` of [method request]: 16 MiB. A response body is held in memory
## (the bytes, their text and any parsed JSON, so a body can cost several times its size),
## so an uncapped read of a large answer can exhaust it. Pass 0 for no cap.
const DEFAULT_MAX_BODY_BYTES := 16 * 1024 * 1024
## Default `timeout_ms` of [method request], in milliseconds (30 seconds).
const DEFAULT_TIMEOUT_MS := 30000
## Longest URL, in characters, `request` accepts: a longer `url` fails with `URL too
## long`, and a redirect whose `Location` or resolved target is longer fails with
## `Redirect URL too long`. 8192 is the request-line limit common web servers use.
const MAX_URL_LENGTH := 8192
## Most response header lines accepted; an answer with more fails with `Headers too large`.
const MAX_RESPONSE_HEADERS := 100
## Most characters accepted across all response header lines together (64 KiB); an
## answer with more fails with `Headers too large`.
const MAX_RESPONSE_HEADER_CHARS := 65536
## Caller headers still sent after a redirect moves to another origin (lower-cased).
## Everything else — Authorization, Cookie, API keys — is dropped.
const _CROSS_ORIGIN_SAFE_HEADERS := ["accept", "accept-language", "content-type", "content-language", "user-agent"]
## Headers the client computes itself; a caller header with one of these names is refused.
const _FRAMING_HEADERS := ["host", "content-length", "transfer-encoding"]
## Characters allowed in a header name (an RFC 9110 token).
const _TOKEN_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~"
## User-Agent sent when the caller gives none.
const _DEFAULT_USER_AGENT := "GodotHTTPClient/4.x"
## URL scheme for plain HTTP.
const _SCHEME_HTTP := "http"
## URL scheme for HTTP over TLS.
const _SCHEME_HTTPS := "https"
## Response header naming a redirect target (lower-cased).
const _HEADER_LOCATION := "location"
## Response header naming the body length (lower-cased), with its separator.
const _CONTENT_LENGTH_PREFIX := "content-length:"
## Digits a Content-Length value may hold; more cannot be read as a 64-bit int.
const _MAX_CONTENT_LENGTH_DIGITS := 18
## Characters a Content-Length value may be made of.
const _DIGITS := "0123456789"
## Response header naming the transfer coding (lower-cased).
const _HEADER_TRANSFER_ENCODING := "transfer-encoding"
## Response header naming the body's media type (lower-cased).
const _HEADER_CONTENT_TYPE := "content-type"
## Caller header that replaces the default User-Agent (lower-cased).
const _HEADER_USER_AGENT_LOWER := "user-agent"
## Caller header that is ignored; the client always asks for an uncompressed body (on the
## web the browser sets this header itself).
const _HEADER_ACCEPT_ENCODING_LOWER := "accept-encoding"
## Name prefix of the headers describing a body, dropped with the body (lower-cased).
const _CONTENT_HEADER_PREFIX := "content-"
## Request line format of the Host header (host[:port]).
const _HOST_HEADER_FORMAT := "Host: %s"
## Request line format of the User-Agent header.
const _USER_AGENT_HEADER_FORMAT := "User-Agent: %s"
## Request line asking for an uncompressed body.
const _ACCEPT_ENCODING_IDENTITY := "Accept-Encoding: identity"
## Format of one caller header line (name, value).
const _HEADER_LINE_FORMAT := "%s: %s"
## Transfer coding that marks a chunked body.
const _CHUNKED := "chunked"
## Media type whose body is parsed as JSON.
const _JSON_MEDIA_TYPE := "application/json"
## Engine feature tag of a web export, where the browser makes the request.
const _FEATURE_WEB := "web"
## Request target used when the URL has no path.
const _ROOT_PATH := "/"
## Separator between the path and the query in a request target.
const _QUERY_SEPARATOR := "?"
## Lowest code point that is not a control character.
const _FIRST_PRINTABLE := 0x20
## Horizontal tab, the one control character allowed in a header value.
const _HTAB := 0x09
## DEL, a control character refused in a header value.
const _DEL := 0x7f
## HTTPClient refuses host names shorter than this many characters.
const _MIN_CONNECT_HOST_LENGTH := 4
## Zero group padded onto a short IPv6 literal to reach `_MIN_CONNECT_HOST_LENGTH`.
const _IPV6_ZERO_GROUP := "0"
## Key of the result `request` resolves to: true for a complete 2xx/3xx answer.
const KEY_OK := "ok"
## Result key: the HTTP status code (0 when none arrived).
const KEY_STATUS := "status"
## Result key: the response headers.
const KEY_HEADERS := "headers"
## Result key: the raw body.
const KEY_BODY_BYTES := "body_bytes"
## Result key: the body as UTF-8 text.
const KEY_BODY_TEXT := "body_text"
## Result key: the parsed JSON body, or null.
const KEY_JSON := "json"
## Result key: a short English failure reason, present only on failure.
const KEY_ERROR := "error"
## Most body bytes read before the game gets a frame back (1 MiB).
const _MAX_BYTES_PER_FRAME := 1048576
## Key of a head reading that is already the final result.
const _KEY_EARLY := "early"
## Redirect-step key: the next URL.
const _KEY_URL := "url"


## Sends a `method` request to `url` and returns the result once the whole answer has
## arrived (use `await`). It needs a running SceneTree. Follows up to `max_redirects`
## redirects (default and most [constant MAX_REDIRECTS]; 0 follows none and returns the
## 3xx answer itself). 301/302 turn a POST
## into a GET and 303 turns any method but HEAD into a GET, each without the body;
## 307/308 resend the method and body to the same origin, and fail with `Body not resent
## to another origin` instead of sending a non-empty body to a different one. A redirect to
## another origin (scheme, host or
## port) keeps only the caller headers that carry no credentials; an https→http
## redirect is refused. `redirect_validator`, when valid, is called as
## `validator(target_url: String, status: int) -> bool` before each redirect is followed;
## anything but `true` fails the request with `Redirect refused` (use it to pin hosts or refuse
## private addresses). `timeout_ms > 0` bounds the whole request, every hop and phase
## included (default [constant DEFAULT_TIMEOUT_MS], 30 s); 0 or less waits as long as the server
## keeps the connection open. `max_body_bytes > 0` caps the response body (default
## [constant DEFAULT_MAX_BODY_BYTES], 16 MiB); 0 or less is no cap. A `url` or
## redirect target longer than [constant MAX_URL_LENGTH], an answer with more header
## lines than [constant MAX_RESPONSE_HEADERS] or more header text than
## [constant MAX_RESPONSE_HEADER_CHARS], and a `Content-Length` that is not one
## non-negative integer each fail the request. `body` is sent as UTF-8 text. Resolves to a Dictionary with
## `ok`, `status`, `headers`, `body_bytes`, `body_text`, `json`, plus `error` (a short
## English reason) on failure. A bad URL or header fails at once without sending anything.
static func request(
	method: HTTPClient.Method,
	url: String,
	headers: Dictionary = {},
	body: String = "",
	timeout_ms := DEFAULT_TIMEOUT_MS,
	max_body_bytes := DEFAULT_MAX_BODY_BYTES,
	max_redirects := MAX_REDIRECTS,
	redirect_validator := Callable(),
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms if timeout_ms > 0 else 0
	if url.length() > MAX_URL_LENGTH:
		return _failure("URL too long")
	var current := LFUrl.parse(url)
	if !_is_http(current):
		return _failure("Invalid URL")
	var header_error := _check_headers(headers)
	if !header_error.is_empty():
		return _failure(header_error)
	var tree := LFUtils.tree_root
	if tree == null:
		return _failure("No SceneTree")

	var send_headers := headers
	var res := {}
	var allowed_hops := clampi(max_redirects, 0, MAX_REDIRECTS)
	for hop in allowed_hops + 1:
		res = await _single_request(tree, method, current, send_headers, body, deadline, max_body_bytes)
		if !res.ok or !_REDIRECT_CODES.has(res.status):
			return res
		var location := str(_header(res.headers, _HEADER_LOCATION))
		if location.is_empty() or allowed_hops == 0:
			return res
		if hop == allowed_hops:
			break
		var next := _next_hop(current, location, send_headers)
		if next.has(KEY_ERROR):
			return _failure(next.error, res.status, res.headers)
		var refusal := _redirect_refusal(res.status, current, next.url, method, body, redirect_validator)
		if !refusal.is_empty():
			return _failure(refusal, res.status, res.headers)
		current = next.url
		send_headers = next.headers
		if _redirect_drops_body(res.status, method):
			method = HTTPClient.METHOD_GET
			body = ""
			send_headers = _without_content_headers(send_headers)
	return _failure("Too many redirects", res.status, res.headers)


## Resolves a redirect `location` against `current`. Returns `{url: LFUrl.Parts, headers}`
## with the headers to send next (credentials stripped when the origin changes), or
## `{error}` for an unusable target or an https→http downgrade.
static func _next_hop(current: LFUrl.Parts, location: String, headers: Dictionary) -> Dictionary:
	if location.length() > MAX_URL_LENGTH:
		return { KEY_ERROR: "Redirect URL too long" }
	var to := LFUrl.resolve(str(current), location)
	if !_is_http(to):
		return { KEY_ERROR: "Invalid redirect" }
	if str(to).length() > MAX_URL_LENGTH:
		return { KEY_ERROR: "Redirect URL too long" }
	if current.scheme == _SCHEME_HTTPS and to.scheme == _SCHEME_HTTP:
		return { KEY_ERROR: "Insecure redirect" }
	var next_headers := headers
	if current.origin() != to.origin():
		next_headers = {}
		for k: Variant in headers.keys():
			if _CROSS_ORIGIN_SAFE_HEADERS.has(str(k).to_lower()):
				next_headers[k] = headers[k]
	return { _KEY_URL: to, KEY_HEADERS: next_headers }


## Why a redirect from `from` to `to` must not be followed, or "" when it may be: the
## caller's `validator` (called with the target URL text and the status) said no, or a 307/308
## would resend a non-empty `body` to another origin.
static func _redirect_refusal(status: int, from: LFUrl.Parts, to: LFUrl.Parts, method: HTTPClient.Method, body: String, validator: Callable) -> String:
	if validator.is_valid():
		var verdict: Variant = validator.call(str(to), status)
		if !(verdict is bool and verdict):
			return "Redirect refused"
	var keeps_body := !_redirect_drops_body(status, method)
	if keeps_body and !body.is_empty() and from.origin() != to.origin():
		return "Body not resent to another origin"
	return ""


static func _redirect_drops_body(status: int, method: HTTPClient.Method) -> bool:
	if status == _STATUS_SEE_OTHER:
		return method != HTTPClient.METHOD_HEAD
	return (status == _STATUS_MOVED_PERMANENTLY or status == _STATUS_FOUND) and method == HTTPClient.METHOD_POST


static func _without_content_headers(headers: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in headers.keys():
		if !str(k).to_lower().begins_with(_CONTENT_HEADER_PREFIX):
			out[k] = headers[k]
	return out


static func _is_http(u: LFUrl.Parts) -> bool:
	return u.is_valid() and (u.scheme == _SCHEME_HTTP or u.scheme == _SCHEME_HTTPS)


## Empty when every caller header is a valid token name with a value free of control
## characters, no name repeats (ignoring case) and none is a framing header.
static func _check_headers(headers: Dictionary) -> String:
	var seen := {}
	for k: Variant in headers.keys():
		var name := str(k)
		var lower := name.to_lower()
		var problem := name.is_empty() or seen.has(lower) or _FRAMING_HEADERS.has(lower)
		for i in name.length():
			if _TOKEN_CHARS.find(name[i]) == -1:
				problem = true
		var value := str(headers[k])
		for i in value.length():
			var c := value.unicode_at(i)
			if (c < _FIRST_PRINTABLE and c != _HTAB) or c == _DEL:
				problem = true
		if problem:
			return "Invalid header: %s" % name.c_escape()
		seen[lower] = true
	return ""


## Case-insensitive header lookup.
static func _header(hdrs: Dictionary, name: String) -> Variant:
	for k: Variant in hdrs.keys():
		if str(k).to_lower() == name:
			return hdrs[k]
	return ""


## HTTPClient refuses hosts shorter than four characters, which short IPv6 literals such
## as `::1` are; an equivalent spelling with a leading zero group is used for those.
static func _connect_host(u: LFUrl.Parts) -> String:
	var h := u.host
	if u.is_ipv6() and h.length() < _MIN_CONNECT_HOST_LENGTH:
		h = _IPV6_ZERO_GROUP + h
		if h.length() < _MIN_CONNECT_HOST_LENGTH:
			h += _IPV6_ZERO_GROUP
	return h


static func _expired(deadline: int) -> bool:
	return deadline > 0 and Time.get_ticks_msec() >= deadline


static func _status_error(status: HTTPClient.Status) -> String:
	match status:
		HTTPClient.STATUS_CANT_RESOLVE: return "Cannot resolve host"
		HTTPClient.STATUS_CANT_CONNECT: return "Cannot connect"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR: return "TLS handshake failed"
	return "Connection lost"


static func _failure(error: String, status := 0, headers := {}, bytes := PackedByteArray()) -> Dictionary:
	return {
		KEY_OK: false,
		KEY_STATUS: status,
		KEY_HEADERS: headers,
		KEY_BODY_BYTES: bytes,
		KEY_BODY_TEXT: "",
		KEY_JSON: null,
		KEY_ERROR: error,
	}


## One request/response exchange with no redirect handling: connects, sends, reads the
## head, then the body. Every phase returns a failure Dictionary (or an error text) at once.
static func _single_request(
	tree: SceneTree,
	method: HTTPClient.Method,
	u: LFUrl.Parts,
	headers: Dictionary,
	body: String,
	deadline: int,
	max_body_bytes: int,
) -> Dictionary:
	var client := HTTPClient.new()
	var error := await _connect(tree, client, u, deadline)
	if !error.is_empty():
		return _failure(error)
	error = await _send(tree, client, method, u, headers, body, deadline)
	if !error.is_empty():
		return _failure(error)
	var head := _read_head(client)
	if head.has(_KEY_EARLY):
		return head[_KEY_EARLY]
	return await _read_body(tree, client, head, deadline, max_body_bytes)


## Connects `client` to `u`. Returns "" once connected, else the failure reason.
static func _connect(tree: SceneTree, client: HTTPClient, u: LFUrl.Parts, deadline: int) -> String:
	var tls: TLSOptions = TLSOptions.client() if u.scheme == _SCHEME_HTTPS else null
	var err := client.connect_to_host(_connect_host(u), u.effective_port(), tls)
	# The engine refuses to start a connection (e.g. a host name it cannot use, or TLS unavailable).
	if err != OK:
		return "Connect error %s" % err
	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		client.poll()
		if _expired(deadline):
			client.close()
			return "Connect timeout"
		await tree.process_frame
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return _status_error(client.get_status())
	return ""


## The request header lines for `u`: Host, the caller's headers (Accept-Encoding dropped),
## a default User-Agent when the caller gave none, and `Accept-Encoding: identity`.
static func _header_lines(u: LFUrl.Parts, headers: Dictionary) -> PackedStringArray:
	var header_list := PackedStringArray([_HOST_HEADER_FORMAT % u.host_port()])
	var has_user_agent := false
	for k: Variant in headers.keys():
		var lower := str(k).to_lower()
		if lower == _HEADER_ACCEPT_ENCODING_LOWER:
			continue
		has_user_agent = has_user_agent or lower == _HEADER_USER_AGENT_LOWER
		header_list.push_back(_HEADER_LINE_FORMAT % [k, str(headers[k])])
	if !has_user_agent:
		header_list.push_back(_USER_AGENT_HEADER_FORMAT % _DEFAULT_USER_AGENT)
	header_list.push_back(_ACCEPT_ENCODING_IDENTITY)
	return header_list


## Sends the request and waits for the response head. Returns "" once it arrived, else the
## failure reason.
static func _send(
	tree: SceneTree,
	client: HTTPClient,
	method: HTTPClient.Method,
	u: LFUrl.Parts,
	headers: Dictionary,
	body: String,
	deadline: int,
) -> String:
	var target := u.path if !u.path.is_empty() else _ROOT_PATH
	if !u.query.is_empty():
		target += _QUERY_SEPARATOR + u.query
	var err := client.request(method, target, _header_lines(u, headers), body)
	# The engine refuses the request (e.g. the connection dropped between the poll and this call).
	if err != OK:
		client.close()
		return "Request error %s" % err
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if client.get_status() != HTTPClient.STATUS_REQUESTING:
			break
		if _expired(deadline):
			client.close()
			return "Header timeout"
		await tree.process_frame
	if !client.has_response():
		var lost := _status_error(client.get_status())
		client.close()
		return lost
	return ""


## Reads the response head. Returns `{status, lines, headers}`, or `{early: result}` when the
## answer is already final: too many headers, a bad Content-Length, or a status without a body.
static func _read_head(client: HTTPClient) -> Dictionary:
	var status := client.get_response_code()
	# The engine hands the header lines over only once, so the Dictionary is built here.
	var lines := client.get_response_headers()
	if _headers_too_large(lines):
		client.close()
		return { _KEY_EARLY: _failure("Headers too large", status) }
	var hdrs := _headers_dictionary(lines)
	if status == _STATUS_NO_CONTENT or status == _STATUS_NOT_MODIFIED or (status >= _STATUS_INFORMATIONAL_MIN and status < _STATUS_SUCCESS_MIN):
		# These answers never have a body, even when they carry a Content-Length.
		client.close()
		return { _KEY_EARLY: _response(status, hdrs, PackedByteArray()) }
	# The engine reads a negative length as one, and then fails every read until the deadline.
	if !_content_length_valid(lines):
		client.close()
		return { _KEY_EARLY: _failure("Invalid Content-Length", status, hdrs) }
	return { KEY_STATUS: status, KEY_HEADERS: hdrs }


## Reads the body of the response whose `head` `_read_head` returned, within `max_body_bytes`
## (0 or less: unlimited) and `deadline`.
static func _read_body(tree: SceneTree, client: HTTPClient, head: Dictionary, deadline: int, max_body_bytes: int) -> Dictionary:
	var status: int = head[KEY_STATUS]
	var hdrs: Dictionary = head[KEY_HEADERS]
	var declared := client.get_response_body_length()
	var chunked := str(_header(hdrs, _HEADER_TRANSFER_ENCODING)).to_lower().contains(_CHUNKED)
	if max_body_bytes > 0 and declared > max_body_bytes:
		client.close()
		return _failure("Body too large", status, hdrs)

	# The body is read without poll(): poll() drops the connection, and any bytes still
	# buffered, as soon as it sees the peer has closed. Reading reports the close itself.
	var bytes := PackedByteArray()
	var read_this_frame := 0
	while client.get_status() == HTTPClient.STATUS_BODY:
		var chunk := client.read_response_body_chunk()
		read_this_frame += chunk.size()
		if chunk.size() > 0:
			bytes.append_array(chunk)
			if max_body_bytes > 0 and bytes.size() > max_body_bytes:
				client.close()
				return _failure("Body too large", status, hdrs)
		if _expired(deadline):
			client.close()
			return _failure("Body timeout", status, hdrs, bytes)
		if chunk.is_empty() or read_this_frame >= _MAX_BYTES_PER_FRAME:
			read_this_frame = 0
			await tree.process_frame

	var end := client.get_status()
	client.close()
	if !_is_complete(declared, bytes.size(), chunked, end, _body_length_trusted()):
		return _failure("Truncated body", status, hdrs, bytes)
	return _response(status, hdrs, bytes)


## The header `lines` as `{name: value}`, both stripped, the last of a repeated name
## winning: what `HTTPClient.get_response_headers_as_dictionary()` returns.
static func _headers_dictionary(lines: PackedStringArray) -> Dictionary:
	var out := {}
	for line in lines:
		var colon := line.find(":")
		if colon != -1:
			out[line.substr(0, colon).strip_edges()] = line.substr(colon + 1).strip_edges()
	return out


## Whether the response header `lines` exceed MAX_RESPONSE_HEADERS lines or
## MAX_RESPONSE_HEADER_CHARS characters.
static func _headers_too_large(lines: PackedStringArray) -> bool:
	if lines.size() > MAX_RESPONSE_HEADERS:
		return true
	var chars := 0
	for line in lines:
		chars += line.length()
	return chars > MAX_RESPONSE_HEADER_CHARS


## Whether every Content-Length line among `lines` holds the same non-negative integer of
## at most _MAX_CONTENT_LENGTH_DIGITS digits (or there is none).
static func _content_length_valid(lines: PackedStringArray) -> bool:
	var value := ""
	for line in lines:
		if !line.to_lower().begins_with(_CONTENT_LENGTH_PREFIX):
			continue
		var digits := line.substr(_CONTENT_LENGTH_PREFIX.length()).strip_edges()
		if digits.is_empty() or digits.length() > _MAX_CONTENT_LENGTH_DIGITS or !_only_digits(digits):
			return false
		if !value.is_empty() and digits != value:
			return false
		value = digits
	return true


static func _only_digits(text: String) -> bool:
	for i in text.length():
		if _DIGITS.find(text[i]) == -1:
			return false
	return true


## Whether the body length the client reports matches the bytes it hands over. Not on the
## web: the browser decompresses a gzip or brotli body while `Content-Length` keeps the
## compressed size (and a cross-origin answer may hide its headers).
static func _body_length_trusted() -> bool:
	return !OS.has_feature(_FEATURE_WEB)


## Whether a body of `received` bytes that ended with the client in state `end` is whole:
## exactly `declared` bytes when that is known and `length_trusted`; a chunked body that
## reached its final chunk; otherwise a body that ended with the connection.
static func _is_complete(declared: int, received: int, chunked: bool, end: HTTPClient.Status, length_trusted: bool) -> bool:
	if length_trusted and declared >= 0:
		return received == declared
	if length_trusted and chunked:
		return end == HTTPClient.STATUS_CONNECTED
	return end == HTTPClient.STATUS_CONNECTED or end == HTTPClient.STATUS_DISCONNECTED


static func _response(status: int, hdrs: Dictionary, bytes: PackedByteArray) -> Dictionary:
	var text := LFText.decode_utf8_lossy(bytes)
	var json_val: Variant = null
	var ct := str(_header(hdrs, _HEADER_CONTENT_TYPE)).to_lower()
	if ct.find(_JSON_MEDIA_TYPE) != -1 and !text.is_empty():
		json_val = LFJson.parse(text)
	return {
		KEY_OK: status >= _STATUS_SUCCESS_MIN and status < _STATUS_OK_END,
		KEY_STATUS: status,
		KEY_HEADERS: hdrs,
		KEY_BODY_BYTES: bytes,
		KEY_BODY_TEXT: text,
		KEY_JSON: json_val,
	}
