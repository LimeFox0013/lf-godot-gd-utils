## One-line helpers for building UI in code instead of in the editor.
##
## Each function makes a common control and sets it up in one call: a label (parent,
## colour, size), wrapping and outlining it, a button wired to a callback, a line edit,
## an expanding spacer, full-rect anchoring with insets, a centred content box that
## scrolls only when it does not fit, and a titled panel. Every builder that adds a new
## control to a parent takes that parent first. Static: call the functions on the class
## (`LFBuild.label(...)`), never `.new()` it.
class_name LFBuild
extends RefCounted

## Theme colour a Label draws its text in.
const _FONT_COLOR := &"font_color"
## Theme font size of a Label.
const _FONT_SIZE := &"font_size"
## Theme colour of a Label's text outline.
const _FONT_OUTLINE_COLOR := &"font_outline_color"
## Theme constant: a Label's outline width, in pixels.
const _OUTLINE_SIZE := &"outline_size"
## Theme constant: a box container's spacing between children, in pixels.
const _SEPARATION := &"separation"
## Theme stylebox of a PanelContainer.
const _PANEL := &"panel"


## Returns a new Label showing `text`, added to `parent` unless it is null. `color` (a
## Color, or null to keep the theme's) and `font_size` (0 keeps the theme's) become
## overrides on it.
static func label(parent: Node = null, text := '', color: Variant = null, font_size := 0) -> Label:
	var made := Label.new()
	made.text = text
	if color != null:
		made.add_theme_color_override(_FONT_COLOR, color)
	if font_size > 0:
		made.add_theme_font_size_override(_FONT_SIZE, font_size)
	if parent != null:
		parent.add_child(made)
	return made


## Makes `target` wrap its text at `width` px (its minimum width) with `mode`. A width of
## 0 wraps at whatever width its container gives it. Returns `target`.
static func wrap(target: Label, width: float, mode := TextServer.AUTOWRAP_WORD_SMART) -> Label:
	target.autowrap_mode = mode
	target.custom_minimum_size.x = width
	return target


## Gives `target` a `size` px text outline in `color`. Returns `target`.
static func outline(target: Label, color: Color, size: int) -> Label:
	target.add_theme_color_override(_FONT_OUTLINE_COLOR, color)
	target.add_theme_constant_override(_OUTLINE_SIZE, size)
	return target


## Returns a new Button showing `text` and `tooltip`, which calls `on_pressed` when
## pressed (when it is a valid Callable). Added to `parent` unless it is null.
static func button(parent: Node, text: String, on_pressed := Callable(), tooltip := '') -> Button:
	var made := Button.new()
	made.text = text
	made.tooltip_text = tooltip
	if on_pressed.is_valid():
		made.pressed.connect(on_pressed)
	if parent != null:
		parent.add_child(made)
	return made


## Returns a new LineEdit (a one-line text field) with `placeholder` hint text and
## `tooltip`, hiding what is typed when `secret` (for passwords). Added to `parent` unless
## it is null.
static func line_edit(parent: Node, placeholder := '', tooltip := '', secret := false) -> LineEdit:
	var made := LineEdit.new()
	made.placeholder_text = placeholder
	made.tooltip_text = tooltip
	made.secret = secret
	if parent != null:
		parent.add_child(made)
	return made


## Returns an empty, click-through Control that expands both ways, pushing its siblings
## in an HBoxContainer or VBoxContainer apart. Added to `parent` when given.
static func spacer(parent: Node = null) -> Control:
	var made := Control.new()
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	made.size_flags_vertical = Control.SIZE_EXPAND_FILL
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(made)
	return made


## Anchors `control` to fill its parent, inset by `left`, `top`, `right` and `bottom` px.
## Returns `control`. Has no effect inside a Container, which lays its children out itself.
static func fill_parent(control: Control, left := 0.0, top := 0.0, right := 0.0, bottom := 0.0) -> Control:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = left
	control.offset_top = top
	control.offset_right = -right
	control.offset_bottom = -bottom
	return control


## Makes a VBoxContainer centred in `parent` (its frame fills `parent`) and returns it.
## `min_width` > 0 sets its minimum width; `separation` ≥ 0 its spacing. With `on_panel` it sits on a
## PanelContainer (styled by `panel_style` when given: `box.get_parent()` is the panel).
## With `scrolls` the frame scrolls vertically when the content is taller than `parent`
## and stays centred when it fits.
static func centered_box(
	parent: Control,
	min_width := 0,
	separation := -1,
	panel_style: StyleBox = null,
	on_panel := true,
	scrolls := false,
) -> VBoxContainer:
	var center := CenterContainer.new()
	if scrolls:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		fill_parent(scroll)
		parent.add_child(scroll)
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(center)
	else:
		fill_parent(center)
		parent.add_child(center)
	var box := VBoxContainer.new()
	if min_width > 0:
		box.custom_minimum_size.x = min_width
	if separation >= 0:
		box.add_theme_constant_override(_SEPARATION, separation)
	if on_panel:
		var panel := PanelContainer.new()
		if panel_style != null:
			panel.add_theme_stylebox_override(_PANEL, panel_style)
		center.add_child(panel)
		panel.add_child(box)
	else:
		center.add_child(box)
	return box


## Makes a PanelContainer (styled by `style` when given) in `parent` holding a VBoxContainer
## whose first child is a `title` label (at `title_size` when > 0). Returns the box, for
## the content; `box.get_parent()` is the panel. `separation` ≥ 0 sets the box spacing.
static func titled_panel(parent: Node, title: String, style: StyleBox = null, title_size := 0, separation := -1) -> VBoxContainer:
	var panel := PanelContainer.new()
	if style != null:
		panel.add_theme_stylebox_override(_PANEL, style)
	if parent != null:
		parent.add_child(panel)
	var box := VBoxContainer.new()
	if separation >= 0:
		box.add_theme_constant_override(_SEPARATION, separation)
	panel.add_child(box)
	label(box, title, null, title_size)
	return box
