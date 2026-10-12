# LFConfirm

> A yes/no popup you wait for in one line: `var ok: bool = await LFConfirm.ask(self, "Quit?", "Progress is lost.")`.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): `LFConfirm.ask(...)` makes it, shows it and frees it for you |
| **Files** | `lf_confirm.gd` |
| **Tests** | `tests/test_lf_confirm.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFBuild`, `LFLogger` |

## When to use it

Use it before something the player cannot undo: quitting to the menu, deleting a save,
selling an item. The code after `await` runs only once the player has answered, so the
question and the action stay in one place instead of being split over a signal handler. For a popup that asks
for text, use `LFPromptDialog`. For a screen of your own design, build a scene instead; this one has the plain look of Godot's default theme.

## Step by step

1. Open the script of the node that should ask (for example the one that handles a "Quit" button).
2. Make the function that runs on the button press start with `await`. A function that contains `await` pauses at that line and carries on later. Write:

   ```gdscript
   func _on_quit_pressed() -> void:
   	var ok: bool = await LFConfirm.ask(self, "Quit?", "Your progress is lost.")
   	if ok:
   		get_tree().quit()
   ```
3. Press **F6**, press the button. A dimmed screen with a small panel appears; the **No** button is highlighted. Press Enter: nothing happens (it chose No). Press the button again and click **Yes**: the game quits.

## API

| Member | Signature | Description |
|---|---|---|
| `ask` | `static ask(parent: Node, title: String, text: String, yes_text := "Yes", no_text := "No", focus_yes_button := false) -> bool` | Shows the popup under `parent` and waits. `true` for Yes. `false` for No, Escape (`ui_cancel`), or when `parent` is freed or leaves the scene tree first. `false` at once, with an error through `LFLogger`, when `parent` is null, freed or not in the tree. The popup frees itself. |
| `answered` | `signal answered(ok: bool)` | Emitted once with the answer. |
| `answer` | `answer(ok: bool) -> void` | Gives the answer from code; only the first one counts. |
| `title_label`, `text_label` | `Label` | The texts. |
| `yes_button`, `no_button` | `Button` | The buttons. |
| `focus_yes` | `var focus_yes := false` | Whether Yes, not No, has the keyboard focus on opening. Set by `focus_yes_button`. |
| `DEFAULT_YES_TEXT`, `DEFAULT_NO_TEXT` | `const String` | Default button texts. |
| `DEFAULT_LAYER`, `DEFAULT_DIM_COLOR`, `TEXT_WIDTH`, `SEPARATION`, `TITLE_FONT_SIZE` | consts | Look defaults: canvas layer 100, dim colour, message wrap width. |

## Usage

```gdscript
# Ask, and make Yes the default for a harmless question.
var again: bool = await LFConfirm.ask(self, "Play again?", "", "Play", "Menu", true)

# Style the popup: build it yourself, skip `ask`, and wait on the signal.
var popup := LFConfirm.new()
popup.title_label.text = "Delete save?"
popup.yes_button.text = "Delete"
add_child(popup)
var ok: bool = await popup.answered
```

## Notes

- **No has the focus by default**, so a player who hits Enter or Space without reading, or a controller's accept button, does not confirm a destructive action. Pass `focus_yes_button = true` for a harmless question.
- The popup draws on its own `CanvasLayer` (layer 100), so it covers the window whatever `parent` is, and its dim layer stops mouse clicks to everything underneath. The popup does not disable the controls under it for the keyboard; disable them yourself if that matters.
- `parent` only decides how long the popup lives: freeing it (a scene change) closes the popup and the awaiting code receives `false`.
- Escape is read from `ui_cancel`; if your project removed that action, the popup can only be closed with a button.
- Two popups at once are independent: each `ask` waits for its own answer.
