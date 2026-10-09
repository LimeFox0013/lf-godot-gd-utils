## Makes random ids (UUIDs) and random secret tokens.
##
## Every method is static: call it on the class, never create an instance. A UUID is a
## standard 36-character random id (RFC 4122 version 4: lowercase `8-4-4-4-12` hex,
## optionally prefixed) with 122 random bits, so a repeat is vanishingly unlikely but
## nothing checks for one. A token is random hex for secrets. Both come from
## `Crypto.generate_random_bytes`, Godot's cryptographically secure generator. Works
## without a SceneTree.
class_name LFUuid

## The default `bytes` of `token`: 16 bytes, 32 hex characters.
const DEFAULT_TOKEN_BYTES := 16

## Random bytes in a UUID.
const _UUID_BYTES := 16
## The byte holding the version in its high nibble.
const _VERSION_BYTE := 6
## Keeps the low nibble of the version byte.
const _VERSION_KEEP_MASK := 0x0F
## The version nibble: 4 (random).
const _VERSION_BITS := 0x40
## The byte holding the variant in its two high bits.
const _VARIANT_BYTE := 8
## Keeps the low six bits of the variant byte.
const _VARIANT_KEEP_MASK := 0x3F
## The RFC 4122 variant bits: `10xx`.
const _VARIANT_BITS := 0x80
## Bytes in each dash-separated group (`8-4-4-4-12` hex characters).
const _GROUP_BYTES := [4, 2, 2, 2, 6]
## One byte as two lowercase hex digits.
const _HEX_BYTE_FORMAT := '%02x'
## Between the groups, and between the prefix and the UUID.
const _SEPARATOR := '-'


## A random UUID v4, as `<prefix>-xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` when `prefix` is
## not empty. Bytes come from `Crypto.generate_random_bytes`, not the clock, so calls in
## the same instant (or from several threads) are as unlikely to repeat as any others.
static func gen(prefix: String = '') -> String:
	var bytes := Crypto.new().generate_random_bytes(_UUID_BYTES)
	bytes[_VERSION_BYTE] = (bytes[_VERSION_BYTE] & _VERSION_KEEP_MASK) | _VERSION_BITS
	bytes[_VARIANT_BYTE] = (bytes[_VARIANT_BYTE] & _VARIANT_KEEP_MASK) | _VARIANT_BITS

	var parts: Array[String] = []
	var idx := 0
	for p: Variant in _GROUP_BYTES:
		var seg := ''
		for _j in range(p):
			seg += _HEX_BYTE_FORMAT % bytes[idx]
			idx += 1
		parts.append(seg)

	var uuid := _SEPARATOR.join(parts)
	return (prefix + _SEPARATOR + uuid) if prefix != '' else uuid


## A secret random token: `bytes` bytes from Godot's cryptographic generator
## (`Crypto.generate_random_bytes`) as lowercase hex, so twice `bytes` characters long.
## For session tokens, invite codes, salts and ids that must be hard to guess; how hard
## depends on `bytes` (8 random bits each). Returns '' when `bytes` is 0 or less. There is no upper limit: the string is built in memory, so a `bytes` in the hundreds of millions costs hundreds of megabytes.
static func token(bytes: int = DEFAULT_TOKEN_BYTES) -> String:
	if bytes <= 0:
		return ''
	return Crypto.new().generate_random_bytes(bytes).hex_encode()
