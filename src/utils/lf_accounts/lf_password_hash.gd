## Turns a password into a salted, deliberately slow hash, and checks a password against
## one with a comparison that does not stop at the first difference.
##
## Store the hash, never the password. A salt is a random string per account mixed into
## the hash so equal passwords hash differently; "rounds" repeats the work so guessing is
## slow. The hash is HMAC-SHA256 iterated `rounds` times (keyed by the salt's UTF-8 bytes,
## starting from the password's UTF-8 bytes, each round's digest the next round's message),
## returned as lowercase hex. It is not PBKDF2, though each round costs about one
## PBKDF2-HMAC-SHA256 iteration. Keep salts random (`LFUuid.token()`) and store the rounds
## with each hash so they can be raised later. Cracking cost grows with the rounds, but
## 20000 (about 25 ms in GDScript on an Apple M2 Max) is far below OWASP's 600,000 PBKDF2
## iterations: weak passwords in a stolen file can be cracked. All functions are static;
## never create an instance.
class_name LFPasswordHash
extends RefCounted

## SHA-256 block size in bytes; the HMAC key is padded to it.
const _BLOCK_SIZE := 64
## HMAC inner-pad byte (RFC 2104).
const _IPAD := 0x36
## HMAC outer-pad byte (RFC 2104).
const _OPAD := 0x5c

static var _crypto := Crypto.new()


## Returns the 64-character hex hash of `password` with `salt` over `rounds` rounds (at least one,
## so a password is never stored as is). An empty password or salt is hashed too.
static func compute(password: String, salt: String, rounds: int) -> String:
	var key := salt.to_utf8_buffer()
	var digest := password.to_utf8_buffer()
	for i in maxi(rounds, 1):
		digest = _hmac_sha256(key, digest)
	return digest.hex_encode()


## Returns `true` when `password` hashes to `expected_hex` with this salt and rounds. The
## comparison (see `equals_full_scan`) does not stop at the first difference.
static func verify(password: String, salt: String, rounds: int, expected_hex: String) -> bool:
	return equals_full_scan(compute(password, salt, rounds), expected_hex)


## Returns `true` when `a` and `b` are equal, comparing every byte of the longer one
## whatever the first difference, so the work does not depend on where they differ. The
## length still shows in the time, and GDScript gives no hard timing guarantee.
static func equals_full_scan(a: String, b: String) -> bool:
	var x := a.to_utf8_buffer()
	var y := b.to_utf8_buffer()
	var difference := x.size() ^ y.size()
	for i in maxi(x.size(), y.size()):
		var p := x[i] if i < x.size() else 0
		var q := y[i] if i < y.size() else 0
		difference |= p ^ q
	return difference == 0


## The engine's HMAC refuses an empty key or message; those are computed by hand, which
## gives the same bytes RFC 2104 defines.
static func _hmac_sha256(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	if not key.is_empty() and not message.is_empty():
		return _crypto.hmac_digest(HashingContext.HASH_SHA256, key, message)
	if key.size() > _BLOCK_SIZE:
		key = _sha256(key)
	key.resize(_BLOCK_SIZE)
	var inner := PackedByteArray()
	var outer := PackedByteArray()
	for byte in key:
		inner.append(byte ^ _IPAD)
		outer.append(byte ^ _OPAD)
	return _sha256(outer + _sha256(inner + message))


static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		context.update(bytes)
	return context.finish()
