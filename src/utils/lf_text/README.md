# LFText

> Small text helpers for games: timer text like `1:05`, "2 rounds", escaping `[` so BBCode shows it literally, and decoding broken UTF-8 bytes without engine errors.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_text.gd` |
| **Tests** | `tests/test_lf_text.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it for the little bits of text every game shows: a countdown timer (`LFText.clock(65)` is
`"1:05"`), a counter with the right noun (`LFText.plural(1, "life")` is `"1 life"`), or a
player's name inside a `RichTextLabel` that must not turn `[b]` into bold
(`bbcode_escape`). The UTF-8 helpers are for bytes that come from outside (a network
socket, a child process, a file): Godot's own decoder prints an engine error on broken
bytes, while `decode_utf8_lossy` quietly shows a replacement character instead. For general
string work, Godot's `String` methods are enough.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **Other Node**, search for **Label**, and press *Create*.
2. Right-click the `Label`, choose **Attach Script**, and press *Create*.
3. Select everything in the script and replace it with:

```gdscript
extends Label

var time_left := 65.0  # seconds


func _ready() -> void:
	print(LFText.plural(1, "coin"))  # 1 coin
	print(LFText.plural(5, "coin"))  # 5 coins


# Godot calls this every frame. delta is the seconds since the last frame.
func _process(delta: float) -> void:
	time_left -= delta
	text = "%s left" % LFText.clock(time_left)
```

4. Press **F6** (*Run Current Scene*) and save the scene when asked.
5. The **Output** panel shows `1 coin` and `5 coins`, and the top-left of the game window shows `1:05 left` counting down to `0:00 left`.
6. Change `65.0` (seconds) for your own timer. For a noun with an odd plural, pass it as a third argument: `LFText.plural(2, "mouse", "mice")`.

## API

Everything the class offers; you only need the rows used above to get started.

### Methods

| Member | Signature | Description |
|---|---|---|
| `decode_utf8_lossy` | `static decode_utf8_lossy(bytes: PackedByteArray) -> String` | UTF-8 to String; every malformed byte (stray continuation, truncated or overlong sequence, surrogate, past U+10FFFF) becomes U+FFFD. Never logs. Stops at the first zero byte, as Godot's decoder does. |
| `utf8_safe_cut` | `static utf8_safe_cut(bytes: PackedByteArray, limit: int) -> int` | The largest cut ≤ `limit` that doesn't split a character. `bytes.size()` when `limit` reaches past the end; `limit` itself when no boundary lies in `1..limit`. |
| `clock` | `static clock(seconds: float, round_up: bool = true) -> String` | `m:ss`, or `h:mm:ss` from one hour. Rounds a fraction up unless `round_up` is false. Never negative: below zero (`-INF` too) is `0:00`. `INF`, NaN and seconds at or past 2^63 give `CLOCK_NO_TIME`. |
| `CLOCK_NO_TIME` | `const String = '--:--'` | What `clock` shows for a time it can't show: `INF` (no limit), NaN, or seconds at or past 2^63. |
| `plural` | `static plural(count: int, singular: String, plural_form: String = '') -> String` | `"1 round"`, `"2 rounds"`; `plural_form` replaces `singular + "s"`. Only exactly 1 is singular. |
| `bbcode_escape` | `static bbcode_escape(text: String) -> String` | Every `[` becomes `[lb]`, so the text renders literally in a BBCode `RichTextLabel`. |

## Usage

```gdscript
extends Control

var time_left := 65.0
var rounds := 2


func _ready() -> void:
	print(LFText.clock(time_left))               # 1:05
	print(LFText.clock(3600))                    # 1:00:00
	print(LFText.clock(59.5, false))             # 0:59 (round down, for elapsed time)
	print("%s left" % LFText.plural(rounds, "round"))      # 2 rounds left
	print(LFText.plural(3, "enemy", "enemies"))  # 3 enemies

	# A player-chosen name shown literally inside BBCode.
	var chat := RichTextLabel.new()
	chat.bbcode_enabled = true
	add_child(chat)
	var player_name := "[b]Bob"
	chat.append_text("[i]%s[/i] joined\n" % LFText.bbcode_escape(player_name))

	# Bytes from outside: broken UTF-8 never logs an engine error.
	var bytes := PackedByteArray([0x48, 0x69, 0xFF])
	print(LFText.decode_utf8_lossy(bytes))       # "Hi" plus a replacement character

	# Send a long text in chunks of at most 4 bytes without splitting a character.
	var buffer := "héllo wörld".to_utf8_buffer()
	while not buffer.is_empty():
		var cut := LFText.utf8_safe_cut(buffer, 4)
		print(LFText.decode_utf8_lossy(buffer.slice(0, cut)))
		buffer = buffer.slice(cut)
```

## Notes

- `PackedByteArray.get_string_from_utf8()` logs an engine error on malformed bytes; use `decode_utf8_lossy` for bytes you don't control (sockets, child processes, archives). Well-formed input goes through the engine decoder unchanged.
- Decoding stops at the first zero byte (`0x00`): everything after it is dropped, as with
  Godot's own decoder. Split NUL-separated data before decoding it.
- `clock` rounds up so a countdown shows `0:00` only once time is really up (`59.5` shows `1:00`). Use `round_up = false` for elapsed time.
- `plural` is English-only (`singular + "s"` by default); pass `plural_form` for irregular nouns.
- `bbcode_escape` only escapes `[`; that is enough, because no tag can open without it.
