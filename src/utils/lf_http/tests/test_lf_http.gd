extends GutTest

## Runs a small hand-rolled HTTP server on 127.0.0.1 (an OS-assigned port) so the client
## can be exercised end to end against crafted responses.

class MockHttpServer:
	var _server := TCPServer.new()
	var _peers: Array[StreamPeerTCP] = []
	var _stopped := false
	var port := 0
	## The raw text (headers and body) of every request received, in order.
	var requests: Array[String] = []

	func _init(ip := "127.0.0.1") -> void:
		if _server.listen(0, ip) == OK:
			port = _server.get_local_port()

	## The last request received, or "".
	func last_request() -> String:
		return requests[-1] if !requests.is_empty() else ""

	## Serves one connection per entry of `responses`, in order. A String entry is sent
	## verbatim and the connection closed; a Callable entry is awaited as
	## `entry(peer: StreamPeerTCP, request: String)` before closing.
	func serve(responses: Array) -> void:
		for response in responses:
			var peer := await _accept()
			if peer == null:
				return
			var req := await _read_request(peer)
			requests.append(req)
			if response is Callable:
				await response.call(peer, req)
			else:
				peer.put_data(str(response).to_utf8_buffer())
			await Engine.get_main_loop().process_frame
			peer.disconnect_from_host()

	func stop() -> void:
		_stopped = true
		for peer in _peers:
			peer.disconnect_from_host()
		_server.stop()

	func _accept() -> StreamPeerTCP:
		var deadline := Time.get_ticks_msec() + 3000
		while !_stopped and Time.get_ticks_msec() < deadline:
			if _server.is_connection_available():
				var peer := _server.take_connection()
				_peers.append(peer)
				return peer
			await Engine.get_main_loop().process_frame
		return null

	## Reads up to the end of the headers plus `Content-Length` body bytes.
	func _read_request(peer: StreamPeerTCP) -> String:
		var buf := PackedByteArray()
		var deadline := Time.get_ticks_msec() + 2000
		while !_stopped and Time.get_ticks_msec() < deadline:
			peer.poll()
			var n := peer.get_available_bytes()
			if n > 0:
				buf.append_array(peer.get_data(n)[1])
				var text := buf.get_string_from_utf8()
				var end := text.find("\r\n\r\n")
				if end != -1 and buf.size() >= end + 4 + _content_length(text.substr(0, end)):
					return text
			else:
				await Engine.get_main_loop().process_frame
		return buf.get_string_from_utf8()

	func _content_length(head: String) -> int:
		for line in head.split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				return line.substr(15).strip_edges().to_int()
		return 0


## Body cap smaller than the 100-byte body served, so the declared length is refused.
const _SMALL_BODY_CAP := 50
## Body cap below the ten 1024-byte chunks streamed, so the running total is refused.
const _CHUNKED_BODY_CAP := 1000
## Deadline shared by a 300 ms redirect hop and a hop that never answers.
const _SHARED_DEADLINE_MS := 600
## Upper bound on how long the shared-deadline request may take.
const _SHARED_DEADLINE_BOUND_MS := 1500
## Redirects followed before the next one fails (mirrors LFHttp.MAX_REDIRECTS).
const _REDIRECT_LIMIT := 5

## Deadline of the endless-body request.
const _ENDLESS_DEADLINE_MS := 1000
## Frames that must pass during it (a starved loop manages a handful).
const _ENDLESS_MIN_FRAMES := 20

var server: MockHttpServer


func after_each():
	if server:
		server.stop()
		server = null


func _url(path: String, s: MockHttpServer = server) -> String:
	return "http://127.0.0.1:%d%s" % [s.port, path]


func _ok(body := "", extra := "") -> String:
	return "HTTP/1.1 200 OK\r\n%sContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [extra, body.to_utf8_buffer().size(), body]


func _redirect(location: String, code := 302) -> String:
	return "HTTP/1.1 %d Moved\r\nLocation: %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % [code, location]


## Awaits `call` for at most `ms`; returns {done, res, elapsed}.
func _within(call: Callable, ms: int) -> Dictionary:
	var box := { "done": false, "res": null }
	var runner := func() -> void:
		box.res = await call.call()
		box.done = true
	runner.call()
	var t0 := Time.get_ticks_msec()
	while !box.done and Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
	return { "done": box.done, "res": box.res, "elapsed": Time.get_ticks_msec() - t0 }


## Serves `responses` while `request` runs; returns the request's result.
func _exchange(responses: Array, method: HTTPClient.Method, url: String, headers := {}, body := "", timeout_ms := 3000, max_body_bytes := 0) -> Dictionary:
	server.serve(responses)
	var r := await _within(func(): return await LFHttp.request(method, url, headers, body, timeout_ms, max_body_bytes), 5000)
	assert_true(r.done, "the request resolved")
	return r.res if r.done else {}


func before_each():
	server = MockHttpServer.new()


func test_a_plain_200_response_is_reported_ok_with_its_body():
	var res := await _exchange([_ok("hello", "Content-Type: text/plain\r\n")], HTTPClient.METHOD_GET, _url("/"))

	assert_true(res.ok)
	assert_eq(res.status, 200)
	assert_eq(res.body_text, "hello")
	assert_false(res.has("error"))


func test_a_redirect_to_another_server_is_followed_to_the_final_response():
	var other := MockHttpServer.new()
	other.serve([_ok("final-ok")])

	var res := await _exchange([_redirect(_url("/final", other))], HTTPClient.METHOD_GET, _url("/start"))
	other.stop()

	assert_true(res.ok)
	assert_eq(res.status, 200)
	assert_eq(res.body_text, "final-ok")


func test_a_json_content_type_response_is_parsed_into_structured_data():
	var body := '{"ok":true,"count":2}'
	var res := await _exchange([_ok(body, "Content-Type: application/json\r\n")], HTTPClient.METHOD_GET, _url("/"))

	assert_eq(res.json, {"ok": true, "count": 2.0})
	assert_eq(res.body_text, body)


func test_a_malformed_json_body_gives_null_json_without_an_engine_error():
	var body := '{"broken":'
	var res := await _exchange([_ok(body, "Content-Type: application/json\r\n")], HTTPClient.METHOD_GET, _url("/"))

	assert_eq(res.json, null)
	assert_eq(res.body_text, body)
	assert_engine_error_count(0, "parsing the body must be quiet")


func test_a_malformed_or_non_http_url_is_rejected_before_connecting():
	for url in ["not a url", "ws://127.0.0.1:%d/" % server.port, "http://127.0.0.1:%d/a b" % server.port]:
		var res: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, url)
		assert_false(res.ok)
		assert_eq(res.error, "Invalid URL", url)


func test_a_crlf_in_the_url_path_is_rejected():
	var res: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, _url("/a HTTP/1.1\r\nX-Injected: yes\r\nFoo: x"))

	assert_eq(res.error, "Invalid URL")
	assert_eq(server.requests.size(), 0)


func test_a_failure_result_carries_every_key():
	var res: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, "not a url")

	for key in ["ok", "status", "headers", "body_bytes", "body_text", "json", "error"]:
		assert_true(res.has(key), key)


func test_a_303_redirect_is_followed_with_get_and_no_body():
	await _exchange([_redirect("/done", 303), _ok()], HTTPClient.METHOD_POST, _url("/form"), {"Content-Type": "text/plain"}, "secret=1")

	assert_eq(server.requests.size(), 2)
	assert_true(server.requests[0].contains("secret=1"), "the first hop carries the body")
	assert_true(server.requests[1].begins_with("GET /done "), "303 means: fetch the new location with GET")
	assert_false(server.requests[1].contains("secret=1"), "the body is not resent")
	assert_false(server.requests[1].to_lower().contains("content-type"), "nor the headers describing it")


func test_a_301_or_302_turns_a_post_into_a_get_without_its_body():
	for code in [301, 302]:
		server.stop()
		server = MockHttpServer.new()
		await _exchange([_redirect("/next", code), _ok()], HTTPClient.METHOD_POST, _url("/p"), {}, "prompt=secret")

		assert_true(server.requests[1].begins_with("GET /next "), "%d turns POST into GET" % code)
		assert_false(server.requests[1].contains("prompt=secret"), "%d drops the body" % code)


func test_a_307_or_308_keeps_the_method_and_body():
	for code in [307, 308]:
		server.stop()
		server = MockHttpServer.new()
		await _exchange([_redirect("/next", code), _ok()], HTTPClient.METHOD_POST, _url("/p"), {}, "prompt=kept")

		assert_true(server.requests[1].begins_with("POST /next "), "%d keeps POST" % code)
		assert_true(server.requests[1].contains("prompt=kept"), "%d keeps the body" % code)


func test_a_302_keeps_a_put_as_a_put():
	await _exchange([_redirect("/next"), _ok()], HTTPClient.METHOD_PUT, _url("/p"), {}, "data")

	assert_true(server.requests[1].begins_with("PUT /next "))


func test_relative_locations_resolve_against_the_current_url():
	var cases := [
		["/start", "next", "GET /next "],
		["/a/b/c", "../x", "GET /a/x "],
		["/a/b", "?q=1", "GET /a/b?q=1 "],
		["/a/b", "#frag", "GET /a/b "],
		["/x", "/root", "GET /root "],
	]
	for c in cases:
		server.stop()
		server = MockHttpServer.new()
		var res := await _exchange([_redirect(c[1]), _ok()], HTTPClient.METHOD_GET, _url(c[0]))

		assert_true(res.ok, "%s + %s" % [c[0], c[1]])
		assert_true(server.last_request().begins_with(c[2]), "%s + %s requests %s, got %s" % [c[0], c[1], c[2], server.last_request().get_slice("\r\n", 0)])


func test_a_network_path_location_moves_to_the_other_host():
	# "localhost" resolves to ::1 first on Windows, so the server listens on both families.
	server.stop()
	server = MockHttpServer.new("*")
	await _exchange([_redirect("//localhost:%d/x" % server.port), _ok()], HTTPClient.METHOD_GET, _url("/a"))

	assert_true(server.last_request().begins_with("GET /x "))
	assert_true(server.last_request().contains("Host: localhost:%d" % server.port))


func test_five_redirects_are_followed_and_a_sixth_fails():
	var five := []
	for i in _REDIRECT_LIMIT:
		five.append(_redirect("/r%d" % (i + 1)))
	five.append(_ok("done"))
	var res := await _exchange(five, HTTPClient.METHOD_GET, _url("/r0"))
	assert_true(res.ok, "a chain of exactly 5 redirects completes")
	assert_eq(res.get("body_text"), "done")

	server.stop()
	server = MockHttpServer.new()
	var six := []
	for i in _REDIRECT_LIMIT + 1:
		six.append(_redirect("/r%d" % (i + 1), 307))
	res = await _exchange(six, HTTPClient.METHOD_GET, _url("/r0"))
	assert_false(res.ok)
	assert_eq(res.error, "Too many redirects")
	assert_eq(res.status, 307, "the last redirect status is kept")
	assert_eq(server.requests.size(), _REDIRECT_LIMIT + 1)


func test_a_cross_origin_redirect_keeps_only_non_credential_headers():
	var other := MockHttpServer.new()
	other.serve([_ok()])
	var headers := {
		"Authorization": "Bearer top-secret",
		"x-api-key": "key-secret",
		"Cookie": "session=secret",
		"Content-Type": "application/json",
		"Accept": "text/csv",
	}

	var res := await _exchange([_redirect(_url("/final", other))], HTTPClient.METHOD_GET, _url("/start"), headers)
	other.stop()

	assert_true(res.ok)
	assert_true(server.last_request().contains("top-secret"), "the first hop carries the caller's headers")
	var second := other.last_request()
	assert_false(second.contains("top-secret"), "Authorization is not sent to another origin")
	assert_false(second.contains("key-secret"), "an api-key header is not sent to another origin")
	assert_false(second.contains("session=secret"), "Cookie is not sent to another origin")
	assert_true(second.contains("Content-Type: application/json"), "Content-Type survives")
	assert_true(second.contains("Accept: text/csv"), "Accept survives")


func test_a_same_origin_redirect_keeps_the_caller_headers():
	await _exchange([_redirect("/next"), _ok()], HTTPClient.METHOD_GET, _url("/x"), {"Authorization": "Bearer same"})

	assert_true(server.last_request().contains("Bearer same"))


func test_an_https_to_http_redirect_is_refused():
	var hop: Dictionary = LFHttp._next_hop(LFUrl.parse("https://example.com/a"), "http://example.com/b", {"Authorization": "x"})
	assert_eq(hop.get("error"), "Insecure redirect")

	var ok_hop: Dictionary = LFHttp._next_hop(LFUrl.parse("http://example.com/a"), "https://example.com/b", {"Authorization": "x"})
	assert_false(ok_hop.has("error"), "an upgrade is allowed")
	assert_eq(str(ok_hop.url), "https://example.com/b")
	assert_false(ok_hop.headers.has("Authorization"), "a scheme change is a different origin")


func test_a_redirect_to_a_non_http_url_is_refused():
	var res := await _exchange([_redirect("ws://127.0.0.1:%d/" % server.port)], HTTPClient.METHOD_GET, _url("/"))

	assert_false(res.ok)
	assert_eq(res.error, "Invalid redirect")


func test_the_host_header_carries_a_non_default_port():
	await _exchange([_ok()], HTTPClient.METHOD_GET, _url("/"))

	assert_true(server.last_request().contains("Host: 127.0.0.1:%d\r\n" % server.port))


func test_the_host_header_brackets_an_ipv6_address():
	var v6 := MockHttpServer.new("::1")
	if v6.port == 0:
		pass_test("no IPv6 loopback on this machine")
		return
	v6.serve([_ok("v6")])
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, "http://[::1]:%d/" % v6.port, {}, "", 3000), 5000)
	v6.stop()

	assert_true(r.done)
	assert_eq(r.res.get("body_text"), "v6")
	assert_true(v6.last_request().contains("Host: [::1]:%d\r\n" % v6.port))


func test_a_body_declared_over_max_body_bytes_is_an_error():
	var res := await _exchange([_ok("0123456789".repeat(10))], HTTPClient.METHOD_GET, _url("/"), {}, "", 3000, _SMALL_BODY_CAP)

	assert_false(res.ok)
	assert_eq(res.error, "Body too large")


func test_a_chunked_body_over_max_body_bytes_is_an_error():
	var chunks := func(peer: StreamPeerTCP, _req: String) -> void:
		peer.put_data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n".to_utf8_buffer())
		for i in 10:
			peer.put_data(("400\r\n" + "y".repeat(1024) + "\r\n").to_utf8_buffer())
			await Engine.get_main_loop().process_frame
		peer.put_data("0\r\n\r\n".to_utf8_buffer())
	var res := await _exchange([chunks], HTTPClient.METHOD_GET, _url("/"), {}, "", 3000, _CHUNKED_BODY_CAP)

	assert_false(res.ok)
	assert_eq(res.error, "Body too large")


func test_a_complete_chunked_body_is_ok():
	var res := await _exchange(["HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n"], HTTPClient.METHOD_GET, _url("/"))

	assert_true(res.ok)
	assert_eq(res.body_text, "abcde")


func test_a_body_shorter_than_its_content_length_is_a_failure():
	var res := await _exchange(["HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 100\r\nConnection: close\r\n\r\n{\"a\":1}   "], HTTPClient.METHOD_GET, _url("/"))

	assert_false(res.ok)
	assert_eq(res.error, "Truncated body")
	assert_eq(res.json, null, "no JSON is parsed from a partial body")


func test_a_chunked_body_cut_off_mid_stream_is_a_failure():
	var res := await _exchange(["HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n5\r\nab"], HTTPClient.METHOD_GET, _url("/"))

	assert_false(res.ok)
	assert_eq(res.error, "Truncated body")


func test_a_body_read_until_close_is_ok():
	var res := await _exchange(["HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nuntil-close"], HTTPClient.METHOD_GET, _url("/"))

	assert_true(res.ok)
	assert_eq(res.body_text, "until-close")


func test_a_peer_closing_without_a_response_fails_promptly_even_without_a_timeout():
	var close_silently := func(_peer: StreamPeerTCP, _req: String) -> void:
		pass
	server.serve([close_silently])
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, _url("/"), {}, "", 0), 3000)

	assert_true(r.done, "the request resolved instead of hanging")
	if r.done:
		assert_false(r.res.ok)
		assert_eq(r.res.error, "Connection lost")


## The error text `LFHttp` gives for a connection to a closed loopback port on this platform.
func _refused_connection_error() -> String:
	match OS.get_name():
		"Windows":
			return "Connect timeout"
		"macOS":
			return "Connection lost"
	return "Cannot connect"


func test_a_refused_connection_names_the_cause():
	var closed := MockHttpServer.new()
	var port := closed.port
	closed.stop()
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, "http://127.0.0.1:%d/" % port, {}, "", 3000), 5000)

	assert_true(r.done)
	if r.done:
		assert_false(r.res.ok)
		# Godot on Windows never reports a refused loopback connection, so the timeout ends it.
		# Godot 4.7.2 on macOS 26 reports it as a lost connection instead of a refused one.
		assert_eq(r.res.error, _refused_connection_error())


func test_the_timeout_bounds_the_whole_request_even_while_bytes_keep_arriving():
	var drip := func(peer: StreamPeerTCP, _req: String) -> void:
		peer.put_data("HTTP/1.1 200 OK\r\nContent-Length: 1000\r\nConnection: close\r\n\r\n".to_utf8_buffer())
		var until := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < until and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.put_data("x".to_utf8_buffer())
			var next := Time.get_ticks_msec() + 100
			while Time.get_ticks_msec() < next:
				await Engine.get_main_loop().process_frame
	server.serve([drip])
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, _url("/"), {}, "", 500), 3000)

	assert_true(r.done, "a slow drip cannot keep the request alive past its timeout")
	if r.done:
		assert_false(r.res.ok)
		assert_eq(r.res.error, "Body timeout")


func test_the_timeout_spans_every_redirect_hop():
	var slow_redirect := func(peer: StreamPeerTCP, _req: String) -> void:
		var until := Time.get_ticks_msec() + 300
		while Time.get_ticks_msec() < until:
			await Engine.get_main_loop().process_frame
		peer.put_data(_redirect("/next").to_utf8_buffer())
	var never_answer := func(_peer: StreamPeerTCP, _req: String) -> void:
		var until := Time.get_ticks_msec() + 2500
		while Time.get_ticks_msec() < until:
			await Engine.get_main_loop().process_frame
	server.serve([slow_redirect, never_answer])
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, _url("/"), {}, "", _SHARED_DEADLINE_MS), 2000)

	assert_true(r.done, "the deadline is shared by both hops")
	if r.done:
		# A slow machine can still be connecting to the second hop when the shared deadline passes.
		assert_true(r.res.error in ["Header timeout", "Connect timeout"], r.res.error)
		assert_lt(r.elapsed, _SHARED_DEADLINE_BOUND_MS)


func test_caller_headers_cannot_set_framing_headers_in_any_case():
	for name in ["host", "HOST", "Content-Length", "content-length", "transfer-encoding", "Transfer-Encoding"]:
		var res: Dictionary = await LFHttp.request(HTTPClient.METHOD_POST, _url("/"), {name: "0"}, "abc", 1000)
		assert_false(res.ok, name)
		assert_eq(res.error, "Invalid header: %s" % name)
	assert_eq(server.requests.size(), 0, "nothing was sent")


func test_crlf_in_a_header_name_or_value_is_rejected():
	var bad := [
		{"X-Note": "a\r\nX-Injected: yes"},
		{"X-Note": "a\nb"},
		{"X-Bad\r\nName": "v"},
		{"X Space": "v"},
		{"X-Colon:": "v"},
		{"": "v"},
	]
	for headers in bad:
		var res: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, _url("/"), headers, "", 1000)
		assert_false(res.ok)
		assert_true(str(res.error).begins_with("Invalid header"), str(headers).c_escape())
	assert_eq(server.requests.size(), 0, "nothing was sent")


func test_two_caller_headers_differing_only_in_case_are_rejected():
	var res: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, _url("/"), {"Accept": "a", "accept": "b"}, "", 1000)

	assert_eq(res.error, "Invalid header: accept")


func test_a_caller_user_agent_replaces_the_default_whatever_its_case():
	await _exchange([_ok()], HTTPClient.METHOD_GET, _url("/"), {"user-agent": "mine/1", "ACCEPT-ENCODING": "gzip"})

	var req := server.last_request().to_lower()
	assert_eq(req.count("user-agent:"), 1)
	assert_true(req.contains("user-agent: mine/1"))
	assert_eq(req.count("accept-encoding:"), 1)
	assert_true(req.contains("accept-encoding: identity"), "the response is always requested unencoded")


func test_a_post_body_is_sent_with_one_content_length():
	await _exchange([_ok()], HTTPClient.METHOD_POST, _url("/"), {"Content-Type": "text/plain"}, "abc")

	var req := server.last_request()
	assert_eq(req.to_lower().count("content-length:"), 1)
	assert_true(req.ends_with("\r\n\r\nabc"))


func test_credentials_dropped_on_another_origin_stay_dropped_back_on_the_first():
	var other := MockHttpServer.new()
	other.serve([_redirect(_url("/back"))])
	var headers := {"Authorization": "Bearer top-secret", "Accept": "text/csv"}

	var res := await _exchange([_redirect(_url("/away", other)), _ok("home")], HTTPClient.METHOD_GET, _url("/start"), headers)
	other.stop()

	assert_true(res.ok)
	assert_eq(res.get("body_text"), "home")
	assert_eq(server.requests.size(), 2)
	if server.requests.size() == 2:
		assert_true(server.requests[0].contains("top-secret"), "the first hop carries the caller's headers")
		assert_false(server.requests[1].contains("top-secret"), "the return to the first origin does not get them back")
		assert_true(server.requests[1].contains("Accept: text/csv"), "safe headers still travel")


func test_with_two_location_headers_the_last_one_is_followed():
	var twice := "HTTP/1.1 302 Found\r\nLocation: /first\r\nLocation: /second\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
	var res := await _exchange([twice, _ok("landed")], HTTPClient.METHOD_GET, _url("/start"))

	assert_true(res.ok)
	assert_eq(res.body_text, "landed")
	assert_eq(server.requests.size(), 2)
	if server.requests.size() == 2:
		assert_true(server.requests[1].begins_with("GET /second "), "followed the last Location, got %s" % server.requests[1].get_slice("\r\n", 0))


func test_a_redirect_status_without_a_location_is_returned_as_it_is():
	var res := await _exchange(["HTTP/1.1 302 Found\r\nContent-Length: 2\r\nConnection: close\r\n\r\nno"], HTTPClient.METHOD_GET, _url("/"))

	assert_true(res.ok, "a 3xx counts as ok")
	assert_eq(res.status, 302)
	assert_eq(res.get("body_text"), "no")
	assert_eq(server.requests.size(), 1, "nothing was followed")


func test_the_default_user_agent_is_sent_when_the_caller_sets_none():
	await _exchange([_ok()], HTTPClient.METHOD_GET, _url("/"))

	assert_true(server.last_request().contains("User-Agent: GodotHTTPClient/4.x"))


func test_a_body_timeout_keeps_the_bytes_received_so_far():
	var stall := func(peer: StreamPeerTCP, _req: String) -> void:
		peer.put_data("HTTP/1.1 200 OK\r\nContent-Length: 100\r\nConnection: close\r\n\r\npartial".to_utf8_buffer())
		var until := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < until and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			await Engine.get_main_loop().process_frame
	server.serve([stall])
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, _url("/"), {}, "", 400), 3000)

	assert_true(r.done)
	if r.done:
		assert_eq(r.res.error, "Body timeout")
		assert_eq(r.res.status, 200)
		assert_eq((r.res.body_bytes as PackedByteArray).get_string_from_utf8(), "partial")


func test_a_body_that_is_not_valid_utf8_decodes_with_replacement_characters_quietly():
	var raw := func(peer: StreamPeerTCP, _req: String) -> void:
		peer.put_data("HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\n".to_utf8_buffer())
		peer.put_data(PackedByteArray([0x61, 0xFF, 0x62]))
	var res := await _exchange([raw], HTTPClient.METHOD_GET, _url("/"))

	assert_true(res.ok)
	assert_eq(res.get("body_text"), "a�b")
	assert_eq((res.body_bytes as PackedByteArray).size(), 3, "the raw bytes are kept")
	assert_engine_error_count(0, "decoding is quiet")


func test_an_error_status_is_not_ok_and_carries_no_error_key():
	var res := await _exchange(['HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 16\r\nConnection: close\r\n\r\n{"missing":true}'], HTTPClient.METHOD_GET, _url("/"))

	assert_false(res.ok)
	assert_eq(res.status, 404)
	assert_false(res.has("error"))
	assert_eq(res.json, {"missing": true}, "the body is still read and parsed")


func test_a_head_response_with_a_content_length_completes_without_a_body():
	var res := await _exchange(["HTTP/1.1 200 OK\r\nContent-Length: 42\r\nConnection: close\r\n\r\n"], HTTPClient.METHOD_HEAD, _url("/"))

	assert_true(res.ok)
	assert_eq(res.status, 200)
	assert_eq((res.body_bytes as PackedByteArray).size(), 0)
	assert_true(server.last_request().begins_with("HEAD / "))


func test_a_304_or_204_with_a_content_length_completes_without_a_body():
	for answer in ["HTTP/1.1 304 Not Modified\r\nContent-Length: 42\r\nConnection: close\r\n\r\n",
			"HTTP/1.1 204 No Content\r\nContent-Length: 42\r\n\r\n"]:
		server.stop()
		server = MockHttpServer.new()
		var res := await _exchange([answer], HTTPClient.METHOD_GET, _url("/"), {}, "", 3000, 10)

		assert_true(res.ok, answer.get_slice("\r\n", 0))
		assert_false(res.has("error"), "a Content-Length on a bodiless answer is not a truncation")
		assert_eq((res.body_bytes as PackedByteArray).size(), 0)


func test_max_redirects_is_five():
	assert_eq(LFHttp.MAX_REDIRECTS, _REDIRECT_LIMIT)


func test_the_result_key_constants_name_the_result_keys():
	assert_eq([LFHttp.KEY_OK, LFHttp.KEY_STATUS, LFHttp.KEY_HEADERS, LFHttp.KEY_BODY_BYTES, LFHttp.KEY_BODY_TEXT, LFHttp.KEY_JSON, LFHttp.KEY_ERROR],
			["ok", "status", "headers", "body_bytes", "body_text", "json", "error"])


## On the web the browser hands over the decompressed body while Content-Length keeps the
## compressed size, so the declared length can't decide completeness there.
func test_a_body_longer_than_an_untrusted_content_length_is_not_called_truncated():
	var decompressed := 900
	var compressed := 300
	assert_true(LFHttp._is_complete(compressed, decompressed, false, HTTPClient.STATUS_CONNECTED, false))
	assert_false(LFHttp._is_complete(compressed, decompressed, false, HTTPClient.STATUS_CONNECTION_ERROR, false), "a dropped connection still fails")
	assert_false(LFHttp._is_complete(compressed, decompressed, false, HTTPClient.STATUS_CONNECTED, true), "a trusted length must match")
	assert_true(LFHttp._is_complete(compressed, compressed, false, HTTPClient.STATUS_DISCONNECTED, true))


func test_the_declared_length_is_trusted_off_the_web():
	assert_eq(LFHttp._body_length_trusted(), not OS.has_feature("web"))


func test_a_url_without_a_path_requests_the_root():
	var res := await _exchange([_ok("root")], HTTPClient.METHOD_GET, "http://127.0.0.1:%d" % server.port)

	assert_eq(res.get("body_text"), "root")
	assert_true(server.last_request().begins_with("GET / HTTP/1.1\r\n"), server.last_request().get_slice("\r\n", 0))


func test_a_303_keeps_a_head_as_a_head():
	await _exchange([_redirect("/next", 303), "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\n"], HTTPClient.METHOD_HEAD, _url("/p"))

	assert_eq(server.requests.size(), 2)
	if server.requests.size() == 2:
		assert_true(server.requests[1].begins_with("HEAD /next "), server.requests[1].get_slice("\r\n", 0))


func test_an_empty_json_body_gives_null_json_and_stays_ok():
	var res := await _exchange([_ok("", "Content-Type: application/json\r\n")], HTTPClient.METHOD_GET, _url("/"))

	assert_true(res.ok)
	assert_eq(res.json, null)
	assert_eq(res.body_text, "")


func test_an_informational_answer_has_no_body_and_is_not_ok():
	var res := await _exchange(["HTTP/1.1 101 Switching Protocols\r\nContent-Length: 42\r\nConnection: close\r\n\r\n"], HTTPClient.METHOD_GET, _url("/"))

	assert_eq(res.get("status"), 101)
	assert_false(res.get("ok", true), "only 2xx and 3xx are ok")
	assert_false(res.has("error"), "a Content-Length on a bodiless answer is not a truncation")
	assert_eq((res.get("body_bytes", PackedByteArray([1])) as PackedByteArray).size(), 0)


func test_an_https_request_to_a_server_that_does_not_speak_tls_fails_the_handshake():
	server.serve([_ok("plain")])
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, "https://127.0.0.1:%d/" % server.port, {}, "", 3000), 5000)

	assert_true(r.done)
	if r.done:
		assert_false(r.res.ok)
		assert_eq(r.res.error, "TLS handshake failed")
	assert_engine_error("TLS handshake", "the engine reports the failed handshake too")


func test_a_host_that_cannot_resolve_names_the_cause():
	# The .invalid top-level domain is reserved never to resolve (RFC 6761).
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, "http://no-such-host.invalid/", {}, "", 4000), 6000)

	assert_true(r.done)
	if r.done:
		assert_false(r.res.ok)
		assert_eq(r.res.error, "Cannot resolve host")


func test_a_redirect_failure_keeps_the_redirect_status_and_headers():
	var res := await _exchange([_redirect("ftp://127.0.0.1/x", 301)], HTTPClient.METHOD_GET, _url("/"))

	assert_eq(res.error, "Invalid redirect")
	assert_eq(res.status, 301)
	assert_eq(str(LFHttp._header(res.headers, "location")), "ftp://127.0.0.1/x")


func test_a_short_ipv6_host_is_padded_to_a_spelling_the_client_accepts():
	assert_eq(LFHttp._connect_host(LFUrl.parse("http://[::1]:8080/")), "0::1")
	assert_eq(LFHttp._connect_host(LFUrl.parse("http://[::]/")), "0::0")
	assert_eq(LFHttp._connect_host(LFUrl.parse("http://[fe80::1]/")), "fe80::1", "long enough already")
	assert_eq(LFHttp._connect_host(LFUrl.parse("http://a.b/")), "a.b", "only IPv6 literals are padded")


func test_each_connection_status_names_its_cause():
	assert_eq(LFHttp._status_error(HTTPClient.STATUS_CANT_RESOLVE), "Cannot resolve host")
	assert_eq(LFHttp._status_error(HTTPClient.STATUS_CANT_CONNECT), "Cannot connect")
	assert_eq(LFHttp._status_error(HTTPClient.STATUS_TLS_HANDSHAKE_ERROR), "TLS handshake failed")
	assert_eq(LFHttp._status_error(HTTPClient.STATUS_CONNECTION_ERROR), "Connection lost")
	assert_eq(LFHttp._status_error(HTTPClient.STATUS_DISCONNECTED), "Connection lost")


func test_a_host_that_never_answers_the_connection_times_out():
	# 192.0.2.1 is TEST-NET-1 (RFC 5737): nothing there accepts a connection.
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, "http://192.0.2.1:9/", {}, "", 300), 3000)

	assert_true(r.done)
	if r.done and r.res.error != "Connect timeout":
		pending("this network refuses TEST-NET at once (%s) instead of letting the connect hang" % r.res.error)
		return
	assert_lt(r.elapsed, 1500)


## A negative Content-Length makes the engine fail every body read; the request fails at
## once with its own reason instead of waiting for the deadline.
func test_a_negative_content_length_fails_at_once_without_engine_errors():
	var r := await _within(func():
		server.serve(["HTTP/1.1 200 OK\r\nContent-Length: -5\r\nConnection: close\r\n\r\nabc"])
		return await LFHttp.request(HTTPClient.METHOD_GET, _url("/"), {}, "", 3000), 5000)

	assert_true(r.done)
	assert_lt(r.elapsed, 1500, "failed before the deadline")
	assert_eq(r.res.error, "Invalid Content-Length")
	assert_engine_error_count(0)


func test_conflicting_or_malformed_content_lengths_are_refused():
	for head in ["Content-Length: 3\r\nContent-Length: 5", "Content-Length: 3x", "Content-Length: +3"]:
		server.stop()
		server = MockHttpServer.new()
		var res := await _exchange(["HTTP/1.1 200 OK\r\n%s\r\nConnection: close\r\n\r\nabcde" % head], HTTPClient.METHOD_GET, _url("/"))
		assert_eq(res.get("error"), "Invalid Content-Length", head.c_escape())


func test_an_answer_with_too_many_header_lines_fails():
	var head := ""
	for i in LFHttp.MAX_RESPONSE_HEADERS + 1:
		head += "X-H%d: v\r\n" % i
	var res := await _exchange(["HTTP/1.1 200 OK\r\n%sContent-Length: 0\r\nConnection: close\r\n\r\n" % head], HTTPClient.METHOD_GET, _url("/"))

	assert_false(res.ok)
	assert_eq(res.error, "Headers too large")
	assert_eq(res.headers, {}, "none of them is handed over")


func test_an_answer_with_too_much_header_text_fails():
	var big := "X-Big: %s\r\n" % "a".repeat(LFHttp.MAX_RESPONSE_HEADER_CHARS)
	var res := await _exchange(["HTTP/1.1 200 OK\r\n%sContent-Length: 0\r\nConnection: close\r\n\r\n" % big], HTTPClient.METHOD_GET, _url("/"))

	assert_eq(res.get("error"), "Headers too large")


func test_a_url_beyond_the_length_cap_fails_without_connecting():
	var long_url := _url("/" + "a".repeat(LFHttp.MAX_URL_LENGTH))
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, long_url, {}, "", 1000), 3000)

	assert_true(r.done)
	if r.done:
		assert_eq(r.res.error, "URL too long")
	assert_eq(server.requests.size(), 0)


## A hostile Location full of dot segments is refused before it is resolved.
func test_a_redirect_location_beyond_the_length_cap_is_refused():
	var location := "/" + "a/".repeat(LFHttp.MAX_URL_LENGTH) + ".."
	var res := await _exchange([_redirect(location)], HTTPClient.METHOD_GET, _url("/"))

	assert_false(res.ok)
	assert_eq(res.error, "Redirect URL too long")
	assert_eq(res.status, 302)
	assert_eq(server.requests.size(), 1, "the target is never requested")


func test_a_request_without_a_timeout_gets_the_default_deadline():
	assert_eq(LFHttp.DEFAULT_TIMEOUT_MS, 30000)
	var script: Script = LFHttp
	var defaults := []
	for method in script.get_script_method_list():
		if method.name == "request":
			defaults = method.default_args
	assert_eq(defaults.slice(-4, -1), [LFHttp.DEFAULT_TIMEOUT_MS, LFHttp.DEFAULT_MAX_BODY_BYTES, LFHttp.MAX_REDIRECTS], "timeout_ms, max_body_bytes and max_redirects default to their constants")
	assert_eq(defaults[-1], Callable(), "no redirect validator by default")


## A server that never stops sending: the client must keep handing frames back to the game.
func test_an_endless_body_does_not_starve_the_frame_loop():
	var tcp := TCPServer.new()
	assert_eq(tcp.listen(0, "127.0.0.1"), OK)
	var port := tcp.get_local_port()
	var serve := func() -> void:
		var peer: StreamPeerTCP = null
		while peer == null:
			if tcp.is_connection_available():
				peer = tcp.take_connection()
			else:
				OS.delay_msec(1)
		OS.delay_msec(50)
		peer.put_data("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n".to_utf8_buffer())
		var block := PackedByteArray()
		block.resize(64 * 1024)
		while peer.put_data(block) == OK:
			pass
	var thread := Thread.new()
	thread.start(serve)
	var counter := { "frames": 0 }
	var on_frame := func() -> void: counter.frames += 1
	get_tree().process_frame.connect(on_frame)

	var res: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, "http://127.0.0.1:%d/" % port, {}, "", _ENDLESS_DEADLINE_MS, 0)
	get_tree().process_frame.disconnect(on_frame)
	thread.wait_to_finish()
	tcp.stop()

	assert_eq(res.error, "Body timeout")
	assert_gt(counter.frames, _ENDLESS_MIN_FRAMES, "reading yields to the game between slices")


# ---- body cap default, redirect limits and validation

## A declared length one byte over the default cap (no body is ever sent).
const _OVER_DEFAULT_CAP := 16 * 1024 * 1024 + 1


func _declares_length(length: int) -> String:
	return "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\nshort" % length


## Awaits a request made with the library defaults and only the given trailing options.
func _request_with(responses: Array, method: HTTPClient.Method, url: String, headers: Dictionary, body: String, max_body: int, max_redirects: int, validator: Callable) -> Dictionary:
	server.serve(responses)
	var r := await _within(func(): return await LFHttp.request(method, url, headers, body, 3000, max_body, max_redirects, validator), 5000)
	assert_true(r.done, "the request resolved")
	return r.res if r.done else {}


func test_the_default_body_cap_is_16_mib():
	assert_eq(LFHttp.DEFAULT_MAX_BODY_BYTES, 16 * 1024 * 1024)


func test_a_body_declared_over_the_default_cap_is_refused_without_reading_it():
	server.serve([_declares_length(_OVER_DEFAULT_CAP)])
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, _url("/")), 5000)

	assert_true(r.done)
	assert_false(r.res.ok)
	assert_eq(r.res.error, "Body too large")


func test_a_body_cap_of_zero_means_unlimited():
	server.serve([_declares_length(_OVER_DEFAULT_CAP)])
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, _url("/"), {}, "", 3000, 0), 5000)

	assert_true(r.done)
	assert_ne(r.res.get("error"), "Body too large", "no cap: the answer is judged on completeness instead")
	assert_eq(r.res.get("error"), "Truncated body")


func test_a_body_just_under_the_default_cap_is_accepted():
	server.serve([_ok("x".repeat(1024 * 1024))])
	var r := await _within(func(): return await LFHttp.request(HTTPClient.METHOD_GET, _url("/")), 5000)

	assert_true(r.res.ok)
	assert_eq((r.res.body_bytes as PackedByteArray).size(), 1024 * 1024)


func test_max_redirects_zero_returns_the_redirect_answer_and_follows_nothing():
	var res := await _request_with([_redirect("/next"), _ok()], HTTPClient.METHOD_GET, _url("/a"), {}, "", LFHttp.DEFAULT_MAX_BODY_BYTES, 0, Callable())

	assert_eq(res.status, 302)
	assert_eq(res.headers.get("Location"), "/next")
	assert_eq(server.requests.size(), 1, "the redirect target is never requested")


func test_a_lower_max_redirects_fails_the_chain_earlier():
	var chain := [_redirect("/r1"), _redirect("/r2"), _redirect("/r3"), _ok()]
	var res := await _request_with(chain, HTTPClient.METHOD_GET, _url("/r0"), {}, "", LFHttp.DEFAULT_MAX_BODY_BYTES, 2, Callable())

	assert_false(res.ok)
	assert_eq(res.error, "Too many redirects")
	assert_eq(server.requests.size(), 3, "two redirects followed, the third refused")


func test_max_redirects_cannot_exceed_the_library_limit():
	var chain := []
	for i in _REDIRECT_LIMIT + 1:
		chain.append(_redirect("/r%d" % (i + 1)))
	var res := await _request_with(chain, HTTPClient.METHOD_GET, _url("/r0"), {}, "", LFHttp.DEFAULT_MAX_BODY_BYTES, 100, Callable())

	assert_eq(res.error, "Too many redirects")
	assert_eq(server.requests.size(), _REDIRECT_LIMIT + 1)


func test_a_redirect_validator_sees_the_target_and_status_and_can_refuse():
	var seen := []
	var validator := func(target: String, status: int) -> bool:
		seen.append([target, status])
		return false
	var res := await _request_with([_redirect("/next", 301), _ok()], HTTPClient.METHOD_GET, _url("/a"), {}, "", LFHttp.DEFAULT_MAX_BODY_BYTES, LFHttp.MAX_REDIRECTS, validator)

	assert_false(res.ok)
	assert_eq(res.error, "Redirect refused")
	assert_eq(res.status, 301, "the refused redirect status is kept")
	assert_eq(seen, [[_url("/next"), 301]])
	assert_eq(server.requests.size(), 1, "the target was never contacted")


func test_a_redirect_validator_returning_true_lets_the_redirect_through():
	var res := await _request_with([_redirect("/next"), _ok("fine")], HTTPClient.METHOD_GET, _url("/a"), {}, "", LFHttp.DEFAULT_MAX_BODY_BYTES, LFHttp.MAX_REDIRECTS, func(_t: String, _s: int) -> bool: return true)

	assert_true(res.ok)
	assert_eq(res.body_text, "fine")


func test_a_validator_that_returns_a_non_bool_refuses():
	var res := await _request_with([_redirect("/next"), _ok()], HTTPClient.METHOD_GET, _url("/a"), {}, "", LFHttp.DEFAULT_MAX_BODY_BYTES, LFHttp.MAX_REDIRECTS, func(_t: String, _s: int): return "yes")

	assert_eq(res.error, "Redirect refused")


func test_a_307_or_308_with_a_body_is_not_resent_to_another_origin():
	for code in [307, 308]:
		server.stop()
		server = MockHttpServer.new()
		var other := MockHttpServer.new()
		other.serve([_ok()])
		var res := await _exchange([_redirect(_url("/steal", other), code)], HTTPClient.METHOD_POST, _url("/p"), {}, "secret-body")
		var reached := other.requests.size()
		other.stop()

		assert_false(res.ok, "%d" % code)
		assert_eq(res.error, "Body not resent to another origin")
		assert_eq(res.status, code)
		assert_eq(reached, 0, "%d: the other origin was never contacted" % code)


func test_a_307_without_a_body_may_cross_origin():
	var other := MockHttpServer.new()
	other.serve([_ok("there")])
	var res := await _exchange([_redirect(_url("/x", other), 307)], HTTPClient.METHOD_GET, _url("/p"))
	other.stop()

	assert_true(res.ok)
	assert_eq(res.body_text, "there")


func test_a_cross_origin_redirect_that_drops_the_body_is_followed():
	var other := MockHttpServer.new()
	other.serve([_ok("there")])
	var res := await _exchange([_redirect(_url("/x", other), 303)], HTTPClient.METHOD_POST, _url("/p"), {}, "body")
	var second := other.last_request()
	other.stop()

	assert_true(res.ok)
	assert_false(second.contains("body"), "a 303 turns the POST into a body-less GET")
