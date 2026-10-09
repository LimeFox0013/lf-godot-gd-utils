## Reads web addresses (http, https, ws and wss URLs) into their parts, rejects malformed
## ones with a reason, and builds them back.
##
## It accepts `scheme://[userinfo@]host[:port][/path][?query][#fragment]` and resolves a
## relative link against a base URL the way browsers do (RFC 3986). The fragment is
## accepted and dropped; percent-escapes (`%20`) are kept verbatim. A host written as a
## legacy numeric IPv4 address (`2130706433`, `0x7f.1`, `127.1`) is rewritten to dotted
## decimal (`127.0.0.1`). `classify_host` and `Parts.target_class` say whether a host is
## loopback, private, link-local or otherwise not a public address, for server-side
## request forgery (SSRF) checks. All functions are static; call them on the class
## (`LFUrl.parse(...)`).
class_name LFUrl
extends RefCounted

## Supported schemes and their default ports.
const DEFAULT_PORTS := { "http": 80, "https": 443, "ws": 80, "wss": 443 }

## Characters allowed in a registered host name (unreserved, percent and sub-delims).
const _HOST_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~%!$&'()*+,;="
## Characters allowed in userinfo: the host characters plus `:`.
const _USERINFO_CHARS := _HOST_CHARS + ":"
## Characters allowed in a scheme after its first letter.
const _SCHEME_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-."
## Characters allowed inside an IPv6 literal.
const _IPV6_CHARS := "0123456789abcdefABCDEF:."
## Characters allowed in a port.
const _DIGIT_CHARS := "0123456789"
## Separates the scheme from the authority.
const _SCHEME_SEPARATOR := "://"
## Starts a network-path reference (`//host/...`).
const _NETWORK_PATH_PREFIX := "//"
## Ends the scheme; separates host and port, and marks an IPv6 literal.
const _COLON := ":"
## Ends the userinfo.
const _AT := "@"
## Separates path segments.
const _SLASH := "/"
## Starts the query.
const _QUERY_MARK := "?"
## Starts the fragment.
const _FRAGMENT_MARK := "#"
## Opens a bracketed IPv6 literal.
const _BRACKET_OPEN := "["
## Closes a bracketed IPv6 literal.
const _BRACKET_CLOSE := "]"
## Format of a bracketed IPv6 literal.
const _BRACKETED_FORMAT := "[%s]"
## Format of `scheme://authority`.
const _SCHEME_AUTHORITY_FORMAT := "%s://%s"
## Format of a `:port` suffix.
const _PORT_SUFFIX_FORMAT := ":%d"
## Format of an origin (`scheme://host:port`).
const _ORIGIN_FORMAT := "%s://%s:%d"
## Lowest explicit port.
const _MIN_PORT := 1
## Highest port.
const _MAX_PORT := 65535
## Most digits a port may have.
const _MAX_PORT_DIGITS := 5
## Code point of `A`.
const _UPPER_A := 65
## Code point of `Z`.
const _UPPER_Z := 90
## Code point of `a`.
const _LOWER_A := 97
## Code point of `z`.
const _LOWER_Z := 122
## Space; it and every code point below it are refused.
const _SPACE := 0x20
## DEL, refused.
const _DEL := 0x7f
## Backslash, refused.
const _BACKSLASH := 0x5c
## First code point of the C1 control characters (refused).
const _C1_FIRST := 0x80
## Last code point of the C1 control characters (refused).
const _C1_LAST := 0x9f
## Dot segment: the current directory.
const _DOT := "."
## Dot segment: the parent directory.
const _DOT_DOT := ".."
## Separates the parts of an IPv4 address.
const _DOT_CHAR := "."
## Prefix of a hexadecimal IPv4 part.
const _HEX_PREFIX := "0x"
## Digits of a decimal IPv4 part.
const _DECIMAL_DIGITS := "0123456789"
## Digits of an octal IPv4 part.
const _OCTAL_DIGITS := "01234567"
## Digits of a hexadecimal IPv4 part.
const _HEX_DIGITS := "0123456789abcdef"
## Most parts a legacy IPv4 address has.
const _MAX_IPV4_PARTS := 4
## Values per IPv4 byte.
const _BYTE_VALUES := 256
## Marks an IPv6 zone id (`fe80::1%eth0`).
const _ZONE_MARK := "%"
## Bytes in an IPv6 address.
const _IPV6_BYTES := 16
## Groups in an IPv6 address.
const _IPV6_GROUPS := 8
## Separates the groups of an IPv6 address.
const _DOUBLE_COLON := "::"
## The host name of this machine.
const _LOCALHOST := "localhost"

## `classify_host`: a public unicast address, or a name that is not known to be local.
const CLASS_PUBLIC := "public"
## `classify_host`: loopback (`127.0.0.0/8`, `::1`).
const CLASS_LOOPBACK := "loopback"
## `classify_host`: private use (`10/8`, `172.16/12`, `192.168/16`, shared `100.64/10`, IPv6 `fc00::/7`).
const CLASS_PRIVATE := "private"
## `classify_host`: link-local (`169.254/16`, `fe80::/10`).
const CLASS_LINK_LOCAL := "link_local"
## `classify_host`: the unspecified address (`0.0.0.0/8`, `::`), which connects to this machine on many systems.
const CLASS_UNSPECIFIED := "unspecified"
## `classify_host`: multicast, broadcast or reserved (`224.0.0.0/3`, `ff00::/8`).
const CLASS_RESERVED := "reserved"
## `classify_host`: a name that means this machine or its network (`localhost`, `*.localhost`, `*.local`, `*.localdomain`, `*.internal`).
const CLASS_LOCAL_NAME := "local_name"


## Parses `url` (surrounding spaces are ignored; any other whitespace or control character,
## even at either end, rejects it). Always returns a `Parts`; check
## `is_valid()`, and read `error` for the reason a URL was rejected.
static func parse(url: String) -> Parts:
	var s := _trim_spaces(url)
	var bad := _bad_char_error(s)
	if bad != "":
		return Parts.invalid(bad)
	var frag := s.find(_FRAGMENT_MARK)
	if frag != -1:
		s = s.substr(0, frag)
	var sep := s.find(_SCHEME_SEPARATOR)
	if sep <= 0:
		return Parts.invalid("Missing scheme")
	var scheme := s.substr(0, sep)
	if !_is_scheme(scheme):
		return Parts.invalid("Malformed scheme")
	scheme = scheme.to_lower()
	if !DEFAULT_PORTS.has(scheme):
		return Parts.invalid("Unsupported scheme %s" % scheme)

	var rest := s.substr(sep + _SCHEME_SEPARATOR.length())
	var auth_end := rest.length()
	for c: Variant in [_SLASH, _QUERY_MARK]:
		var i := rest.find(c)
		if i != -1 and i < auth_end:
			auth_end = i
	var def := _parse_authority(rest.substr(0, auth_end))
	if !def.error.is_empty():
		return def
	def.scheme = scheme
	var tail := rest.substr(auth_end)
	var q := tail.find(_QUERY_MARK)
	if q == -1:
		def.path = tail
	else:
		def.path = tail.substr(0, q)
		def.query = tail.substr(q + 1)
	return def


## Resolves `relative_url` (absolute, `//host…`, `/path`, `relative/path`, `?query` or
## `#fragment`) against `base` per RFC 3986 section 5.2 (like a browser following a link),
## removing `.` and `..` segments. Returns an invalid `Parts` when `base`, the link or
## the result does not parse.
static func resolve(base: String, relative_url: String) -> Parts:
	var b := parse(base)
	if !b.is_valid():
		return b
	var ref := _trim_spaces(relative_url)
	var bad := _bad_char_error(ref)
	if bad != "":
		return Parts.invalid(bad)
	var frag := ref.find(_FRAGMENT_MARK)
	if frag != -1:
		ref = ref.substr(0, frag)

	var colon := ref.find(_COLON)
	var slash := ref.find(_SLASH)
	if colon > 0 and (slash == -1 or colon < slash) and _is_scheme(ref.substr(0, colon)):
		var absolute := parse(ref)
		if absolute.is_valid():
			absolute.path = _remove_dot_segments(absolute.path)
		return absolute
	if ref.begins_with(_NETWORK_PATH_PREFIX):
		var net := parse(b.scheme + _COLON + ref)
		if net.is_valid():
			net.path = _remove_dot_segments(net.path)
		return net

	var ref_path := ref
	var ref_query := ""
	var has_query := false
	var q := ref.find(_QUERY_MARK)
	if q != -1:
		ref_path = ref.substr(0, q)
		ref_query = ref.substr(q + 1)
		has_query = true

	var path := ""
	var query := ""
	if ref_path.is_empty():
		path = b.path
		query = ref_query if has_query else b.query
	else:
		if ref_path.begins_with(_SLASH):
			path = _remove_dot_segments(ref_path)
		elif b.path.is_empty():
			path = _remove_dot_segments(_SLASH + ref_path)
		else:
			path = _remove_dot_segments(b.path.substr(0, b.path.rfind(_SLASH) + 1) + ref_path)
		query = ref_query
	var out := b.copy()
	out.path = path
	out.query = query
	return out


## Returns the default port of `scheme` (case-insensitive), or 0 for an unsupported scheme.
static func default_port(scheme: String) -> int:
	return int(DEFAULT_PORTS.get(scheme.to_lower(), 0))


## Returns `scheme://host:port` with an IPv6 `host` bracketed (`ws://[::1]:9000`); `port` 0
## leaves the port out. `''` when `host` is not a valid host on its own (it may not carry
## a port, path, query or userinfo), the scheme is unsupported, or `port` is outside
## 0-65535.
static func for_host(scheme: String, host: String, port: int) -> String:
	if port < 0 or port > _MAX_PORT:
		return ""
	var bracketed := _BRACKETED_FORMAT % host if host.contains(_COLON) and !host.begins_with(_BRACKET_OPEN) else host
	var url := parse(_SCHEME_AUTHORITY_FORMAT % [scheme, bracketed])
	if !url.is_valid() or url.port != 0 or !url.path.is_empty() or !url.query.is_empty() \
			or !url.userinfo.is_empty() or url.host != _unbracketed(bracketed).to_lower():
		return ""
	url.port = port
	return str(url)


## Returns an address a user typed as a URL: `host`, `host:port`, `[v6]:port`, a bare
## IPv6 address or a full URL. An address without `://` gets `default_scheme`;
## `fallback_port` (when above 0) fills in a missing port. `''` when the result is not a
## valid URL (including a `fallback_port` above 65535), or its scheme is not in
## `allowed_schemes` (an empty list allows every supported scheme). Surrounding
## whitespace is ignored.
static func from_address(address: String, default_scheme: String, allowed_schemes: PackedStringArray = [], fallback_port := 0) -> String:
	var trimmed := address.strip_edges()
	if trimmed.is_empty() or fallback_port > _MAX_PORT:
		return ""
	if !trimmed.contains(_SCHEME_SEPARATOR):
		if trimmed.count(_COLON) > 1 and !trimmed.begins_with(_BRACKET_OPEN):
			trimmed = _BRACKETED_FORMAT % trimmed
		trimmed = _SCHEME_AUTHORITY_FORMAT % [default_scheme, trimmed]
	var url := parse(trimmed)
	if !url.is_valid():
		return ""
	if !allowed_schemes.is_empty():
		var allowed := false
		for each in allowed_schemes:
			allowed = allowed or each.to_lower() == url.scheme
		if !allowed:
			return ""
	return str(url.with_default_port(fallback_port) if fallback_port > 0 else url)


## Returns the classification of `host` (a host name, IPv4 or IPv6 address, bracketed or
## not): one of the `CLASS_*` constants. IPv4 in any legacy numeric form (`2130706433`,
## `0x7f.1`), IPv4-mapped IPv6 (`::ffff:10.0.0.1`), IPv4-compatible IPv6 (`::10.0.0.1`),
## NAT64 (`64:ff9b::/96`) and 6to4 (`2002::/16`) addresses are classified by the IPv4
## address they carry, as is IPv4-translated `::ffff:0:a.b.c.d`. A zone id (`%eth0`, IPv6 only) and trailing dots are ignored. A host with a `%` that is not an IPv6 address is `CLASS_RESERVED`, since a client may decode it. A name that is
## not one of the local names is `CLASS_PUBLIC`: a DNS name can still resolve to a
## private address, and Teredo addresses are not unwrapped, so an SSRF check must also
## check the address a connection actually uses.
static func classify_host(host: String) -> String:
	var h := _unbracketed(host.strip_edges()).to_lower()
	if h.contains(_COLON):
		var zone := h.find(_ZONE_MARK)
		if zone != -1:
			h = h.substr(0, zone)
		var bytes := _ipv6_bytes(h)
		return CLASS_PUBLIC if bytes.is_empty() else _classify_ipv6(bytes)
	if h.contains(_ZONE_MARK):
		# A percent sign outside an IPv6 address would be decoded by a resolver or client
		# (`%6cocalhost` is `localhost`), so the real host is unknown: never public.
		return CLASS_RESERVED
	while h.ends_with(_DOT_CHAR):
		h = h.trim_suffix(_DOT_CHAR)
	if h == _LOCALHOST or h.ends_with(".localhost") or h.ends_with(".local") \
			or h.ends_with(".localdomain") or h.ends_with(".internal"):
		return CLASS_LOCAL_NAME
	var v4 := ipv4_to_dotted(h)
	if v4.is_empty():
		return CLASS_PUBLIC
	return _classify_ipv4(_ipv4_bytes(v4))


## Returns `address` as dotted decimal when it is an IPv4 address in the forms a browser
## or resolver accepts: one to four parts, each decimal, hexadecimal (`0x7f`) or octal
## (leading `0`), the last part filling the remaining bytes (`2130706433` and `127.1` are
## `127.0.0.1`; `0x7f.1` is `127.0.0.1`; `010.0.0.1` is `8.0.0.1`). `''` when it is not
## such an address, including a numeric-looking one with a part out of range.
static func ipv4_to_dotted(address: String) -> String:
	var parts := address.to_lower().trim_suffix(_DOT_CHAR).split(_DOT_CHAR)
	if parts.size() > _MAX_IPV4_PARTS or !_is_number_part(parts[parts.size() - 1]):
		return ""
	var value := 0
	var last := parts.size() - 1
	for i in parts.size():
		var n := _ipv4_part_value(parts[i])
		if n < 0:
			return ""
		if i < last:
			if n >= _BYTE_VALUES:
				return ""
			value += n << (8 * (_MAX_IPV4_PARTS - 1 - i))
		else:
			if n >= 1 << (8 * (_MAX_IPV4_PARTS - last)):
				return ""
			value += n
	return "%d.%d.%d.%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255]


## Whether `part` looks like a number a resolver reads (decimal, `0x` hex or leading-zero octal digits).
static func _is_number_part(part: String) -> bool:
	if part.begins_with(_HEX_PREFIX):
		return _only_chars(part.substr(_HEX_PREFIX.length()), _HEX_DIGITS)
	return !part.is_empty() and _only_chars(part, _DECIMAL_DIGITS)


## The value of one numeric IPv4 part, or -1 when it is not a number (or too long to be one).
static func _ipv4_part_value(part: String) -> int:
	var digits := part
	var base := 10
	var allowed := _DECIMAL_DIGITS
	if part.begins_with(_HEX_PREFIX):
		digits = part.substr(_HEX_PREFIX.length())
		base = 16
		allowed = _HEX_DIGITS
	elif part.length() > 1 and part.begins_with("0"):
		digits = part.substr(1)
		base = 8
		allowed = _OCTAL_DIGITS
	if digits.is_empty():
		return 0 if base == 16 else -1
	if digits.length() > 12 or !_only_chars(digits, allowed):
		return -1
	return digits.hex_to_int() if base == 16 else _digits_to_int(digits, base)


static func _digits_to_int(digits: String, base: int) -> int:
	var n := 0
	for i in digits.length():
		n = n * base + _DECIMAL_DIGITS.find(digits[i])
	return n


static func _ipv4_bytes(dotted: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for part in dotted.split(_DOT_CHAR):
		out.append(int(part))
	return out


static func _classify_ipv4(b: PackedInt32Array) -> String:
	if b[0] == 127:
		return CLASS_LOOPBACK
	if b[0] == 0:
		return CLASS_UNSPECIFIED
	if b[0] == 10 or (b[0] == 172 and b[1] >= 16 and b[1] <= 31) or (b[0] == 192 and b[1] == 168) \
			or (b[0] == 100 and b[1] >= 64 and b[1] <= 127):
		return CLASS_PRIVATE
	if b[0] == 169 and b[1] == 254:
		return CLASS_LINK_LOCAL
	if b[0] >= 224:
		return CLASS_RESERVED
	return CLASS_PUBLIC


## The 16 bytes of the IPv6 address `h` (no brackets, lower case; an IPv4 tail allowed),
## or an empty array when it is not one.
static func _ipv6_bytes(h: String) -> PackedInt32Array:
	var none := PackedInt32Array()
	if !_only_chars(h, _IPV6_CHARS) or (!h.contains(_DOT_CHAR) and !h.is_valid_ip_address()):
		return none
	var text := h
	if text.contains(_DOT_CHAR):
		var cut := text.rfind(_COLON)
		var v4 := ipv4_to_dotted(text.substr(cut + 1))
		if v4.is_empty():
			return none
		var q := _ipv4_bytes(v4)
		text = text.substr(0, cut + 1) + "%x:%x" % [q[0] * 256 + q[1], q[2] * 256 + q[3]]
	var halves := text.split(_DOUBLE_COLON)
	if halves.size() > 2:
		return none
	var head := _groups(halves[0])
	var tail := _groups(halves[1]) if halves.size() == 2 else PackedInt32Array()
	if halves.size() == 1 and head.size() != _IPV6_GROUPS:
		return none
	if halves.size() == 2 and head.size() + tail.size() > _IPV6_GROUPS - 1:
		return none
	var groups := head
	for _i in _IPV6_GROUPS - head.size() - tail.size():
		if halves.size() == 2:
			groups.append(0)
	groups.append_array(tail)
	if groups.size() != _IPV6_GROUPS or groups.has(-1):
		return none
	var out := PackedInt32Array()
	for g in groups:
		out.append(g >> 8)
		out.append(g & 255)
	return out


static func _groups(text: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if text.is_empty():
		return out
	for g in text.split(_COLON):
		if g.is_empty() or g.length() > 4 or !_only_chars(g, _HEX_DIGITS):
			return PackedInt32Array([-1])
		out.append(g.hex_to_int())
	return out


static func _classify_ipv6(b: PackedInt32Array) -> String:
	var zeros_to_10 := true
	for i in 10:
		zeros_to_10 = zeros_to_10 and b[i] == 0
	if zeros_to_10:
		if b[10] == 255 and b[11] == 255:
			return _classify_ipv4(b.slice(12, 16))
		if b[10] == 0 and b[11] == 0:
			if b[12] == 0 and b[13] == 0 and b[14] == 0:
				if b[15] == 0:
					return CLASS_UNSPECIFIED
				if b[15] == 1:
					return CLASS_LOOPBACK
			return _classify_ipv4(b.slice(12, 16))
	# IPv4-translated ::ffff:0:a.b.c.d (RFC 2765) carries the IPv4 address in bytes 12-15.
	var zeros_to_8 := true
	for i in 8:
		zeros_to_8 = zeros_to_8 and b[i] == 0
	if zeros_to_8 and b[8] == 255 and b[9] == 255 and b[10] == 0 and b[11] == 0:
		return _classify_ipv4(b.slice(12, 16))
	# NAT64 well-known prefix 64:ff9b::/96.
	if b[0] == 0 and b[1] == 0x64 and b[2] == 0xff and b[3] == 0x9b:
		var rest_zero := true
		for i in range(4, 12):
			rest_zero = rest_zero and b[i] == 0
		if rest_zero:
			return _classify_ipv4(b.slice(12, 16))
	# 6to4 2002::/16 carries the IPv4 address in bytes 2-5.
	if b[0] == 0x20 and b[1] == 0x02:
		return _classify_ipv4(b.slice(2, 6))
	if (b[0] & 0xfe) == 0xfc:
		return CLASS_PRIVATE
	if b[0] == 0xfe and (b[1] & 0xc0) == 0x80:
		return CLASS_LINK_LOCAL
	if b[0] == 0xff:
		return CLASS_RESERVED
	return CLASS_PUBLIC


## Whether the last label of `host` is numeric, which makes a resolver read it as IPv4.
static func _ends_in_number(host: String) -> bool:
	var labels := host.trim_suffix(_DOT_CHAR).split(_DOT_CHAR)
	return _is_number_part(labels[labels.size() - 1])


static func _trim_spaces(s: String) -> String:
	return s.lstrip(" ").rstrip(" ")


static func _unbracketed(host: String) -> String:
	return host.trim_prefix(_BRACKET_OPEN).trim_suffix(_BRACKET_CLOSE)


static func _is_scheme(s: String) -> bool:
	if s.is_empty() or !_is_alpha(s.unicode_at(0)):
		return false
	return _only_chars(s, _SCHEME_CHARS)


static func _is_alpha(c: int) -> bool:
	return (c >= _UPPER_A and c <= _UPPER_Z) or (c >= _LOWER_A and c <= _LOWER_Z)


static func _only_chars(s: String, allowed: String) -> bool:
	for i in s.length():
		if allowed.find(s[i]) == -1:
			return false
	return true


## Empty when `s` holds no control character (C0, DEL or C1), space or backslash.
static func _bad_char_error(s: String) -> String:
	for i in s.length():
		var c := s.unicode_at(i)
		if c <= _SPACE or c == _DEL or (c >= _C1_FIRST and c <= _C1_LAST):
			return "Control character or space"
		if c == _BACKSLASH:
			return "Backslash"
	return ""


static func _parse_authority(auth: String) -> Parts:
	var def := Parts.new()
	var hostport := auth
	var at := auth.find(_AT)
	if at != -1:
		if auth.find(_AT, at + 1) != -1:
			return Parts.invalid("More than one @ in authority")
		def.userinfo = auth.substr(0, at)
		if !_only_chars(def.userinfo, _USERINFO_CHARS):
			return Parts.invalid("Malformed userinfo")
		hostport = auth.substr(at + 1)

	var port_str := ""
	var has_port := false
	if hostport.begins_with(_BRACKET_OPEN):
		var close := hostport.find(_BRACKET_CLOSE)
		if close == -1:
			return Parts.invalid("Unclosed IPv6 bracket")
		var ip := hostport.substr(1, close - 1)
		if !ip.contains(_COLON) or !_only_chars(ip, _IPV6_CHARS) or !ip.is_valid_ip_address():
			return Parts.invalid("Malformed IPv6 address")
		def.host = ip.to_lower()
		var after := hostport.substr(close + 1)
		if !after.is_empty():
			if !after.begins_with(_COLON):
				return Parts.invalid("Malformed authority")
			port_str = after.substr(1)
			has_port = true
	else:
		var colon := hostport.find(_COLON)
		var host := hostport
		if colon != -1:
			host = hostport.substr(0, colon)
			port_str = hostport.substr(colon + 1)
			has_port = true
		if host.is_empty():
			return Parts.invalid("Missing host")
		if !_only_chars(host, _HOST_CHARS) or host.contains(_ZONE_MARK):
			return Parts.invalid("Malformed host")
		def.host = host.to_lower()
		var dotted := ipv4_to_dotted(def.host)
		if !dotted.is_empty():
			def.host = dotted
		elif _ends_in_number(def.host):
			return Parts.invalid("Malformed IPv4 address")

	if has_port and !port_str.is_empty():
		if port_str.length() > _MAX_PORT_DIGITS or !port_str.is_valid_int() or !_only_chars(port_str, _DIGIT_CHARS):
			return Parts.invalid("Malformed port")
		var p := port_str.to_int()
		if p < _MIN_PORT or p > _MAX_PORT:
			return Parts.invalid("Port out of range")
		def.port = p
	return def


## RFC 3986 section 5.2.4 for a path that is empty or starts with `/` (every path this
## class passes): walks the segments once with a stack, so its time grows linearly with
## the path's length.
static func _remove_dot_segments(path: String) -> String:
	if path.is_empty():
		return path
	var segments := path.split(_SLASH)
	var absolute := path.begins_with(_SLASH)
	var first := 1 if absolute else 0
	var last := segments.size() - 1
	var kept := PackedStringArray()
	for i in range(first, segments.size()):
		var segment := segments[i]
		if segment == _DOT or segment == _DOT_DOT:
			if segment == _DOT_DOT and !kept.is_empty():
				kept.resize(kept.size() - 1)
			# A dot segment at the end leaves the path ending in `/`.
			if i == last:
				kept.append("")
		else:
			kept.append(segment)
	return (_SLASH if absolute else "") + _SLASH.join(kept)


## The parts of a parsed URL, returned by `LFUrl.parse()` and `LFUrl.resolve()`. `str()`
## of it turns it back into text (without a fragment).
class Parts extends RefCounted:
	## Lower-cased scheme: `http`, `https`, `ws` or `wss`.
	var scheme := ""
	## `user[:password]` before the `@`, empty when absent. Never part of `host`.
	var userinfo := ""
	## Lower-cased host name or IP address; an IPv6 literal without its brackets.
	var host := ""
	## Explicit port 1-65535, or 0 when the URL has none.
	var port := 0
	## Path including its leading `/`, empty when absent. Percent-escapes are kept.
	var path := ""
	## Query string without the `?`, empty when absent.
	var query := ""
	## Why the URL was rejected; empty for a valid URL.
	var error := ""

	## Returns an invalid result carrying `reason` in `error`.
	static func invalid(reason: String) -> Parts:
		var def := Parts.new()
		def.error = reason
		return def

	## Returns `true` when the URL parsed. Check it before reading the other fields.
	func is_valid() -> bool:
		return error.is_empty() and !scheme.is_empty() and !host.is_empty()

	## Returns `true` when the host is an IPv6 address (like `::1`).
	func is_ipv6() -> bool:
		return host.contains(_COLON)

	## Returns the `CLASS_*` constant of `LFUrl.classify_host` for this URL's host.
	func target_class() -> String:
		return LFUrl.classify_host(host)

	## Returns `true` when the host is anything but `CLASS_PUBLIC`: loopback, private,
	## link-local, unspecified, reserved or a local name. For SSRF checks; see
	## `LFUrl.classify_host` for what it cannot see (a DNS name resolving to a private address).
	func is_local_target() -> bool:
		return LFUrl.classify_host(host) != LFUrl.CLASS_PUBLIC

	## Returns `port`, or the scheme's default port when the URL has none.
	func effective_port() -> int:
		return port if port > 0 else LFUrl.default_port(scheme)

	## Returns the host (bracketed when IPv6) plus `:port` unless the port is the scheme default;
	## the value of an HTTP `Host` header.
	func host_port() -> String:
		var h := _bracketed_host()
		if port > 0 and port != LFUrl.default_port(scheme):
			h += _PORT_SUFFIX_FORMAT % port
		return h

	## Returns `scheme://host:effective_port`, for same-origin checks (two URLs with the
	## same origin are the same server); empty when invalid.
	func origin() -> String:
		if !is_valid():
			return ""
		return _ORIGIN_FORMAT % [scheme, _bracketed_host(), effective_port()]

	## Returns a copy with `port` set to `fallback` when the URL has no explicit port.
	func with_default_port(fallback: int) -> Parts:
		var out := copy()
		if out.port == 0:
			out.port = fallback
		return out

	## Returns an independent copy; changing it leaves this one as it is.
	func copy() -> Parts:
		var out := Parts.new()
		out.scheme = scheme
		out.userinfo = userinfo
		out.host = host
		out.port = port
		out.path = path
		out.query = query
		out.error = error
		return out

	func _bracketed_host() -> String:
		return _BRACKETED_FORMAT % host if is_ipv6() else host

	func _to_string() -> String:
		if !is_valid():
			return ""
		var s := scheme + _SCHEME_SEPARATOR
		if !userinfo.is_empty():
			s += userinfo + _AT
		s += _bracketed_host()
		if port > 0:
			s += _PORT_SUFFIX_FORMAT % port
		s += path
		if !query.is_empty():
			s += _QUERY_MARK + query
		return s
