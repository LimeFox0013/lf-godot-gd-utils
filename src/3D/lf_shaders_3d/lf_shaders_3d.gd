## Ready-made 3D shader materials: a matte alpha-cut surface whose texture layer comes from each instance.
##
## Each function returns a new `ShaderMaterial` to assign to a mesh's material. All functions are static.
class_name LFShaders3D

## `layered_cutout` parameters.
const PARAM_TEXTURE_ARRAY := &"textureArray"
const PARAM_ALPHA_CUTOFF := &"alphaCutoff"

const DEFAULT_ALPHA_CUTOFF := 0.5

const _LAYERED_CUTOUT := "lf_layered_cutout.gdshader"

static var _log := LFLogger.new(['LFShaders3D'])
static var _shaders: Dictionary = {}


## A matte surface that draws layer `r` of `layers` (a texture array, imported or built), where `r` is the red
## channel of each MultiMesh instance's custom data, and drops pixels whose alpha is below
## `alpha_cutoff` (0 to 1). Pairs with `LFMultiMeshScatter`, which writes that layer number.
static func layered_cutout(layers: TextureLayered, alpha_cutoff := DEFAULT_ALPHA_CUTOFF) -> ShaderMaterial:
	if not is_finite(alpha_cutoff):
		_log.error('a shader parameter must be a finite number, got', alpha_cutoff)
		return null
	var material := _material(_LAYERED_CUTOUT)
	material.set_shader_parameter(PARAM_TEXTURE_ARRAY, layers)
	material.set_shader_parameter(PARAM_ALPHA_CUTOFF, clampf(alpha_cutoff, 0.0, 1.0))
	return material


static func _material(file_name: String) -> ShaderMaterial:
	if not _shaders.has(file_name):
		var folder: String = (LFShaders3D as Script).resource_path.get_base_dir()
		_shaders[file_name] = load(folder.path_join(file_name))
	var material := ShaderMaterial.new()
	material.shader = _shaders[file_name]
	return material
