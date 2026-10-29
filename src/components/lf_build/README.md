# LFBuild

> One-line helpers for building UI in code: labels, buttons wired to a callback, text fields (and their commit), margins, spin boxes, spacers, full-screen anchoring, a centred box that scrolls only when needed, and a titled panel.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_build.gd` |
| **Tests** | `tests/test_lf_build.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it when you build menus or panels from a script rather than in the scene editor: a
"Join game" dialog, a settings list generated from data, or a debug overlay. Each call
replaces the `new()`, property setting and `add_child` lines you would write by hand
(two for `wrap`, more than a dozen for a scrolling `centered_box` on a panel). When a screen
is fixed and you prefer to see it, build it in the editor instead; for the styles
(rounded boxes, borders) to pass in, see `LFStyle`.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock (a full-window
   `Control` root). Save it with Ctrl+S.
2. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control


   func _ready() -> void:   # runs once when the scene starts
   	# A column in the middle of the window: 300 px wide, 12 px between items.
   	var box := LFBuild.centered_box(self, 300, 12)
   	# A gold title, font size 28, added to the column.
   	LFBuild.label(box, "Welcome", Color.GOLD, 28)
   	# A text field with a grey hint inside it.
   	var name_field := LFBuild.line_edit(box, "Your name")
   	# A button; the part after the comma runs when it is pressed.
   	LFBuild.button(box, "Play", func(): print("Hello, ", name_field.text))
   ```
3. Change the numbers and texts to taste: `300` is the column's width in pixels, `12` the
   space between items in pixels, `28` the title's font size.
4. Press **F6** (*Run Current Scene*). You should see a panel in the middle of the window
   with the title, a text box and a Play button. Type a name, press Play, and look in the
   **Output** panel at the bottom of the editor for `Hello, <your name>`.

## API

Everything the class offers; you only need the rows used above to get started. (`Variant` means "any kind of value"; `StyleBox` is a background look, see `LFStyle`.)

| Member | Signature | Description |
|---|---|---|
| `label` | `static label(parent: Node = null, text := '', color: Variant = null, font_size := 0) -> Label` | A Label added to `parent` unless it is null; `color` (null keeps the theme's) and `font_size` (0 keeps the theme's) become overrides. |
| `wrap` | `static wrap(target: Label, width: float, mode := TextServer.AUTOWRAP_WORD_SMART) -> Label` | Wraps at `width` px (its minimum width). Returns `target`. |
| `outline` | `static outline(target: Label, color: Color, size: int) -> Label` | A `size` px text outline in `color`. Returns `target`. |
| `button` | `static button(parent: Node, text: String, on_pressed := Callable(), tooltip := '') -> Button` | A Button connected to `on_pressed` (when valid); added to `parent` unless it is null. |
| `line_edit` | `static line_edit(parent: Node, placeholder := '', tooltip := '', secret := false) -> LineEdit` | A LineEdit; `secret` masks its text. |
| `on_commit` | `static on_commit(edit: LineEdit, callback: Callable) -> LineEdit` | Calls `callback` (no arguments) when the text is committed: Enter or losing focus. Returns `edit`. |
| `margin` | `static margin(parent: Node, px: int) -> MarginContainer` | A MarginContainer with `px` on all four sides; added to `parent` unless it is null. |
| `spin_box` | `static spin_box(parent: Node, min_value: float, max_value: float, step: float, value: float) -> SpinBox` | A SpinBox set in that order (so `value` is clamped); added to `parent` unless it is null. |
| `spacer` | `static spacer(parent: Node = null) -> Control` | An empty, mouse-transparent Control that expands both ways, pushing its Box-container siblings apart. |
| `fill_parent` | `static fill_parent(control: Control, left := 0.0, top := 0.0, right := 0.0, bottom := 0.0) -> Control` | Full-rect anchors, inset by the given pixels on each side. Returns `control`. |
| `centered_box` | `static centered_box(parent: Control, min_width := 0, separation := -1, panel_style: StyleBox = null, on_panel := true, scrolls := false) -> VBoxContainer` | A VBox centred in `parent` (the frame fills it). `on_panel` puts it on a PanelContainer (`box.get_parent()`), styled by `panel_style`. `scrolls` makes the frame scroll vertically once the content is taller than `parent`, while it stays centred when it fits. |
| `titled_panel` | `static titled_panel(parent: Node, title: String, style: StyleBox = null, title_size := 0, separation := -1) -> VBoxContainer` | A PanelContainer holding a VBox whose first child is the title label. Returns the box. |

## Usage

```gdscript
# join_menu.gd, on a full-screen Control (anchors: Full Rect).
extends Control


func _ready() -> void:
	# A 360 px wide column, centred on a rounded panel.
	var box := LFBuild.centered_box(self, 360, 12, LFStyle.flat(Color("#2b2f36"), Color("#5a8dee"), 2, 6, 10.0))
	LFBuild.label(box, "Join a game", null, 28).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var address := LFBuild.line_edit(box, "host:port", "Where the server runs")

	# A row with Back on the left and Join pushed to the right.
	var row := HBoxContainer.new()
	box.add_child(row)
	LFBuild.button(row, "Back", _on_back)
	LFBuild.spacer(row)
	LFBuild.button(row, "Join", func(): _join(address.text), "Connect to that address")

	# A grey hint that wraps at 360 px.
	LFBuild.wrap(LFBuild.label(box, "Ask the host for the address.", Color.GRAY, 13), 360.0)


func _on_back() -> void:
	queue_free()


func _join(address: String) -> void:
	print("Joining ", address)
```

## Notes

- `fill_parent` sets anchors and offsets; inside a Container those are ignored, as the container places its children.
- `centered_box(..., scrolls = true)` is the arrangement that is easy to get wrong by hand: the CenterContainer must expand inside the ScrollContainer, and horizontal scrolling must be off, or the content either never scrolls or never centres.
- Colours and sizes are overrides on the control, so they win over any theme. Leave them null/0 to follow the theme.
- Every builder that makes a new control takes the parent as its first argument (`label`, `button`, `line_edit`, `margin`, `spin_box`, `spacer`, `centered_box`, `titled_panel`); pass `null` to `label`, `button`, `line_edit`, `margin`, `spin_box`, `spacer` or `titled_panel` to get an unparented control. `wrap`, `outline`, `on_commit` and `fill_parent` take the control they change first.
- None of the factories set a `name`; set one if you look children up by name.
