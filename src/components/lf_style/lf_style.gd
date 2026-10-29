## One-line helpers for StyleBoxes, the backgrounds and borders drawn behind controls.
##
## Make a flat box (fill, border, rounded corners) in one call, an outline-only frame, put
## one style on every visual state of a button, or read a box from the project theme with
## a fallback. Static: call the functions on the class, never `.new()` it.
class_name LFStyle
extends RefCounted

## The button states `set_button_styles` overrides by default: every box the default theme
## gives a Button (a state left out falls back to the theme, e.g. a disabled button turning square).
const BUTTON_STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"disabled", &"focus"]
## Default border width of `outline`, in pixels.
const DEFAULT_OUTLINE_WIDTH := 2


## Returns a new StyleBoxFlat filled with `bg`, with a `border_width` px border in
## `border`, corners rounded by `corner_radius` px and, when `content_margin` is 0 or
## more, that inner padding on every side (below 0 keeps the default, which follows the
## border width). `draw_center` false draws the border only; `anti_aliasing` smooths the
## rounded corners.
static func flat(
	bg: Color,
	border := Color.TRANSPARENT,
	border_width := 0,
	corner_radius := 0,
	content_margin := -1.0,
	draw_center := true,
	anti_aliasing := true,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	if content_margin >= 0.0:
		style.set_content_margin_all(content_margin)
	style.draw_center = draw_center
	style.anti_aliasing = anti_aliasing
	return style


## Returns a new StyleBoxFlat with no fill: a `width` px border in `color`, corners
## rounded by `corner_radius` px. For highlight frames drawn over other content.
static func outline(color: Color, width := DEFAULT_OUTLINE_WIDTH, corner_radius := 0) -> StyleBoxFlat:
	return flat(Color.TRANSPARENT, color, width, corner_radius, -1.0, false)


## Returns a `size` x `size` px texture filled with `color`, e.g. a colour chip beside an
## option's text.
static func swatch(color: Color, size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## Puts `style` on every state in `states` of `control` (a Button, or any Control whose
## theme draws those stylebox names), so it looks the same hovered, pressed, disabled and
## focused. `states` holds Strings or StringNames. The one box is shared, not copied.
static func set_button_styles(control: Control, style: StyleBox, states: Array = BUTTON_STATES) -> void:
	for state: Variant in states:
		control.add_theme_stylebox_override(StringName(state), style)


## Returns the project theme's stylebox `name` of `theme_type` (e.g. `&"panel"`,
## `&"TooltipPanel"`), or `fallback` when there is no project theme (Project Settings >
## GUI > Theme > Custom) or it lacks that box.
static func project_stylebox(name: StringName, theme_type: StringName, fallback: StyleBox = null) -> StyleBox:
	var theme := ThemeDB.get_project_theme()
	if theme != null and theme.has_stylebox(name, theme_type):
		return theme.get_stylebox(name, theme_type)
	return fallback
