## Pixel art drawn from code: rectangles, discs, lines, frames, ASCII sprites and bitmap text, built from `ColorRect`s or baked to one texture.
##
## Every drawing function takes its parent first and returns what it made. `rect` returns the `ColorRect`; the others
## return a `Node2D` holder that contains the pieces, so one `queue_free()` removes a whole sprite or word. Sizes and
## positions are in the parent's units, and `pixel` is the edge of one art pixel in those units.
##
## `pattern` and `text` merge neighbouring pixels of one colour in a row into a single rectangle, so a sprite costs far
## fewer nodes than it has pixels. `pattern_texture` and `sprite` bake a pattern into one `ImageTexture` instead, for art
## that never breaks apart.
class_name LFPixelDraw
extends RefCounted

## The glyph drawn for a character the font does not have.
const UNKNOWN_GLYPH := "?"
## Height of every glyph, in art pixels.
const GLYPH_HEIGHT := 5
## Blank art pixels between two glyphs.
const GLYPH_GAP := 1
## Blank art pixels a space takes.
const SPACE_WIDTH := 3

## The 5-row bitmap font: `1` is a pixel. Letters (shown in capitals), digits and `. , : ! ? - + = / ( ) ' % _ * #`.
const FONT := {
	"A": ["010", "101", "111", "101", "101"],
	"B": ["110", "101", "110", "101", "110"],
	"C": ["011", "100", "100", "100", "011"],
	"D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "110", "100", "111"],
	"F": ["111", "100", "110", "100", "100"],
	"G": ["011", "100", "101", "101", "011"],
	"H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"],
	"J": ["001", "001", "001", "101", "010"],
	"K": ["101", "101", "110", "101", "101"],
	"L": ["100", "100", "100", "100", "111"],
	"M": ["10001", "11011", "10101", "10001", "10001"],
	"N": ["1001", "1101", "1011", "1001", "1001"],
	"O": ["010", "101", "101", "101", "010"],
	"P": ["110", "101", "110", "100", "100"],
	"Q": ["010", "101", "101", "111", "011"],
	"R": ["110", "101", "110", "101", "101"],
	"S": ["011", "100", "010", "001", "110"],
	"T": ["111", "010", "010", "010", "010"],
	"U": ["101", "101", "101", "101", "111"],
	"V": ["101", "101", "101", "101", "010"],
	"W": ["10001", "10001", "10101", "11011", "10001"],
	"X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "010", "010", "010"],
	"Z": ["111", "001", "010", "100", "111"],
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["110", "001", "010", "100", "111"],
	"3": ["110", "001", "010", "001", "110"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "110", "001", "110"],
	"6": ["011", "100", "111", "101", "111"],
	"7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "110"],
	".": ["0", "0", "0", "0", "1"],
	",": ["0", "0", "0", "1", "1"],
	":": ["0", "1", "0", "1", "0"],
	"!": ["1", "1", "1", "0", "1"],
	"?": ["110", "001", "010", "000", "010"],
	"-": ["000", "000", "111", "000", "000"],
	"+": ["000", "010", "111", "010", "000"],
	"=": ["000", "111", "000", "111", "000"],
	"/": ["001", "001", "010", "100", "100"],
	"(": ["01", "10", "10", "10", "01"],
	")": ["10", "01", "01", "01", "10"],
	"'": ["1", "1", "0", "0", "0"],
	"%": ["101", "001", "010", "100", "101"],
	"_": ["000", "000", "000", "000", "111"],
	"*": ["000", "101", "010", "101", "000"],
	"#": ["101", "111", "101", "111", "101"],
}


## A `ColorRect` at (`x`, `y`) of size (`w`, `h`) and `color`, added to `parent`. It ignores the mouse. A null parent
## leaves it unattached.
static func rect(parent: Node, x: float, y: float, w: float, h: float, color: Color) -> ColorRect:
	var block := ColorRect.new()
	block.position = Vector2(x, y)
	block.size = Vector2(w, h)
	block.color = color
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(block)
	return block


## A filled disc of `radius` centred on (`cx`, `cy`), drawn as horizontal strips `step` tall (the art pixel). Returns the
## holder, placed at the centre, whose children are the strips. Nothing is drawn for a radius or step of zero or less.
static func disc(parent: Node, cx: float, cy: float, radius: float, color: Color, step := 1.0) -> Node2D:
	var holder := _holder(parent, Vector2(cx, cy))
	if radius <= 0.0 or step <= 0.0:
		return holder
	var y := -radius
	while y < radius:
		var dy := y + step / 2.0
		var half := floorf(sqrt(maxf(radius * radius - dy * dy, 0.0)) / step) * step
		if half > 0.0:
			rect(holder, -half, y, half * 2.0, step, color)
		y += step
	return holder


## A one-pixel-thick line from `from` to `to`, made of squares of `pixel` on the grid of `pixel` (Bresenham). Returns the
## holder. A `pixel` of zero or less draws nothing.
static func line(parent: Node, from: Vector2, to: Vector2, color: Color, pixel := 1.0) -> Node2D:
	var holder := _holder(parent, Vector2.ZERO)
	if pixel <= 0.0:
		return holder
	var a := Vector2i((from / pixel).round())
	var b := Vector2i((to / pixel).round())
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	while true:
		rect(holder, a.x * pixel, a.y * pixel, pixel, pixel, color)
		if a == b:
			break
		var doubled := 2 * err
		if doubled >= dy:
			err += dy
			a.x += sx
		if doubled <= dx:
			err += dx
			a.y += sy
	return holder


## A hollow frame of four strips, `thickness` wide, around the box (`x`, `y`, `w`, `h`). Returns the holder at (`x`, `y`).
## A thickness that would cover the box makes it solid.
static func outline(parent: Node, x: float, y: float, w: float, h: float, color: Color, thickness := 1.0) -> Node2D:
	var holder := _holder(parent, Vector2(x, y))
	var t := minf(maxf(thickness, 0.0), minf(w, h) / 2.0)
	if t <= 0.0 or w <= 0.0 or h <= 0.0:
		return holder
	rect(holder, 0, 0, w, t, color)
	rect(holder, 0, h - t, w, t, color)
	rect(holder, 0, t, t, h - 2.0 * t, color)
	rect(holder, w - t, t, t, h - 2.0 * t, color)
	return holder


## An ASCII sprite as rectangles. `rows` is an array of equal-or-shorter strings; each character picks a colour from
## `palette` (a Dictionary of character to `Color`, or one `Color` that `X` draws). A character the palette lacks (by
## habit `.` or a space) draws nothing. Each art pixel is `pixel` wide; the holder sits at `at`. Neighbouring pixels of one
## colour in a row become one rectangle.
static func pattern(parent: Node, rows: Array, palette, pixel := 1.0, at := Vector2.ZERO) -> Node2D:
	var holder := _holder(parent, at)
	if pixel <= 0.0:
		return holder
	var colors := _palette(palette)
	for row_index in rows.size():
		var row := String(rows[row_index])
		var col := 0
		while col < row.length():
			var key := row[col]
			if not colors.has(key):
				col += 1
				continue
			var end := col + 1
			while end < row.length() and row[end] == key:
				end += 1
			rect(holder, col * pixel, row_index * pixel, (end - col) * pixel, pixel, colors[key])
			col = end
	return holder


## The size of a pattern in art pixels: its longest row by its row count.
static func pattern_size(rows: Array) -> Vector2i:
	var width := 0
	for row in rows:
		width = maxi(width, String(row).length())
	return Vector2i(width, rows.size())


## A pattern baked to an `ImageTexture`, one image pixel per art pixel (a 1x1 image for an empty pattern). Palette rules
## are those of `pattern`; undrawn pixels are transparent.
static func pattern_texture(rows: Array, palette) -> ImageTexture:
	var size := pattern_size(rows)
	var image := Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	var colors := _palette(palette)
	for row_index in rows.size():
		var row := String(rows[row_index])
		for col in row.length():
			if colors.has(row[col]):
				image.set_pixel(col, row_index, colors[row[col]])
	return ImageTexture.create_from_image(image)


## A pattern as one `Sprite2D`: the baked texture, nearest-filtered, scaled by `pixel`, with its corner at `at`. Use it
## for art that never breaks apart; use `pattern` when the pieces must be separate nodes.
static func sprite(parent: Node, rows: Array, palette, pixel := 1.0, at := Vector2.ZERO) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture = pattern_texture(rows, palette)
	node.centered = false
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.scale = Vector2(pixel, pixel)
	node.position = at
	if parent != null:
		parent.add_child(node)
	return node


## `text` in the bitmap font (upper and lower case look the same), the first glyph's top-left corner at (`x`, `y`), each
## art pixel `pixel` wide. A character the font lacks draws `?`; a newline starts a line one glyph plus one pixel lower.
## Returns the holder at (`x`, `y`).
static func text(parent: Node, content: String, x: float, y: float, pixel: float, color: Color) -> Node2D:
	var holder := _holder(parent, Vector2(x, y))
	if pixel <= 0.0:
		return holder
	var line_index := 0
	for line_text in content.split("\n"):
		var cursor := 0
		for character in line_text.to_upper():
			if character == " ":
				cursor += SPACE_WIDTH
				continue
			var glyph: Array = glyph_rows(character)
			for glyph_row in GLYPH_HEIGHT:
				var bits := String(glyph[glyph_row])
				var col := 0
				while col < bits.length():
					if bits[col] != "1":
						col += 1
						continue
					var end := col + 1
					while end < bits.length() and bits[end] == "1":
						end += 1
					rect(holder, (cursor + col) * pixel, (line_index * (GLYPH_HEIGHT + 1) + glyph_row) * pixel, (end - col) * pixel, pixel, color)
					col = end
			cursor += String(glyph[0]).length() + GLYPH_GAP
		line_index += 1
	return holder


## The width `text` takes in the widest line, in the parent's units: from the drawing origin to the right edge of the
## rightmost pixel drawn. Leading spaces count; trailing spaces and the gap after the last glyph do not; a line with no
## ink (empty or only spaces) is 0.
static func text_width(content: String, pixel: float) -> float:
	if pixel <= 0.0:
		return 0.0
	var widest := 0
	for line_text in content.split("\n"):
		var cursor := 0
		for character in line_text.to_upper():
			if character == " ":
				cursor += SPACE_WIDTH
				continue
			var glyph: Array = glyph_rows(character)
			for glyph_row in GLYPH_HEIGHT:
				var bits := String(glyph[glyph_row])
				widest = maxi(widest, cursor + bits.rfind("1") + 1 if bits.contains("1") else 0)
			cursor += String(glyph[0]).length() + GLYPH_GAP
	return widest * pixel


## The rows of the glyph for `character`, or those of `UNKNOWN_GLYPH` when the font lacks it.
static func glyph_rows(character: String) -> Array:
	return FONT.get(character.to_upper(), FONT[UNKNOWN_GLYPH])


static func _holder(parent: Node, at: Vector2) -> Node2D:
	var holder := Node2D.new()
	holder.position = at
	if parent != null:
		parent.add_child(holder)
	return holder


## Character to Color; a lone Color stands for `X`.
static func _palette(palette) -> Dictionary:
	if palette is Color:
		return {"X": palette}
	if palette is Dictionary:
		return palette
	return {}
