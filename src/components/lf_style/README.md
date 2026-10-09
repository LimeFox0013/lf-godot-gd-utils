# LFStyle

> StyleBox helpers: a flat box (fill, border, rounded corners) in one call, an outline-only frame, one style on every button state, and a project-theme lookup with a fallback.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_style.gd` |
| **Tests** | `tests/test_lf_style.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it to give panels and buttons a look from code: a dark card with a gold border behind
an inventory, a round icon button that stays round when disabled, or a yellow frame that
highlights the selected slot. A StyleBox is the background a control draws behind its
content; `LFStyle.flat` makes one in a single line instead of setting six properties. For
a look shared across the whole game, a Theme resource edited in the editor is the better
home; use `project_stylebox` to read from it with a fallback.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock. Save it.
2. Click **+ Add Child Node**, type `PanelContainer`, press *Create*. In the Inspector set
   *Layout → Transform → Position* to `40`, `40`. Select it and add a child
   `Label` (**+ Add Child Node**) with *Text* `Inventory`.
3. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control

   @onready var panel: PanelContainer = $PanelContainer


   func _ready() -> void:   # runs once when the scene starts
   	# A StyleBox is the background a control draws behind its content.
   	# Arguments: fill colour, border colour, border width (px), corner roundness (px),
   	# inner padding (px).
   	var card := LFStyle.flat(Color("#2b2f36"), Color("#5a8dee"), 2, 6, 10.0)
   	# "panel" is the name of the background a PanelContainer draws; this replaces it.
   	panel.add_theme_stylebox_override("panel", card)
   ```
4. Change the colours (`"#2b2f36"` is a hex colour, or use `Color.DIM_GRAY` and similar), the
   border width `2`, the roundness `6` and the padding `10.0` to taste.
5. Press **F6** (*Run Current Scene*). You should see a dark grey card with a blue border
   and rounded corners around the word Inventory.

## API

Everything the class offers; you only need the rows used above to get started. (A `const` is a fixed value; `StyleBoxFlat` is the plain coloured-box kind of StyleBox.)

| Member | Signature | Description |
|---|---|---|
| `BUTTON_STATES` | `const Array[StringName]` | `normal`, `hover`, `pressed`, `disabled`, `focus`: the boxes the default theme gives a Button. |
| `DEFAULT_OUTLINE_WIDTH` | `const int` (2) | Default `width` of `outline`, in pixels. |
| `flat` | `static flat(bg: Color, border := Color.TRANSPARENT, border_width := 0, corner_radius := 0, content_margin := -1.0, draw_center := true, anti_aliasing := true) -> StyleBoxFlat` | A filled box with an optional border and rounded corners. `content_margin` ≥ 0 sets it on all four sides; below 0 keeps the default. |
| `outline` | `static outline(color: Color, width := DEFAULT_OUTLINE_WIDTH, corner_radius := 0) -> StyleBoxFlat` (2) | Border only, no fill: a highlight frame. |
| `set_button_styles` | `static set_button_styles(control: Control, style: StyleBox, states: Array = BUTTON_STATES) -> void` | Overrides every listed stylebox of `control` with the same `style` (shared, not copied). `states` holds Strings or StringNames. |
| `project_stylebox` | `static project_stylebox(name: StringName, theme_type: StringName, fallback: StyleBox = null) -> StyleBox` | The project theme's box (e.g. `&"panel"`, `&"TooltipPanel"`), or `fallback` when there is no project theme or it lacks the box. |

## Usage

```gdscript
# inventory.gd, on a Control with a PanelContainer child, an icon Button and a highlight
# Panel.
extends Control

@onready var panel: PanelContainer = $Panel
@onready var icon_button: Button = $Panel/IconButton
@onready var highlight: Panel = $Highlight


func _ready() -> void:
	# Dark grey card, 2 px blue border, 6 px rounded corners, 10 px inner padding.
	var card := LFStyle.flat(Color("#2b2f36"), Color("#5a8dee"), 2, 6, 10.0)
	panel.add_theme_stylebox_override("panel", card)

	# One round style on every button state, so it stays round when disabled too.
	var round_style := LFStyle.flat(Color.DIM_GRAY, Color.WHITE, 2, 18, 4.0)
	LFStyle.set_button_styles(icon_button, round_style)

	# A border-only frame for the selected slot.
	highlight.add_theme_stylebox_override("panel", LFStyle.outline(Color.GOLD, 2, 6))

	# The project theme's tooltip box, or the card when the theme has none.
	var tooltip_box := LFStyle.project_stylebox(&"panel", &"TooltipPanel", card)
	print(tooltip_box)
```

## Notes

- `set_button_styles` with a hand-picked list is how a button ends up square when disabled: the left-out state falls back to the theme. Prefer the default `BUTTON_STATES`.
- The same StyleBox is shared by every state and every caller you pass it to; duplicate it before changing one user's copy.
- A StyleBoxFlat's content margin defaults to -1, meaning "use the border width"; `content_margin = -1.0` keeps that default.
