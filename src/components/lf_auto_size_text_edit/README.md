# LFAutoSizeTextEdit

> A multi-line text field that grows as you type, between a smallest and a largest size.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene (it is a TextEdit) |
| **Files** | `lf_auto_size_text_edit.gd` |
| **Tests** | `tests/test_lf_auto_size_text_edit.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it for a message box or a note field that should start small and open up as the player
types, like a chat input: it gets wider with the longest line until a limit, then wraps, gets
taller with the wrapped text until a second limit, then scrolls. A plain `TextEdit` keeps
the size you gave it. Godot's `scroll_fit_content_height` makes a `TextEdit` follow its text
in height, but it has no maximum and does not change the width. For a one-line field use
`LineEdit`; for a chat log with a field and a Send button, `LFChatBox`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*, pick **User Interface** (a `Control` root).
2. Click *+ Add Child Node*, search "LFAutoSizeTextEdit" and press *Create*.
3. Select it. In the *Inspector* find *Min Size* and *Max Size* (for example `200, 60` and `500, 240`) and *Extra Width Padding*.
4. Press **F6**, save the scene when asked, and type. The field widens with a long line up to 500 pixels, then wraps, grows taller, and past 240 pixels of height shows a scroll bar.

The field sets its minimum size, so Godot never lays it out smaller than that. In a container (a `VBoxContainer`, a `PanelContainer`) the container grows with it.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `min_size` | `@export var min_size := Vector2(120, 40)` | The smallest size; an empty field has exactly this (or one text line plus the style's margins, if that is larger). |
| `max_size` | `@export var max_size := Vector2(800, 400)` | The largest size. Past it the text wraps (width) and scrolls (height). Below `min_size` counts as `min_size`. |
| `extra_width_padding` | `@export var extra_width_padding := 4.0` | Pixels added to the longest line's width. |
| `refit` | `refit() -> Vector2` | Measures now, sets `custom_minimum_size` and returns it. Outside the scene tree it changes nothing and returns `custom_minimum_size`. |
| `fitted_size` | `static fitted_size(content, font, font_size, margins, smallest, largest, extra_width := 4.0) -> Vector2` | The size for a text, without a scene. `margins` is the space the background style leaves around the text. |
| `DEFAULT_MIN_SIZE`, `DEFAULT_MAX_SIZE`, `DEFAULT_EXTRA_WIDTH_PADDING` | constants | The defaults above. |

The field sets `wrap_mode` to `LINE_WRAPPING_BOUNDARY` when created (change it in the *Inspector* if you want another). It measures again, once at the end of the frame, when the text (typed or set from code), the theme, the visibility or `min_size` / `max_size` / `extra_width_padding` change.

## Usage

```gdscript
# A chat input that opens up while typing and empties when sent.
extends VBoxContainer

@onready var input: LFAutoSizeTextEdit = $LFAutoSizeTextEdit


func _ready() -> void:
	input.min_size = Vector2(300, 48)
	input.max_size = Vector2(600, 200)
	input.placeholder_text = "Say something"


func send() -> void:
	print("sent: ", input.text)
	input.text = ""   # its minimum size drops back to min_size at the end of the frame
```

## Notes

- The size is `custom_minimum_size`, a minimum: a container that is given more room can still stretch the field. Use `size_flags` such as *Shrink Begin* to keep it at the measured size.
- The width counts the longest line as written (lines split at line breaks). The height is measured by wrapping the whole text with a `TextParagraph`, breaking at words and, for a word wider than the field, between characters. `TextEdit` lays out its own text separately, so in unusual texts the two can differ by a line.
- The measurement ignores the vertical scroll bar's width, which can narrow the text area a little when the content is taller than `max_size.y`.
- Font, font size and background style are read from the field's theme (`font`, `font_size`, `normal`), so a theme override changes the result.
