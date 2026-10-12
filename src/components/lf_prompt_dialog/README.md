# LFPromptDialog

> A text prompt you wait for in one line: `var name: String = await LFPromptDialog.ask(self, "Name your save", "Type a name")`.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): `LFPromptDialog.ask(...)` makes it, shows it and frees it for you |
| **Files** | `lf_prompt_dialog.gd` |
| **Tests** | `tests/test_lf_prompt_dialog.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFBuild`, `LFLogger` |

## When to use it

Use it when the game needs one line of text from the player: a save name, a player name, a
room code. The OK button stays grey until something is typed, so you never receive an empty
answer by pressing OK. For a yes/no question use `LFConfirm`; for a growing chat input
`LFAutoSizeTextEdit` or `LFChatBox`.

## Step by step

1. Open the script of the node that should ask.
2. Write a function that uses `await` (the function pauses at that line and carries on once the player answered):

   ```gdscript
   func _on_save_pressed() -> void:
   	var save_name: String = await LFPromptDialog.ask(self, "Name your save", "Type a name")
   	if save_name != "":
   		print("Saving as ", save_name)
   ```
3. Press **F6**, press the button. A panel with a text field appears and the OK button is grey. Type a letter: OK turns on. Press Enter (or OK): the name is printed. Press the button again and click Cancel or press Escape: nothing is printed.

## API

| Member | Signature | Description |
|---|---|---|
| `ask` | `static ask(parent: Node, title: String, placeholder := "", ok_text := "OK", cancel_text := "Cancel", trim_text := true, initial_text := "") -> String` | Shows the prompt under `parent` and waits. Returns the typed text (cut of surrounding spaces when `trim_text`) for OK or Enter, and `""` for Cancel, Escape, or a `parent` that is freed or leaves the scene tree first. Also `""` at once, with an error through `LFLogger`, when `parent` is null, freed or not in the tree. The popup frees itself. |
| `answered` | `signal answered(text: String)` | Emitted once with the result. |
| `submit`, `cancel` | `submit() -> void`, `cancel() -> void` | What OK and Cancel do. `submit` does nothing while `can_submit` is false. |
| `can_submit`, `current_text` | `() -> bool`, `() -> String` | Whether OK would work, and the text it would return. |
| `trim` | `var trim := true` | Spaces around the text are ignored. |
| `title_label`, `edit`, `ok_button`, `cancel_button` | `Label`, `LineEdit`, `Button`, `Button` | The parts. |
| `DEFAULT_OK_TEXT`, `DEFAULT_CANCEL_TEXT`, `DEFAULT_LAYER`, `DEFAULT_DIM_COLOR`, `FIELD_WIDTH`, `SEPARATION`, `TITLE_FONT_SIZE` | consts | Defaults. |

## Usage

```gdscript
# A rename box that starts with the old name and keeps spaces as typed.
var new_name: String = await LFPromptDialog.ask(self, "Rename", "New name", "Rename", "Back", false, old_name)
if new_name != "":
	rename_item(new_name)
```

## Notes

- **Cancel returns `""`.** OK can never return `""` (it is disabled for empty text), so an empty result always means "no answer"; check `!= ""`.
- With `trim_text` (the default) a field holding only spaces counts as empty and OK stays disabled; with it off, spaces count as text and are returned as typed.
- Enter in the field does what OK does (and nothing while OK is disabled). The field has the keyboard focus on opening.
- The popup is on its own `CanvasLayer` (layer 100) and blocks mouse clicks to everything under it. Escape is read from `ui_cancel`.
- Freeing `parent` (a scene change) closes the prompt and the awaiting code gets `""`.
