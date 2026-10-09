extends GutTest

## Requests go to a one-shot HTTP server on an OS-picked 127.0.0.1 port.

const FINISH_REPLY := '{"choices":[{"message":{"tool_calls":[{"function":{"name":"finish","arguments":"{}"}}]}}]}'
const TOOLS := [{'name': 'finish', 'description': 'Finish the task.', 'parameters': {'type': 'object', 'properties': {}}}]

var _clock := [100000]


## Configured, but reads every reply as a call to `wrong`.
class WrongReader extends LFLlmProvider:
	func is_configured() -> bool:
		return true

	func extract_tool_call(_json: Variant) -> Variant:
		return {'name': 'wrong', 'input': {}}


func _now_ms() -> int:
	return _clock[0]


## Answers one request by running `respond(peer)`; the caller stops `server` afterwards.
func _serve_once(server: TCPServer, respond: Callable) -> void:
	var until := Time.get_ticks_msec() + 3000
	while not server.is_connection_available() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	if not server.is_connection_available():
		return
	var peer := server.take_connection()
	var request := ''
	while not request.contains('\r\n\r\n') and Time.get_ticks_msec() < until:
		peer.poll()
		if peer.get_available_bytes() > 0:
			request += peer.get_utf8_string(peer.get_available_bytes())
		else:
			await get_tree().process_frame
	await respond.call(peer)
	peer.disconnect_from_host()


## Writes `data` without blocking the frame, giving up when the peer goes away.
func _write(peer: StreamPeerTCP, data: PackedByteArray) -> void:
	var sent := 0
	var until := Time.get_ticks_msec() + 3000
	while sent < data.size() and Time.get_ticks_msec() < until:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return
		var result: Array = peer.put_partial_data(data.slice(sent, sent + 65536))
		if result[0] != OK:
			return
		sent += int(result[1])
		await get_tree().process_frame


func _json_reply(body: String, status := '200 OK') -> Callable:
	return func(peer: StreamPeerTCP) -> void:
		var bytes := body.to_utf8_buffer()
		await _write(peer, ('HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n' % [status, bytes.size()]).to_utf8_buffer() + bytes)


## Runs `call_tool()` for at most `ms`; returns {done, call}.
func _call_within(client: LFLlmToolClient, ms: int) -> Dictionary:
	var box := {'done': false, 'call': null}
	var runner := func() -> void:
		box.call = await client.call_tool('system', 'user', TOOLS)
		box.done = true
	runner.call()
	var until := Time.get_ticks_msec() + ms
	while not box.done and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	return box


func _local_client(server: TCPServer, timeout_ms := 3000, max_bytes := 0, interval_ms := 0) -> LFLlmToolClient:
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var url := 'http://127.0.0.1:%d/v1' % server.get_local_port()
	return LFLlmToolClient.new(LFOpenAiCompatibleProvider.new(url, 'local-model'), interval_ms, timeout_ms, max_bytes, _now_ms)


func test_a_local_endpoints_tool_call_comes_back():
	var server := TCPServer.new()
	var client := _local_client(server)
	_serve_once(server, _json_reply(FINISH_REPLY))

	var result := await _call_within(client, 5000)
	server.stop()

	assert_true(result.done)
	assert_eq(result.call, {'name': 'finish', 'input': {}})


func test_an_error_status_resolves_to_null_even_with_a_tool_call_in_the_body():
	var server := TCPServer.new()
	var client := _local_client(server)
	_serve_once(server, _json_reply(FINISH_REPLY, '500 Internal Server Error'))

	var result := await _call_within(client, 5000)
	server.stop()

	assert_true(result.done)
	assert_null(result.call)
	assert_false(client.is_in_flight())


func test_the_constructor_fields_and_the_interval_property():
	var provider := LFOpenAiCompatibleProvider.new()
	var client := LFLlmToolClient.new(provider, 250, 1000, 2048)

	assert_true(is_same(client.provider, provider))
	assert_eq([client.min_interval_ms, client.timeout_ms, client.max_response_bytes], [250, 1000, 2048])
	assert_true(client.clock_ms.is_null())
	client.min_interval_ms = 500
	assert_eq(client.min_interval_ms, 500)


func test_an_unconfigured_provider_makes_no_request():
	var client := LFLlmToolClient.new(LFOpenAiCompatibleProvider.new())

	assert_null(await client.call_tool('s', 'u', TOOLS))
	assert_false(client.is_in_flight())


func test_requests_are_one_at_a_time_and_a_minimum_interval_apart():
	var server := TCPServer.new()
	var client := _local_client(server, 3000, 0, 3000)
	assert_true(client.can_request_now())

	var box := {'done': false}
	var runner := func() -> void:
		await client.call_tool('system', 'user', TOOLS)
		box.done = true
	runner.call()
	assert_true(client.is_in_flight())
	assert_false(client.can_request_now(), 'one request at a time')
	assert_null(await client.call_tool('s', 'u', TOOLS), 'a call while one is in flight is refused')
	await _serve_once(server, _json_reply(FINISH_REPLY))
	var until := Time.get_ticks_msec() + 3000
	while not box.done and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	server.stop()

	assert_true(box.done)

	assert_false(client.is_in_flight())
	assert_false(client.can_request_now(), 'too soon after the last')
	_clock[0] += 2999
	assert_false(client.can_request_now(), 'just short of the interval')
	_clock[0] += 1
	assert_true(client.can_request_now(), 'at the interval')


func test_a_clock_replaced_after_construction_drives_the_interval():
	var client := LFLlmToolClient.new(LFOpenAiCompatibleProvider.new(), 1000)
	var mine := [5000]
	client.clock_ms = func() -> int: return mine[0]
	client._cooldown.start()
	assert_false(client.can_request_now())
	mine[0] += 1000
	assert_true(client.can_request_now())


func test_a_response_over_the_size_cap_is_dropped():
	var server := TCPServer.new()
	var client := _local_client(server, 3000, 1024)
	_serve_once(server, _json_reply(FINISH_REPLY + ' '.repeat(4096)))

	var result := await _call_within(client, 5000)
	server.stop()

	assert_true(result.done)
	assert_null(result.call, 'an oversized reply is dropped, however valid')
	assert_false(client.is_in_flight())


func test_a_stalling_endpoint_cannot_keep_a_request_in_flight_past_the_timeout():
	var server := TCPServer.new()
	var client := _local_client(server, 400)
	var drip := func(peer: StreamPeerTCP) -> void:
		await _write(peer, 'HTTP/1.1 200 OK\r\nContent-Length: 100000\r\nConnection: close\r\n\r\n'.to_utf8_buffer())
		var until := Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < until and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.put_data(' '.to_utf8_buffer())
			var next := Time.get_ticks_msec() + 100
			while Time.get_ticks_msec() < next:
				await get_tree().process_frame
	_serve_once(server, drip)

	var result := await _call_within(client, 2500)
	server.stop()

	assert_true(result.done, 'the request gave up at its timeout although bytes kept arriving')
	assert_null(result.call)
	assert_false(client.is_in_flight())


func test_a_non_positive_timeout_means_no_deadline_and_a_non_positive_byte_limit_no_cap():
	var client := LFLlmToolClient.new(LFOpenAiCompatibleProvider.new(), 0, 0, -1)

	assert_eq(client.timeout_ms, 0, '0 means no deadline, as in LFHttp')
	assert_eq(client.max_response_bytes, 0, 'a negative cap is stored as 0: no limit')
	assert_eq(LFLlmToolClient.new(LFOpenAiCompatibleProvider.new(), 0, 0, 0).max_response_bytes, 0)
	assert_eq(LFLlmToolClient.new(LFOpenAiCompatibleProvider.new()).max_response_bytes, LFLlmToolClient.DEFAULT_MAX_RESPONSE_BYTES, 'left out: the default')
	assert_eq(LFLlmToolClient.new(LFOpenAiCompatibleProvider.new(), 0, -5).timeout_ms, 0)
	assert_eq(LFLlmToolClient.new(LFOpenAiCompatibleProvider.new()).timeout_ms, LFLlmToolClient.DEFAULT_TIMEOUT_MS, 'left out: the default')


func test_a_provider_replaced_mid_request_does_not_read_the_reply():
	var server := TCPServer.new()
	var client := _local_client(server)
	_serve_once(server, _json_reply(FINISH_REPLY))

	var box := {'done': false, 'call': null}
	var runner := func() -> void:
		box.call = await client.call_tool('system', 'user', TOOLS)
		box.done = true
	runner.call()
	client.provider = WrongReader.new()
	var until := Time.get_ticks_msec() + 5000
	while not box.done and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	server.stop()

	assert_true(box.done)
	assert_eq(box.call, {'name': 'finish', 'input': {}}, 'the provider that sent the request reads its reply')


func test_a_null_provider_resolves_to_null():
	var client := LFLlmToolClient.new(null)

	assert_null(await client.call_tool('s', 'u', TOOLS))
	assert_false(client.is_in_flight())


## A Claude provider whose key variable is one every test machine has (`PATH`), so it is
## configured; nothing is sent from these tests before the tools are checked.
func _configured_anthropic() -> LFAnthropicProvider:
	return LFAnthropicProvider.new('model', 'PATH')


func test_a_tool_without_a_description_is_refused_and_the_client_stays_usable():
	var server := TCPServer.new()
	var client := _local_client(server)
	client.provider = _configured_anthropic()
	client.provider.api_url = 'http://127.0.0.1:%d/v1/messages' % server.get_local_port()
	var broken := [{'name': 'finish', 'parameters': {'type': 'object', 'properties': {}}}]

	assert_null(await client.call_tool('s', 'u', broken))
	assert_false(client.is_in_flight(), 'a refused call leaves nothing in flight')
	assert_true(client.can_request_now(), 'and starts no interval')
	assert_push_warning('description')

	_serve_once(server, _json_reply('{"content":[{"type":"tool_use","name":"finish","input":{}}]}'))
	var later := await _call_within(client, 5000)
	server.stop()
	assert_eq(later.call, {'name': 'finish', 'input': {}}, 'the next valid call goes through')


func test_tools_that_are_not_tool_dictionaries_are_refused():
	var client := LFLlmToolClient.new(_configured_anthropic())

	for tools in [['finish'], [{'description': 'd', 'parameters': {}}], [{'name': 'n', 'description': 'd', 'parameters': 'x'}]]:
		assert_null(await client.call_tool('s', 'u', tools))
	assert_false(client.is_in_flight())


## Builds no request at all: the base class's `{}`.
class EmptyRequestProvider extends LFLlmProvider:
	func is_configured() -> bool:
		return true


func test_a_provider_that_builds_no_request_is_refused_without_getting_stuck():
	var client := LFLlmToolClient.new(EmptyRequestProvider.new())

	assert_null(await client.call_tool('s', 'u', TOOLS))
	assert_false(client.is_in_flight())
	assert_true(client.can_request_now())


func test_each_unconfigured_provider_in_turn_is_warned_about_once():
	var client := LFLlmToolClient.new(LFOpenAiCompatibleProvider.new())
	await client.call_tool('s', 'u', TOOLS)
	await client.call_tool('s', 'u', TOOLS)
	assert_push_warning_count(1, 'the same provider is reported once')

	client.provider = LFAnthropicProvider.new('model', 'LF_TEST_UNSET_KEY_VARIABLE')
	await client.call_tool('s', 'u', TOOLS)
	await client.call_tool('s', 'u', TOOLS)

	assert_push_warning('LF_TEST_UNSET_KEY_VARIABLE', 'a second unconfigured provider is reported too')


func test_an_endpoint_nobody_listens_on_resolves_to_null_with_a_warning():
	var server := TCPServer.new()
	assert_eq(server.listen(0, '127.0.0.1'), OK)
	var port := server.get_local_port()
	server.stop()
	var client := LFLlmToolClient.new(LFOpenAiCompatibleProvider.new('http://127.0.0.1:%d/v1' % port, 'local-model'), 0, 3000)

	var result := await _call_within(client, 5000)

	assert_true(result.done)
	assert_null(result.call)
	assert_false(client.is_in_flight())
	assert_push_warning('local-model request failed')


func test_an_error_status_is_reported_with_its_status():
	var server := TCPServer.new()
	var client := _local_client(server)
	_serve_once(server, _json_reply('{"error": "overloaded"}', '529 Overloaded'))

	await _call_within(client, 5000)
	server.stop()

	assert_push_warning('status 529')


func test_the_warning_for_a_failed_request_quotes_a_long_error_body_only_in_part():
	var secret_tail := 'TAIL-' + 'x'.repeat(50)
	var body := 'first line\nforged: warning ' + 'y'.repeat(2000) + secret_tail
	var text := LFLlmToolClient._failure_detail({LFHttp.KEY_BODY_TEXT: body})

	assert_lt(text.length(), 400)
	assert_false(text.contains('TAIL-'))
	assert_false(text.contains('\n'), 'a body cannot start a log line of its own')
	assert_eq(LFLlmToolClient._failure_detail({LFHttp.KEY_ERROR: 'Body too large', LFHttp.KEY_BODY_TEXT: 'z'}), 'Body too large')
	assert_eq(LFLlmToolClient._failure_detail({LFHttp.KEY_BODY_TEXT: 'overloaded'}), 'overloaded')


## Configured only while `ready` is true; builds no request.
class SwitchableProvider extends LFLlmProvider:
	var ready := false

	func is_configured() -> bool:
		return ready

	func setup_hint() -> String:
		return 'Flip ready.'


func test_a_provider_that_was_configured_in_between_is_warned_about_again():
	var provider := SwitchableProvider.new()
	var client := LFLlmToolClient.new(provider)
	await client.call_tool('s', 'u', TOOLS)
	assert_push_warning('Flip ready.')
	provider.ready = true
	await client.call_tool('s', 'u', TOOLS)
	provider.ready = false
	await client.call_tool('s', 'u', TOOLS)
	await client.call_tool('s', 'u', TOOLS)

	assert_push_warning_count(3, 'unconfigured, built no request, unconfigured again (once)')


func test_a_missing_provider_is_warned_about_once():
	var client := LFLlmToolClient.new(null)
	await client.call_tool('s', 'u', TOOLS)
	await client.call_tool('s', 'u', TOOLS)
	assert_push_warning('no provider set')
	assert_push_warning_count(1)


class ClockHolder:
	extends Object
	func now() -> int:
		return 0


func test_a_freed_clock_fails_closed_and_errors_once():
	var holder := ClockHolder.new()
	var client := LFLlmToolClient.new(LFOpenAiCompatibleProvider.new(), 0, 1000, 2048, holder.now)
	assert_true(client.can_request_now())
	holder.free()

	assert_false(client.can_request_now())
	assert_false(client.can_request_now())
	assert_push_error_count(1, 'reported once, however often it is read')
