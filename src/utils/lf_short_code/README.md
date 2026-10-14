# LFShortCode

> Makes short readable codes from an alphabet you choose, and checks codes players type.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_short_code.gd` |
| **Tests** | `tests/test_lf_short_code.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it for a code a person reads out or types: a room code, a lobby code, a coupon. You pass
the alphabet, so you can leave out letters that read alike (O and 0, I and 1). The codes are
not secrets and are drawn from the generator you give it, so a seeded generator repeats them.
For a secret use `LFUuid.token`.

## Step by step

1. Make a scene with one **Node** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

```gdscript
extends Node

const LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code := LFShortCode.gen(5, LETTERS, rng)
	print(code)
	print(LFShortCode.is_valid(" " + code.to_lower() + " ", 5, LETTERS))
```

3. Press **F6**. The Output panel shows a 5-character code (different each run), then `true`.

## API

| Member | Signature | Description |
|---|---|---|
| `MAX_ATTEMPTS` | `const := 1000` | How many codes `gen` draws before giving up on finding a free one. |
| `gen` | `static gen(length: int, alphabet: String, rng: RandomNumberGenerator, taken := Callable()) -> String` | A code drawn with one `rng.randi_range` per character. `taken.call(code) -> bool` redraws when true. `''` for a `length` of 0 or less, an empty alphabet, or when every draw was taken. |
| `normalize` | `static normalize(text: String) -> String` | `text` with surrounding whitespace removed, in upper case. |
| `is_valid` | `static is_valid(text: String, length: int, alphabet: String) -> bool` | Whether the normalized `text` is exactly `length` characters, all in `alphabet`. |

## Usage

```gdscript
# Open rooms are kept in a Dictionary keyed by code.
var code := LFShortCode.gen(5, LETTERS, _rng, func(c: String) -> bool: return _rooms.has(c))
```

## Notes

- Use an upper-case alphabet: `is_valid` and `normalize` compare upper-cased text.
- A near-full code space can make `gen` give up and return `''`; check for it.
