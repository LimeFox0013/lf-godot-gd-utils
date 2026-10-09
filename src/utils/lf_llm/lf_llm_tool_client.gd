## Asks a language model to pick one of your tools: one request at a time, no more often
## than `min_interval_ms`, and null when it fails.
##
## It makes tool-calling requests through an `LFLlmProvider`, at most one at a time and no
## more often than `min_interval_ms`, each bounded by a deadline and a response-size cap.
## `await call_tool(system, user, tools)` resolves to `{name, input}` or null — null on
## every failure it checks for (not configured, throttled, a malformed tool, network error,
## oversized reply, refusal, no tool call), without a script error — so a caller that asks
## often (every frame, every update) just gets null while a request is pending or too
## recent. A script error raised inside a provider subclass's own code is not caught.
##
## An unconfigured provider is reported once (a warning naming its `setup_hint()`), not on
## every call; replacing it with another unconfigured one reports that one once too. A
## failed request is logged as a warning, and so is every call refused because a tool is
## not a valid tool definition (`LFLlmTool.is_valid_tool`) or the provider built no usable
## request; such a call sends nothing and leaves no request in flight.
class_name LFLlmToolClient
extends RefCounted

static var _log := LFLogger.new(['[LFLlmToolClient]'])

## A request's deadline when the constructor is not given a timeout.
const DEFAULT_TIMEOUT_MS := 30000
## The response cap when the constructor gets a non-positive one: a tool call is a few
## kilobytes.
const DEFAULT_MAX_RESPONSE_BYTES := 4 * 1024 * 1024

## Most characters of a failed request's reply text put in the warning.
const _LOG_BODY_CHARS := 300

## The provider requests go through. May be replaced at any time: a request in flight
## is still read by the provider that sent it. Null makes `call_tool` resolve to null.
var provider: LFLlmProvider
## Milliseconds that must pass after a request starts before the next may start.
var min_interval_ms: int:
	get:
		return int(_cooldown.interval_ms)
	set(value):
		_cooldown.interval_ms = value
## Milliseconds a whole request may take before it gives up; 0 or less means no deadline.
var timeout_ms: int
## Replies larger than this many bytes are dropped unread; 0 or less means no limit.
var max_response_bytes: int
## A Callable returning milliseconds that drives the interval; empty uses
## `Time.get_ticks_msec()`. May be replaced at any time. If it can no longer be called (its
## object was freed), `can_request_now()` is false and an error is reported once.
var clock_ms: Callable

var _cooldown: LFCooldown
var _in_flight := false
var _clock_error_reported := false
## Instance id of the provider last reported as unconfigured (or missing: 0); -1 for none.
var _warned_provider_id := -1


## Creates a client that sends through `llm_provider`, starting at most one request every
## `request_interval_ms`. `request_timeout_ms` is the deadline of a whole request: 0 or
## less means no deadline (as for `LFHttp`, `LFSocket` and `LFProcess`), so a stalled
## server keeps the request in flight; leave it out for `DEFAULT_TIMEOUT_MS`.
## `response_byte_limit` caps the reply body: 0 or less means no limit (as `max_body_bytes`
## of `LFHttp.request`); leave it out for `DEFAULT_MAX_RESPONSE_BYTES`.
## `initial_clock_ms`
## sets `clock_ms`; without it the interval runs on `Time.get_ticks_msec()`.
func _init(llm_provider: LFLlmProvider, request_interval_ms := 0, request_timeout_ms := DEFAULT_TIMEOUT_MS, response_byte_limit := DEFAULT_MAX_RESPONSE_BYTES, initial_clock_ms := Callable()) -> void:
	provider = llm_provider
	timeout_ms = maxi(request_timeout_ms, 0)
	max_response_bytes = maxi(response_byte_limit, 0)
	clock_ms = initial_clock_ms
	_cooldown = LFCooldown.new(request_interval_ms, _now_ms)


## Returns `true` when `call_tool()` right now would make a request: none in flight and the minimum
## interval since the last one has passed. Does not check `provider.is_configured()`.
func can_request_now() -> bool:
	if not clock_ms.is_null() and not clock_ms.is_valid():
		if not _clock_error_reported:
			_clock_error_reported = true
			_log.error('clock_ms can no longer be called; no request is made')
		return false
	return not _in_flight and _cooldown.is_ready()


## Returns `true` while a request is waiting for its reply.
func is_in_flight() -> bool:
	return _in_flight


## Sends one request built by the provider from `system` (standing instructions), `user`
## (this turn's text) and `tools` (from `LFLlmTool.define`), and resolves to its first tool
## call (`{name, input}`), or null when no request was made or it produced no call. A
## coroutine: always `await` it.
func call_tool(system: String, user: String, tools: Array) -> Variant:
	# The reply is read by the provider that built the request, even if `provider` is
	# replaced while it is in flight.
	var sender := provider
	if sender == null:
		_warn_unconfigured(0, 'no provider set')
		return null
	if not sender.is_configured():
		_warn_unconfigured(sender.get_instance_id(), '%s is not configured. %s' % [sender.display_name(), sender.setup_hint()])
		return null
	_warned_provider_id = -1
	if not can_request_now():
		return null
	for tool: Variant in tools:
		if not LFLlmTool.is_valid_tool(tool):
			_log.warning('not sent: a tool needs a non-empty String name, a String description and a Dictionary parameters; got %s' % [tool])
			return null
	# Built before anything is marked in flight, so a provider that fails here leaves the
	# client free for the next call.
	var request := sender.build_request(system, user, tools)
	if not (request.get(LFLlmProvider.KEY_URL) is String and request.get(LFLlmProvider.KEY_HEADERS) is Dictionary and request.get(LFLlmProvider.KEY_BODY) is Dictionary):
		_log.warning('not sent: %s built no {url, headers, body} request' % sender.display_name())
		return null
	_in_flight = true
	_cooldown.start()
	var response: Dictionary = await LFHttp.request(HTTPClient.METHOD_POST, request[LFLlmProvider.KEY_URL], request[LFLlmProvider.KEY_HEADERS], JSON.stringify(request[LFLlmProvider.KEY_BODY]), timeout_ms, max_response_bytes)
	_in_flight = false
	if not response.get(LFHttp.KEY_OK, false):
		_log.warning('%s request failed (status %s): %s' % [sender.display_name(), response.get(LFHttp.KEY_STATUS), _failure_detail(response)])
		return null
	return sender.extract_tool_call(response.get(LFHttp.KEY_JSON))


## Why a request failed, for a log line: the transport's error, else the start of the
## server's reply text with its line breaks escaped (the reply is untrusted and can be
## large, and a rejected request's reply can quote what was sent).
static func _failure_detail(response: Dictionary) -> String:
	if response.has(LFHttp.KEY_ERROR):
		return str(response[LFHttp.KEY_ERROR])
	var text := str(response.get(LFHttp.KEY_BODY_TEXT, ''))
	return text.left(_LOG_BODY_CHARS).c_escape() + ('...' if text.length() > _LOG_BODY_CHARS else '')


## Warns once per provider in a row: a different one (`id`) is reported again.
func _warn_unconfigured(id: int, message: String) -> void:
	if _warned_provider_id != id:
		_warned_provider_id = id
		_log.warning(message)


func _now_ms() -> int:
	if clock_ms.is_null():
		return Time.get_ticks_msec()
	return int(clock_ms.call()) if clock_ms.is_valid() else 0
