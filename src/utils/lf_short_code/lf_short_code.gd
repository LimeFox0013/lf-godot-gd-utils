## Makes short human-readable codes (a room code, an invite code) and checks typed ones.
##
## You give it the alphabet, so a code can leave out letters that read alike (O and 0).
## Every method is static. `gen` draws one character per `randi_range` call on the
## generator you pass, so a seeded generator makes the same codes every time. These codes
## are not secrets: use `LFUuid.token` for those.
class_name LFShortCode

## The most codes `gen` draws before giving up on finding a free one.
const MAX_ATTEMPTS := 1000


## A code of `length` characters from `alphabet`, drawn from `rng`, that `taken` does not
## claim (`taken.call(code) -> bool`; leave it empty to accept the first). Returns `''` for
## a `length` of 0 or less, an empty `alphabet`, or when `MAX_ATTEMPTS` draws were all taken.
static func gen(length: int, alphabet: String, rng: RandomNumberGenerator, taken := Callable()) -> String:
	if length <= 0 or alphabet.is_empty():
		return ''
	for attempt in MAX_ATTEMPTS:
		var code := ''
		for i in length:
			code += alphabet[rng.randi_range(0, alphabet.length() - 1)]
		if not taken.is_valid() or not taken.call(code):
			return code
	return ''


## `text` as a code is typed: surrounding whitespace removed, upper case.
static func normalize(text: String) -> String:
	return text.strip_edges().to_upper()


## Whether `text`, normalized, is exactly `length` characters that are all in `alphabet`.
static func is_valid(text: String, length: int, alphabet: String) -> bool:
	var clean := normalize(text)
	if clean.length() != length:
		return false
	for letter in clean:
		if not alphabet.contains(letter):
			return false
	return true
