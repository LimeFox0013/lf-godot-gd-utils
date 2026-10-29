# LFPixelDraw

> Pixel art drawn from code: rectangles, discs, lines, frames, ASCII sprites and bitmap text, made of `ColorRect`s or baked to one texture.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it as `LFPixelDraw.pattern(...)` |
| **Files** | `lf_pixel_draw.gd` |
| **Tests** | `tests/test_lf_pixel_draw.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | nothing |

## When to use it

Use it when a game has no art files yet, or on purpose draws everything from coloured squares: a prototype, a game
jam entry, a pixel-art arcade game. Every drawing function takes its parent first and returns what it made, so you keep
the node to move, recolour or free it.

Two ways to draw a sprite:

- `pattern` makes one `ColorRect` per run of same-coloured pixels. Use it when the pieces must stay separate nodes
  (a bird whose wing you move, a block you break).
- `sprite` bakes the same pattern into one `ImageTexture` on one `Sprite2D`. Use it for art that never breaks apart and
  that you want to scale or flip cheaply.

## Step by step

1. Add a `Node2D` to your scene, attach a script and replace its text with the code below.
2. Press **F6**. A grey-lavender ghost (rectangles), a cream ghost (one baked sprite), a red disc, a yellow frame, an orange diagonal line and the word `HELLO 42` appear on a dark background.

```gdscript
extends Node2D

const GHOST := [
	"..XXXX..",
	".XXXXXX.",
	"XXXXXXXX",
	"XX.XX.XX",
	"XXXXXXXX",
	"XX.XX.XX",
]


func _ready() -> void:
	LFPixelDraw.rect(self, 0, 0, 400, 300, Color("171526"))
	LFPixelDraw.pattern(self, GHOST, {"X": Color("c4c0dc")}, 6.0, Vector2(30, 30))
	LFPixelDraw.sprite(self, GHOST, Color("f6dfba"), 6.0, Vector2(120, 30))
	LFPixelDraw.disc(self, 260, 60, 28, Color("aa3f54"), 4.0)
	LFPixelDraw.outline(self, 20, 120, 360, 60, Color("f7c554"), 3.0)
	LFPixelDraw.line(self, Vector2(30, 260), Vector2(370, 200), Color("e79843"), 4.0)
	LFPixelDraw.text(self, "HELLO 42", 40, 135, 5.0, Color("f6dfba"))
```

## API

| Member | Signature | Description |
|---|---|---|
| `rect` | `static rect(parent, x, y, w, h, color) -> ColorRect` | A rectangle that ignores the mouse. A null parent leaves it unattached. |
| `disc` | `static disc(parent, cx, cy, radius, color, step := 1.0) -> Node2D` | A filled disc as horizontal strips `step` tall. The holder sits at the centre. |
| `line` | `static line(parent, from, to, color, pixel := 1.0) -> Node2D` | A stepped line of `pixel` squares on the `pixel` grid. |
| `outline` | `static outline(parent, x, y, w, h, color, thickness := 1.0) -> Node2D` | A hollow frame of four strips. The holder sits at (`x`, `y`). |
| `pattern` | `static pattern(parent, rows, palette, pixel := 1.0, at := Vector2.ZERO) -> Node2D` | An ASCII sprite as rectangles. `palette` is a Dictionary of character to `Color`, or one `Color` for `X`. Characters not in the palette draw nothing. |
| `pattern_size` | `static pattern_size(rows) -> Vector2i` | Longest row by row count, in art pixels. |
| `pattern_texture` | `static pattern_texture(rows, palette) -> ImageTexture` | The pattern baked to a texture, one image pixel per art pixel. |
| `sprite` | `static sprite(parent, rows, palette, pixel := 1.0, at := Vector2.ZERO) -> Sprite2D` | The baked texture on one nearest-filtered `Sprite2D`, scaled by `pixel`. |
| `text` | `static text(parent, content, x, y, pixel, color) -> Node2D` | Bitmap text; capitals and lowercase look the same, `\n` starts a lower line, an unknown character draws `?`. |
| `text_width` | `static text_width(content, pixel) -> float` | Width from the origin to the right edge of the rightmost pixel `text` draws, over all lines. Leading spaces count; trailing spaces and the last gap do not; no ink (empty or only spaces) is 0. |
| `glyph_rows` | `static glyph_rows(character) -> Array` | The five rows of a glyph (`?` when missing). |
| `FONT` | `Dictionary` | Character to five rows of `0`/`1`. Letters, digits and `. , : ! ? - + = / ( ) ' % _ * #`. |

## See also

- [`LFSpriteAtlasFrames`](../../3D/lf_directional_sprite/README.md) for finished art cut from an atlas instead of drawn from code.
- [`LFShaders2D`](../lf_shaders_2d/README.md) to outline, dissolve or darken what you drew.
- [`LFAnimate`](../../utils/lf_animate/README.md) (`one_shot`) to tween and free a drawn piece, such as debris.
- [`LFFactory`](../../utils/lf_factory/README.md) to pool drawn pieces that are made and freed often.

## Notes

- The font is small and plain on purpose (3 wide, 5 tall; `M` and `W` are 5 wide, `N` is 4). Use a real font for long text.
- Pixel positions are in the parent's units. For crisp art in a small window, set the project's stretch mode to
  `viewport` and draw at the small size, or pass a `pixel` above 1.
- `pattern` rows may differ in length; a short row is just shorter.
- Merging runs keeps a 16x16 sprite to a few dozen nodes, but a screen of hundreds of such sprites should use `sprite`.
