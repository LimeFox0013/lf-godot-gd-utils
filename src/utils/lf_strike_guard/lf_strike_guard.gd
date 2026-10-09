## Blocks a key (an address, an account name) for a while after too many failed attempts.
##
## A key that collects `max_strikes` strikes within `window_seconds` seconds is
## blocked for `block_seconds` seconds. Strikes older than the window no longer count. A
## success never clears strikes (only `forget(key)` and `clear()` do), so slow guessing between
## successes still adds up.
##
## Pair it with `LFSocketServer.peer_address` to throttle wrong passwords, access
## codes or keys per address, keyed through `address_key` so one IPv6 user cannot dodge
## the limit by switching addresses inside their /64 network (one holding a larger block,
## such as a /48, can still move between its /64 networks). Behind a reverse proxy
## every peer has the proxy's address, so one guesser would block everyone: limit per
## address at the proxy instead. Call `prune()` now and then (every few
## seconds) on a long-running server so keys that stopped guessing are forgotten.
##
## A `clock_seconds` that can no longer be called (its object was freed) fails closed: every
## key counts as blocked, `strike` returns `true`, and an error is reported once.
class_name LFStrikeGuard
extends RefCounted

static var _log := LFLogger.new()

## Milliseconds in a second, for the default clock.
const _MS_PER_SECOND := 1000.0
## Hextets (16-bit groups) in an IPv6 address.
const _IPV6_HEXTETS := 8
## Hextets that make up an IPv6 /64 network prefix.
const _IPV6_PREFIX_HEXTETS := 4
## Suffix `address_key` puts after an IPv6 /64 prefix.
const _IPV6_PREFIX_SUFFIX := '::/64'
## The sixth group of an IPv4 address written as IPv6 ("IPv4-mapped", `::ffff:a.b.c.d`),
## whose first five groups are zero.
const _IPV4_MAPPED_MARK := 0xffff
## Index of that group.
const _IPV4_MAPPED_MARK_INDEX := 5
## How `address_key` writes an IPv4 address, plain or IPv4-mapped: dotted decimal.
const _IPV4_FORMAT := '%d.%d.%d.%d'

## How many strikes within the window block a key. 1 (or less) blocks on the first
## strike. May be changed at any time; the next strike reads it.
var max_strikes: int
## Seconds a strike keeps counting toward a block. May be changed at any time. A NaN is
## rejected: reported through `LFLogger` as an error, and the value is kept.
var window_seconds: float:
	get:
		return _window_seconds
	set(value):
		if is_nan(value):
			_log.error('LFStrikeGuard: a NaN window_seconds is rejected; keeping %s' % _window_seconds)
			return
		_window_seconds = value
## Seconds a key stays blocked. Changing it affects only blocks that start afterwards. A NaN
## is rejected like `window_seconds`.
var block_seconds: float:
	get:
		return _block_seconds
	set(value):
		if is_nan(value):
			_log.error('LFStrikeGuard: a NaN block_seconds is rejected; keeping %s' % _block_seconds)
			return
		_block_seconds = value
## Returns "now" in seconds on a steady clock (one that never jumps back). Defaults to
## `steady_seconds()`. Replace it to run the guard on a simulated or test clock.
var clock_seconds: Callable

## key -> Array of strike times, oldest first.
var _strikes: Dictionary = {}
var _window_seconds := 0.0
var _block_seconds := 0.0
## key -> time until which it is blocked.
var _blocked_until: Dictionary = {}
var _clock_error_reported := false


## Creates a guard: `strikes_to_block` strikes within `strike_window_seconds` seconds
## block a key for `block_duration_seconds` seconds. Without `initial_clock_seconds`, it runs on
## `steady_seconds()`. A pushed error says so when `block_duration_seconds` is not above
## zero (a block that ends at once, though `strike` still returns true), or when
## `strike_window_seconds` is not above zero while `strikes_to_block` is above 1 (strikes
## never add up, so nothing is ever blocked). A NaN duration or window is rejected with
## its own error and the property stays 0.
func _init(strikes_to_block: int, strike_window_seconds: float, block_duration_seconds: float, initial_clock_seconds := Callable()) -> void:
	if not is_nan(block_duration_seconds) and not block_duration_seconds > 0.0:
		push_error('LFStrikeGuard: block_duration_seconds %s blocks nothing' % block_duration_seconds)
	if strikes_to_block > 1 and not is_nan(strike_window_seconds) and not strike_window_seconds > 0.0:
		push_error('LFStrikeGuard: strike_window_seconds %s lets no strikes add up' % strike_window_seconds)
	max_strikes = strikes_to_block
	window_seconds = strike_window_seconds
	block_seconds = block_duration_seconds
	clock_seconds = initial_clock_seconds if not initial_clock_seconds.is_null() else LFStrikeGuard.steady_seconds


## Returns seconds since the engine started: the default clock. It ignores pausing and
## `Engine.time_scale`.
static func steady_seconds() -> float:
	return Time.get_ticks_msec() / _MS_PER_SECOND


## Returns the key to strike an `address` under: an IPv4 address in dotted decimal
## without leading zeros (Godot accepts `01.2.3.4` and reads each part as decimal, so it
## is keyed as `1.2.3.4`); an IPv6
## address as its /64 network (a home or server connection usually gets a whole /64, so a
## single user can switch to millions of addresses inside it), written as its first four
## groups in lower-case hex without leading zeros, none folded into `::`, then `::/64`:
## `2001:db8:0:1::/64` for `2001:db8:0:1:2:3:4:5`, `fe80:0:0:0::/64` for `fe80::1`. An IPv4
## address written as IPv6 ("IPv4-mapped": `::ffff:1.2.3.4`, `::ffff:102:304` or fully
## expanded) is keyed as the dotted IPv4 address, `1.2.3.4`. Square brackets and a zone
## (`%eth0`) are dropped. Anything that is not an IP address is returned unchanged.
static func address_key(address: String) -> String:
	var bare := address.strip_edges().trim_prefix('[').trim_suffix(']').get_slice('%', 0)
	if not bare.is_valid_ip_address():
		return address
	if not bare.contains(':'):
		var octets := bare.split('.')
		return _IPV4_FORMAT % [octets[0].to_int(), octets[1].to_int(), octets[2].to_int(), octets[3].to_int()]
	var hextets := _ipv6_hextets(bare.to_lower())
	# Engine guard: no address Godot 4.7 accepts parses to other than eight groups here,
	# but this parser is simpler than the engine's, so a mismatch is returned unchanged.
	if hextets.size() != _IPV6_HEXTETS:
		return address
	if _is_ipv4_mapped(hextets):
		return _IPV4_FORMAT % [hextets[6] >> 8, hextets[6] & 0xff, hextets[7] >> 8, hextets[7] & 0xff]
	var prefix := PackedStringArray()
	for i in _IPV6_PREFIX_HEXTETS:
		prefix.append('%x' % hextets[i])
	return ':'.join(prefix) + _IPV6_PREFIX_SUFFIX


## Whether the eight groups are `0:0:0:0:0:ffff:x:y`, an IPv4 address in IPv6 form.
static func _is_ipv4_mapped(hextets: PackedInt32Array) -> bool:
	for i in _IPV4_MAPPED_MARK_INDEX:
		if hextets[i] != 0:
			return false
	return hextets[_IPV4_MAPPED_MARK_INDEX] == _IPV4_MAPPED_MARK


## The eight 16-bit groups of a valid IPv6 address (with `::` expanded and a trailing
## dotted IPv4 part counted as two groups), or fewer when it can't be expanded.
static func _ipv6_hextets(address: String) -> PackedInt32Array:
	var halves := address.split('::')
	var head := _hextet_list(halves[0])
	var tail := _hextet_list(halves[1]) if halves.size() > 1 else PackedInt32Array()
	if halves.size() == 1:
		return head
	var groups := head.duplicate()
	for i in _IPV6_HEXTETS - head.size() - tail.size():
		groups.append(0)
	groups.append_array(tail)
	return groups


## The groups of one side of a `::` (colon-separated hex, the last one possibly a dotted
## IPv4 address worth two groups).
static func _hextet_list(part: String) -> PackedInt32Array:
	var groups := PackedInt32Array()
	for group in part.split(':', false):
		if group.contains('.'):
			var octets := group.split('.')
			groups.append(octets[0].to_int() << 8 | octets[1].to_int())
			groups.append(octets[2].to_int() << 8 | octets[3].to_int())
		else:
			groups.append(group.hex_to_int())
	return groups


## Returns `true` while `key` is blocked (always, when the clock can no longer be called). A block that has run out is
## forgotten here, so the key starts over with no strikes. An unknown key is not blocked.
func is_blocked(key: Variant) -> bool:
	var now: Variant = _now()
	if now == null:
		return true
	if not _blocked_until.has(key):
		return false
	if now < _blocked_until[key]:
		return true
	_blocked_until.erase(key)
	return false


## Records one failed attempt against `key`. Returns `true` when this
## strike blocks the key (always, when the clock can no longer be called; nothing is recorded). Blocking forgets the key's strikes, so after the block it starts
## over. Strikes keep counting while a key is blocked; reaching the limit again restarts
## its block from now.
func strike(key: Variant) -> bool:
	var now: Variant = _now()
	if now == null:
		return true
	var time: float = now
	var recent: Array = _recent(_strikes.get(key, []), time)
	recent.append(time)
	if recent.size() >= max_strikes:
		_strikes.erase(key)
		_blocked_until[key] = time + block_seconds
		return true
	_strikes[key] = recent
	return false


## Forgets every strike against `key` and lifts its block (an admin unblock). An
## unknown key is ignored.
func forget(key: Variant) -> void:
	_strikes.erase(key)
	_blocked_until.erase(key)


## Forgets every strike and lifts every block, for all keys.
func clear() -> void:
	_strikes.clear()
	_blocked_until.clear()


## Forgets every key whose strikes are all older than the window and every block that has
## run out, so the guard holds only keys that are still guessing or blocked.
func prune() -> void:
	var now: Variant = _now()
	if now == null:
		return
	var time: float = now
	for key: Variant in _strikes.keys():
		var recent := _recent(_strikes[key], time)
		if recent.is_empty():
			_strikes.erase(key)
		else:
			_strikes[key] = recent
	for key: Variant in _blocked_until.keys():
		if time >= _blocked_until[key]:
			_blocked_until.erase(key)


## Returns how many keys the guard holds in memory (with strikes or blocked), including
## strikes that aged out but were not pruned yet.
func tracked_count() -> int:
	var keys := _strikes.duplicate()
	keys.merge(_blocked_until)
	return keys.size()


func _recent(times: Array, now: float) -> Array:
	return times.filter(func(at: Variant) -> bool: return now - at < window_seconds)


## The current time in seconds, or null when `clock_seconds` can no longer be called.
func _now() -> Variant:
	if !clock_seconds.is_valid():
		if !_clock_error_reported:
			_clock_error_reported = true
			_log.error("LFStrikeGuard: its clock can no longer be called; every key stays blocked")
		return null
	return float(clock_seconds.call())
