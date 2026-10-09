# LFUuid

> Makes random ids (UUID v4) and random secret tokens from Godot's cryptographic random generator.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_uuid.gd` |
| **Tests** | `tests/test_lf_uuid.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use `gen()` when something needs an id that should not repeat across runs, players and
machines: a save slot, an item a player crafted, a match on a server. Each id carries 122
random bits, so a repeat is possible in theory but vanishingly unlikely (under a 1 in
10^18 chance among a billion ids), and ids can be created anywhere without asking a
central counter. Nothing checks for duplicates, so if a repeat would corrupt data, check
on insert. Use `token()` for secrets that must be hard to guess, such as a session
token or an invite code: the default 16 bytes is 128 random bits, and each byte fewer makes a token
256 times easier to guess. If you only need short, readable ids inside one running game
(`unit-1`, `unit-2`), use `LFObjectIdRegistry`; for reproducible random numbers, use
`LFRandom`.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **Other Node**, pick **Node**, and press *Create*.
2. Right-click the new node, choose **Attach Script**, and press *Create* (the default name is fine). The script editor opens.
3. Select everything in the script and replace it with:

```gdscript
extends Node

func _ready() -> void:
	print(LFUuid.gen())          # a random id, e.g. 550e8400-e29b-41d4-a716-446655440000
	print(LFUuid.gen("save"))    # the same, starting with "save-"
	print(LFUuid.token(8))       # a secret: 8 random bytes written as 16 characters
```

4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: pick any name.
5. The **Output** panel shows three lines. They are different every time you run it, so yours will not match the example above: the first is 36 characters long, the second starts with `save-`, the third is 16 characters.
6. Use `gen()` for ids that should not repeat (a save slot, a crafted item). Use `token()` for secrets that must be hard to guess; each byte adds 8 random bits, so keep the default 16 bytes or more for anything an attacker could try to guess offline (`token(32)` is 64 characters).

## API

Everything the class offers; you only need the rows used above to get started.

### Methods

| Member | Signature | Description |
|---|---|---|
| `gen` | `static gen(prefix: String = '') -> String` | 16 random bytes from `Crypto.generate_random_bytes` with the version (`4`) and variant (`10xx`) bits set (122 random bits), formatted as lowercase `8-4-4-4-12` hex. A non-empty `prefix` is prepended as `prefix + '-'`. |
| `DEFAULT_TOKEN_BYTES` | `const DEFAULT_TOKEN_BYTES := 16` | The default `token` length, in bytes (32 hex characters). |
| `token` | `static token(bytes: int = DEFAULT_TOKEN_BYTES) -> String` (16) | `bytes` bytes from `Crypto.generate_random_bytes` as lowercase hex (`2 * bytes` characters), for session tokens, invite codes, salts and ids that must be hard to guess. `''` when `bytes <= 0`. No upper limit: the string is built in memory, so a `bytes` in the hundreds of millions costs hundreds of megabytes. |

## Usage

```gdscript
extends Node

func _ready() -> void:
	print(make_save("Slot A"))
	print(make_invite_code())


# A save record with its own unique id.
func make_save(slot_name: String) -> Dictionary:
	return {
		"id": LFUuid.gen("save"),
		"name": slot_name,
		"created": Time.get_unix_time_from_system(),
	}


# A short invite code players can type: 4 random bytes as 8 upper-case characters.
# 4 bytes is only about 4 billion codes, so the server must limit how many a player may try.
func make_invite_code() -> String:
	return LFUuid.token(4).to_upper()
```

## Notes

- Bytes come from `Crypto.new().generate_random_bytes()`, which Godot documents as cryptographically secure, not from the clock: calls in the same instant are as independent as any others, and the tests generate 2,000 ids in a tight loop and 1,200 from four threads at once without a repeat. A seed cannot replay them; for replayable randomness use `LFRandom`.
- `token()` has no version bits, so all its bytes are random; prefer it over `gen()` for secrets.
- Needs only the `Crypto` class, so it works without a SceneTree.
