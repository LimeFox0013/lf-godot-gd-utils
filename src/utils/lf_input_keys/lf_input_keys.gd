## Lets the keyboard act as a gamepad for one player, and names keys and pad buttons for hints.
##
## Every method is static: call it on the class, never create an instance. It reads a press
## as a gamepad button for one device (the keyboard standing in for a pad through a key
## map), tests an event against a set of keys and buttons, and names keys and pad buttons
## for on-screen hints such as "Pause  [Space]".
class_name LFInputKeys
extends RefCounted

## The device id that means "the keyboard" to `button_of` and `button_name`. Joypad
## device ids start at 0.
const KEYBOARD := -1
## Key names that differ from `OS.get_keycode_string`: the default `overrides`.
const KEY_NAME_OVERRIDES := {KEY_ESCAPE: 'Esc'}
## The default `format` of `hint`: the text, two spaces, the key in brackets.
const HINT_FORMAT := '%s  [%s]'
## The default `fallback` of `joy_button_name` and `button_name`: the label of a button
## the table does not name.
const DEFAULT_FALLBACK := '?'

## Joins the names of several keys bound to one button ("W / Up").
const _KEY_JOIN_FORMAT := '%s / %s'

## Which controller family's labels `joy_button_name` uses.
enum PadStyle {
	## A, B, X, Y, LB, RB, Back, Start.
	XBOX,
	## Cross, Circle, Square, Triangle, L1, R1, Share, Options.
	PLAYSTATION,
	## The face labels where they sit on a Nintendo pad (the bottom button reads B), L, R, -, +.
	NINTENDO,
}

const _COMMON_NAMES := {
	JOY_BUTTON_DPAD_UP: 'D-pad Up', JOY_BUTTON_DPAD_DOWN: 'D-pad Down',
	JOY_BUTTON_DPAD_LEFT: 'D-pad Left', JOY_BUTTON_DPAD_RIGHT: 'D-pad Right',
}
const _STYLE_NAMES := {
	PadStyle.XBOX: {
		JOY_BUTTON_A: 'A', JOY_BUTTON_B: 'B', JOY_BUTTON_X: 'X', JOY_BUTTON_Y: 'Y',
		JOY_BUTTON_LEFT_SHOULDER: 'LB', JOY_BUTTON_RIGHT_SHOULDER: 'RB',
		JOY_BUTTON_LEFT_STICK: 'LS', JOY_BUTTON_RIGHT_STICK: 'RS',
		JOY_BUTTON_BACK: 'Back', JOY_BUTTON_START: 'Start', JOY_BUTTON_GUIDE: 'Guide',
	},
	PadStyle.PLAYSTATION: {
		JOY_BUTTON_A: 'Cross', JOY_BUTTON_B: 'Circle', JOY_BUTTON_X: 'Square', JOY_BUTTON_Y: 'Triangle',
		JOY_BUTTON_LEFT_SHOULDER: 'L1', JOY_BUTTON_RIGHT_SHOULDER: 'R1',
		JOY_BUTTON_LEFT_STICK: 'L3', JOY_BUTTON_RIGHT_STICK: 'R3',
		JOY_BUTTON_BACK: 'Share', JOY_BUTTON_START: 'Options', JOY_BUTTON_GUIDE: 'PS',
	},
	PadStyle.NINTENDO: {
		JOY_BUTTON_A: 'B', JOY_BUTTON_B: 'A', JOY_BUTTON_X: 'Y', JOY_BUTTON_Y: 'X',
		JOY_BUTTON_LEFT_SHOULDER: 'L', JOY_BUTTON_RIGHT_SHOULDER: 'R',
		JOY_BUTTON_LEFT_STICK: 'LS', JOY_BUTTON_RIGHT_STICK: 'RS',
		JOY_BUTTON_BACK: '-', JOY_BUTTON_START: '+', JOY_BUTTON_GUIDE: 'Home',
	},
}


## The gamepad button (a `JOY_BUTTON_*` value) `event` presses for the player on `device`,
## or -1. On `KEYBOARD`, a key press (not an echo) maps through `key_map` ({keycode: JOY_BUTTON_*}), -1 for an
## unmapped key. On a pad, a button press from that same device gives its button index.
## Releases, echoes, other devices and other event types give -1.
static func button_of(event: InputEvent, device: int, key_map: Dictionary) -> int:
	if event == null or not event.is_pressed() or event.is_echo():
		return -1
	if device == KEYBOARD:
		if not (event is InputEventKey):
			return -1
		return int(key_map.get(_keycode_of(event), -1))
	if not (event is InputEventJoypadButton) or event.device != device:
		return -1
	return (event as InputEventJoypadButton).button_index


## Whether `event` is a press of one of `keycodes` (an echo only with `allow_echo`) or of
## one of the joypad `buttons` (`JOY_BUTTON_*` values), from any device. An "echo" is the
## repeat Godot sends while a key is held down.
static func is_press(event: InputEvent, keycodes: Array, buttons: Array = [], allow_echo: bool = false) -> bool:
	if event == null or not event.is_pressed():
		return false
	if event is InputEventKey:
		return (allow_echo or not event.is_echo()) and keycodes.has(_keycode_of(event))
	if event is InputEventJoypadButton:
		return buttons.has((event as InputEventJoypadButton).button_index)
	return false


## The on-screen name of `keycode`: its entry in `overrides`, else Godot's own name
## ("Space", "Enter", "F1").
static func key_name(keycode: Key, overrides: Dictionary = KEY_NAME_OVERRIDES) -> String:
	if overrides.has(keycode):
		return str(overrides[keycode])
	return OS.get_keycode_string(keycode)


## The label `button` (JOY_BUTTON_*) carries on a `style` pad; `fallback` for a button
## that style does not name.
static func joy_button_name(button: int, style: PadStyle = PadStyle.XBOX, fallback: String = DEFAULT_FALLBACK) -> String:
	var names: Dictionary = _STYLE_NAMES.get(style, _STYLE_NAMES[PadStyle.XBOX])
	return str(names.get(button, _COMMON_NAMES.get(button, fallback)))


## What `button` is called for the player on `device`: on `KEYBOARD` its entry in
## `key_names` ({JOY_BUTTON_*: text}, see `key_names_for`), on a pad its `style` label.
## `fallback` when the table has no entry.
static func button_name(button: int, device: int, key_names: Dictionary, style: PadStyle = PadStyle.XBOX, fallback: String = DEFAULT_FALLBACK) -> String:
	if device == KEYBOARD:
		return str(key_names.get(button, fallback))
	return joy_button_name(button, style, fallback)


## Turns a `button_of` key map ({keycode: JOY_BUTTON_*}) into the names `button_name`
## reads ({JOY_BUTTON_*: key name}), so hints built from it name the mapped keys. A
## button bound to several keys reads "W / Up", in the map's order.
static func key_names_for(key_map: Dictionary, overrides: Dictionary = KEY_NAME_OVERRIDES) -> Dictionary:
	var names := {}
	for keycode: Variant in key_map:
		var button: Variant = key_map[keycode]
		var name := key_name(keycode, overrides)
		names[button] = name if not names.has(button) else _KEY_JOIN_FORMAT % [names[button], name]
	return names


## "`text`  [Key]": a label naming the key that does the same thing. `format` takes the
## text, then the key name.
static func hint(text: String, keycode: Key, format: String = HINT_FORMAT, overrides: Dictionary = KEY_NAME_OVERRIDES) -> String:
	return format % [text, key_name(keycode, overrides)]


## Labels `button` with `hint(text, keycode, format, overrides)` and takes it out of
## focus, so a later Space or Enter cannot press it again on top of the key's own handler.
## Returns `button`.
static func bind_hint(button: Button, text: String, keycode: Key, format: String = HINT_FORMAT, overrides: Dictionary = KEY_NAME_OVERRIDES) -> Button:
	button.text = hint(text, keycode, format, overrides)
	button.focus_mode = Control.FOCUS_NONE
	return button


## The event's keycode, or its physical keycode when it carries only that.
static func _keycode_of(event: InputEventKey) -> Key:
	return event.keycode if event.keycode != KEY_NONE else event.physical_keycode
