## Ready-made 2D shader materials: sprite outline, screen outline, dissolve, darken and cross reveal.
##
## Each function returns a new `ShaderMaterial` to assign to a `CanvasItem.material`. Change
## it later with `material.set_shader_parameter(PARAM_..., value)`. All functions are static.
class_name LFShaders2D

## `sprite_outline` parameters.
const PARAM_OUTLINE_COLOR := &"outline_color"
const PARAM_OUTLINE_WIDTH := &"outline_width"
## `screen_outline` parameters (`outline_color` is shared with `sprite_outline`).
const PARAM_OUTLINE_THICKNESS := &"outline_thickness"
## `dissolve` parameters.
const PARAM_NOISE := &"noise_texture"
const PARAM_AMOUNT := &"amount"
const PARAM_EDGE_COLOR := &"edge_color"
const PARAM_EDGE_WIDTH := &"edge_width"
## `darken` parameter.
const PARAM_DARKNESS := &"darkness"
## `cross_reveal` parameters.
const PARAM_PROGRESS := &"progress"
const PARAM_ARM_HALF_THICKNESS := &"arm_half_thickness"

const DEFAULT_OUTLINE_COLOR := Color(0.0, 1.0, 0.0)
const DEFAULT_OUTLINE_WIDTH := 3.0
const DEFAULT_OUTLINE_THICKNESS := 1
const DEFAULT_EDGE_COLOR := Color(1.0, 0.3, 0.0)
const DEFAULT_EDGE_WIDTH := 0.05
const DEFAULT_DARKNESS := 0.5
const DEFAULT_ARM_HALF_THICKNESS := 0.15

const MAX_OUTLINE_WIDTH := 6.0
const MAX_OUTLINE_THICKNESS := 10
const MAX_EDGE_WIDTH := 0.1
const MAX_ARM_HALF_THICKNESS := 0.5

const _SPRITE_OUTLINE := "lf_sprite_outline.gdshader"
const _SCREEN_OUTLINE := "lf_screen_outline.gdshader"
const _DISSOLVE := "lf_dissolve.gdshader"
const _DARKEN := "lf_darken.gdshader"
const _CROSS_REVEAL := "lf_cross_reveal.gdshader"

static var _log := LFLogger.new(['LFShaders2D'])
static var _shaders: Dictionary = {}


## Outlines the opaque part of the item's own texture, `width` texture pixels wide (0 to 6).
static func sprite_outline(color := DEFAULT_OUTLINE_COLOR, width := DEFAULT_OUTLINE_WIDTH) -> ShaderMaterial:
	if not _finite([color.r, color.g, color.b, color.a, width]):
		return null
	var material := _material(_SPRITE_OUTLINE)
	material.set_shader_parameter(PARAM_OUTLINE_COLOR, color)
	material.set_shader_parameter(PARAM_OUTLINE_WIDTH, clampf(width, 0.0, MAX_OUTLINE_WIDTH))
	return material


## Outlines what is drawn behind the item, `thickness` screen pixels wide (0 to 10). Reads the
## screen once per pixel in the outline's square, so keep it thin.
static func screen_outline(color := DEFAULT_OUTLINE_COLOR, thickness := DEFAULT_OUTLINE_THICKNESS) -> ShaderMaterial:
	if not _finite([color.r, color.g, color.b, color.a]):
		return null
	var material := _material(_SCREEN_OUTLINE)
	material.set_shader_parameter(PARAM_OUTLINE_COLOR, Vector3(color.r, color.g, color.b))
	material.set_shader_parameter(PARAM_OUTLINE_THICKNESS, clampi(thickness, 0, MAX_OUTLINE_THICKNESS))
	return material


## Makes the item burn away along `noise` (a noise texture; its red channel is read).
## `amount` 0 is intact, 1 is gone; animate it with `material.set_shader_parameter(PARAM_AMOUNT, ...)`.
static func dissolve(noise: Texture2D, amount := 0.0, edge_color := DEFAULT_EDGE_COLOR, edge_width := DEFAULT_EDGE_WIDTH) -> ShaderMaterial:
	if not _finite([amount, edge_width, edge_color.r, edge_color.g, edge_color.b, edge_color.a]):
		return null
	var material := _material(_DISSOLVE)
	material.set_shader_parameter(PARAM_NOISE, noise)
	material.set_shader_parameter(PARAM_AMOUNT, clampf(amount, 0.0, 1.0))
	material.set_shader_parameter(PARAM_EDGE_COLOR, edge_color)
	material.set_shader_parameter(PARAM_EDGE_WIDTH, clampf(edge_width, 0.0, MAX_EDGE_WIDTH))
	return material


## Dims the item: 0 is unchanged, 1 is black.
static func darken(darkness := DEFAULT_DARKNESS) -> ShaderMaterial:
	if not _finite([darkness]):
		return null
	var material := _material(_DARKEN)
	material.set_shader_parameter(PARAM_DARKNESS, clampf(darkness, 0.0, 1.0))
	return material


## Shows the item only inside a plus-shaped cut-out whose arms grow with `progress` (0 hidden,
## 1 the arms reach the edges); `arm_half_thickness` is in UV units (0 to 0.5).
static func cross_reveal(progress := 0.0, arm_half_thickness := DEFAULT_ARM_HALF_THICKNESS) -> ShaderMaterial:
	if not _finite([progress, arm_half_thickness]):
		return null
	var material := _material(_CROSS_REVEAL)
	material.set_shader_parameter(PARAM_PROGRESS, clampf(progress, 0.0, 1.0))
	material.set_shader_parameter(PARAM_ARM_HALF_THICKNESS, clampf(arm_half_thickness, 0.0, MAX_ARM_HALF_THICKNESS))
	return material


static func _material(file_name: String) -> ShaderMaterial:
	if not _shaders.has(file_name):
		var folder: String = (LFShaders2D as Script).resource_path.get_base_dir()
		_shaders[file_name] = load(folder.path_join(file_name))
	var material := ShaderMaterial.new()
	material.shader = _shaders[file_name]
	return material


static func _finite(numbers: Array) -> bool:
	for number: float in numbers:
		if not is_finite(number):
			_log.error('a shader parameter must be a finite number, got', number)
			return false
	return true
