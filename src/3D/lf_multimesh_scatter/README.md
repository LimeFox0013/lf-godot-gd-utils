# LFMultiMeshScatter

> Fills a MultiMeshInstance3D with many copies of its mesh, scattered at random over a flat area: grass, pebbles, flowers.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene (it extends `MultiMeshInstance3D`) |
| **Files** | `lf_multimesh_scatter.gd` |
| **Tests** | `tests/test_lf_multimesh_scatter.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it to cover ground with lots of small identical things cheaply (a `MultiMesh` draws them
all in one call): a meadow, scattered rocks, debris. It picks random spots over an area you
mark with a flat mesh, an optional random size, and a random "layer" number per copy that a
shader can use to pick between several looks. For terrain itself see `LFHeightmap`.

## Step by step

1. In the editor choose *Scene → New Scene*, click **3D Scene** (root `Node3D`).
2. Add a child **MeshInstance3D** (the area). In the Inspector set *Mesh* to *New PlaneMesh*,
   click it and set *Size* to `20, 20`. Rename it `Ground`.
3. Add another child **MultiMeshInstance3D**. In the Inspector set *Multimesh* to *New MultiMesh*,
   click it and set *Mesh* to *New BoxMesh* (or any mesh); open the BoxMesh and set *Size* to `0.1, 0.5, 0.1`.
   Right-click *Multimesh* and choose *Make Unique* so it belongs to this node alone.
4. With this node selected, open the Inspector's *Script* property, choose *Load* and pick
   `lf_multimesh_scatter.gd` (in the FileSystem dock, under the library folder in `src/3D/lf_multimesh_scatter`).
5. In the Inspector set *Area* to `Ground` (click *Assign…*), *Density* to `2`.
6. Add a **Camera3D**, move it up and back, press **F6**: about 800 thin boxes cover the plane.

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_DENSITY`, `DEFAULT_LAYER_COUNT`, `UNSEEDED` | `const …` | `1.0`, `1`, `0`. |
| `area` | `@export var area: MeshInstance3D` | Marks the area: a `PlaneMesh` by its size, any other mesh by the width and depth of its bounds. |
| `density` | `@export var density := 1.0` | Instances per square unit (at least one is placed). |
| `scale_range` | `@export var scale_range := Vector2.ONE` | Smallest and largest size of a copy. |
| `shift_y` | `@export var shift_y := 0.0` | Height above the area's surface. |
| `layer_count` | `@export var layer_count := 1` | Number of looks; each copy gets `0..layer_count-1` in its custom data's red channel. At least 1. |
| `random_seed` | `@export var random_seed := 0` | 0: different every run; otherwise repeatable. |
| `scatter_on_ready` | `@export var scatter_on_ready := true` | Scatter when the node is ready. |
| `scattered` | `signal scattered(count: int)` | After `scatter`. |
| `scatter` | `scatter() -> int` | Places the instances (replacing earlier ones); returns the count, or 0 with an error for a missing area, mesh or multimesh. |
| `place` | `static place(size: Vector2, count: int, rng: RandomNumberGenerator, into_space := Transform3D.IDENTITY, height := 0.0, size_range := Vector2.ONE, layer_total := 1) -> Placement` | The placement as plain data (`Placement.transforms`, `Placement.layers`), without a node. |
| `plane_size_xz` | `static plane_size_xz(mesh_instance: MeshInstance3D) -> Vector2` | Width (x) and depth (y) of the mesh; zero for none. |
| `Placement` | `class Placement` | Result of `place`: `transforms: Array[Transform3D]` and `layers: PackedInt32Array`. |

## Usage

Read the layer in a shader to pick a texture from an array (custom data arrives as `INSTANCE_CUSTOM`):

```gdscript
# A grass patch that scatters 6 instances per square unit, one of three looks, a bit of size variety.
var scatter := LFMultiMeshScatter.new()
scatter.multimesh = my_multimesh          # a MultiMesh with its mesh set, used by this node only
scatter.area = $Ground
scatter.density = 6.0
scatter.layer_count = 3
scatter.scale_range = Vector2(0.8, 1.2)
scatter.random_seed = 7
add_child(scatter)                        # scatters when ready
```

## Notes

- The multimesh must not be shared with another node: scattering resets its instance count and custom-data flag.
- Copies keep this node's orientation; the area's rotation and position only decide where they go.
- Changing `density` or the area later needs another `scatter()` call.
- A million small instances still cost memory: lower the density rather than hide them.
