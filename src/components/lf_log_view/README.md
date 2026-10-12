# LFLogView, LFChatBox

> A scrolling log of text lines that drops the oldest past a limit and follows the newest, and a chat panel (escaped "name: text" log with the same kind of limit, a field and Send) that asks its owner to send.

| | |
|---|---|
| **Files** | `lf_log_view.gd`, `lf_chat_box.gd` |
| **Tests** | `tests/test_lf_log_view.gd`, `tests/test_lf_chat_box.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFText` (`bbcode_escape`) |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFLogView` | Node: add it to a scene |
| `LFChatBox` | Node: add it to a scene |

## When to use it

Use `LFLogView` for any growing list of messages: a combat log ("Knight hits Goblin for
12"), quest updates, or an in-game debug console. It keeps at most `max_lines` lines, so the
log does not grow without bound, and keeps the newest line in view. Use `LFChatBox` for multiplayer chat or a
lobby: it escapes what players type (BBCode they enter shows as typed) and tells you what to send;
your networking code does the sending. For a single block of formatted text, use Godot's
`RichTextLabel` directly.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock. Save it.
2. Click **+ Add Child Node**, type `LFLogView`, press *Create*. In the Inspector set
   *Layout → Custom Minimum Size* to x = `400`, y = `150` (pixels) and *Max Lines* to `50`
   (the log keeps the newest 50 lines).
3. Add a second node the same way: `LFChatBox`, with *Custom Minimum Size* x = `400`,
   y = `150` and *Layout → Transform → Position* y = `200`, so it sits below the log.
   (Both look empty in the editor; they fill in while the game runs.)
4. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control

   # "$LFLogView" and "$LFChatBox" are the child nodes with those names.
   @onready var log_view: LFLogView = $LFLogView
   @onready var chat: LFChatBox = $LFChatBox


   func _ready() -> void:   # runs once when the scene starts
   	log_view.append("Welcome to the dungeon")
   	log_view.append("Knight hits Goblin for 12", Color.ORANGE)   # a coloured line
   	# send_requested is a signal: an event other code can listen to. It fires when the
   	# player presses Enter or the Send button with something typed.
   	chat.send_requested.connect(_on_send_requested)
   	chat.add_notice("Ana joined")


   func _input(event: InputEvent) -> void:
   	if event.is_action_pressed("ui_cancel"):   # the Escape key
   		log_view.append("You pressed Escape")


   # `text` is what the player typed. A real game would send it over the network here.
   func _on_send_requested(text: String) -> void:
   	chat.add_line("Me", text, Color.GOLD)   # show it, with the name in gold
   ```
5. Press **F6** (*Run Current Scene*). The top box shows two lines, the second in orange.
   The bottom box shows `Ana joined` in grey, a text field and a Send button. Type a
   message and press Enter: it appears as `Me: <your message>`. Press Escape to add a line
   to the top log.

## API

Everything the class offers; you only need the rows used above to get started. (`Variant` means "any kind of value"; a `StyleBox` is a background look; BBCode is the `[b]bold[/b]` markup Godot's RichTextLabel understands.)

### LFLogView

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_MAX_LINES` | `const int` (100) | Default `max_lines`. |
| `max_lines` | `@export var max_lines := DEFAULT_MAX_LINES` (100) | Most lines kept; appending past it drops the oldest. 0 or less keeps all. A lowered value trims at the next append. |
| `follow` | `@export var follow := true` | Scrolls to the bottom whenever the scroll range changes (see Notes). |
| `font_size` | `@export var font_size := 0` | Font size of new lines; 0 keeps the theme's. |
| `line_scene` | `@export var line_scene: PackedScene` | Makes each line from this scene (root must be a Control). The text goes to the root's `text` property when it has one; `color` applies to a Label root only. Null keeps the plain Label. |
| `line_factory` | `var line_factory := Callable()` | `func(text: String, color: Variant) -> Control`: makes each line yourself (a chat bubble, say). Beats `line_scene`. `font_size` is not applied to it. A result that is not a Control is an error through `LFLogger` and a Label is used. |
| `lines` | `var lines: VBoxContainer` | One control per line (a Label by default), oldest first. |
| `append` | `append(text: String, color: Variant = null) -> Control` | Adds the newest line (a word-wrapped Label by default), in `color` when given. Returns its control. |
| `clear` | `clear() -> void` | Removes every line at once. |
| `line_count` | `line_count() -> int` | Lines shown. |
| `line_text` | `line_text(index: int) -> String` | Text line `index` (0 = oldest) was appended with; `''` out of range. |

### LFChatBox

| Member | Signature | Description |
|---|---|---|
| `send_requested` | `signal send_requested(text: String)` | Enter or Send with something typed; `text` is trimmed and never empty. The field is already cleared when it fires, so a handler may put text back. |
| `DEFAULT_PLACEHOLDER`, `DEFAULT_SEND_TEXT` | `const String` (`'Say something…'`, `'Send'`) | Defaults of `placeholder` and `send_text`. |
| `DEFAULT_LOG_MIN_HEIGHT` | `const float` (64.0) | Default `log_min_height`. |
| `DEFAULT_NAME_COLOR`, `DEFAULT_NOTICE_COLOR` | `const Color` (`Color.WHITE`, `Color.GRAY`) | Default colours of `add_line`'s name and of `add_notice`. |
| `DEFAULT_MAX_LINES` | `const int` (`LFLogView.DEFAULT_MAX_LINES`, 100) | Default `max_lines`. |
| `max_lines` | `@export var max_lines := DEFAULT_MAX_LINES` (100) | Most log lines kept; adding past it drops the oldest. 0 or less keeps all. A lowered value trims at the next added line. |
| `max_length` | `@export var max_length := 0` | Longest line the field accepts (0 = no limit). |
| `placeholder` | `@export var placeholder := DEFAULT_PLACEHOLDER` (`'Say something…'`) | Hint in the empty field. |
| `send_text` | `@export var send_text := DEFAULT_SEND_TEXT` (`'Send'`) | Send button text. |
| `log_font_size` | `@export var log_font_size := 0` | Log font size; 0 keeps the theme's. |
| `log_min_height` | `@export var log_min_height := DEFAULT_LOG_MIN_HEIGHT` (64.0) | Log minimum height. |
| `log_style` | `var log_style: StyleBox` | Log background; null keeps the theme's. |
| `chat_log`, `chat_edit`, `send_button` | `var chat_log: RichTextLabel`, `var chat_edit: LineEdit`, `var send_button: Button` | The parts, made in `_init`. `chat_edit` has `keep_editing_on_text_submit` on. |
| `add_line` | `add_line(sender: String, text: String, name_color := DEFAULT_NAME_COLOR) -> void` (`Color.WHITE`) | Appends "sender: text", the name in `name_color`. Both escaped, their line breaks (`\n`, `\r`, `\r\n`, vertical tab, form feed, U+0085, U+2028, U+2029) turned into spaces. Drops the oldest lines past `max_lines`. |
| `add_notice` | `add_notice(text: String, color := DEFAULT_NOTICE_COLOR) -> void` (`Color.GRAY`) | Appends an escaped line in `color` ("Ana joined"), line breaks turned into spaces. Drops the oldest lines past `max_lines`. |
| `clear_log` | `clear_log() -> void` | Empties the log. |
| `line_count` | `line_count() -> int` | Lines in the log. |
| `send` | `send() -> void` | What Enter and Send do: clears the field, then emits `send_requested`. Nothing while the field is blank. |

## Usage

```gdscript
# lobby.gd, on a VBoxContainer in the lobby screen.
extends VBoxContainer

var combat_log := LFLogView.new()
var chat := LFChatBox.new()


func _ready() -> void:
	# A log 160 px tall that keeps the last 50 lines.
	combat_log.custom_minimum_size = Vector2(0, 160)
	combat_log.max_lines = 50
	add_child(combat_log)
	combat_log.append("Knight hits Goblin for 12", Color.ORANGE)

	# A chat panel: it emits what to send; you send it and show what arrives.
	chat.max_length = 200
	chat.placeholder = "Say something to the room…"
	add_child(chat)
	chat.send_requested.connect(_on_send_requested)
	chat.add_notice("Ana joined")


func _on_send_requested(text: String) -> void:
	# Send `text` with your own networking code here.
	chat.add_line("Me", text, Color.GOLD)   # or wait for the server's echo instead


# Connect your network's "message arrived" signal here.
func _on_chat_received(from: String, text: String) -> void:
	chat.add_line(from, text, Color.SKY_BLUE)
```

## Notes

- **Custom lines.** Set `line_scene` (a scene whose root is a Control with a `text` property, such as a chat bubble script with `var text`) or `line_factory` (a Callable you write) before the first `append`; lines already added keep their look. Either way the cap, `follow` and `clear` work as for Labels. Example: `log_view.line_factory = func(text, color): var bubble := ChatBubble.new(); bubble.text = text; return bubble`. `append` returns a `Control` (it was a `Label`): cast it, `append(...) as Label`, if you style the default line.
- Lines past `max_lines` are removed from the tree at once (and freed later), so `line_count()` is exact right after `append`.
- `follow` scrolls to the bottom whenever the scroll range changes (lines added or removed, or the view resized), also when the reader scrolled up. Turn it off while the reader browses if that matters.
- The chat box never sends anything itself; it only emits. Show your own lines when the server echoes them (or call `add_line` right after emitting), not both.
- Player text goes through `LFText.bbcode_escape`: `[b]` typed in chat shows as `[b]`. Do not pre-escape.
- Line breaks in a name or text (`\n`, `\r`, `\r\n`, vertical tab, form feed, U+0085, U+2028, U+2029: every character Godot's text servers break a line at) become spaces, so every message is exactly one log paragraph: remote text cannot start a new "name: text" paragraph, and the `max_lines` cap holds whatever arrives. A long message still word-wraps onto several drawn lines, so text padded with spaces can land at the start of a drawn line. Show multi-line content some other way.
- The chat log follows new lines (`scroll_following`).
- The field keeps focus and editing after Enter (`keep_editing_on_text_submit`; Godot 4.4 and later otherwise end editing on Enter), so a player can send several lines in a row.
- The chat log drops its oldest lines past `max_lines` (100 by default) with `RichTextLabel.remove_paragraph`; each line is one paragraph (line breaks inside it were turned into spaces). Lines added to `chat_log` directly, not through `add_line` / `add_notice`, are not counted.
