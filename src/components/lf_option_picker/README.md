# LFOptionPicker

> Fill an `OptionButton` (drop-down) from data and read the choice back by value, with each value stored as item metadata.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_option_picker.gd` |
| **Tests** | `tests/test_lf_option_picker.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils` (`same_value`), `LFLogger` |

## When to use it

Use it for any drop-down built from data: choosing a difficulty, a team colour, or which
player owns a unit. You give it your items and two small functions (what to show, what
value to keep), then read `selected_value(...)` or hear `value_selected(...)` as that
value, never as an index. Godot's `OptionButton` stores per-item metadata but has no call
to select or read by it, which is exactly what this adds. For a fixed list of a few
choices set up in the editor, a plain `OptionButton` and its `selected` index are enough.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock. Save it.
2. Click **+ Add Child Node**, type `OptionButton` (Godot's drop-down), press *Create*.
   Leave it with no items: the script fills it.
3. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control

   @onready var picker: OptionButton = $OptionButton

   # Your data: each entry has an id (what the game keeps) and a name (what the player sees).
   var levels := [
   	{"id": "easy", "name": "Easy"},
   	{"id": "normal", "name": "Normal"},
   	{"id": "hard", "name": "Hard"},
   ]


   func _ready() -> void:   # runs once when the scene starts
   	# One item per level. The two `func(l): ...` parts are small functions passed as
   	# values: the first picks the shown text, the second the stored value. "normal"
   	# is the one pre-selected.
   	LFOptionPicker.fill(picker, levels, func(l): return l.name, func(l): return l.id, "normal")
   	# When the player picks something, you get its id (not its position in the list).
   	LFOptionPicker.value_selected(picker, func(id): print("Chosen: ", id))
   ```
4. Press **F6** (*Run Current Scene*). The drop-down shows `Normal`. Open it and pick
   `Hard`: the **Output** panel shows `Chosen: hard`.
5. To read the choice at any other time, call `LFOptionPicker.selected_value(picker)`.
   To change it from code, call `LFOptionPicker.select_value(picker, "easy")`.

## API

Everything the class offers; you only need the rows used above to get started. A Callable is a function passed around as a value, like the `func(l): ...` parts above.

| Member | Signature | Description |
|---|---|---|
| `fill` | `static fill(picker: OptionButton, items: Array, label: Callable, value := Callable(), selected: Variant = null, icon := Callable()) -> bool` | Replaces the items: one per entry, text `label.call(item)`, metadata `value.call(item)` (or the item itself), and with `icon` the Texture2D `icon.call(item)` (null: no icon). Then selects the first item carrying `selected`; when none does, nothing is selected. With `selected` null, the first item is selected. Returns whether an item is selected afterwards. |
| `select_value` | `static select_value(picker: OptionButton, value: Variant) -> bool` | Selects the first item carrying `value`; `false` and no change when none does. |
| `selected_value` | `static selected_value(picker: OptionButton, fallback: Variant = null) -> Variant` | The selected item's value; `fallback` when nothing is selected or the selected item carries no value. |
| `value_selected` | `static value_selected(picker: OptionButton, callback: Callable) -> Callable` | Connects `item_selected` so `callback(value)` gets the chosen item's value (null for an item without one). Returns the connected callable, for `item_selected.disconnect`. An invalid `callback` pushes an error, connects nothing and returns an empty Callable. |

## Usage

```gdscript
# owner_menu.gd, on a Control with an OptionButton child named OwnerOption.
extends Control

@onready var owner_option: OptionButton = $OwnerOption

var players := [{"id": 7, "name": "Ana"}, {"id": 9, "name": "Bo"}]
var current_owner_id := 9


func _ready() -> void:
	# One item per player: shows the name, keeps the id, pre-selects the current owner.
	var found := LFOptionPicker.fill(owner_option, players,
		func(p): return p.name, func(p): return p.id, current_owner_id)
	if not found:
		owner_option.select(0)   # the old owner is gone: show the first player instead

	# Hear the choice as an id rather than an index.
	LFOptionPicker.value_selected(owner_option, _on_owner_chosen)


func _on_owner_chosen(owner_id: Variant) -> void:
	current_owner_id = owner_id


# Read the current choice any time; -1 when nothing is selected.
func chosen_owner() -> int:
	return LFOptionPicker.selected_value(owner_option, -1)
```

With a colour swatch per item, pass an icon function as the last argument:
`LFOptionPicker.fill(color_option, colors, func(c): return c.name, func(c): return c.id, null, func(c): return c.swatch)`.

## Notes

- Values match by value with numeric and text leniency (`LFUtils.same_value`): an int
  `2` matches a float `2.0`, and a String matches a StringName with the same text. An
  int `2` does not match the String `'2'`.
- `fill` with a `selected` that no item carries leaves nothing selected (the picker shows
  no text) and returns `false`; pick a stand-in yourself if you want one.
- `null` as `selected` means "no preference", so a null-valued item cannot be
  pre-selected through `fill`; call `select_value(picker, null)` afterwards.
- `fill` never emits `item_selected`, so a handler connected before a refill does not
  run because of it.
- `fill` clears the picker first; other per-item extras (disabled items, tooltips,
  items without a value such as "Custom") are added by the caller afterwards, by index.
- An invalid `label` callable is reported and leaves the picker as it was.
