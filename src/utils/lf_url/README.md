# LFUrl, LFUrl.Parts

> Checks and takes apart web addresses, and turns what a player typed ("192.168.1.20:9000") into a proper URL, saying clearly when an address is wrong.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_url.gd` |
| **Tests** | `tests/test_lf_url.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | none |

## When to use it

Use it whenever your game handles a web address it did not hard-code: a server address a
player types into a "Join game" box (`192.168.1.20:9000` becomes `ws://192.168.1.20:9000`),
a link a server sends back, or a redirect to follow. It tells you clearly when an address
is wrong and why, instead of failing later inside a connection. Godot has no URL parser
of its own; `HTTPRequest` and `WebSocketPeer` take a URL string and only fail when they
try to connect. `LFHttp` parses its URLs with this class; `LFSocket` does not, so check a
typed address with `LFUrl.from_address` before handing it to `LFSocket`.

## Step by step

Nothing here touches the network; it only reads and builds text, so it works anywhere.

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock click **Other Node**,
   pick **Node**, and press *Create*. Save it (*Ctrl+S*, Cmd+S on macOS) as `url_demo.tscn`.
2. Right-click the Node in the Scene dock and choose *Attach Script*, then press *Create*.
3. Replace everything in the script with this:

```gdscript
extends Node


func _ready() -> void:
	# Turn what a player typed into a WebSocket address.
	# Arguments: the typed text, the scheme to add when missing ("ws" = WebSocket),
	# the schemes you accept, and a port to use when the text has none.
	var typed := "192.168.1.20"
	var address := LFUrl.from_address(typed, "ws", ["ws", "wss"], 9000)
	if address == "":
		print("That address is not usable")   # "" means invalid
	else:
		print(address)                         # ws://192.168.1.20:9000

	# Take an address apart. parse() gives back an object with named parts.
	var parts := LFUrl.parse("https://example.com:8080/api/items?page=2")
	print(parts.host)               # example.com
	print(parts.effective_port())   # 8080 (443 if the address had no port: https default)
	print(parts.path)               # /api/items
	print(parts.query)              # page=2

	# A bad address never crashes; it says why.
	var bad := LFUrl.parse("http://exa mple.com/")
	print(bad.is_valid(), " ", bad.error)   # false, plus the reason
```

4. Press *F6* (Run Current Scene). In the **Output** panel at the bottom you should see
   `ws://192.168.1.20:9000`, then `example.com`, `8080`, `/api/items`, `page=2`, and
   `false` followed by the reason the last address was refused.
5. Make it yours: change `typed` to other input (`"my-server.net:7000"`, `"::1"`, a full
   `"wss://host/play"`); change `9000` to your game's default port; change the allowed
   schemes list, for example `["http", "https"]` for web (not WebSocket) addresses.

## API

Everything the class offers; you only need the rows used above to get started.

### LFUrl (static)

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_PORTS` | `const DEFAULT_PORTS: Dictionary` | `{"http": 80, "https": 443, "ws": 80, "wss": 443}` — the supported schemes. |
| `parse` | `static parse(url: String) -> Parts` | Parses `scheme://[userinfo@]host[:port][/path][?query][#fragment]`. Surrounding spaces are ignored (any other whitespace or control character, even at an end, rejects the URL) and the fragment is dropped. A host in a legacy numeric IPv4 form is rewritten to dotted decimal. Never returns `null` and never raises an engine error: check `is_valid()`, and read `error` for the reason. |
| `resolve` | `static resolve(base: String, relative_url: String) -> Parts` | Resolves `relative_url` against `base` per RFC 3986 section 5.2: an absolute URL replaces the base, `//host/x` keeps the base scheme, `/x` keeps the authority, `x` and `../x` merge with the base path, `?q` keeps the base path, `#f` (or `""`) gives the base itself. `.` and `..` segments are removed. Invalid when `base`, the reference or the result does not parse. |
| `default_port` | `static default_port(scheme: String) -> int` | Default port of a supported scheme (case-insensitive), `0` otherwise. |
| `classify_host` | `static classify_host(host: String) -> String` | Says what a host is, for SSRF checks: one of `CLASS_LOOPBACK` (`127/8`, `::1`), `CLASS_PRIVATE` (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`, IPv6 `fc00::/7`), `CLASS_LINK_LOCAL` (`169.254/16`, `fe80::/10`), `CLASS_UNSPECIFIED` (`0.0.0.0/8`, `::`), `CLASS_RESERVED` (`224.0.0.0/3`, `ff00::/8`), `CLASS_LOCAL_NAME` (`localhost`, `*.localhost`, `*.local`, `*.localdomain`, `*.internal`) or `CLASS_PUBLIC` (anything else). Takes a bare host, a bracketed IPv6 literal or a `Parts.host`; legacy numeric IPv4 (`2130706433`, `0x7f.1`), IPv4-mapped (`::ffff:10.0.0.1`), IPv4-compatible, NAT64 `64:ff9b::/96` and 6to4 `2002::/16` addresses are classified by the IPv4 address they carry, as is IPv4-translated `::ffff:0:a.b.c.d`; a zone id (IPv6 only) and trailing dots are ignored, and a host with a `%` that is not an IPv6 address is `CLASS_RESERVED`. |
| `ipv4_to_dotted` | `static ipv4_to_dotted(address: String) -> String` | An IPv4 address written as one to four decimal, `0x` hexadecimal or leading-zero octal parts, as dotted decimal (`2130706433` and `127.1` give `127.0.0.1`, `010.0.0.1` gives `8.0.0.1`); `""` when it is not one. |
| `for_host` | `static for_host(scheme: String, host: String, port: int) -> String` | `scheme://host:port`, bracketing an IPv6 `host` (`ws://[::1]:9000`); `port` `0` leaves the port out. `""` when `host` is not a valid host on its own (a port, path, query or userinfo in it counts as invalid), the scheme is unsupported, or `port` is outside 0–65535. |
| `from_address` | `static from_address(address: String, default_scheme: String, allowed_schemes: PackedStringArray = [], fallback_port := 0) -> String` | A typed address as a URL: `host`, `host:port`, `[v6]:port`, a bare IPv6 address, or a full URL. Without `://` it gets `default_scheme`; `fallback_port > 0` fills in a missing port. `""` for an empty or invalid address (a `fallback_port` above 65535 counts as invalid), or a scheme outside `allowed_schemes` (empty allows every supported scheme). Surrounding whitespace is ignored. |

### LFUrl.Parts (inner class)

| Member | Signature | Description |
|---|---|---|
| `scheme` | `var scheme: String` | Lower-cased: `http`, `https`, `ws` or `wss`. |
| `userinfo` | `var userinfo: String` | `user[:password]` before the `@`; never part of `host`. Empty when absent. |
| `host` | `var host: String` | Lower-cased host name or IP; an IPv6 literal without its brackets (`::1`); an IPv4 address in dotted decimal, whatever form it was written in. |
| `port` | `var port: int` | Explicit port 1–65535, or `0` when the URL gives none. |
| `path` | `var path: String` | Path with its leading `/`; `""` when absent (`http://h?x=1` has an empty path). |
| `query` | `var query: String` | Query without the `?`; `""` when absent. |
| `error` | `var error: String` | Why parsing failed; `""` for a valid URL. |
| `is_valid` | `is_valid() -> bool` | `true` when the URL parsed. |
| `target_class` | `target_class() -> String` | `LFUrl.classify_host(host)`. |
| `is_local_target` | `is_local_target() -> bool` | `true` unless the host classifies as `CLASS_PUBLIC`. |
| `is_ipv6` | `is_ipv6() -> bool` | `true` when `host` is an IPv6 literal. |
| `effective_port` | `effective_port() -> int` | `port`, or the scheme's default when `port` is `0`. |
| `host_port` | `host_port() -> String` | Host (bracketed for IPv6) plus `:port` unless the port is the scheme default — the HTTP `Host` header value. |
| `origin` | `origin() -> String` | `scheme://host:effective_port` (host bracketed for IPv6), for same-origin checks; `""` when invalid. |
| `with_default_port` | `with_default_port(fallback: int) -> Parts` | A copy whose `port` is `fallback` when the URL had none. |
| `copy` | `copy() -> Parts` | An independent copy. |
| `invalid` | `static invalid(reason: String) -> Parts` | An invalid result with `error = reason`. |
| `str(parts)` / `parts.to_string()` | `-> String` | Serialises the URL (userinfo, bracketed IPv6 host, explicit port, path, query; no fragment). `""` when invalid. |

## Usage

```gdscript
# join_menu.gd: a script on a Node of your "Join game" menu.
extends Node


func _ready() -> void:
	# Read a URL into its parts.
	var url := LFUrl.parse("https://example.com:8080/api/items?page=2")
	if url.is_valid():
		print(url.host, ":", url.effective_port(), url.path)   # example.com:8080/api/items

	# A bad URL says why.
	var bad := LFUrl.parse("http://exa mple.com/")
	print(bad.is_valid(), " ", bad.error)                 # false Control character or space

	# Follow a relative link.
	print(LFUrl.resolve("http://h/a/b/c", "../x"))        # http://h/a/x

	# Build one from a host and a port.
	print(LFUrl.for_host("wss", "fe80::1", 443))          # wss://[fe80::1]:443

	print(server_url_from("10.0.0.2"))                    # ws://10.0.0.2:7777
	print(server_url_from("::1"))                         # ws://[::1]:7777
	print(server_url_from("ftp://x"))                     # (empty: not allowed)


# Turns what the player typed into a WebSocket URL, or "" when it is not usable.
func server_url_from(typed: String) -> String:
	return LFUrl.from_address(typed, "ws", ["ws", "wss"], 7777)
```

## Notes

- The scheme is case-insensitive (`HTTP://` parses as `http`); only `http`, `https`, `ws` and `wss` are accepted.
- Any ASCII control character (CR, LF and tab included), C1 control character (U+0080–U+009F), space, DEL or backslash inside the URL rejects it, and so does a control character at either end, so a parsed URL cannot split a request line or a `Host` header in two. Only plain spaces at the ends are trimmed. Other non-ASCII characters (including U+2028 and zero-width characters) are not refused. A Godot `String` cannot hold a NUL character. `from_address` still trims all surrounding whitespace first, since it takes typed text.
- **Numeric hosts.** A host whose last label is a number is read as IPv4 the way resolvers do: one to four parts, each decimal, `0x` hexadecimal or leading-zero octal, the last part filling the remaining bytes. `http://2130706433/`, `http://0x7f.1/` and `http://127.1/` all have host `127.0.0.1`; one that does not fit (`256.1.1.1`, `1.2.3.4.5`, `08.1.1.1`) is rejected as `Malformed IPv4 address`. A name such as `1.example.com` or `0xzz` is an ordinary name.
- **SSRF checks.** `classify_host`, `Parts.target_class` and `Parts.is_local_target` look at the address text only. A DNS name that resolves to a private address (`localtest.me`, an attacker's own record) is `CLASS_PUBLIC`, Teredo and other IPv6 tunnel addresses are not unwrapped, and a redirect can lead elsewhere. A server that fetches player-supplied URLs must also check the address the connection really uses, and every redirect. Text `classify_host` cannot read as an IPv6 address is `CLASS_PUBLIC`; `parse` never produces such a host.
- The host is a registered name (`A–Z a–z 0–9 - . _ ~ ! $ & ' ( ) * + , ; =`; a `%` is rejected, because a client may decode it into another host: `%6cocalhost` is `localhost`) or a bracketed IPv6 literal checked by `String.is_valid_ip_address()`; zone ids (`%25…`) are not accepted. IPv6 needs brackets.
- `user[:password]@` is split into `userinfo`; `http://trusted.com@evil.com/` has host `evil.com`. More than one `@` is rejected.
- A port must be 1–65535 with at most five digits; `:0`, `:65536` and overlong ports are rejected. An empty port (`http://h:/`) means the default.
- Percent-escapes are kept verbatim (no decoding) in the host, path and query.
- The fragment is dropped by `parse` and `resolve`.
- `resolve` removes `.` and `..` segments in one pass over the path (time grows linearly with its length). Nothing caps the length of a URL here; `LFHttp` refuses URLs longer than `LFHttp.MAX_URL_LENGTH`.
