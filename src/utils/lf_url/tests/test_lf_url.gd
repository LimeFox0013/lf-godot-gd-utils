extends GutTest


func test_parses_scheme_host_port_path_and_query():
	var u := LFUrl.parse("https://example.com:8080/a/b?x=1&y=2")
	assert_true(u.is_valid())
	assert_eq(u.scheme, "https")
	assert_eq(u.host, "example.com")
	assert_eq(u.port, 8080)
	assert_eq(u.path, "/a/b")
	assert_eq(u.query, "x=1&y=2")
	assert_eq(u.error, "")


func test_a_missing_port_is_zero_and_the_effective_port_is_the_scheme_default():
	assert_eq(LFUrl.parse("http://example.com/").port, 0)
	assert_eq(LFUrl.parse("http://example.com/").effective_port(), 80)
	assert_eq(LFUrl.parse("https://example.com/").effective_port(), 443)
	assert_eq(LFUrl.parse("ws://example.com/").effective_port(), 80)
	assert_eq(LFUrl.parse("wss://example.com/").effective_port(), 443)
	assert_eq(LFUrl.parse("ws://example.com:9000").effective_port(), 9000)


func test_default_port_knows_every_supported_scheme():
	assert_eq(LFUrl.default_port("http"), 80)
	assert_eq(LFUrl.default_port("HTTPS"), 443)
	assert_eq(LFUrl.default_port("ws"), 80)
	assert_eq(LFUrl.default_port("wss"), 443)
	assert_eq(LFUrl.default_port("ftp"), 0)


func test_default_ports_lists_the_supported_schemes():
	assert_eq(LFUrl.DEFAULT_PORTS, {"http": 80, "https": 443, "ws": 80, "wss": 443})


func test_invalid_builds_a_result_carrying_its_reason():
	var u := LFUrl.Parts.invalid("Nope")
	assert_false(u.is_valid())
	assert_eq(u.error, "Nope")
	assert_eq(str(u), "")


func test_a_non_url_is_invalid_with_a_reason_and_no_engine_error():
	var u := LFUrl.parse("not a url at all")
	assert_false(u.is_valid())
	assert_ne(u.error, "")
	assert_eq(u.host, "")
	assert_engine_error_count(0)


func test_the_scheme_is_case_insensitive_and_lower_cased():
	assert_eq(LFUrl.parse("HTTP://example.com/").scheme, "http")
	assert_eq(LFUrl.parse("Https://example.com/").scheme, "https")
	assert_eq(LFUrl.parse("WSS://example.com/").scheme, "wss")


func test_unsupported_schemes_are_rejected():
	assert_false(LFUrl.parse("ftp://example.com/").is_valid())
	assert_false(LFUrl.parse("file:///etc/passwd").is_valid())
	assert_false(LFUrl.parse("//example.com/").is_valid())


func test_the_host_is_lower_cased():
	assert_eq(LFUrl.parse("http://Example.COM/A").host, "example.com")
	assert_eq(LFUrl.parse("http://Example.COM/A").path, "/A", "the path keeps its case")


func test_surrounding_spaces_are_stripped():
	var u := LFUrl.parse("  http://x.org/a ")
	assert_true(u.is_valid())
	assert_eq(u.path, "/a")


func test_control_characters_spaces_and_backslashes_are_rejected():
	for bad in [
		"http://h\r\nX-Evil=1/",
		"http://example.com/a b\r\nX-Injected: 1",
		"http://exa mple.com/",
		"http://example.com/a b",
		"http://example.com/a\nb",
		"http://example.com/a\u0007b",
		"http://example.com/a\u007fb",
		"http://example.com\\@evil.com/",
		"http://example.com/a?q=\r\nx",
		"http://example.com/a#\r\nx",
	]:
		assert_false(LFUrl.parse(bad).is_valid(), "rejects %s" % bad.c_escape())


func test_userinfo_is_split_out_and_never_part_of_the_host():
	var u := LFUrl.parse("http://user:pass@example.com:81/x")
	assert_true(u.is_valid())
	assert_eq(u.userinfo, "user:pass")
	assert_eq(u.host, "example.com")
	assert_eq(u.port, 81)

	var trick := LFUrl.parse("http://trusted.example.com@evil.com/")
	assert_eq(trick.host, "evil.com", "the part before @ is userinfo, not the host")
	assert_eq(trick.userinfo, "trusted.example.com")


func test_a_second_at_sign_in_the_authority_is_rejected():
	assert_false(LFUrl.parse("http://a@b@c.com/").is_valid())


func test_hosts_with_invalid_characters_are_rejected():
	assert_false(LFUrl.parse("http://exa<mple.com/").is_valid())
	assert_false(LFUrl.parse("http://exa\"mple.com/").is_valid())
	assert_false(LFUrl.parse("http:///path").is_valid(), "an empty host")
	assert_false(LFUrl.parse("http://:80/").is_valid(), "an empty host with a port")


func test_ipv6_literals_parse_without_brackets_in_host():
	var u := LFUrl.parse("http://[::1]:8080/v1")
	assert_true(u.is_valid())
	assert_eq(u.host, "::1")
	assert_eq(u.port, 8080)
	assert_eq(u.path, "/v1")
	assert_true(u.is_ipv6())

	var bare := LFUrl.parse("ws://[2001:db8::7]")
	assert_eq(bare.host, "2001:db8::7")
	assert_eq(bare.port, 0)


func test_malformed_ipv6_literals_are_rejected():
	assert_false(LFUrl.parse("http://[::1/").is_valid(), "unclosed bracket")
	assert_false(LFUrl.parse("http://[nothex]/").is_valid())
	assert_false(LFUrl.parse("http://[::1]x/").is_valid(), "junk after the bracket")
	assert_false(LFUrl.parse("http://::1/").is_valid(), "IPv6 needs brackets")


func test_ports_are_range_checked():
	assert_eq(LFUrl.parse("http://h:1/").port, 1)
	assert_eq(LFUrl.parse("http://h:65535/").port, 65535)
	assert_false(LFUrl.parse("http://h:0/").is_valid())
	assert_false(LFUrl.parse("http://h:65536/").is_valid())
	assert_false(LFUrl.parse("http://h:99999999999999999999/").is_valid())
	assert_false(LFUrl.parse("http://h:8a/").is_valid())
	assert_false(LFUrl.parse("http://h:-1/").is_valid())
	assert_engine_error_count(0, "an overlong port is rejected without an engine error")


func test_an_empty_port_means_the_default():
	var u := LFUrl.parse("http://h:/x")
	assert_true(u.is_valid())
	assert_eq(u.port, 0)


func test_a_query_without_a_path_leaves_the_path_empty():
	var u := LFUrl.parse("http://example.com?x=1")
	assert_eq(u.path, "")
	assert_eq(u.query, "x=1")


func test_a_question_mark_inside_the_query_stays_in_the_query():
	var u := LFUrl.parse("http://example.com/a?b?c=1#x#y")
	assert_eq(u.path, "/a")
	assert_eq(u.query, "b?c=1")


func test_percent_escapes_are_kept_verbatim():
	var u := LFUrl.parse("http://example.com/a%20b?q=%2F%3D")
	assert_eq(u.path, "/a%20b")
	assert_eq(u.query, "q=%2F%3D")


func test_a_fragment_is_accepted_and_dropped():
	var u := LFUrl.parse("https://example.com:8080/a/b?x=1#section-2")
	assert_true(u.is_valid())
	assert_eq(u.path, "/a/b")
	assert_eq(u.query, "x=1")
	var top := LFUrl.parse("http://example.com#top")
	assert_eq(top.host, "example.com")
	assert_eq(top.path, "")
	assert_eq(top.query, "")


func test_to_string_serialises_the_parts():
	assert_eq(str(LFUrl.parse("HTTP://User@Example.com:8080/a?b=1#f")), "http://User@example.com:8080/a?b=1")
	assert_eq(LFUrl.parse("ws://[::1]:9000").to_string(), "ws://[::1]:9000")
	assert_eq(str(LFUrl.parse("https://h")), "https://h")
	assert_eq(str(LFUrl.parse("bogus")), "")


func test_host_port_brackets_ipv6_and_omits_the_default_port():
	assert_eq(LFUrl.parse("http://h/").host_port(), "h")
	assert_eq(LFUrl.parse("http://h:80/").host_port(), "h")
	assert_eq(LFUrl.parse("http://h:81/").host_port(), "h:81")
	assert_eq(LFUrl.parse("http://[::1]/").host_port(), "[::1]")
	assert_eq(LFUrl.parse("http://[::1]:81/").host_port(), "[::1]:81")


func test_origin_is_scheme_host_and_effective_port():
	assert_eq(LFUrl.parse("http://Example.com/a").origin(), "http://example.com:80")
	assert_eq(LFUrl.parse("https://u@h:8443/").origin(), "https://h:8443")
	assert_eq(LFUrl.parse("http://[::1]/").origin(), "http://[::1]:80")
	assert_eq(LFUrl.parse("bogus").origin(), "")


func test_with_default_port_fills_in_a_missing_port():
	assert_eq(str(LFUrl.parse("ws://10.0.0.2").with_default_port(7777)), "ws://10.0.0.2:7777")
	assert_eq(str(LFUrl.parse("ws://10.0.0.2:7").with_default_port(7777)), "ws://10.0.0.2:7")


## RFC 3986 section 5.4 examples, against the base http://a/b/c/d;p?q (minus fragments).
func test_resolve_follows_the_rfc_3986_examples():
	var base := "http://a/b/c/d;p?q"
	var cases := {
		"g": "http://a/b/c/g",
		"./g": "http://a/b/c/g",
		"g/": "http://a/b/c/g/",
		"/g": "http://a/g",
		"//g": "http://g",
		"?y": "http://a/b/c/d;p?y",
		"g?y": "http://a/b/c/g?y",
		"#s": "http://a/b/c/d;p?q",
		"g#s": "http://a/b/c/g",
		";x": "http://a/b/c/;x",
		"": "http://a/b/c/d;p?q",
		".": "http://a/b/c/",
		"./": "http://a/b/c/",
		"..": "http://a/b/",
		"../": "http://a/b/",
		"../g": "http://a/b/g",
		"../..": "http://a/",
		"../../g": "http://a/g",
		"../../../g": "http://a/g",
		"/./g": "http://a/g",
		"/../g": "http://a/g",
		"g.": "http://a/b/c/g.",
		"..g": "http://a/b/c/..g",
		"./../g": "http://a/b/g",
		"g/./h": "http://a/b/c/g/h",
		"g/../h": "http://a/b/c/h",
		"g?y/./x": "http://a/b/c/g?y/./x",
	}
	for ref in cases:
		assert_eq(str(LFUrl.resolve(base, ref)), cases[ref], "resolve '%s'" % ref)


func test_resolve_from_a_one_segment_path():
	assert_eq(str(LFUrl.resolve("http://h:81/start", "next")), "http://h:81/next")
	assert_eq(str(LFUrl.resolve("http://h:81", "next")), "http://h:81/next", "an empty base path merges as /")


func test_resolve_with_an_absolute_reference_ignores_the_base():
	assert_eq(str(LFUrl.resolve("http://h:81/a", "HTTP://other.com/x")), "http://other.com/x")
	assert_eq(str(LFUrl.resolve("http://h/a", "https://o/b/../c")), "https://o/c")


func test_resolve_with_a_network_path_reference_keeps_the_scheme():
	assert_eq(str(LFUrl.resolve("https://h:81/a", "//other.com/x")), "https://other.com/x")


func test_resolve_keeps_userinfo_and_ipv6_hosts_of_the_base():
	assert_eq(str(LFUrl.resolve("http://u@[::1]:4000/v1/a", "b")), "http://u@[::1]:4000/v1/b")


func test_resolve_rejects_invalid_input():
	assert_false(LFUrl.resolve("not a url", "x").is_valid())
	assert_false(LFUrl.resolve("http://h/", "ftp://x/").is_valid())
	assert_false(LFUrl.resolve("http://h/", "a b").is_valid())
	assert_false(LFUrl.resolve("http://h/", "/a\r\nX: y").is_valid())


func test_a_copy_is_independent_of_its_original():
	var original := LFUrl.parse("http://h/a/b?q=1")
	var copied := original.copy()
	copied.path = "/changed"
	copied.query = "x"
	copied.port = 81

	assert_eq(original.path, "/a/b")
	assert_eq(original.query, "q=1")
	assert_eq(original.port, 0)


func test_for_host_builds_a_url_and_brackets_an_ipv6_host():
	assert_eq(LFUrl.for_host("ws", "192.168.1.20", 7777), "ws://192.168.1.20:7777")
	assert_eq(LFUrl.for_host("ws", "::1", 7777), "ws://[::1]:7777")
	assert_eq(LFUrl.for_host("wss", "[::1]", 443), "wss://[::1]:443")
	assert_eq(LFUrl.for_host("WSS", "Play.Example.com", 9000), "wss://play.example.com:9000")


func test_for_host_with_port_zero_leaves_the_port_out():
	assert_eq(LFUrl.for_host("https", "example.com", 0), "https://example.com")


func test_for_host_refuses_anything_but_a_bare_host():
	assert_eq(LFUrl.for_host("ws", "", 1), "")
	assert_eq(LFUrl.for_host("ws", "host name", 1), "")
	assert_eq(LFUrl.for_host("ws", "host/path", 1), "")
	assert_eq(LFUrl.for_host("ws", "user@host", 1), "")
	assert_eq(LFUrl.for_host("ws", "host?q", 1), "")
	assert_eq(LFUrl.for_host("ftp", "host", 1), "")
	assert_eq(LFUrl.for_host("ws", "host", 65536), "")
	assert_eq(LFUrl.for_host("ws", "host", -1), "")
	assert_eq(LFUrl.for_host("ws", "not:an:ipv6:zz", 1), "")


const _WS: PackedStringArray = ["ws", "wss"]


func test_from_address_gives_a_bare_address_the_default_scheme_and_port():
	assert_eq(LFUrl.from_address("192.168.1.20", "ws", _WS, 7777), "ws://192.168.1.20:7777")


func test_from_address_keeps_a_typed_port_and_ignores_surrounding_space():
	assert_eq(LFUrl.from_address(" 192.168.1.20:7777 ", "ws", _WS, 1), "ws://192.168.1.20:7777")
	assert_eq(LFUrl.from_address("ws://10.0.0.2:7777", "ws", _WS, 1), "ws://10.0.0.2:7777")


func test_from_address_of_nothing_is_no_url():
	assert_eq(LFUrl.from_address("   ", "ws", _WS, 1), "")
	assert_eq(LFUrl.from_address("", "ws", _WS, 1), "")


func test_from_address_keeps_a_typed_secure_scheme():
	assert_eq(LFUrl.from_address("wss://play.example.com", "ws", _WS, 7777), "wss://play.example.com:7777")


func test_from_address_brackets_an_ipv6_address():
	assert_eq(LFUrl.from_address("::1", "ws", _WS, 7777), "ws://[::1]:7777")
	assert_eq(LFUrl.from_address("[::1]:7777", "ws", _WS, 1), "ws://[::1]:7777")


func test_from_address_refuses_what_is_not_an_allowed_url():
	assert_eq(LFUrl.from_address("ftp://x", "ws", _WS, 1), "")
	assert_eq(LFUrl.from_address("http://x", "ws", _WS, 1), "", "a supported scheme outside the allowed list")
	assert_eq(LFUrl.from_address("host name", "ws", _WS, 1), "")
	assert_eq(LFUrl.from_address("host:99999", "ws", _WS, 1), "")


func test_from_address_without_an_allowed_list_or_default_port():
	assert_eq(LFUrl.from_address("HTTP://Example.com/x", "https"), "http://example.com/x")
	assert_eq(LFUrl.from_address("example.com", "https"), "https://example.com")


func test_from_address_refuses_a_fallback_port_out_of_range():
	assert_eq(LFUrl.from_address("10.0.0.2", "ws", _WS, 70000), "", "the result would not be a valid URL")
	assert_eq(LFUrl.from_address("10.0.0.2", "ws", _WS, -5), "ws://10.0.0.2", "a negative fallback is ignored like 0")


func test_every_rejection_names_its_reason():
	var cases := {
		"http://a b/": "Control character or space",
		"http://h\\x/": "Backslash",
		"example.com/path": "Missing scheme",
		"://example.com/": "Missing scheme",
		"1http://example.com/": "Malformed scheme",
		"ht_tp://example.com/": "Malformed scheme",
		"ftp://example.com/": "Unsupported scheme ftp",
		"FTP://example.com/": "Unsupported scheme ftp",
		"http://a@b@c.com/": "More than one @ in authority",
		"http://us<er@h/": "Malformed userinfo",
		"http://[::1/": "Unclosed IPv6 bracket",
		"http://[1.2.3.4]/": "Malformed IPv6 address",
		"http://[::g]/": "Malformed IPv6 address",
		"http://[::1]x/": "Malformed authority",
		"http:///x": "Missing host",
		"http://user@/x": "Missing host",
		"http://h^st/": "Malformed host",
		"http://h:8a/": "Malformed port",
		"http://h:123456/": "Malformed port",
		"http://h:0/": "Port out of range",
		"http://h:65536/": "Port out of range",
	}
	for url in cases:
		var parsed := LFUrl.parse(url)
		assert_false(parsed.is_valid(), url)
		assert_eq(parsed.error, cases[url], "reason for %s" % url.c_escape())


func test_userinfo_may_hold_a_colon_and_the_host_characters():
	var u := LFUrl.parse("ws://player-1:p%40ss!@h:9000/")
	assert_true(u.is_valid())
	assert_eq(u.userinfo, "player-1:p%40ss!")
	assert_eq(u.host, "h")


func test_an_ipv6_literal_is_lower_cased():
	assert_eq(LFUrl.parse("http://[2001:DB8::A]/").host, "2001:db8::a")


func test_parts_without_a_scheme_or_host_are_not_valid():
	var empty := LFUrl.Parts.new()
	assert_false(empty.is_valid(), "a fresh Parts has no scheme or host")
	assert_eq(str(empty), "")
	assert_eq(empty.origin(), "")
	empty.scheme = "http"
	assert_false(empty.is_valid(), "still no host")
	empty.host = "h"
	assert_true(empty.is_valid())
	assert_eq(str(empty), "http://h")


func test_an_unsupported_scheme_has_no_default_port():
	var odd := LFUrl.Parts.new()
	odd.scheme = "gopher"
	odd.host = "h"
	assert_eq(odd.effective_port(), 0)


func test_with_default_port_returns_a_copy():
	var original := LFUrl.parse("ws://h")
	var filled := original.with_default_port(7777)
	assert_eq(filled.port, 7777)
	assert_eq(original.port, 0, "the original is unchanged")


func test_resolve_a_query_only_reference_on_a_base_without_a_path():
	assert_eq(str(LFUrl.resolve("http://h", "?x=1")), "http://h?x=1")
	assert_eq(str(LFUrl.resolve("http://h?old", "")), "http://h?old")


func test_resolve_a_relative_path_containing_a_colon_after_a_slash():
	assert_eq(str(LFUrl.resolve("http://a/b/c", "d/e:f")), "http://a/b/d/e:f")


func test_resolve_refuses_a_reference_whose_scheme_does_not_parse():
	assert_eq(LFUrl.resolve("http://h/", "g:h").error, "Missing scheme", "a scheme-like prefix without ://")
	assert_eq(LFUrl.resolve("http://h/", "//").error, "Missing host", "a network path with no host")
	assert_eq(LFUrl.resolve("http://h/", "a\\b").error, "Backslash")


func test_resolve_returns_the_bases_reason_when_the_base_is_invalid():
	assert_eq(LFUrl.resolve("ftp://h/", "x").error, "Unsupported scheme ftp")


func test_for_host_refuses_a_host_that_carries_a_port():
	assert_eq(LFUrl.for_host("ws", "host:80", 1), "", "an unbracketed host:port is not an IPv6 address")
	assert_eq(LFUrl.for_host("ws", "[::1]:80", 1), "", "a bracketed address with a port")


func test_from_address_matches_allowed_schemes_case_insensitively():
	assert_eq(LFUrl.from_address("h", "ws", PackedStringArray(["WS"]), 7777), "ws://h:7777")


## Dot-segment removal walks the path once: a 1 MB path full of `..` resolves at once (the
## old quadratic walk took over a second on a 200 KB one). The bound is loose on purpose.
func test_a_megabyte_path_of_dot_segments_resolves_quickly_and_correctly():
	var path := "/" + "a/../".repeat(200000) + "b/./c/.."
	var started := Time.get_ticks_msec()
	var parts := LFUrl.resolve("http://h/x", path)

	assert_lt(Time.get_ticks_msec() - started, 3000)
	assert_eq(parts.path, "/b/")


func test_dot_segments_follow_rfc_3986_examples():
	var base := "http://a/b/c/d;p?q"
	var expected := {
		"g": "/b/c/g", "./g": "/b/c/g", "g/": "/b/c/g/", "/./g": "/g", ".": "/b/c/", "./": "/b/c/",
		"..": "/b/", "../": "/b/", "../g": "/b/g", "../..": "/", "../../": "/", "../../g": "/g",
		"../../../g": "/g", "../../../../g": "/g", "/../g": "/g", "g.": "/b/c/g.", ".g": "/b/c/.g",
		"g..": "/b/c/g..", "..g": "/b/c/..g", "./../g": "/b/g", "./g/.": "/b/c/g/", "g/./h": "/b/c/g/h",
		"g/../h": "/b/c/h", "g;x=1/./y": "/b/c/g;x=1/y", "g;x=1/../y": "/b/c/y",
	}
	for ref in expected:
		assert_eq(LFUrl.resolve(base, ref).path, expected[ref], ref)


func test_control_characters_are_rejected_at_either_end_too():
	for url in ["http://x.org/a\n", "\nhttp://x.org/a", "http://x.org/\t", "\rhttp://x.org/", "http://x.org/\u0085", "http://x.org/a\u009f", "\u0080http://x.org/"]:
		var u := LFUrl.parse(url)
		assert_false(u.is_valid(), url.c_escape())
		assert_eq(u.error, "Control character or space")
	assert_false(LFUrl.resolve("http://h/", "x\n").is_valid())
	assert_true(LFUrl.parse("http://x.org/\u00e9").is_valid(), "printable non-ASCII stays accepted")


func test_legacy_numeric_ipv4_hosts_become_dotted_decimal():
	var cases := {
		"http://2130706433/": "127.0.0.1",
		"http://0x7f.1/": "127.0.0.1",
		"http://127.1/": "127.0.0.1",
		"http://0x7f000001/": "127.0.0.1",
		"http://017700000001/": "127.0.0.1",
		"http://010.0.0.1/": "8.0.0.1",
		"http://0xA.0.0.1./": "10.0.0.1",
		"http://10.1.2.3/": "10.1.2.3",
		"http://0/": "0.0.0.0",
	}
	for url in cases:
		var u := LFUrl.parse(url)
		assert_true(u.is_valid(), url)
		assert_eq(u.host, cases[url], url)
	assert_eq(str(LFUrl.parse("http://2130706433:8080/x")), "http://127.0.0.1:8080/x")


func test_numeric_looking_hosts_that_are_not_ipv4_are_rejected():
	for url in ["http://256.1.1.1/", "http://1.2.3.4.5/", "http://4294967296/", "http://08.1.1.1/", "http://1.2.3.0x1ffffff/"]:
		var u := LFUrl.parse(url)
		assert_false(u.is_valid(), url)
		assert_eq(u.error, "Malformed IPv4 address", url)
	assert_true(LFUrl.parse("http://1.example.com/").is_valid(), "a name that only starts with a number")
	assert_true(LFUrl.parse("http://example.123abc/").is_valid())
	assert_true(LFUrl.parse("http://0xzz/").is_valid(), "not a number, so a name")


func test_ipv4_to_dotted():
	assert_eq(LFUrl.ipv4_to_dotted("2130706433"), "127.0.0.1")
	assert_eq(LFUrl.ipv4_to_dotted("0X7F.1"), "127.0.0.1")
	assert_eq(LFUrl.ipv4_to_dotted("192.168.1.20"), "192.168.1.20")
	assert_eq(LFUrl.ipv4_to_dotted("example.com"), "")
	assert_eq(LFUrl.ipv4_to_dotted("1.2.3.999"), "")
	assert_eq(LFUrl.ipv4_to_dotted(""), "")


func test_classify_host_ipv4_ranges():
	var cases := {
		"127.0.0.1": LFUrl.CLASS_LOOPBACK, "127.255.255.254": LFUrl.CLASS_LOOPBACK,
		"10.0.0.1": LFUrl.CLASS_PRIVATE, "172.16.0.1": LFUrl.CLASS_PRIVATE, "172.31.255.255": LFUrl.CLASS_PRIVATE,
		"192.168.1.1": LFUrl.CLASS_PRIVATE, "100.64.0.1": LFUrl.CLASS_PRIVATE,
		"172.15.0.1": LFUrl.CLASS_PUBLIC, "172.32.0.1": LFUrl.CLASS_PUBLIC, "100.63.0.1": LFUrl.CLASS_PUBLIC,
		"169.254.169.254": LFUrl.CLASS_LINK_LOCAL, "0.0.0.0": LFUrl.CLASS_UNSPECIFIED,
		"224.0.0.1": LFUrl.CLASS_RESERVED, "255.255.255.255": LFUrl.CLASS_RESERVED,
		"8.8.8.8": LFUrl.CLASS_PUBLIC, "93.184.216.34": LFUrl.CLASS_PUBLIC,
	}
	for host in cases:
		assert_eq(LFUrl.classify_host(host), cases[host], host)


func test_classify_host_sees_through_legacy_numeric_forms():
	assert_eq(LFUrl.classify_host("2130706433"), LFUrl.CLASS_LOOPBACK)
	assert_eq(LFUrl.classify_host("0x7f.1"), LFUrl.CLASS_LOOPBACK)
	assert_eq(LFUrl.classify_host("127.1"), LFUrl.CLASS_LOOPBACK)
	assert_eq(LFUrl.classify_host("0xa9fea9fe"), LFUrl.CLASS_LINK_LOCAL)
	assert_eq(LFUrl.classify_host("167772161"), LFUrl.CLASS_PRIVATE)


func test_classify_host_ipv6():
	var cases := {
		"::1": LFUrl.CLASS_LOOPBACK, "[::1]": LFUrl.CLASS_LOOPBACK, "0:0:0:0:0:0:0:1": LFUrl.CLASS_LOOPBACK,
		"::": LFUrl.CLASS_UNSPECIFIED,
		"fe80::1": LFUrl.CLASS_LINK_LOCAL, "febf::1": LFUrl.CLASS_LINK_LOCAL, "fe80::1%eth0": LFUrl.CLASS_LINK_LOCAL,
		"fc00::1": LFUrl.CLASS_PRIVATE, "fd12:3456::1": LFUrl.CLASS_PRIVATE,
		"ff02::1": LFUrl.CLASS_RESERVED,
		"2606:4700:4700::1111": LFUrl.CLASS_PUBLIC, "fec0::1": LFUrl.CLASS_PUBLIC,
		"::ffff:10.0.0.1": LFUrl.CLASS_PRIVATE, "::ffff:a00:1": LFUrl.CLASS_PRIVATE,
		"::ffff:127.0.0.1": LFUrl.CLASS_LOOPBACK, "::FFFF:7F00:1": LFUrl.CLASS_LOOPBACK,
		"::ffff:8.8.8.8": LFUrl.CLASS_PUBLIC, "::ffff:169.254.169.254": LFUrl.CLASS_LINK_LOCAL,
		"::10.0.0.1": LFUrl.CLASS_PRIVATE, "64:ff9b::7f00:1": LFUrl.CLASS_LOOPBACK,
		"2002:c0a8:101::1": LFUrl.CLASS_PRIVATE, "2002:808:808::1": LFUrl.CLASS_PUBLIC,
	}
	for host in cases:
		assert_eq(LFUrl.classify_host(host), cases[host], host)


func test_classify_host_local_names():
	for host in ["localhost", "LOCALHOST", "localhost.", "app.localhost", "printer.local", "x.localdomain", "db.internal"]:
		assert_eq(LFUrl.classify_host(host), LFUrl.CLASS_LOCAL_NAME, host)
	for host in ["example.com", "notlocalhost.com", "localhost.example.com", "mylocal", ""]:
		assert_eq(LFUrl.classify_host(host), LFUrl.CLASS_PUBLIC, host)


func test_parts_classify_the_host_of_a_parsed_url():
	assert_eq(LFUrl.parse("http://2130706433/").target_class(), LFUrl.CLASS_LOOPBACK)
	assert_true(LFUrl.parse("http://[::ffff:10.0.0.1]/").is_local_target())
	assert_true(LFUrl.parse("http://[fd00::1]:80/").is_local_target())
	assert_true(LFUrl.parse("ws://LocalHost:9000/").is_local_target())
	assert_true(LFUrl.parse("http://0x7f.1/").is_local_target())
	assert_false(LFUrl.parse("https://example.com/").is_local_target())
	assert_false(LFUrl.parse("https://8.8.8.8/").is_local_target())
	assert_eq(LFUrl.parse("http://[::ffff:10.0.0.1]/").host, "::ffff:10.0.0.1")


func test_classify_host_treats_an_unparseable_ipv6_as_public_rather_than_guessing():
	assert_eq(LFUrl.classify_host("1:2:3"), LFUrl.CLASS_PUBLIC)
	assert_eq(LFUrl.classify_host("::1::2"), LFUrl.CLASS_PUBLIC)
	assert_eq(LFUrl.classify_host("::ffff:999.0.0.1"), LFUrl.CLASS_PUBLIC)


func test_a_percent_sign_in_a_registered_name_is_rejected():
	for host in ["%6cocalhost", "%31%32%37.0.0.1", "127.0.0.1%2e", "localhost%00", "a%20b"]:
		assert_false(LFUrl.parse("http://%s/" % host).is_valid(), "rejects %s" % host)


func test_classify_host_never_calls_a_host_with_a_percent_public():
	assert_eq(LFUrl.classify_host("%6cocalhost"), LFUrl.CLASS_RESERVED)
	assert_eq(LFUrl.classify_host("%31%32%37.0.0.1"), LFUrl.CLASS_RESERVED)
	# A zone id is still stripped from an IPv6 address.
	assert_eq(LFUrl.classify_host("fe80::1%eth0"), LFUrl.CLASS_LINK_LOCAL)
	assert_eq(LFUrl.classify_host("[::1]"), LFUrl.CLASS_LOOPBACK)


func test_several_trailing_dots_still_name_localhost():
	assert_eq(LFUrl.classify_host("localhost.."), LFUrl.CLASS_LOCAL_NAME)
	assert_eq(LFUrl.classify_host("foo.localhost..."), LFUrl.CLASS_LOCAL_NAME)
	assert_eq(LFUrl.classify_host("localhost."), LFUrl.CLASS_LOCAL_NAME)
	assert_eq(LFUrl.classify_host("example.com.."), LFUrl.CLASS_PUBLIC)


func test_ipv4_translated_ipv6_is_classified_by_its_embedded_address():
	assert_eq(LFUrl.classify_host("::ffff:0:127.0.0.1"), LFUrl.CLASS_LOOPBACK)
	assert_eq(LFUrl.classify_host("[::ffff:0:7f00:1]"), LFUrl.CLASS_LOOPBACK)
	assert_eq(LFUrl.classify_host("::ffff:0:10.0.0.1"), LFUrl.CLASS_PRIVATE)
	assert_eq(LFUrl.classify_host("::ffff:0:8.8.8.8"), LFUrl.CLASS_PUBLIC)
