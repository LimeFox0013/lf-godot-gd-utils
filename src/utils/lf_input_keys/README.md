# LFInputKeys

> Lets the keyboard act as one more gamepad, and writes button hints like "Jump  [Space]".

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_input_keys.gd` |
| **Tests** | `tests/test_lf_input_keys.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it for local multiplayer where one player plays on the keyboard and the others on
gamepads. Godot's input map is shared by everyone, so it cannot tell "player 2 pressed A"
from "player 3 pressed A", and it has no on-screen names for pad buttons. Here you write
one key map (`{KEY_SPACE: JOY_BUTTON_A}`), and `button_of` turns any event into "which pad
button did this player press", whether they use the keyboard or their own pad. The same map
gives the hint text ("Jump [Space]" or "Jump [A]"), so the labels match the
keys. For a single-player game, Godot's input map (`Input.is_action_pressed`) is the
simpler choice.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **User Interface** (a `Control`).
2. Right-click the `Control`, choose **Attach Script**, and press *Create*.
3. Select everything in the script and replace it with:

```gdscript
extends Control

# Which keyboard key stands in for which gamepad button.
const KEYS := {KEY_SPACE: JOY_BUTTON_A, KEY_R: JOY_BUTTON_Y}

# Who is playing: the keyboard. For the first gamepad write 0, for the second 1, ...
var device := LFInputKeys.KEYBOARD


func _ready() -> void:
	# A clickable button whose text names its key: "Jump  [Space]".
	var button := Button.new()
	add_child(button)
	LFInputKeys.bind_hint(button, "Jump", KEY_SPACE)


# Godot calls this for every input event nobody else used.
func _unhandled_input(event: InputEvent) -> void:
	match LFInputKeys.button_of(event, device, KEYS):
		JOY_BUTTON_A:
			print("jump")
		JOY_BUTTON_Y:
			print("swap")
```

4. Press **F6** (*Run Current Scene*) and save the scene when asked.
5. A button labelled `Jump  [Space]` appears in the top-left corner. Press **Space**: the **Output** panel prints `jump`. Press **R**: it prints `swap`.
6. Change the keys and buttons in `KEYS` for your own game (`JOY_BUTTON_A` is the bottom face button of any pad). Set `device` to `0` and the same code answers to the first gamepad's A and Y buttons instead.

## API

Everything the class offers; you only need the rows used above to get started.

### Constants and enums

| Member | Description |
|---|---|
| `KEYBOARD` | `-1`: the device id meaning "the keyboard". Joypad ids start at 0. |
| `KEY_NAME_OVERRIDES` | `{KEY_ESCAPE: 'Esc'}`: names that differ from `OS.get_keycode_string`; the default `overrides`. |
| `HINT_FORMAT` | `'%s  [%s]'`: the default hint shape (text, two spaces, key in brackets). |
| `DEFAULT_FALLBACK` | `'?'`: the default `fallback` of `joy_button_name` and `button_name`. |
| `PadStyle` | `XBOX` (A, B, X, Y, LB, RB, Back, Start), `PLAYSTATION` (Cross, Circle, Square, Triangle, L1, R1, Share, Options), `NINTENDO` (labels where they sit on a Nintendo pad: the bottom button reads B; L, R, -, +). |

### Methods

| Member | Signature | Description |
|---|---|---|
| `button_of` | `static button_of(event: InputEvent, device: int, key_map: Dictionary) -> int` | The pad button `event` presses for the player on `device`, or -1. On `KEYBOARD` a non-echo key press maps through `key_map` (`{keycode: JOY_BUTTON_*}`); on a pad, a button press from that device gives its index. Releases, echoes, other devices and other events give -1. |
| `is_press` | `static is_press(event: InputEvent, keycodes: Array, buttons: Array = [], allow_echo: bool = false) -> bool` | Whether `event` presses one of `keycodes` (echoes only with `allow_echo`) or one of the joypad `buttons`, from any device. |
| `key_name` | `static key_name(keycode: Key, overrides: Dictionary = KEY_NAME_OVERRIDES) -> String` | The key's on-screen name: its override, else Godot's ("Space", "Enter", "F1"). |
| `joy_button_name` | `static joy_button_name(button: int, style: PadStyle = PadStyle.XBOX, fallback: String = DEFAULT_FALLBACK) -> String` (`'?'`) | The label a `style` pad prints on `button` (D-pad buttons read "D-pad Up" and so on); `fallback` when unnamed. |
| `button_name` | `static button_name(button: int, device: int, key_names: Dictionary, style: PadStyle = PadStyle.XBOX, fallback: String = DEFAULT_FALLBACK) -> String` (`'?'`) | What `button` is called for the player on `device`: on `KEYBOARD` its entry in `key_names` (`{JOY_BUTTON_*: text}`), on a pad its `style` label. |
| `key_names_for` | `static key_names_for(key_map: Dictionary, overrides: Dictionary = KEY_NAME_OVERRIDES) -> Dictionary` | Turns a `button_of` key map into `button_name`'s table (`{JOY_BUTTON_*: key name}`). A button bound to several keys reads "W / Up". |
| `hint` | `static hint(text: String, keycode: Key, format: String = HINT_FORMAT, overrides: Dictionary = KEY_NAME_OVERRIDES) -> String` | `"Pause  [Space]"`. |
| `bind_hint` | `static bind_hint(button: Button, text: String, keycode: Key, format: String = HINT_FORMAT, overrides: Dictionary = KEY_NAME_OVERRIDES) -> Button` | Sets the button's text to `hint(text, keycode, format, overrides)` and its `focus_mode` to `FOCUS_NONE`. Returns the button. |

## Usage

```gdscript
extends Control  # an inventory screen for one player

# Keyboard keys stand in for pad buttons: Space = A, R = Y, Enter = Start.
const INVENTORY_KEYS := {KEY_SPACE: JOY_BUTTON_A, KEY_R: JOY_BUTTON_Y, KEY_ENTER: JOY_BUTTON_START}

var device := LFInputKeys.KEYBOARD  # or this player's joypad id: 0, 1, ...
var _inventory_key_names := LFInputKeys.key_names_for(INVENTORY_KEYS)  # {JOY_BUTTON_A: "Space", ...}


func _ready() -> void:
	# A clickable button that also names its key: "Pause  [Enter]".
	var pause := Button.new()
	add_child(pause)
	LFInputKeys.bind_hint(pause, "Pause", KEY_ENTER)
	print(swap_hint())  # "Swap [R]" on the keyboard, "Swap [Y]" on a pad


func _unhandled_input(event: InputEvent) -> void:
	match LFInputKeys.button_of(event, device, INVENTORY_KEYS):
		JOY_BUTTON_A:
			print("use item")
		JOY_BUTTON_Y:
			print("swap")
	# Any player, keyboard or pad, may open the menu.
	if LFInputKeys.is_press(event, [KEY_ESCAPE], [JOY_BUTTON_BACK]):
		print("toggle menu")


func swap_hint() -> String:
	return "Swap [%s]" % LFInputKeys.button_name(JOY_BUTTON_Y, device, _inventory_key_names)
```

## Notes

- A key event that carries only a `physical_keycode` (no `keycode`) is matched by its physical code.
- `button_of` ignores key echoes, so holding a key fires once; pass `allow_echo = true` to `is_press` for a held key that should repeat (a menu cursor).
- `bind_hint` takes the button out of focus on purpose: a focused button would also fire on Space/Enter, on top of the shortcut's own handler.
- `is_press` does not filter by device; use `button_of` when several players share the screen.
- Godot's `JOY_BUTTON_A` is the bottom face button on every pad, so on a Nintendo pad it is labelled B.
