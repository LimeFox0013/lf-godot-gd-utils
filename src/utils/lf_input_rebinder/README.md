# LFInputRebinder

> Lets the player reassign the keys and pad buttons of input actions, and keeps the choice between runs.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_input_rebinder.gd` |
| **Tests** | `tests/test_lf_input_rebinder.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger`, `LFInputKeys` |

## When to use it

Use it for a "Controls" screen: each action (jump, move left) has a keyboard binding and a pad binding, and
the player picks a new one. It changes the project's `InputMap`, so the code that asks
`Input.is_action_pressed("jump")` keeps working. It does not draw a screen; you add the buttons.

## Step by step

1. Make a scene with one **Node** and attach a script to it.
2. In **Project > Project Settings > Input Map** add an action called `jump` with the Space key.
3. Replace the script with:

   ```gdscript
   extends Node

   var _rebinder := LFInputRebinder.new("user://controls.json", ["jump"])
   var _waiting := false


   func _ready() -> void:
   	_rebinder.load_saved()                     # the choice of the last run, if any
   	print(_rebinder.label_of(&"jump", LFInputRebinder.Kind.KEYBOARD))   # Space
   	_waiting = true                            # the next press becomes the jump key


   func _input(event: InputEvent) -> void:
   	if _waiting and LFInputRebinder.is_bindable(event):
   		_rebinder.rebind(&"jump", event)
   		_rebinder.save()
   		_waiting = false
   		print("jump is now ", _rebinder.label_of(&"jump", LFInputRebinder.Kind.KEYBOARD))
   ```
4. Press **F6** and press a key: the output shows the new name, and the next run starts with it.

## API

| Member | Signature | Description |
|---|---|---|
| `Kind` | `enum { KEYBOARD, PAD }` | The two kinds of binding every action has. |
| `AXIS_THRESHOLD` | `const := 0.6` | How far a stick must be pushed to count as a binding. |
| `FILE_VERSION` | `const := 1` | The `version` written into the saved file. |
| `new` | `LFInputRebinder.new(save_path, tracked_actions)` | Looks after the actions (missing ones are reported and skipped); the bindings they have now are the defaults. |
| `path`, `actions` | `var` | The save file and the tracked actions. |
| `kind_of` | `static kind_of(event) -> int` | `Kind` of a key / pad button / stick event, otherwise -1. |
| `is_bindable` | `static is_bindable(event) -> bool` | A key going down (not repeating), a pad button going down, a stick pushed far enough. |
| `same` | `static same(a, b) -> bool` | The same physical key, pad button or stick direction. |
| `describe` | `static describe(event, style := XBOX) -> String` | A short name: "A", "Space", "Stick Left". |
| `events_of` | `events_of(action, kind) -> Array` | The bindings of an action of one kind. Empty for an action that is not in the `InputMap`. |
| `label_of` | `label_of(action, kind, style := XBOX) -> String` | Their names joined with " / "; "-" when none or when the action is not in the `InputMap`. |
| `rebind` | `rebind(action, event) -> Array[StringName]` | Replaces the action's bindings of the event's kind. An action that used the event takes the old binding (a swap); those actions are returned. Does nothing (returns an empty array) for an action that is not tracked or an event that is not bindable. |
| `reset` | `reset(action := &"")` | Back to the starting bindings, for one action or all. |
| `save` | `save() -> bool` | Writes the tracked actions' bindings to `path` as JSON; false (and a logged error) when the file cannot be written. Only keys, pad buttons and stick directions are written. |
| `load_saved` | `load_saved() -> bool` | Applies the saved file; false when it is missing or unreadable (nothing changes then). An action missing from the file, or with no readable entry, keeps what it has. An action that is in the file gets exactly the saved bindings, so other event types (such as a mouse button) it had are dropped. |

## Notes

- Keys are stored by physical position (the key where "W" is on a US layout), so a binding survives a
  change of keyboard layout. Modifiers are dropped.
- A stick direction is stored fully pushed (`axis_value` of -1 or 1); the action's own deadzone applies.
- A swap leaves the other action without a binding of that kind when the rebound action had none.
- An action that was tracked but has since been removed from the `InputMap` is skipped, with a logged warning, by `events_of`, `label_of`, `reset`, `save` and `load_saved` (it is not written to the file).
