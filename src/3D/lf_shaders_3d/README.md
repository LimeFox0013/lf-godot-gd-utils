# LFShaders3D

> Ready-made 3D shader materials: today a matte alpha-cut surface that shows a different texture layer on each MultiMesh copy.

| | |
|---|---|
| **Files** | `lf_shaders_3d.gd`, `lf_layered_cutout.gdshader` |
| **Tests** | `tests/test_lf_shaders_3d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFShaders3D` | Static: call its functions on the class name |

## When to use it

For grass, flowers or pebbles scattered with `LFMultiMeshScatter`: the scatter gives every copy
a layer number, and this material draws that layer of a texture array, dropping see-through
pixels. Pixels are lit, with no shine.

## Step by step

1. Import your pictures as one texture array (a `Texture2DArray` or an imported `CompressedTexture2DArray`).
2. Build the material and give it to the mesh your `LFMultiMeshScatter` repeats:
   `mesh.material = LFShaders3D.layered_cutout(my_texture_array)`
3. Set the scatter's `layer_count` to the number of layers in the array.

## API

| Function | What it does |
|---|---|
| `static layered_cutout(layers, alpha_cutoff) -> ShaderMaterial` | Draws layer `r` of `layers`, `r` being the red channel of each instance's custom data; drops pixels with alpha below `alpha_cutoff` (0 to 1, default 0.5). Returns null, with an error through `LFLogger`, for a NaN or infinite cutoff. |

`PARAM_TEXTURE_ARRAY` and `PARAM_ALPHA_CUTOFF` name the shader parameters (`textureArray`, `alphaCutoff`);
`DEFAULT_ALPHA_CUTOFF` is the default.

## Notes

- Materials made by the same function share one compiled shader; their parameters are separate.
- Without per-instance custom data (a plain mesh), every pixel reads layer 0.
