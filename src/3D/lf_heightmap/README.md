# LFHeightmap

> Heightmap terrain from a square height lattice: sample a height function onto the lattice, build a slope-shaded mesh (flat colour on level ground, steep colour on cliffs, one material) and a static body with a matching `HeightMapShape3D` collider.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_heightmap.gd` |
| **Tests** | `tests/test_lf_heightmap.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` (reports unusable arguments) |

## When to use it

Use it when your 3D level needs hills, ramps or plateaus that units can walk on and that
you describe in code: write one function "how high is the ground at (x, z)?", and get a
coloured ground mesh plus a collider (the invisible shape physics uses, so units can stand on it) whose samples sit on the mesh's vertices, in a few lines. Grass on flat
ground and rock on cliffs comes from the slope colouring, with no textures or
shaders. For hand-sculpted terrain painted in the editor use a terrain plugin (such as
Terrain3D) instead; for flat ground a `PlaneMesh` and a `BoxShape3D` are simpler.

## Step by step

This builds a small rolling landscape you can see from above.

1. Choose *Scene → New Scene* and click **3D Scene** under "Create Root Node". Rename the
   root `World`.
2. Select `World`, click **+ Add Child Node**, search `DirectionalLight3D` and press
   *Create* (the sun; without a light the ground renders black). In the Inspector open
   *Transform* and set *Rotation* to `-50, 30, 0` (degrees) so it shines down at an angle.
3. Add another child, a `Camera3D`. Set its *Transform → Position* to `0, 22, 32` and its
   *Rotation* to `-35, 0, 0`, so it looks down at the middle of the terrain.
4. Select `World` and click **Attach Script** (above the Scene dock), then *Create*.
   Replace the contents with:

   ```gdscript
   extends Node3D

   const HALF := 20.0    # the terrain covers -20..20 on X and Z (world units)
   const SPACING := 1.0  # one height sample per world unit


   func _ready() -> void:
   	# 1. Ask "how high is the ground?" at every point. This fills the lattice
   	#    (the grid of heights) using the height_at function below.
   	var data := LFHeightmap.lattice(height_at, HALF, SPACING)
   	# 2. How many samples one side of the lattice has.
   	var samples := LFHeightmap.samples_for(HALF, SPACING)
   	# 3. Build the ground: green on flat parts, brown on steep parts, with collision.
   	var ground := LFHeightmap.build_body(data, samples, SPACING, HALF, Color(0.25, 0.45, 0.25), Color(0.42, 0.36, 0.3))
   	add_child(ground)


   # Your terrain shape: given a point (x, z) on the ground, return its height.
   # Here, gentle waves up to 2 units high.
   func height_at(x: float, z: float) -> float:
   	return sin(x * 0.3) * cos(z * 0.3) * 2.0
   ```
5. Press **F6** (*Run Current Scene*) and save when asked. You should see a square of
   green hills with brown on the steepest slopes.
6. Change `height_at` to shape your own ground (it receives world X and Z and returns
   a height in world units). `HALF` sets the size, `SPACING` the detail: smaller is
   smoother but builds slower. The ground already has a collider, so a `CharacterBody3D`
   or `RigidBody3D` placed above it will land on it.

## The lattice

A lattice is a `PackedFloat32Array` of heights over the square [-half_extent, half_extent] on X and Z, sampled `spacing` apart, row-major: the height at `(x, z) = (-half_extent + ix * spacing, -half_extent + iz * spacing)` is `data[iz * samples + ix]`, with `samples = samples_for(half_extent, spacing)` per side. Pick `spacing` so that `2 * half_extent` is a whole multiple of it (60 and 1, 60 and 2.5): then the last sample lands exactly on +half_extent and the body and mesh are centred on their origin. Otherwise the lattice still starts at -half_extent but ends up to half a `spacing` short of or past +half_extent (the collider's samples still sit on the mesh's vertices). `LFFlowField.climbable_masks` reads the same layout, so one lattice feeds the collider, the mesh and the pathfinding's slope limits.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_STEEP_SLOPE` | `const DEFAULT_STEEP_SLOPE := 1.2` | Slope (rise over run) at which a vertex takes the full steep colour. |
| `DEFAULT_COLLISION_LAYER` | `const DEFAULT_COLLISION_LAYER := 1` | Default `collision_layer` of `build_body` (a layer bitmask: layer 1). |
| `COLLISION_NODE_NAME` | `const COLLISION_NODE_NAME := "Collision"` | Name of `build_body`'s CollisionShape3D child. |
| `MESH_NODE_NAME` | `const MESH_NODE_NAME := "Mesh"` | Name of `build_body`'s MeshInstance3D child. |
| `samples_for` | `static samples_for(half_extent: float, spacing: float) -> int` | `round(2 * half_extent / spacing) + 1`: samples per side, both edges included. 0 (reported) for a bad `spacing` or `half_extent`. |
| `lattice` | `static lattice(height_fn: Callable, half_extent: float, spacing: float, bounds: Array[Rect2] = []) -> PackedFloat32Array` | `height_fn.call(x, z) -> float` at every sample. With `bounds` (XZ rects, z as `y`) only the samples inside some rect (widened to the enclosing samples) are evaluated; the rest stay 0. |
| `slope_at` | `static slope_at(data: PackedFloat32Array, samples: int, spacing: float, ix: int, iz: int) -> float` | Rise over run at a sample (1.0 = 45°) from central differences (one-sided at the edges). |
| `build_mesh` | `static build_mesh(data: PackedFloat32Array, samples: int, spacing: float, half_extent: float, flat_color: Color, steep_color: Color, steep_slope := DEFAULT_STEEP_SLOPE) -> ArrayMesh` | One quad per cell, facing up, vertex colours from `flat_color` to `steep_color` by slope. Needs a material that uses vertex colour as albedo. |
| `build_body` | `static build_body(data: PackedFloat32Array, samples: int, spacing: float, half_extent: float, flat_color: Color, steep_color: Color, collision_layer := DEFAULT_COLLISION_LAYER, steep_slope := DEFAULT_STEEP_SLOPE) -> StaticBody3D` (layer 1) | A body on `collision_layer` (mask 0) with a `Collision` (`COLLISION_NODE_NAME`) child (`HeightMapShape3D`, scaled by `spacing` on X/Z when it is not 1) and a `Mesh` (`MESH_NODE_NAME`) child (`build_mesh` with a vertex-colour material). |

## Usage

A more advanced version: a single hill, sampling only the square around it (the rest
stays flat at height 0). A script on the level's root `Node3D`:

```gdscript
extends Node3D

const HALF := 60.0    # the terrain spans -60..60 on X and Z
const SPACING := 1.0  # one height sample per unit


func _ready() -> void:
	# Only the hill's square needs sampling; the rest of the ground stays at height 0.
	var hills: Array[Rect2] = [Rect2(-12, -12, 24, 24)]
	var data := LFHeightmap.lattice(height_at, HALF, SPACING, hills)
	var samples := LFHeightmap.samples_for(HALF, SPACING)
	# Green on flat ground, brown on slopes; collision layer 1.
	var ground := LFHeightmap.build_body(data, samples, SPACING, HALF, Color(0.25, 0.45, 0.25), Color(0.42, 0.36, 0.3))
	add_child(ground)


# A round hill 3 units high: a flat top 8 units across, sloping down to 20 units across.
func height_at(x: float, z: float) -> float:
	var from_centre := Vector2(x, z).length()
	return clampf((10.0 - from_centre) * 0.5, 0.0, 3.0)
```

The same `data` can feed pathfinding: `LFFlowField.climbable_masks(data, SPACING, HALF, 2.0, 45.0)`.

## Notes

- Choose `spacing` with the slope limit in mind: with one sample per unit, a 3-unit step becomes a ~72° face (too steep for a `CharacterBody3D`'s default 45° floor), while a 12-unit ramp to the same height is a gentle ~14°.
- `bounds` is only an optimisation for terrain that is flat outside a few features; `height_fn` must still answer 0 for flat ground inside a rect.
- `spacing` must be finite and greater than 0 and `half_extent` finite and not negative: otherwise `samples_for` reports it and returns 0, and `lattice` returns an empty array. `build_mesh` and `build_body` report a lattice they cannot read (fewer than 2 samples per side, `data` not holding `samples * samples` heights, or a `steep_slope` that is not finite and above 0) and give an empty mesh / a body with no children. `slope_at` checks nothing: `ix` and `iz` must lie in 0..samples-1 and `data` must hold `samples * samples` heights, or it fails with an out-of-bounds script error. The sample count is not capped: a tiny `spacing` over a large `half_extent` allocates accordingly.
- `HeightMapShape3D` places its samples one unit apart, so a different `spacing` is applied by scaling the collision shape on X and Z; some physics engines warn about non-uniform shape scale.
- The collider's samples sit exactly on the mesh's vertices. Each lattice square is two triangles in both, but the mesh splits it along the diagonal from (ix + 1, iz) to (ix, iz + 1), and the physics engine may split it along the other one, so on a square whose four corners are not in one plane the collider can sit a little above or below the drawn surface between vertices.
- The mesh is built with `SurfaceTool` and `generate_normals`; vertex colours are stored at 8 bits per channel. Building happens right where you call it and the game waits: a 241 × 241 lattice is about 58 000 vertices, so build large terrain once, at load time.
