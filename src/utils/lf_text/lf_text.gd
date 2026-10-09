## Small text helpers: timer text like `1:05`, "2 items", BBCode escaping, and UTF-8 decoding without engine errors.
##
## Every method is static: call it on the class, never create an instance. It formats
## countdown clocks (`m:ss`, `h:mm:ss`) and counted plurals ("2 items"), escapes text for
## a BBCode `RichTextLabel`, decodes untrusted bytes as UTF-8 without engine errors (bad
## bytes become U+FFFD, the "replacement character", which most fonts draw as a question
## mark in a diamond),
## and cuts a byte buffer without splitting a character.
class_name LFText
extends RefCounted

## U+FFFD, the replacement character, encoded as UTF-8 bytes.
const _REPLACEMENT := [0xEF, 0xBF, 0xBD]

## Bytes below this are ASCII: a whole one-byte character.
const _ASCII_END := 0x80
## The bits that mark a continuation byte (`10xxxxxx`): `byte & _CONTINUATION_MASK`.
const _CONTINUATION_MASK := 0xC0
## `byte & _CONTINUATION_MASK` equals this for a continuation byte.
const _CONTINUATION_TAG := 0x80
## The smallest continuation byte.
const _CONTINUATION_LOW := 0x80
## The largest continuation byte.
const _CONTINUATION_HIGH := 0xBF
## The smallest lead byte of a two-byte sequence (0xC0 and 0xC1 would be overlong).
const _LEAD2_LOW := 0xC2
## The largest lead byte of a two-byte sequence.
const _LEAD2_HIGH := 0xDF
## The smallest lead byte of a three-byte sequence.
const _LEAD3_LOW := 0xE0
## The largest lead byte of a three-byte sequence.
const _LEAD3_HIGH := 0xEF
## The smallest lead byte of a four-byte sequence.
const _LEAD4_LOW := 0xF0
## The largest lead byte of a four-byte sequence (past it lies beyond U+10FFFF).
const _LEAD4_HIGH := 0xF4
## Bytes in a two-byte sequence.
const _LENGTH2 := 2
## Bytes in a three-byte sequence.
const _LENGTH3 := 3
## Bytes in a four-byte sequence.
const _LENGTH4 := 4
## After lead 0xE0, the second byte starts here (lower would be overlong).
const _AFTER_E0_LOW := 0xA0
## The lead byte whose sequences reach the surrogates (U+D800..U+DFFF).
const _SURROGATE_LEAD := 0xED
## After lead 0xED, the second byte ends here (higher would be a surrogate).
const _AFTER_ED_HIGH := 0x9F
## After lead 0xF0, the second byte starts here (lower would be overlong).
const _AFTER_F0_LOW := 0x90
## After lead 0xF4, the second byte ends here (higher is past U+10FFFF).
const _AFTER_F4_HIGH := 0x8F

## Seconds in an hour.
const _SECONDS_PER_HOUR := 3600
## Seconds in a minute.
const _SECONDS_PER_MINUTE := 60
## Minutes in an hour.
const _MINUTES_PER_HOUR := 60
## What `clock` returns for a time it can't show: INF (no limit), NaN, or seconds at or
## past 2^63 (the int range).
const CLOCK_NO_TIME := '--:--'
## Seconds from which `clock` shows `CLOCK_NO_TIME`: 2^63, where an int overflows.
const _CLOCK_LIMIT_SECONDS := 9223372036854775808.0
## The `clock` shape from one hour: `h:mm:ss`.
const _CLOCK_HOURS_FORMAT := '%d:%02d:%02d'
## The `clock` shape below one hour: `m:ss`.
const _CLOCK_MINUTES_FORMAT := '%d:%02d'
## The `plural` shape: the count, a space, the noun.
const _PLURAL_FORMAT := '%d %s'
## Added to the singular when no plural form is given.
const _PLURAL_SUFFIX := 's'
## The BBCode character `bbcode_escape` neutralises: it opens a tag.
const _BBCODE_OPEN := '['
## What replaces `_BBCODE_OPEN`: the BBCode tag that prints a literal `[`.
const _BBCODE_OPEN_ESCAPED := '[lb]'


## `bytes` decoded as UTF-8. Every malformed byte (a stray continuation byte, a truncated
## or overlong sequence, a surrogate, anything past U+10FFFF) becomes U+FFFD, and the
## engine logs no error — unlike `PackedByteArray.get_string_from_utf8()`. Like that
## decoder, it stops at the first zero byte: the bytes after a NUL are dropped.
static func decode_utf8_lossy(bytes: PackedByteArray) -> String:
	var i := 0
	while i < bytes.size():
		var length := 1 if bytes[i] < _ASCII_END else _utf8_sequence_length(bytes, i)
		if length == 0:
			return _decode_replacing(bytes)
		i += length
	return bytes.get_string_from_utf8()


## The largest cut at or below `limit` that does not split a UTF-8 sequence, so
## `bytes.slice(0, cut)` ends on a whole character. `bytes.size()` when `limit` reaches
## past the end; `limit` itself when no character boundary lies in `1..limit` (so a caller
## cutting in a loop always makes progress). A negative `limit` counts as 0.
static func utf8_safe_cut(bytes: PackedByteArray, limit: int) -> int:
	if limit >= bytes.size():
		return bytes.size()
	limit = maxi(limit, 0)
	var cut := limit
	while cut > 0 and (bytes[cut] & _CONTINUATION_MASK) == _CONTINUATION_TAG:
		cut -= 1
	return cut if cut > 0 else limit


## A countdown clock: `m:ss` under an hour, `h:mm:ss` from one hour. Fractions round up
## by default (59.5 s shows `1:00`, so the display reaches `0:00` only when time is up);
## pass `round_up = false` to round down. Never negative: anything below zero (`-INF`
## too) is `0:00`. INF, NaN and seconds at or past 2^63 show `CLOCK_NO_TIME` (`--:--`).
static func clock(seconds: float, round_up: bool = true) -> String:
	if is_nan(seconds) or seconds >= _CLOCK_LIMIT_SECONDS:
		return CLOCK_NO_TIME
	var whole := maxi(int(ceil(seconds)) if round_up else int(floor(seconds)), 0)
	@warning_ignore("integer_division")
	var hours := whole / _SECONDS_PER_HOUR
	@warning_ignore("integer_division")
	var minutes := (whole / _SECONDS_PER_MINUTE) % _MINUTES_PER_HOUR
	var secs := whole % _SECONDS_PER_MINUTE
	if hours > 0:
		return _CLOCK_HOURS_FORMAT % [hours, minutes, secs]
	return _CLOCK_MINUTES_FORMAT % [minutes, secs]


## `count` with its noun: `plural(1, 'item')` is `"1 item"`, `plural(2, 'item')` is
## `"2 items"`. `plural_form` replaces the default `singular + "s"`
## (`plural(3, 'box', 'boxes')`). Only exactly 1 takes the singular (0 is "0 items").
static func plural(count: int, singular: String, plural_form: String = '') -> String:
	var noun := singular if count == 1 else (plural_form if plural_form != '' else singular + _PLURAL_SUFFIX)
	return _PLURAL_FORMAT % [count, noun]


## `text` safe to put inside a RichTextLabel's BBCode: every `[` becomes `[lb]`, so user
## text can never open a tag.
static func bbcode_escape(text: String) -> String:
	return text.replace(_BBCODE_OPEN, _BBCODE_OPEN_ESCAPED)


## Length of the well-formed UTF-8 sequence starting at `i`, or 0 when it is malformed.
static func _utf8_sequence_length(bytes: PackedByteArray, i: int) -> int:
	var b := bytes[i]
	var length := 0
	var low := _CONTINUATION_LOW
	var high := _CONTINUATION_HIGH
	if b >= _LEAD2_LOW and b <= _LEAD2_HIGH:
		length = _LENGTH2
	elif b >= _LEAD3_LOW and b <= _LEAD3_HIGH:
		length = _LENGTH3
		if b == _LEAD3_LOW:
			low = _AFTER_E0_LOW
		elif b == _SURROGATE_LEAD:
			high = _AFTER_ED_HIGH
	elif b >= _LEAD4_LOW and b <= _LEAD4_HIGH:
		length = _LENGTH4
		if b == _LEAD4_LOW:
			low = _AFTER_F0_LOW
		elif b == _LEAD4_HIGH:
			high = _AFTER_F4_HIGH
	else:
		return 0
	if i + length > bytes.size():
		return 0
	for k in range(1, length):
		var c := bytes[i + k]
		var lo := low if k == 1 else _CONTINUATION_LOW
		var hi := high if k == 1 else _CONTINUATION_HIGH
		if c < lo or c > hi:
			return 0
	return length


## `bytes` with every malformed byte replaced by U+FFFD, then decoded.
static func _decode_replacing(bytes: PackedByteArray) -> String:
	var clean := PackedByteArray()
	var i := 0
	while i < bytes.size():
		var length := 1 if bytes[i] < _ASCII_END else _utf8_sequence_length(bytes, i)
		if length == 0:
			clean.append_array(_REPLACEMENT)
			i += 1
		else:
			clean.append_array(bytes.slice(i, i + length))
			i += length
	return clean.get_string_from_utf8()
