# LFShaders2D

> Ready-made 2D shader materials: an outline around a sprite, an outline around what is drawn behind it, a burn-away dissolve, a darken and a growing plus-shaped reveal.

| | |
|---|---|
| **Files** | `lf_shaders_2d.gd`, `lf_sprite_outline.gdshader`, `lf_screen_outline.gdshader`, `lf_dissolve.gdshader`, `lf_darken.gdshader`, `lf_cross_reveal.gdshader` |
| **Tests** | `tests/test_lf_shaders_2d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFShaders2D` | Static: call its functions on the class name |

## When to use it

To highlight a selected unit, burn an enemy away when it dies, or dim a sprite, without
writing a shader. Each function returns a `ShaderMaterial`; assign it to any `Sprite2D`,
`TextureRect` or other `CanvasItem`.

## Step by step

1. Pick the effect and build the material, for example in `_ready`:
   `$Sprite2D.material = LFShaders2D.sprite_outline(Color.YELLOW, 2.0)`
2. To change it later: `$Sprite2D.material.set_shader_parameter(LFShaders2D.PARAM_OUTLINE_WIDTH, 0.0)`
3. To burn something away, give it a dissolve material (`noise` is a `NoiseTexture2D`) and animate `amount` from 0 to 1 with a tween:
   `$Sprite2D.material = LFShaders2D.dissolve(noise)`
   `create_tween().tween_property($Sprite2D.material, "shader_parameter/amount", 1.0, 1.5)`

## API

| Function | What it does |
|---|---|
| `static sprite_outline(color, width) -> ShaderMaterial` | Outlines the opaque part of the item's own texture; `width` 0 to 6 texture pixels. |
| `static screen_outline(color, thickness) -> ShaderMaterial` | Outlines what is drawn behind the item; `thickness` 0 to 10 screen pixels. |
| `static dissolve(noise, amount, edge_color, edge_width) -> ShaderMaterial` | Burns the item away along a noise texture; `amount` 0 is intact, 1 is gone. |
| `static darken(darkness) -> ShaderMaterial` | Dims the item; 0 is unchanged, 1 is black. |
| `static cross_reveal(progress, arm_half_thickness) -> ShaderMaterial` | Shows the item only inside a plus whose arms grow with `progress` (0 hidden, 1 reaching the edges); `arm_half_thickness` 0 to 0.5 UV. |

Each returns null, with an error through `LFLogger`, for a NaN or infinite number. Numbers outside
a shader's range are clamped. The `PARAM_*` and `DEFAULT_*` constants name every parameter and default.

## See also

- [`LFPixelDraw`](../lf_pixel_draw/README.md) to make the art these materials restyle.

## Notes

- `screen_outline` reads the screen texture `(2 * thickness + 1)` squared times per pixel: keep it thin and use it on few items.
- Materials made by the same function share one compiled shader; their parameters are separate.
