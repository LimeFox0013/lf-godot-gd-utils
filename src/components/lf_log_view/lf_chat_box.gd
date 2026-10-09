## A ready-made chat panel: a log of "name: text" lines, a field to type in and a Send button.
##
## It only shows lines and asks for one to be sent: Enter or Send clears the field and
## emits `send_requested` with the typed text trimmed (never empty); whoever owns the
## connection sends it and calls `add_line` for every line that arrives. Names and text
## are escaped, so BBCode tags a user types (like `[b]`) show as typed instead of
## formatting the log, and line breaks in them become spaces, so every message is one log
## paragraph (remote text cannot start a new "name: text" paragraph or slip past the cap;
## a long message still word-wraps onto more drawn lines). The
## field keeps editing after Enter, so several lines can be sent in a row, and the log
## keeps at most `max_lines` lines (oldest dropped first), like `LFLogView`.
class_name LFChatBox
extends VBoxContainer

## Emitted when the user presses Enter or Send with something typed. `text` is trimmed
## and never empty; the field is already cleared when it fires, so a handler may put
## text back (for example when sending failed).
signal send_requested(text: String)

## Default `placeholder`: the hint shown in the empty field.
const DEFAULT_PLACEHOLDER := 'Say something…'
## Default `send_text`: the text of the send button.
const DEFAULT_SEND_TEXT := 'Send'
## Default `log_min_height`: the log's minimum height, in pixels.
const DEFAULT_LOG_MIN_HEIGHT := 64.0
## Default colour of the sender's name in `add_line`.
const DEFAULT_NAME_COLOR := Color.WHITE
## Default colour of an `add_notice` line.
const DEFAULT_NOTICE_COLOR := Color.GRAY
## Default `max_lines`: the most log lines kept, as `LFLogView`.
const DEFAULT_MAX_LINES := LFLogView.DEFAULT_MAX_LINES

## Node name of `chat_log`.
const _LOG_NAME := 'Log'
## Node name of the HBoxContainer holding the field and the button.
const _ROW_NAME := 'Row'
## Node name of `chat_edit`.
const _EDIT_NAME := 'Edit'
## Node name of `send_button`.
const _SEND_NAME := 'Send'
## Theme stylebox of the log's background.
const _LOG_STYLE := &"normal"
## Theme font size of the log's normal text.
const _LOG_FONT_SIZE := &"normal_font_size"
## BBCode of one chat line: name colour (hex), escaped name, escaped text.
const _LINE_FORMAT := '[color=#%s]%s:[/color] %s\n'
## BBCode of one notice line: colour (hex), escaped text.
const _NOTICE_FORMAT := '[color=#%s]%s[/color]\n'
## Characters `_flat` turns into spaces, longest first so "\r\n" becomes one space: every
## character Godot's text servers break a line at (line feed, vertical tab, form feed,
## carriage return, U+0085, U+2028, U+2029).
const _LINE_BREAKS: Array[String] = ['\r\n', '\n', '\u000b', '\u000c', '\r', '\u0085', '\u2028', '\u2029']

## Most lines the log keeps; adding past it drops the oldest. 0 or less keeps every line.
## Lowering it trims the log at the next added line.
@export var max_lines := DEFAULT_MAX_LINES
## Longest line the field accepts; 0 means no limit.
@export var max_length := 0:
	set(value):
		max_length = value
		if chat_edit != null:
			chat_edit.max_length = value
## Hint shown in the empty field.
@export var placeholder := DEFAULT_PLACEHOLDER:
	set(value):
		placeholder = value
		if chat_edit != null:
			chat_edit.placeholder_text = value
## Text of the send button.
@export var send_text := DEFAULT_SEND_TEXT:
	set(value):
		send_text = value
		if send_button != null:
			send_button.text = value
## Font size of the log; 0 keeps the theme's.
@export var log_font_size := 0:
	set(value):
		log_font_size = value
		_apply_log_font_size()
## Minimum height of the log in pixels.
@export var log_min_height := DEFAULT_LOG_MIN_HEIGHT:
	set(value):
		log_min_height = value
		if chat_log != null:
			chat_log.custom_minimum_size.y = value
## The log's background StyleBox; null keeps the theme's.
var log_style: StyleBox:
	set(value):
		log_style = value
		if chat_log == null:
			return
		if value != null:
			chat_log.add_theme_stylebox_override(_LOG_STYLE, value)
		else:
			chat_log.remove_theme_stylebox_override(_LOG_STYLE)

## The log of lines (a RichTextLabel with BBCode on). Made in `_init`.
var chat_log: RichTextLabel
## The field the user types in. Made in `_init`.
var chat_edit: LineEdit
## The button that sends what is typed. Made in `_init`.
var send_button: Button

var _line_count := 0


func _init() -> void:
	chat_log = RichTextLabel.new()
	chat_log.name = _LOG_NAME
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(chat_log)
	var row := HBoxContainer.new()
	row.name = _ROW_NAME
	add_child(row)
	chat_edit = LineEdit.new()
	chat_edit.name = _EDIT_NAME
	chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Since Godot 4.4 a LineEdit stops editing on Enter unless told otherwise.
	chat_edit.keep_editing_on_text_submit = true
	chat_edit.text_submitted.connect(_on_submitted)
	row.add_child(chat_edit)
	send_button = Button.new()
	send_button.name = _SEND_NAME
	send_button.pressed.connect(send)
	row.add_child(send_button)
	chat_edit.max_length = max_length
	chat_edit.placeholder_text = placeholder
	send_button.text = send_text
	chat_log.custom_minimum_size.y = log_min_height
	_apply_log_font_size()


## Appends "`sender`: `text`" with the name in `name_color`. Both are escaped, so
## brackets typed by a user show as typed, and their line breaks (`\n`, `\r`, `\r\n`,
## vertical tab, form feed, U+0085, U+2028, U+2029) become spaces, so the message is one
## paragraph. Drops the oldest lines past `max_lines`.
func add_line(sender: String, text: String, name_color := DEFAULT_NAME_COLOR) -> void:
	_append(_LINE_FORMAT % [name_color.to_html(), _flat(sender), _flat(text)])


## Appends `text` on its own line, escaped and with line breaks turned into spaces as in
## `add_line`, in `color`: for notices such as "Ana joined". Drops the oldest lines past
## `max_lines`.
func add_notice(text: String, color := DEFAULT_NOTICE_COLOR) -> void:
	_append(_NOTICE_FORMAT % [color.to_html(), _flat(text)])


## Empties the log.
func clear_log() -> void:
	chat_log.clear()
	_line_count = 0


## Returns the number of lines in the log.
func line_count() -> int:
	return _line_count


## Sends what is typed, as Send does: clears the field, then emits `send_requested` with
## the trimmed text. Nothing happens while the field holds only whitespace.
func send() -> void:
	var text := chat_edit.text.strip_edges()
	if text == '':
		return
	chat_edit.clear()
	send_requested.emit(text)


func _on_submitted(_text: String) -> void:
	send()


## Escapes `text` and turns its line breaks into spaces, so it adds no paragraph.
static func _flat(text: String) -> String:
	for line_break in _LINE_BREAKS:
		text = text.replace(line_break, ' ')
	return LFText.bbcode_escape(text)


## Every line is one paragraph (`_flat` leaves no newline in it and its BBCode ends in
## one), so the oldest line is paragraph 0.
func _append(bbcode: String) -> void:
	chat_log.append_text(bbcode)
	_line_count += 1
	if max_lines <= 0:
		return
	while _line_count > max_lines:
		chat_log.remove_paragraph(0)
		_line_count -= 1


func _apply_log_font_size() -> void:
	if chat_log == null:
		return
	if log_font_size > 0:
		chat_log.add_theme_font_size_override(_LOG_FONT_SIZE, log_font_size)
	else:
		chat_log.remove_theme_font_size_override(_LOG_FONT_SIZE)
